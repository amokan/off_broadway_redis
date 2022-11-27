# Boilerplate Elixir Project Makefile
# ---------------------------------------------------------------------------------
# Adjust to fit your needs.
#
# It is assumed that the user has `asdf` installed. See https://asdf-vm.com.
# ---------------------------------------------------------------------------------

# Build configuration variables
# -------------------
APP_NAME = `grep -Eo '@app_name :\w*' mix.exs | cut -d ':' -f 2`
APP_VERSION = `grep -Eo '@version "[0-9\.]*"' mix.exs | cut -d '"' -f 2`
GIT_REVISION = `git rev-parse HEAD`

ASDF_VERSION = `asdf version | sed 's/v//'`
ASDF_PATH = `which asdf`
NEEDED_ELIXIR_VERSION = `grep 'elixir' .tool-versions | sed 's/elixir//' | sed 's/-otp.*//'`
CURRENT_ELIXIR_VERSION = `asdf current elixir | sed 's/elixir//' | sed 's/-otp.*//'`
CURRENT_OTP_VERSION = `asdf current elixir | sed 's/elixir//' | sed 's/\/.*//' | cut -d- -f3`
NEEDED_OTP_VERSION = `grep 'elixir' .tool-versions | cut -d- -f3`
NEEDED_ERLANG_VERSION = `grep 'erlang' .tool-versions | sed 's/erlang//'`
CURRENT_ERLANG_VERSION = `asdf current erlang | sed 's/erlang//' | sed 's/\/.*//'`

# Misc
# ---------------------
NC = $(\033[0m) # reset color

# Introspection targets
# ---------------------

.PHONY: help
help: header targets

.PHONY: header
header:
	@echo ""
	@echo "\033[34mEnvironment${NC}"
	@echo "\033[34m_______________________________________________________________${NC}"
	@printf "\033[33m%-23s${NC}" "APP_NAME"
	@printf "\033[35m%s${NC}" $(APP_NAME)
	@echo ""
	@printf "\033[33m%-23s${NC}" "APP_VERSION"
	@printf "\033[35m%s${NC}" $(APP_VERSION)
	@echo ""
	@printf "\033[33m%-23s${NC}" "GIT_REVISION"
	@printf "\033[35m%s${NC}" $(GIT_REVISION)
	@echo ""
	@printf "\033[33m%-23s${NC}" "OTP_VERSION"
	@printf "\033[35m%s (\e[3m\033[36m%s\e[0m\033[35m)${NC}" $(NEEDED_OTP_VERSION) $(CURRENT_OTP_VERSION)
	@echo ""
	@printf "\033[33m%-23s${NC}" "ELIXIR_VERSION"
	@printf "\033[35m%s (\e[3m\033[36m%s\e[0m\033[35m)${NC}" $(NEEDED_ELIXIR_VERSION) $(CURRENT_ELIXIR_VERSION)
	@echo ""
	@printf "\033[33m%-23s${NC}" "ERLANG_VERSION"
	@printf "\033[35m%s (\e[3m\033[36m%s\e[0m\033[35m)${NC}" $(NEEDED_ERLANG_VERSION) $(CURRENT_ERLANG_VERSION)
	@echo ""
	@printf "\033[33m%-23s${NC}" "ASDF_VERSION"
	@printf "\033[35m%s${NC}" $(ASDF_VERSION)
	@echo ""
	@printf "\033[33m%-23s${NC}" "ASDF_PATH"
	@printf "\033[35m%s${NC}" $(ASDF_PATH)
	@echo ""
	@echo "\n"

.PHONY: targets
targets:
	@echo "\033[34mTargets${NC}"
	@echo "\033[34m_______________________________________________________________${NC}"
	@perl -nle'print $& if m{^[a-zA-Z_-\d]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s${NC} %s\n", $$1, $$2}'
	@echo ""

# Prepare release targets
# -------------

.PHONY: prepare-release
prepare-release: ## Prepares a release by generating a `RELEASE.md` file
	@printf 'RELEASE_TYPE: patch\n\n- Fixed x\n- Added y' > RELEASE.md
	@echo "Created \`RELEASE.md\`. Adjust the file to meet your needs before continuing"

.PHONY: prepare-release-patch
prepare-release-patch: prepare-release

.PHONY: prepare-release-minor
prepare-release-minor:
	@printf 'RELEASE_TYPE: minor\n\n- Fixed x\n- Added y' > RELEASE.md
	@echo "Created \`RELEASE.md\`. Adjust the file to meet your needs before continuing"

.PHONY: prepare-release-major
prepare-release-major:
	@printf 'RELEASE_TYPE: major\n\n- Fixed x\n- Added y' > RELEASE.md
	@echo "Created \`RELEASE.md\`. Adjust the file to meet your needs before continuing"

.PHONY: bump
bump: ## Bumps the application version and updates the `CHANGELOG.md` file.
	mix bump

.PHONY: git-push
git-push: ## Pushes an updated git commit to `origin main` with updated tags
	git push origin main --tags

# Development targets
# -------------------
.PHONY: dev-setup
dev-setup: install-tooling deps ## Setup local development environment

.PHONY: install-tooling
install-tooling:
	asdf install

.PHONY: deps
deps: ## Install dependencies
	mix deps.get
	mix deps.compile

.PHONY: run
run: ## Run the project inside an IEx shell
	iex -S mix

.PHONY: test
test: ## Run the test suite
	mix test

# Check, lint and format targets
# ------------------------------
.PHONY: check
check: check-format lint deps-check-unused deps-check-security deps-check-outdated check-code-coverage ## Run various checks on project files

.PHONY: check-code-coverage
check-code-coverage:
	mix coveralls

.PHONY: check-format
check-format:
	mix format --check-formatted

.PHONY: deps-check-outdated
deps-check-outdated: ## Check and list any dependency updates
	mix hex.outdated

.PHONY: deps-check-security
deps-check-security:
	mix deps.audit

.PHONY: deps-check-unused
deps-check-unused:
	mix deps.unlock --check-unused

.PHONY: deps-tree
deps-tree: ## Displays the dependency tree
	mix deps.tree

.PHONY: format
format: ## Format project files
	mix format

.PHONY: lint
lint: lint-elixir ## Lint project files

.PHONY: lint-elixir
lint-elixir:
	mix compile --warnings-as-errors --force
	mix credo --strict
