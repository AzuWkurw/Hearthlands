extends SceneTree
## Builders and soldiers walk to their buildings: godot --headless --script res://tools/walk_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 2, 4, true)
	var me := sim.human()
	for i in 50: sim.tick(Sim.TICK)
	# a guard hut a fair way from headquarters
	var spot := Vector2i(-1, -1)
	var bd := 0.0
	for i in sim.owner.size():
		if sim.owner[i] != 1: continue
		var x := i % sim.w; var y := i / sim.w
		var d := Vector2(x - me.hq.x, y - me.hq.y).length()
		if d > bd and d < 8.5 and sim.can_place("hut", x, y, 1) == "":
			var test := sim._path_to_net(x, y, 1)
			if test.size() > 1: bd = d; spot = Vector2i(x, y)
	var land0 := 0
	for o in sim.owner: if o == 1: land0 += 1
	print("hut at ", spot, " (", snappedf(bd, 0.1), " tiles from HQ): ", sim.place("hut", spot.x, spot.y, me))
	var b := sim.bld_at(spot.x, spot.y)
	var t0 := sim.time
	var seen := {}
	var walkers_seen := 0
	while sim.time - t0 < 240.0:
		sim.tick(Sim.TICK)
		for t in sim.trips:
			if (t.kind == "builder" or t.kind == "soldier") and t.site == b.id: walkers_seen += 1
		var st := "%s/%d/%s/g%d w%d" % [b.state, b.builder, b.msg, b.garrison, b.walking]
		if not seen.has(st):
			seen[st] = true
			print("  t+%5.1f  state %s, builder %d, '%s', garrison %d, soldiers walking %d" % [sim.time - t0, b.state, b.builder, b.msg, b.garrison, b.walking])
		if b.garrison > 0: break
	var land1 := 0
	for o in sim.owner: if o == 1: land1 += 1
	print("land %d -> %d, walker ticks %d, reserve %d" % [land0, land1, walkers_seen, me.reserve])
	quit()
