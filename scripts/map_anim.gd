class_name MapAnim
extends RefCounted
## The longer animations of the moments players watch most, drawn by the map view (map_view.gd):
## building sites rising in stages, sieges at the walls of a military building, and ships loading
## and unloading at a harbour. They are only pictures: they read the game and never change it, and
## their timing comes from the game clock, so they freeze while the game is paused and speed up with it.

var v       # the MapView that draws them (its drawing calls go to v._cv)

const TIMBER := Color("a27b4c")
const TIMBER_DARK := Color("6a4b2c")
const EARTH := Color("6b5238")
const STONE := Color("a29d92")
const ROPE := Color("d8c9a0")


func _init(view) -> void:
	v = view


# ---------------------------------------------------------------- what a picture covers
## For each picture: the share of it its painted part covers (Rect2, 0..1), and for 24 columns
## across it the share from the top where the painted part starts (1.0: nothing painted there).
var _spans := {}

func _span(tex: Texture2D) -> Array:
	var k := tex.get_rid()
	var e = _spans.get(k)
	if e != null:
		return e
	var used := Rect2(0, 0, 1, 1)
	var cols := PackedFloat32Array()
	cols.resize(24)
	cols.fill(1.0)
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var iw := img.get_width()
		var ih := img.get_height()
		var ur := img.get_used_rect()
		if iw > 0 and ih > 0 and ur.size.x > 0:
			used = Rect2(float(ur.position.x) / iw, float(ur.position.y) / ih, float(ur.size.x) / iw, float(ur.size.y) / ih)
			for c in 24:
				var x := clampi(int((c + 0.5) / 24.0 * iw), 0, iw - 1)
				for y in range(0, ih, 2):
					if img.get_pixel(x, y).a > 0.5:
						cols[c] = float(y) / ih
						break
	e = [used, cols]
	_spans[k] = e
	return e


## The top of the painted part of a picture drawn in rect, at share sx across it (looking a column to
## each side too, so a gap between battlements does not count), in tiles.
func _top_at(sp: Array, rect: Rect2, sx: float) -> float:
	var cols: PackedFloat32Array = sp[1]
	var c := clampi(int(sx * 24.0), 0, 23)
	var t := cols[c]
	if c > 0: t = minf(t, cols[c - 1])
	if c < 23: t = minf(t, cols[c + 1])
	return rect.position.y + rect.size.y * minf(t, 0.95)


