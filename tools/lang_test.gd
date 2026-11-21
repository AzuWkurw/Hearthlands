extends SceneTree
## Languages: English and Polish are offered; in Polish the interface, text built from templates
## (the event log, the building info), names in lower case, counts with their Polish forms and text of
## several lines with markup are all translated; switching back gives English again; the simulation
## keeps writing English to the log whatever the language; a whole played minute of log, info box and
## side panel translates without errors, and quickly.
##   godot --headless --script res://tools/lang_test.gd

func _init() -> void:
	var ok := true
	GameData.ensure()
	I18n.setup("en")
	var codes := I18n.languages().map(func(l): return l[0])
	print("languages: ", I18n.languages())
	if codes != ["en", "pl"]: ok = false; print("FAIL: expected English and Polish")
	I18n.set_language("pl")
	var cases := [
		["Settings", "Ustawienia"],
		["Sawmill is finished.", "Gotowe: Tartak."],
		["Sawmill is finished. (near Oakford)", "Gotowe: Tartak. (koło: Oakford)"],
		["Uses: 2 planks, 5 stone\n", "Zużywa: 2 deski, 5 kamieni\n"],
		["12 planks", "12 desek"],
		["A trade cart from Aldric brought 22 planks.", "Wóz handlowy z królestwa Aldric przywiózł: 22 deski."],
		["[color=#ddd][color=#777]01:05[/color] A peasant starved.[/color]", "[color=#ddd][color=#777]01:05[/color] Chłop umarł z głodu.[/color]"],
		["Fire: a fire broke out in the sawmill!", "Pożar: wybuchł pożar, płonie: tartak!"],
		["Rival strength: Hard (7)", "Siła rywali: Trudny (7)"],
		["Your realm enters the Roman age.", "Twoje królestwo wkracza w nową epokę: Starożytny Rzym."], ["Style: Bronze", "Styl: Brąz"],
		["Workers: 3", "Pracownicy: 3"],
	]
	for c in cases:
		var got := String(TranslationServer.translate(String(c[0])))
		if got != String(c[1]):
			ok = false
			print("FAIL: %s\n   got  %s\n   want %s" % [c[0], got, c[1]])
	# a template looked up as a key still formats in the code
	var f := String(TranslationServer.translate("Rival realms: %d")) % 3
	if f != "Wrogie królestwa: 3": ok = false; print("FAIL: tr then format gave ", f)
	# the game itself stays English: a minute of play writes English to the log
	var sim := Sim.new()
	sim.new_game("lang test", 2, 5, true, 96, false, {})
	for i in 3000: sim.tick(0.1)
	var t0 := Time.get_ticks_usec()
	var shown := 0
	var still_en := 0
	for l in sim.logs:
		var s := String(l[1])
		var pl := String(TranslationServer.translate(s))
		shown += 1
		if pl == s: still_en += 1; print("   untranslated: ", s)
	for b in sim.blds:
		if b.p == 1:
			TranslationServer.translate(String(b.def.name) + " " + sim.status(b))
	var us := Time.get_ticks_usec() - t0
	print("log lines %d, %d left in English, %d us" % [shown, still_en, us])
	if sim.logs.is_empty() or not String(sim.logs[0][1]).begins_with("The realm is founded"):
		ok = false; print("FAIL: the log should be written in English")
	if still_en > shown / 4: ok = false; print("FAIL: too much of the log untranslated")
	I18n.set_language("en")
	if String(TranslationServer.translate("Settings")) != "Settings": ok = false; print("FAIL: English again")
	print("LANG TEST: PASS" if ok else "LANG TEST: FAIL")
	I18n.unload()
	quit()
