# Troubleshooting Guide

## Enterprise Kubernetes Platform Engineering

This document captures significant implementation issues encountered while building and validating the platform.

The objective is not to document every minor command failure.

Instead, it records production-relevant troubleshooting scenarios that required investigation across AWS, Terraform, Kubernetes, GitOps, IAM, networking and platform controllers.

---

# 1. Troubleshooting Approach

The general troubleshooting workflow used throughout this project was:

```text
Observe
   |
   v
Identify failing component
   |
   v
Inspect Kubernetes status
   |
   v
Inspect controller logs
   |
   v
Inspect AWS resources / IAM
   |
   v
Compare desired state with live state
   |
   v
Apply smallest possible fix
   |
   v
Validate runtime behavior
```
Useful commands included:
```
kubectl get pods -A
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace>
kubectl get events -A --sort-by=.lastTimestamp
kubectl get applications -n argocd
argocd app get <application> --hard-refresh
argocd app diff <application>
terraform plan
terraform validate
aws sts get-caller-identity
```

# 2. Karpenter IAM — ListInstanceProfiles AccessDenied
## Symptom

Karpenter was able to start, but EC2NodeClass reconciliation encountered IAM-related errors.

The controller required permission to list IAM instance profiles.

The missing action was:

iam:ListInstanceProfiles
Root Cause

The IAM policy allowed instance-profile read and modification actions against scoped resources, but iam:ListInstanceProfiles is a list action that requires:
```
Resource = "*"
```
It cannot be constrained to an individual instance-profile ARN in the same way as iam:GetInstanceProfile.

Fix

The Terraform IAM policy was updated with a separate statement:
```
statement {
  sid    = "AllowUnscopedInstanceProfileListAction"
  effect = "Allow"

  actions = [
    "iam:ListInstanceProfiles"
  ]

  resources = ["*"]
}
```
Terraform validation:
```
terraform \
  -chdir="$HOME/Projects/eks-enterprise-kubernetes-platform/terraform/aws/environments/dev" \
  validate
```
Plan validation:
```
terraform \
  -chdir="$HOME/Projects/eks-enterprise-kubernetes-platform/terraform/aws/environments/dev" \
  plan
```
The expected change was:
```
Plan: 0 to add, 1 to change, 0 to destroy
```
## Validation

After applying the IAM update:
```
kubectl logs \
  -n karpenter \
  deployment/karpenter \
  --all-containers=true \
  --since=5m |
grep -Ei \
  'AccessDenied|Unauthorized|Forbidden|ListInstanceProfiles|ERROR' ||
true
```
No relevant IAM errors remained.

## Engineering Lesson

IAM list operations often require wildcard resources even when related read or mutation operations support resource-level scoping.

Least privilege still applies, but permissions must also match AWS IAM action semantics.

---

# 3. Terraform Karpenter Subnet Discovery — for_each with Unknown Values
## Symptom

Terraform encountered planning problems when subnet IDs created by the networking module were used as for_each keys for Karpenter discovery tags.

Conceptually:
```
for_each = toset(var.private_subnet_ids)
```
## Root Cause

During the initial Terraform plan, subnet IDs do not yet exist.

Terraform can know how many subnets will be created, but cannot use unknown resource IDs as stable for_each instance keys during planning.

## Fix

The tagging resource was changed to use count:
```
resource "aws_ec2_tag" "private_subnet_discovery" {
  count = length(var.private_subnet_ids)

  resource_id = var.private_subnet_ids[count.index]
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
```
## Engineering Lesson

Use for_each when instance keys are known during planning.

Use count when the collection length is known but individual resource IDs remain unknown until apply.

This is especially relevant when composing Terraform modules where one module creates resources consumed by another.

---

# 4. Karpenter EC2NodeClass Initially Shows Unknown
## Symptom

Immediately after creation:
```
kubectl get ec2nodeclass
```
showed:
```
NAME      READY     AGE
default   Unknown   ...
```
## Analysis

This was expected during initial reconciliation.

