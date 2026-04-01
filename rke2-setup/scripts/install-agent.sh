#!/bin/bash
# =============================================================================
# RKE2 Agent Node Installation Script (Run on AGENT-1, AGENT-2)
# =============================================================================
# Usage:
#   sudo ./install-agent.sh <SERVER-IP> <NODE-TOKEN>
#
# Example:
#   sudo ./install-agent.sh 10.0.0.1 K10abc123def456::server:ghi789jkl
# =============================================================================

set -euo pipefail

SERVER_IP="${1:?ERROR: Provide server IP: ./install-agent.sh <SERVER-IP> <NODE-TOKEN>}"
NODE_TOKEN="${2:?ERROR: Provide node token: ./install-agent.sh <SERVER-IP> <NODE-TOKEN>}"
NODE_NAME=$(hostname)
RKE2_VERSION="v1.29.4+rke2r1"
CONFIG_DIR="/etc/rancher/rke2"
DATA_DIR="/var/lib/rancher/rke2"

echo "==> Installing RKE2 Agent on ${NODE_NAME} (joining ${SERVER_IP})"

# --- Prerequisites ---
echo "==> Setting up prerequisites..."
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}"

# Disable firewalld if present
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# --- Install RKE2 Agent ---
echo "==> Installing RKE2 Agent ${RKE2_VERSION}..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_VERSION="${RKE2_VERSION}" sh -

# --- Configure RKE2 Agent ---
cat > "${CONFIG_DIR}/config.yaml" <<EOF
# RKE2 Agent Configuration
server: https://${SERVER_IP}:9345
token: ${NODE_TOKEN}
data-dir: "${DATA_DIR}"

# Uncomment if agent has 2TB+ disk for Longhorn:
# node-label:
#   - "node.longhorn.io/create-default-disk=true"
EOF

# --- Start RKE2 Agent ---
echo "==> Enabling and starting RKE2 agent..."
systemctl enable rke2-agent.service
systemctl start rke2-agent.service

# --- Wait for agent to be ready ---
echo "==> Waiting for RKE2 agent to connect..."
timeout=300
elapsed=0
while [[ $elapsed -lt $timeout ]]; do
  if systemctl is-active --quiet rke2-agent.service; then
    echo "==> RKE2 agent service is running."
    break
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

echo ""
echo "============================================="
echo "  AGENT Joined Cluster Successfully!"
echo "============================================="
echo "  Node: ${NODE_NAME}"
echo "  Joined: ${SERVER_IP}"
echo "============================================="
