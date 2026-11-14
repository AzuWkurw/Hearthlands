class_name UiNotices
extends RefCounted
## Notices you can click (build 56): the latest important news with a place on the map ("your fleet was
## sunk", "soldiers are starving", an attack, a fire) shows for a while in a small stack under the top
## bar. Clicking one moves the map there and selects your building on that spot, like Go in the event
## log; its x puts it away. At most MAX at a time, each for SHOW seconds of real time.

const MAX := 4
const SHOW := 25.0

var main: Main
var box: VBoxContainer
var items: Array = []        # [text, colour, tile, real time it came]


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	box = VBoxContainer.new()
	box.position = Vector2(12, 136)
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(box)


## News worth a notice: something with a place on the map that is bad, or that asks for a look.
static func worth(text: String, col: Color) -> bool:
	if col.r > 0.8 and col.g < 0.65:
		return true          # the reds and oranges of bad news
	for w in ["attack", "fleet", "sank", "starving", "fire", "revolt", "plague", "captured", "fell", "general", "warship"]:
		if text.to_lower().contains(w):
			return true
	return false


## Called for every new line of the event log.
func on_log(text: String, col: Color) -> void:
	var logs: Array = main.sim.logs
	if logs.is_empty():
		return
	var e: Array = logs[logs.size() - 1]
	if e.size() < 5 or not worth(text, col):
		return
	items.push_front([text, col, Vector2i(int(e[3]), int(e[4])), Time.get_ticks_msec() / 1000.0])
	if items.size() > MAX:
		items.resize(MAX)
	_rebuild()


## Once a second: old notices go.
func tick() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var n := items.size()
	items = items.filter(func(it): return now - float(it[3]) < SHOW)
	if items.size() != n:
		_rebuild()


func clear() -> void:
	items = []
	_rebuild()


func _rebuild() -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for it in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var b := Button.new()
		var t := String(it[0])
		b.text = t if t.length() <= 70 else t.substr(0, 68) + "…"
		b.tooltip_text = t + "\n" + tr("Click to go there.")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", it[1])
		b.add_theme_stylebox_override("normal", main._panel_style(0.85))
		var at: Vector2i = it[2]
		b.pressed.connect(func(): main.log_ui._go("%d,%d" % [at.x, at.y]))
		row.add_child(b)
		var x := Button.new()
		x.text = "x"
		x.flat = true
		var ref = it
		x.pressed.connect(func():
			items.erase(ref)
			_rebuild())
		row.add_child(x)
		box.add_child(row)
