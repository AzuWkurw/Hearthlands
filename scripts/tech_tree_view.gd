class_name TechTreeView
extends Control
## The tech tree drawn as a map: ages run left to right, each band is a branch of the realm, and lines
## run from what a tech needs to what it leads to. The places come from data/techs.json ("lane", "col",
## "row", worked out to cross as few lines as possible); techs added by a mod without them are put in
## an "Other" band. Repeatable studies sit in the Mastery band at the bottom.
## Drag (or the arrow keys) to move, the wheel to scroll, Ctrl + wheel or a pinch to zoom.

signal selected(id: String)
signal activated(id: String)          # double click: study it, or queue the way to it
signal zoom_changed(z: float)

const ZMIN := 0.2
const ZMAX := 1.75
const GAP_X := 44.0
const GAP_Y := 12.0
const TOP := 40.0                      # room for the age names
const LEFT := 40.0                     # room for the band names
const PAD := 14.0

const C_CARD := Color("1f2326")
const C_LINE := Color("3a4045")
const C_INK := Color("e6e2d3")
const C_DIM := Color("9a9c88")
const C_BRASS := Color("d8aa4a")
const C_DONE := Color("8fc070")
const C_STUDY := Color("8fc0ff")

var sim: Sim
var compact := false
var zoom := 1.0
var cam := Vector2.ZERO               # content point at the top left of the view
var sel := ""
var hover := ""
var search := ""
var hits: Dictionary = {}

var card := Vector2(178, 84)
var pos: Dictionary = {}              # id -> top left of its card, in content pixels
var lanes: Array = []                 # [name, y, height, mastery]
var age_x: Dictionary = {}            # age -> [left, right] in content pixels
var content := Vector2.ZERO
var kids: Dictionary = {}             # tech -> techs that need it
var _chain: Dictionary = {}           # the hovered tech's whole line
var _drag := false
var _drag_from := Vector2.ZERO
var _cam_from := Vector2.ZERO
var _moved := false
var _font: Font


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	_font = get_theme_default_font()
	resized.connect(_clamp_cam)


## Works out where every card goes. Call when the data or the card size changes.
func rebuild() -> void:
	card = Vector2(150, 46) if compact else Vector2(178, 84)
	var cw := card.x + GAP_X
	var rh := card.y + GAP_Y
	# techs that only help a switched-off feature are left out
	var shown := []
	for id in GameData.techs:
		if sim == null or sim.tech_enabled(id):
			shown.append(id)
	var shown_reps := []
	for id in GameData.reps:
		if sim == null or sim.tech_enabled(id):
			shown_reps.append(id)
	kids = {}
	for id in shown:
		kids[id] = []
	for id in shown:
		for r in GameData.techs[id].get("requires", []):
			if kids.has(r):
				kids[r].append(id)
	# columns: from the data, or (for a mod's techs) after the last column of their age
	var cols := {}
	var age_cols := {}
	for id in shown:
		var t: Dictionary = GameData.techs[id]
		if t.has("col"):
			var a := int(t.get("age", 1))
			var c := int(t.col)
			cols[id] = c
			if not age_cols.has(a): age_cols[a] = [c, c]
			age_cols[a][0] = mini(age_cols[a][0], c); age_cols[a][1] = maxi(age_cols[a][1], c)
	var extra_rows := {}
	for id in shown:
		if not cols.has(id):
			var a := int(GameData.techs[id].get("age", 1))
			if not age_cols.has(a):
				var last := -1
				for k in age_cols: last = maxi(last, age_cols[k][1])
				age_cols[a] = [last + 1, last + 1]
			cols[id] = age_cols[a][0]
	pos = {}
	lanes = []
	var y := TOP
	var lane_list: Array = GameData.lanes.duplicate()
	var placed := {}
	for ln in lane_list:
		var lid := String(ln[0])
		var lo := 1e9
		var hi := -1e9
		for id in shown:
			var t: Dictionary = GameData.techs[id]
			if String(t.get("lane", "")) == lid and t.has("row"):
				lo = minf(lo, float(t.row)); hi = maxf(hi, float(t.row))
		if hi < lo:
			continue
		for id in shown:
			var t: Dictionary = GameData.techs[id]
			if String(t.get("lane", "")) == lid and t.has("row"):
				pos[id] = Vector2(LEFT + cols[id] * cw, y + PAD + (float(t.row) - lo) * rh)
				placed[id] = true
		var hgt := (hi - lo) * rh + card.y + PAD * 2.0
		lanes.append([String(ln[1]), y, hgt, false])
		y += hgt + 6.0
	# techs with no place in the data (a mod's): their own band, stacked by column
	var other := {}
	for id in shown:
		if not placed.has(id):
			var c: int = cols[id]
			var k: int = other.get(c, 0)
			pos[id] = Vector2(LEFT + c * cw, y + PAD + k * rh)
			other[c] = k + 1
	if not other.is_empty():
		var most := 0
		for c in other: most = maxi(most, other[c])
		lanes.append(["Other", y, most * rh - GAP_Y + PAD * 2.0, false])
		y += most * rh - GAP_Y + PAD * 2.0 + 6.0
	age_x = {}
	var right := LEFT
	for a in age_cols:
		age_x[a] = [LEFT + age_cols[a][0] * cw - GAP_X / 2.0, LEFT + (age_cols[a][1] + 1) * cw - GAP_X / 2.0]
		right = maxf(right, age_x[a][1])
	# the mastery band: each age's repeatable studies in the first column of that age
	if not shown_reps.is_empty():
		var my := y + 12.0
		var deepest := 0
		var per_age := {}
		for id in shown_reps:
			var a := int(GameData.reps[id].get("age", 1))
			var k: int = per_age.get(a, 0)
			var x0: float = age_x[a][0] + GAP_X / 2.0 if age_x.has(a) else LEFT
			pos[id] = Vector2(x0, my + PAD + k * rh)
			per_age[a] = k + 1
			deepest = maxi(deepest, k + 1)
		lanes.append(["Mastery (repeatable)", my, deepest * rh - GAP_Y + PAD * 2.0, true])
		y = my + deepest * rh - GAP_Y + PAD * 2.0
	content = Vector2(right + 30.0, y + 30.0)
	_clamp_cam()
	_refresh_hover()
	queue_redraw()


