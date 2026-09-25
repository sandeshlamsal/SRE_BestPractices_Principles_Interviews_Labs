# 03: Monitoring, Observability and Alerting

## Monitoring vs observability
- **Monitoring** answers questions you knew to ask in advance: "Is the error rate above 5%?" Dashboards and alerts are monitoring.
- **Observability** lets you answer questions you didn't expect: "Why is checkout slow only for EUR users on the new version?" That requires rich, high-cardinality telemetry you can slice many ways.

You need both. Monitoring tells you something is wrong; observability helps you find out why.

## The three signals (plus one)

| Signal | Best for | Lab tool |
|---|---|---|
| **Metrics** | Trends, alerting, SLOs. Cheap, aggregated. | Prometheus |
| **Traces** | Following a request across services, finding the slow hop | Jaeger (later Tempo) |
| **Logs** | Detailed event context, errors, audit | OpenSearch (later Loki) |
| **Profiles** | CPU and memory hotspots inside a process | Optional: Pyroscope |

OpenTelemetry is the vendor-neutral standard for producing all of them. Every Astronomy Shop service is already instrumented.

## Frameworks for choosing what to watch

**The four golden signals** (Google SRE book), used for any user-facing system:
1. **Latency**: how long requests take. Track successful and failed requests separately, since fast failures hide in averages.
2. **Traffic**: demand, e.g. requests per second.
3. **Errors**: rate of failed requests, whether explicit (5xx) or implicit (wrong content).
4. **Saturation**: how "full" the service is (queue depth, CPU throttling, connection pool usage).

**RED** (for request-driven services): **R**ate, **E**rrors, **D**uration.
**USE** (for resources like nodes, disks, and pools): **U**tilization, **S**aturation, **E**rrors.

## Alerting principles
1. **Page on symptoms, not causes.** "Checkout is failing for users" is a page. "Pod restarted" or "CPU at 90%" isn't.
2. **Every page must be urgent, actionable, and need a human.** If it could wait until morning, make it a ticket. If a script could fix it, automate it.
3. **Alert on SLO burn rate** (see [02](02-error-budgets.md)). It scales with impact and ignores harmless blips.
4. **Every alert has a runbook link** and an owner.
5. **Review alert quality**: track pages per shift and the share that were actionable. A target is under 2 pages per 12-hour shift.

### Alert routing (Alertmanager)

| Label `severity` | Goes to | Example |
|---|---|---|
| `page` | Pager (wakes someone up) | Checkout fast-burn |
| `ticket` | Issue tracker / Slack | Checkout slow-burn over 3 days, disk 80% |
| `info` | Dashboard only | Pod restarts |

Also: **grouping** (combine related alerts into one notification), **inhibition** (if the cluster is down, suppress per-service alerts), and **silences** (planned maintenance).

## Mapped to the lab

### What the Astronomy Shop gives you
- Every service emits OTel traces, metrics, and logs to the **OTel Collector**
- The collector's spanmetrics connector turns traces into RED metrics for every service
- Grafana comes with dashboards for spanmetrics, the collector, and demo services

### Dashboards to build (Phase 2)

| Dashboard | Contents |
|---|---|
| **Shop overview** | Golden signals for frontend-proxy; the SLO and budget panel for each CUJ |
| **Service RED** | Templated by `service_name`: rate, error %, p50/p95/p99 |
| **Kafka / async** | Consumer lag and processing time for accounting and fraud-detection |
| **Cluster USE** | Node CPU, memory, disk, network; pod throttling; OOM kills |

### Alerts to build (Phase 3)

| Alert | Type | Severity |
|---|---|---|
| `CheckoutAvailabilityFastBurn` | SLO burn | page |
| `CheckoutLatencyFastBurn` | SLO burn | page |
| `BrowseAvailabilityFastBurn` | SLO burn | page |
| `*SlowBurn` (3d/6h) | SLO burn | ticket |
| `KafkaConsumerLagHigh` | Cause | ticket |
| `PodCrashLooping` | Cause | ticket |
| `NodeNotReady` | Cause | ticket (pages only if SLOs burn) |

### Exercise: the alert → dashboard → trace → log path
1. Turn on the `productCatalogFailure` flag.
2. Starting from the alert, find the failing endpoint on the overview dashboard.
3. Jump to an exemplar trace in Jaeger and find the span marked as an error.
4. Find the matching log line using the trace ID.
5. Time yourself. The target is under 2 minutes.

## Common mistakes
- Dashboards with 60 panels and no clear story. Start from the user, then drill down.
- Alerting on every cause. This leads to alert fatigue and real pages getting ignored.
- High-cardinality labels in Prometheus (user ID, order ID). Put those in traces or logs instead.
- Watching averages instead of percentiles or histograms.

## Interview questions
1. What's the difference between monitoring and observability?
2. Name the four golden signals. When would you use RED vs USE?
3. Why page on symptoms rather than causes? Give an example of each.
4. How do you reduce alert fatigue on a team?
5. What is metric cardinality, and why can it take Prometheus down?
6. Walk through debugging a latency spike in a microservice app, from alert to root cause.
