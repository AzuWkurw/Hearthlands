extends Feature
## Diseases, their prevention and their cure.
## Every ten seconds each disease may break out in a realm; how likely depends on its causes (cold
## without coats, crowding, too few wells, hunger, heat, wetlands) and on prevention (bathhouses keep
## people clean, wells give clean water, coats keep the cold out). Once in, it spreads among the healthy
## and the sick slowly get better by themselves, faster with medicine: medicine in store cures a few at
## home, and an infirmary cures 8 people with each medicine. Some of the sick die. Sick people don't
## work, so every building of the realm works slower by the share of its people who are sick.
## Uses the seasons (temperature, wetlands) and clothes features when they are switched on.

## id: name, chance of an outbreak per check at risk 1, spread per sick person per second,
## share of the sick who get better each second by themselves, and share who die each second.
const DISEASES := {
	"flu": {"name": "Winter fever", "out": 0.07, "spread": 0.022, "heal": 1.0 / 60.0, "die": 0.0003},
	"dysentery": {"name": "Dysentery", "out": 0.04, "spread": 0.018, "heal": 1.0 / 70.0, "die": 0.0008},
	"marsh": {"name": "Marsh fever", "out": 0.05, "spread": 0.014, "heal": 1.0 / 100.0, "die": 0.0008},
	"plague": {"name": "Plague", "out": 0.004, "spread": 0.02, "heal": 1.0 / 120.0, "die": 0.002},
}
const BATH_PEOPLE := 50.0       # people one working bathhouse keeps clean
const WELL_PEOPLE := 30.0       # people one well gives clean water
const INFIRMARY_CURES := 8.0    # sick people cured per infirmary work cycle
const HOME_CURES := 3.0         # sick people cured by one medicine at home
const GRACE := 360.0            # no outbreaks in the first six minutes

## realm id -> {disease id -> sick people (fractional)}
var sick: Dictionary = {}
## realm id -> deaths waiting to happen (fractional)
var dying: Dictionary = {}
## realm id -> sick people waiting for a home cure (fractional medicine use)
var home_t: Dictionary = {}
## building id -> game time of the last bath cycle
var baths: Dictionary = {}
## realm id -> total who died of disease, and who were cured
var died: Dictionary = {}
var cured: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _t := 0
var _risk: Dictionary = {}      # realm id -> {disease id -> [risk, prevention]}, for the panel
var _speed: Dictionary = {}     # realm id -> work speed change this second


func _init() -> void:
	id = "diseases"
	title = "Diseases"
	info = "Winter fever, dysentery, marsh fever and plague break out and spread. Prevent them with bathhouses, wells and coats; cure them with medicine from the apothecary and infirmaries."
	default_on = true


func on_start(loaded: bool) -> void:
	if not loaded or rng.seed == 0:
		rng.seed = (sim.seed_str + ":disease").hash()


func _people(p: Sim.Player) -> float:
	return float(sim.pop_total(p))


func total_sick(p: Sim.Player) -> float:
	var s := 0.0
	var d: Dictionary = sick.get(p.id, {})
	for k in d:
		s += float(d[k])
	return s


func sick_share(p: Sim.Player) -> float:
	return clampf(total_sick(p) / maxf(1.0, _people(p)), 0.0, 1.0)


## How much of realm p the working bathhouses and wells cover (0 to 1 each).
func _cover(p: Sim.Player) -> Array:
	var bath := 0.0
	var wells := 0.0
	for b: Sim.Bld in sim.realm_blds(p):
		if b.state != "ready":
			continue
		if b.ty == "bathhouse" and sim.time - float(baths.get(b.id, -1e9)) < 75.0:
			bath += BATH_PEOPLE
		elif b.ty == "well" and b.staffed:
			wells += WELL_PEOPLE
	var n := maxf(1.0, _people(p))
	return [clampf(bath / n, 0.0, 1.0), clampf(wells / n, 0.0, 1.0)]


