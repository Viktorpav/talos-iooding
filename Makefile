# Cluster Configuration
CP             := 192.168.0.54
WK             := 192.168.0.55
LB_IP          := 192.168.0.240
TALOSCTL       := talosctl --talosconfig talosconfig
ARGOCD_VERSION ?= stable
TALOS_VERSION  ?= v1.13.0

# Image Configuration
IMG            ?= viktor2003/iooding
TAG            ?= $(shell cd iooding && git rev-parse --short HEAD)

# Environment
export KUBECONFIG := $(shell pwd)/kubeconfig

.PHONY: help all apply creds sync hosts pass dash status reboot upgrade seal fetch-key restore-key build deploy

# ==============================================================================
# 📋 General
# ==============================================================================

help: ## Show this help menu
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

all: apply creds sync ## Full bootstrap (Apply configs -> Credentials -> ArgoCD)
	@echo "✅ Cluster ready. App at https://iooding.local"

# ==============================================================================
# 🏗️ Talos OS Layer (Installation)
# ==============================================================================

gen-config: ## Generate base machine configs and talosconfig
	@echo "⚠️  Generating NEW cluster secrets..."
	talosctl gen config iooding https://$(CP):6443 --output-dir . --force
	$(TALOSCTL) config endpoint $(CP)
	$(TALOSCTL) config node $(CP)

config: ## Repair talosctl configuration context
	$(TALOSCTL) config endpoint $(CP)
	$(TALOSCTL) config node $(CP)

install-cp: ## Install Talos on a NEW Control Plane (UTM ISO mode)
	@if [ ! -f controlplane.yaml ]; then echo "❌ Error: controlplane.yaml missing. Run 'make gen-config'"; exit 1; fi
	@read -p "Enter UTM ISO IP: " IP; \
	talosctl apply-config --insecure --nodes $$IP --file controlplane.yaml --config-patch @patches/controlplane.yaml

install-wk: ## Install Talos on a NEW Worker (UTM ISO mode)
	@if [ ! -f worker.yaml ]; then echo "❌ Error: worker.yaml missing. Run 'make gen-config'"; exit 1; fi
	@read -p "Enter UTM ISO IP: " IP; \
	talosctl apply-config --insecure --nodes $$IP --file worker.yaml --config-patch @patches/worker.yaml

bootstrap: ## Initialize etcd (Run once after install-cp)
	$(TALOSCTL) bootstrap --nodes $(CP)

# ==============================================================================
# ⚙️ Talos OS Layer (Maintenance)
# ==============================================================================

apply: ## Update machine configurations via patches
	$(TALOSCTL) patch mc --nodes $(CP) -p @patches/controlplane.yaml
	$(TALOSCTL) patch mc --nodes $(WK) -p @patches/worker.yaml

creds: ## Sync cluster credentials to local kubeconfig
	$(TALOSCTL) kubeconfig . --nodes $(CP) --force

upgrade: ## Upgrade both CLI and Cluster OS
	brew update && brew upgrade siderolabs/tap/talosctl
	$(TALOSCTL) upgrade --nodes $(CP) --image ghcr.io/siderolabs/talos:$(TALOS_VERSION) --preserve=true
	$(TALOSCTL) upgrade --nodes $(WK) --image ghcr.io/siderolabs/talos:$(TALOS_VERSION) --preserve=true

reboot: ## Reboot all cluster nodes
	$(TALOSCTL) reboot --nodes $(CP),$(WK)

dash: ## Open the Talos dashboard
	$(TALOSCTL) dashboard --nodes $(CP)

status: ## Show cluster health overview
	@echo "=== Nodes ===" && kubectl get nodes -o wide
	@echo "=== ArgoCD Apps ===" && kubectl get app -n argocd || true
	@echo "=== Failed Pods ===" && kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' || true

# ==============================================================================
# ⛵ Kubernetes & GitOps
# ==============================================================================

sync: creds ## Install ArgoCD and apply bootstrap manifests
	@echo "⏳ Waiting for API..."
	@until kubectl cluster-info >/dev/null 2>&1; do sleep 5; printf '.'; done; echo
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VERSION)/manifests/install.yaml
	@echo "⏳ Waiting for ArgoCD..."
	kubectl rollout status deploy/argocd-server -n argocd --timeout=180s
	kubectl apply -f manifests/

pass: ## Get ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

hosts: ## Update /etc/hosts (requires sudo)
	@echo "📌 Updating /etc/hosts..."
	@sudo sed -i '' '/argocd\.local/d;/iooding\.local/d' /etc/hosts
	@printf "$(LB_IP) argocd.local\n$(LB_IP) iooding.local\n" | sudo tee -a /etc/hosts

# ==============================================================================
# 🔐 Secret Management
# ==============================================================================

seal: ## Encrypt secret (Usage: make seal P=plain.yaml S=sealed.yaml)
	@if [ -z "$(P)" ] || [ -z "$(S)" ]; then \
		read -p "Plain secret path: " P_IN; \
		read -p "Sealed secret path: " S_OUT; \
		kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format=yaml < $$P_IN > $$S_OUT; \
	else \
		kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format=yaml < $(P) > $(S); \
	fi
	@echo "✅ Secret sealed. You can now safely commit the destination file."

fetch-key: ## Backup Sealed Secrets master key
	@kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-master.key

restore-key: ## Restore Sealed Secrets master key
	@kubectl apply -f sealed-secrets-master.key
	@kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets

# ==============================================================================
# 📦 Application
# ==============================================================================

build: ## Build and push app image
	cd iooding && docker build --platform linux/arm64 -t $(IMG):v$(TAG) .
	docker push $(IMG):v$(TAG)

deploy: build ## Build, push, and update manifests
	sed -i '' 's|image: $(IMG):.*|image: $(IMG):v$(TAG)|g' iooding/k8s/deployment.yaml