# ---------------------------------------------------------------- building sites
## The stages of a site, by its progress p (0..1):
##   from the start: the plot is pegged out with stakes and a line, the ground dug;
##   up to 0.12: the footing is laid, stone by stone;
##   0.08 to 0.45: the timber frame rises post by post, then beams, braces and the rafters;
##   0.22 to 1: the walls fill in from the ground up, inside scaffolding; the roof goes on last;
##   0.9 to 1: the scaffolding comes down and the dug ground is tidied away.
## This is the part that stays still (the building layer keeps it); site_moving draws the people.
func site_still(tex: Texture2D, rect: Rect2, sw: float, p: float, far: bool) -> void:
	var cv = v._cv
	var sp := _span(tex)
	var used: Rect2 = sp[0]
	var l := rect.position.x + rect.size.x * used.position.x
	var r := rect.position.x + rect.size.x * used.end.x
	var gy := rect.position.y + rect.size.y * used.end.y
	var full := rect.size.y * used.size.y
	var wid := r - l
	# the finished building, faintly, as it is meant to be
	cv.draw_texture_rect(tex, rect, false, Color(1, 1, 1, 0.12))
	# the dug ground
	var tidy := 1.0 - clampf((p - 0.9) / 0.1, 0.0, 1.0)
	var pts := PackedVector2Array()
	var cx := (l + r) / 2.0
	for k in 14:
		var a := k * TAU / 14.0
		pts.append(Vector2(cx + cos(a) * (wid / 2.0 + 0.12), gy - 0.08 + sin(a) * 0.16))
	cv.draw_colored_polygon(pts, Color(EARTH.r, EARTH.g, EARTH.b, 0.7 * tidy))
	# stakes at the corners and a line between them, until the footing is down
	if p < 0.2:
		var a := 1.0 - clampf((p - 0.12) / 0.08, 0.0, 1.0)
		var cs := [Vector2(l + 0.02, gy - 0.02), Vector2(r - 0.02, gy - 0.02), Vector2(r - 0.14, gy - 0.22), Vector2(l + 0.14, gy - 0.22)]
		var line := PackedVector2Array()
		for c: Vector2 in cs:
			line.append(c + Vector2(0, -0.1))
		line.append(line[0])
		cv.draw_polyline(line, Color(0.95, 0.93, 0.86, 0.8 * a), 0.018)
		for c: Vector2 in cs:
			cv.draw_line(c, c + Vector2(0, -0.17), Color(STAKE.r, STAKE.g, STAKE.b, a), 0.045)
	# the footing: a course of stones along the front, laid one by one
	var nst := maxi(3, int(wid / 0.2))
	var laid := nst if p >= 0.12 else int(nst * p / 0.12)
	for k in laid:
		var bw := wid / nst
		cv.draw_rect(Rect2(l + k * bw + 0.01, gy - 0.13, bw - 0.02, 0.12), STONE.darkened(0.12 * (k % 2)))
	# the timber frame
	var fp := clampf((p - 0.08) / 0.37, 0.0, 1.0)
	var fh := full * 0.8
	var base := gy - 0.12
	# (the frame is hidden as the walls close over it)
	var fa := 1.0 - clampf((p - 0.72) / 0.2, 0.0, 1.0)
	if fp > 0.0 and fa > 0.0:
		var posts := clampi(int(wid / 0.45) + 1, 3, 7)
		var xs := []
		for k in posts:
			xs.append(lerpf(l + 0.07, r - 0.07, k / float(posts - 1)))
		for k in posts:
			var g := clampf(fp * 1.7 - float(k) / posts * 0.7, 0.0, 1.0)
			if g > 0.0:
				cv.draw_line(Vector2(xs[k], base), Vector2(xs[k], base - fh * g), Color(TIMBER, fa), 0.06)
		if fp > 0.55:
			var ba := clampf((fp - 0.55) / 0.15, 0.0, 1.0) * fa
			cv.draw_line(Vector2(l + 0.04, base - fh * 0.5), Vector2(r - 0.04, base - fh * 0.5), Color(TIMBER_DARK, ba), 0.05)
		if fp > 0.7:
			var ba := clampf((fp - 0.7) / 0.15, 0.0, 1.0) * fa
			for k in posts - 1:
				var up := k % 2 == 0
				cv.draw_line(Vector2(xs[k], base - (0.0 if up else fh * 0.5)), Vector2(xs[k + 1], base - (fh * 0.5 if up else 0.0)), Color(TIMBER.r, TIMBER.g, TIMBER.b, 0.85 * ba), 0.035)
		if fp > 0.85:
			var ba := clampf((fp - 0.85) / 0.15, 0.0, 1.0) * fa
			var top := base - fh
			cv.draw_line(Vector2(l + 0.04, top), Vector2(r - 0.04, top), Color(TIMBER_DARK, ba), 0.05)
			var apex := Vector2(cx, top - minf(0.55, full * 0.22))
			cv.draw_line(Vector2(l, top + 0.02), apex, Color(TIMBER, ba), 0.045)
			cv.draw_line(Vector2(r, top + 0.02), apex, Color(TIMBER, ba), 0.045)
	# the walls (the finished picture), filling in from the ground up
	var wp := clampf((p - 0.22) / 0.78, 0.0, 1.0)
	if wp > 0.0:
		var cut := rect.position.y if wp >= 1.0 else gy - full * wp
		var th := float(tex.get_height())
		var sy := (cut - rect.position.y) / rect.size.y * th
		cv.draw_texture_rect_region(tex, Rect2(rect.position.x, cut, rect.size.x, rect.end.y - cut), Rect2(0, sy, tex.get_width(), th - sy))
	# scaffolding up the front, a little above the walls, and taken down at the end
	var sa := clampf((p - 0.14) / 0.08, 0.0, 1.0) * (1.0 - clampf((p - 0.9) / 0.08, 0.0, 1.0))
	if sa > 0.0 and not far:
		var hgt := minf(full + 0.1, full * wp + 0.45)
		var poles := [l - 0.06, r + 0.06]
		if wid > 1.6:
			poles.insert(1, cx)
		var pole_c := Color(0.55, 0.4, 0.24, sa)
		for x: float in poles:
			cv.draw_line(Vector2(x, gy + 0.02), Vector2(x, gy - hgt), pole_c, 0.04)
		var lv := 0.42
		while lv < hgt:
			cv.draw_rect(Rect2(l - 0.12, gy - lv, wid + 0.24, 0.045), Color(0.72, 0.56, 0.34, sa))
			cv.draw_line(Vector2(l - 0.12, gy - lv + 0.045), Vector2(r + 0.12, gy - lv + 0.045), Color(0.3, 0.2, 0.1, 0.5 * sa), 0.015)
			lv += 0.42
		for k in poles.size() - 1:
			var x0: float = poles[k]
			var x1: float = poles[k + 1]
			cv.draw_line(Vector2(x0, gy), Vector2(x1, gy - minf(hgt, 0.84)), Color(0.55, 0.4, 0.24, 0.55 * sa), 0.022)
	elif far:
		var cs := minf(sw, 1.6)
		cv.draw_texture_rect(v._constr, Rect2(cx - cs / 2.0, gy - cs, cs, cs), false)
