variable "aws_region" {
  description = "AWS region where the EKS platform is deployed."
  type        = string
}

variable "project_name" {
  description = "Project name used for naming and tagging resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block assigned to the platform VPC."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes minor version used by Amazon EKS."
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types used by the EKS managed node group."
  type        = list(string)
}

variable "node_capacity_type" {
  description = "Capacity type used by the managed node group."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  description = "Root volume size in GiB for each worker node."
  type        = number
  default     = 50
}

variable "desired_size" {
  description = "Desired number of managed worker nodes."
  type        = number
}

variable "min_size" {
  description = "Minimum number of managed worker nodes."
  type        = number
}

variable "max_size" {
  description = "Maximum number of managed worker nodes."
  type        = number
}

variable "cluster_public_access_cidrs" {
  description = "CIDR blocks permitted to reach the public EKS API endpoint."
  type        = list(string)
}

variable "cloudwatch_log_retention_days" {
  description = "Retention period for EKS control-plane CloudWatch logs."
  type        = number
  default     = 30
}


# ============================================================
# ExternalDNS IRSA
# ============================================================

variable "enable_external_dns_irsa" {
  description = "Whether to create the ExternalDNS IAM policy and IRSA role."
  type        = bool
  default     = false
}

variable "external_dns_namespace" {
  description = "Kubernetes namespace containing the ExternalDNS service account."
  type        = string
  default     = "external-dns"
}

variable "external_dns_service_account_name" {
  description = "Name of the Kubernetes service account used by ExternalDNS."
  type        = string
  default     = "external-dns"
}

variable "external_dns_hosted_zone_ids" {
  description = "Amazon Route 53 hosted-zone IDs that ExternalDNS may manage."
  type        = list(string)
  default     = []
}


# ============================================================
# External Secrets Operator IRSA
# ============================================================

variable "enable_external_secrets_irsa" {
  description = "Whether to create the External Secrets Operator IAM policy and IRSA role."
  type        = bool
  default     = false
}

variable "external_secrets_namespace" {
  description = "Kubernetes namespace containing the External Secrets Operator service account."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account_name" {
  description = "Name of the Kubernetes service account used by External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_secret_name_prefixes" {
  description = "AWS Secrets Manager name prefixes that External Secrets Operator may read."
  type        = list(string)
  default     = []
}


# ============================================================
# Amazon VPC CNI NetworkPolicy
# ============================================================

variable "enable_vpc_cni_network_policy" {
  description = "Whether to enable NetworkPolicy enforcement in the Amazon VPC CNI managed add-on."
  type        = bool
  default     = false
}

variable "vpc_cni_network_policy_enforcing_mode" {
  description = "Amazon VPC CNI NetworkPolicy startup enforcement mode."
  type        = string
  default     = "standard"

  validation {
    condition = contains(
      ["standard", "strict"],
      var.vpc_cni_network_policy_enforcing_mode
    )

    error_message = "vpc_cni_network_policy_enforcing_mode must be standard or strict."
  }
}
