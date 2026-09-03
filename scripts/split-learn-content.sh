#!/usr/bin/env bash
#
# Regenerates the committed Learn module files from docs/LEARN_CONTENT.md.
#
# The document is the single source of the Learn text (D-2026-09-03-F4). Run
# this after editing it, and commit the result; acceptance/S7.sh fails when the
# committed files differ from what this produces.
set -euo pipefail
cd "$(dirname "$0")/.."

swift run split-learn-content docs/LEARN_CONTENT.md Sources/IcarusContent/Resources/Learn
