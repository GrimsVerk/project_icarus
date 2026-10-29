import re, json, sys
src, out = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
parts = re.split(r"^## Module (\d+) — (.+)$", text, flags=re.M)
mods = []
for i in range(1, len(parts), 3):
    n, title, body = int(parts[i]), parts[i + 1].strip(), parts[i + 2]
    body = re.sub(r"\n-{3,}\s*$", "", body.strip()).strip()
    mods.append({"n": n, "title": title, "md": body})
js = ("/* Generated from docs/LEARN_CONTENT.md (verbatim, V5). Do not edit by hand. */\n"
      "window.ICARUS_LEARN = " + json.dumps(mods, ensure_ascii=False, indent=1) + ";\n")
open(out, "w", encoding="utf-8").write(js)
print(len(mods), "modules", [m["title"][:30] for m in mods])
