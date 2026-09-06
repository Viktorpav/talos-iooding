# Cluster Configuration
CP             := 192.168.0.54
WK             := 192.168.0.55
LB_IP          := 192.168.0.240
TALOSCTL       := talosctl --talosconfig talosconfig
ARGOCD_VERSION ?= stable
TALOS_VERSION  ?= v1.14.0
K8S_VERSION    ?= 1.36.0

# Image Configuration
IMG            ?= viktor2003/iooding
TAG            ?= $(shell cd iooding && git rev-parse --short HEAD)

# Environment
# KUBECONFIG is handled by talosctl merging into ~/.kube/config automatically

.PHONY: help all apply creds sync hosts pass dash status reboot upgrade upgrade-k8s backup-etcd backup-db restore-db seal fetch-key restore-key build deploy

# ==============================================================================
# 📋 General
# ==============================================================================

help: ## Show this help menu
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

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
	$(TALOSCTL) apply-config --nodes $(CP) --file controlplane.yaml --config-patch @patches/controlplane.yaml
	$(TALOSCTL) apply-config --nodes $(WK) --file worker.yaml --config-patch @patches/worker.yaml

creds: ## Sync cluster credentials to global ~/.kube/config
	$(TALOSCTL) kubeconfig --nodes $(CP) --force

upgrade: ## Upgrade both CLI and Cluster OS
	@brew update && brew upgrade siderolabs/tap/talosctl || true
	$(TALOSCTL) upgrade --nodes $(CP) --image ghcr.io/siderolabs/installer:$(TALOS_VERSION)
	$(TALOSCTL) upgrade --nodes $(WK) --image ghcr.io/siderolabs/installer:$(TALOS_VERSION)

upgrade-k8s: ## Upgrade Kubernetes cluster version
	$(TALOSCTL) upgrade-k8s --nodes $(CP) --to $(K8S_VERSION)

backup-etcd: ## Take an etcd snapshot of the control plane
	@mkdir -p backups
	$(TALOSCTL) etcd snapshot backups/etcd-$$(date +%Y%m%d-%H%M%S).snapshot --nodes $(CP)
	@echo "✅ etcd snapshot saved to backups/"

reboot: ## Reboot all cluster nodes
	$(TALOSCTL) reboot --nodes $(CP),$(WK)

dash: ## Open the Talos dashboard
	$(TALOSCTL) dashboard --nodes $(CP)

status: ## Show cluster health overview
	@echo "\n=== 🖥️  Nodes ===" && kubectl get nodes -o wide
	@echo "\n=== 💾 Persistent Volumes ===" && kubectl get pvc -A
	@echo "\n=== 📜 Certificates ===" && kubectl get certificate,clusterissuer -A
	@echo "\n=== ⛵ ArgoCD Apps ===" && kubectl get app -n argocd || true
	@echo "\n=== ⚠️  Non-Running Pods ===" && kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded' || true

# ==============================================================================
# ⛵ Kubernetes & GitOps
# ==============================================================================

sync: creds ## Install ArgoCD and apply bootstrap manifests
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VERSION)/manifests/install.yaml
	@echo "⏳ Waiting for ArgoCD..."
	kubectl rollout status deploy/argocd-server -n argocd --timeout=180s
	@echo "🔧 Pre-installing cert-manager CRDs to satisfy ClusterIssuer validation..."
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.crds.yaml
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
	@test -f sealed-secrets-master.key || (echo "❌ Error: sealed-secrets-master.key not found" && exit 1)
	@kubectl apply -f sealed-secrets-master.key
	@kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets

# ==============================================================================
# 💾 Database Operations
# ==============================================================================

backup-db: ## Dump PostgreSQL database to backups/
	@mkdir -p backups
	@kubectl exec -n iooding statefulset/postgres -c postgres -- pg_dump -U iooding iooding | gzip > backups/postgres-$$(date +%Y%m%d-%H%M%S).sql.gz
	@echo "✅ Database dumped to backups/"

restore-db: ## Restore PostgreSQL database (Usage: make restore-db F=backups/file.sql.gz)
	@if [ -z "$(F)" ]; then echo "❌ Error: Specify dump file with F=backups/file.sql.gz"; exit 1; fi
	@test -f "$(F)" || (echo "❌ Error: File $(F) not found" && exit 1)
	gunzip -c $(F) | kubectl exec -i -n iooding statefulset/postgres -c postgres -- psql -U iooding -d iooding
	@echo "✅ Database restored from $(F)"

# ==============================================================================
# 📦 Application
# ==============================================================================

build: ## Build and push app image
	cd iooding && docker build --platform linux/arm64 -t $(IMG):v$(TAG) .
	docker push $(IMG):v$(TAG)

deploy: build ## Build, push, and update manifests
	sed -i '' 's|image: $(IMG):.*|image: $(IMG):v$(TAG)|g' iooding/k8s/deployment.yaml
