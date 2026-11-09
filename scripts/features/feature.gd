class_name Feature
extends RefCounted
## Base class for optional game systems ("features"): production statistics, seasons, diseases and so on.
## A feature is a script that extends Feature and overrides only the hooks it needs. The simulation calls
## the hooks of every switched-on feature, and a feature changes the game only through them, so each one
## can be switched on or off in Settings without touching the rest of the game.
## To write your own, put a .gd file that extends Feature in the mods folder (Settings shows where).
## See mods_examples/ in the project for a small example.

var id := ""                 # unique name, used in saved games and in settings
var title := ""              # name shown in Settings
var info := ""               # one line shown under the name in Settings
var default_on := true       # whether new players have it switched on
var needs: Array = []        # ids of features that must be switched on too (shown in Settings)
var sim: Sim                 # the running game; set before on_start is called


## The game starts: loaded is true for a game loaded from a save (load_state has already run).
func on_start(_loaded: bool) -> void:
	pass


## Called once every game second, after the economy has run.
func on_second() -> void:
	pass


## Extra work speed for building b of realm p: 0.1 means 10% faster, -0.2 means 20% slower.
func speed_bonus(_p: Sim.Player, _b: Sim.Bld) -> float:
	return 0.0


## How fast realm p's carriers walk compared with normal (1.0); snow on the roads, say.
func carry_factor(_p: Sim.Player) -> float:
	return 1.0


## How much food realm p eats compared with normal (1.0).
func food_factor(_p: Sim.Player) -> float:
	return 1.0


## A building of realm p made n of res.
func on_made(_p: Sim.Player, _res: String, _n: float) -> void:
	pass


## Realm p used up n of res (as an input, as food, for needs, for building or for a new worker's tool).
func on_used(_p: Sim.Player, _res: String, _n: float) -> void:
	pass


## Building b of realm p finished a work cycle (after its goods were handed over).
func on_cycle(_p: Sim.Player, _b: Sim.Bld) -> void:
	pass


## Building b of realm p made n of res (called with the building, after on_made).
func on_made_at(_b: Sim.Bld, _p: Sim.Player, _res: String, _n: float) -> void:
	pass


## Building b of realm p just took on a worker. took_tool is the tool he took from the stores, or "".
func on_hire(_p: Sim.Player, _b: Sim.Bld, _took_tool: String) -> void:
	pass


## A reason building b cannot start work right now ("" = it can). Shown as the building's status.
func work_block(_p: Sim.Player, _b: Sim.Bld) -> String:
	return ""


## How fast construction site b of realm p goes up compared with normal (1.0).
func build_factor(_p: Sim.Player, _b: Sim.Bld) -> float:
	return 1.0


## Extra steps for a rival realm's building plan: [[building id, how many it wants], ...].
## have(ty) tells how many of a building the realm has. They are tried after the basic economy.
func ai_steps(_p: Sim.Player, _have: Callable) -> Array:
	return []


## Extra lines for the info panel of a selected building.
func building_lines(_b: Sim.Bld) -> PackedStringArray:
	return PackedStringArray()


## Extra lines for the info shown when a map tile is clicked (tile index i).
func tile_lines(_i: int) -> PackedStringArray:
	return PackedStringArray()


## A few words for the top bar (the season and weather, say), or "".
func top_text(_p: Sim.Player) -> String:
	return ""


## Called whenever the interface refreshes (a few times a second).
func refresh_ui(_main: Main) -> void:
	pass


## Draws on the map under the buildings. The transform is in tiles (1 unit = 1 tile); rect is the
## part of the map on screen, in tiles.
func draw_map(_view: CanvasItem, _rect: Rect2i) -> void:
	pass


## Draws on the map over the buildings and people (in tiles), before the selection marks.
func draw_top(_view: CanvasItem, _rect: Rect2i) -> void:
	pass


## Map tools this feature adds to a tab of the Build panel: [[id starting with "@", name, icon, tip], ...].
func tools(_cat: String) -> Array:
	return []


## The player clicked tile t with one of this feature's tools. Returns a message to show.
func use_tool(_tool: String, _t: Vector2i) -> String:
	return ""


## Draws over the whole map view, in screen pixels (rain, snow and the like).
## to_tile turns a screen position into a map tile.
func draw_overlay(_view: CanvasItem, _to_tile: Callable) -> void:
	pass


## Extra lines for the People panel of realm p (the human player's realm).
func panel_lines(_p: Sim.Player) -> PackedStringArray:
	return PackedStringArray()


## What to keep in a saved game, and putting it back when the game is loaded.
func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass


## Lets the feature add buttons, windows or keys to the interface (main is the interface script; use
## main.add_feature_button, main.add_feature_window and main.add_feature_key so they go away again
## when the feature is switched off).
func build_ui(_main: Main) -> void:
	pass
