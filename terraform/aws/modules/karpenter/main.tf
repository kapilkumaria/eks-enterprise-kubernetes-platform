# ============================================================
# AWS data sources
# ============================================================

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}


# ============================================================
# Local values
# ============================================================

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  node_role_name = "KarpenterNodeRole-${var.cluster_name}"

  controller_role_name = (
    "${var.cluster_name}-karpenter-controller-irsa"
  )

  interruption_queue_name = coalesce(
    var.interruption_queue_name,
    var.cluster_name
  )

  discovery_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  common_tags = merge(
    {
      Project   = var.cluster_name
      ManagedBy = "Terraform"
      Component = "Karpenter"
    },
    var.tags
  )
}


# ============================================================
# Karpenter controller IRSA trust policy
# ============================================================

data "aws_iam_policy_document" "controller_assume_role" {
  statement {
    sid     = "AllowKarpenterServiceAccount"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        var.oidc_provider_arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"

      values = [
        "system:serviceaccount:${var.karpenter_namespace}:${var.karpenter_service_account_name}"
      ]
    }
  }
}


# ============================================================
# Karpenter controller IRSA role
# ============================================================

resource "aws_iam_role" "controller" {
  name = local.controller_role_name

  description = (
    "IRSA role used by the Karpenter controller in cluster ${var.cluster_name}."
  )

  assume_role_policy = (
    data.aws_iam_policy_document.controller_assume_role.json
  )

  tags = merge(local.common_tags, {
    Name = local.controller_role_name
  })
}


# ============================================================
# Karpenter worker-node role
# ============================================================

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    sid     = "AllowEC2ServiceToAssumeRole"
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

resource "aws_iam_role" "node" {
  name = local.node_role_name

  description = (
    "IAM role assumed by EC2 worker nodes provisioned by Karpenter."
  )

  assume_role_policy = (
    data.aws_iam_policy_document.node_assume_role.json
  )

  tags = merge(local.common_tags, {
    Name = local.node_role_name
  })
}


# ============================================================
# Karpenter worker-node managed policy attachments
# ============================================================

resource "aws_iam_role_policy_attachment" "node_worker" {
  role = aws_iam_role.node.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    local.partition
  )
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role = aws_iam_role.node.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    local.partition
  )
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role = aws_iam_role.node.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/AmazonEKS_CNI_Policy",
    local.partition
  )
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role = aws_iam_role.node.name

  policy_arn = format(
    "arn:%s:iam::aws:policy/AmazonSSMManagedInstanceCore",
    local.partition
  )
}


# ============================================================
# EKS node authorization
# ============================================================

resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-nodes"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_cni
  ]
}


# ============================================================
# Karpenter security-group discovery tag
# ============================================================

resource "aws_ec2_tag" "cluster_security_group_discovery" {
  resource_id = var.cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}




# ============================================================
# SQS interruption queue
# ============================================================

resource "aws_sqs_queue" "interruption" {
  count = var.enable_interruption_handling ? 1 : 0

  name = local.interruption_queue_name

  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(local.common_tags, {
    Name = local.interruption_queue_name
  })
}


# ============================================================
# SQS interruption queue policy
# ============================================================

data "aws_iam_policy_document" "interruption_queue" {
  count = var.enable_interruption_handling ? 1 : 0

  statement {
    sid    = "AllowEventBridgeAndSQS"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "events.amazonaws.com",
        "sqs.amazonaws.com"
      ]
    }

    actions = [
      "sqs:SendMessage"
    ]

    resources = [
      aws_sqs_queue.interruption[0].arn
    ]
  }

  statement {
    sid    = "DenyUnencryptedTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "sqs:*"
    ]

    resources = [
      aws_sqs_queue.interruption[0].arn
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"

      values = [
        "false"
      ]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  count = var.enable_interruption_handling ? 1 : 0

  queue_url = aws_sqs_queue.interruption[0].id
  policy    = data.aws_iam_policy_document.interruption_queue[0].json
}


