# ============================================================
# ExternalDNS IRSA Trust Policy
# ============================================================

data "aws_iam_policy_document" "external_dns_assume_role" {
  count = var.enable_external_dns_irsa ? 1 : 0

  statement {
    sid     = "AllowExternalDNSServiceAccountToAssumeRole"
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
        "system:serviceaccount:${var.external_dns_namespace}:${var.external_dns_service_account_name}"
      ]
    }
  }
}


# ============================================================
# ExternalDNS Route 53 Permissions Policy
# ============================================================

data "aws_iam_policy_document" "external_dns_permissions" {
  count = var.enable_external_dns_irsa ? 1 : 0

  statement {
    sid    = "AllowRoute53RecordChanges"
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets"
    ]

    resources = [
      for hosted_zone_id in var.external_dns_hosted_zone_ids :
      format(
        "arn:%s:route53:::hostedzone/%s",
        data.aws_partition.current.partition,
        hosted_zone_id
      )
    ]
  }

  statement {
    sid    = "AllowRoute53ReadOperations"
    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource"
    ]

    resources = ["*"]
  }
}


# ============================================================
# ExternalDNS Customer-Managed IAM Policy
# ============================================================

resource "aws_iam_policy" "external_dns" {
  count = var.enable_external_dns_irsa ? 1 : 0

  name        = "${local.cluster_name}-external-dns"
  description = "Allows ExternalDNS to manage approved Amazon Route 53 hosted zones."
  policy      = data.aws_iam_policy_document.external_dns_permissions[0].json

  tags = merge(local.common_tags, {
    Name      = "${local.cluster_name}-external-dns"
    Component = "ExternalDNS"
  })
}


# ============================================================
# ExternalDNS IRSA Role
# ============================================================

resource "aws_iam_role" "external_dns" {
  count = var.enable_external_dns_irsa ? 1 : 0

  name               = "${local.cluster_name}-external-dns-irsa"
  description        = "IRSA role used by the ExternalDNS Kubernetes service account."
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role[0].json

  tags = merge(local.common_tags, {
    Name      = "${local.cluster_name}-external-dns-irsa"
    Component = "ExternalDNS"
  })
}


# ============================================================
# ExternalDNS IAM Policy Attachment
# ============================================================

resource "aws_iam_role_policy_attachment" "external_dns" {
  count = var.enable_external_dns_irsa ? 1 : 0

  role       = aws_iam_role.external_dns[0].name
  policy_arn = aws_iam_policy.external_dns[0].arn
}
