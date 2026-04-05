## ─── Config ──────────────────────────────────────────────────────────────────
CP     := 192.168.0.54
WK     := 192.168.0.55
LB_IP  := 192.168.0.240
T      := talosctl --talosconfig talosconfig
ARGOCD_VERSION ?= stable

.PHONY: all apply creds sync hosts pass dash reboot upgrade status

## ─── Default: full bootstrap ─────────────────────────────────────────────────
all: apply creds sync
	@echo "✅  Cluster ready. Access:"
	@echo "    ArgoCD → https://argocd.local   (run: make pass)"
	@echo "    App    → https://iooding.local"

## ─── OS layer: push machine configs ─────────────────────────────────────────
apply:
	$(T) patch mc --nodes $(CP) -p @patch-cp.yaml
	$(T) patch mc --nodes $(WK) -p @patch-worker.yaml

## ─── Bootstrap ArgoCD + apply all manifests ─────────────────────────────────
sync: creds
	@echo "⏳  Waiting for Kubernetes API..."
	@until kubectl cluster-info >/dev/null 2>&1; do sleep 5; printf '.'; done; echo
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply --server-side -n argocd \
	  -f https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VERSION)/manifests/install.yaml
	@echo "⏳  Waiting for ArgoCD server..."
	kubectl rollout status deploy/argocd-server -n argocd --timeout=180s
	kubectl apply -f cluster-manifests/

## ─── Utilities ───────────────────────────────────────────────────────────────
creds:
	$(T) kubeconfig . --nodes $(CP)

hosts:
	@echo "📌  Updating /etc/hosts → $(LB_IP)"
	@sudo sed -i '' '/argocd\.local/d;/iooding\.local/d' /etc/hosts
	@printf "$(LB_IP) argocd.local\n$(LB_IP) iooding.local\n" | sudo tee -a /etc/hosts

pass:
	@kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath="{.data.password}" | base64 -d && echo

dash:
	$(T) dashboard --nodes $(CP)

status:
	@echo "=== Nodes ===" && kubectl get nodes -o wide
	@echo "=== ArgoCD Apps ===" && kubectl get app -n argocd
	@echo "=== Pods (non-running) ===" && \
	  kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' 2>/dev/null || true

reboot:
	$(T) reboot --nodes $(CP),$(WK)

## ─── Cluster upgrade ─────────────────────────────────────────────────────────
TALOS_VERSION ?= v1.9.5

upgrade:
	@echo "🔄  Upgrading to Talos $(TALOS_VERSION)..."
	$(T) upgrade --nodes $(CP) --image ghcr.io/siderolabs/talos:$(TALOS_VERSION) --preserve=true
	@echo "⏳  Waiting for control-plane..." && sleep 45
	$(T) upgrade --nodes $(WK) --image ghcr.io/siderolabs/talos:$(TALOS_VERSION) --preserve=true
	@echo "✅  Upgrade complete"
