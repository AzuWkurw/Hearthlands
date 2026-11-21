class_name Chronicle
extends RefCounted
## The chronicle (build 77): the story of a game, told when it ends. The simulation notes the moments that
## make a realm's history as they happen (towns founded, ages reached, wonders, buildings taken and lost,
## attacks beaten back, battles in the open field, fires, famines, realms that fell). Each note goes into
## its realm's `Player.chron`, so it is saved with the game like everything else in a Player. A note is a
## Dictionary: "k" its kind, "t" the game second, and a few words of its own (building type, the other
## realm's id...). Nothing in the game ever reads the notes back, so they cannot change how a game goes.
## `story()` turns them, with the statistics and the random events' history, into the written chronicle
## shown by UiChronicle (ui_chronicle.gd); the words are made only then, so they follow the language.

const MAX := 500           # notes kept per realm; past it the oldest fire or battle goes first
const MERGE_S := 120.0     # a fire or a famine this soon after the last one is the same story
const MINOR := ["fire", "burned", "repelled", "beaten", "field_won", "field_lost"]


## Notes moment kind for realm p, with its own words d.
static func note(sim: Sim, p: Sim.Player, kind: String, d := {}) -> void:
	if p == null:
		return
	d["k"] = kind
	d["t"] = floorf(sim.time)
	p.chron.append(d)
	if p.chron.size() > MAX:
		for i in p.chron.size():
			if String((p.chron[i] as Dictionary).get("k", "")) in MINOR:
				p.chron.remove_at(i)
				return
		p.chron.pop_front()


## The last note of kind for p if it was added or touched within MERGE_S seconds, else {}.
static func _recent(sim: Sim, p: Sim.Player, kind: String) -> Dictionary:
	for i in range(p.chron.size() - 1, -1, -1):
		var e: Dictionary = p.chron[i]
		if sim.time - float(e.get("e", e.get("t", 0.0))) > MERGE_S:
			return {}
		if String(e.get("k", "")) == kind:
			return e
	return {}


## A building of p caught fire (fires.gd). Fires close together are one story, counted.
static func fire(sim: Sim, p: Sim.Player) -> void:
	var e := _recent(sim, p, "fire")
	if e.is_empty():
		note(sim, p, "fire", {"n": 1, "lost": 0, "e": floorf(sim.time)})
	else:
		e["n"] = int(e.get("n", 1)) + 1
		e["e"] = floorf(sim.time)


## A building of p burned down.
static func burned(sim: Sim, p: Sim.Player) -> void:
	var e := _recent(sim, p, "fire")
	if e.is_empty():
		note(sim, p, "fire", {"n": 1, "lost": 1, "e": floorf(sim.time)})
	else:
		e["lost"] = int(e.get("lost", 0)) + 1
		e["e"] = floorf(sim.time)


## Realm p ran out of food (people go hungry); died: someone starved.
static func famine(sim: Sim, p: Sim.Player, died := 0) -> void:
	var e := _recent(sim, p, "famine")
	if e.is_empty():
		note(sim, p, "famine", {"dead": died, "e": floorf(sim.time)})
	else:
		e["dead"] = int(e.get("dead", 0)) + died
		e["e"] = floorf(sim.time)


# ---------------------------------------------------------------- telling the story

## Every note of every realm, oldest first (ties: lower realm first), each with "p" its realm's id.
static func all_notes(sim: Sim) -> Array:
	var out := []
	for p: Sim.Player in sim.players:
		for e: Dictionary in p.chron:
			var c := e.duplicate()
			c["p"] = p.id
			out.append(c)
	var ev = sim.get_feature("events")
	if ev != null:
		for h in ev.history:
			if int(h[1]) == 1:
				out.append({"k": "event", "t": floorf(float(h[0])), "p": 1, "ev": String(h[2])})
	out.sort_custom(func(a, b): return float(a.t) < float(b.t) or (float(a.t) == float(b.t) and int(a.p) < int(b.p)))
	return out


static func _min(t: float) -> int:
	return int(t) / 60


func _realm(sim: Sim, pid: int) -> String:
	if pid < 1 or pid > sim.players.size():
		return tr("a rival")
	var q: Sim.Player = sim.players[pid - 1]
	return "[color=#%s]%s[/color]" % [q.color.to_html(false), q.name]


func _bld(ty: String) -> String:
	return tr(String(GameData.bld.get(ty, {}).get("name", ty)))


func _age(a: int) -> String:
	return tr(GameData.age_name(a))