const STAKE := Color("8a6a40")


## The people at a site with its builder there: the builder at work at the height the walls have
## reached (on the ground while the footing goes down, then up on the scaffolding), a labourer
## carrying the materials lying at the site over to the walls, and on a big site a hoist lifting loads.
func site_moving(b, tex: Texture2D, rect: Rect2, p: float, pc: Color) -> void:
	var cv = v._cv
	var sim = v.sim
	var anim: bool = v.animate
	var sp := _span(tex)
	var used: Rect2 = sp[0]
	var l := rect.position.x + rect.size.x * used.position.x
	var r := rect.position.x + rect.size.x * used.end.x
	var gy := rect.position.y + rect.size.y * used.end.y
	var full := rect.size.y * used.size.y
	var wid := r - l
	var t: float = sim.time + b.id * 0.71 if anim else 0.0
	var wp := clampf((p - 0.22) / 0.78, 0.0, 1.0)
	# the builder: he works at one spot a while, then moves along to the next
	var stand := gy + 0.04
	if p >= 0.14 and p < 0.92:
		# on the highest plank of the scaffolding below the top of the walls
		var lv := floorf(minf(full * wp + 0.2, full) / 0.42) * 0.42
		stand = gy - lv + 0.04
	var spots := maxi(2, int(wid / 0.5))
	var leg := fposmod(t / 3.2, float(spots))
	var at := int(leg)
	var within := leg - at
	var x0 := lerpf(l + 0.1, r - 0.1, float(at) / (spots - 1)) if spots > 1 else (l + r) / 2.0
	var nx := (at + 1) % spots
	var x1 := lerpf(l + 0.1, r - 0.1, float(nx) / (spots - 1)) if spots > 1 else x0
	var walking := within > 0.8 and anim
	var bx := lerpf(x0, x1, (within - 0.8) / 0.2) if walking else x0
	var flip := x1 < x0 if walking else (at % 2 == 1)
	var hp := Vector2(bx, stand)
	var beat := int(t * 4.0)
	var fr := (int(t * 8.0) % 4) if walking else (4 + beat % 2)
	v._sprite("unit_worker_hammer", hp, 0.4, fr, flip, pc.lightened(0.35))
	if anim and not walking:
		# each blow: a flick of sparks where the hammer lands
		var ph := fposmod(t * 4.0, 1.0)
		if beat % 2 == 1 and ph < 0.3:
			var sx := hp + Vector2(0.2 * (-1.0 if flip else 1.0), -0.22)
			for k in 3:
				var a := -0.6 - k * 0.5
				cv.draw_line(sx, sx + Vector2(cos(a) * (-1.0 if flip else 1.0), sin(a)) * (0.05 + ph * 0.25), Color(1.0, 0.9, 0.5, 1.0 - ph * 3.0), 0.02)
	if not anim:
		return
	# dust drifting up from the site
	var tt := Time.get_ticks_msec() / 1000.0
	for k in 3:
		var dph := fposmod(tt * 0.45 + k * 0.33 + b.id * 0.17, 1.0)
		var dp := Vector2(l + wid * (0.2 + k * 0.3) + sin(tt + k) * 0.05, gy - 0.05 - dph * 0.7)
		cv.draw_circle(dp, 0.07 + dph * 0.12, Color(0.78, 0.7, 0.58, 0.32 * (1.0 - dph)))
	# a labourer bringing the materials over from where they lie, and going back for more
	var res := ""
	for k in b.onsite:
		if v._res_tex.has(k):
			res = k
			break
	if res != "" and p < 0.95:
		var pile := Vector2(b.x + 0.05, b.y + 0.95)
		var wall := Vector2(lerpf(l, r, 0.35), gy + 0.08)
		var cyc := fposmod(t / 4.4, 1.0)
		var going := cyc < 0.5
		var u := cyc * 2.0 if going else (cyc - 0.5) * 2.0
		var pos := pile.lerp(wall, u) if going else wall.lerp(pile, u)
		var pe: Array = v._spr_info("unit_porter")
		var step := int(t * 8.0) % 8
		var pf := step + (0 if going else 8)
		if int(pe[1]) < 18:
			pf = step
		var dirx := (wall.x - pile.x) * (1.0 if going else -1.0)
		var ch: float = v._sprite("unit_porter", pos, 0.4, pf, dirx < 0.0)
		if bool(pe[4]):
			v._sprite("unit_porter_tint", pos, 0.4, pf, dirx < 0.0, pc.lightened(0.25))
		if going:
			cv.draw_texture_rect(v._res_tex[res], Rect2(pos.x - 0.13, pos.y - ch - 0.22, 0.26, 0.26), false)
	# a hoist beside a big building, lifting a load up to the walls and letting the rope down again
	if wid >= 1.9 and p > 0.25 and p < 0.92:
		var mast := Vector2(r + 0.28, gy + 0.02)
		var mh := full * 0.95
		var head := mast + Vector2(0, -mh)
		var tip := head + Vector2(-0.6, 0.06)
		cv.draw_line(mast, head, TIMBER_DARK, 0.06)
		cv.draw_line(head, tip, TIMBER_DARK, 0.045)
		cv.draw_line(mast + Vector2(0, -mh * 0.45), head + Vector2(-0.3, 0.03), TIMBER, 0.03)
		cv.draw_line(mast + Vector2(0.3, 0.0), mast + Vector2(0, -0.3), TIMBER, 0.03)
		var cyc2 := fposmod(t / 5.0, 1.0)
		var lift := sin(clampf(cyc2 * 2.0, 0.0, 1.0) * PI / 2.0) if cyc2 < 0.5 else 1.0 - (cyc2 - 0.5) * 2.0
		var hook := Vector2(tip.x, lerpf(gy - 0.1, gy - full * maxf(0.3, wp) + 0.1, lift))
		cv.draw_line(tip, hook, ROPE, 0.015)
		cv.draw_line(head, mast + Vector2(-0.05, -0.25), ROPE, 0.012)
		var lr := "stone" if v._res_tex.has("stone") else res
		if cyc2 < 0.5 and lr != "" and v._res_tex.has(lr):
			cv.draw_texture_rect(v._res_tex[lr], Rect2(hook.x - 0.13, hook.y, 0.26, 0.26), false)
		else:
			cv.draw_arc(hook + Vector2(0, 0.03), 0.03, 0.0, PI, 6, Color(0.3, 0.3, 0.3), 0.012)


