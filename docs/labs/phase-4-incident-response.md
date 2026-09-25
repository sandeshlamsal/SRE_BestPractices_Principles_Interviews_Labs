# Phase 4: Incident Response Game Days (Execution Guide)

> **Goal:** practice the full incident lifecycle (detect → declare → roles → mitigate → verify → postmortem) on
> realistic, repeatable failures, and let each game day improve the system.
> **Principles practiced:** [04 Incident management](../principles/04-incident-management.md), [05 Postmortems](../principles/05-postmortems.md), [01 SLIs](../principles/01-sli-slo-sla.md).
> **Status (2026-09-25):** tooling done; **Game Day 1 done** (and it found a silent correctness failure); blind game days next.

## Tooling

| Artifact | Purpose |
|---|---|
| [scripts/gameday.sh](../../scripts/gameday.sh) | Game master: `start` (random scenario + random 1–8 min delay, **answer sealed** in git-ignored `incidents/.gameday/`), `status`, `end` (reset + **reveal** + impact duration) |
| [docs/templates/incident.md](../templates/incident.md) | Live incident doc (roles, UTC timeline, status updates) |
| [postmortems/README.md](../../postmortems/README.md) | Index with MTTD / MTTA / MTTM / budget / open actions, so trends show up across game days |
| [oncall/handoff-log.md](../../oncall/handoff-log.md) | Per-shift handoff: pages, noise, open issues |

```bash
scripts/gameday.sh list          # 13 scenarios; names only, no spoilers
scripts/gameday.sh start         # BLIND: random scenario, random start time
scripts/gameday.sh status
scripts/gameday.sh end           # when you believe you've mitigated: reveals what it was and when it started
```
Scenarios include deliberate **coverage-gap tests** (images, ads, Kafka) that no SLO is expected to catch. If nothing
pages, is that acceptable for users? That's part of the answer.

## Pre-flight checklist (do this before every game day)
```bash
pmset -g assertions | grep -c "caffeinate asserting"   # > 0  (make awake), and on AC power
pgrep -fl "drill|gameday|e2e" || echo clean              # no stray automation (P2-ISSUE-20)
scripts/flag.sh list | grep -v " off" || echo "all off"  # clean baseline
curl -s localhost:9090/-/ready; curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/   # port-forwards alive (P2-ISSUE-7)
```
Game Day 1's pre-flight caught a **dead Prometheus port-forward** and **`caffeinate` about to expire**.

## Game Day 1: `cart-failure` (worked example, not blind)
Full record: [incident](../../incidents/2026-09-25-gd1-cart-not-cleared.md) · **[postmortem](../../postmortems/2026-09-25-gd1-cart-not-cleared.md)**

| | |
|---|---|
| Injected | `cartFailure` 50% at 21:04:00Z |
| Expected (catalog) | "add-to-cart fails" → `cart-availability` pages |
| **Actual** | `AddItem` fine; **`EmptyCart` failed 46%** after payment; checkout still **200**; **no alert for 10+ min** |
| Impact | **17 of 37 orders** charged with the cart not cleared (duplicate-order risk) |
| Detected by | the game-day team investigating why the expected page **didn't** come |
| Fix | new **correctness SLO** `checkout-order-integrity` (99.9%) + runbook; the page reaches both routes |

**Lessons:**
1. Availability and latency SLIs can't see *"succeeded but did the wrong thing"*. You need **correctness SLIs** for key invariants.
2. **"No alert" in a game day is a result to explain, not a pass.**
3. Our own scenario catalog was wrong about what the flag does. Verify expectations against traces.
4. Verifying a fix right after an incident is **confounded by the incident's own data in the SLO windows**. Re-test once the windows are clear.

## Issues log
| ID | Area | Symptom | Root cause | Fix / decision |
|---|---|---|---|---|
| P4-ISSUE-1 | SLI coverage | 46% of orders charged with a stale cart; every SLI at 100% | No correctness SLI; checkout swallows the EmptyCart failure | `checkout-order-integrity` SLO + runbook (postmortem AI-1) |
| P4-ISSUE-2 | Alerting | `SLIDataMissing` would never fire once a 6th SLO existed | Hard-coded `count(...) < 5` | `count(slo:objective:ratio) - count(slo:sli_error:ratio_rate5m) > 0` (self-maintaining) |
| P4-ISSUE-3 | Game-day design | The scenario catalog predicted the wrong symptom and SLO | Assumed from the flag's name/description | Catalog corrected; verify every scenario against traces the first time it runs |
| P4-ISSUE-4 | Verification | The new SLO paged "5 s after re-injection" | The 5m/1h windows still held the first incident's errors | Report as "SLI detects it"; clean time to detect needs a re-run after ≥ 1 h (AI-4) |
| P4-ISSUE-5 | Pre-flight | Dead `:9090` port-forward; `caffeinate` expiring mid-drill | The Prometheus pod restarted earlier; the 4 h `-t` limit | The pre-flight checklist above |

## Next
- **Blind game days** (you): `scripts/gameday.sh start`, respond from alerts and runbooks only, write the postmortem from the template, add a row to the index.
- Open action items from GD1: clean time-to-detect re-run (AI-4), audit swallowed failures in `PlaceOrder` (AI-6: email, Kafka publish).
