extends SceneTree
## The editor's Mission tab with events, and a mission's message window in a game (build 77):
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_events.gd -- out=/dir
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
	var ed: UiEditor = main.editor_ui
	ed.start("events", 3, 128, WorldGen.GEN_DEFAULTS.duplicate())
	ed.mission = {"id": "", "name": "The Long Watch", "story": "Hold the coast.", "foes": 2, "strength": 5, "minutes": 60,
		"goals": [{"kind": "pop", "n": 80, "text": "Grow to 80 people"}, {"kind": "defeat", "n": 1, "text": "Defeat 1 rival realm", "hidden": true}],
		"rules": [
			{"id": "e1", "when": {"kind": "age", "who": 0, "age": 1}, "do": [{"kind": "message", "text": "{1} fears your iron."}, {"kind": "war", "who": 1}]},
			{"id": "e2", "when": {"kind": "time", "min": 30}, "do": [{"kind": "landing", "who": 2, "n": 12}, {"kind": "show_goal", "goal": 1}]},
		]}
	ed._ev = {"when": {"kind": "after", "rule": "e2", "min": 5}, "do": [{"kind": "goods", "who": 0, "res": "bread", "n": 40}]}
	ed.tab = "Mission"
	ed._fill()
	await _snap(out + "editor_events.png")
	ed.close()
	# a message in a game
	main.start_mission({"name": "The Long Watch", "seed": "events", "foes": 1, "strength": 3, "goals": [{"kind": "pop", "n": 999, "text": "Grow"}],
		"rules": [{"id": "e1", "when": {"kind": "start"}, "do": [{"kind": "message", "title": "A sail on the sea", "text": "Scouts have seen the ships of {1} off the coast. Make ready."}]}]})
	for i in 30:
		main.sim.tick(Sim.TICK)
	main._refresh_all()
	await _snap(out + "story.png")
	quit()
