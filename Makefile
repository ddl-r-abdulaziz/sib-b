.DEFAULT_GOAL := help

SHELL := bash
.SHELLFLAGS := -o pipefail -ec

BIN_DIR ?= $(CURDIR)/.bin

# until there's a way to add a version check, install from a known checkout
BUNDLE_BINARY_SRC ?= ../bundle

BUNDLE_OUTPUT ?= $(CURDIR)/.bundle

# Picked up by the bundle cli as the default --remote
export BUNDLE_REMOTE ?= http://k3d-test:59918

BUNDLE := $(BIN_DIR)/bundle
CONFIGURE := $(BIN_DIR)/configure

RENDER2_OUTPUT ?= $(CURDIR)/.render2

BUNDLE_SOURCES := bundle.yaml

.PHONY: help
help: ## Show help for common make targets.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Dependencies

.PHONY: deps
deps: $(BUNDLE) $(CONFIGURE) ## Install local build/push tooling into .bin - bundle is sourced from ../bundle

BUNDLE_BINARY_SOURCES := $(shell find $(BUNDLE_BINARY_SRC) -type f -name '*.go') $(BUNDLE_BINARY_SRC)/go.mod $(BUNDLE_BINARY_SRC)/go.sum

$(BUNDLE): $(BUNDLE_BINARY_SOURCES) | $(BIN_DIR)
	cd $(BUNDLE_BINARY_SRC) && go build -o $(BUNDLE) ./cmd/bundle

$(CONFIGURE): $(BUNDLE_BINARY_SOURCES) | $(BIN_DIR)
	cd $(BUNDLE_BINARY_SRC) && go build -o $(CONFIGURE) ./cmd/configure

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

##@ Bundle

# Re-assembles only when bundle.yaml has changed since the last assembly.
$(BUNDLE_OUTPUT): $(BUNDLE_SOURCES)
	rm -rf $(BUNDLE_OUTPUT)
	$(BUNDLE) assemble $(BUNDLE_OUTPUT) --source .
	@touch $(BUNDLE_OUTPUT)

.PHONY: bundle
bundle: $(BUNDLE_OUTPUT) # Assemble the bundle locally into BUNDLE_OUTPUT

.PHONY: push
push: bundle # Assemble (if needed) and push the bundle to BUNDLE_REMOTE
	$(BUNDLE) push --source $(BUNDLE_OUTPUT)

lock.json: push
	$(BUNDLE) lock "$$(jq -r '.name + ":" + .hash' "$(BUNDLE_OUTPUT)/bundle.json")" -o lock.json

.PHONY: lock
lock: lock.json # Push the bundle, then generate lock.json

##@ Configure

# render2 downloads this bundle's and every imported bundle's capabilities
# (resolved transitively via lock.json) into their own subdirectory here.
$(RENDER2_OUTPUT): lock.json
	rm -rf $(RENDER2_OUTPUT)
	$(BUNDLE) render2 --module capabilities=recv lock.json --output $(RENDER2_OUTPUT)
	@touch $(RENDER2_OUTPUT)

.PHONY: configure
configure: $(CONFIGURE) $(RENDER2_OUTPUT) ## Apply base then gatsby to an agent.yaml (stdin) using configure
	echo "" | $(CONFIGURE) $(RENDER2_OUTPUT) --apply base --apply gatsby

.PHONY: clean
clean: ## Ensure all build artifacts and deps are removed
	rm -rf $(BUNDLE_OUTPUT) $(RENDER2_OUTPUT) lock.json
