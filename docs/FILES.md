# Hearthlands source files

Every source file with what it is for, grouped by part. Written by `tools/file_list.py` from the comment at the
top of each file; run it again after adding files. For how the parts work together, read
`docs/SOURCE_GUIDE.md`. Besides these 199 files there are 969 pictures in `textures/` (made by
`tools/make_textures.py` and `tools/make_scenery.py`, or your own) and 29 sounds in `sounds/` (made by
`tools/make_sounds.py`). Godot's `.import` files next to them are made by the editor.

## Game: simulation

| File | Lines | What it is |
|---|---:|---|
| `scripts/crops.gd` | 260 | What a farm grows. A farm sows one crop at a time, chosen on its panel. Wheat is known from the start; other seeds are unlocked by research. Each crop has its seasons: how much faster or slower it grows in spring, summer, autumn and winter, and OFF where it does not grow at all (the farm stands idle then). With the Three-field system studied, a farm can be set to sow winter rye when its own crop is out of season. Without the seasons feature every crop grows all year. |
| `scripts/diplomacy.gd` | 536 | Relations between realms (war, peace or alliance), each rival's opinion of every other realm, proposals (peace, alliance, trade and gifts) and how rival AIs decide on them. The state itself lives in Sim (rel, rel_since, proposals, and Player.opinion) so it is saved with the game. |
| `scripts/game_data.gd` | 335 | Loads the game's content from data/*.json. Files with the same name in user://data/ are merged on top, so players can add or change resources, buildings and population needs without editing the project. |
| `scripts/sim.gd` | 2517 | The whole game state and rules: map, players, economy, territory, combat and rival AI. Runs without any rendering, so it can be tested headless (see tools/sim_test.gd). |
| `scripts/sim_ai.gd` | 667 | How rival realms think: what to build and where, when to attack, what to research. Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach the rest of the game through `sim`. |
| `scripts/sim_logistics.gd` | 1785 | Roads, the road network, stores, carriers and work areas. Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach the rest of the game through `sim`. |
| `scripts/sim_military.gd` | 845 | Territory, soldiers, attacks, duels and conquest. Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach the rest of the game through `sim`. |
| `scripts/sim_people.gd` | 534 | People: housing, jobs and specialists, homes where people wait, people walking to work and soldiers to their posts, needs and food. Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach the rest of the game through `sim` (sim.gd keeps a one-line wrapper for each, so callers did not change). |
| `scripts/sim_production.gd` | 485 | Production: buildings working in cycles (inputs, outputs, tools, experience) and construction sites. Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach the rest of the game through `sim` (sim.gd keeps a one-line wrapper for each, so callers did not change). |
| `scripts/sim_research.gd` | 264 | Research points, techs and the ages. Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach the rest of the game through `sim`. |
| `scripts/sim_sea.gd` | 258 | Ships and harbours. A shipyard on the coast builds ships (Player.ships). A harbour is a store on the coast that also holds a little land and a soldier, and people can wait there. From a harbour an expedition (a ship, 4 planks, 2 stone and a soldier) sails to another free coast and founds a new harbour there: a colony. Ships then carry goods between harbours that no road joins, from where there is plenty to where there is little. Ships are Trips of kind "ship" along a path over water; `aim` is the tile an expedition lands on. |
| `scripts/world_gen.gd` | 454 | Random map generation. Terrain: 0 water, 1 beach, 2 grass, 3 mountain. Decorations: 1 tree, 2 rock, 3 clay patch. Ore (on mountains): see GameData.ORE_NAMES. |

## Game: features (switchable in Settings)

