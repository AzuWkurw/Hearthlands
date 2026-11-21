class_name MissionScript
extends RefCounted
## Scripted events in a mission (build 77): rules of the form "when this happens, do that", kept in the
## mission's "rules" list (data/missions.json, data/campaign.json, or a mission written in the editor).
##
##   {"id": "e1", "when": {"kind": "age", "who": 0, "n": 1},
##    "do": [{"kind": "message", "text": "..."}, {"kind": "war", "who": 1}]}
##
## "who" picks a realm: 0 you, 1..8 the first, second... rival, -1 any rival (in a "when") or every rival
## (in a "do"). A rule fires once; a "time" rule with "every" fires again every so many minutes.
## Which rules fired, and when, is Sim.script_fired (saved), so a loaded game goes on the same.
## Everything here runs once a game second from Sim._mission_check, and uses no randomness.

## What can start a rule: kind, the words for the editor, the fields it takes.
const WHEN := [
	["start", "The mission starts", []],
	["time", "At a game minute", ["min"]],
	["every", "Every few minutes", ["min", "every"]],
	["after", "Some minutes after another event", ["rule", "min"]],
	["age", "A realm reaches an age", ["who", "age"]],
	["tech", "A realm finishes a study", ["who", "id"]],
	["pop", "A realm has so many people", ["who", "n"]],
	["build", "A realm has so many buildings of a kind", ["who", "ty", "n"]],
	["soldiers", "A realm has so many soldiers", ["who", "n"]],
	["land", "A realm holds so much land", ["who", "n"]],
	["stock", "A realm has goods in store", ["who", "res", "n"]],
	["wonders", "A realm has finished wonders", ["who", "n"]],
	["ships", "A realm has ships", ["who", "n"]],
	["war", "A rival is at war with you", ["who"]],
	["fallen", "A rival realm falls", ["who"]],
	["goal", "A goal is reached", ["goal"]],
]

## What a rule can do.
const DO := [
	["message", "Show a message", ["text"]],
	["war", "A rival declares war on you", ["who"]],
	["peace", "A rival makes peace with you", ["who"]],
	["ally", "A rival becomes your ally", ["who"]],
	["attack", "A rival attacks you now", ["who"]],
	["landing", "A rival's fleet lands soldiers", ["who", "n"]],
	["soldiers", "A realm gets soldiers", ["who", "n"]],
	["goods", "A realm gets goods", ["who", "res", "n"]],
	["tech", "A realm learns a study", ["who", "id"]],
	["show_goal", "A hidden goal is shown", ["goal"]],
	["minutes", "More time for the mission", ["n"]],
	["win", "The mission is won", []],
	["lose", "The mission is lost", []],
]

const TIME_KINDS := ["start", "time", "every", "after"]


## The realms a "who" means: [] when there is no such realm.
static func realms(sim: Sim, who: int) -> Array:
	if who == 0:
		return [sim.human()]
	if who < 0:
		return sim.players.slice(1)
	if who < sim.players.size():
		return [sim.players[who]]
	return []


## Fills {you} and {1}..{8} (the rivals' names) into a text.
static func fill(sim: Sim, text: String) -> String:
	if sim.players.is_empty():
		return text
	text = text.replace("{you}", sim.human().name)
	for k in range(1, sim.players.size()):
		text = text.replace("{%d}" % k, sim.players[k].name)
	return text


## Once a second, before the goals are counted.
static func check(sim: Sim) -> void:
	var rules: Array = sim.mission.get("rules", [])
	for k in rules.size():
		if sim.over:
			return
		var r: Dictionary = rules[k]
		var id := rule_id(r, k)
		var w: Dictionary = r.get("when", {})
		var f: Array = sim.script_fired.get(id, [])
		if not f.is_empty():
			# fired before: only a rule that repeats may go again
			if String(w.get("kind", "")) != "every" or float(w.get("every", 0)) <= 0.0:
				continue
			if sim.time < float(f[1]) + float(w.every) * 60.0:
				continue
		elif not holds(sim, w):
			continue
		sim.script_fired[id] = [(int(f[0]) if not f.is_empty() else 0) + 1, sim.time]
		for a in r.get("do", []):
			run(sim, a)


static func rule_id(r: Dictionary, k: int) -> String:
	var id := String(r.get("id", ""))
	return id if id != "" else "#%d" % k


