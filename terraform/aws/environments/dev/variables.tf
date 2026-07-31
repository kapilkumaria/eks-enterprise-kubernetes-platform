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
