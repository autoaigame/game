GODOT ?= godot
RUN := $(GODOT) --headless --path .

.PHONY: setup check test smoke art export-web run-server part check-part

setup: ## import the project (first run, or after adding assets)
	@$(RUN) --import >/dev/null 2>&1 || $(RUN) --import

test: setup ## unit and state tests
	@$(RUN) -s res://tests/run_tests.gd

smoke: setup ## headless server + clients: join, move, disconnect, reconnect
	@GODOT="$(GODOT)" tools/smoke.sh

check: test smoke ## everything CI requires

art: ## regenerate assets/*.png from art/gen_art.gd
	@$(RUN) -s res://art/gen_art.gd

BLENDER ?= blender

part: ## build one character part: make part ID=<id> [BLEND=1] (Blender for volumes, Python for faces)
	@test -n "$(ID)" || { echo "usage: make part ID=<id>"; exit 2; }
	@if [ -f art/character/faces/$(ID).txt ]; then python3 art/character/faces.py .; \
	else mkdir -p build/parts && touch build/parts/.gdignore && $(BLENDER) -b --python-exit-code 1 --python art/character/parts/$(ID).py $(if $(BLEND),-- --blend) \
		> build/parts/$(ID).log 2>&1 && grep "^## " build/parts/$(ID).log || { tail -30 build/parts/$(ID).log; exit 1; }; fi
	@$(RUN) --import >/dev/null 2>&1 || $(RUN) --import

check-part: setup ## check one character part against the standard and draw its sheet: make check-part ID=<id>
	@test -n "$(ID)" || { echo "usage: make check-part ID=<id>"; exit 2; }
	@$(RUN) -s res://tools/check_part.gd -- $(ID)
	@mkdir -p build/parts && touch build/parts/.gdignore
	@$(GODOT) --path . --rendering-driver opengl3 --resolution 1280x720 -s res://tools/part_sheet.gd -- $(ID) build/parts/$(ID)_sheet.png \
		|| echo "no sheet: rendering needs a display (on Linux without one: xvfb-run make check-part ID=$(ID))"

export-web: setup ## web build into build/web/
	@mkdir -p build/web
	@$(RUN) --export-release "Web" build/web/index.html

run-server: setup ## local server on :9000 with build/dev.db
	@mkdir -p build
	@$(RUN) -- --server --port 9000 --db build/dev.db
