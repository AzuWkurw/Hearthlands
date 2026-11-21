extends SceneTree
## Final scores, the high-score lists and the map of the day (score.gd): the parts add up, harder
## settings score more, a faster win scores more, the lists keep the best first and at most KEEP, and
## the map of the day is the same for the same date: godot --headless --script res://tools/score_test.gd
const PATH := "user://score_test.json"


func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("scores", 3, 5, true)
	for i in 3000: sim.tick(Sim.TICK)   # 5 minutes
	var s := Score.compute(sim, false)
	print("score after 5 minutes, lost: ", s)
	if int(s.total) <= 0: ok = false; print("FAIL: a realm that grew has a score")
	if not is_equal_approx(float(s.mult), 1.0): ok = false; print("FAIL: Normal with 3 rivals of strength 5 is x1.0, got ", s.mult)
	if int(s.total) != int(s.land) + int(s.people) + int(s.wonders) + int(s.victory): ok = false; print("FAIL: the parts add up")
	if int(s.victory) != 0: ok = false; print("FAIL: no victory points for a loss")
	if not bool(s.ranked): ok = false; print("FAIL: a normal game is ranked")
	# a win, and the speed of it
	var w := Score.compute(sim, true)
	if int(w.victory) != Score.WIN_BONUS + Score.SPEED_MAX: ok = false; print("FAIL: a 5-minute win gets the whole speed bonus, got ", w.victory)
	sim.time = 135.0 * 60.0
	var w2 := Score.compute(sim, true)
	print("victory points at 5 and 135 minutes: ", w.victory, " ", w2.victory)
	if int(w2.victory) >= int(w.victory) or int(w2.victory) <= Score.WIN_BONUS: ok = false; print("FAIL: a slower win scores less, but more than a bare win")
	sim.time = 600.0 * 60.0
	if int(Score.compute(sim, true).victory) != Score.WIN_BONUS: ok = false; print("FAIL: a very slow win gets only the bonus")
	sim.time = 300.0
	# a wonder raised counts
	var wb := sim.add_bld("great_hall", 2, 2, sim.human(), false, 0)
	sim.production._finish_site(wb, sim.human())
	var s3 := Score.compute(sim, false)
	if int(s3.won_n) < 1 or int(s3.wonders) < Score.PER_WONDER: ok = false; print("FAIL: the wonder counts ", s3)
	# difficulty
	var base := Score.difficulty(sim)
	sim.strength = 9
	var hard := Score.difficulty(sim)
	sim.strength = 5
	sim.opts["creative"] = true
	var creative := Score.difficulty(sim)
	sim.opts["creative"] = false
	sim.opts["peace_min"] = 60
	sim.opts["start_goods"] = 4.0
	var easy := Score.difficulty(sim)
	sim.opts["peace_min"] = 0
	sim.opts["start_goods"] = 0.5
	var scarce := Score.difficulty(sim)
	sim.opts["start_goods"] = 1.0
	print("difficulty: normal %.2f strength 9 %.2f creative %.2f easy %.2f scarce %.2f" % [base, hard, creative, easy, scarce])
	if not (hard > base and creative < 0.2 and easy < base and scarce > base): ok = false; print("FAIL: difficulty order")
	# the high-score lists
	if FileAccess.file_exists(PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var e1 := Score.entry(sim, s, "2026-11-21")
	if Score.record("scores", e1, PATH) != 1: ok = false; print("FAIL: the first score is first")
	var places := []
	for n in [500, 50000, 10, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 1]:
		var e := e1.duplicate()
		e.score = n
		places.append(Score.record("scores", e, PATH))
	var list := Score.best("scores", PATH)
	print("places: ", places, " list: ", list.map(func(x): return x.score))
	if list.size() != Score.KEEP: ok = false; print("FAIL: at most KEEP scores kept")
	if int(list[0].score) != 50000 or places[1] != 1: ok = false; print("FAIL: the best is first")
	for i in list.size() - 1:
		if int(list[i].score) < int(list[i + 1].score): ok = false; print("FAIL: best first")
	if places[-1] != 0: ok = false; print("FAIL: a score below the list does not make it")
	if Score.record("other seed", e1, PATH) != 1 or Score.best("scores", PATH).size() != Score.KEEP: ok = false; print("FAIL: lists are kept per map")
	print(Score.list_text(list, 1))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	# missions have their own list
	sim.mission = {"id": "first_harvest", "name": "1. The First Harvest"}
	if Score.key(sim) != "mission:first_harvest": ok = false; print("FAIL: mission key ", Score.key(sim))
	sim.mission = {}
	if Score.key(sim) != "scores": ok = false; print("FAIL: seed key")
	# the map of the day
	var d1 := Score.daily_setup("2026-11-21")
	var d2 := Score.daily_setup("2026-11-21")
	var d3 := Score.daily_setup("2026-11-22")
	print("map of the day: ", d1, " ", d3)
	if d1 != d2 or String(d1.seed) != "day 2026-11-21" or String(d3.seed) == String(d1.seed): ok = false; print("FAIL: the map of the day follows the date")
	if not Score.is_daily(String(d1.seed)) or Score.is_daily("scores"): ok = false; print("FAIL: is_daily")
	if not Score.DAILY_FOES.has(int(d1.foes)): ok = false; print("FAIL: daily rivals")
	var a := Sim.new()
	var b := Sim.new()
	a.new_game(String(d1.seed), int(d1.foes), int(d1.strength), true)
	b.new_game(String(d1.seed), int(d1.foes), int(d1.strength), true)
	if a.ter != b.ter or a.human().hq.x != b.human().hq.x: ok = false; print("FAIL: the same day gives the same map")
	# text
	if Score.group(1234567) != "1 234 567" or Score.group(12) != "12": ok = false; print("FAIL: group ", Score.group(1234567))
	var story := Chronicle.new().story(sim, true)
	if not story.contains("Final score:"): ok = false; print("FAIL: the chronicle shows the score")
	print("\n".join(Score.lines(w)))
	# a spectator game has no score
	var sp := Sim.new()
	sp.new_game("watch", 2, 5, true, 0, true, {"spectate": true})
	if bool(Score.compute(sp, true).ranked): ok = false; print("FAIL: a spectator game is not ranked")
	if Chronicle.new().story(sp, true).contains("Final score:"): ok = false; print("FAIL: no score in a spectator chronicle")
	for x in [sim, a, b, sp]: x.dispose()
	print("SCORE TEST: ", "PASS" if ok else "FAIL")
	quit()
