#!/bin/bash
# =============================================================================
# Longhorn Installation Script for RKE2
# =============================================================================
# Run this from a server node or any machine with kubectl access
# Usage: sudo ./install-longhorn.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
RKE2_BIN="/var/lib/rancher/rke2/bin"
HELM_VERSION="3.14.0"

export PATH="${RKE2_BIN}:${PATH}"
export KUBECONFIG

echo "==> Installing Longhorn on RKE2 Cluster"

# --- Verify kubectl access ---
echo "==> Verifying cluster access..."
kubectl get nodes
echo ""

# --- Install Helm if not present ---
if ! command -v helm &>/dev/null; then
  echo "==> Installing Helm ${HELM_VERSION}..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# --- Label SERVER nodes for Longhorn default disk ---
echo "==> Labeling SERVER nodes for Longhorn default disk..."
for node in $(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}'); do
  echo "    Labeling ${node}..."
  kubectl label node "${node}" node.longhorn.io/create-default-disk=true --overwrite
done

# --- (Optional) Label AGENT nodes if they have large disks ---
# Uncomment if agent nodes also have 2TB+ disks you want Longhorn to use
# for node in $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}'); do
#   echo "    Labeling ${node}..."
#   kubectl label node "${node}" node.longhorn.io/create-default-disk=true --overwrite
# done

# --- Add Longhorn Helm repo ---
echo "==> Adding Longhorn Helm repository..."
helm repo add longhorn https://charts.longhorn.io
helm repo update

# --- Install Longhorn ---
echo "==> Installing Longhorn..."
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  -f "${SCRIPT_DIR}/longhorn-values.yaml" \
  --wait --timeout 10m

# --- Wait for Longhorn components ---
echo "==> Waiting for Longhorn pods to be ready..."
kubectl -n longhorn-system rollout status daemonset/longhorn-manager --timeout=300s
kubectl -n longhorn-system rollout status deployment/longhorn-ui --timeout=300s

# --- Verify installation ---
echo ""
echo "============================================="
echo "  Longhorn Installation Complete!"
echo "============================================="
echo ""
echo "  Pods:"
kubectl -n longhorn-system get pods -o wide
echo ""
echo "  StorageClasses:"
kubectl get storageclass
echo ""
echo "  Longhorn UI: kubectl -n longhorn-system port-forward svc/longhorn-ui 8000:80"
echo "  Then open: http://localhost:8000"
echo "============================================="
