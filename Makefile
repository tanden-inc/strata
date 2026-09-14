# Strata developer commands. `make help` lists them.
MOON ?= moon
PURE_PKGS := tanden-inc/strata/core tanden-inc/strata/codec

.PHONY: help setup check check-wasm-gc test test-js test-wasm-gc test-all fmt fmt-check info cov bench todo ci clean docs docs-build

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

setup: ## Install git hooks and refresh the registry index
	git config core.hooksPath .githooks
	$(MOON) update

check: ## Type-check every package for native and js, warnings are errors
	$(MOON) check --deny-warn --target native
	$(MOON) check --deny-warn --target js

check-wasm-gc: ## Type-check the pure packages for the browser target
	$(MOON) check --deny-warn --target wasm-gc

test: ## Run tests on the native target
	$(MOON) test --target native

test-js: ## Run tests on the js target (panics are isolated per test here)
	$(MOON) test --target js

test-wasm-gc: ## Run the pure packages' tests on wasm-gc
	$(MOON) test --target wasm-gc

test-all: test test-js test-wasm-gc ## Run tests on every supported target

fmt: ## Format all sources
	$(MOON) fmt

fmt-check: ## Fail if formatting would change anything
	$(MOON) fmt --check

info: ## Regenerate pkg.generated.mbti files and fail on drift
	$(MOON) info
	git diff --exit-code -- '*.mbti'

cov: ## Coverage report (writes uncovered.log)
	$(MOON) coverage analyze > uncovered.log || true
	@echo "see uncovered.log"

bench: ## Run benchmarks
	$(MOON) bench

todo: ## List unimplemented stubs (`...` bodies and `todo("...")` raises)
	@grep -rn --include='*.mbt' -E '^\s*(\.\.\.|(@strata\.)?todo\("|abort\("TODO\(strata\)|// TODO\(strata\))' core codec store runtime testing examples benchmarks || echo "no stubs left"

ci: fmt-check check check-wasm-gc info test test-js test-wasm-gc ## Everything CI runs

clean: ## Remove build outputs
	$(MOON) clean

docs: ## Serve the documentation site locally (docs/, VitePress via bun)
	cd docs && bun install && bun run dev

docs-build: ## Build the documentation site into docs/.vitepress/dist
	cd docs && bun install --frozen-lockfile && bun run build
