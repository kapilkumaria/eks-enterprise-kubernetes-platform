# Deployment Guide

## Enterprise Kubernetes Platform Engineering on Amazon EKS

This guide provides the high-level deployment and validation workflow used to reproduce the platform.

The repository is intentionally organized so that:

- Terraform provisions AWS infrastructure.
- Argo CD bootstraps and reconciles Kubernetes platform services.
- Git is the source of truth for platform configuration.
- Validation commands confirm that each major capability is operational.

For detailed architecture decisions, see:

- [Architecture](architecture.md)
- [Security Architecture](security.md)

---

# 1. Deployment Model

The platform is deployed in the following order:

```text
Terraform
   |
   v
AWS Infrastructure
   |
   v
Amazon EKS
   |
   v
Argo CD
   |
   v
App-of-Apps
   |
   +--> Gateway API / Traefik
   +--> cert-manager
   +--> ExternalDNS
   +--> External Secrets
   +--> Kyverno
   +--> NetworkPolicies
   +--> Observability
   +--> Metrics Server
   +--> KEDA
   +--> Karpenter
   |
   v
Platform Validation
```
The objective is to minimize manual cluster configuration after bootstrap.

---

# 2. Prerequisites

The deployment workstation requires:
```
AWS CLI
Terraform
kubectl
Helm
Argo CD CLI
Git
jq
```
Verify the tools:
```
aws --version
terraform version
kubectl version --client
helm version
argocd version --client
git --version
jq --version
```
Verify AWS authentication:
```
aws sts get-caller-identity
```
---

# 3. Clone the Repository
```
git clone \
  https://github.com/kapilkumaria/eks-enterprise-kubernetes-platform.git

cd eks-enterprise-kubernetes-platform
```
Confirm repository status:
```
git status
```
---

# 4. Terraform Infrastructure

AWS infrastructure is managed from:
```
terraform/aws/
```
The development environment is located at:
```
terraform/aws/environments/dev/
```
Move to the Terraform environment:
```
cd terraform/aws/environments/dev
```
Initialize Terraform:
```
terraform init
```
Validate the configuration:
```
terraform validate
```
Format check:
```
terraform fmt -recursive ../../
```
Review the execution plan:
```
terraform plan
```
Create the infrastructure:
```
terraform apply
```
Return to the repository root:
```
cd ~/Projects/eks-enterprise-kubernetes-platform
```
---

# 5. Terraform-Provisioned AWS Components

Terraform provisions the core AWS infrastructure required by the platform, including:
```
VPC
public subnets
private subnets
Internet Gateway
NAT Gateway
routing
Amazon EKS
EKS Managed Node Group
IAM roles
IAM policies
EKS OIDC provider
IRSA roles
EKS add-ons
CloudWatch control-plane logging
Karpenter IAM resources
Karpenter interruption infrastructure
Karpenter resource discovery tags
```
The exact resource definitions are maintained in:
```
terraform/aws/modules/
```
---

# 6. Configure kubectl

Retrieve the cluster name:
```
terraform \
  -chdir="$HOME/Projects/eks-enterprise-kubernetes-platform/terraform/aws/environments/dev" \
  output -raw cluster_name
```
Configure kubeconfig:
```
aws eks update-kubeconfig \
  --region us-east-1 \
  --name eks-enterprise-platform-dev
```
Verify Kubernetes connectivity:
```
kubectl cluster-info
```
Check nodes:
```
kubectl get nodes -o wide
```
Expected result:
```
STATUS
Ready
```
for all baseline worker nodes.

---

# 7. Validate the EKS Cluster

Check cluster status from AWS:
```
aws eks describe-cluster \
  --region us-east-1 \
  --name eks-enterprise-platform-dev \
  --query 'cluster.[name,status,version]' \
  --output table
```
Check Kubernetes system pods:
```
kubectl get pods -n kube-system
```
Important platform dependencies should be running before continuing.

---

# 8. Verify EKS Add-ons

Check installed EKS add-ons:
```
aws eks list-addons \
  --region us-east-1 \
  --cluster-name eks-enterprise-platform-dev
```
Important add-ons include:
```
CoreDNS
kube-proxy
Amazon VPC CNI
Amazon EBS CSI Driver
```
---

# 9. Verify OIDC and IRSA

Get the cluster OIDC issuer:
```
aws eks describe-cluster \
  --region us-east-1 \
  --name eks-enterprise-platform-dev \
  --query 'cluster.identity.oidc.issuer' \
  --output text
```
Terraform creates workload-specific IAM roles for components including:
```
ExternalDNS
External Secrets
EBS CSI
VPC CNI
Karpenter
```
This avoids using the worker-node IAM role as a shared AWS credential boundary.

---

# 10. Argo CD Bootstrap

Argo CD provides continuous reconciliation of Kubernetes platform configuration.

