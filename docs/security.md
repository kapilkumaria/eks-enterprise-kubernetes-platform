# Security Architecture

## Enterprise Kubernetes Platform Engineering

This document summarizes the security architecture implemented in the Enterprise Kubernetes Platform Engineering project running on Amazon EKS.

The objective was to build security into the platform itself rather than depend only on developer discipline or manual review.

The platform combines AWS identity controls, Kubernetes policy enforcement, network isolation, secrets management, TLS, GitOps governance, private worker networking, and runtime validation.

---

## 1. Security Objectives

The platform was designed around the following security objectives:

- apply least-privilege access to AWS services
- prevent workloads from inheriting unnecessary AWS permissions
- keep secret values out of Git
- prevent privileged containers
- require application resource governance
- restrict pod-to-pod and pod-to-external communication
- encrypt external application traffic
- keep Kubernetes worker nodes in private subnets
- separate platform-controller permissions
- enforce configuration through GitOps
- validate controls through negative testing

The security model follows a defense-in-depth approach.

No single security mechanism is assumed to provide complete protection.

---

## 2. Defense-in-Depth Model

Security controls operate at multiple layers.

```text
AWS
├── Private subnets
├── IAM roles
├── IAM policies
├── IRSA
├── Security groups
└── Encrypted storage

Kubernetes
├── RBAC
├── Kyverno
├── NetworkPolicies
├── Namespaces
└── Resource governance

Secrets
└── External Secrets Operator

Traffic
├── Gateway API
├── Traefik
└── TLS / cert-manager

GitOps
├── Argo CD
├── AppProject
├── desired-state reconciliation
└── auditable Git history
```
The intention is to reduce blast radius if one layer is bypassed or compromised.

---

# 3. AWS Identity and IRSA

The platform uses IAM Roles for Service Accounts instead of relying on the EC2 worker-node IAM role for application or controller permissions.

The EKS OIDC provider enables Kubernetes ServiceAccounts to assume dedicated IAM roles.

Conceptually:
```
Kubernetes ServiceAccount
        │
        ▼
EKS OIDC Provider
        │
        ▼
Dedicated IAM Role
        │
        ▼
Required AWS API
```
Dedicated IAM permissions are used for platform components including:
```
ExternalDNS
External Secrets Operator
Amazon EBS CSI Driver
Amazon VPC CNI
Karpenter
```
This is preferable to attaching broad AWS permissions to the worker-node role because every workload on that node could otherwise potentially gain access to those permissions.

Example
```
ExternalDNS requires Route 53 access.
```
Instead of allowing all EKS worker nodes to modify Route 53, only the ExternalDNS ServiceAccount assumes the dedicated ExternalDNS IAM role.

The same pattern is applied to other AWS-integrated controllers.

---

# 4. Least-Privilege IAM

IAM policies are separated by function.

Examples include:
```
ExternalDNS
└── Route 53 permissions

External Secrets Operator
└── Secrets Manager permissions

EBS CSI Driver
└── EBS-related permissions

Karpenter Controller
├── EC2 discovery
├── EC2 provisioning
├── IAM instance-profile operations
└── interruption handling

Karpenter Nodes
└── worker-node runtime permissions
```
The objective is to reduce the consequences of a compromised Kubernetes controller or workload.

Broad administrative IAM permissions are not intentionally assigned to application workloads.

---

# 5. Secrets Management

Secret values should not be stored directly inside the Git repository.

The project uses External Secrets Operator to retrieve sensitive data from AWS Secrets Manager.

The design is:
```
Git Repository
        │
        │ ExternalSecret definition
        ▼
External Secrets Operator
        │
        ▼
AWS Secrets Manager
        │
        ▼
Kubernetes Secret
        │
        ▼
Application
```
Git stores only the declarative reference to the secret.

The actual secret value remains in AWS Secrets Manager.

This improves:
```
secret rotation
credential separation
Git repository safety
auditability
centralized secret management
```
The External Secrets controller accesses AWS through its dedicated IRSA role.

---

# 6. Kyverno Policy Enforcement

Kyverno provides policy-as-code enforcement through Kubernetes admission control.

