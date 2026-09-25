# Postmortem: Orders charged but cart not cleared (Game Day 1)

| | |
|---|---|
| Date | 2026-09-25 |
| Severity | SEV2 |
| Type | Game day (worked example, **not blind**) · scenario `cart-failure` |
| Duration | impact 21:04:00 → 21:14:52 UTC (**10 min 52 s**) |
| Detected by | the game-day team noticing the **absence** of an alert, **not** by monitoring |
| MTTD | 10 min 21 s (human, after an expected page never came). **Monitoring MTTD: never** |
| MTTM | 10 min 52 s |
| Customer impact | **17 of 37 orders (46%)** charged with the cart not cleared |
| Error budget | none charged: no SLO covered this. That's the finding |
| Status | Reviewed · action items tracked below |

## Summary
A cart-storage failure made `EmptyCart` fail after payment. The checkout flow **ignores that failure and returns 200**,
so from every SLI's point of view the system was perfectly healthy while customers were charged and left with a full cart.
Our SLOs measured *availability* and *latency* but not *correctness*.

## Impact
- 17 orders completed and charged with the cart still full. Those customers may have ordered and paid again.
- In a real business this means support tickets, refunds, and trust damage, all with zero signal in monitoring.

## What happened
`cartFailure` (50%) makes the cart service fail storage access. The effects:
- `AddItem` and `GetCart` were **not** affected (151 and 558 calls, 0 errors), so the add-to-cart SLO stayed at 100%.
- `EmptyCart` failed 46% of the time with `FailedPrecondition: Can't access cart storage`.
- `checkout` treats `EmptyCart` as best-effort: `PlaceOrder` succeeds and the frontend returns **200**.

## Contributing factors (no single root cause)
1. **No correctness SLI.** Every SLO was availability or latency; "succeeded but did the wrong thing" was invisible.
2. **The failure is swallowed.** Checkout continues after a failed `EmptyCart`, so no error reaches the user-facing layer we measure.
3. **Our own scenario catalog was wrong.** It predicted "add-to-cart fails" and expected `cart-availability` to catch it. The flag's actual behaviour hits a different operation. **We would have missed this if we'd only checked whether the expected alert fired.**
4. `SLIDataMissing` had a **hard-coded `< 5`**, which would have broken silently when a 6th SLO was added (found while fixing #1).

## Detection
None from monitoring. The game-day team investigated because an *expected* page didn't arrive.
**Lesson:** in a game day, "no alert" is a result that needs explaining, not a pass.

## What went well
- Pre-flight caught two things that would have ruined the drill (a dead port-forward, `caffeinate` about to expire).
- Tracing made the invisible failure obvious in one trace: `Charge` ok → `EmptyCart` ERROR → HTTP 200.
- Impact was counted precisely from span metrics (17/37) for support and refunds.

## What went wrong
- No signal for about 11 minutes; a real incident like this would be found by customers.
- The first verification of the new SLO was **confounded**: the page fired 5 s after re-injection because the windows still
  held the incident's own errors. We report it as "the SLI detects it", not as a 5 s time to detect.

## Where we got lucky
- It was a game day. And the flag failed 46% of calls, not a quieter 1%; a small failure rate would still take a long time to show up even with the new SLO.

## Action items
| # | Action | Type | Owner | Due | Status |
|---|---|---|---|---|---|
| 1 | Add a correctness SLO `checkout-order-integrity` (EmptyCart success, 99.9%) + runbook | Detect | SRE | 2026-09-25 | ✅ done: pages via PagerDuty + Slack routes |
| 2 | Make `SLIDataMissing` self-maintaining (`count(objectives) − count(SLIs) > 0`) | Detect | SRE | 2026-09-25 | ✅ done |
| 3 | Fix the game-day catalog: `cart-failure` → "orders charged, cart not cleared", expected `checkout-order-integrity` | Process | SRE | 2026-09-25 | ✅ done |
| 4 | Re-run `cart-failure` **after the SLO windows clear** to measure a clean time to detect | Detect | SRE | after 03:15 UTC | ⏳ deferred: the 6h page window holds GD1's errors (P4-ISSUE-10) |
| 5 | Ask the checkout owners: should `EmptyCart` failure be retried or compensated (clear the cart asynchronously) instead of ignored? | Prevent | app team | — | ⏳ open |
| 6 | Look for other swallowed failures in `PlaceOrder` (email, Kafka publish) | Detect | SRE | Phase 4 | ✅ done: email loss invisible (P4-ISSUE-7, SLI open); **Kafka lost ~13 orders** with OK producer spans and lag 0 → new **order-pipeline-completeness** SLO (pages) (P4-ISSUE-8) |

*This postmortem is blameless. The system allowed a failure to be swallowed and our SLOs didn't look for it. Both are design gaps, not mistakes by any person.*