## The risk (causes) and the prevention of each disease in realm p, as {id: [risk, prevention]}.
func risks(p: Sim.Player) -> Dictionary:
	var cov := _cover(p)
	var bath: float = cov[0]
	var water: float = cov[1]
	var cl = sim.get_feature("seasons")
	var wear = sim.get_feature("clothing")
	var t := 12.0 if cl == null else float(cl.realm_temp(p))
	var crowd := clampf(_people(p) / maxf(1.0, float(sim.housing(p))), 0.0, 1.2)
	var hungry := 1.0 if p.starve > 0 else 0.0
	var cold := clampf((8.0 - t) / 16.0, 0.0, 1.0)
	# without the clothes feature people are assumed dressed for the weather
	var unclad: float = 0.0 if wear == null else float(wear.cold_need(p))
	var heat := clampf((t - 20.0) / 12.0, 0.0, 1.0)
	var wet := 0.0
	if cl != null:
		var n := 0
		var mine := sim.realm_blds(p)
		for b: Sim.Bld in mine:
			if cl.biome_at(b.x, b.y) == cl.WETLAND:
				n += 1
		wet = float(n) / maxf(1.0, mine.size())
	# factory smoke and clean water from waterworks (build 77)
	var smog := 0.0
	var fh = sim.get_feature("factory_health")
	if fh != null and fh.active(p):
		water = maxf(water, float(fh.water_share(p)))
		smog = float(fh.air_of(p))
	var out := {}
	out["flu"] = [smog * 0.8 + cold * 0.8 + unclad * 2.5 + crowd * 0.3, minf(0.65, bath * 0.3 + (0.0 if wear == null else float(wear.warm_share(p)) * 0.35))]
	out["dysentery"] = [(1.0 - water) * 0.8 + heat * 0.6 + hungry * 0.8 + crowd * 0.2, minf(0.75, water * 0.4 + bath * 0.35)]
	out["marsh"] = [wet * 2.5 * (1.0 if t > 14.0 else 0.2), minf(0.7, bath * 0.3 + (0.3 if float(p.stock.get("medicine", 0.0)) >= 1.0 else 0.0))]
	out["plague"] = [maxf(0.0, crowd - 0.95) * 10.0 + (0.3 if sim.time > 2400.0 else 0.0), minf(0.8, bath * 0.6)]
	return out


func on_second() -> void:
	_t += 1
	for p: Sim.Player in sim.players:
		if not p.alive:
			continue
		var d: Dictionary = sick.get(p.id, {})
		sick[p.id] = d
		var people := _people(p)
		# outbreaks
		if _t % 10 == 0 or not _risk.has(p.id):
			_risk[p.id] = risks(p)
		if _t % 10 == 0 and sim.time > GRACE and people >= 25.0:
			for k: String in DISEASES:
				if float(d.get(k, 0.0)) >= 1.0:
					continue
				var rp: Array = _risk[p.id][k]
				if rng.randf() < float(DISEASES[k].out) * float(rp[0]) * (1.0 - float(rp[1])):
					outbreak(p, k)
		# spread, recovery, deaths
		var dead := float(dying.get(p.id, 0.0))
		var sick_now := total_sick(p)
		for k: String in d.keys():
			var n := float(d[k])
			if n <= 0.0:
				d.erase(k)
				continue
			var e: Dictionary = DISEASES[k]
			var rp: Array = _risk[p.id].get(k, [1.0, 0.0])
			var healthy := clampf(1.0 - sick_now / maxf(1.0, people), 0.0, 1.0)
			var grow := n * float(e.spread) * healthy * (1.0 - float(rp[1]) * 0.7) * (0.5 + minf(1.5, float(rp[0])))
			var heal := n * float(e.heal)
			dead += n * float(e.die)
			n = minf(n + grow - heal, people * 0.6)
			if n < 0.5:
				d.erase(k)
				if not p.ai:
					sim.emit_log("%s has left your realm." % String(e.name), Color("a0d070"))
			else:
				d[k] = n
		# medicine at home: one medicine cures 3 people, used now and then while people are sick
		var ht := float(home_t.get(p.id, 0.0)) + total_sick(p) / 40.0
		if ht >= 1.0:
			ht -= 1.0
			if float(p.stock.get("medicine", 0.0)) >= 1.0 and total_sick(p) >= 1.0:
				sim.take(p, "medicine", 1.0)
				sim.used(p, "medicine", 1.0)
				cure(p, HOME_CURES)
		home_t[p.id] = ht
		# deaths
		while dead >= 1.0:
			dead -= 1.0
			_kill(p)
		dying[p.id] = dead
		_speed[p.id] = -sick_share(p)


