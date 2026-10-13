TOFU        ?= tofu
DOCKER      ?= docker
CLUSTER_DIR := infra/clusters/kind
ENV_DIR     := infra/envs/local
KUBECONFIG  := $(abspath $(CLUSTER_DIR)/.kubeconfig)
KUBECTL     := KUBECONFIG=$(KUBECONFIG) kubectl

# local: build the images and load them into kind; remote: take TAG from GHCR.
IMAGES ?= local
TAG    ?=

# Pipeline shortcuts without the page.
N     ?= 5000
POOL  ?= gpu
MODEL ?= champion

.PHONY: help infra-init infra-plan infra-up infra-down infra-status \
        platform-init platform-plan platform-up platform-down platform-status \
        images images-load app-status add-data train run report \
        preflight host-setup test fmt validate

help:
	@echo "preflight        check the host (tools, inotify limits, memory)"
	@echo "host-setup       raise inotify limits for kind, persistently (Linux, uses sudo)"
	@echo "infra-up         create the local kind cluster (runs preflight first)"
	@echo "infra-down       destroy the local kind cluster (run platform-down first)"
	@echo "infra-status     show nodes, pools, taints and GPUs"
	@echo "infra-plan       show planned changes to the cluster"
	@echo "platform-up      build and load the images, install platform services and applications"
	@echo "                 (IMAGES=remote TAG=sha-abc1234 takes the images from GHCR instead)"
	@echo "platform-down    uninstall platform services and applications"
	@echo "platform-status  show platform and application pods"
	@echo "platform-plan    show planned changes to platform services and applications"
	@echo "images           build the application images and pin their tags for platform-up"
	@echo "images-load      load the images into the kind nodes that miss them"
	@echo "add-data N=5000  add the next N MNIST examples (be_service)"
	@echo "train POOL=gpu   start the Train workflow"
	@echo "run MODEL=champion  start the Run workflow"
	@echo "report           start the Report workflow on the latest prediction run"
	@echo "test             unit tests of be_service, de_worker and mle_models"
	@echo "fmt              format OpenTofu code"
	@echo "validate         validate OpenTofu code"

infra-init:
	$(TOFU) -chdir=$(CLUSTER_DIR) init

infra-plan: infra-init
	$(TOFU) -chdir=$(CLUSTER_DIR) plan

preflight:
	@$(CLUSTER_DIR)/scripts/preflight.sh

# The only target that changes the host. Kept out of infra-up on purpose:
# it needs sudo, and preflight tells you when to run it.
host-setup:
	printf 'fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 8192\n' \
	  | sudo tee /etc/sysctl.d/99-kind.conf
	sudo sysctl -p /etc/sysctl.d/99-kind.conf

infra-up: preflight infra-init
	$(TOFU) -chdir=$(CLUSTER_DIR) apply -auto-approve
	@echo
	@echo "export KUBECONFIG=$(KUBECONFIG)"

infra-down:
	$(TOFU) -chdir=$(CLUSTER_DIR) destroy -auto-approve

infra-status:
	$(KUBECTL) get nodes -L node-pool,capacity-type
	@echo
	$(KUBECTL) get nodes \
	  -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key,GPU:.status.allocatable.nvidia\.com/gpu'

ifeq ($(IMAGES),remote)
images:
	scripts/images.sh remote
images-load:
	@echo "IMAGES=remote: the nodes pull from the registry"
else
images:
	DOCKER=$(DOCKER) scripts/images.sh build
images-load:
	DOCKER=$(DOCKER) scripts/images.sh load
endif

platform-init:
	$(TOFU) -chdir=$(ENV_DIR) init

platform-plan: platform-init
	$(TOFU) -chdir=$(ENV_DIR) plan

# Images first: the applications are part of the platform apply, and the
# image tags come from images.auto.tfvars.json.
platform-up: images images-load platform-init
	$(TOFU) -chdir=$(ENV_DIR) apply -auto-approve
	@echo
	@$(TOFU) -chdir=$(ENV_DIR) output

platform-down:
	$(TOFU) -chdir=$(ENV_DIR) destroy -auto-approve

platform-status:
	$(KUBECTL) get pods -o wide -n postgres
	@echo
	$(KUBECTL) get pods -o wide -n temporal
	@echo
	@$(MAKE) --no-print-directory app-status

app-status:
	@for ns in seaweedfs clickhouse mlflow de-worker be-service; do \
	  echo "== $$ns"; $(KUBECTL) get pods,jobs -o wide -n $$ns; echo; done

# The same call the Add data button makes (be_service on the kind port mapping `app`).
add-data:
	@curl -sS -H 'content-type: application/json' -d '{"count": $(N)}' http://127.0.0.1:9001/api/batches; echo

train:
	$(KUBECTL) -n temporal exec deploy/temporal-admintools -- temporal workflow start \
	  --address temporal-frontend:7233 --task-queue de --type Train --workflow-id train \
	  --input '{"pool": "$(POOL)"}'

run:
	$(KUBECTL) -n temporal exec deploy/temporal-admintools -- temporal workflow start \
	  --address temporal-frontend:7233 --task-queue de --type Run --workflow-id run \
	  --input '{"model": "$(MODEL)"}'

# Through be_service: it picks the latest prediction run.
report:
	@curl -sS -H 'content-type: application/json' -d '{}' http://127.0.0.1:9001/api/report; echo

test:
	cd be_service && cargo test
	cd de_worker && uv run pytest
	cd mle_models && uv run pytest

fmt:
	$(TOFU) fmt -recursive

validate: infra-init platform-init
	$(TOFU) -chdir=$(CLUSTER_DIR) validate
	$(TOFU) -chdir=$(ENV_DIR) validate