Verify the Argo CD namespace:
```
kubectl get namespace argocd
```
Verify Argo CD pods:
```
kubectl get pods -n argocd
```
Verify the Argo CD project:
```
kubectl get appproject \
  platform \
  -n argocd
```
---

# 11. App-of-Apps Bootstrap

The root application is defined at:
```
argocd/app-of-apps/root-application.yaml
```
Apply it:
```
kubectl apply \
  -f argocd/app-of-apps/root-application.yaml
```
The root application discovers child applications under:
```
argocd/applications/
```
Verify:
```
kubectl get applications \
  -n argocd
```
A healthy platform should show most applications as:
```
Synced
Healthy
```
---

# 12. Expected Argo CD Applications

The GitOps platform includes applications such as:
```
enterprise-platform
cert-manager
cert-manager-certificates
cert-manager-config
external-dns
external-secrets
external-secrets-config
gateway-api-crds
gateway-smoke-test
karpenter
karpenter-resources
keda
keda-scaledobjects
kyverno
kyverno-policies
metrics-server
network-policies
observability
observability-config
traefik-gateway
```
Check them with:
```
kubectl get applications \
  -n argocd
```
---

# 13. Gateway API Validation

Verify Gateway API resources:
```
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
```
Expected architecture:
```
Internet
   |
   v
AWS Load Balancer
   |
   v
Traefik
   |
   v
Gateway
   |
   v
HTTPRoute
   |
   v
Service
   |
   v
Pod
```
Verify the Gateway address:
```
kubectl get gateway \
  -A \
  -o wide
```
---

# 14. Traefik Validation

Check the Traefik workload:
```
kubectl get pods \
  -n traefik
```
Check services:
```
kubectl get svc \
  -n traefik
```
Check Gateway status:
```
kubectl describe gateway \
  shared-public-gateway \
  -n traefik
```
Look for:
```
Accepted=True
Programmed=True
```
---

# 15. ExternalDNS Validation

Verify ExternalDNS:
```
kubectl get pods \
  -n external-dns
```
Check its service account:
```
kubectl get serviceaccount \
  external-dns \
  -n external-dns \
  -o yaml
```
The service account should reference its dedicated IAM role through IRSA.

Check recent controller logs:
```
kubectl logs \
  -n external-dns \
  deployment/external-dns \
  --tail=100
```
---

# 16. DNS Validation

The demonstration hostname is:
```
whoami-dev.kapilkumaria.com
```
Validate DNS:
```
dig whoami-dev.kapilkumaria.com
```
or:
```
nslookup whoami-dev.kapilkumaria.com
```
ExternalDNS should manage the corresponding Route 53 DNS record.

---

# 17. cert-manager Validation

Check cert-manager pods:
```
kubectl get pods \
  -n cert-manager
```
Check certificate resources:
```
kubectl get certificate \
  -A
```
Check issuers:
```
kubectl get clusterissuer
```
If certificate troubleshooting is required:
```
kubectl get certificaterequest \
  -A
```
```
kubectl get order \
  -A
```
```
kubectl get challenge \
  -A
```
---

# 18. External Secrets Validation

Check External Secrets Operator:
```
kubectl get pods \
  -n external-secrets
```
Check secret stores:
```
kubectl get secretstore \
  -A
```
```
kubectl get clustersecretstore \
  -A
```
Check ExternalSecret resources:
```
kubectl get externalsecret \
  -A
```
The design keeps sensitive secret values outside the Git repository.

---

# 19. Kyverno Validation

Check Kyverno:
```
kubectl get pods \
  -n kyverno
```
Check policies:
```
kubectl get clusterpolicy
```
Implemented controls include:
```
disallow privileged containers
require CPU requests
require memory requests
require CPU limits
require memory limits
```
---

# 20. Validate Privileged Container Enforcement

Create a test pod:
```
cat <<'TEST' >/tmp/kyverno-privileged-test.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kyverno-privileged-test
  namespace: gateway-demo
spec:
  containers:
    - name: nginx
      image: nginx:alpine
      securityContext:
        privileged: true
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 64Mi
TEST
```
Attempt deployment:
```
kubectl apply \
  -f /tmp/kyverno-privileged-test.yaml
```
Expected result:
```
Request denied by Kyverno
```
The privileged workload should not be created.

Clean up:
```
rm -f /tmp/kyverno-privileged-test.yaml
```
---

# 21. Validate Resource Governance

Create a workload without requests and limits:
```
cat <<'TEST' >/tmp/kyverno-resources-test.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kyverno-resources-test
  namespace: gateway-demo
spec:
  containers:
    - name: nginx
      image: nginx:alpine
      securityContext:
        privileged: false
TEST
```
Attempt deployment:
```
kubectl apply \
  -f /tmp/kyverno-resources-test.yaml
```
Expected result:
```
Request denied by Kyverno
```
Clean up:
```
rm -f /tmp/kyverno-resources-test.yaml
```
---

