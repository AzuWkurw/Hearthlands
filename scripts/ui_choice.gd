class_name UiChoice
extends RefCounted
## An event that asks you to choose (pilgrims at the gate, a comet, grumbling over taxes, a strange
## ship): a window with what happened and the answers. The game waits while it is open; an unanswered
## question (window closed with Later) takes its last answer after two game minutes.

var main: Main
var panel: Control
var _was_paused := false
var _later_t := -1e9    # when you put the question off (it comes back a minute later)


func _init(m: Main) -> void:
	main = m


func check() -> void:
	if main.sim.w == 0 or main.sim.over or main.setup.visible or main.editor_ui.open:
		return
	if panel != null and panel.visible:
		return
	if main.age_ui.panel != null and main.age_ui.panel.visible:
		return
	var ev = main.sim.get_feature("events")
	if ev == null:
		return
	var q: Dictionary = ev.question(main.sim.human())
	if q.is_empty() or main.sim.time - _later_t < 60.0:
		return
	_open(ev, q)


func _open(ev, q: Dictionary) -> void:
	if panel == null:
		panel = main._overlay()
	var v: VBoxContainer = main._body(panel)
	for c in v.get_children():
		c.queue_free()
	_was_paused = main.paused
	main.paused = true
	v.add_child(main._label(String(q.title), 22, Main.BRASS))
	var t := main._rich()
	t.custom_minimum_size = Vector2(520, 0)
	t.text = String(q.text)
	v.add_child(t)
	var opts: Array = q.options
	for i in opts.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var b := main._button(String(opts[i][0]), func(): _choose(ev, i))
		b.custom_minimum_size = Vector2(300, 34)
		row.add_child(b)
		row.add_child(main._label(String(opts[i][1]), 13, Main.DIM))
		v.add_child(row)
	v.add_child(main._label(tr("Unanswered, the last answer is taken in %d s of game time.") % int(q.left), 12, Main.DIM))
	v.add_child(main._button(tr("Later"), func():
		_later_t = main.sim.time
		panel.visible = false
		main.paused = _was_paused))
	panel.visible = true


func _choose(ev, i: int) -> void:
	ev.answer(main.sim.human(), i)
	panel.visible = false
	main.paused = _was_paused
	main.log_dirty = true
