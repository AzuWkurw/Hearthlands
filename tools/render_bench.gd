extends SceneTree
## Measures where frame time goes with the current renderer.
## Run: godot --rendering-method <gl_compatibility|forward_plus|mobile> --script res://tools/render_bench.gd -- [w=1600] [h=900] [label=...]
## Prints which renderer and graphics adapter actually run (Godot falls back to OpenGL when Vulkan
## is missing), then for a few scenes the average frame, the time the CPU spends on game logic and
## script drawing ("process"), and the renderer's own CPU and GPU time per frame.

var main
var sim: Sim


func _init() -> void:
	var wsz := 1600
	var hsz := 900
	var label := ""
	var norender := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("w="): wsz = int(a.substr(2))
		if a.begins_with("h="): hsz = int(a.substr(2))
		if a.begins_with("label="): label = a.substr(6)
		if a == "norender": norender = true
	root.size = Vector2i(wsz, hsz)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	# Vulkan renderers (Forward+, Mobile) have a RenderingDevice; the OpenGL one does not
	var api := "Vulkan" if RenderingServer.get_rendering_device() != null else "OpenGL"
	print("RENDERER %s | api=%s %s | adapter=%s (%s) | %dx%d threads=%s" % [label, api,
		RenderingServer.get_video_adapter_api_version(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), wsz, hsz, OS.get_environment("LP_NUM_THREADS")])
	main._start("render", 6, 6, true)
	main.setup.visible = false
	sim = main.sim
	# a fixed, busy scene: six rivals, eight minutes in, every realm run by the AI
	for p in sim.players:
		p.ai = true
	while sim.time < 8 * 60.0:
		sim.tick(Sim.TICK)
	sim.players[0].ai = false
	var hq: Sim.Bld = sim.players[0].hq
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	if norender:
		# the game, the scripts and their drawing commands still run; only turning them into pixels stops
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_DISABLED)
		print("RENDERER screen drawing switched off")
	await _case("close, paused", 32.0, Vector2(hq.x, hq.y), false)
	await _case("close, game 4x", 32.0, Vector2(hq.x, hq.y), true)
	await _case("far, paused", 9.0, Vector2(hq.x, hq.y), false)
	main.view.set_animate(false)
	await _case("close, no anims", 32.0, Vector2(hq.x, hq.y), false)
	main.view.set_animate(true)
	quit()


func _case(name: String, zoom: float, at: Vector2, running: bool) -> void:
	main.view.zoom = zoom
	main.view.center_on(at)
	main.paused = not running
	main.speed = 4.0
	for i in 30: await process_frame
	var n := 90
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var rcpu := 0.0
	var rgpu := 0.0
	var vp := root.get_viewport_rid()
	for i in n:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		rgpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var frame := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("CASE %-16s frame %5.1f ms (%4.1f fps) | map draw code %4.1f ms | renderer setup %4.1f ms" % [name, frame, 1000.0 / frame, float(main.view.draw_usec + main.view.ground_usec) / 1000.0, rcpu / n])
