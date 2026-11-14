class_name UiBottlenecks
extends RefCounted
## The bottleneck finder (N): what holds your economy back, biggest first. Workshops that wait are
## grouped by kind and reason ("7 bakeries wait for flour"), and for a missing good it looks one step
## back: how many buildings make it, how many of those work, and what stops the others ("2 mills: 1
## waits for grain, 1 has no worker"). Carriers all out and goods piling up at workshops show too.
## Each line has Go (to the first such building) and Map (the good's chain drawn on the map).
## Only the interface: it reads the game and changes nothing in it.

var main: Main
var win: Window
var head: Label
var list: VBoxContainer


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Bottlenecks"
	win.transient = true
	win.wrap_controls = false
	win.size = Vector2i(700, 560)
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
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	win.close_requested.connect(func(): win.visible = false)
	main.add_child(win)


func toggle() -> void:
	if win.visible:
		win.visible = false
		return
	refresh()
	win.popup_centered()


## The good a waiting message is about ("Needs flour", "Waiting for flour on its way"), or "".
static func good_of(msg: String) -> String:
	var name := ""
	if msg.begins_with("Needs ") and not msg.ends_with("for a new worker"):
		name = msg.substr(6)
	elif msg.begins_with("Waiting for ") and msg.ends_with(" on its way"):
		name = msg.substr(12, msg.length() - 12 - 11)
	if name == "":
		return ""
	if name == "food":
		return "food"
	for r in GameData.resources:
		if String(r.name).to_lower() == name:
			return String(r.id)
	return ""


## Why a building is not working, in a few words, or "" when it works (or is not meant to).
static func why(sim: Sim, b: Sim.Bld) -> String:
	if b.dead or b.state != "ready" or not b.def.has("cycle") or b.prio == Sim.PRIO_PAUSED or b.reno_to >= 0:
		return ""
	if b.working or b.msg == "" or b.msg == "Working" or b.msg == "The worker is on his way":
		return ""
	if not b.staffed:
		return "no worker"
	var m := b.msg.get_slice(":", 0).to_lower()
	# full stores and a quiet infirmary hold nothing back
	if m.begins_with("stores are full") or m.contains("no patients"):
		return ""
	return m


## [weight, text, building to go to, good for the map] for each bottleneck, biggest first.
static func find(sim: Sim, p: Sim.Player) -> Array:
	var groups := {}       # "ty|reason" -> [count, first building, total of type]
	var total := {}
	var by_ty := {}
	var piled := 0
	for b: Sim.Bld in sim.realm_blds(p):
		if b.dead or b.state != "ready":
			continue
		total[b.ty] = int(total.get(b.ty, 0)) + 1
		if not by_ty.has(b.ty):
			by_ty[b.ty] = []
		(by_ty[b.ty] as Array).append(b)
		for k in b.out_buf:
			piled += int(b.out_buf[k])
		var w := why(sim, b)
		if w == "":
			continue
		var key := b.ty + "|" + w
		if not groups.has(key):
			groups[key] = [0, b, b.msg]
		groups[key][0] += 1
	var out := []
	for key in groups:
		var g: Array = groups[key]
		var ty := String(key).get_slice("|", 0)
		var reason := String(key).get_slice("|", 1)
		var n: int = g[0]
		var b0: Sim.Bld = g[1]
		var nm := String(GameData.bld[ty].name).to_lower()
		if int(total[ty]) > 1 and not nm.ends_with("s"):
			nm += "es" if nm.ends_with("ch") or nm.ends_with("sh") else "s"
		var text := "%d of %d %s: %s" % [n, int(total[ty]), nm, reason]
		var good := good_of(String(g[2]))
		var weight := float(n)
		if good != "":
			weight += 1.0
			text += _upstream(sim, p, good, by_ty)
		elif reason == "no worker":
			text += " (worker priorities, L, or more homes)"
		elif reason.begins_with("waiting for carriers"):
			weight += 0.5
		out.append([weight, text, b0, good])
	if sim.porters_free(p) <= 0 and piled > 10:
		out.append([float(piled) / 5.0, "All carriers are out, and %d goods wait at workshops: more homes, a storehouse nearer the workshops, or donkeys" % piled, null, ""])
	out.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and String(a[1]) < String(b[1])))
	return out


## One step back from a missing good: who makes it and what stops them.
static func _upstream(sim: Sim, p: Sim.Player, good: String, by_ty: Dictionary) -> String:
	if good == "food":
		var f := int(sim.food_total(p))
		return " (food in store: %d%s)" % [f, " — the carriers are slow to bring it: roads, a store nearer, transport priorities (K)" if f > 40 else ""]
	var makers := []
	for ty in by_ty:
		if (GameData.bld[ty].get("out", {}) as Dictionary).has(good):
			makers.append(ty)
	var stock := int(p.stock.get(good, 0.0))
	if makers.is_empty():
		return " — nothing of yours makes %s (%d in store)" % [GameData.res_name(good).to_lower(), stock]
	var parts := []
	for ty in makers:
		var n := 0
		var working := 0
		var why_n := {}
		for b: Sim.Bld in by_ty[ty]:
			n += 1
			var w := why(sim, b)
			if w == "":
				working += 1
			else:
				why_n[w] = int(why_n.get(w, 0)) + 1
		var s := "%d %s, %d at work" % [n, String(GameData.bld[ty].name).to_lower(), working]
		var top := ""
		var tn := 0
		for w in why_n:
			if int(why_n[w]) > tn:
				tn = int(why_n[w]); top = w
		if top != "":
			s += ", %d %s" % [tn, top]
		parts.append(s)
	return " — %s; %d in store" % ["; ".join(parts), stock]


func refresh() -> void:
	var sim: Sim = main.sim
	var p := sim.human()
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var bs := find(sim, p)
	head.text = tr("What holds your economy back, biggest first. Go moves the map to such a building; Map draws the good's chain on the map (Esc hides it).") if not bs.is_empty() else tr("Nothing holds your economy back right now.")
	for e in bs.slice(0, 20):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := main._label(String(e[1]), 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(480, 0)
		row.add_child(l)
		var b: Sim.Bld = e[2]
		if b != null:
			var bid := b.id
			row.add_child(main._button(tr("Go"), func():
				var bb: Sim.Bld = main.sim.by_id.get(bid)
				if bb != null:
					main.view.center_on(Vector2(bb.x, bb.y))
					main.view.sel_id = bb.id
					main._refresh_sel()))
		var good := String(e[3])
		if good != "" and good != "food":
			row.add_child(main._button(tr("Map"), func():
				main.view.chain_res = good
				win.visible = false))
		list.add_child(row)
