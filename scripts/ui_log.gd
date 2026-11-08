class_name UiLog
extends RefCounted
## The event log: a small window, at first in the upper-left corner of the map, that you can move by its
## title bar and resize from its edges. Its place, size and whether it is open are remembered in Settings.
## E (or the Events button on the top bar) shows and hides it. Events that happened somewhere on the
## map end with a Go button that moves the camera there.

## The title bar (26 px) is drawn above the window's position, so it starts low enough to clear the top bar.
const DEFAULT_RECT := Rect2i(12, 84, 430, 210)
const MIN_Y := 72

var main: Main
var win: Window
var text: RichTextLabel


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Events"
	win.transient = true
	win.wrap_controls = false
	win.min_size = Vector2i(220, 100)
	var r: Rect2i = main.settings.log_rect if main.settings.log_rect.size.x > 0 else DEFAULT_RECT
	win.position = Vector2i(r.position.x, maxi(r.position.y, MIN_Y))
	win.size = r.size
	win.visible = main.settings.log_open
	# the window frame and title in the game's dark-and-brass look
	win.theme = window_theme()
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.92))
	win.add_child(bg)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_following = true
	text.add_theme_font_size_override("normal_font_size", 13)
	text.meta_underlined = false
	text.meta_clicked.connect(_go)
	bg.add_child(text)
	win.close_requested.connect(func(): set_open(false))
	# remember where the player put it
	win.size_changed.connect(_remember)
	win.window_input.connect(_forward_keys)
	main.add_child(win)


## A theme for small game windows: a dark frame with a brass title. Feature windows use it too.
static func window_theme() -> Theme:
	var th := Theme.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.09, 0.1, 0.08, 0.96)
	frame.border_color = Color("8a6f35")
	frame.set_border_width_all(2)
	frame.border_width_top = 26
	frame.expand_margin_top = 26
	frame.set_corner_radius_all(4)
	th.set_stylebox("embedded_border", "Window", frame)
	var focused := frame.duplicate()
	focused.border_color = Color("d8aa4a")
	th.set_stylebox("embedded_unfocused_border", "Window", frame)
	th.set_stylebox("embedded_border", "Window", focused)
	th.set_color("title_color", "Window", Color("1c1608"))
	th.set_font_size("title_font_size", "Window", 14)
	return th


## Keys pressed while the log window has focus still reach the game's shortcuts.
func _forward_keys(event: InputEvent) -> void:
	if event is InputEventKey:
		main._unhandled_input(event)
	elif event is InputEventMouseButton and event.pressed:
		_remember()


func _remember() -> void:
	main.settings.log_rect = Rect2i(win.position, win.size)
	main.settings.save_file()


func set_open(on: bool) -> void:
	win.visible = on
	main.settings.log_open = on
	_remember()


func toggle() -> void:
	set_open(not win.visible)


## Shows the newest 60 events, oldest at the top, so the newest is at the bottom where it scrolls to.
func refresh() -> void:
	var lines := []
	for i in range(maxi(0, main.sim.logs.size() - 60), main.sim.logs.size()):
		var l = main.sim.logs[i]
		var go := ""
		if l.size() >= 5:
			go = " [url=%d,%d][bgcolor=#4a3c1c][color=#f0d080] Go [/color][/bgcolor][/url]" % [int(l[3]), int(l[4])]
		lines.append("[color=#%s][color=#777]%s[/color] %s[/color]%s" % [(l[2] as Color).to_html(false), l[0], l[1], go])
	text.text = "\n".join(lines)


## A Go button was clicked: centre the map on that tile, and select the building standing there.
func _go(meta: Variant) -> void:
	var xy := str(meta).split(",")
	if xy.size() != 2:
		return
	var t := Vector2i(int(xy[0]), int(xy[1]))
	main.view.center_on(Vector2(t.x, t.y))
	var b: Sim.Bld = main.sim.bld_at(t.x, t.y)
	if b != null and b.p == 1:
		main.view.sel_id = b.id
		main.sel_res = ""
		main.view.sel_tile = -1
		main._refresh_sel()
	main.view.queue_redraw()
