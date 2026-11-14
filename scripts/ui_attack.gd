class_name UiAttack
extends RefCounted
## The attack window, as in The Settlers II: clicking an enemy military building opens it. It shows the
## defenders, lets you pick how many soldiers march (from all your military buildings in range, the
## nearest first) and which kinds, and gives a rough idea of the odds. Each building keeps at least one
## soldier home, as before.

var main: Main
var panel: Control
var body: VBoxContainer
var tgt_id := 0
var slider: HSlider
var count_lbl: Label
var odds_lbl: Label
var kinds := {}          # kind -> CheckBox


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	panel = main._overlay()
	body = main._body(panel)
	panel.visible = false


## Your military buildings that can send soldiers at t: [[building, how many can go], ...], nearest first.
func sources(t: Sim.Bld) -> Array:
	var sim: Sim = main.sim
	var out := []
	for b: Sim.Bld in sim.mil_list():
		if b.p != 1 or b.state != "ready":
			continue
		if Vector2(t.x - b.x, t.y - b.y).length() > Sim.RANGE:
			continue
		var av := mini(sim.own_def(b) - 1, 16)
		if av >= 1 and not sim.military.land_path(b.x, b.y, t.x, t.y).is_empty():
			out.append([b, av])
	out.sort_custom(func(a, c):
		var da := Vector2(t.x - a[0].x, t.y - a[0].y).length()
		var dc := Vector2(t.x - c[0].x, t.y - c[0].y).length()
		return da < dc or (da == dc and a[0].id < c[0].id))
	return out


## A landing on t from the sea: [your harbour, how many soldiers can sail] or [] when none can (no
## harbour with a free ship, no soldier waiting at the headquarters, or no sea way to a beach near it).
## Kept for the building last asked about, as finding the sea way takes a moment.
var _sea_for := -1
var _sea_at := -1.0
var _sea: Array = []

func sea_option(t: Sim.Bld) -> Array:
	var sim: Sim = main.sim
	if _sea_for == t.id and absf(sim.time - _sea_at) < 2.0:
		return _sea
	_sea_for = t.id
	_sea_at = sim.time
	_sea = []
	var me := sim.human()
	var ships := sim.sea.free_ships(me)
	if ships < 1 or me.reserve < 1:
		return _sea
	var hs := sim.sea.harbours(me)
	hs.sort_custom(func(a, c): return Vector2(a.x - t.x, a.y - t.y).length() < Vector2(c.x - t.x, c.y - t.y).length())
	for h: Sim.Bld in hs.slice(0, 3):
		if not sim.sea.landing_route(h, t).is_empty():
			_sea = [h, mini(mini(me.reserve, ships * SimSea.LANDING_PER_SHIP), SimSea.LANDING_MAX)]
			break
	return _sea


## Why none of your buildings can attack enemy building t now.
func why_not(t: Sim.Bld) -> String:
	var sim: Sim = main.sim
	var in_range := 0
	var walking := 0
	var no_way := 0
	for b: Sim.Bld in sim.mil_list():
		if b.p != 1 or b.state != "ready" or Vector2(t.x - b.x, t.y - b.y).length() > Sim.RANGE:
			continue
		in_range += 1
		walking += b.walking
		if sim.military.land_path(b.x, b.y, t.x, t.y).is_empty():
			no_way += 1
	if in_range == 0:
		return "Too far: none of your military buildings is within %d tiles of it. Build one nearer." % int(Sim.RANGE)
	if no_way == in_range:
		return "No way there by land: water lies between. Build a bridge, or a military building on the other side."
	var me := sim.human()
	if walking > 0:
		return "Your buildings in range each have only the one soldier who stays home. %d more are on their way to them." % walking
	if me.reserve <= 2:
		return "Your buildings in range each have only the one soldier who stays home, and none wait at headquarters. Train more soldiers."
	return "Your buildings in range each have only the one soldier who stays home. More are coming from headquarters."


