class_name UiStory
extends RefCounted
## A mission's scripted messages (build 77, MissionScript "message"): a window with the text that
## pauses the game until you go on. Several at once are shown one after another.

var main: Main
var panel: Control
var queue: Array = []     # [title, text] waiting to be shown
var _was_paused := false


func _init(m: Main) -> void:
	main = m


## Sim.story: kept until the interface next looks (not opened in the middle of a game moment).
func on_story(title: String, text: String) -> void:
	queue.append([title, text])


## A new game or a loaded one: messages of the last game are dropped.
func clear() -> void:
	queue.clear()
	if panel != null and panel.visible:
		panel.visible = false


func check() -> void:
	if queue.is_empty() or main.setup.visible or main.editor_ui.open:
		return
	if panel != null and panel.visible:
		return
	var it: Array = queue.pop_front()
	if panel == null:
		panel = main._overlay()
	var v: VBoxContainer = main._body(panel)
	for c in v.get_children():
		c.queue_free()
	_was_paused = main.paused
	main.paused = true
	var title := String(it[0])
	if title == "":
		title = String(main.sim.mission.get("name", ""))
	v.add_child(main._label(MissionScript.fill(main.sim, tr(title)), 22, Main.BRASS))
	var t := main._rich()
	t.custom_minimum_size = Vector2(520, 0)
	t.text = MissionScript.fill(main.sim, tr(String(it[1])))
	v.add_child(t)
	v.add_child(main._button(tr("Go on"), func():
		panel.visible = false
		main.paused = _was_paused if queue.is_empty() else main.paused))
	panel.visible = true
