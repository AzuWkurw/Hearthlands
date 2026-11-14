extends SceneTree
## A mule station can be upgraded to an ox cart yard where it stands, once ox carts are studied:
## godot --headless --script res://tools/station_upgrade_test.gd
func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("stations", 1, 4, true)
	for i in 5: sim.tick(Sim.TICK)
	var me := sim.human()
	for k in ["planks", "stone", "grain"]:
		sim.give(me, k, 60.0)
	var b := sim.add_bld("mule_station", me.hq.x + 4, me.hq.y + 4, me, false, 0)
	sim.production._finish_site(b, me)
	var id := b.id
	var dt := sim.door_tile(b)
	print("road: '%s'" % sim.build_road(b.x, b.y, me.hq.x, me.hq.y, 1))
	for i in 30: sim.tick(Sim.TICK)
	print("before ox carts: ", sim.upgrades_of(b), " '", sim.upgrade(b, "cart_yard"), "'")
	if not sim.upgrades_of(b).is_empty(): ok = false; print("FAIL: no upgrade without ox carts")
	sim.complete_tech(me, "ox_carts")
	print("after ox carts: ", sim.upgrades_of(b), " costs ", sim.upgrade_cost(b, "cart_yard"))
	if sim.upgrades_of(b) != ["cart_yard"]: ok = false; print("FAIL: the cart yard upgrade")
	var why := sim.upgrade(b, "cart_yard")
	print("upgrade: '%s', upgrading to %s" % [why, b.upg])
	if why != "": ok = false
	var t0 := sim.time
	while b.upg != "" and sim.time - t0 < 600.0:
		sim.tick(Sim.TICK)
	print("after %d s: %s (same building %s), carriers %s" % [int(sim.time - t0), b.ty, sim.by_id.get(id) == b, b.def.get("carriers", {})])
	if b.ty != "cart_yard" or sim.by_id.get(id) != b: ok = false; print("FAIL: it became an ox cart yard where it stands")
	print("STATION UPGRADE TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
