extends SceneTree
## The map editor, the missions list and a mission being played.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_missions.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main.log_ui.set_open(false)
	# 1. the editor: a lake and a mountain with iron painted in
	main.editor_ui.start("editor demo", 4, 0)
	var sim: Sim = main.sim
	var c := Vector2i(sim.w / 2, sim.h / 2)
	main.editor_ui.size = 5
	main.editor_ui.brush = 0
	for k in 12: main.editor_ui._paint(c + Vector2i(k - 6, int(3 * sin(k * 0.6))), k == 0)
	main.editor_ui.brush = 3
	for k in 10: main.editor_ui._paint(c + Vector2i(k - 5, 8), k == 0)
	main.editor_ui.brush = 9
	main.editor_ui.size = 3
	for k in 8: main.editor_ui._paint(c + Vector2i(k - 4, 8), k == 0)
	main.editor_ui._paint_done()
	main.editor_ui._fill()
	main.view.center_on(Vector2(c.x, c.y + 2))
	main.view.zoom = 16.0
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "map_editor.png")
	main.editor_ui.close()
	# 2. the missions list
	main.missions_ui.show()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "missions.png")
	main.missions_ui.win.visible = false
	# 3. mission 3 on its hand-made map, a few minutes in
	main.start_mission(UiMissions.missions()[2])
	sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 6 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.view.center_on(Vector2(me.hq.x, me.hq.y - 8))
	main.view.zoom = 14.0
	main._refresh_all()
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "mission_play.png")
	quit()
