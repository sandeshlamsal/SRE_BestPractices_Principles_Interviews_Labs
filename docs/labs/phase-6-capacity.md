# Phase 6: Capacity and Performance (Execution Guide)

> **Goal:** find the traffic level where the SLO breaks (the *knee*), the component that saturates first, and the headroom.
> **Principles:** [08 Capacity](../principles/08-capacity-resilience-chaos.md). **Executed:** 2026-09-26 04:17–04:25 UTC.

## Test design
- [loadtests/checkout-journey.js](../../loadtests/checkout-journey.js): the **real** user journey with the demo load generator's own payloads:
  products → product → recommendations → add to cart → checkout, 1 s think time.
- Stepped ramp **10 → 25 → 50 → 100 VUs**, 90 s per step.
- Runs **in the cluster** ([k6-job.yaml](../../loadtests/k6-job.yaml), k6 1.4.0) against `frontend-proxy`, so the laptop port-forward
  can't be the bottleneck.
```bash
make loadtest                                        # ConfigMap from the script + Job
kubectl -n astronomy-shop logs -f job/k6-capacity    # summary at the end (~7.5 min)
```

## Result: congestion collapse above ~58 req/s
| Minute (UTC) | Load | Edge throughput | Edge failures | product-catalog p99 |
|---|---|---|---|---|
| 04:17–18 | 10 VUs | 38–49 req/s | 0% | ~200 ms |
| 04:19–20 | 25 VUs | **51–58 req/s (peak)** | 0–2.3% | **942 ms** |
| 04:21–22 | 50 VUs | 33 → 21 req/s | 17–28% | **15 s (timeout)** |
| 04:23–24 | 100 VUs | 21 → 12 req/s | **44–51%** | 15 s |

k6 summary: 13,658 requests, **14.6% failed**, checkout p99 **15 s**. products/product/checkout failed ~17–20%; **add-to-cart 100% OK**.
**More load produced *less* throughput**: past the knee, queued requests time out and retries add load (congestion collapse).

## Finding the bottleneck (what it wasn't, then what it was)
| Hypothesis | Evidence | Verdict |
|---|---|---|
| CPU saturation | Busiest container 0.62 cores of 8; 0% throttling | ❌ |
| Memory-limit thrashing (Postgres limit 100 Mi) | `container_memory_failcnt` rate = **0** everywhere | ❌ |
| Postgres connection limit | `max_connections=100`, no "too many clients" errors | ❌ |
| **Product-catalog waits before querying** | Slow trace: `ListProducts` **68,450 ms**, of which the **DB query = 43 ms**, starting at **+68,406 ms** | ✅ |

**Root cause:** requests queue **inside product-catalog** for ~68 s before issuing a 43 ms query, which points to
**client-side DB connection-pool starvation / a concurrency limit** in the service. Postgres itself is fast. The failing calls
(products, product, checkout) all hit product-catalog; add-to-cart doesn't, and it stayed at 100%.
Metrics couldn't show this. **One trace did.**

## Capacity statement (current configuration)
- **Knee: ~58 req/s at the edge ≈ 25 concurrent users running the full journey (~3.5 checkouts/s).**
- Normal load (the demo load generator): ~10–15 req/s → **~4× headroom** before the latency SLO breaks.
- Past the knee, the system **collapses** rather than degrading gracefully: no load shedding, 15 s timeouts, no backpressure.

## Recommendations (capacity plan)
1. **Fix the constraint, not the symptoms:** raise product-catalog's DB pool / concurrency (a code/config change for the app team),
   or scale product-catalog horizontally (each replica brings its own pool). Re-run the same test to find the new knee.
2. **Fail fast instead of queueing 15–68 s:** shorter timeouts on the product-catalog path (e.g. 2 s) plus load shedding at Envoy,
   so overload returns fast errors instead of collapse.
3. **An HPA won't help this bottleneck by itself**, since CPU never rose. Autoscale on a signal that tracks the constraint (in-flight
   requests / latency), or fix the pool first.
4. Re-run after every capacity-relevant change and record the knee here.

## Issues log
| ID | Area | Symptom | Root cause | Fix / decision |
|---|---|---|---|---|
| P6-ISSUE-1 | Capacity | Throughput collapses above ~58 req/s; 51% errors at 100 VUs | Product-catalog requests queue ~68 s before a 43 ms DB query (pool/concurrency starvation) | Open: raise pool / scale product-catalog, then re-test |
| P6-ISSUE-2 | Resilience | Overload produced 15 s timeouts, not fast failures | No load shedding; long timeouts turn overload into collapse | Open: shorter timeouts + Envoy load shedding |
| P6-ISSUE-3 | Tooling | Grafana/Tempo API returned non-JSON after the hardening deploy | The `:8080` port-forward was bound to a replaced frontend-proxy pod (P2-ISSUE-7 again) | Restart `make open` after rollouts |
