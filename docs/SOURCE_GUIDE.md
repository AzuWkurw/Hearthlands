# Hearthlands source guide

Version 0.27.0, build 32. This guide explains how the source is organised and how the main systems
work, so you (or anyone helping you) can find your way around and change things safely.
`README.md` describes the game for players; `docs/SUGGESTIONS.md` lists what could be improved next.

---

## 1. Opening and running the project

1. Install **Godot 4.3** (standard build, not .NET). Newer 4.x versions should work, but 4.3 is what
   every build so far was made and tested with.
2. In Godot's Project Manager choose **Import**, pick `project.godot` in this folder, and open it.
   The first import takes a minute (about 900 textures and 40 sounds).
3. Press **F5** to play. The main scene is `main.tscn`, which holds a single `Main` node; everything
   else (the map, the side panel, the toolbar, every window) is built in code by `scripts/main.gd`.

The game draws with OpenGL by default. Settings can switch to Vulkan; see section 9.

### Exporting

`export_presets.cfg` has two presets, **Windows Desktop** and **Linux**. Export templates for 4.3 must
be installed (Editor > Manage Export Templates). From the command line:

```
godot --headless --export-release "Windows Desktop"
godot --headless --export-release "Linux"
```

They write to `../build/windows/Hearthlands.exe` and `../build/linux/Hearthlands.x86_64`.

### The release routine used for every build

1. `python3 tools/bump_build.py --minor "x"` for a build with new features (raises the version and the
   build number), or without `--minor` for a fix-only build (raises only the build number). It adds a
   heading to `CHANGELOG.md` with "x" as the text: replace that with the real list of changes.
2. Update `README.md` where the change shows (and run `python3 tools/readme_tables.py` if buildings,
   goods or techs changed: it rebuilds the big tables in the README from the data files).
3. Update `READ_ME_FIRST.txt` next to the exe (version line, "saves from builds 4 to N still load").
4. Export both presets, then run the Linux export for 120 frames to be sure it starts cleanly:
   `xvfb-run -a linux/Hearthlands.x86_64 --rendering-driver opengl3 --write-movie /abs/dir/m.png --fixed-fps 10 --quit-after 120`
   (121 frames and no `SCRIPT ERROR` means it is fine).
5. Zip `Hearthlands.exe`, `READ_ME_FIRST.txt`, `CHANGELOG.md` and `Start in OpenGL safe mode.bat`.

---

## 2. The big picture

The game is split cleanly into a **simulation** that knows nothing about drawing, and an
**interface** that reads the simulation and sends it commands.

```
            ┌──────────────────────── Main (main.gd) ─────────────────────────┐
 mouse/keys │ side panel, toolbar, windows (ui_*.gd)   MapView (map_view.gd)  │
 ─────────► │   └ reads sim, calls sim.place(), sim.build_road() ...           │
            │                                                                 │
            │   game loop: _process() calls sim.tick(0.1) as often as the     │
            │   speed setting asks (1x = 10 ticks per real second)            │
            └───────────────────────────────┬─────────────────────────────────┘
                                            │
            ┌────────────────────────── Sim (sim.gd) ─────────────────────────┐
            │ state: map arrays, players, buildings, carriers, attacks        │
            │ rules: saves, placing, the tick; the rest in its parts:         │
            │   production (sim_production.gd) work cycles, building sites    │
            │   people     (sim_people.gd)     jobs, homes, walkers, needs    │
            │   logistics  (sim_logistics.gd)  roads, stores, carriers        │
            │   military   (sim_military.gd)   territory, soldiers, battles   │
            │   research   (sim_research.gd)   points, techs, ages            │
            │   ai         (sim_ai.gd)         what the rivals build and do   │
            │   sea        (sim_sea.gd)        ships, harbours, expeditions   │
            │   features   (features/*.gd)     optional systems and mods      │
            │   Diplomacy  (diplomacy.gd)      war, peace, alliances, trade   │
            └─────────────────────────────────────────────────────────────────┘
```

`Sim` is a plain `RefCounted` object, so it can run with no window at all. Every test in `tools/`
does exactly that: `godot --headless --script res://tools/some_test.gd`.

---

## 3. The simulation (`sim.gd` and its modules)

