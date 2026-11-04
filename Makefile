# agentic-terminal — convenience wrapper around run.sh and the scripts/ toolkit.
# Run `make` or `make help` to list targets.

SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

# Optional args:
#   make read LINES=500
#   make send CMD='ls -la'
LINES ?=
CMD   ?=

.PHONY: help run setup install-deps start stop read send requests test watch-status reload-watcher stop-watcher ping-selftest

help: ## Show this help
	@echo "agentic-terminal — available targets:"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Args: make read LINES=500 | make send CMD='ls -la'"

run: ## Verify environment, then launch agent + terminal (setup + start)
	@SESSION_CWD="$${SESSION_CWD:-$$PWD}" TERM_CWD="$${TERM_CWD:-$$SESSION_CWD}" ./run.sh

setup: ## Verify prerequisites and make the toolkit executable
	@./scripts/setup.sh

install-deps: ## Verify prerequisites and apt-install missing ones
	@./scripts/setup.sh --install-deps

start: ## Create both tmux sessions and open the term window
	@SESSION_CWD="$${SESSION_CWD:-$$PWD}" TERM_CWD="$${TERM_CWD:-$$SESSION_CWD}" ./scripts/start.sh

stop: ## Tear down both tmux sessions
	@./scripts/stop.sh

read: ## Snapshot the term pane (optional: LINES=N)
	@./scripts/read.sh $(LINES)

send: ## Send a command to term (requires CMD='...')
	@if [ -z "$(CMD)" ]; then echo "Usage: make send CMD='ls -la'" >&2; exit 1; fi
	@printf '%s' "$(CMD)" | ./scripts/send.sh

requests: ## Print unprocessed comment-prompts from term
	@./scripts/requests.sh

watch-status: ## Diagnose the term watcher / auto-ping (healthy?)
	@./scripts/watch.sh status

reload-watcher: ## Repair + verify auto-ping (re-attach, dedupe, self-test)
	@./scripts/watch.sh reload

ping-selftest: ## Prove a '# comment' is detected and pings the agent
	@./scripts/watch.sh selftest

stop-watcher: ## Detach the term watcher (turns auto-ping off)
	@./scripts/watch.sh stop

test: ## Run the test suite (tests/)
	@bash tests/run.sh
