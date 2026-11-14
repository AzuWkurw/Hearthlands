#!/usr/bin/env python3
"""Raise the build number before a release.

Usage:  python3 tools/bump_build.py "What changed"            # build + 1
        python3 tools/bump_build.py --minor "What changed"    # also 0.3.0 -> 0.4.0
        python3 tools/bump_build.py --major "What changed"    # also 0.3.0 -> 1.0.0
        python3 tools/bump_build.py --fix "What changed"      # a fix release: build 43 -> 43.1

Updates scripts/version.gd, project.godot (config/version), export_presets.cfg (Windows file and
product version) and adds an entry at the top of CHANGELOG.md.
"""
import datetime, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
note = args[0] if args else "No notes."
vpath = os.path.join(ROOT, "scripts", "version.gd")
src = open(vpath).read()
number = re.search(r'const NUMBER := "(\d+)\.(\d+)\.(\d+)"', src)
major, minor, patch = (int(g) for g in number.groups())
build = int(re.search(r"const BUILD := (\d+)", src).group(1))
fm = re.search(r"const FIX := (\d+)", src)
fix = int(fm.group(1)) if fm else 0
if "--fix" in sys.argv:
    fix += 1
else:
    build += 1
    fix = 0
if "--major" in sys.argv:
    major, minor, patch = major + 1, 0, 0
elif "--minor" in sys.argv:
    minor, patch = minor + 1, 0
version = f"{major}.{minor}.{patch}"
today = datetime.date.today().isoformat()
src = re.sub(r'const NUMBER := "[^"]*"', f'const NUMBER := "{version}"', src)
src = re.sub(r"const BUILD := \d+", f"const BUILD := {build}", src)
src = re.sub(r"const FIX := \d+", f"const FIX := {fix}", src)
label = str(build) if fix == 0 else f"{build}.{fix}"
src = re.sub(r'const DATE := "[^"]*"', f'const DATE := "{today}"', src)
open(vpath, "w").write(src)
four = f"{version}.{build}"
ppath = os.path.join(ROOT, "project.godot")
proj = open(ppath).read()
if "config/version=" in proj:
    proj = re.sub(r'config/version="[^"]*"', f'config/version="{four}' + (f'.{fix}' if fix else '') + '"', proj)
else:
    proj = proj.replace('config/name="Hearthlands"', f'config/name="Hearthlands"\nconfig/version="{four}"')
open(ppath, "w").write(proj)
epath = os.path.join(ROOT, "export_presets.cfg")
if os.path.exists(epath):
    exp = open(epath).read()
    for key in ("application/file_version", "application/product_version"):
        if key + "=" in exp:
            exp = re.sub(re.escape(key) + r'="[^"]*"', f'{key}="{four}"', exp)
        else:
            exp = exp.replace('application/product_name="Hearthlands"', f'application/product_name="Hearthlands"\n{key}="{four}"')
    open(epath, "w").write(exp)
cpath = os.path.join(ROOT, "CHANGELOG.md")
log = open(cpath).read() if os.path.exists(cpath) else "# Changelog\n"
head, _, rest = log.partition("\n")
entry = f"\n## Build {label} (v{version}, {today})\n\n{note}\n"
open(cpath, "w").write(head + "\n" + entry + rest)
print(f"Now v{version} build {label}")
