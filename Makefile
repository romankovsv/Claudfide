# Developer entry points. Everything here runs without cloud credentials.
#
#   make test          bats suites for the scripts + terraform tests of every unit
#   make verify        fmt / validate / terraform test for every unit (what CI's verify job runs)
#   make lint          shellcheck + actionlint
#   make agent         run the test agent locally against the current branch (vs main)
#   make agent-all     run a full coverage pass over every unit
#   make clean         remove generated output

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: test test-scripts verify lint agent agent-all clean

test: test-scripts verify

test-scripts:
	bats tests/scripts

verify:
	scripts/verify.sh --out .verify-out

lint:
	shellcheck -S style scripts/*.sh tests/scripts/helpers.bash
	python3 -m py_compile scripts/*.py
	actionlint

agent:
	scripts/run-agent-local.sh --base $${BASE:-main}

agent-all:
	scripts/run-agent-local.sh --all

clean:
	rm -rf .verify-out .tf-test-agent
	find modules stacks -type d -name .terraform -prune -exec rm -rf {} +