## Whether a rule's condition is met now.
static func holds(sim: Sim, w: Dictionary) -> bool:
	var kind := String(w.get("kind", ""))
	var n := int(w.get("n", 1))
	match kind:
		"start":
			return true
		"time", "every":
			return sim.time >= float(w.get("min", 0)) * 60.0
		"after":
			var f: Array = sim.script_fired.get(String(w.get("rule", "")), [])
			return not f.is_empty() and sim.time >= float(f[1]) + float(w.get("min", 0)) * 60.0
		"goal":
			var g := int(w.get("goal", 0))
			return g >= 0 and g < sim.mission_done.size() and bool(sim.mission_done[g])
		"fallen":
			var who := int(w.get("who", -1))
			if who < 0:
				var gone := 0
				for p in sim.players.slice(1):
					if not p.alive:
						gone += 1
				return gone >= maxi(1, n)
			for p in realms(sim, who):
				if not p.alive:
					return true
			return false
	for p: Sim.Player in realms(sim, int(w.get("who", 0))):
		if p.alive and _realm_holds(sim, p, kind, w, n):
			return true
	return false


static func _realm_holds(sim: Sim, p: Sim.Player, kind: String, w: Dictionary, n: int) -> bool:
	match kind:
		"age":
			return p.age >= int(w.get("age", 1))
		"tech":
			return p.techs.has(String(w.get("id", "")))
		"pop":
			return sim.pop_total(p) >= n
		"soldiers":
			return sim.soldiers(p) >= n
		"land":
			return sim.owned(p.id)[0].size() >= n
		"stock":
			return float(p.stock.get(String(w.get("res", "")), 0.0)) >= n
		"wonders":
			return sim.wonders_of(p).size() >= n
		"ships":
			return p.ships + p.warships >= n
		"war":
			return p.id != 1 and Diplomacy.at_war(sim, p.id, 1)
		"build":
			var ty := String(w.get("ty", ""))
			var c := 0
			for b in sim.realm_blds(p):
				if b.ty == ty and b.state == "ready" and not b.dead:
					c += 1
					if c >= n:
						return true
			return false
	return false


## Carries out one action.
static func run(sim: Sim, a: Dictionary) -> void:
	var kind := String(a.get("kind", ""))
	var n := int(a.get("n", 0))
	var me := sim.human()
	match kind:
		"message":
			var text := String(a.get("text", ""))
			sim.emit_log(fill(sim, text), Color("e8d8a8"))
			sim.story.emit(String(a.get("title", "")), text)
			return
		"show_goal":
			var goals: Array = sim.mission.get("goals", [])
			var g := int(a.get("goal", 0))
			if g >= 0 and g < goals.size() and (goals[g] as Dictionary).get("hidden", false):
				(goals[g] as Dictionary).erase("hidden")
				sim.emit_log("New goal: %s" % String(goals[g].get("text", "")), Color("e8c870"))
			return
		"minutes":
			if float(sim.mission.get("minutes", 0)) > 0.0 and n != 0:
				sim.mission["minutes"] = maxf(1.0, float(sim.mission.minutes) + n)
				sim.emit_log(("The deadline moves %d minutes later." if n > 0 else "The deadline comes %d minutes sooner.") % absi(n), Color("e8c870"))
			return
		"win", "lose":
			sim.end_mission(kind == "win")
			return
	var who := int(a.get("who", 1 if kind in ["war", "peace", "ally", "attack", "landing"] else 0))
	for p: Sim.Player in realms(sim, who):
		if not p.alive:
			continue
		match kind:
			"war":
				if p.id != 1:
					Diplomacy.declare_war(sim, p.id, 1)
					p.script_war = true
					p.attack_t = minf(p.attack_t, 30.0)
			"peace":
				if p.id != 1:
					Diplomacy.drop_proposals(sim, p.id, 1)
					Diplomacy.set_relation(sim, p.id, 1, Diplomacy.PEACE)
					p.script_war = false
			"ally":
				if p.id != 1:
					Diplomacy.drop_proposals(sim, p.id, 1)
					Diplomacy.set_relation(sim, p.id, 1, Diplomacy.ALLY)
					p.script_war = false
			"attack":
				if p.id != 1:
					_attack(sim, p)
			"landing":
				if p.id != 1:
					_landing(sim, p, maxi(1, n if n > 0 else 12))
			"soldiers":
				_soldiers(p, n)
				if p == me and n > 0:
					sim.emit_log("%d soldiers join your realm." % n, Color("86ad5c"))
			"goods":
				var res := String(a.get("res", ""))
				if GameData.res_by_id.has(res) and n > 0:
					sim.give(p, res, float(n))
					if p == me:
						sim.emit_log("%d %s arrive in your stores." % [n, GameData.res_name(res).to_lower()], Color("86ad5c"))
			"tech":
				var id := String(a.get("id", ""))
				if GameData.techs.has(id) and not p.techs.has(id):
					sim.complete_tech(p, id)


