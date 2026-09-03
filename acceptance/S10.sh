#!/usr/bin/env bash
#
# S10 (R11, R20, R22, R23, R24, R25, R44, R45) — logging and state.
#
# The criterion is a list of behaviours, and every one of them is asserted by a
# test rather than described here: the prompt scheduler, the store and its
# replay, the export round-trip and the totals live in `IcarusDataTests`, and
# the flows that ask the questions live in `IcarusUITests`. So this script runs
# those suites and prints the checklist beside the result, which is what the
# evidence cell in `docs/acceptance.md` cites.
#
# On Linux `IcarusUI` is not built at all (D-2026-09-03-F6), so the UI half of
# the criterion cannot be observed there. The script says so rather than passing
# quietly: an unobserved half reported as a pass is exactly the narration this
# check exists to remove.
#
# An empty selection is not a pass either. `swift test` exits 0 when a filter
# matches nothing, which would read like a suite that holds, so the number of
# tests actually executed is counted and zero fails.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "S10 — logging and state (R11, R20, R22, R23, R24, R25, R44, R45)"
echo

if [[ "$(uname -s)" == "Darwin" ]]; then
  filter='IcarusDataTests|IcarusUITests'
else
  filter='IcarusDataTests'
fi

echo "== swift test --filter '$filter'"
status=0
output="$(swift test --filter "$filter" 2>&1)" || status=$?
printf '%s\n' "$output"
if [[ "$status" -ne 0 ]]; then
  echo "S10: the logging suites failed (exit $status)." >&2
  exit 1
fi

ran="$(printf '%s\n' "$output" | grep -oE 'Executed [0-9]+ test' | grep -oE '[0-9]+' \
  | awk '{ total += $1 } END { print total + 0 }')"
if [[ "$ran" -eq 0 ]]; then
  echo "S10: no test matched '$filter' — the logging behaviour is unasserted." >&2
  exit 1
fi
echo "  ran $ran assertions."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo
  echo "== the skin-check and lasting-colour flows need macOS: IcarusUI is not built on Linux."
  echo "   Their models are asserted by IcarusUITests, which runs on macOS."
fi

echo
echo "== the S10 checklist"
cat <<'CHECKLIST'
  1. a day with one planned and one logged session schedules one skin-check
     prompt after the last of them
  2. the prompt opens with "did you do this session?" and logs the planned
     session on "yes"
  3. the prompt's evidence is the day's summed dose
  4. stopping the timer early shortens the stored dose on the actual
     sub-intervals
  5. with notifications denied the questions are asked in-app within their
     windows
  6. each Q1 answer produces the expected multiplier or tanState movement via
     replay
  7. the Settings sentence renders from derived state and counts reports
  8. a Tunables change followed by a replay changes derived state and every
     historical normalisation for an existing history
  9. the JSON export round-trips every record, each session's stored curve and
     the tunables version, and importing it reproduces the derived state
 10. a result recomputed from an exported session's stored curve, profile and
     Tunables version matches the stored per-region doses
 11. deleting the history shows the warning and resets to the prior
 12. weekly and cycle totals per region are computed from the history
CHECKLIST

echo
echo "S10: the logging suites pass."
