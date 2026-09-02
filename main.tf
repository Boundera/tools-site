# tools.boundera.io: one static host for every Boundera tool that must never
# see the user's data.
#
# THE HOST RULE, enforced by this stack rather than by convention:
#   * Static files only. No compute of any kind sits in front of the bucket.
#   * One strict Content-Security-Policy, applied by CloudFront to every path,
#     so no tool can loosen it for itself.
#   * One path prefix per tool, one deploy role per prefix, each trusted by
#     exactly one GitHub repository on its release tags.
#   * Nothing is logged unless enable_access_logs is set, and even then only
#     what any web server sees: address, path, status.
#
# This repository is public on purpose. Anyone can read how the host is
# configured, which is the point of hosting a privacy tool here at all.

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project    = "tools-site"
    ManagedBy  = "terraform"
    Repository = var.site_repository
  }

  # Every prefix CloudFront may read: the host's own pages, then each tool.
  served_prefixes = concat(["site"], sort(keys(var.tools)))

  # The policy the whole host answers with. The same string ships in every
  # tool's page as a <meta> tag; the header is what makes it hold everywhere.
  content_security_policy = join("; ", [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self' data:",
    "font-src 'self'",
    "connect-src 'none'",
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ])
}

# ---------------------------------------------------------------------------
# The bucket. Private; CloudFront reads it through Origin Access Control.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name

  tags = {
    Name            = var.bucket_name
    DataSensitivity = "public-by-design"
  }
}

resource "aws_s3_bucket_versioning" "site" {
  # Cheap undo for a bad deploy.
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  # Everything here is world-readable by design; AES256 is the right choice
  # for public objects and keeps the host independent of any shared key.
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  # Fully blocked. Only the distribution below can read, via OAC. There is no
  # direct S3 URL to leak.
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid    = "AllowCloudFrontOACRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject"]

    # Only the served prefixes. An object written anywhere else is unreachable.
    resources = [for p in local.served_prefixes : "${aws_s3_bucket.site.arn}/${p}/*"]

    condition {
      # Only THIS distribution. Without it any distribution in any account
      # could pull from the bucket.
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------------------------------------------------------------------------
# Optional access logs. Off by default.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = "${var.bucket_name}-logs"

  tags = {
    Name            = "${var.bucket_name}-logs"
    DataSensitivity = "internal"
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    # CloudFront standard logging writes through the legacy log-delivery
    # group, which needs ACLs to exist on the bucket.
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  access_control_policy {
    owner {
      id = data.aws_canonical_user_id.current.id
    }

    grant {
      permission = "FULL_CONTROL"
      grantee {
        type = "CanonicalUser"
        id   = data.aws_canonical_user_id.current.id
      }
    }

    grant {
      # The CloudFront log delivery account.
      permission = "FULL_CONTROL"
      grantee {
        type = "CanonicalUser"
        id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
      }
    }
  }

  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

data "aws_canonical_user_id" "current" {}

resource "aws_s3_bucket_public_access_block" "logs" {
  count                   = var.enable_access_logs ? 1 : 0
  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }
  }
}
