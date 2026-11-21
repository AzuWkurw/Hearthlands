class_name UiChronicle
extends RefCounted
## The chronicle window (build 77): the written history of the game that just ended (chronicle.gd),
## followed by every realm's people and land over the whole game, with buttons to play the border replay
## and to open the realm graphs. The end-of-game screen opens it ("Read the chronicle").

var main: Main
var win: Window
var text: RichTextLabel
var pop_chart: LineChart
var land_chart: LineChart
var charts: Control
var graph_btns: Control
var legend: RichTextLabel
var won := false


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Chronicle of the realm"
	win.transient = true
	win.visible = false
	win.wrap_controls = false
	win.size = Vector2i(880, 760)
	win.min_size = Vector2i(480, 360)
	win.theme = UiLog.window_theme()
	win.close_requested.connect(func(): win.visible = false)
	win.window_input.connect(func(e): if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE: win.visible = false)
	main.add_child(win)
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(1.0))
	win.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	bg.add_child(v)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.selection_enabled = true
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.add_theme_color_override("default_color", Color("e6e2d3"))
	v.add_child(text)
	# the realms over the whole game
	charts = HBoxContainer.new()
	charts.add_theme_constant_override("separation", 10)
	v.add_child(charts)
	pop_chart = _chart(charts, "People")
	land_chart = _chart(charts, "Land (tiles)")
	legend = RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(legend)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	graph_btns = HBoxContainer.new()
	graph_btns.add_theme_constant_override("separation", 8)
	row.add_child(graph_btns)
	var wb := main._button("Watch the borders", func():
		var st = main.sim.get_feature("statistics")
		if st != null:
			win.visible = false
			main.end_panel.visible = false
			st.replay())
	wb.tooltip_text = "Everyone's land, minute by minute, from the start (in Statistics, Borders)."
	graph_btns.add_child(wb)
	var gb := main._button("Realm graphs", func():
		var st = main.sim.get_feature("statistics")
		if st != null:
			win.visible = false
			main.end_panel.visible = false
			st.open_realms())
	gb.tooltip_text = "Every realm compared over time: people, buildings, soldiers, goods, research, land, gold."
	graph_btns.add_child(gb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(main._button("Close", func(): win.visible = false))


func _chart(parent: Control, title: String) -> LineChart:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	box.add_child(main._label(title, 13, Main.BRASS))
	var c := LineChart.new()
	c.custom_minimum_size = Vector2(300, 150)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(c)
	return c


## Fills the window for the game that just ended (win: whether you won) and shows it.
func open(p_won: bool) -> void:
	won = p_won
	refresh()
	win.popup_centered()


func refresh() -> void:
	var sim: Sim = main.sim
	text.text = Chronicle.new().story(sim, won)
	text.scroll_to_line(0)
	var has_stats: bool = sim.get_feature("statistics") != null
	charts.visible = has_stats
	legend.visible = has_stats
	graph_btns.visible = has_stats
	if not has_stats:
		return
	for pair in [[pop_chart, "pop"], [land_chart, "land"]]:
		var s: Array = Chronicle.series(sim, pair[1])
		var c: LineChart = pair[0]
		c.x_from = int(s[1])
		c.set_series(s[0])
	var parts := []
	for q: Sim.Player in sim.players:
		parts.append("[color=#%s]■ %s[/color]" % [q.color.to_html(false), q.name])
	legend.text = "   ".join(parts) + "   [color=#9a9c88]%s[/color]" % tr("(along the bottom: game minutes)")

