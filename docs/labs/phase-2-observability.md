# Phase 2: Observability Platform (Execution Guide)

> **Goal:** replace the demo's bundled telemetry backends with a production-style platform
> (kube-prometheus-stack + Tempo + Loki on persistent storage), keep the SLOs working, link
> metrics ↔ traces ↔ logs, and **monitor the monitoring pipeline itself**.
> **Principles practiced:** [03 Monitoring & alerting](../principles/03-monitoring-alerting.md), [06 Toil](../principles/06-toil-automation.md), simplicity.
> **Executed:** 2026-09-25. Demo Helm revision 6; kps revision 2; Tempo revision 2; Loki revision 1.
> **Status:** platform running and verified. The host-memory blocker (P2-ISSUE-14) led to the **real root cause**, container memory-limit thrashing (P2-ISSUE-15), which was fixed with before/after proof.

---

## 0. Before and after

```
BEFORE (Phase 0–1)                          AFTER (Phase 2)
astronomy-shop namespace                    astronomy-shop ns            observability ns
  collector ──► prometheus (emptyDir)         collector ─OTLP metrics──► Prometheus (PVC 10Gi, operator)
            ──► jaeger (memory)                         ─OTLP traces───► Tempo (PVC 5Gi) ─service graph─┐
            ──► opensearch                              ─OTLP logs─────► Loki  (PVC 5Gi)                 │
  grafana (300Mi, no auth)                   :8888 ◄── PodMonitor (pull) ── Prometheus ◄─remote write───┘
                                             frontend-proxy /grafana ──► Grafana (auth, datasources, dashboards as code)
                                                                          Alertmanager (PVC 1Gi; routing in Phase 3)
```

| Component | Chart (pinned in [Makefile](../../Makefile)) | Values |
|---|---|---|
| Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, operator | `prometheus-community/kube-prometheus-stack` **91.5.2** | [values](../../observability/kube-prometheus-stack/values.yaml) |
| Tempo 3.0.3 (single binary) | `grafana-community/tempo` **3.0.0** | [values](../../observability/tempo/values.yaml) |
| Loki 3.7.8 (monolithic) | `grafana-community/loki` **18.13.5** | [values](../../observability/loki/values.yaml) |
| Demo overrides (collector exporters, bundled backends off) | `open-telemetry/opentelemetry-demo` 0.42.0 | [values](../../apps/astronomy-shop/values.yaml) |
| SLO rules | generated `PrometheusRule` resources | [slo-prometheusrules.yaml](../../observability/prometheus/slo-prometheusrules.yaml) |
| Collector self-monitoring | `PodMonitor` | [otel-collector.yaml](../../observability/monitors/otel-collector.yaml) |
| Dashboards | JSON as code | [observability/dashboards/](../../observability/dashboards/) |

---

## Step 1: Choose and pin chart versions

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update
helm search repo prometheus-community/kube-prometheus-stack | head -2
helm search repo grafana-community/tempo | head -2
helm search repo grafana-community/loki  | head -2
```
⚠️ **Grafana moved its Loki and Tempo charts to `grafana-community`.** The old `grafana/tempo` is still there but
stale (Tempo 2.9 vs 3.0.3). Many tutorials still point at the old repo (P2-ISSUE-1).

Always read the values before writing overrides:
```bash
helm show values grafana-community/loki --version 18.13.5 > /tmp/loki-values.yaml   # 7,350 lines
```

## Step 2: Key configuration decisions

**kube-prometheus-stack** ([values](../../observability/kube-prometheus-stack/values.yaml)):
- `enableOTLPReceiver: true` so the collector can push OTLP metrics; `promoteResourceAttributes` turns `service.name` and similar into labels.
- `enableRemoteWriteReceiver: true` so Tempo's metrics generator can write service-graph metrics.
- `storageSpec` 10Gi PVC and `retention: 7d` / `retentionSize: 8GB`. **History now survives restarts** (fixes P1-ISSUE-6).
- `*SelectorNilUsesHelmValues: false`, so Prometheus picks up **every** PrometheusRule, ServiceMonitor and PodMonitor, not only ones labelled for this release.
- `kubeControllerManager`, `kubeScheduler`, `kubeEtcd`, `kubeProxy` **disabled on kind**: they listen on localhost only and would fire false "down" alerts (P2-ISSUE-2).
- Grafana: admin password from a **Secret created at install time** (`make obs-secrets`, never in Git); `serve_from_sub_path` so it's reachable at `http://localhost:8080/grafana` through the demo's Envoy; datasources with **links in every direction**:
  - Prometheus **exemplars → Tempo** (`trace_id`)
  - Tempo **→ Loki** (`tracesToLogsV2`), **→ Prometheus** (service map)
  - Loki **→ Tempo** (derived field on `trace_id`)