func outbreak(p: Sim.Player, k: String) -> void:
	var d: Dictionary = sick.get(p.id, {})
	sick[p.id] = d
	var n := maxf(2.0, _people(p) * 0.03)
	d[k] = float(d.get(k, 0.0)) + n
	if not p.ai:
		sim.emit_log("%s has broken out: %d people are sick. Medicine and an infirmary cure them; %s" % [String(DISEASES[k].name), roundi(n), _advice(k)], Color("e0a0c0"))


func _advice(k: String) -> String:
	match k:
		"flu": return "fur coats and bathhouses keep it away."
		"dysentery": return "wells (clean water) and bathhouses keep it away."
		"marsh": return "it comes from the wetlands in warm weather."
		"plague": return "it loves crowded towns; bathhouses and room to live keep it away."
	return ""


## Cures up to n sick people of realm p, the deadliest diseases first.
func cure(p: Sim.Player, n: float) -> void:
	var d: Dictionary = sick.get(p.id, {})
	for k in ["plague", "dysentery", "marsh", "flu"]:
		if n <= 0.0:
			break
		var have := float(d.get(k, 0.0))
		var c := minf(have, n)
		if c > 0.0:
			d[k] = have - c
			n -= c
			cured[p.id] = float(cured.get(p.id, 0.0)) + c


func _kill(p: Sim.Player) -> void:
	var who := ""
	if p.peasant > 4:
		p.peasant -= 1; who = "peasant"
	elif p.artisan > 1:
		p.artisan -= 1; who = "artisan"
	else:
		return
	died[p.id] = int(died.get(p.id, 0)) + 1
	# the dead are no longer sick
	var d: Dictionary = sick.get(p.id, {})
	var worst := ""
	for k in d:
		if worst == "" or float(DISEASES[k].die) > float(DISEASES[worst].die):
			worst = k
	if worst != "":
		d[worst] = maxf(0.0, float(d[worst]) - 1.0)
	if not p.ai:
		sim.emit_log("A %s died of %s." % [who, String(DISEASES.get(worst, {"name": "illness"}).name).to_lower()], Color("e08a6a"))


func on_cycle(p: Sim.Player, b: Sim.Bld) -> void:
	if b.ty == "infirmary":
		cure(p, INFIRMARY_CURES)
	elif b.ty == "bathhouse":
		baths[b.id] = sim.time


func work_block(p: Sim.Player, b: Sim.Bld) -> String:
	if b.ty == "infirmary" and total_sick(p) < 1.0:
		return "No patients"
	return ""


func speed_bonus(p: Sim.Player, _b: Sim.Bld) -> float:
	return float(_speed.get(p.id, 0.0))


func ai_steps(p: Sim.Player, have: Callable) -> Array:
	var mins := sim.time / 60.0
	var pop := sim.pop_total(p)
	var ill := total_sick(p) >= 1.0
	return [
		["herb_garden", 1 if mins > 6 or ill else 0],
		["apothecary", 1 if int(have.call("herb_garden")) > 0 else 0],
		["bathhouse", 1 if pop > 50 else 0],
		["infirmary", 1 if pop > 60 or (ill and pop > 30) else 0],
		["well", 2 if pop > 70 else 1],
		["bathhouse", 2 if pop > 110 else 1],
		["herb_garden", 2 if pop > 120 else 1],
		["bathhouse", 3 if pop > 160 else 0],
		["infirmary", 2 if pop > 160 else 1],
	]


