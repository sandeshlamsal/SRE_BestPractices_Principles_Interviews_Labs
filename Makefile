CLUSTER   := sre-lab
NAMESPACE := astronomy-shop
RELEASE   := shop

.PHONY: help cluster-up cluster-down deploy undeploy status open

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-14s %s\n", $$1, $$2}'

cluster-up: ## Create the local kind cluster
	kind create cluster --config platform/kind/cluster.yaml

cluster-down: ## Delete the local kind cluster
	kind delete cluster --name $(CLUSTER)

deploy: ## Install/upgrade the Astronomy Shop
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
	helm repo update open-telemetry
	helm upgrade --install $(RELEASE) open-telemetry/opentelemetry-demo \
	  --namespace $(NAMESPACE) --create-namespace \
	  -f apps/astronomy-shop/values.yaml --wait --timeout 15m

undeploy: ## Remove the Astronomy Shop
	helm uninstall $(RELEASE) -n $(NAMESPACE)

status: ## Show pod status
	kubectl get pods -n $(NAMESPACE) -o wide

open: ## Port-forward the shop (UI, /grafana, /jaeger/ui, /feature, /loadgen)
	@echo "Shop:     http://localhost:8080"
	@echo "Grafana:  http://localhost:8080/grafana"
	@echo "Jaeger:   http://localhost:8080/jaeger/ui"
	@echo "Flags:    http://localhost:8080/feature"
	@echo "Load gen: http://localhost:8080/loadgen"
	kubectl port-forward -n $(NAMESPACE) svc/frontend-proxy 8080:8080
