class_name UiSpectate
extends RefCounted
## Spectator mode (build 77, the new-game option "spectate"): the computer plays every realm, the
## fog of war is off and the camera goes anywhere. The interface only watches: the toolbar and the
## windows that give orders are hidden, the info box shows no controls, and the keys that give orders
## do nothing. A Realms section at the top of the side panel compares every realm; a click on one
## moves the camera to its headquarters.
##
## The simulation still treats the first realm as sim.human() (only now the computer plays it), so a
## spectator game runs exactly the same whether anyone watches it or not.

var main: Main
var section: Control          # the Realms section at the top of the side panel
var rows: VBoxContainer
var note: Label
var _rows := {}               # realm id -> [name button, stats label, colour swatch]
var _shown := false           # whether the interface is in its spectator state now

## Keys that give orders, which do nothing while watching.
const BLOCKED_KEYS := [KEY_Q, KEY_Z, KEY_I, KEY_J, KEY_K, KEY_L, KEY_N, KEY_M, KEY_U, KEY_B, KEY_R,
	KEY_G, KEY_T, KEY_P, KEY_PAGEUP, KEY_PAGEDOWN, KEY_DELETE]


func _init(p_main: Main) -> void:
	main = p_main


## Whether the game on the map is a spectator game.
func active() -> bool:
	return main.sim != null and not main.sim.players.is_empty() and main.sim.spectating()


## Makes the Realms section; parent is the side panel's column (the section goes first in it).
func build(parent: VBoxContainer) -> void:
	var v := main._section(parent, "Realms")
	section = v.get_parent()
	parent.move_child(section, 0)
	var t := main._label("Spectator mode: the computer plays every realm. Click a realm to go to its headquarters; click any building to see how it is doing.", 12, Main.DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(Main.SIDE_W - 40, 0)
	v.add_child(t)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	v.add_child(rows)
	note = main._label("", 12, Main.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(Main.SIDE_W - 40, 0)
	v.add_child(note)
	section.visible = false


## After a new or loaded game: shows or hides everything that differs while watching.
func apply() -> void:
	var on := active()
	_shown = on
	section.visible = on
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	_rows = {}
	if on:
		for p: Sim.Player in main.sim.players:
			_add_row(p)
	_set_play_ui(not on)
	if on:
		main.view.place_type = ""
		main.view.zoom = 20.0
		refresh()


## The interface for playing (toolbar, order windows, the guide, the rivals list) on or off.
func _set_play_ui(play: bool) -> void:
	main.toolbar.bar.visible = play
	if not play and main.toolbar.popup != null:
		main.toolbar.close_popup()
	for b: Control in main.play_btns:
		b.visible = play
	main.rivals_label.get_parent().get_parent().visible = play
	if not play:
		main.guide_ui.box.visible = false
		for w in [main.workers_ui, main.carry_prio_ui, main.work_prio_ui, main.market_ui, main.blueprints_ui, main.neck_ui]:
			if w.win != null and w.win.visible:
				w.win.hide()
		main.tech_panel.visible = false
		main.dip_panel.visible = false
		main.targets_panel.visible = false


func _add_row(p: Sim.Player) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	rows.add_child(box)
	var hb := HBoxContainer.new()
	box.add_child(hb)
	var sw := ColorRect.new()
	sw.color = p.color
	sw.custom_minimum_size = Vector2(14, 14)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(sw)
	var nb := Button.new()
	nb.flat = true
	nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	nb.focus_mode = Control.FOCUS_NONE
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.add_theme_font_size_override("font_size", 14)
	nb.tooltip_text = tr("Go to this realm's headquarters")
	var pid := p.id
	nb.pressed.connect(func(): go_to(pid))
	hb.add_child(nb)
	var st := main._label("", 12, Main.DIM)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(Main.SIDE_W - 60, 0)
	box.add_child(st)
	_rows[p.id] = [nb, st, sw]


## Moves the camera to realm pid's headquarters (or where it stood).
func go_to(pid: int) -> void:
	for p: Sim.Player in main.sim.players:
		if p.id != pid:
			continue
		var at := Vector2(p.start.x + 0.5, p.start.y + 0.5)
		if p.hq != null and not p.hq.dead:
			at = Vector2(p.hq.x + 0.5, p.hq.y + 0.5)
		main.view.follow = null
		main.view.center_on(at)
		main.view.queue_redraw()


## Once a second with the side panel: each realm's numbers, the top bar, and play UI kept hidden.
func refresh() -> void:
	if active() != _shown:
		apply()
		return
	if not _shown:
		return
	main.guide_ui.box.visible = false
	var alive := 0
	for p: Sim.Player in main.sim.players:
		if p.alive:
			alive += 1
		var r: Array = _rows.get(p.id, [])
		if r.is_empty():
			continue
		var nb: Button = r[0]
		var st: Label = r[1]
		nb.text = tr("%s  (%s, level %d)") % [p.name, tr(p.pers), p.skill]
		if not p.alive:
			nb.modulate = Color(1, 1, 1, 0.45)
			st.text = tr("Defeated")
			continue
		nb.modulate = Color.WHITE
		var n := main.sim.realm_blds(p).size()
		# the age's whole name is the key ("Bronze age"), so a translation can word it its own way
		st.text = tr("%s · %d people · %d buildings · %d soldiers · %d land · %d studies") % [tr("%s age" % GameData.age_name(p.age)), main.sim.pop_total(p), n, main.sim.soldiers(p), main.sim.owned(p.id)[0].size(), p.techs.size()]
	note.text = tr("The stores and people below are %s's.") % main.sim.human().name
	main.lbl_pop.text = tr("Spectating")
	main.lbl_foes.text = tr("Realms %d") % alive


## Whether a key press is an order, which a spectator can't give.
func blocks_key(event: InputEventKey) -> bool:
	return _shown and not main.setup.visible and event.keycode in BLOCKED_KEYS


## The end screen's title and text for a spectator game.
func end_text() -> Array:
	var m := int(main.sim.time) / 60
	var last := String(main.sim.logs[-1][1]) if main.sim.logs.size() > 0 else ""
	return [tr("Game over"), tr("%s (after %d minutes)") % [last, m]]
