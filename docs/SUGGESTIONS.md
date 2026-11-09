# Suggestions for Hearthlands

What could be improved next, gathered while building and testing versions up to 0.27.0 (build 32).
The status table below says what build 33 did with each item.
Each item says why it matters, where in the code it lives, and roughly how big a job it is:
**S** = an hour or two, **M** = a day, **L** = several days. The most useful items come first in each
section. See `docs/SOURCE_GUIDE.md` for how the code fits together.

## Status after build 33

Everything below was done in build 33 except **B3** (moving loops to C++ needs a Windows C++ build that
could not be made here). Notes on what was done and what is left:

| Item | Done | Notes |
|---|---|---|
| A1 closed-in spots | yes | `reach()`; refused with "No road can get to this spot"; also not marked as sites |
| A2 town plans | yes | large spots kept free, workshops near their suppliers; on the 3 test maps people +1% to +17%, buildings -7% to +3% (mixed) |
| A3 road carriers | yes, as a new-game option | goods wait at flags on busy roads, donkeys help on busy stretches; realms grow 10-20% slower than with porters (rivals do not plan roads for it yet) |
| A4 store transfers | yes | per-store setting Normal / Gather here / Send away |
| A5 better attacks | yes | target value, a guard kept near the HQ, rivals call failing attacks back |
| A6 toolsmith waits | yes | helped research on all 3 maps |
| A7 bigger auto maps | yes | the old sizes did worse on all 3 maps |
| A8 small ideas | yes | inputs kept 1/2/4 cycles, arrival times, "+N land" hints, store setting |
| B1 store searches | yes | searches pause at the tile asked about and carry on later |
| B2 fewer trips | yes | a second input fills a part load |
| B3 C++ | no | skipped |
| B4 drawing | partly | carriers drawn in batches by picture; the software renderer here shows no change, a real graphics card should |
| C1-C5 | yes | git, `run_all.py`, `check_data.py`, checksums, files split |
| C6 languages | the interface | German included; messages from the game (event log, building info) are still English |
| D1 raised ground | yes | hills drawn raised (2.5D), can be switched off in Settings; ground details (tufts, reeds) not added |
| D2 guide | yes | eight steps, ticked off by themselves |
| D3 small touches | yes | save pictures, keys in Settings, a bell for building sites, entrance pennants on sites |

Still open: rivals laying roads with road carriers in mind (A3), translating the game's messages (C6), more ground detail (D1),
and B3 if 8x speed in huge games matters.

## Status after build 34

Build 34 did the eight ideas that came next, and the smaller ones with them:

| Idea | Where |
|---|---|
| Problems list and minimap alerts | `ui_problems.gd`, P key |
| Choose who attacks | `ui_attack.gd` |
| Production chain view | `ui_chain.gd` |
| Ships and harbours, expeditions, colonies | `sim_sea.gd`, harbour and shipyard in `buildings.json` |
| Your own flags and donkeys for road carriers | `SimLogistics.toggle_flag`, `_ai_flags`, donkey farm (rivals now place flags, which answers A3) |
| Catapults | `catapult` in `buildings.json`, `catapult_test.gd` |
| Missions and a map editor | `data/missions.json`, `ui_missions.gd`, `ui_editor.gd`, `WorldGen` map files |
| More ground detail, day and night | `map_view.gd` (tufts, stones, flowers; light by time of day) |
| Smaller: copy a building (Q), realms compared, border replay | `main.gd`, `features/statistics.gd` |

Still open: translating the game's messages (C6), and B3.

## Status after build 37

The second ideas page (all but blueprints): trade by cart with markets and standing offers, bridges,
taverns, chapels and festivals, archers and sallies, the traffic map, a campaign of eight chapters,
spreading fires with bucket carriers, and the smaller touches: undo, jump to idle buildings, building
history, minimap filters, follow camera, achievements, 16x speed, colour-blind colours, rivals' words
(warnings, thanks, tribute), town names, snow on unpaved roads and map and mission packs. Not done:
frozen rivers that can be crossed in winter (snow only slows carriers), and blueprints.

---

## A. Gameplay and the rival AI

### A1. Building spots that no road can reach (M) — highest value
In a crowded town about 4 in 10 free spots are pockets that a new road cannot reach (closed in by other
plots, water or rocks). The rivals keep picking them and give up ("No road route"), which is the main
reason some rivals stall on crowded maps. The player meets it too: the site markers show such spots.
- Work out, once per network change, which free tiles a new road could reach from the network (one flood
  fill per realm over passable tiles, cached by `net_ver`).
- Use it in `SimAI._ai_sites` (skip unreachable spots), in `MapView._site_markers` (do not mark them) and
  in `Sim.can_place` ("No road can reach this spot") so the player learns why.

### A2. Rivals that plan their towns (L)
Rivals place each building on its own. With building sizes, a town packed with houses leaves no room for
a farm or a barracks later (the "pull down a house" rule in `ai_think` is a patch for this).
- Reserve a few large spots early for farms and a barracks (mark them in `Player`, skip them in
  `_ai_sites` for other buildings).
- Group buildings: food near farms, smiths near mines, a storehouse and a workers' lodge in each group.

### A3. Carriers per road stretch, as in The Settlers (L)
Today a porter walks the whole way from store to building and back. In The Settlers each stretch of road
between two flags has its own carrier, goods are handed on at flags, and busy roads get donkeys. That
makes road layout matter much more and shows traffic jams.
- It is a big change in `sim_logistics.gd` (trips become a chain of hand-overs) and in drawing. Worth a
  prototype on a copy first, measured with `perf_test.gd`.

