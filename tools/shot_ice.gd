extends SceneTree
## River ice (build 78): a frozen river in deep winter with an ice road over it and a column marching
## across, then the same river just before the thaw.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_ice.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 1, 4, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	var foe := sim.players[1]
	main.log_ui.set_open(false)
	var hx := me.hq.x
	var hy := me.hq.y
	var ry := hy + 5
	# a winding river four or five tiles wide below the headquarters
	for x in range(hx - 30, hx + 30):
		var off := int(round(sin(x * 0.25) * 1.5))
		for y in range(ry + off, ry + off + 4 + (1 if x % 7 < 3 else 0)):
			if sim.inb(x, y) and sim.bmap[sim.idx(x, y)] == 0:
				var i := sim.idx(x, y)
				sim.ter[i] = Sim.WATER; sim.deco[i] = 0; sim.road[i] = 0; sim.plot[i] = 0
	for y in range(ry - 2, ry + 18):
		for x in range(hx - 6, hx + 10):
			if sim.inb(x, y) and sim.ter[sim.idx(x, y)] != Sim.WATER:
				sim.deco[sim.idx(x, y)] = 0
	for y in range(hy - 4, ry + 8):
		for x in range(hx - 10, hx + 12):
			if sim.inb(x, y): sim.owner[sim.idx(x, y)] = 1
	sim.height = WorldGen.heights(sim.seed_str, sim.ter, sim.w, sim.h)
	# all taiga, as a map's maker could paint it
	var se = sim.get_feature("seasons")
	sim.map_biome = PackedByteArray()
	sim.map_biome.resize(sim.w * sim.h)
	sim.map_biome.fill(se.TAIGA + 1)
	se._make_biomes(); se._make_freeze(); se._make_textures()
	sim.logistics.net_dirty(1)
	var t := sim.add_bld("tower", hx + 3, ry + 12, foe, true, 0)
	t.garrison = 2
	var a := sim.add_bld("tower", hx + 3, ry - 3, me, true, 0)
	a.garrison = 8; a.gmix = [0, 0, 0, 8, 0, 0, 0]
	Diplomacy.declare_war(sim, 1, 2)
	main.view.reset_world()
	# deep winter
	sim.time = se.YEAR * se.ICE_FROM + 20.0
	for i in 30: sim.tick(Sim.TICK)
	sim.build_road(hx, hy, hx - 3, hy + 2, 1)
	print("ice road: '%s'" % sim.build_road(hx - 3, hy + 2, hx - 1, ry + 7, 1))
	print("attack: '%s'" % sim.military.launch_attack(a, t, 6))
	for i in 60: sim.tick(Sim.TICK)
	main.view.center_on(Vector2(hx + 1.5, ry + 3)); main.view.zoom = 40.0
	main._refresh_all()
	await _shot(out + "ice_winter.png")
	# just before the thaw: grey, cracked, wet
	sim.time = se.YEAR - 8.0
	for i in 20: sim.tick(Sim.TICK)
	main._refresh_all()
	await _shot(out + "ice_thaw.png")
	quit()
