extends SceneTree
## New-game options: all research done, creative mode; and how steep the land is:
## godot --headless --script res://tools/options_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("opts", 2, 5, false, 0, true, {"all_research": true, "creative": true})
	var p := sim.human()
	print("all research: techs %d of %d, age %s, HQ style %d, rival techs %d" % [p.techs.size(), GameData.techs.size(), GameData.age_name(p.age), p.hq.era, sim.players[1].techs.size()])
	# creative: place a building (no road needed nearby? it builds its own) and see it stand at once
	var placed := ""
	for y in range(p.hq.y - 6, p.hq.y + 7):
		for x in range(p.hq.x - 6, p.hq.x + 7):
			if placed == "" and sim.can_place("house", x, y, p.id) == "":
				var r := sim.place("house", x, y, p)
				if r == "": placed = "%d,%d" % [x, y]
	var b: Sim.Bld = null
	for o in sim.blds:
		if o.ty == "house" and o.p == 1: b = o
	for i in 3: sim.tick(Sim.TICK)
	print("house placed at %s: state %s, materials %d" % [placed, b.state if b != null else "-", b.mat_total if b != null else -1])
	p.stock["gold"] = 0.0
	for i in 15: sim.tick(Sim.TICK)
	print("creative stores: gold %d of %d" % [int(p.stock.gold), int(sim.capacity(p, "gold"))])
	sim.dispose()
	quit()
