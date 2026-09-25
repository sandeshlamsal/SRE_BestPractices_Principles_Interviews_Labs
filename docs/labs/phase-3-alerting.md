# Phase 3: Alerting and On-Call (Execution Guide)

> **Goal:** every alert that reaches a human is **symptom-based, actionable, routed to the right place, and linked to a runbook**.
> Pages go to PagerDuty + Slack `#pages`; tickets go to Slack `#alerts` ([ADR-0003](../adr/0003-paging-and-incident-tooling.md)).
> **Principles practiced:** [03 Monitoring & alerting](../principles/03-monitoring-alerting.md), [04 Incident management](../principles/04-incident-management.md), [09 On-call health](../principles/09-culture-oncall.md).
> **Status (2026-09-25):** alerts, runbooks and routing config done; **waiting on the Slack/PagerDuty secret** to wire and test delivery end to end.

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