### 3.1 State

All game state lives in a `Sim`:

- **Map arrays**, one value per tile, index `y * w + x`:
  `ter` (0 water, 1 beach, 2 grass, 3 mountain), `deco` (trees, rocks, clay), `amt` (how much is left),
  `ore`, `owner` (realm id, 0 nobody), `road` (realm id of a road), `pave`, `bmap` (id of the building
  standing on its own tile), `plot` (id of the building whose plot covers the tile), `height` (0-255).
- **Players** (`class Player`): stock totals, people counts (`peasant`, `artisan`, `noble`, `scout`),
  soldiers in reserve, research, opinions, AI settings, and a few AI memory fields.
- **Buildings** (`class Bld`): type, position, owner, state (`"build"` or `"ready"`), work cycle times,
  worker, garrison, entrance side (`door`), a store's goods (`inv`), inputs carried to it (`inbuf`,
  `incoming`), construction materials (`need`, `coming`, `onsite`, `spent`), and so on.
- **Trips** (`class Trip`): everyone walking along the roads: porters, mules and ox carts with goods
  (to a store, to a construction site via `site`, or to a workshop via `dest`), and builders, workers
  and soldiers on their way to a building (`kind` = `"builder"`, `"worker"`, `"soldier"`).
- **Attacks** (`class Attack`): columns of soldiers marching to an enemy building, fighting at its gate
  or in the open.

`p.stock` is only the **total** of the realm's stores. The goods themselves are in each store's `inv`
(since build 31). Change goods only through `sim.give(p, res, n, at)` and `sim.take(p, res, n, at)`,
which find the nearest store to tile `at` and keep the total in step. Never write `p.stock[...]`
directly.

### 3.2 Time: ticks and seconds

`Sim.TICK` is 0.1 game seconds. `sim.tick(0.1)`:

1. Runs the buildings that are due. A building sleeps until `b.retry` (end of its work cycle, or the
   next time it should check again), so hundreds of busy buildings cost almost nothing.
   Construction sites go through `build_tick`, working buildings through `prod_tick`.
2. Every 3 ticks: `logistics._dispatch()` sends carriers (construction materials, then finished goods,
   then inputs).
3. Moves trips along and handles arrivals (goods into a store, materials to a site, inputs to a
   workshop, a worker reaching his job).
4. Attacks and battles (`military.attack_tick`).
5. Once per game second, `_secondly()`: who works where (`staffing`), people eating, newcomers, taxes,
   garrisons (`mil_fill`), research, renovation, the rivals thinking, diplomacy, features.

### 3.3 Determinism (important)

