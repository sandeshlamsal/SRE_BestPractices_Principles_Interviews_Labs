# ADR-0003: Paging and incident tooling

- **Status:** Accepted
- **Date:** 2026-09-25

## Context
Alerts have to reach a person, and incidents need somewhere to coordinate. We want the lab to
feel like a real on-call setup (acknowledgement, escalation, phone notifications) without paying for it.

## Decision
**Slack (free workspace) + PagerDuty (free plan)**, driven by Alertmanager.

| Signal | Route | Tool |
|---|---|---|
| `severity=page` | Alertmanager → **PagerDuty** (Events API v2) → phone push/SMS, acknowledge, escalation | PagerDuty free plan |
| `severity=page` (copy) | PagerDuty → Slack `#pages` | PagerDuty's Slack integration |
| `severity=ticket` | Alertmanager → Slack `#alerts` | Slack incoming webhook |
| Incident coordination | `#inc-YYYYMMDD-<slug>` channel per incident, plus `#status` | Slack |

PagerDuty setup:
- Service `astronomy-shop` with an Events API v2 integration key (kept in a Kubernetes Secret and never committed)
- Escalation policy: primary (you) → secondary (game master or a friend) after 10 min
- A schedule with a weekly rotation, even if it has only one person, so you practice handoffs

## Alternatives considered
- **Slack or Discord only**: simpler, but has no acknowledgement or escalation, so you miss practicing real on-call.
- **Grafana OnCall OSS**: now in maintenance mode, so it isn't worth learning for new setups.
- **Opsgenie**: Atlassian is winding it down, and existing users are being moved to Jira Service Management and Compass.

## Consequences
- MTTA (time to acknowledge) can be measured from PagerDuty's data, which feeds the metrics table in [incident-response-plan.md](../incident-response-plan.md#7-measuring-how-well-we-respond).
- The free plan's limits (small team, basic features) are fine for a lab. Check the current limits when you sign up.