## Soldiers waiting at the headquarters, of the realm's own age (like the campaign's veterans).
static func _soldiers(p: Sim.Player, n: int) -> void:
	if n <= 0:
		return
	p.reserve += n
	Sim.mix_fix(p.rmix, p.reserve, clampi(p.age, 0, Sim.KINDS - 1))


static func _war_on(sim: Sim, p: Sim.Player) -> void:
	if not Diplomacy.at_war(sim, p.id, 1):
		Diplomacy.declare_war(sim, p.id, 1)
	p.script_war = true


## A rival attacks now with what it can send, whatever its usual odds; if nothing of yours is in reach
## it attacks as soon as it can.
static func _attack(sim: Sim, p: Sim.Player) -> void:
	_war_on(sim, p)
	p.focus = maxf(p.focus, 1.0)
	var odds := p.odds
	p.odds = 0.5
	var went := sim.ai_attack(p)
	p.odds = odds
	if not went:
		p.attack_t = 0.0


## A rival's fleet carries n soldiers to your coast: given to it at its headquarters, with the ships it
## needs, then sent from its harbour to your military building nearest to it. A rival with no harbour,
## or no way by sea, sends them by land from its nearest military building in reach instead; with
## neither they wait at its headquarters and it attacks when it can.
static func _landing(sim: Sim, p: Sim.Player, n: int) -> void:
	_war_on(sim, p)
	n = mini(n, SimSea.LANDING_MAX)
	_soldiers(p, n)
	p.focus = maxf(p.focus, 1.0)
	var mine: Array = sim.mil_list().filter(func(b): return b.p == 1 and b.state == "ready" and not b.dead)
	for h: Sim.Bld in sim.sea.harbours(p):
		if sim.sea.stormy(h.x, h.y):
			continue
		mine.sort_custom(func(x, y): return _d2(x, h) < _d2(y, h) or (_d2(x, h) == _d2(y, h) and x.id < y.id))
		var need := ceili(float(n) / SimSea.LANDING_PER_SHIP)
		if sim.sea.free_ships(p) < need:
			p.ships += need - sim.sea.free_ships(p)
		for t: Sim.Bld in mine.slice(0, 4):
			if sim.military.launch_landing(h, t, n) == "":
				return
	# no way by sea: by land, from the rival's military building nearest one of yours
	var best: Array = []
	for s: Sim.Bld in sim.mil_list():
		if s.p != p.id or s.state != "ready" or s.dead:
			continue
		for t: Sim.Bld in mine:
			var d := _d2(s, t)
			if d <= Sim.RANGE * Sim.RANGE and (best.is_empty() or d < int(best[0]) or (d == int(best[0]) and s.id < (best[1] as Sim.Bld).id)):
				best = [d, s, t]
	if not best.is_empty():
		var s: Sim.Bld = best[1]
		var go := mini(n, p.reserve)
		if s.ty != "hq":
			# the soldiers walk over from the headquarters at once, as if they had been there all along
			sim.gmix_of(s)
			Sim.mix_add(s.gmix, Sim.mix_take_best(sim.rmix_of(p), go))
			p.reserve -= go
			s.garrison += go
		sim.military.launch_attack(s, best[2], go)
		return
	p.attack_t = 0.0


static func _d2(a: Sim.Bld, b: Sim.Bld) -> int:
	return (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)


# ---------------------------------------------------------------- words for the editor and the guide

static func who_text(who: int) -> String:
	if who == 0:
		return TranslationServer.translate("your realm")
	if who < 0:
		return TranslationServer.translate("any rival")
	return TranslationServer.translate("rival %d") % who


