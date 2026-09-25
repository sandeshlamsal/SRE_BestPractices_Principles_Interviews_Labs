#!/usr/bin/env bash
# Verify every alert that can reach a human has a runbook, and that it exists in runbooks/.
# Checks: observability/monitors/*.yaml (PrometheusRules) and the generated SLO rules.
# Exit 1 on any problem, so CI (Phase 7) can gate merges on it.   Usage: make check-runbooks
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import glob, os, sys, yaml
PREFIX = "https://github.com/sandeshlamsal/SRE_BestPractices_Principles_Interviews_Labs/blob/main/"
files = glob.glob("observability/monitors/*.yaml") + ["observability/prometheus/slo-prometheusrules.yaml"]
problems, checked = [], 0
for f in files:
    for doc in yaml.safe_load_all(open(f)):
        if not doc or doc.get("kind") != "PrometheusRule": continue
        for g in doc["spec"]["groups"]:
            for r in g["rules"]:
                if "alert" not in r: continue
                checked += 1
                sev = r.get("labels", {}).get("severity")
                rb = r.get("annotations", {}).get("runbook", "")
                where = f"{f}: {r['alert']} ({sev})"
                if sev not in ("page", "ticket"):
                    problems.append(f"{where}: severity must be page|ticket")
                if not rb:
                    problems.append(f"{where}: missing runbook annotation"); continue
                path = rb.replace(PREFIX, "") if rb.startswith(PREFIX) else rb
                if not os.path.isfile(path):
                    problems.append(f"{where}: runbook not found: {path}")
print(f"checked {checked} alerts")
for p in problems: print("  FAIL", p)
sys.exit(1 if problems else 0)
PY
echo "OK: every alert has an existing runbook"
