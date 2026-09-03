#!/usr/bin/env bash
#
# S15 (R39, R40, R41) — the banner slot is declared, and only where R39 allows.
#
# The screen manifest is the declaration: every screen says whether it carries
# the banner and whether it shows a figure, and `ScreenManifestTests` asserts the
# whole table. The Calculator entry screen and the Learn module list carry the
# banner and nothing else does; the entry screen carries no figure at all, which
# is the second half of R39 and is checked again by the `FigureView` grep below.
#
# The suite needs SwiftUI, so it runs on macOS. On Linux IcarusUI is not built at
# all (D-2026-09-03-F6) and there is nothing to run: the declaration itself is
# checked there instead, row by row, so the script still fails on a table that
# lost a row rather than passing because it could not look.
#
# The AdMob provider's own assertions — the non-personalised flag before the
# first request, the consent flow in a region that requires one, limited ads on
# refusal — land with that provider in M7. Until then the no-op provider is what
# every screen receives, and `IcarusAdsTests` asserts it.
set -euo pipefail
cd "$(dirname "$0")/.."

manifest="Sources/IcarusUI/ScreenManifest.swift"
rows=(
  '("CalculatorEntryView", true, false)'
  '("LearnListView", true, false)'
  '("ModuleView", false, false)'
  '("ResultView", false, true)'
  '("FlipTimerView", false, true)'
  '("OnboardingFlow", false, false)'
  '("SkinCheckFlow", false, false)'
  '("LastingColourFlow", false, false)'
  '("HistoryView", false, true)'
  '("SettingsView", false, true)'
)

echo "S15 — the banner slot and the figures, as declared (R39, R40, R41)"
echo

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "== the screen manifest suite"
  status=0
  output="$(swift test --filter ScreenManifestTests 2>&1)" || status=$?
  printf '%s\n' "$output"
  if [[ "$status" -ne 0 ]]; then
    echo "S15: the screen manifest suite failed (exit $status)." >&2
    exit 1
  fi
  # An empty selection is not a pass: `swift test` exits 0 when a filter matches
  # nothing, which would read exactly like a table that holds.
  ran="$(printf '%s\n' "$output" | grep -oE 'Executed [0-9]+ test' | grep -oE '[0-9]+' \
    | awk '{ total += $1 } END { print total + 0 }')"
  if [[ "$ran" -eq 0 ]]; then
    echo "S15: no test matched ScreenManifestTests — the manifest is unasserted." >&2
    exit 1
  fi
  echo "  ran $ran manifest assertions."
else
  echo "== the manifest test needs macOS: IcarusUI is not built on Linux."
  echo "== checking the declaration in $manifest instead"
  for row in "${rows[@]}"; do
    if ! grep -qF "$row" "$manifest"; then
      echo "S15: $manifest does not declare $row" >&2
      exit 1
    fi
    echo "  $row"
  done
  echo "  all ${#rows[@]} rows present."
fi

echo
echo "== no figure on the Calculator entry screen or in the prompts (R39)"
figures=0
for path in Sources/IcarusUI/Calculator/CalculatorEntryView.swift Sources/IcarusUI/Prompts; do
  [[ -e "$path" ]] || continue
  if grep -rn 'FigureView(' "$path"; then
    figures=1
  fi
done
if [[ "$figures" -eq 1 ]]; then
  echo "S15: the entry screen or a prompt shows a figure. Every figure lives on Result." >&2
  exit 1
fi
echo "  none."

echo
echo "S15: the banner slot is declared where R39 allows it, and nowhere else."
