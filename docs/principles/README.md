# SRE Principles, Mapped to This Lab

This section explains the core SRE concepts. Each one is tied to something concrete
in the Astronomy Shop and to the roadmap phase where you practice it.

[../sre-way.md](../sre-way.md) is the short list of rules we operate by. These
pages explain why those rules exist.

## How the pieces fit together

```
            User journeys (browse, add to cart, checkout)
                              │
                              ▼
   SLI ── "what we measure": good events / valid events
                              │
                              ▼
   SLO ── "the target": 99.5% of checkouts succeed over 30 days
     │                        │
     │                        ▼
     │     Error budget ── 1 − SLO = 0.5% allowed to fail
     │                        │
     │        ┌───────────────┼──────────────────┐
     │        ▼               ▼                  ▼
     │   Burn-rate      Release decisions    Chaos / risk
     │   alerts         (budget policy)      experiments
     │        │
     │        ▼
     │   Incident management ── IC, severity, mitigate first
     │        │
     │        ▼
     │   Postmortem ── blameless, action items
     │        │
     │        ▼
     │   Toil reduction / automation / resilience fixes
     │        │
     └────────┴──► SLOs are reviewed and adjusted (the loop closes)
   SLA ── the external contract, always looser than the SLO
```

## Pages

| # | Topic | Roadmap phase |
|---|---|---|
| 01 | [SLIs, SLOs, SLAs](01-sli-slo-sla.md) | Phase 1 |
| 02 | [Error budgets & budget policy](02-error-budgets.md) | Phases 1, 3, 7 |
| 03 | [Monitoring, observability & alerting](03-monitoring-alerting.md) | Phases 2, 3 |
| 04 | [Incident management](04-incident-management.md) | Phase 4 |
| 05 | [Postmortems](05-postmortems.md) | Phase 4 onward |
| 06 | [Toil & automation](06-toil-automation.md) | Ongoing |
| 07 | [Release engineering & change management](07-release-engineering.md) | Phase 7 |
| 08 | [Capacity, resilience & chaos engineering](08-capacity-resilience-chaos.md) | Phases 5, 6 |
| 09 | [Simplicity, on-call health & SRE culture](09-culture-oncall.md) | Ongoing |

## Glossary

| Term | Meaning |
|---|---|
| **SLI** | Service Level Indicator. A measured ratio of good events to valid events. |
| **SLO** | Service Level Objective. The internal target for an SLI over a window. |
| **SLA** | Service Level Agreement. An external contract with consequences (e.g. refunds). |
| **Error budget** | 1 − SLO. The amount of unreliability you're allowed. |
| **Burn rate** | How fast the budget is being consumed, relative to using it up exactly at the end of the window (1x). |
| **MTTD / MTTA / MTTM / MTTR** | Mean time to detect / acknowledge / mitigate / resolve. |
| **IC** | Incident Commander. Coordinates the response; doesn't debug. |
| **Toil** | Manual, repetitive, automatable, reactive work with no lasting value. |
| **CUJ** | Critical User Journey. A user flow the business depends on. |
| **RED / USE** | Rate-Errors-Duration (services) / Utilization-Saturation-Errors (resources). |
| **Golden signals** | Latency, traffic, errors, saturation. |

## Further reading
- [Site Reliability Engineering](https://sre.google/sre-book/table-of-contents/) (the "SRE book")
- [The Site Reliability Workbook](https://sre.google/workbook/table-of-contents/)
- [Implementing Service Level Objectives](https://www.oreilly.com/library/view/implementing-service-level/9781492076803/) by Alex Hidalgo