# ============================================================
# EventBridge interruption event patterns
# ============================================================

locals {
  interruption_rules = var.enable_interruption_handling ? {
    health = {
      description = "AWS Health scheduled changes for Karpenter nodes."

      event_pattern = jsonencode({
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      })
    }

    spot_interruption = {
      description = "EC2 Spot Instance interruption warnings."

      event_pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      })
    }

    rebalance = {
      description = "EC2 Instance Rebalance Recommendations."

      event_pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      })
    }

    instance_state_change = {
      description = "EC2 Instance State-change Notifications."

      event_pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      })
    }
  } : {}
}


# ============================================================
# EventBridge rules
# ============================================================

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_rules

  name = substr(
    "${var.cluster_name}-${replace(each.key, "_", "-")}",
    0,
    64
  )

  description   = each.value.description
  event_pattern = each.value.event_pattern

  tags = merge(local.common_tags, {
    Name = substr(
      "${var.cluster_name}-${replace(each.key, "_", "-")}",
      0,
      64
    )
  })
}


# ============================================================
# EventBridge targets
# ============================================================

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_rules

  rule = aws_cloudwatch_event_rule.interruption[
    each.key
  ].name

  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption[0].arn
}


# ============================================================
# Karpenter controller node lifecycle permissions
# ============================================================

data "aws_iam_policy_document" "controller_node_lifecycle" {
  statement {
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"

    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]

    resources = [
      "arn:${local.partition}:ec2:${local.region}::image/*",
      "arn:${local.partition}:ec2:${local.region}::snapshot/*",
      "arn:${local.partition}:ec2:${local.region}:*:security-group/*",
      "arn:${local.partition}:ec2:${local.region}:*:subnet/*",
      "arn:${local.partition}:ec2:${local.region}:*:capacity-reservation/*",
      "arn:${local.partition}:ec2:${local.region}:*:placement-group/*"
    ]
  }

  statement {
    sid    = "AllowScopedEC2LaunchTemplateAccessActions"
    effect = "Allow"

    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]

    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"

    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate"
    ]

    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:spot-instances-request/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"

      values = [
        var.cluster_name
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid    = "AllowScopedResourceCreationTagging"
    effect = "Allow"

    actions = [
      "ec2:CreateTags"
    ]

    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:spot-instances-request/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"

      values = [
        "RunInstances",
        "CreateFleet",
        "CreateLaunchTemplate"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"

      values = [
        var.cluster_name
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid    = "AllowScopedResourceTagging"
    effect = "Allow"

    actions = [
      "ec2:CreateTags"
    ]

    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:instance/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"

      values = [
        var.cluster_name
      ]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"

      values = [
        "eks:eks-cluster-name",
        "karpenter.sh/nodeclaim",
        "Name"
      ]
    }
  }

  statement {
    sid    = "AllowScopedDeletion"
    effect = "Allow"

    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate"
    ]

    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }
  }
}


# ============================================================
# Karpenter controller IAM integration permissions
# ============================================================

