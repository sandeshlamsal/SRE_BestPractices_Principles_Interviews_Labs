#!/usr/bin/env bash
# Experiment 03: node failure. Stop the sre-lab-worker node container (like a server dying), observe, restore.
# Hypothesis: pods stranded ~5-6 min (node unreachable 40s + default 300s toleration) -> checkout/cart/browse fail;
#             SLO pages fire but the PAGER (alert-sink, same node) can't deliver until rescheduled;
#             local-PV pods (Loki, Tempo) can't move until the node returns; astronomy-db restarts EMPTY (no PVC).
# Abort: node is restarted after DOWN_SECONDS no matter what.
set -uo pipefail
NODE=${NODE:-sre-lab-worker}; DOWN_SECONDS=${DOWN_SECONDS:-480}; P=http://localhost:9090/api/v1
edge(){ curl -s -G "$P/query" --data-urlencode 'query=sum by (http_status_code) (increase(traces_span_metrics_calls_total{service_name="frontend-proxy",span_kind="SPAN_KIND_SERVER"}[3m]))' \
  | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];d={x['metric'].get('http_status_code'):float(x['value'][1]) for x in r};t=sum(d.values());b=sum(v for k,v in d.items() if k in('0','500','502','503','504'));print(f'edge_fail_3m={b/t*100:.1f}%' if t else 'edge=n/a')" 2>/dev/null || echo edge=err; }
pages(){ curl -s "$P/alerts" | python3 -c "import json,sys;print('pages=',sorted({a['labels']['alertname'] for a in json.load(sys.stdin)['data']['alerts'] if a['state']=='firing' and a['labels'].get('severity')=='page'}) or '-')" 2>/dev/null || echo pages=err; }
sink(){ kubectl -n observability logs deploy/alert-sink --since=20m 2>/dev/null | grep -c '"page"' || true; }
snap(){ echo "$(date -u +%T) t+$(( $(date +%s)-T0 ))s node=$(kubectl get node $NODE --no-headers 2>/dev/null | awk '{print $2}') pending=$(kubectl get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ') shop_notready=$(kubectl -n astronomy-shop get pods --no-headers 2>/dev/null | awk '{split($2,a,"/"); if (a[1]!=a[2]) n++} END{print n+0}') $(edge) $(pages) sink_pages_received=$(sink)"; }
T0=$(date +%s); echo "$(date -u +%T) STOP node $NODE"; docker stop "$NODE" >/dev/null
while [ $(( $(date +%s)-T0 )) -lt "$DOWN_SECONDS" ]; do snap; sleep 30; done
echo "$(date -u +%T) START node $NODE (abort/restore)"; docker start "$NODE" >/dev/null; T1=$(date +%s)
while [ $(( $(date +%s)-T1 )) -lt 360 ]; do snap; sleep 30; done
echo "$(date -u +%T) DONE"
