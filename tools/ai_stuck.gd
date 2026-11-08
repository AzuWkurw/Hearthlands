extends SceneTree
## Why a rival stops building: godot --headless --script res://tools/ai_stuck.gd [-- who=1 mins=20]
func _init() -> void:
	GameData.ensure()
	var who := 1; var mins := 20; var seed := "valley"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("who="): who = int(a.substr(4))
		if a.begins_with("mins="): mins = int(a.substr(5))
		if a.begins_with("seed="): seed = a.substr(5)
	var sim := Sim.new()
	sim.new_game(seed, 7, 6, true)
	while sim.time < mins * 60.0: sim.tick(Sim.TICK)
	sim.ai.stats = {}
	var p := sim.players[who]
	var land := 0
	for o in sim.owner: if o == p.id: land += 1
	var mil := []
	var cnt := {}
	for b in sim.blds:
		if b.p != p.id: continue
		cnt[b.ty] = int(cnt.get(b.ty, 0)) + 1
		if b.def.has("garrison"): mil.append("%s g%d w%d want%d %s" % [b.ty, b.garrison, b.walking, b.want_n, "road" if sim.connected(b) else "NO ROAD"])
	print(p.name, ": pers ", p.pers, " land ", land, " reserve ", p.reserve, " artisans ", p.artisan, " (used ", p.used_artisan, ") weapons ", int(p.stock.get("weapons", 0)), " planks ", int(p.stock.planks), " stone ", int(p.stock.stone))
	print("military: ", mil)
	print("buildings: ", cnt)
	var free := {"small": 0, "medium": 0, "large": 0}
	for i in sim.owned(p.id)[0]:
		var s := sim.site_size(i % sim.w, i / sim.w, p.id)
		if free.has(s): free[s] += 1
	print("free spots: ", free)
	for ty in ["storehouse", "house", "hut", "guardhouse", "barracks", "woodcutter"]:
		print(ty, ": ", sim.ai._ai_build(p, ty))
	print(sim.ai.stats)
	quit()
