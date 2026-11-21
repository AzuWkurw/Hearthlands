class_name Score
extends RefCounted
## The final score of a finished game, the high-score lists kept on this computer, and the map of the day.
##
## The score adds up four parts, each taken at the realm's height so a lost game still counts for
## something: land held, people, wonders raised, and (for a win) a victory bonus that is bigger the
## faster you won. The sum is then multiplied by how hard the game was set up: rival strength and
## number, starting goods, peace, research and construction speed, endless resources, creative mode.
##
## Scores are only read from the game; nothing here changes how a game goes. The lists live in
## user://scores.json, one list per map: the map seed (or the mission), best first, at most KEEP each.
## The map of the day is a seed made from today's date, so everyone playing on the same day gets the
## same map with the same settings.

const FILE := "user://scores.json"
const KEEP := 10             # scores kept for each map

const PER_TILE := 2          # points for each tile of land at the realm's height
const PER_PERSON := 10       # points for each person at the realm's height
const PER_WONDER := 1500     # points for each wonder the realm raised
const WIN_BONUS := 1500      # points for winning at all
const SPEED_MAX := 3000      # extra points for a very fast win, down to nothing ...
const SPEED_FAST := 30.0     # ... from a win in this many minutes or less ...
const SPEED_SLOW := 240.0    # ... to a win in this many minutes or more

const DAILY_FOES := [2, 3, 3, 4]   # rivals on the map of the day, picked by the date
const DAILY_STRENGTH := 5


## The score of the game sim (win: whether you won). Returns {"total", "land", "people", "wonders",
## "victory", "mult", "minutes", "tiles", "pop", "won_n", "win", "ranked"}; "ranked" is false for a
## spectator game, which has no player to score.
static func compute(sim: Sim, win: bool) -> Dictionary:
	var me := sim.human()
	var minutes := int(sim.time) / 60
	var tiles: int = sim.owned(me.id)[0].size() if me.alive else 0
	var pop: int = sim.pop_total(me) if me.alive else 0
	# the realm's height, from the statistics when they are kept
	var st = sim.get_feature("statistics")
	if st != null:
		for b: Dictionary in st.hist.get(me.id, []):
			tiles = maxi(tiles, int(b.get("land", 0)))
			pop = maxi(pop, int(b.get("pop", 0)))
	var raised := 0
	for e: Dictionary in me.chron:
		if String(e.get("k", "")) == "wonder":
			raised += 1
	raised = maxi(raised, sim.wonders_of(me).size() if me.alive else 0)
	var victory := 0
	if win:
		var f := clampf((SPEED_SLOW - float(minutes)) / (SPEED_SLOW - SPEED_FAST), 0.0, 1.0)
		victory = WIN_BONUS + roundi(SPEED_MAX * f)
	var d := {
		"land": tiles * PER_TILE,
		"people": pop * PER_PERSON,
		"wonders": raised * PER_WONDER,
		"victory": victory,
		"mult": difficulty(sim),
		"minutes": minutes, "tiles": tiles, "pop": pop, "won_n": raised,
		"win": win,
		"ranked": not sim.spectating(),
	}
	d["total"] = roundi(float(int(d.land) + int(d.people) + int(d.wonders) + int(d.victory)) * float(d.mult))
	return d


## How hard the game was set up, as a multiplier on the score: 1.0 for the Normal preset with three
## rivals of strength 5. Harder settings raise it, easier ones lower it.
static func difficulty(sim: Sim) -> float:
	var o: Dictionary = sim.opts
	var m := 0.5 + 0.1 * clampf(float(sim.strength), 1.0, 10.0)     # strength 1: 0.6, 5: 1.0, 10: 1.5
	m *= 1.0 + 0.05 * clampf(float(sim.foes - 3), -2.0, 5.0)         # each rival more or fewer: 5%
	var goods := float(o.get("start_goods", 1.0))
	if goods < 1.0:
		m *= 1.15
	elif goods > 1.0:
		m *= 1.0 - 0.1 * log(goods) / log(2.0)                       # double: 0.9, four times: 0.8
	m *= 1.0 - clampf(float(o.get("peace_min", 0)), 0.0, 60.0) / 200.0   # 60 minutes of peace: 0.7
	var res := float(o.get("research", 1.0))
	m *= 1.0 - 0.1 * log(res) / log(2.0)                             # half: 1.1, double: 0.9, four times: 0.8
	m *= 1.0 - 0.1 * (float(o.get("build", 1.0)) - 1.0)              # 150%: 0.95, 200%: 0.9
	if o.get("endless_ore", false): m *= 0.95
	if o.get("endless_raw", false): m *= 0.95
	if not o.get("tools", true): m *= 0.95
	if o.get("road_carriers", false): m *= 1.05
	if o.get("all_research", false): m *= 0.5
	if o.get("creative", false): m *= 0.1
	return snappedf(maxf(0.05, m), 0.01)


