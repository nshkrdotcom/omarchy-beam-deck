.PHONY: static deps format test integration credo dialyzer lint check

static:
	./test/static.sh

deps:
	cd daemon && mix deps.get

format:
	cd daemon && mix format

test:
	cd daemon && mix test

integration:
	cd daemon && BEAM_DECK_INTEGRATION=1 mix test

credo:
	cd daemon && mix credo --strict

dialyzer:
	cd daemon && mix dialyzer

lint: credo dialyzer

check: static
	@if command -v mix >/dev/null 2>&1; then \
		cd daemon && mix deps.get && mix format --check-formatted && MIX_ENV=test mix compile --warnings-as-errors && mix test && BEAM_DECK_INTEGRATION=1 mix test && mix credo --strict && mix dialyzer; \
	else \
		echo "mix not on PATH: BEAM test/lint suite not executed"; \
	fi
