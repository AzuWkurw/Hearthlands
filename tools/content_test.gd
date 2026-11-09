extends SceneTree
## Taverns, chapels, contentment and festivals: godot --headless --script res://tools/content_test.gd
func _spot(sim: Sim, ty: String, me: Sim.Player) -> Sim.Bld:
	for r in range(3, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if sim.can_place(ty, me.hq.x + dx, me.hq.y + dy, 1) == "" and sim.place(ty, me.hq.x + dx, me.hq.y + dy, me) == "":
					return sim.blds[sim.blds.size() - 1]
	return null

func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 1, 4, true)
	var me := sim.human()
	var f = sim.get_feature("contentment")
	var ok := f != null
	for i in 30: sim.tick(Sim.TICK)
	print("contentment at the start: ", f.mood(me))
	if absf(f.mood(me) - 0.5) > 0.01: ok = false; print("FAIL: should start at half")
	var tav := _spot(sim, "tavern", me)
	var house := _spot(sim, "house", me)
	sim.give(me, "beer", 40.0); sim.give(me, "bread", 40.0)
	var t0 := sim.time
	while sim.time < t0 + 400.0 and not f.served.has(tav.id): sim.tick(Sim.TICK)
	for i in 60: sim.tick(Sim.TICK)
	print("tavern staffed ", tav.staffed, ", served ", f.served.has(tav.id), ", cover ", f.cover.get(1), ", contentment ", f.mood(me), ", work bonus ", f.speed_bonus(me, tav))
	if f.mood(me) <= 0.55: ok = false; print("FAIL: a working tavern should raise it")
	f.next_fest[1] = 0.0
	sim.give(me, "beer", 40.0); sim.give(me, "bread", 40.0)
	for i in 30: sim.tick(Sim.TICK)
	print("festival: ", f.in_festival(me), ", bonus ", f.speed_bonus(me, tav))
	if not f.in_festival(me): ok = false; print("FAIL: a festival should start")
	print("content test: ", "ok" if ok else "FAILED")
	quit()