## The high-score list a game belongs to: the mission's id, or the map seed.
static func key(sim: Sim) -> String:
	if not sim.mission.is_empty():
		return "mission:" + String(sim.mission.get("id", sim.mission.get("name", "")))
	return sim.seed_str


## The list's name as shown: the mission's name, or the seed.
static func key_name(k: String) -> String:
	if k.begins_with("mission:"):
		var id := k.substr(8)
		for ms in UiMissions.missions():
			if String(ms.get("id", "")) == id:
				return I18n.t(String(ms.get("name", id)))
		return id
	return k


## What goes into a high-score list for game sim with score s.
static func entry(sim: Sim, s: Dictionary, date := "") -> Dictionary:
	return {
		"score": int(s.total), "date": date if date != "" else Time.get_date_string_from_system(),
		"win": bool(s.win), "min": int(s.minutes), "mult": float(s.mult),
		"foes": sim.foes, "strength": sim.strength, "size": sim.w,
		"daily": is_daily(sim.seed_str),
	}


# ---------------------------------------------------------------- the high-score lists

## Every list from the file at path: {key: [entry, ...] best first}.
static func load_all(path := FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func save_all(all: Dictionary, path := FILE) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all, "\t"))


## The list for key k, best first.
static func best(k: String, path := FILE) -> Array:
	return load_all(path).get(k, [])


## Adds entry e to the list for key k and saves. Returns its place in the list (1 is the best), or 0
## when it did not make the list.
static func record(k: String, e: Dictionary, path := FILE) -> int:
	var all := load_all(path)
	var list: Array = all.get(k, [])
	list.append(e)
	# best first; an equal score keeps the older one ahead
	var idx := range(list.size())
	idx.sort_custom(func(a, b): return int(list[a].score) > int(list[b].score) or (int(list[a].score) == int(list[b].score) and a < b))
	var sorted := idx.map(func(i): return list[i])
	var place := sorted.find(e) + 1
	if sorted.size() > KEEP:
		sorted.resize(KEEP)
	if place > KEEP:
		place = 0
	all[k] = sorted
	save_all(all, path)
	return place


# ---------------------------------------------------------------- the map of the day

## Today's date as "2026-11-21" (or the date given).
static func today() -> String:
	return Time.get_date_string_from_system()


## The seed of the map of the day for date ("2026-11-21").
static func daily_seed(date := "") -> String:
	return "day " + (date if date != "" else today())


static func is_daily(seed: String) -> bool:
	return seed.begins_with("day ") and seed.length() == 14


## The settings of the map of the day for date: the same for everyone on that day.
## Returns {"seed", "foes", "strength"}; the rest is the Normal preset with peaceful victory on.
static func daily_setup(date := "") -> Dictionary:
	var s := daily_seed(date)
	return {"seed": s, "foes": int(DAILY_FOES[absi(s.hash()) % DAILY_FOES.size()]), "strength": DAILY_STRENGTH}


# ---------------------------------------------------------------- text

## The score as BBCode lines: the total, then each part.
static func lines(s: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(I18n.t("Final score: %s") % group(int(s.total)))
	var parts := PackedStringArray()
	parts.append(I18n.t("land %s (%d tiles)") % [group(int(s.land)), int(s.tiles)])
	parts.append(I18n.t("people %s (%d at the height)") % [group(int(s.people)), int(s.pop)])
	parts.append(I18n.t("wonders %s (%d raised)") % [group(int(s.wonders)), int(s.won_n)])
	if bool(s.win):
		parts.append(I18n.t("victory %s (won in %d minutes)") % [group(int(s.victory)), int(s.minutes)])
	out.append(I18n.t("%s; difficulty ×%.2f") % [", ".join(parts), float(s.mult)])
	return out


## n with thin groups of three digits: 12345 -> "12 345".
static func group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## One list as BBCode, best first; mark: the place to highlight (0 for none).
static func list_text(list: Array, mark := 0) -> String:
	if list.is_empty():
		return I18n.t("No scores yet.")
	var rows := PackedStringArray()
	for i in list.size():
		var e: Dictionary = list[i]
		var how := I18n.t("won in %d min") % int(e.get("min", 0)) if bool(e.get("win", false)) else I18n.t("lost after %d min") % int(e.get("min", 0))
		var row := "%d. [b]%s[/b]  %s, %s, ×%.2f" % [i + 1, group(int(e.get("score", 0))), String(e.get("date", "")), how, float(e.get("mult", 1.0))]
		if i + 1 == mark:
			row = "[color=#e8c870]%s  %s[/color]" % [row, I18n.t("(this game)")]
		rows.append(row)
	return "\n".join(rows)
