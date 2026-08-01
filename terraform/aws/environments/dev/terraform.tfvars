aws_region   = "us-east-1"
project_name = "eks-enterprise-platform"
environment  = "dev"

vpc_cidr = "10.30.0.0/16"

cluster_version = "1.34"

node_instance_types = ["t3.medium"]
node_capacity_type  = "ON_DEMAND"
node_disk_size      = 50

desired_size = 3
min_size     = 2
max_size     = 4

cluster_public_access_cidrs = [
  "205.206.76.190/32"
]

cloudwatch_log_retention_days = 30

# ============================================================
# ExternalDNS IRSA
# ============================================================

enable_external_dns_irsa          = true
external_dns_namespace            = "external-dns"
external_dns_service_account_name = "external-dns"

external_dns_hosted_zone_ids = [
  "Z0058793HC1B8WCMOEQ4"
]


# ============================================================
# External Secrets Operator IRSA
# ============================================================

enable_external_secrets_irsa          = true
external_secrets_namespace            = "external-secrets"
external_secrets_service_account_name = "external-secrets"

external_secrets_secret_name_prefixes = [
  "eks-enterprise-platform/dev/"
]


# ============================================================
# Amazon VPC CNI NetworkPolicy
# ============================================================

enable_vpc_cni_network_policy         = true
vpc_cni_network_policy_enforcing_mode = "standard"
