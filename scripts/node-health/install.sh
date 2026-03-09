#!/usr/bin/env bash
# install.sh — install slurm-node-health script and cron job
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_BIN="/usr/local/sbin/slurm-node-health"
CRON_DEST="/etc/cron.d/slurm-node-health"

echo "Installing ${INSTALL_BIN}..."
cp "${REPO_DIR}/scripts/node-health/fix-stuck-nodes.sh" "${INSTALL_BIN}"
chmod 755 "${INSTALL_BIN}"

echo "Installing ${CRON_DEST}..."
cp "${REPO_DIR}/cron/slurm-node-health.cron" "${CRON_DEST}"
chmod 644 "${CRON_DEST}"

echo "Done. Test with: SLURM_HEALTH_DRY_RUN=1 SLURM_HEALTH_LOG_DIR=/tmp ${INSTALL_BIN}"
