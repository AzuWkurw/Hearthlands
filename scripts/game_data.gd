class_name GameData
extends RefCounted
## Loads the game's content from data/*.json.
## Files with the same name in user://data/ are merged on top, so players can add or
## change resources, buildings and population needs without editing the project.

const CATEGORIES := [["raw", "Raw"], ["food", "Food"], ["industry", "Industry"], ["crafts", "Crafts"], ["folk", "Folk"], ["science", "Science"], ["logistics", "Roads & stores"], ["mil", "Military"]]
const ORE_NAMES := {1: "coal", 2: "iron", 3: "gold", 4: "granite", 5: "copper"}
const CLASSES := ["peasant", "artisan", "noble", "soldier"]

static var loaded := false
static var resources: Array = []          # ordered list of resource dictionaries
static var res_by_id: Dictionary = {}
static var bld: Dictionary = {}           # building id -> definition
static var needs: Dictionary = {}         # class -> {resource: rate per person per second}
static var food_ids: Array = []           # food resources, cheapest first
static var techs: Dictionary = {}         # tech id -> definition, in tree order
static var reps: Dictionary = {}          # repeatable study id -> definition (age, cost, max levels, effects)
static var lanes: Array = []              # branches of the tech tree, top to bottom: [id, name]
static var ages: Array = []
static var values: Dictionary = {}       # rough worth of one unit of each resource, for trading
static var trades: Dictionary = {}       # trade id -> {"name": ..., "title": ...}; workers specialise in one
static var tool_ids: Array = []          # every tool resource, in data order
static var _tool_of_trade: Dictionary = {}  # trade id -> the tool its new workers need
static var errors: Array = []


static func ensure() -> void:
	if loaded:
		return
	reload()


static func reload() -> void:
	errors.clear()
	resources = []
	res_by_id = {}
	bld = {}
	needs = {}
	var base_res = _read("res://data/resources.json")
	if base_res is Array:
		for r in base_res:
			_add_res(r)
	var mod_res = _read("user://data/resources.json")
	if mod_res is Array:
		for r in mod_res:
			_add_res(r)
	var base_b = _read("res://data/buildings.json")
	if base_b is Dictionary:
		for k in base_b:
			bld[k] = base_b[k]
	var mod_b = _read("user://data/buildings.json")
	if mod_b is Dictionary:
		for k in mod_b:
			if bld.has(k) and mod_b[k] is Dictionary:
				var merged: Dictionary = (bld[k] as Dictionary).duplicate(true)
				merged.merge(mod_b[k], true)
				bld[k] = merged
			else:
				bld[k] = mod_b[k]
	for k in bld.keys():
		if bld[k] == null:
			bld.erase(k)  # a mod can remove a building with "id": null
	var base_n = _read("res://data/needs.json")
	if base_n is Dictionary:
		needs = base_n
	var mod_n = _read("user://data/needs.json")
	if mod_n is Dictionary:
		for k in mod_n:
			needs[k] = mod_n[k]
	techs = {}
	reps = {}
	lanes = []
	ages = ["Roman", "Early Medieval", "High Medieval", "Renaissance", "Enlightenment", "Industrial"]
	var base_t = _read("res://data/techs.json")
	var mod_t = _read("user://data/techs.json")
	for src in [base_t, mod_t]:
		if src is Dictionary:
			if src.has("ages"):
				ages = src.ages
			if src.has("lanes"):
				lanes = src.lanes
			for r in src.get("repeatables", []):
				if r is Dictionary and r.has("id"):
					if reps.has(r.id):
						var rm: Dictionary = (reps[r.id] as Dictionary).duplicate(true)
						rm.merge(r, true)
						reps[r.id] = rm
					else:
						reps[r.id] = r
			for t in src.get("techs", []):
				if t is Dictionary and t.has("id"):
					if techs.has(t.id):
						var m: Dictionary = (techs[t.id] as Dictionary).duplicate(true)
						m.merge(t, true)
						techs[t.id] = m
					else:
						techs[t.id] = t
	food_ids = []
	for r in resources:
		if r.has("food"):
			food_ids.append(r.id)
	food_ids.sort_custom(func(a, b): return float(res_by_id[a].food) < float(res_by_id[b].food))
	tool_ids = []
	_tool_of_trade = {}
	for r in resources:
		if r.has("tool"):
			tool_ids.append(String(r.id))
			_tool_of_trade[String(r.tool)] = String(r.id)
	trades = {}
	for src2 in [_read("res://data/trades.json"), _read("user://data/trades.json")]:
		if src2 is Dictionary:
			for k in src2:
				trades[k] = src2[k]
	_compute_values()
	_validate()
	loaded = true


