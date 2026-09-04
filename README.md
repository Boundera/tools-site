# tools-site

The infrastructure behind **https://tools.boundera.io**, the host for every Boundera tool that must never see the user's data. Public on purpose: anyone can read exactly how the host is configured, which is the point of hosting a privacy tool here at all.

## The host rule

- **Static files only.** An S3 bucket behind CloudFront. No server, no function that reads a request, no cookie, no analytics.
- **One strict policy for every path.** CloudFront adds the Content-Security-Policy and the other security headers to every response on the host. A tool cannot loosen it for itself.
- **One prefix per tool, one deploy role per prefix.** Each role is trusted by exactly one GitHub repository on its release tags, and can write only its own prefix and invalidate the cache. No role can run Terraform.
- **Nothing is counted unless asked.** Access logs are off by default. When on, they hold what any web server sees: address, path, status. Never a document.

A tool that needs a server, analytics, or an email gate does not belong here. It goes on boundera.io.

## What is here

| Path | What |
| --- | --- |
| `main.tf` | The bucket, its policy, the optional log bucket |
| `cloudfront.tf` | The distribution, the headers policy, the origin access control, the viewer function |
| `dns.tf` | The certificate and the DNS alias, with the zone looked up by name |
| `oidc.tf` | One deploy role per prefix, trusted by one repository each |
| `function/viewer-request.js` | The only code in front of the bucket: path rewrites, nothing else |
| `site/` | The host's own pages: the tools index, the 404 page, and the files crawlers expect at the root |

Nothing in this repository names an account, a zone id, a distribution id, or a state bucket. Those appear in Terraform outputs and state, which stay private.

## Tools on the host

| Prefix | Repository | Tool |
| --- | --- | --- |
| `sdr-redactor/` | [Boundera/fedramp-sdr-redactor](https://github.com/Boundera/fedramp-sdr-redactor) | Redact a FedRAMP Security Decision Record in the browser |

## Apply

Applying is done by a person on an administrative profile, never by CI.

```bash
terraform init \
  -backend-config="bucket=<state bucket>" \
  -backend-config="key=tools-site/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"
terraform plan
terraform apply
```

The first apply issues the certificate, waits for DNS validation, creates the distribution, and points `tools.boundera.io` at it. Expect fifteen minutes. Then copy the outputs into each repository's Actions variables:

| Variable | Output |
| --- | --- |
| `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arns["<prefix>"]` |
| `S3_BUCKET` | `bucket_name` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `cloudfront_distribution_id` |

This repository's own variables use the `site` role, so a reviewed merge to `main` that touches `site/` publishes the index.

## Add a tool

1. Add an entry to `tools` in `variables.tf` (or in `terraform.tfvars`): the prefix, the repository, and its numeric id from `gh api repos/<owner>/<name> --jq .id`. The id is pinned in the role's trust policy, because GitHub's subject claims now carry it. Open a pull request; the owner reviews it.
2. Apply. A new deploy role appears in the outputs.
3. Set the three variables in the tool's repository and give it a deploy workflow that builds, checks, syncs its prefix, invalidates, and verifies the live hashes. The redactor's workflow is the reference.
4. Add the tool to the index in `site/index.html`, to `site/sitemap.xml`, to `site/llms.txt`, and to the table above.

## Verify a deploy

```bash
curl -sI https://tools.boundera.io/ | grep -i content-security-policy
curl -s https://tools.boundera.io/sdr-redactor/BUNDLE_SHA256.txt
```

The header must be present on every path. Each tool's served hashes must equal its release's hash list.

## Review rule

`main` is protected. Every change needs an approving review from a code owner, and the owner is the code owner for every file. CI must pass. No force pushes, no deletions.

## License

MIT. See [LICENSE](LICENSE).
