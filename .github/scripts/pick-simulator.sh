#!/usr/bin/env bash
#
# pick-simulator.sh — print the UDID of an available iPhone simulator.
# Used by screenshots.yml.
#
# CI used to name one fixed device ("iPhone 16"). A runner image without that
# exact device — or without any iOS runtime installed — fails before a single
# test runs, and the same commit passes on the next runner. Choose whatever
# iPhone the runner actually has, and download the iOS platform first if it
# has none at all.
set -euo pipefail

available() { xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' || true; }

if [[ -z "$(available)" ]]; then
  echo "pick-simulator: no iOS simulator on this runner; downloading the platform" >&2
  xcodebuild -downloadPlatform iOS >&2
fi

# Lines look like "    iPhone 16 Pro (UDID) (Shutdown)". A numbered model beats
# an SE, and the highest number wins; sort -V alone would rank "SE" above "16".
line="$(available | grep -E '^[[:space:]]+iPhone [0-9]+' | sort -V | tail -1 || true)"
[[ -n "$line" ]] || line="$(available | tail -1)"
udid="$(printf '%s\n' "$line" | sed -E 's/.*\(([0-9A-Fa-f-]+)\) \([A-Za-z ]+\)[[:space:]]*$/\1/')"
[[ -n "$udid" ]] || { echo "pick-simulator: still no iPhone simulator available" >&2; exit 1; }
echo "$udid"
