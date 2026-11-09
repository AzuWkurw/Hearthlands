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


## The crop farm b sows now: its own, or winter rye while its own is out of season (when set to rotate).
static func now(sim: Sim, b: Sim.Bld) -> String:
	var c := chosen(b)
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
