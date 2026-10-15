# Single entry point for local checks — CI runs these same targets.
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help

BASH_SOURCES := $(shell find bin lib tests -name '*.sh' -o -name '*.bash' 2>/dev/null | sort)

.PHONY: help install fmt lint lint-bash lint-ps test test-bash test-ps prepush

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}'

install: ## Install pinned toolchain and git hooks
	mise install
	pre-commit install --hook-type pre-commit --hook-type pre-push

fmt: ## Auto-format bash (shfmt writes in place)
	shfmt -w $(BASH_SOURCES)

lint: lint-bash lint-ps ## Run all linters

lint-bash: ## ShellCheck + shfmt format check
ifneq ($(BASH_SOURCES),)
	shellcheck $(BASH_SOURCES)
	shfmt --diff $(BASH_SOURCES)
else
	@echo "lint-bash: no bash sources found, skipping"
endif

lint-ps: ## PSScriptAnalyzer over all PowerShell files
	pwsh -NoProfile -File scripts/lint-ps.ps1

test: test-bash test-ps ## Run all test suites

test-bash: ## bats tests
	@tests=$$(find tests -name '*.bats' 2>/dev/null | sort); \
	if [[ -z "$$tests" ]]; then echo "test-bash: no .bats files, skipping"; exit 0; fi; \
	bats $$tests

test-ps: ## Pester tests (installs Pester 5 if missing)
	pwsh -NoProfile -File scripts/test-ps.ps1

prepush: lint test ## Full gate: everything CI runs (pre-push hook target)
