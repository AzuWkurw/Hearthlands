class_name Keys
extends RefCounted
## The game's keyboard shortcuts, and the keys the player gave them in Settings.
## Every shortcut is an action with a default key. A key is a key code with the Shift, Ctrl and Alt
## masks added (KEY_MASK_SHIFT | KEY_Q is Shift+Q), the same form OS.get_keycode_string() names.
## The player's choices are kept in Settings.keys (action -> key), only for actions moved off their
## default, and saved with the other settings. A key does one action only: giving an action a key that
## another action has swaps the two.

## [action, what it does, default key, group in Settings]. The order is the order in Settings.
const ACTIONS := [
	["pan_up", "Move the map up", KEY_W, "Map"],
	["pan_down", "Move the map down", KEY_S, "Map"],
	["pan_left", "Move the map left", KEY_A, "Map"],
	["pan_right", "Move the map right", KEY_D, "Map"],
	["zoom_in", "Zoom in", KEY_EQUAL, "Map"],
	["zoom_out", "Zoom out", KEY_MINUS, "Map"],
	["zoom_fit", "Fit the research tree in the window", KEY_0, "Map"],
	["idle", "Go to the next idle or stuck building", KEY_I, "Map"],
	["sites", "Show free building spots", KEY_B, "Map"],
	["traffic", "Traffic map", KEY_F7, "Map"],
	["pause", "Pause the game", KEY_SPACE, "Game"],
	["speed1", "Speed 1x", KEY_1, "Game"],
	["speed2", "Speed 2x", KEY_2, "Game"],
	["speed3", "Speed 4x", KEY_3, "Game"],
	["speed4", "Speed 8x", KEY_4, "Game"],
	["speed5", "Speed 16x", KEY_5, "Game"],
	["quicksave", "Quick save", KEY_F5, "Game"],
	["quickload", "Quick load", KEY_F9, "Game"],
	["undo", "Undo", KEY_MASK_CTRL | KEY_Z, "Game"],
	["redo", "Redo (map editor)", KEY_MASK_CTRL | KEY_Y, "Game"],
	["settings", "Settings", KEY_F10, "Game"],
	["perf", "Show or hide the frame rate", KEY_F3, "Game"],
	["ui_bigger", "Interface a size bigger", KEY_MASK_CTRL | KEY_EQUAL, "Game"],
	["ui_smaller", "Interface a size smaller", KEY_MASK_CTRL | KEY_MINUS, "Game"],
	["copy", "Build another of the building under the mouse", KEY_Q, "Buildings"],
	["queue_site", "Put the building site under the mouse in the build queue", KEY_MASK_SHIFT | KEY_Q, "Buildings"],
	["turn", "Turn the entrance (research when not placing)", KEY_R, "Buildings"],
	["prio_pause", "Pause the selected building", KEY_P, "Buildings"],
	["prio_up", "Raise the selected building's priority", KEY_PAGEUP, "Buildings"],
	["prio_down", "Lower the selected building's priority", KEY_PAGEDOWN, "Buildings"],
	["demolish", "Demolish the selected building", KEY_DELETE, "Buildings"],
	["events", "Show or hide the event log", KEY_E, "Windows"],
	["problems", "Show or hide the Problems list", KEY_O, "Windows"],
	["diplomacy", "Diplomacy", KEY_G, "Windows"],
	["targets", "Production targets", KEY_T, "Windows"],
	["buildings", "Buildings window", KEY_J, "Windows"],
	["transport", "Transport priorities", KEY_K, "Windows"],
	["workers", "Worker priorities", KEY_L, "Windows"],
	["bottlenecks", "Bottleneck finder", KEY_N, "Windows"],
	["market", "Market prices", KEY_M, "Windows"],
	["blueprints", "Blueprints", KEY_U, "Windows"],
	["sea_guide", "Sea and supplies guide", KEY_MASK_SHIFT | KEY_H, "Windows"],
	["handbook", "Handbook", KEY_F1, "Windows"],
]

