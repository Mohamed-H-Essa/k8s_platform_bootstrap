# tflint for every Terraform directory under infra/terraform (`make aws-check` runs it
# with --recursive): the bundled Terraform rules (recommended preset) plus the AWS
# ruleset, which knows the AWS API (instance types, regions, IAM policy syntax, …).
config {
  # follow calls to our own modules (../../modules/*), not remote ones
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
