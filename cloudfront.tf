# ---------------------------------------------------------------------------
# The distribution: the only thing on the internet in front of the bucket.
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.bucket_name}-oac"
  description                       = "CloudFront reads ${var.bucket_name}; nothing else does."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Path handling only. The source is in function/viewer-request.js and is
# short enough to read in one sitting: it never reads a header, never makes
# a request, never logs.
resource "aws_cloudfront_function" "viewer_request" {
  name    = "tools-site-viewer-request"
  runtime = "cloudfront-js-2.0"
  comment = "Directory URLs to index.html; the root to the tools index; nothing else."
  publish = true
  code    = file("${path.module}/function/viewer-request.js")
}

# The host rule as headers. Attached to the only cache behavior, so every
# path on the host answers with it and no deploy can change that.
resource "aws_cloudfront_response_headers_policy" "site" {
  name    = "tools-site-security-headers"
  comment = "Strict policy for a host that must never see the user's data."

  security_headers_config {
    content_security_policy {
      content_security_policy = local.content_security_policy
      override                = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
      override = true
    }

    items {
      header   = "Cross-Origin-Opener-Policy"
      value    = "same-origin"
      override = true
    }

    items {
      header   = "Cross-Origin-Resource-Policy"
      value    = "same-origin"
      override = true
    }
  }
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "site" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Boundera tools host: ${var.domain_name}"
  aliases         = [var.domain_name]
  price_class     = var.price_class
  http_version    = "http2and3"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  # A missing object comes back from S3 as 403 because the distribution may
  # not list the bucket. Both become the host's own 404 page.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/site/404.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/site/404.html"
    error_caching_min_ttl = 60
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  dynamic "logging_config" {
    for_each = var.enable_access_logs ? [1] : []

    content {
      bucket          = aws_s3_bucket.logs[0].bucket_domain_name
      include_cookies = false
      prefix          = "cloudfront/"
    }
  }

  depends_on = [aws_s3_bucket_acl.logs]
}
