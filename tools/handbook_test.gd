extends SceneTree
## The handbook and the first-time tips: every building, good, tech, mastery study, age, law and game
## feature has a page, links on the pages lead to pages that exist, the search finds pages by name and
## by words on them, the pages are written in Polish too, the window opens with F1 and follows links
## and Back, the ? in the info box opens the selected building's page, and the tips show once each
## (new age, worn-out tool, smoke), stay away when turned off, and come back when turned on again.
## godot --headless --script res://tools/handbook_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func press(main: Main, k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	main._unhandled_input(e)


func _init() -> void:
	# the player's own settings file is put back at the end
	var kept := FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else PackedByteArray()
	GameData.ensure()
	I18n.setup("en")

	# 1. the pages
	var t0 := Time.get_ticks_msec()
	var hb := Handbook.new()
	hb.make()
	print("pages: %d in %d ms" % [hb.pages.size(), Time.get_ticks_msec() - t0])
	var missing := []
	for id in GameData.bld: if not hb.by_id.has("bld:" + id): missing.append(id)
	for r in GameData.resources: if not hb.by_id.has("res:" + String(r.id)): missing.append(r.id)
	for id in GameData.techs: if not hb.by_id.has("tech:" + id): missing.append(id)
	for id in GameData.reps: if not hb.by_id.has("tech:" + id): missing.append(id)
	for a in GameData.ages.size(): if not hb.by_id.has("age:%d" % a): missing.append("age %d" % a)
	for l in Handbook.LawsScript.law_list(): if not hb.by_id.has("law:" + String(l.id)): missing.append(l.id)
	for f in Features.available(): if not hb.by_id.has("feat:" + String(f.id)): missing.append(f.id)
	check(missing.is_empty(), "a page for every building, good, tech, age, law and feature %s" % [missing])
	var re := RegEx.new()
	re.compile("\\[url=([^\\]]+)\\]")
	var bad := []
	var links := 0
	for p in hb.pages:
		for m in re.search_all(String(p.text)):
			links += 1
			if not hb.by_id.has(m.get_string(1)): bad.append("%s -> %s" % [p.id, m.get_string(1)])
	check(links > 1000 and bad.is_empty(), "%d links, all to pages that exist %s" % [links, bad.slice(0, 5)])
	var saw: String = hb.by_id["bld:sawmill"].text
	check(saw.contains("Logs into planks.") and saw.contains("[url=res:wood]") and saw.contains("[url=res:planks]"), "the sawmill's page: its line, logs in, planks out")
	var steel: String = hb.by_id["bld:steelworks"].text
	check(steel.contains("Smoke:") and steel.contains("[url=feat:factory_health]"), "the steelworks' page tells of its smoke")
	check(String(hb.by_id["bld:park"].text).contains("Clean air:") and String(hb.by_id["bld:waterworks"].text).contains("Clean water:"), "parks and waterworks tell what they clean")
	var planks: String = hb.by_id["res:planks"].text
	check(planks.contains("Made by:") and planks.contains("[url=bld:sawmill]"), "planks: made by the sawmill")
	check(String(hb.by_id["res:axes"].text).contains("Tool:"), "axes are a tool")
	check(String(hb.by_id["tech:iron_working"].text).contains("Opens:"), "iron working opens an age")
	check(String(hb.by_id["law:tax"].text).contains("noble tax"), "the tax law tells its effects")
	check(String(hb.by_id["age:1"].text).contains("picks one of these"), "the Roman age lists its bonuses")
	var s1 := hb.search("sawm")
	check(not s1.is_empty() and s1[0] == "bld:sawmill", "search 'sawm': the sawmill first (%s)" % [s1.slice(0, 3)])
	var s2 := hb.search("planks")
	check(s2.size() > 5 and s2[0] == "res:planks", "search 'planks': the good first, then pages that use it (%d)" % s2.size())
	check(hb.search("zzqx").is_empty(), "nonsense finds nothing")
	check(hb.search("").size() == hb.pages.size(), "an empty search lists every page")

	# 2. in Polish
	I18n.set_language("pl")
	var pl := Handbook.new()
	pl.make()
	var psaw: String = pl.by_id["bld:sawmill"].text
	check(String(pl.by_id["bld:sawmill"].title) == "Tartak" and psaw.contains("Drewno na deski."), "the sawmill in Polish: %s" % pl.by_id["bld:sawmill"].title)
	var en_left := 0
	for p in pl.pages:
		for line in Handbook.plain(String(p.text)).split("\n"):
			for w in ["Cost:", "Made by:", "Used by:", "Needs:", "Worker:", "Effects:", "Size:", "Kind:"]:
				if line.begins_with(w): en_left += 1
	check(en_left == 0, "no English labels left on the Polish pages (%d)" % en_left)
	check(not pl.search("tartak").is_empty() and pl.search("tartak")[0] == "bld:sawmill", "search in Polish: 'tartak'")
	I18n.set_language("en")

	# 3. the window in a game
	var main: Main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	main.settings.keys = {}
	main.settings.tips = true
	main.settings.tips_seen = {}
	main._start("handbook", 2, 5, true)
	main.setup.visible = false
	main.paused = false
	await process_frame
	press(main, KEY_F1)
	check(main.handbook_ui.win.visible and main.handbook_ui.page == "home", "F1 opens the handbook on its first page")
	main.handbook_ui.text.meta_clicked.emit("bld:sawmill")
	check(main.handbook_ui.page == "bld:sawmill", "a link goes to its page")
	main.handbook_ui.show_page("res:planks")
	main.handbook_ui.go_back()
	check(main.handbook_ui.page == "bld:sawmill", "Back returns")
	main.handbook_ui.find.text = "quarry"
	main.handbook_ui.find.text_changed.emit("quarry")
	var first := main.handbook_ui.tree.get_root().get_first_child()
	check(first != null and String(first.get_metadata(0)) == "bld:quarry", "typing 'quarry' lists the quarry first")
	main.handbook_ui.find.text = ""
	main.handbook_ui.find.text_changed.emit("")
	press(main, KEY_F1)
	check(not main.handbook_ui.win.visible, "F1 again closes it")
	var hq: Sim.Bld = null
	for b in main.sim.realm_blds(main.sim.human()):
		if b.ty == "hq": hq = b
	main.view.sel_id = hq.id
	main._handbook_sel()
	check(main.handbook_ui.win.visible and main.handbook_ui.page == "bld:hq", "the ? in the info box opens the headquarters' page")
	main.handbook_ui.win.visible = false

	# 4. tips
	var me := main.sim.human()
	main.tips_ui.check()
	check(main.tips_ui.tip == "" and not main.tips_ui.box.visible, "no tip at the start")
	me.tools_worn += 1
	main.tips_ui.check()
	check(main.tips_ui.tip == "tool" and main.tips_ui.box.visible, "the first worn-out tool shows a tip")
	main.tips_ui.more_btn.pressed.emit()
	check(main.handbook_ui.win.visible and main.handbook_ui.page == "feat:tool_quality", "Read more opens its page")
	main.handbook_ui.win.visible = false
	me.tools_worn += 1
	main.tips_ui.check()
	check(main.tips_ui.tip == "", "it shows only once")
	main.settings.tips = false
	me.age += 1
	main.tips_ui.check()
	check(main.tips_ui.tip == "", "no tips while they are off")
	# turned on again in Settings: all of them come back
	main.settings.tips = true
	main.settings.tips_seen = {}
	main.tips_ui.check()
	if main.age_ui.panel != null: main.age_ui.panel.visible = false
	main.tips_ui.check()
	check(main.tips_ui.tip == "age", "the new age shows its tip (%s)" % main.tips_ui.tip)
	check(main.tips_ui._page("age") == "age:%d" % me.age, "its page is the age you are in")
	main.tips_ui.close()
	var fh = main.sim.get_feature("factory_health")
	if fh != null:
		fh.air[me.id] = 0.3
		main.tips_ui.check()
		check(main.tips_ui.tip == "smoke", "smoke in your homes shows its tip")
		fh.air[me.id] = 0.0
		main.tips_ui.close()
	var seen: Dictionary = main.settings.tips_seen
	check(seen.has("age") and seen.has("smoke"), "the tips seen are kept (%s)" % [seen.keys()])

	main.queue_free()
	await process_frame
	if kept.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(kept)
		f.close()
	print("HANDBOOK TEST: " + ("PASS" if ok else "FAIL"))
	I18n.unload()
	quit()
