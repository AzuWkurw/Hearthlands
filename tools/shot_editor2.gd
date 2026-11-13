extends SceneTree
## The map editor's tools (mirror, river, climate, ruins and camps), and ruins and a bandit camp in a game:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_editor2.gd -- out=/dir
func _snap(path: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _init() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	# the new-game screen with the landscape settings open
	for c in main.setup.find_children("*", "Button", true, false):
		if (c as Button).text == "Landscape...":
			(c as Button).button_pressed = true
			(c as Button).pressed.emit()
	await _snap(out + "newgame_landscape.png")
	var ed: UiEditor = main.editor_ui
	var p := WorldGen.GEN_DEFAULTS.duplicate(); p["shape"] = "continent"
	ed.start("mirror", 4, 128, p)
	var sim: Sim = main.sim
	# mirrored four ways: a mountain ridge and a lake, a river across the middle, climate painted
	ed.mirror = "four ways"; ed.tool = "brush"; ed.size = 5; ed.round_brush = true
	ed.brush = 3
	for k in 10: ed._paint(Vector2i(30 + k, 34 + k / 2), k == 0)
	ed._paint_done()
	ed.brush = 0
	ed._paint(Vector2i(46, 30), true); ed._paint(Vector2i(48, 31), false); ed._paint_done()
	ed.mirror = "left-right"; ed.tool = "river"; ed.ford_k = 2
	ed._paint(Vector2i(64, 10), true); ed._paint(Vector2i(60, 60), false); ed._paint_done()
	ed.tool = "brush"; ed.mirror = "four ways"; ed.brush = 22; ed.size = 15
	ed._paint(Vector2i(30, 30), true); ed._paint_done()
	ed.brush = 23; ed._paint(Vector2i(50, 50), true); ed._paint_done()
	ed.brush = 25; ed.size = 1; ed._paint(Vector2i(40, 44), true); ed._paint_done()
	ed.mirror = "off"; ed.brush = 4; ed.size = 9
	ed.show_climate = true
	ed._fill()
	main.view.center_on(Vector2(64, 64)); main.view.zoom = 6.5
	main.view.ghost = Vector2i(44, 52)
	ed.mirror = "four ways"; ed._sync_view()
	await _snap(out + "editor_mirror_climate.png")
	ed.tab = "Check"; ed.show_climate = false; ed._fill()
	await _snap(out + "editor_check.png")
	# a game: ruins and a bandit camp near you, soldiers marching out to clear it
	var m := ed.current_map()
	var s0: Vector2i = ed.starts[0]
	m.places = [["ruins", s0.x + 5, s0.y - 3], ["bandits", s0.x + 7, s0.y + 4]]
	ed.close()
	main.start_map(m, 2)
	main.paused = false
	var sm: Sim = main.sim
	var me := sm.human()
	main.view.center_on(Vector2(s0.x + 5, s0.y + 2)); main.view.zoom = 48.0
	await _snap(out + "game_camp.png")
	me.reserve += 10
	Places.send(sm, me, sm.places[1])
	for k in 4: sm.tick(1.0)
	await _snap(out + "game_camp_party.png")
	quit()
