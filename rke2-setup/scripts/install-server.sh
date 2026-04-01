#!/bin/bash
# =============================================================================
# RKE2 Server Node Installation Script (Run on SERVER-1 first, then SERVER-2,3)
# =============================================================================
# Usage:
#   SERVER-1 (bootstrap): sudo ./install-server.sh bootstrap
#   SERVER-2,3 (join):    sudo ./install-server.sh join <SERVER-1-IP>
# =============================================================================

set -euo pipefail

ROLE="${1:-bootstrap}"
JOIN_IP="${2:-}"
NODE_NAME=$(hostname)
RKE2_VERSION="v1.29.4+rke2r1"
TOKEN_FILE="/var/lib/rancher/rke2/server/node-token"
CONFIG_DIR="/etc/rancher/rke2"
DATA_DIR="/var/lib/rancher/rke2"

echo "==> Installing RKE2 Server on ${NODE_NAME} (${ROLE})"

# --- Prerequisites ---
echo "==> Setting up prerequisites..."
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}"

# Disable firewalld if present
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# --- Install RKE2 Server ---
echo "==> Installing RKE2 ${RKE2_VERSION}..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="${RKE2_VERSION}" sh -

# --- Configure RKE2 Server ---
cat > "${CONFIG_DIR}/config.yaml" <<EOF
# RKE2 Server Configuration
write-kubeconfig-mode: "0644"
tls-san:
  - "${NODE_NAME}"
  - "127.0.0.1"
# Uncomment and set your VIP/load balancer IP:
#   - "10.0.0.100"

# Enable workload scheduling on control plane
node-taint: []

# Snapshot settings for etcd
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 5

# Data directory
data-dir: "${DATA_DIR}"

# CNI (default: canal, options: canal, calico, cilium)
# cni: canal

# Cloud provider (if needed)
# cloud-provider-name: ""
EOF

# --- Bootstrap or Join ---
if [[ "${ROLE}" == "join" ]]; then
  if [[ -z "${JOIN_IP}" ]]; then
    echo "ERROR: For join mode, provide the server IP to join: ./install-server.sh join <IP>"
    exit 1
  fi
  echo "==> Joining existing cluster via ${JOIN_IP}:9345..."
  cat >> "${CONFIG_DIR}/config.yaml" <<EOF
server: https://${JOIN_IP}:9345
EOF
fi

# --- Start RKE2 Server ---
echo "==> Enabling and starting RKE2 server..."
systemctl enable rke2-server.service
systemctl start rke2-server.service

# --- Wait for server to be ready ---
echo "==> Waiting for RKE2 server to be ready..."
timeout=300
elapsed=0
while [[ $elapsed -lt $timeout ]]; do
  if systemctl is-active --quiet rke2-server.service; then
    if [[ -f "${DATA_DIR}/server/node-token" ]] || [[ "${ROLE}" == "join" ]]; then
      break
    fi
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

# --- Setup kubectl ---
echo "==> Configuring kubectl..."
mkdir -p /root/.kube
cp "${DATA_DIR}/server/cred/kubeconfig-system.yaml" /root/.kube/config
chmod 600 /root/.kube/config

# Symlink kubectl
export PATH="${DATA_DIR}/bin:$PATH"
if ! command -v kubectl &>/dev/null; then
  ln -sf "${DATA_DIR}/bin/kubectl" /usr/local/bin/kubectl
fi

# --- Print join token ---
if [[ "${ROLE}" == "bootstrap" ]]; then
  echo ""
  echo "============================================="
  echo "  SERVER-1 Bootstrap Complete!"
  echo "============================================="
  echo "  Node Token: $(cat ${TOKEN_FILE})"
  echo "  Join other servers with:"
  echo "    ./install-server.sh join $(hostname -I | awk '{print $1}')"
  echo "  Join agents with:"
  echo "    ./install-agent.sh $(hostname -I | awk '{print $1}') $(cat ${TOKEN_FILE})"
  echo "============================================="
else
  echo ""
  echo "============================================="
  echo "  SERVER Joined Cluster Successfully!"
  echo "============================================="
fi

# --- Label node for Longhorn ---
sleep 10
NODE_OBJ=$(kubectl get node ${NODE_NAME} -o name 2>/dev/null || echo "")
if [[ -n "${NODE_OBJ}" ]]; then
  kubectl label node "${NODE_NAME}" node.longhorn.io/create-default-disk=true --overwrite
  echo "==> Node labeled for Longhorn default disk creation."
fi
