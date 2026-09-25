# Phase 0: Foundation (Execution Guide)

> **Goal:** a 3-node local Kubernetes cluster running the Astronomy Shop, and you can trace one
> checkout request from end to end.
> **Principles practiced:** toil reduction (everything scripted), simplicity, observability basics.
> **Time:** about 45 minutes the first time (mostly pulling images), about 10 minutes to rebuild.

This guide records **exactly what was run**, the output we saw, and every issue we hit along
with how it was fixed. You should be able to repeat Phase 0 from this page alone.

---

## 0. Environment used

| Item | Value |
|---|---|
| Date executed | 2026-09-25 |
| Machine | MacBook Pro, Intel i9-8950HK, 12 threads, 32 GB RAM, macOS (Darwin 24.6) |
| Docker Desktop | 4.72.0 (Engine 29.4.2) |
| kind | v0.31.0 |
| kubectl | v1.35.3 |
| helm | v3.21.2 |
| Kubernetes (node image) | `kindest/node:v1.35.0` (pinned in [cluster.yaml](../../platform/kind/cluster.yaml)) |
| Chart | `open-telemetry/opentelemetry-demo` **0.42.0** (app 3.1.0), pinned in the [Makefile](../../Makefile) |

Check your own versions:
```bash
docker version --format 'Client {{.Client.Version}} / Server {{.Server.Version}}'
kind version
kubectl version --client
helm version --short
```

---

## Step 1: Give Docker Desktop enough resources

The full lab needs **8 CPUs, 16 GB RAM, 2 GB swap, and a 100 GB disk** (see [sizing](../environments-and-sizing.md)).

**Option A: GUI (recommended).** Docker Desktop → Settings → Resources → Advanced → set CPUs 8, Memory 16 GB, Swap 2 GB, Disk 100 GB → *Apply & restart*.

**Option B: settings file (what we did).** Only do this while Docker Desktop is **stopped**:
```bash
F="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
cp "$F" "$F.bak-sre-lab"                      # back up first
python3 - "$F" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d.update({"Cpus": 8, "MemoryMiB": 16384, "SwapMiB": 2048, "DiskSizeMiB": 102400})
json.dump(d, open(p, "w"), indent=2)
EOF
open -a Docker
```

**Verify:**
```bash
until docker info >/dev/null 2>&1; do sleep 5; done   # wait for the engine
docker info --format 'CPUs={{.NCPU}} Mem={{.MemTotal}}'
```
Expected: `CPUs=8 Mem=16767680512` (about 15.6 GiB usable).

---

## Step 2: Create the kind cluster

Config: [platform/kind/cluster.yaml](../../platform/kind/cluster.yaml). It creates 1 control plane and 2 workers, with the node image pinned.

```bash
kind get clusters        # expect: "No kind clusters found." (a clean start)
make cluster-up
```
`make cluster-up` runs:
```bash
kind create cluster --config platform/kind/cluster.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=180s
```
It took about **1m15s**. kind automatically sets the kubectl context to `kind-sre-lab`.

**Verify:**
```bash
kubectl config current-context      # kind-sre-lab
kubectl get nodes -o wide
```
Expected: 3 nodes, all `Ready`, `v1.35.0`:
```
NAME                    STATUS   ROLES           VERSION
sre-lab-control-plane   Ready    control-plane   v1.35.0
sre-lab-worker          Ready    <none>          v1.35.0
sre-lab-worker2         Ready    <none>          v1.35.0
```
If you check within the first ~20 seconds, the workers may show `NotReady` (see ISSUE-2).

---

## Step 3: Review the chart before installing

Production habit: **know what you're deploying before you deploy it.**

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update open-telemetry
helm search repo open-telemetry/opentelemetry-demo --versions | head -4   # pick & pin a version

# Render locally and inspect: which workloads, images, memory limits?
helm template shop open-telemetry/opentelemetry-demo --version 0.42.0 \
  -n astronomy-shop -f apps/astronomy-shop/values.yaml > /tmp/render.yaml
grep -E '^kind: (Deployment|StatefulSet)' -A3 /tmp/render.yaml | grep '  name:' | sort

