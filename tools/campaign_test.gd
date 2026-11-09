extends SceneTree
## The campaign: chapters open one after another, a won chapter is recorded and carries soldiers over.
## xvfb-run -a godot --rendering-driver opengl3 --script res://tools/campaign_test.gd -- out=/dir
func _init() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var keep := ""
	if FileAccess.file_exists(UiCampaign.PROGRESS):
		keep = FileAccess.get_file_as_string(UiCampaign.PROGRESS)
		DirAccess.remove_absolute(UiCampaign.PROGRESS)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	var cu: UiCampaign = main.campaign_ui
	var ok := true
	cu.show()
	print("chapters ", cu.chapters.size(), ", open: ", range(cu.chapters.size()).filter(func(k): return cu.is_open(k)))
	if cu.chapters.size() != 8 or cu.is_open(1): ok = false; print("FAIL: only chapter 1 should be open")
	if out != "":
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		cu.win.get_texture().get_image().save_png(out + "campaign.png")
	cu.start(0)
	print("playing: ", main.sim.mission.get("name"), " campaign ", main.sim.mission.get("campaign"))
	main.sim.time = 1500.0
	main._on_end(true)
	print("end text: ", main.end_text.text.replace("\n", " | "))
	print("chapter 2 open: ", cu.is_open(1), ", next button: ", main.end_next.visible)
	if not cu.is_open(1) or not main.end_next.visible: ok = false; print("FAIL: chapter 2 should open")
	var r0 := 0
	main.end_next.pressed.emit()
	var me: Sim.Player = main.sim.human()
	print("chapter 2: ", main.sim.mission.get("name"), ", soldiers waiting ", me.reserve, " (bonus ", main.sim.mission.get("bonus"), ")")
	if int((main.sim.mission.get("bonus", {}) as Dictionary).get("goods", {}).get("bread", 0)) != 20: ok = false; print("FAIL: chapter 1 carries bread over")
	if out != "":
		main.end_panel.visible = false
		for i in 5: await process_frame
		cu.show()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		cu.win.get_texture().get_image().save_png(out + "campaign2.png")
	DirAccess.remove_absolute(UiCampaign.PROGRESS)
	if keep != "":
		var f := FileAccess.open(UiCampaign.PROGRESS, FileAccess.WRITE); f.store_string(keep)
	print("campaign test: ", "ok" if ok else "FAILED")
	quit()
