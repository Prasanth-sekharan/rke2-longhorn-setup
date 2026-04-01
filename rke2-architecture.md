# RKE2 Cluster Architecture (3 + 2 Node) with Longhorn Storage

## Topology Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         LOAD BALANCER / VIP                                  │
│                        (API Server :6443)                                    │
└────────────┬─────────────────────┬──────────────────────┬───────────────────┘
             │                     │                      │
     ┌───────┴────────┐   ┌───────┴────────┐    ┌────────┴───────┐
     │   SERVER-1     │   │   SERVER-2     │    │   SERVER-3     │
     │ CP + ETCD +    │   │ CP + ETCD +    │    │ CP + ETCD +    │
     │    WORKER      │   │    WORKER      │    │    WORKER      │
     │                │   │                │    │                │
     │ ┌────────────┐ │   │ ┌────────────┐ │    │ ┌────────────┐ │
     │ │kube-api    │ │   │ │kube-api    │ │    │ │kube-api    │ │
     │ │scheduler   │ │   │ │scheduler   │ │    │ │scheduler   │ │
     │ │controller  │ │   │ │controller  │ │    │ │controller  │ │
     │ │etcd        │ │   │ │etcd        │ │    │ │etcd        │ │
     │ │kubelet     │ │   │ │kubelet     │ │    │ │kubelet     │ │
     │ │kube-proxy  │ │   │ │kube-proxy  │ │    │ │kube-proxy  │ │
     │ └────────────┘ │   │ └────────────┘ │    │ └────────────┘ │
     │                │   │                │    │                │
     │ ┌────────────┐ │   │ ┌────────────┐ │    │ ┌────────────┐ │
     │ │ Longhorn   │ │   │ │ Longhorn   │ │    │ │ Longhorn   │ │
     │ │ Manager    │ │   │ │ Manager    │ │    │ │ Manager    │ │
     │ │ Replica    │ │   │ │ Replica    │ │    │ │ Replica    │ │
     │ │ 2TB Disk   │ │   │ │ 2TB Disk   │ │    │ │ 2TB Disk   │ │
     │ └────────────┘ │   │ └────────────┘ │    │ └────────────┘ │
     └───────┬────────┘   └───────┬────────┘    └────────┬───────┘
             │                     │                      │
     ┌───────┴────────┐   ┌───────┴────────┐             │
     │   AGENT-1      │   │   AGENT-2      │             │
     │   WORKER       │   │   WORKER       │             │
     │                │   │                │             │
     │ ┌────────────┐ │   │ ┌────────────┐ │             │
     │ │kubelet     │ │   │ │kubelet     │ │             │
     │ │kube-proxy  │ │   │ │kube-proxy  │ │             │
     │ └────────────┘ │   │ └────────────┘ │             │
     │                │   │                │             │
     │ ┌────────────┐ │   │ ┌────────────┐ │             │
     │ │ Longhorn   │ │   │ │ Longhorn   │ │             │
     │ │ Manager    │ │   │ │ Manager    │ │             │
     │ └────────────┘ │   │ └────────────┘ │             │
     └────────────────┘   └────────────────┘             │
                                                          │
         ┌────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   LONGHORN STORAGE NETWORK                      │
│             (Replication Traffic - Dedicated NIC/VLAN)          │
└─────────────────────────────────────────────────────────────────┘
```

## Longhorn Data Replication Architecture

```
                    ┌─────────────────────────┐
                    │     Longhorn Volume     │
                    │    (PersistentVolume)   │
                    │                         │
                    │  "mysql-data-pv"        │
                    │  Size: 100Gi            │
                    │  Replicas: 3            │
                    └────────────┬────────────┘
                                 │
           ┌─────────────────────┼─────────────────────┐
           │                     │                     │
           ▼                     ▼                     ▼
    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
    │  Replica 1   │    │  Replica 2   │    │  Replica 3   │
    │  SERVER-1    │    │  SERVER-2    │    │  SERVER-3    │
    │              │    │              │    │              │
    │ /var/lib/    │    │ /var/lib/    │    │ /var/lib/    │
    │ longhorn/    │    │ longhorn/    │    │ longhorn/    │
    │ volumes/     │    │ volumes/     │    │ volumes/     │
    │              │    │              │    │              │
    │ (2TB disk)   │◄──►│ (2TB disk)   │◄──►│ (2TB disk)   │
    └──────────────┘    └──────────────┘    └──────────────┘
           ▲                     ▲                     ▲
           │                     │                     │
           └─────────────────────┴─────────────────────┘
                  Sync / Replicate Data
```

## PV / PVC Provisioning Flow

```
  Pod ──► PVC ──► StorageClass (longhorn) ──► Longhorn CSI ──► Volume ──► Replicas
                    │                                               │
                    │  Default Settings:                            │  Replica Count: 3
                    │  - numberOfReplicas: 3                        │  Spread across
                    │  - staleReplicaTimeout: 2880                  │  SERVER-1,2,3
                    │  - fsType: ext4                               │
                    │  - dataLocality: best-effort                  │
```

## Node Roles & Storage

| Node      | Role                   | Workloads | Storage         | Disk  |
|-----------|------------------------|-----------|-----------------|-------|
| SERVER-1  | CP + ETCD + WORKER     | ✅ Yes    | Longhorn Replica| 2TB   |
| SERVER-2  | CP + ETCD + WORKER     | ✅ Yes    | Longhorn Replica| 2TB   |
| SERVER-3  | CP + ETCD + WORKER     | ✅ Yes    | Longhorn Replica| 2TB   |
| AGENT-1   | WORKER                 | ✅ Yes    | Longhorn Manager| Local |
| AGENT-2   | WORKER                 | ✅ Yes    | Longhorn Manager| Local |

## Quorum & Fault Tolerance

- **ETCD Quorum**: 3 nodes → tolerates 1 failure
- **Longhorn Replicas**: 3 replicas → tolerates 2 replica failures (data on 3 separate disks)
- **Workloads**: All 5 nodes are schedulable for pods

---

## Deployment Order

```
Step 1: Install SERVER-1 (bootstrap)
  $ sudo ./scripts/install-server.sh bootstrap

Step 2: Install SERVER-2 (join)
  $ sudo ./scripts/install-server.sh join <SERVER-1-IP>

Step 3: Install SERVER-3 (join)
  $ sudo ./scripts/install-server.sh join <SERVER-1-IP>

Step 4: Install AGENT-1
  $ sudo ./scripts/install-agent.sh <SERVER-1-IP> <NODE-TOKEN>

Step 5: Install AGENT-2
  $ sudo ./scripts/install-agent.sh <SERVER-1-IP> <NODE-TOKEN>

Step 6: Install Longhorn (from any server node with kubectl)
  $ sudo ./scripts/install-longhorn.sh

Step 7: Apply StorageClasses & sample workloads
  $ sudo ./scripts/setup-complete.sh
```

## Files

```
rke2-setup/
├── scripts/
│   ├── install-server.sh       # Run on SERVER-1,2,3
│   ├── install-agent.sh        # Run on AGENT-1,2
│   ├── install-longhorn.sh     # Run after all nodes join
│   └── setup-complete.sh       # Apply manifests
├── manifests/
│   ├── storageclass.yaml       # 3 StorageClasses (3-replica default)
│   └── sample-workloads.yaml   # PVC + Pod + MySQL StatefulSet
└── longhorn-values.yaml        # Helm values for Longhorn
```
