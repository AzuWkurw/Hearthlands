extends Feature
## Realm laws (build 77): every realm sets five laws (taxes, food rations, conscription, the working day
## and road tolls), each with three options from data/laws.json. The usual option of each changes
## nothing. The others trade something the realm gains (gold, work speed, soldiers) against the
## contentment of some of its four classes of people (peasants, artisans, nobles, soldiers).
##
## How a class's contentment works on the realm:
## - the realm's contentment (the contentment feature) moves by the classes' changes, weighted by how
##   many people each class has; peasants leave when the peasants' own contentment is low;
## - unhappy nobles pay less tax, unhappy artisans and peasants work slower in their workplaces, and
##   unhappy soldiers train slower (and content ones faster).
## A law can be changed again CHANGE_WAIT seconds after its last change. Rivals choose their laws by
## their personality (the "ai" table) and change them when food runs short, when they are at war or
## when their people grow unhappy.

const CHANGE_WAIT := 120.0
const CLASSES := ["peasant", "artisan", "noble", "soldier"]
const CLASS_NAMES := {"peasant": "Peasants", "artisan": "Artisans", "noble": "Nobles", "soldier": "Soldiers"}
const WORK_MOOD := 0.2     # work speed change for each 1.0 of a working class's contentment change
const TRAIN_MOOD := 0.3    # training speed change for each 1.0 of the soldiers' contentment change
const TAX_MOOD := 0.5      # noble tax change for each 1.0 of the nobles' contentment change
const AI_EVERY := 60       # seconds between a rival's looks at its laws
const TOLL_KINDS := ["porter", "mule", "cart"]  # carriers with goods that pay road tolls
const LOW_MOOD := 0.35     # a rival under this contentment eases its laws

static var _data: Dictionary = {}
static var _tr_added := false

var laws := {}        # realm id -> {law id -> option id} (only laws not at their default)
var changed := {}     # realm id -> {law id -> game time of its last change}
var tolls := {}       # realm id -> gold taken in tolls so far
var toll_acc := {}    # realm id -> gold building up towards the next whole coin
var _eff := {}        # (not saved) realm id -> the laws' summed effects, worked out again when a law changes
var _t := 0

# the interface
var win: Window
var rows := {}        # law id -> OptionButton
var notes := {}       # law id -> Label
var moods_lbl: RichTextLabel
var rivals_lbl: RichTextLabel
var status_lbl: Label
var _main: Main
var _quiet := false   # (not saved) while the window fills its lists


func _init() -> void:
	id = "laws"
	title = "Realm laws"
	info = "Laws: taxes, food rations, conscription, the working day and road tolls. Each one pleases some classes of people and displeases others. Rivals choose theirs by their character."
	default_on = true


## The laws file (data/laws.json), read once.
static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/laws.json"))
		_data = d if d is Dictionary else {"laws": [], "ai": {}, "pl": {}}
	return _data


static func law_list() -> Array:
	return data().get("laws", [])


static func law_def(lid: String) -> Dictionary:
	for l: Dictionary in law_list():
		if String(l.id) == lid:
			return l
	return {}


static func option_def(lid: String, oid: String) -> Dictionary:
	for o: Dictionary in law_def(lid).get("options", []):
		if String(o.id) == oid:
			return o
	return {}


## Adds the Polish text of the laws to the game's translations (once).
static func add_translations() -> void:
	if _tr_added:
		return
	_tr_added = true
	var pl: Dictionary = data().get("pl", {})
	if pl.is_empty():
		return
	var t := Translation.new()
	t.locale = "pl"
	for k in pl:
		t.add_message(String(k), String(pl[k]))
	TranslationServer.add_translation(t)


func on_start(loaded: bool) -> void:
	add_translations()
	_eff.clear()
	if not loaded:
		# a new game (or the feature just switched on): the rivals pick their laws straight away
		for p: Sim.Player in sim.players:
			if p.ai and p.alive:
				_ai_choose(p, true)


# ---------------------------------------------------------------- laws and their effects
## The option realm p has for law lid.
func law_of(p: Sim.Player, lid: String) -> String:
	var mine: Dictionary = laws.get(p.id, {})
	return String(mine.get(lid, law_def(lid).get("default", "")))


## Seconds until realm p may change law lid again (0: now).
func wait_left(p: Sim.Player, lid: String) -> float:
	var at := float((changed.get(p.id, {}) as Dictionary).get(lid, -1e9))
	return maxf(0.0, at + CHANGE_WAIT - sim.time)


