TOFU        ?= tofu
CLUSTER_DIR := infra/clusters/kind
ENV_DIR     := infra/envs/local
KUBECONFIG  := $(abspath $(CLUSTER_DIR)/.kubeconfig)

.PHONY: help infra-init infra-plan infra-up infra-down infra-status \
        platform-init platform-plan platform-up platform-down platform-status \
        preflight fmt validate

help:
	@echo "preflight        check the host (tools, inotify limits, memory)"
	@echo "infra-up         create the local kind cluster (runs preflight first)"
	@echo "infra-down       destroy the local kind cluster (run platform-down first)"
	@echo "infra-status     show nodes, pools, taints and GPUs"
	@echo "infra-plan       show planned changes to the cluster"
	@echo "platform-up      install platform services (Postgres, Temporal) into the cluster"
	@echo "platform-down    uninstall platform services"
	@echo "platform-status  show platform pods"
	@echo "platform-plan    show planned changes to platform services"
	@echo "fmt              format OpenTofu code"
	@echo "validate         validate OpenTofu code"

infra-init:
	$(TOFU) -chdir=$(CLUSTER_DIR) init

infra-plan: infra-init
	$(TOFU) -chdir=$(CLUSTER_DIR) plan

preflight:
	@$(CLUSTER_DIR)/scripts/preflight.sh

infra-up: preflight infra-init
	$(TOFU) -chdir=$(CLUSTER_DIR) apply -auto-approve
	@echo
	@echo "export KUBECONFIG=$(KUBECONFIG)"

infra-down:
	$(TOFU) -chdir=$(CLUSTER_DIR) destroy -auto-approve

infra-status:
	KUBECONFIG=$(KUBECONFIG) kubectl get nodes -L node-pool,capacity-type
	@echo
	KUBECONFIG=$(KUBECONFIG) kubectl get nodes \
	  -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key,GPU:.status.allocatable.nvidia\.com/gpu'

platform-init:
	$(TOFU) -chdir=$(ENV_DIR) init

platform-plan: platform-init
	$(TOFU) -chdir=$(ENV_DIR) plan

platform-up: platform-init
	$(TOFU) -chdir=$(ENV_DIR) apply -auto-approve

platform-down:
	$(TOFU) -chdir=$(ENV_DIR) destroy -auto-approve

platform-status:
	KUBECONFIG=$(KUBECONFIG) kubectl get pods -o wide -n postgres
	@echo
	KUBECONFIG=$(KUBECONFIG) kubectl get pods -o wide -n temporal

fmt:
	$(TOFU) fmt -recursive

validate: infra-init platform-init
	$(TOFU) -chdir=$(CLUSTER_DIR) validate
	$(TOFU) -chdir=$(ENV_DIR) validate
