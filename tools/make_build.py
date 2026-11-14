#!/usr/bin/env python3
"""Make a release build of Hearthlands in one go.

Usage:
    python3 tools/make_build.py "What changed"              a fix build (build + 1)
    python3 tools/make_build.py --minor "What changed"      new features (0.34.0 -> 0.35.0)
    python3 tools/make_build.py --minor --notes-file notes.md
    python3 tools/make_build.py --fix "What was fixed"      a fix release of the last build (43 -> 43.1)

What it does, in order (any failed step stops it, and says which):
  1. raises the build number (tools/bump_build.py) and puts the notes into CHANGELOG.md
  2. checks the game data (tools/check_data.py); with --tests also runs every test (tools/run_all.py)
  3. imports the project and exports Hearthlands.exe (Windows) and, unless --no-linux, Linux
  4. starts the exported game for 120 frames and checks it ran without a script error
     (on Linux it uses xvfb-run when there is one; --no-check skips this)
  5. writes the Windows zip: Hearthlands.exe, READ_ME_FIRST.txt (from dist/windows, with this
     version, date and build filled in), CHANGELOG.md and "Start in OpenGL safe mode.bat"
  6. writes the source zip: the project without .git and .godot, in a folder Hearthlands-source,
     with FILES.md (tools/file_list.py) at its top
  7. commits "Build N (vX)" with the notes, when the project is a git repository (--no-commit skips)

Options:
    --godot PATH    the Godot 4.3 program (default: $GODOT, else "godot" on the PATH). On Windows,
                    e.g. --godot "C:/Godot/Godot_v4.3-stable_win64.exe"
    --out DIR       where the builds go (default: ../build next to the project)
    --major         raise the major version instead (0.34.0 -> 1.0.0)
    --tests         run all tests before exporting (slower)
    --no-linux      skip the Linux export
    --no-check      skip the 120-frame start check
    --no-commit     don't commit
    --dry-run       only print what it would do
    --no-bump       package the version as it is (no new build number, no changelog entry, no
                    commit): what the GitHub Actions release workflow runs for a pushed tag

Exporting needs Godot's export templates for 4.3 installed (in the Godot editor: Editor > Manage
Export Templates > Download and Install).
"""
import argparse
import datetime
import glob
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist", "windows")
SKIP_DIRS = {".git", ".godot", "__pycache__"}


def step(msg):
    print(f"\n== {msg}", flush=True)


