import re, json, sys
src, out = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8").read().splitlines()
copy, ids, key = {}, {}, None
for ln in lines:
    m = re.match(r"^### (\w+)\s*$", ln)
    if m: key = m.group(1); continue
    if key:
        m = re.match(r"^- base: (.*)$", ln)
        if m: copy[key] = m.group(1)
        m = re.match(r"^- fair: (.*)$", ln)
        if m: copy[key + "_fair"] = m.group(1)
        m = re.match(r"^- id: (.*)$", ln)
        if m: ids[key] = m.group(1).strip()
    if ln.startswith("## Skin types"): key = None
# skin types table
types = []
for ln in lines:
    m = re.match(r"^\| (I|II|III|IV|V|VI) \| (Type \w+) \| (.+) \|$", ln)
    if m: types.append({"type": m.group(1), "name": m.group(2), "description": m.group(3)})
quiz = []
for ln in lines:
    m = re.match(r"^(\d+)\. (.+?) — (.+)$", ln)
    if m: quiz.append({"q": m.group(2), "answers": [a.strip() for a in m.group(3).split("|")]})
for ln in lines:
    m = re.match(r"^- PERM-1: (.*)$", ln)
    if m: copy["permLocationDialog"] = m.group(1)
js = ("/* Generated from docs/APP_COPY.md (base lines). Do not edit by hand.\n"
      "   ICARUS_COPY[key] = text with {placeholders}; ICARUS_COPY_IDS[key] = owner id (CALC-9 ...). */\n"
      "window.ICARUS_COPY = " + json.dumps(copy, ensure_ascii=False, indent=1) + ";\n"
      "window.ICARUS_COPY_IDS = " + json.dumps(ids, ensure_ascii=False) + ";\n"
      "window.ICARUS_SKIN_TYPES = " + json.dumps(types, ensure_ascii=False, indent=1) + ";\n"
      "window.ICARUS_QUIZ = " + json.dumps(quiz, ensure_ascii=False, indent=1) + ";\n")
open(out, "w", encoding="utf-8").write(js)
print(len(copy), "keys,", len(types), "types,", len(quiz), "quiz questions")
