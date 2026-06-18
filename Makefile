# kimi-work-linux — Kimi Work DMG → Linux conversion framework
#
# Thin orchestration layer. Real logic lives in install.sh and scripts/*.sh.

APP_DIR         := $(CURDIR)/kimi-app
PACKAGE_NAME    := kimi-work
DEFAULT_VERSION := 3.0.22
DIST_DIR        := $(CURDIR)/dist

DMG ?=

.DEFAULT_GOAL := help

.PHONY: help bootstrap install-deps fetch extract inspect build-app build-app-fresh \
        package deb appimage install run-app clean

help: ## Show this help
	@awk 'BEGIN { \
		FS = ":.*?##"; \
		printf "kimi-work-linux - Kimi Work DMG -> Linux conversion framework\n\n"; \
		printf "Usage:\n  make <target>\n\nTargets:\n"; \
	} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

install-deps: ## Bootstrap system build deps + modern 7zz
	@bash scripts/install-deps.sh

fetch: ## Download the upstream Kimi Work DMG (cached by HTTP fingerprint)
	@./install.sh --fetch-only $(if $(DMG),$(DMG),)

extract: ## Extract the .app bundle from the DMG
	@./install.sh --extract-only $(if $(DMG),$(DMG),)

inspect: ## Analyze app.asar and write inspect-report.json (no conversion)
	@./install.sh --inspect $(if $(DMG),$(DMG),)

build-app: ## Build kimi-app/ (reuses cached DMG)
	@./install.sh $(if $(DMG),$(DMG),)

build-app-fresh: ## Build kimi-app/ after discarding the cached DMG
	@./install.sh --fresh $(if $(DMG),$(DMG),)

package: ## Auto-detect distro and build the native package (.deb for Debian/Ubuntu)
	@bash scripts/build-deb.sh

deb: ## Build a .deb into dist/
	@bash scripts/build-deb.sh

appimage: ## Build an AppImage into dist/
	@bash scripts/build-appimage.sh

install: ## Install the latest package from dist/ (needs sudo)
	@if [ -f "$(DIST_DIR)/$(PACKAGE_NAME)_*.deb" ]; then \
		sudo dpkg -i $(DIST_DIR)/$(PACKAGE_NAME)_*.deb || sudo apt-get -f install -y; \
	else echo "No package found in $(DIST_DIR). Run 'make deb' first."; fi

run-app: ## Launch the generated kimi-app
	@"$(APP_DIR)/start.sh"

bootstrap: ## One-shot: install latest Kimi Work (deps → build → package → install)
	@bash scripts/install-latest.sh $(if $(filter-out bootstrap,$(MAKECMDGOALS)),$(MAKECMDGOALS),)

clean: ## Remove generated app, work dirs and dist artifacts
	@rm -rf "$(APP_DIR)" app-extracted dmg-extract "$(DIST_DIR)" work
	@rm -f inspect-report.json patch-report.json build-info.json
	@echo "cleaned."
