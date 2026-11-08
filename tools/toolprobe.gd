extends SceneTree
## An AI-only game: are realms held up by missing tools? Prints, every 10 minutes, each realm's size,
## buildings waiting for a tool, tools in stock, toolsmiths and research.
func _init() -> void:
	GameData.ensure()
	print("data errors: ", GameData.errors)
	var sim := Sim.new()
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a == "notools": opts["tools"] = false
	sim.new_game("tools", 5, 6, true, 0, true, opts)
	for p in sim.players: p.ai = true
	for m in [10, 20, 30, 40]:
		while sim.time < m * 60.0:
			sim.tick(Sim.TICK)
		print("--- minute %d" % m)
		for p in sim.players:
			var waiting := 0
			var smiths := 0
			for b in sim.realm_blds(p):
				if b.need_tool != "": waiting += 1
				if b.def.has("makes_tools") and b.state == "ready": smiths += 1
			var tools := 0
			for t in GameData.tool_ids: tools += int(p.stock.get(t, 0))
			print("%-9s pop=%3d bld=%3d waiting-for-tools=%2d tools=%3d toolsmiths=%d techs=%2d age=%d food=%d" % [p.name, sim.pop_total(p), sim.realm_blds(p).size(), waiting, tools, smiths, p.techs.size(), p.age, sim.food_total(p)])
	quit()
