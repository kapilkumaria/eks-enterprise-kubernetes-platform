module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr

  karpenter_discovery_tag = "${var.project_name}-${var.environment}"
}

module "eks" {
  source = "../../modules/eks"

  project_name    = var.project_name
  environment     = var.environment
  cluster_version = var.cluster_version

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  cluster_public_access_cidrs     = var.cluster_public_access_cidrs

  authentication_mode                         = "API_AND_CONFIG_MAP"
  bootstrap_cluster_creator_admin_permissions = true

  control_plane_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  cloudwatch_log_retention_days = var.cloudwatch_log_retention_days

  node_group_name     = "general"
  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_disk_size      = var.node_disk_size

  desired_size = var.desired_size
  min_size     = var.min_size
  max_size     = var.max_size

  max_unavailable = 1

  # ExternalDNS IRSA
  enable_external_dns_irsa          = var.enable_external_dns_irsa
  external_dns_namespace            = var.external_dns_namespace
  external_dns_service_account_name = var.external_dns_service_account_name
  external_dns_hosted_zone_ids      = var.external_dns_hosted_zone_ids

  # External Secrets Operator IRSA
  enable_external_secrets_irsa          = var.enable_external_secrets_irsa
  external_secrets_namespace            = var.external_secrets_namespace
  external_secrets_service_account_name = var.external_secrets_service_account_name
  external_secrets_secret_name_prefixes = var.external_secrets_secret_name_prefixes

  node_labels = {
    node-pool = "general"
    lifecycle = "on-demand"
  }

  enable_vpc_cni_addon    = true
  enable_coredns_addon    = true
  enable_kube_proxy_addon = true
  enable_ebs_csi_addon    = true

  # Amazon VPC CNI NetworkPolicy
  enable_vpc_cni_network_policy = (
    var.enable_vpc_cni_network_policy
  )

  vpc_cni_network_policy_enforcing_mode = (
    var.vpc_cni_network_policy_enforcing_mode
  )

  tags = {
    Owner      = "Kapil"
    CostCenter = "Portfolio"
  }
}


# ============================================================
# Karpenter node autoscaling
# ============================================================

module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name = module.eks.cluster_name
  cluster_arn  = module.eks.cluster_arn

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  cluster_security_group_id = (
    module.eks.cluster_security_group_id
  )

  private_subnet_ids = module.networking.private_subnet_ids

  karpenter_namespace            = "karpenter"
  karpenter_service_account_name = "karpenter"

  enable_interruption_handling = true
  interruption_queue_name      = module.eks.cluster_name

  tags = local.common_tags
}
