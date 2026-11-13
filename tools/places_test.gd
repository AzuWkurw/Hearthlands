extends SceneTree
## Ruins and bandit camps on a hand-made map: the ruins are looted by the realm whose land reaches them,
## nothing is built near a camp, the bandits steal from a realm nearby, soldiers sent from the
## headquarters clear the camp and take its gold, and the places are kept in a saved game:
## godot --headless --script res://tools/places_test.gd

func _spot(g: Dictionary, s: Vector2i, dmin: float, dmax: float) -> Vector2i:
	for r in 400:
		var a := r * 0.37
		var d := dmin + fmod(r * 0.61, dmax - dmin)
		var p := s + Vector2i(roundi(cos(a) * d), roundi(sin(a) * d))
		if p.x < 3 or p.y < 3 or p.x >= int(g.w) - 3 or p.y >= int(g.h) - 3:
			continue
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if (g.ter as PackedByteArray)[(p.y + dy) * int(g.w) + p.x + dx] != Sim.GRASS:
					ok = false
		if ok:
			return p
	return Vector2i(-1, -1)


func _init() -> void:
	GameData.ensure()
	var ok := true
	var g := WorldGen.generate("places", 1, 128)
	var s0: Vector2i = g.starts[0]
	var m := {"name": "t", "w": g.w, "h": g.h, "seed": "places", "starts": g.starts}
	for k in WorldGen.MAP_KEYS:
		m[k] = (g[k] as PackedByteArray).duplicate()
	var ruin := _spot(g, s0, 4.0, 6.0)
	var camp := _spot(g, s0, 8.0, 10.0)
	m["places"] = [["ruins", ruin.x, ruin.y], ["bandits", camp.x, camp.y]]
	print("ruins at %s, camp at %s, headquarters at %s" % [ruin, camp, s0])
	if ruin.x < 0 or camp.x < 0: print("FAIL: no room for the places"); quit(1); return
	var sim := Sim.new()
	sim.new_game("places", 1, 4, false, 0, false, {}, m)
	var me := sim.human()
	var ruins: Dictionary = sim.places[0]
	var bandits: Dictionary = sim.places[1]
	var planks0 := float(me.stock.get("planks", 0.0))
	var gold0 := float(me.stock.get("gold", 0.0))
	for k in 3:
		sim.tick(1.0)
	print("ruins looted: %s; planks %d -> %d" % [ruins.done, int(planks0), int(me.stock.get("planks", 0.0))])
	if not bool(ruins.done) or float(me.stock.get("planks", 0.0)) <= planks0: ok = false; print("FAIL: looting the ruins")
	# nothing is built right by the camp
	var why := Places.block(sim, camp.x + 1, camp.y)
	var near := Vector2i(-1, -1)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if dx * dx + dy * dy <= 9 and sim.inb(camp.x + dx, camp.y + dy) and sim.owner[sim.idx(camp.x + dx, camp.y + dy)] == me.id:
				near = Vector2i(camp.x + dx, camp.y + dy)
	if near.x >= 0:
		why = sim.can_place("woodcutter", near.x, near.y, 1)
	print("building next to the camp (at %s, your land): '%s'" % [near, why])
	if not why.contains("bandit"): ok = false; print("FAIL: the camp should stop building next to it")
	# a raid takes goods from the realm nearby
	for r in ["bread", "fish", "meat", "planks", "stone", "beer"]:
		if me.stock.has(r):
			sim.give(me, r, 10.0, sim.idx(me.hq.x, me.hq.y))
	var total0 := 0.0
	for r in ["bread", "fish", "meat", "planks", "stone", "beer"]:
		total0 += float(me.stock.get(r, 0.0))
	bandits.raid_t = 0.0
	sim.tick(1.0)
	var total1 := 0.0
	for r in ["bread", "fish", "meat", "planks", "stone", "beer"]:
		total1 += float(me.stock.get(r, 0.0))
	print("goods before the raid %d, after %d" % [int(total0), int(total1)])
	if total1 >= total0: ok = false; print("FAIL: the bandits' raid")
	# soldiers from the headquarters clear it
	me.reserve += 20
	var err := Places.send(sim, me, bandits)
	print("sent: '%s', party %s" % [err, str(bandits.party.get("n", 0))])
	if err != "": ok = false; print("FAIL: sending soldiers")
	# saved and loaded on the way
	var sim2 := Sim.new()
	var e2 := sim2.from_save(sim.to_save())
	print("loaded: '%s', places %d, party on its way %s" % [e2, sim2.places.size(), not (sim2.places[1].party as Dictionary).is_empty()])
	if sim2.places.size() != 2 or (sim2.places[1].party as Dictionary).is_empty(): ok = false; print("FAIL: places in a saved game")
	for k in 40:
		sim.tick(1.0)
	print("camp cleared: %s, bandits left %d, gold %d -> %d, soldiers home %d" % [bandits.done, int(bandits.n), int(gold0), int(me.stock.get("gold", 0.0)), me.reserve])
	if not bool(bandits.done) or float(me.stock.get("gold", 0.0)) < gold0 + Places.CAMP_LOOT.gold: ok = false; print("FAIL: clearing the camp")
	print("can build there now: '%s'" % sim.can_place("woodcutter", camp.x + 1, camp.y, 1))
	print("PLACES TEST: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
