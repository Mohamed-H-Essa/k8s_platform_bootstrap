# GitHub Actions → AWS without stored keys.
#
# GitHub signs a short-lived OIDC token for each workflow run. AWS trusts GitHub's issuer
# (the provider below) and lets a run assume the role only if the token's claims match:
# audience sts.amazonaws.com, and a subject naming this repository and an allowed ref or
# environment. The run gets credentials for at most an hour; there is nothing to leak or
# rotate.
#
# An account has at most one provider per issuer URL: if it already exists, import it
# (terraform import module.<name>.aws_iam_openid_connect_provider.github <arn>).

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # no thumbprint_list: AWS validates GitHub's certificate against its own trusted CAs
  tags = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # exact subjects only (no wildcards): e.g. repo:owner/name:ref:refs/heads/main
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "Assumed by GitHub Actions (${join(", ", var.subjects)}) through OIDC"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
  tags                 = var.tags
}

# What the role may do is passed in by the caller, so this module stays generic.
resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}