# ---------------------------------------------------------------- sieges
## A siege at the walls of building tgt, attacked by column a, whose front fights at the gate (`at`):
## the defenders on the walls duck, rise and shoot down at the attackers; the attackers' archers shoot
## back; a ladder leans on the wall with soldiers climbing it and being thrown down; a ram beats on
## the gate (dust, splinters); smoke rises from the walls. ndef: the defenders, pairs: how many pairs
## fight at the gate (the rest of the defenders are on the walls).
func siege(a, tgt, at: Vector2, left: bool, ndef: int, pairs: int, did: String, dcol: Color, aid: String, acol: Color) -> void:
	if v.zoom < v.ANIM_ZOOM:
		return
	var bc = v._bd.get(tgt)
	if bc == null:
		return
	var cv = v._cv
	var sim = v.sim
	var anim: bool = v.animate
	var tex: Texture2D = bc[2]
	var rect: Rect2 = bc[4]
	var sp := _span(tex)
	var used: Rect2 = sp[0]
	var l := rect.position.x + rect.size.x * used.position.x
	var r := rect.position.x + rect.size.x * used.end.x
	var gy := rect.position.y + rect.size.y * used.end.y
	var t: float = sim.time + a.uid * 0.37 if anim else 0.0
	var dgun := did.begins_with("unit_soldier_e5") or did.begins_with("unit_soldier_e6")
	var agun := aid.begins_with("unit_soldier_e5") or aid.begins_with("unit_soldier_e6")
	var target := at + Vector2(0, -0.25)
	# smoke from the walls, thicker as the garrison falls
	if anim:
		var cap := maxi(1, int(tgt.def.get("garrison", 1)))
		var hurt := clampf(1.0 - float(ndef) / cap, 0.2, 1.0)
		var sx := 0.3 if tgt.id % 2 == 0 else 0.7
		v._smoke_at(Vector2(lerpf(l, r, sx), _top_at(sp, rect, used.position.x + used.size.x * sx) + 0.2), tgt.id * 0.31, 0.6 + hurt)
		for k in 3:
			var eph := fposmod(t * 0.9 + k * 0.33, 1.0)
			var ep := Vector2(lerpf(l, r, sx) + sin(t * 3.0 + k) * 0.15, _top_at(sp, rect, used.position.x + used.size.x * sx) + 0.1 - eph * 0.9)
			cv.draw_circle(ep, 0.025, Color(1.0, 0.6, 0.2, 0.9 * (1.0 - eph)))
	# the defenders on the walls
	var nw := clampi(ndef - pairs, 1 if ndef > 0 else 0, 4)
	for k in nw:
		var sx := lerpf(0.2, 0.8, (k + 0.5) / nw)
		var wx := used.position.x + used.size.x * sx
		var top := _top_at(sp, rect, wx)
		var px := rect.position.x + rect.size.x * wx
		var ph := fposmod(t * 0.55 + k * 0.41, 1.0) if anim else 0.4
		# 0..0.2 ducked behind the parapet, rising; 0.2..0.65 taking aim; then the shot
		var up := clampf(ph / 0.2, 0.0, 1.0)
		var fr := 4 if ph < 0.65 else 5
		_upper(did, Vector2(px, top + 0.3), 0.42, fr, target.x < px, dcol, 0.55 * up + 0.1)
		if anim and ph >= 0.65:
			var u := (ph - 0.65) / 0.35
			var from := Vector2(px, top + 0.05)
			var to := target + Vector2((k - nw / 2.0) * 0.22, (k % 2) * 0.15)
			if dgun:
				_gun_puff(from, u)
			else:
				_arrow(from, to, u, 0.9)
	# the attackers' answer: arrows (or shots) from the back of the column up at the walls
	if anim:
		var back := at + Vector2(0.95 * (1.0 if left else -1.0), 0.35)
		for k in 2:
			var ph := fposmod(t * 0.5 + 0.5 * k + 0.2, 1.0)
			if ph < 0.45:
				var u := ph / 0.45
				var wx := used.position.x + used.size.x * (0.3 + 0.4 * k)
				var to := Vector2(rect.position.x + rect.size.x * wx, _top_at(sp, rect, wx) + 0.25)
				if agun:
					_gun_puff(back + Vector2(0, -0.3), u)
				else:
					_arrow(back + Vector2(0, -0.3), to, u, 1.2)
	# a ladder against the wall, on the side the column came from, with a soldier on it
	if a.n >= 4:
		var side := 0.22 if left else 0.78
		var wx := used.position.x + used.size.x * side
		var top := _top_at(sp, rect, wx) + 0.12
		var lx := rect.position.x + rect.size.x * wx
		var foot := Vector2(lx + (-0.35 if side < 0.5 else 0.35), gy + 0.12)
		var head := Vector2(lx, top)
		var dirv := head - foot
		var nrm := Vector2(-dirv.y, dirv.x).normalized() * 0.09
		cv.draw_line(foot - nrm, head - nrm, TIMBER_DARK, 0.03)
		cv.draw_line(foot + nrm, head + nrm, TIMBER_DARK, 0.03)
		var rungs := int(dirv.length() / 0.16)
		for k in range(1, rungs):
			var q := foot.lerp(head, float(k) / rungs)
			cv.draw_line(q - nrm, q + nrm, TIMBER, 0.022)
		# the climber: up the ladder, a moment's struggle at the top, then thrown down
		var cyc := fposmod(t / 4.5, 1.0) if anim else 0.4
		var flip := head.x < foot.x
		if cyc < 0.62:
			var u := cyc / 0.62
			var pos := foot.lerp(head, u * 0.92) + Vector2(0, 0.12)
			v._sprite(aid, pos, 0.42, int(t * 6.0) % 4, flip, acol)
		elif cyc < 0.8:
			v._sprite(aid, head + Vector2(0, 0.05), 0.42, 4 + int(t * 6.0) % 2, flip, acol)
		else:
			var u := (cyc - 0.8) / 0.2
			var pos := head.lerp(foot + Vector2((foot.x - head.x) * 0.6, 0), u) + Vector2(0, -sin(u * PI) * 0.3)
			var e: Array = v._spr_info(aid)
			var stex: Texture2D = e[0]
			var src := Rect2(0, 0, float(e[2]), float(e[3]))
			var hgt := 0.42 * src.size.y / maxf(1.0, src.size.x)
			cv.draw_set_transform(v._origin + pos * v.zoom, u * PI * (1.2 if foot.x > head.x else -1.2), Vector2(v.zoom, v.zoom))
			cv.draw_texture_rect_region(stex, Rect2(-0.21, -hgt, 0.42, hgt), src, acol)
			cv.draw_set_transform(v._origin, 0.0, Vector2(v.zoom, v.zoom))
	# a ram beating on the gate
	if a.n >= 6:
		var gate := Vector2((l + r) / 2.0, gy - 0.05)
		var cyc := fposmod(t / 1.6, 1.0) if anim else 0.3
		# drawn back slowly, swung in fast
		var swing := cyc / 0.7 if cyc < 0.7 else 1.0 - (cyc - 0.7) / 0.3
		# seen from the front: the iron-capped log swinging out of the back of its shed of hides
		var shed := gate + Vector2(0, 0.46)
		var log_end := gate + Vector2(0, 0.02 + 0.2 * swing)
		cv.draw_line(shed + Vector2(0, -0.2), log_end, Color("4e3620"), 0.15)
		cv.draw_circle(log_end, 0.08, Color("6f6f72"))
		cv.draw_circle(log_end + Vector2(-0.02, -0.02), 0.035, Color("a0a0a4"))
		var roof := PackedVector2Array([shed + Vector2(-0.42, 0.1), shed + Vector2(0, -0.34), shed + Vector2(0.42, 0.1)])
		cv.draw_colored_polygon(roof, Color("7a5c3c"))
		for k in 3:
			var q := 0.25 + k * 0.25
			cv.draw_line(shed + Vector2(-0.42 * q, 0.1 - 0.44 * (1.0 - q)), shed + Vector2(0.42 * q, 0.1 - 0.44 * (1.0 - q)), Color(0.33, 0.23, 0.13, 0.8), 0.02)
		roof.append(roof[0])
		cv.draw_polyline(roof, Color(0.2, 0.13, 0.06), 0.025)
		cv.draw_circle(shed + Vector2(-0.33, 0.12), 0.08, Color("3e2c18"))
		cv.draw_circle(shed + Vector2(0.33, 0.12), 0.08, Color("3e2c18"))
		if anim and (cyc > 0.95 or cyc < 0.2):
			var u := (cyc - 0.95) / 0.25 if cyc > 0.95 else (cyc + 0.05) / 0.25
			for k in 6:
				var ang := -PI / 2.0 + (k - 2.5) * 0.45
				cv.draw_circle(gate + Vector2(cos(ang) * 0.5, sin(ang) * 0.25) * (0.3 + u), 0.06 + u * 0.12, Color(0.78, 0.72, 0.6, 0.55 * (1.0 - u)))
			for k in 4:
				var ang := -PI / 2.0 + (k - 1.5) * 0.7
				var sp2 := gate + Vector2(cos(ang), sin(ang)) * (0.1 + u * 0.4) + Vector2(0, u * u * 0.3)
				cv.draw_line(sp2, sp2 + Vector2(cos(ang + 1.0), sin(ang + 1.0)) * 0.07, Color("8a6a40"), 0.025)


