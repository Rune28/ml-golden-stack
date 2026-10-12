TOFU         ?= tofu
INFRA_DIR    := infra/local
PLATFORM_DIR := infra/platform
KUBECONFIG   := $(abspath $(INFRA_DIR)/.kubeconfig)

.PHONY: help infra-init infra-plan infra-up infra-down infra-status \
        platform-init platform-plan platform-up platform-down platform-status \
        fmt validate

help:
	@echo "infra-up         create the local kind cluster"
	@echo "infra-down       destroy the local kind cluster"
	@echo "infra-status     show nodes, pools and taints"
	@echo "infra-plan       show planned changes to the cluster"
	@echo "platform-up      install platform services (Temporal) into the cluster"
	@echo "platform-down    uninstall platform services"
	@echo "platform-status  show platform pods"
	@echo "platform-plan    show planned changes to platform services"
	@echo "fmt              format OpenTofu code"
	@echo "validate         validate OpenTofu code"

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

platform-init:
	$(TOFU) -chdir=$(PLATFORM_DIR) init

platform-plan: platform-init
	$(TOFU) -chdir=$(PLATFORM_DIR) plan

platform-up: platform-init
	$(TOFU) -chdir=$(PLATFORM_DIR) apply -auto-approve

platform-down:
	$(TOFU) -chdir=$(PLATFORM_DIR) destroy -auto-approve

platform-status:
	KUBECONFIG=$(KUBECONFIG) kubectl get pods -n temporal -o wide

fmt:
	$(TOFU) fmt -recursive

validate: infra-init platform-init
	$(TOFU) -chdir=$(INFRA_DIR) validate
	$(TOFU) -chdir=$(PLATFORM_DIR) validate
