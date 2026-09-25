# 01: SLIs, SLOs and SLAs

> "It's not a question of whether the system is up. It's whether users are happy."

## Definitions

| | SLI | SLO | SLA |
|---|---|---|---|
| **What** | A measurement | A target for that measurement | A contract built on the target |
| **Example** | % of checkout requests that return success in < 1s | 99.5% over 30 days | 99.0% monthly, or customers get 10% credit |
| **Audience** | Engineers | Engineering + product | Customers, legal, sales |
| **If missed** | — | Error budget policy applies (freeze features, focus on reliability) | Financial or legal penalty |

The rule: **SLA < SLO < what you actually achieve.** The SLO sits tighter than the SLA
so you get warned internally well before you owe anyone money.

## SLI: Service Level Indicator

An SLI is always a ratio:

```
SLI = good events / valid events × 100%
```

Using a ratio keeps every SLI on a 0–100% scale and makes error budgets easy to compute.

### Common SLI types

| Type | Question it answers | Good event |
|---|---|---|
| **Availability** | Did it work? | Non-5xx response |
| **Latency** | Was it fast enough? | Response in < threshold (use a histogram, not the average) |
| **Quality / correctness** | Was the answer right? | Response not degraded (e.g. real recommendations, not a fallback) |
| **Freshness** | Is the data recent? | Data updated within N minutes |
| **Throughput / durability** | Did the pipeline keep up? Did data survive? | Message processed within N seconds |

### Where to measure
Measure as close to the user as possible. Options, from best to worst fidelity:

1. **Client/RUM** (browser): the truest picture, but noisy and harder to collect
2. **Edge / load balancer** (our `frontend-proxy`, which is Envoy): **the default in this lab**
3. **Service** (spans/metrics from each service): good for diagnosis, not ideal for SLOs
4. **Synthetic probes**: useful for low-traffic paths and for catching total outages

## SLO: Service Level Objective

An SLO is **SLI target + time window**, e.g. *99.5% of checkout requests succeed, measured over a rolling 30 days*.

### What the "nines" allow (30-day window)

| SLO | Error budget | Allowed full downtime / 30d |
|---|---|---|
| 99% | 1% | 7h 12m |
| 99.5% | 0.5% | 3h 36m |
| 99.9% | 0.1% | 43m 12s |
| 99.95% | 0.05% | 21m 36s |
| 99.99% | 0.01% | 4m 19s |

Each extra nine costs roughly **10× more** engineering effort. Pick the lowest target at which users are still happy.

### Why not 100%?
- Users can't tell 99.99% from 100%, because their Wi-Fi, ISP, and phone are less reliable than that.
- 100% means no changes, which means no features.
- Dependencies multiply: five serial dependencies at 99.9% each give at most **0.999⁵ ≈ 99.5%**.

### Rolling vs calendar windows
- **Rolling 30d**: matches what users experience. This is the default here.
- **Calendar month**: matches how SLAs and billing are measured, but the budget "resets" on the 1st, which encourages bad habits.

### How to choose a target
1. Measure the current baseline over 2–4 weeks.
2. Ask what level users would actually notice or complain about.
3. Set the SLO at or slightly below the baseline. Don't promise what you don't achieve today.
4. Review it quarterly. Tighten it if users complain while you're still in budget. Loosen it if you're burning budget and nobody notices.

## SLA: Service Level Agreement
- A business and legal document. SREs usually **advise** on it but don't own it.
- Only a few SLIs appear in an SLA, and they're usually the simplest (availability).
- Keep a margin: if the SLO is 99.5%, the SLA might be 99.0%.
- Internal platforms often have SLOs and **no** SLA.

---

## Mapped to the lab: Astronomy Shop

### Critical user journeys (CUJs)

| CUJ | Entry point | Services involved |
|---|---|---|
| **Browse catalog** | `GET /api/products`, `GET /product/{id}` | frontend → product-catalog, currency, ad, recommendation, image-provider |
| **Add to cart** | `POST /api/cart` | frontend → cart → valkey (Redis) |
| **Checkout** | `POST /api/checkout` | frontend → checkout → cart, product-catalog, currency, shipping, quote, payment, email, Kafka → accounting / fraud-detection |

Checkout is where the money comes from, so it gets the strictest SLO.

### Proposed SLOs (to be validated against the baseline in Phase 1)

| CUJ | SLI | SLO (30d rolling) | Budget |
|---|---|---|---|
| Checkout | Availability: non-error `PlaceOrder` responses | 99.5% | 3h 36m |
| Checkout | Latency: `PlaceOrder` under 1s | 99% | 7h 12m |
| Browse | Availability: non-5xx on product APIs | 99.9% | 43m |
| Browse | Latency: product API under 300ms | 99% | 7h 12m |
| Add to cart | Availability | 99.9% | 43m |

### Example SLI queries (PromQL)

The OTel demo derives request metrics from traces using the collector's *spanmetrics*
connector. Metric and label names differ between chart versions, so **check them in
Prometheus during Phase 1** before relying on these.

```promql
# Checkout availability SLI (ratio of good to valid, over 5m)
sum(rate(traces_span_metrics_calls_total{
      service_name="checkout", span_name="oteldemo.CheckoutService/PlaceOrder",
      status_code!="STATUS_CODE_ERROR"}[5m]))
/
sum(rate(traces_span_metrics_calls_total{
      service_name="checkout", span_name="oteldemo.CheckoutService/PlaceOrder"}[5m]))

# Checkout latency SLI: share of requests under 1000ms
sum(rate(traces_span_metrics_duration_milliseconds_bucket{
      service_name="checkout", span_name="oteldemo.CheckoutService/PlaceOrder", le="1000"}[5m]))
/
sum(rate(traces_span_metrics_duration_milliseconds_count{
      service_name="checkout", span_name="oteldemo.CheckoutService/PlaceOrder"}[5m]))
```

### Lab exercises (Phase 1)
- [ ] Record a one-week baseline for each SLI above
- [ ] Write one SLO doc per CUJ in `slos/` using [the template](../templates/slo.md)
- [ ] Generate recording rules and alerts with Sloth
- [ ] Turn on the `paymentFailure` flag at 10% and watch the checkout SLI fall while browse stays flat

## Common mistakes
- Using CPU or memory as an SLI. Users don't feel CPU.
- Averaging latency. Use percentiles or threshold-based ratios.
- Too many SLOs. Aim for 1–3 per CUJ.
- Setting the SLO equal to the SLA, which leaves no warning before a breach.
- Counting health checks or load-generator traffic as user traffic. Exclude them, or label them separately.

## Interview questions
1. Explain SLI vs SLO vs SLA with an example.
2. Why shouldn't an SLO be 100%?
3. How would you choose an SLO for a new service with no history?
4. Where would you measure availability for a web app, and what are the trade-offs?
5. Your service depends on 4 services, each at 99.9%. What's your best possible availability?
6. Why use a ratio (good/valid) instead of counting "minutes of downtime"?
