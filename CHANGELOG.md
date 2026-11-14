# Changelog

## Build 43.2 (v0.38.0, 2026-11-14)

Fix for the plain green map when zoomed out.

- Zoomed out (below about 10 pixels a tile) the map was drawn from the minimap's flat colours: one bright green, no trees, roads or texture, in OpenGL and Vulkan alike. It now uses ground baked at a quarter of the size, with grass, roads, borders and forests, at every zoom; trees are drawn one by one down to a closer zoom than before.
- A bridge picture at the smallest size no longer logs errors.

## Build 43.1 (v0.38.0, 2026-11-14)

Fixes for graphics glitches and the Vulkan switch.

- Vulkan: choosing Vulkan in Settings now works. The game did start with Vulkan, but then could not tell which renderer it was running and went back to OpenGL with "Vulkan could not start". The first-start Vulkan test had the same fault and never switched.
- The "Start in OpenGL safe mode" shortcut no longer runs the Vulkan test.
- An attack on your land no longer turns the whole screen red: a short red glow shows along the screen's edges instead, at most once every 20 seconds.
- No more white dashes along the shores: the foam is drawn only by the moving waves now.
- The fisher's hut on stilts no longer has a blue box of water drawn under it, only ripples round its piles.
- Building shadows are smaller and softer, so they no longer leave dark smudges beside buildings (most visible on water).

## Build 43 (v0.38.0, 2026-11-14)

A special study at the end of each age opens the next one.

Ages
- Five new studies open the ages: The new kingdoms (Early Medieval), Rise of the towns (High Medieval), Rebirth of learning (Renaissance), Age of reason (Enlightenment) and Dawn of industry (Industrial). Each gives a small bonus of its own.
- Every tech of an age needs its opening study, and the study needs a number of techs of the age before (8 for the medieval ages and the Renaissance, 7 after that). Entering a new age is now a choice you make, not a side effect of one cheap tech.
- In the research tree each opening study stands in its own column with a gold band; its card shows how many of the needed techs you have, and the details list them.
- "Queue the way there" for a later tech also queues the cheapest techs needed to open the age.
- Saved games keep working: a realm already in an age gets its opening study.

Fixes
- The archer test no longer fails on one unlucky fight.

## Build 42 (v0.37.0, 2026-11-14)

More detailed textures everywhere, and buildings that each look like their trade.

Buildings
- 72 buildings that used to be the same house in another colour now have their own shape and the tools and goods of their trade: a log on the saw trestle at the sawmill, a bread oven at the bakery, a copper and barrels at the brewery, an open forge and grindstone at the toolsmith, weapon racks, armour stands, hides on frames, cloth drying, a slipway with a ship at the shipyard, a factory with a cog and tall stacks, a textile mill with rows of windows, a tavern with two floors and a tankard sign, a bathhouse with a dome...
- Farms: fruit trees, hop poles and an oast house, sheep and pigs in their pens, flax, vines, a granary on stones, donkeys in a paddock, a cow at the dairy.
- Small workplaces: a chopping block, a tree nursery, a clay pit, salt pans, beehives, sand heaps, a lookout platform.
- Furnaces: a smoking charcoal mound, a bloomery shaft, a bottle furnace, a glass cone, a steel converter.
- Halls and castles: a log lodge, a chapel with a spire, a cloister, a library with columns and a dome, a manor, a university with a clock tower, a walled fortress, a fortified depot.
- Mines show their ore (coal, iron, gold, copper); the keep, watch tower, guardhouse, redoubt and paper mill (with a water wheel) have their own look.
- Smoke and furnace glow come from the new chimneys and fire mouths.

Textures
- Walls, roofs and doors are drawn with real materials: stone blocks, bricks, plaster, timber framing, planks, roof tiles, slates and thatch, in the style of each age.
- The ground has more detail and is drawn at double resolution when you zoom in close; hills and mountains are shaded by their slope.
- New pictures for the research tree.

## Build 41 (v0.36.0, 2026-11-14)

Better graphics, a much bigger map editor, ruins and bandit camps, music and new sound, and a faster game.

Sound and music
- Music: four calm pieces (harp, lute, recorder, fiddle) in turn with silence between them, a war theme while your land is attacked or your soldiers fight, and cues for a new age, victory and defeat. Its own volume in Settings.
- Sounds of the world come from where they happen on screen, left or right, quieter further off: axes, saws, anvils, picks, spades, nets, mill wheels, building sites, falling trees, cows, sheep, pigs, the chapel bell, wolves, battles, volleys, marching columns.
- The ambience follows what you look at and the weather there: birds over meadows and forests, waves on a shore, wind over mountains and in winter, rain and thunderstorms, crickets in summer, a town's bustle, the din of a battle, burning buildings.
- Sounds for windows, roads and a building site that can't go where you clicked.

Graphics
- Soft shadows under buildings, people and trees; trees and crops sway in the wind (harder in a storm); drifting cloud shadows and foam on the shores.
- Fields drawn as ploughed plots with rows of crops that grow and ripen; birds over the land; fishermen in boats.
- Work shows: chips fly from axes and picks, seeds and chaff on farms, sparks and dust from builders, trees fall, a finished building puffs dust.
- Battles: soldiers fight in front of the gate, arrows fly from archers, banners and up to five figures on a column, soldiers fall.
- A clear "!" badge on idle buildings.

Map editor
- Tabs: Paint, Map, Starts, Mission, Check.
- Undo and redo (Ctrl+Z, Ctrl+Y); round or square brushes from 1 to 15 tiles; mirrored painting (left-right, top-bottom, four ways, turned) for fair maps.
- Fill bucket, smoothing, rivers with fords, copy and paste (turned or mirrored).
- Climate painting (temperate, taiga, steppe, wetland), ruins and bandit camps.
- Open saved maps, and make new ones with a seed, a size, starts and landscape settings (island, continent, lakes, archipelago; water, mountains, forests, ore, landform size).
- Set up each start: a name, more or fewer goods, extra soldiers, the rival's strength and manner.
- Write missions with goals on your map, save them to the Missions list or play them at once.
- Check: what lies around each start, so you can make the starts fair.
- Bigger maps: Colossal (320), Titanic (384) and Vast (448).
- Landscape settings on the new-game screen too.

Ruins and bandit camps
- The first realm whose land reaches ruins finds planks, stone, gold and tools there.
- Nobody builds next to a bandit camp, and the bandits steal from realms nearby. Click a camp to send soldiers; clearing it gives its gold and weapons. Rivals clear camps too.

