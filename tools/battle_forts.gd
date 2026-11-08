extends SceneTree
## Forts: the same attack on each military building (walls and cannon).
## Battles between kinds of soldier: an attack of A soldiers of one kind on a hut held by D of another,
## repeated many times, prints how often the attackers take it and how many fall on each side.
## Run: godot --headless --script res://tools/battle_test.gd
const K := ["legion", "spear", "m-at-a", "pike", "musket", "rifle"]

func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("battle", 1, 5, false, 0, true, {"features": []})
	var a_p := sim.players[0]
	var d_p := sim.players[1]
	Diplomacy.set_relation(sim, 1, 2, Diplomacy.WAR)
	# an empty spot far from the defender's headquarters for the hut
	var spot := Vector2i(-1, -1)
	for y in sim.h:
		for x in sim.w:
			if spot.x < 0 and sim.ter[sim.idx(x, y)] == Sim.GRASS and sim.bmap[sim.idx(x, y)] == 0 and Vector2(x - d_p.hq.x, y - d_p.hq.y).length() > 14 and Vector2(x - a_p.hq.x, y - a_p.hq.y).length() > 14:
				spot = Vector2i(x, y)
	var cases := []
	for ty in ["hut", "palisade", "guardhouse", "tower", "keep", "battery", "bastion", "redoubt"]:
		cases.append([4, 10, 4, 4, "10 musketeers v 4 in " + ty, ty])
	for c in cases:
		var wins := 0
		var lost_a := 0
		var lost_d := 0
		var runs := 60
		for r in runs:
			var hut := sim.add_bld(String(c[5]), spot.x, spot.y, d_p, true)
			hut.garrison = int(c[3])
			hut.gmix = [0, 0, 0, 0, 0, 0]
			hut.gmix[int(c[2])] = int(c[3])
			var at := Sim.Attack.new()
			at.p = 1; at.src = a_p.hq.id; at.tgt = hut.id; at.n = int(c[1])
			at.amix = [0, 0, 0, 0, 0, 0]
			at.amix[int(c[0])] = int(c[1])
			at.era = float(c[0])
			at.from = Vector2(spot.x - 9, spot.y); at.to = Vector2(spot.x, spot.y)
			at.t0 = sim.time; at.t1 = sim.time + 10.0; at.vt = [sim.time, sim.time]; at.dvt = [sim.time, sim.time]
			sim.attacks.append(at)
			var guard := 0
			while sim.attacks.has(at) and guard < 2000:
				sim.time += 0.1
				sim.military.attack_tick(0.1)
				guard += 1
			if hut.p == 1:
				wins += 1
			lost_a += int(c[1]) - (sim.players[0].reserve * 0 + (at.n if hut.p == 1 else 0))
			lost_d += int(c[3]) - (hut.garrison if hut.p == 2 else 0)
			sim.destroy(hut)
			a_p.reserve = 8; a_p.rmix = []
		print("%-26s attackers take it %3d%%   (%d of %d)" % [c[4], roundi(100.0 * wins / runs), wins, runs])
	sim.dispose()
	quit()