**Tempo:** OTLP gRPC/HTTP receivers, 72h retention, 5Gi PVC, metrics generator with **only the `service-graphs`** processor (P2-ISSUE-8).
**Loki:** `deploymentMode: Monolithic`, filesystem storage, `auth_enabled: false`, TSDB schema v13, 72h retention, `allow_structured_metadata: true` (needed for OTLP). The chart defaults to 3× scalable replicas + memcached + object storage, which is too heavy for a laptop (P2-ISSUE-3).

Validate everything renders **before** installing:
```bash
helm template kps prometheus-community/kube-prometheus-stack --version 91.5.2 -n observability \
  -f observability/kube-prometheus-stack/values.yaml > /dev/null && echo OK      # 105 objects
helm template tempo grafana-community/tempo --version 3.0.0 -n observability -f observability/tempo/values.yaml > /dev/null && echo OK
helm template loki  grafana-community/loki  --version 18.13.5 -n observability -f observability/loki/values.yaml  > /dev/null && echo OK
```

## Step 3: Install the platform

```bash
make obs-up          # = obs-secrets + helm upgrade --install kps / tempo / loki (all --wait)
make grafana-password
kubectl -n observability get pods        # 10 pods Running
kubectl -n observability get pvc         # 4 Bound: prometheus 10Gi, loki 5Gi, tempo 5Gi, alertmanager 1Gi
```
It took **2m16s**.

## Step 4: Cut the demo over to the platform

In [apps/astronomy-shop/values.yaml](../../apps/astronomy-shop/values.yaml):
- `prometheus/grafana/jaeger/opensearch.enabled: false`
- New collector exporters `otlp_http/platform-prometheus` (`…/api/v1/otlp`), `otlp_grpc/platform-tempo` (`tempo.observability:4317`), `otlp_http/platform-loki` (`…:3100/otlp`), with the `traces/metrics/logs` pipelines pointed only at them
- `ports.metrics.enabled: true` plus a `pull` telemetry reader on `:8888` (P2-ISSUE-5)
- `kubeletstats.insecure_skip_verify: true` (kind only; P1-ISSUE-17)
- `frontend-proxy.envOverrides`: `GRAFANA_HOST=kps-grafana.observability.svc.cluster.local`

Check the collector config renders as expected:
```bash
helm template shop open-telemetry/opentelemetry-demo --version 0.42.0 -n astronomy-shop \
  -f apps/astronomy-shop/values.yaml | python3 -c "
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
  if d and d['kind']=='ConfigMap' and d['metadata']['name'].startswith('otel-collector'):
    c=yaml.safe_load(list(d['data'].values())[0]); print({k:v['exporters'] for k,v in c['service']['pipelines'].items()})"
```
Then apply:
```bash
make deploy          # demo revision 6: bundled backends removed, collectors restarted
make slo-rules       # Sloth → promtool → 3 PrometheusRules (85 rules) → kubectl apply
make monitors        # PodMonitor for the collectors
make dashboards      # ConfigMap in observability ns (sidecar searches ALL namespaces)
kubectl -n astronomy-shop delete configmap sre-lab-dashboards --ignore-not-found   # old copy
```
⚠️ Restart `make open` afterwards. A port-forward is bound to **one pod**, and the frontend-proxy pod was replaced (P2-ISSUE-7).
The dashboards' datasource UID changed from `webstore-metrics` to `prometheus`.

## Step 5: Verify every signal end to end

