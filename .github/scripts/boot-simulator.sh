#!/usr/bin/env bash
#
# boot-simulator.sh <udid> — boot the simulator and wait until it is ready.
# Used by screenshots.yml.
#
# On some runners the first boot hangs ("Waiting on BackBoard") and never
# finishes: run 40941378554 then sat 43 minutes in xcodebuild without a test,
# and run 40976330798 hung here. Give each boot five minutes; after a hang,
# shut the device down, erase it and boot again, three tries in all.
set -euo pipefail

udid="${1:?usage: boot-simulator.sh <udid>}"

for attempt in 1 2 3; do
  echo "boot-simulator: attempt $attempt" >&2
  xcrun simctl bootstatus "$udid" -b &
  pid=$!
  for _ in $(seq 60); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 5
  done
  if ! kill -0 "$pid" 2>/dev/null; then
    if wait "$pid"; then
      exit 0
    fi
  else
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  echo "boot-simulator: no boot after attempt $attempt; erasing the device" >&2
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  xcrun simctl erase "$udid" 2>/dev/null || true
done
echo "boot-simulator: the simulator never booted" >&2
exit 1
