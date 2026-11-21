class_name Crops
extends RefCounted
## What a farm grows. A farm sows one crop at a time, chosen on its panel. Wheat is known from the start;
## other seeds are unlocked by research. Each crop has its seasons: how much faster or slower it grows in
## spring, summer, autumn and winter, and OFF where it does not grow at all (the farm stands idle then).
## With the Three-field system studied, a farm can be set to sow winter rye when its own crop is out of
## season. Without the seasons feature every crop grows all year.

const OFF := -1.0
## id -> name, what a harvest gives, growth by season (spring, summer, autumn, winter), the tech that
## unlocks its seed ("" = from the start), and a feature it needs ("" = none).
const LIST := {
	"wheat": {"name": "Wheat", "out": {"grain": 3}, "season": [0.10, 0.25, 0.10, OFF], "tech": "", "need": "",
		"info": "Grain for mills and bakeries. Sown in spring, harvested by autumn; nothing in winter."},
	"rye": {"name": "Winter rye", "out": {"grain": 2}, "season": [0.0, -0.10, 0.05, -0.10], "tech": "heavy_plough", "need": "",
		"info": "Hardy grain that grows through the winter, but gives less than wheat."},
	"vegetables": {"name": "Vegetables", "out": {"vegetables": 3}, "season": [0.20, 0.30, -0.15, OFF], "tech": "open_fields", "need": "",
		"info": "Turnips, beans and cabbages: food straight from the field, no mill or bakery needed. Best in spring and summer."},
	"potatoes": {"name": "Potatoes", "out": {"vegetables": 4}, "season": [0.10, 0.20, 0.10, OFF], "tech": "new_crops", "need": "",
		"info": "New World tubers: plenty of food from one field. Planted in spring, dug up by autumn."},
	"flax": {"name": "Flax", "out": {"flax": 2}, "season": [0.10, 0.25, 0.0, OFF], "tech": "wool_trade", "need": "clothing",
		"info": "Flax for linen clothes."},
	"hops": {"name": "Hops", "out": {"hops": 2}, "season": [OFF, 0.25, 0.20, OFF], "tech": "monasteries", "need": "",
		"info": "Hops for the brewery. They climb in summer and are picked in autumn."},
}
const ORDER := ["wheat", "rye", "vegetables", "potatoes", "flax", "hops"]
## Other crop buildings that stand idle in winter.
const WINTER_IDLE := ["orchard", "hop_farm", "vineyard", "flax_farm", "apiary"]
const ROTATE_TECH := "three_field"

# ---------------------------------------------------------------- fields
## A farm works fields around it, in its work area. A work cycle either sows a free tile (no harvest
## yet) or harvests a ripe field and sows it again. A field ripens after GROW seconds of growth; the
## season speeds or slows that (a crop out of season does not grow at all, so a field sown in late
## autumn waits for spring). A building or road put on a field, or the land lost, ends the field.
const GROW := 60.0
const MAX_FIELDS := 6


static func is_farm(b: Sim.Bld) -> bool:
	return b.ty == "farm"


## The crop farm b has chosen.
static func chosen(b: Sim.Bld) -> String:
	return b.crop if LIST.has(b.crop) else "wheat"


## The season now (0 spring .. 3 winter), or -1 without the seasons feature.
static func season_now(sim: Sim) -> int:
	var f = sim.get_feature("seasons")
	return int(f.season()) if f != null else -1


static func grows(id: String, season: int) -> bool:
	return season < 0 or float(LIST[id].season[season]) > OFF


## The crop farm b sows now: the one set for this season, else its own, or winter rye while its own
## is out of season (when set to rotate).
static func now(sim: Sim, b: Sim.Bld) -> String:
	var c := chosen(b)
	if b.season_crop.size() == 4:
		var s0 := season_now(sim)
		if s0 >= 0 and LIST.has(String(b.season_crop[s0])) and known(sim, sim.players[b.p - 1], String(b.season_crop[s0])):
			return String(b.season_crop[s0])
	if b.rotate and c != "rye":
		var s := season_now(sim)
		var p := sim.players[b.p - 1]
		if not grows(c, s) and known(sim, p, "rye") and p.techs.has(ROTATE_TECH):
			return "rye"
	return c


## Whether realm p has the seed of crop id (and the game has what the crop needs).
static func known(sim: Sim, p: Sim.Player, id: String) -> bool:
	var d: Dictionary = LIST[id]
	if String(d.need) != "" and sim.get_feature(String(d.need)) == null:
		return false
	return String(d.tech) == "" or p.techs.has(String(d.tech)) or not sim.tech_enabled(String(d.tech))


