class_name UiMissions
extends RefCounted
## The missions list, opened from the new-game screen: games with goals and often a deadline, from
## data/missions.json (a mod's data/missions.json adds more). Each mission plays on a map made from its
## seed or on a hand-made map file; its goals show in the box on the left while playing.

var main: Main
var win: Window
var body: VBoxContainer


func _init(p_owner: Main) -> void:
	main = p_owner


static func missions() -> Array:
	var out := []
	for path in ["res://data/missions.json", "user://data/missions.json"]:
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Array:
				out.append_array(d)
	return out


func build() -> void:
	win = Window.new()
	win.title = "Missions"
	win.transient = true
	win.exclusive = false
	win.wrap_controls = false
	win.size = Vector2i(620, 560)
	win.theme = UiLog.window_theme()
	win.visible = false
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.96))
	win.add_child(bg)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	sc.add_child(body)
	win.close_requested.connect(func(): win.visible = false)
	main.add_child(win)


func show() -> void:
	for c in body.get_children():
		c.queue_free()
	for ms in missions():
		var box := VBoxContainer.new()
		body.add_child(box)
		box.add_child(main._label(String(ms.get("name", "")), 17, Main.BRASS))
		var st := main._label(String(ms.get("story", "")), 13, Main.DIM)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size = Vector2(560, 0)
		box.add_child(st)
		var goals: Array = ms.get("goals", [])
		var gl := "\n".join(goals.map(func(g): return "  •  " + String(g.get("text", ""))))
		var mins := int(ms.get("minutes", 0))
		var info := "%s\n  %d rival%s, strength %d%s" % [gl, int(ms.get("foes", 1)), "s" if int(ms.get("foes", 1)) > 1 else "", int(ms.get("strength", 5)), (", within %d minutes" % mins) if mins > 0 else ""]
		box.add_child(main._label(info, 13))
		var play := main._button("Play this mission", func():
			win.visible = false
			if not main.start_mission(ms):
				main._show_hint("This mission could not be started.", 5.0))
		play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(play)
	win.popup_centered()
