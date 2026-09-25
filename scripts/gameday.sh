#!/usr/bin/env bash
# Game master for incident-response game days (Phase 4).
# Secretly picks a failure scenario and a random start time, injects it via flagd, and SEALS the
# answer (scenario + exact inject time) until you reveal it. Respond using only alerts, dashboards,
# traces, logs and runbooks, just like a real on-call.
#
#   scripts/gameday.sh list                     # scenario catalog (names only; no spoilers)
#   scripts/gameday.sh start                    # random scenario, starts within 1-8 min
#   scripts/gameday.sh start cart-failure       # a specific scenario (worked examples)
#   scripts/gameday.sh status                   # is a game running? (no spoilers)
#   scripts/gameday.sh end                      # mitigation check: resets ALL flags, reveals the answer + timings
#
# Sealed state: incidents/.gameday/current.json (git-ignored). Needs `make open` (flag API) and `make awake`.
set -euo pipefail
cd "$(dirname "$0")/.."
STATE_DIR="incidents/.gameday"; STATE="$STATE_DIR/current.json"; mkdir -p "$STATE_DIR"

# name | flag | variant | what users would notice | SLO expected to catch it ("none" = coverage gap test)
CATALOG='
payment-failure|paymentFailure|50%|half of orders fail|checkout-availability
payment-unreachable|paymentUnreachable|on|all orders fail|checkout-availability
cart-failure|cartFailure|50%|orders charged but cart NOT cleared (EmptyCart fails; checkout still 200)|checkout-order-integrity (added after GD1)
product-failure|productCatalogFailure|on|one product page and recommendations error|browse-availability
catalog-lock|productCatalogLockContention|on|catalog slow under DB lock contention|browse-latency / checkout-latency
shipping-slow|intlShippingSlowdown|5sec|international checkouts slow|checkout-latency
recs-cache|recommendationCacheFailure|on|recommendation service leaks memory|browse-latency (eventually)
email-leak|emailMemoryLeak|1000x|email service memory grows|ContainerMemoryLimitThrashing / checkout-latency
readiness|failedReadinessProbe|on|cart pods fail readiness|cart-availability
image-slow|imageSlowLoad|5sec|product images load slowly|none (images not in any SLI)
ad-cpu|adHighCpu|on|ad service burns CPU|none (ads not in any SLI)
kafka|kafkaQueueProblems|on|order processing backlog (async)|none (no freshness SLI yet)
flood|loadGeneratorFloodHomepage|on|homepage traffic flood|browse-latency (maybe)
'
line_for() { echo "$CATALOG" | grep -E "^$1\|" || { echo "unknown scenario: $1" >&2; exit 1; }; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

case "${1:-}" in
  list)
    echo "$CATALOG" | awk -F'|' 'NF{print "  " $1}'
    ;;
  start)
    [ -f "$STATE" ] && { echo "A game is already running (scripts/gameday.sh end first)"; exit 1; }
    if [ -n "${2:-}" ]; then line=$(line_for "$2"); delay=0
    else line=$(echo "$CATALOG" | awk 'NF' | awk 'BEGIN{srand()} {a[NR]=$0} END{print a[int(rand()*NR)+1]}'); delay=$(( (RANDOM % 420) + 60 )); fi
    IFS='|' read -r name flag variant symptom slo <<<"$line"
    id="gd-$(date -u +%Y%m%d-%H%M%S)"
    python3 - "$STATE" "$id" "$name" "$flag" "$variant" "$symptom" "$slo" "$(now)" "$delay" <<'PY'
import json,sys
p,id,name,flag,variant,symptom,slo,created,delay=sys.argv[1:]
json.dump({"id":id,"scenario":name,"flag":flag,"variant":variant,"user_symptom":symptom,"expected_detection":slo,
           "created":created,"planned_delay_s":int(delay),"injected_at":None},open(p,"w"),indent=2)
PY
    echo "$(now) GAME $id armed. Failure starts within $(( delay/60 + 1 )) min. Watch your alerts. Good luck."
    ( sleep "$delay"
      out=$(scripts/flag.sh set "$flag" "$variant")
      python3 - "$STATE" "$(now)" <<'PY'
import json,sys
p,t=sys.argv[1:]; d=json.load(open(p)); d["injected_at"]=t; json.dump(d,open(p,"w"),indent=2)
PY
      echo "$out" >> "$STATE_DIR/$id.inject.log" ) >/dev/null 2>&1 &
    ;;
  status)
    [ -f "$STATE" ] && python3 -c "import json;d=json.load(open('$STATE'));print('running:',d['id'],'| armed at',d['created'],'| injected:', 'yes' if d['injected_at'] else 'not yet')" || echo "no game running"
    ;;
  end)
    [ -f "$STATE" ] || { echo "no game running"; exit 1; }
    ended=$(now); scripts/flag.sh reset
    python3 - "$STATE" "$ended" <<'PY'
import json,sys,datetime as dt
p,ended=sys.argv[1:]; d=json.load(open(p)); d["ended_at"]=ended
f=lambda s: dt.datetime.strptime(s,"%Y-%m-%dT%H:%M:%SZ")
print("\n=== REVEAL ===")
for k in ("id","scenario","flag","variant","user_symptom","expected_detection","injected_at","ended_at"): print(f"  {k:19} {d.get(k)}")
if d.get("injected_at"): print(f"  {'impact_duration':19} {int((f(ended)-f(d['injected_at'])).total_seconds())} s (inject -> mitigation)")
print("\nRecord in your postmortem: when did you DETECT (first alert/notice) and MITIGATE? Compare with injected_at.")
json.dump(d,open(p.replace("current.json", d["id"]+".json"),"w"),indent=2)
PY
    rm -f "$STATE"
    ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