# 22. NetworkPolicy Validation

Check NetworkPolicies:
```
kubectl get networkpolicy \
  -A
```
The demonstration application namespace uses:
```
default-deny-ingress
default-deny-egress
allow-dns-egress
allow-traefik-ingress
```
This implements a default-deny application network posture.

---

# 23. Observability Validation

Check monitoring workloads:
```
kubectl get pods \
  -n monitoring
```
The stack includes:
```
Prometheus
Grafana
Alertmanager
Prometheus Operator
kube-state-metrics
node-exporter
```
Verify Prometheus resources:
```
kubectl get prometheus \
  -n monitoring
```
Verify Alertmanager:
```
kubectl get alertmanager \
  -n monitoring
```
Verify ServiceMonitors:
```
kubectl get servicemonitor \
  -A
```
---

# 24. Metrics Server Validation

Check Metrics Server:
```
kubectl get pods \
  -n kube-system |
grep metrics-server
```
Validate resource metrics:
```
kubectl top nodes
kubectl top pods \
  -A
```
These metrics support Kubernetes resource-based autoscaling.

---

# 25. HPA Validation

Check HorizontalPodAutoscalers:
```
kubectl get hpa \
  -A
```
The HPA layer handles workload replica scaling based on Kubernetes resource metrics.

HPA scales:
```
Pods
```
It does not create EC2 instances.

---

# 26. KEDA Validation

Check KEDA:
```
kubectl get pods \
  -n keda
```
Check ScaledObjects:
```
kubectl get scaledobject \
  -A
```
The project includes Prometheus-driven KEDA autoscaling.

Example expected resource:
```
gateway-demo / whoami-prometheus
```
Inspect it:
```
kubectl describe scaledobject \
  whoami-prometheus \
  -n gateway-demo
```
KEDA represents the external/event-driven workload scaling layer.

---

# 27. Karpenter Validation

Check the Karpenter controller:
```
kubectl get deployment,pods \
  -n karpenter
```
Verify the EC2NodeClass:
```
kubectl get ec2nodeclass
```
Expected:
```
default   True
```
Verify the NodePool:
```
kubectl get nodepool
```
Expected:
```
default   default   ...   True
```
Check NodeClaims:
```
kubectl get nodeclaims \
  -o wide
```
No NodeClaims are required when there is no workload waiting for Karpenter capacity.

---

# 28. Karpenter Scale-Out Test

Create a temporary namespace:
```
kubectl create namespace karpenter-test \
  --dry-run=client \
  -o yaml |
kubectl apply -f -
```
Create a workload that can only run on a Karpenter node:
```
cat >/tmp/karpenter-scale-test.yaml <<'TEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: karpenter-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      nodeSelector:
        node-provisioner: karpenter
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.10
          resources:
            requests:
              cpu: "1"
              memory: 1Gi
            limits:
              cpu: "1"
              memory: 1Gi
TEST
```
Deploy it:
```
kubectl apply \
  -f /tmp/karpenter-scale-test.yaml
```
Initially verify that the pod is pending:
```
kubectl get pods \
  -n karpenter-test \
  -o wide
```
Watch Karpenter create a NodeClaim:
```
kubectl get nodeclaims \
  -w
```
In the validated environment, Karpenter successfully created an EC2 instance and registered a new node with the cluster.

---

# 29. Validate the Karpenter Node

Check nodes with Karpenter labels:
```
kubectl get nodes \
  -L node-provisioner,karpenter.sh/nodepool,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```
A dynamically provisioned node should contain values similar to:
```
node-provisioner = karpenter
nodepool         = default
capacity-type    = on-demand or spot
instance-type    = selected by Karpenter
```
During validation, Karpenter successfully selected and launched compatible EC2 capacity for the pending workload.

---

# 30. Karpenter Consolidation Test

Delete the temporary workload:
```
kubectl delete deployment \
  inflate \
  -n karpenter-test
```
Watch the NodeClaim:
```
kubectl get nodeclaims \
  -w
```
With consolidation enabled, Karpenter eventually removes unnecessary capacity.

Verify:
```
kubectl get nodeclaims
kubectl get nodepool
```
Expected after consolidation:
```
NodeClaims: 0
NodePool nodes: 0
```
Remove the test namespace:
```
kubectl delete namespace \
  karpenter-test \
  --ignore-not-found
```
Clean up:
```
rm -f /tmp/karpenter-scale-test.yaml
```
---

# 31. Persistent Storage Validation

Check available StorageClasses:
```
kubectl get storageclass
```
The platform provides a gp3 StorageClass backed by the Amazon EBS CSI Driver.

