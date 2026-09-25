# Laptop lab for "The Case of the Green Dashboard".
# Prereqs: OrbStack (or any Docker), k3d, kubectl, helm, python3, openssl, htpasswd.

.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

.PHONY: help
help: ## Show this help
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[1m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: doctor
doctor: ## Check local prerequisites
	@hack/doctor.sh

.PHONY: up
up: ## Create staging, prod and mgmt clusters with the full control plane
	@hack/up.sh

.PHONY: bootstrap
bootstrap: ## Apply the root app-of-apps (after this repo is pushed to GitHub)
	kubectl --context k3d-mgmt apply -f bootstrap/platform-aoa.yaml

.PHONY: credentials
credentials: ## Give each Kargo Project git credentials (GITHUB_USER, GITHUB_TOKEN)
	@hack/add-credentials.sh

.PHONY: status
status: ## One-screen summary of the lab
	@hack/status.sh

.PHONY: down
down: ## Delete the lab's clusters (other k3d clusters are untouched)
	@hack/down.sh

.PHONY: reset
reset: down up ## Recreate the lab from scratch (scene reset arrives in Phase 5)

.PHONY: lint
lint: ## Run every pre-commit hook (in a container; no local installs needed)
	@hack/lint.sh

.PHONY: verify-pins
verify-pins: ## Check chart sha256s and that every image is pinned by digest
	@hack/verify-pins.sh

.PHONY: verify-images
verify-images: ## Verify image signatures and scan for vulnerabilities (needs cosign, trivy)
	@hack/verify-images.sh

.PHONY: pins
pins: ## Show which pinned image tags now point at a different digest
	@hack/pins.sh

.PHONY: phase0
phase0: ## Phase 0 black-hole repro on a scratch cluster (see docs/)
	@hack/phase0/up.sh
