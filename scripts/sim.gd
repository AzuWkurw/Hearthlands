class_name Sim


extends RefCounted
## The whole game state and rules: map, players, economy, territory, combat and rival AI.
## Runs without any rendering, so it can be tested headless (see tools/sim_test.gd).


signal log_added(text: String, color: Color)


signal ended(win: bool)


signal tech_done(pid: int, tech: String)


signal diplomacy_changed

## The simulation's parts (see sim_*.gd). Each holds a reference back to this object.
var ai := SimAI.new(self)
var military := SimMilitary.new(self)
var logistics := SimLogistics.new(self)
var research := SimResearch.new(self)
var sea := SimSea.new(self)
var people := SimPeople.new(self)
var production := SimProduction.new(self)


## The parts and the simulation refer to each other, so neither would ever be freed on its own.
## Call this when a simulation is thrown away (the game does when it closes).
func dispose() -> void:
	ai.sim = null
	military.sim = null
	logistics.sim = null
	research.sim = null
	sea.sim = null
	production.sim = null
	people.sim = null
	for f: Feature in features:
		f.sim = null


const TICK := 0.1


const RANGE := 24.0


const WATER := 0


const BEACH := 1


const GRASS := 2


const MOUNT := 3


const D_TREE := 1


const D_ROCK := 2


const D_CLAY := 3


const PCOL := [Color("3d86e0"), Color("d9483d"), Color("e0b83a"), Color("a055d0"), Color("e07b2c"), Color("2fb5a6"), Color("e06a9f"), Color("c9c9c0"), Color("8fd13f")]


const AI_NAMES := ["Aldric", "Brunhild", "Cedric", "Dagny", "Eadric", "Fenwick", "Gisela", "Hartmut"]


const PERSONALITIES := ["builder", "balanced", "warlord"]


const BASIC := ["planks", "stone"]


const SAVE_VERSION := 3


const INF := 1e9                           # "unreachable" distance on the road network


const PORTER_LOAD := 2                     # goods a porter carries at once


## Seconds to walk one tile. They are exact binary fractions (13/64 and 22/64 of a second), so adding them
## up gives the same total in any order: updating the road network step by step then matches rebuilding it.
const PAVED_COST := 0.203125


const DIRT_COST := 0.34375


## When a new building's road is planned, each new road tile counts as this many seconds of walking:
## a shortcut is laid only when it saves clearly more walking than the road it adds.
const NEW_ROAD_COST := 1.0


const WORKER_XP := [0, 8, 24, 60, 140]    # completed work cycles needed for levels 1 to 5


const LEVEL_BONUS := 0.1                   # extra work speed for each worker level above 1


const SPECIALIST := 3                      # from this level on a worker counts as a specialist of his trade


## Building priorities, set by the player: who gets workers, builders, scarce goods and carriers first.
const PRIO_HIGH := 2


const PRIO_NORMAL := 1


const PRIO_LOW := 0


const PRIO_PAUSED := -1


const PRIO_NAMES := {2: "High", 1: "Normal", 0: "Low", -1: "Paused"}


const LOW_RESERVE := 6.0                   # low-priority buildings leave this much of each input for others


const TOOL_TARGET := 2                     # tools kept in stock when no production target is set


## Difficulty options chosen when founding a realm (the new-game screen). Saved with the game.
## How steep the way between two neighbouring tiles is: 0 flat, 1 gentle, 2 steep, 3 very steep (by the
## difference in height), and how much longer carriers take on it.
const SLOPE_STEPS := [10, 22, 38]
const SLOPE_MUL := [1.0, 1.3, 1.7, 2.3]
const SLOPE_NAMES := ["flat", "gentle slope", "steep slope", "very steep slope"]


const DEFAULT_OPTS := {
	"start_goods": 1.0,     # starting goods: 0.5 scarce, 1 normal, 2 plenty, 4 rich
	"endless_ore": false,   # ore veins never run dry
	"endless_raw": false,   # stone, clay and fish never run out
	"peace_min": 0,         # minutes before rivals start attacking
	"research": 1.0,        # research speed
	"build": 1.0,           # construction speed
	"tools": true,          # new workers need their trade's tool
	"road_carriers": false, # The Settlers style: one carrier for each stretch of road, goods handed on at flags
	"all_research": false,  # every realm starts with all research done (but the Industrial Revolution)
	"creative": false,      # creative mode: you build for free and at once, and your stores never run low
}


## The tool kit every realm starts with (times the starting goods setting).
const START_TOOLS := {"axes": 4, "pickaxes": 5, "farm_tools": 4, "bows": 2, "knives": 3, "saws": 2, "tongs": 2, "quills": 2, "trowels": 1}


const SOLDIER_XP := [0, 6, 18, 40, 80]    # experience needed for soldier levels 1 to 5


class Bld:
	var id := 0
	var ty := ""
	var def: Dictionary = {}
	var x := 0
	var y := 0
	var p := 0
	var state := "build"
	var prog := 0.0
	var staffed := false
	var k := 0.0       # work done in the current cycle; only read when loading saves from before build 8
	var working := false
	var garrison := 0
	var path := PackedInt32Array()
	var target := -1
	var msg := ""
	var dead := false
	var wxp := 0.0     # experience of the worker here
	var cyc := 0.0     # seconds per work cycle, copied from the data (0 = this building never works)
	var rate_c := 1.0  # work speed, worked out once a second by staffing()
	var retry := 0.0   # game time before which nobody checks again why work cannot start
	var fails := 0     # failed start checks in a row; each one makes the next wait a little longer
	var t_start := 0.0 # game time the current work cycle started
	var t_end := 0.0   # game time it will finish; the building sleeps until then
	var prio := 1      # priority: 2 high, 1 normal, 0 low, -1 paused (see PRIO_NAMES)
	var need_tool := "" # the tool this building waits for before it can take on a new worker
	var out_buf: Dictionary = {}           # finished goods waiting for a carrier
	var work := Vector2i(-1, -1)           # moved work area centre, or (-1, -1) for the building itself
	var path_ver := -1                     # road network version that `path` was traced on
	var busy := 0      # for mule stations and cart yards: animals or carts out on the road
	var sxp := 0.0     # average experience of the soldiers stationed here
	## Construction materials, carried to the site by carriers: still to be sent from the stores,
	## on the way, arrived and not used yet, and used up. mat_total is the whole cost in units
	## (0 = no materials needed: the headquarters, or a site from a save made before build 16).
	var need: Dictionary = {}
	var coming: Dictionary = {}
	var onsite: Dictionary = {}
	var spent: Dictionary = {}
	var mat_total := 0
	var mat_used := 0
	var era := -1      # the age it was built in, which decides its look (-1: from a save before ages had looks)
	var reno_to := -1  # being renovated into this age's style (-1: not)
	var reno_prog := 0.0
	var builder := 0   # a construction site's builder: 0 none, 1 walking there from his home, 2 at work
	var worker := 0    # its worker: 0 none, 1 walking here from his home, 2 at work
	var walking := 0   # soldiers on their way here from a store to join the garrison
	var inv: Dictionary = {}   # a store's goods (res -> amount); the realm's stock is their total
	var policy := 0            # a store: 0 normal, 1 gather here (others send it goods), 2 send away (takes nothing new)
	var keep := 0      # a workshop: how many work cycles of inputs it keeps (0: the usual two)
	var inbuf: Dictionary = {}     # goods carried here for its work (res -> count), used as it works
	var incoming: Dictionary = {}  # goods on their way here for its work
	var door := -1     # the side its entrance faces: 0 south, 1 east, 2 north, 3 west; roads join it only
	                   # there (-1: any side, the headquarters and buildings from saves before build 29)
	var sera := -1.0   # average age of the soldiers stationed here (their kind: legionary... rifleman)
	var retrain := false # a barracks retraining an old soldier this cycle instead of training a new one
	var gmix: Array = [] # the garrison by kind: how many legionaries, spearmen ... riflemen (see mix_fix)
	var want_n := -1                       # soldiers the player wants here (-1: as many as it holds)
	var want_kinds: Array = []             # 6 flags: which kinds may serve here (empty: any)
	var keep_kind := -1                    # the kind that stays home when it attacks (-1: the oldest)
	var archer_want := 0                   # how many of its soldiers should be archers (they take up bows)
	var archers := 0                       # how many are archers now (never more than its garrison)
	var sally := false                     # its soldiers march out to meet an attack instead of waiting
	var dry_t := -1.0                      # a mine: game time its vein was found to have run dry (-1: not dry)


class Player:
	var id := 0
	var name := ""
	var color := Color.WHITE
	var ai := false
	var alive := true
	var stock: Dictionary = {}
	var peasant := 14
	var artisan := 2
	var noble := 0
	var reserve := 8
	var scout := 0     # scouts: they man watch towers and explore (fog of war feature)
	var used_scout := 0
	var scout_out := 0 # scouts out exploring
	var away := 0      # peasants away from work (geologists out surveying)
	var res_xp := 0.0  # average experience of the soldiers waiting at headquarters
	var res_era := -1.0 # average age of the soldiers at headquarters (-1: from an older save, see _fix_eras)
	var rmix: Array = []  # the soldiers at headquarters by kind (legionaries ... riflemen)
	var busy_porters := 0                  # porters out carrying goods
	var segs := {}                         # road carriers mode: stretch of road (two flag tiles) -> when its carrier is free again
	var road_carriers := 0                 # road carriers mode: porters posted on stretches in use
	var flags := {}                        # road carriers mode: flags the player set on roads (tile -> true)
	var ships := 0                         # ships built at its shipyards
	var ships_out := 0                     # ships at sea (expeditions and cargoes)
	var donkeys_used := 0                  # road carriers mode: donkeys out helping on busy stretches
	var store_total := 0                   # room for each good across all stores (before per-good factors)
	var store_porters := 0                 # porters employed by the stores
	var vets := 0.0
	var hunger := 0.0
	var starve := 0
	var imm_t := 0
	var die_t := 0
	var used_peasant := 0
	var used_artisan := 0
	var hq: Bld = null
	var start := Vector2i.ZERO
	var need_meter: Dictionary = {}
	var need_ok: Dictionary = {}
	## Idle workers who are specialists: "class:trade" -> experience of each one. A worker who leaves
	## a building keeps the experience of its trade and is hired first by the next building of that trade.
	var spec: Dictionary = {}
	## Production targets set by the player: resource -> how many to keep in stock (-1 = no limit).
	var targets: Dictionary = {}
	## Tools that buildings are waiting for right now: tool -> buildings that cannot hire a new worker.
	var tool_wait: Dictionary = {}
	var crowded := false      # rivals only: their land is full, so they grow by taking land (attack more)
	var crowded_t := 0.0      # game time it became crowded (0: it is not)
	var swap_t := -999.0      # rivals only: when it last pulled down a house to make room for a key building
	var swap_key := ""        # rivals only: the building that room was made for (built first)
	var reserved := PackedInt32Array()  # rivals only: large spots kept free for a farm or another large building
	var keep_artisans := 0    # rivals only: artisans kept free of workshop jobs so the barracks can train soldiers
	var sat: Dictionary = {"artisan": 0.0, "noble": 0.0}
	var tax := 0.0
	var opinion: Dictionary = {}   # other realm id -> how much this realm likes it (-100 to 100)
	var dip_t := 30.0
	var techs: Dictionary = {}
	var research := ""
	var reps: Dictionary = {}     # repeatable study id -> levels done
	var rqueue: Array = []        # what to study after the current research, in order (a study can repeat)
	var rp := 0.0
	var rp_total := 0.0
	var mods: Dictionary = {}
	var age := 0
	# AI settings
	var skill := 5
	var pers := "balanced"
	var prod := 1.0
	var think := 5.0
	var think_t := 0.0
	var grace := 0.0
	var attack_t := 0.0
	var odds := 1.3
	var focus := 0.0
	var max_b := 1


