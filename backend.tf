terraform {
  # State lives in a private S3 bucket. Nothing about that bucket is written
  # here, because this repository is public. Supply it at init time:
  #
  #   terraform init \
  #     -backend-config="bucket=<state bucket>" \
  #     -backend-config="key=tools-site/terraform.tfstate" \
  #     -backend-config="region=us-east-1" \
  #     -backend-config="use_lockfile=true"
  #
  # `terraform init -backend=false` is enough for fmt and validate, which is
  # all CI does.
  backend "s3" {}
}
