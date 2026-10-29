#!/usr/bin/env python3
"""Writes the owner's readable list of the app's copy, with ids, as one HTML file.

    scripts/copy-review.py <output.html> [--screenshots <dir>]

It reads docs/APP_COPY.md and docs/privacy-policy.md from this repository and
writes a self-contained page: the provisional lines by screen, under the ids
the owner and agents refer to them by (D-2026-10-29-C1), then the lines
approved earlier. With --screenshots, the PNGs of a Screenshots run (the
`screenshots` artifact, unzipped) are embedded beside the screens they show.

The output path is the caller's: the page is for the owner and lives outside
every repository. Python 3 standard library only, so it runs on macOS and Linux
with nothing installed.
"""

import argparse
import base64
import datetime
import html
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
COPY = REPO / "docs" / "APP_COPY.md"
POLICY = REPO / "docs" / "privacy-policy.md"

# Sections the build script reads but that hold no keyed lines.
NON_KEYED = {"Skin types", "Fitzpatrick quiz"}

# Which screenshots (by the name the Screenshots test gives them) show which
# section, matched on the start of the section's title.
SHOTS = {
    "Tabs": ["03-calculator"],
    "Plan screen": ["03-calculator"],
    "Due questions": ["03-calculator"],
    "Result screen": ["04-result", "04-result-scrolled"],
    "Result figures": ["04-result", "04-result-scrolled"],
    "Flip timer": ["05-flip-timer"],
    "Skin check": ["10-skin-check"],
    "Lasting colour": ["11-lasting-colour"],
    "History": ["06-history"],
    "Settings": ["07-settings", "07-settings-scrolled"],
    "Onboarding": [
        "01-onboarding-1-module",
        "01-onboarding-2-disclaimer",
        "01-onboarding-3-skin-type",
        "01-onboarding-4-permissions",
    ],
    "Learn": ["08-learn-list"],
}


def parse_copy(text):
    """Every keyed line and every `- <id>: text` line, in document order."""
    sections = []
    current = None
    entry = None
    for raw in text.split("\n"):
        line = raw.strip()
        if line.startswith("## "):
            current = {"title": line[3:].strip(), "entries": [], "loose": []}
            sections.append(current)
            entry = None
            continue
        if current is None or current["title"] in NON_KEYED:
            continue
        if line.startswith("### "):
            entry = {"key": line[4:].strip()}
            current["entries"].append(entry)
            continue
        field = re.match(r"^- (id|where|base|fair|why|status):\s*(.*)$", line)
        if field and entry is not None:
            entry[field.group(1)] = field.group(2)
            continue
        loose = re.match(r"^- ([A-Z]+-\d+):\s*(.*)$", line)
        if loose:
            entry = {"id": loose.group(1), "base": loose.group(2), "key": None}
            current["loose"].append(entry)
            continue
        sub = re.match(r"^- (where|why|status):\s*(.*)$", line)
        if sub and current["loose"]:
            current["loose"][-1][sub.group(1)] = sub.group(2)
    return sections


def parse_policy(text):
    """`<!-- PRIV-n -->` followed by its paragraph."""
    lines = []
    for match in re.finditer(r"<!-- (PRIV-\d+) -->\n(.+?)(?:\n\n|\Z)", text, re.S):
        lines.append((match.group(1), match.group(2).strip().lstrip("# ").strip()))
    return lines


def grouped(entries):
    """One row per id: an id with several values is one key per value."""
    rows = []
    for entry in entries:
        if rows and rows[-1]["id"] == entry["id"]:
            rows[-1]["values"].append(entry["base"])
            rows[-1]["keys"].append(entry["key"])
        else:
            rows.append({**entry, "values": [entry["base"]], "keys": [entry["key"]]})
    return rows


def words(text):
    """Escaped, with `{placeholders}` marked."""
    return re.sub(r"(\{[a-zA-Z]+\})", r'<span class="ph">\1</span>', html.escape(text))


def anchor(title):
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def screenshots(directory, title):
    if directory is None:
        return ""
    names = next((shots for prefix, shots in SHOTS.items() if title.startswith(prefix)), [])
    out = []
    for name in names:
        path = directory / f"{name}.png"
        if not path.is_file():
            continue
        data = base64.b64encode(path.read_bytes()).decode()
        out.append(
            f'<details class="shot"><summary>Screenshot: {html.escape(name)}</summary>'
            f'<img alt="Screenshot {html.escape(name)}" src="data:image/png;base64,{data}"></details>'
        )
    return "".join(out)


def row(entry):
    keys = ", ".join(f"<code>{html.escape(k)}</code>" for k in entry.get("keys", []) if k)
    parts = [f'<div class="line"><div class="id">{html.escape(entry["id"])}</div>']
    if entry.get("where"):
        parts.append(f'<div class="where">{html.escape(entry["where"])}</div>')
    parts.append(f'<div class="text">{" · ".join(words(v) for v in entry["values"])}</div>')
    if entry.get("fair"):
        parts.append(f'<div class="where">Types I and II: {words(entry["fair"])}</div>')
    if entry.get("why"):
        parts.append(f'<div class="why">{html.escape(entry["why"])}</div>')
    meta = [m for m in [entry.get("status", ""), keys] if m]
    parts.append(f'<div class="meta">{" · ".join(meta)}</div></div>')
    return "".join(parts)


