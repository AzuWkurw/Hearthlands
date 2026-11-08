class_name UiChain
extends RefCounted
## The production chain of a good: boxes for the buildings that make it and, step by step, what they
## need, with arrows to the buildings that use it. Each box shows how many you have and how much they
## make a minute: what they made over the last ten minutes when Statistics is on, and what they could
## make at full speed. An arrow turns red where what they can make at full speed falls short of what the next step needs, and the
## weakest link gets a tip. Opened from a good's info box ("Production chain").

var main: Main
var panel: Control
var body: VBoxContainer
var canvas: ChainCanvas
var tip: Label
var good := ""


class ChainCanvas extends Control:
	var nodes: Array = []      # [rect, title, line2, line3, colour]
	var links: Array = []      # [from index, to index, colour, label]
	var font: Font

	func _draw() -> void:
		font = get_theme_default_font()
		for l in links:
			var a: Rect2 = nodes[l[0]][0]
			var b: Rect2 = nodes[l[1]][0]
			var p0 := Vector2(a.end.x, a.get_center().y)
			var p1 := Vector2(b.position.x, b.get_center().y)
			var c: Color = l[2]
			var mid := (p0.x + p1.x) / 2.0
			var pts := PackedVector2Array()
			for k in 13:
				var t := k / 12.0
				# a smooth S from one box to the next
				var x := lerpf(p0.x, p1.x, t)
				var y := lerpf(p0.y, p1.y, t * t * (3.0 - 2.0 * t))
				pts.append(Vector2(x, y))
			draw_polyline(pts, c, 3.0 if c.r > 0.7 and c.g < 0.5 else 2.0, true)
			draw_colored_polygon(PackedVector2Array([p1, p1 + Vector2(-9, -5), p1 + Vector2(-9, 5)]), c)
			if String(l[3]) != "":
				draw_string(font, Vector2(mid - 40, (p0.y + p1.y) / 2.0 - 6), String(l[3]), HORIZONTAL_ALIGNMENT_CENTER, 80, 12, c)
		for n in nodes:
			var r: Rect2 = n[0]
			draw_rect(r, Color(0.1, 0.11, 0.08))
			draw_rect(r, n[4], false, 2.0)
			draw_string(font, r.position + Vector2(10, 21), String(n[1]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 14, Color("e7e3d0"))
			draw_string(font, r.position + Vector2(10, 40), String(n[2]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 12, n[4])
			draw_string(font, r.position + Vector2(10, 56), String(n[3]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 12, Color("a3a28b"))


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	panel = main._overlay()
	body = main._body(panel)
	panel.visible = false


func close() -> void:
	panel.visible = false


## Goods a realm made and used per minute, over the last ten finished minutes (Statistics), or {}.
func _actual(p: Sim.Player) -> Array:
	var st = main.sim.get_feature("statistics")
	if st == null or not st.hist.has(p.id):
		return [{}, {}]
	var h: Array = st.hist[p.id]
	var last := h.slice(maxi(0, h.size() - 10))
	var made := {}
	var used := {}
	for m in last:
		for k in m.made: made[k] = float(made.get(k, 0.0)) + float(m.made[k]) / last.size()
		for k in m.used: used[k] = float(used.get(k, 0.0)) + float(m.used[k]) / last.size()
	return [made, used]


## Building types making good res (the first few), with how many you have.
func _makers(res: String) -> Array:
	var out := []
	for ty in GameData.bld:
		var d: Dictionary = GameData.bld[ty]
		if (d.get("out", {}) as Dictionary).has(res) and d.has("cycle"):
			out.append(ty)
	out.sort_custom(func(a, b): return _count(a) > _count(b) or (_count(a) == _count(b) and a < b))
	return out.slice(0, 2)


func _count(ty: String) -> int:
	var n := 0
	for b in main.sim.realm_blds(main.sim.human()):
		if b.ty == ty and b.state == "ready":
			n += 1
	return n


## What all your buildings of type ty make (or use) of res a minute at full speed.
func _full(ty: String, res: String, part: String) -> float:
	var sim: Sim = main.sim
	var p := sim.human()
	var tot := 0.0
	for b in sim.realm_blds(p):
		if b.ty != ty or b.state != "ready" or not b.staffed:
			continue
		var d: Dictionary = b.def
		var cyc := float(d.get("cycle", 0.0))
		if cyc <= 0.0:
			continue
		tot += float((d.get(part, {}) as Dictionary).get(res, 0.0)) * 60.0 / cyc * sim.rate(p, b)
	return tot


func open(res: String) -> void:
	good = res
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	body.add_child(head)
	var tl := main._label(tr("Production chain: %s") % GameData.res_name(res), 22, Main.BRASS)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(main._button("Close (Esc)", close))
	body.add_child(main._label("Rates are a minute of game time. \"made\" is the last ten minutes (needs Statistics), \"can\" is at full speed with the workers you have.", 12, Main.DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(860, 420)
	body.add_child(sc)
	canvas = ChainCanvas.new()
	sc.add_child(canvas)
	tip = main._label("", 15)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(840, 0)
	body.add_child(tip)
	_layout()
	panel.visible = true


## Builds the boxes: column 0 the deepest inputs, then their users, ending with the makers of the good
## and, last, the buildings that use it.
func _layout() -> void:
	var sim: Sim = main.sim
	var act := _actual(sim.human())
	var made: Dictionary = act[0]
	var cols: Array = []       # depth -> [[type, good it makes here]]
	var seen := {}
	var frontier := []
	for ty in _makers(good):
		frontier.append([ty, good])
	var depth := 0
	while not frontier.is_empty() and depth < 4:
		cols.append(frontier)
		var nxt := []
		for e in frontier:
			seen[e[0]] = true
			var ins: Dictionary = GameData.bld[e[0]].get("in", {})
			var keys := ins.keys()
			keys.sort()
			for k in keys:
				if k == "food":
					continue
				for ty in _makers(k):
					if not seen.has(ty):
						seen[ty] = true
						nxt.append([ty, k])
		frontier = nxt
		depth += 1
	cols.reverse()
	# users of the good
	var users := []
	for ty in GameData.bld:
		if (GameData.bld[ty].get("in", {}) as Dictionary).has(good) and _count(ty) > 0:
			users.append([ty, ""])
	users.sort_custom(func(a, b): return _count(a[0]) > _count(b[0]))
	users = users.slice(0, 5)
	if not users.is_empty():
		cols.append(users)
	# positions
	var W := 178.0
	var H := 66.0
	var gx := 52.0
	var gy := 22.0
	var index := {}
	var nodes := []
	var tallest := 0
	for ci in cols.size():
		tallest = maxi(tallest, (cols[ci] as Array).size())
	for ci in cols.size():
		var col: Array = cols[ci]
		var x0 := 10.0 + ci * (W + gx)
		var y0 := 10.0 + (tallest - col.size()) * (H + gy) / 2.0
		for ri in col.size():
			var ty: String = col[ri][0]
			var res: String = col[ri][1]
			var n := _count(ty)
			var l2 := ""
			var l3 := ""
			if res != "":
				var can := _full(ty, res, "out")
				l2 = tr("%s: made %.1f, can %.1f") % [GameData.res_name(res).to_lower(), float(made.get(res, 0.0)), can] if not made.is_empty() else tr("%s: can make %.1f") % [GameData.res_name(res).to_lower(), can]
			else:
				var need := _full(ty, good, "in")
				l2 = tr("use %.1f %s at full speed") % [need, GameData.res_name(good).to_lower()]
			l3 = tr("you have %d") % n if n > 0 else tr("you have none")
			index[ty] = nodes.size()
			nodes.append([Rect2(x0, y0 + ri * (H + gy), W, H), "%s × %d" % [String(GameData.bld[ty].name), n], l2, l3, Color("86ad5c")])
	# links: from each input maker to the buildings that use that input; red where short
	var links := []
	var worst := 99.0
	var worst_txt := ""
	for ci in range(1, cols.size()):
		for e in cols[ci]:
			var user: String = e[0]
			var ins: Dictionary = GameData.bld[user].get("in", {})
			for ep in cols[ci - 1]:
				var maker: String = ep[0]
				var res: String = ep[1]
				if user == maker or not ins.has(res):
					continue
				# compared at full speed: what was made also drops when the stores are full or work is paused
				var supply := _full(maker, res, "out")
				var demand := 0.0
				for e2 in cols[ci]:
					demand += _full(e2[0], res, "in")
				var ratio := supply / demand if demand > 0.01 else 9.9
				var col := Color("86ad5c") if ratio >= 0.9 else (Color("e0b060") if ratio >= 0.6 else Color("d9483d"))
				links.append([index[maker], index[user], col, "%.0f%%" % minf(999.0, ratio * 100.0) if demand > 0.01 else ""])
				if ratio < worst and demand > 0.01:
					worst = ratio
					var mk: Dictionary = GameData.bld[maker]
					worst_txt = tr("Weakest link: %s supply only %d%% of what the %s need. Build another %s, or check its inputs and workers.") % [GameData.res_name(res).to_lower(), roundi(ratio * 100.0), String(GameData.bld[user].name).to_lower(), String(mk.name).to_lower()]
				if ratio < 0.9:
					nodes[index[maker]][4] = col
	canvas.nodes = nodes
	canvas.links = links
	canvas.custom_minimum_size = Vector2(20 + cols.size() * (W + gx), 20 + tallest * (H + gy))
	canvas.queue_redraw()
	if cols.is_empty():
		tip.text = tr("Nothing you can build makes this good.")
	elif worst < 0.9:
		tip.text = worst_txt
		tip.add_theme_color_override("font_color", Color("e0b060"))
	else:
		tip.text = tr("Every step keeps up with the next one.")
		tip.add_theme_color_override("font_color", Color("86ad5c"))
