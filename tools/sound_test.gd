extends SceneTree
## Sound: every effect, loop and piece of music loads; the mixer has its buses; the music follows the
## game (the new-game screen, peace, war while your land is attacked, the end); sounds of the world
## play where they are on screen and not when far off it; the ambience follows what is on screen; news
## in the log picks its sound; muting works; the settings have the four volumes.
##   xvfb-run -a godot --rendering-driver opengl3 --script res://tools/sound_test.gd

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	var ok := true
	var snd: Sound = main.sound
	# everything loads
	var missing := []
	for id in Sound.SINGLES + Sound.LOOPS + Sound.PEACE + [Sound.WAR, "cue_age", "cue_victory", "cue_defeat"]:
		if not snd._streams.has(id): missing.append(id)
	for fam in Sound.VARIANT_FAMILIES:
		if not (snd._streams.get(fam) is Array) or (snd._streams[fam] as Array).size() < 2: missing.append(fam + "_*")
	var music_len := 0.0
	for id in Sound.PEACE + [Sound.WAR]:
		if snd._streams.has(id): music_len += (snd._streams[id] as AudioStream).get_length()
	print("sounds loaded: %d ids, missing %s; music %d s" % [snd._streams.size(), str(missing), int(music_len)])
	if not missing.is_empty() or music_len < 400: ok = false; print("FAIL: sounds missing")
	for b in ["Music", "Effects", "Ambience"]:
		if AudioServer.get_bus_index(b) < 0: ok = false; print("FAIL: no bus ", b)
	# the new-game screen: menu music
	main.setup.visible = true
	for i in 10: await process_frame
	snd._gap = 0.0
	for i in 5: await process_frame
	print("on the new-game screen: mood %s, playing %s" % [snd._mood, str(snd._mus.map(func(p): return p.playing))])
	if snd._mood != "menu" or not (snd._mus[0].playing or snd._mus[1].playing): ok = false; print("FAIL: menu music")
	# a game: peace
	main._start("soundtest", 2, 5, true)
	main.setup.visible = false
	main.paused = false
	for i in 10: await process_frame
	print("in the game: mood %s" % snd._mood)
	if snd._mood != "peace": ok = false; print("FAIL: peace music")
	# an attack on you: war
	var sim: Sim = main.sim
	var foe: Sim.Player = sim.players[1]
	var a := Sim.Attack.new()
	a.p = foe.id; a.tgt = sim.human().hq.id; a.n = 3; a.from = Vector2(foe.hq.x, foe.hq.y); a.to = Vector2(sim.human().hq.x, sim.human().hq.y)
	sim.attacks.append(a)
	for i in 5: await process_frame
	var war_playing: bool = snd._mus[snd._mus_cur].playing and snd._mus[snd._mus_cur].stream == snd._streams[Sound.WAR]
	print("attacked: mood %s, war theme playing %s" % [snd._mood, war_playing])
	if snd._mood != "war" or not war_playing: ok = false; print("FAIL: war music")
	sim.attacks.erase(a)
	snd._war_quiet = 25.0
	for i in 5: await process_frame
	print("after the fighting: mood %s" % snd._mood)
	if snd._mood != "peace": ok = false; print("FAIL: back to peace")
	# sounds of the world: on screen they play (panned), far off they don't
	var hq := sim.human().hq
	main.view.center_on(Vector2(hq.x, hq.y)); main.view.zoom = 30.0
	await process_frame
	# the game goes on meanwhile and may be playing sounds of its own: only the players these two calls
	# start count (the test was flaky before)
	for p in snd._world:
		p.stop()
	var was := snd._world.filter(func(p): return p.playing)
	snd._last.clear()
	snd.play_at("chop", Vector2(hq.x + 3, hq.y))
	var started := snd._world.filter(func(p): return p.playing and not was.has(p))
	var on := started.size()
	snd._last.clear()
	snd.play_at("chop", Vector2(hq.x + 200, hq.y))
	var off := snd._world.filter(func(p): return p.playing and not was.has(p)).size() - on
	var p0: AudioStreamPlayer2D = started[0] if not started.is_empty() else snd._world[0]
	var right: bool = p0.global_position.x > main.view.get_global_rect().get_center().x
	print("a sound on screen plays: %s (to the right: %s), far off it: %s" % [on == 1, right, off == 1])
	if on != 1 or off != 0 or not right: ok = false; print("FAIL: sounds where they happen")
	# every effect plays without errors
	for id in Sound.SINGLES + Sound.VARIANT_FAMILIES:
		snd._last.clear()
		snd.play(id, 0.1)
	# the ambience follows the screen: a coast shows the shore loop
	var shore := Vector2i(-1, -1)
	for y in range(4, sim.h - 4, 2):
		for x in range(4, sim.w - 4, 2):
			if shore.x < 0 and sim.ter[sim.idx(x, y)] == Sim.WATER and sim.ter[sim.idx(x + 3, y)] != Sim.WATER:
				shore = Vector2i(x, y)
	main.view.center_on(Vector2(shore)); main.view.zoom = 24.0
	await process_frame
	var w := snd._ambience_targets()
	print("over a coast: %s" % str(w))
	if float(w.get("amb_shore", 0.0)) <= 0.1: ok = false; print("FAIL: no shore sound by the sea")
	# news in the log picks its sound
	for q in snd._ui: q.stop()
	snd._last.clear()
	snd.on_log("Woodcutter is finished.", Color.WHITE)
	snd.on_log("Aldric attacks your Tower with 3 soldiers!", Color.WHITE)
	snd.on_log("Building a farm.", Color.WHITE)
	var heard := []
	for q in snd._ui:
		if q.playing: heard.append(String(q.stream.resource_path.get_file().get_basename()))
	heard.sort()
	print("playing after three log lines: ", heard)
	if heard != ["alert", "done", "place"]: ok = false; print("FAIL: news sounds")
	# muted: nothing plays
	for q in snd._ui: q.stop()
	main.settings.sound_on = false
	snd._last.clear()
	snd.play("click")
	var muted: bool = snd._ui.filter(func(q): return q.playing).is_empty()
	main.settings.sound_on = true
	print("muted: click refused %s" % muted)
	if not muted: ok = false; print("FAIL: muting")
	# the settings show the four volumes
	main._open_settings()
	await process_frame
	var labels := []
	for c in main.set_body.find_children("*", "Label", true, false):
		if c.text in ["Volume", "Music", "Effects", "Ambience"]: labels.append(c.text)
	print("settings sound rows: ", labels)
	if labels.size() < 4: ok = false; print("FAIL: volume settings")
	main.set_panel.visible = false
	# the end: a cue, the music stops
	sim.over = true
	sim.ended.emit(true)
	for i in 5: await process_frame
	print("victory: mood %s, cue playing %s" % [snd._mood, snd._cue.playing])
	if snd._mood != "end" or not snd._cue.playing: ok = false; print("FAIL: victory cue")
	print("SOUND TEST: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
