#!/usr/bin/env bash
# Prepares the nodes of GPU pools after the kind cluster is created.
# Called by OpenTofu (terraform_data.gpu_nodes), see main.tf for the inputs.
#
# nvidia:    the node containers already see the host GPUs (injected by the
#            host's nvidia-container-runtime). Install the toolkit inside each
#            node and make nvidia the default containerd runtime, as on cloud
#            GPU images. Steps follow NVIDIA's nvkind.
# simulated: advertise a fake nvidia.com/gpu extended resource on each node.
set -Eeuo pipefail

: "${KUBECONFIG:?}" "${GPU_MODE:?}" "${NODE_SELECTOR:?}" "${SIMULATED_GPUS:=1}"

nodes=$(kubectl get nodes -l "$NODE_SELECTOR" -o jsonpath='{.items[*].metadata.name}')
[ -n "$nodes" ] || { echo "no nodes match '$NODE_SELECTOR'" >&2; exit 1; }

setup_nvidia() {
  local node=$1

  if ! docker exec "$node" test -e /proc/driver/nvidia/params; then
    echo "$node: no GPU inside the node container, check the host setup in README" >&2
    exit 1
  fi

  docker exec "$node" bash -Eeuo pipefail -c '
    apt-get update -q
    apt-get install -yq gpg
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update -q
    apt-get install -yq nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=containerd --config-source=file --set-as-default
    systemctl restart containerd
  '

  # Stop the driver from recreating /dev/nvidia* nodes inside the node.
  # Toolkit >= 1.19 on the host already masks this (ModifyDeviceFiles: 0).
  if docker exec "$node" grep -q '^ModifyDeviceFiles: 1$' /proc/driver/nvidia/params; then
    docker exec "$node" bash -Eeuo pipefail -c '
      umount -R /proc/driver/nvidia
      cp /proc/driver/nvidia/params /root/gpu-params
      sed -i "s/^ModifyDeviceFiles: 1$/ModifyDeviceFiles: 0/" /root/gpu-params
      mount --bind /root/gpu-params /proc/driver/nvidia/params
    '
  fi

  docker exec "$node" nvidia-smi -L
}

setup_simulated() {
  local node=$1
  kubectl patch node "$node" --subresource=status --type=json \
    -p "[{\"op\": \"add\", \"path\": \"/status/capacity/nvidia.com~1gpu\", \"value\": \"$SIMULATED_GPUS\"}]"
}

for node in $nodes; do
  echo "$node: gpu_mode=$GPU_MODE"
  case "$GPU_MODE" in
    nvidia)    setup_nvidia "$node" ;;
    simulated) setup_simulated "$node" ;;
    *)         echo "unknown GPU_MODE $GPU_MODE" >&2; exit 1 ;;
  esac
done
