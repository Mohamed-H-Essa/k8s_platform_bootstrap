# AWS environment and CI checks. Everything here is offline: nothing talks to an AWS
# account (there is none), nothing is applied. Included by the Makefile.

TF_AWS       := infra/terraform/envs/aws
TFLINT_IMAGE ?= ghcr.io/terraform-linters/tflint:v0.65.0
# plugins (the AWS ruleset) are cached in .local; GITHUB_TOKEN, if set, avoids API rate limits
TFLINT       := docker run --rm -v "$(CURDIR)":/data -w /data \
                  -e TFLINT_PLUGIN_DIR=/data/.local/tflint-plugins -e GITHUB_TOKEN \
                  $(TFLINT_IMAGE) --chdir=infra/terraform --config=/data/infra/terraform/.tflint.hcl

.PHONY: aws-check
aws-check: ## AWS env, offline: terraform validate, tflint, trivy config (HIGH/CRITICAL fail)
	terraform -chdir=$(TF_AWS) init -backend=false -input=false >/dev/null
	terraform -chdir=$(TF_AWS) validate
	$(TFLINT) --init >/dev/null
	$(TFLINT) --recursive
	trivy config --quiet --exit-code 1 --severity HIGH,CRITICAL infra/terraform
	@echo "aws-check: OK (nothing applied)"

.PHONY: ci-lint
ci-lint: ## lint the GitHub Actions workflows (actionlint, shellcheck inside run: blocks if installed)
	actionlint
