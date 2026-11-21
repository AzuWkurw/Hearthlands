class_name UiTips
extends RefCounted
## Short tips the first time something happens: the first new age, the first factory smoke in your
## homes, the first worn-out tool. Each shows once ever (kept in the settings) in a small box near the
## top of the screen, with a button to its handbook page. "No more tips" or the Settings check box turns
## them off; turning them on again shows them all again. The tips only look at the game, never change it.

var main: Main
var box: PanelContainer
var title_lbl: Label
var body: RichTextLabel
var more_btn: Button
var tip := ""                # the tip shown now, or ""
var _sim: Sim = null         # the game the starting values below belong to
var _age0 := 0               # your age when this game was started or loaded
var _worn0 := 0              # tools worn out by then

## [id, title, text, handbook page]
const TIPS := [
	["age", "A new age", "Your realm has entered a new age. New techs are open in the research window, and with them new buildings and stronger soldiers. Each age also has its own mastery studies.", "age"],
	["smoke", "Factory smoke", "Smoke from your factories has reached homes. Smoky homes lower your realm's health: work slows and fevers spread. A park takes away half the smoke of the homes near it, and a waterworks gives them clean water. Keep smelters and mills away from houses.", "feat:factory_health"],
	["tool", "A worn-out tool", "One of your workers has worn out his tool. He takes a new one from the stores; if there is none, he works on a quarter slower. Keep a toolsmith busy and a few tools of each kind in store.", "feat:tool_quality"],
]


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	box = PanelContainer.new()
	var sb: StyleBoxFlat = main._panel_style(0.95)
	sb.border_color = Main.BRASS
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(420, 0)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	title_lbl = main._label("", 16, Main.BRASS)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_lbl)
	var x := Button.new()
	x.text = "x"
	x.flat = true
	x.tooltip_text = "Close the tip"
	x.pressed.connect(close)
	top.add_child(x)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(400, 0)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_color_override("default_color", Color("e6e2d3"))
	v.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	more_btn = main._button("Read more in the handbook", func():
		var pg := _page(tip)
		close()
		main.handbook_ui.open(pg))
	row.add_child(more_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var off := main._button("No more tips", func():
		main.settings.tips = false
		main.settings.save_file()
		close())
	off.tooltip_text = "Settings can turn the tips on again."
	row.add_child(off)
	row.add_child(main._button("Got it", close))
	main.add_child(box)


func _def(id: String) -> Array:
	for t in TIPS:
		if String(t[0]) == id:
			return t
	return []


## The handbook page of a tip; the new-age tip opens the page of the age you are in.
func _page(id: String) -> String:
	var d := _def(id)
	if d.is_empty():
		return "home"
	var pg := String(d[3])
	if pg == "age" and main.sim != null and not main.sim.players.is_empty():
		pg = "age:%d" % main.sim.human().age
	return pg


func close() -> void:
	tip = ""
	if box != null:
		box.visible = false


## Shows tip id (once ever, while tips are on). Returns whether it was shown.
func show_tip(id: String) -> bool:
	var d := _def(id)
	if d.is_empty() or not main.settings.tips or main.settings.tips_seen.has(id) or tip != "":
		return false
	main.settings.tips_seen[id] = true
	main.settings.save_file()
	tip = id
	title_lbl.text = String(d[1])
	body.text = String(d[2])
	box.visible = true
	box.reset_size()
	var vp := main.get_viewport().get_visible_rect().size
	box.position = Vector2(roundf((vp.x - box.size.x) / 2.0), 96)
	if main.sound != null:
		main.sound.play("good", 0.5)
	return true


## Once a second: shows a tip whose moment has come.
func check() -> void:
	var sim: Sim = main.sim
	if sim == null or sim.players.is_empty() or sim.w == 0 or sim.over:
		return
	var p := sim.human()
	if sim != _sim:
		_sim = sim
		_age0 = p.age
		_worn0 = p.tools_worn
	if not main.settings.tips or tip != "" or main.setup.visible or main.editor_ui.open:
		return
	if main.age_ui.panel != null and main.age_ui.panel.visible:
		return
	if p.age > _age0 and show_tip("age"):
		return
	var fh = sim.get_feature("factory_health")
	if fh != null and fh.air_of(p) > 0.02 and show_tip("smoke"):
		return
	if p.tools_worn > _worn0 and show_tip("tool"):
		return