static func when_text(w: Dictionary) -> String:
	var who := who_text(int(w.get("who", 0)))
	var n := int(w.get("n", 1))
	var T := func(s: String) -> String: return TranslationServer.translate(s)
	match String(w.get("kind", "")):
		"start": return T.call("When the mission starts")
		"time": return T.call("At minute %d") % int(w.get("min", 0))
		"every": return T.call("Every %d minutes from minute %d") % [int(w.get("every", 0)), int(w.get("min", 0))]
		"after": return T.call("%d minutes after event %s") % [int(w.get("min", 0)), String(w.get("rule", "?"))]
		"age": return T.call("When %s reaches the %s Age") % [who, T.call(_age_name(int(w.get("age", 1))))]
		"tech": return T.call("When %s studies %s") % [who, GameData.tech_name(String(w.get("id", "")))]
		"pop": return T.call("When %s has %d people") % [who, n]
		"build": return T.call("When %s has %d: %s") % [who, n, String(GameData.bld.get(String(w.get("ty", "")), {}).get("name", w.get("ty", ""))).to_lower()]
		"soldiers": return T.call("When %s has %d soldiers") % [who, n]
		"land": return T.call("When %s holds %d tiles of land") % [who, n]
		"stock": return T.call("When %s has %d %s in store") % [who, n, GameData.res_name(String(w.get("res", ""))).to_lower()]
		"wonders": return T.call("When %s has %d wonders") % [who, n]
		"ships": return T.call("When %s has %d ships") % [who, n]
		"war": return T.call("When %s is at war with you") % who
		"fallen": return T.call("When %s falls") % who if int(w.get("who", -1)) >= 0 else T.call("When %d rival realms have fallen") % maxi(1, n)
		"goal": return T.call("When goal %d is reached") % (int(w.get("goal", 0)) + 1)
	return "?"


static func do_text(a: Dictionary) -> String:
	var kind := String(a.get("kind", ""))
	var who_i := int(a.get("who", 1 if kind in ["war", "peace", "ally", "attack", "landing"] else 0))
	var who: String = who_text(who_i) if who_i >= 0 else TranslationServer.translate("every rival")
	var n := int(a.get("n", 0))
	var T := func(s: String) -> String: return TranslationServer.translate(s)
	match kind:
		"message": return T.call("show \"%s\"") % String(a.get("text", "")).left(60)
		"war": return T.call("%s declares war") % who
		"peace": return T.call("%s makes peace") % who
		"ally": return T.call("%s becomes your ally") % who
		"attack": return T.call("%s attacks") % who
		"landing": return T.call("%s lands %d soldiers from the sea") % [who, n]
		"soldiers": return T.call("%s gets %d soldiers") % [who, n]
		"goods": return T.call("%s gets %d %s") % [who, n, GameData.res_name(String(a.get("res", ""))).to_lower()]
		"tech": return T.call("%s learns %s") % [who, GameData.tech_name(String(a.get("id", "")))]
		"show_goal": return T.call("goal %d is shown") % (int(a.get("goal", 0)) + 1)
		"minutes": return T.call("%d more minutes") % n
		"win": return T.call("the mission is won")
		"lose": return T.call("the mission is lost")
	return "?"


static func rule_text(r: Dictionary) -> String:
	var parts: Array = []
	for a in r.get("do", []):
		parts.append(do_text(a))
	return "%s: %s" % [when_text(r.get("when", {})), ", ".join(parts)]


static func _age_name(age: int) -> String:
	var ages: Array = GameData.ages
	return String(ages[clampi(age, 0, ages.size() - 1)]) if not ages.is_empty() else str(age)


## Problems a rule list has, for the editor and the data check: [] when it is fine.
static func problems(ms: Dictionary) -> Array:
	var out := []
	var ids := {}
	var rules: Array = ms.get("rules", [])
	for k in rules.size():
		ids[rule_id(rules[k], k)] = true
	var goals: Array = ms.get("goals", [])
	for k in rules.size():
		var r: Dictionary = rules[k]
		var w: Dictionary = r.get("when", {})
		var wk := String(w.get("kind", ""))
		if not WHEN.any(func(e): return e[0] == wk):
			out.append("event %d: unknown start \"%s\"" % [k + 1, wk])
		if wk == "after" and not ids.has(String(w.get("rule", ""))):
			out.append("event %d: no event \"%s\" to follow" % [k + 1, String(w.get("rule", ""))])
		if wk == "goal" and (int(w.get("goal", 0)) < 0 or int(w.get("goal", 0)) >= goals.size()):
			out.append("event %d: no goal %d" % [k + 1, int(w.get("goal", 0)) + 1])
		if (r.get("do", []) as Array).is_empty():
			out.append("event %d: does nothing" % (k + 1))
		for a in r.get("do", []):
			var ak := String(a.get("kind", ""))
			if not DO.any(func(e): return e[0] == ak):
				out.append("event %d: unknown action \"%s\"" % [k + 1, ak])
			if ak == "show_goal" and (int(a.get("goal", 0)) < 0 or int(a.get("goal", 0)) >= goals.size()):
				out.append("event %d: no goal %d to show" % [k + 1, int(a.get("goal", 0)) + 1])
	return out
