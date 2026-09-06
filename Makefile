CACHE_HOME ?= $(if $(XDG_CACHE_HOME),$(XDG_CACHE_HOME),$(HOME)/.cache)/beam-deck/dev
MIX_ENV_VARS = MIX_BUILD_PATH="$(CACHE_HOME)/_build" MIX_DEPS_PATH="$(CACHE_HOME)/deps"

.PHONY: static deps format test integration protocol credo dialyzer lint check

static:
	./test/static.sh

deps:
	cd daemon && $(MIX_ENV_VARS) mix deps.get

format:
	cd daemon && $(MIX_ENV_VARS) mix format

test:
	cd daemon && $(MIX_ENV_VARS) mix test

integration:
	cd daemon && $(MIX_ENV_VARS) BEAM_DECK_INTEGRATION=1 mix test

protocol:
	python3 test/live-protocol.py

credo:
	cd daemon && $(MIX_ENV_VARS) mix credo --strict

dialyzer:
	cd daemon && $(MIX_ENV_VARS) mix dialyzer

lint: credo dialyzer

check: static
	@if command -v mix >/dev/null 2>&1; then \
		cd daemon && $(MIX_ENV_VARS) mix deps.get && $(MIX_ENV_VARS) mix format --check-formatted && $(MIX_ENV_VARS) MIX_ENV=test mix compile --warnings-as-errors && $(MIX_ENV_VARS) mix test && $(MIX_ENV_VARS) BEAM_DECK_INTEGRATION=1 mix test && $(MIX_ENV_VARS) mix credo --strict && $(MIX_ENV_VARS) mix dialyzer && cd .. && python3 test/live-protocol.py; \
	else \
		echo "ERROR: mix not on PATH; release validation has NOT passed. Run make static separately." >&2; exit 127; \
	fi
