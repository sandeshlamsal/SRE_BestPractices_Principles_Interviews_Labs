# Lab Execution Guides

Each guide records **exactly what was run**: commands, real outputs, and every issue hit, with its root cause and fix.
You can rebuild any phase from its guide alone. How the phases map to SRE principles: [sre-in-practice.md](../sre-in-practice.md).

| Phase | Guide | Status | Headline result | Issues logged |
|---|---|---|---|---|
| 0 | [Foundation](phase-0-foundation.md) | ✅ | Shop on a 3-node kind cluster; one checkout traced across 8 services + 2 stores | 6 |
| 1 | [SLIs, SLOs, error budgets](phase-1-slos.md) | ✅ | 5 SLOs as code; **found an SLI blind to a 50% outage (422s)** and fixed it; page in ~4 min | 18 |
| 2 | [Observability platform](phase-2-observability.md) | ✅ | kps + Tempo + Loki, cross-signal links, pipeline self-monitoring; alert → trace → log < 2 min; **root-cause correction (host sleep)** | 22 |
| 3 | [Alerting & on-call](phase-3-alerting.md) | ✅ (real PagerDuty/Slack pending) | 15 alerts, 9 runbooks, routing tests 11/11; e2e page 332 s, resolved 591 s | 9 |
| 4 | [Incident response game days](phase-4-incident-response.md) | 🔄 in progress | GD1 found **orders charged with the cart not cleared, no alert**; new correctness SLO | 5 |

## Conventions
- Issue IDs: `ISSUE-n` (Phase 0), `P1-ISSUE-n`, `P2-ISSUE-n`, … Each has symptom, root cause, fix, and how it was verified.
- Times are **UTC** (the host's local time is CDT = UTC−5; that matters when matching `pmset` logs).
- Before any long-running test: `make awake` (host sleep freezes the cluster, see P2-ISSUE-19).