class Trip:
	var p := 0
	var res := ""
	var n := 1
	var t0 := 0.0
	var t1 := 0.0      # arrival at the store
	var t2 := 0.0      # back home, carrier free again
	var kind := "porter"
	var station := 0   # mule station or cart yard id, 0 for porters
	var delivered := false
	var path := PackedInt32Array()
	var site := 0      # a construction site this carrier brings materials to (0: goods to a store)
	var dest := 0      # a building this carrier brings goods to work with (from a store)
	var legs := PackedFloat32Array()  # road carriers mode: per stretch [from path index, to index, start, end]
	var aim := -1      # a ship on an expedition: the tile it lands on
	var res2 := ""    # a second good in the same load for that building (filling the load up)
	var n2 := 0
	                   # kind "builder" or "soldier": a person walking to building `site` (0: walking home);
	                   # for a soldier, n is his kind (0 legionary to 5 rifleman, -1 any)


class Attack:
	var p := 0
	var src := 0
	var tgt := 0
	var n := 0
	var t0 := 0.0
	var t1 := 0.0
	var fighting := false
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var step := 0.0
	var vet := 0.0
	var sxp := 0.0
	var era := 0.0     # average age of the soldiers marching
	var amix: Array = [] # the soldiers marching by kind
	var vt: Array = [0.0, 0.0]   # when the attackers' musketeers / riflemen can fire their next volley
	var dvt: Array = [0.0, 0.0]  # the same for the defenders shooting back
	var shot_t := -99.0          # game time of the last volley by the attackers (for the picture and sound)
	var dshot_t := -99.0         # and by the defenders
	var hits := 0                # soldiers hit by the last volley, for the picture
	var uid := 0                 # its own number (from the building ids), so a field battle can name its foe
	var n0 := 0                  # how many set out (a rival pulls back when over half have fallen and the gate still holds)
	var field := 0               # uid of the enemy column it is fighting in the open (0: none)
	var fstep := 0.0


class MinHeap:
	var k := PackedFloat32Array()
	var v := PackedInt32Array()

	func size() -> int:
		return k.size()

	func push(key: float, val: int) -> void:
		var i := k.size()
		k.append(key); v.append(val)
		while i > 0:
			var par := (i - 1) >> 1
			if k[par] <= k[i]:
				break
			var tk := k[par]; k[par] = k[i]; k[i] = tk
			var tv := v[par]; v[par] = v[i]; v[i] = tv
			i = par

	func pop() -> int:
		var top := v[0]
		var last := k.size() - 1
		k[0] = k[last]; v[0] = v[last]
		k.resize(last); v.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < last and k[l] < k[m]: m = l
			if r < last and k[r] < k[m]: m = r
			if m == i:
				break
			var tk := k[m]; k[m] = k[i]; k[i] = tk
			var tv := v[m]; v[m] = v[i]; v[i] = tv
			i = m
		return top


var w := 0


var h := 0


var ter := PackedByteArray()


var deco := PackedByteArray()


var amt := PackedByteArray()


var ore := PackedByteArray()


var shade := PackedByteArray()
var height := PackedByteArray()     # 0 to 255 per tile, from the ground and the seed (see WorldGen.heights); not saved


var pave := PackedByteArray()        # 1 where a road is paved with stone


var changed_tiles := PackedInt32Array()  # tiles whose look changed since the map view last checked


var vein := PackedInt32Array()       # vein id for each ore tile (0 = no vein)


var vein_amt: Array = [0]             # units left in each vein


var vein_tiles: Array = [PackedInt32Array()]


var owner := PackedByteArray()


var road := PackedByteArray()
var plot := PackedInt32Array()      # per tile: the building standing there (all its plot tiles); not saved, see _rebuild_plots


var bmap := PackedInt32Array()


var players: Array[Player] = []


var blds: Array[Bld] = []


var by_id: Dictionary = {}


var trips: Array[Trip] = []


var attacks: Array[Attack] = []


var time := 0.0


var over := false


var logs: Array = []


var map_dirty := true          # terrain/deco changed (minimap)


var territory_version := 0


var rng := RandomNumberGenerator.new()


var seed_str := ""


var foes := 3


var strength := 5


var map_size := 0


var mix := true


var research_victory := true


var rel: Dictionary = {}          # "a:b" -> Diplomacy.WAR / PEACE / ALLY


var rel_since: Dictionary = {}    # "a:b" -> time the relation last changed


var proposals: Array = []         # offers waiting for your answer
var standing: Array = []          # your standing trade offers (Diplomacy.standing_tick)


var _prop_id := 0


var _bid := 0


var _net_dist: Array = []          # per realm: walking seconds from each tile to the nearest store


var _net_dirty: Array = []         # per realm: network needs rebuilding


var _pending: Dictionary = {}      # ids of buildings with goods waiting for a carrier
var _supply: Dictionary = {}       # ids of construction sites still waiting for materials to be sent
var _reno: Dictionary = {}         # ids of buildings being renovated
var reno_queue: Dictionary = {}    # realm id -> ids of buildings waiting their turn to be renovated
const RENO_AT_ONCE := 2            # renovations a realm runs at once; the rest wait their turn


var _mil_dirty := true


var _tickers: Array[Bld] = []        # buildings that need ticks: under construction, or with a work cycle


var _tick_dirty := true              # _tickers must be rebuilt before the next tick


var _net_builds := 0                 # how many times a road network was rebuilt (for the benchmark)


var _net_add: Array = []             # per realm: tiles that only got better for its roads since the last update


var opts: Dictionary = DEFAULT_OPTS.duplicate()   # this game's difficulty options
var features: Array = []             # the switched-on optional features (Feature objects, see features/)


var perf: Dictionary = {}          # microseconds spent in each part of the simulation (shown with F3)


var _acc1 := 0.0


var _ticks := 0                     # counts ticks, so work can be spread over several of them
var _coming: Dictionary = {}        # realm id -> good -> on its way to the stores (see coming())
var _coming_tick := -1
var _type_bonus: Dictionary = {}    # realm id -> building type -> speed bonus from research (see rate()); emptied when research changes


var _owned_dirty := true


var _gs := PackedFloat32Array()


var _came := PackedInt32Array()


var _seen := PackedInt32Array()


var _closed := PackedInt32Array()


var _stamp := 0


# ================================================================ setup

func new_game(p_seed: String, p_foes: int, p_strength: int, p_mix: bool, p_size := 0, p_research_victory := true, p_opts := {}, p_map := {}, p_mission := {}) -> bool:
	GameData.ensure()
	# a hand-made map (map editor, missions) or one made from the seed
	var g := WorldGen.from_map(p_map, p_foes + 1) if not p_map.is_empty() else WorldGen.generate(p_seed, p_foes, p_size)
	if g.is_empty():
		return false
	if not p_map.is_empty():
		p_seed = String(g.seed)
		p_size = int(g.w)
	mission = p_mission.duplicate(true)
	mission_done = []
	seed_str = p_seed; foes = p_foes; strength = p_strength; mix = p_mix; map_size = p_size; research_victory = p_research_victory
	opts = DEFAULT_OPTS.duplicate()
	opts.merge(p_opts, true)
	w = g.w; h = g.h
	ter = g.ter; deco = g.deco; amt = g.amt; ore = g.ore; shade = g.shade
	height = WorldGen.heights(p_seed, ter, w, h)
	vein = g.vein; vein_amt = g.vein_amt; vein_tiles = g.vein_tiles
	pave = PackedByteArray(); pave.resize(w * h)
	changed_tiles = PackedInt32Array()
	_pending = {}; _supply = {}; _reno = {}; reno_queue = {}; _mil_dirty = true; _tick_dirty = true
	owner = PackedByteArray(); owner.resize(w * h)
	road = PackedByteArray(); road.resize(w * h)
	bmap = PackedInt32Array(); bmap.resize(w * h)
	plot = PackedInt32Array(); plot.resize(w * h)
	_avail = {}; _avail_at = {}
	players.clear(); blds.clear(); by_id.clear(); trips.clear(); attacks.clear(); logs.clear()
	rel = {}; rel_since = {}; proposals = []; standing = []; _prop_id = 0
	time = 0.0; over = false; _bid = 0; _acc1 = 0.0; _owned_dirty = true
	_alloc_path_buffers()
	rng.seed = seed_str.hash()
	var names := AI_NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = names[i]; names[i] = names[j]; names[j] = t
	var starts: Array = g.starts
	for k in starts.size():
		var p := Player.new()
		p.id = k + 1
		p.color = PCOL[k % PCOL.size()]
		p.ai = k != 0
		p.name = "You" if k == 0 else String(names[(k - 1) % names.size()])
		p.start = starts[k]
		p.res_era = 0.0
		for r in GameData.resources:
			p.stock[r.id] = 0.0
		var start_stock := {"wood": 20, "planks": 24, "stone": 18, "bread": 14, "fish": 8, "weapons": 2, "water": 6, "iron": 4}
		start_stock.merge(START_TOOLS)
		var sg := float(opts.start_goods)
		for r in start_stock:
			if p.stock.has(r):
				p.stock[r] = roundf(float(start_stock[r]) * sg)
		# with road carriers every realm starts with a few donkeys for its busiest stretches
		if bool(opts.get("road_carriers", false)) and p.stock.has("donkey"):
			p.stock["donkey"] = 4.0
		if p.ai:
			p.skill = clampi(roundi(strength + (rng.randf_range(-2.0, 2.0) if mix else 0.0)), 1, 10)
			var f := (p.skill - 1) / 9.0
			p.pers = PERSONALITIES[rng.randi() % 3]
			p.prod = 0.6 + 0.1 * p.skill
			p.think = 9.0 - 0.75 * p.skill
			p.think_t = 2.0 + k
			var pm := 0.75 if p.pers == "warlord" else (1.3 if p.pers == "builder" else 1.0)
			p.grace = (16.0 - 1.3 * p.skill) * 60.0 * pm * rng.randf_range(0.85, 1.15)
			p.attack_t = p.grace
			p.odds = 2.0 - 0.13 * p.skill
			p.focus = f * 0.8
			p.max_b = 1 + p.skill / 4
			p.stock.planks += roundf(f * 16); p.stock.stone += roundf(f * 10); p.stock.bread += roundf(f * 10)
			p.stock.weapons += roundf(f * 2)
			for t in ["axes", "pickaxes", "farm_tools"]:
				p.stock[t] += roundf(f * 2)
			p.artisan += roundi(f * 3); p.reserve += roundi(f * 4)
		players.append(p)
	for p in players:
		p.hq = add_bld("hq", p.start.x, p.start.y, p, true, 0)
		# the starting goods are in the headquarters
		for r in p.stock:
			if float(p.stock[r]) > 0.0:
				p.hq.inv[r] = float(p.stock[r])
		# the headquarters' plot is cleared of trees and rocks
		for t in plot_tiles("hq", p.start.x, p.start.y):
			if deco[t] != 0:
				deco[t] = 0; amt[t] = 0
	_reset_nets()
	for p in players:
		_recount_stores(p)
	recompute_territory()
	emit_log("The realm is founded. Build woodcutters, a sawmill and a quarry first.", Color("d8aa4a"))
	if bool(opts.get("all_research", false)):
		# every realm starts in the last age, with everything studied but the Industrial Revolution itself
		for p in players:
			for id in GameData.techs:
				if not GameData.techs[id].get("final", false):
					p.techs[id] = true
			_recompute_mods(p)
			p.res_era = float(p.age)
			p.rmix = []
			p.hq.era = p.age
		emit_log("All research is done: every realm starts in the %s age." % GameData.age_name(players[0].age), Color("8fc0ff"))
	if creative():
		emit_log("Creative mode: you build for free and at once, and your stores never run low.", Color("8fc0ff"))
	setup_features(opts.get("features", Features.default_ids()), false, {})
	return true


