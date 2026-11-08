class_name UiDemolish
extends RefCounted
## The window that asks before a building is demolished.
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main`.

var main: Main

var confirm_id := 0                # the building waiting for "Demolish" to be confirmed
var _cam_before := Vector2.ZERO    # where the map was before it moved to show what would be lost
var _zoom_before := 0.0


func _init(p_owner: Main) -> void:
	main = p_owner


func _build_confirm_panel() -> void:
	main.confirm_panel = main._overlay()
	var v: VBoxContainer = main.confirm_panel.find_child("Body", true, false)
	main.confirm_title = main._label("", 20, Main.BRASS)
	v.add_child(main.confirm_title)
	main.confirm_text = main._rich()
	main.confirm_text.custom_minimum_size = Vector2(440, 0)
	v.add_child(main.confirm_text)
	var dont := CheckBox.new()
	dont.text = "Don't ask again (turn it back on under Textures and mods)"
	dont.focus_mode = Control.FOCUS_NONE
	dont.name = "Dont"
	v.add_child(dont)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(main._button("Keep it (Esc)", func(): main.confirm_panel.visible = false))
	# closing the window, either way, takes the preview off the map and puts the map back
	main.confirm_panel.visibility_changed.connect(func():
		if not main.confirm_panel.visible and not main.view.preview_tiles.is_empty() or not main.confirm_panel.visible and not main.view.preview_blds.is_empty():
			_end_preview())
	var go := main._button("Demolish (Enter)", _do_demolish)
	go.add_theme_color_override("font_color", Color("f08a7a"))
	row.add_child(go)
	main.confirm_panel.visible = false


## Shows what demolishing b would mean and waits for an answer, or demolishes at once if asking is off.
func _ask_demolish(b: Sim.Bld) -> void:
	confirm_id = b.id
	if not main.ask_demolish:
		_do_demolish()
		return
	main.confirm_title.text = "Demolish the %s?" % String(b.def.name).to_lower()
	main.confirm_text.text = "\n".join(demolish_effects(b))
	(main.confirm_panel.find_child("Dont", true, false) as CheckBox).button_pressed = false
	_preview(b)
	main.confirm_panel.visible = true


## Shows on the map the land and buildings that demolishing b would lose: the window's dark backdrop
## is lifted and the map moves so the building sits left of the window.
func _preview(b: Sim.Bld) -> void:
	var loss := main.sim.territory_loss(b)
	var tiles: PackedInt32Array = loss.tiles
	var bg: ColorRect = main.confirm_panel.get_child(0)
	if tiles.is_empty() and (loss.blds as Array).is_empty():
		bg.color.a = 0.8
		return
	main.view.preview_tiles = tiles
	main.view.preview_blds = (loss.blds as Array).map(func(o): return o.id)
	bg.color.a = 0.15
	_cam_before = main.view.cam
	_zoom_before = main.view.zoom
	var r := float(b.def.get("radius", 6)) + 3.0
	var room := maxf(120.0, (main.view.size.x - 500.0) / 2.0)
	main.view.zoom = clampf(room / r / 1.1, 6.0, 28.0)
	main.view.cam = Vector2(b.x + 0.5, b.y + 0.5) + Vector2(main.view.size.x / 2.0 - room / 2.0 - 10.0, 0) / main.view.zoom
	main.view.queue_redraw()


func _end_preview() -> void:
	main.view.preview_tiles = PackedInt32Array()
	main.view.preview_blds = []
	(main.confirm_panel.get_child(0) as ColorRect).color.a = 0.8
	if _zoom_before > 0.0:
		main.view.cam = _cam_before
		main.view.zoom = _zoom_before
		_zoom_before = 0.0
	main.view.queue_redraw()


## Plain-language list of what happens when building b is demolished.
func demolish_effects(b: Sim.Bld) -> PackedStringArray:
	var out := PackedStringArray()
	var p: Sim.Player = main.sim.players[b.p - 1]
	var back := []
	var cost: Dictionary = b.def.get("cost", {})
	for k in cost:
		var n := int(floorf(float(cost[k]) * 0.4))
		if n > 0:
			back.append("%d %s" % [n, GameData.res_name(k).to_lower()])
	if back.is_empty():
		out.append("You get nothing back.")
	else:
		out.append("You get back [b]%s[/b] (40%% of what it cost, rounded down)." % ", ".join(back))
	if b.state == "build":
		out.append("Construction stops; the work done so far is lost.")
	var lost := []
	for k in b.out_buf:
		if int(b.out_buf[k]) > 0:
			lost.append("%d %s" % [int(b.out_buf[k]), GameData.res_name(k).to_lower()])
	if not lost.is_empty():
		out.append("[color=#f08a7a]Goods waiting for a carrier are lost: %s.[/color]" % ", ".join(lost))
	if b.state == "ready" and b.staffed and b.def.has("worker"):
		var lv := Sim.level(b.wxp, Sim.WORKER_XP)
		var title := GameData.trade_title(GameData.trade(b.ty))
		if lv > 1:
			out.append("Its %s (level %d) goes back to the idle workers and keeps his skill for the next %s job." % [title, lv, GameData.trade_name(GameData.trade(b.ty)).to_lower()])
		else:
			out.append("Its %s goes back to the idle workers." % String(b.def.worker))
	if b.def.has("garrison") and b.state == "ready":
		if b.garrison > 0:
			out.append("Its %d soldier%s return%s to the headquarters." % [b.garrison, "s" if b.garrison != 1 else "", "" if b.garrison != 1 else "s"])
		var loss: Dictionary = main.sim.territory_loss(b)
		var nt: int = (loss.tiles as PackedInt32Array).size()
		if nt == 0:
			out.append("[color=#8fc070]Your border stays as it is: other buildings hold all its land.[/color]")
		else:
			var rv := ""
			if int(loss.rival) > 0:
				rv = ", %d of them to a rival" % int(loss.rival)
			out.append("[color=#f08a7a]You lose [b]%d tiles[/b] of land%s (red on the map).[/color]" % [nt, rv])
			var gone: Array = loss.blds
			if gone.is_empty():
				out.append("No other building of yours is lost.")
			else:
				var count := {}
				for o in gone:
					var nm := String(o.def.name)
					count[nm] = int(count.get(nm, 0)) + 1
				var parts := []
				for nm in count:
					parts.append(("%d × %s" % [count[nm], nm]) if int(count[nm]) > 1 else String(nm))
				out.append("[color=#f08a7a][b]These buildings are left outside the border and lost:[/b] %s (crossed out on the map).[/color]" % ", ".join(parts))
	if main.sim.is_store(b) and b.state == "ready":
		var left: int = p.store_total - int(b.def.store)
		out.append("[color=#f08a7a]Storage drops to %d of each good; goods above that are lost.[/color]" % left)
	if b.def.has("carriers") and b.state == "ready":
		out.append("Its %s stop carrying goods." % ("mules" if String(b.def.carriers.kind) == "mule" else "carts"))
	return out


func _do_demolish() -> void:
	var dont: CheckBox = main.confirm_panel.find_child("Dont", true, false)
	if main.confirm_panel.visible and dont.button_pressed:
		main.ask_demolish = false
		main.settings.ask_demolish = false
		main.settings.save_file()
	main.confirm_panel.visible = false
	var b: Sim.Bld = main.sim.by_id.get(confirm_id)
	if b == null or b.p != 1:
		main._show_hint("That building is already gone.", 3.0)
		return
	main.sim.demolish(b)
	if main.sound != null:
		main.sound.play("demolish", 0.8)
	if main.view.sel_id == b.id:
		main.view.sel_id = 0
	main._refresh_all()
