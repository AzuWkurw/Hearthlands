extends SceneTree
## Build 63: sandbox goals (a chain of goals in endless games, gold for each), the hats of each age,
## the music for the later ages and the workers' voices. godot --headless --script res://tools/goals_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("goals", 1, 5, false, 128, false, {"features": Features.default_ids()})
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	check(me.goal_i == 0 and SandboxGoals.LIST.size() >= 20, "a new game starts at the first of %d goals" % SandboxGoals.LIST.size())
	# 1. the first goal reached: the next, and its gold
	me.peasant = 40
	var g0 := float(me.stock.get("gold", 0.0))
	for i in int(6.0 / Sim.TICK): sim.tick(Sim.TICK)
	check(me.goal_i >= 1, "30 people: the first goal is reached (now at goal %d)" % (me.goal_i + 1))
	check(float(me.stock.get("gold", 0.0)) >= g0 + 4.0, "and its gold is in the treasury")
	var said := false
	for l in sim.logs:
		if String(l[1]).begins_with("Goal reached"): said = true
	check(said, "the log says so")
	# 2. each kind of goal can be measured
	var bad := []
	for g in SandboxGoals.LIST:
		var gp := SandboxGoals.progress(sim, g)
		if gp.size() != 2 or int(gp[1]) < 1:
			bad.append(String(g.text))
		if String(g.get("kind", "")) == "build" and not GameData.bld.has(String(g.get("ty", ""))):
			bad.append(String(g.text))
	check(bad.is_empty(), "every goal can be measured %s" % str(bad))
	# 3. a mission game has its own goals instead
	var ms := Sim.new()
	ms.new_game("goals2", 1, 5, false, 128, false, {})
	ms.mission = {"name": "test", "goals": [{"kind": "pop", "n": 9999, "text": "x"}]}
	ms.human().peasant = 60
	for i in int(6.0 / Sim.TICK): ms.tick(Sim.TICK)
	check(ms.human().goal_i == 0, "no sandbox goals in a mission")
	# 4. saved and loaded
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(s2.human().goal_i == me.goal_i, "the goal reached is saved")
	# 5. hats, music and voices are there
	var hats := 0
	for k in 6:
		if ResourceLoader.exists("res://textures/unit_hat_e%d.png" % k): hats += 1
	check(hats == 6, "a hat for each age (%d)" % hats)
	check(ResourceLoader.exists("res://music/peace_court.ogg") and ResourceLoader.exists("res://music/peace_foundry.ogg"), "music for the later ages")
	check(ResourceLoader.exists("res://sounds/voice_low.ogg") or FileAccess.file_exists("res://sounds/voice_low.wav") or ResourceLoader.exists("res://sounds/voice_low.wav"), "the workers' voices")
	print("GOALS TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
