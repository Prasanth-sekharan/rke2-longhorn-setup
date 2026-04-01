# RKE2 + Longhorn Complete Guide
### A Plain-English Guide to Building, Managing, and Scaling Your Kubernetes Cluster

---

## Table of Contents

1. [What is All This? (The Big Picture)](#1-what-is-all-this)
2. [Understanding the Architecture](#2-understanding-the-architecture)
3. [What You Need Before Starting](#3-what-you-need-before-starting)
4. [Installation Guide](#4-installation-guide)
5. [Verifying Your Installation](#5-verifying-your-installation)
6. [Troubleshooting](#6-troubleshooting)
7. [Scaling Your Infrastructure](#7-scaling-your-infrastructure)
8. [Daily Operations Cheat Sheet](#8-daily-operations-cheat-sheet)
9. [Backup and Recovery](#9-backup-and-recovery)
10. [Glossary](#10-glossary)

---

## 1. What is All This?

### The Analogy

Imagine you run a **restaurant chain** with multiple branches:

- **Kubernetes** is the **head office manager** — it decides which branch handles each order, makes sure food is prepared, and if one branch burns down, it reroutes customers to other branches automatically.

- **RKE2** is the **franchise system** — it's the specific way you build and run your restaurant branches (Kubernetes cluster). It's made by Rancher (now SUSE) and is designed to be secure and easy to manage.

- **Longhorn** is the **shared filing cabinet system** — it stores all your recipes, customer records, and inventory data. If one filing cabinet catches fire, two other copies exist in other branches. Your data is always safe.

- **Nodes** are the **restaurant branches (computers/servers)**:
  - **Server nodes (3)** = Main branches with managers, chefs, and filing cabinets
  - **Agent nodes (2)** = Satellite branches with chefs only

### Why This Setup?

| What                  | Why                                                                 |
|-----------------------|---------------------------------------------------------------------|
| 3 Server nodes        | If one crashes, the other two keep running. No downtime.            |
| 2 Agent nodes         | Extra cooking capacity for your applications.                       |
| Longhorn storage      | Your data is copied 3 times across 3 different servers.             |
| 2TB disks on servers  | Plenty of room for your data with built-in safety copies.           |

---

## 2. Understanding the Architecture

### Visual Overview

```
                         INTERNET / USERS
                               │
                               ▼
                    ┌──────────────────────┐
                    │    LOAD BALANCER     │
                    │  (Entry Point/VIP)   │
                    └──────────┬───────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
    │  SERVER-1   │    │  SERVER-2   │    │  SERVER-3   │
    │             │    │             │    │             │
    │ Brain +     │    │ Brain +     │    │ Brain +     │
    │ Chef +      │    │ Chef +      │    │ Chef +      │
    │ Filing      │    │ Filing      │    │ Filing      │
    │ Cabinet     │    │ Cabinet     │    │ Cabinet     │
    │ (2TB disk)  │    │ (2TB disk)  │    │ (2TB disk)  │
    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
           │                  │                   │
           └──────────────────┼───────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │  Internal Network │
                    └─────────┬─────────┘
                              │
               ┌──────────────┴──────────────┐
               │                             │
        ┌──────┴──────┐              ┌───────┴─────┐
        │  AGENT-1    │              │  AGENT-2    │
        │             │              │             │
        │ Chef only   │              │ Chef only   │
        └─────────────┘              └─────────────┘
```

### What Each Piece Does

#### Server Nodes (SERVER-1, SERVER-2, SERVER-3)

Each server node runs ALL of these:

| Component           | What It Does (In Plain English)                                      |
|---------------------|----------------------------------------------------------------------|
| **etcd**            | The shared notebook that remembers the state of everything           |
| **kube-apiserver**  | The receptionist — accepts all requests and validates them           |
| **kube-scheduler**  | The dispatcher — decides which node runs each application           |
| **kube-controller** | The supervisor — makes sure everything is running as intended       |
| **kubelet**         | The local manager — runs and monitors containers on this node       |
| **kube-proxy**      | The traffic cop — routes network traffic to the right containers    |
| **Longhorn**        | The storage manager — manages the 2TB disk for data replication     |

#### Agent Nodes (AGENT-1, AGENT-2)

Agent nodes are simpler — they only run applications:

| Component        | What It Does                                      |
|------------------|----------------------------------------------------|
| **kubelet**      | Runs and monitors containers on this node          |
| **kube-proxy**   | Routes network traffic                             |
| **Applications** | Your actual software (web servers, databases, etc) |

#### How Data Replication Works

```
Your App Writes Data
        │
        ▼
┌─────────────────────────────────────────────┐
│              Longhorn Volume                │
│          (A virtual "hard drive")           │
└──────────────────┬──────────────────────────┘
                   │
     ┌─────────────┼─────────────┐
     │             │             │
     ▼             ▼             ▼
┌─────────┐  ┌─────────┐  ┌─────────┐
│ Copy 1  │  │ Copy 2  │  │ Copy 3  │
│         │  │         │  │         │
│SERVER-1 │  │SERVER-2 │  │SERVER-3 │
│2TB disk │  │2TB disk │  │2TB disk │
└─────────┘  └─────────┘  └─────────┘

If SERVER-2 dies → Copies 1 & 3 are still safe.
Longhorn will create a new copy on another node.
```

### Fault Tolerance

| Component         | Can Survive                | What Happens                                      |
|-------------------|----------------------------|----------------------------------------------------|
| **etcd (3 nodes)**| 1 server failure           | Cluster continues normally                         |
| **Longhorn (3 replicas)** | 2 disk/node failures | Data is still available from surviving replicas    |
| **Applications**  | Any node failure           | Kubernetes reschedules apps on surviving nodes     |

---

## 3. What You Need Before Starting

### Hardware Requirements

| Node      | CPU   | RAM   | Disk     | Notes                                      |
|-----------|-------|-------|----------|--------------------------------------------|
| SERVER-1  | 4+    | 8GB+  | 2TB      | Control plane + storage + workloads        |
| SERVER-2  | 4+    | 8GB+  | 2TB      | Control plane + storage + workloads        |
| SERVER-3  | 4+    | 8GB+  | 2TB      | Control plane + storage + workloads        |
| AGENT-1   | 4+    | 8GB+  | 50GB+    | Workloads only                             |
| AGENT-2   | 4+    | 8GB+  | 50GB+    | Workloads only                             |

### Software Requirements (All Nodes)

- **OS**: RHEL 8/9, CentOS 8/9, Rocky Linux 8/9, or Ubuntu 20.04/22.04
- **Root/sudo access** on all nodes
- **Ports open**: 6443, 9345, 2379-2380, 10250, 30000-32767, 4789, 8472
- **SELinux**: Either disabled or properly configured
- **Firewalld**: Disabled or configured for RKE2 ports

### Network Requirements

| What              | Ports          | Purpose                                |
|-------------------|----------------|----------------------------------------|
| API Server        | 6443           | Kubernetes API access                  |
| Node Registration | 9345           | Nodes joining the cluster              |
| etcd              | 2379, 2380     | Cluster state database                 |
| Kubelet API       | 10250          | Node management                        |
| NodePort Services | 30000-32767    | Exposing services externally           |
| VXLAN (Canal)     | 4789, 8472     | Pod-to-pod networking                  |
| Longhorn          | 9500-9502      | Storage replication                    |
| Longhorn UI       | 31080          | Storage management dashboard           |

### Before You Start Checklist

```
[ ] All 5 servers have IP addresses on the same network
[ ] All 5 servers can ping each other
[ ] All 5 servers have the OS installed and updated
[ ] All 5 servers have root/sudo access configured
[ ] You know the IP addresses of all 5 servers
[ ] Firewall is disabled or ports are open
[ ] SELinux is disabled or configured
[ ] Swap is disabled on all nodes
[ ] Time is synchronized across all nodes (NTP)
[ ] DNS resolution works between all nodes
```

### Quick Pre-Installation Commands (Run on ALL nodes)

```bash
# Check OS version
cat /etc/os-release

# Check hostname
hostname

# Check IP address
ip addr show

# Check swap (should show 0)
free -h

# Disable swap immediately
swapoff -a

# Disable swap permanently (edit /etc/fstab)
sed -i '/ swap / s/^/#/' /etc/fstab

# Disable firewalld (RKE2 manages its own firewall)
systemctl stop firewalld
systemctl disable firewalld

# Disable SELinux (requires reboot)
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# Synchronize time
yum install -y chrony   # RHEL/CentOS
systemctl enable chronyd
systemctl start chronyd
chronyc tracking

# Test connectivity from each node to all others
ping -c 2 <OTHER_NODE_IP>
```

---

## 4. Installation Guide

### Overview of Steps

```
Step 1 → Install SERVER-1 (the first/bootstrap server)
Step 2 → Install SERVER-2 (join SERVER-1)
Step 3 → Install SERVER-3 (join SERVER-1)
Step 4 → Install AGENT-1 (join SERVER-1)
Step 5 → Install AGENT-2 (join SERVER-1)
Step 6 → Install Longhorn (storage system)
Step 7 → Apply storage configuration
```

### Step 1: Install SERVER-1 (Bootstrap Node)

This is the first server. It creates the cluster from scratch.

```bash
# SSH into SERVER-1
ssh root@<SERVER-1-IP>

# Download the install script (or copy it manually)
# If you have the scripts from rke2-setup/ folder:
cd /root
# ... copy scripts here ...

# Run the bootstrap installation
sudo bash install-server.sh bootstrap
```

**What happens:**
1. Installs RKE2 server software
2. Creates the cluster configuration
3. Starts the Kubernetes control plane
4. Generates a "node token" (password for other nodes to join)

**Expected output:**
```
=============================================
  SERVER-1 Bootstrap Complete!
=============================================
  Node Token: K10abc123def456::server:ghi789jkl
  Join other servers with:
    ./install-server.sh join 10.0.0.1
  Join agents with:
    ./install-agent.sh 10.0.0.1 K10abc123def456::server:ghi789jkl
=============================================
```

**IMPORTANT**: Save the **Node Token**! You need it for all other nodes.

### Step 2: Install SERVER-2

```bash
# SSH into SERVER-2
ssh root@<SERVER-2-IP>

# Copy the install script, then run:
sudo bash install-server.sh join <SERVER-1-IP>
```

Replace `<SERVER-1-IP>` with the actual IP of SERVER-1.

### Step 3: Install SERVER-3

```bash
# SSH into SERVER-3
ssh root@<SERVER-3-IP>

# Same as SERVER-2:
sudo bash install-server.sh join <SERVER-1-IP>
```

### Step 4: Install AGENT-1

```bash
# SSH into AGENT-1
ssh root@<AGENT-1-IP>

# Run:
sudo bash install-agent.sh <SERVER-1-IP> <NODE-TOKEN>
```

Replace:
- `<SERVER-1-IP>` with SERVER-1's IP
- `<NODE-TOKEN>` with the token from Step 1

### Step 5: Install AGENT-2

```bash
# SSH into AGENT-2
ssh root@<AGENT-2-IP>

# Same as AGENT-1:
sudo bash install-agent.sh <SERVER-1-IP> <NODE-TOKEN>
```

### Step 6: Verify All Nodes Are Joined

```bash
# SSH into SERVER-1 (or any server node)
ssh root@<SERVER-1-IP>

# Set up kubectl access
export PATH="/var/lib/rancher/rke2/bin:$PATH"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Check all nodes
kubectl get nodes
```

**Expected output:**
```
NAME       STATUS   ROLES                       AGE   VERSION
server-1   Ready    control-plane,etcd,master   10m   v1.29.4+rke2r1
server-2   Ready    control-plane,etcd,master   8m    v1.29.4+rke2r1
server-3   Ready    control-plane,etcd,master   6m    v1.29.4+rke2r1
agent-1    Ready    <none>                      4m    v1.29.4+rke2r1
agent-2    Ready    <none>                      2m    v1.29.4+rke2r1
```

All 5 nodes should show **Ready** status.

### Step 7: Install Longhorn (Storage System)

```bash
# On SERVER-1 (or any server node with kubectl access)
ssh root@<SERVER-1-IP>

# Run the Longhorn installer
sudo bash install-longhorn.sh
```

**What happens:**
1. Labels the 3 server nodes so Longhorn uses their 2TB disks
2. Downloads and installs Longhorn via Helm
3. Creates the StorageClass for persistent volumes

**Expected output:**
```
=============================================
  Longhorn Installation Complete!
=============================================
  Pods:
  NAME                          READY   STATUS
  longhorn-manager-xxxxx        1/1     Running
  longhorn-driver-deployer-xxx  1/1     Running
  longhorn-ui-xxxxxxxxx-xxxxx   1/1     Running
  ...

  StorageClasses:
  NAME                   PROVISIONER          RECLAIMPOLICY
  longhorn (default)     driver.longhorn.io   Delete
=============================================
```

### Step 8: Apply Storage Configuration

```bash
# On SERVER-1
sudo bash setup-complete.sh
```

This applies the StorageClass definitions and sample workloads.

---

## 5. Verifying Your Installation

### Check 1: Cluster Health

```bash
# Check all nodes are Ready
kubectl get nodes

# Check all system pods are running
kubectl get pods -A

# Check etcd health
kubectl -n kube-system exec etcd-server-1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  endpoint health
```

### Check 2: Longhorn Health

```bash
# Check Longhorn pods
kubectl -n longhorn-system get pods

# Check Longhorn volumes
kubectl -n longhorn-system get volumes

# Check Longhorn nodes and their disks
kubectl -n longhorn-system get nodes
```

### Check 3: Storage Test

Create a test PVC and pod to verify storage works:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
    - name: test
      image: busybox
      command: ["sh", "-c", "echo 'Storage works!' > /data/test.txt && cat /data/test.txt && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test-pvc
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/test-pod --timeout=60s

# Check the test
kubectl logs test-pod

# Clean up
kubectl delete pod test-pod
kubectl delete pvc test-pvc
```

**Expected output from logs:** `Storage works!`

### Check 4: Access Longhorn UI

```bash
# From your local machine, set up port forwarding
kubectl -n longhorn-system port-forward svc/longhorn-ui 8000:80

# Open in browser: http://localhost:8000
```

In the UI you should see:
- 3 nodes with their 2TB disks
- Default disk configured
- Volumes listed (including test PVC if still exists)

### Check 5: Verify Data Replication

```bash
# Create a PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: replication-test
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Check the volume replicas
kubectl -n longhorn-system get volumes

# You should see a volume with 3 replicas
# NAME                  STATE       ROBUSTNESS   SCHEDULER   SIZE
# pvc-xxxxxx            attached    healthy      -           5Gi

# Get detailed replica info
kubectl -n longhorn-system get replicas
```

---

## 6. Troubleshooting

### Problem: Node Shows "NotReady"

**Symptoms:** `kubectl get nodes` shows a node as `NotReady`

**Check the node:**
```bash
# Describe the node to see the issue
kubectl describe node <NODE-NAME>

# Common causes:
# - Kubelet not running
# - Network issues
# - Disk pressure
# - Memory pressure
```

**Fix:**
```bash
# SSH into the problematic node
ssh root@<NODE-IP>

# Check RKE2 service status
# For server nodes:
sudo systemctl status rke2-server

# For agent nodes:
sudo systemctl status rke2-agent

# Check logs
sudo journalctl -u rke2-server -f   # Server nodes
sudo journalctl -u rke2-agent -f    # Agent nodes

# Restart if needed
sudo systemctl restart rke2-server   # Server nodes
sudo systemctl restart rke2-agent    # Agent nodes
```

### Problem: Pod Stuck in "Pending"

**Symptoms:** Pod won't start, shows `Pending` status

**Diagnose:**
```bash
# See why the pod is pending
kubectl describe pod <POD-NAME>

# Common causes in the Events section:
# - "Insufficient cpu/memory" → Not enough resources
# - "node(s) had taint" → Taint/toleration mismatch
# - "volume not available" → Storage issue
```

**Fix for taint issues (pods not scheduling on server nodes):**
```yaml
# Add this to your pod spec:
spec:
  tolerations:
    - key: "node-role.kubernetes.io/control-plane"
      operator: "Exists"
      effect: "NoSchedule"
```

### Problem: PVC Stuck in "Pending"

**Symptoms:** PVC won't bind, shows `Pending`

**Diagnose:**
```bash
# Check PVC events
kubectl describe pvc <PVC-NAME>

# Check if Longhorn is healthy
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get volumes
```

**Fix:**
```bash
# If Longhorn manager pods are not running:
kubectl -n longhorn-system delete pod -l app=longhorn-manager
# They will restart automatically

# If disks are full:
kubectl -n longhorn-system get nodes -o yaml | grep -A 10 storage
# Check "storageAvailable" vs "storageScheduled"

# Clean up unused volumes
kubectl -n longhorn-system delete volumes --field-selector=status.state=detached
```

### Problem: etcd Issues

**Symptoms:** Cluster seems broken, API server errors

**Diagnose:**
```bash
# Check etcd pods
kubectl -n kube-system get pods | grep etcd

# Check etcd member list
kubectl -n kube-system exec etcd-<NODE> -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  member list
```

**If one etcd node is down:**
```bash
# SSH into the down node
ssh root@<DOWN-NODE-IP>

# Check if RKE2 server is running
sudo systemctl status rke2-server

# If not, start it
sudo systemctl start rke2-server

# If it won't start, check logs
sudo journalctl -u rke2-server -n 100
```

**If etcd is corrupted:**
```bash
# On the corrupted node, restore from snapshot
# (This is a last resort - see Backup and Recovery section)
sudo systemctl stop rke2-server
sudo rke2 server --cluster-reset
sudo systemctl start rke2-server
```

### Problem: Longhorn Volume Degraded

**Symptoms:** Volume shows "Degraded" or replicas show "Failed"

**Diagnose:**
```bash
# Check volume status
kubectl -n longhorn-system get volumes

# Check replica status
kubectl -n longhorn-system get replicas

# Check manager logs
kubectl -n longhorn-system logs -l app=longhorn-manager --tail=50
```

**Fix:**
```bash
# If a replica failed, Longhorn will auto-rebuild
# Monitor the rebuild:
kubectl -n longhorn-system get replicas -w

# If a node's disk is full, expand it or clean up old volumes:
# List all volumes and their sizes
kubectl -n longhorn-system get volumes -o custom-columns=\
NAME:.metadata.name,SIZE:.spec.size,STATE:.status.state

# Delete unused/detached volumes
kubectl -n longhorn-system delete volume <VOLUME-NAME>
```

### Problem: Node Won't Join Cluster

**Symptoms:** New node shows error during join

**Diagnose:**
```bash
# On the node trying to join:
sudo journalctl -u rke2-server -f   # (or rke2-agent)

# Common errors:
# - "certificate signed by unknown authority" → Wrong token or server IP
# - "connection refused" → Server not reachable, check firewall
# - "node already exists" → Node was previously in cluster
```

**Fix:**
```bash
# If node was previously in cluster, clean up first:
sudo systemctl stop rke2-server  # or rke2-agent
sudo rm -rf /var/lib/rancher/rke2
sudo rm -rf /etc/rancher/rke2
# Then re-run the install script
```

### Problem: Pods Can't Communicate

**Symptoms:** Pods can't reach each other or external services

**Diagnose:**
```bash
# Check CNI pods (Canal/Calico)
kubectl -n kube-system get pods | grep -E "canal|calico|cilium"

# Check network policies
kubectl get networkpolicies -A

# Test DNS
kubectl run test-dns --image=busybox --rm -it -- nslookup kubernetes.default
```

**Fix:**
```bash
# If CNI pods are crashing:
kubectl -n kube-system delete pod -l k8s-app=canal
# They will restart

# Check if VXLAN ports are open on all nodes:
# On each node:
sudo ss -ulnp | grep -E "4789|8472"
```

### Problem: Can't Access Longhorn UI

```bash
# Method 1: Port forward (from your machine with kubectl access)
kubectl -n longhorn-system port-forward svc/longhorn-ui 8000:80

# Method 2: NodePort (access via any node IP)
# Default NodePort is 31080
# http://<ANY-NODE-IP>:31080

# If NodePort doesn't work, check the service:
kubectl -n longhorn-system get svc longhorn-ui
```

### Quick Diagnostic Commands

```bash
# Everything at a glance
echo "=== NODES ==="
kubectl get nodes -o wide
echo ""
echo "=== ALL PODS ==="
kubectl get pods -A
echo ""
echo "=== PVCs ==="
kubectl get pvc -A
echo ""
echo "=== LONGHORN VOLUMES ==="
kubectl -n longhorn-system get volumes
echo ""
echo "=== EVENTS (recent) ==="
kubectl get events --sort-by='.lastTimestamp' -A | tail -20
```

---

## 7. Scaling Your Infrastructure

### Part A: Adding More Nodes

#### Adding a New Server Node (Control Plane)

This adds another control plane node (grows from 3 to 4, or 4 to 5, etc).

**Important:** Always add server nodes in odd numbers (3, 5, 7) for etcd quorum.

```bash
# On the new node:

# 1. Prepare the OS (same as original nodes)
#    - Disable swap
#    - Disable firewalld
#    - Disable SELinux
#    - Sync time

# 2. Run the server install script
sudo bash install-server.sh join <ANY-EXISTING-SERVER-IP>

# 3. Verify on any existing server:
kubectl get nodes
# New node should appear as Ready

# 4. Label for Longhorn (if it has a large disk):
kubectl label node <NEW-NODE> node.longhorn.io/create-default-disk=true
```

#### Adding a New Agent Node (Worker)

```bash
# On the new node:

# 1. Prepare the OS (same as original nodes)

# 2. Run the agent install script
sudo bash install-agent.sh <SERVER-IP> <NODE-TOKEN>

# 3. Verify:
kubectl get nodes
```

#### Scaling Recommendations

| Current Setup | Recommended Scaling | Why |
|--------------|---------------------|-----|
| 3 servers    | Add 2 agents        | More compute capacity |
| 5 nodes total| Add 2 more servers  | Better HA (5 etcd members) |
| 7 nodes      | Add agents as needed | Don't add more servers unless >10 nodes |

### Part B: Adding More Storage

#### Option 1: Add a New Disk to Existing Node

```bash
# 1. Attach new disk to the server (physically or via VM settings)

# 2. Find the disk name on the node:
lsblk
# Example output shows new disk as /dev/sdb

# 3. SSH into the node and add the disk to Longhorn:
# Via Longhorn UI:
#   - Go to Node page
#   - Click on the node
#   - Click "Edit Disks"
#   - Add new disk path: /dev/sdb
#   - Save

# Or via kubectl:
kubectl -n longhorn-system edit node <NODE-NAME>
# Add under spec.disks:
#   <disk-name>:
#     path: /dev/sdb
#     allowScheduling: true
#     tags: []
#     storageReserved: 0
```

#### Option 2: Expand Existing Disks

If your 2TB disks are running low, you can expand them:

```bash
# 1. Expand the disk at the VM/hypervisor level (e.g., 2TB → 4TB)

# 2. On the node, resize the partition:
sudo growpart /dev/sda 3    # Example: expand partition 3 of /dev/sda

# 3. Resize the filesystem:
sudo resize2fs /dev/sda3    # For ext4
# OR
sudo xfs_growfs /mount/point  # For XFS

# 4. Longhorn will automatically detect the new size
# Verify in Longhorn UI or:
kubectl -n longhorn-system get nodes -o yaml | grep -A 5 storageMaximum
```

#### Option 3: Add a Node with Storage

The easiest way to add storage capacity:

```bash
# 1. Add a new server node (see Part A above)

# 2. Make sure it has a large disk (2TB+)

# 3. Label it for Longhorn:
kubectl label node <NEW-NODE> node.longhorn.io/create-default-disk=true

# 4. Longhorn will automatically use the new disk for replicas
# Verify:
kubectl -n longhorn-system get nodes
```

### Part C: Increasing Replicas for Existing Volumes

If you want more safety for specific volumes:

```bash
# Edit a PVC to use more replicas (creates a new StorageClass or uses annotations)

# Method 1: Create a higher-replica StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-ha
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "5"  # 5 replicas instead of 3
  staleReplicaTimeout: "2880"
  fsType: "ext4"
  dataLocality: "best-effort"
EOF

# Then use this StorageClass for critical PVCs:
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: critical-data
spec:
  storageClassName: longhorn-ha  # Use the 5-replica class
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
EOF

# Method 2: Edit replica count for an existing volume via Longhorn UI
# Or via kubectl:
kubectl -n longhorn-system edit volume <VOLUME-NAME>
# Change: spec.numberOfReplicas: 5
```

### Part D: Node Maintenance (Removing a Node)

#### Draining a Node Before Removal

```bash
# 1. Cordon the node (stop new pods from scheduling on it)
kubectl cordon <NODE-NAME>

# 2. Drain the node (move all pods off it)
kubectl drain <NODE-NAME> --ignore-daemonsets --delete-emptydir-data

# 3. If it's a Longhorn node, disable scheduling first:
# Via Longhorn UI → Node → Edit → Disable Scheduling
# Or via kubectl:
kubectl -n longhorn-system patch node <NODE-NAME> -p '{"spec":{"allowScheduling":false}}'

# 4. Wait for replicas to migrate off the node
kubectl -n longhorn-system get replicas | grep <NODE-NAME>
# Wait until no replicas remain on this node

# 5. Remove the node from the cluster
kubectl delete node <NODE-NAME>

# 6. On the removed node, clean up RKE2:
sudo systemctl stop rke2-server   # or rke2-agent
sudo systemctl disable rke2-server  # or rke2-agent
sudo rm -rf /var/lib/rancher/rke2
sudo rm -rf /etc/rancher/rke2
```

---

## 8. Daily Operations Cheat Sheet

### Checking Cluster Status

```bash
# Set up kubectl (add to ~/.bashrc for convenience)
export PATH="/var/lib/rancher/rke2/bin:$PATH"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Node status
kubectl get nodes

# All running pods
kubectl get pods -A

# Resource usage (requires metrics-server)
kubectl top nodes
kubectl top pods -A

# Disk usage
kubectl -n longhorn-system get volumes
```

### Managing Applications

```bash
# Deploy an application
kubectl apply -f my-app.yaml

# See what's running
kubectl get deployments -A

# Scale an application
kubectl scale deployment my-app --replicas=3

# View application logs
kubectl logs deployment/my-app

# Delete an application
kubectl delete -f my-app.yaml
```

### Managing Storage

```bash
# List all PVCs
kubectl get pvc -A

# See Longhorn volumes
kubectl -n longhorn-system get volumes

# Check disk usage on Longhorn nodes
kubectl -n longhorn-system get nodes -o custom-columns=\
NAME:.metadata.name,\
DISK:.status.diskStatus

# Create a snapshot manually (via kubectl)
# Or use Longhorn UI: Volume → Create Snapshot
```

### Restarting Services

```bash
# Restart RKE2 server (do one at a time!)
sudo systemctl restart rke2-server

# Restart RKE2 agent
sudo systemctl restart rke2-agent

# Restart a Longhorn component
kubectl -n longhorn-system delete pod -l app=longhorn-manager
# It will restart automatically
```

---

## 9. Backup and Recovery

### Backing Up etcd (Cluster State)

RKE2 automatically takes etcd snapshots every 6 hours (configurable).

```bash
# Manual snapshot
sudo rke2 etcd-snapshot save --name manual-backup

# List snapshots
sudo rke2 etcd-snapshot ls

# Snapshots are stored at:
ls /var/lib/rancher/rke2/server/db/snapshots/
```

### Restoring etcd from Backup

```bash
# 1. Stop RKE2 on ALL server nodes
sudo systemctl stop rke2-server

# 2. On the node with the snapshot, restore:
sudo rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/<SNAPSHOT-NAME>

# 3. Start the restored node
sudo systemctl start rke2-server

# 4. On other server nodes, clean and rejoin:
sudo rm -rf /var/lib/rancher/rke2/server/db
sudo systemctl start rke2-server
```

### Backing Up Longhorn Volumes

```bash
# Via Longhorn UI:
# 1. Go to Volume page
# 2. Select a volume
# 3. Click "Create Backup"
# 4. Backups go to the configured backup target

# Configure a backup target (S3, NFS, etc):
# In Longhorn UI → Settings → Backup Target
# Example S3: s3://my-bucket@us-east-1/longhorn-backups
```

### Disaster Recovery Scenario

**Scenario:** SERVER-2 dies completely.

```bash
# 1. On remaining servers, check cluster health
kubectl get nodes
# SERVER-2 should show NotReady

# 2. After confirming it's dead, remove it:
kubectl delete node server-2

# 3. Check etcd is still healthy (2 of 3 is still a quorum)
kubectl -n kube-system get pods | grep etcd

# 4. Check Longhorn volumes are still accessible
kubectl -n longhorn-system get volumes
# All volumes should still be Healthy (2 of 3 replicas)

# 5. Set up a new SERVER-2 and join it:
sudo bash install-server.sh join <SERVER-1-IP>

# 6. Label for Longhorn if it has a 2TB disk:
kubectl label node server-2 node.longhorn.io/create-default-disk=true

# 7. Longhorn will automatically rebuild replicas on the new node
kubectl -n longhorn-system get replicas -w
```

---

## 10. Glossary

| Term | Plain English |
|------|---------------|
| **Kubernetes (K8s)** | Software that manages and runs your applications across multiple computers |
| **RKE2** | Rancher's version of Kubernetes, designed to be secure and easy |
| **Cluster** | A group of computers working together as one system |
| **Node** | One computer in the cluster |
| **Control Plane** | The "brain" nodes that manage the cluster (your SERVER-1, 2, 3) |
| **Worker Node** | A node that runs your applications (your AGENT-1, 2) |
| **etcd** | The database that remembers the state of everything in the cluster |
| **Pod** | A group of containers (your application running in the cluster) |
| **Deployment** | A template that tells Kubernetes how to run your application |
| **Service** | A stable network address to reach your application |
| **PVC** | Persistent Volume Claim — a request for storage |
| **PV** | Persistent Volume — actual storage space |
| **StorageClass** | A template for creating storage (like a recipe for PVCs) |
| **Longhorn** | The storage system that manages your 2TB disks |
| **Replica** | A copy of your data — you have 3 for safety |
| **CSI** | Container Storage Interface — how Kubernetes talks to storage |
| **CNI** | Container Network Interface — how pods talk to each other |
| **kubectl** | The command-line tool to talk to your Kubernetes cluster |
| **Helm** | A package manager for Kubernetes (like apt/yum for Kubernetes) |
| **NodePort** | A way to expose your application on a specific port on every node |
| **Taint/Toleration** | Rules about which nodes can run which pods |
| **Drain** | Moving all pods off a node so you can maintain it |
| **Cordon** | Marking a node so no new pods get scheduled on it |
| **Quorum** | The minimum number of nodes needed to make decisions (2 of 3 for etcd) |

---

## Quick Reference Card

```
┌──────────────────────────────────────────────────────────────────┐
│                     QUICK REFERENCE                              │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SET KUBECONFIG:                                                 │
│    export PATH="/var/lib/rancher/rke2/bin:$PATH"                │
│    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml                │
│                                                                  │
│  CHECK CLUSTER:                                                  │
│    kubectl get nodes                                             │
│    kubectl get pods -A                                           │
│                                                                  │
│  CHECK STORAGE:                                                  │
│    kubectl get pvc -A                                            │
│    kubectl -n longhorn-system get volumes                        │
│                                                                  │
│  RESTART RKE2:                                                   │
│    sudo systemctl restart rke2-server  # (server nodes)         │
│    sudo systemctl restart rke2-agent   # (agent nodes)          │
│                                                                  │
│  VIEW LOGS:                                                      │
│    sudo journalctl -u rke2-server -f   # (server nodes)         │
│    sudo journalctl -u rke2-agent -f    # (agent nodes)          │
│                                                                  │
│  LONGHORN UI:                                                    │
│    kubectl -n longhorn-system port-forward svc/longhorn-ui 8000 │
│    → http://localhost:8000                                       │
│                                                                  │
│  ETCD BACKUP:                                                    │
│    sudo rke2 etcd-snapshot save                                  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```
