class_name LineChart
extends Control
## A simple line chart: one line per series over the same time axis, newest on the right.
## Set `series` to [{"name": String, "color": Color, "values": Array of numbers}, ...] and `x_label`.

var series: Array = []
var x_label := "minutes ago"
var unit := ""
var x_from := -1   # when 0 or more: the bottom shows game minutes counted from this one, not "minutes ago"


func _ready() -> void:
	custom_minimum_size = Vector2(420, 220)


func set_series(s: Array) -> void:
	series = s
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 12
	var left := 44.0
	var bottom := 22.0
	var area := Rect2(left, 8, size.x - left - 8, size.y - bottom - 8)
	draw_rect(area, Color(0, 0, 0, 0.25))
	var n := 0
	var top := 0.0
	for s in series:
		n = maxi(n, (s.values as Array).size())
		for v in s.values:
			top = maxf(top, float(v))
	if n < 2:
		draw_string(font, area.position + Vector2(10, 20), "Not enough data yet: one point per game minute.", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.6))
		return
	top = _nice(top)
	# horizontal grid lines with their values
	for k in 5:
		var y := area.end.y - area.size.y * k / 4.0
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.08))
		draw_string(font, Vector2(2, y + 4), _fmt(top * k / 4.0), HORIZONTAL_ALIGNMENT_RIGHT, left - 6, fs, Color(0.7, 0.7, 0.6))
	# time labels along the bottom
	for k in 5:
		var x := area.position.x + area.size.x * k / 4.0
		var ago := roundi((n - 1) * (1.0 - k / 4.0))
		var lbl := ("now" if ago == 0 else str(ago)) if x_from < 0 else str(x_from + n - ago)
		draw_string(font, Vector2(x - 20, size.y - 4), lbl, HORIZONTAL_ALIGNMENT_CENTER, 40, fs, Color(0.7, 0.7, 0.6))
	for s in series:
		var vals: Array = s.values
		var pts := PackedVector2Array()
		var off := n - vals.size()
		for i in vals.size():
			var x := area.position.x + area.size.x * float(i + off) / float(n - 1)
			var y := area.end.y - area.size.y * clampf(float(vals[i]) / maxf(top, 0.0001), 0.0, 1.0)
			pts.append(Vector2(x, y))
		if pts.size() >= 2:
			draw_polyline(pts, s.color, 2.0, true)


## A round number just above v, so the scale reads well.
func _nice(v: float) -> float:
	if v <= 0.0:
		return 1.0
	var e := pow(10.0, floorf(log(v) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if v <= m * e:
			return m * e
	return 10.0 * e


func _fmt(v: float) -> String:
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return str(roundi(v)) if v >= 10.0 or is_equal_approx(v, roundf(v)) else "%.1f" % v
