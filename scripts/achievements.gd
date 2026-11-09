class_name Achievements
extends RefCounted
## Achievements: little goals across all your games, kept in user://achievements.json with the day
## each was earned. Checked every few seconds while you play; a new one rings and shows a line. The
## end screen lists the ones earned in that game, and the new-game screen shows them all.

const FILE := "user://achievements.json"

## [id, name, what earns it]
const LIST := [
	["village", "Village", "Grow to 50 people"],
	["town", "Market town", "Grow to 200 people"],
	["city", "City", "Grow to 500 people"],
	["bread", "Bread for all", "Keep 100 bread in store"],
	["bridge", "Bridge builder", "Build a bridge"],
	["merchant", "Merchant", "Make 10 trades with other realms"],
	["shores", "New shores", "Found a colony across the water"],
	["brigade", "Fire brigade", "Put out 5 fires"],
	["feast", "Feast day", "Hold a festival at a tavern"],
	["archers", "Archers on the walls", "Have 10 archers"],
	["scholar", "Scholar", "Study 30 techs in one game"],
	["modern", "Steam and iron", "Reach the last age"],
	["conqueror", "Conqueror", "Defeat a rival realm"],
	["peace", "Peacemaker", "Win a game without ever attacking"],
	["chronicle", "Chronicler", "Win every chapter of the campaign"],
]

var main: Main
var got := {}             # id -> the day it was earned ("2026-11-09")
var this_game: Array = [] # ids earned in the game being played
var _t := 0.0


func _init(p_owner: Main) -> void:
	main = p_owner
	if FileAccess.file_exists(FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary:
			got = d


func _save() -> void:
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(got, "\t"))


func new_game() -> void:
	this_game = []


func _earn(id: String) -> void:
	if got.has(id):
		return
	got[id] = Time.get_date_string_from_system()
	this_game.append(id)
	_save()
	for a in LIST:
		if a[0] == id:
			main._show_hint(tr("Achievement: %s! (%s)") % [tr(a[1]), tr(a[2])], 5.0)
			main.sim.emit_log(tr("Achievement earned: %s (%s).") % [tr(a[1]), tr(a[2])], Color("e8c870"))
	if main.sound != null:
		main.sound.play("good", 0.9)


## Called as the interface refreshes; looks every 5 seconds.
func check(delta_real: float) -> void:
	var sim: Sim = main.sim
	if sim == null or sim.players.is_empty() or sim.w == 0 or main.editor_ui.open:
		return
	_t += delta_real
	if _t < 5.0:
		return
	_t = 0.0
	var me := sim.human()
	var pop: int = sim.pop_total(me)
	if pop >= 50: _earn("village")
	if pop >= 200: _earn("town")
	if pop >= 500: _earn("city")
	if float(me.stock.get("bread", 0.0)) >= 100.0: _earn("bread")
	if me.trades >= 10: _earn("merchant")
	if me.colonies >= 1: _earn("shores")
	if me.techs.size() >= 30: _earn("scholar")
	if me.age >= GameData.ages.size() - 1: _earn("modern")
	var fires = sim.get_feature("fires")
	if fires != null and int(fires.put_out.get(1, 0)) >= 5: _earn("brigade")
	var co = sim.get_feature("contentment")
	if co != null and int(co.feasts.get(1, 0)) >= 1: _earn("feast")
	var archers := 0
	for b: Sim.Bld in sim.realm_blds(me):
		archers += b.archers
	if archers >= 10: _earn("archers")
	if not got.has("bridge"):
		for i in sim.owned(1)[0]:
			if sim.road[i] == 1 and sim.ter[i] == Sim.WATER:
				_earn("bridge")
				break
	for p in sim.players:
		if p.ai and not p.alive:
			_earn("conqueror")
			break


## At the end of a game: the ones that need a won game.
func on_end(won: bool) -> void:
	var sim: Sim = main.sim
	if won and sim.human().attacks_made == 0 and sim.mission.is_empty():
		_earn("peace")
	var cu: UiCampaign = main.campaign_ui
	cu.load_data()
	if not cu.chapters.is_empty() and range(cu.chapters.size()).all(func(k): return cu.is_done(k)):
		_earn("chronicle")


func earned_text() -> String:
	if this_game.is_empty():
		return ""
	var names := []
	for a in LIST:
		if this_game.has(a[0]):
			names.append(tr(a[1]))
	return "\n\nAchievements this game: " + ", ".join(names) + "."


## All achievements, earned ones ticked with their day, for the window on the new-game screen.
func list_text() -> String:
	var lines := []
	for a in LIST:
		if got.has(a[0]):
			lines.append("[color=#86ad5c]✔ [b]%s[/b][/color]  %s  [color=#9a9c88](%s)[/color]" % [tr(a[1]), tr(a[2]), String(got[a[0]])])
		else:
			lines.append("[color=#6a6c60]○[/color] [b]%s[/b]  [color=#9a9c88]%s[/color]" % [tr(a[1]), tr(a[2])])
	return "%d of %d earned\n\n" % [got.size(), LIST.size()] + "\n".join(lines)
