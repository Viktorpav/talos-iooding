# ==============================================================================
# Configuration
# ==============================================================================
CP             := 192.168.0.54
WK             := 192.168.0.55
LB_IP          := 192.168.0.240
TALOSCTL       := talosctl --talosconfig talosconfig
ARGOCD_VERSION ?= stable
TALOS_VERSION  ?= v1.9.5

# Export KUBECONFIG so that all kubectl commands use the local kubeconfig securely
export KUBECONFIG := $(shell pwd)/kubeconfig

# ==============================================================================
# Main Targets
# ==============================================================================
.PHONY: help all apply creds sync hosts pass dash status reboot upgrade

help: ## Show this help menu
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

all: apply creds sync ## Full bootstrap (apply patches, fetch creds, sync ArgoCD)
	@echo "✅  Cluster ready. Access:"
	@echo "    ArgoCD → https://argocd.local   (run: make pass)"
	@echo "    App    → https://iooding.local"

# ==============================================================================
# Talos OS Layer
# ==============================================================================
apply: ## Push machine configs to control-plane and worker nodes
	$(TALOSCTL) patch mc --nodes $(CP) -p @patch-cp.yaml
	$(TALOSCTL) patch mc --nodes $(WK) -p @patch-worker.yaml

creds: ## Fetch/Sync kubeconfig to have valid client cert & endpoint config
	$(TALOSCTL) kubeconfig . --nodes $(CP) --force
	@echo "✅ Kubeconfig synced to $${KUBECONFIG}"

dash: ## Open the Talos dashboard
	$(TALOSCTL) dashboard --nodes $(CP)

reboot: ## Reboot control-plane and worker nodes
	$(TALOSCTL) reboot --nodes $(CP),$(WK)

upgrade: ## Upgrade Talos OS on all nodes
	@echo "🔄  Upgrading to Talos $(TALOS_VERSION)..."
	$(TALOSCTL) upgrade --nodes $(CP) --image ghcr.io/siderolabs/talos:$(TALOS_VERSION) --preserve=true
	@echo "⏳  Waiting for control-plane..." && sleep 45
	$(TALOSCTL) upgrade --nodes $(WK) --image ghcr.io/siderolabs/talos:$(TALOS_VERSION) --preserve=true
	@echo "✅  Upgrade complete"

# ==============================================================================
# Kubernetes / ArgoCD Layer
# ==============================================================================
sync: creds ## Bootstrap ArgoCD and apply all cluster manifests
	@echo "⏳  Waiting for Kubernetes API..."
	@until kubectl cluster-info >/dev/null 2>&1; do sleep 5; printf '.'; done; echo
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply --server-side -n argocd \
	  -f https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VERSION)/manifests/install.yaml
	@echo "⏳  Waiting for ArgoCD server..."
	kubectl rollout status deploy/argocd-server -n argocd --timeout=180s
	kubectl apply -f cluster-manifests/

status: ## Show cluster status (Nodes, ArgoCD Apps, failed Pods)
	@echo "=== Nodes ===" && kubectl get nodes -o wide
	@echo "=== ArgoCD Apps ===" && kubectl get app -n argocd || true
	@echo "=== Pods (non-running) ===" && \
	  kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' 2>/dev/null || true

pass: ## Retrieve the initial ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath="{.data.password}" | base64 -d && echo

# ==============================================================================
# Utilities
# ==============================================================================
hosts: ## Update /etc/hosts for local domains (requires sudo)
	@echo "📌  Updating /etc/hosts → $(LB_IP)"
	@sudo sed -i '' '/argocd\.local/d;/iooding\.local/d' /etc/hosts
	@printf "$(LB_IP) argocd.local\n$(LB_IP) iooding.local\n" | sudo tee -a /etc/hosts
