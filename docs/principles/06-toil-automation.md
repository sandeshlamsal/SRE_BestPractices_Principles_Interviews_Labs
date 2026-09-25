# 06: Toil and Automation

> "If a human operator needs to touch your system during normal operations, you have a bug."

## What toil is
Google's definition: work that is **manual, repetitive, automatable, tactical (interrupt-driven),
without lasting value, and that grows linearly as the service grows**.

| Toil | Not toil |
|---|---|
| Manually restarting a pod that leaks memory every night | Fixing the memory leak |
| Hand-editing YAML to scale before a sale | Setting up an HPA |
| Silencing the same noisy alert every week | Deleting or fixing that alert |
| Copy-pasting an incident timeline from Slack | Writing a postmortem (useful overhead) |
| Clicking through a UI to deploy | Building the pipeline |

Meetings, planning, and postmortems are **overhead**, not toil. They're necessary even though they aren't engineering.

## The 50% rule
SREs should spend **at most 50%** of their time on toil and operational work. The rest goes
to **engineering that reduces future toil** or improves reliability. If toil goes over 50%,
the team is turning back into a traditional ops team.

## Measuring toil
- Track interrupts, tickets, and pages per week, grouped by category
- In each sprint, estimate the % of time spent on toil
- Rank what to automate by **frequency × time per occurrence × risk of error**

## Automation, in stages
1. No automation: a human does everything
2. A documented runbook
3. A script a human runs
4. Automation a human triggers (a ChatOps command, a pipeline button)
5. Automation that runs itself (controllers, operators, auto-remediation)
6. The system is designed so the task isn't needed at all (the best outcome)

Don't jump straight to stage 5 for something that happens twice a year. The **rule of three**: automate it the third time you do it.

## Mapped to the lab

| Toil you'll hit | Automation to build | Phase |
|---|---|---|
| Recreating the cluster and redeploying | `make` targets (already in place) → later Terraform + Argo CD | 0, 7, 8 |
| Port-forwarding to find dashboards | Ingress + stable URLs | 2 |
| Hand-writing PromQL for each SLO | Sloth SLO specs → generated rules | 1 |
| Restarting the leaking recommendation service | Memory limits + liveness probe, then fix the code | 5 |
| Picking and flipping flags for game days | A `scripts/gameday.sh` randomizer | 4 |
| Checking recent changes during incidents | A Grafana annotation for every deploy and flag change | 3 |

Keep a **toil log** at `docs/toil-log.md`: date, task, minutes spent, how often, and whether to automate.

## Interview questions
1. Define toil. Is on-call toil? Are postmortems?
2. Why cap toil at 50%?
3. How do you decide what to automate first?
4. Give an example of toil you eliminated and how you measured the impact.