func _list(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return tr("%s and %s") % [", ".join(words.slice(0, words.size() - 1)), words[-1]]


## The chapters of your realm's story: one per age it lived through, from when it entered that age.
## Returns [{"age": int, "t0": seconds, "t1": seconds}, ...].
static func chapters(sim: Sim) -> Array:
	var me := sim.human()
	var ages := []
	for e: Dictionary in me.chron:
		if String(e.get("k", "")) == "age":
			ages.append(e)
	var first := me.age if ages.is_empty() else int(ages[0].age) - 1
	var out := [{"age": maxi(0, first), "t0": 0.0, "t1": sim.time + 1.0}]
	for e in ages:
		out[-1].t1 = float(e.t)
		out.append({"age": int(e.age), "t0": float(e.t), "t1": sim.time + 1.0})
	return out


## The written chronicle of the game as BBCode: a chapter for each age, then how it ended and the
## realm at its height.
func story(sim: Sim, win: bool) -> String:
	var me := sim.human()
	var notes := all_notes(sim)
	var out := PackedStringArray()
	var cap := me.hq.town if me.hq != null and me.hq.town != "" else ""
	if cap == "":
		for b in sim.blds:
			if b.p == 1 and b.ty == "hq":
				cap = b.town
	var opening := tr("In the first year, your people raised their headquarters in an empty land.")
	if cap != "":
		opening = tr("In the first year, your people raised their headquarters at %s, in an empty land.") % cap
	var foes := sim.players.size() - 1
	if foes > 0:
		opening += " " + (tr("One rival realm shared the world with them.") if foes == 1 else tr("%d rival realms shared the world with them.") % foes)
	out.append(opening)
	for ch: Dictionary in chapters(sim):
		var t0 := float(ch.t0)
		var t1 := float(ch.t1)
		if t1 <= t0 and t0 > 0.0:
			continue
		var part := notes.filter(func(e): return float(e.t) >= t0 and float(e.t) < t1)
		var head := tr("The %s age") % _age(int(ch.age))
		var span := tr("minutes %d to %d") % [_min(t0), _min(minf(t1, sim.time))]
		out.append("\n[font_size=18][color=#d8aa4a]%s[/color][/font_size]  [color=#9a9c88](%s)[/color]" % [head, span])
		var lines := _chapter(sim, part, t0 > 0.0, int(ch.age))
		if lines.is_empty():
			lines.append(tr("The years passed quietly: the realm worked its fields and its workshops, and nothing the chroniclers thought worth a line happened."))
		out.append("\n".join(lines))
	out.append("\n[font_size=18][color=#d8aa4a]%s[/color][/font_size]" % tr("The end"))
	out.append("\n".join(_ending(sim, win, notes)))
	return "\n".join(out)


## The lines of one chapter from its notes (entered: the realm entered this age during the game).
func _chapter(sim: Sim, part: Array, entered: bool, age: int) -> PackedStringArray:
	var lines := PackedStringArray()
	if entered:
		var e0: Dictionary = {}
		for e in part:
			if e.k == "age" and int(e.p) == 1:
				e0 = e
				break
		if not e0.is_empty():
			lines.append(tr("In minute %d the realm entered the %s age.") % [_min(float(e0.t)), _age(age)])
	# towns and colonies
	var towns := []
	var colonies := []
	for e in part:
		if int(e.p) == 1 and e.k == "town":
			(colonies if bool(e.get("sea", false)) else towns).append(String(e.get("name", "")))
	if not towns.is_empty():
		lines.append((tr("A new town was founded: %s.") if towns.size() == 1 else tr("New towns were founded: %s.")) % _list(towns))
	if not colonies.is_empty():
		lines.append((tr("Ships carried settlers across the water to found %s.")) % _list(colonies))
	# wonders, yours and everyone else's
	for e in part:
		if e.k == "wonder":
			if int(e.p) == 1:
				lines.append(tr("In minute %d the %s was finished, and people came from far away to see it.") % [_min(float(e.t)), _bld(String(e.b))])
			else:
				lines.append(tr("%s raised the %s in minute %d.") % [_realm(sim, int(e.p)), _bld(String(e.b)), _min(float(e.t))])
	# war: buildings taken and lost, by the other realm
	var took := {}
	var lost := {}
	var took_names := {}
	for e in part:
		if e.k == "capture":
			if int(e.p) == 1:
				took[int(e.o)] = int(took.get(int(e.o), 0)) + 1
				if not took_names.has(int(e.o)):
					took_names[int(e.o)] = _bld(String(e.b))
			elif int(e.o) == 1:
				lost[int(e.p)] = int(lost.get(int(e.p), 0)) + 1
	var foes := took.keys() + lost.keys().filter(func(k): return not took.has(k))
	foes.sort()
	for q in foes:
		var a := int(took.get(q, 0))
		var b := int(lost.get(q, 0))
		if a > 0 and b > 0:
			lines.append(tr("War with %s: your soldiers took %d of their buildings and lost %d of yours.") % [_realm(sim, q), a, b])
		elif a == 1:
			lines.append(tr("Your soldiers took a %s from %s.") % [took_names[q], _realm(sim, q)])
		elif a > 1:
			lines.append(tr("Your soldiers took %d buildings from %s.") % [a, _realm(sim, q)])
		elif b == 1:
			lines.append(tr("%s took one of your buildings.") % _realm(sim, q))
		else:
			lines.append(tr("%s took %d of your buildings.") % [_realm(sim, q), b])
	var held := 0
	var failed := 0
	var fw := 0
	var fl := 0
	for e in part:
		match String(e.k):
			"repelled":
				if int(e.p) == 1:
					held += 1
				elif int(e.get("o", 0)) == 1:
					failed += 1
			"field_won":
				if int(e.p) == 1:
					fw += 1
				elif int(e.get("o", 0)) == 1:
					fl += 1
	if held > 0:
		lines.append(tr("An attack on your walls was beaten back.") if held == 1 else tr("%d attacks on your walls were beaten back.") % held)
	if failed > 0:
		lines.append(tr("One of your attacks was beaten back at the gate.") if failed == 1 else tr("%d of your attacks were beaten back at the gate.") % failed)
	if fw > 0 or fl > 0:
		lines.append(tr("Columns met in the open field: you won %d of those battles and lost %d.") % [fw, fl])
	# fires and famines at home
	var fires := 0
	var burned := 0
	for e in part:
		if e.k == "fire" and int(e.p) == 1:
			fires += int(e.get("n", 1))
			burned += int(e.get("lost", 0))
	if fires > 0:
		var s := tr("Fire broke out once") if fires == 1 else tr("Fire broke out %d times") % fires
		if burned == 0:
			s += tr(", and every time the bucket lines put it out.") if fires > 1 else tr(", and the bucket lines put it out.")
		elif burned == 1:
			s += tr("; one building burned to the ground.")
		else:
			s += tr("; %d buildings burned to the ground.") % burned
		lines.append(s)
	for e in part:
		if e.k == "famine" and int(e.p) == 1:
			var dead := int(e.get("dead", 0))
			var m0 := _min(float(e.t))
			var m1 := _min(float(e.get("e", e.t)))
			var when := tr("in minute %d") % m0 if m1 <= m0 else tr("from minute %d to %d") % [m0, m1]
			if dead == 0:
				lines.append(tr("The stores ran empty %s and the people went hungry, but nobody starved.") % when)
			elif dead == 1:
				lines.append(tr("Hunger came %s; one of your people starved.") % when)
			else:
				lines.append(tr("Hunger came %s; %d of your people starved.") % [when, dead])
	# the random events of your realm
	var evs := []
	var ev = sim.get_feature("events")
	for e in part:
		if e.k == "event" and ev != null and ev.EVENTS.has(String(e.ev)):
			evs.append("%s (%d)" % [tr(String(ev.EVENTS[String(e.ev)][0])), _min(float(e.t))])
	if not evs.is_empty():
		lines.append(tr("The chroniclers also wrote down, by the minute: %s.") % ", ".join(evs))
	# the rest of the world
	for e in part:
		if int(e.p) == 1:
			continue
		if e.k == "age" and int(e.age) >= 2:
			lines.append(tr("%s reached the %s age in minute %d.") % [_realm(sim, int(e.p)), _age(int(e.age)), _min(float(e.t))])
	for e in part:
		if e.k == "fall":
			if int(e.p) == 1:
				lines.append(tr("In minute %d %s captured your headquarters.") % [_min(float(e.t)), _realm(sim, int(e.by))])
			elif int(e.by) == 1:
				lines.append(tr("In minute %d your soldiers took the headquarters of %s, and that realm was no more.") % [_min(float(e.t)), _realm(sim, int(e.p))])
			else:
				lines.append(tr("In minute %d %s fell to %s.") % [_min(float(e.t)), _realm(sim, int(e.p)), _realm(sim, int(e.by))])
	# surrenders and vassals breaking free
	for e in part:
		if e.k == "vassal":
			if int(e.p) == 1:
				lines.append(tr("In minute %d your realm surrendered to %s and became its vassal.") % [_min(float(e.t)), _realm(sim, int(e.o))])
			elif int(e.o) == 1:
				lines.append(tr("In minute %d %s surrendered to you and became your vassal.") % [_min(float(e.t)), _realm(sim, int(e.p))])
			else:
				lines.append(tr("In minute %d %s became a vassal of %s.") % [_min(float(e.t)), _realm(sim, int(e.p)), _realm(sim, int(e.o))])
		elif e.k == "free":
			if int(e.p) == 1:
				lines.append(tr("In minute %d your realm was free of %s again.") % [_min(float(e.t)), _realm(sim, int(e.o))])
			elif int(e.o) == 1:
				lines.append(tr("In minute %d %s was no longer your vassal.") % [_min(float(e.t)), _realm(sim, int(e.p))])
	return lines


## The last chapter: how the game ended, the realm at its height, and where everyone stood.
func _ending(sim: Sim, win: bool, notes: Array) -> PackedStringArray:
	var me := sim.human()
	var lines := PackedStringArray()
	var m := _min(sim.time)
	if win:
		lines.append(tr("After %d minutes the realm stood victorious.") % m)
	elif me.alive:
		lines.append(tr("After %d minutes another realm carried the day, and the chronicle of yours ends here.") % m)
	else:
		lines.append(tr("After %d minutes the realm fell, and its chronicle ends here.") % m)
	var st = sim.get_feature("statistics")
	var h: Array = st.hist.get(1, []) if st != null else []
	if not h.is_empty():
		var first: int = int(st.minute) - h.size()
		var best := {}
		var at := {}
		for k in ["pop", "land", "bld", "sol"]:
			best[k] = 0.0
			at[k] = 0
		for i in h.size():
			for k in best:
				var v := float((h[i] as Dictionary).get(k, 0.0))
				if v > float(best[k]):
					best[k] = v
					at[k] = first + i + 1
		lines.append(tr("At its height the realm had %d people (minute %d), held %d tiles of land (minute %d), and stood %d buildings and %d soldiers strong.") % [int(best.pop), int(at.pop), int(best.land), int(at.land), int(best.bld), int(best.sol)])
		var made := 0.0
		for b: Dictionary in h:
			made += float(b.get("made_total", 0.0))
		if made > 0.0:
			lines.append(tr("Its workers made %d goods in all.") % roundi(made))
	var towns := 0
	var wonders := 0
	var took := 0
	var lost := 0
	var fires := 0
	var hungry := 0
	for e in notes:
		match String(e.k):
			"town":
				if int(e.p) == 1: towns += 1
			"wonder":
				if int(e.p) == 1: wonders += 1
			"capture":
				if int(e.p) == 1: took += 1
				elif int(e.o) == 1: lost += 1
			"fire":
				if int(e.p) == 1: fires += int(e.get("n", 1))
			"famine":
				if int(e.p) == 1: hungry += 1
	var tally := PackedStringArray()
	if towns > 0: tally.append(tr("%d towns founded") % towns if towns > 1 else tr("one town founded"))
	if wonders > 0: tally.append(tr("%d wonders raised") % wonders if wonders > 1 else tr("one wonder raised"))
	if took > 0: tally.append(tr("%d buildings taken in war") % took if took > 1 else tr("one building taken in war"))
	if lost > 0: tally.append(tr("%d buildings lost to enemies") % lost if lost > 1 else tr("one building lost to enemies"))
	if fires > 0: tally.append(tr("%d fires") % fires if fires > 1 else tr("one fire"))
	if hungry > 0: tally.append(tr("%d hungry spells") % hungry if hungry > 1 else tr("one hungry spell"))
	if not tally.is_empty():
		lines.append(tr("In all: %s.") % ", ".join(tally))
	# where everyone stood at the end
	var rows := ["[table=5][cell][b]%s[/b]  [/cell][cell][b]%s[/b]  [/cell][cell][b]%s[/b]  [/cell][cell][b]%s[/b]  [/cell][cell][b]%s[/b][/cell]" % [tr("Realm"), tr("Age"), tr("People"), tr("Land"), tr("Wonders")]]
	for q: Sim.Player in sim.players:
		var gone := "" if q.alive else " " + tr("(fallen)")
		rows.append("[cell]%s%s  [/cell][cell]%s  [/cell][cell]%d  [/cell][cell]%d  [/cell][cell]%d[/cell]" % [_realm(sim, q.id), gone, _age(q.age), sim.pop_total(q) if q.alive else 0, sim.owned(q.id)[0].size() if q.alive else 0, sim.wonders_of(q).size() if q.alive else 0])
	lines.append("\n" + "".join(rows) + "[/table]")
	return lines


## Each realm's line for a chart of key ("pop", "land"...), from the statistics, and the minute the
## lines start at. Returns [series, first minute] (series empty without the statistics feature).
static func series(sim: Sim, key: String) -> Array:
	var st = sim.get_feature("statistics")
	if st == null:
		return [[], 0]
	var ser := []
	var longest := 0
	for q: Sim.Player in sim.players:
		var hq: Array = st.hist.get(q.id, [])
		longest = maxi(longest, hq.size())
		ser.append({"name": q.name, "color": q.color, "values": hq.map(func(b): return float(b.get(key, 0.0)))})
	return [ser, maxi(0, st.minute - longest)]
