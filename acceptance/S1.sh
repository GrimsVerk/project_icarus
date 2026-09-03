#!/usr/bin/env bash
#
# S1 (R4, R6, R30) — the Core dose, target and Tunables tests pass, and every
# constant the engine uses is read from the single Tunables file.
#
# The suite is the evidence for the numbers: trapezoidal integration against a
# known analytic curve, the steep-then-flat window, the type II at UVI 7, the
# selector moving the number for every skin type, no setting above MED, and the
# provenance of every constant. The listing below is the evidence for "one
# file": the read keys the engine's accessors report, taken from the file
# itself, so the count is not something this script asserts about itself.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "S1 — dose, target and the single constants file (R4, R6, R30)"
echo

echo "== the filtered Core suite"
# Class-name prefixes, not exact names: the classes are split by subject
# (DoseCalculatorDurationTests, TunablesProvenanceTests, ...), and `--filter`
# is an unanchored regular expression over "Target.Class/method".
swift test --filter \
  'IcarusCoreTests.(DoseCalculator|ForecastCurve|StoredCurve|Tunables|DayKey|TargetModel|RegionTargetScaling)'

echo
echo "== every constant the engine reads, from Sources/IcarusCore/Tunables.swift"
keys="$(grep -oE 'read\("[^"]+"' Sources/IcarusCore/Tunables.swift \
  | cut -d'"' -f2 \
  | sed -E 's/\\\(([a-z]+)\.[A-Za-z]+\)/<\1>/' \
  | sort -u)"
printf '%s\n' "$keys" | sed 's/^/  /'
echo "  ---"
echo "  $(printf '%s\n' "$keys" | grep -c .) read keys. A key ending in <type>, <band>,"
echo "  <ceiling> or <answer> is one entry per case, and every one of them has a"
echo "  Basis — TunablesProvenanceTests above is what checks that."
