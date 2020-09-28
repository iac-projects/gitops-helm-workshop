
.ONESHELL:
.SHELL := /bin/sh
.DEFAULT_GOAL := help
CURRENT_FOLDER=$(shell basename "$$(pwd)")
BOLD=$(shell tput bold)
RED=$(shell tput setaf 1)
RESET=$(shell tput sgr0)
REPO=git@github.com:iac-projects/gitops-helm-workshop
MSG?="up"


## Burn, baby, burn
help: ## Shows this makefile help
	@echo ""
	@echo "gitops-linkerd!"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

PHONY: all
all: deploy
	@echo "Setting up local environment"



PHONY: sync
sync:
	git add -A && git commit -m $(MSG) && git push origin master
	fluxctl --k8s-fwd-ns=fluxcd sync


PHONY: deploy
deploy:
	chmod a+x scripts/*.sh ; \
	./scripts/flux-init.sh $(REPO)

PHONY: start
start:
	minikube start

PHONY: destroy
destroy:
	minikube delete  --all --purge

