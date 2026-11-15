extends SceneTree
## Weapons wear out in fights and are replaced from the stores; worn weapons fight worse:
## godot --headless --script res://tools/weapon_test.gd

## One attack of 8 on a tower of 6. blunt: defenders with worn weapons at the start; weapons: in store.
## Returns [defender won, worn after the fight, weapons used, worn 30 s later].
func _run(seed_n: int, blunt: int, weapons: float) -> Array:
	var sim := Sim.new()
	sim.new_game("weap%d" % seed_n, 1, 4, true)
	var me := sim.human()
	var foe := sim.players[1]
	var mx := me.hq.x; var my := me.hq.y
	var a := sim.add_bld("tower", mx + 2, my - 14, foe, true, 0)
	a.garrison = 9; a.gmix = [0, 9, 0, 0, 0, 0, 0]
	var d := sim.add_bld("tower", mx + 2, my - 2, me, true, 0)
	d.garrison = 6; d.gmix = [0, 6, 0, 0, 0, 0, 0]
	var have := float(me.stock.get("weapons", 0.0))
	sim.take(me, "weapons", have)
	sim.take(foe, "weapons", float(foe.stock.get("weapons", 0.0)))
	for i in 20: sim.tick(Sim.TICK)
	d.blunt = blunt
	sim.military.launch_attack(a, d, 8)
	var t0 := sim.time
	while sim.time < t0 + 90.0 and sim.attacks.size() > 0:
		sim.tick(Sim.TICK)
		d.blunt = maxi(d.blunt, mini(blunt, d.garrison)) if weapons < 0.0 else d.blunt
	var won := d.p == 1 and not d.dead
	var worn := d.blunt
	sim.give(me, "weapons", maxf(0.0, weapons))
	var before := float(me.stock.get("weapons", 0.0))
	for i in 30 * 10: sim.tick(Sim.TICK)
	return [won, worn, before - float(me.stock.get("weapons", 0.0)), d.blunt if won else -1, d.garrison if won else 0]

func _init() -> void:
	GameData.ensure()
	var ok := true
	var sharp := 0; var dull := 0; var worn_tot := 0; var fights := 0
	var used := 0.0; var left := 0
	var N := 30
	var left_sharp := 0; var left_dull := 0
	for s in N:
		var r := _run(s, 0, 10.0)
		if r[0]:
			sharp += 1
			worn_tot += int(r[1]); fights += 1
			used += float(r[2]); left += maxi(0, int(r[3]))
		left_sharp += int(r[4])
		var r2 := _run(s, 6, -1.0)   # every defender fights with a worn weapon the whole time
		if r2[0]: dull += 1
		left_dull += int(r2[4])
	print("defenders with sharp weapons won %d of %d (%.1f of 6 left); with worn weapons %d of %d (%.1f of 6 left)" % [sharp, N, left_sharp / float(N), dull, N, left_dull / float(N)])
	print("after a won fight: %.1f worn weapons on average; %.1f weapons taken from the stores; %d still worn 30 s later" % [float(worn_tot) / maxf(1, fights), used / maxf(1, fights), left])
	if worn_tot == 0:
		print("FAIL: no weapon wore out"); ok = false
	if used <= 0.0 or left > 0:
		print("FAIL: worn weapons were not replaced from the stores"); ok = false
	if left_dull >= left_sharp:
		print("FAIL: worn weapons do not fight worse"); ok = false
	print("WEAPON TEST: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
