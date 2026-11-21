class_name UiAge
extends RefCounted
## The new age: when your realm enters an age, a window shows what the age brings (its soldiers, the new
## look of buildings, the buildings and studies it opens) and asks you to pick one of three paths for it:
## wealth, war or learning (age_bonuses in data/techs.json). The game waits while it is open. Rivals pick
## theirs at once (SimResearch._ai_age_bonus).

var main: Main
var panel: Control
var _was_paused := false
var _age := -1


func _init(m: Main) -> void:
	main = m


## Called with the side panel's refresh: opens the window when an age still waits for its path.
func check() -> void:
	if main.sim.w == 0 or main.sim.over or main.setup.visible or main.editor_ui.open or (main.welcome_ui != null and main.welcome_ui.visible):
		return
	if panel != null and panel.visible:
		return
	var a: int = main.sim.missing_age_bonus(main.sim.human())
	if a > 0:
		open(a)


func open(a: int) -> void:
	_age = a
	if panel == null:
		panel = main._overlay()
	var v: VBoxContainer = main._body(panel)
	for c in v.get_children():
		c.queue_free()
	_was_paused = main.paused
	main.paused = true
	var name := GameData.age_name(a)
	v.add_child(main._label(tr("The %s age begins" % name), 24, Main.BRASS))
	var t := main._rich()
	t.custom_minimum_size = Vector2(640, 0)
	t.text = _what_it_brings(a)
	v.add_child(t)
	v.add_child(main._label(tr("Choose your realm's path for this age:"), 16, Color("e6e2d3")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for o in main.sim.age_bonus_options(a):
		row.add_child(_choice_card(a, o))
	panel.visible = true


func _choice_card(a: int, o: Dictionary) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.19, 0.15)
	sb.border_color = Color("6a5a30")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(206, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var kind := String(o.get("kind", ""))
	v.add_child(main._label({"wealth": tr("Wealth"), "war": tr("War"), "learning": tr("Learning")}.get(kind, kind), 13, Main.DIM))
	v.add_child(main._label(String(o.name), 17, Main.BRASS))
	var r := main._rich()
	r.text = "%s\n\n[color=#8fc070]%s[/color]" % [String(o.get("info", "")), GameData.effect_text(o.get("effects", {}))]
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(r)
	var b := main._button(tr("Choose"), func(): _choose(a, String(o.id)))
	v.add_child(b)
	return pc


func _choose(a: int, id: String) -> void:
	main.sim.choose_age_bonus(main.sim.human(), a, id)
	panel.visible = false
	main.paused = _was_paused
	main.log_dirty = true
	# an older save can still wait for a later age's path
	check()


## What entering age a brings: its soldiers, the look of new buildings, what its studies open.
func _what_it_brings(a: int) -> String:
	var s := ""
	s += tr("Your barracks now train [b]%s[/b], and new buildings go up in the %s style (Renovate brings old ones up to date)." % [Sim.soldier_plural(a), GameData.age_name(a)])
	var n := 0
	var blds := []
	for id in GameData.techs:
		var t: Dictionary = GameData.techs[id]
		if int(t.get("age", 0)) != a or t.get("gate", false) or not main.sim.tech_enabled(id):
			continue
		n += 1
		for b in GameData.unlocks(id):
			if main.sim.bld_enabled(b) and not blds.has(b):
				blds.append(b)
	s += "\n\n" + tr("[b]%d studies[/b] are open to you now." % n)
	if not blds.is_empty():
		var names := blds.slice(0, 10).map(func(b): return String(GameData.bld[b].name))
		s += " " + tr("They lead to new buildings: %s%s." % [", ".join(names), (tr(" and %d more") % (blds.size() - 10)) if blds.size() > 10 else ""])
	var reps := []
	for id in GameData.reps:
		if int(GameData.reps[id].get("age", 0)) == a:
			reps.append(String(GameData.reps[id].name))
	if not reps.is_empty():
		s += "\n\n" + tr("Mastery studies (repeatable): %s." % ", ").join(reps)
	var nxt := GameData.gate_of(a + 1)
	if nxt != "":
		s += "\n\n" + tr("To reach the %s age, study [b]%s[/b] once you know %d %s techs." % [GameData.age_name(a + 1), GameData.tech_name(nxt), int(GameData.techs[nxt].get("need", 0)), GameData.age_name(a)])
	return s
