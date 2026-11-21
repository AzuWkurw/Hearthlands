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
# --- Border replay: a small picture of who holds what, once a game minute (BORDER_W tiles across)
const BORDER_W := 96
var borders: Array = []   # one compressed picture (a byte per cell: the owner) per game minute
var bw := 0               # cells across in those pictures (the map's own width if smaller)
var tab_box: TabContainer
var border_pic: TextureRect
var border_slider: HSlider
var border_lbl: Label
var play_btn: Button
var playing := false
var _play_t := 0.0
var realm_legend: RichTextLabel
var sel_good := "planks"
var bhist := {}           # your building id -> {"last": minute, "c": made in each of the last 30 minutes}
const BKEEP := 30


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


## What each of your buildings made, minute by minute, for the chart in its info box.
func on_made_at(b: Sim.Bld, p: Sim.Player, res: String, n: float) -> void:
	if p.id != 1 or res == "research":
		return
	var m := int(sim.time / 60.0)
	var e: Dictionary = bhist.get(b.id, {})
	if e.is_empty():
		e = {"last": m, "c": []}
		(e.c as Array).resize(BKEEP)
		(e.c as Array).fill(0.0)
		bhist[b.id] = e
	_roll(e, m)
	var c: Array = e.c
	c[m % BKEEP] = float(c[m % BKEEP]) + n


func _roll(e: Dictionary, m: int) -> void:
	var c: Array = e.c
	var last := int(e.last)
	for k in range(last + 1, mini(m, last + BKEEP) + 1):
		c[k % BKEEP] = 0.0
	e.last = maxi(last, m)


const BARS := "▁▂▃▄▅▆▇█"

func building_lines(b: Sim.Bld) -> PackedStringArray:
	if not bhist.has(b.id):
		return PackedStringArray()
	var e: Dictionary = bhist[b.id]
	var m := int(sim.time / 60.0)
	_roll(e, m)
	var c: Array = e.c
	var vals := []
	var total := 0.0
	var top := 0.0
	for k in range(m - BKEEP + 1, m + 1):
		var v := float(c[posmod(k, BKEEP)]) if k >= 0 else 0.0
		vals.append(v)
		total += v
		top = maxf(top, v)
	var line := ""
	for v in vals:
		line += " " if v <= 0.0 else BARS[clampi(int(v / maxf(top, 0.01) * 7.99), 0, 7)]
	return PackedStringArray(["Made in the last 30 minutes: [b]%d[/b]\n[color=#86ad5c]%s[/color] [color=#9a9c88](a bar a minute, now on the right)[/color]" % [roundi(total), line]])


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
		b["land"] = sim.owned(p.id)[0].size()
		b["techs"] = p.techs.size()
		b["gold"] = float(p.stock.get("gold", 0.0))
		var worth := 0.0
		for k in p.stock:
			if sim.market.traded(k):
				worth += float(p.stock[k]) * sim.market.price(k)
		b["wealth"] = snappedf(worth + float(p.stock.get("gold", 0.0)), 0.1)
		b["alive"] = p.alive
		var made_total := 0.0
		for k in b.made:
			if k != "research":
				made_total += float(b.made[k])
		b["made_total"] = made_total
		# tools and arms by metal (build 72)
		var tm := 0.0
		for k in b.made:
			if GameData.is_tool_res(String(k)):
				tm += float(b.made[k])
		b["tools_made"] = tm
		var hp: Array = hist.get(p.id, [])
		b["worn_cum"] = p.tools_worn
		b["tools_worn"] = maxi(0, p.tools_worn - int((hp[hp.size() - 1] as Dictionary).get("worn_cum", p.tools_worn))) if hp.size() > 0 else 0
		b["arms_b"] = int(p.arm_n[1])
		b["arms_i"] = int(p.arm_n[2])
		b["arms_s"] = int(p.arm_n[3])
		if not hist.has(p.id):
			hist[p.id] = []
		(hist[p.id] as Array).append(b)
		if (hist[p.id] as Array).size() > KEEP:
			(hist[p.id] as Array).pop_front()
		cur[p.id] = {"made": {}, "used": {}}
	_snapshot_borders()
	for id in bhist.keys():
		if not sim.by_id.has(id):
			bhist.erase(id)
	if win != null and win.visible:
		refresh()


func save_state() -> Dictionary:
	return {"hist": hist, "cur": cur, "minute": minute, "borders": borders, "bw": bw, "bhist": bhist}


func load_state(d: Dictionary) -> void:
	hist = d.get("hist", {})
	cur = d.get("cur", {})
	minute = int(d.get("minute", -1))
	borders = d.get("borders", [])
	bw = int(d.get("bw", 0))
	bhist = d.get("bhist", {})


