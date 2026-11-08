extends SceneTree
## Explored land survives saving and loading through the game's own save files:
## xvfb-run godot --rendering-driver opengl3 --script res://tools/fogsave_test.gd
func _count(sim: Sim) -> int:
	var f = sim.get_feature("fog")
	if f == null: return -1
	var n := 0
	for v in f.explored: n += v
	return n

func _init() -> void:
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("fogsave", 2, 5, true); main.setup.visible = false
	var sim: Sim = main.sim
	var p := sim.human()
	var fog = sim.get_feature("fog")
	p.scout = 3
	print("send: '", fog.send_scout(p, p.hq.x + 25, p.hq.y), "'")
	var t0 := sim.time
	while sim.time < t0 + 40.0: sim.tick(Sim.TICK)
	var before := _count(sim)
	main.view.zoom = 9.0
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/claude-0/-home-claude/5960235b-5447-57a9-aec8-872cd259bb3a/scratchpad/fogload_before.png")
	main._save_game("fogtest", true)
	for i in 3: await process_frame
	main._load_game("fogtest")
	for i in 5: await process_frame
	print("same session: explored before %d, after load %d" % [before, _count(main.sim)])
	# as after starting the game again: a fresh window, straight to Load
	main.queue_free()
	for i in 3: await process_frame
	var m2 = load("res://main.tscn").instantiate(); root.add_child(m2)
	for i in 5: await process_frame
	m2._load_game("fogtest")
	for i in 5: await process_frame
	var s2: Sim = m2.sim
	print("fresh start: after load %d, features %s" % [_count(s2), s2.feature_ids()])
	for i in 30: s2.tick(Sim.TICK)
	print("after 3 s: %d" % _count(s2))
	var fg = s2.get_feature("fog")
	m2.view.zoom = 9.0
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/claude-0/-home-claude/5960235b-5447-57a9-aec8-872cd259bb3a/scratchpad/fogload_after.png")
	print("fog texture: ", fg.tex != null, " vis sum ", Array(fg.vis).reduce(func(a, v): return a + v, 0))
	quit()
