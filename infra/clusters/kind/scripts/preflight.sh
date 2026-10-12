#!/usr/bin/env bash
# Checks that the host can run the kind cluster, before it is created.
# Only checks and prints fixes; never changes the host (fixes need sudo).
set -uo pipefail

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

if [ "$failed" -ne 0 ]; then
  echo "preflight failed, fix the items above and rerun"
  exit 1
fi