func build_ui(main: Main) -> void:
	main.add_feature_button(self, "Statistics", open)
	main.add_feature_button(self, "Realms", open_realms)
	main.add_feature_key(self, KEY_F2, open)
	main.add_feature_key(self, KEY_V, open_realms)
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
	for t in ["Population", "Buildings", "Soldiers", "Goods made per minute", "Research points (total)", "Land (tiles)", "Techs studied", "Gold", "Wealth (goods and gold, in gold)", "Tools made per minute", "Tools worn out per minute", "Soldiers with steel arms", "Soldiers with iron arms", "Soldiers with bronze arms"]:
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
	# borders: everyone's land minute by minute, to play back
	var bt := VBoxContainer.new()
	bt.name = "Borders"
	tabs.add_child(bt)
	tab_box = tabs
	border_pic = TextureRect.new()
	border_pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	border_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	border_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	border_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bt.add_child(border_pic)
	var row := HBoxContainer.new()
	bt.add_child(row)
	play_btn = Button.new()
	play_btn.text = "Play"
	play_btn.pressed.connect(func():
		playing = not playing
		if playing and border_slider.value >= border_slider.max_value:
			border_slider.value = 0
		play_btn.text = "Pause" if playing else "Play")
	row.add_child(play_btn)
	border_slider = HSlider.new()
	border_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	border_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	border_slider.value_changed.connect(func(_v): _show_border(int(border_slider.value)))
	row.add_child(border_slider)
	border_lbl = Label.new()
	row.add_child(border_lbl)
	var tm := Timer.new()
	tm.wait_time = 0.2
	tm.autostart = true
	tm.timeout.connect(_play_step)
	win.add_child(tm)


func open() -> void:
	win.visible = not win.visible
	if win.visible:
		refresh()


## The Realms tab: every realm compared over time (V, build 61).
func open_realms() -> void:
	if win.visible and tab_box.current_tab == 1:
		win.visible = false
		return
	tab_box.current_tab = 1
	win.visible = true
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
	var key: String = ["pop", "bld", "sol", "made_total", "rp", "land", "techs", "gold", "wealth", "tools_made", "tools_worn", "arms_s", "arms_i", "arms_b"][realm_metric.selected]
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
	# where you stand now against each rival
	var rank := ["[table=7][cell][b]Realm[/b]  [/cell][cell][b]People[/b]  [/cell][cell][b]Buildings[/b]  [/cell][cell][b]Soldiers[/b]  [/cell][cell][b]Land[/b]  [/cell][cell][b]Techs[/b]  [/cell][cell][b]Gold[/b][/cell]"]
	for q: Sim.Player in sim.players:
		var cells := [sim.pop_total(q), sim.realm_blds(q).size(), sim.soldiers(q), sim.owned(q.id)[0].size(), q.techs.size(), int(q.stock.get("gold", 0.0))]
		rank.append("[cell][color=#%s]■ %s%s[/color]  [/cell]" % [q.color.to_html(false), q.name, "" if q.alive else " (gone)"] + "".join(cells.map(func(v): return "[cell]%d  [/cell]" % v)))
	realm_legend.text = "   ".join(legend) + "\n\n" + "".join(rank) + "[/table]"
	_refresh_borders()


## Takes this minute's picture of everyone's land (downscaled to at most BORDER_W cells across).
func _snapshot_borders() -> void:
	if sim.w == 0:
		return
	bw = mini(BORDER_W, sim.w)
	var bh := maxi(1, sim.h * bw / sim.w)
	var px := PackedByteArray()
	px.resize(bw * bh)
	for y in bh:
		for x in bw:
			px[y * bw + x] = sim.owner[(y * sim.h / bh) * sim.w + x * sim.w / bw]
	borders.append(px.compress(FileAccess.COMPRESSION_DEFLATE))
	borders.append(bh)   # (the height goes with each picture)


func _border_count() -> int:
	return borders.size() / 2


func _refresh_borders() -> void:
	if border_slider == null:
		return
	var n := _border_count()
	border_slider.max_value = maxi(0, n - 1)
	if not playing and n > 0:
		border_slider.value = n - 1
	_show_border(int(border_slider.value))


## Draws picture k: water dark blue, land nobody holds grey-green, each realm in its colour.
func _show_border(k: int) -> void:
	var n := _border_count()
	if n == 0 or bw == 0:
		border_lbl.text = "no minutes yet"
		return
	k = clampi(k, 0, n - 1)
	var bh := int(borders[k * 2 + 1])
	var px: PackedByteArray = (borders[k * 2] as PackedByteArray).decompress(bw * bh, FileAccess.COMPRESSION_DEFLATE)
	var img := Image.create(bw, bh, false, Image.FORMAT_RGB8)
	# while the game goes on, land you have not seen stays dark (no peeking past the fog)
	var fog = sim.get_feature("fog")
	var hide: bool = fog != null and not sim.over
	for y in bh:
		for x in bw:
			var o := px[y * bw + x]
			var ti := (y * sim.h / bh) * sim.w + x * sim.w / bw
			if hide and not fog.seen.has(ti) and not fog.visible_at(ti):
				img.set_pixel(x, y, Color("101210"))
				continue
			var t := sim.ter[ti]
			var c := Color("1d3550") if t == Sim.WATER else (Color("5a5a52") if t == Sim.MOUNT else Color("3c4a30"))
			if o > 0 and o <= sim.players.size():
				c = sim.players[o - 1].color.darkened(0.15)
			img.set_pixel(x, y, c)
	border_pic.texture = ImageTexture.create_from_image(img)
	border_lbl.text = "  minute %d of %d" % [k + 1, n]


## While playing: one minute every fifth of a second (a timer calls this).
func _play_step() -> void:
	if not playing or win == null or not win.visible:
		return
	if border_slider.value >= border_slider.max_value:
		playing = false
		play_btn.text = "Play"
		return
	border_slider.value += 1


## Opens the window on the border replay and plays it from the start (the end-of-game screen).
func replay() -> void:
	win.visible = true
	refresh()
	tab_box.current_tab = 2
	border_slider.value = 0
	playing = true
	play_btn.text = "Pause"
