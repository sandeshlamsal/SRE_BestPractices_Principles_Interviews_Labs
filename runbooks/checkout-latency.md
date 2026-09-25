# Runbook: Checkout latency

| | |
|---|---|
| **Alert** | `CheckoutLatencyBudgetBurn` (page: 14.4x over 1h+5m or 6x over 6h+30m · ticket: 3x over 1d+2h or 1x over 3d+6h) |
| **SLO** | 99% / 30d (spec: [slos/](https://github.com/sandeshlamsal/SRE_BestPractices_Principles_Interviews_Labs/blob/main/slos)) |
| **SLI** | `POST /api/checkout` slower than **1000 ms** (histogram bucket `le=1000`) ÷ all |
| **Dashboards** | *SRE Lab / SLO & Error Budgets*, *SRE Lab / Service RED* |
| **Critical path** | as for checkout availability; latency usually comes from product-catalog, currency, shipping/quote or payment |

## What this alert means
Users are affected, and at the current rate the 30-day error budget runs out early. The page variant means at least
2% of the monthly budget went in the last hour (or 5% in 6 hours).

## First 5 minutes
1. **Acknowledge** the page (PagerDuty) and say you're on it in `#pages`.
2. **Confirm user impact:** Grafana → *SRE Lab / SLO & Error Budgets* → select the SLO. Is the SLI below the objective line? What's the burn rate?
3. **Check what changed** in the last hour:
   ```bash
   helm history shop -n astronomy-shop | tail -3                 # recent deploys
   scripts/flag.sh list | grep -v " off"                          # feature flags that are ON
   kubectl get events -n astronomy-shop --sort-by=.lastTimestamp | tail -15
   ```
4. **Declare an incident** if the impact is confirmed (severity rules: [incident-response-plan.md](../docs/incident-response-plan.md#2-severity-matrix-tied-to-slos)).

## Diagnose
- *SRE Lab / Service RED* → `checkout`, then each dependency: whose p99 moved?
- Tempo: `{resource.service.name="checkout" && duration > 1s}` → the widest child span is the slow hop.
- **Check for memory-limit thrashing** on the slow service (Phase 2 root cause: product-catalog at a 20Mi limit):
  ```bash
  curl -s -G localhost:9090/api/v1/query --data-urlencode \
   'query=topk(5, sum by (namespace,container) (rate(container_memory_failcnt{container!=""}[5m])))'
  ```
- CPU saturation: RED p99 against the kube-prometheus-stack *Node Exporter / USE Method* dashboard.

## Mitigate (in this order)
1. Flag-induced (`intlShippingSlowdown`, `productCatalogLockContention`, `imageSlowLoad`) → `scripts/flag.sh reset`.
2. Thrashing → raise that container's memory limit in `apps/astronomy-shop/values.yaml`, then `make deploy` (size from `failcnt` and working set, not guesses).
3. Recent deploy → `helm rollback`.
4. Saturation → `kubectl -n astronomy-shop scale deploy/<svc> --replicas=2` as a stopgap, then fix it properly through Git.

## Verify recovery
- SLI 5m back under the objective on the SLO dashboard. **Expect the page to keep firing for up to ~30 min** after the fix:
  the 30m/6h pair stays over its threshold until the failures age out of the window (P1-ISSUE-14). That's by design.
- Record in the incident doc: detection time, mitigation time, budget consumed (`slo:period_error_budget_remaining:ratio`).

## Known causes seen in this lab
- Injected with flags: `scripts/flag.sh list`.
- Memory-limit thrashing on a dependency shows up as **latency, not crashes** ([container-memory-thrashing.md](container-memory-thrashing.md)).