## Sets law lid of realm p to option oid. Returns "" or why it cannot be done.
func set_law(p: Sim.Player, lid: String, oid: String, force := false) -> String:
	var od := option_def(lid, oid)
	if od.is_empty():
		return "No such law"
	if law_of(p, lid) == oid:
		return ""
	if not force and wait_left(p, lid) > 0.0:
		return "This law can be changed again in %d s" % ceili(wait_left(p, lid))
	if not laws.has(p.id):
		laws[p.id] = {}
	if oid == String(law_def(lid).get("default", "")):
		(laws[p.id] as Dictionary).erase(lid)
	else:
		laws[p.id][lid] = oid
	if not changed.has(p.id):
		changed[p.id] = {}
	changed[p.id][lid] = sim.time
	_eff.erase(p.id)
	if not p.ai:
		sim.emit_log("New law: %s: %s." % [String(law_def(lid).name), String(od.name)], Color("e8c870"))
	return ""


## The summed effects of realm p's laws: {"tax", "food", "work", "train", "carry", "toll", "mood": {class: change}}.
func effects(p: Sim.Player) -> Dictionary:
	if _eff.has(p.id):
		return _eff[p.id]
	var e := {"tax": 0.0, "food": 0.0, "work": 0.0, "train": 0.0, "carry": 0.0, "toll": 0.0, "mood": {}}
	for c in CLASSES:
		e.mood[c] = 0.0
	for l: Dictionary in law_list():
		var od := option_def(String(l.id), law_of(p, String(l.id)))
		var fx: Dictionary = od.get("effects", {})
		for k in fx:
			if k == "mood":
				for c in fx.mood:
					e.mood[c] = float(e.mood.get(c, 0.0)) + float(fx.mood[c])
			elif e.has(k):
				e[k] = float(e[k]) + float(fx[k])
	_eff[p.id] = e
	return e


## How much the laws change class cls's contentment in realm p (-1 to 1).
func class_delta(p: Sim.Player, cls: String) -> float:
	return float((effects(p).mood as Dictionary).get(cls, 0.0))


## How many people of class cls realm p has.
func class_count(p: Sim.Player, cls: String) -> int:
	match cls:
		"peasant": return p.peasant
		"artisan": return p.artisan
		"noble": return p.noble
		"soldier": return sim.soldiers(p)
	return 0


## The change of the whole realm's contentment: the classes' changes weighted by their numbers.
func mood_shift(p: Sim.Player) -> float:
	var tot := 0
	var sum := 0.0
	for c in CLASSES:
		var n := class_count(p, c)
		tot += n
		sum += n * class_delta(p, c)
	return sum / tot if tot > 0 else 0.0


## Class cls's contentment in realm p (0 to 1): the realm's own, without the laws' average, plus the
## class's own change from the laws.
func class_mood(p: Sim.Player, cls: String) -> float:
	var ct = sim.get_feature("contentment")
	var base: float = (float(ct.mood(p)) - mood_shift(p)) if ct != null else 0.5
	return clampf(base + class_delta(p, cls), 0.0, 1.0)


func speed_bonus(p: Sim.Player, b: Sim.Bld) -> float:
	var e := effects(p)
	if String(b.def.get("train", "")) == "soldier":
		return float(e.train) + TRAIN_MOOD * class_delta(p, "soldier")
	var wk := String(b.def.get("worker", ""))
	if wk == "":
		return 0.0
	var bonus := float(e.work)
	if wk == "artisan" or wk == "peasant":
		bonus += WORK_MOOD * class_delta(p, wk)
	return bonus


func food_factor(p: Sim.Player) -> float:
	return 1.0 + float(effects(p).food)


func carry_factor(p: Sim.Player) -> float:
	return 1.0 + float(effects(p).carry)


func tax_factor(p: Sim.Player) -> float:
	return maxf(0.0, (1.0 + float(effects(p).tax)) * (1.0 + TAX_MOOD * class_delta(p, "noble")))


func on_second() -> void:
	_t += 1
	# road tolls: every 10 seconds, for each carrier with goods on the road
	if _t % 10 == 0:
		var on_road := {}
		for tp: Sim.Trip in sim.trips:
			if tp.res != "" and tp.kind in TOLL_KINDS:
				on_road[tp.p] = int(on_road.get(tp.p, 0)) + 1
		for p: Sim.Player in sim.players:
			if not p.alive:
				continue
			var toll := float(effects(p).toll)
			if toll <= 0.0:
				continue
			var acc := float(toll_acc.get(p.id, 0.0)) + toll * int(on_road.get(p.id, 0)) * 10.0 / 60.0
			if acc >= 1.0:
				var n := floorf(acc)
				sim.give(p, "gold", n)
				acc -= n
				tolls[p.id] = int(tolls.get(p.id, 0)) + int(n)
			toll_acc[p.id] = acc
	for p: Sim.Player in sim.players:
		if p.ai and p.alive and (_t + p.id * 7) % AI_EVERY == 0:
			_ai_choose(p, false)


