#!/usr/bin/env python3
"""Rebuilds the Resources, Buildings and Research tree tables in README.md from the data files.

Usage:  python3 tools/readme_tables.py
Everything between "## Resources" and "## Custom textures" is replaced, so edit the data, not the tables.
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    return json.load(open(os.path.join(ROOT, "data", name)))


res = load("resources.json")
bld = load("buildings.json")
techs = load("techs.json")
trades = load("trades.json")
names = {r["id"]: r["name"] for r in res}
names.update({"food": "food", "research": "research"})
ages = techs.get("ages", [])
tech = {t["id"]: t for t in techs["techs"]}


def goods(d):
    return ", ".join("%d %s" % (n, names.get(k, k).lower()) for k, n in d.items()) or "–"


def research_of(b):
    t = b.get("tech")
    if not t:
        return "%s (start)" % ages[0]
    return tech[t]["name"] if t in tech else t


def effect(eff):
    out = []
    for k, v in eff.items():
        pct = "%+d%%" % round(v * 100)
        if k.startswith("speed:trade:"): out.append("%s workers %s speed" % (trades.get(k[12:], {}).get("name", k[12:]).lower(), pct))
        elif k == "xp": out.append("workers learn %s faster" % pct)
        elif k == "food": out.append("people eat %s" % pct)
        elif k == "need": out.append("artisans and nobles use %s goods" % pct)
        elif k == "store": out.append("store room %s" % pct)
        elif k == "housing": out.append("housing %s" % pct)
        elif k == "immigration": out.append("newcomers arrive %s faster" % pct)
        elif k == "vein": out.append("%d%% of mining leaves the vein untouched" % round(v * 100))
        elif k == "tool_save": out.append("%d%% of new workers need no new tool" % round(v * 100))
        elif k.startswith("speed:cat:"): out.append("%s buildings %s speed" % (k[10:], pct))
        elif k == "speed:all": out.append("all production %s" % pct)
        elif k == "speed:worker:artisan": out.append("artisan workshops %s" % pct)
        elif k.startswith("speed:"): out.append("%s %s speed" % (bld.get(k[6:], {}).get("name", k[6:]), pct))
        elif k.startswith("out:"): out.append("%s +%d output" % (bld.get(k[4:], {}).get("name", k[4:]), v))
        elif k == "tax": out.append("gold tax %s" % pct)
        elif k == "research": out.append("research %s" % pct)
        elif k == "carry": out.append("carrier speed %s" % pct)
        elif k == "build": out.append("build speed %s" % pct)
        elif k == "attack": out.append("attack odds %s" % pct)
        elif k == "defense": out.append("defence odds %s" % pct)
        else: out.append("%s %s" % (k, pct))
    return ", ".join(out) or "–"


L = []
L.append("## Resources (%d)\n" % len(res))
food = [r["name"] for r in res if "food" in r]
L.append(", ".join(r["name"] for r in res) + ".\n")
L.append("Food (everyone eats it, cheapest first): " + ", ".join(food) + ".\n")
buildable = [k for k, b in bld.items() if k != "hq"]
L.append("## Buildings (%d you can build)\n" % len(buildable))
cats = [("raw", "Raw"), ("food", "Food"), ("industry", "Industry"), ("crafts", "Crafts"), ("folk", "Folk"),
        ("science", "Science"), ("logistics", "Roads & stores"), ("mil", "Military")]
for cid, cname in cats:
    rows = [(k, b) for k, b in bld.items() if b.get("cat") == cid and k != "hq"]
    if not rows:
        continue
    L.append("**%s**\n" % cname)
    L.append("| Building | Cost | Worker (trade) | Uses | Makes | Research |")
    L.append("|---|---|---|---|---|---|")
    for k, b in rows:
        w = b.get("worker")
        tr = b.get("trade", b.get("cat"))
        worker = "%s (%s)" % (w, trades.get(tr, {}).get("name", tr).lower()) if w else "–"
        makes = goods(b.get("out", {}))
        if "garrison" in b:
            makes = "claims %d tiles, holds %d" % (b.get("radius", 6), b["garrison"])
            if b.get("wall"):
                makes += ", walls +%d%%" % round(b["wall"] * 100)
            if b.get("cannon"):
                makes += ", %d cannon (range %d)" % (b["cannon"][2], b["cannon"][0])
        elif "store" in b:
            makes = "room for %d of each good, %d porters" % (b["store"], b.get("porters", 0))
        elif "carriers" in b:
            c = b["carriers"]
            makes = "%d %ss carrying %d within %d tiles" % (c["count"], c["kind"], c["load"], c["range"])
        elif "makes_tools" in b:
            makes = "%d tools, the kind most wanted" % b["makes_tools"] + ((", " + goods(b["out"])) if b.get("out") else "")
        elif "train" in b:
            makes = ("trains an " if b["train"][0] in "aeiou" else "trains a ") + b["train"]
        elif "housing" in b:
            makes = "houses %d" % b["housing"]
        L.append("| %s | %s | %s | %s | %s | %s |" % (b["name"], goods(b.get("cost", {})), worker, goods(b.get("in", {})), makes, research_of(b)))
    L.append("")
L.append("## Research tree\n")
L.append("![Research tree](docs/research.png)\n")
L.append("| Age | Tech | Cost | Requires | Unlocks | Effect |")
L.append("|---|---|---|---|---|---|")
for t in techs["techs"]:
    req = ", ".join(tech[r]["name"] for r in t.get("requires", [])) or "–"
    unl = ", ".join(bld[u]["name"] for u in t.get("unlocks", []) if u in bld) or "–"
    L.append("| %s | %s | %d | %s | %s | %s |" % (ages[t.get("age", 0)], t["name"], t.get("cost", 0), req, unl, effect(t.get("effects", {}))))
L.append("")
if techs.get("repeatables"):
    L.append("### Mastery: repeatable studies\n")
    L.append("Each age has its own; they open when the realm enters that age. Each level costs half the first again.\n")
    L.append("| Age | Study | First level | Levels | Each level |")
    L.append("|---|---|---|---|---|")
    for r in techs["repeatables"]:
        L.append("| %s | %s | %d | %d | %s |" % (ages[r.get("age", 0)], r["name"], r.get("cost", 0), r.get("max", 1), effect(r.get("effects", {}))))
    L.append("")

p = os.path.join(ROOT, "README.md")
s = open(p).read()
a = s.index("## Resources")
e = s.index("## Custom textures")
open(p, "w").write(s[:a] + "\n".join(L) + "\n" + s[e:])
print("README tables rebuilt: %d resources, %d buildings, %d techs" % (len(res), len(buildable), len(techs["techs"])))