func _alloc_path_buffers() -> void:
	_gs = PackedFloat32Array(); _gs.resize(w * h)
	_came = PackedInt32Array(); _came.resize(w * h)
	_seen = PackedInt32Array(); _seen.resize(w * h)
	_closed = PackedInt32Array(); _closed.resize(w * h)
	_stamp = 0


## Adds a line to the event log. at is the tile it happened on, if any: the Events window then shows
## a Go button that moves the camera there. A log entry is [time, text, colour] or [time, text, colour, x, y].
func emit_log(text: String, col := Color(0.85, 0.85, 0.8), at := Vector2i(-1, -1)) -> void:
	var m := int(time) / 60
	var s := int(time) % 60
	if at.x >= 0:
		logs.append(["%02d:%02d" % [m, s], text, col, at.x, at.y])
	else:
		logs.append(["%02d:%02d" % [m, s], text, col])
	if logs.size() > 80:
		logs.pop_front()
	log_added.emit(text, col)


func human() -> Player:
	return players[0]


## How steep the way from tile a to its neighbour b is: 0 flat to 3 very steep.
func slope_level(a: int, b: int) -> int:
	if height.is_empty():
		return 0
	var dh := absi(int(height[a]) - int(height[b]))
	if dh < SLOPE_STEPS[0]: return 0
	if dh < SLOPE_STEPS[1]: return 1
	if dh < SLOPE_STEPS[2]: return 2
	return 3


## The steepest way out of tile i along realm pid's roads (or to its buildings): 0 to 3.
func road_slope(i: int, pid: int) -> int:
	var worst := 0
	var x := i % w
	var y := i / w
	for dd in 4:
		var nx := x + (1 if dd == 0 else (-1 if dd == 1 else 0))
		var ny := y + (1 if dd == 2 else (-1 if dd == 3 else 0))
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var ni := ny * w + nx
		if road[ni] == pid or (bmap[ni] != 0 and pid != 0 and links(i, ni)):
			worst = maxi(worst, slope_level(i, ni))
	return worst


func idx(x: int, y: int) -> int:
	return y * w + x


func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


# ================================================================ buildings

func add_bld(ty: String, x: int, y: int, p: Player, instant: bool, door := -1) -> Bld:
	var b := Bld.new()
	_bid += 1
	b.id = _bid; b.ty = ty; b.def = GameData.bld[ty]; b.x = x; b.y = y; b.p = p.id; b.door = door
	b.state = "ready" if instant else "build"
	b.cyc = float(b.def.get("cycle", 0.0))
	b.era = p.age
	b.sera = float(p.age)   # (loading fills it in like this too, so a loaded game matches)
	blds.append(b); by_id[b.id] = b
	bmap[idx(x, y)] = b.id
	for t in plot_tiles(ty, x, y):
		plot[t] = b.id
	_after_building_change(b)
	return b


func destroy(b: Bld, why := "") -> void:
	if b.dead:
		return
	var p := players[b.p - 1]
	p.res_xp = mix_xp(p.res_xp, p.reserve, b.sxp, b.garrison)
	if b.garrison > 0:
		mix_add(rmix_of(p), gmix_of(b))
	p.reserve += b.garrison
	b.garrison = 0
	b.gmix = []
	if b.staffed and b.state == "ready":
		_release_worker(p, b)
	# goods carried here for its work go back to the nearest store
	for k in b.inbuf:
		give(p, k, float(b.inbuf[k]), idx(b.x, b.y))
	b.inbuf = {}
	if is_store(b) and not b.inv.is_empty():
		b.dead = true
		logistics._store_ver += 1
		logistics.store_lost(b, p)
	b.dead = true
	by_id.erase(b.id)
	bmap[idx(b.x, b.y)] = 0
	for t in plot_tiles(b.ty, b.x, b.y):
		if plot[t] == b.id:
			plot[t] = 0
	blds.erase(b)
	_pending.erase(b.id)
	_supply.erase(b.id)
	_reno.erase(b.id)
	_after_building_change(b)
	if is_store(b):
		_recount_stores(p)
		_clamp_stock(p)
	if why != "" and b.p == 1:
		emit_log("%s %s" % [String(b.def.name), why], Color("e08a6a"), Vector2i(b.x, b.y))


func bld_at(x: int, y: int) -> Bld:
	if not inb(x, y):
		return null
	var id := bmap[idx(x, y)]
	return by_id.get(id) if id != 0 else null


func is_mil(b: Bld) -> bool:
	return b.ty == "hq" or b.def.has("garrison")


func demolish(b: Bld) -> void:
	var p := players[b.p - 1]
	var cost: Dictionary = b.def.get("cost", {})
	var at := idx(b.x, b.y)
	if b.reno_to >= 0:
		for k in b.onsite:
			give(p, k, int(b.onsite[k]), at)
	if b.state == "build" and b.mat_total > 0:
		# a site gives back what lies there unused, and some of what went into it
		for k in b.onsite:
			give(p, k, int(b.onsite[k]), at)
		for k in b.spent:
			give(p, k, floorf(int(b.spent[k]) * 0.4), at)
	else:
		for k in cost:
			give(p, k, floorf(float(cost[k]) * 0.4), at)
	var mil := is_mil(b) or bool(b.def.get("claim_only", false))
	destroy(b)
	if mil:
		recompute_territory()


## Level 1 to 5 for an amount of experience, using one of the XP tables above.
static func level(xp: float, table: Array) -> int:
	var lv := 0
	for t in table:
		if xp >= float(t):
			lv += 1
	return maxi(1, lv)


## Average experience after putting n_b soldiers of experience xp_b together with n_a of experience xp_a.
static func mix_xp(xp_a: float, n_a: int, xp_b: float, n_b: int) -> float:
	return (xp_a * n_a + xp_b * n_b) / maxf(1.0, n_a + n_b)


# ================================================================ placement

func count_near(cx: int, cy: int, r: int, mode: String, arg := 0) -> int:
	var c := 0
	var r2 := r * r + 1
	for y in range(maxi(0, cy - r), mini(h - 1, cy + r) + 1):
		for x in range(maxi(0, cx - r), mini(w - 1, cx + r) + 1):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy > r2:
				continue
			var i := y * w + x
			match mode:
				"tree":
					if deco[i] == D_TREE: c += 1
				"rock":
					if deco[i] == D_ROCK: c += amt[i]
					elif ore[i] == 4 and vein_left(i) > 0: c += 10
				"fish":
					if ter[i] == WATER: c += amt[i]
				"water":
					if ter[i] == WATER: c += 1
				"clay":
					if deco[i] == D_CLAY: c += amt[i]
				"open":
					if (ter[i] == GRASS or ter[i] == BEACH) and deco[i] == 0 and bmap[i] == 0 and plot[i] == 0 and road[i] == 0: c += 1
				"ore":
					if ore[i] == arg: c += mini(vein_left(i), 50)
	return c


func find_near(cx: int, cy: int, r: int, mode: String, arg := 0, pid := 0) -> int:
	var best := -1
	var bd := 9999
	var r2 := r * r + 1
	for y in range(maxi(0, cy - r), mini(h - 1, cy + r) + 1):
		for x in range(maxi(0, cx - r), mini(w - 1, cx + r) + 1):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy > r2:
				continue
			var i := y * w + x
			var ok := false
			match mode:
				"tree": ok = deco[i] == D_TREE
				"rock": ok = deco[i] == D_ROCK or (ore[i] == 4 and vein_left(i) > 0)
				"fish": ok = ter[i] == WATER and amt[i] > 0
				"clay": ok = deco[i] == D_CLAY and amt[i] > 0
				"ore": ok = ore[i] == arg and vein_left(i) > 0
				"plant": ok = ter[i] == GRASS and deco[i] == 0 and bmap[i] == 0 and plot[i] == 0 and road[i] == 0 and owner[i] == pid and rng.randf() < 0.35
			if ok:
				var dd := absi(dx) + absi(dy)
				if dd < bd:
					bd = dd; best = i
	return best


func site_check(d: Dictionary, x: int, y: int, runtime: bool) -> String:
	var s := String(d.get("site", ""))
	if s == "":
		return ""
	var a := s.split(":")
	match a[0]:
		"trees":
			if not runtime and count_near(x, y, int(a[2]), "tree") < int(a[1]): return "Not enough trees nearby"
		"rocks":
			if not runtime and count_near(x, y, int(a[1]), "rock") < 1: return "No rocks or granite nearby"
		"fish":
			if not runtime and count_near(x, y, int(a[1]), "fish") < 1: return "No fish nearby"
		"clay":
			if not runtime and count_near(x, y, int(a[1]), "clay") < 1: return "No clay nearby"
		"shore":
			if count_near(x, y, int(a[1]), "water") < 2: return "Needs open water nearby"
		"forest":
			if count_near(x, y, int(a[2]), "tree") < int(a[1]): return "Not enough forest nearby"
		"open":
			var need := int(a[1]) if not runtime else maxi(2, int(a[1]) - 3)
			if count_near(x, y, int(a[2]), "open") < need: return "Not enough open land"
	return ""


