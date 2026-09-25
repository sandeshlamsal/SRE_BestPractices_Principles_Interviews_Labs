# Postmortems

Blameless reviews of every SEV1/SEV2, every page that burned > 10% of a budget, every game day, and every chaos surprise.
Template: [docs/templates/postmortem.md](../docs/templates/postmortem.md). Process: [principles/05](../docs/principles/05-postmortems.md).

## Index and response metrics

Times are measured from **impact start** (for game days, `injected_at` from `scripts/gameday.sh end`).
MTTD = until the first alert or human notice; MTTA = alert → acknowledged; MTTM = until users are no longer affected.

| Date | Postmortem | Type | Sev | MTTD | MTTA | MTTM | Budget used | Action items open |
|---|---|---|---|---|---|---|---|---|
| 2026-09-25 | [GD1: orders charged, cart not cleared](2026-09-25-gd1-cart-not-cleared.md) | game day (not blind) | SEV2 | 10m21s (human; **monitoring: never**) | n/a | 10m52s | none (no SLO covered it) | 2 of 6 (AI-4 deferred, AI-5 app team) |

Targets ([incident-response-plan §7](../docs/incident-response-plan.md#7-measuring-how-well-we-respond)): **MTTD < 5 min**, **MTTM < 15 min**, **0 action items older than 30 days**.
