# Runbooks

Every alert that can reach a human links here through its `runbook` annotation. `make check-runbooks` checks that each link points to a file that exists.

| Alert | Severity | Runbook |
|---|---|---|
| CheckoutAvailabilityBudgetBurn | page / ticket | [checkout-availability.md](checkout-availability.md) |
| CheckoutLatencyBudgetBurn | page / ticket | [checkout-latency.md](checkout-latency.md) |
| BrowseAvailabilityBudgetBurn | page / ticket | [browse-availability.md](browse-availability.md) |
| BrowseLatencyBudgetBurn | page / ticket | [browse-latency.md](browse-latency.md) |
| CartAvailabilityBudgetBurn | page / ticket | [cart-availability.md](cart-availability.md) |
| CheckoutOrderIntegrityBudgetBurn | page / ticket | [checkout-order-integrity.md](checkout-order-integrity.md) |
| OrderPipelineCompletenessBudgetBurn | page / ticket | [order-pipeline-completeness.md](order-pipeline-completeness.md) |
| SLIDataMissing | page | [sli-data-missing.md](sli-data-missing.md) |
| TelemetryPipelineStale, OtelCollectorDown | page, ticket | [telemetry-pipeline-stale.md](telemetry-pipeline-stale.md) |
| OtelCollectorExportFailing | ticket | [collector-export-failing.md](collector-export-failing.md) |
| ContainerMemoryLimitThrashing | ticket | [container-memory-thrashing.md](container-memory-thrashing.md) |
| kube-prometheus-stack defaults | critical / warning → ticket | upstream `runbook_url` (runbooks.prometheus-operator.dev) |

## Silencing during planned work
Planned maintenance (upgrades, migrations) burns budget and fires alerts (P2-ISSUE-11/12). Silence **before** you start:
```bash
AM="kubectl -n observability exec alertmanager-kps-alertmanager-0 -c alertmanager -- amtool --alertmanager.url=http://localhost:9093"
$AM silence add namespace=astronomy-shop --duration=1h --author="$USER" --comment="planned: chart upgrade"
$AM silence query
$AM silence expire <id>          # when done
```
Silences aren't a substitute for fixing noisy alerts. An alert that's silenced repeatedly should be fixed or deleted.
