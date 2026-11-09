#!/usr/bin/env python3
"""Check the data files (and optionally a mod's JSON files) for mistakes.

    python3 tools/check_data.py                 the game's own data/
    python3 tools/check_data.py path/to/mods    also check every .json in that folder, merged on top

Reports goods, techs, trades or features that do not exist, buildings missing a size or a picture style,
techs that require unknown techs, and research loops. Prints "data check: ok" when all is well.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZES = {"small", "medium", "large", "mine"}
CATS = {"raw", "food", "industry", "crafts", "folk", "science", "logistics", "mil", "special"}  # special: the headquarters
WORKERS = {"peasant", "artisan", "noble", "scout"}
FEATURES = {"statistics", "seasons", "clothing", "diseases", "events", "tool_quality", "fog", "geology", "wildlife", "contentment", "fires"}
VIRTUAL = {"food", "research", "ship"}  # "ship": a ship for the realm (sim_sea.gd)  # "food" in an input means any food; "research" out means research points


def load(name, mods):
	with open(os.path.join(ROOT, "data", name)) as f:
		data = json.load(f)
	for m in mods:
		p = os.path.join(m, name)
		if os.path.exists(p):
			with open(p) as f:
				extra = json.load(f)
			if isinstance(data, dict) and isinstance(extra, dict):
				data.update(extra)
			elif isinstance(data, list) and isinstance(extra, list):
				data += extra
	return data


def main():
	mods = sys.argv[1:]
	errs = []
	res = load("resources.json", mods)
	rids = {r["id"] for r in res}
	for r in res:
		for k in ("id", "name", "color", "icon"):
			if k not in r:
				errs.append("good %s: no %s" % (r.get("id", "?"), k))
	techs = load("techs.json", mods)
	tids = {t["id"] for t in techs["techs"]}
	for t in techs["techs"]:
		for q in t.get("requires", []):
			if q not in tids:
				errs.append("tech %s requires unknown tech %s" % (t["id"], q))
		if "feature" in t and t["feature"] not in FEATURES:
			errs.append("tech %s: unknown feature %s" % (t["id"], t["feature"]))
	# research loops
	req = {t["id"]: t.get("requires", []) for t in techs["techs"]}
	state = {}

	def visit(n, path):
		if state.get(n) == 1:
			errs.append("research loop: %s" % " -> ".join(path + [n]))
			return
		if state.get(n) == 2:
			return
		state[n] = 1
		for q in req.get(n, []):
			visit(q, path + [n])
		state[n] = 2
	for n in req:
		visit(n, [])
	trades = load("trades.json", mods)
	blds = load("buildings.json", mods)
	for bid, b in blds.items():
		if not isinstance(b, dict):
			continue
		where = "building %s" % bid
		for k in ("name", "cat", "size", "cost", "time", "art", "info"):
			if k not in b:
				errs.append("%s: no %s" % (where, k))
		if b.get("size") not in SIZES:
			errs.append("%s: size %r is not small, medium, large or mine" % (where, b.get("size")))
		if b.get("cat") not in CATS:
			errs.append("%s: group %r is unknown" % (where, b.get("cat")))
		if "style" not in b.get("art", {}):
			errs.append("%s: its art has no style (no picture can be drawn)" % where)
		for part in ("cost", "in", "out"):
			for g in b.get(part, {}):
				if g not in rids and g not in VIRTUAL:
					errs.append("%s: unknown good %r in %s" % (where, g, part))
		if "tech" in b and b["tech"] not in tids:
			errs.append("%s: unknown tech %s" % (where, b["tech"]))
		if "worker" in b and b["worker"] not in WORKERS:
			errs.append("%s: unknown worker class %s" % (where, b["worker"]))
		if "trade" in b and b["trade"] not in trades:
			errs.append("%s: unknown trade %s" % (where, b["trade"]))
		if "feature" in b and b["feature"] not in FEATURES:
			errs.append("%s: unknown feature %s" % (where, b["feature"]))
		if "cycle" in b and "worker" not in b:
			errs.append("%s: works in cycles but has no worker" % where)
	for e in errs:
		print("  " + e)
	print("data check: ok" if not errs else "data check: %d problem(s)" % len(errs))
	sys.exit(1 if errs else 0)


if __name__ == "__main__":
	main()
