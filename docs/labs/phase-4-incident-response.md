# Phase 4: Incident Response Game Days (Execution Guide)

> **Goal:** practice the full incident lifecycle (detect → declare → roles → mitigate → verify → postmortem) on
> realistic, repeatable failures, and let each game day improve the system.
> **Principles practiced:** [04 Incident management](../principles/04-incident-management.md), [05 Postmortems](../principles/05-postmortems.md), [01 SLIs](../principles/01-sli-slo-sla.md).
> **Status (2026-09-25):** tooling done; **Game Day 1 done** (a silent correctness failure); **swallowed-failure audit done** (email loss invisible; **~13 orders lost in Kafka with healthy-looking telemetry**); blind game days next.

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
| Fix | new **correctness SLO** `checkout-order-integrity` (99.9%) + runbook; **clean re-test: page in 103 s** (was: never) |

**Lessons:**
1. Availability and latency SLIs can't see *"succeeded but did the wrong thing"*. You need **correctness SLIs** for key invariants.
2. **"No alert" in a game day is a result to explain, not a pass.**
3. Our own scenario catalog was wrong about what the flag does. Verify expectations against traces.
4. Verifying a fix right after an incident is **confounded by the incident's own data in the SLO windows**. Re-test once the windows are clear.

## Audit: failures that PlaceOrder swallows (GD1 action item 6)

**Step 1, passive (TraceQL over 6 h):** find successful `PlaceOrder` spans with error descendants.
```bash
# Structural operators (>>, >) returned 0 even for known positives in this Tempo version (P4-ISSUE-6).
# Working pattern: spanset AND (same trace), then walk the tree to keep only true descendants.
{resource.service.name="checkout" && name="oteldemo.CheckoutService/PlaceOrder" && status!=error} && {status=error}
```
Result: only GD1's `EmptyCart` (16 traces). **But you can't audit a failure mode that hasn't happened yet**: email and
Kafka had simply never failed. So:

**Step 2, active experiments (3 min each, hypothesis first):**

| Experiment | Hypothesis | Result |
|---|---|---|
| `kubectl scale deploy/email --replicas=0` (22:01–22:04) | Orders still succeed; emails silently lost; no SLO notices | ✅ Confirmed: 4× HTTP 200, 4 email calls ERROR, **every availability SLI = 0**. Only side effect: checkout-latency 7.1% (waiting on the dead dependency). A fast-failing dependency wouldn't even show that |
| `kubectl scale deploy/kafka --replicas=0` (22:05–22:08) | Orders succeed; accounting/fraud never receive them; nothing alerts | ✅ **Worse than expected** (below) |

**Kafka findings:**
1. The checkout **`publish orders` PRODUCER span said OK 4/4 while Kafka was down**. Async send = *queued*, not *delivered*: **the telemetry lies**.
2. Checkout published **77** orders in 30 min, accounting and fraud-detection processed **66**: **11 lost** (the outage plus the in-memory broker's backlog wiped on restart).
3. After Kafka returned, the consumers took ~3 min to re-join. Published vs processed since the restore stayed at a **constant gap of 9** (18/9 → 26/17): the orders published before re-subscription were **permanently skipped** (the `auto.offset.reset=latest`-on-a-recreated-topic trap), not delivered late.
4. **Consumer lag stayed 0** the whole time, because the topic and offsets reset. *Lag 0 can mean "caught up" or "the data was deleted".*
5. Pods: all `Running`, 0 restarts. **Health checks saw nothing.**

**Fix: an end-to-end completeness SLO** ([slos/order-pipeline.yaml](../../slos/order-pipeline.yaml), [runbook](../../runbooks/order-pipeline-completeness.md)):
error = `clamp_min(published − processed, 0)` ÷ published. It caught the loss **immediately** (5m error 84.6%), and it's how the
skipped-orders gap was proven. At 99% it only raised a **ticket** (1h error 9.8% < 14.4% page threshold). Measured steady-state
noise was 0.0, so it was tightened to **99.9%**, and it **pages**.

## Issues log
| ID | Area | Symptom | Root cause | Fix / decision |
|---|---|---|---|---|
| P4-ISSUE-1 | SLI coverage | 46% of orders charged with a stale cart; every SLI at 100% | No correctness SLI; checkout swallows the EmptyCart failure | `checkout-order-integrity` SLO + runbook (postmortem AI-1) |
| P4-ISSUE-2 | Alerting | `SLIDataMissing` would never fire once a 6th SLO existed | Hard-coded `count(...) < 5` | `count(slo:objective:ratio) - count(slo:sli_error:ratio_rate5m) > 0` (self-maintaining) |
| P4-ISSUE-3 | Game-day design | The scenario catalog predicted the wrong symptom and SLO | Assumed from the flag's name/description | Catalog corrected; verify every scenario against traces the first time it runs |
| P4-ISSUE-4 | Verification | The new SLO paged "5 s after re-injection" | The 5m/1h windows still held the first incident's errors | Report as "SLI detects it"; clean time to detect needs a re-run after ≥ 1 h (AI-4) |
| P4-ISSUE-5 | Pre-flight | Dead `:9090` port-forward; `caffeinate` expiring mid-drill | The Prometheus pod restarted earlier; the 4 h `-t` limit | The pre-flight checklist above |
| P4-ISSUE-6 | Tooling | TraceQL `>>` / `>` returned **0 for a known positive** (GD1 window: 16 expected) | Structural operators don't work as expected in this Tempo 3.0 setup | Validate every detection query against a known positive. Use spanset AND + a manual tree walk |
| P4-ISSUE-7 | Coverage | Email down 3 min: 4 orders, 4 confirmations lost, no SLO noticed | email is best-effort in PlaceOrder; no delivery SLI | **Open:** email-delivery SLI needs the checkout→email client span, but all outbound HTTP spans are named just `POST` (can't tell email from shipping) → add a `server.address`/`url.path` span-metrics dimension |
| **P4-ISSUE-8** | **Data loss** | Kafka down 3 min: **~13 orders never processed** (4 during the outage + 9 skipped at re-subscribe); producer span OK; lag 0; pods healthy | Async producer (queued ≠ delivered), in-memory broker (restart wipes the topic), consumers re-join at `latest` | End-to-end **completeness SLO** (99.9%, pages). **Backlog:** Kafka persistence (PVC) + `acks=all`, producer delivery callbacks that mark spans ERROR, consumer `auto.offset.reset=earliest` + idempotent processing |
| P4-ISSUE-9 | SLO tuning | Completeness at 99% → 13 lost orders = ticket only | Objective chosen from *fear* of noise, not data | Measured noise (0.0) → 99.9% → pages. **Set objectives from measurements, and by the cost of the failure** (lost money ≠ slow page) |
| P4-ISSUE-10 | Verification | GD1 AI-4 (clean time-to-detect) couldn't be measured right after the incident | The 6h page window held GD1's errors | Waited until **every** window read exactly 0.0 (03:14:56Z), then re-ran: **clean time-to-page = 103 s** (before the fix: never). Rule: *don't publish a confounded number; wait for clean windows* |

## Next
- **Blind game days** (you): `scripts/gameday.sh start`, respond from alerts and runbooks only, write the postmortem from the template, add a row to the index.
- Email-delivery SLI (P4-ISSUE-7). Kafka durability (P4-ISSUE-8, scheduled for Phase 5). Blind game days.
