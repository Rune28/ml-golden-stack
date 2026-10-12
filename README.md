# ml-golden-stack

Reference stack for multi-model batch ML pipelines: OpenTofu, Kubernetes, Kueue and Temporal. Runs locally on kind and is designed to run on EKS with the same platform layer.

> Work in progress. Only the local cluster (`infra/local`) is implemented so far.

## Layout

| Directory | Purpose | Status |
|---|---|---|
| `infra/local` | kind cluster provisioned with OpenTofu | ✅ |
| `temporal` | Temporal workflows: pipeline orchestration, model promotion | planned |
| `de_worker` | data engineering worker: video decoding, segmentation, I/O | planned |
| `mle_models` | model steps behind a common batch interface | planned |

## Local cluster

The cluster mimics cloud node groups so that scheduling rules written locally carry over to EKS:

| Node | Pool label | Capacity label | Taint |
|---|---|---|---|
| control-plane | — | — | `node-role.kubernetes.io/control-plane:NoSchedule` |
| worker | `node-pool=cpu` | `capacity-type=on-demand` | — |
| worker | `node-pool=gpu-sim` | `capacity-type=spot` | `nvidia.com/gpu=present:NoSchedule` |

`gpu-sim` has no GPU. It reproduces the labels and taint of a GPU node group so that Kueue flavors, tolerations and node selectors can be exercised locally. Workloads on it run on CPU.

Pools, sizes, labels and taints are configured through the `node_pools` variable.

Services that will be exposed on the host (NodePort → `127.0.0.1`):

| Service | URL |
|---|---|
| Temporal UI | http://127.0.0.1:8080 |
| MLflow | http://127.0.0.1:5000 |
| MinIO console | http://127.0.0.1:9001 |

### Requirements

- [OpenTofu](https://opentofu.org/docs/intro/install/) ≥ 1.8
- Docker (Podman works with `KIND_EXPERIMENTAL_PROVIDER=podman`)
- kubectl
- ~6 GB of free RAM for the cluster and platform services

The `kind` CLI is not required: the cluster is created by the `tehcyx/kind` provider.

### Usage

```bash
make infra-up        # create the cluster
export KUBECONFIG=$PWD/infra/local/.kubeconfig
make infra-status    # nodes, pools and taints
make infra-down      # destroy the cluster
```

The kubeconfig is written to `infra/local/.kubeconfig` (gitignored), so `~/.kube/config` is left untouched.

### Versions

| Component | Version | Why |
|---|---|---|
| `tehcyx/kind` provider | `~> 0.11` | bundles kind v0.31 |
| Kubernetes node image | `v1.35.0` | default image of kind v0.31, pinned by digest |