The platform currently implements policies that:
```
reject privileged containers
require CPU requests
require memory requests
require CPU limits
require memory limits
```
The enforcement path is:
```
kubectl apply
      │
      ▼
Kubernetes API Server
      │
      ▼
Kyverno Admission Webhook
      │
      ├── Policy passes
      │      │
      │      ▼
      │   Resource created
      │
      └── Policy fails
             │
             ▼
        Request rejected
```
This converts security rules from documentation into executable policy.

---

# 7. Privileged Container Prevention

Privileged containers provide elevated access to the underlying node and significantly increase the impact of container compromise.

The project enforces a Kyverno ClusterPolicy preventing privileged containers in the application namespace.

The policy was tested by attempting to create a Pod containing:
```
securityContext:
  privileged: true
```
The Kubernetes API rejected the request through the Kyverno admission webhook.

Example validation result:

resource Pod/gateway-demo/kyverno-privileged-test was blocked

disallow-privileged-containers:
Privileged containers are prohibited in application namespaces.

This confirms that the policy was not only defined in Git but actively enforced at runtime.

---

# 8. Resource Governance Policy

The platform also requires application containers to define CPU and memory requests and limits.

Required configuration includes:
```
resources:
  requests:
    cpu: ...
    memory: ...
  limits:
    cpu: ...
    memory: ...
```
This is both a reliability and security-related control.

Without resource governance, workloads can consume excessive node resources and affect neighboring workloads.

The policy was validated by intentionally submitting a Pod without resource requests and limits.

Kyverno rejected the workload.

Example:
```
require-resource-requests-limits:

Every container must define CPU and memory requests and limits.
```
This demonstrates operational policy enforcement rather than static YAML alone.

---

# 9. Kubernetes Network Security

The application namespace uses Kubernetes NetworkPolicies with a default-deny model.

The base posture is:
```
Ingress = DENY
Egress  = DENY
```
Required communication is then explicitly allowed.

Implemented policies include:
```
default-deny ingress
default-deny egress
allow DNS egress
allow Traefik ingress to application workloads
```
This creates a zero-trust network model inside the Kubernetes cluster.

A workload does not automatically receive unrestricted communication simply because it is running in the same cluster.

---

# 10. NetworkPolicy Traffic Model

The intended inbound application path is:
```
Internet
   │
   ▼
AWS Load Balancer
   │
   ▼
Traefik
   │
   ▼
Allowed by NetworkPolicy
   │
   ▼
Application Pod
```
DNS resolution remains explicitly allowed because application workloads require access to Kubernetes DNS.

All other communication remains denied unless an explicit policy allows it.

This reduces lateral movement opportunities if an application workload is compromised.

---

# 11. Private Worker Nodes

EKS worker nodes are deployed in private subnets.

They do not require direct public Internet exposure.

Conceptually:
```
Internet
   │
   ▼
Public Load Balancer
   │
   ▼
Private EKS Worker Nodes
```
Outbound connectivity from private nodes is provided through controlled AWS networking such as the NAT Gateway.

The advantage is that worker nodes do not expose public IP addresses for direct inbound administrative or application access.

---

# 12. Security Groups

AWS security groups provide another network-control layer outside Kubernetes.

Security groups are used for communication between:
```
EKS control plane
worker nodes
load-balancing infrastructure
other AWS-integrated resources
```
Kubernetes NetworkPolicies and AWS security groups solve different problems.

Security groups protect AWS network interfaces and VPC-level connectivity.

NetworkPolicies control Kubernetes pod communication.

Using both provides layered network security.

---

# 13. Gateway API Security Boundary

External traffic enters the cluster through Gateway API managed by Traefik.

The traffic model is:
```
Client
  │
  ▼
DNS
  │
  ▼
AWS Load Balancer
  │
  ▼
Traefik Gateway
  │
  ▼
HTTPRoute
  │
  ▼
Service
  │
  ▼
Application Pod
```
The Gateway model separates platform-owned infrastructure from application-specific routes.

This provides clearer ownership boundaries than a single monolithic ingress configuration.

---

# 14. TLS Encryption

External application traffic is designed to use TLS.

cert-manager automates certificate lifecycle management.

