extends SceneTree
## The path chosen on entering each age (age_bonuses in data/techs.json): rivals pick at once by their
## manner, you pick in a window; the pick's effects count and survive saving:
## godot --headless --script res://tools/age_bonus_test.gd
func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("agebonus", 3, 5, true)
	for i in 5: sim.tick(Sim.TICK)
	var me := sim.human()
	print("waiting at the start (Roman age): ", sim.missing_age_bonus(me))
	if sim.missing_age_bonus(me) != -1: ok = false; print("FAIL: nothing to pick in the Roman age")
	sim.complete_tech(me, "new_kingdoms")
	var tax0 := sim.mod(me, "tax")
	print("after The new kingdoms: age %d, waiting for age %d" % [me.age, sim.missing_age_bonus(me)])
	if me.age != 1 or sim.missing_age_bonus(me) != 1: ok = false; print("FAIL: the Early Medieval path should wait")
	sim.choose_age_bonus(me, 1, "royal_estates")
	print("royal estates: tax %+.2f -> %+.2f, waiting %d" % [tax0, sim.mod(me, "tax"), sim.missing_age_bonus(me)])
	if absf(sim.mod(me, "tax") - tax0 - 0.10) > 0.001 or sim.missing_age_bonus(me) != -1: ok = false; print("FAIL: the pick's tax should count")
	sim.choose_age_bonus(me, 2, "merchant_guilds")
	if me.age_bonus.has("2"): ok = false; print("FAIL: no pick for an age not reached")
	# a rival entering an age picks by its manner
	for p in sim.players:
		if p.ai:
			sim.complete_tech(p, "new_kingdoms")
			print("%s (%s) picked %s" % [p.name, p.pers, p.age_bonus.get("1", "-")])
			var want: String = {"warlord": "war_bands", "builder": "royal_estates", "balanced": "monastic_schools"}[p.pers]
			if p.age_bonus.get("1", "") != want: ok = false; print("FAIL: rival pick by manner")
	var d := sim.to_save()
	var sim2 := Sim.new()
	print("load: '%s'" % sim2.from_save(d))
	if String(sim2.human().age_bonus.get("1", "")) != "royal_estates" or absf(sim2.mod(sim2.human(), "tax") - sim.mod(me, "tax")) > 0.001: ok = false; print("FAIL: the pick should survive a save")
	print("age bonus test: ", "ok" if ok else "FAILED")
	sim.dispose(); sim2.dispose()
	quit()
