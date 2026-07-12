# ============================================================
# Networking outputs
# ============================================================

output "vpc_id" {
  description = "VPC ID created for the EKS platform."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs created for internet-facing load balancers."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by EKS and worker nodes."
  value       = module.networking.private_subnet_ids
}


# ============================================================
# EKS cluster outputs
# ============================================================

output "cluster_name" {
  description = "Amazon EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "Amazon EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on Amazon EKS."
  value       = module.eks.cluster_version
}

output "cluster_status" {
  description = "Current status of the Amazon EKS cluster."
  value       = module.eks.cluster_status
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group ID."
  value       = module.eks.cluster_security_group_id
}


# ============================================================
# Managed node-group outputs
# ============================================================

output "node_group_name" {
  description = "Name of the general-purpose managed node group."
  value       = module.eks.node_group_name
}

output "node_group_status" {
  description = "Current status of the managed node group."
  value       = module.eks.node_group_status
}

output "node_role_arn" {
  description = "IAM role ARN used by managed worker nodes."
  value       = module.eks.node_role_arn
}


# ============================================================
# OIDC and IRSA outputs
# ============================================================

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN used by IRSA."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "IAM OIDC provider URL."
  value       = module.eks.oidc_provider_url
}

output "vpc_cni_irsa_role_arn" {
  description = "IAM role ARN used by the Amazon VPC CNI add-on."
  value       = module.eks.vpc_cni_irsa_role_arn
}

output "ebs_csi_irsa_role_arn" {
  description = "IAM role ARN used by the Amazon EBS CSI Driver."
  value       = module.eks.ebs_csi_irsa_role_arn
}


# ============================================================
# Operational convenience output
# ============================================================

output "kubectl_update_command" {
  description = "Command used to update the local kubeconfig."
  value       = module.eks.kubectl_update_command
}
