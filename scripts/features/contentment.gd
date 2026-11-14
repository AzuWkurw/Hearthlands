extends Feature
## Contentment: how happy a realm's people are, from 0 to 1. Half (0.5) is where every realm starts and
## changes nothing. Taverns serving beer and bread to the homes near them, and chapels burning candles
## near them, raise it; hunger and sickness lower it. Content people work faster (up to 10%), unhappy
## ones slower (down to about 7%). A tavern with beer and bread to spare holds a festival now and then:
## everyone works 10% faster for 3 minutes. When the realm stays unhappy for 3 minutes, idle peasants
## start to leave, one a minute.

const TAVERN_R := 9        # tiles a tavern serves
const CHAPEL_R := 10       # tiles a chapel calms
const SERVED_FOR := 75.0   # seconds a tavern or chapel counts as working after its last cycle
const FESTIVAL := 180.0
const FEST_COST := 5       # beer and bread a festival takes
const LOW := 0.3           # below this the realm is unhappy
const FEST_COVER := 0.15   # share of homes its taverns must reach for a festival (0.3 before build 53)

var served := {}           # building id -> time of its last cycle
var mood_of := {}          # realm id -> contentment now
var cover := {}            # realm id -> [share of homes near a tavern, near a chapel]
var festival := {}         # realm id -> end time of the festival
var next_fest := {}        # realm id -> earliest time of the next festival
var low_since := {}        # realm id -> since when it has been unhappy (or absent)
var left := {}             # realm id -> peasants who left
var feasts := {}           # realm id -> festivals held
var _t := 0


func _init() -> void:
	id = "contentment"
	title = "Taverns and contentment"
	info = "Taverns (beer and bread) and chapels (candles) make the homes near them content, and content people work faster; festivals speed everyone up for a while. Unhappy realms lose idle peasants."
	default_on = true


func on_cycle(_p: Sim.Player, b: Sim.Bld) -> void:
	if b.ty == "tavern" or b.ty == "chapel":
		served[b.id] = sim.time


func mood(p: Sim.Player) -> float:
	return float(mood_of.get(p.id, 0.5))


func in_festival(p: Sim.Player) -> bool:
	return sim.time < float(festival.get(p.id, -1.0))


## The share of realm p's homes (by room) near a working tavern and near a working chapel.
func _cover(p: Sim.Player) -> Array:
	var taverns := []
	var chapels := []
	var homes := []
	for b: Sim.Bld in sim.realm_blds(p):
		if b.state != "ready" or b.dead:
			continue
		if b.ty == "tavern" and sim.time - float(served.get(b.id, -1e9)) < SERVED_FOR:
			taverns.append(b)
		elif b.ty == "chapel" and sim.time - float(served.get(b.id, -1e9)) < SERVED_FOR:
			chapels.append(b)
		elif b.def.has("housing"):
			homes.append(b)
	var room := 0.0
	var by_t := 0.0
	var by_c := 0.0
	for h: Sim.Bld in homes:
		var n := float(h.def.housing)
		room += n
		for t: Sim.Bld in taverns:
			if (t.x - h.x) * (t.x - h.x) + (t.y - h.y) * (t.y - h.y) <= TAVERN_R * TAVERN_R:
				by_t += n
				break
		for c: Sim.Bld in chapels:
			if (c.x - h.x) * (c.x - h.x) + (c.y - h.y) * (c.y - h.y) <= CHAPEL_R * CHAPEL_R:
				by_c += n
				break
	if room <= 0.0:
		return [0.0, 0.0]
	return [by_t / room, by_c / room]


func on_second() -> void:
	_t += 1
	for p: Sim.Player in sim.players:
		if not p.alive:
			continue
		if _t % 5 == 0 or not cover.has(p.id):
			cover[p.id] = _cover(p)
		var cv: Array = cover[p.id]
		var m := 0.5 + 0.3 * float(cv[0]) + 0.2 * float(cv[1])
		if p.starve > 0:
			m -= 0.25
		var dis = sim.get_feature("diseases")
		if dis != null:
			m -= 0.15 * maxf(0.0, float(dis.sick_share(p)) - 0.1)
		if in_festival(p):
			m += 0.2
		m = clampf(m, 0.0, 1.0)
		mood_of[p.id] = m
		# a festival, when a tavern serves a good part of the town and there is beer and bread to spare
		if float(cv[0]) >= FEST_COVER and not in_festival(p) and sim.time >= float(next_fest.get(p.id, 600.0)) \
				and float(p.stock.get("beer", 0.0)) >= FEST_COST * 2 and float(p.stock.get("bread", 0.0)) >= FEST_COST * 2:
			sim.take(p, "beer", FEST_COST)
			sim.take(p, "bread", FEST_COST)
			sim.used(p, "beer", FEST_COST)
			sim.used(p, "bread", FEST_COST)
			festival[p.id] = sim.time + FESTIVAL
			feasts[p.id] = int(feasts.get(p.id, 0)) + 1
			next_fest[p.id] = sim.time + FESTIVAL + 300.0 + float((p.id * 97 + _t) % 180)
			if not p.ai:
				sim.emit_log("A festival at the tavern! Everyone works 10% faster for 3 minutes.", Color("e8c870"))
			elif Diplomacy.relation(sim, 1, p.id) != Diplomacy.WAR and sim.players[0].alive:
				sim.emit_log("%s holds a festival: its people work faster for a while." % p.name, p.color.lightened(0.35))
		# unhappy for long: idle peasants leave, one a minute
		if m < LOW:
			if not low_since.has(p.id):
				low_since[p.id] = sim.time
			elif sim.time - float(low_since[p.id]) >= 180.0 and _t % 60 == 0 and p.peasant - p.used_peasant - p.away > 0 and p.peasant > 4:
				p.peasant -= 1
				left[p.id] = int(left.get(p.id, 0)) + 1
				if not p.ai:
					sim.emit_log("An unhappy peasant has left your realm. Taverns, chapels and food keep people content.", Color("e0b060"))
		else:
			low_since.erase(p.id)


