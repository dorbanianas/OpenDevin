# Makefile for OpenDevin project

# Variables
DOCKER_IMAGE = ghcr.io/opendevin/sandbox
BACKEND_PORT = 3000
BACKEND_HOST = "127.0.0.1:$(BACKEND_PORT)"
FRONTEND_PORT = 3001
DEFAULT_WORKSPACE_DIR = "./workspace"
DEFAULT_MODEL = "gpt-4-0125-preview"
CONFIG_FILE = config.toml
PRECOMMIT_CONFIG_PATH = "./dev_config/python/.pre-commit-config.yaml"

# ANSI color codes
GREEN=\033[0;32m
YELLOW=\033[0;33m
RED=\033[0;31m
BLUE=\033[0;34m
RESET=\033[0m

# Build
build:
	@echo "$(GREEN)Building project...$(RESET)"
	@echo "$(YELLOW)Checking Python installation...$(RESET)"
	@if command -v python3 > /dev/null; then \
		echo "$(BLUE)$(shell python3 --version) is already installed.$(RESET)"; \
	else \
		echo "$(RED)Python 3 is not installed. Please install Python 3 to continue.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Checking npm installation...$(RESET)"
	@if command -v npm > /dev/null; then \
		echo "$(BLUE)npm $(shell npm --version) is already installed.$(RESET)"; \
	else \
		echo "$(RED)npm is not installed. Please install Node.js to continue.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Checking Docker installation...$(RESET)"
	@if command -v docker > /dev/null; then \
		echo "$(BLUE)$(shell docker --version) is already installed.$(RESET)"; \
	else \
		echo "$(RED)Docker is not installed. Please install Docker to continue.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Installing Python dependencies...$(RESET)"
	@if command -v poetry > /dev/null; then \
		echo "$(BLUE)Poetry is already installed.$(RESET)"; \
	else \
		echo "$(YELLOW)Poetry is not installed. You can install poetry by running the following command, then adding Poetry to your PATH:"; \
		echo "$(YELLOW) curl -sSL https://install.python-poetry.org | python3 -$(RESET)"; \
		echo "$(YELLOW)More detail here: https://python-poetry.org/docs/#installing-with-the-official-installer$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Pulling Docker image...$(RESET)"
	@docker pull $(DOCKER_IMAGE)
	@if [ "$(shell uname)" = "Darwin" ]; then \
		echo "$(BLUE)Installing `chroma-hnswlib`...$(RESET)"; \
		export HNSWLIB_NO_NATIVE=1; \
		poetry run pip install chroma-hnswlib; \
	fi
	@poetry install --without evaluation
	@echo "$(GREEN)Activating Poetry shell...$(RESET)"
	@echo "$(GREEN)Setting up frontend environment...$(RESET)"
	@echo "$(YELLOW)Detect Node.js version...$(RESET)"
	@cd frontend && node ./scripts/detect-node-version.js
	@cd frontend && \
		echo "$(BLUE)Installing frontend dependencies with npm...$(RESET)" && \
		npm install && \
		echo "$(BLUE)Running make-i18n with npm...$(RESET)" && \
		npm run make-i18n
	@echo "$(GREEN)Installing pre-commit hooks...$(RESET)"
	@git config --unset-all core.hooksPath || true
	@poetry run pre-commit install --config $(PRECOMMIT_CONFIG_PATH)
	@echo "$(GREEN)Build completed successfully.$(RESET)"

# Start backend
start-backend:
	@echo "$(GREEN)Starting backend...$(RESET)"
	@poetry run uvicorn opendevin.server.listen:app --port $(BACKEND_PORT)

# Start frontend
start-frontend:
	@echo "$(GREEN)Starting frontend...$(RESET)"
	@cd frontend && BACKEND_HOST=$(BACKEND_HOST) FRONTEND_PORT=$(FRONTEND_PORT) npm run start

# Run the app
run:
	@echo "$(GREEN)Running the app...$(RESET)"
	@if [ "$(OS)" = "Windows_NT" ]; then \
		echo "$(RED)`make run` is not supported on Windows. Please run `make start-frontend` and `make start-backend` separately.$(RESET)"; \
		exit 1; \
	fi
	@mkdir -p logs
	@poetry run nohup uvicorn opendevin.server.listen:app --port $(BACKEND_PORT) > logs/backend_$(shell date +'%Y%m%d_%H%M%S').log 2>&1 &
	@echo "$(YELLOW)Waiting for the backend to start...$(RESET)"
	@until nc -z localhost $(BACKEND_PORT); do sleep 0.1; done
	@echo "$(GREEN)Backend started successfully.$(RESET)"
	@cd frontend && echo "$(BLUE)Starting frontend with npm...$(RESET)" && npm run start -- --port $(FRONTEND_PORT)
	@echo "$(GREEN)Application started successfully.$(RESET)"

# Setup config.toml
setup-config:
	@echo "$(GREEN)Setting up config.toml...$(RESET)"
	@read -p "Enter your LLM Model name (see https://docs.litellm.ai/docs/providers for full list) [default: $(DEFAULT_MODEL)]: " llm_model; \
	 llm_model=$${llm_model:-$(DEFAULT_MODEL)}; \
	 echo "LLM_MODEL=\"$$llm_model\"" > $(CONFIG_FILE).tmp

	@read -p "Enter your LLM API key: " llm_api_key; \
	 echo "LLM_API_KEY=\"$$llm_api_key\"" >> $(CONFIG_FILE).tmp

	@read -p "Enter your LLM Base URL [mostly used for local LLMs, leave blank if not needed - example: http://localhost:5001/v1/]: " llm_base_url; \
	 if [[ ! -z "$$llm_base_url" ]]; then echo "LLM_BASE_URL=\"$$llm_base_url\"" >> $(CONFIG_FILE).tmp; fi

	@echo "Enter your LLM Embedding Model\nChoices are openai, azureopenai, llama2 or leave blank to default to 'BAAI/bge-small-en-v1.5' via huggingface"; \
	 read -p "> " llm_embedding_model; \
	 	echo "LLM_EMBEDDING_MODEL=\"$$llm_embedding_model\"" >> $(CONFIG_FILE).tmp; \
		if [ "$$llm_embedding_model" = "llama2" ]; then \
			read -p "Enter the local model URL (will overwrite LLM_BASE_URL): " llm_base_url; \
				echo "LLM_BASE_URL=\"$$llm_base_url\"" >> $(CONFIG_FILE).tmp; \
		elif [ "$$llm_embedding_model" = "azureopenai" ]; then \
			read -p "Enter the Azure endpoint URL (will overwrite LLM_BASE_URL): " llm_base_url; \
				echo "LLM_BASE_URL=\"$$llm_base_url\"" >> $(CONFIG_FILE).tmp; \
			read -p "Enter the Azure LLM Deployment Name: " llm_deployment_name; \
				echo "LLM_DEPLOYMENT_NAME=\"$$llm_deployment_name\"" >> $(CONFIG_FILE).tmp; \
			read -p "Enter the Azure API Version: " llm_api_version; \
				echo "LLM_API_VERSION=\"$$llm_api_version\"" >> $(CONFIG_FILE).tmp; \
		fi

	@read -p "Enter your workspace directory [default: $(DEFAULT_WORKSPACE_DIR)]: " workspace_dir; \
	 workspace_dir=$${workspace_dir:-$(DEFAULT_WORKSPACE_DIR)}; \
	 echo "WORKSPACE_DIR=\"$$workspace_dir\"" >> $(CONFIG_FILE).tmp

	@mv $(CONFIG_FILE).tmp $(CONFIG_FILE)
	@echo "$(GREEN)Config.toml setup completed.$(RESET)"

# Help
help:
	@echo "$(BLUE)Usage: make [target]$(RESET)"
	@echo "Targets:"
	@echo "  $(GREEN)build$(RESET)               - Build project, including environment setup and dependencies."
	@echo "  $(GREEN)build-eval$(RESET)          - Build project evaluation pipeline, including environment setup and dependencies."
	@echo "  $(GREEN)start-backend$(RESET)       - Start the backend server for the OpenDevin project."
	@echo "  $(GREEN)start-frontend$(RESET)      - Start the frontend server for the OpenDevin project."
	@echo "  $(GREEN)run$(RESET)                 - Run the OpenDevin application, starting both backend and frontend servers."
	@echo "                        Backend Log file will be stored in the 'logs' directory."
	@echo "  $(GREEN)setup-config$(RESET)        - Setup the configuration for OpenDevin by providing LLM API key,"
	@echo "                        LLM Model name, and workspace directory."
	@echo "  $(GREEN)help$(RESET)                - Display this help message, providing information on available targets."

# Phony targets
.PHONY: build build-eval start-backend start-frontend run setup-config help
