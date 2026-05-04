# talos-iooding

Homelab **Kubernetes infrastructure** — a 2-node **Talos Linux** cluster managed with **ArgoCD GitOps**.

This repo contains **only the cluster infrastructure**. The application source lives in a [separate repo](https://github.com/Viktorpav/iooding).

```
talos-iooding/
├── Makefile                     # All cluster ops in one place
├── patches/
│   ├── controlplane.yaml        # Control-plane machine config patch
│   └── worker.yaml              # Worker machine config patch
└── manifests/                   # ArgoCD Application CRs (applied via make sync)
    ├── sealed-secrets.yaml      # Sealed Secrets controller
    ├── storage.yaml             # local-path-provisioner + StorageClass
    ├── cert-manager.yaml        # cert-manager + internal CA
    ├── kube-vip.yaml            # kube-vip DaemonSet + cloud provider (ARP LB)
    ├── ingress-nginx.yaml       # Ingress controller
    ├── argocd-ingress.yaml      # ArgoCD UI ingress (argocd.local)
    └── iooding-app.yaml         # Points ArgoCD → github.com/Viktorpav/iooding (k8s/)

## Repository Architecture

This project is split into two independent repositories to separate infrastructure concerns from application logic:

1.  **`talos-iooding` (This repo)**: Manages the cluster OS (Talos), core networking, shared storage, and ArgoCD bootstrap manifests.
2.  **`iooding` ([App repo](https://github.com/Viktorpav/iooding))**: Contains the Django source code and its specific Kubernetes deployment manifests (`k8s/`).

**Why?** This decoupling allows you to upgrade the cluster (Talos OS) or change shared services (Ingress) without risk to the application code.

---

## 🚀 Day 0: Fresh Cluster Installation

Follow these steps perfectly in order to build the cluster from scratch.

### 1. Virtualization Setup (UTM on Apple Silicon)
To run this cluster on an Apple Silicon Mac, use **UTM** with these optimized settings:
1. Create VM -> Virtualize -> Linux
2. **RAM**: 2GB for Control Plane (4GB recommended for Worker) | **CPU**: Minimum 2 cores
3. Check "Use Apple Virtualization"
4. Boot ISO image from: `https://factory.talos.dev/?platform=metal&target=metal` (Choose ARM64)
5. Disk: Minimum 10GB of storage.
6. **Network**: **Bridged (Advanced)**

### 2. Generate OS Configurations
Run this **only once** to generate your cryptographic certificates and configurations. It will automatically inject your local DNS (`192.168.0.1`) to fix UTM Bridged network drops:
```bash
make gen-config
```

### 3. Boot the Nodes
1. Boot the **Control Plane VM** from the ISO. Note the IP shown on the screen.
   ```bash
   make install-cp  # Enter the IP when prompted
   ```
   *Eject the ISO when it reboots. It will take the static IP `192.168.0.54`.*
2. Boot the **Worker VM** from the ISO. Note the IP shown on the screen.
   ```bash
   make install-wk  # Enter the IP when prompted
   ```
   *Eject the ISO when it reboots. It will take the static IP `192.168.0.55`.*

### 4. Bootstrap Kubernetes
Once both nodes are running, initialize the `etcd` database and fetch your admin credentials:
```bash
make bootstrap
make creds
```

### 5. 🔐 INJECT SECRETS (CRITICAL)
Before you deploy your application, you **must** provide the encryption keys. Every time a cluster is rebuilt, it generates a new master encryption key. 

*   **If you previously backed up your key:**
    ```bash
    make restore-key
    ```
*   **If this is your first time (or you lost the backup):**
    1. Create `secrets-plain.yaml` locally (do not commit this):
       ```yaml
       apiVersion: v1
       kind: Secret
       metadata: { name: iooding-secrets, namespace: iooding }
       type: Opaque
       stringData:
           django_secret_key: "your-key"
           username: "admin"
           password: "your-password"
           db_password: "your-db-password"
           lm_studio_api_key: "your-ai-token"
       ```
    2. Encrypt them using the new cluster's public key:
       ```bash
       make seal P=secrets-plain.yaml S=iooding/k8s/sealed-secrets.yaml
       git add iooding/k8s/sealed-secrets.yaml && git commit -m "update secrets" && git push
       ```
    3. **Backup your new key immediately:**
       ```bash
       make fetch-key
       ```

### 6. Deploy the Application Stack
Now that the cluster is running and secrets are injected, deploy ArgoCD. It will automatically install the database, ingress, cert-manager, and your application:
```bash
make sync
```

### 7. Access your Site
Map the internal load balancer to your Mac's DNS, and fetch the ArgoCD login password:
```bash
make hosts
make pass
```
You can now visit `https://argocd.local` and `https://iooding.local`!

---

## 🛠️ Day 2: Operations & Maintenance

| Command | Description |
|---|---|
| `make apply` | Push updates from `patches/` directly to the running nodes without rebooting. |
| `make upgrade` | Performs a zero-downtime rolling upgrade of Talos OS on all nodes (Set `TALOS_VERSION` in Makefile). |
| `make status` | Quick cluster health overview (Nodes, ArgoCD, Failed Pods). |
| `make reboot` | Gracefully restart both nodes. |
| `make dash` | Open the native Talos metrics dashboard. |

## Disaster Recovery (DR)

The files `controlplane.yaml`, `worker.yaml`, and `talosconfig` contain your cluster's **private keys and certificates**. 

*   **Backup**: Store these files in a secure location (e.g., Vault, 1Password).
*   **Loss**: If you lose these files, you cannot add new nodes to the existing cluster or recover it from scratch with the same identity.



## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    GitHub (GitOps)                        │
│                                                          │
│  Viktorpav/talos-iooding  ──→  Cluster infra manifests   │
│  Viktorpav/iooding        ──→  App K8s manifests (k8s/)  │
└──────────────┬──────────────────────────┬────────────────┘
               │                          │
               ▼                          ▼
┌─────────────────────┐    ┌──────────────────────────────┐
│      ArgoCD         │    │    ArgoCD: iooding-app        │
│  (cluster infra)    │    │  (syncs from iooding repo)    │
│                     │    │                                │
│  • kube-vip         │    │  • Django deployment           │
│  • ingress-nginx    │    │  • PostgreSQL StatefulSet      │
│  • cert-manager     │    │  • Redis StatefulSet           │
│  • sealed-secrets   │    │  • Ingress                     │
│  • storage          │    │  • Secrets                     │
└─────────────────────┘    └──────────────────────────────┘
```

## Tech Highlights

- **Talos Linux** — immutable, API-driven OS; no SSH, no shell.
- **ArgoCD** — everything is GitOps, zero manual `kubectl apply`.
- **Real-Time AI Streaming** — Nginx Ingress and Gunicorn specifically tuned for low-latency token delivery (gzip off, buffering off).
- **kube-vip ARP mode** — provides real LoadBalancer IPs on bare-metal without a cloud provider.
- **local-path-provisioner** — lightweight persistent storage (no Longhorn RAM overhead).
- **Sealed Secrets** — secrets committed safely to Git.
- **Redis Stack** — vector search for RAG without a separate vector DB.

## Useful One-Liners

```bash
# Watch all pods
kubectl get pods -A -w

# Tail ArgoCD logs
kubectl logs -n argocd deploy/argocd-server -f

# Force ArgoCD sync (trigger polling immediately)
argocd app sync iooding-app --force

# Check Nginx configuration inside the controller
kubectl exec -n ingress-nginx <controller-pod> -- nginx -T | grep -A 50 "iooding.local"
```
