variable "aws_region" {
  description = "Region for the bucket, the roles, and the optional log bucket. The certificate is always issued in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "The host name every client-only tool is served from."
  type        = string
  default     = "tools.boundera.io"
}

variable "zone_name" {
  description = "The public Route53 hosted zone that holds domain_name. Looked up by name, never by id."
  type        = string
  default     = "boundera.io"
}

variable "bucket_name" {
  description = "S3 bucket for the host. Globally unique. Deliberately carries no account number: this repository is public."
  type        = string
  default     = "boundera-tools-site"
}

variable "tools" {
  description = <<-EOT
    One entry per tool on the host. The key is the tool's path prefix, so the
    tool is served at https://<domain_name>/<key>/. `repository` is the GitHub
    owner/name whose Actions may deploy that prefix and nothing else.
    `deploy_refs` lists the git refs the deploy role trusts; release tags by
    default, so a deploy always corresponds to a tagged, reviewed release.
  EOT
  type = map(object({
    repository  = string
    deploy_refs = optional(list(string), ["refs/tags/v*"])
  }))
  default = {
    "sdr-redactor" = {
      repository = "Boundera/fedramp-sdr-redactor"
    }
  }

  validation {
    condition     = alltrue([for k in keys(var.tools) : can(regex("^[a-z0-9][a-z0-9-]*$", k)) && k != "site"])
    error_message = "Tool keys are lower-case slugs (letters, digits, dashes). The key \"site\" is reserved for the host's own pages."
  }
}

variable "site_repository" {
  description = "The repository whose Actions may deploy the host's own pages under site/."
  type        = string
  default     = "Boundera/tools-site"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC identity provider. An account can hold only one for token.actions.githubusercontent.com; leave this false when it already exists."
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Write CloudFront standard access logs (client address, path, status) to a private bucket. Off by default: the host counts nothing unless asked, and never sees a document either way."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Days to keep access logs when enable_access_logs is true."
  type        = number
  default     = 30
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 serves North America and Europe."
  type        = string
  default     = "PriceClass_100"
}
