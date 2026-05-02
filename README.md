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

## Bootstrap from Scratch

```bash
# 1. Generate machine configs (first time only)
talosctl gen config my-cluster https://192.168.0.54:6443

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
