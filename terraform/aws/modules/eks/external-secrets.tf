# ============================================================
# AWS account information for Secrets Manager ARNs
# ============================================================

data "aws_caller_identity" "external_secrets" {
  count = var.enable_external_secrets_irsa ? 1 : 0
}


# ============================================================
# External Secrets Operator IRSA trust policy
# ============================================================

data "aws_iam_policy_document" "external_secrets_assume_role" {
  count = var.enable_external_secrets_irsa ? 1 : 0

  statement {
    sid     = "AllowExternalSecretsServiceAccountToAssumeRole"
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
        "system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_service_account_name}"
      ]
    }
  }
}


# ============================================================
# External Secrets Operator AWS Secrets Manager permissions
# ============================================================

data "aws_iam_policy_document" "external_secrets_permissions" {
  count = var.enable_external_secrets_irsa ? 1 : 0

  statement {
    sid    = "AllowReadApprovedSecretsManagerSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecretVersionIds"
    ]

    resources = [
      for secret_name_prefix in var.external_secrets_secret_name_prefixes :
      format(
        "arn:%s:secretsmanager:%s:%s:secret:%s*",
        data.aws_partition.current.partition,
        data.aws_region.current.name,
        data.aws_caller_identity.external_secrets[0].account_id,
        secret_name_prefix
      )
    ]
  }
}


# ============================================================
# External Secrets Operator customer-managed IAM policy
# ============================================================

resource "aws_iam_policy" "external_secrets" {
  count = var.enable_external_secrets_irsa ? 1 : 0

  name = "${local.cluster_name}-external-secrets"

  description = (
    "Allows External Secrets Operator to read approved AWS Secrets Manager secrets."
  )

  policy = data.aws_iam_policy_document.external_secrets_permissions[0].json

  tags = merge(local.common_tags, {
    Name      = "${local.cluster_name}-external-secrets"
    Component = "External-Secrets-Operator"
  })
}


# ============================================================
# External Secrets Operator IRSA role
# ============================================================

resource "aws_iam_role" "external_secrets" {
  count = var.enable_external_secrets_irsa ? 1 : 0

  name = "${local.cluster_name}-external-secrets-irsa"

  description = (
    "IRSA role used by the External Secrets Operator Kubernetes service account."
  )

  assume_role_policy = (
    data.aws_iam_policy_document.external_secrets_assume_role[0].json
  )

  tags = merge(local.common_tags, {
    Name      = "${local.cluster_name}-external-secrets-irsa"
    Component = "External-Secrets-Operator"
  })
}


# ============================================================
# External Secrets Operator IAM policy attachment
# ============================================================

resource "aws_iam_role_policy_attachment" "external_secrets" {
  count = var.enable_external_secrets_irsa ? 1 : 0

  role       = aws_iam_role.external_secrets[0].name
  policy_arn = aws_iam_policy.external_secrets[0].arn
}
