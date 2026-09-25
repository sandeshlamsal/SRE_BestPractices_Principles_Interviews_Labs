CLUSTER   := sre-lab
NAMESPACE := astronomy-shop
RELEASE   := shop
# Pinned so the lab is reproducible. Bump deliberately and note it in docs/labs/.
CHART_VERSION := 0.42.0
OBS_NS        := observability
# prometheus-community/kube-prometheus-stack, grafana-community/tempo, grafana-community/loki
# (Grafana moved the Loki/Tempo charts to grafana-community; grafana/tempo is stale.)
KPS_VERSION   := 91.5.2
TEMPO_VERSION := 3.0.0
LOKI_VERSION  := 18.13.5

# Observability stack (Phase 2)
.PHONY: obs-secrets obs-up obs-down grafana-password
.PHONY: help cluster-up cluster-down deploy undeploy status open slo-rules prom dashboards monitors

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
	  --wait --timeout 15m

slo-rules: ## Generate + validate SLO rules from slos/ (Sloth + promtool) and apply as PrometheusRules
	scripts/gen-slo-rules.sh
	kubectl apply -f observability/prometheus/slo-prometheusrules.yaml

monitors: ## Apply ServiceMonitors/PodMonitors/extra rules in observability/monitors/
	kubectl apply -f observability/monitors/

dashboards: ## Load Grafana dashboards from observability/dashboards/ (sidecar picks up label grafana_dashboard=1)
	kubectl create configmap sre-lab-dashboards -n $(OBS_NS) \
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
	kubectl port-forward -n $(OBS_NS) svc/kps-prometheus 9090:9090

obs-secrets: ## Create the Grafana admin secret (random password; never committed)
	kubectl create namespace $(OBS_NS) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl -n $(OBS_NS) get secret grafana-admin >/dev/null 2>&1 || \
	  kubectl -n $(OBS_NS) create secret generic grafana-admin \
	    --from-literal=admin-user=admin --from-literal=admin-password="$$(openssl rand -base64 18)"

obs-up: obs-secrets ## Install/upgrade kube-prometheus-stack, Tempo, Loki into the observability namespace
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
	helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null 2>&1 || true
	helm repo update prometheus-community grafana-community
	helm upgrade --install kps prometheus-community/kube-prometheus-stack --version $(KPS_VERSION) \
	  -n $(OBS_NS) -f observability/kube-prometheus-stack/values.yaml --wait --timeout 10m
	helm upgrade --install tempo grafana-community/tempo --version $(TEMPO_VERSION) \
	  -n $(OBS_NS) -f observability/tempo/values.yaml --wait --timeout 5m
	helm upgrade --install loki grafana-community/loki --version $(LOKI_VERSION) \
	  -n $(OBS_NS) -f observability/loki/values.yaml --wait --timeout 5m

obs-down: ## Uninstall the observability stack (PVCs are kept)
	-helm uninstall loki tempo kps -n $(OBS_NS)

grafana-password: ## Print the Grafana admin password
	@kubectl -n $(OBS_NS) get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
