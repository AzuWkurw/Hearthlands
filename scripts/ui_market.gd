class_name UiMarket
extends RefCounted
## The Market window (M): every good's price in gold, where it is going (a little line of the last 30
## minutes and an arrow), what you have, and buttons to sell or buy 10 at your market (SimMarket).

var main: Main
var win: Window
var head: Label
var grid: GridContainer
var only_mine: CheckBox
var routes_box: VBoxContainer
var r_res: OptionButton
var r_kind: OptionButton
var r_n: OptionButton
var r_every: OptionButton
var r_keep: SpinBox
var _r_ids: Array = []


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Market prices"
	win.transient = true
	win.wrap_controls = false
	win.size = Vector2i(900, 720)
	win.theme = UiLog.window_theme()
	win.visible = false
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.96))
	win.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	bg.add_child(v)
	head = main._label("", 14)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(head)
	only_mine = CheckBox.new()
	only_mine.text = tr("Only goods you have")
	only_mine.button_pressed = true
	only_mine.toggled.connect(func(_on): refresh())
	v.add_child(only_mine)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(grid)
	# standing orders (build 61)
	v.add_child(HSeparator.new())
	var rh := main._label(tr("Standing orders: merchants sell or buy for you every few minutes, as long as you keep what you set."), 13, Main.DIM)
	rh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(rh)
	var add := HBoxContainer.new()
	add.add_theme_constant_override("separation", 6)
	v.add_child(add)
	r_kind = OptionButton.new()
	r_kind.add_item(tr("Sell")); r_kind.add_item(tr("Buy"))
	r_kind.item_selected.connect(func(_i): _keep_hint())
	add.add_child(r_kind)
	r_n = OptionButton.new()
	for n in SimMarket.ROUTE_N: r_n.add_item(str(n))
	add.add_child(r_n)
	r_res = OptionButton.new()
	r_res.custom_minimum_size = Vector2(170, 0)
	add.add_child(r_res)
	add.add_child(main._label(tr("every"), 13))
	r_every = OptionButton.new()
	for m in SimMarket.ROUTE_EVERY: r_every.add_item(tr("%d min" % m))
	r_every.select(1)
	add.add_child(r_every)
	add.add_child(main._label(tr("keep"), 13))
	r_keep = SpinBox.new()
	r_keep.min_value = 0; r_keep.max_value = 999; r_keep.step = 5; r_keep.value = 40
	add.add_child(r_keep)
	add.add_child(main._button(tr("Add order"), _add_route))
	routes_box = VBoxContainer.new()
	v.add_child(routes_box)
	win.close_requested.connect(func(): win.visible = false)
	main.add_child(win)


func toggle() -> void:
	if win.visible:
		win.visible = false
		return
	refresh()
	win.popup_centered()


func refresh() -> void:
	var sim: Sim = main.sim
	var me := sim.human()
	var has := sim.market.has_market(me)
	head.text = (tr("Prices follow what all realms have in store: short goods grow dear, plentiful ones cheap. Your market sells at %d%% and buys at %d%% of the price. You have %d gold." % [roundi(SimMarket.SELL * 100), roundi(SimMarket.BUY * 100), int(me.stock.get("gold", 0.0))])) \
		+ ("" if has else "\n" + tr("Build a market to sell and buy here."))
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for h in ["", tr("Good"), tr("10 cost (gold)"), tr("Last 30 min"), tr("You have"), "", "", "", ""]:
		grid.add_child(main._label(h, 12, Main.DIM))
	var ids := []
	for r in GameData.resources:
		var id := String(r.id)
		if not sim.market.traded(id):
			continue
		if only_mine.button_pressed and float(me.stock.get(id, 0.0)) < 1.0:
			continue
		ids.append(id)
	for id in ids:
		var ic := TextureRect.new()
		ic.texture = Tex.get_tex("res_" + id)
		ic.custom_minimum_size = Vector2(24, 24)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		grid.add_child(ic)
		grid.add_child(main._label(GameData.res_name(id), 14))
		var tr_ := sim.market.trend(id)
		var arrow := " ▲" if tr_ > 0 else (" ▼" if tr_ < 0 else "")
		var pl := main._label("%.1f%s" % [sim.market.price(id) * 10.0, arrow], 14, Color("e07a5a") if tr_ > 0 else (Color("86ad5c") if tr_ < 0 else Color("e6e2d3")))
		pl.tooltip_text = tr("%.0f%% of its usual worth" % (sim.market.factor(id) * 100.0))
		grid.add_child(pl)
		var sp := Sparkline.new()
		sp.values = sim.price_hist.get(id, [])
		sp.custom_minimum_size = Vector2(110, 22)
		grid.add_child(sp)
		grid.add_child(main._label(str(int(me.stock.get(id, 0.0))), 14))
		var sb := main._button(tr("Sell 10 (+%d)" % sim.market.sell_price(id, 10)), func(): _do(sim.market.sell(me, id, 10)))
		sb.disabled = not has or float(me.stock.get(id, 0.0)) < 10.0
		grid.add_child(sb)
		var bb := main._button(tr("Buy 10 (-%d)" % sim.market.buy_price(id, 10)), func(): _do(sim.market.buy(me, id, 10)))
		bb.disabled = not has or float(me.stock.get("gold", 0.0)) < sim.market.buy_price(id, 10)
		grid.add_child(bb)
		# in lots of 50, so cheap goods are worth the trip (build 61)
		var sb5 := main._button(tr("Sell 50 (+%d)" % sim.market.sell_price(id, 50)), func(): _do(sim.market.sell(me, id, 50)))
		sb5.disabled = not has or float(me.stock.get(id, 0.0)) < 50.0
		grid.add_child(sb5)
		var bb5 := main._button(tr("Buy 50 (-%d)" % sim.market.buy_price(id, 50)), func(): _do(sim.market.buy(me, id, 50)))
		bb5.disabled = not has or float(me.stock.get("gold", 0.0)) < sim.market.buy_price(id, 50)
		grid.add_child(bb5)
		# tools, weapons and armor of a chosen metal, from merchants who come from afar (build 72)
		if SimArms.PICTURED.has(id) and id != "scrap":
			for k in 5:
				grid.add_child(Control.new())
			for t in [SimArms.BRONZE, SimArms.STEEL]:
				var tt: int = t
				var cost := sim.market.metal_price(id, 10, tt)
				var mb := main._button(tr("Buy 10 %s (-%d)" % [SimArms.NAMES[tt], cost]), func(): _do(sim.market.buy_metal(me, id, 10, tt)))
				mb.icon = Tex.get_tex(SimArms.icon_id(id, tt))
				mb.add_theme_constant_override("icon_max_width", 20)
				mb.disabled = not has or float(me.stock.get("gold", 0.0)) < cost
				mb.tooltip_text = tr("Merchants bring %s from afar: %s" % [GameData.res_name(id).to_lower(), tr("bronze, cheaper than the market's") if tt == SimArms.BRONZE else tr("steel, at two and a half times the price")])
				grid.add_child(mb)
			for k in 2:
				grid.add_child(Control.new())
	_refresh_routes()


