# The SRE Way: Our Operating Model

This is the working agreement for how we run services in this lab. It is based on
the Google SRE books and adapted as we learn. Change it through a PR that says what
we learned.

## 1. Reliability is a feature, and it has a target
- 100% is the wrong target. Every service has an **SLO** agreed with its "product owner"
  (us, playing that role).
- We measure what users experience (**SLIs** at the edge: availability, latency,
  correctness), not CPU or memory.
- **Error budget** = 1 − SLO. The budget is there to be spent on shipping and experiments.

## 2. Error budget policy
| Budget remaining (30-day window) | What we do |
|---|---|
| > 50% | Ship freely, run chaos experiments |
| 25–50% | Riskier changes need a rollback plan |
| < 25% | Reliability work takes priority over features |
| Exhausted | Feature freeze, and only reliability fixes ship until the budget recovers |

## 3. Alerting
- **Page only on symptoms that users feel** and that need action now, using multi-window,
  multi-burn-rate alerts on SLOs.
- Cause-based signals (disk, CPU, restarts) go to tickets or dashboards, not pages.
- Every page links to a **runbook**. An alert without a runbook isn't finished.
- An alert that fires with nothing to do gets fixed or deleted within one week.

## 4. Observability
- Every service emits the **three signals** (metrics, traces, logs) through OpenTelemetry.
- Dashboards follow **RED** (Rate, Errors, Duration) for services and **USE**
  (Utilization, Saturation, Errors) for resources.
- The four golden signals (latency, traffic, errors, saturation) appear on the top-level dashboard.

## 5. Incident response
- Roles: **Incident Commander**, **Ops/Tech lead**, **Comms**. The IC coordinates and does not debug.
- Severity: SEV1 (major user impact), SEV2 (partial or degraded), SEV3 (minor, no urgent user impact).
- Mitigate first, then find the root cause. Rollback is the default mitigation.
- Keep a timeline in the incident channel or doc as it happens.

## 6. Postmortems
- Required for every SEV1/SEV2, every page that burned more than 10% of the budget, and every chaos surprise.
- **Blameless**: we look at systems and incentives, not people.
- Every action item has an owner and a due date, and gets tracked until it's done.

## 7. Toil
- Toil: manual, repetitive, automatable work with no lasting value.
- Keep toil below 50% of time. Automate anything done three times.

## 8. Change management
- Everything is in Git (IaC and GitOps). No `kubectl edit` in "prod".
- Progressive delivery: canary → watch SLIs → promote or roll back automatically.

## 9. Capacity and resilience
- Load test before claiming capacity. Know the saturation point of each critical path.
- Run chaos experiments with a hypothesis, a limited blast radius, and an abort condition.
