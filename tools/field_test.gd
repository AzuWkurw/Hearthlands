extends SceneTree
## Columns that meet on the march fight in the open: godot --headless --script res://tools/field_test.gd
func _col(sim: Sim, p: int, k: int, n: int, from: Vector2, to: Vector2, tgt: int) -> Sim.Attack:
	var a := Sim.Attack.new()
	a.p = p; a.src = 0; a.tgt = tgt; a.n = n
	a.amix = [0, 0, 0, 0, 0, 0]; a.amix[k] = n; a.era = float(k)
	a.from = from; a.to = to; a.t0 = sim.time; a.t1 = sim.time + from.distance_to(to) * 1.1 + 1.0
	a.vt = [sim.time, sim.time]; a.dvt = [sim.time, sim.time]
	sim._bid += 1; a.uid = sim._bid
	sim.attacks.append(a)
	return a

func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("field", 1, 5, false, 0, true, {"features": []})
	Diplomacy.set_relation(sim, 1, 2, Diplomacy.WAR)
	var p1 := sim.players[0]; var p2 := sim.players[1]
	var K := ["legion", "spear", "m-at-a", "pike", "musket", "rifle"]
	for c in [[3, 6, 4, 4], [4, 4, 3, 6], [2, 5, 3, 5], [5, 3, 3, 6], [1, 5, 1, 5]]:
		var wins := 0; var left := 0; var met := 0
		for r in 60:
			# far-off targets so neither column arrives during the test
			var a := _col(sim, 1, c[0], c[1], Vector2(10, 40), Vector2(60, 40), p2.hq.id)
			var b := _col(sim, 2, c[2], c[3], Vector2(50, 40), Vector2(0, 40), p1.hq.id)
			var g := 0
			while a.n > 0 and b.n > 0 and g < 900:
				sim.time += 0.1
				sim.military._field_battles(0.1)
				g += 1
			if a.field == 0 and b.field == 0 and (a.n <= 0 or b.n <= 0): met += 1
			if a.n > 0 and b.n <= 0:
				wins += 1; left += a.n
			sim.attacks.clear()
		print("%d %-7s v %d %-7s  first side wins %3d%%, %.1f left on average" % [c[1], K[c[0]], c[3], K[c[2]], roundi(100.0 * wins / 60), left / maxf(1.0, wins)])
	# a real attack: still gets to its target after winning
	var a2 := sim.launch_attack(p1.hq, p2.hq)
	print("launch: '", a2, "'")
	sim.dispose(); quit()
