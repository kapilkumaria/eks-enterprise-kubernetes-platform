output "controller_role_arn" {
  description = "IAM role ARN used by the Karpenter controller service account."
  value       = aws_iam_role.controller.arn
}

output "controller_role_name" {
  description = "IAM role name used by the Karpenter controller service account."
  value       = aws_iam_role.controller.name
}

output "node_role_arn" {
  description = "IAM role ARN used by EC2 nodes provisioned by Karpenter."
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "IAM role name used by EC2 nodes provisioned by Karpenter."
  value       = aws_iam_role.node.name
}

output "interruption_queue_name" {
  description = "SQS interruption queue name used by Karpenter."
  value = (
    var.enable_interruption_handling
    ? aws_sqs_queue.interruption[0].name
    : null
  )
}

output "interruption_queue_arn" {
  description = "SQS interruption queue ARN used by Karpenter."
  value = (
    var.enable_interruption_handling
    ? aws_sqs_queue.interruption[0].arn
    : null
  )
}

output "discovery_tag" {
  description = "Karpenter subnet and security-group discovery tag."
  value = {
    key   = "karpenter.sh/discovery"
    value = var.cluster_name
  }
}

output "node_access_entry_arn" {
  description = "ARN of the EKS access entry for Karpenter worker nodes."
  value       = aws_eks_access_entry.karpenter_nodes.access_entry_arn
}