Faster
- The game runs about 20% faster in a big late game (rivals choose building spots much faster, workers' speed is worked out only when work starts).
- No more stutters on big maps when borders move (the minimap and the fog redraw only what changed). Big maps load faster.

Fixes
- Map editor: clearing things over water no longer empties its fish.
- Bandit camps hidden in the fog can't be clicked.

## Build 40 (v0.35.0, 2026-11-13)

Fixes and features from the playtest list.

Military
- Soldiers no longer walk on water: columns march round lakes and rivers and over bridges. A building with water all round can't be attacked by land; the attack window says so.
- Military buildings react to enemy columns passing by: their archers shoot, and one set to "March out" sends soldiers to stop the column in the open.
- Fixed: after one attack you could not attack again. Survivors of a won attack now go back to the building they came from, and clicking an enemy building you can't attack says why.
- Archers are extra to the soldiers: up to half as many as the soldiers inside, not counted as soldiers.
- Upgrade a military building where it stands (a guardhouse to a tower, a keep to a castle...): its soldiers stay inside. Rivals upgrade their border buildings too.
- Border priority: inland military buildings can hold fewer soldiers (75%, 50%, 25%), and new soldiers go to the border first.
- Rivals at peace grow tired of a neighbour whose land touches theirs (a warlord fast, a builder hardly) and, when stronger, warn and then declare war. Gifts and trades win them back.

Economy
- Buildings window (J): how many buildings of each kind you have, how many work and how many wait for a worker, a priority for a whole kind, a limit on workers per kind, and Next to jump to them.
- Keep one builder free for new building sites.
- Move building: build it again somewhere else; the old one works until the new one is done and hands over its settings.
- Farms: a crop for each season, and "Use for all farms".
- The geologist's work area shows while sending him: the ring he surveys and the tiles he would visit.

Interface
- Research complete messages say what the study brings; new buildings are marked NEW on the toolbar until you pick them.
- Confirm windows before starting a new game or loading over a game in play, and before deleting a save.
- Map editor: ore amounts (poor to very rich, and Set ore amount for ore already painted), and animals you place (deer, boar, hare, wolf).

Fixes
- Fixed: random explored patches on the map (the fog saw the buildings of the game before when a game was started or loaded).
- Fixed: deleting roads on land that changed hands. A road on land you take is now yours.
- Late game drawing is faster: carriers off screen are skipped, entrance flags and the weather are cheaper, and the building spots are worked out a few rows a frame, so turning a building's entrance no longer stalls.
- The F3 overlay keeps the simulation time while paused and shows the real game speed; the speed button turns orange when the computer can't keep up with the speed chosen.

## Build 39 (v0.34.0, 2026-11-09)

Farms work real fields.

- A farm sows up to 6 fields on open grass in its work area (7 tiles across; Move work area moves it) and harvests each when ripe, sowing it again. A field takes about a minute to ripen, faster in summer and slower in autumn; a crop out of season does not grow, so a field sown late waits for spring.
- Fields show on the map: furrowed soil when sown, green rows as they grow, the crop's colour when ripe. The farmer walks out to them.
- A farm's info box says how many fields are sown and ripe, and when the next will be ripe.
- A building or road put on a field ends it; foresters don't plant trees on fields.
- Fixed: a building spot could be offered where the only way for a road went through the new building's own plot.

## Build 38 (v0.33.0, 2026-11-09)

Weapons that wear out, and farms that choose their crop.

- Weapons wear out: each fight may wear out a soldier's weapon (1 in 10). Worn weapons fight about 12% worse until new ones come from the stores, one a second per building. A military building's info box and the People panel say how many are worn. Bows break now and then after a volley; the archer takes a new one.
- Farms choose their crop in the info box: wheat from the start; winter rye, vegetables, potatoes, flax and hops come as seeds from research (Heavy plough, Open-field farming, New World crops, Wool trade, Monasteries). The research window lists the seeds a study unlocks.
- Crops have seasons: wheat, vegetables and potatoes stand idle in winter, hops grow only in summer and autumn, rye grows all year but gives less. Orchards, vineyards, hop and flax farms and apiaries rest in winter.
- With the Three-field system a farm can sow winter rye while its own crop is out of season.
- Vegetables: a new food straight from the field, no mill or bakery needed.
- Rivals sow food crops on some farms and switch to rye in winter.

## Build 37 (v0.32.0, 2026-11-09)

The second list of ideas (all but blueprints), and fixes.

- Trade: build a market, then trade in the Diplomacy window, which says whether the realm would accept and how long the carts take. Goods go by cart market to market and are lost if war breaks out on the way. "Repeat every 5 minutes" makes a standing offer. Rivals build markets and trade with each other.
- Bridges: roads cross up to 3 tiles of water straight across, 2 planks a tile; paving makes a stone bridge. The far shore counts as reachable, so rivals and auto roads build bridges too.
- Taverns and chapels: homes near a working tavern (beer and bread) or chapel (candles) are content, and content people work up to 10% faster; hunger and sickness pull the other way. Taverns hold festivals (+10% work for 3 minutes). Unhappy realms lose idle peasants.
- Archers and sallies: a bowyer makes bows. Set how many of a military building's soldiers are archers; they shoot attackers from 6 tiles out but fight worse at the gate. "March out to meet attackers" sends soldiers to fight a column in the open.
- Traffic map (F7, or Traffic): roads coloured free, busy or jammed; click a road for what is stuck there and what might help.
- Campaign: 8 chapters on a map with a story before and after each; a won chapter opens the next and carries soldiers or goods over; best time and score are kept.
- Spreading fires: fire jumps between wooden buildings and burns them down. Wells nearby send a person with a bucket, a fire station three. Stone and brick buildings don't catch; catapult stones can start fires.
- Ctrl+Z undoes the last building, road or demolition within 10 seconds. I goes to the next building with nobody working, then the next stuck one.
- A building's info box shows what it made in the last 30 minutes, a bar a minute.
- The minimap can show only roads, only land and forts, or only the buildings making one good.
- Click a carrier, cart, ship or soldier column to follow it with the camera.
- 15 achievements, kept between games (Achievements on the new-game screen).
- 16x speed (key 5). Colour-blind colours in Settings.
- Rivals warn you before war, thank you for trades, and a much stronger rival may demand tribute.
- Every store is a town with a name on the map and in messages; rename it in its info box.
- Snow slows carriers on unpaved roads in winter.
- Maps and missions can be exported and imported as .hlpack files (map editor and Missions window).
- Fixed: a captured harbour's goods stayed counted with the old owner; land not updated when a military building burned; reaching over bridges longer than one tile.

## Build 36 (v0.31.0, 2026-11-08)

- Boundary stones (Military group): claim free land 4 tiles around without any soldier, for 3 stone and a plank. A stone must stand on land your soldiers hold, so stones can't be chained across the map. It holds only land no soldiers hold: a rival's military building that reaches its land takes that land, and the stone falls if its own tile goes. Rivals with no soldiers to spare set them too.
- Problems list: hide a warning with its x, or all of them with Hide all. A hidden warning stays out of the list, the count and the minimap until its reason changes (changing numbers, like "29 of 30", don't count); Show hidden and Unhide all bring them back.
- Infirmaries with no patients are no longer listed as a problem.

## Build 35 (v0.30.0, 2026-11-08)

- Trees, mountain peaks and boulders stand upright on the hills instead of being bent and stretched with the raised ground.
- New pictures for them, twice as detailed and shaded so they look round: firs, spruces, oaks, limes and birches (two more kinds of tree), peaks with a lit and a shaded side, boulders with soft shadows.
- Woods grow in patches of one kind (firs here, broad-leaved trees there), and each tree is a little bigger or smaller, lighter or darker and off the tile's centre, so forests no longer look stamped.
- Map editor: ore you paint shows at once, and painting redraws only the part of the map that changed instead of the whole map.
- The map editor takes the side panel's place, so it no longer covers the map.

## Build 34 (v0.29.0, 2026-11-08)

The eight ideas from the "what next" list, and smaller touches with them.

- Problems list (P): every building that is stuck and why, with alerts on the minimap. Click one to go there.
- Attack window: choose how many soldiers attack and of which kinds, with the odds shown.
- Production chain window: who makes a good, what goes into it and who uses it, with rates and the weakest link.
- Catapults: a catapult near the border throws stones at enemy forts in range; each hit may kill a defender. Rivals build them at war.
- Road carriers: set your own flags on roads (Flag tool) to split long stretches; a donkey farm breeds donkeys that help on busy stretches. Rivals place flags on jammed stretches.
- Ships and harbours: a shipyard on the coast builds ships; from a harbour, an expedition (a ship, 4 planks, 2 stone and a soldier) founds a colony on another free coast, and ships carry goods between harbours no road joins. Rivals sail when their land is crowded.
- Missions: four missions with goals and time limits, shown in the guide box; "The Iron Coast" is played on a hand-made map.
- Map editor (on the new-game screen): paint ground, trees, rocks, clay and ore, move the start places, save maps and play them. Saved maps can be picked on the new-game screen.
- Statistics: realms compared (land, techs, a ranking table) and a replay of how the borders changed, also on the end screen.
- Q copies the selected building into placing mode.
- Ground details (tufts, flowers, pebbles, reeds, shore foam, snow on peaks) and an optional day and night.
- Fixed: building flags floated above small buildings; a game loaded from a save could drift from the original after a while (the tick rhythm is now saved).

## Build 33 (v0.28.0, 2026-11-08)

Everything from the suggestions list (docs/SUGGESTIONS.md), and a round of bug fixes.

- Raised ground: hills stand up from the map as in The Settlers II (2.5D). Buildings, people, markers, fog and seasons sit at the right height, and clicks find the right tile. Settings can turn it off.
- Road carriers, a new-game option: one carrier for each stretch of road between flags, goods handed on at the flags, a donkey on busy stretches. On busy roads goods wait at the flags, so road layout matters.
- Rivals plan their towns a little (large spots kept for farms, workshops near their suppliers), choose attack targets by their worth, keep a guard home, and call back attacks that go badly. Their toolsmith waits when weapons are short, and maps for many realms are larger.
- Building spots no new road can reach are refused ("No road can get to this spot") and are no longer marked as free.
- Stores pass goods to each other; with more than one store each can be set to Normal, Gather here or Send away.
- A workshop can keep inputs for 1, 2 or 4 work cycles; a carrier with room left brings a second input; the info box shows who is walking there and when they arrive.
- While placing a military building, the spots that claim the most new land show "+N".
- A first-game guide (eight steps, ticked off as you go), German as a second language (interface; game messages are still English), keys you can change in Settings, small map pictures in the save list, a bell for building sites, and entrance pennants on building spots.
- Fixes: a loaded game now goes on exactly like the game that was saved (equal-length road choices, the statistics minute, a reset timer and the soldiers' age differed after loading); presets on the new-game screen no longer cause an error.
- For developers: tools/run_all.py runs every test, tools/check_data.py checks data and mods, game checksums (-- checksums) and tools/checksum_diff.gd find where two games part, and sim.gd and main.gd are split into smaller files.

## Build 32 (v0.27.0, 2026-11-08)

Better rival realms: five rounds of tuning, each tested on the same maps.

- Rivals pull down gatherers that have stood idle a long while with nothing left to gather (woodcutters with no forester close by, quarries, fishers, hunters), so new ones go up where there still is something, and they plant more foresters.
- Research grows with the realm: up to 4 scriptoriums and 3 libraries for a large realm (warlords keep less), and a second school for the artisans who work there.
- When choosing a building spot, rivals avoid spots far from any road (the new road often finds no way through) and try more spots before giving up; they stop putting up military buildings while three or more of theirs still wait for their first soldier.
- More iron and coal mines as the game goes on, and when a rival is short of soldiers or out of room its weaponsmith and barracks get high priority, so iron and carriers reach them first.
- On three test maps, 30 minutes with seven rivals: 5% more buildings and people than in build 31, 40% more research, and hunger nearly gone. Two other tries (more smelters, a stricter road check) were tested, made things no better and were left out.

## Build 31 (v0.27.0, 2026-11-08)

Goods kept in each store, raw materials carried to workshops, people who live in buildings and walk to work, a workers' lodge, walking builders and soldiers, and rival realms tuned for all of it.

- No shared stock any more: the headquarters, storehouses, warehouses and depots each keep their own goods (up to their own room). Goods made are carried to the nearest store, and on to the next one with room if it is full. The Stores panel shows the total of all your stores; click a store to see what it holds. A lost store's goods move to your other stores as far as they have room.
- Workshops, mines, schools and the like work only with goods carried to them: a carrier (or a mule or ox cart close by) fetches them from the nearest store by road that has them. Each keeps enough for two work cycles, food for one. Construction materials also come from whichever store has them. The info box shows "Here for its work: 1 logs (+1 on the way)".
- People live in buildings: newcomers in houses and apartments, the freshly trained at the building that trained them (artisans at the school, soldiers at the barracks, scouts at the scout lodge), the rest at headquarters. A new worker walks along the roads from the nearest of these to his job, and the building starts work when he arrives ("The worker is on his way"). Homes and the headquarters show who is waiting there.
- New building: Workers' lodge (Folk group, medium, 3 planks and 1 stone). Up to 12 idle workers wait there, close to where they will be needed; lodges fill before homes.
- Builders walk to construction sites from where they live; work starts when the builder arrives, and he walks home when it is done. Soldiers walk from the headquarters or barracks to their military building; a new building claims its land only when its first soldier is in. Soldiers whose building is lost on the way go back to the reserve.
- The headquarters has 12 porters (was 8) and storehouses 8 (was 6), since inputs need carriers too. The barracks is now a medium building. Newcomers move in only when the stores hold at least 8 food plus 0.2 per person.
- Rival realms: they look for building spots among free tiles only, keep big spots for big buildings, build close to their roads and pack buildings together; build storehouses in time and workers' lodges out among their workshops; build more fishers, hunters, farms and orchards as they grow; pull down quarries whose rocks are used up; make room for a missing barracks, school or toolsmith by pulling down a house; keep two artisans free to train soldiers when they run out of room; and bring soldiers home from safe buildings to man new ones at the border. A rival whose land is full mans its front, attacks more often and at worse odds, and goes to war with a neighbour it can reach. Across test maps rivals grow 15-25% bigger than in build 30.
- Saves from earlier builds load with all their goods in the headquarters; workers already at a job stay there.
- Fixed: inputs for every realm after one that ran out of carriers were not sent.

## Build 30 (v0.26.0, 2026-11-08)

Building sizes as in The Settlers, building-place markers and a Sites button, and fixes for the toolbar's Geologist and Scout.

- Building sizes: small buildings (guard hut, palisade, watch tower, woodcutter, forester, quarry, fisher, hunter, well...) stand on one tile; medium ones (houses, workshops, guardhouse, tower, storehouse...) on two, one behind the other; large ones (farms, keep, castle, fortress, bastion, warehouse, university, the headquarters...) on a plot three wide and two deep, on fairly flat ground; mines on one mountain tile. Every building needs one free tile all round its plot (roads may use it), so buildings never stand on top of each other. Nothing else can go on a plot: no roads, no trees from foresters.
- Entrances by size: small buildings and mines can face any side, medium ones south, east or west, large ones only south. R turns only to the sides allowed.
- Building-place markers: while placing a building, every spot it fits gets a gold marker, and its whole plot and the free tile it needs are shown. With a building group open, or the new Sites button (or B) switched on, every free spot shows the largest building it takes: a small house, a bigger house, a castle, or a mine sign where a geologist has found ore. Close up only.
- The building buttons and their tooltips show each building's size.
- Rival realms push their border out with an extra military building when their land is full, and stop searching after a few failed tries. Their towns now grow about a fifth more slowly than before (buildings need more room), and they need less computer time.
- Buildings in saves from earlier builds stay where they are, even where they stand closer than the new rules allow.
- Fixed: the toolbar's Geologist and Scout did nothing unless the Industry (Geologist) or Military (Scout) group had been the last one opened.
- Fixed: clicking a building's entrance flag with the road tool now starts its road (it used to say "Start a road on one of your roads or buildings").
- Fixed: road steepness marks next to a building counted its closed sides too; now only its entrance counts.

## Build 29 (v0.25.0, 2026-11-08)

A toolbar along the bottom of the screen, building entrances with roads you lay yourself, Go buttons on events, and Vulkan as the preferred renderer.

- Toolbar along the bottom of the map, as in The Settlers: the eight building groups (Raw, Food, Industry, Crafts, Folk, Science, Stores, Military), each opening its buildings in a panel just above the bar; Road, Pave and Remove road; Auto roads; Demolish; and Scout and Geologist. Esc closes an open group. The side panel no longer has the Build section, and the minimap sits above the toolbar. In a narrow window (or at a large interface size) the toolbar shows icons only; hover a button for its name.
- Demolish tool: click one of your buildings to pull it down (with the usual question and the preview of lost land).
- Building entrances: every new building's entrance faces one side, shown while placing it by an arrow and a flag on the tile in front. R turns it (Shift+R the other way); R still opens research when you are not placing a building. Roads and carriers join a building only at its entrance, and nothing can be built on another building's entrance tile. Your buildings show a small flag at the entrance; a pulsing ring means no road reaches it yet. Buildings from older saves, and the headquarters, can still be reached from any side.
- Roads by hand: after placing a building the road tool starts at its entrance. Click where it should join your roads; the tool stops by itself once it joins, or Esc leaves the road for later (the site waits for it).
- Auto roads button on the toolbar (off by default): on, a new building gets its road at once, from its entrance, and you see that road while placing it.
- Events window: events that happened somewhere on the map (attacks, battles, finished buildings, captures, dry mines and veins, new soldiers...) end with a Go button that moves the camera there and selects the building.
- Vulkan is the preferred renderer: on the first start the game tests Vulkan once in a small extra window; if it works the game restarts with Vulkan and keeps it, if not it stays on OpenGL. Settings lists Vulkan first.

## Build 28 (v0.24.0, 2026-11-08)

Hills that slow the carriers, road steepness marks, and two new-game options: all research done, and creative mode.

- The land has heights: it rises away from the sea, rolls in hills and climbs steeply towards the mountains. The same map always gets the same hills, older saves too. The map and the minimap shade them: slopes facing the light (upper left) and high ground lighter, slopes facing away and low ground darker. Click a tile to see its height.
- Slopes slow transport: each step along a road takes longer the steeper it is, 1.3 times as long on a gentle slope, 1.7 on a steep one, 2.3 on a very steep one, for porters, mules and ox carts alike. Roads laid for you (with a new building, or with the road tool) go round hills where they can. On a typical map about 60% of grassland is flat, a third gently sloping and 6% steep.
- Road steepness marks, as in The Settlers II: 1, 2 or 3 marks on a road tile, yellow, orange or red, for a gentle, steep or very steep road; a flat road has none. A road being planned is coloured the same way, so you can pick a flatter way. Clicking a road tile says how much slower carriers are there.
- New-game option "All research done at the start": every realm starts in the Industrial age with everything studied but the Industrial Revolution itself (so research victory can still be won); soldiers and headquarters start in the Industrial style. Mastery studies are still open.
- New-game option "Creative mode": your buildings cost nothing and stand at once (no builder, no materials), and every good in your stores is kept at least half full. The rivals play by the usual rules.

## Build 27 (v0.23.0, 2026-11-08)

A faster simulation in big games.

- In a 60-minute game with 8 realms (about 1,200 buildings) the simulation now does about 46 ms of work per game second instead of 52 (10-15% less), which matters most at 4x and 8x speed:
  - "Is there room in the stores?" now counts goods on their way only when a store is nearly full, and only for that realm, instead of for every realm on every check. (This check came with build 23 and was the largest single cost.)
  - Work speeds from research are worked out once per kind of building and remembered until research changes, instead of for every building every second.
  - A building waiting for the land or the stores to change (no trees left, stores full, every tool in stock...) looks again every 6 seconds at most instead of every 3; one waiting for goods still looks every 3 at most.

## Build 26 (v0.23.0, 2026-11-08)

A livelier town drawn in more detail, and texture quality that follows the zoom so the game runs faster.

- Townsfolk (close up): people walk the roads near their homes, the more the fuller your houses are: peasants in straw hats, women in kerchiefs and aprons, artisans in caps and leather aprons, and (once you have them) nobles in feathered hats and cloaks. Neighbours stand chatting at their doors, children run round the houses, and newcomers walk in to headquarters with a bundle on their head while there is room in the houses. They are only for show and cost nothing in the game.
- Porters: men carry a crate on a wooden A-frame, women a sack on the head; on the way back they walk empty, and at the store they stoop to set the load down. Their tunics are in the realm's colour.
- Ox carts: the ox has horns, a yoke and a swishing tail, its legs bend as it walks, the wheel has eight spokes and turns smoothly, and the load is the goods themselves: stacked planks, stone blocks, grain sacks, logs or crates, as many as it carries.
- Pack mules carry two panniers on a pack saddle, with a bridle.
- Workers (woodcutters, miners, diggers, fishers, sowers, builders) are redrawn in the same style, with their tools on the shoulder while they walk and raised and striking while they work, and tunics in the realm's colour.
- Every figure has 8 walking frames instead of 4, with knees that bend and a body that bobs with each step.
- Texture quality follows the zoom: every picture now has smaller copies that the graphics card uses when you zoom out; below 16 pixels a tile the ground comes from pictures at half resolution (each piece is baked over twice as fast and uses a quarter of the memory); below 10 pixels a tile carriers are drawn as dots. Your own custom textures get the smaller copies too.
- Modding: the new pictures are unit_folk_*, unit_porter, unit_porter_w, unit_load_* and their *_tint companions (the tunic alone, drawn in the realm's colour); a custom picture in the old 4- or 6-frame layout still works. tools/folk_sprites.py draws them.

## Build 25 (v0.22.0, 2026-11-07)

Battles in the open, a fix for attacks fighting before they arrived, and dry mines that clear themselves away.

- Fixed (since build 20): an attacking column fought its duels at the gate from the moment it set out, instead of when it got there, so an attack could be decided while it was still marching. Columns now march, trade volleys on the way, and fight at the gate when they arrive. The cannon of gun batteries, star forts and armoured redoubts keep firing at the attackers outside the walls during that fight, which makes those forts as strong as intended: 10 musketeers now take a gun battery held by 4 musketeers 68% of the time and an armoured redoubt 27% (it was 77% and 60%).
- Battles in the open: when marching columns of two realms at war meet, they stop and fight.
  - While they close in, their musketeers and riflemen fire volleys at each other.
  - Then one-on-one duels with no walls and no defender's bonus; kinds, ages, veterans, experience and attack techs count as at a gate.
  - The winners march on to their own target with whoever is left; the losers are gone. Crossed swords mark the battle, with the clash of arms when you are close.
  - The event log says when your soldiers meet an enemy column and how it ended. Columns of realms at peace or allied pass each other by.
- Dry mines: when the vein under one of your mines runs dry, the event log warns you, and 30 seconds later the mine is demolished, giving back 40% of its cost. The info box counts down. Switch it off in Settings ("Demolish mines whose vein has run dry"); you are then only told, and the mine stands idle.

## Build 24 (v0.21.0, 2026-11-07)

Garrison settings for military buildings, and a demolish question that shows what you would lose.

- Garrison settings: select one of your military buildings (not headquarters) to set its garrison in the info box.
  - Soldiers wanted: - and + set how many it keeps, from 1 to its full size; Full puts it back. Extra soldiers go back to headquarters, missing ones come from there.
  - Kinds that may serve here: one button per kind of soldier, showing how many are at headquarters and in the building. Allowed kinds are gold. Missing soldiers come newest allowed kind first, and a soldier of a kind you turn off is swapped for an allowed one as soon as headquarters has one. "Any" goes back to normal; at least one kind stays allowed.
  - Stays home when it attacks: which kind holds the building when it sends all but one soldier to attack (the oldest kind, as before, unless you pick one).
  - New buildings and the computer realms work as before. Saves keep the settings.
- Demolishing a military building now shows exactly what it would cost:
  - The question says how many tiles of land you would lose (and how many a rival would gain), or that your border stays as it is because other buildings hold the land.
  - It names the buildings that would be left outside the border and lost.
  - The map moves beside the question and shows the lost land in red and those buildings crossed out; it goes back to where it was when you answer.

## Build 23 (v0.20.0, 2026-11-07)

Full stores now really stop production, and new research goes to the end of the queue.

- Full stores: a building only starts work if the stores will have room for what it makes, counting goods already on their way (waiting at a building, carried, or being made). Before, several buildings could start at once and push a store past its room (in a test, 74 bread in room for 60). Now a store never holds more than its room.
  - A good whose stores are full shows amber in the stores list; clicking it says it is full and how many more are on the way.
  - The building says why it stopped: "Stores are full of water (30 of 30): production stops until some is used, or build a storehouse". It starts again by itself once some is used.
  - Buildings that make two goods (hunter, pig farm, apiary, textile mill) keep working while either has room; anything that still arrives at a full store is lost rather than going over.
- Research: a tech you add goes to the end of the queue.
  - Double-click a ready tech (or Mastery study) to add it to the end of the queue; double-click a locked one to add it and everything it needs.
  - The main button is "Add to the queue" ("Study it" when nothing is being studied). "Study it now (ahead of the queue)" is still there; the tech being studied goes back to the front of the queue and keeps its points.

## Build 22 (v0.20.0, 2026-11-07)

Fixes for the new research window and the computer realms' research.

- The computer realms reach new ages sooner again. With more techs in each age they used to study nearly every cheap tech of an age before moving on. Now, after 12 techs in an age, they aim for the next age, and they leave Mastery studies until no next-age tech is open. In a 70-minute test the first rival reached the High Medieval age at about 40 minutes instead of 70.
- Herbals and Hospitals only help buildings of the diseases feature. With that feature switched off they are now hidden from the tree, can't be studied, and the computer doesn't pick them. They don't count in the "of N techs" totals either. Techs in mods can do the same with `"feature"`.
- The research window:
  - A highlighted line no longer stays lit when the tree moves under a still mouse (zoom, keys, centring on a tech) or after the window is closed and opened again.
  - Search: Enter shows the first match and clears the search, so the rest of the tree is no longer dimmed. The search box is empty each time the window opens.
  - Esc in the search box clears it; a second Esc closes the window.
  - The button on the tech being studied says what it does: "Skip it: study X instead" when something is queued, "Stop studying it" when nothing is.

## Build 21 (v0.20.0, 2026-11-07)

A new research window laid out as a real tech tree, a research queue, 34 more techs and repeatable Mastery studies.

- The research window (R) is now a tech tree. Ages run left to right and each band is a branch of the realm: Roads and stores, Workshops and mines, Land and food, Learning, People and coin, War. Lines run from what a tech needs to what it leads to. The cards are sorted so the lines cross as little as possible.
  - Each card shows the tech's cost or progress, the buildings it unlocks (as small pictures) or its effect.
  - Hover a card to light up everything it needs and everything it leads to.
  - Click a card for its details: effects, buildings, what it needs, what it leads to, and for a locked tech the whole way there with points and time.
  - Drag or use the wheel to move around; Ctrl + wheel, a pinch, the + and - keys or the buttons zoom from 20% to 175%; 0 shows the whole tree. Compact makes the cards smaller.
  - Search finds techs by name, effect or the building they unlock.
  - The age strip shows how far you are through each age; click one to go there.
- Research queue: queue techs to study one after another. "Queue the way there" (or a double-click on a locked tech) queues everything a tech needs in an order that works. The queue shows when each one will be done; taking a tech off also takes off anything queued that needs it. The side panel shows what is next.
- 34 new techs, every age:
  - Early Medieval: Charcoal clamps, Clay working, Hunting dogs, Village smithy, Militia levy, Pack mules.
  - High Medieval: Smoke curing, Candle making, Tanners' guild, Herbals, Glassblowing, Fulling mills, Tournaments, Treadwheel cranes, Stone bridges.
  - Renaissance: Distilling, Trip hammers, Milled coinage, Navigators' school, Hospitals, Clockmaking, Field artillery.
  - Enlightenment: Agricultural societies, Sewers, Turnpike roads, Chemistry, Bayonets, Insurance, Royal academies.
  - Industrial: Tenements, Steam trawlers, Blasting powder, Rotary press, Breech-loaders.
  - They speed up buildings that had no tech of their own (charcoal burner, clay pit, hunter, smokehouse, chandler, glassworks, apothecary, mint, infirmary, bathhouse...) and give the early techs that led nowhere a follow-up. 132 techs in all.
- Mastery: repeatable studies. Each age has three, open once your realm enters that age; each level gives a small bonus and costs half the first level more than the last. The limit rises with the age: 3 levels each in the Early and High Medieval ages, 4 in the Renaissance and Enlightenment, 5 in the Industrial age.

  | Age | Studies (bonus a level) |
  |---|---|
  | Early Medieval | Better tools (+2% production), Weapon drill (+2% defence), Track upkeep (+4% carriers) |
  | High Medieval | Craft secrets (+3% workshops), Tax rolls (+4% tax), Muster (+2% attack) |
  | Renaissance | Workshop practice (+2% production), Scholarship (+4% research), Veteran training (+5% learning) |
  | Enlightenment | Method (+2% production), Logistics (+4% carriers, +3% building), Fortification (+2% defence) |
  | Industrial | Mass production (+2% production), Statistics (+3% research and tax), General staff (+2% attack and defence) |

- The computer realms study Mastery levels too, once the cheap techs of their age are done, and are a little keener to reach the next age.
- Saves keep the queue and Mastery levels; older saves load with an empty queue.
- Modding: techs.json has `lane`, `col` and `row` for each tech's place in the tree, `"lanes"` for the bands and `"repeatables"` for the Mastery studies (see README). A mod's tech without a place goes in an "Other" band.

## Build 20 (v0.19.0, 2026-11-07)

More military buildings, a tidier build menu, and a fix for buildings missing from older saves.

- Fixed: games saved before a feature existed (for example fog of war or geologists) kept only the features they were saved with, so the scout lodge, watch tower, flax farm, furrier and other buildings were missing from the build menu. Features that are new since a game was saved are now switched on when it loads, and the event log says which. You can still switch them off under Settings > Game features. Saves now record which features existed when they were made, so a feature you switch off stays off.
- Six new military buildings, one or more for each age:

  | Building | Cost | Garrison | Unlocked by | What it adds |
  |---|---|---|---|---|
  | Palisade | 3 planks | 1 | (from the start) | The cheapest way to claim land |
  | Guardhouse | 2 planks, 3 stone | 3 | Shield walls | Low walls (defenders +3% a duel) |
  | Keep | 4 planks, 6 stone | 6 | Town walls | Stone walls (+5%), wide land |
  | Gun battery | 3 planks, 4 stone, 3 iron | 5 | Drill manuals | Three cannon, range 8 |
  | Star fort | 4 planks, 10 stone, 6 bricks | 10 | Star forts | Thick walls (+8%), two cannon |
  | Armoured redoubt | 3 planks, 8 stone, 10 bricks, 6 iron | 16 | Rifling | Thick walls, four cannon, range 9 |

- Walls: the defenders of a guardhouse, keep, star fort or redoubt are harder to beat in each duel.
- Cannon: the guns of a battery, star fort or redoubt fire on attackers in range while they march in and while they fight at the gate, as long as someone is inside. In tests, 10 musketeers took a hut held by 4 musketeers 98% of the time, a gun battery 77%, and an armoured redoubt 60%.
- The computer builds the new forts too: palisades early on, guardhouses and keeps, and batteries when it is at war.
- The build menu shows only the buildings you can build now. Buildings still locked by research are hidden, and a line says how many more research will unlock. They appear when the research is done.
- Goods your realm doesn't know of yet are hidden from the stores, the production targets and the trade window. A good shows up once a building you can build makes it, uses it or costs it, or once you have some in store.
- Text off screen: the side panel was a few pixels too narrow for its contents, so the right edge of the stores and build buttons was cut off. It is wider now. The note under the texture buttons on the start screen now wraps instead of running off the side. The "Soldier kinds" button takes one cell of the build grid instead of two.

## Build 19 (v0.18.0, 2026-11-07)

Each kind of soldier now fights its own way.

- Garrisons, headquarters and attacking columns keep count of each kind of soldier (legionaries, spearmen, men-at-arms, pikemen, musketeers, riflemen) instead of an average. The info box and the People panel list them, e.g. "3 pikemen, 2 musketeers".
- Who beats whom (+12% a duel on top of the 15%-per-age strength): legionaries beat spearmen; men-at-arms beat spearmen and legionaries; pikemen beat men-at-arms and legionaries; musketeers beat pikemen; riflemen beat every older kind.
- Each kind has its own edge:
  - Legionaries: shield wall, strong holding a gate.
  - Spearmen: cheap and quick to train (barracks 30% faster in the Early Medieval age).
  - Men-at-arms: heavy armour turns half the blows that would fell them, but not pikes or bullets.
  - Pikemen: long reach, strong in defence.
  - Musketeers: fire a volley or two (4 tiles, 6 s reload) on the way in, but are poor hand to hand.
  - Riflemen: fire again and again (7 tiles, 2.5 s reload).
- Gunfire: musketeers and riflemen in an attacking column fire on the defenders as soon as they are in range; musketeers and riflemen in the defending building fire back. An attack can be shot to pieces before it reaches the gate, or a building can be emptied by fire and taken without a fight.
- At the gate the defenders always send their best answer to each attacker; marching out, the best soldiers go and the oldest stay to hold the building. A captured building is held by the best of the attackers.
- Barracks with no artisan to train retrain the oldest soldier at headquarters to the current kind.
- On the map an attacking column shows up to three figures, one for each of its most numerous kinds; the last stretch is a charge with weapons lowered; volleys show muzzle flashes, smoke and streaks, and sound like a musket's boom or a rifle's crack.
- Military tab: "Soldier kinds: who beats whom" explains all of this and lists your soldiers.
- tools/battle_test.gd fights each pairing of kinds 60 times and prints how often the attackers win.
- Saves from before this build turn their soldiers into the kind of their realm's age.

## Build 18 (v0.17.0, 2026-11-07)

Last of the three stages: a look for each age, renovation, and soldiers for each age.

- Every building now has a look for each of the six ages: Roman (whitewashed plaster, terracotta tiles, arched doors, shuttered windows, pilasters), Early Medieval (timber framing and thatch, the look so far), High Medieval (stone footings, steep slate roofs), Renaissance (pale plaster, red tiles, framed windows and a cornice), Enlightenment (brick, dark slate, tall white sash windows) and Industrial (dark red brick, iron-framed factory windows, tall chimneys).
- A building keeps the look of the age its realm was in when it was placed, so towns show their history. New games start in the Roman style.
- Renovate (a button on your building, once your realm has reached a later age): the building is rebuilt in your current age's style for half its building cost, carried there by carriers, and half its building time. Work stops meanwhile and the worker keeps his job and skill; scaffolding shows the new look rising. "Renovate all" queues every outdated building of that type; two renovations run at a time, the rest wait their turn. The info box shows a building's style and its renovation materials. Rivals renovate now and then when they have materials to spare.
- Soldiers of each age: legionaries, spearmen, men-at-arms, pikemen, musketeers and riflemen, each with their own look on the map (crested helmet and oblong shield; round helmet and kite shield; great helm and heater shield; morion and long pike; tricorne and musket; peaked cap and rifle). Each age ahead makes soldiers about 15% stronger in battle.
- New soldiers are of your realm's current age. A barracks with no artisan to train retrains an older soldier at headquarters to the current kind instead (it uses a weapon and bread as usual). The People panel and military buildings say what kind of soldiers you mostly have.
- Your own textures: bld_<id>_e0.png to bld_<id>_e5.png replace one age's look (0 Roman to 5 Industrial); bld_<id>.png alone stands for every age. "Export defaults" writes all of them.
- Saves from before this build keep their buildings in the Early Medieval look, and their soldiers are of their realm's current age.

## Build 17 (v0.16.0, 2026-11-07)

Second of three stages: geologists and wildlife (next: a look for each age with renovation, and soldier types for each age).

- Geologists (an optional feature, on by default): what lies under the mountains is unknown until surveyed. Ore no longer shows on unsurveyed mountains (mountain peaks stand there instead, so they give nothing away), and mines can only be built on surveyed tiles of their ore.
  - Send geologist (Industry tab), then click a mountain in your land or up to 3 tiles beyond it. An idle peasant takes a pickaxe from the nearest store, walks there over land, checks up to 12 unsurveyed mountain tiles around the spot (3.5 seconds each) and walks home. He brings the pickaxe back.
  - Each checked tile gets a marker: a pennant in the ore's colour (coal, iron, gold, copper, granite), bigger for richer veins, or an empty pole for nothing. Markers fade after five minutes, but your realm remembers what was found. While you place a mine, every surveyed tile of its ore lights up.
  - Two geologists can be out at once. New research: Prospecting (Early Medieval) lets 4 out at once and widens the survey to 18 tiles; Geological survey (Renaissance) makes a find reveal its whole vein.
  - The log reports what each geologist found; clicking a mountain tile tells whether it is surveyed. Rivals send geologists too.
  - Games from before this build know the land around their existing mines.
- Wildlife (an optional feature, on by default): deer, boars, hares and wolves roam the land, keep a little away from buildings and have young (not in winter) up to what the land can feed. Wolves are commoner in the northern taiga.
  - Hunters must find a real animal in their hunting grounds (or track one up to 4 tiles beyond); each catch takes one. Over-hunting empties the grounds for a while; game wanders back in from the wild. A hunter's info shows how much game is about.
  - Wolves now and then scare the herds of sheep and pig farms and dairies (the farm stops for 45 seconds) unless a hunter's grounds reach the farm, and they take deer and hares themselves.
  - Fish jump in the fishing grounds.
- Carriers pick up waiting goods in a fixed order (priority, then the oldest building), so a loaded game goes on exactly as it would have.
- Feature data is copied into saves, never shared with the running game.

## Build 16 (v0.15.0, 2026-11-07)

First of three stages: carried materials, fog of war, watch towers and scouts (geologists and wildlife come next, then a look for each age with renovation and new soldier types).

- Construction materials are carried: placing a building takes nothing from the stores and sets nothing aside. Carriers (porters, mules and carts) bring the planks, stone and so on from the nearest store to the site a load at a time, and the builder works only as far as the materials that have arrived allow. A site holds at most 6 units waiting at a time.
  - Sites share the materials by priority: high-priority sites are served first, then the oldest; paused sites get nothing.
  - You can place a building even when its materials are not in store yet; it waits until they are.
  - The info box lists each material delivered, on the way and still missing, and why a site is waiting. Materials lying at a site show on the map, and its progress bar shows how far the materials reach.
  - Demolishing a site gives back what lies there unused and 40% of what was built in.
  - Rivals play by the same rules and don't count materials promised to their own sites.
  - Sites in saves from before this build keep the old rules (their materials were already paid).
- Fog of war (an optional feature, on by default): you see your own land, a few tiles around every building, further around military buildings (their radius + 2) and the headquarters. Land you've seen stays on the map, darkened, with rival buildings as you last saw them; rival soldiers and carriers show only in sight. Unexplored land is black, on the map and the minimap. You can't select what you can't see.
- Scouts, a new class: the scout lodge (Military tab) trains peasants into scouts with bread and a bow, keeping 2 idle. Scouts eat like soldiers. The People panel counts them.
- Watch tower (Military tab): a cheap wooden lookout that sees 14 tiles around with a scout inside. It claims no land.
- Send scout (Military tab): click any spot and an idle scout walks there over land from the nearest store and back, seeing 5 tiles around him. If he can't reach the spot, he goes as close as he can.
- Rain and snow no longer fall on land you have never seen; snow settles and melts by game time, so it looks right at any game speed.
- Features can add their own map tools (like Send scout) and draw over the buildings.

## Build 15 (v0.14.0, 2026-11-07)

Last of the four stages: better textures and sounds.

- Sound effects: button clicks; placing, finishing and demolishing buildings; finished research and new ages; good and bad news (outbreaks, deaths, fires, raids); merchants' coins; a horn when your buildings are attacked; a chime when the season changes. Up close you hear the buildings on screen at work: axes, picks, hammers, saws, building sites and sword fights.
- Ambience that follows what you look at: birdsong in the warm seasons, wind in winter and when zoomed far out, rain where it rains (with the seasons feature), and the murmur of a town up close.
- Settings has a Sound section: sound on or off, and volume, effects and ambience sliders. All sounds are made by tools/make_sounds.py; nothing is recorded or licensed.
- Better textures: every building and tree now has a fine surface grain, light falling from above, a lit upper-left rim and a dark outline, so they stand out from the ground. Richer ground tiles: grass with roots and tips on its blades, tufts, clover, flowers and drier patches; water with ripple crests and troughs; sand with damp patches, ripples, pebbles and shells; layered rock with lichen.
- The whole map gets large lighter and darker patches of grass and rock, so the ground no longer looks tiled, and water darkens as it gets deeper away from the shore.
- The bathhouse and infirmary got their own signs (a water drop and a red cross).
- Your own replacement textures in the textures folder still take priority.

## Build 14 (v0.13.0, 2026-11-07)

Third of four stages: diseases, random events and tool quality.

- Diseases: winter fever, dysentery, marsh fever and plague can break out (not in the first 6 minutes) and spread through a realm. Sick people don't work, so all your buildings slow down by the share of people who are sick, and some of the sick die.
  - Causes: cold without fur coats and crowding (winter fever); too few wells, heat and hunger (dysentery); buildings in the wetlands in warm weather (marsh fever); a town packed to its housing limit (plague).
  - Prevention: bathhouses (each keeps 50 people clean while it has water, logs and a worker), wells (each gives clean water for 30 people) and fur coats.
  - Cure: medicine. Medicine in store cures a few people at home; an infirmary cures 8 people per medicine and works only while somebody is sick.
  - New buildings (Folk tab): herb garden (herbs), apothecary (herbs into medicine), infirmary and bathhouse, with a new healer trade. The People panel shows who is sick, the bath and water cover, and warns of high risks. The log tells you about outbreaks and deaths.
- Random events: every 4 to 7 minutes something happens to each realm: bumper harvest, rats in the granary, fire, mine collapse, travelling merchant, refugees, festival, lucky find, wolves, skilled newcomer, storm damage, bandits, wandering scholar or an epidemic. Rivals get them too. Switch all of them off in Settings > Game features, or single events in the events window (F6), which also lists your recent events.
- Tool quality: tools are crude, standard, fine or masterwork. The toolsmith's level decides (an apprentice makes crude and standard tools, a master fine and masterwork ones; the machine works does better). Better tools work faster (crude -12%, fine +12%, masterwork +25%) and last longer (40 to 180 work cycles). A worn-out tool is replaced from the stores; without a spare the worker carries on 25% slower. Click a building to see its tool; the People panel counts the tools in use.
- All three are optional features in Settings; "Classic rules" still switches every new feature off at once.
- Settings and the other big windows scroll when they don't fit on the screen.

## Build 13 (v0.12.0, 2026-11-07)

Second of four stages: the climate.

- Seasons: a year has four seasons of 5 minutes, starting in spring. Crops (farms, orchards, hop, flax and herb gardens, vineyards, apiaries) grow +10% in spring, +25% in summer, +10% in autumn (orchards and vineyards +25% more at harvest) and -60% in winter. Winter also slows animal farms, fishers, hunters, foresters, quarries and building, and people eat more below 5°C. The map turns golden in autumn and white under snow in winter.
- Biomes: the north is cold taiga (woodland work and hunting +20%, crops -25%), the south a warm, dry steppe (crops +10%, sheep farms, dairies and saltworks +20%, foresters -30%), with wetlands by the water (fishers +20%, clay pits +25%) and temperate land in between (crops +10%). Each has its own tint on the map.
- Weather: each biome has its own weather, changing every 1 to 2.5 minutes: clear, cloudy, rain, storm, snow, blizzard, heat wave or fog, each with its own effects (storms keep fishermen ashore, blizzards stop outdoor work, heat waves wilt crops, rain helps them). Rain, snow, fog and storms are drawn over the map. The log warns you of bad weather where you live.
- Temperature: season + biome + weather, colder on mountains. Shown on the top bar with the season and weather, and for any building you click.
- Summer and winter clothes: people need fur coats in the cold and linen clothes in the heat. One piece dresses 3 people and wears out after about 10 minutes of use. Without them people work up to 30% slower in bitter cold (and eat up to 25% more), or 20% slower in great heat. New buildings: flax farm, linen weaver (flax into linen clothes) and furrier (hides into fur coats). Every realm starts with a few of each. The People panel shows how many of your people are dressed for the weather. Rivals build them too.
- Climate window (F4 or the Climate button): every biome's weather and temperature, and all the season, biome and weather effects.
- Seasons and clothes are optional features (Settings > Game features); clothes need the seasons. Saves from build 12 keep the features they were started with (switch the climate on in Settings if you like); older saves start with everything on and everyone already dressed.
- The building info box no longer runs off the bottom of the screen: it grows upwards and stays in view. Drag its title to move it anywhere; double-click the title to send it back to the corner.
- The top bar wraps onto a second row when its buttons don't fit, instead of running under the side panel.
- Feature scripts get more hooks: work cycles, hiring, building info, tile info, construction speed, the rival building plan, the top bar, and drawing on the map and over it.

## Build 12 (v0.11.0, 2026-11-07)

First of four stages (next: seasons, biomes, weather and clothes; then diseases, random events and tool quality; then new textures and sounds).

- Production statistics (Statistics button or F2): a window with a chart and a table. Goods tab: how much of any good was made and used per minute over the last 10, 30, 60 or 240 minutes. Realms tab: population, buildings, soldiers, research and goods made, for you and every rival. Kept in save games.
- The event log is now its own window, in the upper-left corner of the map. Drag its title bar to move it, drag its edges to resize it, close it with its X, and bring it back with E or the Events button. Its place and size are remembered.
- Optional features: Settings has a new "Game features" list. Each feature can be switched on or off; "Classic rules" switches every optional feature off at once. Production statistics is the first; the coming seasons, weather, clothes, diseases, random events and tool quality will all be switchable there. Each game remembers which features it was started with.
- Mods: script mods (.gd files) dropped into the mods folder (%APPDATA%\Godot\app_userdata\Hearthlands\mods\) appear in the same list, marked "(mod)", and are off until you tick them. Settings has a button that opens the folder. A mod can speed up buildings, change how much people eat, count goods, add text to the People panel, add top-bar buttons, windows and keys, and save its own data.
- The code is split into smaller parts (AI, combat and territory, roads and carriers, research; and one file per window), so features can be added without touching the core. Games play exactly as before, and saves from builds 4 to 11 still load.

## Build 11 (v0.10.0, 2026-11-07)

- Four times as much research: 96 techs instead of 24 (24 in each medieval age, 16 in each later one). The new ones speed up single trades and buildings, let workers learn faster, make people eat less, add store room and housing, bring newcomers sooner, make veins last longer, and save tools. Each needs an earlier tech, so the ages still come in order. The research window is more compact and scrolls.
- Specialised tools: the single "Tools" good is now 12 tools, one per trade (axes, pickaxes, farm tools, bows and rods, knives, saws, smith's tongs, trowels, shears, chisels, quills, harnesses). A building taking on a new worker needs its trade's tool; an idle specialist of the trade brings his own. Buildings waiting for a tool say so. The toolsmith (now 2 tools per cycle, and the machine works 3) makes whichever tool is most wanted, buildings waiting first, and needs no tool itself, so tools can't run out for good. Every realm starts with a tool kit and a little iron. Schools now need 2 bread instead of tools and bread. Old saves share their tools out among the new kinds.
- Production targets: set how many of each good to keep in store (Production targets window, T, or the − and + buttons when you click a good). Buildings stop making it at the target and start again below it. Tools keep 2 of each by default.
- Difficulty settings on the new-game screen: a preset (Easy, Normal, Hard or Custom) plus starting goods (half to four times), peace at the start (none to 60 minutes before rivals attack), research speed (50% to 400%), construction speed (100% to 200%), endless ore veins, endless stone, clay and fish, and whether new workers need tools. They are saved with the game.

## Build 10 (v0.9.0, 2026-11-07)

- Smarter road laying: a new building's road now joins the network where the new road plus the walk on to a store is shortest, not simply at the nearest road. Carriers walk about 13% less on average (3.90 s to 3.40 s from a working building to its store in a 30-minute 6-realm test) for about 2% more road.
- Faster road network: new roads, buildings, finished stores and paving update the network in place instead of rebuilding it; only losses rebuild it, and a border change rebuilds only realms that lost road or building tiles. Full rebuilds in 30 minutes: 3,872 to 43; their cost fell from up to 2 ms to about 0.1 ms per game second. The whole simulation is 6 to 13% faster.
- Walking times per tile are now exact binary fractions (13/64 s paved, 22/64 s dirt), so step-by-step updates give exactly the same results as a rebuild. tools/net_test.gd checks this; tools/roadprobe.gd measures road quality.

## Build 9 (v0.9.0, 2026-11-07)

- Settings window (top bar button or F10), remembered between games in `user://settings.cfg`.
- Renderer choice: OpenGL (Compatibility, the default; works on almost every PC), Vulkan (Forward+) or Vulkan (Mobile). Switching restarts the game: it autosaves first and continues where you were. A new renderer is tried in a one-off start and kept only if it works, so a PC without Vulkan always comes back on OpenGL (with a message saying so). The Windows zip includes "Start in OpenGL safe mode.bat".
- Display: window, borderless fullscreen or exclusive fullscreen. Resolution: the screen's native size or a list of common sizes that fit the screen. In a window it sets the window size; in fullscreen a lower resolution draws fewer pixels and stretches them to the screen, which helps slow graphics cards.
- Interface size from 75% to 150%, VSync on or off, and a frame-rate limit (30 to 240 fps or none).
- Animations, smooth scaling and "Ask before demolishing" moved into Settings and are now remembered.
- tools/render_bench.gd measures where frame time goes for a renderer and resolution; tools/settings_test.gd tests the settings.

## Build 8 (v0.8.0, 2026-11-07)

- Demolish asks first: a window lists what you get back, what is lost (goods waiting for carriers, stored goods above the new limit, your border) and what happens to the worker and soldiers. Enter demolishes, Esc keeps the building. The Delete key demolishes the selected building. "Don't ask again", or the option under Textures and mods, turns the question off.
- Building priorities: High, Normal, Low or Paused for every working building and construction site (buttons in the building panel, Page Up / Page Down, P to pause). High gets workers, builders and carriers first and re-checks missing goods every half second; Low gets workers last and leaves the last 6 of each input (12 food) for others; Paused stops the building and frees its worker. Arrows and a pause sign on the map show non-normal priorities.
- Trades and specialists: every working building belongs to one of 12 trades (woodland, mining and quarrying, farming, fishing and hunting, food and drink, woodwork, metalwork, kilns and glass, textiles and leather, fine crafts, teaching and learning, transport). Workers level up only in their own trade, 10% faster per level (was 8%). From level 3 they are specialists (woodsmen, miners, smiths, joiners...), at level 5 masters. A worker who leaves a building keeps his skill and is hired first by the next building of his trade; in another trade he starts again at level 1. The People panel shows each trade's workers and levels; the building panel shows the worker's trade and rank.
- 10 new resources (44 in all) and 9 new buildings: sand pit and glassworks (glassware), apiary (honey and beeswax) and chandler (candles), dairy farm (milk) and cheesery (cheese), butcher (sausages), vineyard and winery (wine). Cheese, sausages and honey are food. Wine is a second drink for artisans and nobles; nobles also want glassware or candles. Rivals build the new chains too.
- Needs can offer a choice: "wine|beer" in needs.json is met by either good.
- Faster simulation: a working building now sleeps until its work cycle ends instead of being updated five times a second, buildings that cannot start back off up to 3 seconds, and the tick loop no longer copies the building list. About a quarter less time per game second at 30 minutes (19.2 ms in build 7, 14 to 15.7 ms now on the benchmark, with more buildings).
- Smoother when borders move: only map chunks where tiles changed hands are redrawn, not every chunk on screen (worst frame while the game runs at 8x: 117 to 81 ms on the benchmark). Map chunks are baked within a 3 ms budget per frame.
- Fixed (build 7 bug): zoomed far out, the map turned black with solid blobs of territory colour.
- tools/readme_tables.py rebuilds the README's resource, building and research tables from the data.
- Saves from build 7 still load.

## Build 7 (v0.7.0, 2026-11-07)

- Redrawn textures: every picture is drawn four times larger and shrunk, so edges are smooth. Buildings are twice the resolution and show depth (side walls, gable ends), timber framing, stonework, planks, thatch, roof tiles and slate, real windows and doors, and a hanging sign showing what each workshop makes.
- Terrain: beach, grass and mountain now blend softly into each other instead of meeting at square edges; snowy peaks stand on mountain ranges; three kinds of trees (pine, broad-leaved, birch); shaded rocks, ore and cobbled roads.
- Water shimmers: ripples, drifting glints and slow swells, done on the graphics card by a shader (shaders/ground.gdshader).
- Animations: porters, mules and ox carts walk with moving legs and wheels and face the way they go; soldiers march, and at the gate attacker and defender take turns to strike. Woodcutters, quarrymen, clay diggers, fishers and foresters walk to their work, swing their tools there and carry the result home. Buildings rise out of their scaffold as they are built, with a builder hammering. Chimneys smoke, furnaces glow, windmill sails turn, flags wave, and sheep and pigs graze around their farms.
- Animations follow the game clock: they freeze when paused and speed up at 2x to 8x.
- New options in Textures and mods: Animations (turn off on slow computers) and Smooth scaling, now on by default.
- Custom textures can be animated: a strip of frames side by side (see README). A single still picture still works.
- Map drawing costs about 2 to 5 ms per frame on the benchmark (was 1.5 to 4).
- Saves from build 6 still load.

## Build 6 (v0.6.0, 2026-11-07)

- Roads: build, pave and remove roads yourself (Roads & stores tab). Paved roads cost 1 stone per tile and carriers walk them faster.
- Logistics: finished goods wait at the building until a carrier takes them along the roads to the nearest store. Porters come from the stores and from idle peasants; mule stations (6 mules, 3 goods each) and ox cart yards (4 carts, 6 goods each, new tech Ox carts) carry faster within their range.
- Tiered stores: headquarters (60 of each good), storehouse (+40), warehouse (+120, new tech Trade fairs) and great depot (+300, unlocked by Railways). Production pauses when there is no room; losing a store loses the goods that no longer fit.
- Work areas: woodcutters, foresters, quarries, fishers, clay pits and hunters can move their work area up to 6 tiles away, at the cost of extra walking.
- Faster: the simulation needs about 3.5 times less time per building (85 ms down to 24 ms per game second on a 200-tile map with 9 realms and 1,000 buildings). The map is drawn from pre-baked 16x16 chunks, cutting its drawing code to under 5 ms per frame; the minimap updates only changed pixels.
- F3 shows a performance overlay. tools/bench.gd measures performance.
- Saves from build 5 still load.

## Build 5 (v0.5.0, 2026-11-06)

- Resource info: click any resource in Stores to see what makes it, what uses it, what it is worth and who wants it, in the same panel as buildings.
- Deposit info: click a tree, rock, clay patch, fishing ground or ore vein on the map to see how much is left.
- Ore now comes in veins with a random, limited amount: most are modest, a few are very rich. A mine draws from its whole vein until it runs dry.
- Experience: every worker gains experience and levels up from 1 to 5, working up to 32% faster. Soldiers gain experience in battle and win more duels.
- Diplomacy: war, peace and alliances; opinions; trading and gifts; rivals make offers to you and treaties with each other. Allies help defend each other, and an alliance with every remaining rival (after at least half are defeated) is an allied victory.
- Saves from build 4 still load: old ore deposits become small veins.

## Build 4 (v0.4.0, 2026-11-06)

- Every release now has a version and build number, shown on the top bar and the new-game screen.
- Saves record which version made them; the save list shows it.
- `tools/bump_build.py` raises the build number and updates the version everywhere before a release.
- Fixed: the save list showed the file name instead of the name you typed.

## Build 3 (v0.3.0, 2026-11-06)

- Windows build: a single `Hearthlands.exe` with everything packed in, plus Windows and Linux export presets.
- Annotated copy of the source with a plain-English explanation above every line of code, and `LEARNING.md`.

## Build 2 (v0.2.0, 2026-11-06)

- Save and load: named saves, quick save (F5) and quick load (F9), autosave every 5 minutes.
- Map size choice from Small (96) to Giant (256), or Auto.
- Research tree from the Roman age to the Industrial Revolution: 22 techs, research victory.
- New buildings: scriptorium, library, university, paper mill, fortress, steelworks, machine works, textile mill. New resource: paper.

## Build 1 (v0.1.0, 2026-11-06)

- Hearthlands moved from a web page to Godot 4.
- 33 resources, 43 buildings, population needs (beer, clothes, jewelry, furniture), veterans with armor.
- Custom textures for every picture, and data mods for resources and buildings.
