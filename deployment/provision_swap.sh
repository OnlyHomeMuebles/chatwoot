#!/usr/bin/env bash

# Description: Provision a swap file on the production VM so asset builds survive memory spikes.
# OS: Ubuntu (any systemd release). Run as root on the HOST — Dokploy's server terminal, not an
# application container shell: swap is a host-level resource and swapon has no effect in a container.
# Usage: sudo bash deployment/provision_swap.sh [size]   # size defaults to 4G
#
# Why this exists: the app, Sidekiq, Postgres and Redis all share a single 16GB VM
# (~9GB steady state) and Dokploy builds the release on that same machine. The vite build
# peaks near 4GB of RSS, so a deploy lands at ~13GB and the kernel OOM killer picks a
# victim — usually the running app. Swap does not make the build cheaper; it gives the
# kernel somewhere to push cold pages during the few minutes the build is hot, instead of
# killing a process. vm.swappiness is held low so this stays a spike buffer and Postgres'
# working set is not paged out during normal traffic.
#
# The real fix is building the image in CI and having Dokploy pull it; this is the cheap
# safety net until then.

set -euo pipefail

SWAP_SIZE="${1:-4G}"
SWAP_FILE="/swapfile"
SWAPPINESS=10
SYSCTL_FILE="/etc/sysctl.d/99-chatwoot-swap.conf"

# Refuse to run anywhere but Linux. On macOS `dd` would happily write a 4GB file to / before
# the script died at `mkswap`, and this file gets cloned onto dev laptops.
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script provisions swap on the Linux production VM. Run it on the server."
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash $0 ${SWAP_SIZE}"
  exit 1
fi

if swapon --show --noheadings | grep -q "^${SWAP_FILE} "; then
  echo "Swap already active at ${SWAP_FILE}:"
  swapon --show
else
  if [[ -e "${SWAP_FILE}" ]]; then
    echo "${SWAP_FILE} exists but is not active — reusing it."
  else
    echo "Allocating ${SWAP_SIZE} at ${SWAP_FILE}..."
    # fallocate is instant but unsupported on some filesystems, dd always works.
    fallocate -l "${SWAP_SIZE}" "${SWAP_FILE}" \
      || dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="$(numfmt --from=iec "${SWAP_SIZE}" | awk '{print $1/1048576}')" status=progress
  fi

  chmod 600 "${SWAP_FILE}"
  mkswap "${SWAP_FILE}" > /dev/null
  swapon "${SWAP_FILE}"
  echo "Swap enabled."
fi

# Persist across reboots. Only touch fstab once swapon has already succeeded above.
if ! grep -qs "^${SWAP_FILE} " /etc/fstab; then
  cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
  echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
  echo "Added ${SWAP_FILE} to /etc/fstab (backup kept alongside it)."
fi

# Keep swap as a spike buffer: the kernel should reach for it under real pressure, not to
# trim Postgres' page cache while the box is idle.
if [[ ! -f "${SYSCTL_FILE}" ]]; then
  echo "vm.swappiness=${SWAPPINESS}" > "${SYSCTL_FILE}"
  sysctl --load="${SYSCTL_FILE}"
fi

echo
echo "=== Memory after provisioning ==="
free -h
swapon --show
