# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Hearthlands is an economy and conquest game in **Godot 4.3** (standard build, GDScript only, no .NET, no
addons). `main.tscn` holds one `Main` node; the whole interface is built in code by `scripts/main.gd`.
Almost every script has a `class_name`, so classes (`Sim`, `SimLogistics`, `GameData`, `Version`...) are
used globally without autoloads.

Deeper docs: `docs/SOURCE_GUIDE.md` (system-by-system explanation and a "where things are" index; its
header says build 32 but the architecture still holds), `docs/FILES.md` (every source file, regenerate
with `python3 tools/file_list.py`), `README.md` (player docs, data-mod field tables, Feature hook table).

## Commands

Godot must be on the PATH as `godot` (or set `GODOT=/path/to/godot`).

```
godot --headless --script res://tools/NAME.gd [-- key=value ...]   # run one test / tool
python3 tools/run_all.py                 # every test (~10 min); exit code 0 = all passed
python3 tools/run_all.py quick           # the fast subset (~3 min)
python3 tools/run_all.py save door       # only tests whose name or script contains these words
python3 tools/check_data.py [modsdir]    # validate data/*.json (prints "data check: ok")
```

- Tests are `extends SceneTree` scripts in `tools/` that build a `Sim` headlessly and print `ok`/`FAIL`
  lines plus a final marker (e.g. `ECON TEST: PASS`). `run_all.py` holds the list of tests and the regex
  each output must match; a new test must be added to its `TESTS` table. Any `SCRIPT ERROR` fails a test.
- Tests not in `BRONZE_AWARE` in `run_all.py` run with `HEARTHLANDS_START_AGE=1` (start in the Roman age,
  as before build 65). Set it yourself when running such a test by hand.
- Tests flagged as needing a window (and all `shot_*.gd` screenshot scripts) need a display:
  `xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/X.gd`.
- After **any** simulation change run `save_test` (must report three `true` matches). After touching goods,
  `stores_test`. For pure refactors, `checksum_run.gd` before and after must print identical numbers;
  `checksum_diff.gd` finds the first field that differs after a load.
- Performance: `perf_test.gd`, `bench.gd`, `late_bench.gd`, `testbench.gd` (`-- mins=60`), `ai_bench.gd`.

### Releases

`python3 tools/make_build.py [--minor|--fix] "Notes"` does a whole release: bumps the version
(`scripts/version.gd`, `project.godot`, `export_presets.cfg`, a new `CHANGELOG.md` entry via
`tools/bump_build.py`), checks data, exports Windows and Linux, smoke-runs the export, zips to `../build`,
and commits. `--dry-run` shows the steps, `--tests` runs all tests first. Pushing a change to
`scripts/version.gd` on `main` triggers `.github/workflows/release.yml`, which builds and publishes a
GitHub Release. The welcome screen shows the newest CHANGELOG entry; add its Polish version at the top of
`CHANGELOG_pl.md` (same format, heading `## Wersja N`), or Polish players see it in English. Per build, the README's roadmap table and relevant sections are updated too; run
`python3 tools/readme_tables.py` after changing buildings, goods or techs (it regenerates the README tables).

## Architecture

**Simulation vs. interface.** `Sim` (`scripts/sim.gd`, a `RefCounted`) owns all game state and rules and
knows nothing about drawing, which is why every test runs headless. `Main` reads the sim and calls its
methods (`place`, `build_road`, ...); `_process` calls `sim.tick(Sim.TICK)` (0.1 game s) as often as the
speed setting asks. `Sim` delegates to modules that each hold a back-reference to it: `sim_production`
(work cycles, construction sites), `sim_people` (jobs, homes, needs, food), `sim_logistics` (roads,
stores, carriers; the largest and most performance-sensitive), `sim_military`, `sim_research`, `sim_ai`
(rival plan in `ai_think`'s `steps`), `sim_sea`, `sim_navy`, `sim_rail`, `sim_market`, `sim_arms`, plus
`diplomacy.gd`. The UI is `main.gd` plus one `ui_*.gd` helper per window/panel; `map_view.gd` renders
the world (with `map_chunks.gd` baking terrain into 16x16-tile images).

**State shape.** Map data is flat per-tile arrays indexed `y * w + x` (`ter`, `deco`, `amt`, `ore`,
`owner`, `road`, `bmap`, `plot`, `height`...). Entities are inner classes `Player`, `Bld`, `Trip`, `Attack`.
Buildings sleep until `b.retry`, so idle buildings cost nothing per tick.

**Goods.** `p.stock` is only a cached total of the realm's stores; the goods live in each store's `inv`.
Always change goods through `sim.give(p, res, n, at)` / `sim.take(...)`, never by writing `p.stock`.

**Determinism is a hard rule** (saves, `save_test`, and checksums depend on it):
- Game randomness only from `sim.rng` (seeded and saved). `randf()` etc. only for visuals/sound.
- Anything affecting outcomes must be saved or recomputed identically from saved state. Caches must be
  keyed by a version counter (`net_ver`, `_store_ver`) or the current tick.
- Iterated collections need stable order (buildings in id order; sort dictionaries where order matters).
- Road searches round distances to 32-bit and break ties by lower tile index (`SimLogistics._f32`).

**Saves.** `Sim.to_save()` dumps every `Bld`/`Player`/`Trip`/`Attack` via its property list, so a new `var`
on those classes is saved automatically; give it a default that suits older saves. Conversions for old
saves live in `Sim.from_save()` (comments start "saves from before build ..."). Old saves must keep
loading (`oldsave_test.gd`, `load_saves_test.gd`).

**Data-driven content.** Buildings, goods, techs, needs and trades are in `data/*.json`, loaded and merged
with the player's `user://data/` mod files by `game_data.gd`. Balance changes are usually data edits.
A new building: add it to `buildings.json`, run `python3 tools/make_textures.py` to draw its texture, run
`readme_tables.py`, and add an `ai_think` step if rivals should build it. Texture/sound/music assets are
generated by the `tools/make_*.py` scripts.

**Optional features / script mods.** Systems like seasons, fog, geology, diseases, fires, wildlife and
contentment are `Feature` subclasses (`scripts/features/feature.gd`), registered in `BUILT_IN` in
`features/features.gd`; the sim calls their hooks (`on_second`, `speed_bonus`, `work_block`, `draw_map`,
`save_state`/`load_state`, ...; full table in the README) for each enabled feature. Data entries can carry
`"feature": "<id>"` to hide them while that feature is off. Mods in `user://mods/` use the same API.

**Translations.** Interface text is English source strings; `data/lang_<code>.json` maps them to
translations. Labels whose text is exactly a key are translated automatically; text with numbers goes
through `tr("... %d ..." % n)` (format inside `tr`). Polish is the one translation, chosen on the new-game
screen or in Settings. The simulation, event log and saves always stay English (game logic matches on
those messages); text is translated only when shown, by `I18n.Table` in `scripts/i18n.gd`, which also
matches `%s`/`%d` keys as templates and picks Polish plural forms from `"a|b|c|d"` values. Run
`python3 tools/extract_strings.py` (`--missing` lists untranslated text) to collect new strings;
`check_data.py` checks placeholders and plural forms, and `lang_test` covers the switch.

## Conventions

- GDScript uses tabs and static typing; doc comments use `##`. Comments and docs are written in plain,
  everyday English describing what happens in the game.
- Don't mention or compare to other games in code, UI text, README or changelog (removed in build 75.1).
