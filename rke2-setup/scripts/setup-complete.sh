#!/bin/bash
# =============================================================================
# RKE2 + Longhorn Complete Setup Script
# =============================================================================
# Run this after all nodes are installed to apply manifests
# Usage: sudo ./setup-complete.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RKE2_BIN="/var/lib/rancher/rke2/bin"
export PATH="${RKE2_BIN}:${PATH}"
export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"

echo "==> Applying Longhorn StorageClasses..."
kubectl apply -f "${SCRIPT_DIR}/../manifests/storageclass.yaml"

echo "==> Applying sample workloads..."
kubectl apply -f "${SCRIPT_DIR}/../manifests/sample-workloads.yaml"

echo "==> Verifying..."
echo ""
echo "--- Nodes ---"
kubectl get nodes -o wide
echo ""
echo "--- StorageClasses ---"
kubectl get storageclass
echo ""
echo "--- PVCs ---"
kubectl get pvc
echo ""
echo "--- Pods ---"
kubectl get pods -o wide
echo ""
echo "============================================="
echo "  Setup Complete!"
echo "============================================="
echo "  Storage: Longhorn with 3-replica replication"
echo "  PVCs: longhorn (default), longhorn-high-perf, longhorn-minimal"
echo "  Sample: sample-app pod with 10Gi PV"
echo "============================================="
