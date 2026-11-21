#!/usr/bin/env python3
"""Run every automatic test and say which passed.

    python3 tools/run_all.py            all tests (about 10 minutes on a desktop)
    python3 tools/run_all.py quick      only the fast ones (about 3 minutes)
    python3 tools/run_all.py save door  only the tests whose names contain these words

Needs `godot` (4.3) on the PATH, or set GODOT=/path/to/godot. Tests that open the game window need a
display; on Linux without one they run under xvfb-run when it is installed, otherwise they are skipped.
Exit code 0 when everything that ran passed, 1 otherwise, so it can run in CI.
"""
import os, re, shutil, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "godot")

# name, script, extra args, needs a window, quick?, patterns that must appear (regex)
TESTS = [
	("data files",        None, [], False, True, []),
	("save and load",     "save_test", [], False, True, [r"match after load: true", r"match after 5 more minutes: true", r"checksum match after 5 more minutes: true"]),
	("goods in stores",   "stores_test", ["mins=8"], False, True, [r"stock = sum of stores all game: yes"]),
	("entrances",         "door_test", [], False, True, [r"door test: \d+ ok, 0 bad"]),
	("walking people",    "walk_test", [], False, True, [r"garrison [1-9]"]),
	("site materials",    "site_test", [], False, True, [r"site trip-ticks seen [1-9]"]),
	("full stores",       "full_test", [], False, True, [r"after using them: well: Working"]),
	("garrisons",         "garrison_test", [], False, False, [r"attack: '' marching"]),
	("field battles",     "field_test", [], False, False, [r"first side wins"]),
	("research",          "research_test", [], False, False, [r"load: '' reps"]),
	("new-game options",  "options_test", [], False, False, [r"all research: techs 169 of 170", r"creative stores"]),
	("reachable spots",   "reach_test", [], False, True, [r"reach test: \d+ ok, 0 bad"]),
	("store transfers",   "transfer_test", [], False, False, [r"transfer test: ok"]),
	("road carriers",     "stretch_test", [], False, False, [r"stretch test: ok"]),
	("missions and maps", "mission_test", [], False, False, [r"mission test: ok"]),
	("mission events",    "script_test", [], False, False, [r"SCRIPT TEST: PASS"]),
	("ships and harbours", "sea_test", ["seed=bay"], False, False, [r"sea test: ok"]),
	("catapults",         "catapult_test", [], False, True, [r"catapult test: ok"]),
	("boundary stones",   "claim_test", [], False, True, [r"claim test: ok"]),
	("trade by cart",     "trade_test", [], False, True, [r"trade test: ok"]),
	("choices and allies", "choice_test", [], False, False, [r"choice test: ok"]),
	("luxuries",          "luxury_test", [], False, False, [r"luxury test: ok"]),
	("wonders",           "wonder_test", [], False, False, [r"wonder test: ok"]),
	("station upgrade",   "station_upgrade_test", [], False, True, [r"STATION UPGRADE TEST: PASS"]),
	("sea war",           "sea_war_test", [], False, True, [r"SEA WAR TEST: PASS"]),
	("navy",              "navy_test", [], False, True, [r"NAVY TEST: PASS"]),
	("economy",           "econ_test", [], False, True, [r"ECON TEST: PASS"]),
	("priority sets",     "prio2_test", [], False, True, [r"PRIO2 TEST: PASS"]),
	("world and weather", "world_test", [], False, True, [r"WORLD TEST: PASS"]),
	("saves, size, notices", "qol_test", [], False, True, [r"QOL TEST: PASS"]),
	("gunpowder",         "powder_test", [], False, True, [r"POWDER TEST: PASS"]),
	("priorities",        "priorities_test", [], False, True, [r"PRIORITIES TEST: PASS"]),
	("age paths",         "age_bonus_test", [], False, False, [r"age bonus test: ok"]),
	("bridges",           "bridge_test", [], False, True, [r"bridge test: ok"]),
	("taverns and contentment", "content_test", [], False, True, [r"content test: ok"]),
	("archers and sallies", "archer_test", [], False, True, [r"archer test: ok"]),
	("weapons wear out",  "weapon_test", [], False, True, [r"WEAPON TEST: PASS"]),
	("crops and seeds",   "crop_test", [], False, True, [r"CROP TEST: PASS"]),
	("columns and water", "march_test", [], False, True, [r"MARCH TEST: PASS"]),
	("upgrades and war",  "mil2_test", [], False, False, [r"MIL2 TEST: PASS"]),
	("workers and editor", "econ2_test", [], False, True, [r"ECON2 TEST: PASS"]),
	("map editor",        "editor_test", [], True, True, [r"EDITOR TEST: PASS"]),
	("ruins and bandits", "places_test", [], False, True, [r"PLACES TEST: PASS"]),
	("sound and music",   "sound_test", [], True, True, [r"SOUND TEST: PASS"]),
	("campaign",          "campaign_test", [], True, False, [r"campaign test: ok"]),
	("spreading fires",   "fire_test", [], False, True, [r"fire test: ok"]),
	("small touches",     "touches_test", [], True, False, [r"touches test: ok"]),
	("fog after loading", "fogsave_test", [], True, False, [r"after 3 s: (\d+)"]),
	("coast defended",    "coast_test", [], False, False, [r"COAST TEST: PASS"]),
	("town quarters",     "town_test", [], False, False, [r"TOWN TEST: PASS"]),
	("market orders",     "route_test", [], False, False, [r"ROUTE TEST: PASS"]),
	("guilds and queue",  "guild_test", [], False, False, [r"GUILD TEST: PASS"]),
	("sandbox goals",     "goals_test", [], False, False, [r"GOALS TEST: PASS"]),
	("steam and rails",   "rail_test", [], False, False, [r"RAIL TEST: PASS"]),
	("the Bronze Age",    "bronze_test", [], False, False, [r"BRONZE TEST: PASS"]),
	("tools and arms by metal", "arms_test", [], False, False, [r"ARMS TEST: PASS"]),
	("blueprints",        "bp_test", [], False, False, [r"BLUEPRINT TEST: PASS"]),
	("toolbar tools",     "toolbar_tool_test", [], True, False, [r"tool clicks answered: 8 of 8"]),
]