The flow is:
```
Certificate Resource
      │
      ▼
cert-manager
      │
      ▼
ACME Provider
      │
      ▼
Challenge Validation
      │
      ▼
TLS Certificate
      │
      ▼
Kubernetes Secret
      │
      ▼
Gateway Listener
```
This reduces manual certificate-management effort and supports automated renewal.

TLS protects traffic between external clients and the exposed application endpoint.

---

# 15. ExternalDNS Security Model

ExternalDNS manages Route 53 DNS records from Kubernetes resources.

Its permissions are provided through a dedicated IAM role using IRSA.

The controller is therefore able to perform required Route 53 operations without granting Route 53 permissions to unrelated workloads.

This is another example of separating AWS privileges according to controller responsibility.

---

# 16. Karpenter Security Architecture

Karpenter requires significant AWS integration because it dynamically provisions EC2 capacity.

The platform separates:
```
Karpenter Controller Role
        │
        ├── discover EC2 resources
        ├── create compute capacity
        ├── manage instance profiles
        └── process interruption events

Karpenter Node Role
        │
        └── permissions required by worker nodes
```
Separating these roles reduces the amount of privilege assigned to individual EC2 worker nodes.

The Karpenter controller itself assumes its dedicated IAM role through IRSA.

---

# 17. Karpenter Instance Profile Permissions

During implementation, Karpenter required IAM permissions for instance-profile lifecycle operations.

One important permission was:

iam:ListInstanceProfiles

This action cannot be resource-scoped and therefore requires:
```
"Resource": "*"
```
The permission was added as a separate IAM policy statement instead of unnecessarily broadening unrelated IAM actions.

This preserves least privilege while satisfying AWS IAM API requirements.

---

# 18. EC2 Spot Service-Linked Role

Karpenter supports both On-Demand and Spot capacity.

During testing, Spot provisioning initially encountered:
```
AuthFailure.ServiceLinkedRoleCreationNotPermitted
```
The required AWS service-linked role was created:

AWSServiceRoleForEC2Spot

This enabled the AWS account to use EC2 Spot capacity.

The issue demonstrates an important real-world distinction between:
```
Karpenter controller permissions
AWS account-level service-linked roles
```
Not every provisioning failure is caused by Kubernetes or the Karpenter controller IAM policy.

---

# 19. Karpenter Runtime Validation

Karpenter was validated by forcing a workload to require a Karpenter-managed node.

The workload used:
```
nodeSelector:
  node-provisioner: karpenter
```
The existing EKS Managed Node Group could not satisfy that scheduling requirement.

The workflow became:
```
Pending Pod
   │
   ▼
Karpenter detects unschedulable workload
   │
   ▼
NodeClaim created
   │
   ▼
EC2 instance launched
   │
   ▼
Node joins EKS
   │
   ▼
Pod scheduled
```
A c6a.large instance was dynamically created during validation.

The resulting node contained labels including:
```
node-provisioner=karpenter
karpenter.sh/nodepool=default
karpenter.sh/capacity-type=on-demand
node.kubernetes.io/instance-type=c6a.large
```
This confirmed end-to-end compute provisioning.

---

# 20. Karpenter Consolidation

After the test workload was removed, Karpenter eventually removed the no-longer-required compute node.

This validates the reverse lifecycle:
```
Workload removed
   │
   ▼
Node becomes unnecessary
   │
   ▼
Karpenter consolidation
   │
   ▼
NodeClaim deleted
   │
   ▼
EC2 instance terminated
```
From a security and operational perspective, this also reduces the lifetime of unnecessary compute resources.

---

# 21. Storage Security

The platform uses the Amazon EBS CSI Driver for persistent-storage integration.

The project defines a gp3 StorageClass using:
```
ebs.csi.aws.com
```
EBS volumes are configured with encryption for Karpenter-created worker-node block devices.

The EBS CSI Driver uses a dedicated IRSA role instead of broad worker-node permissions.

This separates storage-controller permissions from general workloads.

# 22. Kubernetes RBAC

Kubernetes RBAC controls access to Kubernetes API resources.

RBAC and AWS IAM serve different purposes.
```
AWS IAM
└── AWS API authorization

Kubernetes RBAC
└── Kubernetes API authorization
```
For example:
```
IAM determines whether a controller may modify Route 53
RBAC determines whether a Kubernetes identity may create or modify Kubernetes resources
```
Production Kubernetes security requires consideration of both authorization systems.