## The upper part of soldier picture id (head and shoulders above a parapet): show is the share of
## the picture shown, from its top; foot is where its feet would be.
func _upper(id: String, foot: Vector2, wid: float, f: int, flip: bool, col: Color, show: float) -> void:
	var e: Array = v._spr_info(id)
	var tex: Texture2D = e[0]
	var fw: float = e[2]
	var fh: float = e[3]
	var hgt := wid * fh / maxf(1.0, fw)
	var src := Rect2(fw * posmod(f, int(e[1])), 0, fw, fh * show)
	var dst := Rect2(foot.x - wid / 2.0, foot.y - hgt, wid, hgt * show)
	if flip:
		dst = Rect2(foot.x + wid / 2.0, foot.y - hgt, -wid, hgt * show)
	v._cv.draw_texture_rect_region(tex, dst, src, col)


## An arrow u (0..1) of the way from a to b, arcing up by `arc` tiles.
func _arrow(a: Vector2, b: Vector2, u: float, arc: float) -> void:
	var p0 := a.lerp(b, u) + Vector2(0, -sin(u * PI) * arc)
	var u1 := minf(1.0, u + 0.04)
	var p1 := a.lerp(b, u1) + Vector2(0, -sin(u1 * PI) * arc)
	var d := (p1 - p0).normalized() * 0.26
	if d == Vector2.ZERO:
		return
	var cv = v._cv
	cv.draw_line(p0 - d, p0, Color(0.28, 0.2, 0.1), 0.03)
	cv.draw_line(p0 - d, p0 - d * 0.7, Color(0.95, 0.95, 0.92), 0.05)


