CLUSTER   := sre-lab
NAMESPACE := astronomy-shop
RELEASE   := shop
# Pinned so the lab is reproducible. Bump deliberately and note it in docs/labs/.
CHART_VERSION := 0.42.0

.PHONY: help cluster-up cluster-down deploy undeploy status open slo-rules prom dashboards

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-14s %s\n", $$1, $$2}'

cluster-up: ## Create the local kind cluster
	kind create cluster --config platform/kind/cluster.yaml
	kubectl wait --for=condition=Ready nodes --all --timeout=180s

cluster-down: ## Delete the local kind cluster
	kind delete cluster --name $(CLUSTER)

deploy: ## Install/upgrade the Astronomy Shop
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
	helm repo update open-telemetry
	helm upgrade --install $(RELEASE) open-telemetry/opentelemetry-demo --version $(CHART_VERSION) \
	  --namespace $(NAMESPACE) --create-namespace \
	  -f apps/astronomy-shop/values.yaml \
	  -f apps/astronomy-shop/values-slo-rules.yaml \
	  --wait --timeout 15m

slo-rules: ## Generate + validate SLO rules from slos/ (Sloth + promtool, via Docker)
	scripts/gen-slo-rules.sh

dashboards: ## Load Grafana dashboards from observability/dashboards/ (sidecar picks up label grafana_dashboard=1)
	kubectl create configmap sre-lab-dashboards -n $(NAMESPACE) \
	  --from-file=observability/dashboards/ --dry-run=client -o yaml \
	| kubectl label --local -f - grafana_dashboard=1 -o yaml \
	| kubectl apply -f -

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

prom: ## Port-forward Prometheus to http://localhost:9090
	kubectl port-forward -n $(NAMESPACE) svc/prometheus 9090:9090