## What a cycle of building b makes.
static func out_of(sim: Sim, b: Sim.Bld) -> Dictionary:
	if is_farm(b):
		return LIST[now(sim, b)].out
	return b.def.get("out", {})


## Why building b cannot work this season ("" when it can).
static func block(sim: Sim, b: Sim.Bld) -> String:
	var s := season_now(sim)
	if s < 0:
		return ""
	if is_farm(b):
		var c := now(sim, b)
		if not grows(c, s):
			var when := []
			for k in 4:
				if grows(c, k):
					when.append(["spring", "summer", "autumn", "winter"][k])
			var w := ", ".join(when.slice(0, when.size() - 1)) + " and " + String(when[-1]) if when.size() > 1 else String(when[0])
			return "Out of season: %s grow%s only in %s" % [String(LIST[c].name).to_lower(), "" if String(LIST[c].name).ends_with("s") else "s", w]
	elif s == 3 and b.ty in WINTER_IDLE:
		return "Out of season: nothing grows here in winter"
	return ""


## Growth a second of crop id now (1 = normal).
static func rate(sim: Sim, id: String) -> float:
	var s := season_now(sim)
	if s < 0:
		return 1.0
	var v := float(LIST[id].season[s])
	return 0.0 if v <= OFF else maxf(0.2, 1.0 + v)


## Once a second: fields grow; fields under a building or road, of a gone farm or on lost land end.
static func grow(sim: Sim) -> void:
	if sim.fields.is_empty():
		return
	var rates := {}
	for i in sim.fields.keys():
		var f: Array = sim.fields[i]
		var b: Sim.Bld = sim.by_id.get(int(f[0]))
		if b == null or b.dead or sim.bmap[i] != 0 or sim.plot[i] != 0 or sim.road[i] != 0 or sim.deco[i] != 0 or sim.owner[i] != b.p:
			sim.fields.erase(i)
			_ff_del(sim, i, int(f[0]))
			continue
		var c := String(f[1])
		if not rates.has(c):
			rates[c] = rate(sim, c)
		f[2] = minf(GROW, float(f[2]) + float(rates[c]))


## Whether tile i can take a new field of a farm of realm pid.
static func free_for_field(sim: Sim, i: int, pid: int) -> bool:
	return sim.ter[i] == Sim.GRASS and sim.deco[i] == 0 and sim.bmap[i] == 0 and sim.plot[i] == 0 and sim.road[i] == 0 \
		and sim.owner[i] == pid and not sim.fields.has(i)


## Fields of farm b: [all, ripe].
## The fields of each farm (farm id -> tiles), worked out again whenever a field is sown or ends, so a
## farm does not look through every field on the map each time it starts work.
static func of_farm(sim: Sim, id: int) -> Array:
	if sim._ff_dirty:
		sim._ff_dirty = false
		sim._farm_fields = {}
		for i in sim.fields:
			var fid := int(sim.fields[i][0])
			if not sim._farm_fields.has(fid):
				sim._farm_fields[fid] = []
			(sim._farm_fields[fid] as Array).append(i)
	return sim._farm_fields.get(id, [])


## (Build 74) A field sown or ended: its farm's list is changed, not made again from every field on the
## map (on a big map, fields come and go every moment).
static func _ff_add(sim: Sim, i: int, fid: int) -> void:
	if sim._ff_dirty:
		return
	if not sim._farm_fields.has(fid):
		sim._farm_fields[fid] = []
	(sim._farm_fields[fid] as Array).append(i)


static func _ff_del(sim: Sim, i: int, fid: int) -> void:
	if sim._ff_dirty:
		return
	var l = sim._farm_fields.get(fid)
	if l != null:
		(l as Array).erase(i)


static func count(sim: Sim, b: Sim.Bld) -> Vector2i:
	var n := 0
	var r := 0
	for i in of_farm(sim, b.id):
		var f: Array = sim.fields[i]
		n += 1
		if float(f[2]) >= GROW: r += 1
	return Vector2i(n, r)


## The nearest ripe field of farm b, or -1.
static func ripe_field(sim: Sim, b: Sim.Bld) -> int:
	var best := -1
	var bd := 1 << 30
	for i in of_farm(sim, b.id):
		var f: Array = sim.fields[i]
		if float(f[2]) >= GROW:
			var dd := absi(i % sim.w - b.x) + absi(i / sim.w - b.y)
			if dd < bd or (dd == bd and i < best):
				bd = dd; best = i
	return best


