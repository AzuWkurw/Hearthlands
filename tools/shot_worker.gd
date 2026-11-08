extends SceneTree
## A new worker walking from his home to his job:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_worker.gd -- out=/dir
var out := "user://"
var main

func shot(name: String) -> void:
	main.view.queue_redraw()
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")

func pick(b: Sim.Bld) -> void:
	main.view.sel_id = b.id
	main.view.center_on(Vector2(b.x + 3.0, b.y + 1.0))
	main._refresh_all()

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	var lodge_done := false
	while sim.time < 3 * 60.0:
		sim.tick(Sim.TICK)
		if not lodge_done and sim.time > 7 * 60.0:
			for r in range(3, 9):
				if lodge_done: break
				for dy in range(-r, r + 1):
					if lodge_done: break
					for dx in range(-r, r + 1):
						if sim.place("lodge", me.hq.x + dx, me.hq.y + dy, me) == "":
							lodge_done = true; break
	main.paused = true
	main.log_ui.set_open(false)
	for i in 6000:
		sim.tick(Sim.TICK)
		var tw: Sim.Trip = null
		for t in sim.trips:
			if t.p == 1 and t.kind == "worker" and sim.time - t.t0 > 1.5 and t.t1 - sim.time > 1.5 and t.t1 - t.t0 > 6.0: tw = t
		if tw != null:
			var n := tw.path.size() - 1
			var prog := 1.0 - clampf((sim.time - tw.t0) / maxf(0.01, tw.t1 - tw.t0), 0.0, 0.999)
			var k := mini(floori(prog * n), n - 1)
			main.view.center_on(Vector2(tw.path[k] % sim.w + 0.5, tw.path[k] / sim.w + 0.5))
			main.view.zoom = 72.0
			main._refresh_all()
			await shot("5_worker")
			print("worker walking to ", sim.by_id.get(tw.site).ty if sim.by_id.has(tw.site) else "?")
			break
	quit()
