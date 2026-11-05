GODOT ?= godot
RUN := $(GODOT) --headless --path .

.PHONY: setup check test smoke art export-web run-server

setup: ## import the project (first run, or after adding assets)
	@$(RUN) --import >/dev/null 2>&1 || $(RUN) --import

test: setup ## unit and state tests
	@$(RUN) -s res://tests/run_tests.gd

smoke: setup ## headless server + clients: join, move, disconnect, reconnect
	@GODOT="$(GODOT)" tools/smoke.sh

check: test smoke ## everything CI requires

art: ## regenerate assets/*.png from art/gen_art.gd
	@$(RUN) -s res://art/gen_art.gd

export-web: setup ## web build into build/web/
	@mkdir -p build/web
	@$(RUN) --export-release "Web" build/web/index.html

run-server: setup ## local server on :9000 with build/dev.db
	@mkdir -p build
	@$(RUN) -- --server --port 9000 --db build/dev.db