## The nearest free tile in farm b's work area for a new field, or -1. Tiles next to its fields come
## first, so they lie together.
static func free_tile(sim: Sim, b: Sim.Bld, wc: Vector2i, r: int) -> int:
	var best := -1
	var bs := 1e9
	for y in range(maxi(0, wc.y - r), mini(sim.h - 1, wc.y + r) + 1):
		for x in range(maxi(0, wc.x - r), mini(sim.w - 1, wc.x + r) + 1):
			var dx := x - wc.x
			var dy := y - wc.y
			if dx * dx + dy * dy > r * r + 1:
				continue
			var i := y * sim.w + x
			if not free_for_field(sim, i, b.p):
				continue
			var sc := float(absi(x - b.x) + absi(y - b.y))
			for o in [1, -1, sim.w, -sim.w]:
				var j: int = i + o
				if j >= 0 and j < sim.w * sim.h and sim.fields.has(j):
					sc -= 0.6
			if sc < bs:
				bs = sc; best = i
	return best


## The start of a farm's work cycle: the ripe field to harvest, or a free tile to sow. Returns why it
## cannot work ("" when it can); sets b.target and b.sowing.
static func farm_start(sim: Sim, b: Sim.Bld) -> String:
	var rf := ripe_field(sim, b)
	if rf >= 0:
		b.target = rf
		b.sowing = false
		return ""
	var why := block(sim, b)
	if why != "":
		return why
	var c := count(sim, b)
	if c.x >= MAX_FIELDS:
		return "Waiting for the fields to ripen"
	var t := free_tile(sim, b, sim.work_center(b), sim.work_radius(b))
	if t < 0:
		return "Waiting for the fields to ripen" if c.x > 0 else "No room for fields in the work area"
	b.target = t
	b.sowing = true
	return ""


## The end of a farm's work cycle: sows the tile, or harvests the field (and sows it again while the
## crop is in season). Returns what the harvest gives ({} when it sowed).
static func farm_finish(sim: Sim, b: Sim.Bld) -> Dictionary:
	var tg := b.target
	if tg < 0:
		return {}
	if b.sowing:
		if free_for_field(sim, tg, b.p):
			sim.fields[tg] = [b.id, now(sim, b), 0.0]
			_ff_add(sim, tg, b.id)
		return {}
	var f = sim.fields.get(tg)
	if f == null or int(f[0]) != b.id or float(f[2]) < GROW:
		return {}
	var got: Dictionary = LIST[String(f[1])].out
	var c := now(sim, b)
	if grows(c, season_now(sim)):
		sim.fields[tg] = [b.id, c, 0.0]
	else:
		sim.fields.erase(tg)
		_ff_del(sim, tg, b.id)
	return got


## What farm b's info box says about its fields.
static func fields_line(sim: Sim, b: Sim.Bld) -> String:
	var c := count(sim, b)
	var growing := 0.0
	for i in sim.fields:
		var f: Array = sim.fields[i]
		if int(f[0]) == b.id and float(f[2]) < GROW:
			growing = maxf(growing, float(f[2]))
	var t := "Fields: %d of %d sown, %d ripe" % [c.x, MAX_FIELDS, c.y]
	if c.x > c.y and c.y == 0:
		var r := rate(sim, now(sim, b))
		t += (", the next ripe in about %d s" % ceili((GROW - growing) / r)) if r > 0.0 else ", not growing now (out of season)"
	return t


## Copies farm b's crop plan (main crop, crop by season, winter rye) to every farm of its realm.
## Returns how many farms changed.
static func apply_to_all(sim: Sim, b: Sim.Bld) -> int:
	var n := 0
	for f: Sim.Bld in sim.realm_blds(sim.players[b.p - 1]):
		if f != b and is_farm(f) and not f.dead:
			f.crop = b.crop
			f.season_crop = b.season_crop.duplicate()
			f.rotate = b.rotate
			n += 1
	return n


## Seeds tech id unlocks (names).
static func seeds_of(tech: String) -> Array:
	var out := []
	for k in ORDER:
		if String(LIST[k].tech) == tech:
			out.append(String(LIST[k].name))
	if tech == ROTATE_TECH:
		out.append("winter rye rotation")
	return out


static func season_text(id: String) -> String:
	var parts := []
	for k in 4:
		var v := float(LIST[id].season[k])
		parts.append("%s %s" % [["Sp", "Su", "Au", "Wi"][k], "—" if v <= OFF else "%+d%%" % roundi(v * 100.0)])
	return "  ".join(parts)