```bash
make prom   # now forwards svc/kps-prometheus in the observability namespace
P=http://localhost:9090/api/v1
curl -s "$P/targets?state=active" | python3 -c "import json,sys;t=json.load(sys.stdin)['data']['activeTargets'];print(sum(x['health']=='up' for x in t),'/',len(t))"   # 24 / 24
curl -s -G "$P/query" --data-urlencode 'query=slo:sli_error:ratio_rate5m'        # 5 SLIs
curl -s -G "$P/query" --data-urlencode 'query=sum by (client,server) (rate(traces_service_graph_request_total[2m])) > 0'   # 27 edges

PW=$(make -s grafana-password); G="http://admin:$PW@localhost:8080/grafana"
curl -s "$G/api/datasources" | python3 -c "import json,sys;print([(d['name'],d['uid']) for d in json.load(sys.stdin)])"
curl -s "$G/api/datasources/proxy/uid/loki/loki/api/v1/labels"                  # service_name, k8s_* labels
curl -s -G "$G/api/datasources/proxy/uid/tempo/api/search" \
  --data-urlencode 'q={resource.service.name="checkout" && name="oteldemo.CheckoutService/PlaceOrder"}' --data-urlencode limit=2
```

| Check | Result |
|---|---|
| Scrape targets | **24 / 24 up** (kubelet, node-exporter, kube-state-metrics, apiserver, coredns, operator, Prometheus, Alertmanager, Grafana, 2× collector) |
| SLO rules | 15 Sloth groups loaded, 0 errors; 5 SLIs evaluating |
| Persistence | SLI series **survived a Prometheus restart** (PVC) |
| Traces | Tempo returns `PlaceOrder` traces |
| Logs | Loki has OTLP logs, e.g. `service_name=checkout` |
| Service graph | **27 edges**, including async `checkout→kafka` and `accounting→astronomy-db` |
| Grafana | Reachable at `http://localhost:8080/grafana` (login required); 4 datasources |

## Step 6: Dashboards added (as code)

| Dashboard | Purpose |
|---|---|
| **SRE Lab / SLO & Error Budgets** | From Phase 1, now on the platform Prometheus |
| **SRE Lab / Service RED** | Rate, errors and p50/p95/p99 per service; **exemplars on p99 open the trace in Tempo** |
| **SRE Lab / Telemetry Pipeline Health** | Collector self-metrics **pulled directly**: collectors up, freshest span-metric age, export failures, memory-limiter refusals, queue fill |
| kube-prometheus-stack defaults | Node USE-method, Kubernetes compute resources, Alertmanager, Prometheus |

RED dashboard (checkout): ![RED](img-phase2-red-dashboard.png)
It shows checkout p99 at about **1.35 s during the cutover (12:11–12:15)**, then back to about 100 ms (P2-ISSUE-11).

Telemetry pipeline health: ![Pipeline](img-phase2-pipeline-health.png)
**On its first render it caught a real problem:** about 0.8 metric points per second rejected by Prometheus (P2-ISSUE-10).

---

## Issues log