---

# 23. GitOps as a Security Control

Argo CD provides centralized desired-state management.

Instead of relying on manual cluster modifications, configuration is stored in Git and reconciled into the cluster.

Benefits include:
```
auditable change history
reproducible configuration
easier rollback
drift detection
controlled deployment workflow
separation between declared and live state
```
The App-of-Apps pattern allows individual platform services to be managed independently.

---

# 24. Argo CD AppProject

The project uses an Argo CD AppProject to define platform boundaries.

The AppProject controls:
```
approved source repositories
target cluster
destination namespaces
allowed namespace-scoped resources
allowed cluster-scoped resources
```
This provides a governance layer around GitOps applications.

Without an AppProject boundary, Argo CD applications could be given unnecessarily broad deployment freedom.

---

# 25. GitOps Drift Detection

Argo CD continuously compares desired configuration in Git with live Kubernetes state.

The desired model is:
```
Git
 │
 ▼
Argo CD
 │
 ├── compare desired state
 │
 ├── detect drift
 │
 └── reconcile resources
 │
 ▼
Kubernetes
```
For managed resources, manual changes can therefore be detected and corrected.

This supports configuration integrity.

---

# 26. Security Testing Strategy

Security controls were not considered complete until they were tested.

The project uses negative testing for controls such as:
```
privileged containers
missing resource requests and limits
IAM failures
Karpenter provisioning
NetworkPolicy behavior
external secret synchronization
TLS configuration
GitOps synchronization
```
Negative testing is especially valuable because it proves that a control blocks an invalid condition.

---

# 27. Runtime Security Evidence

Validated security controls include:

## Kyverno
```
disallow-privileged-containers
READY=True
```
```
require-resource-requests-limits
READY=True
```
Privileged workloads were rejected.

Workloads without resource governance were rejected.

NetworkPolicies

The application namespace included:
```
default-deny-ingress
default-deny-egress
allow-dns-egress
allow-traefik-ingress
```
## External Secrets

External Secrets Operator pods were running successfully.

## Karpenter

Karpenter successfully created and removed EC2 worker capacity.

## TLS / Gateway

Gateway API, Traefik, cert-manager and ExternalDNS were deployed and integrated.

---

# 28. Threat Scenario: Compromised Application Pod

If an application container is compromised, the platform attempts to reduce the blast radius through several controls.
```
Compromised Pod
   │
   ├── no privileged container capability
   ├── limited network connectivity
   ├── no broad worker-node AWS permissions
   ├── namespace boundaries
   ├── dedicated controller IAM identities
   └── resource limits
```
These controls do not make compromise impossible.

They reduce the opportunities available after compromise.

---

# 29. Threat Scenario: Credential Exposure

Credential risk is reduced by avoiding plaintext application secrets in Git.

The intended flow is:
```
Git
└── secret reference only

AWS Secrets Manager
└── actual secret value
```
External Secrets Operator retrieves the value using dedicated AWS identity.

A Git repository compromise therefore does not automatically expose all runtime secret values.

---

# 30. Threat Scenario: Unsafe Workload Configuration

A developer could accidentally deploy a privileged container or omit resource controls.

Without admission policy, that configuration may reach production.

Kyverno prevents this by evaluating the resource before it is accepted by the Kubernetes API.

This creates a centralized platform guardrail that does not depend on every developer remembering every security requirement.

---

# 31. Security Responsibility Model

The platform separates responsibilities.

## Infrastructure Engineering

Responsible for:
```
VPC
subnets
IAM
EKS
AWS security groups
Terraform
```
## Platform Engineering

Responsible for:
```
Argo CD
Kyverno
NetworkPolicies
External Secrets
Gateway API
cert-manager
Karpenter
observability
platform security standards
```
## Application Teams

Responsible for:
```
secure application code
container images
application configuration
resource requests and limits
application routes
workload-specific secrets usage
```
Security is shared across layers rather than assigned entirely to one team.

---

# 32. Production Improvements

The project demonstrates strong production concepts, but a real enterprise environment could add additional controls.