# ---------------------------------------------------------------- rivals
## Rival p looks at its laws: its personality's choice, eased when food is short or its people are
## unhappy, a levy in wartime.
func _ai_choose(p: Sim.Player, start: bool) -> void:
	var ai: Dictionary = data().get("ai", {})
	var want: Dictionary = (ai.get(p.pers, ai.get("balanced", {})) as Dictionary).duplicate()
	if not start:
		var pop := sim.pop_total(p)
		var food := sim.food_total(p)
		if p.starve > 0 or food < pop * 0.3:
			want["rations"] = "meagre"
		elif food < pop * 1.5 and String(want.get("rations", "")) == "generous":
			want["rations"] = "usual"
		var at_war := false
		for q: Sim.Player in sim.players:
			if q.id != p.id and q.alive and Diplomacy.relation(sim, p.id, q.id) == Diplomacy.WAR:
				at_war = true
				break
		if at_war and p.pers != "builder":
			want["conscription"] = "levy"
		var ct = sim.get_feature("contentment")
		if ct != null and float(ct.mood(p)) < LOW_MOOD:
			# unhappy: every law that displeases its people goes back to the usual
			for lid in want:
				var fx: Dictionary = option_def(String(lid), String(want[lid])).get("effects", {})
				var m := 0.0
				for c in (fx.get("mood", {}) as Dictionary):
					m += float(fx.mood[c])
				if m < 0.0:
					want[lid] = String(law_def(String(lid)).get("default", "usual"))
	for lid in want:
		if not law_def(String(lid)).is_empty() and law_of(p, String(lid)) != String(want[lid]):
			set_law(p, String(lid), String(want[lid]), start)


# ---------------------------------------------------------------- text
## The effects of one option as short text ("work speed +10%, Peasants -14").
func effect_text(od: Dictionary) -> String:
	var fx: Dictionary = od.get("effects", {})
	var bits := PackedStringArray()
	if fx.has("tax"): bits.append(tr("noble tax %+d%%") % roundi(float(fx.tax) * 100.0))
	if fx.has("food"): bits.append(tr("food eaten %+d%%") % roundi(float(fx.food) * 100.0))
	if fx.has("work"): bits.append(tr("work speed %+d%%") % roundi(float(fx.work) * 100.0))
	if fx.has("train"): bits.append(tr("training %+d%%") % roundi(float(fx.train) * 100.0))
	if fx.has("carry"): bits.append(tr("carriers %+d%%") % roundi(float(fx.carry) * 100.0))
	if fx.has("toll"): bits.append(tr("tolls %.2f gold a minute per carrier") % float(fx.toll))
	for c in CLASSES:
		var m := float((fx.get("mood", {}) as Dictionary).get(c, 0.0))
		if m != 0.0:
			bits.append(tr("%s %+d") % [tr(CLASS_NAMES[c]), roundi(m * 100.0)])
	return ", ".join(bits) if not bits.is_empty() else tr("no effect")


## The laws of realm p that are not at their usual, as text.
func laws_text(p: Sim.Player) -> String:
	var bits := PackedStringArray()
	for l: Dictionary in law_list():
		var oid := law_of(p, String(l.id))
		if oid != String(l.get("default", "")):
			bits.append("%s: %s" % [tr(String(l.name)), tr(String(option_def(String(l.id), oid).name))])
	return ", ".join(bits) if not bits.is_empty() else tr("Usual")


func moods_text(p: Sim.Player) -> String:
	var bits := PackedStringArray()
	for c in CLASSES:
		var m := class_mood(p, c)
		var col := "#86ad5c" if m >= 0.6 else ("#d9483d" if m < 0.3 else "#e7e3d0")
		bits.append("%s [color=%s]%d%%[/color]" % [tr(CLASS_NAMES[c]), col, roundi(m * 100.0)])
	return ", ".join(bits)


func panel_lines(p: Sim.Player) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(tr("Laws  %s") % laws_text(p))
	out.append(tr("Contentment by class  %s") % moods_text(p))
	if int(tolls.get(p.id, 0)) > 0:
		out.append(tr("Tolls this game  %d gold") % int(tolls[p.id]))
	return out


