# 09: Simplicity, On-Call Health and SRE Culture

## What SRE is
> "SRE is what happens when you ask a software engineer to design an operations team." (Ben Treynor Sloss, Google)

SRE treats **operations as a software problem**. `class SRE implements DevOps`: DevOps
describes the culture, and SRE is one concrete way to practice it, with SLOs, error budgets,
toil caps, and blameless postmortems.

### The core principles, in one place
1. **Embrace risk**: target the reliability users need, not 100%. → [01](01-sli-slo-sla.md), [02](02-error-budgets.md)
2. **Service level objectives**: measure what users experience. → [01](01-sli-slo-sla.md)
3. **Eliminate toil**: cap it at 50% and engineer it away. → [06](06-toil-automation.md)
4. **Monitor distributed systems**: symptoms, golden signals, actionable alerts. → [03](03-monitoring-alerting.md)
5. **Automation**: prefer systems that fix themselves over heroics. → [06](06-toil-automation.md)
6. **Release engineering**: small, safe, automated, reversible changes. → [07](07-release-engineering.md)
7. **Simplicity**: complexity is the enemy of reliability. (below)
8. **Incident response and learning**: structured response, blameless postmortems. → [04](04-incident-management.md), [05](05-postmortems.md)

## Simplicity
- Every line of code and every component is a liability that has to be kept running.
- Prefer boring, well-understood technology. Add a new component only when it removes more complexity than it adds.
- Delete dead code, unused flags, unused alerts, and unused dashboards.
- **In the lab:** Phase 2 replaces the bundled stack only if the replacement is clearly better. Write an ADR for every tool you add (Chaos Mesh vs Litmus, Tempo vs Jaeger, Sloth vs Pyrra).

## Healthy on-call
| Practice | Why |
|---|---|
| Rotations of at least 6–8 people (or follow-the-sun) | Avoid burnout |
| ≤ 2 incidents per 12h shift on average | More than that means you can't do follow-up properly |
| Every page is actionable | Pages that need no action wear people down |
| Primary + secondary on-call | A backup and escalation path |
| Handoff notes at shift change | Continuity |
| Compensation or time off after hard shifts | Keeps the rotation sustainable |
| On-call review each week | Turn pain into backlog items |

**In the lab:** keep `oncall/handoff-log.md`. After each game-day "shift", write what fired, what was noise, and what to fix.

## Working with product and development
- SLOs are **agreed with product**. Reliability is a product feature with a cost.
- Error budgets make decisions **based on data** instead of on who argues hardest.
- SREs can **hand back the pager** for services that stay out of SLO and ignore the budget policy.
- Production Readiness Reviews (PRRs) happen before SRE takes on a service: SLOs, dashboards, alerts, runbooks, capacity, rollback.

## Production Readiness Review checklist (use it on the Astronomy Shop)
- [ ] SLOs defined for each CUJ, with a dashboard
- [ ] Burn-rate alerts with runbooks
- [ ] RED dashboards for every service
- [ ] Resource limits, probes, PDBs, HPAs
- [ ] Rollback tested (canary + automatic rollback)
- [ ] Capacity known (load-tested), N-1 headroom
- [ ] Dependencies mapped, with a known failure mode for each
- [ ] Game days run for the top failure scenarios
- [ ] Postmortem process in place

Completing this checklist is the **"graduation" goal of the whole roadmap**.

## Interview questions
1. What is SRE, and how does it differ from DevOps and traditional ops?
2. What makes on-call sustainable?
3. How do you convince a product team to invest in reliability?
4. What's in a production readiness review?
5. Tell me about a time you simplified a system to make it more reliable.
