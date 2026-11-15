class_name UiGuide
extends RefCounted
## The first-game guide: a short checklist for the first minutes of a new game (build a woodcutter, join
## it to the roads, a sawmill, a quarry...). Each step is ticked off by itself when it is done, with a
## line on the rule that matters for it (entrances, sizes, roads). It closes when every step is done or
## with its x, and "Show the first-game guide" in Settings brings it back for the next new game.

var main: Main
var box: PanelContainer
var list: VBoxContainer
var shown := false
var _last := ""
var title_lbl: Label

## [what to do, how it is checked, the tip shown under the step being worked on]
const STEPS := [
	["Build a woodcutter", "has:woodcutter", "Open Raw materials on the toolbar (or press B to see free spots). The arrow shows its entrance; R turns it."],
	["Join it to your roads", "joined:woodcutter", "Click Road, then the flag at its entrance, then a road or the headquarters. Turn on Auto roads to have them laid for you."],
	["Build a forester", "has:forester", "Foresters plant trees, so the woodcutter never runs out."],
	["Build a quarry near rocks", "has:quarry", "Stone and planks build almost everything."],
	["Build a sawmill", "has:sawmill", "A medium building: it needs a bigger free spot (the bigger house marker)."],
	["Find food: a fisher or a hunter", "any:fisher,hunter", "Workers and miners need food. Fishers need water close by, hunters need woods with game."],
	["Build a guard hut to claim land", "any:hut,palisade,tower", "Soldiers walk there from the headquarters; the land is yours when they arrive."],
	["Build a house for more people", "has:house", "Newcomers arrive when there is food and room; homes keep people until a job needs them."],
	["Pick something to study (R)", "studying", "Scriptoriums make research. Each age opens with one study, its gate: it can be studied once you know enough techs of the age you are in (the research window counts them for you)."],
]


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", main._panel_style(0.9))
	box.position = Vector2(12, 310)
	box.custom_minimum_size = Vector2(330, 0)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	box.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title_lbl = title
	title.text = "First steps"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("e8c870"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var x := Button.new()
	x.text = "x"
	x.flat = true
	x.tooltip_text = "Close the guide (Settings can show it again in the next new game)"
	x.pressed.connect(func():
		main.settings.guide = false
		main.settings.save_file()
		box.visible = false)
	top.add_child(x)
	list = VBoxContainer.new()
	v.add_child(list)
	box.visible = false
	main.add_child(box)


## Called when a new game starts.
func start() -> void:
	var mission: bool = not main.sim.mission.is_empty()
	shown = main.settings.guide or mission
	box.visible = shown
	title_lbl.text = String(main.sim.mission.get("name", "")) if mission else "First steps"
	_last = ""
	refresh()


## A mission's goals instead of the first steps: each with how far it is, ticked when done.
func _mission() -> void:
	var sim: Sim = main.sim
	var goals: Array = sim.mission.get("goals", [])
	var lines := []
	for k in goals.size():
		var g: Dictionary = goals[k]
		var gp := sim.goal_progress(g)
		var done: bool = k < sim.mission_done.size() and bool(sim.mission_done[k])
		var prog := "" if int(gp[1]) <= 1 else " (%d of %d)" % [mini(int(gp[0]), int(gp[1])), int(gp[1])]
		if done:
			lines.append("[color=#86ad5c]✔[/color] [color=#9a9c88]%s[/color]" % String(g.get("text", "")))
		else:
			lines.append("[color=#e8c870]▶[/color] %s[color=#b8b8a8]%s[/color]" % [String(g.get("text", "")), prog])
	var mins := float(sim.mission.get("minutes", 0))
	if mins > 0.0:
		var left := maxf(0.0, mins * 60.0 - sim.time)
		lines.append("[color=%s]Time left: %d:%02d[/color]" % ["#d9483d" if left < 300.0 else "#b8b8a8", int(left) / 60, int(left) % 60])
	var key := "\n".join(lines)
	if key == _last:
		return
	_last = key
	for c in list.get_children():
		c.queue_free()
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	l.add_theme_font_size_override("normal_font_size", 13)
	l.text = key
	list.add_child(l)


## Ticks off what is done; called once a second.
func refresh() -> void:
	if box == null or not box.visible or main.sim == null or main.sim.w == 0:
		return
	if not main.sim.mission.is_empty():
		_mission()
		return
	var done: Array = []
	var all := true
	for s in STEPS:
		var ok := _check(String(s[1]))
		done.append(ok)
		all = all and ok
	var key := str(done)
	if key == _last:
		return
	_last = key
	for c in list.get_children():
		c.queue_free()
	var tip_given := false
	for k in STEPS.size():
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.scroll_active = false
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(320, 0)
		l.add_theme_font_size_override("normal_font_size", 13)
		if done[k]:
			l.text = "[color=#86ad5c]✔[/color] [color=#9a9c88]%s[/color]" % tr(STEPS[k][0])
		elif not tip_given:
			tip_given = true
			l.text = "[color=#e8c870]▶[/color] [b]%s[/b]\n[color=#b8b8a8]%s[/color]" % [tr(STEPS[k][0]), tr(STEPS[k][2])]
		else:
			l.text = "[color=#6a6c60]○[/color] %s" % tr(STEPS[k][0])
		list.add_child(l)
	if all:
		main._show_hint("First steps done! Your town is on its way. (The guide closes.)", 5.0)
		main.settings.guide = false
		main.settings.save_file()
		box.visible = false


func _check(rule: String) -> bool:
	var sim: Sim = main.sim
	if rule == "studying":
		return sim.human().research != "" or sim.human().techs.size() > 0
	var kind := rule.get_slice(":", 0)
	var tys := rule.get_slice(":", 1).split(",")
	for b in sim.blds:
		if b.p != 1 or b.dead or not (b.ty in tys):
			continue
		if kind == "joined":
			if sim.connected(b):
				return true
		else:
			return true
	return false
