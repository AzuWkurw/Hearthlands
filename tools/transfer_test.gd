extends SceneTree
## Goods move between stores: godot --headless --script res://tools/transfer_test.gd
func total(s: Sim.Bld) -> int:
	var n := 0.0
	for k in s.inv: n += float(s.inv[k])
	return int(n)

func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 1, 1, false, 0, true, {"creative": false, "all_research": true})
	var me := sim.human()
	for i in 20: sim.tick(Sim.TICK)
	var spot := Vector2i(-1, -1)
	for r in range(6, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if spot.x < 0 and absi(dx) + absi(dy) >= 6 and sim.can_place("storehouse", me.hq.x + dx, me.hq.y + dy, 1) == "":
					spot = Vector2i(me.hq.x + dx, me.hq.y + dy)
	print("storehouse: ", sim.place("storehouse", spot.x, spot.y, me))
	var st := sim.bld_at(spot.x, spot.y)
	while st.state != "ready" and sim.time < 600.0: sim.tick(Sim.TICK)
	print("built at %d s; HQ %d goods, storehouse %d" % [int(sim.time), total(me.hq), total(st)])
	me.hq.policy = 2
	var t0 := sim.time
	while sim.time - t0 < 180.0: sim.tick(Sim.TICK)
	print("after 3 min with the HQ sending away: HQ %d goods, storehouse %d" % [total(me.hq), total(st)])
	var moved := total(st) > 15
	me.hq.policy = 0
	st.policy = 2
	var before := total(st)
	t0 = sim.time
	while sim.time - t0 < 120.0: sim.tick(Sim.TICK)
	print("then the storehouse sending away for 2 min: storehouse %d -> %d" % [before, total(st)])
	var back := total(st) < before
	var m: String = sim.logistics.stock_matches()
	print("stock = stores: ", "yes" if m == "" else m)
	print("transfer test: ", "ok" if moved and back and m == "" else "FAILED")
	quit()