The game is **deterministic**: the same save, run for the same time, always ends the same way. This is
what makes saving and loading reliable, and `tools/save_test.gd` checks it after every change ("match
after 5 more minutes: true"). The rules that keep it so:

- Only `sim.rng` (a seeded `RandomNumberGenerator` that is saved) may be used for game randomness.
  `randf()` and friends are fine only for looks (drawing, sounds).
- Anything that changes the outcome must be saved, or be worked out again from saved state in exactly
  the same way. Caches are fine when they are keyed by a version number (the road network has
  `net_ver`, stores `_store_ver`) or by the current tick (`home_avail`), so a loaded game rebuilds them
  identically.
- Lists that are iterated must have a stable order (buildings are kept in id order; dictionaries are
  sorted where order matters).
- Saving uses `Sim.to_save()`: every `Bld`, `Player`, `Trip` and `Attack` is dumped through its property
  list (`_dump`), so **a new `var` in one of those classes is saved automatically**. Give it a default
  that suits older saves, because `_restore` leaves missing keys at their defaults. `from_save()` holds
  the conversions for older saves (look for comments starting "saves from before build ...").
- Files are written with `FileAccess.open_compressed(..., COMPRESSION_ZSTD)` and `store_var`
  (`ui_saves.gd`).
- Road searches round each distance to 32-bit precision and break ties by the lower tile number
  (`SimLogistics._f32`), so a network built in one go (after loading) finds exactly the same ways as one
  that grew road by road. Without that, equal-length ways differed after a load.
- `Sim.checksum()` hashes the whole saved state. Start the game with `-- checksums` to print it every game
  minute; `tools/checksum_run.gd` prints it for a rivals-only game (two versions of a pure code move must
  print the same numbers), and `tools/checksum_diff.gd` finds the first field that differs between a game
  and the same game saved and loaded. `save_test.gd` checks the checksums too.

### 3.4 How goods flow

```
 gatherer / workshop ── finish_prod() ── deliver() ── b.out_buf ──► carrier ──► nearest store (inv)
        ▲                                                                            │
        │ b.inbuf ◄── carrier ◄── source_for(): nearest store BY ROAD that has it ◄──┘
        │
   start_check(): inputs here? store room for the output? worker at work? work area OK?
```

- **Production** (`sim_production.gd`: `prod_tick`, `start_check`, `finish_prod`, `deliver`; `sim.gd`
  keeps one-line wrappers with the same names, so callers use `sim.prod_tick(...)` as before). A building starts a
  cycle when `start_check` returns `""`. Otherwise its message (`b.msg`, shown in the info box) says
  why, and it checks again a little later (`b.retry`, with a back-off in `b.fails`).
- **Carriers** (`sim_logistics.gd`). Porters come from the stores' own porters plus idle peasants
  (`porters_free`); mule stations and ox cart yards add faster carriers within their range.
  `carry_to()` is the one place a load leaves a store for a building, either to a construction site
  (`_dispatch_supply`) or as inputs (`_dispatch_inputs`); a carrier fills a part load with a second input
  the same building is short of (`Trip.res2`, `n2`). Each workshop keeps inputs for `b.keep` work cycles
  (0 means two). Stores pass goods on to each other (`transfers`, every 5 s) by their setting `b.policy`.
- **Road carriers** (a new-game option, `opts.road_carriers`, `plan_chain` in `sim_logistics.gd`): one
  carrier per stretch of road between flags (buildings, junctions, at least every 4 tiles), plus a donkey on
  a busy stretch. A load's whole
  journey is planned when it sets off: on each stretch it starts when it is at the flag and that
  stretch's carrier is free (`p.segs`: a `Vector3` per stretch, the free-again times of its two
  carriers and of its donkey slot, used only once the realm has donkeys from a donkey farm; legs carried by a
  donkey are marked `DONKEY_LEG`), so loads wait at flags on busy
  roads; a load that would wait over `MAX_QUEUE` is held back. `Trip.legs` holds the plan for drawing.
  `tools/carriers_compare.gd` plays the same game with and without the option. Flags the player sets
  (`p.flags`, `toggle_flag`) split a stretch where they stand; rivals set theirs in `_ai_flags`.
- **Ships** (`sim_sea.gd`). A shipyard makes the virtual good "ship" (`p.ships`, at most `MAX_SHIPS`).
  `expedition()` sends a ship with planks, stone and a soldier from a harbour to a free coast, where
  `ship_arrival()` founds a new harbour (a colony). `sea_transfers()` (every 5 s) carries a load between
  two harbours no road joins. Ships are Trips of kind "ship" that follow `water_path()` (`Trip.aim` is the
  landing tile); `p.ships_out` counts those at sea.
- **The road network**. For each realm, `_build_net` runs a Dijkstra search from all its stores at once
  over its roads, giving every road tile its walking time to the nearest store (`_net_dist`) and the way
  there (`_net_par`). `_relax_net` updates it cheaply when roads are only added. `store_field(s)` does
  the same search from one store, for fetching goods from a particular store. Walking time per step is
  `step_cost(a, b)`: dirt or paved, times a slope factor (`SLOPE_MUL`). `store_field` is worked out only as
  far as the tile asked about and carried on later (the search is paused, never changed), so a nearby
  building costs little. `reach(pid)` floods out from the network over land a road may cross: a building
  spot whose entrance is not reached is refused ("No road can get to this spot").
- **Entrances and plots**. A building joins the road only at its entrance tile (`door_tile`; `links(a, b)`
  enforces it everywhere roads are searched). Its plot (`PLOTS`, by size: small, medium, large, mine) is
  kept free of other buildings, roads and trees, with one free tile all round (`plot_check`).

### 3.5 People