def source_commit():
    try:
        return subprocess.run(
            ["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


STYLE = """
:root { --bg:#fafaf7; --fg:#1d1d1b; --muted:#66645e; --line:#e3e1da; --card:#fff; --accent:#b4560f; --ph:#1f5fa8; }
@media (prefers-color-scheme: dark) { :root { --bg:#161614; --fg:#ecebe6; --muted:#a3a19a; --line:#2f2e2a; --card:#1f1f1c; --accent:#f0a060; --ph:#8cb8f0; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.5 -apple-system, system-ui, "Segoe UI", sans-serif; }
main { max-width:760px; margin:0 auto; padding:16px 16px 64px; }
h1 { font-size:1.5rem; margin:.5rem 0 .25rem; }
h2 { font-size:1.15rem; margin:2rem 0 .5rem; padding-top:.5rem; border-top:2px solid var(--line); }
.intro, .meta { color:var(--muted); font-size:.85rem; }
nav { font-size:.9rem; line-height:1.9; }
nav a, details.shot summary { color:var(--ph); }
.line { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:10px 12px; margin:8px 0; }
.id { font:600 .8rem ui-monospace, Menlo, monospace; color:var(--accent); }
.where { color:var(--muted); font-size:.85rem; }
.text { font-size:1.05rem; margin:4px 0; overflow-wrap:anywhere; }
.why { color:var(--muted); font-size:.85rem; font-style:italic; }
.ph { color:var(--ph); font-family:ui-monospace, Menlo, monospace; font-size:.92em; }
code { font-family:ui-monospace, Menlo, monospace; font-size:.85em; overflow-wrap:anywhere; }
details.shot summary { cursor:pointer; font-size:.85rem; }
details.shot img { display:block; max-width:min(100%, 300px); margin:8px 0; border:1px solid var(--line); border-radius:8px; }
"""


def page(sections, policy, shots):
    provisional, earlier = [], []
    for section in sections:
        with_id = [e for e in section["entries"] if e.get("id")]
        without = [e for e in section["entries"] if not e.get("id")]
        if with_id or section["loose"]:
            provisional.append((section["title"], grouped(with_id) + grouped(section["loose"])))
        if without:
            earlier.append((section["title"], without))
    count = sum(len(rows) for _, rows in provisional) + len(policy)

    commit = source_commit()
    made = datetime.date.today().isoformat()
    body = [
        "<h1>Icarus: the app's copy</h1>",
        f'<p class="meta">{count} provisional lines with ids, generated {made} from '
        f"<code>docs/APP_COPY.md</code> and <code>docs/privacy-policy.md</code>"
        + (f" at <code>{commit}</code>" if commit else "")
        + " by <code>scripts/copy-review.py</code>. Don't edit this file: it is rewritten.</p>",
        '<p class="intro">The ids are how a line is named from now on (“CALC-9: Staying until the end”). '
        "Every line with an id is provisional: OK'd on 2026-10-29 so it can be judged in the app, and "
        "work in progress until you settle it. A line with several values separated by · is one id. "
        '<span class="ph">{braces}</span> are values the app fills in.</p>',
    ]
    titles = [t for t, _ in provisional] + ["Privacy policy (not published)", "Approved earlier"]
    body.append("<nav>" + " · ".join(f'<a href="#{anchor(t)}">{html.escape(t)}</a>' for t in titles) + "</nav>")
    for title, rows in provisional:
        body.append(f'<section id="{anchor(title)}"><h2>{html.escape(title)}</h2>')
        body.append(screenshots(shots, title))
        body.extend(row(r) for r in rows)
        body.append("</section>")

    title = titles[-2]
    body.append(f'<section id="{anchor(title)}"><h2>{html.escape(title)}</h2>')
    body.append('<p class="intro">Provisional too. It still needs the app\'s name, a contact address and the '
                "date before it goes on this repository's GitHub Pages.</p>")
    body.extend(row({"id": i, "values": [t], "keys": []}) for i, t in policy)
    body.append("</section>")

    title = titles[-1]
    body.append(f'<section id="{anchor(title)}"><h2>{html.escape(title)}</h2>')
    body.append('<p class="intro">Approved line by line in 2026-09. They have no id; they are named by '
                "their key. The skin-type table and the questionnaire are in <code>docs/APP_COPY.md</code>.</p>")
    for section_title, entries in earlier:
        body.append(f"<h3>{html.escape(section_title)}</h3>")
        for entry in entries:
            body.append(
                f'<div class="line"><div class="id">{html.escape(entry["key"])}</div>'
                f'<div class="text">{words(entry.get("base", ""))}</div>'
                + (f'<div class="where">Types I and II: {words(entry["fair"])}</div>' if entry.get("fair") else "")
                + "</div>"
            )
    body.append("</section>")

    return (
        '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"<title>Icarus copy</title>\n<style>{STYLE}</style></head>\n"
        "<body><main>\n" + "\n".join(b for b in body if b) + "\n</main></body></html>\n"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("output", type=pathlib.Path, help="the HTML file to write")
    parser.add_argument("--screenshots", type=pathlib.Path, help="a folder of Screenshots-run PNGs")
    args = parser.parse_args()
    if args.screenshots is not None and not args.screenshots.is_dir():
        sys.exit(f"copy-review: {args.screenshots} is not a folder")

    sections = parse_copy(COPY.read_text(encoding="utf-8"))
    policy = parse_policy(POLICY.read_text(encoding="utf-8"))
    args.output.write_text(page(sections, policy, args.screenshots), encoding="utf-8")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
