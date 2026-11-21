extends SceneTree
## Rebindable keys (keys.gd): swapping on a clash, Shift and Ctrl combinations, reset, saving, cleaning
## up clashing keys from older settings files, keys of game features, and the keys working in a game.
## godot --headless --script res://tools/keys_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func press(main: Main, k: int, down := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k & KEY_CODE_MASK
	e.shift_pressed = k & KEY_MASK_SHIFT != 0
	e.ctrl_pressed = k & KEY_MASK_CTRL != 0
	e.alt_pressed = k & KEY_MASK_ALT != 0
	e.pressed = down
	main._unhandled_input(e)


func key_event(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k & KEY_CODE_MASK
	e.shift_pressed = k & KEY_MASK_SHIFT != 0
	e.ctrl_pressed = k & KEY_MASK_CTRL != 0
	e.pressed = true
	return e


func _init() -> void:
	# the player's own settings file is put back at the end
	var kept := FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else PackedByteArray()

	# 1. every default key is different, and none is Esc or Enter
	var st := Settings.new()
	var ks := Keys.new(st)
	var seen := {}
	var clash := ""
	for a in ks.actions():
		var k := int(a[2])
		if seen.has(k) or not Keys.usable(k):
			clash += " " + String(a[0])
		seen[k] = true
	check(clash == "", "%d shortcuts, each on its own key%s" % [ks.actions().size(), clash])
	check(ks.actions().size() >= 40, "at least 40 shortcuts can be changed")
	check(ks.action_of(key_event(KEY_E)) == "events" and ks.action_of(key_event(KEY_MASK_SHIFT | KEY_Q)) == "queue_site" and ks.action_of(key_event(KEY_Q)) == "copy", "E, Q and Shift+Q do their own things")
	check(ks.action_of(key_event(KEY_MASK_SHIFT | KEY_R)) == "turn", "Shift+R still turns (the other way)")
	check(ks.action_of(key_event(KEY_UP)) == "pan_up" and ks.action_of(key_event(KEY_KP_ADD)) == "zoom_in", "arrow keys and keypad + are second keys")

	# 2. a key another action has: the two swap
	var msg := ks.set_key("sites", KEY_Q)
	check(ks.key_for("sites") == KEY_Q and ks.key_for("copy") == KEY_B, "sites on Q, copy swapped to B")
	check(msg.contains("Q") and msg.contains("B"), "the player is told: %s" % msg)
	check(ks.action_of(key_event(KEY_Q)) == "sites" and ks.action_of(key_event(KEY_B)) == "copy", "the keys do the swapped actions")
	# a key with Ctrl
	ks.set_key("market", KEY_MASK_CTRL | KEY_M)
	check(ks.action_of(key_event(KEY_MASK_CTRL | KEY_M)) == "market" and ks.action_of(key_event(KEY_M)) == "", "Ctrl+M opens the market, M alone does nothing now")
	check(Keys.name_of(ks.key_for("market")) == "Ctrl+M", "named Ctrl+M")
	# Esc, Enter and Shift alone cannot be given
	check(ks.set_key("pause", KEY_ESCAPE) == "" and ks.key_for("pause") == KEY_SPACE, "Esc cannot be a shortcut")
	check(not Keys.usable(KEY_SHIFT) and not Keys.usable(KEY_ENTER), "Shift alone and Enter cannot either")
	# an arrow key given to something else stops moving the map
	msg = ks.set_key("pause", KEY_UP)
	check(ks.action_of(key_event(KEY_UP)) == "pause" and not ks.held_keys("pan_up").has(KEY_UP) and ks.held_keys("pan_up").has(KEY_W), "Up given to pause; W still moves the map up (%s)" % msg)
	# one back to its default: whoever had that key gets the other one
	ks.reset_key("sites")
	check(ks.key_for("sites") == KEY_B and ks.key_for("copy") == KEY_Q, "sites back on B, copy back on Q")
	check(ks.saved.size() == 2, "only changed keys are saved (%s)" % [ks.saved])

	# 3. saved with the settings and read back
	st.save_file()
	var st2 := Settings.new()
	st2.load_file()
	var ks2 := Keys.new(st2)
	check(ks2.key_for("market") == KEY_MASK_CTRL | KEY_M and ks2.key_for("pause") == KEY_UP, "kept in the settings file")
	ks2.reset_all()
	check(ks2.saved.is_empty() and ks2.key_for("market") == KEY_M, "Default keys puts them all back")

	# 4. a settings file from an older build where two actions ended up on one key
	var st3 := Settings.new()
	st3.keys = {"sites": KEY_Q, "events": KEY_O, "pause": KEY_ESCAPE}
	var ks3 := Keys.new(st3)
	check(ks3.action_of(key_event(KEY_Q)) == "copy" and ks3.action_of(key_event(KEY_B)) == "sites", "a clash from an old file: the moved key is dropped")
	check(ks3.action_of(key_event(KEY_E)) == "events" and ks3.action_of(key_event(KEY_O)) == "problems" and ks3.action_of(key_event(KEY_SPACE)) == "pause", "and the others go back too")
	check(st3.keys.is_empty(), "nothing clashing is left (%s)" % [st3.keys])

	# 5. in a game: keys of game features, and moved keys working
	var main: Main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	main.settings.keys = {}
	main._start("keys", 2, 5, true)
	main.setup.visible = false
	main.paused = false
	await process_frame
	var fid := ""
	for a in main.keys.actions():
		if String(a[0]) == "f:statistics:%d" % KEY_F2:
			fid = String(a[0])
	check(fid != "", "the Statistics window's key is listed (%s)" % fid)
	var feat_win: Window = null
	for n in main.feature_ui.get("statistics", {}).get("nodes", []):
		if n is Window: feat_win = n
	if feat_win != null:
		feat_win.visible = false
		main.keys.set_key(fid, KEY_F11)
		press(main, KEY_F11)
		check(feat_win.visible, "F11 now opens Statistics")
		feat_win.visible = false
		press(main, KEY_F2)
		check(not feat_win.visible, "F2 no longer does")
	main.keys.set_key("events", KEY_X)
	var was: bool = main.log_ui.win != null and main.log_ui.win.visible
	press(main, KEY_X)
	var now: bool = main.log_ui.win != null and main.log_ui.win.visible
	check(was != now, "X shows or hides the event log")
	main.keys.set_key("pause", KEY_MASK_CTRL | KEY_P)
	var p0: bool = main.paused
	press(main, KEY_SPACE)
	check(main.paused == p0, "Space does not pause any more")
	press(main, KEY_MASK_CTRL | KEY_P)
	check(main.paused != p0, "Ctrl+P pauses")
	press(main, KEY_4)
	check(main.speed == 8.0, "4 still sets 8x")

	# 6. the Settings window: waiting for a key, swapping, Esc keeps it
	main._open_settings()
	main.settings_ui.keys_open = true
	main.settings_ui._fill_settings()
	main.key_wait = "diplomacy"
	var e := key_event(KEY_SHIFT)
	main._input(e)
	check(main.key_wait == "diplomacy", "Shift on its own: still waiting")
	main._input(key_event(KEY_T))
	check(main.key_for("diplomacy") == KEY_T and main.key_for("targets") == KEY_G, "T pressed for diplomacy: production targets moved to G")
	check(main.hint.visible and main.hint.text.contains("G"), "a hint says so: %s" % main.hint.text)
	main.key_wait = "diplomacy"
	main._input(key_event(KEY_ESCAPE))
	check(main.key_wait == "" and main.key_for("diplomacy") == KEY_T, "Esc keeps the key")
	main.key_wait = "diplomacy"
	main._input(key_event(KEY_ENTER))
	check(main.key_for("diplomacy") == KEY_T, "Enter is refused")
	var buttons := main.set_body.find_children("*", "Button", true, false).size()
	check(buttons > main.keys.actions().size(), "the window lists every key (%d buttons)" % buttons)
	var sc: ScrollContainer = main.settings_ui._scroller()
	if sc != null:
		for i in 3: await process_frame
		sc.scroll_vertical = 400
		var at := sc.scroll_vertical
		main.settings_ui._fill_settings()
		for i in 4: await process_frame
		check(sc.scroll_vertical == at, "the list stays where it was scrolled to (%d, %d)" % [at, sc.scroll_vertical])
	main.set_panel.visible = false

	# put the player's settings back
	if kept.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(kept)
		f.close()
	print("KEYS TEST: " + ("PASS" if ok else "FAIL"))
	quit()