Karpenter still needed to resolve:
```
AMIs
subnets
security groups
instance profile
validation state
```
## Validation

The resource was inspected:
```
kubectl describe ec2nodeclass default
```
Successful conditions eventually included:
```
AMIsReady=True
SubnetsReady=True
SecurityGroupsReady=True
InstanceProfileReady=True
ValidationSucceeded=True
Ready=True
```
Final check:
```
kubectl get ec2nodeclass \
  default \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" reason="}{.reason}{"\n"}{end}'
```
## Engineering Lesson

Controllers are asynchronous.

An initial Unknown status is not automatically a failure.

The correct troubleshooting method is to inspect individual reconciliation conditions rather than react only to the top-level readiness field.

---

# 5. Karpenter NodePool Ready but No Nodes
## Symptom

The NodePool showed:
```
READY=True
NODES=0
```
and:
```
kubectl get nodeclaims
```
returned:
```
No resources found
Root Cause
```
This was expected.

Karpenter is demand-driven.

It does not automatically launch EC2 instances simply because a NodePool exists.

A pending unschedulable workload is required to create demand.

## Validation

A temporary workload was created with:
```
nodeSelector:
  node-provisioner: karpenter
```
The existing managed-node-group nodes did not contain that label, forcing the workload to remain Pending.

Karpenter then created a NodeClaim.

## Engineering Lesson

Karpenter reacts to unschedulable pods.

NodePool readiness validates configuration; NodeClaim creation validates provisioning behavior.

Both should be tested separately.

---

# 6. Karpenter Spot Capacity — Missing AWS Service-Linked Role
## Symptom

Karpenter logged:
```
AuthFailure.ServiceLinkedRoleCreationNotPermitted
```
during EC2 fleet provisioning.

The error referred to the EC2 Spot service-linked role.

## Root Cause

The AWS account did not yet contain:
```
AWSServiceRoleForEC2Spot
```
and the credentials used by Karpenter did not have permission to create that service-linked role automatically.

## Validation

The role was checked:
```
aws iam get-role \
  --role-name AWSServiceRoleForEC2Spot
```
AWS returned:
```
NoSuchEntity
```
## Fix

The role was created once at the AWS account level:
```
aws iam create-service-linked-role \
  --aws-service-name spot.amazonaws.com
```
# Validation:
```
aws iam get-role \
  --role-name AWSServiceRoleForEC2Spot \
  --query 'Role.[RoleName,Arn]' \
  --output table
```
# Engineering Lesson

Some AWS capabilities depend on account-level service-linked roles.

These dependencies may exist outside the direct Terraform/Kubernetes object being debugged.

When EC2 fleet provisioning fails, IAM service-linked roles should be considered alongside controller permissions.

---

# 7. Karpenter Scale-Out Validation
## Symptom

A test workload remained Pending:
```
0/4 nodes are available:
4 node(s) didn't match Pod's node affinity/selector
```
# Analysis

This was intentional.

The pod specified:
```
nodeSelector:
  node-provisioner: karpenter
```
while baseline managed-node-group nodes did not have that label.

Karpenter detected the unschedulable pod and nominated a NodeClaim.

## Validation

Watch NodeClaims:
```
kubectl get nodeclaims -w
```
A successful claim appeared similar to:
```
TYPE        CAPACITY    ZONE
c6a.large   on-demand   us-east-1a
```
The node then registered:
```
kubectl get nodes \
  -L node-provisioner,karpenter.sh/nodepool,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```
and contained:
```
node-provisioner=karpenter
karpenter.sh/nodepool=default
```
The pod transitioned to Running.

## Engineering Lesson

A pending pod is not always a failure.

In autoscaling tests, Pending can be the required trigger that proves infrastructure automation works.

---

# 8. Karpenter Consolidation Validation
## Symptom

After deleting the test workload, the dynamically provisioned EC2 node remained temporarily visible.

## Analysis

Karpenter consolidation is asynchronous.

The configured NodePool contained:
```
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 1m
```
## Validation

