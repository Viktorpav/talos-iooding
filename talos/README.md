# Talos Cluster — Operations Guide

Source of truth for the 2-node **Talos Linux** Kubernetes cluster running the iooding stack.

## Nodes

| Role | IP | Interface |
|---|---|---|
| Control Plane | `192.168.0.54` | `enp0s1` |
| Worker | `192.168.0.55` | `enp0s1` |
| LB Pool | `192.168.0.240–250` | (kube-vip ARP) |

## Make Targets

| Command | Description |
|---|---|
| `make all` | Full bootstrap: patch nodes → kubeconfig → ArgoCD → manifests |
| `make apply` | Push machine config patches to nodes |
| `make sync` | Bootstrap ArgoCD + apply all `cluster-manifests/` |
| `make creds` | Fetch kubeconfig from control plane |
| `make hosts` | Add `argocd.local` + `iooding.local` to `/etc/hosts` |
| `make pass` | Print ArgoCD initial admin password |
| `make status` | Quick cluster health overview |
| `make dash` | Open Talos dashboard |
| `make reboot` | Reboot all nodes |
| `make upgrade` | Upgrade Talos (set `TALOS_VERSION=vX.Y.Z`) |

## Cluster Manifests (ArgoCD Apps)

| File | What it deploys |
|---|---|
| `sealed-secrets.yaml` | Sealed Secrets controller (wave 0) |
| `storage.yaml` | local-path-provisioner + StorageClass (wave 0) |
| `cert-manager.yaml` | cert-manager + internal CA issuer (wave 0–3) |
| `kube-vip.yaml` | kube-vip DaemonSet + cloud-provider (ARP LB) |
| `ingress-nginx.yaml` | ingress-nginx controller (wave 1) |
| `argocd-ingress.yaml` | Ingress for ArgoCD UI (`argocd.local`) |
| `iooding-app.yaml` | ArgoCD App pointing to `k8s/manifests/` |

## Node Patches

Patches are applied with:
```bash
talosctl patch mc --nodes <IP> -p @patch-<role>.yaml
```

Both patches configure:
- Static IPs, DNS (`8.8.8.8`, `1.1.1.1`), gateway
- NTP (`time.cloudflare.com`)
- inotify sysctls (needed for ArgoCD/watchers)
- Network hardening sysctls
- `kubeReserved` + `systemReserved` + `evictionHard` (prevents OOM on low-RAM VMs)
- Container log rotation (10 MiB, 3 files)

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

## Useful One-Liners

```bash
# Watch all pods
kubectl get pods -A -w

# Tail ArgoCD logs
kubectl logs -n argocd deploy/argocd-server -f

# Force ArgoCD sync
kubectl -n argocd patch app iooding-app -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}' --type merge

# Check kube-vip IP assignments
kubectl get svc -A --field-selector spec.type=LoadBalancer
```
