#!/usr/bin/env bash
# Advertises a fake nvidia.com/gpu extended resource on the nodes of GPU pools,
# so GPU pods schedule locally as they would on cloud GPU nodes.
# Called by OpenTofu (terraform_data.gpu_nodes), see main.tf for the inputs.
set -Eeuo pipefail

: "${KUBECONFIG:?}" "${NODE_SELECTOR:?}" "${SIMULATED_GPUS:=1}"

nodes=$(kubectl get nodes -l "$NODE_SELECTOR" -o jsonpath='{.items[*].metadata.name}')
[ -n "$nodes" ] || { echo "no nodes match '$NODE_SELECTOR'" >&2; exit 1; }

for node in $nodes; do
  kubectl patch node "$node" --subresource=status --type=json \
    -p "[{\"op\": \"add\", \"path\": \"/status/capacity/nvidia.com~1gpu\", \"value\": \"$SIMULATED_GPUS\"}]"
done