After waiting:
```
kubectl get nodeclaims
```
returned:
```
No resources found
```
and:
```
kubectl get nodepool
```
showed:
```
NODES=0
```
The EC2 instance transitioned toward termination.

## Engineering Lesson

Scale-in behavior should be validated separately from scale-out.

A production autoscaler must prove both:
```
Demand rises -> capacity added
Demand falls -> unnecessary capacity removed
```
---

# 9. Argo CD Karpenter Repository Not Permitted
## Symptom

The Karpenter Argo CD Application showed:
```
InvalidSpecError
```
with a message indicating:
```
application repo public.ecr.aws/karpenter is not permitted in project 'platform'
```
## Root Cause

The Argo CD AppProject source repository allowlist did not include the Karpenter OCI Helm repository.

## Fix

The following source was added to:
```
argocd/projects/platform-project.yaml
sourceRepos:
  - public.ecr.aws/karpenter
```
Apply the AppProject:
```
kubectl apply \
  -f argocd/projects/platform-project.yaml
```
Validate:
```
kubectl get appproject \
  platform \
  -n argocd \
  -o json |
jq -r '.spec.sourceRepos[]'
```
# Engineering Lesson

Argo CD AppProjects are security boundaries.

Application repository access is intentionally denied unless explicitly permitted.

This is preferable to using unrestricted repository access.

---

# 10. Argo CD Karpenter Application OutOfSync After Helm Install
## Symptom

Karpenter was already installed manually with Helm.

After GitOps ownership was introduced, Argo CD displayed many resources as OutOfSync.

Examples included:
```
Deployment
Service
ServiceAccount
RBAC resources
PodDisruptionBudget
Root Cause
```
The live resources had been created by Helm before Argo CD began tracking them.

Argo CD needed to establish its own resource tracking annotations and ownership metadata.

## Fix

The application was synchronized:
```
argocd app sync karpenter
```
Then:
```
argocd app wait \
  karpenter \
  --sync \
  --health \
  --timeout 600
```
## Validation
```
kubectl get application \
  karpenter \
  -n argocd
```
returned:
```
Synced
Healthy
```
and:
```
argocd app diff karpenter
```
returned no differences.

## Engineering Lesson

Moving from imperative installation to GitOps ownership is a migration operation.

Existing resources may be healthy while still lacking the tracking state required by Argo CD.

---

# 11. Argo CD AppProject YAML Allowlist Formatting Error
## Symptom

After modifying the AppProject repository allowlist, Argo CD continued to report permitted repositories incorrectly.

The generated YAML contained malformed list formatting.
## Root Cause

An earlier automated file-edit operation inserted repository entries incorrectly.

This produced structurally valid-looking text but incorrect YAML list semantics.

## Fix

The AppProject file was rewritten cleanly with one repository per list item.

Example:
```
sourceRepos:
  - public.ecr.aws/karpenter
  - https://prometheus-community.github.io/helm-charts
  - https://github.com/kapilkumaria/eks-enterprise-kubernetes-platform.git
```
Validation:
```
kubectl apply \
  --dry-run=client \
  -f argocd/projects/platform-project.yaml
```
then:
```
kubectl apply \
  -f argocd/projects/platform-project.yaml
```
## Engineering Lesson

Automated text replacement is useful but must always be followed by:
```
git diff
git diff --check
```
and, when possible:
```
kubectl apply --dry-run=client
```
Configuration automation should never eliminate validation.

---

# 12. Kyverno ClusterPolicy Appeared OutOfSync
## Symptom

The Kyverno policies were:
```
READY=True
```
and runtime enforcement worked, but Argo CD displayed:
```
OutOfSync
```
for the policy Application.

At the same time:
```
argocd app diff kyverno-policies
```
returned no visible differences.

## Investigation

The following were checked:
```
kubectl get clusterpolicy
argocd app get kyverno-policies --hard-refresh
kubectl get application \
  kyverno-policies \
  -n argocd \
  -o json |
jq '.status.resources'
```
The resources were cluster-scoped ClusterPolicy objects.

