extends Feature
## Fires that spread. A fire starts in a building (a random event's fire, or a catapult's stone) and
## grows. A building on fire stops working, and when the fire has burned it down it is gone. Fire jumps
## to wooden neighbours within 3 tiles; buildings mostly of stone or brick do not catch, and nor do the
## headquarters, stores and stone forts. People from working wells within 10 tiles, and the crew of a
## fire station within 14, run with buckets: the more of them, the faster the fire dies. A fire left
## alone burns a building down in a minute or two.

const SPREAD_R := 3.0
const WELL_R := 10.0
const STATION_R := 14.0
const GROW := 0.009          # heat a second, unfought
const FIGHT := 0.03          # heat a second taken off by each bucket carrier
const BURN := 0.02           # damage a second at full heat (the building is gone at 1)
const CATCH := 0.012         # chance a second, at full heat, for each wooden neighbour to catch

var burning := {}            # building id -> {"heat": 0..1, "dmg": 0..1, "t": since}
var lost := {}               # realm id -> buildings burned down
var put_out := {}            # realm id -> fires put out
var rng := RandomNumberGenerator.new()


func _init() -> void:
	id = "fires"
	title = "Spreading fires"
	info = "Fires spread from building to wooden building. Wells and fire stations near them send people with buckets; stone and brick buildings don't catch."
	default_on = true


func on_start(loaded: bool) -> void:
	if not loaded or rng.seed == 0:
		rng.seed = (sim.seed_str + ":fire").hash()


## Whether building b can catch fire: mostly wood (more planks than stone and bricks in its cost),
## and not a headquarters, store or fort.
func flammable(b: Sim.Bld) -> bool:
	if b.ty == "hq" or b.dead or sim.is_store(b) or b.state != "ready":
		return false
	var c: Dictionary = b.def.get("cost", {})
	var wood := float(c.get("planks", 0)) + float(c.get("wood", 0))
	var stone := float(c.get("stone", 0)) + float(c.get("bricks", 0))
	return wood > stone


## Sets building b on fire (if it can burn). Returns whether it did.
func ignite(b: Sim.Bld) -> bool:
	if b == null or burning.has(b.id) or not flammable(b):
		return false
	burning[b.id] = {"heat": 0.3, "dmg": 0.0, "t": sim.time}
	Chronicle.fire(sim, sim.players[b.p - 1])
	if b.p == 1:
		sim.emit_log("Fire in your %s! Wells and fire stations nearby send people with buckets." % String(b.def.name).to_lower(), Color("e0603a"), Vector2i(b.x, b.y))
	return true


## Bucket carriers who can reach building b: one from each working well near it, three from each
## manned fire station.
func fighters(b: Sim.Bld) -> int:
	var n := 0
	for w: Sim.Bld in sim.realm_blds(sim.players[b.p - 1]):
		if w.state != "ready" or not w.staffed or burning.has(w.id):
			continue
		var d := Vector2(w.x - b.x, w.y - b.y).length()
		if w.ty == "well" and d <= WELL_R:
			n += 1
		elif w.ty == "fire_station" and d <= STATION_R:
			n += 3
	return n


func on_second() -> void:
	if burning.is_empty():
		return
	var ids := burning.keys()
	ids.sort()
	for bid in ids:
		var f: Dictionary = burning[bid]
		var b: Sim.Bld = sim.by_id.get(bid)
		if b == null or b.dead:
			burning.erase(bid)
			continue
		var n := fighters(b)
		f.heat = clampf(float(f.heat) + GROW - FIGHT * n, 0.0, 1.0)
		f.dmg = float(f.dmg) + BURN * float(f.heat)
		if float(f.heat) <= 0.0:
			burning.erase(bid)
			put_out[b.p] = int(put_out.get(b.p, 0)) + 1
			if b.p == 1:
				sim.emit_log("The fire at your %s is out." % String(b.def.name).to_lower(), Color("86ad5c"), Vector2i(b.x, b.y))
			continue
		if float(f.dmg) >= 1.0:
			burning.erase(bid)
			lost[b.p] = int(lost.get(b.p, 0)) + 1
			Chronicle.burned(sim, sim.players[b.p - 1])
			var mil: bool = sim.is_mil(b) or bool(b.def.get("claim_only", false))
			sim.destroy(b, "burned down.")
			if mil:
				sim.recompute_territory()
			continue
		# sparks: each wooden building near it may catch
		for o: Sim.Bld in sim.realm_blds(sim.players[b.p - 1]):
			if o == b or burning.has(o.id) or Vector2(o.x - b.x, o.y - b.y).length() > SPREAD_R:
				continue
			if rng.randf() < CATCH * float(f.heat) and flammable(o):
				ignite(o)


func work_block(_p: Sim.Player, b: Sim.Bld) -> String:
	return "On fire!" if burning.has(b.id) else ""


