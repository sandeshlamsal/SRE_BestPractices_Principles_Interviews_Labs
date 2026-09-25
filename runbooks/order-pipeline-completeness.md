# Runbook: Order pipeline completeness

| | |
|---|---|
| **Alert** | `OrderPipelineCompletenessBudgetBurn` (page / ticket) |
| **SLO** | 99.9% / 30d: orders published by checkout vs orders processed by accounting |
| **Why it exists** | Phase 4 audit: Kafka down 3 min → checkout still 200, publish span "OK", **11 orders never processed**, consumer lag 0 (the topic was wiped). Nothing else alerted |

## What this alert means
Customers' orders succeeded, but downstream **accounting and fraud checks are not receiving them**: lost (broker restart)
or stuck (consumer down, backlog growing). Money and fraud risk, invisible to the customer-facing SLOs.

## Diagnose
```bash
kubectl -n astronomy-shop get pods | grep -E "kafka|accounting|fraud"
# published vs processed per minute:
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=sum(increase(traces_span_metrics_calls_total{service_name="checkout",span_name="publish orders"}[10m]))'
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=sum(increase(traces_span_metrics_calls_total{service_name="accounting",span_name="order-consumed"}[10m]))'
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=max(kafka_consumer_records_lag_max)'     # lag = stuck; lag 0 + missing = LOST
```
- Gap and **growing lag** → the consumer is slow or down: scale or restart accounting.
- Gap and **lag 0** → messages were **lost** (broker restart without persistence). Count them for reconciliation.

## Mitigate
Restore the broker or consumer; `kafkaQueueProblems` flag → `scripts/flag.sh reset`.
**Then reconcile:** lost orders must be replayed from the order database (in production) or listed for finance.

## Prevention (backlog)
Kafka persistence (PVC) + `acks=all`; producer delivery callbacks that mark spans ERROR on failed delivery.
