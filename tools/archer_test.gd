extends SceneTree
## Archers shoot attackers on the way in, take bows from the stores; sallies meet attacks in the open:
## godot --headless --script res://tools/archer_test.gd
func _hut(sim: Sim, p: Sim.Player, x: int, y: int, n: int) -> Sim.Bld:
	var b := sim.add_bld("tower", x, y, p, true, 0)
	b.garrison = n; b.gmix = [n, 0, 0, 0, 0, 0]
	return b

func _run(archers: int, sally: bool, luck := 0) -> Array:
	var sim := Sim.new()
	sim.new_game("showcase", 1, 4, true)
	if luck > 0:
		sim.rng.seed = 7919 * luck
	var me := sim.human()
	var foe := sim.players[1]
	var mx := me.hq.x; var my := me.hq.y
	# two towers 12 tiles apart in open land (outside everyone's land is fine for the test)
	var a := _hut(sim, foe, mx + 2, my - 14, 9)
	var d := _hut(sim, me, mx + 2, my - 2, 6)
	sim.give(me, "bows", 10.0)
	d.archer_want = archers
	d.sally = sally
	for i in 80: sim.tick(Sim.TICK)
	var had_bows := d.archers
	var why := sim.military.launch_attack(a, d, 8)
	var t0 := sim.time
	var killed_on_way := 0
	var at_gate := -1
	while sim.time < t0 + 60.0 and sim.attacks.size() > 0:
		sim.tick(Sim.TICK)
		for at in sim.attacks:
			if at.p == 2 and at.fighting and at_gate < 0: at_gate = at.n
	return [had_bows, why, d.garrison, d.dead or d.p != 1, a.garrison, at_gate]

func _init() -> void:
	GameData.ensure()
	var ok := true
	var r0 := _run(0, false)
	var r1 := _run(4, false)
	var r2 := _run(0, true)
	print("no archers:   archers %d, attack '%s', attackers reaching the gate %d of 8, defenders left %d, lost %s" % [r0[0], r0[1], r0[5], r0[2], r0[3]])
	print("archers:      archers %d, attack '%s', attackers reaching the gate %d of 8, defenders left %d, lost %s" % [r1[0], r1[1], r1[5], r1[2], r1[3]])
	# a single fight is down to luck: compare the attackers reaching the gate over a few of them
	var g0 := int(r0[5])
	var g1 := int(r1[5])
	for k in range(1, 4):
		g0 += int(_run(0, false, k)[5])
		g1 += int(_run(4, false, k)[5])
	print("over 4 fights: attackers reaching the gate %d without archers, %d with" % [g0, g1])
	if g1 >= g0: ok = false; print("FAIL: archers should thin the attack on its way in")
	print("march out:    attack '%s', defenders left %d, lost %s, attackers' tower now %d" % [r2[1], r2[2], r2[3], r2[4]])
	if int(r1[0]) != 2: ok = false; print("FAIL: a tower of 4 should hold 2 archers (half its soldiers, extra to them)")
	print("archer test: ", "ok" if ok else "FAILED")
	quit()
