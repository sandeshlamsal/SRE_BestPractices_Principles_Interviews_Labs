#!/usr/bin/env bash
# Get/set Astronomy Shop feature flags (flagd) for fault injection / game days.
# Uses the flagd-ui API through the frontend-proxy port-forward (make open).
#
#   scripts/flag.sh list                       # all flags + current variant
#   scripts/flag.sh get paymentFailure         # one flag + its variants
#   scripts/flag.sh set paymentFailure 50%     # switch variant (logged to stdout with UTC time)
#   scripts/flag.sh reset                      # all flags back to "off"
#
# NOTE: flags live in an emptyDir copy; a flagd pod restart resets them to chart defaults.
set -euo pipefail
API="${FLAG_API:-http://localhost:8080/feature/api}"
cmd="${1:-list}"

curl -sf "$API/read-file" > /tmp/.flags.json || { echo "Cannot reach $API (is 'make open' running?)" >&2; exit 1; }

python3 - "$cmd" "${2:-}" "${3:-}" "$API" <<'PY'
import json, sys, urllib.request, datetime
cmd, name, variant, api = sys.argv[1:5]
flags = json.load(open("/tmp/.flags.json"))
f = flags["flags"]
now = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")

# flagd evaluates `targeting` BEFORE defaultVariant. For targeted flags of the form
# {"if": [condition, then_variant, else_variant]} the demo keeps both branches "off";
# enabling means setting the THEN branch (P2-ISSUE-19). defaultVariant alone does nothing.
def targeted(flag):
    t = flag.get("targeting") or {}
    return isinstance(t.get("if"), list) and len(t["if"]) == 3

def effective(flag):
    return flag["targeting"]["if"][1] if targeted(flag) else flag["defaultVariant"]

def set_variant(flag, v):
    flag["defaultVariant"] = v if not targeted(flag) else "off"
    if targeted(flag):
        flag["targeting"]["if"][1] = v

def write():
    req = urllib.request.Request(f"{api}/write-to-file", data=json.dumps({"data": flags}).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    urllib.request.urlopen(req).read()

if cmd == "list":
    for k in sorted(f):
        print(f"{k:32} {effective(f[k])}{'  (targeted)' if targeted(f[k]) else ''}")
elif cmd == "get":
    print(json.dumps(f[name], indent=2))
elif cmd == "set":
    if variant not in f[name]["variants"]:
        sys.exit(f"Unknown variant '{variant}'. Options: {list(f[name]['variants'])}")
    old = effective(f[name]); set_variant(f[name], variant); write()
    print(f"{now} FLAG {name}: {old} -> {variant}" + ("  (targeted: applies when the targeting condition matches)" if targeted(f[name]) else ""))
elif cmd == "reset":
    changed = [k for k in f if "off" in f[k]["variants"] and effective(f[k]) != "off"]
    for k in changed: set_variant(f[k], "off")
    write(); print(f"{now} RESET flags to off: {changed or 'none were on'}")
else:
    sys.exit("usage: flag.sh list|get <flag>|set <flag> <variant>|reset")
PY
