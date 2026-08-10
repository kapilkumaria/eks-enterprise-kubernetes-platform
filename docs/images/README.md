# Runtime Evidence and Platform Validation

This directory contains runtime evidence captured from the deployed Enterprise Kubernetes Platform on Amazon EKS.

The screenshots are intended to demonstrate that the platform components described in the repository were not only defined as Infrastructure as Code and GitOps manifests, but were also deployed and validated in a running AWS environment.

> The platform infrastructure is intentionally destroyed when not being actively tested in order to avoid unnecessary AWS costs. Runtime evidence is captured during clean deployment and validation cycles.

---

## Evidence Categories

```text
docs/images/
├── argocd/
├── autoscaling/
├── aws/
├── gateway/
├── observability/
├── security/
└── storage/
```
Each directory represents a major platform capability.

---

# AWS and Amazon EKS

Location:
```
docs/images/aws/
```
Evidence in this directory demonstrates the AWS infrastructure supporting the Kubernetes platform.

Examples include:
```
Amazon EKS cluster
Kubernetes worker nodes
EKS managed node group
AWS networking
EKS cluster status
dynamically provisioned Karpenter EC2 capacity
```
The AWS infrastructure itself is provisioned through Terraform under:
```
terraform/aws/
```
---

# GitOps — Argo CD

Location:
```
docs/images/argocd/
```
Evidence in this directory demonstrates GitOps reconciliation and platform lifecycle management.

Examples include:
```
Argo CD application dashboard
App-of-Apps deployment
platform application health
synchronization status
individual platform components
Git-to-cluster reconciliation
```
The expected platform applications include components such as:
```
cert-manager
external-dns
external-secrets
gateway-api-crds
traefik-gateway
kyverno
kyverno-policies
network-policies
observability
metrics-server
keda
keda-scaledobjects
karpenter
karpenter-resources
```
---

# Gateway API and Traffic Management
Location:
```
docs/images/gateway/
```
Evidence in this directory demonstrates external application routing through Kubernetes Gateway API.

The request path is conceptually:
```
Internet
   |
   v
Route 53
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
Kubernetes Service
   |
   v
Application Pod
```
Evidence may include:
```
GatewayClass
Gateway
HTTPRoute
AWS load balancer address
DNS resolution
HTTPS application access
TLS certificate status
```
---

# Security

Location:
```
docs/images/security/
```
Evidence in this directory demonstrates security controls implemented across AWS and Kubernetes.

Examples include:
```
Kyverno ClusterPolicies
privileged-container rejection
resource requests/limits enforcement
Kubernetes NetworkPolicies
External Secrets synchronization
cert-manager certificate status
IRSA integration
```
Negative testing is intentionally included.

For example, a privileged workload should be rejected by the Kubernetes admission layer:
```
kubectl apply
      |
      v
Kubernetes API
      |
      v
Kyverno Admission Webhook
      |
      +---- policy passes ----> workload admitted
      |
      +---- policy fails -----> request rejected
```
This demonstrates enforcement rather than configuration alone.

See:
```
docs/security.md
```
---

# Observability

Location:
```
docs/images/observability/
```
Evidence in this directory demonstrates the monitoring and observability capabilities of the platform.

Examples include:
```
Prometheus
Grafana
Alertmanager
kube-state-metrics
node-exporter
Kubernetes resource metrics
cluster dashboards
node utilization
workload utilization
```
The monitoring architecture is conceptually:
```
Kubernetes / Applications
          |
          v
       Metrics
          |
          v
      Prometheus
       /      \
      v        v
 Grafana    Alertmanager
```
---

# Autoscaling

Location:
```
docs/images/autoscaling/
```
Evidence in this directory demonstrates the three autoscaling layers implemented by the platform.

---

# Horizontal Pod Autoscaler

HPA provides resource-based workload scaling.
```
CPU / Memory Demand
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

# KEDA

KEDA provides external or event-driven workload autoscaling.

This project validates Prometheus-driven scaling.
```
Prometheus Metric
       |
       v
      KEDA
       |
       v
 ScaledObject
       |
       v
      HPA
       |
       v
Deployment Replicas
```
---

# Karpenter

Karpenter provides infrastructure-level autoscaling.
```
Pending Pods
     |
     v
Karpenter
     |
     v
NodeClaim
     |
     v
EC2 Instance
     |
     v
EKS Node
     |
     v
Pods Scheduled
```
Runtime evidence should demonstrate both:
```
Scale Out
```
and:
```
Consolidation / Scale In
```
This distinction is important because HPA/KEDA and Karpenter solve different scaling problems.

---

# Persistent Storage

Location:
```
docs/images/storage/
```
Evidence in this directory demonstrates Kubernetes persistent storage integration with Amazon EBS.

The storage flow is:
```
Application
     |
     v
PersistentVolumeClaim
     |
     v
StorageClass
     |
     v
EBS CSI Driver
     |
     v
Amazon EBS
```
Evidence may include:
```
gp3 StorageClass
PersistentVolumeClaim
PersistentVolume
dynamically provisioned EBS storage
```
---
# Validation Philosophy

The project follows a simple validation principle:
```
Configuration
     |
     v
Deployment
     |
     v
Runtime Validation
     |
     v
Evidence
```
A manifest existing in Git does not by itself demonstrate that a platform capability works.

For important platform components, validation therefore includes one or more of the following:
```
Kubernetes resource status
controller health
GitOps synchronization
functional testing
negative security testing
workload scaling
infrastructure scaling
external connectivity
AWS resource validation
```
---

# Reproducibility

The platform is designed to be recreated rather than permanently maintained as a continuously running demonstration environment.

The general recovery and reproduction workflow is:
```
Terraform Apply
      |
      v
AWS Infrastructure
      |
      v
Amazon EKS
      |
      v
Argo CD Bootstrap
      |
      v
App-of-Apps
      |
      v
Platform Reconciliation
      |
      v
Runtime Validation
```
After validation and evidence collection, infrastructure can be destroyed:
```
terraform destroy
```
This approach demonstrates both infrastructure reproducibility and cloud cost awareness.

For the complete deployment workflow, see:
```
docs/deployment-guide.md
```
For the platform architecture, see:
```
docs/architecture.md
```
For security design and validation, see:
```
docs/security.md
```
For engineering failures and troubleshooting scenarios encountered during implementation, see:
```
docs/troubleshooting.md
```
---

# Evidence Disclaimer

Screenshots in this directory represent point-in-time runtime validation from deployed test environments.

Resource identifiers, public endpoints, AWS account information, credentials, tokens, secrets, and other sensitive information should be removed or redacted before evidence is committed to the public repository.