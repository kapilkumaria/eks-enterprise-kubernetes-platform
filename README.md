# Enterprise Kubernetes Platform Engineering on AWS EKS

[![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS-blue)](https://kubernetes.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-orange)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-purple)](https://www.terraform.io/)
[![Argo CD](https://img.shields.io/badge/GitOps-Argo%20CD-orange)](https://argo-cd.readthedocs.io/)
[![Karpenter](https://img.shields.io/badge/Autoscaling-Karpenter-blue)](https://karpenter.sh/)
[![Kyverno](https://img.shields.io/badge/Policy-Kyverno-green)](https://kyverno.io/)
[![Prometheus](https://img.shields.io/badge/Monitoring-Prometheus-red)](https://prometheus.io/)

Production-oriented Kubernetes platform engineering project demonstrating the design and implementation of an enterprise-style application platform on **Amazon EKS**.

The platform combines:

- Infrastructure as Code
- managed Kubernetes
- GitOps
- Gateway API
- automated DNS
- automated TLS
- external secrets management
- policy-as-code
- Kubernetes network security
- observability
- workload autoscaling
- event-driven autoscaling
- dynamic node provisioning
- persistent storage

The objective was not simply to deploy an application to Kubernetes, but to build the surrounding **platform capabilities required to operate Kubernetes workloads reliably, securely, and declaratively**.

---

# 1. Project Overview

Modern Kubernetes environments require substantially more than a running cluster.

A production platform must address questions such as:

- How is the underlying cloud infrastructure created consistently?
- How are Kubernetes changes deployed and reconciled?
- How are workloads exposed to users?
- How are DNS records created?
- How are TLS certificates issued and renewed?
- How are application secrets retrieved securely?
- How are unsafe workloads prevented from entering the cluster?
- How is network communication restricted?
- How are workloads monitored?
- How are applications scaled?
- How is cluster compute capacity scaled?
- How is persistent storage dynamically provisioned?

This project implements those capabilities as an integrated Kubernetes platform running on AWS.

---

# 2. Problem Statement

A Kubernetes cluster by itself does not provide a complete production application platform.

Without additional platform engineering controls, organizations commonly face:

- manually created cloud infrastructure
- configuration drift
- inconsistent deployments
- direct production changes
- manually maintained DNS
- manual certificate management
- Kubernetes Secrets containing long-lived credentials
- privileged or improperly configured containers
- unrestricted pod-to-pod communication
- insufficient monitoring
- inefficient static node capacity
- poor workload scaling
- inconsistent persistent storage provisioning

This project addresses those problems through a declarative platform architecture.

---

# 3. High-Level Architecture

The platform combines Terraform-provisioned AWS infrastructure with GitOps-managed Kubernetes services on Amazon EKS.

The following diagram presents the end-to-end platform architecture, including infrastructure provisioning, GitOps reconciliation, traffic management, security controls, observability, workload autoscaling, dynamic node provisioning, persistent storage, and AWS service integrations.

![Enterprise Kubernetes Platform Architecture](diagrams/enterprise-kubernetes-platform-architecture.png)

## Architecture at a Glance

The platform is organized into several integrated engineering layers:

- **Infrastructure as Code** — Terraform provisions AWS networking, Amazon EKS, IAM, OIDC/IRSA, managed node capacity, and supporting infrastructure.
- **GitOps** — Argo CD continuously reconciles Kubernetes desired state from Git using the App-of-Apps pattern.
- **Traffic Management** — Kubernetes Gateway API and Traefik provide external application routing through shared gateway infrastructure.
- **DNS and TLS Automation** — ExternalDNS integrates Kubernetes with Amazon Route 53, while cert-manager automates certificate lifecycle management.
- **Security** — IRSA, Kyverno, NetworkPolicies, private worker nodes, security groups, External Secrets, and Kubernetes RBAC provide layered security controls.
- **Observability** — Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporter provide metrics collection, visualization, alerting, and infrastructure visibility.
- **Workload Autoscaling** — HPA provides resource-based pod scaling, while KEDA provides Prometheus-driven autoscaling.
- **Infrastructure Autoscaling** — Karpenter dynamically provisions EC2 capacity when Kubernetes workloads require additional compute and consolidates capacity when demand decreases.
- **Persistent Storage** — the Amazon EBS CSI driver and `gp3` StorageClass provide dynamic persistent-volume provisioning.

The architecture separates infrastructure provisioning from Kubernetes platform lifecycle management:

```text
                   Git Repository
                         |
                         v
                      Argo CD
                         |
                         v
               Kubernetes Desired State
                         |
                         v
                    Amazon EKS
                         ^
                         |
                 AWS Infrastructure
                         ^
                         |
                      Terraform
```

Terraform manages the underlying AWS infrastructure, while Argo CD manages the Kubernetes platform desired state stored in Git.

Application traffic follows a separate runtime path:

```text
Internet
   |
   v
Amazon Route 53
   |
   v
AWS Load Balancer
   |
   v
Kubernetes Gateway API
   |
   v
Traefik Gateway
   |
   v
HTTPRoute
   |
   v
Application Workloads
```

Platform controllers provide supporting capabilities around those workloads:

```text
Application Workloads
        |
        +------> Prometheus ------> Grafana / Alertmanager
        |
        +------> HPA / KEDA ------> Replica Scaling
        |
        +------> Karpenter -------> Dynamic EC2 Capacity
        |
        +------> Kyverno ---------> Admission Policy Enforcement
        |
        +------> NetworkPolicy ---> Network Isolation

External Secrets ------> AWS Secrets Manager
ExternalDNS -----------> Amazon Route 53
cert-manager ----------> Automated TLS Certificates
EBS CSI Driver --------> Amazon EBS / gp3
```

This architecture provides three complementary control loops:

**Infrastructure reconciliation**

```text
Terraform -> AWS Infrastructure -> Amazon EKS
```

**Platform reconciliation**

```text
Git -> Argo CD -> Kubernetes Desired State
```

**Runtime elasticity**

```text
Metrics / Events
      |
      v
HPA / KEDA
      |
      v
Pod Scaling
      |
      v
Karpenter
      |
      v
EC2 Node Capacity
```

Together, these layers provide a declarative, secure, observable, and dynamically scalable Kubernetes platform rather than simply an EKS cluster.

For a detailed discussion of the architecture and individual platform components, see:

[`docs/architecture.md`](docs/architecture.md)

---
# 4. Core Platform Capabilities

| Capability           | Technology                | Purpose                                 |
| -------------------- | ------------------------- | --------------------------------------- |
| Cloud Infrastructure | Terraform                 | Declarative AWS infrastructure          |
| Managed Kubernetes   | Amazon EKS                | Kubernetes control plane                |
| Networking           | Amazon VPC                | Network isolation and routing           |
| Identity             | AWS IAM + OIDC/IRSA       | Pod-level AWS access                    |
| GitOps               | Argo CD                   | Continuous desired-state reconciliation |
| Traffic Management   | Kubernetes Gateway API    | Modern application routing              |
| Gateway Controller   | Traefik                   | Gateway API implementation              |
| DNS Automation       | ExternalDNS               | Route 53 record management              |
| TLS Automation       | cert-manager              | Certificate lifecycle automation        |
| Secrets              | External Secrets Operator | External secret synchronization         |
| Policy Enforcement   | Kyverno                   | Kubernetes policy-as-code               |
| Network Security     | NetworkPolicy             | Pod communication restrictions          |
| Metrics              | Prometheus                | Metrics collection                      |
| Visualization        | Grafana                   | Dashboards and observability            |
| Alerting             | Alertmanager              | Alert routing                           |
| Resource Metrics     | Metrics Server            | Kubernetes resource metrics             |
| Workload Scaling     | HPA                       | CPU/resource-based scaling              |
| Event Scaling        | KEDA                      | Prometheus/event-driven scaling         |
| Node Provisioning    | Karpenter                 | Dynamic EC2 capacity                    |
| Persistent Storage   | AWS EBS CSI               | Kubernetes persistent volumes           |
| Storage Class        | gp3                       | AWS EBS dynamic provisioning            |

---

# 5. Platform Engineering Principles

Several engineering principles guided the implementation.

### Declarative Infrastructure

AWS infrastructure is defined through Terraform rather than being manually created.

This improves:
```
reproducibility
auditability
consistency
disaster recovery
environment recreation
```
### Git as Desired State

Kubernetes platform configuration is stored in Git.

Argo CD continuously compares:

```
Git Desired State
        |
        v
Argo CD Reconciliation
        |
        v
Kubernetes Live State
```
This reduces configuration drift and discourages unmanaged production changes.

### Separation of Platform and Application Concerns

The repository separates:

infrastructure
platform components
GitOps configuration
application configuration
environment configuration
documentation

This mirrors the separation commonly used by platform engineering teams.

### Least-Privilege Cloud Access:

Kubernetes workloads requiring AWS API access use:

```
Kubernetes ServiceAccount
          |
          v
        OIDC
          |
          v
        IRSA
          |
          v
      AWS IAM Role
```
Applications do not require static AWS credentials stored inside container images.

### Defense in Depth

Security controls exist across multiple layers:

```
AWS IAM
   +
Private Networking
   +
TLS
   +
External Secrets
   +
Kyverno
   +
NetworkPolicy
   +
Resource Controls
   +
Encrypted Storage
```
---

# 6. Repository Structure
```
eks-enterprise-kubernetes-platform/
|
├── applications/
│   └── online-boutique/
|
├── argocd/
│   ├── applications/
│   ├── app-of-apps/
│   ├── bootstrap/
│   └── projects/
|
├── clusters/
│   ├── dev/
│   ├── staging/
│   └── prod/
|
├── platform/
│   ├── autoscaling/
│   ├── cert-manager/
│   ├── external-dns/
│   ├── external-secrets/
│   ├── gateway-api/
│   ├── karpenter/
│   ├── keda/
│   ├── kyverno/
│   ├── metrics-server/
│   ├── network-policies/
│   ├── observability/
│   ├── storage/
│   └── traefik-gateway/
|
├── terraform/
│   └── aws/
|
├── manifests/
├── docs/
├── diagrams/
├── scripts/
├── Makefile
└── README.md
```
This structure separates infrastructure provisioning from Kubernetes platform configuration and GitOps orchestration.

---

# 7. Infrastructure as Code

Terraform provisions the AWS infrastructure required by the platform.

The infrastructure layer includes:

VPC
public subnets
private subnets
routing
NAT connectivity
security groups
EKS
managed worker nodes
IAM roles
OIDC integration
EKS add-ons
supporting IAM resources

Conceptually:

```
Terraform
    |
    v
AWS Infrastructure
    |
    +--> VPC
    |
    +--> Public Subnets
    |
    +--> Private Subnets
    |
    +--> IAM
    |
    +--> EKS Control Plane
    |
    +--> Managed Node Group
    |
    +--> EKS Add-ons
```
---

# 8. Amazon EKS Architecture

Amazon EKS provides the managed Kubernetes control plane.

Worker nodes operate inside the project VPC.

The implementation uses AWS-managed Kubernetes integrations including:
```
Amazon VPC CNI
CoreDNS
kube-proxy
Amazon EBS CSI
```
The architecture separates the managed Kubernetes control plane from worker compute capacity.

---

# 9. GitOps with Argo CD

Argo CD is responsible for deploying and continuously reconciling Kubernetes platform components.

The repository uses an App-of-Apps pattern.
```
Bootstrap
    |
    v
Root Argo CD Application
    |
    v
+-----------------------------+
| Platform Applications       |
+-----------------------------+
| cert-manager                |
| ExternalDNS                 |
| External Secrets            |
| Gateway API                 |
| Traefik                     |
| Kyverno                     |
| Metrics Server              |
| Prometheus / Grafana        |
| KEDA                        |
| Karpenter                   |
| Network Policies            |
+-----------------------------+
```
Once Argo CD is bootstrapped, the majority of the Kubernetes platform is reconstructed through GitOps.

Argo CD provides:
```
automated synchronization
pruning
self-healing
application health visibility
declarative deployment
Git-based audit history
```
---

# 10. Kubernetes Gateway API

Application ingress is implemented using the Kubernetes Gateway API rather than relying exclusively on the traditional Ingress API.

Primary resources include:

GatewayClass
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
Pods

Traefik acts as the Gateway API controller.

This provides a structured separation between infrastructure-level gateway configuration and application routing configuration.

---

# 11. Automated DNS

ExternalDNS integrates Kubernetes resources with Amazon Route 53.

The desired flow is:
```
Gateway / Route
       |
       v
ExternalDNS
       |
       v
Amazon Route 53
       |
       v
DNS Record
```
This removes the requirement to manually create DNS records whenever Kubernetes endpoints change.

---

# 12. Automated TLS

cert-manager provides certificate lifecycle automation.

The platform integrates:

```
cert-manager
      |
      v
Let's Encrypt / ACME
      |
      v
Certificate
      |
      v
Kubernetes TLS Secret
      |
      v
Gateway HTTPS Listener
```
This architecture enables automated certificate issuance and renewal.

---

# 13. External Secrets Management

Application secrets are not intended to be managed directly as plaintext values in Git.

External Secrets Operator integrates Kubernetes with external secret stores.

Conceptually:
```
AWS Secrets Manager
        |
        v
External Secrets Operator
        |
        v
ExternalSecret
        |
        v
Kubernetes Secret
        |
        v
Application Pod
```
AWS access is provided using IAM/OIDC integration rather than embedding long-lived AWS credentials in workloads.

---

# 14. Policy as Code with Kyverno

Kyverno provides Kubernetes admission policy enforcement.

Two policies were implemented and validated:

### Disallow Privileged Containers

Privileged containers are rejected in the protected application namespace.

### Require Resource Requests and Limits

Application containers must specify CPU and memory requests and limits.

The enforcement path is:
```
kubectl apply
      |
      v
Kubernetes API Server
      |
      v
Kyverno Admission Webhook
      |
      v
ClusterPolicy
      |
      +---- compliant ----> admitted
      |
      +---- violation ----> rejected
```
The policies were validated using negative tests.

A privileged Pod was intentionally submitted and rejected:
```
admission webhook "validate.kyverno.svc-fail" denied the request

disallow-privileged-containers:
Privileged containers are prohibited in application namespaces.
```
A Pod without CPU and memory requests/limits was also intentionally submitted and rejected.

This demonstrates that the policies were not only installed but functionally tested.

---

# 15. Kubernetes Network Security

NetworkPolicy resources implement application-level traffic restrictions.

The protected namespace includes controls for:
```
default-deny ingress
default-deny egress
explicit DNS egress
explicitly permitted gateway-to-application traffic
```
The model follows:
```
Default Deny
     |
     +--> Explicit DNS
     |
     +--> Explicit Gateway Traffic
     |
     +--> Other Traffic Denied
```
This reduces unrestricted east-west communication between workloads.

---

# 16. Observability

The platform includes a Kubernetes-native monitoring stack based on:
```
Prometheus
Grafana
Alertmanager
kube-state-metrics
node-exporter
Prometheus Operator
```
Conceptually:
```
Kubernetes
     |
     +--> Node Metrics
     |
     +--> Pod Metrics
     |
     +--> Application Metrics
     |
     v
Prometheus
     |
     +--> Grafana
     |
     +--> Alertmanager
```
Prometheus provides the metrics foundation for both observability and metric-driven autoscaling.

---

# 17. Workload Autoscaling

The platform demonstrates multiple layers of autoscaling.

### Horizontal Pod Autoscaler

HPA provides Kubernetes-native workload scaling based on resource utilization.
```
CPU / Resource Demand
        |
        v
Metrics Server
        |
        v
HPA
        |
        v
Deployment Replicas
```
---

# 18. Event-Driven Autoscaling with KEDA

KEDA extends workload autoscaling beyond standard CPU and memory metrics.

A Prometheus-backed ScaledObject was implemented for the demonstration workload.
```
Application Metrics
        |
        v
Prometheus
        |
        v
KEDA
        |
        v
HPA
        |
        v
Deployment
```
The implementation was validated with:
```
ScaledObject: whoami-prometheus
Target:       Deployment/whoami
Minimum:      2
Maximum:      6
Ready:        True
Trigger:      Prometheus
```
This demonstrates event/metric-driven autoscaling using an external metrics source.

---

# 19. Dynamic Node Provisioning with Karpenter

Karpenter provides dynamic Kubernetes worker-node provisioning.

It addresses a different scaling layer than HPA and KEDA.
```
Application Demand
       |
       v
HPA / KEDA
       |
       v
Additional Pods
       |
       v
Unschedulable Pods
       |
       v
Karpenter
       |
       v
NodePool
       |
       v
EC2NodeClass
       |
       v
EC2 Instance
```
Karpenter was configured using:
```
NodePool
EC2NodeClass
IAM integration
subnet discovery
security group discovery
instance constraints
consolidation behavior
```
Scale-out was validated by creating workload demand that could not fit on existing nodes.

Karpenter dynamically provisioned additional EC2 capacity.

After demand was removed, consolidation behavior was also validated.

This demonstrates both:
```
Scale Out
   +
Scale In / Consolidation
```
---

# 20. Three Layers of Autoscaling

A key architectural aspect of the project is the separation of autoscaling responsibilities.
```
| Layer                                | Technology | Responsibility                                  |
| ------------------------------------ | ---------- | ----------------------------------------------- |
| Resource-based workload scaling      | HPA        | Scale Pods based on CPU/resource metrics        |
| Event/metric-driven workload scaling | KEDA       | Scale Pods based on Prometheus/external metrics |
| Infrastructure scaling               | Karpenter  | Provision/remove EC2 worker capacity            |
```
Together:
```
Traffic / Demand
       |
       v
Application Metrics
       |
       v
HPA / KEDA
       |
       v
More Pods
       |
       v
Scheduler Capacity Pressure
       |
       v
Karpenter
       |
       v
More Nodes
```
This is a core platform engineering design demonstrated by the project.

---

# 21. Persistent Storage

AWS EBS CSI provides Kubernetes persistent storage integration.

A gp3 StorageClass is available for dynamic provisioning.
```
PersistentVolumeClaim
        |
        v
StorageClass: gp3
        |
        v
EBS CSI Driver
        |
        v
Amazon EBS Volume
        |
        v
PersistentVolume
        |
        v
Pod
```
The StorageClass uses:
```
Provisioner:          ebs.csi.aws.com
ReclaimPolicy:        Delete
VolumeBindingMode:    WaitForFirstConsumer
AllowVolumeExpansion: true
```
WaitForFirstConsumer allows volume placement to consider the topology of the Pod consuming the storage.

---

# 22. Environment Strategy

The repository contains environment-oriented structure for:
```
clusters/
├── dev/
├── staging/
└── prod/
```
The implemented environment is primarily the development platform.

The directory model demonstrates how the architecture can be extended toward environment-specific GitOps configuration.

Production environments would typically introduce additional controls including:
```
stricter promotion workflows
protected branches
approval gates
production-specific capacity
stronger availability requirements
backup and disaster recovery policies
production secret stores
dedicated DNS and certificate configuration
```
---

# 23. Reproducing the Platform

Important: cloud resources created by this project can incur AWS charges.

The repository is designed so that the platform can be recreated from source-controlled configuration.

## Prerequisites

Typical prerequisites include:
```
AWS account
AWS CLI
Terraform
kubectl
Helm
Argo CD CLI
Git
appropriate AWS IAM permissions
```
## Step 1 — Clone Repository
```
git clone https://github.com/kapilkumaria/eks-enterprise-kubernetes-platform.git

cd eks-enterprise-kubernetes-platform
```
## Step 2 — Provision AWS Infrastructure

Navigate to the Terraform development environment:
```
cd terraform/aws/environments/dev
```
Initialize Terraform:
```
terraform init
```
Validate configuration:
```
terraform validate
```
Review the execution plan:
```
terraform plan
```
Provision the infrastructure:
```
terraform apply
```
## Step 3 — Configure kubectl

After EKS becomes available:
```
aws eks update-kubeconfig \
  --region us-east-1 \
  --name eks-enterprise-platform-dev
```
Validate connectivity:
```
kubectl get nodes
```
## Step 4 — Bootstrap GitOps

Bootstrap Argo CD using the repository's bootstrap configuration.

Then deploy the platform project and root application using the manifests under:
```
argocd/
├── bootstrap/
├── projects/
└── app-of-apps/
```
After the root application is created, Argo CD becomes responsible for reconciling the remaining platform components.

## Step 5 — Validate Argo CD
kubectl get applications -n argocd

The expected objective is for platform applications to converge toward:
```
SYNC STATUS     HEALTH STATUS
Synced          Healthy
```
Some operators may temporarily report intermediate reconciliation states during installation.

## Step 6 — Validate Platform Components

Example validation commands:
```
kubectl get nodes

kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A

kubectl get clusterpolicy

kubectl get networkpolicy -A

kubectl get scaledobject -A

kubectl get ec2nodeclass
kubectl get nodepool
kubectl get nodeclaims

kubectl get storageclass

kubectl top nodes

kubectl get pods -A
```
---

# 24. Platform Validation

The completed platform was validated across multiple control planes.

## Kubernetes Nodes

Worker nodes reached:
```
STATUS
Ready
```
## Gateway API

The GatewayClass was accepted and the shared Gateway reached a programmed state.
```
GatewayClass: traefik
Accepted:     True

Gateway:      shared-public-gateway
Programmed:   True
```
## Kyverno

Both implemented ClusterPolicies reached:
```
READY
True
```
Functional negative testing confirmed policy enforcement.

## Metrics

Metrics Server successfully provided node-level resource metrics:
```
kubectl top nodes
```
## KEDA

The Prometheus-backed ScaledObject reached:
```
READY: True
```
## Karpenter

Both primary Karpenter resources reached readiness:
```
EC2NodeClass/default    Ready=True
NodePool/default        Ready=True
```
Dynamic node provisioning and consolidation were tested separately.

## Storage

The platform provided a gp3 StorageClass using:
```
ebs.csi.aws.com
```
with volume expansion enabled.

## Platform Health

At final infrastructure validation:
```
EKS worker nodes were Ready
Gateway API was operational
ExternalDNS was running
External Secrets was running
Kyverno policies were Ready and enforcing
Prometheus was running
Grafana was running
Alertmanager was running
Metrics Server was operational
KEDA was operational
Karpenter was operational
NetworkPolicies were present
gp3 storage was available
no unexpected Pending or Failed Pods remained
```
---

# 25. Engineering Challenges

Building the platform required troubleshooting interactions between Kubernetes, AWS APIs, operators, GitOps controllers, IAM and admission control.

Several issues provided particularly useful engineering lessons.

## Karpenter IAM Permissions

Karpenter required AWS IAM permissions beyond basic EC2 provisioning.

One troubleshooting case involved AWS IAM discovery operations such as:
```
iam:ListInstanceProfiles
```
Some AWS list operations cannot be resource-scoped in the same manner as individual resource APIs.

The IAM policy therefore had to distinguish between:
```
resource-scoped actions
```
and:
```
actions legitimately requiring Resource: "*"
```
This reinforced the importance of understanding AWS IAM API behavior rather than mechanically applying wildcard permissions or overly restrictive policies.

## Karpenter Subnet Discovery

Karpenter uses AWS resource tags to discover networking resources.

Terraform ownership and Karpenter discovery tagging had to be coordinated so that subnet discovery worked without creating competing ownership of infrastructure tags.

The final design separated:
```
Terraform infrastructure ownership
```
from:
```
Karpenter resource discovery
```
while maintaining Infrastructure-as-Code as the source of truth.

## GitOps and Cluster-Scoped Resources

Kyverno ClusterPolicy resources are cluster-scoped.

An Argo CD configuration initially introduced namespace-related tracking behavior for resources that do not belong to a Kubernetes namespace.

The configuration was corrected so the GitOps Application treated the policies as cluster-scoped resources.

The policies themselves remained healthy and admission enforcement was validated independently through negative tests.

This highlighted the difference between:
```
resource operational health
```
and:
```
GitOps reconciliation representation
```
when troubleshooting Kubernetes operators and custom resources.

## Negative Security Testing

Security controls were not considered complete merely because their Kubernetes objects existed.

For Kyverno, intentionally invalid workloads were submitted to confirm that the admission webhook rejected them.

This changed validation from:
```
Policy exists
```
to:
```
Policy actually prevents the prohibited behavior
```
which is the more meaningful production validation.

---

# 26. Engineering Decisions

| Decision             | Selected Approach | Reason                                     |
| -------------------- | ----------------- | ------------------------------------------ |
| Kubernetes           | Amazon EKS        | Managed Kubernetes control plane           |
| Infrastructure       | Terraform         | Reproducible cloud infrastructure          |
| Deployment Model     | GitOps            | Declarative desired-state operations       |
| GitOps Controller    | Argo CD           | Continuous reconciliation and visibility   |
| Traffic API          | Gateway API       | Modern role-oriented Kubernetes networking |
| Gateway              | Traefik           | Gateway API implementation                 |
| DNS                  | ExternalDNS       | Automated Route 53 integration             |
| TLS                  | cert-manager      | Automated certificate lifecycle            |
| Secrets              | External Secrets  | External secret source integration         |
| AWS Identity         | OIDC / IRSA       | Avoid static AWS credentials in Pods       |
| Admission Policy     | Kyverno           | Kubernetes-native policy-as-code           |
| Network Security     | NetworkPolicy     | Restrict workload communication            |
| Metrics              | Prometheus        | Kubernetes-native metrics platform         |
| Dashboards           | Grafana           | Metrics visualization                      |
| Resource Scaling     | HPA               | Kubernetes-native autoscaling              |
| Metric/Event Scaling | KEDA              | External metric-driven scaling             |
| Node Scaling         | Karpenter         | Dynamic compute provisioning               |
| Persistent Storage   | EBS CSI + gp3     | AWS-native Kubernetes storage              |

---

# 27. Production Considerations

This project demonstrates production-oriented architecture but is intentionally implemented as a portfolio/lab environment rather than claiming to be a complete enterprise production environment.

A real production implementation would typically extend the design with:

```
multiple AWS accounts
stronger environment isolation
production-grade Terraform remote state
CI validation for Terraform and Kubernetes manifests
pull-request approval workflows
policy testing in CI
image vulnerability scanning
container image signing
admission verification
centralized logging
SLOs and SLIs
production alert routing
PodDisruptionBudgets
topology spread constraints
multi-AZ resilience testing
backup automation
Velero or application-aware backup
restore testing
secret rotation
AWS KMS key lifecycle controls
cost monitoring
FinOps policies
stronger Argo CD RBAC
SSO integration
progressive delivery
production change-management controls
```
These are intentionally identified as production evolution paths rather than represented as implemented features where they were not validated.

---

# 28. Disaster Recovery Model

The declarative architecture provides several important recovery characteristics.

AWS infrastructure can be recreated through:
```
Terraform
```
Kubernetes platform desired state can be reconstructed from:
```
Git
```
Argo CD can reconcile that desired state back into the cluster.

Conceptually:
```
Infrastructure Failure
        |
        v
Terraform Recreates AWS
        |
        v
EKS Available
        |
        v
Bootstrap Argo CD
        |
        v
Git Desired State
        |
        v
Platform Reconciliation
```
Persistent application data requires a separate backup and recovery strategy.

Production implementation would therefore include tested backup and restore procedures for persistent volumes and application data.

---

# 29. Evidence and Screenshots

The final portfolio includes evidence captured from the running environment.

Screenshots are added after recreating the EKS platform to avoid keeping AWS resources running solely for documentation purposes.

## Planned Evidence
## AWS / EKS
```
 EKS cluster overview
 EKS worker nodes
 AWS VPC/subnet architecture
```
## Argo CD
```
 Argo CD Applications overview
 App-of-Apps hierarchy
 Synced/Healthy platform applications
 ```
## Gateway API
```
 GatewayClass
 Gateway
 HTTPRoute
 application accessed through public endpoint
```
## Security
```
 Kyverno ClusterPolicies
 privileged Pod rejection
 resource requests/limits rejection
 NetworkPolicies
 External Secrets synchronization
```
## Observability
```
Prometheus
 Grafana dashboard
 Kubernetes node metrics
 application metrics
```
## Autoscaling
```
 HPA scaling
 KEDA ScaledObject
 Prometheus metric trigger
 Karpenter NodeClaim
 dynamically provisioned EC2 node
 Karpenter consolidation
```
## Storage
```
 gp3 StorageClass
 PVC/PV validation
```
Suggested repository organization:
```
docs/
└── evidence/

diagrams/
├── platform-architecture.png
├── gitops-flow.png
└── autoscaling-flow.png

screenshots/
├── aws/
├── argocd/
├── gateway/
├── security/
├── observability/
├── autoscaling/
└── storage/
```
---

# 30. What This Project Demonstrates

This project demonstrates practical experience across several Senior DevOps / Platform Engineering domains.

## AWS
```
Amazon EKS
VPC networking
IAM
OIDC
IRSA
EC2
Route 53
EBS
Secrets integration
```
## Kubernetes
```
managed Kubernetes
Gateway API
HTTPRoute
Services
Deployments
resource management
NetworkPolicy
admission policies
persistent storage
autoscaling
```
## Infrastructure as Code
```
Terraform
modular infrastructure
repeatable provisioning
infrastructure lifecycle management
```
## GitOps
```
Argo CD
App-of-Apps
automated reconciliation
pruning
self-healing
declarative configuration
```
## Security
```
least privilege
workload identity
external secrets
policy-as-code
admission control
network isolation
TLS automation
negative security testing
```
## Observability
```
Prometheus
Grafana
Alertmanager
Kubernetes metrics
```
## Autoscaling
```
HPA
KEDA
Karpenter
workload scaling
metric-driven scaling
infrastructure scaling
node consolidation
```
## Platform Engineering

Most importantly, the project demonstrates how these technologies work together as a platform rather than as isolated tools.

---

# 31. Key Architecture Takeaway

The central architecture can be summarized as:

```
                         Git
                          |
                          v
                       Argo CD
                          |
                          v
                Kubernetes Desired State
                          |
        +-----------------+------------------+
        |                 |                  |
        v                 v                  v
     Security          Traffic          Observability
        |                 |                  |
        v                 v                  v
     Kyverno          Gateway API         Prometheus
 NetworkPolicy          Traefik            Grafana
External Secrets     cert-manager        Alertmanager
        |                 |
        +--------+--------+
                 |
                 v
             Workloads
                 |
         +-------+-------+
         |               |
         v               v
        HPA             KEDA
         |               |
         +-------+-------+
                 |
                 v
          Kubernetes Scheduler
                 |
                 v
             Karpenter
                 |
                 v
            AWS EC2 Nodes
                 |
                 v
             Amazon EKS
                 |
                 v
       Terraform-managed AWS
```
The project therefore demonstrates an integrated platform lifecycle:

```
Provision
   |
   v
Bootstrap
   |
   v
Reconcile
   |
   v
Secure
   |
   v
Expose
   |
   v
Observe
   |
   v
Scale
   |
   v
Validate
```
---

# 32. Documentation

For a deeper technical discussion of the architecture, design decisions, component interactions, security model, autoscaling model and production considerations, see:
```
docs/architecture.md
```
The README intentionally provides the recruiter and hiring-manager overview while the architecture document provides the engineering deep dive.

---

# 33. Author

## Kapil Kumaria

### DevOps / Cloud / Platform Engineering

Primary areas demonstrated by this project:
```
AWS · Kubernetes · EKS · Terraform · Argo CD · GitOps · Gateway API · Traefik · cert-manager · ExternalDNS · External Secrets · Kyverno · Prometheus · Grafana · KEDA · Karpenter
```
## Repository

This repository is part of a portfolio demonstrating production-oriented DevOps, Cloud and Platform Engineering practices.
