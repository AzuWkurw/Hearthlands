#!/usr/bin/env python3
"""Collect the interface text from the scripts into the translation files.

    python3 tools/extract_strings.py            update data/lang_*.json with new text (empty translations)
    python3 tools/extract_strings.py --report   only say how much of each language is translated

Text is found in the interface helpers (_button, _label, _check, _set_row, add_feature_button), in
`.text = "..."` and `.tooltip_text = "..."`, in tr("...") and in the toolbar and setting tables. Each
data/lang_<code>.json maps the English text to the translation; an empty translation shows English.
The game loads these files at start (scripts/i18n.gd); Godot then translates every label and button
whose text is exactly a key. Text built with numbers in it goes through tr() with %s / %d placeholders.
Messages from the game itself (the event log) are not translated yet.
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATTERNS = [
    r'_button\(\s*"((?:[^"\\]|\\.)+)"',
    r'_label\(\s*"((?:[^"\\]|\\.)+)"',
    r'_check\(\s*"((?:[^"\\]|\\.)+)"',
    r'_set_row\([^,]+,\s*"((?:[^"\\]|\\.)+)"',
    r'add_feature_button\([^,]+,\s*"((?:[^"\\]|\\.)+)"',
    r'\.text\s*=\s*"((?:[^"\\]|\\.)+)"',
    r'\.tooltip_text\s*=\s*"((?:[^"\\]|\\.)+)"',
    r'\.title\s*=\s*"((?:[^"\\]|\\.)+)"',
    r'\btr\(\s*"((?:[^"\\]|\\.)+)"',
    r'_show_hint\(\s*"((?:[^"\\]|\\.)+)"',
    r'_section\([^,]+,\s*"((?:[^"\\]|\\.)+)"',
    r'_group\([^,]+,\s*"((?:[^"\\]|\\.)+)"',
    r'_btn\(\s*"((?:[^"\\]|\\.)+)"',
    r'\["[a-z_]+", "([A-Z][^"\\]+)"\]',                # building groups: ["raw", "Raw"]
    r'\["[a-z_]+", "((?:[^"\\]|\\.)+)", KEY_',          # keys in Settings
    r'\["@\w+", "((?:[^"\\]|\\.)+)"',                   # road tools: name
    r'\["@\w+", "[^"]*", "[^"]*", "((?:[^"\\]|\\.)+)"\]',  # road tools: tooltip
    r'\["((?:[^"\\]|\\.)+)", "(?:has|joined|any):[^"]*", "(?:[^"\\]|\\.)+"\]',   # the first-game guide
    r'\["(?:[^"\\]|\\.)+", "(?:has|joined|any):[^"]*", "((?:[^"\\]|\\.)+)"\]',
    r'\[\s*"([A-Z][^"\\]{1,60})",\s*"[a-z_@]+"',     # tables like [["Raw", "raw"], ...]
]


def strings():
    found = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)):
        src = open(path, encoding="utf-8").read()
        for pat in PATTERNS:
            for m in re.finditer(pat, src):
                s = m.group(1).replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\\\", "\\")
                if s.startswith("res://") or s.startswith("user://") or s.startswith("@"):
                    continue
                # only text with words in it (not "%02d:%02d", "+" or "x")
                if not re.search(r"[A-Za-z]{3,}", re.sub(r"%[-+0-9.]*[sdf%]|\[/?\w+[^\]]*\]", "", s)):
                    continue
                found.setdefault(s, os.path.relpath(path, ROOT))
    return found


def main():
    found = strings()
    files = sorted(glob.glob(os.path.join(ROOT, "data", "lang_*.json")))
    for f in files:
        d = json.load(open(f, encoding="utf-8"))
        done = sum(1 for k in found if d.get(k))
        print("%s: %d of %d texts translated" % (os.path.basename(f), done, len(found)))
        if "--report" in sys.argv:
            continue
        for k in found:
            d.setdefault(k, "")
        # texts no longer in the scripts are dropped (except the language's own name)
        d = {k: v for k, v in d.items() if k in found or k.startswith("_")}
        json.dump(dict(sorted(d.items())), open(f, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    if not files:
        print("%d texts found; no data/lang_*.json yet" % len(found))


if __name__ == "__main__":
    main()
