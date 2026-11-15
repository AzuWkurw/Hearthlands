class_name SimArms
extends RefCounted
## Build 66: tools and weapons are made of bronze, iron or steel, and the better the metal the faster
## and longer they work.
##
## Tools: a worker who starts at a workshop takes his trade's tool from the stores (the best metal kept
## there) and works TOOL_SPEED faster or slower by its metal; with the tool-quality feature on (wear and
## the smith's craft) a tool lasts TOOL_LIFE as long as an iron one. Workers waiting for a new tool (a
## worn-out one) count as wanting one, so the toolsmiths make it. Idle specialists keep their tool.
##
## Weapons: the barracks arm a recruit with the best weapons in store. Bronze arms make only bronze
## warriors (whatever the age), iron arms anything up to musketeers, and riflemen need steel; better
## arms train faster (ARM_TRAIN) and wear out less often in a fight (ARM_WEAR).
##
## The goods in store are counted by kind only ("axes", "weapons"), so the realm keeps how many of each
## kind are of each metal (Player.tq: res -> [_, bronze, iron, steel]) from what its smiths made. Goods
## it did not make (from the start, the market, a gift) count as the metal of its age. Every ten seconds
## the counts are trimmed (the poorest first) to the goods there are, after losses and sales.

const NONE := 0
const BRONZE := 1
const IRON := 2
const STEEL := 3
const NAMES := ["", "bronze", "iron", "steel"]
const TOOL_SPEED := [1.0, 0.9, 1.0, 1.15]
const TOOL_LIFE := [1.0, 0.6, 1.0, 1.6]             # how long a tool lasts, against an iron one
const ARM_KIND_MAX := [6, 0, 5, 6]                  # the newest kind of soldier each metal can arm
const ARM_TRAIN := [1.0, 0.9, 1.0, 1.15]            # training speed by the metal of the arms
const ARM_WEAR := [1.0, 1.5, 1.0, 0.6]              # how often a weapon wears out in a fight, by metal

var sim


func _init(s) -> void:
	sim = s


func tiered(res: String) -> bool:
	return res == "weapons" or GameData.is_tool_res(res)


## The metal of goods a realm did not make itself: that of its age.
func default_tier(p) -> int:
	return BRONZE if p.age == 0 else IRON


## The metal building type ty makes its tools and weapons of (buildings.json "tier").
func maker_tier(ty: String) -> int:
	return int(GameData.bld.get(ty, {}).get("tier", IRON))


func _pool(p, res: String) -> Array:
	if not p.tq.has(res):
		p.tq[res] = [0, 0, 0, 0]
	return p.tq[res]


## Goods made by a smith of that metal.
func add(p, res: String, tier: int, n: int) -> void:
	if n <= 0 or not tiered(res):
		return
	var a := _pool(p, res)
	a[clampi(tier, BRONZE, STEEL)] = int(a[clampi(tier, BRONZE, STEEL)]) + n


## The best metal of res in the realm's stores (without taking it); the age's metal if none is counted.
func best(p, res: String) -> int:
	var a: Array = p.tq.get(res, [])
	for t in [STEEL, IRON, BRONZE]:
		if a.size() > t and int(a[t]) > 0:
			return t
	return default_tier(p)


## One of res is used: the best counted metal goes first. Returns its metal.
func take_best(p, res: String) -> int:
	var a: Array = p.tq.get(res, [])
	for t in [STEEL, IRON, BRONZE]:
		if a.size() > t and int(a[t]) > 0:
			a[t] = int(a[t]) - 1
			return t
	return default_tier(p)


## Every ten seconds: no more counted than there are (in store, made and waiting, on the way, or
## carried to where they are used). The poorest metal goes first.
func trim(p) -> void:
	if p.tq.is_empty():
		return
	var have := {}
	for res in p.tq:
		have[res] = float(p.stock.get(res, 0.0))
	for b: Sim.Bld in sim.realm_blds(p):
		for k in b.out_buf:
			if have.has(k): have[k] = float(have[k]) + int(b.out_buf[k])
		for k in b.inbuf:
			if have.has(k): have[k] = float(have[k]) + int(b.inbuf[k])
	for t in sim.trips:
		if t.p == p.id and not t.delivered and have.has(t.res):
			have[t.res] = float(have[t.res]) + t.n
	for res in p.tq:
		var a: Array = p.tq[res]
		var extra := int(a[1]) + int(a[2]) + int(a[3]) - int(floor(float(have[res]) + 0.001))
		for t in [BRONZE, IRON, STEEL]:
			if extra <= 0:
				break
			var cut := mini(extra, int(a[t]))
			a[t] = int(a[t]) - cut
			extra -= cut


# ------------------------------------------------------------------ tools at work
## Building b's new worker takes a tool from the stores: which metal (it was taken already).
func give_tool(b: Sim.Bld, tier: int) -> void:
	b.tool_q = tier


## The tool-quality feature's record of building b's tool ([craft quality, cycles left]), or [].
func _held(b: Sim.Bld) -> Array:
	var tq = sim.get_feature("tool_quality")
	if tq == null:
		return []
	return tq.held.get(b.id, [])


## A work cycle starts at building b: the speed its tool's metal gives (none with a worn-out tool; the
## wear itself, and the tool's craft quality, are the tool-quality feature's).
func tool_cycle(b: Sim.Bld, _p, _cyc: float) -> float:
	if b.tool_q <= 0 or not bool(sim.opts.tools) or worn(b):
		return 1.0
	return TOOL_SPEED[clampi(b.tool_q, 0, STEEL)]


## How much longer a tool of this metal lasts than an iron one.
static func life_of(tier: int) -> float:
	return TOOL_LIFE[clampi(tier, 0, STEEL)] / TOOL_LIFE[IRON] if tier > 0 else 1.0


## Whether building b's tool is worn out (and waiting for a new one).
func worn(b: Sim.Bld) -> bool:
	var h := _held(b)
	return not h.is_empty() and float(h[0]) < 0.0 and bool(sim.opts.tools)


## A specialist leaving building b keeps his tool: its metal.
func pack(b: Sim.Bld) -> float:
	return float(b.tool_q)


func unpack(b: Sim.Bld, v: float) -> void:
	b.tool_q = int(floor(v))


## The tools or weapons of each metal a realm holds, for the stores' panel: "3 bronze, 5 iron".
func split_text(p, res: String) -> String:
	var a: Array = p.tq.get(res, [])
	var n := int(floor(float(p.stock.get(res, 0.0)) + 0.001))
	var parts := []
	var counted := 0
	for t in [STEEL, IRON, BRONZE]:
		if a.size() > t and int(a[t]) > 0:
			parts.append("%d %s" % [mini(int(a[t]), n - counted), NAMES[t]])
			counted += mini(int(a[t]), n - counted)
	if counted < n:
		parts.append("%d %s" % [n - counted, NAMES[default_tier(p)]])
	return ", ".join(parts)