Potential improvements include:
```
private EKS API endpoint
AWS VPC endpoints
AWS WAF
GuardDuty
Security Hub
CloudTrail alerting
container image signing
admission-time signature verification
SBOM generation
continuous vulnerability scanning
runtime security tooling
centralized SIEM integration
stricter Argo CD RBAC
SSO integration
mandatory pull-request approvals
branch protection
policy exceptions with approval workflow
stronger Pod Security Standards
workload identity migration where appropriate
AWS KMS key separation
encrypted Terraform remote state
multi-account environment separation
```
These are deliberately treated as production hardening enhancements rather than falsely represented as completed functionality.

---

# 33. Security Validation Checklist

The final environment should validate:
```
[ ] EKS worker nodes are Ready
[ ] worker nodes are using private subnets
[ ] ExternalDNS uses dedicated IRSA
[ ] External Secrets uses dedicated IRSA
[ ] EBS CSI uses dedicated IRSA
[ ] Karpenter controller uses dedicated IRSA
[ ] Kyverno controllers are Running
[ ] ClusterPolicies are Ready
[ ] privileged Pod test is rejected
[ ] missing-resource Pod test is rejected
[ ] default-deny NetworkPolicies exist
[ ] DNS egress policy exists
[ ] Traefik ingress policy exists
[ ] cert-manager controllers are Running
[ ] Gateway API is programmed
[ ] ExternalDNS is Running
[ ] Karpenter EC2NodeClass is Ready
[ ] Karpenter NodePool is Ready
[ ] Karpenter can create a NodeClaim
[ ] Karpenter can launch an EC2 worker node
[ ] Karpenter can remove unused capacity
[ ] Argo CD applications are healthy
[ ] no unexpected failed or pending Pods remain
```
---

# 34. Evidence to Capture

During the final environment recreation, screenshots should be captured for portfolio evidence.

Recommended screenshots:
```
docs/images/security/
├── aws-iam-irsa.png
├── external-secrets.png
├── kyverno-policies-ready.png
├── kyverno-privileged-denied.png
├── kyverno-resources-denied.png
├── network-policies.png
├── gateway-tls.png
├── karpenter-irsa.png
├── karpenter-nodeclaim.png
├── karpenter-node.png
└── argocd-security-apps.png
```
Sensitive information should be redacted where appropriate.

Do not expose:
```
secrets
access keys
tokens
passwords
private keys
session credentials
```
AWS account IDs and resource ARNs may also be redacted in public screenshots if desired.

---

# 35. Senior DevOps Engineering Perspective

The important security lesson from this project is that Kubernetes security is not one feature.

It is a combination of controls across multiple domains.
```
Identity
├── IAM
└── IRSA

Network
├── Security Groups
└── NetworkPolicies

Secrets
└── External Secrets Operator

Admission
└── Kyverno

Transport
└── TLS

Configuration
└── GitOps

Compute
└── Karpenter role separation

Storage
└── EBS CSI + encryption
```
A production platform becomes safer when these controls reinforce one another.

The strongest evidence in this project is not simply that these technologies were installed.

The controls were integrated and validated through real runtime behavior.

Examples include:
```
deliberately attempting privileged workload deployment
deliberately omitting resource requests and limits
troubleshooting AWS IAM failures
separating Karpenter controller and node roles
validating Karpenter dynamic node creation
verifying node consolidation
implementing default-deny networking
integrating external secret retrieval through IRSA
```
That distinction is important in platform engineering.

Installing a security tool is not the same as proving that the security control works.

---

# 36. Final Security Architecture

The resulting platform security model can be summarized as:
```
                         GitHub
                           │
                           ▼
                        Argo CD
                           │
                 Desired State / Audit
                           │
                           ▼
                    Kubernetes API
                           │
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
         Kyverno       Kubernetes     Platform
         Policy        NetworkPolicy  Controllers
            │              │              │
            │              │              ▼
            │              │             IRSA
            │              │              │
            └──────────────┼──────────────┤
                           │              │
                           ▼              ▼
                        Workloads        AWS
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ▼                     ▼                     ▼
                 Route 53          Secrets Manager             EC2
                    │                                         Karpenter
                    ▼
                 DNS / TLS
```
The architecture demonstrates a layered security model where AWS security, Kubernetes security, GitOps, network policy, identity, secrets, admission policy, and runtime validation operate together.
