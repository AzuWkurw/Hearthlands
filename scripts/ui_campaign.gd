class_name UiCampaign
extends RefCounted
## The campaign: the chapters of data/campaign.json on a parchment map, each a mission with a story
## before and after it. A chapter opens when the one before it is won. Winning a chapter can carry
## something into the next (veteran soldiers, a stock of goods), and the map remembers the best time
## and score of each chapter. Progress is kept in user://campaign_progress.json.

const DATA := "res://data/campaign.json"
const PROGRESS := "user://campaign_progress.json"

var main: Main
var win: Window
var map: Control
var detail: VBoxContainer
var chapters: Array = []
var title := ""
var sel := 0
var progress := {"done": {}}
var playing := ""        # the chapter being played ("" when none)


func _init(p_owner: Main) -> void:
	main = p_owner


func load_data() -> void:
	chapters = []
	if FileAccess.file_exists(DATA):
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if d is Dictionary:
			chapters = d.get("chapters", [])
			title = String(d.get("name", "Campaign"))
	progress = {"done": {}}
	if FileAccess.file_exists(PROGRESS):
		var p = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS))
		if p is Dictionary:
			progress = p
	if not progress.has("done"):
		progress["done"] = {}


func save_progress() -> void:
	var f := FileAccess.open(PROGRESS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(progress, "\t"))


func is_done(k: int) -> bool:
	return (progress.done as Dictionary).has(String(chapters[k].id))


func is_open(k: int) -> bool:
	return k == 0 or is_done(k - 1)


func build() -> void:
	win = Window.new()
	win.title = "Campaign"
	win.transient = true
	win.wrap_controls = false
	win.size = Vector2i(860, 640)
	win.theme = UiLog.window_theme()
	win.visible = false
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.96))
	win.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	bg.add_child(v)
	map = Control.new()
	map.custom_minimum_size = Vector2(840, 340)
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.draw.connect(_draw_map)
	map.gui_input.connect(_map_input)
	v.add_child(map)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(detail)
	win.close_requested.connect(func(): win.visible = false)
	main.add_child(win)


func show() -> void:
	load_data()
	if chapters.is_empty():
		main._show_hint("No campaign found (data/campaign.json).", 4.0)
		return
	# the first chapter not yet won
	sel = 0
	for k in chapters.size():
		if is_open(k):
			sel = k
		if not is_done(k):
			break
	_fill()
	win.popup_centered()


func _node_pos(k: int) -> Vector2:
	var p: Array = chapters[k].get("pos", [0.5, 0.5])
	return Vector2(30 + float(p[0]) * (map.size.x - 60), 30 + float(p[1]) * (map.size.y - 60))


func _draw_map() -> void:
	var sz := map.size
	map.draw_rect(Rect2(Vector2.ZERO, sz), Color("cdbb8e"))
	map.draw_rect(Rect2(Vector2(6, 6), sz - Vector2(12, 12)), Color("7a6640"), false, 2.0)
	var font := map.get_theme_default_font()
	map.draw_string(font, Vector2(20, 30), map.tr(title), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("3a2410"))
	# the road from chapter to chapter, dashed
	for k in range(1, chapters.size()):
		var a := _node_pos(k - 1)
		var b := _node_pos(k)
		var n := int(a.distance_to(b) / 12.0)
		for s in n:
			if s % 2 == 0:
				map.draw_line(a.lerp(b, float(s) / n), a.lerp(b, float(s + 1) / n), Color("7a3a2a") if is_done(k - 1) else Color(0.48, 0.4, 0.25, 0.6), 3.0)
	for k in chapters.size():
		var p := _node_pos(k)
		var col := Color("86ad5c") if is_done(k) else (Color("d8aa4a") if is_open(k) else Color("9a948a"))
		if k == sel:
			map.draw_circle(p, 20, Color(0.23, 0.14, 0.06, 0.35))
		map.draw_circle(p, 15, col)
		map.draw_arc(p, 15, 0, TAU, 32, Color("3a2410"), 2.0)
		var mark := "✔" if is_done(k) else str(k + 1)
		map.draw_string(font, p + Vector2(-6, 6), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("1b1e15"))
		var nm := String(chapters[k].mission.get("name", "")).get_slice(": ", 1)
		map.draw_string(font, p + Vector2(-90, 34), map.tr(nm), HORIZONTAL_ALIGNMENT_CENTER, 180, 12, Color("3a2410"))


func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for k in chapters.size():
			if _node_pos(k).distance_to(ev.position) < 20:
				sel = k
				_fill()
				return


