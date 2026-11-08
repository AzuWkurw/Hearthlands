extends SceneTree
## How much of a new realm's land takes small, medium and large buildings: godot --headless --script res://tools/size_stats.gd
func _init() -> void:
	GameData.ensure()
	for seed in ["showcase", "alpha", "brook", "cedar"]:
		var sim := Sim.new()
		sim.new_game(seed, 3, 5, true)
		var c := {"": 0, "small": 0, "medium": 0, "large": 0, "mine": 0}
		var free := 0
		var slope_fail := 0
		for i in sim.owner.size():
			if sim.owner[i] != 1: continue
			var s := sim.site_size(i % sim.w, i / sim.w, 1)
			c[s] += 1
			if sim.ter[i] == Sim.GRASS and sim.deco[i] == 0 and sim.bmap[i] == 0 and sim.plot[i] == 0:
				free += 1
				if s == "medium" and sim.plot_check("large", i % sim.w, i / sim.w, 1).begins_with("Too steep"): slope_fail += 1
		print("%s: free grass %d -> large %d, medium %d, small %d, none %d (large blocked only by slope: %d)" % [seed, free, c.large, c.medium, c.small, c[""], slope_fail])
	quit()
