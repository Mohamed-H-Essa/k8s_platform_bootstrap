# Own small Terraform modules for AWS, not terraform-aws-modules

**Status:** accepted

## Context
The AWS environment (VPC, EKS, GitHub OIDC) is never applied: there is no account. Its value is
that a reader can see every resource and why it is there, and that it passes `validate`, `tflint`
and `trivy config` offline. The repository already had custom `vpc` and `eks` modules from March
2026, written for an older EKS (aws-auth era, AL2, public subnets with public IPs).

## Decision
Keep our own modules in `infra/terraform/modules/` (`vpc`, `eks`, `github-oidc`), rewritten from
the old ones: `for_each` keyed by AZ, access entries, KMS for Secrets, managed add-ons, Pod
Identity, IMDSv2-only launch templates, the night schedule. Each module is a few short files with
only the inputs this project uses. The old `terraform/` tree is deleted.

## Alternatives
- **terraform-aws-modules/vpc and /eks**: the usual choice for a team, widely used and maintained,
  with many options. Here they would hide the interesting parts behind hundreds of inputs, need
  module downloads for every check, and Trivy would report findings inside code we don't control.
- **EKS Blueprints / eksctl**: faster to a cluster, but less to show and harder to review offline.

## Consequences
- The whole AWS design reads in a few hundred lines; every Trivy finding is ours to fix or accept
  (one accepted, documented inline).
- We maintain the modules ourselves and they have never met a real account. For a team running
  production, switching to terraform-aws-modules (same resources, same ideas) would be reasonable.