func _p() -> Sim.Player:
	return sim.human() if sim != null and not sim.players.is_empty() else null


## done, study, avail or locked
func state_of(id: String) -> String:
	var p := _p()
	if p == null:
		return "locked"
	if GameData.reps.has(id):
		if int(p.reps.get(id, 0)) >= int(GameData.reps[id].get("max", 1)):
			return "done"
	elif p.techs.has(id):
		return "done"
	if p.research == id:
		return "study"
	return "avail" if sim.tech_available(p, id) else "locked"


# ---------------------------------------------------------------- view

func set_zoom(z: float, at := Vector2(-1, -1)) -> void:
	z = clampf(z, ZMIN, ZMAX)
	if absf(z - zoom) < 0.0001:
		return
	if at.x < 0:
		at = size / 2.0
	var world := cam + at / zoom
	zoom = z
	cam = world - at / zoom
	_clamp_cam()
	zoom_changed.emit(zoom)
	_refresh_hover()
	queue_redraw()


## Zoom so the whole tree fits.
func fit() -> void:
	var z := minf(size.x / maxf(1.0, content.x), size.y / maxf(1.0, content.y))
	zoom = clampf(z, ZMIN, ZMAX)
	cam = Vector2.ZERO
	_clamp_cam()
	zoom_changed.emit(zoom)
	_refresh_hover()
	queue_redraw()


func center_on(id: String) -> void:
	if not pos.has(id):
		return
	cam = pos[id] + card / 2.0 - size / 2.0 / zoom
	_clamp_cam()
	_refresh_hover()
	queue_redraw()


func show_age(a: int) -> void:
	if age_x.has(a):
		cam.x = float(age_x[a][0]) - 10.0
		_clamp_cam()
		_refresh_hover()
		queue_redraw()


func pan(d: Vector2) -> void:
	cam += d / zoom
	_clamp_cam()
	_refresh_hover()
	queue_redraw()


## The card under the mouse may change when the view moves under a still mouse.
func _refresh_hover() -> void:
	if not is_visible_in_tree():
		_set_hover("")
		return
	var m := get_local_mouse_position()
	_set_hover(id_at(m) if Rect2(Vector2.ZERO, size).has_point(m) else "")


func _clamp_cam() -> void:
	var view := size / zoom
	cam.x = clampf(cam.x, 0.0, maxf(0.0, content.x - view.x))
	cam.y = clampf(cam.y, 0.0, maxf(0.0, content.y - view.y))


func _sp(v: Vector2) -> Vector2:
	return (v - cam) * zoom


func id_at(screen: Vector2) -> String:
	var w := cam + screen / zoom
	for id in pos:
		if Rect2(pos[id], card).has_point(w):
			return id
	return ""


func set_search(q: String) -> Array:
	search = q.strip_edges().to_lower()
	hits = {}
	var first := []
	if search != "":
		for id in pos:
			if _matches(id):
				hits[id] = true
				first.append(id)
	queue_redraw()
	return first


