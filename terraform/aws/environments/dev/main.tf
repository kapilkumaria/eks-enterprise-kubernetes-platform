module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
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

  node_labels = {
    node-pool = "general"
    lifecycle = "on-demand"
  }

  enable_vpc_cni_addon    = true
  enable_coredns_addon    = true
  enable_kube_proxy_addon = true
  enable_ebs_csi_addon    = true

  tags = {
    Owner      = "Kapil"
    CostCenter = "Portfolio"
  }
}
