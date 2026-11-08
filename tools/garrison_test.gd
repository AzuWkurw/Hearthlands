extends SceneTree
## Garrison settings: how many soldiers, which kinds, who stays home: godot --headless --script res://tools/garrison_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("gar", 1, 5, false, 0, true, {"features": []})
	var p := sim.human()
	var e := sim.players[1]
	var tw: Sim.Bld = null
	for y in range(p.hq.y - 8, p.hq.y + 9):
		for x in range(p.hq.x - 8, p.hq.x + 9):
			if tw == null and Vector2(x - p.hq.x, y - p.hq.y).length() > 5 and sim.can_place("tower", x, y, p.id) == "":
				tw = sim.add_bld("tower", x, y, p, true)
	p.reserve = 12
	p.rmix = [0, 2, 4, 6, 0, 0]
	sim.mil_fill(p)
	print("tower fills: %s; HQ: %s" % [Sim.mix_text(sim.gmix_of(tw)), Sim.mix_text(sim.rmix_of(p))])
	tw.want_n = 2
	sim.mil_fill(p)
	print("want 2: %s; HQ %d: %s" % [Sim.mix_text(sim.gmix_of(tw)), p.reserve, Sim.mix_text(sim.rmix_of(p))])
	tw.want_n = -1
	tw.want_kinds = [false, false, true, false, false, false]
	for i in 6: sim.mil_fill(p)
	print("men-at-arms only, full: %s; HQ %d: %s" % [Sim.mix_text(sim.gmix_of(tw)), p.reserve, Sim.mix_text(sim.rmix_of(p))])
	tw.want_kinds = [false, true, false, false, false, false]
	for i in 6: sim.mil_fill(p)
	print("spearmen only (2 at HQ): %s; HQ: %s" % [Sim.mix_text(sim.gmix_of(tw)), Sim.mix_text(sim.rmix_of(p))])
	# who stays home: an attack from a mixed tower
	tw.want_kinds = []
	tw.garrison = 4; tw.gmix = [0, 1, 1, 2, 0, 0]
	tw.keep_kind = 1
	var tgt: Sim.Bld = null
	for b in sim.realm_blds(e):
		if sim.is_mil(b): tgt = b
	Diplomacy.set_relation(sim, 1, 2, Diplomacy.WAR)
	var hut := sim.add_bld("hut", tw.x + 4, tw.y, e, true) if sim.can_place("hut", tw.x + 4, tw.y, e.id) == "" else null
	if hut == null:
		for y in range(tw.y - 6, tw.y + 7):
			for x in range(tw.x - 6, tw.x + 7):
				if hut == null and Vector2(x - tw.x, y - tw.y).length() > 3 and sim.ter[sim.idx(x, y)] == Sim.GRASS and sim.bmap[sim.idx(x, y)] == 0:
					hut = sim.add_bld("hut", x, y, e, true)
	print("hut: ", hut != null)
	var r := sim.launch_attack(tw, hut) if hut != null else "no hut"
	print("attack: '%s' marching %s, stays: %s" % [r, Sim.mix_text(sim.attacks[-1].amix) if not sim.attacks.is_empty() else "-", Sim.mix_text(sim.gmix_of(tw))])
	var d := sim.to_save()
	var s2 := Sim.new()
	s2.from_save(d)
	var t2: Sim.Bld = s2.by_id[tw.id]
	print("load: want %d kinds %s keep %d" % [t2.want_n, t2.want_kinds, t2.keep_kind])
	sim.dispose(); s2.dispose()
	quit()
