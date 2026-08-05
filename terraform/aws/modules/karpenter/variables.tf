# ============================================================
# General configuration
# ============================================================

variable "cluster_name" {
  description = "Name of the existing Amazon EKS cluster."
  type        = string

  validation {
    condition     = length(trimspace(var.cluster_name)) > 0
    error_message = "cluster_name cannot be empty."
  }
}

variable "cluster_arn" {
  description = "ARN of the existing Amazon EKS cluster."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:eks:[^:]+:[0-9]{12}:cluster/.+$", var.cluster_arn))
    error_message = "cluster_arn must be a valid Amazon EKS cluster ARN."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS IAM OIDC provider used for IRSA."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:oidc-provider/.+$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without the https:// prefix."
  type        = string

  validation {
    condition     = length(trimspace(var.oidc_provider_url)) > 0
    error_message = "oidc_provider_url cannot be empty."
  }
}

variable "cluster_security_group_id" {
  description = "EKS-created cluster security group selected by Karpenter."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.cluster_security_group_id))
    error_message = "cluster_security_group_id must be a valid security group ID."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs that Karpenter may use for worker nodes."
  type        = list(string)

  validation {
    condition = (
      length(var.private_subnet_ids) >= 2 &&
      alltrue([
        for subnet_id in var.private_subnet_ids :
        can(regex("^subnet-[0-9a-f]+$", subnet_id))
      ])
    )

    error_message = "private_subnet_ids must contain at least two valid subnet IDs."
  }
}


# ============================================================
# Karpenter controller configuration
# ============================================================

variable "karpenter_namespace" {
  description = "Kubernetes namespace where Karpenter is installed."
  type        = string
  default     = "karpenter"
}

variable "karpenter_service_account_name" {
  description = "Kubernetes service account used by the Karpenter controller."
  type        = string
  default     = "karpenter"
}


# ============================================================
# Interruption handling
# ============================================================

variable "enable_interruption_handling" {
  description = "Whether to create the SQS queue and EventBridge interruption rules."
  type        = bool
  default     = true
}

variable "interruption_queue_name" {
  description = "Optional custom SQS interruption queue name. Defaults to the cluster name."
  type        = string
  default     = null
}


# ============================================================
# Tagging
# ============================================================

variable "tags" {
  description = "Additional tags applied to Karpenter AWS resources."
  type        = map(string)
  default     = {}
}