# ---------------------------------------------------------------- the window
func build_ui(main: Main) -> void:
	_main = main
	add_translations()
	main.add_feature_button(self, tr("Laws"), open)
	main.add_feature_key(self, KEY_F8, open)
	win = main.add_feature_window(self, tr("Laws (F8)"), Vector2i(660, 640))
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	var head := Label.new()
	head.text = tr("Each law makes some classes happier and others less so. Contentment by class (with the laws now in force):")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	moods_lbl = RichTextLabel.new()
	moods_lbl.bbcode_enabled = true
	moods_lbl.fit_content = true
	moods_lbl.scroll_active = false
	box.add_child(moods_lbl)
	rows.clear()
	notes.clear()
	for l: Dictionary in law_list():
		var lid := String(l.id)
		box.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		box.add_child(row)
		var lbl := Label.new()
		lbl.text = tr(String(l.name))
		lbl.custom_minimum_size = Vector2(170, 0)
		lbl.tooltip_text = tr(String(l.get("info", "")))
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(lbl)
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for o: Dictionary in l.options:
			ob.add_item(tr(String(o.name)))
			ob.set_item_metadata(ob.item_count - 1, String(o.id))
			ob.set_item_tooltip(ob.item_count - 1, effect_text(o))
		ob.item_selected.connect(func(i): _picked(lid, String(ob.get_item_metadata(i))))
		row.add_child(ob)
		rows[lid] = ob
		var note := Label.new()
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Color("b8b49c"))
		box.add_child(note)
		notes[lid] = note
	box.add_child(HSeparator.new())
	var how := Label.new()
	how.text = tr("Unhappy nobles pay less tax, unhappy artisans and peasants work slower, unhappy soldiers train slower, and unhappy peasants leave.") + " " + tr("A law can be changed again %d s after its last change.") % int(CHANGE_WAIT)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_color_override("font_color", Color("b8b49c"))
	box.add_child(how)
	status_lbl = Label.new()
	status_lbl.add_theme_color_override("font_color", Color("e0b060"))
	box.add_child(status_lbl)
	var rh := Label.new()
	rh.text = tr("Rivals' laws")
	box.add_child(rh)
	rivals_lbl = RichTextLabel.new()
	rivals_lbl.bbcode_enabled = true
	rivals_lbl.fit_content = true
	rivals_lbl.scroll_active = false
	box.add_child(rivals_lbl)


func open() -> void:
	if win == null:
		return
	win.visible = not win.visible
	if win.visible:
		status_lbl.text = ""
		refresh()
		win.grab_focus()


func _picked(lid: String, oid: String) -> void:
	if _quiet:
		return
	var why := set_law(sim.human(), lid, oid)
	status_lbl.text = tr(why) if why != "" else ""
	refresh()


func refresh_ui(_m: Main) -> void:
	if win != null and win.visible:
		refresh()


func refresh() -> void:
	if win == null or sim.players.is_empty():
		return
	var p := sim.human()
	_quiet = true
	for l: Dictionary in law_list():
		var lid := String(l.id)
		var ob: OptionButton = rows.get(lid)
		if ob == null:
			continue
		var cur := law_of(p, lid)
		for i in ob.item_count:
			if String(ob.get_item_metadata(i)) == cur and ob.selected != i:
				ob.select(i)
		var wl := wait_left(p, lid)
		ob.disabled = wl > 0.0
		var txt := tr(String(l.get("info", ""))) + "\n" + tr("Effects: %s") % effect_text(option_def(lid, cur))
		if wl > 0.0:
			txt += "  (" + tr("can change again in %d s") % ceili(wl) + ")"
		(notes[lid] as Label).text = txt
	_quiet = false
	moods_lbl.text = moods_text(p)
	var rl := PackedStringArray()
	for q: Sim.Player in sim.players:
		if q.ai and q.alive:
			rl.append("[color=#%s]%s[/color]: %s" % [q.color.lightened(0.3).to_html(false), q.name, laws_text(q)])
	rivals_lbl.text = "\n".join(rl)


func save_state() -> Dictionary:
	return {"laws": laws, "changed": changed, "tolls": tolls, "toll_acc": toll_acc, "t": _t}


func load_state(d: Dictionary) -> void:
	for key in ["laws", "changed", "tolls", "toll_acc"]:
		var dst: Dictionary = get(key)
		dst.clear()
		var src: Dictionary = d.get(key, {})
		for k in src:
			dst[int(k)] = (src[k] as Dictionary).duplicate() if src[k] is Dictionary else src[k]
	_t = int(d.get("t", 0))
	_eff.clear()