# Full default values (to find override keys)
helm show values open-telemetry/opentelemetry-demo --version 0.42.0 > /tmp/values.yaml
```

What we found in chart 0.42.0 / app 3.1.0: **29 workloads**. Beyond the classic shop services, there
are `astronomy-db` (Postgres), `opamp-server`, `telemetry-docs`, and three AI components
(`agent`, `chatbot`, `mcp`) that need an external LLM. We turned those three off (see ISSUE-3).

Our overrides: [apps/astronomy-shop/values.yaml](../../apps/astronomy-shop/values.yaml).

---

## Step 4: Deploy the Astronomy Shop

```bash
make deploy
```
`make deploy` runs:
```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update open-telemetry
helm upgrade --install shop open-telemetry/opentelemetry-demo --version 0.42.0 \
  --namespace astronomy-shop --create-namespace \
  -f apps/astronomy-shop/values.yaml --wait --timeout 15m
```

It took **3m49s** (a first install that pulls about 26 images; later installs are faster).
Helm prints the available URLs when it finishes.

**Verify the release and pods:**
```bash
helm list -n astronomy-shop
# NAME  NAMESPACE       REVISION  STATUS    CHART                      APP VERSION
# shop  astronomy-shop  1         deployed  opentelemetry-demo-0.42.0  3.1.0

make status        # = kubectl get pods -n astronomy-shop -o wide
# Quick health summary: every pod should be Running, READY n/n, 0 restarts
kubectl get pods -n astronomy-shop --no-headers | awk '{print $3}' | sort | uniq -c
kubectl get pods -n astronomy-shop --no-headers | awk '$2 !~ /^([0-9]+)\/\1$/ || $3!="Running" || $4!="0"'   # prints nothing when healthy
```
Result: **28 pods, all Running and Ready, 0 restarts**, spread across `sre-lab-worker` and `sre-lab-worker2`.

**Resource use** (metrics-server isn't installed yet, so measure the kind node containers):
```bash
docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' | grep sre-lab
```
| Node | Memory used right after deploy |
|---|---|
| sre-lab-control-plane | ~0.9 GiB |
| sre-lab-worker | ~2.6 GiB |
| sre-lab-worker2 | ~4.4 GiB |
| **Total** | **~7.9 GiB** of 15.6 GiB, which leaves room for the Phase 2+ add-ons |

---

## Step 5: Open the shop and its tools

```bash
make open          # = kubectl -n astronomy-shop port-forward svc/frontend-proxy 8080:8080
```
Leave that running in its own terminal. Everything goes through a single Envoy proxy:

| URL | What it is | Status we saw |
|---|---|---|
| http://localhost:8080/ | The Astronomy Shop storefront | 200 |
| http://localhost:8080/api/products | Product API (10 products, e.g. "Solar System Color Imager") | 200 |
| http://localhost:8080/jaeger/ui/ | Jaeger: distributed traces | 200 |
| http://localhost:8080/grafana/ | Grafana: dashboards (the demo ships several) | 200 |
| http://localhost:8080/feature/ | flagd UI: **failure-injection flags** | 200 |
| http://localhost:8080/loadgen/ | Locust: the synthetic user traffic | 200 |
| http://localhost:8080/telemetry/ | Telemetry docs for the demo | 200 |
| http://localhost:8080/profiles/ | Continuous profiling (Firepit) | 503: disabled by default (ISSUE-5) |
| http://localhost:8080/chatbot/ | AI chatbot | 503: we turned it off on purpose (ISSUE-3) |

Smoke test from the terminal:
```bash
for p in / /api/products /jaeger/ui/ /grafana/ /feature/ /loadgen/; do
  printf "%-16s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code} %{time_total}s' http://localhost:8080$p)"
done
```

**Walk through the app manually:** open the storefront → click a product (note the
recommendations and ad) → add to cart → cart → *Place Order* → confirmation page.
Then look around Grafana, the flag UI (**look, but don't turn anything on yet**), and Locust.

---

## Step 6: Trace one checkout from end to end (the exit criterion)

**In the UI:** Jaeger → Service `checkout` → Operation `oteldemo.CheckoutService/PlaceOrder` → *Find Traces* → open one.

**From the terminal** (Jaeger's API, through the same port-forward):
```bash
B=http://localhost:8080/jaeger/ui/api
curl -s "$B/services" | python3 -m json.tool          # services that are sending traces
curl -s -G "$B/traces" --data-urlencode service=checkout \
  --data-urlencode operation=oteldemo.CheckoutService/PlaceOrder \
  --data-urlencode limit=1 --data-urlencode lookback=1h > /tmp/trace.json
