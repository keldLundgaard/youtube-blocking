.PHONY: clean install format lint test sync-project-name check update-deps

#################################################################################
# GLOBALS                                                                       #
#################################################################################
PROJECT_DIR=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
PROJECT_NAME=$(shell basename $(PROJECT_DIR))
PYTHONVERSION=3.10
VENV_DIR=.venv-$(PROJECT_NAME)  # Using standard characters
PIP=$(VENV_DIR)/bin/pip

#################################################################################
# COMMANDS                                                                      #
#################################################################################
## Create virtual environment using uv
create_environment:
	@echo "Creating virtual environment with uv..."
	@command -v uv >/dev/null 2>&1 || { \
		echo "uv is not installed. Installing uv..."; \
		curl -LsSf https://astral.sh/uv/install.sh | sh; \
	}
	uv venv $(VENV_DIR) --python=$(PYTHONVERSION)
	make sync-project-configs
	@echo "Virtual environment created at $(VENV_DIR)"
	@echo "To activate: source $(VENV_DIR)/bin/activate"

## Sync project configurations (name and Python version)
sync-project-configs:
	@echo "Updating project configurations..."
	@if [ -f pyproject.toml ]; then \
		cp pyproject.toml pyproject.toml.bak && \
		sed -i.tmp \
			-e 's/PROJECT_NAME_PLACEHOLDER/$(PROJECT_NAME)/' \
			-e 's/PYTHON_VERSION_PLACEHOLDER/$(PYTHONVERSION)/' \
			-e 's/pyPYVERSION_SHORT/py'"$(shell echo $(PYTHONVERSION) | sed 's/\.[0-9]*$$//')"'/' \
			pyproject.toml && \
		rm -f pyproject.toml.tmp && \
		echo "Successfully updated pyproject.toml" || \
		{ echo "Error updating pyproject.toml"; mv pyproject.toml.bak pyproject.toml; exit 1; }; \
	else \
		echo "pyproject.toml not found!"; \
		exit 1; \
	fi

## Install project dependencies
install: sync-project-configs
	@echo "Installing project with uv..."
	uv pip install -e ".[dev]"
	make make_jupyter_kernel
	@if [ ! -f .pre-commit-config.yaml ]; then \
		make setup-pre-commit; \
	fi

## Setup pre-commit hooks
setup-pre-commit:
	@echo "Setting up pre-commit hooks..."
	@echo "\
repos:\
-   repo: https://github.com/pre-commit/pre-commit-hooks\
    rev: v4.5.0\
    hooks:\
    -   id: trailing-whitespace\
    -   id: end-of-file-fixer\
    -   id: check-yaml\
    -   id: check-added-large-files\
-   repo: https://github.com/psf/black\
    rev: 23.12.1\
    hooks:\
    -   id: black\
-   repo: https://github.com/astral-sh/ruff-pre-commit\
    rev: v0.1.9\
    hooks:\
    -   id: ruff\
        args: [--fix]\
-   repo: https://github.com/pre-commit/mirrors-mypy\
    rev: v1.8.0\
    hooks:\
    -   id: mypy\
        additional_dependencies: [types-all]" > .pre-commit-config.yaml
	$(PYTHON) -m pre_commit install

## Install jupyter kernel for the project
make_jupyter_kernel: 
	$(PYTHON) -m ipykernel install --user --name $(PROJECT_NAME) --display-name $(PROJECT_NAME)

## Format code using black
format:
	$(PYTHON) -m black .
	$(PYTHON) -m ruff check . --fix

## Lint code using ruff and mypy
lint:
	$(PYTHON) -m ruff check .
	$(PYTHON) -m mypy .

## Run tests using pytest
test:
	$(PYTHON) -m pytest tests/ --cov=src --cov-report=term-missing

## Run all checks (format, lint, test)
check: format lint test

## Update all dependencies to their latest compatible versions
update-deps:
	@echo "Updating dependencies..."
	uv pip compile pyproject.toml --upgrade --output-file=requirements.lock
	uv pip install -r requirements.lock
	rm requirements.lock
	@echo "Dependencies updated successfully!"

## Export dependencies to requirements.txt (useful for CI/CD)
export-deps:
	@echo "Exporting dependencies to requirements.txt..."
	uv pip list | tail -n +3 | awk '{print $$1 "==" $$2}' > requirements.txt

## Start Jupyter Lab
jupyter:
	$(PYTHON) -m jupyter lab

## Delete all compiled Python files and virtual environment
clean:
	find . -name "*.pyc" -exec rm {} \;
	find . -type d -name "__pycache__" -exec rm -r {} +
	find . -type d -name "*.egg-info" -exec rm -r {} +
	find . -type d -name ".pytest_cache" -exec rm -r {} +
	find . -type d -name ".coverage" -exec rm -r {} +
	find . -type d -name ".ruff_cache" -exec rm -r {} +
	find . -type d -name ".mypy_cache" -exec rm -r {} +
	rm -rf $(VENV_DIR)
	rm -rf .coverage
	rm -rf htmlcov
	@echo "Cleaned up compiled Python files and virtual environment"

## Initialize new project
init:
	@if [ -z "$(version)" ]; then \
		echo "Please provide Python version, e.g., make init version=3.10"; \
		exit 1; \
	fi
	@echo "$(version)" > pyversion
	@echo "Creating initial project structure..."
	mkdir -p src tests
	touch src/__init__.py tests/__init__.py
	make create_environment

#################################################################################
# Self Documenting Commands                                                     #
################################################################################
.DEFAULT_GOAL := show-help

.PHONY: show-help
show-help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) == Darwin && echo '--no-init --raw-control-chars')