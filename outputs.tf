output "domain_name" {
  description = "The host."
  value       = var.domain_name
}

output "bucket_name" {
  description = "Paste into each deploying repository's Actions variable S3_BUCKET."
  value       = aws_s3_bucket.site.bucket
}

output "cloudfront_distribution_id" {
  description = "Paste into each deploying repository's Actions variable CLOUDFRONT_DISTRIBUTION_ID."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  description = "The distribution's own name, the target of the DNS alias."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "deploy_role_arns" {
  description = "One per prefix. Paste each into the matching repository's Actions variable AWS_DEPLOY_ROLE_ARN. These carry the account number, so they are shown here and never committed."
  value       = { for k, r in aws_iam_role.deploy : k => r.arn }
}