| File | Lines | What it is |
|---|---:|---|
| `scripts/features/clothing.gd` | 164 | Summer and winter clothes. Needs "Seasons, biomes and weather" for the temperature. Every realm keeps a wardrobe: how many of its people own a fur coat and how many own linen clothes. Whenever coats or linen are in store and not everyone has them, people take them (one piece dresses 3 people). Clothes wear out only while worn: coats in the cold, linen in the heat. Below 8 C people without a coat work slower and eat more, the more so the colder it is; above 24 C people without linen clothes work slower. Diseases (if switched on) read cold_need(). |
| `scripts/features/contentment.gd` | 191 | Contentment: how happy a realm's people are, from 0 to 1. Half (0.5) is where every realm starts and changes nothing. Taverns serving beer and bread to the homes near them, and chapels burning candles near them, raise it; hunger and sickness lower it. Content people work faster (up to 10%), unhappy ones slower (down to about 7%). A tavern with beer and bread to spare holds a festival now and then: everyone works 10% faster for 3 minutes. When the realm stays unhappy for 3 minutes, idle peasants start to leave, one a minute. |
| `scripts/features/diseases.gd` | 333 | Diseases, their prevention and their cure. Every ten seconds each disease may break out in a realm; how likely depends on its causes (cold without coats, crowding, too few wells, hunger, heat, wetlands) and on prevention (bathhouses keep people clean, wells give clean water, coats keep the cold out). Once in, it spreads among the healthy and the sick slowly get better by themselves, faster with medicine: medicine in store cures a few at home, and an infirmary cures 8 people with each medicine. Some of the sick die. Sick people don't work, so every building of the realm works slower by the share of its people who are sick. Uses the seasons (temperature, wetlands) and clothes features when they are switched on. |
| `scripts/features/events.gd` | 368 | Random events: every four to seven minutes something happens to each realm, good or bad: a bumper harvest, rats in the granary, a fire, a mine collapse, a travelling merchant, refugees, a festival, a lucky find, wolves, a skilled newcomer, storm damage, bandits, a wandering scholar, an epidemic. Rivals get them too. Switch them off in Settings > Game features ("Random events"); each event can also be switched off on its own in the Events list window (F6). |
| `scripts/features/feature.gd` | 149 | Base class for optional game systems ("features"): production statistics, seasons, diseases and so on. A feature is a script that extends Feature and overrides only the hooks it needs. The simulation calls the hooks of every switched-on feature, and a feature changes the game only through them, so each one can be switched on or off in Settings without touching the rest of the game. To write your own, put a .gd file that extends Feature in the mods folder (Settings shows where). See mods_examples/ in the project for a small example. |
| `scripts/features/features.gd` | 62 | Finds the features the game can use: the built-in ones and any mod scripts in the mods folder. |
| `scripts/features/fires.gd` | 204 | Fires that spread. A fire starts in a building (a random event's fire, or a catapult's stone) and grows. A building on fire stops working, and when the fire has burned it down it is gone. Fire jumps to wooden neighbours within 3 tiles; buildings mostly of stone or brick do not catch, and nor do the headquarters, stores and stone forts. People from working wells within 10 tiles, and the crew of a fire station within 14, run with buckets: the more of them, the faster the fire dies. A fire left alone burns a building down in a minute or two. |
| `scripts/features/fog.gd` | 277 | Fog of war, watch towers and scouts. You see only what your realm can see: your own land, a few tiles around each building, further from military buildings, 14 tiles from a watch tower with a scout inside, and around scouts out exploring. Land you have seen once stays on the map (explored), but darkened, and rival buildings there show as you last saw them; their soldiers and carriers show only in sight. Unexplored land is black. Scouts are trained at the scout lodge. Idle scouts can be sent to any spot on the map (the Send scout tool in the Military tab): one walks there and back, seeing 5 tiles around him, and turns back at the shore. Rivals are not limited by the fog (the computer plays without it). |
| `scripts/features/geology.gd` | 331 | Geologists. What lies under the mountains is unknown until a geologist has surveyed it: ore veins don't show on the map, and mines can only be built on surveyed tiles with the right ore. Send geologist (Industry tab), then click a mountain in or near your land: an idle peasant takes a pickaxe from the store (he brings it back), walks there over land, checks up to 12 mountain tiles around the spot (18 with Prospecting) and plants a marker on each: coal, iron, gold, copper, granite or nothing, bigger for richer veins. The markers fade after five minutes but your realm remembers what was found; picking a mine to build shows every surveyed tile of its ore again. Prospecting also lets 4 geologists out at once instead of 2; Geological survey makes one find reveal its whole vein. Rivals send geologists too. |
| `scripts/features/seasons.gd` | 601 | Seasons, biomes and weather. A year has four seasons of five game minutes each, starting in spring. The map is split into biomes: a cold northern taiga, a temperate middle, a dry southern steppe and wetland patches near water. Each biome has its own weather, which changes every one to two and a half minutes, and its own temperature (season + biome + weather; mountains are colder). Season, biome and weather speed up or slow down outdoor work, construction, and how much people eat. Other features (clothes, diseases) read the temperature through temp_at() and realm_temp(). |
| `scripts/features/statistics.gd` | 379 | Production statistics: for every realm and every game minute, how much of each good was made and used, plus its population, buildings, soldiers and research. The Statistics window (F2) shows charts. |
| `scripts/features/tool_quality.gd` | 201 | Tool quality. Every tool is crude, standard, fine or masterwork. The toolsmith's skill decides the quality: an apprentice makes crude and standard tools, a master fine and masterwork ones; the machine works does better still. Tools in store are kept as a pool with an average quality. A worker uses his tool every work cycle and it wears out: crude after 40 cycles, masterwork after 180. Then he takes a new one from the stores; if there is none, he works on with a worn-out tool, 25% slower. Better tools make work faster: crude -12%, standard +0%, fine +12%, masterwork +25%. Only matters when new workers need tools (the difficulty option). |
| `scripts/features/wildlife.gd` | 310 | Wildlife you can see: deer and boars in and near the woods, hares in the open, wolves in the forests (more in the northern taiga). They wander, keep away from buildings, and have young (not in winter) up to what the land can feed. Hunters must find a real animal in their hunting grounds; each catch takes one, so over-hunting empties a forest for a while. Wolves now and then scare the herds of sheep and pig farms and dairies (the farm stops for a while) and take deer and hares themselves. Fish jump in the fishing grounds. |

## Game: map drawing

