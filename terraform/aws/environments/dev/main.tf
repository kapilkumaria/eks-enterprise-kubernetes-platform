module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
}

# EKS module will be enabled after we create:
# terraform/aws/modules/eks/variables.tf
# terraform/aws/modules/eks/main.tf
# terraform/aws/modules/eks/outputs.tf

# module "eks" {
#   source = "../../modules/eks"
#
#   project_name        = var.project_name
#   environment         = var.environment
#   cluster_version     = var.cluster_version
#   vpc_id              = module.networking.vpc_id
#   private_subnet_ids  = module.networking.private_subnet_ids
#   node_instance_types = var.node_instance_types
#   desired_size        = var.desired_size
#   min_size            = var.min_size
#   max_size            = var.max_size
# }
