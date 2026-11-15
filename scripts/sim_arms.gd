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
## How the metals look in the panels (build 67): a colour for the name and an ingot badge; the tools and
## weapons have a picture for each metal (textures/res_<good>_bronze.png and _steel.png; iron is the
## usual picture).
const COLORS := ["c8c8c0", "d9a25a", "b9bec8", "8cc8f2"]
const PICTURED := ["axes", "pickaxes", "farm_tools", "knives", "saws", "tongs", "trowels", "shears", "chisels", "weapons"]

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


## Build 68: the player says which metal is used first (Player.metal_order: "tools" / "weapons" -> the
## metals in order, best first by default), how many of each metal to keep at most in store (metal_lim:
## a smith stops making a good of his metal once that many are in store) and how much of each metal the
## tool smiths or weapon smiths leave in store for the other (metal_keep).
const ORDERS := [[3, 2, 1], [1, 2, 3], [2, 3, 1], [2, 1, 3], [3, 1, 2], [1, 3, 2]]
const METAL_RES := ["", "bronze", "iron", "steel"]


static func group(res: String) -> String:
	return "weapons" if res == "weapons" else "tools"


func order_of(p, res: String) -> Array:
	var o: Array = p.metal_order.get(group(res), [])
	return o if o.size() == 3 else [STEEL, IRON, BRONZE]


## How many of res of each metal are in store: [_, bronze, iron, steel] (goods not counted by metal are
## the age's metal).
func by_metal(p, res: String) -> Array:
	var a: Array = p.tq.get(res, [])
	var n := int(floor(float(p.stock.get(res, 0.0)) + 0.001))
	var by := [0, 0, 0, 0]
	var counted := 0
	for t in [STEEL, IRON, BRONZE]:
		if a.size() > t and int(a[t]) > 0:
			var k := mini(int(a[t]), n - counted)
			by[t] += k
			counted += k
	if counted < n:
		by[default_tier(p)] += n - counted
	return by


## The metal of res that is used first (the player's order; the age's metal if none is in store).
func best(p, res: String) -> int:
	var by := by_metal(p, res)
	for t in order_of(p, res):
		if int(by[t]) > 0:
			return t
	return default_tier(p)


## One of res is used: the first metal in the player's order that is in store. Returns its metal.
func take_best(p, res: String) -> int:
	var by := by_metal(p, res)
	var a: Array = p.tq.get(res, [])
	for t in order_of(p, res):
		if int(by[t]) > 0:
			if a.size() > t and int(a[t]) > 0:
				a[t] = int(a[t]) - 1
			return t
	# none in store (taken on the way): the best counted, else the age's metal
	for t in [STEEL, IRON, BRONZE]:
		if a.size() > t and int(a[t]) > 0:
			a[t] = int(a[t]) - 1
			return t
	return default_tier(p)


## The most of res of that metal to keep in store, or -1 for no limit.
func limit_of(p, res: String, tier: int) -> int:
	var l: Array = p.metal_lim.get(group(res), [])
	return int(l[tier]) if l.size() > tier else -1


## Whether a smith of that metal may make one more res (its metal's limit not reached).
func under_limit(p, res: String, tier: int) -> bool:
	var lim := limit_of(p, res, tier)
	return lim < 0 or int(by_metal(p, res)[tier]) < lim


## How much of a metal (bronze, iron, steel) the smiths of a group leave in store.
func keep_of(p, grp: String, metal: String) -> int:
	return int((p.metal_keep.get(grp, {}) as Dictionary).get(metal, 0))


