GODOT ?= godot
RUN := $(GODOT) --headless --path .

.PHONY: setup check test smoke

setup: ## import the project (first run, or after adding assets)
	@$(RUN) --import >/dev/null 2>&1 || $(RUN) --import

test: setup ## unit and state tests
	@$(RUN) -s res://tests/run_tests.gd

smoke: setup ## headless server + clients: join, move, disconnect, reconnect
	@echo "smoke: not implemented yet" && exit 1

check: test ## everything CI requires
