#!/usr/bin/env bash
# Run a Chaos Mesh experiment and measure user impact from the frontend's point of view.
#   scripts/chaos-run.sh <experiment.yaml> <frontend span_name regex> <component> [observe_seconds=180]
# Prints: HTTP status breakdown for the route during the window + time until the component is Ready again.
set -euo pipefail
cd "$(dirname "$0")/.."
EXP="$1"; ROUTE="$2"; COMP="$3"; OBS="${4:-180}"
P=http://localhost:9090/api/v1
pgrep -fl "gameday" >/dev/null && { echo "a game day is running: abort"; exit 1; }
name=$(python3 -c "import yaml,sys;print(yaml.safe_load(open('$EXP'))['metadata']['name'])")
kind=$(python3 -c "import yaml,sys;print(yaml.safe_load(open('$EXP'))['kind'].lower())")
kubectl -n astronomy-shop delete "$kind" "$name" --ignore-not-found >/dev/null
S=$(date +%s); echo "$(date -u +%T) INJECT $name"
kubectl apply -f "$EXP" >/dev/null
sleep 3
until kubectl -n astronomy-shop wait --for=condition=Ready pod -l app.kubernetes.io/component="$COMP" --timeout=5s >/dev/null 2>&1 \
      && [ "$(kubectl -n astronomy-shop get pods -l app.kubernetes.io/component=$COMP --no-headers | grep -c Running)" -ge 1 ]; do
  sleep 2; [ $(( $(date +%s)-S )) -gt 300 ] && { echo "ABORT: $COMP not Ready in 5 min"; kubectl -n astronomy-shop rollout restart deploy/"$COMP"; exit 1; }
done
R=$(date +%s); echo "$(date -u +%T) $COMP Ready again after $((R-S))s"
sleep "$OBS"; E=$(date +%s); W=$((E-S))
kubectl -n astronomy-shop delete "$kind" "$name" --ignore-not-found >/dev/null
echo "--- frontend '$ROUTE' by HTTP status during the ${W}s window (+60s metric flush):"
sleep 60
curl -s -G "$P/query" --data-urlencode "query=sum by (http_response_status_code) (increase(traces_span_metrics_calls_total{service_name=\"frontend\",span_kind=\"SPAN_KIND_SERVER\",span_name=~\"$ROUTE\",http_response_status_code!=\"\"}[${W}s]))" --data-urlencode "time=$((E+60))" \
 | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];tot=sum(float(x['value'][1]) for x in r);bad=sum(float(x['value'][1]) for x in r if x['metric']['http_response_status_code'][0]=='5');print('  ',{x['metric']['http_response_status_code']:round(float(x['value'][1])) for x in r},f'| 5xx = {bad/tot*100:.1f}%' if tot else '')"
