# ============================================================
# Amazon EKS Cluster Outputs
# ============================================================

output "cluster_name" {
  description = "Name of the Amazon EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "Amazon Resource Name (ARN) of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the EKS control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_platform_version" {
  description = "Amazon EKS platform version."
  value       = aws_eks_cluster.this.platform_version
}

output "cluster_status" {
  description = "Current status of the Amazon EKS cluster."
  value       = aws_eks_cluster.this.status
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded Kubernetes cluster certificate authority."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_identity_oidc_issuer" {
  description = "OIDC issuer URL for the Amazon EKS cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "Cluster security group automatically created by Amazon EKS."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}


# ============================================================
# Managed Node Group Outputs
# ============================================================

output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.general.node_group_name
}

output "node_group_arn" {
  description = "ARN of the managed node group."
  value       = aws_eks_node_group.general.arn
}

output "node_group_status" {
  description = "Current status of the managed node group."
  value       = aws_eks_node_group.general.status
}

output "node_role_arn" {
  description = "IAM Role ARN used by the managed worker nodes."
  value       = aws_iam_role.eks_node.arn
}

output "node_role_name" {
  description = "IAM Role name used by the managed worker nodes."
  value       = aws_iam_role.eks_node.name
}


# ============================================================
# IAM Outputs
# ============================================================

output "cluster_role_arn" {
  description = "IAM Role ARN used by the EKS control plane."
  value       = aws_iam_role.eks_cluster.arn
}

output "cluster_role_name" {
  description = "IAM Role name used by the EKS control plane."
  value       = aws_iam_role.eks_cluster.name
}


# ============================================================
# OIDC / IRSA Outputs
# ============================================================

output "oidc_provider_arn" {
  description = "IAM OpenID Connect Provider ARN used for IRSA."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "IAM OpenID Connect Provider URL."
  value       = aws_iam_openid_connect_provider.eks.url
}


# ============================================================
# IRSA Role Outputs
# ============================================================

output "vpc_cni_irsa_role_arn" {
  description = "IAM Role ARN used by the Amazon VPC CNI add-on."
  value       = aws_iam_role.vpc_cni.arn
}

output "vpc_cni_irsa_role_name" {
  description = "IAM Role name used by the Amazon VPC CNI add-on."
  value       = aws_iam_role.vpc_cni.name
}

output "ebs_csi_irsa_role_arn" {
  description = "IAM Role ARN used by the Amazon EBS CSI Driver."
  value       = aws_iam_role.ebs_csi.arn
}

output "ebs_csi_irsa_role_name" {
  description = "IAM Role name used by the Amazon EBS CSI Driver."
  value       = aws_iam_role.ebs_csi.name
}


# ============================================================
# Networking Outputs
# ============================================================

output "vpc_id" {
  description = "VPC ID hosting the EKS cluster."
  value       = var.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs hosting the EKS cluster."
  value       = var.private_subnet_ids
}


# ============================================================
# Convenience Outputs
# ============================================================

output "kubectl_cluster_name" {
  description = "Cluster name used when updating kubeconfig."
  value       = aws_eks_cluster.this.name
}

output "kubectl_update_command" {
  description = "AWS CLI command used to configure kubectl."

  value = format(
    "aws eks update-kubeconfig --region %s --name %s",
    data.aws_region.current.name,
    aws_eks_cluster.this.name
  )
}


# ============================================================
# ExternalDNS IRSA Outputs
# ============================================================

output "external_dns_irsa_role_arn" {
  description = "IAM Role ARN used by the ExternalDNS Kubernetes service account."

  value = (
    var.enable_external_dns_irsa
    ? aws_iam_role.external_dns[0].arn
    : null
  )
}

output "external_dns_irsa_role_name" {
  description = "IAM Role name used by the ExternalDNS Kubernetes service account."

  value = (
    var.enable_external_dns_irsa
    ? aws_iam_role.external_dns[0].name
    : null
  )
}

output "external_dns_policy_arn" {
  description = "Customer-managed IAM policy ARN used by ExternalDNS."

  value = (
    var.enable_external_dns_irsa
    ? aws_iam_policy.external_dns[0].arn
    : null
  )
}
