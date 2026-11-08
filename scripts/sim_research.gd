class_name SimResearch
extends RefCounted
## Research points, techs and the ages.
## Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `sim`.

var sim: Sim

const AI_TECHS_PER_AGE := 12     # techs a computer realm studies in an age before it aims for the next



func _init(p_sim: Sim) -> void:
	sim = p_sim


func mod(p: Sim.Player, key: String) -> float:
	return float(p.mods.get(key, 0.0))


func tech_available(p: Sim.Player, id: String) -> bool:
	if not sim.tech_enabled(id):
		return false
	if GameData.reps.has(id):
		# a repeatable study: open from its age on, up to its number of levels
		var r: Dictionary = GameData.reps[id]
		return p.age >= int(r.get("age", 0)) and int(p.reps.get(id, 0)) < int(r.get("max", 1))
	if p.techs.has(id) or not GameData.techs.has(id):
		return false
	for r in GameData.techs[id].get("requires", []):
		if not p.techs.has(r):
			return false
	return true


func set_research(p: Sim.Player, id: String) -> void:
	if id == "" or tech_available(p, id):
		# what was being studied goes back to the front of the queue (points are kept either way)
		if p.research != "" and p.research != id and id != "":
			p.rqueue.push_front(p.research)
		# studying a queued tech takes it off the queue (one level, for a repeatable)
		var k := p.rqueue.find(id)
		if k >= 0:
			p.rqueue.remove_at(k)
		p.research = id


## Points the next study of id costs. ahead: levels of the same repeatable already ahead of it in
## the queue (each level costs more).
func cost(p: Sim.Player, id: String, ahead := 0) -> float:
	if GameData.reps.has(id):
		return GameData.rep_cost(id, int(p.reps.get(id, 0)) + ahead)
	return float(GameData.techs[id].cost) if GameData.techs.has(id) else 0.0


## Levels of repeatable id that are planned: being studied or queued.
func planned(p: Sim.Player, id: String) -> int:
	var n := 1 if p.research == id else 0
	for q in p.rqueue:
		if q == id:
			n += 1
	return n


## Adds id to the end of the research queue (starts it if nothing is being studied).
## Returns how many entries were added (0 if it can't be: done, or every level already planned).
func queue_add(p: Sim.Player, id: String) -> int:
	if GameData.reps.has(id):
		var r: Dictionary = GameData.reps[id]
		if int(p.reps.get(id, 0)) + planned(p, id) >= int(r.get("max", 1)):
			return 0
	elif not GameData.techs.has(id) or p.techs.has(id) or p.research == id or p.rqueue.has(id):
		return 0
	p.rqueue.append(id)
	_start_next(p)
	return 1


## Takes entry i off the queue (-1: the study under way). Anything queued that needs a tech taken
## off goes too.
func queue_remove(p: Sim.Player, i: int) -> void:
	var id := ""
	if i < 0:
		id = p.research
		p.research = ""
	elif i < p.rqueue.size():
		id = String(p.rqueue[i])
		p.rqueue.remove_at(i)
	if id == "":
		return
	if GameData.techs.has(id):
		var gone := {id: true}
		var keep := []
		for q in p.rqueue:
			var needs_gone := false
			if GameData.techs.has(q):
				for r in GameData.techs[q].get("requires", []):
					if gone.has(r):
						needs_gone = true
			if needs_gone:
				gone[q] = true
			else:
				keep.append(q)
		p.rqueue = keep
	if i < 0:
		_start_next(p)


## The techs still to study to reach id, in an order that can be studied (id last).
func path_to(p: Sim.Player, id: String) -> Array:
	if GameData.reps.has(id):
		return [id]
	var out := []
	var seen := {}
	var walk := func(x: String, f: Callable) -> void:
		if seen.has(x) or p.techs.has(x) or not GameData.techs.has(x):
			return
		seen[x] = true
		for r in GameData.techs[x].get("requires", []):
			f.call(String(r), f)
		out.append(x)
	walk.call(id, walk)
	return out


## When nothing is being studied, starts the first queued study that can be studied now; entries that
## can never be studied (already done, or past their levels) are dropped.
func _start_next(p: Sim.Player) -> void:
	if p.research != "" and tech_available(p, p.research):
		return
	p.research = ""
	var i := 0
	while i < p.rqueue.size():
		var q := String(p.rqueue[i])
		var dead := p.techs.has(q) or not (GameData.techs.has(q) or GameData.reps.has(q))
		if GameData.reps.has(q) and int(p.reps.get(q, 0)) >= int(GameData.reps[q].get("max", 1)):
			dead = true
		if dead:
			p.rqueue.remove_at(i)
			continue
		if tech_available(p, q):
			p.research = q
			p.rqueue.remove_at(i)
			return
		i += 1


