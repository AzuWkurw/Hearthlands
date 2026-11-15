extends Feature
## Tool quality. Every tool is crude, standard, fine or masterwork. The toolsmith's skill decides the
## quality: an apprentice makes crude and standard tools, a master fine and masterwork ones; the machine
## works does better still. Tools in store are kept as a pool with an average quality. A worker uses his
## tool every work cycle and it wears out: crude after 40 cycles, masterwork after 180. Then he takes a
## new one from the stores; if there is none, he works on with a worn-out tool, 25% slower.
## Better tools make work faster: crude -12%, standard +0%, fine +12%, masterwork +25%.
## Build 66: a tool is also of a metal (SimArms): bronze lasts 0.6 as long as iron and works 10% slower,
## steel lasts 1.6 times as long and works 15% faster.
## Only matters when new workers need tools (the difficulty option).

const NAMES := ["crude", "standard", "fine", "masterwork"]
const BONUS := [-0.12, 0.0, 0.12, 0.25]
const LIFE := [40.0, 80.0, 120.0, 180.0]
const WORN := -0.25

## building id -> [quality (0 to 3, -1 = worn out), cycles left]
var held: Dictionary = {}
## realm id -> {tool -> sum of the qualities of the tools in store}
var pool: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _last: Dictionary = {}       # "realm:tool" -> quality of the tool last taken from the store


func _init() -> void:
	id = "tool_quality"
	title = "Tool quality"
	info = "Tools come crude, standard, fine or masterwork, by the toolsmith's skill. Better tools work faster and last longer; tools wear out and must be replaced."
	default_on = true


func on_start(loaded: bool) -> void:
	if not loaded or rng.seed == 0:
		rng.seed = (sim.seed_str + ":tools").hash()


func _active() -> bool:
	return bool(sim.opts.get("tools", true))


static func q_value(table: Array, q: float) -> float:
	if q < 0.0:
		return WORN
	var a := clampi(floori(q), 0, 3)
	var b := mini(a + 1, 3)
	return lerpf(float(table[a]), float(table[b]), q - a)


static func q_name(q: float) -> String:
	if q < 0.0:
		return "worn-out"
	return NAMES[clampi(roundi(q), 0, 3)]


## The average quality of realm p's tools of this kind in store. The pool counts the tools made since
## this feature came on; tools that were there before (and the starting kit) count as standard.
func store_quality(p: Sim.Player, tool: String) -> float:
	var e: Array = (pool.get(p.id, {}) as Dictionary).get(tool, [0.0, 0.0])
	var have := float(p.stock.get(tool, 0.0))
	var n := maxf(have, float(e[1]))
	if n < 0.5:
		return 1.0
	return clampf((float(e[0]) + maxf(0.0, have - float(e[1]))) / n, 0.0, 3.0)


func _entry(p: Sim.Player, tool: String) -> Array:
	var m: Dictionary = pool.get(p.id, {})
	pool[p.id] = m
	if not m.has(tool):
		m[tool] = [0.0, 0.0]
	return m[tool]


## A toolsmith made a tool: its quality comes from the smith's level and a little luck.
func on_made_at(b: Sim.Bld, p: Sim.Player, res: String, n: float) -> void:
	if not GameData.is_tool_res(res):
		return
	var lv := Sim.level(b.wxp, Sim.WORKER_XP)
	var e := _entry(p, res)
	for i in int(n):
		var score := lv * 0.5 + rng.randf() * 1.5 + (1.0 if b.ty == "machine_works" else 0.0)
		e[0] = float(e[0]) + clampf(floorf(score), 0.0, 3.0)
		e[1] = float(e[1]) + 1.0


## A tool left the stores (to a worker, or as an input): it takes the average quality with it.
func on_used(p: Sim.Player, res: String, n: float) -> void:
	if not GameData.is_tool_res(res):
		return
	var e := _entry(p, res)
	var have := float(p.stock.get(res, 0.0)) + n
	var cnt := float(e[1])
	var avg := 1.0
	if maxf(have, cnt) >= 0.5:
		avg = clampf((float(e[0]) + maxf(0.0, have - cnt)) / maxf(have, cnt), 0.0, 3.0)
	# the tracked tools leave in proportion to their share of the stock
	var share := clampf(cnt / maxf(maxf(have, cnt), 0.001), 0.0, 1.0) if cnt > 0.0 else 0.0
	var take := minf(cnt, n * share)
	if cnt > 0.0:
		e[0] = maxf(0.0, float(e[0]) - float(e[0]) / cnt * take)
		e[1] = cnt - take
	_last["%d:%s" % [p.id, res]] = avg


func on_hire(p: Sim.Player, b: Sim.Bld, took: String) -> void:
	if not _active() or sim.tool_of(b) == "":
		return
	if took != "":
		var q := float(_last.get("%d:%s" % [p.id, took], 1.0))
		held[b.id] = [q, q_value(LIFE, q) * SimArms.life_of(b.tool_q)]
	elif not held.has(b.id):
		# a specialist brings his own tool, or good tool care made one do: a standard one, half worn
		held[b.id] = [1.0, LIFE[1] * 0.5]


