#!/usr/bin/env bash
#
# S11 (R32, R34, R42) — the static checks.
#
# Seven pieces of evidence, and each one is a fact about the tree rather than a
# claim about it:
#
#   1. The committed app copy is what `docs/APP_COPY.md` produces right now.
#      The document is the single source of every non-Learn string and the owner
#      approves every line of it (S17), so drift between the document and the
#      JSON the app reads is a change nobody approved.
#   2. Every `CopyKey` has a line in the document, and every line in the
#      document is a `CopyKey`. Both directions, because a key with no copy
#      crashes and copy with no key is text nothing can show.
#   3. No literal at a copy-bearing call site in the UI or the app target.
#   4. IcarusCore depends on nothing and imports nothing but Foundation.
#   5. No network or weather import outside IcarusData, no ad SDK outside
#      IcarusAds.
#   6. No figure on the Calculator entry screen or in the prompts (R39).
#   7. The location permission's purpose string is PERM-1, word for word: it
#      is copy, but iOS reads it from the Info.plist, so it lives in
#      project.yml rather than behind a CopyKey.
#
# Everything here runs on Linux and on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "S11 — copy is data, and the layers hold (R32, R34, R42)"
echo

# 1 ---------------------------------------------------------------- generated
echo "== the committed app copy is docs/APP_COPY.md, built"
generated="$(mktemp -d)"
trap 'rm -rf "$generated"' EXIT
swift run build-app-copy docs/APP_COPY.md "$generated/app-copy.json"
diff "Sources/IcarusContent/Resources/app-copy.json" "$generated/app-copy.json"
echo "  no drift: the committed JSON is the document, built."

# 2 --------------------------------------------------------------------- keys
echo
echo "== every CopyKey has copy, and every key of copy is a CopyKey"
cases="$(grep -oE '^ *case [a-zA-Z][a-zA-Z0-9]*' Sources/IcarusCore/Models/CopyKey.swift \
  | awk '{ print $2 }' | sort)"
# The `## Notification texts` section is approved wording for a later plan: its
# keys are deliberately not in the enum yet, so they are excluded here exactly
# as the build script skips them.
headings="$(awk '
  /^## / { section = substr($0, 4); next }
  /^### / { if (section != "Notification texts") print substr($0, 5) }
' docs/APP_COPY.md | sort)"

missing="$(comm -23 <(printf '%s\n' "$cases") <(printf '%s\n' "$headings"))"
extra="$(comm -13 <(printf '%s\n' "$cases") <(printf '%s\n' "$headings"))"
if [[ -n "$missing" ]]; then
  echo "S11: CopyKey cases with no copy in docs/APP_COPY.md:" >&2
  printf '  %s\n' $missing >&2
  exit 1
fi
if [[ -n "$extra" ]]; then
  echo "S11: keys in docs/APP_COPY.md that are not CopyKey cases:" >&2
  printf '  %s\n' $extra >&2
  exit 1
fi
echo "  $(printf '%s\n' "$cases" | grep -c .) keys, both directions."

# 3 ------------------------------------------------------------------ literals
echo
echo "== no literal at a copy-bearing call site in Sources/IcarusUI or App/"
sites='(Text|Label|Button|Section|navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint)\("'
found=0
for tree in Sources/IcarusUI App; do
  [[ -d "$tree" ]] || continue
  if grep -rnE "$sites" "$tree"; then
    found=1
  fi
done
if [[ "$found" -eq 1 ]]; then
  echo "S11: a view holds copy. Every user-visible string resolves through AppCopy (R42)." >&2
  exit 1
fi
echo "  none. System image names are not copy: Image(systemName:) is not a call site here."

# 4 ---------------------------------------------------------------- IcarusCore
echo
echo "== IcarusCore depends on nothing and imports nothing but Foundation"
dependencies="$(swift package describe --type json \
  | jq -r '.targets[] | select(.name == "IcarusCore") | (.target_dependencies // []) | join(", ")')"
if [[ -n "$dependencies" ]]; then
  echo "S11: IcarusCore depends on: $dependencies" >&2
  exit 1
fi
imports="$(grep -rhoE '^ *(@testable )?import [A-Za-z_]+' Sources/IcarusCore | awk '{ print $NF }' | sort -u)"
printf '  imports: %s\n' "$(printf '%s ' $imports)"
if [[ "$(printf '%s\n' "$imports")" != "Foundation" ]]; then
  echo "S11: IcarusCore imports more than Foundation." >&2
  exit 1
fi
echo "  no target dependencies."

# 5 ------------------------------------------------------------------- layers
echo
echo "== the network, the weather and the ad SDK stay in their packages"
# `WeatherKitProvider` is IcarusData's own public type and the composition root
# names it; the import is what may not leave the package, so that is what this
# looks for.
leaks=0
if grep -rn 'URLSession\|^ *import WeatherKit' Sources App --include='*.swift' \
  | grep -v '^Sources/IcarusData/'; then
  leaks=1
fi
if grep -rn 'import GoogleMobileAds\|import UserMessagingPlatform' Sources App --include='*.swift' \
  | grep -v '^Sources/IcarusAds/'; then
  leaks=1
fi
if [[ "$leaks" -eq 1 ]]; then
  echo "S11: a package imports something that belongs to another one (R34, R40)." >&2
  exit 1
fi
echo "  none outside Sources/IcarusData and Sources/IcarusAds."

# 6 ------------------------------------------------------------------ figures
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
  echo "S11: the entry screen or a prompt shows a figure. Every figure lives on Result." >&2
  exit 1
fi
echo "  none. (A path that does not exist yet shows no figure either.)"

# 7 ------------------------------------------------------------ purpose string
echo
echo "== the location purpose string in project.yml is PERM-1"
approved="$(sed -n 's/^- PERM-1: //p' docs/APP_COPY.md)"
built="$(sed -n 's/^ *INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: *"\(.*\)"$/\1/p' project.yml)"
if [[ -z "$approved" || "$approved" != "$built" ]]; then
  echo "S11: project.yml's location purpose string is not PERM-1 in docs/APP_COPY.md." >&2
  echo "  PERM-1:      $approved" >&2
  echo "  project.yml: $built" >&2
  exit 1
fi
echo "  $built"

echo
echo "S11: all seven checks hold."