func building_lines(b: Sim.Bld) -> PackedStringArray:
	if burning.has(b.id):
		var f: Dictionary = burning[b.id]
		return PackedStringArray(["[color=#e0603a]On fire: %d%% burned, %s.[/color]" % [roundi(float(f.dmg) * 100.0), "nobody to fight it (no well or fire station near)" if fighters(b) == 0 else ("1 person with a bucket" if fighters(b) == 1 else "%d people with buckets" % fighters(b))]])
	if b.ty == "fire_station":
		return PackedStringArray(["Sends 3 people with buckets to fires within %d tiles." % int(STATION_R)])
	if not flammable(b) and b.state == "ready" and b.ty != "hq":
		return PackedStringArray()
	return PackedStringArray()


func panel_lines(p: Sim.Player) -> PackedStringArray:
	var n := 0
	for bid in burning:
		var b: Sim.Bld = sim.by_id.get(bid)
		if b != null and b.p == p.id:
			n += 1
	var out := PackedStringArray()
	if n > 0:
		out.append("[color=#e0603a]Fires: %d of your buildings are burning.[/color]" % n)
	if int(lost.get(p.id, 0)) > 0:
		out.append("Burned down so far: %d" % int(lost[p.id]))
	return out


## Flames and smoke over burning buildings, and the bucket carriers running to them.
func draw_top(view: CanvasItem, rect: Rect2i) -> void:
	if burning.is_empty():
		return
	var mv = view
	var tm := float(Time.get_ticks_msec()) / 1000.0
	for bid in burning:
		var b: Sim.Bld = sim.by_id.get(bid)
		if b == null or not rect.has_point(Vector2i(b.x, b.y)):
			continue
		var f: Dictionary = burning[bid]
		var h := float(f.heat)
		var base := Vector2(b.x + 0.5, b.y - 0.15)
		if mv.raised:
			base.y -= mv.lift_at(base.x, base.y + 0.3)
		# smoke
		for k in 4:
			var ph := fmod(tm * 0.35 + k * 0.25, 1.0)
			view.draw_circle(base + Vector2(sin(k * 1.7 + tm) * 0.2 + ph * 0.4, -0.7 - ph * 2.0), 0.22 + ph * 0.45, Color(0.28, 0.28, 0.28, 0.5 * (1.0 - ph)))
		# flames
		for k in 5:
			var x := -0.45 + k * 0.22
			var fl := (0.45 + 0.75 * h) * (0.75 + 0.25 * sin(tm * 9.0 + k * 2.1)) * (1.0 - 0.25 * absf(k - 2) / 2.0)
			var p0 := base + Vector2(x, 0.0)
			view.draw_colored_polygon(PackedVector2Array([p0 + Vector2(-0.14, 0.1), p0 + Vector2(-0.05, -fl * 0.55), p0 + Vector2(0.0, -fl), p0 + Vector2(0.06, -fl * 0.5), p0 + Vector2(0.14, 0.1)]), Color(0.95, 0.42, 0.08, 0.92))
			view.draw_colored_polygon(PackedVector2Array([p0 + Vector2(-0.06, 0), p0 + Vector2(0.0, -fl * 0.6), p0 + Vector2(0.06, 0)]), Color(1.0, 0.85, 0.3, 0.95))
		# bucket carriers: little blue figures running between the fire and the nearest well
		var src := Vector2(-1, -1)
		var bd := 1e9
		for w: Sim.Bld in sim.realm_blds(sim.players[b.p - 1]):
			if (w.ty == "well" or w.ty == "fire_station") and w.state == "ready" and w.staffed:
				var d := Vector2(w.x - b.x, w.y - b.y).length()
				if d < bd and d <= STATION_R:
					bd = d; src = Vector2(w.x + 0.5, w.y + 0.8)
		if src.x >= 0.0:
			var dst := Vector2(b.x + 0.5, b.y + 0.9)
			for k in mini(4, fighters(b)):
				var ph := fmod(tm * 0.4 + k * 0.27, 1.0)
				var q := src.lerp(dst, ph if k % 2 == 0 else 1.0 - ph)
				if mv.raised:
					q.y -= mv.lift_at(q.x, q.y)
				view.draw_circle(q + Vector2(0, -0.32), 0.09, Color("e7c48a"))
				view.draw_rect(Rect2(q + Vector2(-0.08, -0.24), Vector2(0.16, 0.24)), Color("5b8fd6"))
				view.draw_rect(Rect2(q + Vector2(0.08, -0.16), Vector2(0.09, 0.09)), Color("9cc6e8"))


func ai_steps(p: Sim.Player, _have: Callable) -> Array:
	# a fire station once the town is middling, a second for a big one; one after any fire
	var pop: int = sim.pop_total(p)
	var had := int(lost.get(p.id, 0)) + int(put_out.get(p.id, 0)) > 0
	return [["fire_station", (1 if pop > 50 or had else 0) + (1 if pop > 160 else 0)]]


func save_state() -> Dictionary:
	return {"burning": burning, "lost": lost, "put_out": put_out, "rng": rng.state, "seed": rng.seed}


func load_state(d: Dictionary) -> void:
	burning = {}
	for k in d.get("burning", {}):
		burning[int(k)] = (d.burning[k] as Dictionary).duplicate()
	lost = {}
	for k in d.get("lost", {}):
		lost[int(k)] = int(d.lost[k])
	put_out = {}
	for k in d.get("put_out", {}):
		put_out[int(k)] = int(d.put_out[k])
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng", 0))
