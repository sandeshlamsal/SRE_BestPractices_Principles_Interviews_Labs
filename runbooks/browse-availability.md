# Runbook: Browse availability

| | |
|---|---|
| **Alert** | `BrowseAvailabilityBudgetBurn` (page: 14.4x over 1h+5m or 6x over 6h+30m · ticket: 3x over 1d+2h or 1x over 3d+6h) |
| **SLO** | 99.9% / 30d (spec: [slos/](https://github.com/sandeshlamsal/SRE_BestPractices_Principles_Interviews_Labs/blob/main/slos)) |
| **SLI** | `GET /api/products*` + `GET /api/recommendations` responses that are 5xx ÷ all |
| **Dashboards** | *SRE Lab / SLO & Error Budgets*, *SRE Lab / Service RED* |
| **Critical path** | frontend → product-catalog → astronomy-db (Postgres); ad, recommendation, currency on the page |

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
- RED → `product-catalog`: errors by operation.
- Tempo: `{resource.service.name="product-catalog" && status=error}`. Is it **one product** or all? (`productCatalogFailure` fails only `OLJCESPC7Z`.) Partial failures matter: 99.9% leaves only 43 min of budget per 30 days.
- DB: `kubectl -n astronomy-shop logs deploy/astronomy-db --since=15m | tail`.

## Mitigate (in this order)
1. Flag → `scripts/flag.sh reset` (seen: `productCatalogFailure`, a **targeted** flag, P2-ISSUE-18).
2. Recent deploy → `helm rollback`.
3. DB down → check the `astronomy-db` pod and events; restart only as a last resort.

## Verify recovery
- SLI 5m back under the objective on the SLO dashboard. **Expect the page to keep firing for up to ~30 min** after the fix:
  the 30m/6h pair stays over its threshold until the failures age out of the window (P1-ISSUE-14). That's by design.
- Record in the incident doc: detection time, mitigation time, budget consumed (`slo:period_error_budget_remaining:ratio`).

## Known causes seen in this lab
- Injected with flags: `scripts/flag.sh list`.
- Memory-limit thrashing on a dependency shows up as **latency, not crashes** ([container-memory-thrashing.md](container-memory-thrashing.md)).
