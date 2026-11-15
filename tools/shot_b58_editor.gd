extends SceneTree
## Build 58: sulfur and lead brushes in the map editor, painted on a mountain.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_b58_editor.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.editor_ui.start("editor demo", 4, 0)
	var sim: Sim = main.sim
	var ed = main.editor_ui
	var best := Vector2i(-1, -1)
	for y in range(6, sim.h - 6):
		for x in range(6, sim.w - 6):
			var ok := true
			for dy in range(-3, 4):
				for dx in range(-5, 6):
					if sim.ter[sim.idx(x + dx, y + dy)] != Sim.MOUNT: ok = false
			if ok: best = Vector2i(x, y); break
		if best.x >= 0: break
	main.view.center_on(Vector2(best)); main.view.zoom = 34.0
	ed.tool = "brush"; ed.size = 3
	var k := 0
	for nm in ["Sulfur", "Lead"]:
		for j in UiEditor.BRUSHES.size():
			if UiEditor.BRUSHES[j][0] == nm: ed.brush = j
		ed._paint(best + Vector2i(-3 + k * 6, -1), true)
		ed._paint(best + Vector2i(-3 + k * 6, 1), false)
		ed._paint_done()
		k += 1
	ed._fill()
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "b58_editor_sulfur.png")
	quit()