# ---------------------------------------------------------------- building sizes
## As in The Settlers: small buildings (huts, guard posts) stand on one tile, medium ones on two (one
## behind the other), large ones (farms, castles, warehouses) on a plot three wide and two deep, on
## flat ground. Mines stand on one mountain tile. Between any two buildings' plots there is at least
## one free tile (roads may use it), so buildings never stand on top of each other.
const SIZE_NAMES := {"small": "Small", "medium": "Medium", "large": "Large", "mine": "Mine"}
const PLOTS := {
	"small": [Vector2i(0, 0)],
	"mine": [Vector2i(0, 0)],
	"medium": [Vector2i(0, 0), Vector2i(0, -1)],
	"large": [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)],
}
## The sides an entrance may face (0 south, 1 east, 2 north, 3 west): never into its own plot.
const SIZE_DOORS := {"small": [0, 1, 2, 3], "mine": [0, 1, 2, 3], "medium": [0, 1, 3], "large": [0]}
## The largest height difference allowed across the plot (heights run 0 to 255).
const SIZE_SLOPE := {"small": 999, "mine": 999, "medium": 50, "large": 40}


func size_of(ty: String) -> String:
	var d: Dictionary = GameData.bld.get(ty, {})
	return String(d.get("size", "mine" if d.has("mine") else "medium"))


## The tiles building type ty would stand on at (x, y); empty if part of it is off the map.
func plot_tiles(ty: String, x: int, y: int) -> PackedInt32Array:
	return plot_tiles_size(size_of(ty), x, y)


