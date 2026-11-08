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
	("new-game options",  "options_test", [], False, False, [r"all research: techs 131 of 132", r"creative stores"]),
	("reachable spots",   "reach_test", [], False, True, [r"reach test: \d+ ok, 0 bad"]),
	("store transfers",   "transfer_test", [], False, False, [r"transfer test: ok"]),
	("road carriers",     "stretch_test", [], False, False, [r"stretch test: ok"]),
	("catapults",         "catapult_test", [], False, True, [r"catapult test: ok"]),
	("fog after loading", "fogsave_test", [], True, False, [r"after 3 s: (\d+)"]),
	("toolbar tools",     "toolbar_tool_test", [], True, False, [r"tool clicks answered: 8 of 8"]),
]


def run(cmd, timeout):
	try:
		p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
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
			out = run(cmd, 1800)
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
