extends SceneTree
## Build 56: rolling autosaves, interface size, notices worth a click.
## godot --headless --script res://tools/qol_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	# 1. rolling autosaves: autosave -> autosave 2 -> autosave 3 (the user's own autosaves are put back)
	var dir := Main.SAVE_DIR + "/"
	DirAccess.make_dir_recursive_absolute(Main.SAVE_DIR)
	var names := ["autosave", "autosave 2", "autosave 3"]
	var kept := {}
	for n in names:
		if FileAccess.file_exists(dir + n + ".save"):
			kept[n] = FileAccess.get_file_as_bytes(dir + n + ".save")
	var sv := UiSaves.new(null)
	for k in 3:
		sv._roll_autosaves()
		var f := FileAccess.open(dir + "autosave.save", FileAccess.WRITE)
		f.store_string("game %d" % k)
		f.close()
	check(FileAccess.get_file_as_string(dir + "autosave.save") == "game 2" and FileAccess.get_file_as_string(dir + "autosave 2.save") == "game 1" and FileAccess.get_file_as_string(dir + "autosave 3.save") == "game 0", "three autosaves kept, newest first")
	sv._roll_autosaves()
	check(FileAccess.get_file_as_string(dir + "autosave 3.save") == "game 1", "the oldest drops out")
	for n in names:
		DirAccess.remove_absolute(dir + n + ".save")
		if kept.has(n):
			var f := FileAccess.open(dir + n + ".save", FileAccess.WRITE)
			f.store_buffer(kept[n])
			f.close()
	# 2. interface size
	var st := Settings.new()
	st.ui_scale = 1.0
	st.step_scale(1)
	check(st.ui_scale == 1.15, "Ctrl and +: a size bigger (115%)")
	st.ui_scale = 2.0
	st.step_scale(1)
	check(st.ui_scale == 2.0, "no bigger than 200%")
	st.ui_scale = 0.0
	check(st.scale_now() >= 1.0 and st.scale_now() <= 2.0, "Auto picks a size for the screen (%d%%)" % roundi(st.scale_now() * 100))
	# 3. notices
	check(UiNotices.worth("Your fleet was sunk at sea.", Color("e08a6a")) and UiNotices.worth("Bandits came", Color("e0603a")), "bad news makes a notice")
	check(not UiNotices.worth("A peasant became an artisan.", Color("86ad5c")), "good everyday news does not")
	print("QOL TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