| File | Lines | What it is |
|---|---:|---|
| `scripts/line_chart.gd` | 73 | A simple line chart: one line per series over the same time axis, newest on the right. Set `series` to [{"name": String, "color": Color, "values": Array of numbers}, ...] and `x_label`. |
| `scripts/map_chunks.gd` | 517 | Bakes the parts of the map that rarely change (ground, roads, scenery, ore, territory) into large images of 16 x 16 tiles called chunks. Drawing a few dozen chunks each frame is far cheaper than drawing thousands of separate tiles. A chunk is baked again only when something inside it changes. Where two kinds of ground meet, the higher one (beach over water, grass over beach, mountain over grass) spills softly over the edge. Open water is baked half transparent: the ground shader uses that as a marker to make the water shimmer. |
| `scripts/map_view.gd` | 1895 | Draws the world and turns mouse input into tile clicks. The ground, roads, scenery and borders come from pre-baked chunks (map_chunks.gd), drawn by a child layer whose shader makes the water shimmer. Everything that moves or changes often (buildings, carriers, soldiers, workers, smoke, selections, tool previews) is drawn every frame on top. Animations follow the game clock, so they freeze while the game is paused and speed up with it. |
| `scripts/minimap.gd` | 213 | Whole-map overview: terrain, roads, territory, military buildings and the camera frame. Its images double as the far-zoom picture of the main map. |
| `scripts/tech_tree_view.gd` | 590 | The tech tree drawn as a map: ages run left to right, each band is a branch of the realm, and lines run from what a tech needs to what it leads to. The places come from data/techs.json ("lane", "col", "row", worked out to cross as few lines as possible); techs added by a mod without them are put in an "Other" band. Repeatable studies sit in the Mastery band at the bottom. Drag (or the arrow keys) to move, the wheel to scroll, Ctrl + wheel or a pinch to zoom. |
| `scripts/tex.gd` | 201 | Texture lookup with user overrides. For an id like "bld_sawmill" the game looks for, in order: 1. user://textures/bld_sawmill.png   (your custom texture, any size) 2. res://textures/bld_sawmill.png    (the default shipped with the project) 3. a magenta placeholder, so a missing file is obvious in game. |

## Game: interface