# tests written for the Bronze Age itself; the older ones start their games in the Roman age, as
# games did before build 65 (Sim.new_game reads HEARTHLANDS_START_AGE)
BRONZE_AWARE = {"bronze_test", "save_test", "arms_test", "script_test"}


def run(cmd, timeout, env=None):
	try:
		p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout, env=env)
		return p.stdout + p.stderr
	except subprocess.TimeoutExpired:
		return "TIMEOUT"


def main():
	args = sys.argv[1:]
	quick = "quick" in args
	words = [a for a in args if a != "quick"]
	xvfb = shutil.which("xvfb-run")
	has_display = bool(os.environ.get("DISPLAY")) or sys.platform in ("win32", "darwin")
	results = []
	for name, script, extra, window, is_quick, pats in TESTS:
		if quick and not is_quick:
			continue
		if words and not any(w in name or (script and w in script) for w in words):
			continue
		t0 = time.time()
		if script is None:
			out = run([sys.executable, os.path.join(ROOT, "tools", "check_data.py")], 120)
			ok = "data check: ok" in out
		else:
			if not os.path.exists(os.path.join(ROOT, "tools", script + ".gd")):
				results.append((name, "MISSING", 0.0, ""))
				continue
			cmd = [GODOT]
			if window:
				if not has_display and xvfb:
					cmd = [xvfb, "-a", "-s", "-screen 0 1920x1080x24", GODOT]
				elif not has_display:
					results.append((name, "SKIPPED", 0.0, "no display"))
					continue
				cmd += ["--rendering-driver", "opengl3"]
			else:
				cmd += ["--headless"]
			cmd += ["--script", "res://tools/%s.gd" % script]
			if extra:
				cmd += ["--"] + extra
			env = dict(os.environ)
			if script not in BRONZE_AWARE:
				env["HEARTHLANDS_START_AGE"] = "1"
			out = run(cmd, 900, env)
			ok = out != "TIMEOUT" and "SCRIPT ERROR" not in out and all(re.search(p, out) for p in pats)
		why = ""
		if not ok:
			lines = [l for l in out.splitlines() if "SCRIPT ERROR" in l or "ERROR" in l]
			why = (lines[0] if lines else out.strip().splitlines()[-1] if out.strip() else "no output")[:110]
		results.append((name, "PASS" if ok else "FAIL", time.time() - t0, why))
		print("%-20s %-7s %5.0f s  %s" % results[-1], flush=True)
	failed = [r for r in results if r[1] == "FAIL" or r[1] == "MISSING"]
	print("\n%d passed, %d failed, %d skipped" % (sum(1 for r in results if r[1] == "PASS"), len(failed), sum(1 for r in results if r[1] == "SKIPPED")))
	sys.exit(1 if failed else 0)


if __name__ == "__main__":
	main()