## Works out what one unit of each resource is worth: raw goods cost the time to gather them,
## made goods cost their inputs plus the work. Repeated passes let values flow down production chains.
static func _compute_values() -> void:
	values = {}
	for pass_i in 8:
		for id in bld:
			var d: Dictionary = bld[id]
			var outs: Dictionary = (d.get("out", {}) as Dictionary).duplicate()
			# a toolsmith's tools are valued as if it made each kind
			if d.has("makes_tools"):
				for t in tool_ids:
					outs[t] = float(d.makes_tools) / maxf(1.0, tool_ids.size())
			if outs.is_empty() or not d.has("cycle"):
				continue
			var cost := float(d.cycle) / 15.0 + (0.5 if String(d.get("worker", "")) == "artisan" else 0.0)
			var known := true
			var inp: Dictionary = d.get("in", {})
			for k in inp:
				if k == "food":
					cost += 1.0 * float(inp[k])
				elif values.has(k):
					cost += float(values[k]) * float(inp[k])
				else:
					known = false
			if not known:
				continue
			var count := 0.0
			for k in outs:
				if k != "research":
					count += float(outs[k])
			if count <= 0.0:
				continue
			var each := maxf(0.5, cost / count)
			for k in outs:
				if k != "research" and (not values.has(k) or each < float(values[k])):
					values[k] = each


static func res_value(id: String) -> float:
	return float(values.get(id, 2.0))


static func _add_res(r) -> void:
	if not (r is Dictionary) or not r.has("id"):
		return
	if res_by_id.has(r.id):
		var i := 0
		for k in range(resources.size()):
			if resources[k].id == r.id:
				i = k
		resources[i] = r
	else:
		resources.append(r)
	res_by_id[r.id] = r


static func _validate() -> void:
	for id in bld:
		var d: Dictionary = bld[id]
		for sec in ["cost", "in", "out"]:
			var m: Dictionary = d.get(sec, {})
			for k in m:
				if k != "food" and k != "research" and k != "ship" and not res_by_id.has(k):
					errors.append("Building '%s' uses unknown resource '%s' in %s" % [id, k, sec])
		if d.has("tech") and not techs.has(d.tech):
			errors.append("Building '%s' needs unknown tech '%s'" % [id, d.tech])
		if d.has("trade") and not trades.has(d.trade):
			errors.append("Building '%s' has unknown trade '%s'" % [id, d.trade])
	for t in techs.values():
		for r in t.get("requires", []):
			if not techs.has(r):
				errors.append("Tech '%s' requires unknown tech '%s'" % [t.id, r])
	for e in errors:
		push_warning(e)


