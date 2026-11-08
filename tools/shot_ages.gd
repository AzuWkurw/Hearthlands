extends SceneTree
## Screenshots of building looks from different ages, renovation and soldier kinds.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_ages.gd -- out=/dir
var out := "user://"
func _snap(name: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("saved ", name)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	main._start("ages", 3, 5, true)
	main.setup.visible = false
	main.log_ui.set_open(false)
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	# the realm moves through the ages as it grows, so its town mixes the styles
	var stages := [[180.0, 1], [330.0, 2], [450.0, 3], [560.0, 4], [640.0, 5]]
	for st in stages:
		while sim.time < float(st[0]): sim.tick(Sim.TICK)
		me.age = int(st[1])
	while sim.time < 700.0: sim.tick(Sim.TICK)
	me.ai = false
	# a few renovations under way
	var k := 0
	for b in sim.realm_blds(me):
		if k < 3 and sim.can_renovate(b) == "" and Vector2(b.x - me.hq.x, b.y - me.hq.y).length() < 6:
			sim.renovate(b); k += 1
	me.stock.planks += 20; me.stock.stone += 20
	for i in 120: sim.tick(Sim.TICK)
	main.view.center_on(Vector2(me.hq.x + 0.5, me.hq.y + 1.5))
	main.view.zoom = 40.0
	main._refresh_all()
	await _snap("ages_town")
	main.view.zoom = 26.0
	await _snap("ages_town_wide")
	quit()
