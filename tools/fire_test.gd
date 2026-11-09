extends SceneTree
## Fires spread between wooden buildings and burn them down; wells nearby put them out:
## godot --headless --script res://tools/fire_test.gd
func _row(sim: Sim, me: Sim.Player, ty: String, n: int) -> Array:
	var out := []
	for r in range(3, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if out.size() < n and sim.can_place(ty, me.hq.x + dx, me.hq.y + dy, 1) == "":
					var b := sim.add_bld(ty, me.hq.x + dx, me.hq.y + dy, me, true, 0)
					out.append(b)
	return out

func _run(with_wells: bool) -> Array:
	var sim := Sim.new()
	sim.new_game("showcase", 1, 4, true)
	var me := sim.human()
	var f = sim.get_feature("fires")
	var houses := _row(sim, me, "woodcutter", 8)
	if with_wells:
		for w in _row(sim, me, "well", 3):
			w.staffed = true
	sim._rebuild_realm_lists()
	f.ignite(houses[0])
	var t0 := sim.time
	var most := 0
	while sim.time < t0 + 240.0:
		sim.tick(Sim.TICK)
		most = maxi(most, f.burning.size())
	var gone := 0
	for h in houses:
		if h.dead: gone += 1
	return [most, gone, f.burning.size()]

func _init() -> void:
	GameData.ensure()
	var ok := true
	var a := _run(false)
	var b := _run(true)
	print("no wells:   most burning at once %d, burned down %d of 8, still burning %d" % a)
	print("3 wells:    most burning at once %d, burned down %d of 8, still burning %d" % b)
	if int(a[1]) < 2: ok = false; print("FAIL: a fire left alone should spread and burn buildings down")
	if int(b[1]) >= int(a[1]): ok = false; print("FAIL: wells should save buildings")
	print("fire test: ", "ok" if ok else "FAILED")
	quit()
