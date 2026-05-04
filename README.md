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

**Why?** This decoupling allows you to upgrade the cluster (Talos OS) or change shared services (Ingress) without risk to the application code, and vice-versa.
```

## Nodes

| Role | IP | Interface |
|---|---|---|
| Control Plane | `192.168.0.54` | `enp0s1` |
| Worker | `192.168.0.55` | `enp0s1` |
| LB Pool | `192.168.0.240–250` | (kube-vip ARP) |

## Quick Start

```bash
make all      # bootstrap the entire cluster in one command
make hosts    # add local DNS entries
make status   # health check
make pass     # get ArgoCD admin password
```

## Virtualization (UTM on Apple Silicon)
| **Architecture** | ARM64 |
To run this cluster on a MacBook M1-M5 Pro, Max, or Ultra, use **UTM** with these optimized settings:

| Setting | Recommendation |
|---|---|
1. Create VM - Virtualize
2. Choose Linux
3. | **RAM** | 2GB per node (4GB recommended for Worker) | **CPU** | Default (Host) — 2 cores per node minimum |
4. Click Use Apple Virtualization
5. Boot ISO image fromhttps://factory.talos.dev/?platform=metal&target=metal
6. In image specification choose ARM image
7. In UTM settings choose minimum 10GB of storage
8. Set removable disk to talos ISO
8. In UTM network settings choose bridged (advanced)
9.  **Generate Cluster Secrets**: Run `make gen-config`. This creates your `controlplane.yaml`, `worker.yaml`, and `talosconfig`. **(Only do this once ever)**.
11. **Install CP**: Run `make install-cp` (enter the temporary UTM IP).
12. **Static IP**: When the VM reboots, eject the ISO. The node will take its static IP (`192.168.0.54`).
13. **Install Worker**: Create the second VM and run `make install-wk`.
14. **Initialize Cluster**: Run `make bootstrap` once both nodes are reachable it will take 2 minutes to initialize.
15. **Fetch Credentials**: Run `make creds` to get your `kubeconfig`.
16. **Deploy Stack**: Run `make sync` to install ArgoCD and all site manifests.
17. **Access**: Run `make hosts` and `make pass` to get into the dashboards.
18. **Sealing secrets**: Run `make seal P=secrets-plain.yaml S=iooding/k8s/sealed-secrets.yaml` to seal your secrets.
19. **Restoring master key**: Run `make fetch-key` to backup your master key. Run `make restore-key` to restore your master key.
20. **ArgoCD admin password**: Run `make pass` to get ArgoCD admin password.


## Make Targets

| Command | Description |
|---|---|
| `make all` | Full bootstrap: patch nodes → kubeconfig → ArgoCD → manifests |
| `make apply` | Push machine config patches to nodes |
| `make sync` | Bootstrap ArgoCD + apply all `manifests/` |
| `make creds` | Fetch kubeconfig from control plane |
| `make hosts` | Add `argocd.local` + `iooding.local` to `/etc/hosts` |
| `make pass` | Print ArgoCD initial admin password |
| `make status` | Quick cluster health overview |
| `make dash` | Open Talos dashboard |
| `make reboot` | Reboot all nodes |
| `make upgrade` | Upgrade Talos (set `TALOS_VERSION=vX.Y.Z`) |

## Bootstrap from Scratch (Totally New VM)

1.  **Create VM in UTM**: Use ARM64, Bridged Networking, and the Talos ISO.
2.  **Note the IP**: When the VM boots to the "Maintenance" screen, note the IP.
3.  **Run Install**:
    ```bash
    make install-cp  # When prompted, enter the IP from UTM
    ```
    The node will reboot and take its static IP (`192.168.0.54`).
4.  **Bootstrap**:
    ```bash
    make bootstrap   # Initializes etcd
    make creds       # Fetches the kubeconfig
    ```

## Maintenance (Existing Cluster)

If the cluster is already running and you just want to update settings in `patches/`:
```bash
make apply       # Re-patches the running configuration
```

## Upgrading

To keep your Mac and the entire cluster in sync, simply update `TALOS_VERSION` in the `Makefile` and run:

```bash
make upgrade
```
*(This one command updates your `talosctl` CLI via Homebrew and performs a rolling upgrade of the OS on all nodes).*

## Secret Management & Disaster Recovery (Sealed Secrets)

Your app uses **Sealed Secrets** to securely store passwords in Git. 

⚠️ **CRITICAL REBUILD WARNING:** Every time you delete and recreate your cluster, the Sealed Secrets controller generates a **brand new encryption key**. Your old encrypted secrets in Git will throw an `ErrUnsealFailed` because the new cluster cannot decrypt them!

You have two ways to fix this:

### Option A: The "Proper" Way (If you backed up the master key)
If you ran `make fetch-key` before deleting the old cluster, you have the old master key saved locally in `sealed-secrets-master.key`.
To inject the old master key into your new cluster so it can decrypt Git:
```bash
make restore-key
```

### Option B: The "Fresh" Way (If you lost the master key)
If you didn't back up the master key, you must re-encrypt your plain passwords using the new cluster's public key.

1. **Prepare the plain secret**: Create `secrets-plain.yaml` (ignored by git) with all your keys:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
       name: iooding-secrets
       namespace: iooding
   type: Opaque
   stringData:
       # Use this new secure key I generated for you
       django_secret_key: "django-insecure-pv^@u#y*v$h9*"
       # Your passwords
       username: "admin"
       password: "mydoadmanel12345!"
       db_password: "postgres1!"
       # Your AI token
       lm_studio_api_key: "sk-lm-ejbjmnr6:UZ"
   ```

2. **Seal and Commit**:
   ```bash
   make seal P=secrets-plain.yaml S=iooding/k8s/sealed-secrets.yaml
   git add iooding/k8s/sealed-secrets.yaml && git commit -m "update secrets" && git push
   ```

3. **Backup your New Master Key**:
   Run this now so you don't have to do Option B next time!
   ```bash
   make fetch-key
   ```

## Disaster Recovery (DR)

The files `controlplane.yaml`, `worker.yaml`, and `talosconfig` contain your cluster's **private keys and certificates**. 

*   **Backup**: Store these files in a secure location (e.g., Vault, 1Password).
*   **Loss**: If you lose these files, you cannot add new nodes to the existing cluster or recover it from scratch with the same identity.

## Bootstrap from Scratch (Day 0)

```bash
# 1. Generate machine configs (only if you don't have them)
# Warning: This creates a NEW cluster identity.
make gen-config 

# 2. Apply patches and bootstrap
make all

# 3. Add hosts entries
make hosts

# 4. Open ArgoCD
open https://argocd.local
make pass
```

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