- Counts per realm: `p.peasant`, `p.artisan`, `p.noble`, `p.scout`, soldiers in `p.reserve` plus the
  garrisons and attacks. Housing comes from `housing` in the building data.
- `staffing(p)` (every second) decides which buildings have a worker, high priority first. Training
  buildings (`"train"` in the data) turn peasants into artisans, artisans into soldiers or nobles,
  peasants into scouts.
- Where idle people wait is worked out by `home_avail(p)`: at the building that trained them, then
  workers' lodges, then homes, then the headquarters. `send_from_home()` finds the nearest of those by
  road (`nearest_home`) and starts a walking trip; the building's `worker` (or `builder`) goes 0 → 1 → 2
  (none, on his way, at work), and it works only at 2.
- Food: people eat from the stores every second (`take_food`); hunger lowers work speed and in the end
  people starve. Newcomers move in when there is housing and food to spare.

### 3.6 Territory and war (`sim_military.gd`)

- Military buildings (and the headquarters) claim land within their `radius`; `recompute_territory`
  works out the owner of every tile, the strongest claim winning. A building claims only once its
  first soldier has walked in.
- `mil_fill` sends soldiers from the reserve to garrisons (`garrison_wanted` respects the player's
  settings in the info box).
- `launch_attack` sends a column. It marches (`column_pos`), may meet an enemy column in the open
  (`_field_battles`), takes and returns fire (`_volleys`, `_cannon`), then fights one duel per second at
  the gate. Six soldier kinds, one per age, each with its own strengths (`Sim.SOLDIER_NAMES` and the kind
  tables in `sim_military.gd`).
  Winning captures the building (`_capture`); taking the headquarters ends that realm.

### 3.7 Research (`sim_research.gd`)

Science buildings make research points. Points go into the current tech (`p.research`, then the queue
`p.rqueue`). Techs come from `data/techs.json`: what they need, what they unlock, their bonuses
(`mods`, cached in `_type_bonus`). Finishing the last tech of an age moves the realm to the next age;
buildings built later take that age's look, older ones can be renovated. Repeatable "mastery" studies
give small bonuses a few times each.

### 3.7b Missions and maps

A mission (`data/missions.json`, or one in `user://data/missions.json`) is a new game with goals: `pop`,
`build`, `soldiers`, `tech`, `land`, `stock` or `defeat`, and an optional time limit. `sim.mission` and
`sim.mission_done` are saved; `_mission_check` (every second) ticks goals off and ends the game
(`ended.emit(win)`); `goal_progress(g)` gives [have, need] for the guide box. A mission can name a map.
Maps (`WorldGen.load_map`, `save_map`, `from_map`) are JSON with the map arrays (`MAP_KEYS`)
compressed and the start places; `new_game(..., p_map)` plays one instead of generating a world. The
editor (`ui_editor.gd`) saves them to `user://maps`.

### 3.8 The rival AI (`sim_ai.gd`)

Every few seconds each rival runs `ai_think(p)`:

1. Looks after its buildings: pulls down mines and gatherers that have nothing left, sets weaponsmith
   and barracks priority, makes room for a missing key building.
2. Walks down a **list of steps** (`steps`: building type and how many it wants, from formulas on
   population, minutes played and its personality: builder, balanced or warlord) and builds the first
   ones it can afford, up to `p.max_b` per think.
3. For each building it looks for spots: `_ai_sites` samples free tiles and scores them with
   `_site_score` (trees for a woodcutter, open land for a farm, distance to stores for a storehouse...)
   plus `_pack_score` (do not waste big spots, stay near roads, pack buildings together).
   `_ai_mil_sites` scores military spots by the new land they would claim.
4. When land runs out: expands with military buildings, frees soldiers from safe buildings, keeps
   artisans free to train soldiers, and when completely boxed in (`p.crowded`) mans its front and
   attacks (`ai_attack`) and goes to war more readily (`Diplomacy.ai_tick`).

Since build 33 a rival also plans its town a little: it keeps one or two large spots free for farms and
the like (`p.reserved`, `_plan_town`; other buildings stay two tiles off them), and places workshops
near the buildings they trade goods with (`_kin`, `_kin_score`). When attacking it weighs what a target
is worth (`_attack_value`: the land it holds and the mines and workshops on that land), keeps one more
soldier home in buildings near its headquarters, and calls an attack back once over half have fallen
while the gate still holds (`Attack.n0`, in `attack_tick`).

