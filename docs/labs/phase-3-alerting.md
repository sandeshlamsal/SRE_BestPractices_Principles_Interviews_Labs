# Phase 3: Alerting and On-Call (Execution Guide)

> **Goal:** every alert that reaches a human is **symptom-based, actionable, routed to the right place, and linked to a runbook**.
> Pages go to PagerDuty + Slack `#pages`; tickets go to Slack `#alerts` ([ADR-0003](../adr/0003-paging-and-incident-tooling.md)).
> **Principles practiced:** [03 Monitoring & alerting](../principles/03-monitoring-alerting.md), [04 Incident management](../principles/04-incident-management.md), [09 On-call health](../principles/09-culture-oncall.md).
> **Status (2026-09-25):** alerts, runbooks, routing and **end-to-end delivery (via the in-cluster alert sink) done and tested**. Remaining: switch to real PagerDuty/Slack once `alerting-secrets` exists, then measure time to acknowledge on a phone.

---

## Before you start: keep the lab host awake

```bash
make awake        # own terminal; runs `caffeinate -i -m -s`. Ctrl-C to stop. Stay on AC power.
```
**If the Mac idle-sleeps, the Docker VM freezes** and everything stops at once: telemetry gaps, alerts that can't fire,
drills that silently fail. It caused every unexplained gap in Phases 1–2 ([P2-ISSUE-19](phase-2-observability.md#correction-a-wrong-root-cause-p2-issue-19)).
Check with `pmset -g assertions | grep PreventUserIdleSystemSleep`.

---

## Step 1: Audit what's already firing (noise first)

```bash
curl -s localhost:9090/api/v1/alerts | python3 -c "
import json,sys
for a in json.load(sys.stdin)['data']['alerts']:
  if a['state'] in('firing','pending'): print(a['state'], a['labels'].get('severity'), a['labels']['alertname'])" | sort | uniq -c
```

| Alert | Verdict | Action |
|---|---|---|
| `*BudgetBurn` (ticket) | Real: budget burned in Phase 2 / by drills | Keep |
| `NodeClockNotSynchronising` ×3 | **Noise**: kind nodes have no NTP; not actionable locally | Disabled via `defaultRules.disabled` (P3-ISSUE-1). **Re-enable on EKS** |
| `PrometheusMissingRuleEvaluations` ×19 (pending) | Leftover from stalls (host sleep); rule eval is only 0.25 s total now | Keep the rule. It correctly detected the stalls |
| `Watchdog` | Always firing by design: proves the alert pipeline works | Routed to `null` locally; to a **dead-man's switch** in production |

## Step 2: Alert rules (new, from lessons of Phases 1–2)

[observability/monitors/sre-lab-alerts.yaml](../../observability/monitors/sre-lab-alerts.yaml), applied with `make monitors`:

| Alert | Severity | Expression (summary) | Why it exists |
|---|---|---|---|
| `SLIDataMissing` | **page** | `count(slo:sli_error:ratio_rate5m) < 5` for 10m | P1-ISSUE-16: SLIs go **blank, not red**, so burn alerts can't fire |
| `TelemetryPipelineStale` | **page** | `time() - max(timestamp(traces_span_metrics_calls_total)) > 300` for 5m | The cause behind SLIDataMissing (and it inhibits it) |
| `OtelCollectorDown` | ticket | `up{job="observability/otel-collector"} == 0` | Uses the independent **pull** path (P2-ISSUE-5) |
| `OtelCollectorExportFailing` | ticket | failed metric points > 0 for 10m | P2-ISSUE-10 (400s from two writers) |
| `ContainerMemoryLimitThrashing` | ticket | `rate(container_memory_failcnt[5m]) > 10` for 10m | P2-ISSUE-15: tight limits cause **latency, not OOM** |

Plus the 10 Sloth SLO alerts (5 SLOs × page/ticket). Validate before applying:
```bash
python3 -c "import yaml;d=yaml.safe_load(open('observability/monitors/sre-lab-alerts.yaml'));yaml.safe_dump({'groups':d['spec']['groups']},open('/tmp/r.yaml','w'))"
docker run --rm -v /tmp:/r --entrypoint promtool prom/prometheus:v3.14.0 check rules /r/r.yaml     # SUCCESS: 5 rules found
kubectl apply --dry-run=server -f observability/monitors/sre-lab-alerts.yaml
```
Signal choice for thrashing (P3-ISSUE-4): `container_memory_failcnt` is cgroup v2 `memory.events: max` (**limit hits**).
Major page faults alone would be a **false positive** (load-generator: 31/s while far below its limit), and
`container_spec_memory_limit_bytes` doesn't exist here, so limits come from kube-state-metrics.

## Step 3: Runbooks for every alert

[runbooks/](../../runbooks/README.md): 9 runbooks + an index, each with *what it means → first 5 minutes → diagnose (real commands) → mitigate (in order) → verify*,
built from real incidents in Phases 1–2. SLO alerts now point to their own runbook (fixes P1-ISSUE-18).
```bash
make check-runbooks        # checked 15 alerts; OK: every alert has an existing runbook
```
The check fails if any alert lacks `severity: page|ticket` or a runbook, or links to a file that doesn't exist. **Phase 7 CI runs it on every PR.**

## Step 4: Routing (Alertmanager)

[observability/alerting/alertmanagerconfig.yaml](../../observability/alerting/alertmanagerconfig.yaml) (an `AlertmanagerConfig` CR used as the **global** config):

```
route (group_by: alertname, sloth_service, namespace)
├── Watchdog, InfoInhibitor          → null     (production: dead-man's switch)
├── severity=page  → PagerDuty  (continue) ─┐   group_wait 10s, repeat 1h
├── severity=page  → Slack #pages  ◄────────┘
├── severity=ticket|critical|warning → Slack #alerts   (kps "critical" = cause, not user symptom → ticket)
└── severity=info|none → null
inhibit:
  TelemetryPipelineStale ⟶ suppresses SLIDataMissing + all *BudgetBurn   (can't trust SLIs if the pipeline is down)
  page ⟶ suppresses the same SLO's ticket                                (equal: alertname, sloth_id)
  critical ⟶ suppresses warning                                         (kps default, kept)
```
Credentials come from Secret `observability/alerting-secrets` and are **never in Git**.
```bash
kubectl apply --dry-run=server -f observability/alerting/alertmanagerconfig.yaml      # validated against the CRD
```

### Unit-test the routing (no credentials needed)
```bash
make test-routing      # scripts/test-alert-routing.sh
```
The script **converts the real CR** into a plain `alertmanager.yml` with dummy secrets, runs `amtool check-config`,
then asserts the receivers for 11 alerts (`amtool config routes test`). Result: **11/11 PASS**:

| Alert | Receivers |
|---|---|
| SLO burn / SLIDataMissing / TelemetryPipelineStale, `severity=page` | `pagerduty, slack-pages` |
| SLO burn / thrashing, `severity=ticket`; kps `critical`/`warning` | `slack-alerts` |
| An alert **with no severity** | `slack-alerts` (a safe default, never dropped silently) |
| `Watchdog`, `InfoInhibitor`, `severity=info` | `null` |

Routing is code, so it gets tests. Run this in CI (Phase 7) so a routing change can't silently stop pages.

## Step 5: End-to-end delivery through an in-cluster alert sink

To test the **whole** path (SLI → burn rate → Alertmanager routing, grouping, inhibition → delivered notification)
without PagerDuty/Slack credentials, all receivers are pointed at [alert-sink](../../observability/alerting/alert-sink.yaml),
a 25-line Python webhook that logs every notification. The URL path is the receiver Alertmanager chose.

```bash
make alerting-sink        # generates alertmanagerconfig-sink.yaml from the REAL CR (same routes/inhibitions),
                          # deploys alert-sink, points Alertmanager at it
kubectl -n observability logs deploy/alert-sink -f      # watch notifications arrive
```
The switch lives in [kube-prometheus-stack values](../../observability/kube-prometheus-stack/values.yaml)
(`alertmanagerSpec.alertmanagerConfiguration.name: sre-lab-sink` → `sre-lab`), **not only** in a `kubectl patch`,
because the next `helm upgrade` would silently revert a patch (P3-ISSUE-8).

Check that Alertmanager loaded it:
```bash
kubectl -n observability get secret alertmanager-kps-alertmanager-generated -o jsonpath='{.data.alertmanager\.yaml\.gz}' \
  | base64 -d | gunzip | grep -E "url:|receiver:"
```
**First deliveries (18:22 UTC):** 4 tickets on `/slack-alerts`: three SLO budget burns left over from the drills, and
**`OtelCollectorExportFailing`**, where the new alert caught the residual P2-ISSUE-10 400s by itself.

### E2E page test (`paymentFailure` 50%)

| Time (UTC) | Event | Delivered to |
|---|---|---|
| 18:24:22 | `scripts/flag.sh set paymentFailure 50%` | |
| 18:27:41 | 🎫 ticket `CheckoutAvailabilityBudgetBurn` (slow-burn window crossed first) | `/slack-alerts` |
| **18:29:51** | 🚨 **page** `CheckoutAvailabilityBudgetBurn`, with the runbook URL in the payload | **`/pagerduty` + `/slack-pages`** (same second, so `continue: true` fan-out works) |
| 18:30:13 | Mitigation: `scripts/flag.sh reset` | |
| **18:39:51** | ✅ **RESOLVED** page (591 s after mitigation: the 30m/6h pair had to fall below 3%; a short 5.5-min incident clears faster than Phase 1's ~30 min) | `/pagerduty` + `/slack-pages` |

**Time from injection to page = 332 s** (SLI lag ~2.5 min + the 1h window needing > 7.2% errors).

**Inhibition, checked in Alertmanager's API:**
```bash
kubectl -n observability exec alertmanager-kps-alertmanager-0 -c alertmanager -- \
  wget -qO- 'http://localhost:9093/api/v2/alerts?active=true&inhibited=true' | python3 -c "
import json,sys
for a in json.load(sys.stdin): print(a['labels']['alertname'], a['labels'].get('severity'), a['status']['state'], len(a['status']['inhibitedBy']))"
```
| Alert | State |
|---|---|
| CheckoutAvailabilityBudgetBurn **ticket** | **suppressed** (inhibited by the checkout page) |
| CheckoutAvailabilityBudgetBurn page | active |
| Other SLOs' tickets | active (the `equal: [alertname, sloth_id]` scoping is correct) |

⚠️ The ticket was **delivered before** the page existed (18:27:41). Inhibition only suppresses notifications *while* the source
alert fires, so the ordering of windows matters (P3-ISSUE-9).

### ⏳ Pending: create the secret (you), then wire it up
1. Slack: workspace + channels `#pages`, `#alerts` → an app with **Incoming Webhooks** → one webhook per channel.
2. PagerDuty (free): service `astronomy-shop` → Integrations → **Events API V2** → copy the Integration Key.
3. Create the secret in your own terminal (not in chat, not in Git):
```bash
kubectl -n observability create secret generic alerting-secrets \
  --from-literal=pagerduty-routing-key='<PD integration key>' \
  --from-literal=slack-pages-webhook='<https://hooks.slack.com/...>' \
  --from-literal=slack-alerts-webhook='<https://hooks.slack.com/...>'
make alerting     # refuses to run until the secret exists
```

---

## Issues log

| ID | Area | Symptom | Root cause | Fix / decision |
|---|---|---|---|---|
| P3-ISSUE-1 | Noise | `NodeClockNotSynchronising` ×3 always firing | kind nodes have no NTP | `defaultRules.disabled` for kind; re-enable on EKS |
| **P3-ISSUE-2** | Lab host | Drill ran 25 min with no page; SLIs blinking out | **Mac idle sleep** froze the VM for 16 of the 25 minutes (= P2-ISSUE-19) | `make awake`; AC power. Drills must record whether the host stayed awake |
| P3-ISSUE-3 | Rules | 19× `PrometheusMissingRuleEvaluations` pending | Missed evaluations while the VM was frozen, not slow rules (0.25 s total) | Keep it: the alert correctly detected the stall |
| P3-ISSUE-4 | Signal choice | Candidate thrashing signals were misleading | Major faults false-positive (load-generator); `container_spec_memory_limit_bytes` missing | `container_memory_failcnt` (= limit hits) + kube-state-metrics limits |
| P3-ISSUE-5 | Detection | A partial failure (1 of 10 products, 8% errors) needs ~11 min to page | The page condition needs **both** 5m and 1h above 14.4 × 0.1%; the 1h average dilutes a new partial failure | By design (multi-window avoids flapping); record time to detect per scenario |
| P3-ISSUE-6 | Alerting | `SLIDataMissing` pending during the sleep gap | Real data loss (the VM was frozen) | **Worked as designed.** In real life a gap like that should page |
| P3-ISSUE-7 | Tooling | `$AM config routes test ...` → `no such file or directory: docker run ...` | zsh doesn't word-split `$VAR` (same as P2-ISSUE-13) | Put multi-word commands in bash scripts or functions: `scripts/test-alert-routing.sh` |
| P3-ISSUE-8 | Config drift | Pointing Alertmanager at a config with `kubectl patch` works, until the next `helm upgrade kps` silently reverts it | Helm owns the `Alertmanager` resource; manual patches are drift | Keep the choice in values (`alertmanagerConfiguration.name`). `make alerting` / `alerting-sink` patch *and* the values file records the intended state. GitOps (Phase 7) removes this class of problem |
| P3-ISSUE-9 | Inhibition | The checkout **ticket** reached #alerts 2 min *before* the page | The slow-burn ticket windows (3x over 1d+2h) crossed their threshold before the page's 1h window did. Inhibition can't un-send an earlier notification | Acceptable: one extra #alerts message. From the moment the page fires, the ticket is suppressed (verified in the API) |

---

## Phase 3 exit checklist

- [x] Noise audit; kind-only noise disabled
- [x] Alerts for every lesson of Phases 1–2 (blind SLIs, stale pipeline, collector, thrashing)
- [x] A runbook for every alert; `make check-runbooks` (15/15)
- [x] Routing as code with inhibitions; `make test-routing` (11/11)
- [x] **E2E:** injected failure → page delivered to PagerDuty + Slack receivers in 332 s → resolved 591 s after mitigation (alert sink)
- [x] Inhibition verified in the Alertmanager API
- [ ] Real PagerDuty + Slack (`alerting-secrets` → `make alerting`), then time a phone acknowledgement
- [ ] Production heartbeat: route `Watchdog` to a dead-man's switch (e.g. a healthchecks.io ping) so a dead Alertmanager or Prometheus pages someone

## Re-run Phase 3 from scratch
```bash
make monitors          # platform alert rules
make slo-rules         # SLO rules with runbook links
make check-runbooks && make test-routing
make alerting-sink     # e2e without credentials   (or: make alerting, once the secret exists)
kubectl -n observability logs deploy/alert-sink -f &
scripts/flag.sh set paymentFailure 50%    # expect a page in ~5-6 min on /pagerduty + /slack-pages
scripts/flag.sh reset                     # expect RESOLVED ~10 min later
```
