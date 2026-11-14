#!/usr/bin/env python3
"""Writes docs/FILES.md: every source file of the project with what it is for.

The description of a .gd file is its opening "##" comment (the lines after `class_name`/`extends`),
of a .py file its docstring's first paragraph; data files and the rest are described below by hand.
Run it again after adding or changing files:  python3 tools/file_list.py
"""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HAND = {
    "project.godot": "Godot project settings: name, version, main scene, window and renderer options.",
    "main.tscn": "The one scene: a Node with scripts/main.gd, which builds the whole interface in code.",
    "export_presets.cfg": "Godot export settings for the Windows and Linux builds.",
    "README.md": "How to play, the rules, controls, settings, modding and the project layout.",
    "CHANGELOG.md": "What changed in each build.",
    "docs/SOURCE_GUIDE.md": "A tour of the code for programmers: the parts, how a game tick runs, where things live.",
    "docs/SUGGESTIONS.md": "Ideas and their status after each round of work.",
    "docs/FILES.md": "This list (written by tools/file_list.py).",
    "data/buildings.json": "Every building: name, group, size, cost, build time, worker, inputs and outputs, work cycle, garrison, store room, art style and info text.",
    "data/resources.json": "Every good: name, icon shape, colour, store room and info.",
    "data/techs.json": "The research tree: techs, ages, costs, what each unlocks or improves.",
    "data/trades.json": "The trades (woodland, mining, farming...): their names, tools and levels.",
    "data/needs.json": "What each class of people (peasants, artisans, nobles, soldiers) uses up to stay content.",
    "data/missions.json": "The missions: story, map or seed, rivals, options, time limit and goals.",
    "data/campaign.json": "The campaign: its chapters, their place on the campaign map, story before and after, what carries over, and the mission of each.",
    "data/map_iron_coast.json": "The hand-made map of the Iron Coast mission (made by tools/make_mission_map.gd).",
    "data/lang_de.json": "German translation of the interface.",
    "shaders/ground.gdshader": "Draws the ground: the baked map pictures on the raised mesh, moving water and shore foam, drifting cloud shadows.",
    "shaders/map_sway.gdshader": "The map view's own shader: bends the tops of trees and crops in the wind (corners marked by their colour's alpha).",
    "mods_examples/bountiful_harvest.gd": "A small example mod: a feature that makes farms faster (copy it to the mods folder).",
}

GROUPS = [
    ("Game: simulation", lambda p: p.startswith("scripts/sim") or p in ("scripts/diplomacy.gd", "scripts/world_gen.gd", "scripts/game_data.gd", "scripts/crops.gd")),
    ("Game: features (switchable in Settings)", lambda p: p.startswith("scripts/features/")),
    ("Game: map drawing", lambda p: p in ("scripts/map_view.gd", "scripts/map_chunks.gd", "scripts/minimap.gd", "scripts/tex.gd", "scripts/tech_tree_view.gd", "scripts/line_chart.gd")),
    ("Game: interface", lambda p: p.startswith("scripts/")),
    ("Data", lambda p: p.startswith("data/")),
    ("Shaders", lambda p: p.startswith("shaders/")),
    ("Tools: automatic tests", lambda p: p.startswith("tools/") and (p.endswith("_test.gd") or p.endswith("run_all.py"))),
    ("Tools: screenshots", lambda p: p.startswith("tools/") and "shot" in os.path.basename(p)),
    ("Tools: benchmarks and diagnostics", lambda p: p.startswith("tools/") and p.endswith(".gd")),
    ("Tools: making textures, sounds and releases", lambda p: p.startswith("tools/")),
    ("Project and documents", lambda p: True),
]


def gd_desc(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    out = []
    for ln in lines[:40]:
        s = ln.strip()
        if s.startswith("##"):
            out.append(s[2:].strip())
        elif out:
            break
        elif s.startswith(("class_name", "extends", "@tool", "")) or s == "":
            continue
        else:
            break
    return " ".join(out)


def py_desc(path):
    src = open(path, encoding="utf-8").read()
    m = re.search(r'"""(.*?)"""', src, re.S)
    if not m:
        return ""
    para = m.group(1).strip().split("\n\n")[0]
    return " ".join(x.strip() for x in para.splitlines())


def files():
    out = []
    for d, dirs, fs in os.walk(ROOT):
        rel = os.path.relpath(d, ROOT)
        if rel.startswith((".git", ".godot", "textures", "sounds")) or "__pycache__" in rel:
            continue
        for f in sorted(fs):
            p = os.path.normpath(os.path.join(rel, f)).replace("\\", "/")
            if p.startswith("./"):
                p = p[2:]
            if f.endswith((".gd", ".py", ".json", ".gdshader", ".md", ".tscn", ".cfg", ".godot")):
                out.append(p)
    return sorted(out)


def lines_of(path):
    with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as fh:
        return sum(1 for _ in fh)


def main():
    by_group = {g[0]: [] for g in GROUPS}
    missing = []
    for p in files():
        full = os.path.join(ROOT, p)
        desc = HAND.get(p) or (gd_desc(full) if p.endswith(".gd") else py_desc(full) if p.endswith(".py") else "")
        if not desc:
            missing.append(p)
            desc = "(no description yet)"
        for name, test in GROUPS:
            if test(p):
                by_group[name].append((p, desc))
                break
    n_tex = len([f for f in os.listdir(os.path.join(ROOT, "textures")) if f.endswith(".png")])
    n_snd = len([f for f in os.listdir(os.path.join(ROOT, "sounds")) if not f.endswith(".import")])
    n_mus = len([f for f in os.listdir(os.path.join(ROOT, "music")) if f.endswith(".ogg")])
    total = sum(len(v) for v in by_group.values())
    out = ["# Hearthlands source files", "",
           "Every source file with what it is for, grouped by part. Written by `tools/file_list.py` from the comment at the",
           "top of each file; run it again after adding files. For how the parts work together, read",
           "`docs/SOURCE_GUIDE.md`. Besides these %d files there are %d pictures in `textures/` (made by" % (total, n_tex),
           "`tools/make_textures.py` and `tools/make_scenery.py`, or your own) and %d sounds in `sounds/` (made by" % n_snd,
           "`tools/make_sounds.py`) and %d pieces of music in `music/` (made by `tools/make_music.py`). Godot's" % n_mus,
           "`.import` files next to them are made by the editor.", ""]
    for name, _ in GROUPS:
        rows = by_group[name]
        if not rows:
            continue
        out.append("## %s" % name)
        out.append("")
        out.append("| File | Lines | What it is |")
        out.append("|---|---:|---|")
        for p, d in rows:
            out.append("| `%s` | %d | %s |" % (p, lines_of(p), d.replace("|", "\\|")))
        out.append("")
    open(os.path.join(ROOT, "docs", "FILES.md"), "w", encoding="utf-8").write("\n".join(out))
    print("docs/FILES.md: %d files, %d without a description" % (total, len(missing)))
    for m in missing:
        print("  no description:", m)


if __name__ == "__main__":
    main()
