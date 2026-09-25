# 02: Error Budgets and the Budget Policy

> The error budget turns reliability from an argument into a number.

## Definition

```
Error budget = 1 − SLO
```

With a 99.5% checkout SLO over 30 days, **0.5% of checkouts are allowed to fail**.
- By requests: 1,000,000 checkouts/month → **5,000** failures allowed.
- By time: a full outage could last **3h 36m** before the budget is gone.

## Why it matters
Without a budget, dev and ops pull against each other: dev wants to ship fast, ops wants no changes.
The budget gives both sides the same number to decide with:

- **Budget left?** Ship features, run experiments, do chaos testing, take risks.
- **Budget gone?** Slow down and work on reliability.

No one has to argue about whether the system is "reliable enough". The budget answers it.

## Burn rate

**Burn rate** = how fast you're consuming the budget, relative to using it up exactly at the end of the window.

```
burn rate = observed error rate / (1 − SLO)
```

| Burn rate | Meaning (30d window) |
|---|---|
| 1x | Budget runs out exactly at day 30 |
| 2x | Runs out in 15 days |
| 6x | Runs out in 5 days |
| 14.4x | Runs out in ~2 days (2% of the monthly budget in 1 hour) |
| 720x | A total outage: runs out in 1 hour |

For the checkout SLO (99.5%), a 14.4x burn means the error rate is **14.4 × 0.5% = 7.2%**.

## Multi-window, multi-burn-rate alerts
This is the standard method from the SRE Workbook. It pages on fast burns, opens tickets
for slow ones, and uses a **short window to confirm** the burn is still happening, which
stops alerts from firing after the problem has already recovered.

| Severity | Long window | Short window | Burn rate | Budget consumed when it fires |
|---|---|---|---|---|
| Page | 1h | 5m | 14.4x | 2% |
| Page | 6h | 30m | 6x | 5% |
| Ticket | 3d | 6h | 1x | 10% |

```promql
# Page: fast burn on checkout availability (SLO 99.5% → budget 0.005)
(
  slo:checkout_errors:ratio_rate1h > (14.4 * 0.005)
  and
  slo:checkout_errors:ratio_rate5m > (14.4 * 0.005)
)
or
(
  slo:checkout_errors:ratio_rate6h > (6 * 0.005)
  and
  slo:checkout_errors:ratio_rate30m > (6 * 0.005)
)
```
Sloth generates these recording rules and alerts from a short SLO spec.

## The error budget policy
A budget does nothing unless there's an agreed policy for what happens when it runs out.
Ours is in [sre-way.md §2](../sre-way.md#2-error-budget-policy). A good policy:
- Is **agreed in advance** by engineering and product, not negotiated during an incident
- States **what changes** at each threshold (release pace, on-call staffing, priorities)
- Has an **escalation path** for disagreements (e.g. a director decides)
- Has **exceptions**: security fixes always ship

### Budget as a release gate
- Canary deploys check the SLI. If the canary burns budget faster than baseline, it rolls back automatically (Phase 7, Argo Rollouts).
- Before a risky change, check how much budget is left in Grafana.

## Mapped to the lab

| Activity | How the budget is used |
|---|---|
| **Phase 1** | Build an error-budget dashboard: remaining %, burn rate, and a burndown for each SLO |
| **Phase 3** | Implement the multi-burn-rate alerts above |
| **Phase 4** | Each game day records **how much budget the incident used**, which goes in the postmortem |
| **Phase 5** | Only run chaos experiments while the budget is above 50% |
| **Phase 7** | Argo Rollouts analysis uses burn rate to decide promote or roll back |

### Exercise: watch the budget burn
1. Open the error-budget dashboard for checkout.
2. In the flag UI (`/feature`), set `paymentFailure` to 50%.
3. Predict: error rate ≈ 50% of checkouts, so burn rate ≈ 0.5 / 0.005 = **100x**, and the budget is gone in 7.2 hours.
4. Confirm the fast-burn page fires in about 5 minutes. Turn the flag off and record the budget consumed.

## Common mistakes
- Having a budget but no policy, so nothing changes when it's exhausted.
- Paging on 1x burn. That's a ticket, not a 3 a.m. wake-up.
- Letting planned maintenance or dependency outages "not count" without writing it down in the SLO.
- Treating unused budget as success. A budget that's always 100% left means the SLO is too loose or you're moving too slowly.

## Interview questions
1. What is an error budget, and how does it resolve conflict between dev and ops?
2. Define burn rate. What does 14.4x mean for a 30-day SLO?
3. Why use multiple windows instead of a single threshold alert?
4. The budget is exhausted but product wants to ship a big launch. What do you do?
5. The budget is always nearly full. Is that good?
