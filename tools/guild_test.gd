extends SceneTree
## Build 62: guilds (workplaces of one trade close together, with the Guilds tech, work faster), the
## build queue (queued sites get their materials one after another, before other sites), and copying
## a building's settings to all of its kind. godot --headless --script res://tools/guild_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func spot(sim: Sim, ty: String, cx: int, cy: int) -> Vector2i:
	for r in range(1, 25):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and sim.can_place(ty, cx + dx, cy + dy, 1) == "":
					return Vector2i(cx + dx, cy + dy)
	return Vector2i(-1, -1)


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("guilds", 1, 5, false, 128, false, {"start_goods": 4.0})
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	for y in range(maxi(0, me.hq.y - 22), mini(sim.h, me.hq.y + 23)):
		for x in range(maxi(0, me.hq.x - 22), mini(sim.w, me.hq.x + 23)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	sim.net_dirty(1)
	# 1. guilds: three sawmills side by side
	var mills := []
	var near := Vector2i(me.hq.x + 6, me.hq.y)
	for k in 3:
		var at := spot(sim, "sawmill", near.x, near.y)
		if at.x >= 0:
			var b := sim.add_bld("sawmill", at.x, at.y, me, true)
			b.staffed = true
			mills.append(b)
			near = at
	for i in 12: sim.tick(Sim.TICK)
	for b in mills: b.staffed = true
	var m0: Sim.Bld = mills[0]
	var n: int = sim.people.guild_size(me, m0)
	check(n >= 3, "three sawmills together: %d in reach" % n)
	var r0 := sim.rate(me, m0)
	me.techs["guilds"] = true
	sim._type_bonus.clear()
	var r1 := sim.rate(me, m0)
	check(r1 > r0 and is_equal_approx(sim.people.guild_bonus(me, m0), SimPeople.GUILD_BONUS), "with Guilds they form a guild: work %.2f -> %.2f" % [r0, r1])
	m0.staffed = false
	var mid: Sim.Bld = mills[1]
	check(sim.people.guild_size(me, mid) == n - 1, "a workplace with nobody working does not count")
	m0.staffed = true
	# 2. the build queue
	var sites := []
	near = Vector2i(me.hq.x - 6, me.hq.y + 4)
	for k in 3:
		var at := spot(sim, "house", near.x, near.y)
		if at.x >= 0 and sim.place("house", at.x, at.y, me, 0, true) == "":
			sites.append(sim.bld_at(at.x, at.y))
			near = at
	check(sites.size() == 3, "three house sites")
	var a: Sim.Bld = sites[0]
	var b: Sim.Bld = sites[1]
	var c: Sim.Bld = sites[2]
	check(sim.queue_site(c, true) == 1 and sim.queue_site(b, true) == 2, "two sites queued: the third first, then the second")
	for i in int(3.0 / Sim.TICK): sim.tick(Sim.TICK)
	var got := func(s: Sim.Bld) -> int:
		var t := 0
		for k in s.coming: t += int(s.coming[k])
		for k in s.onsite: t += int(s.onsite[k])
		return t
	check(int(got.call(c)) > 0 and int(got.call(b)) == 0, "only the head of the queue gets materials (%d on its way, the next %d)" % [got.call(c), got.call(b)])
	var t_end := sim.time + 240.0
	while sim.time < t_end and c.state == "build":
		sim.tick(Sim.TICK)
	check(c.state == "ready" and c.queue_n == 0 and b.queue_n == 1, "the first is built and leaves the queue; the next moves up (#%d)" % b.queue_n)
	sim.queue_site(b, false)
	check(b.queue_n == 0 and sim.build_queue(1).is_empty(), "a site taken out of the queue")
	# 3. copy settings
	m0.prio = Sim.PRIO_HIGH
	m0.keep = 4
	var copied := UiInfo.copy_settings(sim, m0)
	var same := true
	for o in mills:
		same = same and o.keep == 4 and o.prio == Sim.PRIO_HIGH
	check(copied == mills.size() - 1 and same, "the sawmill's priority and inputs kept copied to the %d others" % copied)
	# 4. saved and loaded
	# (a site still being built: a new one if the first is up already)
	if a.state != "build":
		var at2 := spot(sim, "house", me.hq.x + 4, me.hq.y + 8)
		sim.place("house", at2.x, at2.y, me, 0, true)
		a = sim.bld_at(at2.x, at2.y)
	sim.queue_site(a, true)
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(s2.build_queue(1).size() == 1 and (s2.build_queue(1)[0] as Sim.Bld).id == a.id, "the queue is saved")
	print("GUILD TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
