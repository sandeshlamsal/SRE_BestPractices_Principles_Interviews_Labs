# Runbook: SLIDataMissing

| | |
|---|---|
| **Alert** | `SLIDataMissing` (page): fewer than 5 of 5 SLIs have data for 10 min |
| **Why it pages** | Without SLI data **every burn-rate alert is blind**. An outage can happen with nothing firing |
| **Inhibited by** | `TelemetryPipelineStale` (the more specific cause) |

## Diagnose
```bash
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=slo:sli_error:ratio_rate5m'      # which SLIs are missing?
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=time()-max(timestamp(traces_span_metrics_calls_total))'
```
- **All missing** → the telemetry pipeline: [telemetry-pipeline-stale.md](telemetry-pipeline-stale.md).
- **Some missing** → no traffic for that journey (is the load generator running? `http://localhost:8080/loadgen/`), or a span name or status label changed (e.g. a demo upgrade renamed a route); compare with `slos/*.yaml`.
- **SLO rules not loaded** → `kubectl -n observability get prometheusrule slo-checkout`; `make slo-rules`.

## Mitigate
Restore the data path. Until then, **watch user-facing signals by hand** (the shop, Locust failures, frontend-proxy status codes).

## Lesson (P1-ISSUE-16, P2-ISSUE-15)
When telemetry stops, dashboards go **blank, not red**. This alert exists because 5 minutes of SLI data were once lost without anyone noticing.
