# Slipway: a production-style platform on a laptop.  `make help` lists everything.
SHELL := /bin/bash
.DEFAULT_GOAL := help

LOCAL      := $(CURDIR)/.local
TF_LOCAL   := infra/terraform/envs/local
OVERLAY    := platform/workloads/shortener/overlays/local/kustomization.yaml
export KUBECONFIG := $(LOCAL)/kubeconfig
# the active Docker context's socket (OrbStack, Docker Desktop, Colima…), for Terraform
DOCKER_SOCK ?= $(shell docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
TAG        ?= $(shell yq '.images[0].newTag' $(OVERLAY))
GIT_SSH    := ssh -i $(LOCAL)/git_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 23231

.PHONY: help
help: ## list the targets
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

# ---- the platform ------------------------------------------------------------------
.PHONY: up
up: keys ## create everything: cluster, registry, caches, Git, Argo CD, then the platform
	terraform -chdir=$(TF_LOCAL) init -upgrade -input=false >/dev/null
	@# chart downloads can fail on a flaky network; apply is idempotent, so retry it
	for i in 1 2 3; do \
	  TF_VAR_docker_host=$(DOCKER_SOCK) TF_VAR_git_admin_public_key=$(LOCAL)/git_ed25519.pub \
	    terraform -chdir=$(TF_LOCAL) apply -auto-approve -input=false && break; \
	  [ $$i = 3 ] && exit 1; echo "apply failed, retrying ($$i/3)"; sleep 10; \
	done
	terraform -chdir=$(TF_LOCAL) output -raw kubeconfig > $(KUBECONFIG)
	@# the two secrets that never go to Git: the release public key and Grafana's admin password
	for ns in kyverno monitoring; do kubectl create namespace $$ns --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done
	kubectl -n kyverno create secret generic cosign-pub --from-file=cosign.pub=$(LOCAL)/cosign.pub \
	  --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin \
	  --from-file=admin-password=$(LOCAL)/grafana-password --dry-run=client -o yaml | kubectl apply -f -
	$(MAKE) --no-print-directory publish
	SKIP_IF_SIGNED=1 scripts/release-image.sh $(TAG)
	scripts/wait-healthy.sh
	@$(MAKE) --no-print-directory urls

.PHONY: down
down: ## delete the cluster and Argo CD (registry, caches and Git data are kept)
	TF_VAR_docker_host=$(DOCKER_SOCK) TF_VAR_git_admin_public_key=$(LOCAL)/git_ed25519.pub \
	  terraform -chdir=$(TF_LOCAL) destroy -auto-approve -input=false

.PHONY: clean
clean: down ## down, and also delete the image caches and the local registry's data
	-docker volume rm slipway-registry-data slipway-git-data \
	  slipway-cache-dockerio-data slipway-cache-quayio-data slipway-cache-ghcrio-data slipway-cache-k8sio-data

.PHONY: keys
keys: $(LOCAL)/git_ed25519 $(LOCAL)/cosign.key $(LOCAL)/grafana-password ## make the local keys and passwords (once)
$(LOCAL)/git_ed25519:
	@mkdir -p $(LOCAL)
	ssh-keygen -q -t ed25519 -N '' -C slipway-git -f $@
$(LOCAL)/cosign.key:
	@mkdir -p $(LOCAL)
	cd $(LOCAL) && COSIGN_PASSWORD= cosign generate-key-pair --output-key-prefix cosign >/dev/null
$(LOCAL)/grafana-password:
	@mkdir -p $(LOCAL)
	@openssl rand -base64 18 | tr -d '\n' > $@

# ---- GitOps --------------------------------------------------------------------------
.PHONY: publish
publish: ## push the committed state to the in-cluster Git server (Argo CD syncs it)
	@git diff --quiet HEAD -- platform || echo "note: uncommitted changes under platform/ are not published"
	GIT_SSH_COMMAND="$(GIT_SSH)" git push --force --quiet ssh://localhost/platform.git HEAD:main
	-@kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1
	@echo "published $$(git rev-parse --short HEAD)"

.PHONY: image
image: ## build, scan, SBOM, sign and push the shortener image for the current tag
	scripts/release-image.sh $(TAG)

.PHONY: release
release: ## ship a new version: image (as above) → bump the tag in Git → Argo CD rolls it out
	$(eval NEW := $(shell git rev-parse --short HEAD)-$(shell date +%H%M%S))
	scripts/release-image.sh $(NEW)
	yq -i '.images[0].newTag = "$(NEW)"' $(OVERLAY)
	git add $(OVERLAY) && git commit -q -m "release: shortener $(NEW)"
	$(MAKE) --no-print-directory publish

# ---- checks ------------------------------------------------------------------------
.PHONY: test
test: ## unit tests (race detector on)
	cd app && go vet ./... && go test -race -count=1 ./...

.PHONY: lint
lint: ## Terraform, manifests, policies and workflows
	terraform fmt -check -recursive infra
	scripts/lint-manifests.sh
	actionlint

.PHONY: smoke
smoke: ## create a link through the gateway and follow it
	scripts/smoke.sh

.PHONY: unsigned
unsigned: ## show that an unsigned image is refused at admission
	scripts/try-unsigned.sh

.PHONY: load
load: ## 2 minutes of traffic (k6): writes and reads through the gateway
	k6 run --quiet scripts/load.js

.PHONY: chaos
chaos: ## chaos day: pod kill, node loss, database failover, bad release (see docs/chaos-day.md)
	scripts/chaos/run-all.sh

.PHONY: urls
urls: ## where everything is
	@echo
	@echo "  Shortener  http://sho.localtest.me      (POST /api/links {\"url\": \"https://…\"})"
	@echo "  Grafana    http://grafana.localtest.me  (dashboard: Shortener · service and SLOs; admin / $$(cat $(LOCAL)/grafana-password))"
	@echo "  Argo CD    http://argocd.localtest.me   (admin / $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d))"
	@echo "  Prometheus http://prometheus.localtest.me"
	@echo

# extra targets live in mk/*.mk (e.g. mk/aws.mk for the AWS environment and CI checks)
-include mk/*.mk