The destination namespace was removed from the Argo CD policy application because cluster-scoped resources do not require a namespace.

## Runtime Validation

Privileged pod test:
```
kubectl apply \
  -f /tmp/kyverno-privileged-test.yaml
```
was rejected with a Kyverno admission error.

A pod without CPU and memory requests/limits was also rejected.

## Conclusion

The policies were operationally valid even though Argo CD continued to report a comparison-state inconsistency.

The evidence was:
```
Policy Ready=True
+
Sync operations succeeded
+
argocd app diff returned no differences
+
runtime admission tests passed
```
## Engineering Lesson

Operational validation should not depend on a single status indicator.

For controller-managed resources, use multiple signals:
```
Desired-state comparison
+
Resource health
+
Controller logs
+
Runtime behavior
```
---

# 13. Kyverno Cluster-Scoped Destination Namespace
## Symptom

Argo CD tracked ClusterPolicy resources using namespace-related metadata even though ClusterPolicy is cluster scoped.

## Root Cause

The Argo CD Application contained:
```
destination:
  server: https://kubernetes.default.svc
  namespace: kyverno
```
The resources themselves were cluster scoped.

## Fix

The destination namespace was removed:
```
destination:
  server: https://kubernetes.default.svc
```
Validation:
```
python3 - <<'PY'
import yaml

f = "argocd/applications/kyverno-policies.yaml"

with open(f) as fh:
    data = yaml.safe_load(fh)

print(data["spec"]["destination"].get("namespace"))
PY
```
Expected:
```
None
```
## Engineering Lesson

Cluster-scoped and namespace-scoped resources should be modeled correctly in GitOps definitions.

Incorrect namespace assumptions can cause tracking and comparison inconsistencies.

---

# 14. Kyverno Negative Security Testing
## Scenario

A privileged container was intentionally submitted to the gateway-demo namespace.

## Test
```
securityContext:
  privileged: true
```
## Result

Kyverno rejected the request:
```
admission webhook "validate.kyverno.svc-fail" denied the request
```
The policy reported:
```
Privileged containers are prohibited in application namespaces.
```
## Validation
```
kubectl get pod \
  kyverno-privileged-test \
  -n gateway-demo
```
returned no pod.

## Engineering Lesson

Security policy should be tested negatively.

A policy existing in the cluster does not prove that it actually blocks forbidden behavior.

---

## 15. Resource Governance Negative Test
## Scenario

A pod was submitted without CPU and memory requests and limits.

Result
```
Kyverno rejected it with:
```
Every container must define CPU and memory requests and limits.

## Engineering Lesson

Resource governance supports:
```
predictable scheduling
autoscaling
cluster capacity planning
noisy-neighbor prevention
workload reliability
```
Admission enforcement provides stronger guarantees than relying on developer documentation.

---

# 16. cert-manager ACME Challenge / DNS Failure
## Symptom

Certificate issuance remained pending.

The HTTP-01 challenge failed with DNS-related messages similar to:
```
no such host
```
The environment also encountered Let's Encrypt issuance constraints during repeated testing.

## Investigation

Useful commands:
```
kubectl get certificate -A
kubectl get certificaterequest -A
kubectl get order -A
kubectl get challenge -A
```
Detailed inspection:
```
kubectl describe challenge \
  <challenge-name> \
  -n <namespace>
```
DNS validation:
```
dig whoami-dev.kapilkumaria.com
```
Gateway validation:
```
kubectl get gateway -A
kubectl get httproute -A
Root Cause Categories
```
Potential causes encountered during testing included:
```
DNS record not yet resolvable
ExternalDNS reconciliation delay
ACME HTTP-01 routing dependency
Gateway listener state
repeated certificate issuance attempts
public CA rate limits
Engineering Lesson
```
Certificate automation crosses several independent systems:
```
Kubernetes
+
cert-manager
+
Gateway
+
DNS
+
Route 53
+
ACME provider
```
Troubleshooting TLS requires validating the entire dependency chain rather than only the Certificate object.

