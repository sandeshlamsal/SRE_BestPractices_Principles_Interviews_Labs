# Runbook: TelemetryPipelineStale / OtelCollectorDown

| | |
|---|---|
| **Alerts** | `TelemetryPipelineStale` (page): no span-derived metrics for > 5 min · `OtelCollectorDown` (ticket) |
| **Dashboard** | *SRE Lab / Telemetry Pipeline Health* (collector self-metrics are **pulled** directly, so it works even when the pipeline is down) |

## Diagnose, from the top down
```bash
kubectl -n astronomy-shop get pods -l app.kubernetes.io/name=opentelemetry-collector
kubectl -n observability get pods                                   # Prometheus / Tempo / Loki up?
kubectl -n astronomy-shop logs <collector-pod> --since=10m | grep -iE "error|refused|dropping" | tail
```
Pipeline dashboard: *received* dropping → the apps stopped sending. *Received* fine but *sent* dropping → an exporter or backend problem. Refused → the memory limiter.

**Then check the platform itself** (the real cause in Phases 1–2):
```bash
top -l 1 -n 0 | grep -E "PhysMem|Load Avg"                                   # host starved? (Docker VM RSS)
docker exec sre-lab-worker cat /proc/pressure/memory /proc/pressure/io        # VM stalls
```
and container limit thrashing ([container-memory-thrashing.md](container-memory-thrashing.md)).

## Mitigate
- Collector crash-looping → `kubectl -n astronomy-shop rollout restart ds/otel-collector-agent`.
- Backend down → restore Prometheus (`kubectl -n observability get pod prometheus-kps-prometheus-0`).
- Host or VM starved → free memory; Docker Desktop ≤ 12 GB on a 32 GB Mac (P2-ISSUE-14).
