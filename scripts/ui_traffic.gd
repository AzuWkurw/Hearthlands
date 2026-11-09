class_name UiTraffic
extends RefCounted
## The traffic map (F7, or the Traffic button): every road of yours coloured by how busy it has been
## over the last few minutes. Green is free, amber busy, red jammed (goods waiting at a flag, or a
## carrier on it nearly all the time). Click a road while it shows to hear what goes on there and
## what might help. Each game second it notes where your carriers are; older notes fade (a tenth
## every 10 seconds), so it follows the town as it changes. Only the interface: the game itself is
## not touched, and nothing of it is saved.

const BUSY := 12.0     # amber from here (about one carrier on the tile an eighth of the time)
const JAM := 40.0      # red from here
const WAIT_JAM := 15.0

var main: Main
var on := false
var busy := PackedFloat32Array()   # carrier-seconds per tile, fading
var wait := PackedFloat32Array()   # goods-seconds waiting at a flag on the tile, fading
var _last := -1
var legend: PanelContainer
var _swatches: Array = []


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	legend = PanelContainer.new()
	legend.add_theme_stylebox_override("panel", main._panel_style(0.9))
	legend.position = Vector2(12, 96)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	legend.add_child(v)
	v.add_child(main._label("TRAFFIC (F7)", 14, Main.BRASS))
	for row in [["bad", "jammed: goods waiting"], ["warn", "busy"], ["good", "free"]]:
		var h := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = Main.col(row[0])
		sw.set_meta("col", row[0])
		_swatches.append(sw)
		sw.custom_minimum_size = Vector2(16, 6)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		h.add_child(main._label(String(row[1]), 12))
		v.add_child(h)
	v.add_child(main._label("Click a road to see what goes on there.", 11, Main.DIM))
	legend.visible = false
	main.add_child(legend)


func reset() -> void:
	busy = PackedFloat32Array()
	wait = PackedFloat32Array()
	_last = -1


func toggle() -> void:
	on = not on
	legend.visible = on
	for sw: ColorRect in _swatches:
		sw.color = Main.col(String(sw.get_meta("col")))
	main.view.queue_redraw()


## Called as the interface refreshes: once per game second, notes where your carriers are.
func update() -> void:
	var sim: Sim = main.sim
	if sim == null or sim.w == 0 or sim.players.is_empty():
		return
	if busy.size() != sim.w * sim.h:
		busy.resize(sim.w * sim.h); busy.fill(0.0)
		wait.resize(sim.w * sim.h); wait.fill(0.0)
	var now := int(sim.time)
	if _last < 0:
		_last = now
	var steps := mini(10, now - _last)
	if steps <= 0:
		return
	_last = now
	for s in steps:
		for t in sim.trips:
			if t.p != 1 or not (t.kind == "porter" or t.kind == "mule" or t.kind == "cart"):
				continue
			var at := _tile_of(t)
			if at.x < 0:
				continue
			if at.y == 1:
				wait[at.x] += 1.0
			else:
				busy[at.x] += 1.0
		if (now - s) % 10 == 0:
			for i in busy.size():
				if busy[i] > 0.0: busy[i] *= 0.9
				if wait[i] > 0.0: wait[i] *= 0.9
	if on:
		main.view.queue_redraw()


## The tile a carrier is on now, and 1 when his load is waiting at a flag: Vector2i(tile, waiting).
func _tile_of(t: Sim.Trip) -> Vector2i:
	var sim: Sim = main.sim
	var n := t.path.size() - 1
	if n < 1:
		return Vector2i(-1, 0)
	if not t.legs.is_empty():
		var lp: Vector3 = main.view._leg_pos(t)
		if lp.z < 0.0:
			return Vector2i(int(lp.x), 1)
		return Vector2i(int(lp.x) if absf(lp.z) < 0.5 else int(lp.y), 0)
	var prog := 0.0
	if not t.delivered:
		prog = clampf((sim.time - t.t0) / maxf(0.01, t.t1 - t.t0), 0.0, 0.999)
	else:
		prog = 1.0 - clampf((sim.time - t.t1) / maxf(0.01, t.t2 - t.t1), 0.0, 1.0)
	if t.site != 0 or t.dest != 0:
		prog = 1.0 - prog
	var k := clampi(roundi(prog * n), 0, n)
	return Vector2i(t.path[k], 0)


func level(i: int) -> int:
	if i < 0 or i >= busy.size():
		return 0
	if wait[i] >= WAIT_JAM or busy[i] >= JAM:
		return 2
	return 1 if busy[i] >= BUSY else 0


func color_of(i: int) -> Color:
	return [Main.col("good"), Main.col("warn"), Main.col("bad")][level(i)]


## Draws the coloured roads over the map (called by the map view, in tiles).
func draw(view: MapView, x0: int, x1: int, y0: int, y1: int) -> void:
	if not on or busy.is_empty():
		return
	var sim: Sim = main.sim
	var w := sim.w
	for y in range(maxi(0, y0), mini(sim.h, y1 + 1)):
		for x in range(maxi(0, x0), mini(w, x1 + 1)):
			var i := y * w + x
			if sim.road[i] != 1:
				continue
			var c := color_of(i)
			c.a = 0.85
			var p := Vector2(x + 0.5, y + 0.5)
			if view.raised:
				p.y -= view.lift_at(p.x, p.y)
			var any := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= sim.h:
					continue
				var ni := ny * w + nx
				if sim.road[ni] == 1 or (sim.bmap[ni] != 0 and sim.links(i, ni)):
					any = true
					view.draw_line(p, p + Vector2(d) * 0.5, c, 0.34)
			if not any:
				view.draw_circle(p, 0.15, c)


## What the tile info says about road tile i while the traffic map shows.
func tile_text(i: int) -> String:
	if not on or i < 0 or i >= busy.size() or main.sim.road[i] != 1:
		return ""
	var sim: Sim = main.sim
	var lv := level(i)
	var t := "[b]Traffic:[/b] %s. A carrier here about %d%% of the time" % [["free", "busy", "jammed"][lv], mini(100, roundi(busy[i]))]
	if wait[i] >= 1.0:
		t += ", goods waiting here about %d%% of the time" % mini(100, roundi(wait[i]))
	t += ".\n"
	if lv == 2:
		var tips := []
		if wait[i] >= WAIT_JAM:
			tips.append("set a flag (Flag tool) to split this stretch, or build a second road beside it")
		else:
			tips.append("build a second road beside this one")
		# far from any store: a store closer to where the goods come from shortens every trip
		var near := INF
		for b: Sim.Bld in sim.realm_blds(sim.human()):
			if b.state == "ready" and sim.logistics.is_store(b):
				near = minf(near, Vector2(b.x - i % sim.w, b.y - i / sim.w).length())
		if near > 10.0:
			tips.append("a storehouse near here, so goods have less far to go")
		t += "[color=#86ad5c]Might help: %s.[/color]\n" % "; or ".join(tips)
	return t