func plot_tiles_size(size: String, x: int, y: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for o: Vector2i in PLOTS.get(size, PLOTS.medium):
		if not inb(x + o.x, y + o.y):
			return PackedInt32Array()
		out.append(idx(x + o.x, y + o.y))
	return out


## Whether an entrance of building type ty may face side d.
func door_ok(ty: String, d: int) -> bool:
	return d < 0 or (SIZE_DOORS.get(size_of(ty), [0]) as Array).has(d)


## Marks every building's plot (after loading; plots are not saved). Old saves may have buildings
## closer than the plots allow; they simply keep standing.
func _rebuild_plots() -> void:
	plot = PackedInt32Array(); plot.resize(w * h)
	for b in blds:
		if not b.dead:
			for t in plot_tiles(b.ty, b.x, b.y):
				plot[t] = b.id


## Whether a building of size size has room at (x, y) (its own tile is checked by can_place): every
## plot tile free and buildable, flat enough, and a free tile all round it. "" when it fits.
func plot_check(size: String, x: int, y: int, pid: int) -> String:
	var i0 := idx(x, y)
	var tiles := plot_tiles_size(size, x, y)
	if tiles.is_empty(): return "Too close to the edge of the map"
	var lo := 255
	var hi := 0
	for t in tiles:
		lo = mini(lo, int(height[t]) if not height.is_empty() else 0)
		hi = maxi(hi, int(height[t]) if not height.is_empty() else 0)
		if t == i0:
			continue
		if owner[t] != pid: return "The %s building does not fit inside your territory here" % String(SIZE_NAMES[size]).to_lower()
		if bmap[t] != 0 or plot[t] != 0: return "Not enough room: a %s building needs %d tiles" % [String(SIZE_NAMES[size]).to_lower(), tiles.size()]
		if road[t] != 0: return "A road crosses the plot (a %s building needs %d tiles)" % [String(SIZE_NAMES[size]).to_lower(), tiles.size()]
		if deco[t] == D_TREE: return "Trees in the way of the plot"
		if deco[t] == D_ROCK or deco[t] == D_CLAY: return "Rocks in the way of the plot"
		if ter[t] == WATER or ter[t] == MOUNT: return "Not enough flat land for a %s building" % String(SIZE_NAMES[size]).to_lower()
		var eb := door_owner(t % w, t / w, owner[t])
		if eb != null: return "Keep the entrance of the %s free" % String(eb.def.name).to_lower()
	if hi - lo > int(SIZE_SLOPE[size]): return "Too steep: a %s building needs flatter ground" % String(SIZE_NAMES[size]).to_lower()
	for t in tiles:
		var tx := t % w
		var ty2 := t / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not inb(tx + dx, ty2 + dy):
					continue
				var n := idx(tx + dx, ty2 + dy)
				if plot[n] != 0 and not tiles.has(n):
					var nb: Bld = by_id.get(plot[n])
					return "Too close to the %s: buildings need a free tile between them" % (String(nb.def.name).to_lower() if nb != null else "next building")
	return ""


## The largest size of building that has room at (x, y) for realm pid, ignoring what a particular
## building needs nearby (trees, water...) and research: "" (none), "small", "medium", "large" or "mine".
## The map shows it as building-site markers, as in The Settlers.
func site_size(x: int, y: int, pid: int) -> String:
	if not inb(x, y):
		return ""
	var i := idx(x, y)
	if owner[i] != pid or bmap[i] != 0 or plot[i] != 0 or deco[i] != 0 or road[i] != 0:
		return ""
	if door_owner(x, y, pid) != null:
		return ""
	var t := ter[i]
	if t == WATER:
		return ""
	if t == MOUNT and (ore[i] == 0 or ore[i] == 4 or not ore_known(pid, i) or vein_left(i) == 0):
		return ""        # mine sites only where a geologist found coal, iron, gold or copper
	var best := ""
	for size in (["mine"] if t == MOUNT else ["small", "medium", "large"]):
		if plot_check(size, x, y, pid) != "":
			break
		# it needs somewhere for its entrance too
		var any := false
		for d: int in SIZE_DOORS[size]:
			var dt := door_at(x, y, d)
			if dt >= 0 and owner[dt] == pid and bmap[dt] == 0 and plot[dt] == 0 and ter[dt] != WATER and deco[dt] != D_ROCK and deco[dt] != D_CLAY:
				any = true
				break
		if not any:
			break
		best = size
	return best


# ---------------------------------------------------------------- entrances
## A building's entrance faces one side (Bld.door); its road must join it there, on the entrance tile.
const DOOR_DX := [0, 1, 0, -1]
const DOOR_DY := [1, 0, -1, 0]
const DOOR_NAMES := ["south", "east", "north", "west"]


## The tile in front of an entrance at (x, y) facing side d, or -1 off the map.
func door_at(x: int, y: int, d: int) -> int:
	if d < 0:
		return -1
	var nx: int = x + int(DOOR_DX[d])
	var ny: int = y + int(DOOR_DY[d])
	return idx(nx, ny) if inb(nx, ny) else -1


## The entrance tile of building b, or -1 when it can be reached from any side.
func door_tile(b: Bld) -> int:
	return door_at(b.x, b.y, b.door)


## The side neighbour tile o lies on from tile a (0 south, 1 east, 2 north, 3 west).
func side_of(a: int, o: int) -> int:
	var dx := o % w - a % w
	var dy := o / w - a / w
	if dy > 0: return 0
	if dx > 0: return 1
	if dy < 0: return 2
	return 3


## Your building (realm pid) whose entrance is tile (x, y), or null.
func door_owner(x: int, y: int, pid: int) -> Bld:
	if not inb(x, y):
		return null
	var i := idx(x, y)
	for dd in 4:
		var nb := bld_at(x + int(DOOR_DX[dd]), y + int(DOOR_DY[dd]))
		if nb != null and nb.p == pid and nb.door >= 0 and door_tile(nb) == i:
			return nb
	return null


## Whether neighbouring tiles a and o join for roads and carriers: a building only through its entrance.
func links(a: int, o: int) -> bool:
	if bmap[a] != 0:
		var b: Bld = by_id.get(bmap[a])
		if b != null and b.door >= 0 and door_tile(b) != o:
			return false
	if bmap[o] != 0:
		var c: Bld = by_id.get(bmap[o])
		if c != null and c.door >= 0 and door_tile(c) != a:
			return false
	return true


## Whether (x, y) lies within the land of one of realm pid's manned military buildings (or its
## headquarters), not only in land a boundary stone claimed. Stones can't be chained out that way.
func _soldiers_hold(x: int, y: int, pid: int) -> bool:
	for b in blds:
		if b.p != pid or b.dead or b.state != "ready" or not (b.ty == "hq" or (b.def.has("garrison") and b.garrison > 0)):
			continue
		var r := int(b.def.get("radius", 6))
		if (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) <= r * r:
			return true
	return false


func can_place(ty: String, x: int, y: int, pid: int, door := -1) -> String:
	if not inb(x, y):
		return "Outside the map"
	var i := idx(x, y)
	var d: Dictionary = GameData.bld[ty]
	if owner[i] != pid: return "Outside your territory"
	if bmap[i] != 0 or plot[i] != 0: return "Tile is occupied"
	if deco[i] == D_TREE: return "Trees in the way"
	if deco[i] == D_ROCK: return "Rocks in the way"
	if deco[i] == D_CLAY: return "Clay in the way"
	if road[i] != 0: return "A road is in the way"
	if d.get("claim_only", false) and not _soldiers_hold(x, y, pid):
		return "A boundary stone must stand on land your soldiers hold"
	# no building on the doorstep of a neighbour
	for dd in 4:
		var nb := bld_at(x + int(DOOR_DX[dd]), y + int(DOOR_DY[dd]))
		if nb != null and door_tile(nb) == i:
			return "Keep the entrance of the %s free" % String(nb.def.name).to_lower()
	var size := size_of(ty)
	var pc := plot_check(size, x, y, pid)
	if pc != "": return pc
	if not door_ok(ty, door):
		return "A %s building's entrance can face only %s" % [String(SIZE_NAMES[size]).to_lower(), " or ".join((SIZE_DOORS[size] as Array).map(func(k): return DOOR_NAMES[k]))]
	# a new road must be able to get to its entrance (not closed in by plots, water or rocks)
	var rr := logistics.reach(pid)
	var any_way := false
	var own_plot := plot_tiles_size(size, x, y)
	for d2: int in ([door] if door >= 0 else SIZE_DOORS.get(size, [0])):
		var t2 := door_at(x, y, d2)
		if t2 < 0 or rr[t2] != 1:
			continue
		if road[t2] == pid:
			any_way = true
			break
		# the way to it must not lead through the new building's own plot
		for dd in 4:
			var nx: int = t2 % w + DOOR_DX[dd]
			var ny: int = t2 / w + DOOR_DY[dd]
			if inb(nx, ny) and rr[ny * w + nx] == 1 and not own_plot.has(ny * w + nx) and ny * w + nx != idx(x, y):
				any_way = true
				break
		if any_way:
			break
	if not any_way:
		return "No road can get to this spot (closed in by buildings, water or rocks)" if door < 0 else "No road can get to this entrance (try turning it with R)"
	if door >= 0:
		var dt := door_at(x, y, door)
		if dt < 0 or owner[dt] != pid: return "The entrance must face your own land"
		if bmap[dt] != 0 or plot[dt] != 0: return "Another building blocks the entrance"
		if ter[dt] == WATER: return "The entrance faces water"
		if deco[dt] == D_ROCK or deco[dt] == D_CLAY: return "Rocks block the entrance"
	if d.has("tech") and not players[pid - 1].techs.has(d.tech):
		return "Needs research: " + GameData.tech_name(d.tech)
	if not bld_enabled(ty):
		return "Belongs to a game feature that is switched off"
	var t := ter[i]
	if d.has("mine"):
		if t != MOUNT: return "Mines go on mountains"
		if not ore_known(pid, i): return "Not surveyed: send a geologist here first"
		if ore[i] != int(d.mine) or vein_left(i) == 0: return "No %s deposit here" % GameData.ORE_NAMES.get(int(d.mine), "ore")
		return ""
	if t == WATER: return "Cannot build on water"
	if t == MOUNT: return "Too steep, mines only"
	var sc := site_check(d, x, y, false)
	if sc != "": return sc
	if d.get("needs_noble", false) and players[pid - 1].noble < 1: return "Needs a noble in your realm"
	return ""


func missing(p: Player, cost: Dictionary) -> String:
	for k in cost:
		if float(p.stock.get(k, 0.0)) < float(cost[k]):
			return k
	return ""


## Creative mode (a new-game option): your buildings cost nothing and stand at once, and your stores
## are kept at least half full. The rivals play by the usual rules.
func creative(p: Player = null) -> bool:
	return bool(opts.get("creative", false)) and (p == null or not p.ai)


## Places a building site. door is the side its entrance faces (-1: whichever side its road leaves
## from, as the rivals build). With road true the road to your network is laid at once; without it you
## lay it yourself (the site waits for it).
func place(ty: String, x: int, y: int, p: Player, door := -1, road := true) -> String:
	var bad := can_place(ty, x, y, p.id, door)
	if bad != "":
		return bad
	var d: Dictionary = GameData.bld[ty]
	var cost: Dictionary = d.get("cost", {})
	var path := PackedInt32Array()
	if road or door < 0:
		# the road may not cross the new building's own plot, and leaves by an allowed entrance
		var own := plot_tiles(ty, x, y)
		for t in own:
			if t != idx(x, y): plot[t] = -1
		path = _path_to_net(x, y, p.id, door, SIZE_DOORS.get(size_of(ty), [0]))
		for t in own:
			if plot[t] == -1: plot[t] = 0
		if path.is_empty():
			return "No road route to your roads or a store"
		var bw := logistics.bridge_cost_ok(path, p.id)
		if bw != "":
			return bw
		if door < 0 and path.size() > 1:
			door = side_of(path[0], path[1])
	# nothing is taken from the stores now: carriers bring the materials to the site as it needs them
	var b := add_bld(ty, x, y, p, false, door)
	if creative(p):
		cost = {}
	for k in cost:
		if int(cost[k]) > 0:
			b.need[k] = int(cost[k])
			b.mat_total += int(cost[k])
	if b.mat_total > 0:
		_supply[b.id] = true
	if not path.is_empty():
		lay_road(path, p.id)
	return ""


## A carrier reached construction site t.site with materials. If the site is gone (demolished,
## captured, burnt), he takes them back to the store.
func _site_arrival(t: Trip, p: Player) -> void:
	var b: Bld = by_id.get(t.site)
	if b != null and not b.dead and (b.state == "build" or b.reno_to >= 0) and b.p == t.p:
		b.coming[t.res] = maxi(0, int(b.coming.get(t.res, 0)) - t.n)
		if int(b.coming[t.res]) == 0:
			b.coming.erase(t.res)
		b.onsite[t.res] = int(b.onsite.get(t.res, 0)) + t.n
		b.retry = 0.0
	elif p.alive:
		give(p, t.res, t.n, t.path[0] if t.path.size() > 0 else -1)


# ================================================================ ages: looks, renovation, soldiers

const SOLDIER_NAMES := ["legionary", "spearman", "man-at-arms", "pikeman", "musketeer", "rifleman"]


const SOLDIER_PLURALS := ["legionaries", "spearmen", "men-at-arms", "pikemen", "musketeers", "riflemen"]


# ---------------------------------------------------------------- soldiers by kind
## A "mix" is an array of six counts: legionaries, spearmen, men-at-arms, pikemen, musketeers,
## riflemen. The plain counts (reserve, garrison, attack size) stay the totals; mix_fix keeps a mix
## matching its total, adding soldiers of the given kind or dropping the oldest, so the two can never
## drift apart.
static func mix_fix(m: Array, n: int, fill: int) -> Array:
	while m.size() < 6:
		m.append(0)
	var sum := 0
	for k in 6:
		m[k] = maxi(0, int(m[k]))
		sum += int(m[k])
	if sum < n:
		m[clampi(fill, 0, 5)] += n - sum
	var k2 := 0
	while sum > n and k2 < 6:
		var take := mini(int(m[k2]), sum - n)
		m[k2] -= take
		sum -= take
		k2 += 1
	return m


static func mix_count(m: Array) -> int:
	var n := 0
	for v in m:
		n += int(v)
	return n


## The average kind (0 legionaries to 5 riflemen), or 0 if empty.
static func mix_avg(m: Array) -> float:
	var n := 0
	var s := 0
	for k in m.size():
		n += int(m[k])
		s += int(m[k]) * k
	return float(s) / n if n > 0 else 0.0


static func mix_newest(m: Array) -> int:
	for k in range(m.size() - 1, -1, -1):
		if int(m[k]) > 0:
			return k
	return -1


static func mix_oldest(m: Array) -> int:
	for k in m.size():
		if int(m[k]) > 0:
			return k
	return 99


static func mix_add(dst: Array, src: Array) -> void:
	mix_fix(dst, mix_count(dst), 0)
	for k in mini(6, src.size()):
		dst[k] += int(src[k])


## Takes up to n soldiers out of m, the newest kinds first, and returns them as a new mix.
static func mix_take_best(m: Array, n: int) -> Array:
	var out := [0, 0, 0, 0, 0, 0]
	for k in range(m.size() - 1, -1, -1):
		var t := mini(int(m[k]), n)
		m[k] -= t
		out[k] += t
		n -= t
	return out


## Removes one soldier of kind k (or, if there is none, the oldest one). Returns the kind removed.
static func mix_remove(m: Array, k: int) -> int:
	if k >= 0 and k < m.size() and int(m[k]) > 0:
		m[k] -= 1
		return k
	var o := mix_oldest(m)
	if o < m.size():
		m[o] -= 1
		return o
	return -1


## A soldier picked at random from the mix (weighted by the counts).
static func mix_pick(m: Array, r: RandomNumberGenerator) -> int:
	var n := mix_count(m)
	if n <= 0:
		return 1
	var x := r.randi() % n
	for k in m.size():
		x -= int(m[k])
		if x < 0:
			return k
	return 0


## "3 pikemen, 2 musketeers"
static func mix_text(m: Array) -> String:
	var parts := []
	for k in range(m.size() - 1, -1, -1):
		var v := int(m[k])
		if v > 0:
			parts.append("%d %s" % [v, soldier_name(k) if v == 1 else soldier_plural(k)])
	return ", ".join(parts) if not parts.is_empty() else "none"


## Realm p's soldiers at headquarters by kind, kept matching p.reserve.
func rmix_of(p: Player) -> Array:
	return mix_fix(p.rmix, p.reserve, roundi(maxf(0.0, p.res_era)))


## Building b's garrison by kind, kept matching b.garrison.
func gmix_of(b: Bld) -> Array:
	return mix_fix(b.gmix, b.garrison, roundi(maxf(0.0, b.sera)))


## All of realm p's soldiers by kind: at headquarters, in garrisons and marching.
func soldier_mix(p: Player) -> Array:
	var m := rmix_of(p).duplicate()
	for b: Bld in mil_list():
		if b.p == p.id and b.ty != "hq":
			mix_add(m, gmix_of(b))
	for a in attacks:
		if a.p == p.id:
			mix_add(m, mix_fix(a.amix, a.n, roundi(a.era)))
	return m


static func soldier_name(era: int) -> String:
	return SOLDIER_NAMES[clampi(era, 0, 5)]


static func soldier_plural(era: int) -> String:
	return SOLDIER_PLURALS[clampi(era, 0, 5)]


## Saves from before build 18: buildings keep the Early Medieval look they always had, and soldiers
## are of their realm's current age.
func _fix_eras() -> void:
	for p in players:
		if p.res_era < 0.0:
			p.res_era = float(p.age)
	for b in blds:
		if b.era < 0:
			b.era = 1
		if b.sera < 0.0:
			b.sera = float(players[b.p - 1].age)


## Why building b can't be renovated now ("" if it can).
func can_renovate(b: Bld) -> String:
	var p := players[b.p - 1]
	if b.state != "ready":
		return "Not finished yet"
	if b.reno_to >= 0 or (reno_queue.get(p.id, []) as Array).has(b.id):
		return "Already being renovated"
	if b.era >= p.age:
		return "Already in the style of your age"
	return ""


func _renos_running(p: Player) -> int:
	var n := 0
	for id in _reno:
		var b: Bld = by_id.get(id)
		if b != null and b.p == p.id:
			n += 1
	return n


## Renovates building b into the style of its realm's current age: half its building cost, carried
## there by carriers, and half its building time; work stops meanwhile. A realm renovates two
## buildings at once; more wait their turn. Returns "" or why not.
func renovate(b: Bld) -> String:
	var why := can_renovate(b)
	if why != "":
		return why
	var p := players[b.p - 1]
	if _renos_running(p) >= RENO_AT_ONCE:
		if not reno_queue.has(p.id):
			reno_queue[p.id] = []
		(reno_queue[p.id] as Array).append(b.id)
		return ""
	_start_reno(b)
	return ""


func _start_reno(b: Bld) -> void:
	var p := players[b.p - 1]
	b.need = {}; b.coming = {}; b.onsite = {}; b.spent = {}
	b.mat_total = 0; b.mat_used = 0
	var cost: Dictionary = b.def.get("cost", {})
	for k in cost:
		var n := ceili(float(cost[k]) * 0.5)
		if n > 0:
			b.need[k] = n
			b.mat_total += n
	b.reno_to = p.age
	b.reno_prog = 0.0
	b.retry = 0.0
	_reno[b.id] = true
	if b.mat_total > 0:
		_supply[b.id] = true


## Queues every outdated building of type ty in realm p for renovation. Returns how many.
func renovate_all(p: Player, ty: String) -> int:
	var n := 0
	for b: Bld in realm_blds(p):
		if b.ty == ty and can_renovate(b) == "":
			renovate(b)
			n += 1
	return n


## Renovation work, once a second: like construction, it goes only as far as the materials allow.
func _reno_tick(p: Player) -> void:
	for id in _reno.keys():
		var b: Bld = by_id.get(id)
		if b == null or b.dead:
			_reno.erase(id)
			continue
		if b.p != p.id:
			continue
		if b.mat_total > 0 and b.reno_prog >= float(b.mat_used) / b.mat_total - 0.0001 and b.mat_used < b.mat_total:
			var got := ""
			for k in b.onsite:
				if int(b.onsite[k]) > 0:
					got = k
					break
			if got == "":
				continue
			b.onsite[got] = int(b.onsite[got]) - 1
			if int(b.onsite[got]) <= 0:
				b.onsite.erase(got)
			b.spent[got] = int(b.spent.get(got, 0)) + 1
			b.mat_used += 1
		var t := maxf(4.0, float(b.def.get("time", 10)) * 0.5)
		b.reno_prog += (1.0 + mod(p, "build")) * float(opts.build) / t
		if b.mat_total > 0:
			b.reno_prog = minf(b.reno_prog, float(b.mat_used) / b.mat_total)
		if b.reno_prog >= 1.0:
			b.era = b.reno_to
			b.reno_to = -1
			b.reno_prog = 0.0
			b.need = {}; b.coming = {}; b.onsite = {}; b.spent = {}
			b.mat_total = 0; b.mat_used = 0
			b.retry = 0.0
			_reno.erase(id)
			changed_tiles.append(idx(b.x, b.y))
			if not p.ai:
				emit_log("The %s now stands in the %s style." % [String(b.def.name).to_lower(), GameData.age_name(b.era)], Color("d8aa4a"), Vector2i(b.x, b.y))
			# the next one waiting gets its turn
			var q: Array = reno_queue.get(p.id, [])
			while not q.is_empty() and _renos_running(p) < RENO_AT_ONCE:
				var nb: Bld = by_id.get(int(q.pop_front()))
				if nb != null and not nb.dead and nb.state == "ready" and nb.era < p.age and nb.reno_to < 0:
					_start_reno(nb)
	# rivals renovate now and then when they have materials to spare
	if p.ai and p.age > 0 and _renos_running(p) == 0 and rng.randf() < 1.0 / 90.0:
		var promised := committed(p)
		if float(p.stock.get("planks", 0.0)) - int(promised.get("planks", 0)) > 20.0 and float(p.stock.get("stone", 0.0)) - int(promised.get("stone", 0)) > 14.0:
			var old := []
			for b: Bld in realm_blds(p):
				if can_renovate(b) == "":
					old.append(b)
			if not old.is_empty():
				renovate(old[rng.randi() % old.size()])


## Materials realm p has promised to its construction sites but not yet sent: res -> units.
func committed(p: Player) -> Dictionary:
	var out := {}
	for id in _supply:
		var b: Bld = by_id.get(id)
		if b != null and b.p == p.id:
			for k in b.need:
				out[k] = int(out.get(k, 0)) + int(b.need[k])
	return out


## What construction site b is waiting for, as text ("" when it has what it needs).
func materials_text(b: Bld) -> String:
	var parts := []
	for k in b.def.get("cost", {}):
		var total := int(b.def.cost[k])
		var arrived := int(b.spent.get(k, 0)) + int(b.onsite.get(k, 0))
		var way := int(b.coming.get(k, 0))
		parts.append("%s %d/%d%s" % [GameData.res_name(k).to_lower(), arrived, total, (" (+%d on the way)" % way) if way > 0 else ""])
	return ", ".join(parts)


# ================================================================ economy

func food_total(p: Player) -> float:
	return people.food_total(p)


func take_food(p: Player, at := -1) -> float:
	return people.take_food(p, at)


## Puts n of res into realm p's stores, nearest tile `at` first (see SimLogistics.give).
func give(p: Player, res: String, n: float, at := -1) -> float:
	return logistics.give(p, res, n, at)


## Takes up to n of res from realm p's stores, nearest tile `at` first. Returns how much it got.
func take(p: Player, res: String, n: float, at := -1) -> float:
	return logistics.take(p, res, n, at)


# ================================================================ optional features
## Switches on the features with these ids (and off all others). states holds saved feature data.
func setup_features(ids: Array, loaded: bool, states: Dictionary) -> void:
	features.clear()
	var keep := []
	for e in Features.available():
		if e.id in ids:
			var f: Feature = (e.script as GDScript).new()
			# a feature that needs another one switched off stays off
			var ok := true
			for need in f.needs:
				if not (need in ids):
					ok = false
			if not ok:
				continue
			f.sim = self
			if loaded and states.has(f.id):
				f.load_state(states[f.id])
			features.append(f)
			keep.append(f.id)
	opts["features"] = keep
	for f: Feature in features:
		f.on_start(loaded)


## Switches one feature on or off in the running game.
func set_feature(id: String, on: bool) -> void:
	var ids: Array = feature_ids()
	if on == (id in ids):
		return
	if on:
		for e in Features.available():
			if e.id == id:
				for need in e.needs:
					if not (need in ids):
						return
				var f: Feature = (e.script as GDScript).new()
				f.sim = self
				features.append(f)
				# always in the same order as a new or loaded game has them (seasons before clothes...)
				var order := Features.available().map(func(x): return x.id)
				features.sort_custom(func(x, y): return order.find(x.id) < order.find(y.id))
				f.on_start(false)
	else:
		for f: Feature in features.duplicate():
			if f.id == id:
				features.erase(f)
		# features that need this one go off with it
		for f: Feature in features.duplicate():
			if id in f.needs:
				set_feature(f.id, false)
	opts["features"] = feature_ids()


## Whether realm pid knows what lies under tile i (always, unless the geologists feature is on).
func ore_known(pid: int, i: int) -> bool:
	var g = get_feature("geology")
	return g == null or g.known_at(pid, i)


## Whether the feature with this id is switched on in this game.
func feature_on(id: String) -> bool:
	for f: Feature in features:
		if f.id == id:
			return true
	return false


## Whether building type ty can be built: buildings that belong to a feature need it switched on.
func bld_enabled(ty: String) -> bool:
	var d: Dictionary = GameData.bld.get(ty, {})
	if bool(d.get("carriers_mode", false)) and not bool(opts.get("road_carriers", false)):
		return false
	var fid := String(d.get("feature", ""))
	return fid == "" or feature_on(fid)


## Whether tech (or repeatable study) id is in play: a tech that only helps a switched-off feature isn't.
func tech_enabled(id: String) -> bool:
	var d: Dictionary = GameData.techs.get(id, GameData.reps.get(id, {}))
	var fid := String(d.get("feature", ""))
	return fid == "" or feature_on(fid)


func feature_ids() -> Array:
	return features.map(func(f): return f.id)


func get_feature(id: String) -> Feature:
	for f: Feature in features:
		if f.id == id:
			return f
	return null


## Realm p used up n of res: tells the features (statistics count it).
func used(p: Player, res: String, n: float) -> void:
	for f: Feature in features:
		f.on_used(p, res, n)


func _feature_states() -> Dictionary:
	var out := {}
	for f: Feature in features:
		# a deep copy: the save must not share arrays with the running game
		out[f.id] = f.save_state().duplicate(true)
	return out


## A building of realm p made n of res.
func made(p: Player, res: String, n: float) -> void:
	for f: Feature in features:
		f.on_made(p, res, n)


func housing(p: Player) -> int:
	return people.housing(p)


func pop_total(p: Player) -> int:
	return people.pop_total(p)


func soldiers(p: Player) -> int:
	return people.soldiers(p)


func idle(p: Player, cls: String) -> int:
	return people.idle(p, cls)


func rate(p: Player, b: Bld) -> float:
	return people.rate(p, b)


func staffing(p: Player) -> void:
	people.staffing(p)


## Whether building b has a priority to set: construction sites and buildings with a worker.
func has_priority(b: Bld) -> bool:
	return b.state == "build" or b.def.has("worker")


func set_priority(b: Bld, pr: int) -> void:
	people.set_priority(b, pr)


func spec_key(b: Bld) -> String:
	return people.spec_key(b)


func _release_worker(p: Player, b: Bld) -> void:
	people._release_worker(p, b)


func _hire_worker(p: Player, b: Bld) -> void:
	people._hire_worker(p, b)


func _trim_specialists(p: Player, cls: String, idle_n: int) -> void:
	people._trim_specialists(p, cls, idle_n)


func trade_summary(p: Player) -> Dictionary:
	return people.trade_summary(p)


func start_check(b: Bld, p: Player) -> String:
	return production.start_check(b, p)


func coming(p: Player, res: String) -> float:
	return production.coming(p, res)


func _count_cycle(b: Bld, p: Player, c: Dictionary) -> void:
	production._count_cycle(b, p, c)


func _extra_out(p: Player, ty: String) -> int:
	return production._extra_out(p, ty)


func store_goods(p: Player, res: String, n: float, at := -1) -> void:
	production.store_goods(p, res, n, at)


func deliver(b: Bld, p: Player, res: String, n: int) -> void:
	production.deliver(b, p, res, n)


func finish_prod(b: Bld, p: Player) -> void:
	production.finish_prod(b, p)


func build_tick(b: Bld, p: Player, dt: float) -> void:
	production.build_tick(b, p, dt)


func _finish_site(b: Bld, p: Player) -> void:
	production._finish_site(b, p)


func prod_tick(b: Bld, p: Player, _dt: float) -> void:
	production.prod_tick(b, p, _dt)


func work_progress(b: Bld) -> float:
	return production.work_progress(b)


# ---------------------------------------------------------------- where people wait
## Idle people do not wait just anywhere: newcomers live in homes (houses, apartments), people who
## were just trained wait at the building that trained them (artisans at the school, soldiers at the
## barracks, scouts at the scout lodge), workers' lodges keep up to 12 idle workers near where work is,
## and the headquarters takes everyone else. A worker, builder or soldier who is needed walks along the
## roads from the nearest of these that has one. Who waits where is worked out from the counts each
## time it is needed (it is not saved), always in the same order.

func walks_to_work(b: Bld) -> bool:
	return people.walks_to_work(b)


func home_cap(b: Bld, cls: String) -> int:
	return people.home_cap(b, cls)


var _avail_at := {}      # realm id -> tick the list below was worked out
var _avail := {}         # realm id -> {class: {building id: idle people there}}

func home_avail(p: Player) -> Dictionary:
	return people.home_avail(p)


func nearest_home(p: Player, b: Bld, cls: String) -> Array:
	return people.nearest_home(p, b, cls)


func send_from_home(b: Bld, p: Player, kind: String, cls: String, n := 0) -> bool:
	return people.send_from_home(b, p, kind, cls, n)


func send_walker(b: Bld, p: Player, kind: String, n: int) -> bool:
	return people.send_walker(b, p, kind, n)


func _walker_arrival(t: Trip, p: Player) -> void:
	people._walker_arrival(t, p)


func mil_fill(p: Player) -> bool:
	return people.mil_fill(p)


func garrison_wanted(b: Bld) -> int:
	return people.garrison_wanted(b)


func kind_allowed(b: Bld, k: int) -> bool:
	return people.kind_allowed(b, k)


func _newest_allowed(b: Bld, m: Array) -> int:
	return people._newest_allowed(b, m)


func _garrison_settle(b: Bld, p: Player, want: int) -> void:
	people._garrison_settle(b, p, want)


func update_needs(p: Player) -> void:
	people.update_needs(p)


# ================================================================ tick

## Adds the time since t0 (from Time.get_ticks_usec) to the perf counter called k.
func _pf(k: String, t0: int) -> void:
	perf[k] = int(perf.get(k, 0)) + Time.get_ticks_usec() - t0


func tick(dt: float) -> void:
	time += dt
	_ticks += 1
	var t0 := Time.get_ticks_usec()
	var parity := _ticks % 2
	if _tick_dirty:
		_tickers.clear()
		for b in blds:
			if b.state == "build" or b.cyc > 0.0:
				_tickers.append(b)
		_tick_dirty = false
	# destroy() only marks buildings dead and flags the list, so walking it here is safe
	for b: Bld in _tickers:
		if b.dead or b.retry > time:
			continue
		if b.state == "build" and b.id % 2 != parity:
			continue
		if b.cyc <= 0.0 and b.state == "ready":
			continue
		var p := players[b.p - 1]
		if not p.alive:
			continue
		if b.state == "build":
			build_tick(b, p, dt * 2.0)
		else:
			prod_tick(b, p, dt * 2.0)
	_pf("buildings", t0)
	t0 = Time.get_ticks_usec()
	if _ticks % 3 == 0:
		_dispatch()
	var k := trips.size() - 1
	while k >= 0:
		var t := trips[k]
		if not t.delivered and time >= t.t1:
			t.delivered = true
			var p := players[t.p - 1]
			if t.kind == "ship":
				sea.ship_arrival(t, p)
			elif t.kind == "trade":
				Diplomacy.cart_arrival(self, t)
			elif t.kind == "builder" or t.kind == "soldier" or t.kind == "worker":
				_walker_arrival(t, p)
			elif t.dest != 0:
				logistics.input_arrival(t, p)
			elif t.site != 0:
				_site_arrival(t, p)
			elif p.alive:
				logistics.arrive_at_store(t, p)
		if t.delivered and time >= t.t2:
			_free_carrier(t)
			trips[k] = trips[trips.size() - 1]
			trips.pop_back()
		k -= 1
	if changed_tiles.size() > 100000:
		changed_tiles.clear()
		map_dirty = true
	_pf("carriers", t0)
	t0 = Time.get_ticks_usec()
	attack_tick(dt)
	_pf("combat", t0)
	_acc1 += dt
	if _acc1 >= 1.0:
		_acc1 -= 1.0
		_secondly()


## For finding where two runs of the same game part ways: a number that changes with any change to the
## saved state. Start the game with "-- checksums" (or set Sim.log_checksums) to print one every game
## minute; two runs (or a run and a reload) that print different numbers went apart in that minute.
static var log_checksums := false

# --- Missions -------------------------------------------------------------------------------------------
# A mission (data/missions.json) is a game with goals: {name, story, goals: [...], minutes (a deadline,
# 0 for none), ...}. Each goal is {"kind": ..., ...}: "pop" (n people), "build" (ty, n ready buildings),
# "soldiers" (n), "tech" (id studied), "land" (n tiles), "stock" (res, n in store), "defeat" (n rival
# realms gone; 0 or missing: all of them). All goals done: won. The deadline passes first: lost.
var mission := {}
var mission_done: Array = []      # one flag per goal; a goal once done stays done


## How far goal g is: [now, needed].
func goal_progress(g: Dictionary) -> Array:
	var me := human()
	var n := int(g.get("n", 1))
	match String(g.get("kind", "")):
		"pop":
			return [pop_total(me), n]
		"build":
			var c := 0
			for b in realm_blds(me):
				if b.ty == String(g.get("ty", "")) and b.state == "ready":
					c += 1
			return [c, n]
		"soldiers":
			return [soldiers(me), n]
		"tech":
			return [1 if me.techs.has(String(g.get("id", ""))) else 0, 1]
		"land":
			return [owned(me.id)[0].size(), n]
		"stock":
			return [int(float(me.stock.get(String(g.get("res", "")), 0.0))), n]
		"defeat":
			var gone := 0
			for p in players:
				if p.ai and not p.alive:
					gone += 1
			return [gone, n if n > 0 else players.size() - 1]
	return [0, 1]


func _mission_check() -> void:
	var goals: Array = mission.get("goals", [])
	if mission_done.size() != goals.size():
		mission_done.resize(goals.size())
		mission_done.fill(false)
	var all := true
	for k in goals.size():
		if not mission_done[k]:
			var gp := goal_progress(goals[k])
			if int(gp[0]) >= int(gp[1]):
				mission_done[k] = true
				emit_log("Goal reached: %s" % String(goals[k].get("text", "")), Color("86ad5c"))
		all = all and bool(mission_done[k])
	if all:
		over = true
		emit_log("Mission complete: %s" % String(mission.get("name", "")), Color("d8aa4a"))
		ended.emit(true)
	elif float(mission.get("minutes", 0)) > 0.0 and time > float(mission.minutes) * 60.0:
		over = true
		emit_log("Time is up: the mission is lost.", Color("d9483d"))
		ended.emit(false)


## A number for the whole game state, for comparing two runs minute by minute (log_checksums). Caches
## that a loaded game rebuilds differently but that change nothing (path_ver) are left out, so a game
## and the same game saved and loaded give the same numbers.
const CHECKSUM_SKIP := ["path_ver"]

func checksum() -> int:
	var d := to_save()
	for b: Dictionary in d.get("blds", []):
		for k in CHECKSUM_SKIP:
			b.erase(k)
	return hash(var_to_bytes(d))


func _secondly() -> void:
	if not mission.is_empty() and not over:
		_mission_check()
	if log_checksums and int(time) % 60 == 0:
		print("minute %d checksum %d" % [int(time) / 60, checksum()])
	_rebuild_realm_lists()
	if logistics.road_carriers_on():
		for p in players:
			logistics.road_carrier_tick(p)
	if int(time) % 5 == 0:
		logistics.transfers()
		sea.sea_transfers()
	Diplomacy.expire(self)
	military.archers_tick()
	if not standing.is_empty() and int(time) % 5 == 0:
		Diplomacy.standing_tick(self)
	for f: Feature in features:
		f.on_second()
	if not over:
		_check_alliance_end()
	for p in players:
		if not p.alive:
			continue
		var t0 := Time.get_ticks_usec()
		staffing(p)
		_pf("workers", t0)
		if creative(p):
			# creative mode: every good is kept at least half full (production still runs to the top)
			for r in GameData.resources:
				var half := floorf(capacity(p, r.id) * 0.5)
				if float(p.stock.get(r.id, 0.0)) < half:
					give(p, r.id, half - float(p.stock.get(r.id, 0.0)))
		t0 = Time.get_ticks_usec()
		var rt := (p.peasant * 0.004 + p.artisan * 0.005 + p.noble * 0.008 + (soldiers(p) + p.scout) * 0.004) * maxf(0.4, 1.0 + mod(p, "food"))
		for f: Feature in features:
			rt *= f.food_factor(p)
		p.hunger += rt
		while p.hunger >= 1.0:
			var v := take_food(p)
			if v <= 0.0:
				p.starve = mini(30, p.starve + 10)
				p.hunger -= 1.0
			else:
				p.hunger -= v
		if p.starve > 0:
			p.starve -= 1
			p.die_t += 1
			if p.die_t % 10 == 0 and p.peasant < 10 and p.artisan > 2:
				p.artisan -= 1; p.peasant += 1
				if not p.ai: emit_log("Hunger sends an artisan back to the fields.", Color("e08a6a"))
			if p.die_t >= 12 and p.peasant > 4:
				p.peasant -= 1; p.die_t = 0
				if not p.ai: emit_log("A peasant starved.", Color("e08a6a"))
		else:
			p.die_t = 0
		p.imm_t += 1
		if p.imm_t >= 8.0 / (1.0 + mod(p, "immigration")) and p.starve == 0 and pop_total(p) < housing(p) and food_total(p) >= 8.0 + pop_total(p) * 0.2:
			p.peasant += 1; p.imm_t = 0
		update_needs(p)
		_pf("people", t0)
		t0 = Time.get_ticks_usec()
		p.tax += p.noble * (0.4 + 0.8 * float(p.sat.noble)) * (1.0 + mod(p, "tax")) / 60.0
		if p.tax >= 1.0:
			give(p, "gold", floorf(p.tax)); p.tax -= floorf(p.tax)
		if mil_fill(p):
			recompute_territory()
		_pf("garrisons", t0)
		t0 = Time.get_ticks_usec()
		_research_tick(p)
		_reno_tick(p)
		_pf("research", t0)
		t0 = Time.get_ticks_usec()
		if over:
			return
		if p.ai:
			p.dip_t -= 1.0
			if p.dip_t <= 0.0:
				p.dip_t = rng.randf_range(20.0, 30.0)
				Diplomacy.ai_tick(self, p)
		_pf("diplomacy", t0)
		t0 = Time.get_ticks_usec()
		if p.ai:
			p.think_t -= 1.0
			if p.think_t <= 0.0:
				p.think_t = p.think * rng.randf_range(0.8, 1.2)
				ai_think(p)
			_pf("ai building", t0)
			t0 = Time.get_ticks_usec()
			p.attack_t -= 1.0
			if p.attack_t <= 0.0 and time > p.grace and time >= float(opts.peace_min) * 60.0:
				p.attack_t = (25.0 + (10 - p.skill) * 8.0 + rng.randf() * 20.0) * (0.5 if p.crowded else 1.0)
				ai_attack(p)
			_pf("ai attacks", t0)


# ================================================================ save / load

static func _dump(o: Object, skip: Array) -> Dictionary:
	var d := {}
	for pr in o.get_property_list():
		if (pr.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and not (pr.name in skip):
			d[pr.name] = o.get(pr.name)
	return d


static func _restore(o: Object, d: Dictionary) -> void:
	var names := {}
	for pr in o.get_property_list():
		if (pr.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names[pr.name] = true
	for k in d:
		if names.has(k):
			o.set(k, d[k])


func to_save() -> Dictionary:
	var pl := []
	for p in players:
		var pd := _dump(p, ["hq"])
		pd["hq_id"] = p.hq.id if p.hq != null else 0
		pl.append(pd)
	var bl := []
	for b in blds:
		bl.append(_dump(b, ["def"]))
	var tr := []
	for t in trips:
		tr.append(_dump(t, []))
	var at := []
	for a in attacks:
		at.append(_dump(a, []))
	return {
		"version": SAVE_VERSION, "seed": seed_str, "foes": foes, "strength": strength, "map_size": map_size, "mix": mix,
		"research_victory": research_victory, "opts": opts, "feature_state": _feature_states(),
		"features_known": Features.available().map(func(e): return e.id), "build": Version.BUILD, "reno_queue": reno_queue.duplicate(true), "w": w, "h": h, "ter": ter, "deco": deco, "amt": amt, "ore": ore, "shade": shade,
		"owner": owner, "road": road, "bmap": bmap, "time": time, "over": over, "logs": logs, "bid": _bid, "acc1": _acc1,
		"rng_seed": rng.seed, "rng_state": rng.state, "players": pl, "blds": bl, "trips": tr, "attacks": at,
		"vein": vein, "vein_amt": vein_amt, "vein_tiles": vein_tiles, "pave": pave,
		"rel": rel, "rel_since": rel_since, "proposals": proposals, "standing": standing, "prop_id": _prop_id,
		"mission": mission, "mission_done": mission_done, "ticks": _ticks,
	}


## The features the game had when save d was made (null for saves from before build 20, which didn't
## record them). Features added since then can be switched on as the game loads.
var loaded_known = null


func from_save(d: Dictionary) -> String:
	loaded_known = d.get("features_known", null)
	if int(d.get("version", 0)) > SAVE_VERSION:
		return "This save is from a newer version of the game"
	GameData.ensure()
	seed_str = d.seed; foes = d.foes; strength = d.strength; map_size = d.map_size; mix = d.mix; research_victory = d.research_victory
	opts = DEFAULT_OPTS.duplicate()
	opts.merge(d.get("opts", {}), true)
	w = d.w; h = d.h
	ter = d.ter; deco = d.deco; amt = d.amt; ore = d.ore; shade = d.shade; owner = d.owner; road = d.road; bmap = d.bmap
	_avail = {}; _avail_at = {}
	height = WorldGen.heights(String(d.get("seed", "")), ter, int(d.w), int(d.h))
	time = d.time; over = d.over; logs = d.logs; _bid = d.bid; _acc1 = d.acc1
	rng.seed = d.rng_seed; rng.state = d.rng_state
	rel = d.get("rel", {}); rel_since = d.get("rel_since", {}); proposals = d.get("proposals", []); standing = d.get("standing", []); _prop_id = int(d.get("prop_id", 0))
	mission = d.get("mission", {}); mission_done = d.get("mission_done", [])
	# the tick count decides which ticks hand out work (every 2nd, 3rd...): a loaded game must go on in
	# the same rhythm (saves from before build 34 did not keep it; the time gives it closely enough)
	_ticks = int(d.get("ticks", roundi(time / TICK)))
	if d.has("vein"):
		vein = d.vein; vein_amt = d.vein_amt; vein_tiles = d.vein_tiles
	else:
		_veins_from_old_save()
	players.clear(); blds.clear(); by_id.clear(); trips.clear(); attacks.clear()
	for bd in d.blds:
		if not GameData.bld.has(bd.ty):
			bmap[int(bd.y) * w + int(bd.x)] = 0
			continue
		var b := Bld.new()
		_restore(b, bd)
		b.def = GameData.bld[b.ty]
		# saves from before build 31: workers already at work stay there
		if not bd.has("worker") and b.staffed and b.state == "ready":
			b.worker = 2
		blds.append(b); by_id[b.id] = b
	for pd in d.players:
		var p := Player.new()
		_restore(p, pd)
		p.hq = by_id.get(int(pd.get("hq_id", 0)))
		for r in GameData.resources:
			if not p.stock.has(r.id):
				p.stock[r.id] = 0.0
		for t in p.techs.keys():
			if not GameData.techs.has(t):
				p.techs.erase(t)
		for t in p.reps.keys():
			if not GameData.reps.has(t):
				p.reps.erase(t)
		p.rqueue = p.rqueue.filter(func(x): return GameData.techs.has(x) or GameData.reps.has(x))
		if p.research != "" and not (GameData.techs.has(p.research) or GameData.reps.has(p.research)):
			p.research = ""
		_recompute_mods(p)
		players.append(p)
	for td in d.trips:
		var t := Trip.new(); _restore(t, td); trips.append(t)
	for ad in d.attacks:
		var a := Attack.new(); _restore(a, ad); attacks.append(a)
	for a in attacks:
		if a.uid == 0:
			_bid += 1
			a.uid = _bid
	_rebuild_plots()
	pave = d.get("pave", PackedByteArray())
	if pave.size() != w * h:
		pave = PackedByteArray(); pave.resize(w * h)
	_alloc_path_buffers()
	_reset_nets()
	_pending = {}
	_supply = {}
	for b in blds:
		b.path_ver = -1
		if not b.out_buf.is_empty():
			_pending[b.id] = true
		if b.state == "build" and not b.need.is_empty():
			_supply[b.id] = true
	for p in players:
		_recount_stores(p)
	for t in trips:
		if t.t2 <= 0.0:
			t.t2 = t.t1
	# saves from before build 11 had one kind of "tools": share them out among the trades' tools
	for p in players:
		var old := int(p.stock.get("tools", 0.0))
		p.stock.erase("tools")
		for n in old:
			var t: String = GameData.tool_ids[n % GameData.tool_ids.size()]
			p.stock[t] = float(p.stock.get(t, 0.0)) + 1.0
	# saves from before build 31 had one realm-wide stock: it is all in the headquarters now
	logistics._store_ver += 1
	for p in players:
		var any := false
		for s: Bld in logistics.stores_of(p):
			if not s.inv.is_empty():
				any = true
		var list: Array = logistics.stores_of(p)
		if not any and not list.is_empty():
			var home: Bld = p.hq if p.hq != null and not p.hq.dead and p.hq.state == "ready" else list[0]
			for r in p.stock:
				if float(p.stock[r]) > 0.0:
					home.inv[r] = float(p.stock[r])
	# saves from before build 8 kept work progress in b.k instead of start and end times
	for b in blds:
		if b.working and b.t_end <= 0.0:
			var total := (b.cyc + walk_time(b)) / maxf(0.05, b.rate_c)
			b.t_start = time - b.k / maxf(0.05, b.rate_c)
			b.t_end = b.t_start + total
			b.retry = b.t_end
		elif b.retry > time + 10.0 and not (b.working and b.retry <= b.t_end + 0.001):
			# (a working building waits for the end of its cycle, which may be further off: kept, so
			# a loaded game goes on exactly like the one that was saved)
			b.retry = 0.0
	_mil_dirty = true
	_tick_dirty = true
	_owned_dirty = true
	map_dirty = true
	changed_tiles = PackedInt32Array()
	territory_version += 1
	_fix_eras()
	reno_queue = {}
	for k in d.get("reno_queue", {}):
		reno_queue[int(k)] = d.reno_queue[k]
	_reno = {}
	for b in blds:
		if b.reno_to >= 0:
			_reno[b.id] = true
			if not b.need.is_empty():
				_supply[b.id] = true
	setup_features(opts.get("features", Features.default_ids()), true, d.get("feature_state", {}))
	return ""


## Saves from before build 5 kept ore per tile; turn each ore tile into its own small vein.
func _veins_from_old_save() -> void:
	vein = PackedInt32Array(); vein.resize(w * h)
	vein_amt = [0]; vein_tiles = [PackedInt32Array()]
	for i in w * h:
		if ore[i] != 0 and amt[i] > 0:
			vein[i] = vein_amt.size()
			vein_amt.append(int(amt[i]))
			vein_tiles.append(PackedInt32Array([i]))
			amt[i] = 0


# ================================================================ entry points into the parts
## Other scripts (and mods) call these on the simulation as before; the work happens in the part.

func ai_think(p: Player) -> void:
	ai.ai_think(p)

func ai_attack(p: Player) -> bool:
	return ai.ai_attack(p)

func find_path(sx: int, sy: int, gx: int, gy: int, pid: int) -> PackedInt32Array:
	return logistics.find_path(sx, sy, gx, gy, pid)

func vein_left(i: int) -> int:
	return logistics.vein_left(i)

func take_ore(i: int, kind: int, keep := false) -> bool:
	return logistics.take_ore(i, kind, keep)

func lay_road(path: PackedInt32Array, pid: int) -> void:
	logistics.lay_road(path, pid)

func _territory_nets(before: PackedByteArray) -> void:
	logistics._territory_nets(before)

func _after_building_change(b: Bld) -> void:
	logistics._after_building_change(b)

func _reset_nets() -> void:
	logistics._reset_nets()

func net_dirty(pid := 0) -> void:
	logistics.net_dirty(pid)

func _net_ready(pid: int) -> void:
	logistics._net_ready(pid)

func is_store(b: Bld) -> bool:
	return logistics.is_store(b)

func _build_net(pid: int) -> void:
	logistics._build_net(pid)

func net_dist(pid: int, i: int) -> float:
	return logistics.net_dist(pid, i)

func connected(b: Bld) -> bool:
	return logistics.connected(b)

func _path_to_net(sx: int, sy: int, pid: int, door := -1, doors: Array = [0, 1, 2, 3]) -> PackedInt32Array:
	return logistics._path_to_net(sx, sy, pid, door, doors)

func capacity(p: Player, res: String) -> float:
	return logistics.capacity(p, res)

func target_of(p: Player, res: String) -> int:
	return logistics.target_of(p, res)

func wanted_tool(p: Player) -> String:
	return logistics.wanted_tool(p)

func tool_of(b: Bld) -> String:
	return logistics.tool_of(b)

func _can_hire(p: Player, b: Bld) -> bool:
	return logistics._can_hire(p, b)

func _recount_stores(p: Player) -> void:
	logistics._recount_stores(p)

func _clamp_stock(p: Player) -> void:
	logistics._clamp_stock(p)

func porters_free(p: Player) -> int:
	return logistics.porters_free(p)

func _rebuild_realm_lists() -> void:
	logistics._rebuild_realm_lists()

func realm_blds(p: Player) -> Array:
	return logistics.realm_blds(p)

func mil_list() -> Array:
	return logistics.mil_list()

func _dispatch() -> void:
	logistics._dispatch()

func _free_carrier(t: Trip) -> void:
	logistics._free_carrier(t)

func build_road(sx: int, sy: int, gx: int, gy: int, pid: int) -> String:
	return logistics.build_road(sx, sy, gx, gy, pid)

func remove_road(x: int, y: int, pid: int) -> int:
	return logistics.remove_road(x, y, pid)

func pave_road(x: int, y: int, p: Player) -> String:
	return logistics.pave_road(x, y, p)

func work_center(b: Bld) -> Vector2i:
	return logistics.work_center(b)

func work_radius(b: Bld) -> int:
	return logistics.work_radius(b)

func walk_time(b: Bld) -> float:
	return logistics.walk_time(b)

func set_work_area(b: Bld, x: int, y: int) -> String:
	return logistics.set_work_area(b, x, y)

func status(b: Bld) -> String:
	return logistics.status(b)

func territory_loss(b: Bld) -> Dictionary:
	return military.territory_loss(b)

func recompute_territory() -> void:
	military.recompute_territory()

func owned(pid: int) -> Array:
	return military.owned(pid)

func own_def(b: Bld) -> int:
	return military.own_def(b)

func defenders(t: Bld) -> int:
	return military.defenders(t)

func launch_attack(src: Bld, tgt: Bld) -> String:
	return military.launch_attack(src, tgt)

func attack_tick(dt: float) -> void:
	military.attack_tick(dt)

func _check_alliance_end() -> void:
	military._check_alliance_end()

func mod(p: Player, key: String) -> float:
	return research.mod(p, key)

func tech_available(p: Player, id: String) -> bool:
	return research.tech_available(p, id)

func set_research(p: Player, id: String) -> void:
	research.set_research(p, id)

func research_cost(p: Player, id: String, ahead := 0) -> float:
	return research.cost(p, id, ahead)

func queue_research(p: Player, id: String) -> int:
	return research.queue_add(p, id)

func unqueue_research(p: Player, i: int) -> void:
	research.queue_remove(p, i)

func research_path(p: Player, id: String) -> Array:
	return research.path_to(p, id)

func _recompute_mods(p: Player) -> void:
	research._recompute_mods(p)

func complete_tech(p: Player, id: String) -> void:
	research.complete_tech(p, id)

func _research_tick(p: Player) -> void:
	research._research_tick(p)
