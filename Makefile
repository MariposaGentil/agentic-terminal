# agentic-terminal — convenience wrapper around run.sh and the scripts/ toolkit.
# Run `make` or `make help` to list targets.

SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

# Optional args:
#   make read LINES=500
#   make send CMD='ls -la'
LINES ?=
CMD   ?=

.PHONY: help run setup install-deps start stop read send requests test

help: ## Show this help
	@echo "agentic-terminal — available targets:"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Args: make read LINES=500 | make send CMD='ls -la'"

run: ## Verify environment, then launch agent + terminal (setup + start)
	@./run.sh

setup: ## Verify prerequisites and make the toolkit executable
	@./scripts/setup.sh

install-deps: ## Verify prerequisites and apt-install missing ones
	@./scripts/setup.sh --install-deps

start: ## Create both tmux sessions and open the term window
	@./scripts/start.sh

stop: ## Tear down both tmux sessions
	@./scripts/stop.sh

read: ## Snapshot the term pane (optional: LINES=N)
	@./scripts/read.sh $(LINES)

send: ## Send a command to term (requires CMD='...')
	@if [ -z "$(CMD)" ]; then echo "Usage: make send CMD='ls -la'" >&2; exit 1; fi
	@printf '%s' "$(CMD)" | ./scripts/send.sh

requests: ## Print unprocessed comment-prompts from term
	@./scripts/requests.sh

test: ## Run the test suite (tests/)
	@bash tests/run.sh
