extends Feature
## Summer and winter clothes. Needs "Seasons, biomes and weather" for the temperature.
## Every realm keeps a wardrobe: how many of its people own a fur coat and how many own linen clothes.
## Whenever coats or linen are in store and not everyone has them, people take them (one piece
## dresses 3 people). Clothes wear out only while worn: coats in the cold, linen in the heat.
## Below 8 C people without a coat work slower and eat more, the more so the colder it is;
## above 24 C people without linen clothes work slower. Diseases (if switched on) read cold_need().

const PER_PIECE := 3.0          # people dressed by one piece
const WEAR := 1.0 / 600.0       # share of worn clothes that wear out per second of use (10 minutes)
const COLD_AT := 8.0
const HOT_AT := 24.0

var warm: Dictionary = {}       # realm id -> people with a fur coat
var light: Dictionary = {}      # realm id -> people with linen clothes
var _speed: Dictionary = {}     # realm id -> work speed change this second
var _food: Dictionary = {}      # realm id -> food factor this second


func _init() -> void:
	id = "clothing"
	title = "Summer and winter clothes"
	info = "People need fur coats in the cold and linen clothes in the heat, or they work slower and eat more. Adds the flax farm, linen weaver and furrier."
	default_on = true
	needs = ["seasons"]


func on_start(loaded: bool) -> void:
	# a save, or a game that has been running a while when clothes were switched on: everyone is dressed
	if loaded or sim.time > 60.0:
		# a save from before clothes mattered: everyone already owns what they need
		if warm.is_empty():
			for p: Sim.Player in sim.players:
				warm[p.id] = _people(p)
				light[p.id] = _people(p)
		return
	# every realm starts with a little of each, enough for its first families
	for p: Sim.Player in sim.players:
		sim.give(p, "fur_coats", 4.0)
		sim.give(p, "linen_clothes", 4.0)
		warm[p.id] = 12.0
		light[p.id] = 12.0


## The seasons feature (untyped, so its own functions can be called), or null.
func _climate():
	return sim.get_feature("seasons")


func _people(p: Sim.Player) -> float:
	return float(sim.pop_total(p) + sim.soldiers(p))


## 0 (no cold) to 1 (bitter cold) at realm p.
func cold(p: Sim.Player) -> float:
	var c = _climate()
	if c == null:
		return 0.0
	return clampf((COLD_AT - float(c.realm_temp(p))) / 16.0, 0.0, 1.0)


func heat(p: Sim.Player) -> float:
	var c = _climate()
	if c == null:
		return 0.0
	return clampf((float(c.realm_temp(p)) - HOT_AT) / 10.0, 0.0, 1.0)


## Share of realm p's people with a coat / with linen, 0 to 1.
func warm_share(p: Sim.Player) -> float:
	return clampf(float(warm.get(p.id, 0.0)) / maxf(1.0, _people(p)), 0.0, 1.0)


func light_share(p: Sim.Player) -> float:
	return clampf(float(light.get(p.id, 0.0)) / maxf(1.0, _people(p)), 0.0, 1.0)


## How badly realm p suffers from the cold for want of coats (0 to 1). Diseases use this too.
func cold_need(p: Sim.Player) -> float:
	return cold(p) * (1.0 - warm_share(p))


func heat_need(p: Sim.Player) -> float:
	return heat(p) * (1.0 - light_share(p))


func on_second() -> void:
	for p: Sim.Player in sim.players:
		if not p.alive:
			continue
		var people := _people(p)
		var wv := float(warm.get(p.id, 0.0))
		var lv := float(light.get(p.id, 0.0))
		# clothes wear out while worn
		if cold(p) > 0.0:
			wv -= wv * WEAR
		if heat(p) > 0.0 or (_climate() != null and _climate().season() == 1):
			lv -= lv * WEAR
		# people who lack them take new ones from the stores, a piece a second
		if wv + 0.5 < people and float(p.stock.get("fur_coats", 0.0)) >= 1.0:
			sim.take(p, "fur_coats", 1.0)
			sim.used(p, "fur_coats", 1.0)
			wv += PER_PIECE
		if lv + 0.5 < people and float(p.stock.get("linen_clothes", 0.0)) >= 1.0:
			sim.take(p, "linen_clothes", 1.0)
			sim.used(p, "linen_clothes", 1.0)
			lv += PER_PIECE
		# the dead and departed leave their clothes behind for the others; nobody has two
		warm[p.id] = minf(wv, people)
		light[p.id] = minf(lv, people)
		var cn := cold_need(p)
		_speed[p.id] = -0.30 * cn - 0.20 * heat_need(p)
		_food[p.id] = 1.0 + 0.25 * cn


func speed_bonus(p: Sim.Player, _b: Sim.Bld) -> float:
	return float(_speed.get(p.id, 0.0))


func food_factor(p: Sim.Player) -> float:
	return float(_food.get(p.id, 1.0))


func ai_steps(p: Sim.Player, have: Callable) -> Array:
	var mins := sim.time / 60.0
	var pop := sim.pop_total(p)
	return [
		["hunter", 2 if mins > 3 else 1],
		["furrier", 1 if mins > 3 else 0],
		["flax_farm", 1 if mins > 5 else 0],
		["linen_weaver", 1 if int(have.call("flax_farm")) > 0 else 0],
		["furrier", 2 if pop > 80 else 1],
		["hunter", 3 if pop > 80 else 2],
		["flax_farm", 2 if pop > 120 else 1],
	]


func panel_lines(p: Sim.Player) -> PackedStringArray:
	var people := _people(p)
	var out := PackedStringArray()
	var line := "Clothes  coats for [b]%d%%[/b], linen for [b]%d%%[/b]" % [roundi(warm_share(p) * 100.0), roundi(light_share(p) * 100.0)]
	var cn := cold_need(p)
	var hn := heat_need(p)
	if cn > 0.02:
		line += "  [color=#9fd0e8]cold: work -%d%%, food +%d%%[/color]" % [roundi(cn * 30.0), roundi(cn * 25.0)]
	elif hn > 0.02:
		line += "  [color=#f0b070]heat: work -%d%%[/color]" % roundi(hn * 20.0)
	out.append(line)
	if people > 0.0 and cold(p) > 0.0 and warm_share(p) < 0.6 and float(p.stock.get("fur_coats", 0.0)) < 1.0:
		out.append("[color=#f0a090]Not enough fur coats: build a furrier (hides from hunters).[/color]")
	return out


func save_state() -> Dictionary:
	return {"warm": warm, "light": light}


func load_state(d: Dictionary) -> void:
	warm = {}
	light = {}
	for k in d.get("warm", {}):
		warm[int(k)] = float(d.warm[k])
	for k in d.get("light", {}):
		light[int(k)] = float(d.light[k])
