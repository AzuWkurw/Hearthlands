---
name: hearthlands-localization
description: Translate or check Hearthlands text in data/lang_*.json (Polish, German, new languages). Use when adding player-facing text, translating strings, fixing a wrong or missing translation, adding Polish plural forms, or reviewing a language file.
---

# Hearthlands localization

The game is written in English. Each `data/lang_<code>.json` maps the **exact English text** (the key)
to its translation. `scripts/i18n.gd` loads the files at start; `tools/extract_strings.py` collects the
text to translate. The simulation, event log and saves always stay English; text is translated only
where it is shown, so never translate inside sim code or saved data.

Read `scripts/i18n.gd` first: the Polish work added a `Table` translation with templates and count
forms. If the file you have has no `Table` class, only exact matches work and the count forms below
do not exist yet.

## Workflow

1. Write new player-facing text in English in the scripts or data files, as usual.
   - Text with numbers or names in it: build it from one template, `tr("%d %s left") % [n, name]`
     or `"%s is finished." % name`, not by joining pieces. A template is one key; pieces are many keys
     that cannot be reordered in another language.
2. Run `python3 tools/extract_strings.py`. It adds new keys with an empty value to every
   `data/lang_*.json`. An empty value shows English.
3. Translate. See `python3 tools/extract_strings.py --missing` for what is left, and
   `--report` for how much each language has.
4. Check with the commands under "Checking".

## Rules for a translation

- **Keys are never edited by hand.** A key must be the English text byte for byte, including
  leading or trailing spaces (`"  you give"`), `\n` and BBCode tags. If the English changes, run
  the extractor; it adds the new key; delete the stale one.
- **Same placeholders, same order.** `%s`, `%d`, `%.1f`, `%02d` in the key must all appear in the
  translation, in the same order (`%%` for a percent sign when the English has one). If the
  sentence needs another order in Polish, change the English template instead.
- `%.0s` consumes a value and shows nothing. Use it where the English has a plural-`s` placeholder
  that Polish does not need: `"%d soldier%s"` → `"%d żołnierzy%.0s|..."`.
- **Keep markup.** BBCode (`[b]`, `[color=...]`, `[url=...]`) and line breaks stay where they are;
  only the words between them change.
- Keys starting with `_` are metadata. `"_language"` is the language's own name (`"Polski"`).
- Keep the file valid JSON, UTF-8, tab indented, keys sorted as the extractor writes them.
  Polish letters (ą ć ę ł ń ó ś ź ż) are written as themselves, not `\u` escapes.

## Polish count forms

A Polish value can hold four forms split by `|`: **name|one|few|many**.

- name: shown on its own, without a count (a list heading, a building panel).
- one: n = 1.
- few: n ends in 2, 3 or 4, except 12 to 14 (2, 3, 4, 22, 23, 24, 102 ...). Fractions also use it.
- many: everything else (0, 5 to 21, 25 to 31, 112 ...).

The game picks the form from the first number in the text. Examples from `data/lang_pl.json`:

```json
"Planks": "Deski|deska|deski|desek",
"woodsmen": "drwale|drwal|drwale|drwali",
"%d trees": "%d drzew|%d drzewo|%d drzewa|%d drzew",
"%d cycle%s": "%d cykli%.0s|%d cykl%.0s|%d cykle%.0s|%d cykli%.0s"
```

- Give all four or none. Exactly three `|` makes forms; any other count is shown as is, so a literal
  `"Lewo | prawo"` is safe but `"a|b|c"` would show the pipes.
- In a template with forms, every form repeats all the placeholders.
- Mass nouns still need four forms: `"Water": "Woda|woda|wody|wody"`.
- Check each form in a sentence: "1 deska, 2 deski, 5 desek, 12 desek, 22 deski".

## Polish style

- Informal "ty" to the player, as in the rest of the file ("twój lud").
- Buttons and menu items: infinitive or noun ("Zapisz grę", "Ustawienia"), short.
- Polish text is often 20 to 40% longer than English. Keep button and tooltip text short; the
  screenshot step below shows overflow.
- Same English word, same Polish word everywhere. Search the file for an existing translation of a
  term before choosing a new one (resources, buildings, unit names, ages).

## Checking

```bash
python3 tools/extract_strings.py --report     # coverage per language
python3 tools/check_data.py                   # data files are valid
godot --headless --script res://tools/lang_test.gd          # templates, forms, switching languages
xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
  --script res://tools/shot_lang.gd -- out=/tmp/shots     # screenshots in Polish, look for overflow
```

Quick placeholder check for one language file (run from the repo root):

```bash
python3 - data/lang_pl.json <<'EOF'
import json, re, sys
ph = re.compile(r"%(?:%|[-+0-9.]*[sdf])")
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k, v in d.items():
    if k.startswith("_") or not v:
        continue
    forms = v.split("|") if v.count("|") == 3 else [v]
    want = [p for p in ph.findall(k) if p != "%%"]
    for f in forms:
        got = [("%s" if p == "%.0s" else p) for p in ph.findall(f) if p != "%%"]
        if got != want:
            print(f"{k!r}: {f!r} has {got}, English has {want}")
EOF
```

## Adding a new language

Copy the key list from an existing file with empty values (or run the extractor after creating
`data/lang_<code>.json` with `{"_language": "<own name>"}`), then translate. Players can also drop a
file with the same name into the mods folder (`user://data/`); its entries override the built-in ones.
The count-form rule in `i18n.gd` is Polish; a language with other plural rules needs its own rule there.
