# SRE Principles in Practice: What the Lab Proved (Phases 0–3)

The [principles](principles/README.md) explain *what* SRE is. The [execution guides](labs/README.md) record
*what we ran*. This page connects the two: for each principle, **what we built, the evidence, and the lesson**,
with links to the real issues (`P2-ISSUE-15` = Phase 2, issue 15).

---

## 1. Embrace risk: 100% is the wrong target

**Principle:** pick the reliability users need; spend the rest on change. ([01](principles/01-sli-slo-sla.md))

**In the lab:** five SLOs, sized to the journey: checkout availability **99.5%**; browse and add-to-cart availability **99.9%**; checkout (< 1 s) and browse (< 400 ms) latency **99%**.
We chose them from a measured baseline and marked them **provisional**, because 27 minutes of data isn't a baseline ([P1-ISSUE-4](labs/phase-1-slos.md#issues-log)).

**Lesson:** an SLO is a *product decision backed by data*. We didn't promise what we hadn't measured.

---

## 2. Service Level Indicators: measure what users experience

**Principle:** SLI = good events ÷ valid events, measured as close to the user as possible. ([01](principles/01-sli-slo-sla.md))

**What we built:** [slos/*.yaml](../slos/) (Sloth) → 85 generated Prometheus rules, measured at the frontend's server spans.

**Evidence: every design detail came from a failure we found:**

| SLI rule | Why | Issue |
|---|---|---|
| Measure at the frontend, not Envoy | Envoy spans have no route, so journeys can't be told apart | P1-ISSUE-1 |
| Latency thresholds on histogram buckets (400 ms, not 300 ms) | A threshold between buckets silently measures the wrong thing | P1-ISSUE-2 |
| `http_response_status_code!=""` | The frontend emits **two** server spans per request, doubling counts | P1-ISSUE-3 |
| `or vector(0)` on error queries | With zero errors the series doesn't exist, so the SLI goes **empty**, not 0 | P1-ISSUE-5 |
| **Classify by HTTP status (5xx + 422)**, not span status | **A 50% checkout outage was invisible**: failed orders return 422, and OTel only marks 5xx server spans as errors | **P1-ISSUE-11** |
| Include `/api/recommendations` in browse | A drill showed it was the **largest** error source, with no SLO covering it | P2-ISSUE-21 |

**Lesson, the most important one in the lab:** *an SLI you haven't tested with an injected failure is a hypothesis, not a measurement.*

---

## 3. Error budgets: a shared number for the speed-vs-stability decision

**Principle:** budget = 1 − SLO; burn rate says how fast it's being spent; a policy says what to do. ([02](principles/02-error-budgets.md), [policy](sre-way.md#2-error-budget-policy))

**What we built:** an error-budget dashboard ([slo-overview.json](../observability/dashboards/slo-overview.json)) with the budget-policy tier shown **as text**, not colour alone.

**Evidence:**
- The `paymentFailure` 50% test ran at an **80–116x** burn, against a predicted ~100x ([Phase 1 §7](labs/phase-1-slos.md#7-the-experiment-inject-a-failure-and-watch-the-budget-burn)).
- The budget showed **−618%** after 8 minutes. With only ~30 minutes of history, the "30-day" window meant "since start-up" (P1-ISSUE-12).
- **Migrations spend budget:** the Phase 2 platform cutover burned browse-latency budget (P2-ISSUE-11).

**Lesson:** budget numbers are only meaningful once the window is full. Planned work belongs in the budget conversation *before* it happens.

---

## 4. Monitoring distributed systems: symptoms, golden signals, and the monitoring's own health

**Principle:** RED for services, USE for resources; page on symptoms; observability links the signals together. ([03](principles/03-monitoring-alerting.md))

**What we built (Phase 2):**
- kube-prometheus-stack + Tempo + Loki on **persistent storage**
- Cross-signal links: exemplars → traces → logs → traces, plus a service graph (27 edges)
- RED, USE and SLO dashboards, all **as code**

**Evidence:**
- **Exit drill:** alert → RED → trace (`Product Catalog Fail Feature Flag Enabled`) → log line in **under 2 minutes** ([Phase 2 Step 7](labs/phase-2-observability.md#step-7-exit-drill-alert--dashboard--trace--log)).
- **Monitor the monitoring:** the collector's self-metrics are *pulled* independently of its own pipeline (P2-ISSUE-5). The pipeline-health dashboard **caught real data loss on its first render** (P2-ISSUE-10).
- Telemetry that looks right can be wrong. **Two collectors wrote the same series** (24 samples/2 min instead of 12), silently corrupting counters (P2-ISSUE-10).

**Lesson:** when telemetry stops, dashboards go **blank, not red**. Losing sight is a failure mode in its own right, so it gets its own alert.

---

## 5. Alerting: every page urgent, actionable, and documented

**Principle:** page on user-facing symptoms via multi-window burn rates; causes become tickets; every alert has a runbook. ([03](principles/03-monitoring-alerting.md), [ADR-0003](adr/0003-paging-and-incident-tooling.md))

**What we built (Phase 3):**
- 15 alerts. **Pages:** 5 SLO burns, `SLIDataMissing`, `TelemetryPipelineStale`. **Tickets:** 5 slow burns, collector down, collector export failing, memory thrashing.
- [Runbooks](../runbooks/README.md) built from real incidents.
- Routing as code ([AlertmanagerConfig](../observability/alerting/alertmanagerconfig.yaml)), with credentials only in a Kubernetes Secret.

**Evidence:**
- **Noise removed first:** clock alerts that always fire on kind were turned off (P3-ISSUE-1).
- **Alerting is tested like code:** `make check-runbooks` (15/15), `make test-routing` (11/11 routing assertions).
- **End to end, through the in-cluster alert sink:** injected failure → **page to PagerDuty + Slack receivers in 332 s** → **resolved 591 s** after mitigation. The same SLO's ticket was **suppressed by inhibition**, verified in Alertmanager's API ([Phase 3 Step 5](labs/phase-3-alerting.md#step-5-end-to-end-delivery-through-an-in-cluster-alert-sink)).
- **Detection time depends on the failure shape:** a partial failure (1 of 10 products) takes ~11 minutes by design (P3-ISSUE-5).
- **Why pages keep firing after a fix:** the 30m/6h window pair is anti-flapping behaviour, not a bug (P1-ISSUE-14).

**Lesson:** an alert that has never fired is unverified. Routing, inhibition and runbook links all need tests.

---

## 6. Eliminating toil: automate what you'd repeat

**Principle:** keep toil under 50%; automate the third time. ([06](principles/06-toil-automation.md))

**Toil we removed:**

| Toil | Automation |
|---|---|
| Rebuilding the lab | `make cluster-up obs-up deploy slo-rules monitors dashboards` |
| Writing PromQL for each SLO | Sloth spec → `make slo-rules` (generate, `promtool` check, apply) |
| Clicking through the flag UI | [scripts/flag.sh](../scripts/flag.sh): list, set, reset, handles targeted flags, UTC timestamps for timelines |
| Checking alert hygiene by hand | `make check-runbooks`, `make test-routing` |
| Testing delivery with real accounts | `make alerting-sink`, generated from the real config |

**Lesson:** our own automation has bugs too. `flag.sh` once reported success while changing nothing (P2-ISSUE-18), and a stale drill process interfered with a live experiment (P2-ISSUE-20). Test the tooling and **verify cleanup**.

---

## 7. Release engineering and change management

**Principle:** everything in Git; reproducible; small, safe changes. ([07](principles/07-release-engineering.md))

**Evidence:**
- **Everything is pinned:** chart 0.42.0, node image v1.35.0, kps 91.5.2, Tempo 3.0.0, Loki 18.13.5 (ISSUE-4, P2-ISSUE-1).
- **Read before you install:** `helm template` + `helm show values` before every change. That's how the AI components needing an external LLM were found (ISSUE-3).
- **Drift is real:** a `kubectl patch` gets reverted by the next `helm upgrade`, so the intended state lives in values files (P3-ISSUE-8). Phase 7 (GitOps) removes this class of problem.
- **Changes cost budget:** the observability cutover measurably burned the latency SLO (P2-ISSUE-11).

---

## 8. Capacity and resilience

**Principle:** size from measured demand; know your failure modes. ([08](principles/08-capacity-resilience-chaos.md))

**Evidence:**
- **Tight limits show up as latency, not crashes:** product-catalog hit its 20 MiB limit **644,293 times** (1.86M major page faults) with **zero OOM kills and zero restarts**. It was fixed from a cgroup sweep of every container, and is now detected by `ContainerMemoryLimitThrashing` (P2-ISSUE-15).
- **Readiness:** 22 of 25 deployments have no readiness probe, which caused start-up errors (ISSUE-6). Scheduled for Phase 5.
- **Single-replica fragility:** after a pause, Loki evicted *itself* from its ring and dropped all logs until restarted (P2-ISSUE-22).
- **The host is a dependency:** Docker was sized from measurement (16 → 12 GB, P2-ISSUE-14).

---

## 9. Simplicity, and honesty in analysis

**Principle:** complexity is the enemy of reliability; blameless learning needs accurate facts. ([09](principles/09-culture-oncall.md), [05](principles/05-postmortems.md))

**The most important process lesson (P2-ISSUE-19):** in Phase 2 we concluded that memory thrashing caused the telemetry gaps.
**That was wrong.** The real cause was the **Mac idle-sleeping** and freezing the Docker VM. `pmset -g log` matched every gap to the minute.
We had found a *real* problem at the same time as the symptoms and built a plausible story connecting them.

**We corrected it in the open** ([the correction](labs/phase-2-observability.md#correction-a-wrong-root-cause-p2-issue-19)):
the thrashing stays fixed (the kernel counters prove it), and the before/after numbers confounded by sleep are marked.
The same honesty applies to "fixed" claims: P2-ISSUE-10 was re-opened when the evidence didn't hold.

**Lessons:** (1) correlation plus a good story isn't proof; check timestamps at every layer, down to the host.
(2) When **every** process on **every** node stops at once with **no errors**, suspect a paused machine, not a slow service.
(3) A postmortem or guide that hides a wrong turn teaches less than one that shows it.

---

## Principle coverage so far

| Principle | Status | Where |
|---|---|---|
| SLIs / SLOs / error budgets | ✅ practiced, tested with injected failures | Phase 1 |
| Monitoring & observability | ✅ platform + cross-signal links + self-monitoring | Phase 2 |
| Alerting & on-call routing | ✅ end to end via alert sink; ⏳ real PagerDuty/Slack | Phase 3 |
| Toil & automation | ✅ ongoing | all phases |
| Incident management & postmortems | ⏭️ next | Phase 4 |
| Chaos & resilience | partial (thrashing, readiness, Loki ring found) | Phase 5 |
| Capacity | partial (sized from measurement) | Phase 6 |
| Release engineering / GitOps | partial (pinning, drift) | Phase 7 |
| IaC / cloud / DR | not yet | Phases 8–9 |
