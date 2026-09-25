# Incident: Orders charged but cart not cleared (Game Day 1)

> Live incident record (game day). Postmortem: [postmortems/2026-09-25-gd1-cart-not-cleared.md](../postmortems/2026-09-25-gd1-cart-not-cleared.md)

| | |
|---|---|
| **Status** | Resolved |
| **Severity** | SEV2 (money involved: possible duplicate charges) |
| **Declared** | 2026-09-25T21:14:21Z (by the game-day team; **no alert fired**) |
| **IC / Ops / Comms / Scribe** | Claude (worked example; one person, all roles) |
| **Affected SLOs** | none alerted: *that is the finding*. New: `checkout-order-integrity` |
| **Game day** | `gd-20260925-210359`, scenario `cart-failure` (`cartFailure` = 50%). Not blind: the responder knew the scenario |

## Summary
From 21:04:00 to 21:14:52 UTC, 46% of `EmptyCart` calls failed (`Can't access cart storage`). Checkout still returned
**HTTP 200** and payment was charged, so customers kept a full cart after paying (duplicate-order risk).
**17 of 37 orders** were affected. No SLI moved and nothing alerted.

## Timeline (UTC)
| Time | Event |
|---|---|
| 21:03:35 | Pre-flight: flags off, awake, no stray jobs. Found and fixed: dead Prometheus port-forward; `caffeinate` about to expire |
| 21:04:00 | Failure injected: `cartFailure` → 50% |
| 21:04–21:14 | **No alert.** Cart availability SLI = 0 errors; all pages silent |
| 21:14:21 | Game-day team checks why no page: `AddItem` 151/151 OK; **`EmptyCart` 12/26 ERROR** |
| 21:14:35 | Trace `85e4982c…`: `checkout PlaceOrder` ok, `payment Charge` ok, **`cart EmptyCart` ERROR `FailedPrecondition: Can't access cart storage`**; frontend `POST /api/checkout` = 200 |
| 21:14:40 | **Declared SEV2**: customers charged with stale carts |
| 21:14:52 | Mitigation: `scripts/gameday.sh end` (flag reset) |
| 21:16:22 | Verified: 0 `EmptyCart` errors in the last minute |
| 21:16:30 | Impact counted: **17 of 37** EmptyCart calls failed between 21:04 and 21:16 |
| 21:17 | Detection fix deployed: `checkout-order-integrity` SLO + runbook; `SLIDataMissing` made self-maintaining |
| 21:18:32 | `CheckoutOrderIntegrityBudgetBurn` **page** delivered (PagerDuty + Slack sinks), computed from this incident's data still in its windows |
| 21:18:34 | Re-injection stopped (it wasn't needed for the page, see postmortem) |

## Follow-ups
See the postmortem's action items.
