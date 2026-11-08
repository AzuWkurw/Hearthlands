extends SceneTree
## Drives the research window with real mouse and key events and prints what happened.
var main
func _f(n := 3) -> void:
	for i in n: await process_frame

func _mouse_btn(pos: Vector2, btn: int, pressed: bool, dbl := false, ctrl := false) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos; e.global_position = pos; e.button_index = btn; e.pressed = pressed; e.double_click = dbl; e.ctrl_pressed = ctrl
	Input.parse_input_event(e)
	await _f(2)

func _move(pos: Vector2, mask := 0) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos; e.button_mask = mask
	Input.parse_input_event(e)
	await _f(2)

func _key(k: int) -> void:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = true
	Input.parse_input_event(e); await _f(2)
	e = e.duplicate(); e.pressed = false; Input.parse_input_event(e); await _f(2)

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	await _f()
	main._start("uitest", 2, 5, true)
	main.setup.visible = false
	var sim: Sim = main.sim
	var p := sim.human()
	sim.complete_tech(p, "iron_axes")
	await _f()
	await _key(KEY_R)
	var ui = main.research_ui
	var tree: TechTreeView = ui.tree
	print("open: ", main.tech_panel.visible, " tree size ", tree.size, " content ", tree.content)
	# click a card
	var id := "coppicing"
	tree.center_on(id); await _f()
	var c: Vector2 = tree.global_position + (tree.pos[id] - tree.cam) * tree.zoom + Vector2(40, 20)
	await _move(c)
	print("hover: ", tree.hover, " chain ", tree._chain.size())
	await _mouse_btn(c, MOUSE_BUTTON_LEFT, true); await _mouse_btn(c, MOUSE_BUTTON_LEFT, false)
	print("selected: ", tree.sel, " actions ", ui.actions.get_children().map(func(b): return b.text))
	# double click on a locked tech queues the way there
	tree.center_on("printing_press"); await _f()
	c = tree.global_position + (tree.pos["printing_press"] - tree.cam) * tree.zoom + Vector2(40, 20)
	await _mouse_btn(c, MOUSE_BUTTON_LEFT, true, true); await _mouse_btn(c, MOUSE_BUTTON_LEFT, false)
	print("after double click: research=", p.research, " queue=", p.rqueue)
	# drag pans
	var cam0 := tree.cam
	var a := tree.global_position + Vector2(300, 300)
	await _mouse_btn(a, MOUSE_BUTTON_LEFT, true)
	await _move(a + Vector2(-60, -40), MOUSE_BUTTON_MASK_LEFT); await _move(a + Vector2(-160, -120), MOUSE_BUTTON_MASK_LEFT)
	await _mouse_btn(a + Vector2(-160, -120), MOUSE_BUTTON_LEFT, false)
	print("drag: cam ", cam0, " -> ", tree.cam, " sel still ", tree.sel)
	# wheel scrolls, ctrl+wheel zooms
	var y0 := tree.cam.y
	await _mouse_btn(a, MOUSE_BUTTON_WHEEL_DOWN, true); await _mouse_btn(a, MOUSE_BUTTON_WHEEL_DOWN, false)
	print("wheel: cam.y ", y0, " -> ", tree.cam.y)
	await _mouse_btn(a, MOUSE_BUTTON_WHEEL_UP, true, false, true); await _mouse_btn(a, MOUSE_BUTTON_WHEEL_UP, false, false, true)
	print("ctrl wheel: zoom ", tree.zoom, " button ", ui.zoom_btn.text)
	await _key(KEY_MINUS); await _key(KEY_MINUS)
	print("minus x2: zoom ", tree.zoom)
	await _key(KEY_0)
	print("0: zoom ", tree.zoom)
	# compact
	ui.compact_btn.emit_signal("pressed"); await _f()
	print("compact: card ", tree.card, " btn ", ui.compact_btn.text)
	# search
	ui.search.text = "redoubt"; ui.search.text_changed.emit("redoubt"); ui.search.text_submitted.emit("redoubt"); await _f()
	print("search redoubt: sel ", tree.sel, " box '", ui.search.text, "' dimming '", tree.search, "'")
	# queue buttons: remove the first queued one with its x
	var xs: Array = ui.queue_row.get_children().filter(func(b): return b is Button and b.text == "x")
	print("queue items ", ui.queue_row.get_children().filter(func(b): return b is Button and b.text != "x").map(func(b): return b.text))
	if xs.size() > 1: xs[1].emit_signal("pressed"); await _f()
	print("after removing 1st queued: research=", p.research, " queue=", p.rqueue)
	# rep via detail buttons
	ui._select("r1_tools", true); await _f()
	print("rep actions: ", ui.actions.get_children().map(func(b): return b.text))
	for b in ui.actions.get_children():
		if b.text.begins_with("Queue level"): b.emit_signal("pressed"); break
	await _f()
	print("rep queued: ", p.rqueue, " actions now ", ui.actions.get_children().map(func(b): return b.text))
	# Esc in the search box: first clears it, then closes the window
	ui.search.grab_focus(); ui.search.text = "mill"; ui.search.text_changed.emit("mill"); await _f()
	print("search mill dims: ", tree.search, " hits ", tree.hits.size())
	await _key(KEY_ESCAPE)
	print("esc 1: text '", ui.search.text, "' open=", main.tech_panel.visible)
	await _key(KEY_ESCAPE)
	print("esc 2: open=", main.tech_panel.visible)
	await _key(KEY_R)
	print("hover after reopen: '", tree.hover, "'")
	# a feature off hides its techs
	print("herbals on tree with diseases on: ", tree.pos.has("herbals"))
	sim.set_feature("diseases", false); main.research_ui._open_tech(); await _f()
	print("with diseases off: on tree ", tree.pos.has("herbals"), ", available ", sim.tech_available(p, "herbals"))
	# Esc closes, then time runs the queue
	tree.set_zoom(0.55); tree.center_on("guilds"); await _f(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/claude-0/-home-claude/5960235b-5447-57a9-aec8-872cd259bb3a/scratchpad/rshots/compact55.png")
	await _key(KEY_ESCAPE)
	print("esc: open=", main.tech_panel.visible)
	p.rp = 3000.0
	var t0 := sim.time
	while sim.time < t0 + 20.0: sim.tick(Sim.TICK)
	print("after time: techs ", p.techs.keys(), " reps ", p.reps, " research '", p.research, "' queue ", p.rqueue)
	main._refresh_all(); await _f()
	print("side panel: ", main.research_label.get_parsed_text().replace("\n", " | "))
	await _key(KEY_R)
	print("reopen ok: ", main.tech_panel.visible)
	quit()