| File | Lines | What it is |
|---|---:|---|
| `scripts/achievements.gd` | 133 | Achievements: little goals across all your games, kept in user://achievements.json with the day each was earned. Checked every few seconds while you play; a new one rings and shows a line. The end screen lists the ones earned in that game, and the new-game screen shows them all. |
| `scripts/i18n.gd` | 54 | Interface languages. Each data/lang_<code>.json (and the same name in the mods folder) maps the English text to its translation; "_language" holds the language's own name. The files are loaded at start as Godot translations, so every label and button whose text is a key is shown translated, and text with numbers in it goes through tr("... %d ...") in the code. tools/extract_strings.py collects new text into the files. The game's own messages (event log, building info) stay English. |
| `scripts/main.gd` | 2162 | Builds the interface in code and runs the game loop. |
| `scripts/settings.gd` | 227 | Options that last between games: renderer, display mode and resolution, interface size, frame rate, and a few conveniences. They are kept in user://settings.cfg. The renderer is special: Godot picks it before any script runs, so it goes into a second file, user://graphics_override.cfg, which the engine reads at start-up (project.godot points to it with application/config/project_settings_override). A new renderer is first tried in a one-off restart; only if that start works is it written there, so a PC without Vulkan always gets back to OpenGL. Vulkan is preferred: on the first start the game checks, in a small hidden-away test start, whether Vulkan works on this PC, and switches to it if it does (Main._probe_vulkan). |
| `scripts/share_pack.gd` | 105 | Sharing maps and missions as one file (.hlpack): the map editor exports the map being edited (with any of your missions that are played on it), the Missions window exports all your own missions and their maps, and imports a pack someone sent you. A pack is JSON: {"hearthlands_pack": 1, "maps": {file name: map file contents}, "missions": [mission, ...]}. Imported maps go into user://maps (renamed if the name is taken), missions into user://data/missions.json with their map paths pointing at the imported maps. |
| `scripts/sound.gd` | 219 | Sound effects and ambience. The sounds are made by tools/make_sounds.py (synthesised, no samples). Effects: button clicks, placing and finishing buildings, research, good and bad news, attacks, and the work of buildings on screen (axes, picks, hammers, saws, building sites, battles) when zoomed in. Ambience loops, faded in and out by what is on screen: birdsong in the warm seasons, wind in winter, rain when it rains where you look (with the seasons feature), and a town murmur close up. Volumes are in Settings and kept in user://settings.cfg. |
| `scripts/ui_attack.gd` | 177 | The attack window, as in The Settlers II: clicking an enemy military building opens it. It shows the defenders, lets you pick how many soldiers march (from all your military buildings in range, the nearest first) and which kinds, and gives a rough idea of the odds. Each building keeps at least one soldier home, as before. |
| `scripts/ui_campaign.gd` | 251 | The campaign: the chapters of data/campaign.json on a parchment map, each a mission with a story before and after it. A chapter opens when the one before it is won. Winning a chapter can carry something into the next (veteran soldiers, a stock of goods), and the map remembers the best time and score of each chapter. Progress is kept in user://campaign_progress.json. |
| `scripts/ui_chain.gd` | 246 | The production chain of a good: boxes for the buildings that make it and, step by step, what they need, with arrows to the buildings that use it. Each box shows how many you have and how much they make a minute: what they made over the last ten minutes when Statistics is on, and what they could make at full speed. An arrow turns red where what they can make at full speed falls short of what the next step needs, and the weakest link gets a tip. Opened from a good's info box ("Production chain"). |
| `scripts/ui_demolish.gd` | 170 | The window that asks before a building is demolished. Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main`. |
| `scripts/ui_diplomacy.gd` | 265 | The Diplomacy window: alliances, peace, war and trade with rivals. Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main`. |
| `scripts/ui_editor.gd` | 282 | The map editor: opened from the new-game screen. It starts from the map of the seed and size chosen there, without any realm on it, and paints ground, trees, rocks, clay and ore with a brush. The numbered banners are the headquarters' places (start 1 is yours); "Move start" puts one where you click next. Maps are saved as JSON in the "maps" folder of the game's data folder (user://maps) and can be played from the editor or picked on the new-game screen. Missions can name a map too. |
| `scripts/ui_guide.gd` | 164 | The first-game guide: a short checklist for the first minutes of a new game (build a woodcutter, join it to the roads, a sawmill, a quarry...). Each step is ticked off by itself when it is done, with a line on the rule that matters for it (entrances, sizes, roads). It closes when every step is done or with its x, and "Show the first-game guide" in Settings brings it back for the next new game. |
| `scripts/ui_info.gd` | 463 | The building info box: what the selected building is doing, and its buttons (priority, stores, garrison...). Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main` (main.gd keeps a one-line wrapper for each, so callers did not change). |
| `scripts/ui_log.gd` | 119 | The event log: a small window, at first in the upper-left corner of the map, that you can move by its title bar and resize from its edges. Its place, size and whether it is open are remembered in Settings. E (or the Events button on the top bar) shows and hides it. Events that happened somewhere on the map end with a Go button that moves the camera there. |
| `scripts/ui_missions.gd` | 93 | The missions list, opened from the new-game screen: games with goals and often a deadline, from data/missions.json (a mod's data/missions.json adds more). Each mission plays on a map made from its seed or on a hand-made map file; its goals show in the box on the left while playing. |
| `scripts/ui_problems.gd` | 242 | The Problems list: every one of your buildings that cannot work and why, and attacks on you, longest waiting first, each with a Go button. Opened from the top bar (or the key, O by default). The same problems blink on the minimap: red where you are attacked, amber where a building is stuck. A problem can be hidden with its x (or all at once with "Hide all"): it leaves the list, the count and the minimap until its reason changes, or for an attack until that attack is over. "Show hidden" brings them all back. Only the interface: it reads the game and changes nothing in it. |
| `scripts/ui_research.gd` | 431 | The research window: the tech tree from Rome to the Industrial Revolution. Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main`. |
| `scripts/ui_saves.gd` | 143 | Saving and loading games, and the Save / Load window. Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main`. |
| `scripts/ui_settings.gd` | 283 | The Settings window: renderer, display, resolution and options. Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main`. |
| `scripts/ui_side.gd` | 166 | The side panel: stores, people, the build list, research and rivals, refreshed once a second. Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main` (main.gd keeps a one-line wrapper for each, so callers did not change). |
| `scripts/ui_targets.gd` | 82 | Production targets: how many of each good to keep in stock. Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main`. |
| `scripts/ui_textures.gd` | 69 | The texture browser: every picture the game uses, and your replacements. Part of the interface: main.gd holds the shared state and calls in here; the functions reach the rest of the game through `main`. |
| `scripts/ui_toolbar.gd` | 390 | The toolbar along the bottom of the map, as in the Settlers games: a button per building group (each opens a panel of its buildings just above the bar), the road tools and Auto roads, Demolish, and the tools of the game features (send a scout, send a geologist). Esc closes the panel. |
| `scripts/ui_traffic.gd` | 187 | The traffic map (F7, or the Traffic button): every road of yours coloured by how busy it has been over the last few minutes. Green is free, amber busy, red jammed (goods waiting at a flag, or a carrier on it nearly all the time). Click a road while it shows to hear what goes on there and what might help. Each game second it notes where your carriers are; older notes fade (a tenth every 10 seconds), so it follows the town as it changes. Only the interface: the game itself is not touched, and nothing of it is saved. |
| `scripts/ui_undo.gd` | 115 | Undo (Ctrl+Z): takes back the last building placed, road laid or building demolished, if it was within the last 10 seconds, with everything paid back: a site's materials (delivered or used), a road's bridge planks, and for a demolished building the goods it gave back are taken again and it stands as before (its workers and soldiers come back by themselves). |
| `scripts/version.gd` | 18 | The game's version. Run `python3 tools/bump_build.py` before every release: it raises BUILD by one, updates DATE and copies the version into project.godot and the Windows export settings. |

## Data

| File | Lines | What it is |
|---|---:|---|
| `data/buildings.json` | 2268 | Every building: name, group, size, cost, build time, worker, inputs and outputs, work cycle, garrison, store room, art style and info text. |
| `data/campaign.json` | 397 | The campaign: its chapters, their place on the campaign map, story before and after, what carries over, and the mission of each. |
| `data/lang_de.json` | 275 | German translation of the interface. |
| `data/map_iron_coast.json` | 1 | The hand-made map of the Iron Coast mission (made by tools/make_mission_map.gd). |
| `data/missions.json` | 63 | The missions: story, map or seed, rivals, options, time limit and goals. |
| `data/needs.json` | 13 | What each class of people (peasants, artisans, nobles, soldiers) uses up to stay content. |
| `data/resources.json` | 503 | Every good: name, icon shape, colour, store room and info. |
| `data/techs.json` | 155 | The research tree: techs, ages, costs, what each unlocks or improves. |
| `data/trades.json` | 67 | The trades (woodland, mining, farming...): their names, tools and levels. |

## Shaders

| File | Lines | What it is |
|---|---:|---|
| `shaders/ground.gdshader` | 52 | Draws the ground: the baked map pictures on the raised mesh, moving water, day and night. |

## Tools: automatic tests

| File | Lines | What it is |
|---|---:|---|
| `tools/age_test.gd` | 58 | Tests the looks of the ages, renovation and soldier kinds. Run: godot --headless --script res://tools/age_test.gd |
| `tools/ai_roads_test.gd` | 18 | Rival realms' buildings all get roads (entrances and all): godot --headless --script res://tools/ai_roads_test.gd |
| `tools/ai_space_test.gd` | 45 | Where rival realms run out of room: godot --headless --script res://tools/ai_space_test.gd [-- seed=perf mins=20] |
| `tools/archer_test.gd` | 45 | Archers shoot attackers on the way in, take bows from the stores; sallies meet attacks in the open: godot --headless --script res://tools/archer_test.gd |
| `tools/battle_test.gd` | 59 | Battles between kinds of soldier: an attack of A soldiers of one kind on a hut held by D of another, repeated many times, prints how often the attackers take it and how many fall on each side. Run: godot --headless --script res://tools/battle_test.gd |
| `tools/bridge_test.gd` | 54 | Bridges: roads across narrow water, paid in planks; too wide water is refused: godot --headless --script res://tools/bridge_test.gd |
| `tools/campaign_test.gd` | 47 | The campaign: chapters open one after another, a won chapter is recorded and carries soldiers over. xvfb-run -a godot --rendering-driver opengl3 --script res://tools/campaign_test.gd -- out=/dir |
| `tools/catapult_test.gd` | 44 | A catapult wears down an enemy fort: godot --headless --script res://tools/catapult_test.gd |
| `tools/claim_test.gd` | 74 | Boundary stones claim free land without soldiers, and lose it to soldiers: godot --headless --script res://tools/claim_test.gd |
| `tools/climate_test.gd` | 63 | Plays the same all-AI game twice for 30 minutes: once with the default features (seasons, clothes...), once with classic rules, and prints the climate and each realm's growth so the balance can be compared. Run: godot --headless --script res://tools/climate_test.gd -- [min=30] [seed=climate] |
| `tools/content_test.gd` | 35 | Taverns, chapels, contentment and festivals: godot --headless --script res://tools/content_test.gd |
| `tools/crop_test.gd` | 91 | Farms sow a chosen crop; seeds come from research; crops keep their seasons: godot --headless --script res://tools/crop_test.gd |
| `tools/door_test.gd` | 54 | Entrances: roads join buildings only at the door. godot --headless --script res://tools/door_test.gd |
| `tools/feature_test.gd` | 31 | Tests the feature system: statistics counting, saving and loading feature data, switching a feature off, and a mod loaded from the mods folder. |
| `tools/field_test.gd` | 39 | Columns that meet on the march fight in the open: godot --headless --script res://tools/field_test.gd |
| `tools/fire_test.gd` | 45 | Fires spread between wooden buildings and burn them down; wells nearby put them out: godot --headless --script res://tools/fire_test.gd |
| `tools/fog_test.gd` | 43 | Tests carried building materials, the fog of war, scouts and watch towers. Run: godot --headless --script res://tools/fog_test.gd |
| `tools/fogsave_test.gd` | 49 | Explored land survives saving and loading through the game's own save files: xvfb-run godot --rendering-driver opengl3 --script res://tools/fogsave_test.gd |
| `tools/full_test.gd` | 29 | Full stores stop production: godot --headless --script res://tools/full_test.gd |
| `tools/garrison_test.gd` | 51 | Garrison settings: how many soldiers, which kinds, who stays home: godot --headless --script res://tools/garrison_test.gd |
| `tools/geo_test.gd` | 44 | Tests geologists: ore hidden until surveyed, mines only on surveyed ore, a survey trip, rivals surveying. Run: godot --headless --script res://tools/geo_test.gd |
| `tools/load_saves_test.gd` | 34 | Loads every save in the saves folder (user://saves) and plays each on for a minute: old saves must still load. godot --headless --script res://tools/load_saves_test.gd |
| `tools/log_go_test.gd` | 34 | Checks the Go buttons of the event log: xvfb-run godot --rendering-driver opengl3 --script res://tools/log_go_test.gd -- out=/dir |
| `tools/menu_test.gd` | 44 | Lists what each tab of the Build panel shows, for a new game and for a loaded older save, and names every building that appears in no tab. Run: godot --headless --script res://tools/menu_test.gd -- [save=path] |
| `tools/mission_test.gd` | 55 | Missions and hand-made maps: every mission in data/missions.json starts, its goals are counted, a mission is won when its goals are met and lost at its deadline, and a game on a hand-made map saves and loads the same. godot --headless --script res://tools/mission_test.gd |
| `tools/net_test.gd` | 33 | Checks that updating road networks step by step gives exactly the same walking distances as rebuilding them from scratch, every 10 game seconds of an AI-only game. |
| `tools/oldsave_test.gd` | 28 | A save from before build 31 (one shared stock) loads with its goods in the stores: run with "-- make=/path" in the old game folder, then "-- load=/path" in this one. |
| `tools/options_test.gd` | 26 | New-game options: all research done, creative mode; and how steep the land is: godot --headless --script res://tools/options_test.gd |
| `tools/overflow_test.gd` | 77 | Quick check for text off screen: opens the main windows at a few window sizes and lists visible controls that reach past the window, and labels/buttons whose text is wider than they are. |
| `tools/perf_test.gd` | 39 | Simulation cost in a big game: godot --headless --script res://tools/perf_test.gd [-- foes=7 mins=60] Prints, every 10 game minutes, the time per game second spent in each part of the simulation. |
| `tools/reach_test.gd` | 27 | Building spots no road can reach are refused: every spot that passes can_place finds a road route. godot --headless --script res://tools/reach_test.gd |
| `tools/research_ai_test.gd` | 21 | Plays 70 minutes with computer realms only and prints how far each got in research, and how many levels of repeatable studies each took: godot --headless --script res://tools/research_ai_test.gd |
| `tools/research_test.gd` | 30 | The research queue and repeatable studies: godot --headless --script res://tools/research_test.gd |
| `tools/research_ui_test.gd` | 113 | Drives the research window with real mouse and key events and prints what happened. |
| `tools/rules_test.gd` | 55 | Tests the build 11 rules: difficulty options, tools for new workers, the toolsmith's choice and production targets. |
| `tools/run_all.py` | 106 | Run every automatic test and say which passed. |
| `tools/save_test.gd` | 33 | Save/load round trip: play, save, load into a fresh Sim, then check both continue identically. |
| `tools/sea_test.gd` | 95 | Ships and harbours: a harbour on your coast, an expedition founds a colony across the water, ships then carry goods there, and a game with ships at sea saves and loads the same. godot --headless --script res://tools/sea_test.gd [-- seed=valley] |
| `tools/settings_test.gd` | 41 | Tests the Settings window: display mode, resolution, interface size, a renderer trial that fails, and continuing the autosaved game after a restart. Run it twice: first with "-- step1", then "-- resume". |
| `tools/sim_test.gd` | 60 | Headless check: godot --headless --script res://tools/sim_test.gd Plays a game where every realm, including yours, is run by the AI, and prints progress. |
| `tools/site_test.gd` | 25 | Do carriers bring materials to a new construction site? godot --headless --script res://tools/site_test.gd |
| `tools/soak_test.gd` | 81 | A long game with every rival (and you played by the AI) to catch errors and broken rules: godot --headless --script res://tools/soak_test.gd -- seed=valley mins=60 Every minute it checks: stock equals the sum of the stores, no negative stocks or people, no dead building still listed, every building on its tile, archers never above the garrison, carts and fires only for living buildings. It prints what it saw of the new things (trades, fires, bridges...). |
| `tools/sound_test.gd` | 36 | Checks the sound system: every sound loads, effects play, ambience fades in, and news in the log picks the right sound. Run: godot --headless --script res://tools/sound_test.gd |
| `tools/stores_test.gd` | 29 | Goods kept in each store: godot --headless --script res://tools/stores_test.gd [-- mins=15] |
| `tools/stretch_test.gd` | 54 | Road carriers mode (one carrier per stretch of road): goods still get through, loads wait at flags on busy roads, stock matches the stores, and a saved game goes on exactly the same. godot --headless --script res://tools/stretch_test.gd |
| `tools/toolbar_tool_test.gd` | 35 | The toolbar's feature tools work whatever building group was open last: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/toolbar_tool_test.gd |
| `tools/touches_test.gd` | 70 | The smaller touches of build 37: undo, town names, follow camera, minimap filters, map packs. xvfb-run -a godot --rendering-driver opengl3 --script res://tools/touches_test.gd |
| `tools/trade_test.gd` | 60 | Trade by cart between markets, standing offers, and war on the way: godot --headless --script res://tools/trade_test.gd |
| `tools/transfer_test.gd` | 39 | Goods move between stores: godot --headless --script res://tools/transfer_test.gd |
| `tools/ui_test.gd` | 169 | Headless UI smoke test: new game with a chosen map size, build through the click handler, research, save, load, and the tech/save/texture panels. |
| `tools/walk_test.gd` | 38 | Builders and soldiers walk to their buildings: godot --headless --script res://tools/walk_test.gd |
| `tools/weapon_test.gd` | 60 | Weapons wear out in fights and are replaced from the stores; worn weapons fight worse: godot --headless --script res://tools/weapon_test.gd |

## Tools: screenshots

| File | Lines | What it is |
|---|---:|---|
| `tools/anim_shot.gd` | 48 | Records short frame sequences of the animations for checking and for animated previews. Run: godot --rendering-driver opengl3 --script res://tools/anim_shot.gd -- out=/some/folder Plays an AI-run realm for a while, then films a few busy spots frame by frame while the game clock moves on a little between frames. Writes <spot>_<frame>.png files. |
| `tools/shot.gd` | 54 | Renders screenshots: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot.gd -- out=/path/dir |
| `tools/shot_ages.gd` | 44 | Screenshots of building looks from different ages, renovation and soldier kinds. xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_ages.gd -- out=/dir |
| `tools/shot_b33.gd` | 81 | Build 33 interface additions: the first-game guide, expand hints while placing a military building, the workshop input setting and walkers' arrival times, keys in Settings, and save thumbnails. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_b33.gd -- out=/dir |
| `tools/shot_b34.gd` | 69 | Build 34 additions: the Problems list with minimap alerts, and the attack window. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_b34.gd -- out=/dir |
| `tools/shot_b37.gd` | 108 | Build 37 additions on a town grown for 12 minutes: fire, a workshop's history, archers, trade, the minimap filter and town names, achievements, and a tavern's festival. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_b37.gd -- out=/dir |
| `tools/shot_b38.gd` | 44 | Build 38 screenshots: a farm's crop choice, and worn weapons in a tower: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b38.gd -- out=/dir |
| `tools/shot_battle.gd` | 69 | Screenshots of a battle: a column of riflemen and musketeers firing on the way in, pikemen and musketeers in the hut firing back, then the fight at the gate. xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_battle.gd -- out=/dir |
| `tools/shot_bridge.gd` | 39 | A bridge over a channel, with carriers going over it. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_bridge.gd -- out=/dir |
| `tools/shot_carriers.gd` | 38 | Road carriers mode: loads waiting at flags on busy roads. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_carriers.gd -- out=/dir |
| `tools/shot_demolish.gd` | 46 | Screenshot of the demolish question for a border building: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_demolish.gd -- out=/dir |
| `tools/shot_detail.gd` | 45 | Ground details and day and night: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_detail.gd -- out=/dir |
| `tools/shot_door.gd` | 96 | Screenshots of building entrances, manual roads and the Go buttons in the event log: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_door.gd -- out=/dir |
| `tools/shot_editor.gd` | 52 | The map editor: ore painted onto a mountain shows at once, and a stroke re-bakes only what changed. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_editor.gd -- out=/dir |
| `tools/shot_features.gd` | 100 | Screenshots of the optional features: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_features.gd -- out=/dir Plays an AI-run realm through a year and saves pictures of summer, rain, winter snow and the windows. |
| `tools/shot_field.gd` | 33 | Screenshot of a battle in the open: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_field.gd -- out=/dir |
| `tools/shot_fields.gd` | 30 | Screenshot of a farm with its fields: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_fields.gd -- out=/dir |
| `tools/shot_fog.gd` | 61 | Screenshots of the fog of war, a scout, a watch tower and construction sites waiting for materials. xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_fog.gd -- out=/dir |
| `tools/shot_folk.gd` | 30 | Frames of the town close up, for a moving picture of townsfolk and carriers: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_folk.gd -- out=/dir |
| `tools/shot_garrison.gd` | 31 | Screenshot of the garrison settings: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_garrison.gd -- out=/dir |
| `tools/shot_geo.gd` | 62 | Screenshots of geologists at work, their markers, surveyed ore shown while placing a mine, and wildlife. xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_geo.gd -- out=/dir |
| `tools/shot_hide.gd` | 41 | Hiding problems in the Problems list. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_hide.gd.gd -- out=/dir |
| `tools/shot_hills.gd` | 34 | Screenshot of hilly land with roads (slope marks): xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_hills.gd -- out=/dir |
| `tools/shot_lang.gd` | 24 | The interface in German: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_lang.gd -- out=/dir |
| `tools/shot_missions.gd` | 53 | The map editor, the missions list and a mission being played. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_missions.gd -- out=/dir |
| `tools/shot_raised.gd` | 43 | Raised ground (2.5D) on and off, same view: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_raised.gd -- out=/dir |
| `tools/shot_research.gd` | 37 | Screenshots of the research window: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_research.gd -- out=/dir |
| `tools/shot_scenery.gd` | 45 | Trees, peaks and boulders standing on hilly ground, close up and further out. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_scenery.gd -- out=/dir tag=new |
| `tools/shot_sea.gd` | 67 | An expedition at sea and the colony it founds. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_sea.gd -- out=/dir |
| `tools/shot_sites.gd` | 27 | The Sites button showing building places: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_sites.gd -- out=/dir |
| `tools/shot_sizes.gd` | 113 | Screenshots of building sizes and site markers: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_sizes.gd -- out=/dir |
| `tools/shot_stats.gd` | 38 | Statistics: realms compared, and the border replay. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_stats.gd -- out=/dir |
| `tools/shot_stone.gd` | 49 | Boundary stones: one built at the border, another being placed with the land it would claim. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_stone.gd -- out=/dir |
| `tools/shot_stores.gd` | 80 | Pictures of goods in each store, people waiting in homes and a lodge, and inputs at a workshop: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_stores.gd -- out=/dir |
| `tools/shot_toolbar.gd` | 51 | Screenshots of the bottom toolbar: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_toolbar.gd -- out=/dir |
| `tools/shot_toolbar_small.gd` | 24 | The toolbar in a 1280 x 720 window (compact, icons only): xvfb-run ... --script res://tools/shot_toolbar_small.gd -- out=/dir |
| `tools/shot_traffic.gd` | 37 | The traffic map on a town that grew for 12 minutes, with a jammed road clicked. xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_traffic.gd -- out=/dir |
| `tools/shot_walk.gd` | 62 | Pictures of a builder and soldiers walking to their buildings: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_walk.gd -- out=/dir |
| `tools/shot_worker.gd` | 56 | A new worker walking from his home to his job: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_worker.gd -- out=/dir |

## Tools: benchmarks and diagnostics

| File | Lines | What it is |
|---|---:|---|
| `tools/ai_bench.gd` | 62 | Rival AI benchmark: godot --headless --script res://tools/ai_bench.gd [-- seed=valley mins=30] Seven rivals (and an idle human). Prints each rival at the end, how much it grew in the last 10 minutes, why its workshops wait, and one summary line to compare versions by. |
| `tools/ai_stuck.gd` | 34 | Why a rival stops building: godot --headless --script res://tools/ai_stuck.gd [-- who=1 mins=20] |
| `tools/battle_forts.gd` | 55 | Forts: the same attack on each military building (walls and cannon). Battles between kinds of soldier: an attack of A soldiers of one kind on a hut held by D of another, repeated many times, prints how often the attackers take it and how many fall on each side. Run: godot --headless --script res://tools/battle_test.gd |
| `tools/bench.gd` | 74 | Performance benchmark. Simulation only:  godot --headless --script res://tools/bench.gd With drawing (needs a display):         godot --script res://tools/bench.gd -- draw Plays a heavy game (200-tile map, 8 rivals, every realm run by the AI) and prints timings. |
| `tools/carriers_compare.gd` | 20 | The same game with and without road carriers: how far each realm gets. godot --headless --script res://tools/carriers_compare.gd [-- seed=showcase mins=15] |
| `tools/chain_diag.gd` | 29 | Where the iron chain chokes for rivals: godot --headless --script res://tools/chain_diag.gd [-- seed=valley mins=25] |
| `tools/checksum_diff.gd` | 42 | Finds what differs between a game and the same game saved and loaded, after both run on. godot --headless --script res://tools/checksum_diff.gd [-- seed=savetest at=10 more=5] |
| `tools/checksum_run.gd` | 17 | Plays a game with rivals only and prints the state checksum each minute. Two versions that should behave the same (a pure code move, say) must print the same numbers. godot --headless --script res://tools/checksum_run.gd [-- seed=valley mins=6] |
| `tools/econ_diag.gd` | 26 | What buildings wait for: godot --headless --script res://tools/econ_diag.gd [-- seed=valley mins=12] |
| `tools/food_diag.gd` | 34 | Why a rival goes hungry: godot --headless --script res://tools/food_diag.gd [-- who=1] |
| `tools/make_mission_map.gd` | 38 | Makes data/map_iron_coast.json, the hand-made map of mission 3, the way the map editor would: a generated map with an iron ridge (two passes) between your start in the south and the rivals. godot --headless --script res://tools/make_mission_map.gd |
| `tools/rel_diag.gd` | 21 | Diagnosis of how rivals see each other after 22 minutes on the valley map: crowding, reserve, strength, and the nearest distance between their military buildings (why they go to war or not). godot --headless --script res://tools/rel_diag.gd |
| `tools/render_bench.gd` | 73 | Measures where frame time goes with the current renderer. Run: godot --rendering-method <gl_compatibility\|forward_plus\|mobile> --script res://tools/render_bench.gd -- [w=1600] [h=900] [label=...] Prints which renderer and graphics adapter actually run (Godot falls back to OpenGL when Vulkan is missing), then for a few scenes the average frame, the time the CPU spends on game logic and script drawing ("process"), and the renderer's own CPU and GPU time per frame. |
| `tools/rival_check.gd` | 75 | How rival realms cope with local stores, carried inputs and walking workers: godot --headless --script res://tools/rival_check.gd [-- seed=valley mins=30] |
| `tools/roadprobe.gd` | 25 | Road quality in an AI-only game: road tiles per building, average walk to the nearest store, and how long road work took. |
| `tools/route_diag.gd` | 42 | Why new buildings find no road route: godot --headless --script res://tools/route_diag.gd |
| `tools/size_stats.gd` | 19 | How much of a new realm's land takes small, medium and large buildings: godot --headless --script res://tools/size_stats.gd |
| `tools/toolprobe.gd` | 26 | An AI-only game: are realms held up by missing tools? Prints, every 10 minutes, each realm's size, buildings waiting for a tool, tools in stock, toolsmiths and research. |
| `tools/ui_soak.gd` | 54 | The interface through a long game: every few game seconds a frame is drawn with something else on (traffic map, minimap filters, a followed carrier, fires, an info box, the windows), to catch errors in drawing and windows. xvfb-run -a godot --rendering-driver opengl3 --script res://tools/ui_soak.gd -- mins=25 |
| `tools/war_check.gd` | 40 | Do rivals whose land is full fight for more? godot --headless --script res://tools/war_check.gd [-- seed=valley mins=40] |
| `tools/zoom_bench.gd` | 38 | Drawing cost at different zoom levels in a busy game: xvfb-run godot --rendering-driver opengl3 --script res://tools/zoom_bench.gd |

## Tools: making textures, sounds and releases

| File | Lines | What it is |
|---|---:|---|
| `tools/bump_build.py` | 53 | Raise the build number before a release. |
| `tools/check_data.py` | 104 | Check the data files (and optionally a mod's JSON files) for mistakes. |
| `tools/extract_strings.py` | 76 | Collect the interface text from the scripts into the translation files. |
| `tools/file_list.py` | 134 | Writes docs/FILES.md: every source file of the project with what it is for. |
| `tools/folk_sprites.py` | 382 | Townsfolk, porters, workers, pack mules and ox carts, drawn in detail. Run on its own (python3 tools/folk_sprites.py) or from make_textures.py; it writes the unit_folk_*, unit_porter*, unit_worker_*, unit_mule, unit_cart and unit_load_* strips into textures/. Everything is drawn in design pixels with make_textures' Pen, so edges come out smooth. Strips that the game tints with the realm's colour come with a *_tint companion: the tunic alone, in grey, drawn over the picture in the realm's colour. |
| `tools/make_build.py` | 224 | Make a release build of Hearthlands in one go. |
| `tools/make_scenery.py` | 251 | Trees, mountain peaks and boulders for the map, drawn with light and shade so they look round. |
| `tools/make_sounds.py` | 247 | Generate Hearthlands' sound effects and ambience loops into ../sounds (16-bit mono WAV). |
| `tools/make_textures.py` | 1580 | Generate Hearthlands' default textures into ../textures. |
| `tools/readme_tables.py` | 128 | Rebuilds the Resources, Buildings and Research tree tables in README.md from the data files. |

## Project and documents

| File | Lines | What it is |
|---|---:|---|
| `CHANGELOG.md` | 489 | What changed in each build. |
| `README.md` | 868 | How to play, the rules, controls, settings, modding and the project layout. |
| `docs/FILES.md` | 260 | This list (written by tools/file_list.py). |
| `docs/SOURCE_GUIDE.md` | 439 | A tour of the code for programmers: the parts, how a game tick runs, where things live. |
| `docs/SUGGESTIONS.md` | 203 | Ideas and their status after each round of work. |
| `export_presets.cfg` | 61 | Godot export settings for the Windows and Linux builds. |
| `main.tscn` | 12 | The one scene: a Node with scripts/main.gd, which builds the whole interface in code. |
| `mods_examples/bountiful_harvest.gd` | 40 | A small example mod: a feature that makes farms faster (copy it to the mods folder). |
| `project.godot` | 24 | Godot project settings: name, version, main scene, window and renderer options. |
