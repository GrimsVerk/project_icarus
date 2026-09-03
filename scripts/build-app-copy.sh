#!/usr/bin/env bash
#
# Regenerates the committed app copy from docs/APP_COPY.md.
#
# The document is the single source of every non-Learn string, and the owner
# approves every line of it (R42, S17, D-2026-09-03-F7). Run this after the
# document changes, and commit the result; acceptance/S11.sh fails when the
# committed JSON differs from what this produces.
set -euo pipefail
cd "$(dirname "$0")/.."

swift run build-app-copy docs/APP_COPY.md Sources/IcarusContent/Resources/app-copy.json