| ID | Area | Symptom | Root cause | Fix / decision | Verified by |
|---|---|---|---|---|---|
| P2-ISSUE-1 | Charts | Tutorials use `grafana/tempo` and `grafana/loki` | Grafana moved them to `grafana-community`; the old charts are stale | Pinned `grafana-community/tempo 3.0.0`, `grafana-community/loki 18.13.5` | `helm search repo` versions |
| P2-ISSUE-2 | kind | Controller-manager/scheduler/etcd/kube-proxy targets would be DOWN and fire alerts | On kind they bind to localhost only | Disabled those ServiceMonitors locally. **Re-enable on EKS** | No false Kube*Down alerts from them |
| P2-ISSUE-3 | Loki | The default install is 3× read/write/backend + memcached + S3 | The chart targets scalable production installs | Monolithic, filesystem, 1 replica, caches/gateway/canary off. S3 in Phase 8 | `loki-0` 2/2 Running, ~1 GB |
| P2-ISSUE-4 | Helm | `otlp_grpc/jaeger: null` didn't remove the exporter | The collector chart deep-merges config inside its template, so Helm's null-deletion doesn't reach it | Left them defined but **unused**; the collector only starts exporters referenced by a pipeline | Pipelines list only the `platform-*` exporters |
| P2-ISSUE-5 | Self-monitoring | The collector's own metrics went through **its own pipeline** | Demo default: a periodic OTLP push to itself | Added a `pull` reader on :8888 + `ports.metrics` + a `PodMonitor`, so the independent path works even if the pipeline stalls | `up{job="observability/otel-collector"}` = 2 |
| P2-ISSUE-6 | Grafana | Grafana scrape target DOWN: `localhost:3000/grafana/metrics` refused | With `serve_from_sub_path`, `/metrics` redirects to `root_url` (localhost), which from Prometheus's side is itself | `grafana.serviceMonitor.path: /grafana/metrics` | Target up |
| P2-ISSUE-7 | Tooling | `:8080` and `:9090` stopped responding after upgrades | `kubectl port-forward` attaches to a single pod; when it's replaced, the forward dies | Restart `make open` / `make prom` after rollouts. (Phase 7: a real Gateway removes this) | 200s after restart |
| P2-ISSUE-8 | Tempo | Service graph had 0 edges | The metrics-generator processors are **off per tenant** by default | `overrides.defaults.metrics_generator.processors: [service-graphs]`. **Not `span-metrics`**, which would duplicate the collector's span metrics that the SLIs use | 27 edges |
| P2-ISSUE-9 | Naming | `otelcol_exporter_sent_spans_total` returned nothing | The same metric has **different names by path**: pulled (`…_sent_spans`) vs pushed via OTLP (`…_total`) | Dashboards and alerts use the **pull** names | Pipeline dashboard populated |
| **P2-ISSUE-10** | Ingestion | Collector on `sre-lab-worker`: HTTP **400**, 40 metric points dropped **every 60s** (~0.3% of points) | **Open.** Not SLI metrics (0 failures on span-metric series). Started when `kubeletstats` began working (P1-ISSUE-17 fix); Prometheus debug logs didn't show the reason | Next: temporarily add the `debug` exporter (detailed) to a metrics pipeline filtered to that node, find the rejected metric, then drop or rename it with a `transform`/`filter` processor | `otelcol_exporter_send_failed_metric_points` on the pipeline dashboard |
| P2-ISSUE-11 | SLO | `browse-latency` showed 3.5% slow requests (3.5x burn); checkout p99 ~1.35s | The cutover itself: collectors and proxy restarting while worker CPU was at 117–240% | **Migrations spend error budget.** In production: schedule them, check the budget first, and announce them. Recovered to ~100ms | RED dashboard |
| P2-ISSUE-12 | Alerts | `KubeAPIDown` firing after the Prometheus restart | During the restart the apiserver target was briefly absent; the alert uses `absent()` with `for:` | Restart artifact; `up{job="apiserver"}=1`. Phase 3 alert routing should suppress alerts during planned maintenance (silences) | apiserver up |
| P2-ISSUE-13 | Tooling | A render loop failed: `no such file or directory: r-kps prometheus-...` | zsh doesn't split `$var` into words the way bash does | Use explicit arguments or a function | — |
| **P2-ISSUE-14** | **Host capacity** | Telemetry stalls, sparse scrapes, `helm upgrade` took ~16 min | **Part 1:** the host Mac ran out of memory: Docker's VM used **26.6 GB** of 32 GB (above the 16 GB setting), 112 MB free | Docker memory **16 → 12 GB** (measured need ~9–11 GB), then restarted Docker (`docker desktop stop` → edit `settings-store.json` → `docker desktop start`). The kind nodes restarted by themselves and PVC data was kept. Host went from 112 MB to ~16 GB free on stop. **Not the whole story:** symptoms continued, see P2-ISSUE-15 | `top`: Docker VM 12G; swap 0.5 GB |
| **P2-ISSUE-15** | **Resource limits (root cause)** | After the Docker fix: checkout latency SLI **100% > 1s**, span metrics **284 s** old, 5 scrapes/5 min instead of ~20, VM PSI memory-full 10% & io-full 8%, yet containers showed tiny CPU | **product-catalog's 20Mi limit** (chart default): it hit its limit **644,293 times** with **1.86M major page faults**, evicting and re-reading its own code from disk continuously. **No OOM kill, no restart, no alert**, just latency and node-wide I/O pressure. checkout (20Mi, 9,070 hits), flagd, accounting, fraud-detection and Grafana were also thrashing | Swept **every** container's `memory.events` (`max` count) and `pgmajfault` and raised limits from the data: product-catalog 128Mi, checkout 64Mi, flagd 128Mi, accounting 256Mi, fraud-detection 384Mi, Grafana 1Gi. **Most likely root cause of P1-ISSUE-16** too | Checkout latency SLI 1.0 → **0.0**; p99 **299 ms**; span-metric age 284 → **4 s**; PSI mem 10 → **0.19%**, io 7.9 → **0.30%**; helm upgrade 16 min → **31 s** |
| P2-ISSUE-16 | Tooling | Wait loops hung until timeout | `awk '$2 !~ /^([0-9]+)\/\1$/'` uses a back-reference, which **macOS awk doesn't support**, so every pod looked "not ready" | Use `kubectl wait --for=condition=Ready pods --all -n <ns>` | Waits return immediately |
| P2-ISSUE-17 | Diagnosis | Misleading signals during the investigation | (a) Prometheus per-pod CPU undercounted because its own samples were sparse; (b) Locust rps (~0.7–0.9) is capped by users × think time, so it's **not** a health signal; (c) kind nodes share **one VM kernel**, so `/proc/pressure` is VM-wide, not per node | Diagnose from the lowest layer that's still trustworthy: **cgroup files inside the node** (`memory.events`, `memory.stat`, `memory.pressure`) | — |

