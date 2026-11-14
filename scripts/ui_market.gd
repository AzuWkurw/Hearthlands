class_name UiMarket
extends RefCounted
## The Market window (M): every good's price in gold, where it is going (a little line of the last 30
## minutes and an arrow), what you have, and buttons to sell or buy 10 at your market (SimMarket).

var main: Main
var win: Window
var head: Label
var grid: GridContainer
var only_mine: CheckBox


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Market prices"
	win.transient = true
	win.wrap_controls = false
	win.size = Vector2i(720, 640)
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
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(grid)
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
	head.text = (tr("Prices follow what all realms have in store: short goods grow dear, plentiful ones cheap. Your market sells at %d%% and buys at %d%% of the price. You have %d gold.") % [roundi(SimMarket.SELL * 100), roundi(SimMarket.BUY * 100), int(me.stock.get("gold", 0.0))]) \
		+ ("" if has else "\n" + tr("Build a market to sell and buy here."))
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for h in ["", tr("Good"), tr("10 cost (gold)"), tr("Last 30 min"), tr("You have"), "", ""]:
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
		pl.tooltip_text = tr("%.0f%% of its usual worth") % (sim.market.factor(id) * 100.0)
		grid.add_child(pl)
		var sp := Sparkline.new()
		sp.values = sim.price_hist.get(id, [])
		sp.custom_minimum_size = Vector2(110, 22)
		grid.add_child(sp)
		grid.add_child(main._label(str(int(me.stock.get(id, 0.0))), 14))
		var sb := main._button(tr("Sell 10 (+%d)") % sim.market.sell_price(id, 10), func(): _do(sim.market.sell(me, id, 10)))
		sb.disabled = not has or float(me.stock.get(id, 0.0)) < 10.0
		grid.add_child(sb)
		var bb := main._button(tr("Buy 10 (-%d)") % sim.market.buy_price(id, 10), func(): _do(sim.market.buy(me, id, 10)))
		bb.disabled = not has or float(me.stock.get("gold", 0.0)) < sim.market.buy_price(id, 10)
		grid.add_child(bb)


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
