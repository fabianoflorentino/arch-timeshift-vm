# arch-timeshift-vm - developer entrypoints.
#
# Recipes use '>' instead of TAB via .RECIPEPREFIX so the file is robust to
# editors that expand tabs.
.RECIPEPREFIX = >

SHELL := /bin/bash
VENV ?= .venv
BIN := $(VENV)/bin
TEST_IMAGE ?= arch-timeshift-test:latest

# Tests must talk to the *local* Docker daemon and bypass the broken
# "desktop" credential store configured in ~/.docker/config.json.
export DOCKER_CONFIG := $(CURDIR)/.docker
export DOCKER_HOST ?= unix:///var/run/docker.sock
export PATH := $(CURDIR)/$(BIN):$(PATH)
export ANSIBLE_PYTHON_INTERPRETER := $(CURDIR)/$(BIN)/python

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
> @grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: venv
venv: ## Create .venv and install pinned dev dependencies
> python -m venv $(VENV)
> $(BIN)/python -m pip install --upgrade pip
> $(BIN)/pip install -r requirements-dev.txt

.PHONY: deps
deps: ## Install Ansible collections from requirements.yml
> $(BIN)/ansible-galaxy collection install -r requirements.yml

.PHONY: lint
lint: docker-config ## Run yamllint and ansible-lint
> $(BIN)/yamllint .
> $(BIN)/ansible-lint

.PHONY: syntax
syntax: ## Syntax-check the restore playbook
> $(BIN)/ansible-playbook playbooks/restore.yml --syntax-check

.PHONY: docker-config
docker-config: ## Generate a local Docker config (bypasses broken credsStore)
> @mkdir -p $(DOCKER_CONFIG)
> @[ -f $(DOCKER_CONFIG)/config.json ] || printf '{}' > $(DOCKER_CONFIG)/config.json

.PHONY: test-image
test-image: docker-config ## Build the Tier 1 test container image
> docker build -t $(TEST_IMAGE) molecule/default

.PHONY: test
test: lint test-image ## Molecule Tier 1 (unprivileged, Docker)
> $(BIN)/molecule test -s default

.PHONY: test-integration
test-integration: lint ## Molecule Tier 2 (privileged sandbox, requires root)
> $(BIN)/molecule test -s integration

.PHONY: clean
clean: ## Remove caches, docker config and molecule scratch
> rm -rf .cache .docker molecule/*/.molecule
