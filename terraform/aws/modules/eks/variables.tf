# ============================================================
# General project configuration
# ============================================================

variable "project_name" {
  description = "Project name used for naming and tagging EKS resources."
  type        = string

  validation {
    condition     = length(trimspace(var.project_name)) > 0
    error_message = "project_name cannot be empty."
  }
}

variable "environment" {
  description = "Deployment environment such as dev, staging, or prod."
  type        = string

  validation {
    condition = contains(
      ["dev", "staging", "prod"],
      lower(var.environment)
    )

    error_message = "environment must be one of: dev, staging, or prod."
  }
}

variable "cluster_version" {
  description = "Kubernetes minor version used by the Amazon EKS control plane and managed node group."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.cluster_version))
    error_message = "cluster_version must use Kubernetes minor-version format, for example 1.34."
  }
}

variable "tags" {
  description = "Additional tags applied to EKS resources in addition to the module's standard tags."
  type        = map(string)
  default     = {}
}


# ============================================================
# VPC and subnet configuration
# ============================================================

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster is deployed."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid AWS VPC ID beginning with vpc-."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by the EKS control plane network interfaces and managed worker nodes."
  type        = list(string)

  validation {
    condition = (
      length(var.private_subnet_ids) >= 2 &&
      alltrue([
        for subnet_id in var.private_subnet_ids :
        can(regex("^subnet-[0-9a-f]+$", subnet_id))
      ])
    )

    error_message = "private_subnet_ids must contain at least two valid AWS subnet IDs."
  }
}


# ============================================================
# EKS API endpoint configuration
# ============================================================

variable "cluster_endpoint_public_access" {
  description = "Whether the public Amazon EKS Kubernetes API endpoint is enabled."
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Whether the private Amazon EKS Kubernetes API endpoint is enabled inside the VPC."
  type        = bool
  default     = true
}

variable "cluster_public_access_cidrs" {
  description = "CIDR blocks allowed to access the public Amazon EKS Kubernetes API endpoint."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.cluster_public_access_cidrs :
      can(cidrnetmask(cidr))
    ])

    error_message = "Every value in cluster_public_access_cidrs must be a valid IPv4 CIDR block."
  }

  validation {
    condition = !contains(
      var.cluster_public_access_cidrs,
      "0.0.0.0/0"
    )

    error_message = "Do not expose the EKS API endpoint to 0.0.0.0/0. Use a restricted CIDR such as the control node public IP with /32."
  }
}


# ============================================================
# EKS access and authentication configuration
# ============================================================

variable "authentication_mode" {
  description = "EKS cluster authentication mode. API_AND_CONFIG_MAP supports EKS access entries and the legacy aws-auth ConfigMap."
  type        = string
  default     = "API_AND_CONFIG_MAP"

  validation {
    condition = contains(
      ["CONFIG_MAP", "API", "API_AND_CONFIG_MAP"],
      var.authentication_mode
    )

    error_message = "authentication_mode must be CONFIG_MAP, API, or API_AND_CONFIG_MAP."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Whether the IAM principal creating the cluster receives initial Kubernetes cluster administrator permissions."
  type        = bool
  default     = true
}


# ============================================================
# Control-plane logging
# ============================================================

variable "control_plane_log_types" {
  description = "Amazon EKS control-plane log types exported to Amazon CloudWatch Logs."
  type        = list(string)

  default = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  validation {
    condition = alltrue([
      for log_type in var.control_plane_log_types :
      contains(
        [
          "api",
          "audit",
          "authenticator",
          "controllerManager",
          "scheduler"
        ],
        log_type
      )
    ])

    error_message = "control_plane_log_types may contain only api, audit, authenticator, controllerManager, and scheduler."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days Amazon CloudWatch retains EKS control-plane logs."
  type        = number
  default     = 30

  validation {
    condition = contains(
      [
        1,
        3,
        5,
        7,
        14,
        30,
        60,
        90,
        120,
        150,
        180,
        365,
        400,
        545,
        731,
        1096,
        1827,
        2192,
        2557,
        2922,
        3288,
        3653
      ],
      var.cloudwatch_log_retention_days
    )

    error_message = "cloudwatch_log_retention_days must be a supported CloudWatch Logs retention value."
  }
}


# ============================================================
# Managed node group configuration
# ============================================================

variable "node_group_name" {
  description = "Logical name appended to the EKS managed node group."
  type        = string
  default     = "general"

  validation {
    condition     = length(trimspace(var.node_group_name)) > 0
    error_message = "node_group_name cannot be empty."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types used by the EKS managed node group."
  type        = list(string)

  validation {
    condition = (
      length(var.node_instance_types) > 0 &&
      alltrue([
        for instance_type in var.node_instance_types :
        length(trimspace(instance_type)) > 0
      ])
    )

    error_message = "node_instance_types must contain at least one EC2 instance type."
  }
}

variable "node_capacity_type" {
  description = "Capacity type used by the managed node group."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition = contains(
      ["ON_DEMAND", "SPOT"],
      var.node_capacity_type
    )

    error_message = "node_capacity_type must be either ON_DEMAND or SPOT."
  }
}

variable "node_disk_size" {
  description = "Root EBS volume size in GiB for each managed worker node."
  type        = number
  default     = 50

  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 1024
    error_message = "node_disk_size must be between 20 and 1024 GiB."
  }
}

variable "desired_size" {
  description = "Desired number of worker nodes in the EKS managed node group."
  type        = number

  validation {
    condition     = var.desired_size >= 0
    error_message = "desired_size cannot be negative."
  }
}

variable "min_size" {
  description = "Minimum number of worker nodes in the EKS managed node group."
  type        = number

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size cannot be negative."
  }
}

