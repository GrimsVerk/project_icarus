#!/usr/bin/env bash
#
# S7 (R26, R27) — the twelve Learn modules load, their text is the source text
# after normalisation, every citation keeps the identifier the source carries,
# and every module id resolves for a deep link.
#
# Two pieces of evidence. First, the committed module files are what the
# generator produces from `docs/LEARN_CONTENT.md` right now: they are
# regenerated into a temporary directory and diffed byte for byte, so the
# document stays the single source (D-2026-09-03-F4) and drift fails here
# rather than shipping. Second, the content suite, which loads the bundled
# files and checks the text, the citations and the deep links.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "S7 — Learn modules, citations and deep links (R26, R27)"
echo

generated="$(mktemp -d)"
trap 'rm -rf "$generated"' EXIT

echo "== regenerate the module files from docs/LEARN_CONTENT.md"
swift run split-learn-content docs/LEARN_CONTENT.md "$generated"

echo
echo "== byte-for-byte against Sources/IcarusContent/Resources/Learn"
diff -r Sources/IcarusContent/Resources/Learn "$generated"
echo "  no drift: the committed files are the document, split."
echo "  $(ls "$generated" | wc -l) module files compared."

echo
echo "== the content suite"
swift test --filter IcarusContentTests
