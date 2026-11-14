class_name UiSeaGuide
extends RefCounted
## The guide to the sea and army supplies (build 56): harbours and ships, expeditions, cargo, landings,
## warships and coastal forts, river boats, and the food an army needs far from home. It opens by itself
## the first time you have a harbour or a shipyard (once, kept in the settings), and from the "Sea and
## supplies guide" buttons in a harbour's info and the attack window, or Shift+H.

var main: Main
var win: Window
var text: RichTextLabel

const PAGES := [
	["Harbours and ships", "A [b]harbour[/b] is a store on the coast. A [b]shipyard[/b] next to the water builds ships (planks), up to 6. Ships do three things:\n• [b]Cargo:[/b] between your harbours that no road joins, ships carry goods from where there is plenty to where there is little, by themselves.\n• [b]Expeditions:[/b] in a harbour's info, [i]Send an expedition[/i], then click a free coast: a ship, 4 planks, 2 stone and a soldier found a new harbour there, with land around it.\n• [b]Landings:[/b] see below.\nIn a [b]storm[/b] no ship or boat leaves the coast; wait for it to pass."],
	["Landings", "Click an enemy military building across the water. If a harbour of yours has a free ship and soldiers wait at the headquarters, the attack window offers [i]Land from the sea[/i]. Each ship carries 6 soldiers (24 at most in one landing) to the nearest beach to the target; they march from there and the ships sail home. A fleet beaten at sea goes down with its ships. Your [b]general[/b] leads any column of 5 or more while he is at home (a gold star over it)."],
	["Warships and coastal forts", "A [b]naval yard[/b] (navigators' school) builds warships from planks, iron and weapons, up to 8. They guard the water near your harbours: they chase enemy warships, fire on landing fleets coming at you and sink enemy cargo ships. With [i]Escort landings[/i] on (harbour info) up to 3 sail with each landing you send. A [b]coastal fort[/b] (star forts) fires its guns on enemy ships within 7 tiles while soldiers hold it."],
	["River boats", "A [b]river landing[/b] (timber framing) is a small store with a boat. When two of your landings lie on the same river or lake and the road between them is long (or there is none), the boat carries goods across, 6 at a time."],
	["Supplies far from home", "An army that marches more than 14 tiles from home, and every landing, takes food from the stores where it sets out: half a ration a soldier for the way and three rounds at the gate. At the gate it eats a ration for every four soldiers every 20 seconds. [b]Hungry soldiers lose more duels[/b], and starving ones much more. Keep the stores full before a long march, and build a [b]field depot[/b] (pack mules) near the front: carriers fill it with food, and an army attacking within 14 tiles eats from it."],
]


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Sea and supplies guide"
	win.transient = true
	win.wrap_controls = false
	win.size = Vector2i(680, 600)
	win.theme = UiLog.window_theme()
	win.visible = false
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.96))
	win.add_child(bg)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	bg.add_child(text)
	win.close_requested.connect(func(): win.visible = false)
	main.add_child(win)


func open() -> void:
	var t := ""
	for pg in PAGES:
		t += "[color=#d8aa4a][font_size=18]%s[/font_size][/color]\n%s\n\n" % [tr(String(pg[0])), tr(String(pg[1]))]
	text.text = t
	win.popup_centered()


## Once a second: the first harbour or shipyard opens the guide (once ever).
func check() -> void:
	if main.settings.sea_guide or main.sim == null or main.sim.players.is_empty():
		return
	for b: Sim.Bld in main.sim.realm_blds(main.sim.human()):
		if (b.ty == "harbour" or b.ty == "shipyard" or b.ty == "river_landing") and b.state == "ready":
			main.settings.sea_guide = true
			main.settings.save_file()
			open()
			return