def fail(msg):
    print(f"\nBUILD STOPPED: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd, dry, cwd=ROOT, check=True, capture=False, timeout=None):
    print("   $ " + " ".join(f'"{c}"' if " " in c else c for c in cmd), flush=True)
    if dry:
        return ""
    try:
        r = subprocess.run(cmd, cwd=cwd, text=True, timeout=timeout,
                           stdout=subprocess.PIPE if capture else None,
                           stderr=subprocess.STDOUT if capture else None)
    except FileNotFoundError:
        fail(f"could not start {cmd[0]} (is it installed, and on the PATH?)")
    except subprocess.TimeoutExpired:
        fail(f"{cmd[0]} took too long")
    if check and r.returncode != 0:
        if capture and r.stdout:
            print(r.stdout[-3000:])
        fail(f"{os.path.basename(cmd[0])} failed (exit code {r.returncode})")
    return r.stdout or ""


def version():
    src = open(os.path.join(ROOT, "scripts", "version.gd"), encoding="utf-8").read()
    num = re.search(r'const NUMBER := "([^"]+)"', src).group(1)
    build = int(re.search(r"const BUILD := (\d+)", src).group(1))
    fm = re.search(r"const FIX := (\d+)", src)
    fix = int(fm.group(1)) if fm else 0
    return num, (str(build) if fix == 0 else f"{build}.{fix}")


def project_files():
    """Every file of the project, as paths relative to ROOT, without .git and .godot."""
    out = []
    for d, dirs, files in os.walk(ROOT):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in sorted(files):
            out.append(os.path.relpath(os.path.join(d, f), ROOT))
    return out


def main():
    ap = argparse.ArgumentParser(description="Make a release build of Hearthlands.",
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("notes", nargs="?", default="", help="what changed (for CHANGELOG.md)")
    ap.add_argument("--notes-file")
    ap.add_argument("--minor", action="store_true")
    ap.add_argument("--major", action="store_true")
    ap.add_argument("--fix", action="store_true", help="a fix release of the last build: 43 -> 43.1")
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(ROOT), "build"))
    ap.add_argument("--tests", action="store_true")
    ap.add_argument("--no-linux", action="store_true")
    ap.add_argument("--no-check", action="store_true")
    ap.add_argument("--no-commit", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-bump", action="store_true", help="package the current version as it is")
    a = ap.parse_args()
    dry = a.dry_run

    notes = a.notes
    if a.notes_file:
        notes = open(a.notes_file, encoding="utf-8").read().strip()
    if not notes and a.no_bump:
        notes = "-"
        a.no_commit = True
    if not notes:
        fail('give the notes: what changed, e.g.  make_build.py --minor "Farms work real fields."')
    for f in ("READ_ME_FIRST.txt", "Start in OpenGL safe mode.bat"):
        if not os.path.exists(os.path.join(DIST, f)):
            fail(f"dist/windows/{f} is missing")
    py = sys.executable or "python3"
    out = os.path.abspath(a.out)
    win_dir = os.path.join(out, "windows")
    lin_dir = os.path.join(out, "linux")
    if not dry:
        os.makedirs(win_dir, exist_ok=True)
        os.makedirs(lin_dir, exist_ok=True)

    # 1. version and changelog
    old_num, old_build = version()
    step(f"1. Version (now v{old_num} build {old_build})")
    if a.no_bump:
        print("   (kept as it is)")
        num, build = old_num, old_build
    elif dry:
        print("   (would raise the build number)")
        num, build = old_num, "next"
    else:
        flag = ["--major"] if a.major else (["--minor"] if a.minor else (["--fix"] if a.fix else []))
        run([py, os.path.join("tools", "bump_build.py")] + flag + ["@@NOTES@@"], dry)
        cl_path = os.path.join(ROOT, "CHANGELOG.md")
        cl = open(cl_path, encoding="utf-8").read()
        open(cl_path, "w", encoding="utf-8").write(cl.replace("@@NOTES@@", notes, 1))
        num, build = version()
    today = datetime.date.today().isoformat()
    print(f"   -> v{num} build {build}, {today}")

    # 2. checks
    step("2. Checking the game data" + (" and running every test" if a.tests else ""))
    run([py, os.path.join("tools", "check_data.py")], dry)
    run([py, os.path.join("tools", "file_list.py")], dry)
    if a.tests:
        run([py, os.path.join("tools", "run_all.py")], dry)

    # 3. export
    step("3. Exporting")
    run([a.godot, "--headless", "--import"], dry, check=False, capture=True, timeout=900)
    exe = os.path.join(win_dir, "Hearthlands.exe")
    run([a.godot, "--headless", "--export-release", "Windows Desktop", exe], dry, capture=True, timeout=900)
    if not dry and not os.path.exists(exe):
        fail("the Windows export made no Hearthlands.exe (are the export templates installed?)")
    lin = os.path.join(lin_dir, "Hearthlands.x86_64")
    if not a.no_linux:
        run([a.godot, "--headless", "--export-release", "Linux", lin], dry, capture=True, timeout=900)

    # 4. start check: the exported game for 120 frames
    if not a.no_check:
        step("4. Starting the exported game for 120 frames")
        system = platform.system()
        game = exe if system == "Windows" else (lin if system == "Linux" and not a.no_linux else None)
        if game is None:
            print("   (skipped: no export for this system to start)")
        else:
            movie = tempfile.mkdtemp(prefix="hl_check_")
            cmd = [game, "--rendering-driver", "opengl3", "--write-movie", os.path.join(movie, "m.png"),
                   "--fixed-fps", "10", "--quit-after", "120"]
            if system == "Linux" and shutil.which("xvfb-run"):
                cmd = ["xvfb-run", "-a"] + cmd
            log = run(cmd, dry, check=False, capture=True, timeout=600)
            if not dry:
                frames = len(glob.glob(os.path.join(movie, "*.png")))
                errors = log.count("SCRIPT ERROR")
                shutil.rmtree(movie, ignore_errors=True)
                print(f"   {frames} frames, {errors} script errors")
                if frames < 120 or errors:
                    print(log[-3000:])
                    fail("the exported game did not run cleanly")

    # the newest changelog entry, for the release page (the GitHub Actions workflow uses it)
    if not dry:
        cl = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
        parts = cl.split("\n## ")
        latest = ("## " + parts[1]).strip() if len(parts) > 1 else ""
        open(os.path.join(out, "release_notes.md"), "w", encoding="utf-8").write(latest + "\n")

    # 5. Windows zip
    step("5. Windows zip")
    zip_win = os.path.join(out, f"Hearthlands-v{num}-build{build}-Windows.zip")
    if not dry:
        readme = open(os.path.join(DIST, "READ_ME_FIRST.txt"), encoding="utf-8").read()
        readme = readme.replace("{VERSION}", num).replace("{BUILD}", str(build)).replace("{DATE}", today)
        open(os.path.join(win_dir, "READ_ME_FIRST.txt"), "w", encoding="utf-8", newline="\r\n").write(readme)
        shutil.copy(os.path.join(ROOT, "CHANGELOG.md"), win_dir)
        shutil.copy(os.path.join(DIST, "Start in OpenGL safe mode.bat"), win_dir)
        with zipfile.ZipFile(zip_win, "w", zipfile.ZIP_DEFLATED) as z:
            for f in ("Hearthlands.exe", "READ_ME_FIRST.txt", "CHANGELOG.md", "Start in OpenGL safe mode.bat"):
                z.write(os.path.join(win_dir, f), f)
    print(f"   {zip_win}")

    # 6. source zip
    step("6. Source zip")
    zip_src = os.path.join(out, f"Hearthlands-v{num}-build{build}-Source.zip")
    if not dry:
        with zipfile.ZipFile(zip_src, "w", zipfile.ZIP_DEFLATED) as z:
            for rel in project_files():
                z.write(os.path.join(ROOT, rel), os.path.join("Hearthlands-source", rel))
            z.write(os.path.join(ROOT, "docs", "FILES.md"), "Hearthlands-source/FILES.md")
    print(f"   {zip_src}")

    # 7. commit
    if not a.no_commit and os.path.isdir(os.path.join(ROOT, ".git")):
        step("7. Commit")
        run(["git", "add", "-A"], dry)
        run(["git", "commit", "-q", "-m", f"Build {build} (v{num})\n\n{notes}"], dry)

    print(f"\nDone: v{num} build {build}")
    for f in (zip_win, zip_src):
        if os.path.exists(f):
            print(f"   {os.path.basename(f)}  {os.path.getsize(f) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