Expected characteristics include:
```
Provisioner: ebs.csi.aws.com
VolumeBindingMode: WaitForFirstConsumer
AllowVolumeExpansion: true
```
---

# 32. Platform-Wide Validation

Run the following validation after the complete platform has reconciled:
```
echo "===== EKS NODES ====="
kubectl get nodes -o wide

echo
echo "===== ARGO CD APPLICATIONS ====="
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
The final validation should show:
```
EKS nodes Ready
platform controllers Running
Gateway programmed
ExternalDNS running
External Secrets running
Kyverno policies Ready
Prometheus and Grafana running
Metrics Server returning metrics
KEDA ScaledObject Ready
EC2NodeClass Ready
NodePool Ready
no unexpected Pending or Failed workloads
```
---

# 33. GitOps Validation

Check all Argo CD applications:
```
kubectl get applications \
  -n argocd
```
For an individual application:
```
argocd app get karpenter \
  --hard-refresh
```
Check for configuration drift:
```
argocd app diff karpenter
```
A blank diff indicates that the live resource matches the desired state.

---

# 34. Important GitOps Note

A small number of Argo CD status edge cases may occur with resources that are mutated by Kubernetes controllers after admission.

For example, Kyverno CRDs or policies may appear OutOfSync even when:
```
the sync operation succeeds
argocd app diff is empty
the policy is Ready
runtime admission tests succeed
```
Operational functionality must therefore be validated using both:
```
GitOps status
+
Kubernetes resource health
+
runtime tests
```
rather than relying solely on one UI status field.

---

# 35. Evidence Capture

During the final clean deployment, screenshots should be captured for portfolio evidence.

Recommended evidence:
```
docs/images/
├── aws-eks-cluster.png
├── eks-nodes.png
├── argocd-platform-applications.png
├── gateway-api.png
├── external-dns.png
├── cert-manager.png
├── external-secrets.png
├── kyverno-policy-enforcement.png
├── grafana-kubernetes-dashboard.png
├── metrics-server.png
├── keda-scaledobject.png
├── karpenter-nodeclaim.png
├── karpenter-node.png
├── karpenter-consolidation.png
└── final-platform-health.png
```
Screenshots are supporting evidence.

The repository configuration and reproducible deployment workflow remain the primary project artifact.

---

# 36. Tear Down

The development environment should be destroyed when it is no longer required to avoid unnecessary AWS cost.

Before destroying infrastructure, verify that no required evidence or validation data remains uncaptured.

Move to the Terraform environment:
```
cd \
  ~/Projects/eks-enterprise-kubernetes-platform/terraform/aws/environments/dev
```
Review destruction:
```
terraform plan \
  -destroy
```
Destroy infrastructure:
```
terraform destroy
```
Confirm AWS resources have been removed as expected.

---

# 37. Reproduction Workflow Summary

A future deployment can follow this sequence:
```
1. Clone repository
2. Authenticate to AWS
3. terraform init
4. terraform validate
5. terraform plan
6. terraform apply
7. aws eks update-kubeconfig
8. Validate EKS
9. Bootstrap Argo CD
10. Apply App-of-Apps
11. Allow GitOps reconciliation
12. Validate Gateway API
13. Validate DNS
14. Validate TLS
15. Validate External Secrets
16. Validate Kyverno
17. Validate NetworkPolicies
18. Validate Observability
19. Validate Metrics Server
20. Validate KEDA
21. Validate Karpenter scale-out
22. Validate Karpenter consolidation
23. Validate storage
24. Capture portfolio evidence
25. terraform destroy when finished
38. Production Considerations
```
A real production deployment would normally add or strengthen capabilities such as:
```
Terraform remote state with locking
dedicated AWS accounts per environment
private EKS API access where appropriate
VPC endpoints
stronger Argo CD RBAC
SSO integration
secrets rotation
image signing and verification
vulnerability scanning
Pod Security Standards
admission policy expansion
centralized logs
long-term metrics retention
backup and restore
Velero or equivalent DR tooling
multi-region or secondary-region recovery where required
infrastructure CI/CD
automated integration testing
controlled promotion between dev, staging and production
```
These are production evolution paths rather than requirements for demonstrating the core platform architecture in this portfolio project.

---

# 38. Deployment Outcome

The deployment demonstrates a complete Kubernetes platform lifecycle:
```
Infrastructure as Code
        |
        v
Amazon EKS
        |
        v
GitOps
        |
        v
Platform Services
        |
        +--> Networking
        +--> Security
        +--> Secrets
        +--> TLS
        +--> DNS
        +--> Observability
        +--> Workload Autoscaling
        +--> Node Autoscaling
        +--> Storage
        |
        v
Runtime Validation
```
The key engineering outcome is not simply that individual tools were installed.

The platform demonstrates how multiple controllers and AWS services can be integrated into a declarative, secure, observable and dynamically scalable Kubernetes platform.
