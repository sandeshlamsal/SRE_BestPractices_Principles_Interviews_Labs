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

def write():
    req = urllib.request.Request(f"{api}/write-to-file", data=json.dumps({"data": flags}).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    urllib.request.urlopen(req).read()

if cmd == "list":
    for k in sorted(f):
        print(f"{k:32} {f[k]['defaultVariant']}")
elif cmd == "get":
    print(json.dumps(f[name], indent=2))
elif cmd == "set":
    if variant not in f[name]["variants"]:
        sys.exit(f"Unknown variant '{variant}'. Options: {list(f[name]['variants'])}")
    old = f[name]["defaultVariant"]; f[name]["defaultVariant"] = variant; write()
    print(f"{now} FLAG {name}: {old} -> {variant}")
elif cmd == "reset":
    changed = [k for k in f if f[k]["defaultVariant"] != "off" and "off" in f[k]["variants"]]
    for k in changed: f[k]["defaultVariant"] = "off"
    write(); print(f"{now} RESET flags to off: {changed or 'none were on'}")
else:
    sys.exit("usage: flag.sh list|get <flag>|set <flag> <variant>|reset")
PY