func panel_lines(p: Sim.Player) -> PackedStringArray:
	var out := PackedStringArray()
	var d: Dictionary = sick.get(p.id, {})
	var parts := []
	for k in d:
		if float(d[k]) >= 0.5:
			parts.append("%s %d" % [String(DISEASES[k].name).to_lower(), roundi(float(d[k]))])
	var cov := _cover(p)
	var line := "Health  "
	if parts.is_empty():
		line += "[color=#a0d070]nobody sick[/color]"
	else:
		line += "[color=#e0a0c0][b]%d sick[/b] (%s), work -%d%%[/color]" % [roundi(total_sick(p)), ", ".join(parts), roundi(sick_share(p) * 100.0)]
	line += ", baths for %d%%, clean water for %d%%" % [roundi(float(cov[0]) * 100.0), roundi(float(cov[1]) * 100.0)]
	if int(died.get(p.id, 0)) > 0:
		line += ", %d died" % int(died.get(p.id, 0))
	out.append(line)
	if _risk.has(p.id):
		var high := []
		for k in _risk[p.id]:
			var rp: Array = _risk[p.id][k]
			var r := float(rp[0]) * (1.0 - float(rp[1]))
			if r >= 0.6:
				high.append(String(DISEASES[k].name).to_lower())
		if not high.is_empty():
			out.append("[color=#e0b080]High risk of %s.[/color]" % ", ".join(high))
	return out


func building_lines(b: Sim.Bld) -> PackedStringArray:
	var p: Sim.Player = sim.players[b.p - 1]
	match b.ty:
		"infirmary":
			return PackedStringArray(["Patients: %d sick in the realm; cures %d per medicine." % [roundi(total_sick(p)), int(INFIRMARY_CURES)]])
		"bathhouse":
			var on := sim.time - float(baths.get(b.id, -1e9)) < 75.0
			return PackedStringArray(["Keeps %d people clean%s." % [int(BATH_PEOPLE), "" if on else " (not yet: it needs water, logs and a worker)"]])
		"well":
			return PackedStringArray(["Clean water for %d people: fewer cases of dysentery." % int(WELL_PEOPLE)])
	return PackedStringArray()


func save_state() -> Dictionary:
	# forget bathhouses that are gone
	for k in baths.keys():
		if not sim.by_id.has(k):
			baths.erase(k)
	return {"sick": sick, "dying": dying, "home": home_t, "baths": baths, "died": died, "cured": cured, "rng": rng.state, "seed": rng.seed, "t": _t, "risk": _risk, "speed": _speed}


func load_state(d: Dictionary) -> void:
	sick = {}
	for k in d.get("sick", {}):
		var m := {}
		for dz in d.sick[k]:
			m[String(dz)] = float(d.sick[k][dz])
		sick[int(k)] = m
	dying = _ints(d.get("dying", {}))
	home_t = _ints(d.get("home", {}))
	baths = _ints(d.get("baths", {}))
	died = _ints(d.get("died", {}))
	# the work speed sickness gives this second (worked out once a second): kept, so a loaded game goes on the same
	_speed = {}
	var sp: Dictionary = d.get("speed", {})
	for k in sp:
		_speed[int(k)] = float(sp[k])
	cured = _ints(d.get("cured", {}))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng", 0))
	_t = int(d.get("t", 0))
	# the risks are worked out every ten seconds; keep the last ones so a loaded game goes on the same
	_risk = {}
	for k in d.get("risk", {}):
		_risk[int(k)] = d.risk[k]


static func _ints(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[int(k)] = src[k]
	return out
