extends Feature
## Example mod: every few game minutes the harvest is bountiful, and farms, orchards and the like work
## 25% faster for a minute. Copy this file into the mods folder (Settings shows where), restart the game,
## and switch "Bountiful harvests" on in Settings.

var until := -1.0           # game time the good harvest ends


func _init() -> void:
	id = "bountiful_harvest"
	title = "Bountiful harvests"
	info = "Example mod: now and then farms work 25% faster for a minute."
	default_on = false


func on_second() -> void:
	# every 4 game minutes a new harvest starts
	if int(sim.time) % 240 == 0 and sim.time > until:
		until = sim.time + 60.0
		sim.emit_log("A bountiful harvest! Farms work faster for a minute.", Color("a0d070"))


func speed_bonus(_p: Sim.Player, b: Sim.Bld) -> float:
	if sim.time < until and GameData.trade(b.ty) == "farming":
		return 0.25
	return 0.0


func panel_lines(_p: Sim.Player) -> PackedStringArray:
	if sim.time < until:
		return PackedStringArray(["Harvest  [color=#a0d070]bountiful[/color] for %d more seconds" % int(until - sim.time)])
	return PackedStringArray()


func save_state() -> Dictionary:
	return {"until": until}


func load_state(d: Dictionary) -> void:
	until = float(d.get("until", -1.0))