data "aws_iam_policy_document" "controller_iam_integration" {
  statement {
    sid    = "AllowScopedInstanceProfileCreationActions"
    effect = "Allow"

    actions = [
      "iam:CreateInstanceProfile"
    ]

    resources = [
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"

      values = [
        var.cluster_name
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/topology.kubernetes.io/region"

      values = [
        "*"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid    = "AllowScopedInstanceProfileTagActions"
    effect = "Allow"

    actions = [
      "iam:TagInstanceProfile"
    ]

    resources = [
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/eks:eks-cluster-name"

      values = [
        var.cluster_name
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"

      values = [
        "*"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid    = "AllowScopedInstanceProfileActions"
    effect = "Allow"

    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile"
    ]

    resources = [
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/eks:eks-cluster-name"

      values = [
        var.cluster_name
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"

      values = [
        "*"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"

      values = [
        "*"
      ]
    }
  }


  statement {
    sid    = "AllowUnscopedInstanceProfileListAction"
    effect = "Allow"

    actions = [
      "iam:ListInstanceProfiles"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowInstanceProfileReadActions"
    effect = "Allow"

    actions = [
      "iam:GetInstanceProfile"
    ]

    resources = [
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/*"
    ]
  }

  statement {
    sid    = "AllowPassingInstanceRole"
    effect = "Allow"

    actions = [
      "iam:PassRole"
    ]

    resources = [
      aws_iam_role.node.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"

      values = [
        "ec2.amazonaws.com"
      ]
    }
  }
}


# ============================================================
# Karpenter controller discovery permissions
# ============================================================

data "aws_iam_policy_document" "controller_discovery" {
  statement {
    sid    = "AllowRegionalReadActions"
    effect = "Allow"

    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeHosts",
      "ec2:DescribePlacementGroups",
      "ec2:DescribeVolumes",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "ec2:DescribeInstanceTopology",
      "pricing:GetProducts",
      "ssm:GetParameter"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowAPIServerEndpointDiscovery"
    effect = "Allow"

    actions = [
      "eks:DescribeCluster"
    ]

    resources = [
      var.cluster_arn
    ]
  }

  statement {
    sid    = "AllowSSMParameterRead"
    effect = "Allow"

    actions = [
      "ssm:GetParameter"
    ]

    resources = [
      "arn:${local.partition}:ssm:${local.region}::parameter/aws/service/*"
    ]
  }
}


# ============================================================
# Karpenter interruption queue permissions
# ============================================================

data "aws_iam_policy_document" "controller_interruption" {
  count = var.enable_interruption_handling ? 1 : 0

  statement {
    sid    = "AllowInterruptionQueueActions"
    effect = "Allow"

    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage"
    ]

    resources = [
      aws_sqs_queue.interruption[0].arn
    ]
  }
}


# ============================================================
# Controller managed IAM policies
# ============================================================

resource "aws_iam_policy" "controller_node_lifecycle" {
  name = "${var.cluster_name}-karpenter-node-lifecycle"

  description = (
    "Allows Karpenter to provision and terminate EC2 worker-node infrastructure."
  )

  policy = (
    data.aws_iam_policy_document.controller_node_lifecycle.json
  )

  tags = local.common_tags
}

resource "aws_iam_policy" "controller_iam_integration" {
  name = "${var.cluster_name}-karpenter-iam-integration"

  description = (
    "Allows Karpenter to manage instance profiles and pass its worker-node role."
  )

  policy = (
    data.aws_iam_policy_document.controller_iam_integration.json
  )

  tags = local.common_tags
}

resource "aws_iam_policy" "controller_discovery" {
  name = "${var.cluster_name}-karpenter-discovery"

  description = (
    "Allows Karpenter to discover EC2, pricing, SSM and EKS resources."
  )

  policy = (
    data.aws_iam_policy_document.controller_discovery.json
  )

  tags = local.common_tags
}

resource "aws_iam_policy" "controller_interruption" {
  count = var.enable_interruption_handling ? 1 : 0

  name = "${var.cluster_name}-karpenter-interruption"

  description = (
    "Allows Karpenter to consume interruption events from Amazon SQS."
  )

  policy = (
    data.aws_iam_policy_document.controller_interruption[0].json
  )

  tags = local.common_tags
}


# ============================================================
# Controller IAM policy attachments
# ============================================================

resource "aws_iam_role_policy_attachment" "controller_node_lifecycle" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller_node_lifecycle.arn
}

resource "aws_iam_role_policy_attachment" "controller_iam_integration" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller_iam_integration.arn
}

resource "aws_iam_role_policy_attachment" "controller_discovery" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller_discovery.arn
}

resource "aws_iam_role_policy_attachment" "controller_interruption" {
  count = var.enable_interruption_handling ? 1 : 0

  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller_interruption[0].arn
}
