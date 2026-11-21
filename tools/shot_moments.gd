extends SceneTree
## Films the animations of the moments players watch most, frame by frame, for checking and for the
## animated previews: building sites rising in stages, a siege at the walls of a castle, and a cargo
## ship loading at one harbour and unloading at another.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_moments.gd -- out=/dir [only=sites|siege|harbour] [frames=40] [zoom=56]
## Writes <moment>_<frame>.png. The game is not run while filming: the clock is moved on by hand, so
## each moment stays where it is set up (the animations follow the game clock).
var main
var sim: Sim
var out := "user://"
var frames := 40
var zoom := 56.0
var only := ""
var focus := Vector2.ZERO     # the map point the frames are cut round
var cut := Vector2i(720, 440)  # the size of the frames written


func _shot(name: String) -> void:
	for i in 2: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if focus != Vector2.ZERO:
		var c: Vector2 = main.view.position + main.view._origin + focus * main.view.zoom
		var r := Rect2i(Vector2i(c) - cut / 2, cut)
		r.position = r.position.clamp(Vector2i.ZERO, img.get_size() - cut)
		img = img.get_region(r)
	img.save_png(out + name)


## Plain grass round (cx, cy), so the moment is easy to see.
func _clear(cx: int, cy: int, rx: int, ry: int) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if sim.inb(x, y) and sim.bmap[sim.idx(x, y)] == 0 and sim.ter[sim.idx(x, y)] != Sim.WATER:
				var i := sim.idx(x, y)
				sim.ter[i] = Sim.GRASS; sim.deco[i] = 0
	sim.changed_tiles.append(sim.idx(cx, cy))
	main.view.chunks.mark_all()


func _film(name: String, n: int, dt: float, each: Callable = Callable()) -> void:
	for f in n:
		if each.is_valid():
			each.call(f)
		sim.time += dt
		main.view.queue_redraw()
		await _shot("%s_%02d.png" % [name, f])


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("frames="): frames = int(a.substr(7))
		if a.begins_with("zoom="): zoom = float(a.substr(5))
		if a.begins_with("only="): only = a.substr(5)
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	if only == "" or only == "sites":
		await _sites()
	if only == "" or only == "siege":
		await _siege()
	if only == "" or only == "harbour":
		await _harbour()
	quit()


func _hide_ui() -> void:
	main.setup.visible = false
	main.paused = true
	main.side_box.visible = false
	main.guide_ui.box.visible = false
	main.log_ui.set_open(false)
	var fog = sim.get_feature("fog")
	if fog != null: fog.explored.fill(1); fog.vis.fill(1); fog.seen = {}; fog._img_dirty = true; fog._make_image()


## Three sites side by side (a house, a workshop, a castle), rising from bare ground to done.
func _sites() -> void:
	main._start("moments", 1, 5, true)
	sim = main.sim
	_hide_ui()
	focus = Vector2.ZERO
	var me := sim.human()
	var mx := me.hq.x; var my := me.hq.y + 5
	_clear(mx, my, 9, 4)
	var sites := []
	for e in [["house", -4], ["sawmill", 0], ["castle", 4]]:
		var b := sim.add_bld(String(e[0]), mx + int(e[1]), my, me, false, -1)
		b.builder = 2
		b.onsite = {"planks": 1.0, "stone": 1.0}
		sites.append(b)
	main.view.center_on(Vector2(mx + 0.5, my - 0.3)); main.view.zoom = zoom
	focus = Vector2(mx + 0.5, my - 0.9)
	cut = Vector2i(int(zoom * 12.5), int(zoom * 4.4))
	for i in 6: await process_frame
	await _film("sites", frames, 0.1, func(f: int) -> void:
		for k in sites.size():
			var b: Sim.Bld = sites[k]
			b.prog = clampf(float(f) / float(frames - 6) - k * 0.03, 0.0, 1.0)
			b.mat_total = 10; b.mat_used = int(b.prog * 10.0)
			b.builder = 2 if b.prog < 1.0 else 0)


