# ---------------------------------------------------------------------------
# Deploy roles. One per prefix, each trusted by one repository on the refs
# it names. A role can write its own prefix and invalidate the cache. It
# cannot read another tool's prefix, change the bucket, touch the
# distribution's configuration, or run Terraform.
# ---------------------------------------------------------------------------

locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"

  deployers = merge(
    {
      # The host's own pages deploy from this repository's main branch, which
      # is protected and requires review.
      site = {
        repository  = var.site_repository
        deploy_refs = ["refs/heads/main"]
      }
    },
    var.tools,
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = local.github_oidc_url
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's tokens against its own trust store now; the
  # thumbprint is still a required argument.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = local.github_oidc_url
}

locals {
  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

data "aws_iam_policy_document" "deploy_trust" {
  for_each = local.deployers

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for ref in each.value.deploy_refs : "repo:${each.value.repository}:ref:${ref}"]
    }
  }
}

data "aws_iam_policy_document" "deploy_permissions" {
  for_each = local.deployers

  statement {
    sid       = "ListOwnPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.key}/*", each.key]
    }
  }

  statement {
    sid    = "WriteOwnPrefix"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.site.arn}/${each.key}/*"]
  }

  statement {
    sid       = "InvalidateCache"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role" "deploy" {
  for_each = local.deployers

  name                 = "tools-site-deploy-${each.key}"
  description          = "Deploys ${each.key}/ on ${var.domain_name} from ${each.value.repository}."
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust[each.key].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.deployers

  name   = "deploy-${each.key}"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.deploy_permissions[each.key].json
}
