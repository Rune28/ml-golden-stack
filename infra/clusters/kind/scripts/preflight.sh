#!/usr/bin/env bash
# Checks that the host can run the kind cluster, before it is created.
# Only checks and prints fixes; never changes the host (fixes need sudo).
#
# Usage: preflight.sh [cluster dir]   (default: directory of this script's parent)
set -uo pipefail

dir=${1:-$(dirname "$0")/..}
failed=0

ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  warn  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; shift; printf '        %s\n' "$@"; failed=1; }

echo "preflight:"

for cmd in tofu docker kubectl; do
  if command -v "$cmd" >/dev/null; then ok "$cmd found"; else fail "$cmd not found" "see Requirements in README"; fi
done

if docker info >/dev/null 2>&1; then
  ok "docker daemon reachable"
else
  fail "docker daemon not reachable" "start docker, and check that your user may use it: docker info"
fi

# Every kind node runs its own kubelet, containerd and kube-proxy, all using
# inotify on the host kernel. Distro defaults (128 instances) are enough for
# about 3 nodes; beyond that kube-proxy crashes with "too many open files"
# and pods lose service and DNS access.
# https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files
if [ "$(uname -s)" = Linux ]; then
  watches=$(sysctl -n fs.inotify.max_user_watches)
  instances=$(sysctl -n fs.inotify.max_user_instances)
  if [ "$watches" -ge 524288 ] && [ "$instances" -ge 512 ]; then
    ok "inotify limits (watches=$watches, instances=$instances)"
  else
    fail "inotify limits too low (watches=$watches, instances=$instances), kube-proxy will crash" \
      "sudo sysctl fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=512" \
      "printf 'fs.inotify.max_user_watches = 524288\\nfs.inotify.max_user_instances = 512\\n' | sudo tee /etc/sysctl.d/99-kind.conf"
  fi

  avail_mb=$(awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo)
  if [ "$avail_mb" -ge 4096 ]; then
    ok "free memory ${avail_mb} MiB"
  else
    warn "free memory ${avail_mb} MiB, the cluster and platform need about 4 GiB"
  fi
fi

# GPU mode is a per-machine setting in the gitignored local.auto.tfvars.
if grep -qsE '^\s*gpu_mode\s*=\s*"nvidia"' "$dir"/*.auto.tfvars; then
  warn "gpu_mode = nvidia is experimental, see GPU modes in README"

  if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
    ok "NVIDIA driver"
  else
    fail "gpu_mode = nvidia, but nvidia-smi does not work" "install the NVIDIA driver, or remove gpu_mode from local.auto.tfvars"
  fi

  if [ "$(docker info --format '{{.DefaultRuntime}}' 2>/dev/null)" = nvidia ]; then
    ok "docker default runtime is nvidia"
  else
    fail "gpu_mode = nvidia, but docker's default runtime is not nvidia" "see GPU modes in README, step 1"
  fi

  if grep -qsE '^\s*accept-nvidia-visible-devices-as-volume-mounts\s*=\s*true' /etc/nvidia-container-runtime/config.toml; then
    ok "nvidia runtime accepts devices as volume mounts"
  else
    fail "accept-nvidia-visible-devices-as-volume-mounts is not enabled" "see GPU modes in README, step 1"
  fi
fi

if [ "$failed" -ne 0 ]; then
  echo "preflight failed, fix the items above and rerun"
  exit 1
fi