## Opens the window for enemy building t. Returns "" or why no attack is possible.
func open(t: Sim.Bld) -> String:
	var sim: Sim = main.sim
	if not Diplomacy.at_war(sim, 1, t.p):
		return "You are not at war with %s. Declare war in Diplomacy first." % sim.players[t.p - 1].name
	var src := sources(t)
	var sea := sea_option(t)
	if src.is_empty() and sea.is_empty():
		return "None of your military buildings in range has a soldier to spare."
	tgt_id = t.id
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	body.add_child(main._label(tr("Attack %s's %s") % [sim.players[t.p - 1].name, String(t.def.name)], 22, Main.BRASS))
	if src.is_empty():
		_open_sea(t, sea)
		return ""
	var dm: Array = sim.military.mix_of(sim.military._defending(t))
	body.add_child(main._label(tr("Defenders: %d (%s)") % [sim.defenders(t), Sim.mix_text(dm)], 14, Main.DIM))
	if t.archers > 0 or t.sally:
		var extra := []
		if t.archers > 0:
			extra.append(tr("plus %d archers: they shoot from 6 tiles out") % t.archers)
		if t.sally:
			extra.append("they march out to meet attackers")
		var et := ", ".join(extra)
		body.add_child(main._label(et[0].to_upper() + et.substr(1) + ".", 13, Color("e0b060")))
	var total := 0
	var have := [0, 0, 0, 0, 0, 0]
	for s in src:
		total += int(s[1])
		var m: Array = sim.military.mix_of(s[0])
		for k in mini(6, m.size()):
			have[k] += int(m[k])
	count_lbl = main._label("", 15)
	body.add_child(count_lbl)
	slider = HSlider.new()
	slider.min_value = 1
	slider.max_value = total
	slider.step = 1
	slider.value = total
	slider.custom_minimum_size = Vector2(380, 24)
	slider.value_changed.connect(func(_v): _update())
	body.add_child(slider)
	body.add_child(main._label("Kinds that march:", 14, Main.DIM))
	var kr := HFlowContainer.new()
	body.add_child(kr)
	kinds = {}
	for k in 6:
		if have[k] <= 0:
			continue
		var cb := CheckBox.new()
		cb.text = "%s (%d)" % [Sim.soldier_plural(k), have[k]]
		cb.button_pressed = true
		cb.toggled.connect(func(_on): _update())
		kinds[k] = cb
		kr.add_child(cb)
	odds_lbl = main._label("", 15)
	body.add_child(odds_lbl)
	body.add_child(main._label(general_words(), 13, Color("e8c860")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	row.add_child(main._button("Attack", _go))
	row.add_child(main._button("Cancel (Esc)", close))
	if not sea.is_empty():
		body.add_child(main._label(tr("Or land from the sea: up to %d soldiers waiting at headquarters sail from your %s.") % [int(sea[1]), String((sea[0] as Sim.Bld).def.name).to_lower()], 13, Color("9fd0e8")))
		body.add_child(main._button(tr("Land from the sea instead"), func(): _open_sea(t, sea)))
	_update()
	panel.visible = true
	return ""


## The window for a landing from the sea: how many sail, the ships and supplies it takes.
var sea_slider: HSlider

func _open_sea(t: Sim.Bld, sea: Array) -> void:
	var sim: Sim = main.sim
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	body.add_child(main._label(tr("Land on %s's coast: attack the %s") % [sim.players[t.p - 1].name, String(t.def.name)], 22, Main.BRASS))
	var dm: Array = sim.military.mix_of(sim.military._defending(t))
	body.add_child(main._label(tr("Defenders: %d (%s)") % [sim.defenders(t), Sim.mix_text(dm)], 14, Main.DIM))
	body.add_child(main._label(general_words(), 13, Color("e8c860")))
	var me_w := sim.human()
	if me_w.warships > 0:
		body.add_child(main._label(tr("Warships: %d afloat; escorts %s (up to %d sail with the fleet).") % [me_w.warships, tr("on") if me_w.escort else tr("off"), SimNavy.ESCORTS], 13, Color("9fd0e8")))
	var h: Sim.Bld = sea[0]
	var info := main._rich()
	info.custom_minimum_size = Vector2(460, 0)
	info.text = tr("Soldiers waiting at your headquarters board ships at your %s, %d to a ship, sail to the nearest beach to it and march from there. The ships sail home once they are ashore; a fleet beaten at sea is lost with them. Enemy ships they meet on the way are sunk.\nFar from home they live on what they carry: rations from the stores for the crossing and three rounds at the gate.") % [String(h.def.name).to_lower(), SimSea.LANDING_PER_SHIP]
	body.add_child(info)
	var cl := main._label("", 15)
	body.add_child(cl)
	sea_slider = HSlider.new()
	sea_slider.min_value = 1
	sea_slider.max_value = int(sea[1])
	sea_slider.step = 1
	sea_slider.value = int(sea[1])
	sea_slider.custom_minimum_size = Vector2(380, 24)
	var upd := func(_v = 0):
		var n := int(sea_slider.value)
		cl.text = tr("%d soldiers on %d ships, %d rations") % [n, ceili(float(n) / SimSea.LANDING_PER_SHIP), ceili(n * SimMilitary.SUPPLY_PER) + SimMilitary.ration(n) * 3]
	sea_slider.value_changed.connect(upd)
	upd.call()
	body.add_child(sea_slider)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	row.add_child(main._button(tr("Set sail"), func():
		var r := sim.military.launch_landing(h, t, int(sea_slider.value))
		close()
		main._show_hint(tr("The fleet sets sail.") if r == "" else r, 3.0)
		main._refresh_all()))
	row.add_child(main._button("Cancel (Esc)", close))
	panel.visible = true


func close() -> void:
	panel.visible = false


func _allowed() -> Array:
	var out := []
	for k in kinds:
		if (kinds[k] as CheckBox).button_pressed:
			out.append(k)
	return out


func _update() -> void:
	var sim: Sim = main.sim
	var t: Sim.Bld = sim.by_id.get(tgt_id)
	if t == null:
		close()
		return
	var n := int(slider.value)
	var src := sources(t)
	var total := 0
	for s in src:
		total += int(s[1])
	count_lbl.text = tr("Soldiers to send: %d of %d in range") % [n, total]
	var ratio := float(n) / maxf(1.0, sim.defenders(t))
	var txt := ""
	var col := Color("86ad5c")
	if _allowed().is_empty():
		txt = tr("Pick at least one kind.")
		col = Color("d9483d")
	elif ratio >= 2.0:
		txt = tr("Good odds: about %.1f to 1 in your favour.") % ratio
	elif ratio >= 1.2:
		txt = tr("Fair odds: about %.1f to 1. Walls and gun fire help the defenders.") % ratio
		col = Color("e0b060")
	else:
		txt = tr("Poor odds: they have as many or more. Send more, or wear them down first.")
		col = Color("d9483d")
	odds_lbl.text = txt
	odds_lbl.add_theme_color_override("font_color", col)


func _go() -> void:
	var sim: Sim = main.sim
	var t: Sim.Bld = sim.by_id.get(tgt_id)
	var allowed := _allowed()
	if t == null or allowed.is_empty():
		return
	var left := int(slider.value)
	var sent := 0
	var why := ""
	for s in sources(t):
		if left <= 0:
			break
		var before := sim.attacks.size()
		var r := sim.military.launch_attack(s[0], t, mini(left, int(s[1])), allowed)
		if r != "":
			why = r
			continue
		if sim.attacks.size() > before:
			var a: Sim.Attack = sim.attacks[before]
			left -= a.n
			sent += a.n
	close()
	main._show_hint(tr("%d soldiers march.") % sent if sent > 0 else why, 3.0)
	main._refresh_all()


## Where your general is, for the attack windows.
func general_words() -> String:
	var sim: Sim = main.sim
	var me := sim.human()
	var lvl := SimNavy.general_level(me.general_xp)
	if me.general_uid != 0:
		return tr("Your general (level %d) is away leading another column.") % lvl
	if sim.time < me.general_back:
		return tr("A new general will be ready in %d s.") % ceili(me.general_back - sim.time)
	return tr("Your general (level %d, +%d%% a duel) leads this column if it has %d soldiers or more.") % [lvl, roundi(lvl * SimNavy.GEN_DUEL * 100.0), SimNavy.GENERAL_MIN]
