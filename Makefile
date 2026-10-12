TOFU       ?= tofu
INFRA_DIR  := infra/local
KUBECONFIG := $(abspath $(INFRA_DIR)/.kubeconfig)

.PHONY: help infra-init infra-plan infra-up infra-down infra-status fmt validate

help:
	@echo "infra-up      create the local kind cluster"
	@echo "infra-down    destroy the local kind cluster"
	@echo "infra-status  show nodes, pools and taints"
	@echo "infra-plan    show planned changes"
	@echo "fmt           format OpenTofu code"
	@echo "validate      validate OpenTofu code"

infra-init:
	$(TOFU) -chdir=$(INFRA_DIR) init

infra-plan: infra-init
	$(TOFU) -chdir=$(INFRA_DIR) plan

infra-up: infra-init
	$(TOFU) -chdir=$(INFRA_DIR) apply -auto-approve
	@echo
	@echo "export KUBECONFIG=$(KUBECONFIG)"

infra-down:
	$(TOFU) -chdir=$(INFRA_DIR) destroy -auto-approve

infra-status:
	KUBECONFIG=$(KUBECONFIG) kubectl get nodes -L node-pool,capacity-type
	@echo
	KUBECONFIG=$(KUBECONFIG) kubectl get nodes \
	  -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key'

fmt:
	$(TOFU) fmt -recursive

validate: infra-init
	$(TOFU) -chdir=$(INFRA_DIR) validate