### How P2-ISSUE-14 and P2-ISSUE-15 were diagnosed (reusable method)

```bash
# 1. Host: is the Mac itself starved?
top -l 1 -n 0 | grep -E "PhysMem|Load Avg|CPU usage"
top -l 2 -o cpu -n 8 -stats pid,command,cpu,mem | tail -9      # Docker VM = com.apple.Virtualization...
# 2. VM kernel: where does the time go? (shared by all kind nodes)
docker exec sre-lab-worker cat /proc/loadavg /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io
# 3. Which container? Sweep every container's cgroup for limit hits and major faults
for n in sre-lab-worker sre-lab-worker2; do docker exec $n sh -c 'for d in $(find /sys/fs/cgroup/kubelet.slice -name "cri-containerd-*.scope" -type d); do
  m=$(cat $d/memory.max); [ "$m" = max ] && continue
  echo "$(grep "^max " $d/memory.events|cut -d" " -f2) $(grep "^pgmajfault " $d/memory.stat|cut -d" " -f2) $(cat $d/memory.current) $m $(basename $d|cut -c16-27)"; done' | sort -rn | head; done
# map a container id to a name:  docker exec <node> crictl ps -a --id <id>
```
**Lesson:** a memory limit set too tight usually **doesn't OOM**. The kernel keeps reclaiming page cache (including the
program's own code), so the service gets slow and drives I/O for everyone. Look at `memory.events: max`, not just OOM kills.
Phase 3 turns this into an alert.

---|---|---|
| A. Restart Docker Desktop | The VM gives back its bloated memory; the kind cluster restarts (PVCs keep data) | ~5 min of downtime |
| B. Lower Docker memory to 12 GB + restart | Leaves ~20 GB for macOS. Our measured peak need is ~9–11 GB | Same as A; a little less headroom for later phases |
| C. Turn on Docker's *Resource Saver* / close heavy apps | Less pressure without a restart | May not be enough |

Recommended: **B**. It matches the measured need (see [environments-and-sizing](../environments-and-sizing.md)), and "size to measured demand" is itself the capacity lesson.

---

## Phase 2 exit checklist

- [x] kube-prometheus-stack, Tempo and Loki on persistent storage, versions pinned
- [x] The demo sends all three signals to the platform; bundled backends removed
- [x] SLO rules as `PrometheusRule` CRs; SLIs survive restarts
- [x] Metrics ↔ traces ↔ logs links configured (exemplars, tracesToLogs, derived fields, service map)
- [x] RED, pipeline-health and SLO dashboards as code; USE dashboards from kps
- [x] The monitoring is monitored (independent pull path)
- [x] P2-ISSUE-14/15 host memory + container limit thrashing: fixed with before/after data
- [ ] P2-ISSUE-10 OTLP 400s
- [ ] The alert → dashboard → trace → log drill in under 2 minutes (after P2-ISSUE-14)

## Re-run Phase 2 from scratch

```bash
make cluster-up && make obs-up && make deploy && make slo-rules && make monitors && make dashboards
make open            # http://localhost:8080 (shop) and http://localhost:8080/grafana (admin / make grafana-password)
make prom            # http://localhost:9090
```
