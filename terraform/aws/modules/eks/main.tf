# ============================================================
# AWS Data Sources
# ============================================================

data "aws_partition" "current" {}

data "aws_region" "current" {}


# ============================================================
# Local Values
# ============================================================

locals {
  cluster_name = "${var.project_name}-${var.environment}"

  oidc_provider_url = replace(
    aws_eks_cluster.this.identity[0].oidc[0].issuer,
    "https://",
    ""
  )

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "Amazon-EKS"
    },
    var.tags
  )

  default_node_labels = {
    workload    = var.node_group_name
    environment = var.environment
    managed-by  = "terraform"
  }
}


# ============================================================
# EKS Control-Plane IAM Role
# ============================================================

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    sid     = "AllowEKSServiceToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = [
        "eks.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.cluster_name}-cluster-role"
  description        = "IAM role used by the ${local.cluster_name} EKS control plane."
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role = aws_iam_role.eks_cluster.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/AmazonEKSClusterPolicy",
    data.aws_partition.current.partition
  )
}


# ============================================================
# EKS Managed Node-Group IAM Role
# ============================================================

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    sid     = "AllowEC2ToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = [
        "ec2.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.cluster_name}-${var.node_group_name}-node-role"
  description        = "IAM role used by the ${local.cluster_name} managed worker nodes."
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-${var.node_group_name}-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role = aws_iam_role.eks_node.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    data.aws_partition.current.partition
  )
}

resource "aws_iam_role_policy_attachment" "eks_ecr_pull_only" {
  role = aws_iam_role.eks_node.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    data.aws_partition.current.partition
  )
}


# ============================================================
# CloudWatch Log Group for EKS Control-Plane Logs
# ============================================================

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-control-plane-logs"
  })
}


# ============================================================
# Amazon EKS Control Plane
# ============================================================

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  enabled_cluster_log_types = var.control_plane_log_types

  access_config {
    authentication_mode = var.authentication_mode

    bootstrap_cluster_creator_admin_permissions = (
      var.bootstrap_cluster_creator_admin_permissions
    )
  }

  vpc_config {
    subnet_ids = var.private_subnet_ids

    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_public_access_cidrs
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_control_plane
  ]

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })

  lifecycle {
    precondition {
      condition = (
        var.cluster_endpoint_public_access ||
        var.cluster_endpoint_private_access
      )

      error_message = "At least one EKS API endpoint access method must be enabled."
    }

    precondition {
      condition = (
        !var.cluster_endpoint_public_access ||
        length(var.cluster_public_access_cidrs) > 0
      )

      error_message = "cluster_public_access_cidrs must contain at least one restricted CIDR when public API access is enabled."
    }
  }
}


# ============================================================
# EKS OIDC Issuer Certificate
# ============================================================

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}


# ============================================================
# IAM OIDC Provider for IRSA
# ============================================================

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[
      length(data.tls_certificate.eks_oidc.certificates) - 1
    ].sha1_fingerprint
  ]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-oidc-provider"
  })
}


# ============================================================
# Amazon VPC CNI IRSA Trust Policy
# ============================================================

data "aws_iam_policy_document" "vpc_cni_assume_role" {
  statement {
    sid     = "AllowVPCCNIServiceAccountToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.eks.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"

      values = [
        "system:serviceaccount:kube-system:aws-node"
      ]
    }
  }
}


# ============================================================
# Amazon VPC CNI IRSA Role
# ============================================================

resource "aws_iam_role" "vpc_cni" {
  name               = "${local.cluster_name}-vpc-cni-irsa"
  description        = "IRSA role used by the Amazon VPC CNI aws-node service account."
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-vpc-cni-irsa"
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role = aws_iam_role.vpc_cni.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/AmazonEKS_CNI_Policy",
    data.aws_partition.current.partition
  )
}


# ============================================================
# Amazon EBS CSI Driver IRSA Trust Policy
# ============================================================

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    sid     = "AllowEBSCSIServiceAccountToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.eks.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"

      values = [
        "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      ]
    }
  }
}


# ============================================================
# Amazon EBS CSI Driver IRSA Role
# ============================================================

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.cluster_name}-ebs-csi-irsa"
  description        = "IRSA role used by the Amazon EBS CSI controller service account."
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-ebs-csi-irsa"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role = aws_iam_role.ebs_csi.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
    data.aws_partition.current.partition
  )
}


# ============================================================
# Amazon VPC CNI EKS Managed Add-on
#
# This add-on is created before the worker node group. The
# worker nodes require pod networking during their bootstrap
# and cluster-registration process.
# ============================================================

resource "aws_eks_addon" "vpc_cni" {
  count = var.enable_vpc_cni_addon ? 1 : 0

  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"
  addon_version = (
    var.vpc_cni_addon_version
  )

  service_account_role_arn = aws_iam_role.vpc_cni.arn

  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update

  depends_on = [
    aws_iam_openid_connect_provider.eks,
    aws_iam_role_policy_attachment.vpc_cni
  ]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-vpc-cni"
  })
}


# ============================================================
# EKS Managed Node Group
# ============================================================

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-${var.node_group_name}"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids

  version        = var.cluster_version
  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = var.max_unavailable
  }

  labels = merge(
    local.default_node_labels,
    var.node_labels
  )

  dynamic "taint" {
    for_each = var.node_taints

    content {
      key    = taint.value.key
      value  = try(taint.value.value, null)
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_ecr_pull_only,
    aws_eks_addon.vpc_cni
  ]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-${var.node_group_name}"

    "k8s.io/cluster-autoscaler/enabled" = "true"

    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  })

  lifecycle {
    precondition {
      condition = (
        var.min_size <= var.desired_size &&
        var.desired_size <= var.max_size
      )

      error_message = "Node-group scaling must satisfy min_size <= desired_size <= max_size."
    }
  }
}


# ============================================================
# kube-proxy EKS Managed Add-on
# ============================================================

resource "aws_eks_addon" "kube_proxy" {
  count = var.enable_kube_proxy_addon ? 1 : 0

  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
  addon_version = (
    var.kube_proxy_addon_version
  )

  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update

  depends_on = [
    aws_eks_node_group.general
  ]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-kube-proxy"
  })
}


# ============================================================
# CoreDNS EKS Managed Add-on
# ============================================================

resource "aws_eks_addon" "coredns" {
  count = var.enable_coredns_addon ? 1 : 0

  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
  addon_version = (
    var.coredns_addon_version
  )

  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update

  depends_on = [
    aws_eks_node_group.general
  ]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-coredns"
  })
}


# ============================================================
# Amazon EBS CSI Driver EKS Managed Add-on
# ============================================================

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi_addon ? 1 : 0

  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-ebs-csi-driver"
  addon_version = (
    var.ebs_csi_addon_version
  )

  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update

  depends_on = [
    aws_eks_node_group.general,
    aws_iam_openid_connect_provider.eks,
    aws_iam_role_policy_attachment.ebs_csi
  ]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-ebs-csi-driver"
  })
}