```

What one real `PlaceOrder` trace showed (total **~47 ms**; the whole user session was 155 spans across 11 services):
```
checkout: PlaceOrder (46.8 ms)
├─ prepareOrderItemsAndShippingQuoteFromCart (29.4 ms)
│  ├─ cart: GetCart ─────────────────────► valkey-cart (Redis)
│  ├─ product-catalog: GetProduct (×4) ──► astronomy-db (Postgres)
│  ├─ currency: Convert (×5)
│  └─ shipping: /get-quote ──────────────► quote: /getquote
├─ payment: Charge (5.2 ms)
├─ shipping: /ship-order
├─ cart: EmptyCart ──► flagd (feature flag check) + valkey-cart
├─ email: /send_order_confirmation (5.9 ms)
└─ publish orders ──► Kafka ──► accounting, fraud-detection (async)
```

**What this teaches:**
- **Critical path:** 8 services plus 2 data stores are *synchronous* for a checkout. Any one of them failing means the checkout fails. That's the dependency chain behind the checkout SLO.
- **Async edge:** Kafka consumers aren't on the user's critical path. Their failures show up as *freshness* problems, not errors.
- **Where time goes:** preparing the order (cart, catalog, currency, quote) is about 60% of the latency.
- The service map is recorded in [architecture.md](../architecture.md).

---

## Step 7: Confirm the metrics Phase 1 will use

```bash
kubectl -n astronomy-shop port-forward svc/prometheus 9090:9090     # second terminal
curl -s -G http://localhost:9090/api/v1/query --data-urlencode \
 'query=sum by (status_code) (rate(traces_span_metrics_calls_total{service_name="checkout",span_name="oteldemo.CheckoutService/PlaceOrder"}[5m]))'
