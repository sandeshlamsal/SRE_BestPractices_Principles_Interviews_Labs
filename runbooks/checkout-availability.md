# Runbook: Checkout availability

| | |
|---|---|
| **Alert** | `CheckoutAvailabilityBudgetBurn` (page: 14.4x over 1h+5m or 6x over 6h+30m · ticket: 3x over 1d+2h or 1x over 3d+6h) |
| **SLO** | 99.5% / 30d (spec: [slos/](https://github.com/sandeshlamsal/SRE_BestPractices_Principles_Interviews_Labs/blob/main/slos)) |
| **SLI** | `POST /api/checkout` responses that are 5xx **or 422** (the frontend's failed-order response) ÷ all |
| **Dashboards** | *SRE Lab / SLO & Error Budgets*, *SRE Lab / Service RED* |
| **Critical path** | frontend → checkout → cart, product-catalog, currency, shipping→quote, **payment**, email, Kafka |

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
```bash
# Which dependency is failing? (server-span errors by service/operation)
curl -s -G localhost:9090/api/v1/query --data-urlencode \
 'query=topk(5, sum by (service_name,span_name) (rate(traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])))'
```
- Grafana → Explore → **Tempo**: `{resource.service.name="checkout" && status=error}` → open a trace → the red span names the failing dependency and the error (e.g. `failed to charge card ... Invalid token`).
- From the span → **Logs for this span** (Loki) for full context.
- The HTTP status is **422**, not 5xx. Span-status dashboards can look green while checkout is failing (P1-ISSUE-11).

## Mitigate (in this order)
1. **Recent flag change?** → `scripts/flag.sh reset`. Seen: `paymentFailure`, `paymentUnreachable`.
2. **Recent deploy?** → `helm rollback shop <previous-revision> -n astronomy-shop`.
3. **One dependency wedged?** → capture a trace first, then `kubectl -n astronomy-shop rollout restart deploy/<service>` (a restart destroys evidence).
4. Escalate to the owning team if it's none of the above.

## Verify recovery
- SLI 5m back under the objective on the SLO dashboard. **Expect the page to keep firing for up to ~30 min** after the fix:
  the 30m/6h pair stays over its threshold until the failures age out of the window (P1-ISSUE-14). That's by design.
- Record in the incident doc: detection time, mitigation time, budget consumed (`slo:period_error_budget_remaining:ratio`).

## Known causes seen in this lab
- Injected with flags: `scripts/flag.sh list`.
- Memory-limit thrashing on a dependency shows up as **latency, not crashes** ([container-memory-thrashing.md](container-memory-thrashing.md)).
