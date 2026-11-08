extends SceneTree
## Quick check for text off screen: opens the main windows at a few window sizes and lists visible
## controls that reach past the window, and labels/buttons whose text is wider than they are.
var main
var out := []

func _clipped(c: Control) -> bool:
	var n := c.get_parent()
	while n is Control:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false

func _walk(n: Node, vp: Rect2, tag: String) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control and not (n is MapView):
		var c := n as Control
		var r := c.get_global_rect()
		var txt := ""
		if c is Label: txt = (c as Label).text
		elif c is Button: txt = (c as Button).text
		elif c is RichTextLabel: txt = (c as RichTextLabel).get_parsed_text()
		if c.get_combined_minimum_size().x > 360 and c.get_global_rect().position.x > 850:
			out.append("%s MINW %s %s %.0f '%s'" % [tag, c.get_class(), c.name, c.get_combined_minimum_size().x, txt.left(60).replace("\n", " ")])
		if r.size.x > 1 and r.size.y > 1 and not _clipped(c):
			if r.end.x > vp.end.x + 1 or r.end.y > vp.end.y + 1 or r.position.x < -1 or r.position.y < -1:
				out.append("%s OFF %s %s [%s] '%s'" % [tag, c.get_class(), c.name, str(r), txt.left(50).replace("\n", " ")])
		if txt != "" and (c is Label or c is Button):
			var f: Font = c.get_theme_font("font")
			var fs: int = c.get_theme_font_size("font_size")
			var aw: int = (c as Label).autowrap_mode if c is Label else 0
			if aw == 0 and not (c is Label and (c as Label).clip_text):
				for line in txt.split("\n"):
					var wdt := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					if wdt > r.size.x + 2 and r.size.x > 0:
						out.append("%s WIDE %s %s %.0f>%.0f '%s'" % [tag, c.get_class(), c.name, wdt, r.size.x, line.left(50)])
	for ch in n.get_children():
		_walk(ch, vp, tag)

func snap(tag: String) -> void:
	for i in 4: await process_frame
	_walk(root, Rect2(Vector2.ZERO, Vector2(root.size)), tag)

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	for sz in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		DisplayServer.window_set_size(sz)
		root.size = sz
		if main.get_parent() == null:
			root.add_child(main)
		var t := "%dx%d" % [sz.x, sz.y]
		await snap(t + " setup")
		main._start("showcase", 3, 6, true)
		main.setup.visible = false
		var sim: Sim = main.sim
		for i in 600: sim.tick(Sim.TICK)
		main.view.sel_id = sim.players[0].hq.id
		for cat in ["raw", "food", "industry", "crafts", "folk", "mil", "logistics", "science"]:
			main._set_cat(cat)
			main._refresh_all()
			await snap(t + " tab " + cat)
		for f in ["_open_tech", "_open_diplomacy", "_open_saves", "_open_settings", "_open_targets", "_open_soldier_kinds"]:
			main.call(f)
			await snap(t + " " + f)
			main._unhandled_key_esc() if main.has_method("_unhandled_key_esc") else null
			for w in ["tech_panel", "dip_panel", "save_panel", "settings_panel", "target_panel", "kinds_panel"]:
				if main.get(w) != null: main.get(w).visible = false
	var seen := {}
	for l in out:
		var k: String = l.substr(l.find(" ", 12))
		if true:
			seen[k] = true
			print(l)
	print("issues: ", seen.size())
	quit()
