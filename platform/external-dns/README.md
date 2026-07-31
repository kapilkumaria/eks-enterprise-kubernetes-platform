# ExternalDNS

ExternalDNS synchronizes Kubernetes Gateway API hostnames with Amazon Route 53.

## Problem statement

AWS load-balancer DNS names change when an EKS environment is recreated. Applications require stable public DNS names without manual Route 53 updates.

## Architecture

```text
HTTPRoute hostname
  ↓
ExternalDNS controller
  ↓
Kubernetes ServiceAccount
  ↓
EKS OIDC / IRSA
  ↓
Dedicated ExternalDNS IAM role
  ↓
Amazon Route 53
```