func _recompute_mods(p: Sim.Player) -> void:
	sim._type_bonus.erase(p.id)
	p.mods = {}
	p.age = 0
	for id in p.techs:
		var t: Dictionary = GameData.techs.get(id, {})
		p.age = maxi(p.age, int(t.get("age", 0)))
		var eff: Dictionary = t.get("effects", {})
		for k in eff:
			p.mods[k] = float(p.mods.get(k, 0.0)) + float(eff[k])
	# repeatable studies: their effects once per level
	for id in p.reps:
		var r: Dictionary = GameData.reps.get(id, {})
		var lv := float(p.reps[id])
		for k in r.get("effects", {}):
			p.mods[k] = float(p.mods.get(k, 0.0)) + float(r.effects[k]) * lv


## A level of repeatable study id is done.
func complete_rep(p: Sim.Player, id: String) -> void:
	p.reps[id] = int(p.reps.get(id, 0)) + 1
	_recompute_mods(p)
	if p.research == id:
		p.research = ""
	if not p.ai:
		var r: Dictionary = GameData.reps[id]
		sim.emit_log("Research complete: %s, level %d of %d." % [String(r.name), int(p.reps[id]), int(r.get("max", 1))], Color("8fc0ff"))
	_start_next(p)
	sim.tech_done.emit(p.id, id)


func complete_tech(p: Sim.Player, id: String) -> void:
	p.techs[id] = true
	var old_age := p.age
	_recompute_mods(p)
	if p.research == id:
		p.research = ""
	_start_next(p)
	var t: Dictionary = GameData.techs[id]
	if not p.ai:
		sim.emit_log("Research complete: %s." % String(t.name), Color("8fc0ff"))
		if p.age > old_age:
			sim.emit_log("Your realm enters the %s age." % GameData.age_name(p.age), Color("8fc0ff"))
	elif p.age > old_age and p.age >= 3:
		sim.emit_log("%s has reached the %s age." % [p.name, GameData.age_name(p.age)], Color("c0a0e0"))
	sim.tech_done.emit(p.id, id)
	if t.get("final", false) and sim.research_victory and not sim.over:
		sim.over = true
		if p.id == 1 or Diplomacy.relation(sim, p.id, 1) == Diplomacy.ALLY:
			sim.emit_log("Your realm leads the world into the Industrial Revolution!" if p.id == 1 else "Your ally %s reached the Industrial Revolution. Shared victory!" % p.name, Color("d8aa4a"))
			sim.ended.emit(true)
		else:
			sim.emit_log("%s reached the Industrial Revolution first." % p.name, Color("e0603a"))
			sim.ended.emit(false)


func _research_tick(p: Sim.Player) -> void:
	var base := (0.15 + 0.03 * p.noble) * (1.0 + mod(p, "research")) * float(sim.opts.research)
	p.rp += base
	p.rp_total += base
	if p.research != "" and not tech_available(p, p.research):
		p.research = ""
	if p.research == "" and not p.rqueue.is_empty():
		_start_next(p)
	if p.ai and p.research == "":
		p.research = _ai_pick_tech(p)
	if p.research != "" and tech_available(p, p.research):
		var c := cost(p, p.research)
		if p.rp >= c:
			p.rp -= c
			if GameData.reps.has(p.research):
				complete_rep(p, p.research)
			else:
				complete_tech(p, p.research)


func _ai_pick_tech(p: Sim.Player) -> String:
	var best := ""
	var best_sc := 1e9
	# how far into its age the realm is: after a handful of techs it aims for the next age, as a player
	# would, instead of buying every cheap tech of the age first
	var in_age := 0
	var next_open := false
	for id in p.techs:
		if int(GameData.techs.get(id, {}).get("age", 0)) == p.age:
			in_age += 1
	for id in GameData.techs:
		if int(GameData.techs[id].get("age", 0)) > p.age and tech_available(p, id):
			next_open = true
			break
	var push := p.age >= 1 and in_age >= AI_TECHS_PER_AGE and next_open
	for id in GameData.techs:
		if not tech_available(p, id):
			continue
		var t: Dictionary = GameData.techs[id]
		var eff: Dictionary = t.get("effects", {})
		var sc := float(t.cost) * sim.rng.randf_range(0.85, 1.15)
		var military := eff.has("attack") or eff.has("defense") or eff.has("speed:barracks")
		if p.pers == "warlord" and military: sc *= 0.6
		if p.pers == "builder" and (eff.has("research") or eff.has("speed:all") or eff.has("speed:farm")): sc *= 0.7
		if t.get("final", false): sc *= 0.5
		if int(t.get("age", 0)) > p.age: sc *= 0.3 if push else 0.85
		if sc < best_sc:
			best_sc = sc; best = id
	# repeatable studies: worth it once the cheap techs of the age are gone (they cost more for less)
	for id in GameData.reps:
		if not tech_available(p, id):
			continue
		var r: Dictionary = GameData.reps[id]
		var reff: Dictionary = r.get("effects", {})
		var rsc := cost(p, id) * 1.6 * sim.rng.randf_range(0.85, 1.15)
		if next_open and p.age < GameData.ages.size() - 1: rsc *= 2.5     # the next age first
		if p.pers == "warlord" and (reff.has("attack") or reff.has("defense")): rsc *= 0.7
		if p.pers == "builder" and (reff.has("speed:all") or reff.has("research")): rsc *= 0.8
		if rsc < best_sc:
			best_sc = rsc; best = id
	return best
