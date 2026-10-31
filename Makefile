# Chess Dashboard — Developer Makefile
# Usage: make <target>
#
# Requires: uv, make. Python is pinned in .python-version (CI's version); uv
# fetches it, so the venv is the same in any checkout or worktree.

VENV      := .venv
PYTHON    := $(VENV)/bin/python
PYTEST    := $(VENV)/bin/pytest
RUFF      := $(VENV)/bin/ruff
STUDY     ?= abcdWXYZ
SCREEN    ?= overview
OUT       ?= ios/build/shot-$(SCREEN).png

.PHONY: help install install-dev run demo check test lint fix typecheck clean docker docker-up \
	ios-codegen ios-generate ios-build ios-build-release ios-test kit-test ios-testflight ios-shot

# iOS (ios/). `xcrun simctl list devices available` lists simulator names.
SIM_NAME  ?= iPhone 17
SIM       ?= platform=iOS Simulator,name=$(SIM_NAME)
IOS_PROJ  := ios/ChessDashboard.xcodeproj
IOS_FLAGS := -project $(IOS_PROJ) -scheme ChessDashboard -derivedDataPath ios/build/DerivedData

help:          ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*##' Makefile | awk 'BEGIN{FS=":.*##"}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

# The venv is a file target: built once with the pinned Python, rebuilt when
# the pin changes. The stamps reinstall only when a requirements file changes.
$(VENV)/pyvenv.cfg: .python-version
	rm -rf $(VENV)
	uv venv --quiet --python "$$(cat .python-version)" $(VENV)

$(VENV)/.installed: $(VENV)/pyvenv.cfg requirements.txt
	uv pip install --quiet --python $(PYTHON) -r requirements.txt
	touch $@

$(VENV)/.installed-dev: $(VENV)/pyvenv.cfg requirements.txt requirements-dev.txt
	uv pip install --quiet --python $(PYTHON) -r requirements-dev.txt
	touch $@

install: $(VENV)/.installed  ## Install runtime dependencies

install-dev: $(VENV)/.installed-dev  ## Install runtime + dev dependencies

check: lint typecheck test  ## Everything CI's lint, typecheck and test jobs run

run: install   ## Start the dashboard locally
	$(PYTHON) app.py --study $(STUDY)

demo: install  ## Start the dashboard from the committed PGN cache
	$(PYTHON) app.py --demo

run-debug: install  ## Start with hot-reload debug mode
	$(PYTHON) app.py --study $(STUDY) --debug

test: install-dev  ## Run the test suite
	$(PYTEST) tests/ --cov --cov-report=term-missing --cov-fail-under=92

lint: install-dev  ## Lint with ruff (check-only, mirrors CI)
	$(RUFF) check .

fix: install-dev  ## Auto-fix lint violations with ruff
	$(RUFF) check . --fix

typecheck: install-dev  ## Type check with mypy
	$(VENV)/bin/mypy

clean:         ## Remove virtual environment and caches
	rm -rf $(VENV) __pycache__ .pytest_cache .mypy_cache .ruff_cache

docker:        ## Build the Docker image
	docker build -t chess-dashboard .

docker-up:     ## Run the dashboard in Docker
	docker compose up --build

ios-codegen:   ## Regenerate the Swift API types (openapi/v1.json) and theme tokens (styles.THEME)
	$(PYTHON) ios/scripts/gen_api_types.py
	$(PYTHON) ios/scripts/gen_theme.py

ios-generate:  ## Generate the Xcode project from ios/project.yml (xcodegen)
	cd ios && xcodegen generate --quiet

ios-build: ios-generate  ## Debug build for a simulator (SIM_NAME=...)
	set -o pipefail; xcodebuild build $(IOS_FLAGS) -destination '$(SIM)' | tail -5

ios-build-release: ios-generate  ## Release build for any simulator (no signing)
	set -o pipefail; xcodebuild build $(IOS_FLAGS) -configuration Release \
		-destination 'generic/platform=iOS Simulator' | tail -5

ios-test: ios-generate  ## The ChessDashboardKit tests on a simulator (SIM_NAME=...)
	set -o pipefail; xcodebuild test $(IOS_FLAGS) -destination '$(SIM)' | tail -20

kit-test:      ## The ChessDashboardKit tests on the Mac, in seconds (swift test)
	cd ios/ChessDashboardKit && swift test

ios-shot:      ## Screenshot one screen on a simulator from fixtures (SCREEN=overview OUT=shot.png)
	ios/scripts/shot.sh $(SCREEN) $(OUT)

ios-testflight:  ## Archive, sign and upload a TestFlight build (ios/testflight.sh; reads .env)
	ios/testflight.sh
