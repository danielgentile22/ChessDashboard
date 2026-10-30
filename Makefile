# Chess Dashboard — Developer Makefile
# Usage: make <target>
#
# Requires: python3, pip, make

VENV      := .venv
PYTHON    := $(VENV)/bin/python
PIP       := $(VENV)/bin/pip
PYTEST    := $(VENV)/bin/pytest
RUFF      := $(VENV)/bin/ruff
STUDY     ?= abcdWXYZ

.PHONY: help venv install install-dev run demo test lint fix typecheck clean docker docker-up \
	ios-codegen ios-generate ios-build ios-build-release ios-test kit-test

# iOS (ios/). `xcrun simctl list devices available` lists simulator names.
SIM_NAME  ?= iPhone 17
SIM       ?= platform=iOS Simulator,name=$(SIM_NAME)
IOS_PROJ  := ios/ChessDashboard.xcodeproj
IOS_FLAGS := -project $(IOS_PROJ) -scheme ChessDashboard -derivedDataPath ios/build/DerivedData

help:          ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*##' Makefile | awk 'BEGIN{FS=":.*##"}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

venv:          ## Create Python virtual environment
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip

install: venv  ## Install runtime dependencies
	$(PIP) install -r requirements.txt

install-dev: venv  ## Install runtime + dev dependencies
	$(PIP) install -r requirements-dev.txt

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