static func _read(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		errors.append("%s line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		push_warning(errors[-1])
		return null
	return j.data


static func res_name(id: String) -> String:
	if id == "food":
		return "Food"
	if id == "research":
		return "Research points"
	return String(res_by_id[id].name) if res_by_id.has(id) else id


static func res_color(id: String) -> Color:
	return Color(String(res_by_id[id].color)) if res_by_id.has(id) else Color.MAGENTA


static func res_abbr(id: String) -> String:
	return String(res_by_id[id].get("abbr", id.substr(0, 2))) if res_by_id.has(id) else id


## Production stops while the store holds this many (set "cap" on a resource to change it).
static func res_cap(id: String) -> float:
	return float(res_by_id[id].get("cap", 80)) if res_by_id.has(id) else 80.0


static func food_value(id: String) -> float:
	return float(res_by_id[id].get("food", 0.0)) if res_by_id.has(id) else 0.0


static func tech_name(id: String) -> String:
	if reps.has(id):
		return String(reps[id].name)
	return String(techs[id].name) if techs.has(id) else id


## The cost of a repeatable study's next level, for a realm that has done `level` levels already:
## each level costs half the first again.
static func rep_cost(id: String, level: int) -> float:
	return roundf(float(reps[id].cost) * (1.0 + 0.5 * level) / 10.0) * 10.0


static func age_name(i: int) -> String:
	return String(ages[clampi(i, 0, ages.size() - 1)]) if ages.size() > 0 else ""


## Plain-language description of a tech's effects.
static func effect_text(eff: Dictionary) -> String:
	var parts := []
	for k: String in eff:
		var v := float(eff[k])
		var pct := "%+d%%" % roundi(v * 100)
		if k.begins_with("speed:trade:"):
			parts.append("%s workers %s speed" % [trade_name(k.substr(12)).to_lower(), pct])
		elif k == "xp": parts.append("workers learn %s faster" % pct)
		elif k == "food": parts.append("people eat %s" % pct)
		elif k == "need": parts.append("artisans and nobles use %s goods" % pct)
		elif k == "store": parts.append("store room %s" % pct)
		elif k == "housing": parts.append("housing %s" % pct)
		elif k == "immigration": parts.append("newcomers arrive %s faster" % pct)
		elif k == "vein": parts.append("%d%% of mining leaves the vein untouched" % roundi(v * 100))
		elif k == "tool_save": parts.append("%d%% of new workers need no new tool" % roundi(v * 100))
		elif k.begins_with("speed:cat:"):
			parts.append("%s buildings %s speed" % [k.substr(10).capitalize(), pct])
		elif k == "speed:all":
			parts.append("all production %s speed" % pct)
		elif k == "speed:worker:artisan":
			parts.append("artisan workshops %s speed" % pct)
		elif k.begins_with("speed:"):
			parts.append("%s %s speed" % [String(bld.get(k.substr(6), {}).get("name", k.substr(6))), pct])
		elif k.begins_with("out:"):
			parts.append("%s +%d output" % [String(bld.get(k.substr(4), {}).get("name", k.substr(4))), int(v)])
		elif k == "tax": parts.append("gold tax %s" % pct)
		elif k == "research": parts.append("research %s" % pct)
		elif k == "carry": parts.append("carriers %s faster" % pct)
		elif k == "build": parts.append("construction %s faster" % pct)
		elif k == "attack": parts.append("attackers %+d%% win chance" % roundi(v * 100))
		elif k == "defense": parts.append("defenders %+d%% win chance" % roundi(v * 100))
		else: parts.append("%s %s" % [k, pct])
	return ", ".join(parts)


## The trade a building's worker practises: its "trade" in buildings.json, or its build category.
static func trade(id: String) -> String:
	var d: Dictionary = bld.get(id, {})
	return String(d.get("trade", d.get("cat", "")))


## The tool a trade's new workers need ("axes" for woodland), or "" if the trade has none.
static func tool_for(trade_id: String) -> String:
	return String(_tool_of_trade.get(trade_id, ""))


static func is_tool_res(res: String) -> bool:
	return res_by_id.has(res) and res_by_id[res].has("tool")


static func trade_name(t: String) -> String:
	return String(trades[t].get("name", t)) if trades.has(t) else t.capitalize()


## What a specialist of trade t is called ("smith", "woodsman").
static func trade_title(t: String) -> String:
	return String(trades[t].get("title", "worker")) if trades.has(t) else "worker"


## More than one specialist of trade t ("smiths", "woodsmen").
static func trade_plural(t: String) -> String:
	return String(trades[t].get("plural", trade_title(t) + "s")) if trades.has(t) else "workers"


## The resources a need asks for: "wine|beer" means either will do.
static func need_options(key: String) -> PackedStringArray:
	return key.split("|")


static func bld_tex_id(id: String) -> String:
	var d: Dictionary = bld.get(id, {})
	return String(d.get("tex", "bld_" + id))


static func is_mil(id: String) -> bool:
	var d: Dictionary = bld.get(id, {})
	return id == "hq" or d.has("garrison")


static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), res_abbr(k)])
	return " ".join(parts)
