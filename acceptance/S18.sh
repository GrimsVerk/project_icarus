#!/usr/bin/env bash
#
# S18 (R6, R9, R13, R15, R19, R21, R45) — every §4 use case is a fixture, and
# the engine reproduces its outcome type, headline minutes, per-region doses and
# copy keys from the fixture's forecast, clock, profile, history and window.
#
# Twice, under two time zones. The day is the unit of budget and it is a local
# calendar day at the forecast's place, never at the machine's: a fixture that
# only passes under the runner's own zone is a fixture that will not pass on a
# phone in Oslo.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "S18 — the §4 use cases as fixtures (1-6, 8 and 9 for M1)"
echo

# A prefix, not an exact class name: the fixtures are written blind from the
# same plan and the class may name itself UseCaseTests or UseCaseFixtureTests.
filter='IcarusCoreTests.UseCase'

for zone in UTC Europe/Oslo; do
  echo "== TZ=$zone"
  status=0
  output="$(TZ="$zone" swift test --filter "$filter" 2>&1)" || status=$?
  printf '%s\n' "$output"
  if [[ "$status" -ne 0 ]]; then
    echo "S18: the use-case fixtures failed under TZ=$zone (exit $status)." >&2
    exit 1
  fi
  # An empty selection is not a pass. `swift test` exits 0 when a filter matches
  # nothing, so "no fixtures" would otherwise read exactly like "every fixture
  # passed" — which is the one thing this criterion exists to tell apart.
  ran="$(printf '%s\n' "$output" | grep -oE 'Executed [0-9]+ test' | grep -oE '[0-9]+' \
    | awk '{ total += $1 } END { print total + 0 }')"
  if [[ "$ran" -eq 0 ]]; then
    echo "S18: no test matched '$filter' under TZ=$zone — the use-case fixtures are missing." >&2
    exit 1
  fi
  echo "  ran $ran use-case assertions under TZ=$zone"
  echo
done

echo "both time zones agree."