variable "max_size" {
  description = "Maximum number of worker nodes in the EKS managed node group."
  type        = number

  validation {
    condition     = var.max_size >= 1
    error_message = "max_size must be at least 1."
  }
}

variable "max_unavailable" {
  description = "Maximum number of managed worker nodes that may be unavailable during an update."
  type        = number
  default     = 1

  validation {
    condition     = var.max_unavailable >= 1
    error_message = "max_unavailable must be at least 1."
  }
}

variable "node_labels" {
  description = "Additional Kubernetes labels applied to managed worker nodes."
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Optional Kubernetes taints applied to the EKS managed node group."
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))

  default = []

  validation {
    condition = alltrue([
      for taint in var.node_taints :
      contains(
        ["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"],
        taint.effect
      )
    ])

    error_message = "Each node taint effect must be NO_SCHEDULE, NO_EXECUTE, or PREFER_NO_SCHEDULE."
  }
}


# ============================================================
# EKS managed add-ons
# ============================================================

variable "enable_vpc_cni_addon" {
  description = "Whether to install and manage the Amazon VPC CNI EKS add-on."
  type        = bool
  default     = true
}

variable "enable_coredns_addon" {
  description = "Whether to install and manage the CoreDNS EKS add-on."
  type        = bool
  default     = true
}

variable "enable_kube_proxy_addon" {
  description = "Whether to install and manage the kube-proxy EKS add-on."
  type        = bool
  default     = true
}

variable "enable_ebs_csi_addon" {
  description = "Whether to install and manage the Amazon EBS CSI Driver EKS add-on."
  type        = bool
  default     = true
}

variable "vpc_cni_addon_version" {
  description = "Optional version of the Amazon VPC CNI EKS add-on. Null allows EKS to select a compatible version."
  type        = string
  default     = null
}

variable "coredns_addon_version" {
  description = "Optional version of the CoreDNS EKS add-on. Null allows EKS to select a compatible version."
  type        = string
  default     = null
}

variable "kube_proxy_addon_version" {
  description = "Optional version of the kube-proxy EKS add-on. Null allows EKS to select a compatible version."
  type        = string
  default     = null
}

variable "ebs_csi_addon_version" {
  description = "Optional version of the Amazon EBS CSI Driver EKS add-on. Null allows EKS to select a compatible version."
  type        = string
  default     = null
}

variable "addon_resolve_conflicts_on_create" {
  description = "Conflict resolution behavior when creating EKS managed add-ons."
  type        = string
  default     = "OVERWRITE"

  validation {
    condition = contains(
      ["NONE", "OVERWRITE"],
      var.addon_resolve_conflicts_on_create
    )

    error_message = "addon_resolve_conflicts_on_create must be NONE or OVERWRITE."
  }
}

variable "addon_resolve_conflicts_on_update" {
  description = "Conflict resolution behavior when updating EKS managed add-ons."
  type        = string
  default     = "PRESERVE"

  validation {
    condition = contains(
      ["NONE", "OVERWRITE", "PRESERVE"],
      var.addon_resolve_conflicts_on_update
    )

    error_message = "addon_resolve_conflicts_on_update must be NONE, OVERWRITE, or PRESERVE."
  }
}