`tools/ai_bench.gd` is the yardstick for AI changes: seven rivals for 30 minutes on one map, ending with
a `SUMMARY` line (buildings, people, research, soldiers, smallest rival, how many stalled or went
hungry). Run it on two or three maps (`-- seed=valley`, `ridge`, `perf`) before and after a change; one
map alone is too noisy.

### 3.9 Optional features (`scripts/features/`)

`Feature` (feature.gd) is a base class with hooks the simulation calls: `on_second`, `on_cycle`,
`on_made`, `work_factor`, `build_factor`, `food_factor`, `tools`/`use_tool`, `draw_map`,
`building_lines`, `save_state`/`load_state` and more (the full table is in the README). The built-in
features are statistics, seasons, clothing, diseases, events, tool_quality, fog, geology and wildlife.
Players switch them under Settings > Game features. **Script mods** are the same thing: a `.gd` file in
the user's mods folder that extends `Feature` (see `mods_examples/bountiful_harvest.gd`).

### 3.10 Data (`data/*.json`)

| File | What it holds |
|---|---|
| `buildings.json` | every building: name, group (`cat`), `size`, cost, build `time`, worker, `cycle`, `in`/`out`, `site` needs, `garrison`, `radius`, `store`, `porters`, `housing`, `residence`, `train`, `tech`, art (`style`, `wall`, `sw` width in tiles) |
| `resources.json` | every good: name, icon, colour, food value, room it takes in a store (`cap`) |
| `techs.json` | the research tree (one tech per line), the bands (`lanes`) and the repeatable studies |
| `needs.json` | what artisans and nobles want to be content |
| `trades.json` | the trades workers learn, their titles and tools |

`game_data.gd` loads them and merges the player's mod JSON files over them, so balance changes are
usually just data edits. After changing buildings, goods or techs, run `tools/readme_tables.py`.

---

## 4. The interface

