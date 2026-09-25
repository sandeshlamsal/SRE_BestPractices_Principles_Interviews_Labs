# Runbook: Checkout order integrity

| | |
|---|---|
| **Alert** | `CheckoutOrderIntegrityBudgetBurn` (page / ticket) |
| **SLO** | 99.9% / 30d, correctness |
| **SLI** | cart `EmptyCart` calls that fail ÷ all. EmptyCart runs **after payment** inside `PlaceOrder` |
| **Why it exists** | Game Day 1: 46% of orders were charged but the cart wasn't cleared. Checkout returned **200**, so every availability SLI stayed green ([postmortem](../postmortems/2026-09-25-gd1-cart-not-cleared.md)) |

## What this alert means
Customers are **successfully charged**, but their cart still shows the items. They may order (and pay) twice.
This is a **correctness** failure: nothing returns an error to the user.

## First 5 minutes
1. Acknowledge; confirm on *SRE Lab / SLO & Error Budgets* → `checkout-order-integrity`.
2. What changed? `scripts/flag.sh list | grep -v " off"` (seen: `cartFailure`), `helm history shop -n astronomy-shop | tail -3`.
3. Declare **SEV2** (money is involved) and loop in whoever owns payments/support: affected customers may need refunds.

## Diagnose
- Tempo: `{resource.service.name="cart" && name=~".*EmptyCart" && status=error}`. Seen: `FailedPrecondition: Can't access cart storage`.
- Is Valkey healthy? `kubectl -n astronomy-shop get pod -l app.kubernetes.io/component=valkey-cart`; check its logs.

## Mitigate
1. Flag → `scripts/flag.sh reset`. 2. Valkey down → restart valkey-cart (carts are in memory and will be lost). 3. Recent deploy → `helm rollback`.

## After mitigation (don't skip)
**Count the affected orders** for support and refunds:
```bash
curl -s -G localhost:9090/api/v1/query --data-urlencode \
 'query=sum(increase(traces_span_metrics_calls_total{service_name="cart",span_name="POST /oteldemo.CartService/EmptyCart",status_code="STATUS_CODE_ERROR"}[<incident duration>]))'
```
