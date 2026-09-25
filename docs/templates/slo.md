# SLO: <service> / <user journey>

| Field | Value |
|---|---|
| Service | |
| User journey | e.g. "Customer completes checkout" |
| SLI type | availability / latency / correctness |
| SLI definition | good events / valid events, and the PromQL |
| Measurement point | e.g. frontend-proxy (edge) |
| SLO target | e.g. 99.5% |
| Window | 30 days rolling |
| Error budget | e.g. 0.5% = ~3h 36m / 30d |
| Burn-rate alerts | 14.4x over 1h & 5m (page) · 6x over 6h & 30m (page) · 1x over 3d & 6h (ticket) |
| Owner | |

## Rationale
Why this target? What does the user notice below it?

## Exclusions
What doesn't count, e.g. synthetic traffic or 4xx client errors.
