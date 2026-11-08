extends SceneTree
## Tests the build 11 rules: difficulty options, tools for new workers, the toolsmith's choice and
## production targets.
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("rules", 2, 5, false, 0, true, {"start_goods": 4.0, "endless_ore": true, "research": 4.0, "peace_min": 30})
	var p: Sim.Player = sim.players[0]
	print("rich start: planks %d axes %d pickaxes %d; techs in data: %d" % [p.stock.planks, p.stock.axes, p.stock.pickaxes, GameData.techs.size()])
	# endless ore: a vein never shrinks
	var vi := -1
	for i in sim.w * sim.h:
		if sim.ore[i] == 2 and sim.vein_left(i) > 0: vi = i; break
	var before := sim.vein_left(vi)
	for n in 10: sim.take_ore(vi, 2)
	print("endless ore: vein %d -> %d after 10 digs" % [before, sim.vein_left(vi)])
	# research speed x4
	var rp0 := p.rp
	sim._research_tick(p)
	print("research per second with no buildings: %.2f (x4 of 0.15)" % (p.rp - rp0))
	# tools: a woodcutter with no axes and no idle woodsman cannot take a worker
	for t in GameData.tool_ids: p.stock[t] = 0.0
	sim.place("woodcutter", p.hq.x + 3, p.hq.y + 1, p)
	var wc: Sim.Bld = null
	for b in sim.blds:
		if b.p == 1 and b.ty == "woodcutter": wc = b
	if wc == null:
		for dx in range(-6, 7):
			for dy in range(-6, 7):
				if wc == null and sim.place("woodcutter", p.hq.x + dx, p.hq.y + dy, p) == "":
					for b in sim.blds:
						if b.p == 1 and b.ty == "woodcutter": wc = b
	wc.state = "ready"; sim._after_building_change(wc)
	p.peasant += 5
	sim.staffing(p)
	for i in 20: sim.tick(0.1)
	print("no axes: staffed=%s waiting for '%s' msg='%s' tool_wait=%s" % [wc.staffed, wc.need_tool, wc.msg, p.tool_wait])
	print("toolsmith would make: ", sim.wanted_tool(p))
	p.stock.axes = 1.0
	sim.staffing(p)
	print("one axe: staffed=%s axes left %d" % [wc.staffed, p.stock.axes])
	# a specialist returning brings his own tool
	wc.wxp = 30.0
	sim._release_worker(p, wc)
	wc.staffed = false
	sim.staffing(p)
	print("specialist rehired: staffed=%s level %d axes left %d" % [wc.staffed, Sim.level(wc.wxp, Sim.WORKER_XP), p.stock.axes])
	# production targets: a sawmill stops at its target
	p.stock.planks = 12.0; p.stock.wood = 20.0
	p.targets["planks"] = 10
	var saw := Sim.Bld.new(); saw.ty = "sawmill"; saw.def = GameData.bld.sawmill; saw.p = 1; saw.x = wc.x; saw.y = wc.y
	print("sawmill with target 10 and 12 planks: ", sim.start_check(saw, p))
	p.targets["planks"] = 50
	print("target 50: '%s' (empty or a road message means it would work)" % sim.start_check(saw, p))
	quit()
