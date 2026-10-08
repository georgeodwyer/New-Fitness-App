#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator (newest iOS runtime first).
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in data if "iOS" in r), reverse=True)
for r in runtimes:
    for d in data[r]:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit(0)
sys.exit("No iPhone simulator found")
'