## Second keys that do the same as an action, as long as the player has not given the key to another.
const ALIASES := {
	KEY_UP: "pan_up", KEY_DOWN: "pan_down", KEY_LEFT: "pan_left", KEY_RIGHT: "pan_right",
	KEY_KP_ADD: "zoom_in", KEY_KP_SUBTRACT: "zoom_out", KEY_KP_0: "zoom_fit",
	KEY_MASK_CTRL | KEY_KP_ADD: "ui_bigger", KEY_MASK_CTRL | KEY_KP_SUBTRACT: "ui_smaller",
	KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_Z: "redo",
}

## Keys no action can have: Esc cancels and closes windows, Enter answers questions.
const RESERVED := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]

## Keys that are only half of a key: waiting for a new key ignores them.
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]

const GROUPS := ["Map", "Game", "Buildings", "Windows", "Game features"]


## The heading of a group in Settings, translated (written out so tools/extract_strings.py finds them).
func group_title(g: String) -> String:
	match g:
		"Map": return tr("Map")
		"Game": return tr("Game")
		"Buildings": return tr("Buildings")
		"Windows": return tr("Windows")
		"Game features": return tr("Game features")
	return tr(g)

var settings: Settings           # its `keys`: action -> key, for actions not on their default
var extra := []                  # keys added by game features and mods, as in ACTIONS
var _map := {}                   # key -> action, built from the above
var _built_from := -1            # hash of `saved` and `extra` when _map was built


func _init(p_settings: Settings) -> void:
	settings = p_settings


## The player's choices (the dictionary is replaced when the settings are loaded again).
var saved: Dictionary:
	get: return settings.keys


## Every action, the built-in ones first, then those of game features.
func actions() -> Array:
	return ACTIONS + extra


func info(id: String) -> Array:
	for a in actions():
		if a[0] == id:
			return a
	return []


func title(id: String) -> String:
	var a := info(id)
	return String(a[1]) if not a.is_empty() else id


func default_key(id: String) -> int:
	var a := info(id)
	return int(a[2]) if not a.is_empty() else KEY_NONE


## The key that does action id now.
func key_for(id: String) -> int:
	return int(saved.get(id, default_key(id)))


## The name of action id's key, for hints and buttons ("Shift+Q").
func key_name(id: String) -> String:
	return name_of(key_for(id))


static func name_of(k: int) -> String:
	return OS.get_keycode_string(k) if k != KEY_NONE else "-"


## A pressed key as a key with its Shift, Ctrl and Alt masks.
static func of_event(e: InputEventKey) -> int:
	var k := int(e.keycode)
	if k == KEY_NONE:
		k = int(e.physical_keycode)
	if e.shift_pressed: k |= KEY_MASK_SHIFT
	if e.ctrl_pressed: k |= KEY_MASK_CTRL
	if e.alt_pressed: k |= KEY_MASK_ALT
	return k


## A key game features and mods add (main.add_feature_key). Its action is "f:<feature>:<default key>".
func add_feature(fid: String, key: int, what: String) -> String:
	var id := "f:%s:%d" % [fid, key]
	if info(id).is_empty():
		extra.append([id, what, key, "Game features"])
	return id


## The action a pressed key does, or "". Shift+R does what R does when nothing is on Shift+R, so the
## actions that look at Shift (turning the other way, redo) keep working.
func action_of(e: InputEventKey) -> String:
	_build()
	var k := of_event(e)
	if _map.has(k):
		return _map[k]
	if k & KEY_MASK_SHIFT and _map.has(k & ~KEY_MASK_SHIFT):
		return _map[k & ~KEY_MASK_SHIFT]
	return ""


## The keys (without Shift, Ctrl, Alt) that do action id, for actions that work while held (moving the map).
func held_keys(id: String) -> Array:
	_build()
	var out := []
	for k in _map:
		if _map[k] == id:
			out.append(int(k) & KEY_CODE_MASK)
	return out