func on_cycle(p: Sim.Player, b: Sim.Bld) -> void:
	if not _active():
		return
	var tool := sim.tool_of(b)
	if tool == "":
		return
	var h: Array = held.get(b.id, [1.0, LIFE[1]])
	h[1] = float(h[1]) - 1.0
	if float(h[1]) <= 0.0:
		# worn out: fetch a new one, or carry on with the old one, slowly
		if float(p.stock.get(tool, 0.0)) >= 1.0:
			sim.take(p, tool, 1.0, sim.idx(b.x, b.y))
			sim.used(p, tool, 1.0)
			var q := float(_last.get("%d:%s" % [p.id, tool], 1.0))
			# its metal (build 66): the best in store
			sim.arms.give_tool(b, sim.arms.take_best(p, tool))
			h = [q, q_value(LIFE, q) * SimArms.life_of(b.tool_q)]
			if not p.ai and float(p.stock.get(tool, 0.0)) < 1.0:
				sim.emit_log("The last %s in store went to the %s. Tools wear out: keep a toolsmith busy." % [GameData.res_name(tool).to_lower(), String(b.def.name).to_lower()], Color("e0b080"))
		else:
			h = [-1.0, 0.0]
	held[b.id] = h


func speed_bonus(_p: Sim.Player, b: Sim.Bld) -> float:
	if not held.has(b.id):
		return 0.0
	return q_value(BONUS, float(held[b.id][0]))


func building_lines(b: Sim.Bld) -> PackedStringArray:
	var out := PackedStringArray()
	if not _active():
		return out
	var p: Sim.Player = sim.players[b.p - 1]
	if b.def.has("makes_tools") and b.staffed:
		var lv := Sim.level(b.wxp, Sim.WORKER_XP)
		var lo := clampf(floorf(lv * 0.5 + (1.0 if b.ty == "machine_works" else 0.0)), 0.0, 3.0)
		var hi := clampf(floorf(lv * 0.5 + 1.49 + (1.0 if b.ty == "machine_works" else 0.0)), 0.0, 3.0)
		out.append("Makes %s to %s tools (the smith's level decides; masters make the best)." % [NAMES[int(lo)], NAMES[int(hi)]])
	var tool := sim.tool_of(b)
	if tool != "" and held.has(b.id) and b.staffed:
		var h: Array = held[b.id]
		var q := float(h[0])
		var bonus := q_value(BONUS, q)
		var metal: String = SimArms.NAMES[clampi(b.tool_q, 0, 3)]
		if q < 0.0:
			out.append("[color=#f0a090]Tool: worn-out %s, %d%% work. Needs a new one from the stores.[/color]" % [GameData.res_name(tool).to_lower(), roundi(WORN * 100.0)])
		else:
			var ms: float = SimArms.TOOL_SPEED[clampi(b.tool_q, 0, 3)]
			out.append("Tool: [img=16x16]%s[/img] %s %s%s, %d of %d cycles left (%+d%% work)" % ["res://textures/%s.png" % SimArms.icon_id(tool, b.tool_q), q_name(q), (SimArms.tag(b.tool_q) + " ") if metal != "" else "", GameData.res_name(tool).to_lower(), ceili(float(h[1])),
				roundi(q_value(LIFE, q) * SimArms.life_of(b.tool_q)), roundi(((1.0 + bonus) * ms - 1.0) * 100.0)])
	if tool != "":
		var sp: String = sim.arms.split_text(p, tool)
		if int(p.stock.get(tool, 0.0)) <= 0:
			out.append("%s in store: none" % GameData.res_name(tool))
		else:
			out.append("%s in store: %d, %s on average%s" % [GameData.res_name(tool), int(p.stock.get(tool, 0.0)), q_name(store_quality(p, tool)), (" (%s)" % sim.arms.split_bb(p, tool)) if sp != "" else ""])
	return out


func panel_lines(p: Sim.Player) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	var counts := [0, 0, 0, 0, 0]   # worn, crude, standard, fine, master
	var metals := [0, 0, 0, 0]
	for b: Sim.Bld in sim.realm_blds(p):
		if b.staffed and held.has(b.id):
			var q := float(held[b.id][0])
			counts[0 if q < 0.0 else clampi(roundi(q), 0, 3) + 1] += 1
			if q >= 0.0:
				metals[clampi(b.tool_q, 0, 3)] += 1
	var bits := []
	for i in [4, 3, 2, 1]:
		if counts[i] > 0:
			bits.append("%d %s" % [counts[i], NAMES[i - 1]])
	if counts[0] > 0:
		bits.append("[color=#f0a090]%d worn out[/color]" % counts[0])
	if bits.is_empty():
		return PackedStringArray()
	var mb := []
	for t in [3, 2, 1]:
		if metals[t] > 0:
			mb.append("%d %s" % [metals[t], SimArms.tag(t)])
	return PackedStringArray(["Tools in use  " + ", ".join(bits) + ("  (%s)" % ", ".join(mb) if not mb.is_empty() else "")])


func save_state() -> Dictionary:
	for k in held.keys():
		if not sim.by_id.has(k):
			held.erase(k)
	return {"held": held, "pool": pool, "rng": rng.state, "seed": rng.seed, "last": _last}


func load_state(d: Dictionary) -> void:
	held = {}
	for k in d.get("held", {}):
		held[int(k)] = d.held[k]
	pool = {}
	for k in d.get("pool", {}):
		pool[int(k)] = d.pool[k]
	_last = d.get("last", {})
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng", 0))
