#!/usr/bin/env bash
# Unit-test Alertmanager routing WITHOUT real credentials.
# Converts observability/alerting/alertmanagerconfig.yaml (the CR we deploy) into a plain
# alertmanager.yml with DUMMY secrets, validates it, then asserts which receivers each alert reaches.
# Requires only Docker.  Usage: scripts/test-alert-routing.sh   (or: make test-routing)
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"; chmod 755 "$WORK"; trap 'rm -rf "$WORK"' EXIT
IMAGE="prom/alertmanager:v0.28.1"

python3 - observability/alerting/alertmanagerconfig.yaml "$WORK/alertmanager.yml" <<'PY'
import sys, yaml
cr = yaml.safe_load(open(sys.argv[1]))["spec"]
def matchers(ms):
    op = {"=": "=", "!=": "!=", "=~": "=~", "!~": "!~"}
    return [f'{m["name"]}{op[m.get("matchType", "=")]}"{m["value"]}"' for m in ms]
def route(r):
    out = {"receiver": r["receiver"]}
    if "matchers" in r: out["matchers"] = matchers(r["matchers"])
    if r.get("continue"): out["continue"] = True
    if "groupBy" in r: out["group_by"] = r["groupBy"]
    if "routes" in r: out["routes"] = [route(x) for x in r["routes"]]
    return out
receivers = []
for rc in cr["receivers"]:
    o = {"name": rc["name"]}
    if "pagerdutyConfigs" in rc: o["pagerduty_configs"] = [{"routing_key": "DUMMY"}]
    if "slackConfigs" in rc: o["slack_configs"] = [{"api_url": "https://hooks.slack.com/services/DUMMY"}]
    receivers.append(o)
inhibit = [{"source_matchers": matchers(i["sourceMatch"]), "target_matchers": matchers(i["targetMatch"]),
            **({"equal": i["equal"]} if "equal" in i else {})} for i in cr.get("inhibitRules", [])]
yaml.safe_dump({"route": route(cr["route"]), "receivers": receivers, "inhibit_rules": inhibit},
               open(sys.argv[2], "w"), sort_keys=False)
PY

amtool() { docker run --rm -v "$WORK:/c" --entrypoint amtool "$IMAGE" "$@"; }
amtool check-config /c/alertmanager.yml | grep -E "SUCCESS|FAILED"

fails=0
expect() {  # expect <receivers> <label=value>...
  local want="$1"; shift
  local got; got="$(amtool config routes test --config.file=/c/alertmanager.yml "$@" | tail -1)"
  if [ "$got" = "$want" ]; then printf "PASS  %-62s -> %s\n" "$*" "$got"
  else printf "FAIL  %-62s -> %s (expected %s)\n" "$*" "$got" "$want"; fails=$((fails+1)); fi
}
# Pages reach PagerDuty AND Slack #pages
expect "pagerduty,slack-pages" alertname=CheckoutAvailabilityBudgetBurn severity=page sloth_id=checkout-availability
expect "pagerduty,slack-pages" alertname=SLIDataMissing severity=page
expect "pagerduty,slack-pages" alertname=TelemetryPipelineStale severity=page
# Tickets and kube-prometheus-stack causes go to #alerts only (never wake anyone)
expect "slack-alerts" alertname=CheckoutAvailabilityBudgetBurn severity=ticket
expect "slack-alerts" alertname=ContainerMemoryLimitThrashing severity=ticket
expect "slack-alerts" alertname=KubeAPIDown severity=critical
expect "slack-alerts" alertname=KubePodCrashLooping severity=warning namespace=astronomy-shop
expect "slack-alerts" alertname=AlertWithNoSeverity
# Heartbeat and info are dropped
expect "null" alertname=Watchdog severity=none
expect "null" alertname=InfoInhibitor severity=none
expect "null" alertname=Something severity=info

[ "$fails" -eq 0 ] && echo "OK: all routing tests passed" || { echo "$fails routing test(s) FAILED"; exit 1; }