## A puff of gun smoke at p, u (0..1) after the shot, with the flash at first.
func _gun_puff(p: Vector2, u: float) -> void:
	var cv = v._cv
	cv.draw_circle(p + Vector2(0, -u * 0.25), 0.08 + u * 0.18, Color(0.92, 0.92, 0.88, 0.7 * (1.0 - u)))
	if u < 0.2:
		cv.draw_circle(p, 0.05, Color(1.0, 0.85, 0.4, 0.95))


# ---------------------------------------------------------------- ships at a harbour
## A cargo ship's first and last moments of its outward voyage are spent at the quays: loading at the
## harbour it sails from and unloading at the one it sails to (the voyage's planned time has two
## seconds to spare for it). How long, in game seconds, each.
func _dwell(t) -> float:
	return clampf((t.t1 - t.t0) * 0.2, 0.0, 1.5)


## How far along its way a ship on its outward voyage is drawn (0..1): still at the first harbour
## while it loads, already at the second while it unloads.
func ship_prog(t) -> float:
	var sim = v.sim
	var total: float = maxf(0.01, t.t1 - t.t0)
	var d0 := _dwell(t) if _quay(t, true) != null else 0.0
	var d1 := _dwell(t) if _quay(t, false) != null else 0.0
	# it lies at the first water of its way (the way starts on the harbour's own tile)
	var n: int = t.path.size() - 1
	var i0 := 0
	while i0 < mini(n, 4) and not _open_water(t.path[i0]):
		i0 += 1
	var i1 := n
	while i1 > maxi(i0, n - 4) and not _open_water(t.path[i1]):
		i1 -= 1
	var p0 := float(i0) / maxf(1.0, n) if d0 > 0.0 else 0.0
	var p1 := float(i1) / maxf(1.0, n) if d1 > 0.0 else 0.999
	var e: float = sim.time - t.t0
	if e <= d0:
		return p0
	if e >= total - d1:
		return minf(p1, 0.999)
	return lerpf(p0, minf(p1, 0.999), clampf((e - d0) / maxf(0.01, total - d0 - d1), 0.0, 1.0))