### A4. Moving goods between stores (M)
Goods stay in the store they were first carried to. A far store can be full of planks while the
workshops near another one wait. Add a slow background transfer from stores with plenty to stores near
where a good is used (and maybe player settings per store: "keep", "send away", "do not take").

### A5. Better attacks (M)
Rivals attack the target with the best odds. They could also think about value (a headquarters, a
building that holds a lot of land, a mine), keep defenders back near their own headquarters, and pull
back when an attack goes badly. `SimAI.ai_attack`, `SimMilitary`.

### A6. Soldiers versus tools for iron (S)
Rivals now research more but hold about 10% fewer soldiers, because iron goes into tools too. Let the
toolsmith wait (low priority) when weapons are short and no tool is badly needed (`p.tool_wait`).

### A7. Bigger default maps for many realms (S)
With building sizes, eight realms fill a normal map by minute 20 and growth turns into war. Scale the
automatic map size with the number of realms a bit more (`Sim.new_game`, map size "Auto").

### A8. Smaller gameplay ideas (S each)
- A setting for how much each workshop keeps of its inputs (now two work cycles, food one).
- Show walking workers and builders in the info box with how long until they arrive.
- An "expand here" hint: mark spots where a military building would claim the most new land.
- Let the player set a store as "collect" or "supply only".

---

## B. Speed

Measured with `tools/perf_test.gd`: carried inputs and walking people made the simulation about 30%
busier than before build 31. A big game (8 realms, 60 minutes) is fine at 1x and 2x but heavy at 8x.

### B1. Per-store road searches (M)
`SimLogistics.store_field` runs a full search over the realm's roads for each store whenever the road
network changes, and the network changes often while rivals build. Options: update the fields
incrementally like `_relax_net`, or only refresh a field when it is asked for and the store actually
holds the good.

### B2. Fewer input trips (S)
Many input trips carry one item. Let a carrier take two kinds of goods for the same building at once, or
wait a moment to fill his load. `SimLogistics._dispatch_inputs`, `carry_to`.

### B3. Move the hottest loops out of GDScript (L)
Road searches, territory and the start checks are the biggest costs. They could go into a GDExtension
(C++) or a C# helper, keeping the GDScript rules around them. Only worth it if 8x speed in huge games
matters to you.

### B4. Drawing (M)
`MapView._draw` draws every sprite each frame. MultiMesh batches for trees, carriers and townsfolk would
cut drawing time, especially zoomed out. `tools/zoom_bench.gd` measures it.

---

## C. Code health

### C1. Put the project under version control (S) — do this first
Use git (GitHub, GitLab or just a local repository). Every change becomes undoable and you can compare
versions. Add a `.gitignore` with `.godot/` and `tools/__pycache__/`.

### C2. One command that runs all the tests (S)
Write `tools/run_all.gd` (or a small shell script) that runs `save_test`, `stores_test`, `door_test`,
`walk_test`, `site_test`, `garrison_test`, `field_test`, `research_test`, `options_test` and checks
their output. Then a CI job (for example GitHub Actions with the Godot headless binary) can run it on
every change.

### C3. Split the two biggest files (M)
- `sim.gd` (about 3,000 lines): move production (`prod_tick`, `start_check`, `finish_prod`, `deliver`)
  into `sim_production.gd`, and people (`staffing`, homes, walking people, food, newcomers) into
  `sim_people.gd`, the same way `sim_logistics.gd` and `sim_military.gd` are already split out.
- `main.gd` (about 2,100 lines): move the side panel and the building info box (`_refresh_sel`) into
  `ui_side.gd` and `ui_info.gd`.

### C4. A determinism check you can switch on (S)
In a debug build, print a checksum of the simulation state every game minute. When something stops
matching after a load, comparing checksums shows the minute it went wrong.

### C5. Check the data files (S)
A small script that loads `data/*.json` and reports mistakes: unknown goods in `in`/`out`/`cost`, a
`tech` that does not exist, a building without `size` or `art`. Mods would benefit most.

### C6. Text in one place (M)
All the interface text is written in the code. Moving it into a table (Godot's translation CSV files)
would make it possible to translate the game, and easier to change wording.

---

## D. Look and feel

### D1. 2.5D terrain (L)
Raise each tile by its height and light it from its slope, as in The Settlers II, with more ground detail
(grass tufts, pebbles, reeds, foam, snow on peaks). This was asked for earlier and is not done yet. It
mostly lives in `map_chunks.gd` (baking) and needs buildings and people drawn at the raised height in
`map_view.gd`.

### D2. A first-game guide (M)
A short series of hints for the first ten minutes (build a woodcutter, a sawmill, a quarry, connect the
road, ...), each ticked off when done. It would help new players with the entrance, road and size rules.

### D3. Smaller touches (S each)
- Save slots with a small picture of the map.
- Re-bindable keys.
- A sound when a building you are waiting for is finished.
- Show the flag of an entrance in the site markers while placing.

---

## E. Testing your own changes

1. Make the change on a copy or a branch (see C1).
2. Run `tools/save_test.gd` (must say `true` twice) and `tools/stores_test.gd`.
3. For rule or AI changes, run `tools/ai_bench.gd` on `valley`, `ridge` and `perf` before and after,
   and compare the `SUMMARY` lines. A change is real only if it shows on more than one map; one map can
   swing 10% by chance.
4. For anything you can see, take a screenshot with one of the `tools/shot_*.gd` scripts.