func _refresh_routes() -> void:
	var sim: Sim = main.sim
	var me := sim.human()
	# the goods to pick from: everything that can be traded and that the realm knows
	var ids := []
	for r in GameData.resources:
		var id := String(r.id)
		if sim.market.traded(id) and main.res_shown(id):
			ids.append(id)
	if ids != _r_ids:
		_r_ids = ids
		var sel := r_res.selected
		r_res.clear()
		for id in ids:
			r_res.add_icon_item(Tex.get_tex("res_" + id), GameData.res_name(id))
		r_res.select(clampi(sel, 0, ids.size() - 1))
	for c in routes_box.get_children():
		routes_box.remove_child(c)
		c.queue_free()
	if me.routes.is_empty():
		routes_box.add_child(main._label(tr("No standing orders yet."), 13, Main.DIM))
	for i in me.routes.size():
		var r: Dictionary = me.routes[i]
		var row := HBoxContainer.new()
		var t := (tr("Sell %d %s every %d min while more than %d stay") if bool(r.sell) else tr("Buy %d %s every %d min up to %d in store")) % [int(r.n), GameData.res_name(String(r.res)).to_lower(), int(r.every), int(r.keep)]
		var wy := String(r.get("why", ""))
		var l := main._label(t + "  ·  " + tr("%d so far, %+d gold" % [int(r.done), int(r.gold)]) + ("  ·  " + tr("last time: %s" % tr(wy)) if wy != "" else ""), 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(main._button(tr("Remove"), func():
			sim.market.remove_route(me, i)
			refresh()))
		routes_box.add_child(row)


func _keep_hint() -> void:
	r_keep.value = 40 if r_kind.selected == 0 else 20


func _add_route() -> void:
	var sim: Sim = main.sim
	if _r_ids.is_empty():
		return
	var why := sim.market.add_route(sim.human(), String(_r_ids[maxi(0, r_res.selected)]), r_kind.selected == 0, int(SimMarket.ROUTE_N[r_n.selected]), int(SimMarket.ROUTE_EVERY[r_every.selected]), int(r_keep.value))
	if why != "":
		main._show_hint(why, 3.0)
	elif not sim.market.has_market(sim.human()):
		main._show_hint(tr("The order is kept, but it goes through only once you have a market."), 4.0)
	refresh()


func _do(why: String) -> void:
	if why != "":
		main._show_hint(why, 3.0)
	refresh()


## A little line of the price over the last minutes.
class Sparkline extends Control:
	var values: Array = []

	func _draw() -> void:
		var n := values.size()
		# the usual worth (factor 1)
		var y1 := size.y * (1.0 - (1.0 - SimMarket.MIN_F) / (SimMarket.MAX_F - SimMarket.MIN_F))
		draw_line(Vector2(0, y1), Vector2(size.x, y1), Color(1, 1, 1, 0.15), 1.0)
		if n < 2:
			return
		var lo := SimMarket.MIN_F
		var hi := SimMarket.MAX_F
		var pts := PackedVector2Array()
		for i in n:
			var f := (float(values[i]) - lo) / (hi - lo)
			pts.append(Vector2(size.x * i / float(n - 1), size.y * (1.0 - clampf(f, 0.0, 1.0))))
		draw_polyline(pts, Color("d8aa4a"), 1.5, true)