```
Confirmed in chart 0.42.0: the span metrics are named **`traces_span_metrics_calls_total`** and
`traces_span_metrics_duration_milliseconds_*`, with labels `service_name`, `span_name`,
`status_code` (`STATUS_CODE_UNSET` = success, `STATUS_CODE_ERROR` = failure). These match the
queries in [principles/01](../principles/01-sli-slo-sla.md) and the [observability plan](../observability-plan.md).
Baseline checkout traffic from the load generator: **about 0.035 req/s (~2 checkouts/min)**.

---

## Step 8: First finding: checkout errors at startup

Step 7 showed about 11% checkout errors (`0.004` of `0.037` req/s) **with no failure flag turned on**.
We investigated it the same way we'll handle real incidents.

1. **Find error traces:**
   ```bash
   curl -s -G "$B/traces" --data-urlencode service=checkout \
     --data-urlencode operation=oteldemo.CheckoutService/PlaceOrder \
     --data-urlencode 'tags={"error":"true"}' --data-urlencode limit=5 --data-urlencode lookback=1h
   ```
   Error: `shipping quote failure: failed POST to shipping service: dial tcp 10.96.69.183:8080: connect: connection refused`
2. **Hypothesis:** the load generator started sending traffic before `shipping` was ready.
3. **Check the timeline:**
   ```bash
   kubectl -n astronomy-shop get pod -l app.kubernetes.io/component=load-generator \
     -o jsonpath='{.items[0].status.containerStatuses[0].state.running.startedAt}'   # 10:10:12Z
   kubectl -n astronomy-shop get pod -l app.kubernetes.io/component=shipping \
     -o jsonpath='{.items[0].status.containerStatuses[0].state.running.startedAt}'   # 10:11:17Z
   ```
   There were **65 seconds** of checkout traffic before shipping was up. Errors per 2-minute window since 10:14 have been **0**.
4. **Root cause:** there are no readiness probes, so Kubernetes and Envoy can't tell when a service is ready to serve:
   ```bash
   kubectl get deploy -n astronomy-shop -o json | python3 -c "import json,sys;d=json.load(sys.stdin)['items'];print([x['metadata']['name'] for x in d if not any('readinessProbe' in c for c in x['spec']['template']['spec']['containers'])])"
   ```
   **22 of 25 deployments have no readiness probe.**
5. **Decision:** accept it for now (it's a lab start-up transient), and fix it in **Phase 5 (hardening)**
   by adding readiness probes and the Kyverno `require-probes` policy. Logged as ISSUE-6.

> **SRE lesson:** a "deploy succeeded" (`helm --wait` exit 0) is not the same as "users are
> being served". Measure success with the SLI, not with the deploy tool.

---

## Phase 0 exit checklist

- [x] 3-node cluster running (`kubectl get nodes`: all Ready)
- [x] Shop deployed with a pinned chart; 28/28 pods healthy
- [x] All tool UIs reachable through `make open`
- [x] One checkout traced end to end; critical path and async edge identified
- [x] Phase 1 metric names confirmed in Prometheus
- [x] First reliability finding investigated and logged (ISSUE-6)
- [x] Service map updated in [architecture.md](../architecture.md)

**Interview takeaway:** "Walk me through what happens when a user clicks *Place order*." You
can now answer this with real spans, real latencies, and a real startup failure you found and explained.

---

## Issues log

| ID | Step | Symptom | Root cause | Fix | Verified by |
|---|---|---|---|---|---|
| ISSUE-1 | 1 | `docker info` → `failed to connect to the docker API at unix:///Users/.../.docker/run/docker.sock ... no such file or directory` | Docker Desktop wasn't running. Its settings had no resource keys, so it would have used the (too small) defaults | Set the resources in `settings-store.json` while Docker was stopped (backup: `settings-store.json.bak-sre-lab`), then `open -a Docker` | `docker info` → `CPUs=8 Mem=16767680512` |
| ISSUE-2 | 2 | Straight after `kind create cluster`, `kubectl get nodes` showed the workers `NotReady` | Normal: the CNI (kindnet) was still starting on nodes that had joined seconds earlier. Scripts that deploy right away can fail | Added `kubectl wait --for=condition=Ready nodes --all --timeout=180s` to `make cluster-up` | All 3 nodes `Ready` within ~20s |
| ISSUE-3 | 3 | Rendering the chart showed `agent`, `chatbot`, `mcp` with `LLM_BASE_URL=https://local-llm.com`, `API_KEY=""` | Demo 3.x added AI assistant features that need an external LLM provider | Turned them off in `values.yaml` (`components.<name>.enabled: false`). Saves ~1.5 GB and removes noise unrelated to the shop's user journeys. The frontend-proxy route to `chatbot` returns 503 but the proxy stays up | Pods absent: `kubectl get deploy -n astronomy-shop \| grep -E 'agent\|chatbot\|mcp'` returns nothing |
| ISSUE-4 | 3 | The deploy would pull whatever chart version is latest, so rebuilds weren't reproducible | No version pin | Pinned `CHART_VERSION := 0.42.0` in the Makefile and the `kindest/node:v1.35.0` image in cluster.yaml | `helm list -n astronomy-shop` shows `opentelemetry-demo-0.42.0` |
| ISSUE-5 | 5 | `/profiles/` returns **503** | Continuous profiling (Firepit + the eBPF profiler) is **off by default** in the chart; the eBPF profiler needs privileged access | None needed for now. Could be turned on later (`components.firepit.enabled` + `otel-ebpf-profiler.enabled`) as an optional observability extra | Expected 503; everything else returns 200 |
| ISSUE-6 | 8 | About 11% checkout errors right after the deploy, with no flags on: `checkout → shipping: connection refused` | The load generator started 65s before `shipping` was up. **22 of 25 deployments have no readiness probe**, so traffic reaches pods before they're ready | Accepted as a start-up transient (0 errors since 10:14). **Scheduled for Phase 5:** add readiness probes + the Kyverno `require-probes` policy, then redeploy and confirm zero start-up errors | `increase(...STATUS_CODE_ERROR[2m])` = 0 after start-up |

---

## Teardown and rebuild

```bash
make undeploy        # remove the shop, keep the cluster
make cluster-down    # delete the whole cluster (everything is in Git, so rebuilding is cheap)
make cluster-up && make deploy   # full rebuild
```