func _matches(id: String) -> bool:
	var d: Dictionary = GameData.reps[id] if GameData.reps.has(id) else GameData.techs[id]
	var txt := String(d.name) + " " + GameData.effect_text(d.get("effects", {}))
	for b in unlocks(id):
		txt += " " + String(GameData.bld[b].name)
	for sd in Crops.seeds_of(id):
		txt += " " + sd + " seed"
	return search in txt.to_lower()


## Buildings tech id unlocks (from the tech's own list and the buildings' "tech").
func unlocks(id: String) -> Array:
	var out := []
	if GameData.techs.has(id):
		for b in GameData.techs[id].get("unlocks", []):
			if GameData.bld.has(b) and not out.has(b):
				out.append(b)
		for b in GameData.bld:
			if String(GameData.bld[b].get("tech", "")) == id and not out.has(b):
				out.append(b)
	return out


func _set_hover(id: String) -> void:
	if id == hover:
		return
	hover = id
	_chain = {}
	if id != "" and GameData.techs.has(id):
		_chain[id] = true
		var up := [id]
		while not up.is_empty():
			var x: String = up.pop_back()
			for r in GameData.techs[x].get("requires", []):
				if not _chain.has(r):
					_chain[r] = true; up.append(r)
		var down := [id]
		while not down.is_empty():
			var x: String = down.pop_back()
			for k in kids.get(x, []):
				if not _chain.has(k):
					_chain[k] = true; down.append(k)
	elif id != "":
		_chain[id] = true
	tooltip_text = ""
	queue_redraw()


