extends Feature
## Production statistics: for every realm and every game minute, how much of each good was made and
## used, plus its population, buildings, soldiers and research. The Statistics window (F2) shows charts.

const KEEP := 240                  # minutes kept

var hist := {}                     # realm id -> Array of finished minutes (Dictionaries, oldest first)
var cur := {}                      # realm id -> the minute being counted now
var minute := -1

var win: Window
var goods_list: ItemList
var range_opt: OptionButton
var chart: LineChart
var table: RichTextLabel
var realm_metric: OptionButton
var realm_chart: LineChart
var realm_legend: RichTextLabel
var sel_good := "planks"


func _init() -> void:
	id = "statistics"
	title = "Production statistics"
	info = "Counts what every realm makes and uses each minute; charts in the Statistics window (F2)."


func on_start(loaded: bool) -> void:
	if not loaded:
		hist = {}
		cur = {}
	# (a loaded game keeps the minute being counted; saves from before build 33 did not have it)
	if not loaded or minute < 0:
		minute = int(sim.time / 60.0)


func _bucket(p: Sim.Player) -> Dictionary:
	if not cur.has(p.id):
		cur[p.id] = {"made": {}, "used": {}}
	return cur[p.id]


func on_made(p: Sim.Player, res: String, n: float) -> void:
	var m: Dictionary = _bucket(p).made
	m[res] = float(m.get(res, 0.0)) + n


func on_used(p: Sim.Player, res: String, n: float) -> void:
	var u: Dictionary = _bucket(p).used
	u[res] = float(u.get(res, 0.0)) + n


## Each new game minute closes the minute just counted, with a snapshot of each realm.
func on_second() -> void:
	var now := int(sim.time / 60.0)
	if now == minute:
		return
	minute = now
	for p: Sim.Player in sim.players:
		var b := _bucket(p)
		b["pop"] = sim.pop_total(p)
		b["bld"] = sim.realm_blds(p).size()
		b["sol"] = sim.soldiers(p)
		b["rp"] = p.rp_total
		b["alive"] = p.alive
		var made_total := 0.0
		for k in b.made:
			if k != "research":
				made_total += float(b.made[k])
		b["made_total"] = made_total
		if not hist.has(p.id):
			hist[p.id] = []
		(hist[p.id] as Array).append(b)
		if (hist[p.id] as Array).size() > KEEP:
			(hist[p.id] as Array).pop_front()
		cur[p.id] = {"made": {}, "used": {}}
	if win != null and win.visible:
		refresh()


func save_state() -> Dictionary:
	return {"hist": hist, "cur": cur, "minute": minute}


func load_state(d: Dictionary) -> void:
	hist = d.get("hist", {})
	cur = d.get("cur", {})
	minute = int(d.get("minute", -1))


func build_ui(main: Main) -> void:
	main.add_feature_button(self, "Statistics", open)
	main.add_feature_key(self, KEY_F2, open)
	win = main.add_feature_window(self, "Statistics (F2)", Vector2i(760, 520))
	var tabs := TabContainer.new()
	tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.add_child(tabs)
	# goods: made and used per minute for one good
	var goods := HBoxContainer.new()
	goods.name = "Goods"
	tabs.add_child(goods)
	goods_list = ItemList.new()
	goods_list.custom_minimum_size = Vector2(190, 0)
	for r in GameData.resources:
		goods_list.add_item(String(r.name), Tex.get_tex("res_" + String(r.id)))
		goods_list.set_item_metadata(goods_list.item_count - 1, String(r.id))
	goods_list.fixed_icon_size = Vector2i(18, 18)
	goods_list.item_selected.connect(func(i): sel_good = String(goods_list.get_item_metadata(i)); refresh())
	goods.add_child(goods_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goods.add_child(right)
	range_opt = OptionButton.new()
	for t in ["Last 30 minutes", "Last hour", "Last 4 hours"]:
		range_opt.add_item(t)
	range_opt.select(1)
	range_opt.item_selected.connect(func(_i): refresh())
	right.add_child(range_opt)
	chart = LineChart.new()
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(chart)
	table = RichTextLabel.new()
	table.bbcode_enabled = true
	table.custom_minimum_size = Vector2(0, 120)
	right.add_child(table)
	# realms: compare everyone over time
	var realms := VBoxContainer.new()
	realms.name = "Realms"
	tabs.add_child(realms)
	realm_metric = OptionButton.new()
	for t in ["Population", "Buildings", "Soldiers", "Goods made per minute", "Research points (total)"]:
		realm_metric.add_item(t)
	realm_metric.item_selected.connect(func(_i): refresh())
	realms.add_child(realm_metric)
	realm_chart = LineChart.new()
	realm_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	realms.add_child(realm_chart)
	realm_legend = RichTextLabel.new()
	realm_legend.bbcode_enabled = true
	realm_legend.fit_content = true
	realms.add_child(realm_legend)


func open() -> void:
	win.visible = not win.visible
	if win.visible:
		refresh()


func _span() -> int:
	return [30, 60, 240][range_opt.selected]


## Refills both tabs from the counted minutes.
func refresh() -> void:
	if win == null:
		return
	var p := sim.human()
	var h: Array = hist.get(p.id, [])
	var span := _span()
	var part := h.slice(maxi(0, h.size() - span))
	var made := []
	var used := []
	for b in part:
		made.append(float(b.made.get(sel_good, 0.0)))
		used.append(float(b.used.get(sel_good, 0.0)))
	chart.set_series([{"name": "made", "color": Color("86c55c"), "values": made}, {"name": "used", "color": Color("e07a5f"), "values": used}])
	# a table of the last ten minutes for every good that moved
	var last := h.slice(maxi(0, h.size() - 10))
	var rows := []
	for r in GameData.resources:
		var m := 0.0
		var u := 0.0
		for b in last:
			m += float(b.made.get(r.id, 0.0))
			u += float(b.used.get(r.id, 0.0))
		if m > 0.0 or u > 0.0:
			var net := (m - u) / maxf(1.0, last.size())
			rows.append("%s: made [color=#86c55c]%.1f[/color], used [color=#e07a5f]%.1f[/color] per minute (%s), %d in store" % [r.name, m / maxf(1.0, last.size()), u / maxf(1.0, last.size()), ("[color=#86c55c]%+.1f[/color]" if net >= 0.0 else "[color=#e07a5f]%+.1f[/color]") % net, int(p.stock.get(r.id, 0.0))])
	table.text = tr("[b]%s[/b]: green made, red used, per game minute.\n[b]Last 10 minutes[/b]\n%s") % [GameData.res_name(sel_good), "\n".join(rows) if rows.size() > 0 else "nothing counted yet"]
	var key: String = ["pop", "bld", "sol", "made_total", "rp"][realm_metric.selected]
	var ser := []
	var legend := []
	for q: Sim.Player in sim.players:
		var hq: Array = hist.get(q.id, [])
		var vals := []
		for b in hq.slice(maxi(0, hq.size() - span)):
			vals.append(float(b.get(key, 0.0)))
		ser.append({"name": q.name, "color": q.color, "values": vals})
		legend.append("[color=#%s]■ %s[/color]" % [q.color.to_html(false), q.name])
	realm_chart.set_series(ser)
	realm_legend.text = "   ".join(legend)
