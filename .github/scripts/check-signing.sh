#!/usr/bin/env bash
#
# check-signing.sh — assert the app target's resolved signing settings.
# Used by nightly.yml's new-xcode job.
#
# Usage: check-signing.sh <bundle id> <entitlements path, or "" for none> [team]
#
# Signing.xcconfig sets the bundle id and the entitlements file, and an
# optional Local.xcconfig overrides them (README, "Run on your iPhone"). Both
# depend on XcodeGen leaving those keys off the target and on Xcode honouring
# `#include?`, so the check reads what Xcode itself resolves.
set -euo pipefail

want_id="$1"
want_entitlements="$2"
want_team="${3-}"

settings="$(xcodebuild -showBuildSettings -project ProjectIcarus.xcodeproj \
  -target ProjectIcarus -configuration Debug)"
value() { printf '%s\n' "$settings" | sed -n "s/^ *$1 = //p" | head -n 1; }

status=0
check() {
  local got
  got="$(value "$1")"
  if [[ "$got" == "$2" ]]; then
    echo "check-signing: $1 = '$got'"
  else
    echo "check-signing: $1 is '$got', expected '$2'" >&2
    status=1
  fi
}

check PRODUCT_BUNDLE_IDENTIFIER "$want_id"
check CODE_SIGN_ENTITLEMENTS "$want_entitlements"
if [[ -n "$want_team" ]]; then
  check DEVELOPMENT_TEAM "$want_team"
fi
exit "$status"