func speed_bonus(p: Sim.Player, _b: Sim.Bld) -> float:
	return (mood(p) - 0.5) * 0.2 + (0.1 if in_festival(p) else 0.0)


func top_text(p: Sim.Player) -> String:
	return "Festival!" if in_festival(p) else ""


func panel_lines(p: Sim.Player) -> PackedStringArray:
	var cv: Array = cover.get(p.id, [0.0, 0.0])
	var m := mood(p)
	var col := "#86ad5c" if m >= 0.6 else ("#d9483d" if m < LOW else "#e7e3d0")
	var eff := roundi((m - 0.5) * 20.0 + (10.0 if in_festival(p) else 0.0))
	var t := "Contentment  [color=%s][b]%d%%[/b][/color] (work %s%d%%): taverns serve %d%% of homes, chapels %d%%" % [col, roundi(m * 100.0), "+" if eff >= 0 else "", eff, roundi(float(cv[0]) * 100.0), roundi(float(cv[1]) * 100.0)]
	if in_festival(p):
		t += ", [color=#e8c870]festival for %d s[/color]" % int(float(festival[p.id]) - sim.time)
	if int(left.get(p.id, 0)) > 0:
		t += ", %d left unhappy" % int(left[p.id])
	return PackedStringArray([t])


func building_lines(b: Sim.Bld) -> PackedStringArray:
	if b.ty != "tavern" and b.ty != "chapel":
		return PackedStringArray()
	var on := sim.time - float(served.get(b.id, -1e9)) < SERVED_FOR
	var r := TAVERN_R if b.ty == "tavern" else CHAPEL_R
	var homes := 0
	for h: Sim.Bld in sim.blds:
		if h.p == b.p and not h.dead and h.def.has("housing") and (h.x - b.x) * (h.x - b.x) + (h.y - b.y) * (h.y - b.y) <= r * r:
			homes += 1
	var what := "Serves" if b.ty == "tavern" else "Calms"
	return PackedStringArray(["%s %d homes within %d tiles%s" % [what, homes, r, "" if on else " [color=#e0b060](not while it lacks %s)[/color]" % ("beer and bread" if b.ty == "tavern" else "candles")]])


func draw_map(view: CanvasItem, _rect: Rect2i) -> void:
	# while placing a tavern or chapel, the ring it would serve
	var mv = view
	if not ("place_type" in mv):
		return
	var pt := String(mv.place_type)
	if (pt == "tavern" or pt == "chapel") and mv.ghost.x >= 0:
		var r := float(TAVERN_R if pt == "tavern" else CHAPEL_R)
		view.draw_arc(Vector2(mv.ghost) + Vector2(0.5, 0.5), r, 0.0, TAU, 64, Color(0.95, 0.85, 0.5, 0.6), 0.08)


func ai_steps(p: Sim.Player, have: Callable) -> Array:
	var mins := sim.time / 60.0
	var pop := sim.pop_total(p)
	return [
		# enough taverns for a festival: they must reach a good part of the homes (build 53)
		["tavern", (1 + pop / 80) if mins > 14 and int(have.call("brewery")) > 0 and float(p.stock.get("bread", 0.0)) > 12.0 else 0],
		["chapel", (1 + pop / 120) if mins > 18 and int(have.call("chandler")) > 0 and float(p.stock.get("candles", 0.0)) > 6.0 else 0],
	]


func save_state() -> Dictionary:
	return {"served": served, "festival": festival, "next_fest": next_fest, "low_since": low_since, "left": left, "feasts": feasts, "t": _t, "mood": mood_of, "cover": cover}


func load_state(d: Dictionary) -> void:
	served = {}
	for k in d.get("served", {}):
		served[int(k)] = float(d.served[k])
	for key in ["festival", "next_fest", "low_since", "left", "feasts", "mood_of", "cover"]:
		var dst: Dictionary = get(key)
		dst.clear()
		var src: Dictionary = d.get({"mood_of": "mood", "cover": "cover"}.get(key, key), {})
		for k in src:
			dst[int(k)] = src[k]
	_t = int(d.get("t", 0))
