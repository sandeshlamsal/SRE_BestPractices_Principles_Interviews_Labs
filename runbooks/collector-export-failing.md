# Runbook: OtelCollectorExportFailing

| | |
|---|---|
| **Alert** | `OtelCollectorExportFailing` (ticket): a collector is dropping metric points to an exporter for 10+ min |
| **Dashboard** | *SRE Lab / Telemetry Pipeline Health* → Failures |

## Diagnose
```bash
kubectl -n astronomy-shop logs <pod> --since=10m | grep -E "Exporting failed|Permanent error" | tail -5
```
- **HTTP 400 from Prometheus OTLP** → Prometheus rejected the data. Seen in P2-ISSUE-10: **two collectors writing the same series**,
  because a distinguishing resource attribute wasn't promoted to a label (fixed by promoting `host.name`). Check sample density:
  `count_over_time(<metric>[2m])` should be 12 at a 10s interval; 24 means two writers.
- **HTTP 400, small and steady (~1.5%) from one collector on the 60 s flush** → known open issue (P2-ISSUE-10 residual). Prometheus doesn't log OTLP rejection reasons; capture the response with a debugging proxy.
- **HTTP 503 from Loki `at least 1 live replicas required, could only find 0`** → Loki evicted itself from its ring (typically after a host sleep or VM freeze, P2-ISSUE-22): `kubectl -n observability delete pod loki-0`.
- **Connection refused / timeouts** → the backend is down or overloaded.

## Mitigate
Fix the label collision (promote the attribute, or drop/dedupe with a `filter`/`transform` processor) or restore the backend.
