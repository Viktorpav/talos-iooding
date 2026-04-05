# talos-iooding

Personal **homelab Kubernetes** project — a Django blog + AI assistant deployed on a 2-node **Talos Linux** cluster, managed with **ArgoCD GitOps**.

```
talos-iooding/
├── talos/          ← Cluster configuration & ArgoCD manifests
│   ├── Makefile                 # All ops in one place
│   ├── patch-cp.yaml            # Control-plane machine config patch
│   ├── patch-worker.yaml        # Worker machine config patch
│   └── cluster-manifests/       # ArgoCD Application CRs
│       ├── sealed-secrets.yaml
│       ├── storage.yaml
│       ├── cert-manager.yaml
│       ├── kube-vip.yaml
│       ├── ingress-nginx.yaml
│       ├── argocd-ingress.yaml
│       └── iooding-app.yaml     # Points ArgoCD at k8s/manifests/
└── iooding/        ← Django application source
    ├── Dockerfile
    ├── requirements.txt
    ├── docker-entrypoint.sh
    ├── iooding/                 # Django project settings
    └── blog/                    # Blog + AI chat application
```

## Getting Started

```bash
cd talos/
make all      # bootstrap the entire cluster in one command
make hosts    # add local DNS entries
make status   # health check
```

See [`talos/README.md`](talos/README.md) for full cluster operations and [`iooding/README.md`](iooding/README.md) for the application guide.

## Tech Highlights

- **Talos Linux** — immutable, API-driven OS; no SSH, no shell
- **ArgoCD** — everything is GitOps, zero manual `kubectl apply`
- **kube-vip** — real LoadBalancer IPs on bare-metal (ARP mode)
- **local-path-provisioner** — lightweight persistent storage (no Longhorn RAM overhead)
- **Sealed Secrets** — secrets committed safely to Git
- **Django ASGI** — async views + Server-Sent Events for AI chat streaming
- **Redis Stack** — vector search for RAG without a separate vector DB