## Why smith b may not start (build 68), or "": his metal's limit reached, or the metal kept for the others.
func smith_check(b, p) -> String:
	var d: Dictionary = b.def
	var grp := ""
	if d.has("makes_tools"):
		grp = "tools"
	elif (d.get("out", {}) as Dictionary).has("weapons"):
		grp = "weapons"
	else:
		return ""
	var tier := maker_tier(b.ty)
	if grp == "weapons" and not under_limit(p, "weapons", tier):
		return "Limit reached: %d %s weapons in store (see production targets)" % [int(by_metal(p, "weapons")[tier]), NAMES[tier]]
	for m in (d.get("in", {}) as Dictionary):
		var keep := keep_of(p, grp, String(m))
		if keep > 0 and float(p.stock.get(m, 0.0)) < keep:
			return "Leaving %s in store for the %s (keep %d, see production targets)" % [GameData.res_name(String(m)).to_lower(), "weapons" if grp == "tools" else "tools", keep]
	return ""


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


# ------------------------------------------------------------------ how they look
## The picture of res made of that metal (the usual one for iron or goods with no metal pictures).
static func icon_id(res: String, tier: int) -> String:
	if (tier == BRONZE or tier == STEEL) and res in PICTURED:
		return "res_%s_%s" % [res, NAMES[tier]]
	return "res_" + res


## The metal's name in its colour, for the panels (with its ingot badge when pic).
static func tag(tier: int, pic := false) -> String:
	if tier <= 0 or tier > STEEL:
		return ""
	var badge := "[img=14x14]res://textures/metal_%s.png[/img] " % NAMES[tier] if pic else ""
	return "%s[color=#%s]%s[/color]" % [badge, COLORS[tier], NAMES[tier]]


## split_text, with each metal in its colour.
func split_bb(p, res: String) -> String:
	var t := split_text(p, res)
	for k in [STEEL, IRON, BRONZE]:
		t = t.replace(" " + NAMES[k], " " + tag(k))
	return t


# ------------------------------------------------------------------ soldiers' arms
## How many of the realm's soldiers carry arms of each metal (Player.arm_n: [_, bronze, iron, steel]),
## for the panels: counted as they are armed and re-armed, and kept to the soldiers there are (losses
## fall on each metal in proportion). Soldiers from before (a start, an older save) carry the age's metal.
func armed(p, tier: int) -> void:
	p.arm_n[clampi(tier, BRONZE, STEEL)] = int(p.arm_n[clampi(tier, BRONZE, STEEL)]) + 1


## A soldier with a worn weapon takes a new one of that metal: his old one was of the poorest kind.
func rearmed(p, tier: int) -> void:
	for t in [BRONZE, IRON, STEEL]:
		if int(p.arm_n[t]) > 0:
			p.arm_n[t] = int(p.arm_n[t]) - 1
			break
	armed(p, tier)


func fit_arms(p) -> void:
	var n: int = sim.soldiers(p)
	var have := int(p.arm_n[1]) + int(p.arm_n[2]) + int(p.arm_n[3])
	if have < n:
		var t := default_tier(p) if p.arm_q <= 0 else int(p.arm_q)
		p.arm_n[t] = int(p.arm_n[t]) + n - have
	elif have > n:
		var keep := []
		var kept := 0
		for t in 4:
			var k := int(floor(float(p.arm_n[t]) * n / have)) if t > 0 else 0
			keep.append(k)
			kept += k
		for t in [STEEL, IRON, BRONZE]:
			if kept < n and int(p.arm_n[t]) > int(keep[t]):
				keep[t] = int(keep[t]) + 1
				kept += 1
		p.arm_n = keep


## "30 iron, 8 bronze" (best first), the metals coloured when bb.
func arms_text(p, bb := false) -> String:
	var parts := []
	for t in [STEEL, IRON, BRONZE]:
		if int(p.arm_n[t]) > 0:
			parts.append("%d %s" % [int(p.arm_n[t]), tag(t) if bb else NAMES[t]])
	return ", ".join(parts)


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
	var by := by_metal(p, res)
	var parts := []
	for t in [STEEL, IRON, BRONZE]:
		if by[t] > 0:
			parts.append("%d %s" % [by[t], NAMES[t]])
	return ", ".join(parts)