## Whether k may be given to an action: not Esc or Enter, and not Shift or Ctrl alone.
static func usable(k: int) -> bool:
	var code := k & KEY_CODE_MASK
	return code != KEY_NONE and not (code in RESERVED) and not (code in MODIFIERS)


## Text that names keys, translated and with the player's own keys in it: each action's default key is
## replaced by the key it has now. With ids, only those actions, wherever their key stands as a word of
## its own ("Space pauses, R opens research"). Without, every action, but only where its key stands in
## brackets ("(O)", "(I for the next)"), so letters in ordinary words are left alone. The translation is
## looked up for the English text as written, so translations keep working when keys move.
func keyed(text: String, ids: Array = []) -> String:
	var out := tr(text)
	var loose := not ids.is_empty()
	var swaps := []
	for a in actions():
		var id := String(a[0])
		if (loose and not (id in ids)) or is_default(id):
			continue
		var n := name_of(int(a[2])).replace("+", "\\+").replace(".", "\\.")
		var re := RegEx.new()
		re.compile(("(?<![A-Za-z0-9+])%s(?![A-Za-z0-9+])" if loose else "(?<=\\()%s(?=[)\\s,])") % n)
		swaps.append([re, name_of(key_for(id))])
	# through placeholders, so two swapped keys do not turn into each other again
	for i in swaps.size():
		out = (swaps[i][0] as RegEx).sub(out, "\u0001%d\u0001" % i, true)
	for i in swaps.size():
		out = out.replace("\u0001%d\u0001" % i, String(swaps[i][1]))
	return out


## Gives action id the key k. The action that had k gets id's old key. Returns a line for the player
## saying what else changed, or "" when nothing else did.
func set_key(id: String, k: int) -> String:
	if not usable(k) or info(id).is_empty():
		return ""
	var old := key_for(id)
	if k == old:
		return ""
	var other := ""
	for a in actions():
		if a[0] != id and key_for(a[0]) == k:
			other = a[0]
	_store(id, k)
	var msg := ""
	if other != "":
		_store(other, old)
		msg = tr("%s was the key for \"%s\"; that now has %s.") % [name_of(k), tr(title(other)), name_of(old)]
	elif ALIASES.has(k) and ALIASES[k] != id:
		msg = tr("%s no longer does \"%s\" as well.") % [name_of(k), tr(title(ALIASES[k]))]
	_built_from = -1
	return msg


## Puts action id back on its default key; the action that had that key gets id's key.
func reset_key(id: String) -> String:
	return set_key(id, default_key(id))


## Every action back on its default key.
func reset_all() -> void:
	saved.clear()
	_built_from = -1


func is_default(id: String) -> bool:
	return key_for(id) == default_key(id)


func _store(id: String, k: int) -> void:
	if k == default_key(id):
		saved.erase(id)
	else:
		saved[id] = k


## Builds the key -> action map. Keys saved by an older build, or edited by hand, that clash with
## another action or cannot be used are dropped, so the action goes back to its default key.
func _build() -> void:
	var h := hash([saved, extra.size()])
	if h == _built_from:
		return
	for _round in 64:
		_map.clear()
		var bad := ""
		for a in actions():
			var id := String(a[0])
			var k := key_for(id)
			if saved.has(id) and not usable(k):
				bad = id
				break
			if _map.has(k):
				# a clash: drop the player's choice of whichever of the two has one; when both are on
				# their default (a mod's key), the first keeps it
				var o := String(_map[k])
				if saved.has(id):
					bad = id
					break
				if saved.has(o):
					bad = o
					break
				continue
			_map[k] = id
		if bad == "":
			break
		saved.erase(bad)
	for k in ALIASES:
		if not _map.has(k):
			_map[k] = ALIASES[k]
	_built_from = hash([saved, extra.size()])
