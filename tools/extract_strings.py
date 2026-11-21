#!/usr/bin/env python3
"""Collect the text the player sees into the translation files.

    python3 tools/extract_strings.py            update data/lang_*.json with new text (empty translations)
    python3 tools/extract_strings.py --report   only say how much of each language is translated
    python3 tools/extract_strings.py --missing  also list the texts that have no translation yet

Text is found in the scripts (every string with words in it, outside debug prints and comments) and in
the data files (names, descriptions, mission and campaign stories, goals). Each data/lang_<code>.json
maps the English text to the translation; an empty translation shows English. The game loads these
files at start (scripts/i18n.gd). Keys with %s / %d / %.1f in them also translate text built from them,
so a translation must keep the same placeholders in the same order (and %% for a percent sign when the
English has it).
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIT = re.compile(r'(?<![&^])"((?:[^"\\\n]|\\.)*)"')
# lines that never reach the player
SKIP_LINE = re.compile(r'^\s*(?:#|print|prints|printerr|push_error|push_warning|assert|@export|signal |class_name|extends|preload|const [A-Z_]+ *:?= *preload)')
SKIP_BEFORE = re.compile(r'(?:\b(?:print|prints|printerr|print_rich|push_error|push_warning|assert|load|preload|Color|get_node|has_node|'
                         r'set_meta|get_meta|has_meta|connect|emit_signal|has_method|call_deferred|is_action_pressed|'
                         r'get_setting|set_setting|set_shader_parameter|add_theme_[a-z_]+|get_theme_[a-z_]+|_log_net)\(\s*$)')
TEXT_KEYS = {"name", "info", "title", "plural", "text", "story", "intro", "outro", "new"}
# single words the game puts into its messages (people, soldiers); the checks above skip lone lower-case words
WORDS = ["peasant", "peasants", "artisan", "artisans", "noble", "nobles", "scout", "scouts", "soldier", "soldiers",
         "carrier", "carriers", "builder", "worker", "workers", "geologist", "porters", "mules", "carts",
         "legionary", "spearman", "man-at-arms", "pikeman", "musketeer", "rifleman",
         "legionaries", "spearmen", "pikemen", "musketeers", "riflemen", "veteran ",
         "north", "south", "east", "west", "spring", "summer", "autumn", "winter",
         "crude", "standard", "fine", "masterwork", "bronze", "iron", "steel", "and", "or", "now"]


def unescape(s):
    return s.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\\\", "\\")


def is_text(s):
    """Words for the player, not an id, a key, a path or a colour."""
    if s.startswith(("res://", "user://", "http", "#", "@", "HLBP")):
        return False
    core = re.sub(r'%[-+ 0-9.]*[sdfxX%]|\[/?[a-z_]+[^\]]*\]', ' ', s)
    words = re.findall(r'[A-Za-z]{2,}', core)
    if not words:
        return False
    if re.fullmatch(r'[a-z0-9_.:/@|,=+-]+', s):          # ids, keys, paths
        return False
    if re.fullmatch(r'[A-Z0-9_]*[_0-9][A-Z0-9_]*|[A-Z]{1,3}', s) or re.fullmatch(r'[A-Za-z]+_[A-Za-z0-9_]+', s):
        return False
    if re.fullmatch(r'[0-9a-fA-F]{6,8}', s):
        return False
    if " " in s.strip() or "\n" in s:
        return any(len(w) >= 3 for w in words) or len(words) >= 2
    # one word: capitalised words (labels such as "Workers") and words ending a sentence
    return bool(re.fullmatch(r'[A-Z][a-z\'-]+(?:[.:!?+]|\.\.\.)?|[A-Z][a-z]+ ?|[A-Z]{4,}', s)) or bool(re.fullmatch(r'[a-z]{3,}[.:!?]', s))


def script_strings(found):
    for path in sorted(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)):
        rel = os.path.relpath(path, ROOT)
        for line in open(path, encoding="utf-8"):
            if SKIP_LINE.match(line):
                continue
            # cut the comment
            code, instr, i = line, False, 0
            while i < len(code):
                ch = code[i]
                if instr:
                    if ch == "\\":
                        i += 2
                        continue
                    if ch == '"':
                        instr = False
                elif ch == '"':
                    instr = True
                elif ch == "#":
                    code = code[:i]
                    break
                i += 1
            for m in LIT.finditer(code):
                if SKIP_BEFORE.search(code[:m.start()]):
                    continue
                s = unescape(m.group(1))
                if is_text(s):
                    found.setdefault(s, rel)


def data_strings(found):
    def walk(x, key, src):
        if isinstance(x, dict):
            for k, v in x.items():
                walk(v, k, src)
        elif isinstance(x, list):
            for v in x:
                walk(v, key, src)
        elif isinstance(x, str) and key in TEXT_KEYS and (is_text(x) or (key in ("title", "plural") and x)):
            found.setdefault(x, src)
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "*.json"))):
        name = os.path.basename(path)
        if name.startswith(("lang_", "map_")):
            continue
        d = json.load(open(path, encoding="utf-8"))
        walk(d, "", "data/" + name)
        if name == "techs.json":
            for a in d.get("ages", []):
                found.setdefault(a, "data/" + name)
            for ln in d.get("lanes", []):
                found.setdefault(ln[1], "data/" + name)


def strings():
    found = {}
    script_strings(found)
    data_strings(found)
    for w in WORDS:
        found.setdefault(w, "words")
    return found


def main():
    found = strings()
    files = sorted(glob.glob(os.path.join(ROOT, "data", "lang_*.json")))
    for f in files:
        d = json.load(open(f, encoding="utf-8"))
        done = sum(1 for k in found if d.get(k))
        print("%s: %d of %d texts translated" % (os.path.basename(f), done, len(found)))
        if "--missing" in sys.argv:
            for k in found:
                if not d.get(k):
                    print("   %s: %r" % (found[k], k))
        if "--report" in sys.argv or "--missing" in sys.argv:
            continue
        for k in found:
            d.setdefault(k, "")
        # texts no longer in the game are dropped (except the language's own name)
        d = {k: v for k, v in d.items() if k in found or k.startswith("_")}
        json.dump(dict(sorted(d.items())), open(f, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    if not files:
        print("%d texts found; no data/lang_*.json yet" % len(found))


if __name__ == "__main__":
    main()