---

# 17. ExternalDNS Validation Strategy
## Problem

DNS automation may appear healthy at the pod level while DNS records are not yet usable.

## Validation

Check pod state:
```
kubectl get pods \
  -n external-dns
```
Check logs:
```
kubectl logs \
  -n external-dns \
  deployment/external-dns \
  --tail=100
```
Check the DNS record externally:
```
dig whoami-dev.kapilkumaria.com
```
## Engineering Lesson

Controller health does not guarantee external-system convergence.

For ExternalDNS, validation must include Route 53 or public DNS resolution.

---

# 18. Grafana Password Secret Change Did Not Immediately Work
## Symptom

The Grafana Kubernetes Secret was patched with a new admin password and the Deployment was restarted, but login still failed.
```
Attempted Change
kubectl patch secret \
  observability-grafana \
  -n monitoring \
  --type merge \
  -p '{"stringData":{"admin-password":"NewStrongPassword123!"}}'
```
Then:
```
kubectl rollout restart \
  deployment observability-grafana \
  -n monitoring
```
## Analysis

Grafana credentials can be affected by how the Helm chart initializes and persists admin credentials.

A Secret patch does not always imply that an already initialized Grafana database will adopt the changed password.

## Engineering Lesson

Kubernetes Secrets are configuration inputs, but application runtime state may also exist in internal databases or persistent storage.

Configuration changes must be understood in the context of the application's initialization model.

---

# 19. Argo CD "Another Operation Is Already in Progress"
## Symptom

An attempted sync returned:
```
rpc error:
another operation is already in progress
```
## Root Cause

The application controller was already performing an automated reconciliation.

## Resolution

Wait for the existing operation:
```
sleep 20
```
Then inspect:
```
argocd app get \
  enterprise-platform \
  --hard-refresh
```
or retry the sync after the active operation completes.

## Engineering Lesson

GitOps controllers are asynchronous systems.

Avoid launching overlapping manual operations unless necessary.

First inspect the current operation state.

---

# 20. Argo CD Hard Refresh vs Normal Refresh
## Scenario

Some application states appeared stale after Git changes were pushed.

## Resolution

A hard refresh was used:
```
argocd app get \
  enterprise-platform \
  --hard-refresh
```
For Kubernetes-level refresh:
```
kubectl annotate application \
  enterprise-platform \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite
```
## Engineering Lesson

Cached manifest state can temporarily differ from newly committed repository state.

A hard refresh is useful when troubleshooting apparent reconciliation delays.

---

# 21. Argo CD Orphaned Resource Warnings
## Symptom

Applications displayed warnings such as:
```
Application has N orphaned resources
```
while the application itself remained healthy.

## Analysis

The AppProject had:
```
orphanedResources:
  warn: true
```
This intentionally enables detection of resources in managed namespaces or scopes that are not owned by the current Argo CD Application.

## Engineering Lesson

An orphan warning is not equivalent to application failure.

It is an ownership/governance signal.

The correct response is to determine whether the resource is:
```
expected
created by another application
manually created
stale and removable
```
---

# 22. Kubernetes Pod Pending Is a Diagnostic Signal
## Scenario

During Karpenter testing, the workload was intentionally Pending.

Useful Commands
```
kubectl get pods \
  -n karpenter-test \
  -o wide
kubectl describe pod \
  -n karpenter-test \
  -l app=inflate
```
Scheduler events showed:
```
FailedScheduling
```
followed by Karpenter:
```
Nominated
Pod should schedule on: nodeclaim/...
```
## Engineering Lesson

Scheduler events often provide the fastest explanation for Pending pods.

Always inspect:

Events:
```
before changing manifests.
```
---

# 23. Final Platform Validation