func _fill() -> void:
	map.queue_redraw()
	for c in detail.get_children():
		c.queue_free()
	var ch: Dictionary = chapters[sel]
	var ms: Dictionary = ch.mission
	detail.add_child(main._label(String(ms.get("name", "")), 19, Main.BRASS))
	var intro := main._label(String(ch.get("intro", "")), 14)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(800, 0)
	detail.add_child(intro)
	var lines := []
	lines.append("New in this chapter: " + String(ch.get("new", "")))
	for g in ms.get("goals", []):
		lines.append("  •  " + String(g.get("text", "")))
	var mins := int(ms.get("minutes", 0))
	lines.append("%d rival%s, strength %d%s" % [int(ms.get("foes", 1)), "s" if int(ms.get("foes", 1)) > 1 else "", int(ms.get("strength", 5)), (", within %d minutes" % mins) if mins > 0 else ""])
	var bonus := _bonus_for(sel)
	if not bonus.is_empty():
		lines.append("Carried over from the chapter before: " + _bonus_text(bonus))
	var rec = (progress.done as Dictionary).get(String(ch.id))
	if rec != null:
		lines.append("Won: best time %d:%02d, best score %d" % [int(rec.secs) / 60, int(rec.secs) % 60, int(rec.score)])
	detail.add_child(main._label("\n".join(lines), 13, Main.DIM))
	if is_open(sel):
		var play := main._button("Play this chapter" if not is_done(sel) else "Play it again", func(): start(sel))
		play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		detail.add_child(play)
	else:
		detail.add_child(main._label("Win the chapter before to open this one.", 13, Color("e0b060")))


## What winning the chapter before k carries into chapter k.
func _bonus_for(k: int) -> Dictionary:
	if k <= 0 or not is_done(k - 1):
		return {}
	return chapters[k - 1].get("carry", {})


func _bonus_text(b: Dictionary) -> String:
	var parts := []
	if int(b.get("soldiers", 0)) > 0:
		parts.append("%d veteran soldiers" % int(b.soldiers))
	if b.has("goods"):
		parts.append(Diplomacy.goods_text(b.goods))
	return ", ".join(parts)


func start(k: int) -> void:
	var ms: Dictionary = (chapters[k].mission as Dictionary).duplicate(true)
	ms["campaign"] = String(chapters[k].id)
	var b := _bonus_for(k)
	if not b.is_empty():
		ms["bonus"] = b
	win.visible = false
	if not main.start_mission(ms):
		main._show_hint("This chapter could not be started.", 5.0)
		return
	playing = String(chapters[k].id)
	main.sim.emit_log(String(chapters[k].get("intro", "")), Color("e8c870"))


## The game ended (main._on_end): a won chapter is recorded with its time and score. Returns the
## chapter's closing text (or the hint to try again), for the end screen.
func on_end(won: bool) -> String:
	var cid := String(main.sim.mission.get("campaign", ""))
	if cid == "":
		return ""
	load_data()
	var k := -1
	for i in chapters.size():
		if String(chapters[i].id) == cid:
			k = i
	if k < 0:
		return ""
	if not won:
		return "\n\nThe chronicle waits: try the chapter again from Campaign on the new-game screen."
	var sim: Sim = main.sim
	var me := sim.human()
	var score: int = sim.pop_total(me) + sim.owned(me.id)[0].size() / 10 + sim.soldiers(me) * 2 + maxi(0, int(float(sim.mission.get("minutes", 0)) * 60.0 - sim.time)) / 10
	var rec: Dictionary = (progress.done as Dictionary).get(cid, {})
	rec["secs"] = mini(int(rec.get("secs", 1 << 30)), int(sim.time))
	rec["score"] = maxi(int(rec.get("score", 0)), score)
	progress.done[cid] = rec
	save_progress()
	var t := "\n\n" + String(chapters[k].get("outro", "")) + "\nScore %d." % score
	if k + 1 < chapters.size():
		t += " The next chapter is open: %s." % String(chapters[k + 1].mission.get("name", ""))
	else:
		t += " The chronicle is complete!"
	return t


func has_next() -> bool:
	var cid := String(main.sim.mission.get("campaign", ""))
	for i in chapters.size():
		if String(chapters[i].id) == cid:
			return i + 1 < chapters.size() and is_done(i)
	return false


func play_next() -> void:
	var cid := String(main.sim.mission.get("campaign", ""))
	for i in chapters.size():
		if String(chapters[i].id) == cid and i + 1 < chapters.size():
			start(i + 1)
			return