## Whether tile i and the four round it are water (where a ship looks afloat, clear of the beach).
func _open_water(i: int) -> bool:
	var sim = v.sim
	var x: int = i % sim.w
	var y: int = i / sim.w
	for d: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if not sim.inb(x + d.x, y + d.y) or sim.ter[sim.idx(x + d.x, y + d.y)] != Sim.WATER:
			return false
	return true


## The harbour a ship loads at (from) or unloads at, or null.
func _quay(t, from: bool):
	var b = v.sim.by_id.get(t.site if from else t.dest)
	if b == null or b.dead or not v.sim.sea.is_harbour(b):
		return null
	return b


## [harbour, how far through (0..1), loading] while ship t is at a quay, or [].
func docked(t) -> Array:
	if t.kind != "ship" or t.delivered or t.res == "":
		return []
	var e: float = v.sim.time - t.t0
	var dw := _dwell(t)
	if dw <= 0.0:
		return []
	if e < dw:
		var h = _quay(t, true)
		return [h, e / dw, true] if h != null else []
	var left: float = t.t1 - v.sim.time
	if left < dw and left >= 0.0:
		var h = _quay(t, false)
		return [h, 1.0 - left / dw, false] if h != null else []
	return []


## The work at the quay round a docked ship at pos (its sail furled): a gangplank to the shore,
## dockers carrying the cargo across it (aboard when loading, ashore when unloading), and the cargo on
## deck growing or shrinking.
func dock_work(t, pos: Vector2, dock: Array, pc: Color) -> void:
	var cv = v._cv
	var sim = v.sim
	var h = dock[0]
	var u: float = dock[1]
	var loading: bool = dock[2]
	var res: String = "planks" if t.res == "@expedition" else String(t.res)
	var rt: Texture2D = v._res_tex.get(res)
	var anim: bool = v.animate
	var tm: float = sim.time + t.t0 if anim else 0.0
	var bob := 0.03 * sin(sim.time * 3.0 + t.t0)
	var deck := pos + Vector2(0, -0.36 + bob)
	# the cargo on deck: a stack that grows while loading and shrinks while unloading
	var have := u if loading else 1.0 - u
	if rt != null:
		var n := clampi(int(ceil(have * 4.0)), 0, 4)
		for k in n:
			var c := deck + Vector2(-0.3 + (k % 2) * 0.28, -0.24 - (k / 2) * 0.2)
			cv.draw_texture_rect(rt, Rect2(c, Vector2(0.28, 0.28)), false)
	# the shore: the first land toward the harbour from the ship
	var hc := Vector2(h.x + 0.5, h.y + 0.9)
	var dirv := (hc - pos).normalized()
	var shore := pos
	for k in 24:
		var q := pos + dirv * (0.25 * k)
		var i: int = sim.idx(clampi(int(q.x), 0, sim.w - 1), clampi(int(q.y - 0.4), 0, sim.h - 1))
		if sim.ter[i] != Sim.WATER:
			shore = q
			break
	if shore == pos:
		shore = pos + dirv * 0.8
	var plank0 := deck + dirv * 0.35
	# a jetty of boards on posts out to the ship (a short gangplank when it lies close in)
	var jl := plank0.distance_to(shore)
	if jl > 0.9:
		var nposts := int(jl / 0.45)
		for k in range(1, nposts + 1):
			var q := shore.lerp(plank0, float(k) / (nposts + 1))
			cv.draw_line(q + Vector2(0, 0.04), q + Vector2(0, 0.2), Color("4a3520"), 0.05)
		cv.draw_line(plank0, shore, Color("9a774a"), 0.2)
		var nb := int(jl / 0.12)
		var side := (plank0 - shore).normalized().orthogonal() * 0.1
		for k in nb:
			var q := shore.lerp(plank0, (k + 0.5) / nb)
			cv.draw_line(q - side, q + side, Color(0.36, 0.25, 0.13, 0.5), 0.012)
		cv.draw_line(plank0 + Vector2(0, 0.1), shore + Vector2(0, 0.1), Color(0.25, 0.17, 0.08, 0.7), 0.025)
	else:
		cv.draw_line(plank0, shore, Color("8a6a40"), 0.09)
		cv.draw_line(plank0 + Vector2(0, 0.04), shore + Vector2(0, 0.04), Color(0.25, 0.17, 0.08, 0.6), 0.02)
	# dockers across the gangplank and along the quay
	var quay := shore + (shore - hc).normalized() * -0.6
	for k in 2:
		var ph := fposmod(tm / 2.2 + k * 0.5, 1.0)
		var out := ph < 0.5
		var w := ph * 2.0 if out else (ph - 0.5) * 2.0
		# loading: from the quay to the deck with a load, back empty; unloading the other way
		var a := quay if loading else plank0
		var b := plank0 if loading else quay
		var p := a.lerp(b, w) if out else b.lerp(a, w)
		var loaded := out
		var pe: Array = v._spr_info("unit_porter")
		var step := int(tm * 8.0) % 8
		var fr := step + (0 if loaded else 8)
		if int(pe[1]) < 18:
			fr = step
		var flip := ((b.x - a.x) * (1.0 if out else -1.0)) < 0.0
		var ch: float = v._sprite("unit_porter", p + Vector2(0, 0.1), 0.38, fr, flip)
		if bool(pe[4]):
			v._sprite("unit_porter_tint", p + Vector2(0, 0.1), 0.38, fr, flip, pc.lightened(0.25))
		if loaded and rt != null:
			cv.draw_texture_rect(rt, Rect2(p + Vector2(-0.12, 0.1 - ch - 0.22), Vector2(0.24, 0.24)), false)
