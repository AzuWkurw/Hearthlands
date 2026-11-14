extends SceneTree
## Opens the newer windows and tools one after another on a save and plays a little between, to catch
## script errors in the interface. xvfb-run godot --rendering-driver opengl3 --script res://tools/ui_smoke.gd -- save=user_save
func _frames(n: int) -> void:
	for i in n: await process_frame


func _init() -> void:
	var save := "user_save"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("save="): save = a.substr(5)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main._load_game(save)
	main.setup.visible = false
	main.paused = false
	var sim: Sim = main.sim
	var me := sim.human()
	await _frames(10)
	print("step market"); main.market_ui.toggle(); await _frames(5); main.market_ui.only_mine.button_pressed = false; main.market_ui.refresh(); await _frames(5); main.market_ui.win.visible = false
	print("step bottlenecks"); main.neck_ui.toggle(); await _frames(5); main.neck_ui.win.visible = false
	print("step chain"); main.view.chain_res = "bread"; await _frames(10); main.view.chain_res = "coal"; await _frames(10); main.view.chain_res = ""
	print("step transport"); main.carry_prio_ui.toggle(); await _frames(5)
	main.carry_prio_ui.presets.select(1); main.carry_prio_ui._use_preset(); await _frames(5)
	main.carry_prio_ui.move("bread", "food"); await _frames(3); main.carry_prio_ui.win.visible = false
	print("step workers"); main.work_prio_ui.toggle(); await _frames(5); main.work_prio_ui.win.visible = false
	print("step info")
	for b in sim.realm_blds(me):
		if b.state == "ready" and b.ty in ["bakery", "harbour", "market", "school", "field_depot", "naval_yard"]:
			main.view.sel_id = b.id
			main._refresh_sel()
			await _frames(2)
	main.view.sel_id = 0
	print("step attack window")
	for q in sim.players:
		if q.id != 1 and q.alive:
			Diplomacy.declare_war(sim, 1, q.id)
			main.attack_ui.open(q.hq)
			await _frames(4)
			main.attack_ui.close()
			break
	print("step guide"); main.sea_guide_ui.open(); await _frames(4); main.sea_guide_ui.win.visible = false
	print("step notices"); sim.emit_log("Your fleet was sunk at sea.", Color("e08a6a"), Vector2i(me.hq.x, me.hq.y)); await _frames(4)
	(main.notices_ui.box.get_child(0).get_child(0) as Button).emit_signal("pressed"); await _frames(4)
	print("step scale"); main.settings.step_scale(1); main.settings.apply_scale(main.get_window()); await _frames(4); main.settings.step_scale(-1); main.settings.apply_scale(main.get_window())
	print("step choice")
	var ev = sim.get_feature("events")
	if ev != null:
		for k in ["great_fire", "plague", "revolt"]:
			ev.pending[me.id] = [k, sim.time]
			main.choice_ui.check()
			await _frames(3)
			ev.answer(me, 0)
			main.choice_ui.check()
			await _frames(3)
	print("step play")
	for i in 600:
		sim.tick(Sim.TICK)
		if i % 60 == 0:
			main._refresh_all()
			await _frames(1)
	print("UI SMOKE DONE")
	quit()