- **`main.gd`**: builds the whole interface in code (`_build_ui`), runs the game loop (`_process`),
  handles keys (`_unhandled_input`; keys the player changed in Settings are mapped back to the default
  keys first, `_translate_key`), placing buildings and roads (`_on_tile`, `_use_tool`), and the new-game
  screen. The rest is split out into `ui_*.gd` helpers, each a small class that holds a reference to
  `main`: `ui_info` (the building info box, `_refresh_sel`), `ui_side` (the side panel), `ui_research`,
  `ui_settings`, `ui_saves` (with map pictures), `ui_diplomacy`, `ui_demolish`, `ui_targets`,
  `ui_textures`, `ui_log`, `ui_toolbar`, `ui_guide` (the first-game checklist, or a mission's goals),
  `ui_problems` (what is stuck and why), `ui_attack` (the attack window), `ui_chain` (a good's production
  chain), `ui_editor` (the map editor) and `ui_missions` (the mission list).
- **Languages** (`i18n.gd`): `data/lang_<code>.json` maps English text to a translation and is loaded as a
  Godot translation, so labels and buttons whose text is a key show translated; text with numbers goes
  through `tr("... %d ...")`. `tools/extract_strings.py` collects new text into the files. German is
  included. Messages from the simulation (event log, building info) are still English.
- **`map_view.gd`** draws the world each frame in tile units (one tile = 1.0, scaled by `zoom`). With
  raised ground (2.5D, on by default) every tile corner is lifted by the height there (`_lift`,
  `lift_at`); the ground is drawn as grid meshes through those corners (`_chunk_grid`, and
  `draw_map_texture` for whole-map pictures such as fog and seasons), things standing on the ground are
  drawn raised (`_lift_to` / `_unlift`), and `screen_to_tile` traces a click back through the raised
  ground. It draws:
  ground from baked chunks, site markers, buildings sorted back to front with townsfolk between them,
  entrance flags, carriers and walkers, soldiers and battles, the placement ghost, selection rings.
  It turns mouse input into tile clicks for `main`.
- **`map_chunks.gd`** bakes the parts of the map that rarely change (terrain with blended edges,
  relief shading, roads with slope marks, trees and rocks, territory borders) into 16×16-tile images,
  re-baking only chunks whose tiles changed (`sim.changed_tiles`). Far out it uses a lower-resolution
  twin set (`LORES_ZOOM`).
- **`minimap.gd`**, **`tech_tree_view.gd`** (the research tree, drawn as a map you can pan and zoom),
  **`line_chart.gd`** (statistics), **`sound.gd`** (effects and ambience, chosen from log messages and
  what is on screen).
- **`tex.gd`** looks up textures by name, lets the player override any picture from the user textures
  folder, and knows the frame layout of animated strips (`ANIM`, `frames`, `frame_rect`).

---

## 5. Pictures and sounds

All default art is **generated by Python scripts**, so it can be changed in one place and remade:

- `tools/make_textures.py` draws every building in every age (by `art.style`), terrain, roads, icons,
  and (through `tools/folk_sprites.py`) townsfolk, porters, workers, mules and ox carts. It reads the
  data files, so a new building gets a picture from its `art` entry. `--force` overwrites everything.
- `tools/make_sounds.py` synthesises the sound effects and ambience loops.

Both need Pillow and numpy (`pip install pillow numpy`). Textures are imported with mipmaps on (their
`.import` files), which keeps them smooth when zoomed out.

---

## 6. Tests and measuring tools (`tools/`)

There are about 75 scripts. The ones to know:

| Script | Run it when |
|---|---|
| `run_all.py` | runs every test below and says which passed (`python3 tools/run_all.py quick` for the fast ones) |
| `check_data.py` | after editing `data/*.json` or a mod: unknown goods, techs, sizes, research loops |
| `save_test.gd` | after **any** simulation change: save, load, play on, compare (must say `true` three times) |
| `checksum_run.gd`, `checksum_diff.gd` | proving a code move changed nothing; finding what differs after a load |
| `reach_test.gd`, `transfer_test.gd`, `stretch_test.gd` | closed-in spots, goods between stores, road carriers |
| `stores_test.gd` | after touching goods: every realm's stock must equal the sum of its stores |
| `ai_bench.gd` | before and after AI changes, on 2-3 maps |
| `perf_test.gd` | to see where simulation time goes (`-- foes=7 mins=60 seed=...`) |
| `door_test.gd`, `walk_test.gd`, `site_test.gd`, `full_test.gd` | roads and entrances, walking people, construction supply, full stores |
| `garrison_test.gd`, `field_test.gd`, `battle_test.gd`, `battle_forts.gd` | soldiers and fighting |
| `research_test.gd`, `research_ai_test.gd`, `options_test.gd`, `oldsave_test.gd` | research, new-game options, old saves |
| `mission_test.gd`, `sea_test.gd`, `catapult_test.gd`, `claim_test.gd` | missions and maps, ships and colonies, catapults, boundary stones |
| `ai_stuck.gd`, `econ_diag.gd`, `food_diag.gd`, `chain_diag.gd`, `route_diag.gd`, `war_check.gd`, `rival_check.gd` | finding out why rivals are stuck, hungry, short of iron, or not fighting |
| `shot_*.gd` | screenshots of a feature (need a display: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script ...`) |

Headless tests run with `godot --headless --script res://tools/NAME.gd`; anything that opens the
interface needs a display (xvfb on Linux, or just run it on a desktop).

---

## 7. Common changes, step by step

**A new building.** Add it to `data/buildings.json` (copy a similar one; give it `cat`, `size`, `cost`,
`time`, and `worker`/`cycle`/`in`/`out` if it works). Run `tools/make_textures.py` to draw it, then
`tools/readme_tables.py`. If the rivals should build it, add a step in `ai_think` (`sim_ai.gd`).

**A new good.** Add it to `data/resources.json`, give some building an `out` for it, run the two
scripts above.

**Balance.** Costs, cycle times, outputs, store room and tech bonuses are all data. Rival behaviour is
the `steps` list and the scoring functions in `sim_ai.gd`.

**A new rule in the simulation.** Put it in the module it belongs to. If it needs new state, add a `var`
to `Bld`/`Player` (saved automatically) with a default that works for old saves. Then run `save_test`.

**An optional system.** Write a `Feature` subclass in `scripts/features/` and add it to the
`BUILT_IN` list in `features.gd`; players can then switch it on and off, and it saves its own data.

---

## 8. Where things are (quick index)

| You are looking for | Look in |
|---|---|
| building costs, outputs, sizes | `data/buildings.json` |
| why a building does not work | `Sim.start_check`, `Sim.prod_tick` (its `msg`) |
| placing rules (room, slope, entrance) | `Sim.can_place`, `Sim.plot_check`, `Sim.PLOTS` |
| road laying for new buildings | `SimLogistics._path_to_net_inner` |
| carriers and what they carry | `SimLogistics._dispatch`, `_dispatch_supply`, `_dispatch_inputs`, `carry_to` |
| goods in stores | `SimLogistics.give`, `take`, `store_add`, `stores_of` |
| who works where | `SimPeople.staffing`, `home_avail`, `send_from_home` |
| territory | `SimMilitary.recompute_territory`, `compute_owner` (boundary stones: `claim_only`, `Sim._soldiers_hold`) |
| attacks and duels | `SimMilitary.launch_attack`, `attack_tick`, `_field_battles` |
| rival building plan | `SimAI.ai_think` (`steps`) |
| saving and loading | `Sim.to_save`, `Sim.from_save`, `ui_saves.gd` |
| the toolbar and build menus | `ui_toolbar.gd`, `Main._rebuild_build_list` |
| the info box | `UiInfo._refresh_sel` (`ui_info.gd`) |
| work cycles and sites | `sim_production.gd` |
| jobs, homes, walking people | `sim_people.gd` |
| road carriers | `SimLogistics.plan_chain`, `_chain_trip` |
| ships and colonies | `SimSea.expedition`, `ship_arrival`, `sea_transfers` |
| missions | `Sim._mission_check`, `goal_progress`, `data/missions.json`, `ui_missions.gd` |
| maps and the editor | `WorldGen.load_map`, `save_map`, `from_map`, `ui_editor.gd` |
| statistics and border replay | `features/statistics.gd` |
| trade by cart, standing offers, rivals' words | `Diplomacy.send_cart`, `cart_arrival`, `standing_tick`, `say`, `_warn_first` |
| bridges | `SimLogistics.bridge_landing`, `bridge_step`, `bridge_cost_ok` |
| taverns, chapels, contentment | `features/contentment.gd` |
| realm laws, contentment by class | `features/laws.gd`, `data/laws.json` |
| archers and sallies | `SimMilitary.archers_tick`, `_arrows`, `_sally` |
| spreading fires | `features/fires.gd` |
| campaign | `ui_campaign.gd`, `data/campaign.json` |
| traffic map, undo, follow camera | `ui_traffic.gd`, `ui_undo.gd`, `MapView.follow` / `pick_mover` |
| achievements, packs, town names | `achievements.gd`, `share_pack.gd`, `Sim.new_town_name` |
| snow on the roads | `seasons.gd carry_factor`, `Sim.carry_factor` |
| raised ground | `MapView._ensure_lift`, `lift_at`, `_grid_mesh` |
| translations | `i18n.gd`, `data/lang_*.json`, `tools/extract_strings.py` |
| drawing buildings, people, carriers | `MapView._draw`, `_draw_building`, `_collect_folk` |
| trees, peaks and boulders | `MapView._draw_scenery`, `_scenery_mesh` (pictures from `tools/make_scenery.py`) |
| renderer and display settings | `settings.gd`, `ui_settings.gd`, `Main._probe_vulkan` |

---

## 9. Renderer notes

The project's default renderer is OpenGL (Compatibility). Godot 4.3 cannot fall back from Vulkan to
OpenGL by itself, so a Vulkan default would leave PCs without Vulkan unable to start. Instead, on the
first start `Main._probe_vulkan` launches the game once more in a small window with Vulkan; if that
window draws a frame, Vulkan is written to `user://graphics_override.cfg` (which the engine reads at
start-up, through `application/config/project_settings_override`) and the game restarts with it.
`Start in OpenGL safe mode.bat` forces OpenGL whatever was chosen.
