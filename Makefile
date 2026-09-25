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
bootstrap: ## Apply the root app-of-apps (creates the live branch if needed)
	@hack/bootstrap.sh

.PHONY: credentials
credentials: ## Give each Kargo Project git credentials (GITHUB_USER; prompts for the token)
	@hack/add-credentials.sh

.PHONY: status
status: ## One-screen summary of the lab
	@hack/status.sh

.PHONY: down
down: ## Delete the lab's clusters (other k3d clusters are untouched)
	@hack/down.sh

.PHONY: reset
reset: ## Put the lab into the "2am" state (scene 00; takes a few minutes)
	@scenes/00-crime.sh

.PHONY: rebuild
rebuild: down up ## Recreate all clusters from scratch

.PHONY: scene-2
scene-2: ## Chapter 2: the warm-up case (Hubble finds the policy drop)
	@scenes/02-cold-case.sh

.PHONY: scene-4
scene-4: ## Chapter 4: live tcpdump of the failing uploads (prod)
	@scenes/04-capture.sh

.PHONY: scene-5
scene-5: ## Chapter 5: the reveal (the culprit in the rendered branch)
	@scenes/05-reveal.sh

.PHONY: scene-5-fix
scene-5-fix: ## Chapter 5: revert the culprit; the fix auto-promotes
	@scenes/05-reveal.sh --fix

.PHONY: scene-6
scene-6: ## Chapter 6: merge the gate, re-push the culprit, watch it get caught
	@scenes/06-never-again.sh

.PHONY: test
test: ## Go vet, tests (with -race), golangci-lint and govulncheck, in pinned containers
	@hack/test.sh

.PHONY: images
images: ## Build our images locally (case-file, evidence-kit) and scan them
	@hack/images.sh

.PHONY: validate
validate: ## Render every overlay and validate all manifests with kubeconform
	@hack/validate.sh

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
