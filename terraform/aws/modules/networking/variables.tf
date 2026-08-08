variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

# ============================================================
# Karpenter subnet discovery
# ============================================================

variable "karpenter_discovery_tag" {
  description = "Value of the karpenter.sh/discovery tag applied to private subnets. Set to null to omit the tag."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.karpenter_discovery_tag == null ||
      length(trimspace(var.karpenter_discovery_tag)) > 0
    )

    error_message = "karpenter_discovery_tag must be null or a non-empty string."
  }
}
