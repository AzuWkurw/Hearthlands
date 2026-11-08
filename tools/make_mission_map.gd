extends SceneTree
## Makes data/map_iron_coast.json, the hand-made map of mission 3, the way the map editor would: a
## generated map with an iron ridge (two passes) between your start in the south and the rivals.
## godot --headless --script res://tools/make_mission_map.gd
func _init() -> void:
	GameData.ensure()
	var g := WorldGen.generate("iron coast", 2, 150)
	var w: int = g.w
	var h: int = g.h
	var starts: Array = g.starts.duplicate()
	starts.sort_custom(func(a, b): return a.y > b.y)   # the southernmost is yours
	var south: Vector2i = starts[0]
	var north_y: int = maxi(starts[1].y, starts[2].y)
	var ridge := (south.y + north_y) / 2
	var ter: PackedByteArray = g.ter
	var ore: PackedByteArray = g.ore
	var deco: PackedByteArray = g.deco
	var amt: PackedByteArray = g.amt
	for x in range(8, w - 8):
		# two passes through the ridge, a third and two thirds of the way across
		if absi(x - w / 3) < 3 or absi(x - 2 * w / 3) < 3:
			continue
		var wob := int(2.0 * sin(x * 0.21))
		for y in range(ridge - 3 + wob, ridge + 4 + wob):
			var i := y * w + x
			if ter[i] == WorldGen.WATER:
				continue
			ter[i] = WorldGen.MOUNT
			deco[i] = 0
			# iron in the ridge's heart, coal on its flanks
			ore[i] = 2 if absi(y - ridge - wob) <= 1 else (1 if (x / 5) % 2 == 0 else 0)
			amt[i] = 20 if ore[i] > 0 else 0
	var m := {"name": "Iron Coast", "w": w, "h": h, "seed": "iron coast", "starts": starts, "ter": ter, "deco": deco, "amt": amt, "ore": ore, "shade": g.shade}
	var err := WorldGen.save_map(m, ProjectSettings.globalize_path("res://data/map_iron_coast.json"))
	print("map saved: ", err == "", " ", w, "x", h, " ridge at y ", ridge, " starts ", starts)
	var back := WorldGen.load_map("res://data/map_iron_coast.json")
	print("reads back: ", not back.is_empty() and back.ter == ter)
	quit()
