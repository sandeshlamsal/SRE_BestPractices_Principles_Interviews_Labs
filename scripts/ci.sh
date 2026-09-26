#!/usr/bin/env bash
# CI checks. Runs the SAME way locally (`make ci`) and in GitHub Actions (.github/workflows/ci.yml).
# Needs: helm, python3 + pyyaml, docker, kubeconform.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
step(){ echo; echo "==> $*"; }
V(){ grep -E "^$1 *:=" Makefile | awk '{print $3}'; }

step "1/7 Helm: add repos"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add chaos-mesh https://charts.chaos-mesh.org >/dev/null 2>&1 || true
helm repo update >/dev/null

step "2/7 Render every chart with our values (catches schema errors, bad values, post-renderer failures)"
helm template shop open-telemetry/opentelemetry-demo --version "$(V CHART_VERSION)" -n astronomy-shop \
  -f apps/astronomy-shop/values.yaml -f apps/astronomy-shop/values-resilience.yaml \
  --post-renderer scripts/helm-postrender.py > "$OUT/shop.yaml"
helm template kps prometheus-community/kube-prometheus-stack --version "$(V KPS_VERSION)" -n observability \
  -f observability/kube-prometheus-stack/values.yaml > "$OUT/kps.yaml"
helm template tempo grafana-community/tempo --version "$(V TEMPO_VERSION)" -n observability -f observability/tempo/values.yaml > "$OUT/tempo.yaml"
helm template loki grafana-community/loki --version "$(V LOKI_VERSION)" -n observability -f observability/loki/values.yaml > "$OUT/loki.yaml"
helm template chaos-mesh chaos-mesh/chaos-mesh --version "$(V CHAOS_MESH_VERSION)" -n chaos-mesh -f platform/chaos-mesh/values.yaml > "$OUT/chaos.yaml"
for f in "$OUT"/*.yaml; do echo "   $(basename "$f"): $(grep -c '^kind:' "$f") objects"; done

step "3/7 kubeconform: rendered charts + our raw manifests (CRDs via the datree catalog)"
kubeconform -strict -summary -kubernetes-version 1.35.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -skip CustomResourceDefinition \
  "$OUT"/*.yaml observability/monitors observability/alerting observability/prometheus/slo-prometheusrules.yaml \
  platform/resilience loadtests/k6-job.yaml
# Chaos Mesh CRDs are not in the public schema catalog -> structure-only check (known gap; fix: vendor schemas from the CRDs)
kubeconform -summary -ignore-missing-schemas chaos/*.yaml

step "4/7 SLO rules: regenerate from slos/ and fail on drift (generated files must be committed)"
scripts/gen-slo-rules.sh >/dev/null
git diff --exit-code -- observability/prometheus/ && echo "   no drift"

step "5/7 promtool: platform alert rules"
python3 -c "import yaml;d=yaml.safe_load(open('observability/monitors/sre-lab-alerts.yaml'));yaml.safe_dump({'groups':d['spec']['groups']},open('$OUT/alerts.yaml','w'))"
docker run --rm -v "$OUT:/r" --entrypoint promtool prom/prometheus:v3.14.0 check rules /r/alerts.yaml

step "6/7 Alerting hygiene: runbooks + routing tests"
scripts/check-runbooks.sh
scripts/test-alert-routing.sh

step "7/7 Docs + dashboards"
python3 scripts/check-links.py
for d in observability/dashboards/*.json; do python3 -c "import json,sys;json.load(open('$d'))" && echo "   valid json: $d"; done

echo; echo "CI: ALL CHECKS PASSED"