## A column at the gate of a castle, its garrison on the walls.
func _siege() -> void:
	main._start("moments", 1, 5, true)
	sim = main.sim
	_hide_ui()
	focus = Vector2.ZERO
	var me := sim.human(); var foe := sim.players[1]
	var mx := me.hq.x; var my := me.hq.y
	_clear(mx + 3, my + 8, 8, 8)
	var a := sim.add_bld("castle", mx + 3, my + 3, me, true, 0)
	a.garrison = 16; a.gmix = [16, 0, 0, 0, 0, 0]
	var d := sim.add_bld("castle", mx + 3, my + 11, foe, true, 0)
	d.garrison = 8; d.gmix = [8, 0, 0, 0, 0, 0]
	Diplomacy.declare_war(sim, 1, 2)
	main.view.center_on(Vector2(mx + 3.5, my + 10.3)); main.view.zoom = zoom
	focus = Vector2(mx + 3.5, my + 9.6)
	cut = Vector2i(int(zoom * 7.0), int(zoom * 6.0))
	for i in 6: await process_frame
	print("launch: ", sim.military.launch_attack(a, d, 14))
	var at: Sim.Attack = null
	while sim.time < 90.0:
		sim.tick(Sim.TICK)
		if not sim.attacks.is_empty() and sim.attacks[0].fighting:
			at = sim.attacks[0]
			break
	if at == null:
		print("siege: no fight")
		return
	_hide_ui()      # (what the fog remembers is drawn over the walls)
	at.n = maxi(at.n, 10)
	d.garrison = maxi(d.garrison, 6)
	print("siege: fighting, attackers ", at.n, " defenders ", d.garrison)
	await _film("siege", frames, 0.05)


## A harbour on the coast with a ship loading at it, then one unloading.
func _harbour() -> void:
	main._start("islands", 2, 5, false, 160, false, {"features": Features.default_ids(), "sea_start": true})
	sim = main.sim
	_hide_ui()
	var me := sim.human()
	for i in 30: sim.tick(Sim.TICK)
	var h := me.hq
	me.ships = 3
	# a far bit of open water to sail to
	var far := -1
	var best := 0.0
	var moor: PackedInt32Array = sim.sea._moorings(h.x, h.y)
	var body: int = sim.sea.water_body(moor[0]) if not moor.is_empty() else -1
	for i in sim.w * sim.h:
		if sim.ter[i] == Sim.WATER and sim.sea.water_body(i) == body:
			var dd := Vector2(i % sim.w - h.x, i / sim.w - h.y).length()
			if dd > 14.0 and dd < 30.0 and dd > best:
				best = dd; far = i
	var path: PackedInt32Array = sim.sea.water_path(h.x, h.y, far % sim.w, far / sim.w)
	print("harbour: path ", path.size())
	var out_t := Sim.Trip.new()
	out_t.p = me.id; out_t.kind = "ship"; out_t.res = "planks"; out_t.n = 8; out_t.site = h.id; out_t.dest = 0
	out_t.path = path
	var st: float = sim.sea._sail_time(path)
	out_t.t0 = sim.time; out_t.t1 = sim.time + st + 2.0; out_t.t2 = out_t.t1 + st
	sim.trips.append(out_t)
	me.ships_out += 1
	main.view.center_on(Vector2(h.x + 0.5, h.y + 0.5)); main.view.zoom = zoom
	var dock := path[mini(4, path.size() - 1)]
	focus = (Vector2(h.x + 0.5, h.y + 0.5) + Vector2(dock % sim.w + 0.5, dock / sim.w)) / 2.0
	cut = Vector2i(int(zoom * 9.0), int(zoom * 5.5))
	for i in 6: await process_frame
	await _film("harbour_load", frames, 0.06)
	# and one coming in to unload (the same way backwards)
	sim.trips.erase(out_t)
	var rev := PackedInt32Array()
	for i in range(path.size() - 1, -1, -1):
		rev.append(path[i])
	var in_t := Sim.Trip.new()
	in_t.p = me.id; in_t.kind = "ship"; in_t.res = "stone"; in_t.n = 8; in_t.site = 0; in_t.dest = h.id
	in_t.path = rev
	in_t.t0 = sim.time - st - 2.0 + 1.6; in_t.t1 = in_t.t0 + st + 2.0; in_t.t2 = in_t.t1 + st
	sim.trips.append(in_t)
	await _film("harbour_unload", frames, 0.06)
