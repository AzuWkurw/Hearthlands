extends SceneTree
## Checks the sound system: every sound loads, effects play, ambience fades in, and news in the log
## picks the right sound. Run: godot --headless --script res://tools/sound_test.gd
func _init() -> void:
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	var snd: Sound = main.sound
	print("sounds loaded: %d of %d" % [snd._streams.size(), Sound.EFFECTS.size() + Sound.LOOPS.size()])
	main._start("sound", 2, 5, true)
	main.setup.visible = false
	main.paused = false
	main.view.zoom = 30.0
	for i in 120: await process_frame
	var lv := {}
	for k in snd._amb_level: lv[k] = snd._amb_level[k]
	print("ambience after 2 s: ", lv)
	var heard := []
	snd.on_log("Woodcutter is finished.", Color.WHITE)
	snd.on_log("Aldric attacks your Tower with 3 soldiers!", Color.WHITE)
	snd.on_log("Building a farm.", Color.WHITE)
	for p in snd._pool:
		if p.playing: heard.append(String(p.stream.resource_path.get_file()))
	print("playing after three log lines: ", heard)
	main.settings.sound_on = false
	snd.play("click")
	print("muted: click refused = %s" % str(snd._pool.filter(func(p): return p.playing and String(p.stream.resource_path).ends_with("click.wav")).is_empty()))
	main.settings.sound_on = true
	main._open_settings()
	await process_frame
	var labels := []
	for c in main.set_body.find_children("*", "Label", true, false):
		if c.text in ["Sound", "Volume", "Effects", "Ambience"]: labels.append(c.text)
	print("settings sound rows: ", labels)
	quit()
