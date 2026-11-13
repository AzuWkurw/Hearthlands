extends SceneTree
## Prints a hash of the maps a few seeds make (to check map generation has not changed):
## godot --headless --script res://tools/map_hash.gd
func _init() -> void:
	for sd in ["hearth", "valley", "islands42", "abc"]:
		var g := WorldGen.generate(sd, 3, 0)
		print("%s %d %d" % [sd, hash(g.ter) ^ hash(g.deco) ^ hash(g.ore), hash(str(g.starts))])
	quit()