Before considering the platform healthy, the following checks were used.
```
echo "===== EKS NODES ====="
kubectl get nodes -o wide

echo
echo "===== ARGO CD ====="
kubectl get applications -n argocd

echo
echo "===== GATEWAY API ====="
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A

echo
echo "===== CERT-MANAGER ====="
kubectl get pods -n cert-manager

echo
echo "===== EXTERNAL DNS ====="
kubectl get pods -n external-dns

echo
echo "===== EXTERNAL SECRETS ====="
kubectl get pods -n external-secrets

echo
echo "===== KYVERNO ====="
kubectl get pods -n kyverno
kubectl get clusterpolicy

echo
echo "===== OBSERVABILITY ====="
kubectl get pods -n monitoring

echo
echo "===== METRICS SERVER ====="
kubectl top nodes

echo
echo "===== KEDA ====="
kubectl get pods -n keda
kubectl get scaledobject -A

echo
echo "===== KARPENTER ====="
kubectl get deployment,pods -n karpenter
kubectl get ec2nodeclass
kubectl get nodepool
kubectl get nodeclaims

echo
echo "===== NETWORK POLICIES ====="
kubectl get networkpolicy -A

echo
echo "===== STORAGE ====="
kubectl get storageclass

echo
echo "===== FAILED / PENDING PODS ====="
kubectl get pods -A \
  --field-selector=status.phase!=Running,status.phase!=Succeeded
```
---

# 24. Troubleshooting Principles Demonstrated

This project reinforced several operational principles.

Validate the Layer That Owns the Problem

Examples:
```
Terraform problem
-> terraform plan / state / provider behavior

AWS permission problem
-> IAM policy / CloudTrail / AWS CLI

Kubernetes scheduling problem
-> describe pod / scheduler events

Controller problem
-> controller logs / CR status

GitOps problem
-> Argo CD diff / sync / tracking state

DNS problem
-> DNS resolution, not only pod health

Security problem
-> negative runtime test
```
## Prefer Small Fixes

Changes were made as narrowly as possible.

Examples:
```
one IAM action added
one AppProject repository allowed
one destination namespace removed
one service-linked role created
```
This reduces regression risk.

## Separate Configuration Health from Runtime Health

A manifest can be valid while runtime integration fails.

A runtime component can also work while GitOps displays a metadata comparison issue.

Both states must be inspected.

## Test Failure Paths

Successful deployment is only one form of validation.

The platform also validated expected failure behavior:
```
Privileged pod
-> denied

Pod without resource governance
-> denied

Unschedulable Karpenter workload
-> triggers node provisioning
```
---

# 25. Senior DevOps Perspective

The most important troubleshooting skill demonstrated in this platform is not knowledge of individual commands.

It is the ability to determine which control plane owns the failure.

This platform contains several interacting control planes:
```
Terraform
AWS APIs
Amazon EKS
Kubernetes Scheduler
Argo CD
Kyverno
cert-manager
ExternalDNS
External Secrets
Prometheus Operator
KEDA
Karpenter
```
A failure can therefore appear in one layer while the root cause exists in another.

Examples from this project include:
```
Karpenter provisioning failure
-> AWS IAM service-linked role

Terraform planning failure
-> unknown subnet IDs used as for_each keys

Argo CD application failure
-> AppProject repository allowlist

Certificate failure
-> DNS / Gateway / ACME dependency chain

Security validation
-> admission controller runtime behavior
```
This cross-layer diagnosis is a core platform-engineering responsibility.

---

# 26. Final Outcome

The troubleshooting work performed during this project validated the platform beyond simple installation.

The final environment demonstrated:
```
Terraform-managed AWS infrastructure
healthy Amazon EKS nodes
GitOps-managed platform services
functional Gateway API routing
automated DNS integration
certificate-management integration
AWS-backed secrets integration
enforced Kyverno policies
zero-trust NetworkPolicies
Prometheus-based observability
Kubernetes metrics
KEDA autoscaling
Karpenter scale-out
Karpenter consolidation
dynamic EBS storage
repeatable infrastructure destruction and recreation
```
The resulting platform therefore represents not only a deployment exercise, but also a documented set of implementation, validation and troubleshooting patterns applicable to real Kubernetes platform engineering.