# ---------------------------------------------------------------- input

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var dirn := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if mb.ctrl_pressed or mb.meta_pressed:
				set_zoom(zoom * (1.0 / 1.12 if dirn > 0 else 1.12), mb.position)
			elif mb.shift_pressed:
				pan(Vector2(dirn * 80.0, 0))
			else:
				pan(Vector2(0, dirn * 80.0))
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			pan(Vector2(-80.0 if mb.button_index == MOUSE_BUTTON_WHEEL_LEFT else 80.0, 0))
			accept_event()
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_drag = true; _moved = false
				_drag_from = mb.position; _cam_from = cam
				if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
					var d := id_at(mb.position)
					if d != "":
						activated.emit(d)
					_drag = false
			else:
				if _drag and not _moved and mb.button_index == MOUSE_BUTTON_LEFT:
					var id := id_at(mb.position)
					sel = id
					selected.emit(id)
					queue_redraw()
				_drag = false
			accept_event()
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _drag:
			if (mm.position - _drag_from).length() > 5.0:
				_moved = true
			if _moved:
				cam = _cam_from - (mm.position - _drag_from) / zoom
				_clamp_cam()
				queue_redraw()
		else:
			_set_hover(id_at(mm.position))
	elif e is InputEventMagnifyGesture:
		var g := e as InputEventMagnifyGesture
		set_zoom(zoom * g.factor, g.position)
		accept_event()
	elif e is InputEventPanGesture:
		pan((e as InputEventPanGesture).delta * 20.0)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_set_hover("")


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var p := _p()
	draw_rect(Rect2(Vector2.ZERO, size), Color("15181a"))
	if p == null or pos.is_empty():
		return
	var z := zoom
	# bands
	for i in lanes.size():
		var ln: Array = lanes[i]
		var r := Rect2(_sp(Vector2(0, ln[1])), Vector2(size.x, float(ln[2]) * z))
		r.position.x = 0
		if ln[3]:
			draw_rect(r, Color(0.85, 0.67, 0.29, 0.035))
			draw_line(r.position, Vector2(r.end.x, r.position.y), C_LINE, 1.0)
		elif i % 2 == 1:
			draw_rect(r, Color(1, 1, 1, 0.02))
	# age dividers
	for a in age_x:
		var x := _sp(Vector2(age_x[a][0], 0)).x
		draw_dashed_line(Vector2(x, 0), Vector2(x, size.y), Color("2b3034"), 1.0, 6.0)
	# lines
	var plan := {}
	if p.research != "": plan[p.research] = true
	for q in p.rqueue: plan[q] = true
	var focusing := hover != ""
	for id in GameData.techs:
		if not pos.has(id): continue
		for r in GameData.techs[id].get("requires", []):
			if not pos.has(r): continue
			var a: Vector2 = _sp(pos[r] + Vector2(card.x, card.y / 2.0))
			var b: Vector2 = _sp(pos[id] + Vector2(0, card.y / 2.0))
			if maxf(a.x, b.x) < 0 or minf(a.x, b.x) > size.x or maxf(a.y, b.y) < -20 or minf(a.y, b.y) > size.y + 20:
				continue
			var col := Color("3d4348")
			var w := 1.6
			var in_chain: bool = focusing and _chain.has(id) and _chain.has(r)
			if in_chain:
				col = C_INK; w = 2.4
			elif plan.has(id) and (plan.has(r) or p.techs.has(r)):
				col = C_BRASS; w = 2.2
			elif p.techs.has(r) and p.techs.has(id):
				col = Color("4f6d40")
			elif p.techs.has(r):
				col = Color("8a7036")
			if focusing and not in_chain:
				col.a = 0.3
			_bezier(a, b, col, w * maxf(0.6, z))
	# cards
	for id in pos:
		var r := Rect2(_sp(pos[id]), card * z)
		if r.end.x < 0 or r.position.x > size.x or r.end.y < 0 or r.position.y > size.y:
			continue
		_draw_card(p, id, r, plan)
	# pinned: age names on top, band names on the left
	draw_rect(Rect2(0, 0, size.x, 30), Color(0.08, 0.09, 0.1, 0.94))
	draw_line(Vector2(0, 30), Vector2(size.x, 30), C_LINE, 1.0)
	for a in age_x:
		var x := maxf(_sp(Vector2(age_x[a][0], 0)).x, 0.0) + 10.0
		var x_end := _sp(Vector2(age_x[a][1], 0)).x
		if x_end < 20: continue
		var col: Color = C_STUDY if a == p.age else (C_DONE if a < p.age else C_DIM)
		draw_string(_font, Vector2(x, 21), GameData.age_name(a), HORIZONTAL_ALIGNMENT_LEFT, maxf(10, x_end - x - 6), 15, col)
	for ln in lanes:
		var y0 := _sp(Vector2(0, ln[1])).y
		var hgt := float(ln[2]) * z
		if y0 + hgt < 30 or y0 > size.y: continue
		var name := String(ln[0])
		var fs := 13
		var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cy := clampf(y0 + 8.0 + tw, 30.0 + 8.0 + tw, maxf(30.0 + 8.0 + tw, y0 + hgt - 6.0))
		draw_rect(Rect2(6, cy - tw - 6, 20, tw + 12), Color("15181a"))
		draw_rect(Rect2(6, cy - tw - 6, 20, tw + 12), C_LINE, false, 1.0)
		draw_set_transform(Vector2(21, cy), -PI / 2.0, Vector2.ONE)
		draw_string(_font, Vector2.ZERO, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_DIM)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _bezier(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var dx := maxf(30.0 * zoom, (b.x - a.x) / 2.0)
	var pts := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		var u := 1.0 - t
		var c1 := a + Vector2(dx, 0)
		var c2 := b - Vector2(dx, 0)
		pts.append(u * u * u * a + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * b)
	draw_polyline(pts, col, w, true)


func _fit_text(s: String, w: float, fs: int) -> String:
	if _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
		return s
	while s.length() > 1 and _font.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		s = s.substr(0, s.length() - 1)
	return s + "…"


func _draw_card(p: Sim.Player, id: String, r: Rect2, plan: Dictionary) -> void:
	var z := zoom
	var st := state_of(id)
	var is_rep := GameData.reps.has(id)
	var d: Dictionary = GameData.reps[id] if is_rep else GameData.techs[id]
	var fade := 1.0
	if hover != "" and not _chain.has(id): fade = 0.25
	elif search != "" and not hits.has(id): fade = 0.2
	elif st == "locked": fade = 0.62
	var fill := C_CARD
	var border := C_LINE
	var bw := 1.0
	match st:
		"done": fill = Color("1d241c"); border = Color("3f5a33")
		"avail": border = C_BRASS; bw = 1.5
		"study": border = C_STUDY; bw = 2.0
	fill.a *= fade
	border.a *= fade
	draw_rect(r, fill)
	draw_rect(r, border, false, bw)
	if id == sel:
		draw_rect(r.grow(2), C_INK, false, 2.0)
	var pad := 6.0 * z
	var ic := 36.0 * z
	var tex := Tex.get_tex("tech_" + id)
	if tex != null:
		draw_texture_rect(tex, Rect2(r.position + Vector2(pad, pad), Vector2(ic, ic)), false, Color(1, 1, 1, fade))
	var tx := r.position.x + pad * 1.4 + ic
	var tw := r.end.x - tx - pad
	var fs := roundi(14 * z)
	var fs2 := roundi(12 * z)
	if fs < 6:
		return
	var ink := C_INK; ink.a = fade
	draw_string(_font, Vector2(tx, r.position.y + pad + fs), _fit_text(String(d.name), tw - (16 * z if plan.has(id) else 0.0), fs), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	var lv := int(p.reps.get(id, 0)) if is_rep else 0
	var c := sim.research_cost(p, id)
	var line2 := ""
	var col2 := C_DIM
	match st:
		"done": line2 = "All levels" if is_rep else "Done"; col2 = C_DONE
		"study": line2 = ("Level %d · " % (lv + 1) if is_rep else "") + "%d / %d" % [int(minf(p.rp, c)), int(c)]; col2 = C_STUDY
		"avail": line2 = ("Level %d · " % (lv + 1) if is_rep else "") + "%d points" % int(c); col2 = C_BRASS
		_: line2 = ("Opens in the %s age" % GameData.age_name(int(d.get("age", 0)))) if is_rep else "%d points" % int(c)
	col2.a = fade
	var y2 := r.position.y + pad + fs + 3.0 * z + fs2
	draw_string(_font, Vector2(tx, y2), _fit_text(line2, tw, fs2), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, col2)
	# progress of the study under way
	if st == "study" and c > 0:
		draw_rect(Rect2(r.position.x, r.end.y - 3.0 * z, r.size.x * clampf(p.rp / c, 0, 1), 3.0 * z), C_STUDY)
	# its place in the queue
	var qn := 0
	var qi := -1
	for k in p.rqueue.size():
		if p.rqueue[k] == id:
			qn += 1
			if qi < 0: qi = k
	if qn > 0:
		var badge := ("+%d" % qn) if is_rep else str(qi + 1)
		var bsz := Vector2(maxf(18.0, 8.0 + _font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11 * z)).x / z), 18.0) * z
		var br := Rect2(Vector2(r.end.x - bsz.x - 4 * z, r.position.y + 4 * z), bsz)
		draw_rect(br, C_BRASS)
		draw_string(_font, br.position + Vector2(0, br.size.y * 0.75), badge, HORIZONTAL_ALIGNMENT_CENTER, br.size.x, roundi(11 * z), Color("1b1608"))
	if compact:
		return
	var y3 := y2 + 6.0 * z
	if is_rep:
		# one pip a level: green done, outlined planned
		var mx := int(d.get("max", 1))
		var pl := qn + (1 if st == "study" else 0)
		for k in mx:
			var pr := Rect2(tx + k * 17.0 * z, y3, 14.0 * z, 6.0 * z)
			if k < lv: draw_rect(pr, C_DONE)
			else:
				draw_rect(pr, Color("15181a"))
				draw_rect(pr, C_BRASS if k < lv + pl else C_LINE, false, 1.0)
		var eff := GameData.effect_text(d.get("effects", {})) + " a level"
		var dim := C_DIM; dim.a = fade
		draw_string(_font, Vector2(tx, y3 + 8.0 * z + fs2), _fit_text(eff, tw, fs2), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, dim)
		return
	var ub := unlocks(id)
	if not ub.is_empty():
		var bx := tx
		for k in mini(4, ub.size()):
			var bt := Tex.bld_era_tex("bld_" + String(ub[k]), int(d.get("age", 1)))
			if bt != null:
				draw_rect(Rect2(bx, y3, 22 * z, 22 * z), Color("15181a"))
				draw_texture_rect(bt, Rect2(bx + 1, y3 + 1, 20 * z, 20 * z), false, Color(1, 1, 1, fade))
			bx += 24 * z
		if ub.size() > 4:
			draw_string(_font, Vector2(bx + 2, y3 + 16 * z), "+%d" % (ub.size() - 4), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11 * z), C_DIM)
	else:
		var eff2 := GameData.effect_text(d.get("effects", {}))
		if eff2 == "": eff2 = String(d.get("info", ""))
		var dim2 := C_DIM; dim2.a = fade
		# two lines at most
		var words := eff2.split(" ")
		var lines := ["", ""]
		var li := 0
		for wd in words:
			var tryl: String = (lines[li] + " " + wd).strip_edges()
			if _font.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x > tw and lines[li] != "":
				if li == 1:
					lines[1] = _fit_text(lines[1] + " " + wd, tw, fs2)
					break
				li = 1
				lines[1] = wd
			else:
				lines[li] = tryl
		draw_string(_font, Vector2(tx, y3 + fs2), lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, dim2)
		if lines[1] != "":
			draw_string(_font, Vector2(tx, y3 + fs2 * 2 + 2 * z), lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, dim2)
