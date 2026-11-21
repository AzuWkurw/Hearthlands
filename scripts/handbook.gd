class_name Handbook
extends RefCounted
## The handbook's pages, written from the data files: one page for every building, good, tech and
## mastery study, age, law and game feature, and a first page on how to use it. Nothing is written by
## hand per page: a new building or good in data/*.json (or a mod's) gets its page by itself.
##
## Pages are made in the language shown now (each piece goes through tr()), so the window makes them
## again when the language changes. A page is a dictionary: its id ("bld:sawmill", "res:planks",
## "tech:herding", "age:1", "law:tax", "feat:fires" or "home"), the group of the list it is in, a smaller
## heading inside the group (a building's kind, a tech's age), its title and text (BBCode, translated,
## with [url=<id>] links to other pages), and "find", the lower-case title and plain text the search
## box looks through.
## The handbook itself never changes the game, so it may read anything.

const GROUPS := ["Buildings", "Goods", "Techs", "Ages", "Laws", "Game features"]
const HEAD := "#d8aa4a"
const LINK := "#e8c870"
const DIM := "#9a9c88"
const GOOD := "#8fc070"
const LawsScript := preload("res://scripts/features/laws.gd")
const HealthScript := preload("res://scripts/features/factory_health.gd")

var pages: Array = []          # every page, in list order
var by_id: Dictionary = {}     # page id -> page
var _health: Dictionary = {}
var _feats: Array = []


## Writes every page again (in the language shown now).
func make() -> void:
	GameData.ensure()
	LawsScript.add_translations()
	_health = HealthScript.load_cfg()
	_feats = Features.available()
	pages = []
	by_id = {}
	_add("home", "", "", tr("Handbook"), _home_text())
	for c in GameData.CATEGORIES:
		for id: String in GameData.bld:
			var d: Dictionary = GameData.bld[id]
			if String(d.get("cat", "")) == String(c[0]) or (String(c[0]) == "logistics" and String(d.get("cat", "")) == "special"):
				_add("bld:" + id, "Buildings", tr(String(c[1])), tr(String(d.get("name", id))), _bld_text(id))
	for r: Dictionary in GameData.resources:
		_add("res:" + String(r.id), "Goods", "", tr(String(r.get("name", r.id))), _res_text(String(r.id)))
	for a in GameData.ages.size():
		for id: String in GameData.techs:
			var t: Dictionary = GameData.techs[id]
			if int(t.get("age", 0)) == a:
				_add("tech:" + id, "Techs", tr(GameData.age_name(a)), tr(String(t.get("name", id))), _tech_text(id))
	for id: String in GameData.reps:
		_add("tech:" + id, "Techs", tr("Mastery"), tr(String(GameData.reps[id].get("name", id))), _rep_text(id))
	for a in GameData.ages.size():
		_add("age:%d" % a, "Ages", "", tr(GameData.age_name(a)), _age_text(a))
	for l: Dictionary in LawsScript.law_list():
		_add("law:" + String(l.id), "Laws", "", tr(String(l.get("name", l.id))), _law_text(l))
	for f: Dictionary in _feats:
		_add("feat:" + String(f.id), "Game features", "", tr(String(f.title)), _feat_text(f))


func _add(id: String, group: String, sub: String, title: String, text: String) -> void:
	var page := {"id": id, "group": group, "sub": sub, "title": title,
		"text": "[font_size=22][color=%s]%s[/color][/font_size]\n%s" % [HEAD, title, text]}
	page["find"] = (title + "\n" + plain(text)).to_lower()
	pages.append(page)
	by_id[id] = page


## The ids of the pages that match a search, best first: the title starting with it, then the title
## holding it, then the text holding it. Every word of the search must be found.
func search(q: String) -> Array:
	var words := q.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return pages.map(func(p): return p.id)
	var ranked := [[], [], []]
	for p: Dictionary in pages:
		if p.id == "home":
			continue
		var title := String(p.title).to_lower()
		var all := true
		for w in words:
			if not String(p.find).contains(w):
				all = false
				break
		if not all:
			continue
		var whole := " ".join(words)
		if title.begins_with(whole):
			ranked[0].append(p.id)
		elif title.contains(whole):
			ranked[1].append(p.id)
		else:
			ranked[2].append(p.id)
	return ranked[0] + ranked[1] + ranked[2]


## BBCode without its tags.
static func plain(t: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(t, "", true)


# ---------------------------------------------------------------- pieces

func link(id: String, text: String) -> String:
	return "[url=%s][color=%s]%s[/color][/url]" % [id, LINK, text]


func _bld_link(id: String) -> String:
	return link("bld:" + id, tr(String(GameData.bld.get(id, {}).get("name", id)))) if GameData.bld.has(id) else id


func _res_link(id: String) -> String:
	return link("res:" + id, tr(GameData.res_name(id))) if GameData.res_by_id.has(id) else id


func _tech_link(id: String) -> String:
	return link("tech:" + id, tr(GameData.tech_name(id))) if GameData.techs.has(id) or GameData.reps.has(id) else id


func _age_link(a: int) -> String:
	return link("age:%d" % a, tr(GameData.age_name(a)))


func _feat_link(id: String) -> String:
	for f: Dictionary in _feats:
		if String(f.id) == id:
			return link("feat:" + id, tr(String(f.title)))
	return id


## "Logs ×1, Stone ×2" with each good a link.
func _goods(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in d:
		var n = d[k]
		var amount := str(int(n)) if float(n) == floorf(float(n)) else "%.1f" % float(n)
		parts.append("%s ×%s" % [_res_link(String(k)), amount])
	return ", ".join(parts)


func _list(ids: Array, f: Callable) -> String:
	return ", ".join(PackedStringArray(ids.map(f)))


## A line with a label: "[color=dim]Cost:[/color] ...".
func _row(label: String, value: String) -> String:
	return "[color=%s]%s[/color] %s\n" % [DIM, tr(label), value]


## The effects of a tech, age bonus or wonder, each part translated on its own.
func effects(eff: Dictionary) -> String:
	var txt := GameData.effect_text(eff)
	if txt == "":
		return ""
	var parts := PackedStringArray()
	for part in txt.split(", "):
		parts.append(tr(part))
	return ", ".join(parts)


func _feature_note(d: Dictionary) -> String:
	var f := String(d.get("feature", ""))
	return ("\n" + _row("Only with the game feature:", _feat_link(f))) if f != "" else ""


static func _class_name(c: String) -> String:
	match c:
		"peasant": return "Peasants"
		"artisan": return "Artisans"
		"noble": return "Nobles"
		"soldier": return "Soldiers"
		"scout": return "Scouts"
	return c.capitalize()


# ---------------------------------------------------------------- pages

func _home_text() -> String:
	var t := tr("Every building, good, tech, age, law and game feature has a page here, written from the game's own data, so it is always up to date (mods included).") + "\n\n"
	t += tr("Type in the search box to find a page by its name or by any word on it. Gold words are links: click one to go to its page, and Back to return.") + "\n\n"
	t += tr("The question mark in a building's info box opens that building's page.") + "\n\n"
	for g in GROUPS:
		var n := pages.filter(func(p): return p.group == g).size()
		t += "• " + tr("%s: %d pages" % [g, n]) + "\n"
	return t


func _bld_text(id: String) -> String:
	var d: Dictionary = GameData.bld[id]
	var t := ""
	if String(d.get("info", "")) != "":
		t += "[i]%s[/i]\n\n" % tr(String(d.info))
	var cat := String(d.get("cat", ""))
	for c in GameData.CATEGORIES:
		if String(c[0]) == cat:
			t += _row("Kind:", tr(String(c[1])))
	t += _row("Size:", tr(String(Sim.SIZE_NAMES.get(String(d.get("size", "small")), "Small"))))
	if not (d.get("cost", {}) as Dictionary).is_empty():
		t += _row("Cost:", _goods(d.cost))
	if int(d.get("time", 0)) > 0:
		t += _row("Build time:", tr("%d s" % int(d.time)))
	if d.has("tech"):
		t += _row("Needs the tech:", _tech_link(String(d.tech)))
	if d.has("worker"):
		var who := tr(_class_name(String(d.worker)))
		var tr_id := GameData.trade(id)
		if GameData.trades.has(tr_id):
			who += " (%s)" % tr(GameData.trade_name(tr_id))
		t += _row("Worker:", who)
		var tool := GameData.tool_for(tr_id)
		if tool != "":
			t += _row("New workers need:", _res_link(tool))
	var ins: Dictionary = d.get("in", {})
	var outs: Dictionary = d.get("out", {})
	if d.has("cycle") and (not ins.is_empty() or not outs.is_empty()):
		var cyc := tr("%d s" % int(d.cycle))
		if not ins.is_empty() and not outs.is_empty():
			t += _row("Work:", tr("every %s: %s into %s") % [cyc, _goods(ins), _goods(outs)])
		elif not outs.is_empty():
			t += _row("Work:", tr("every %s it makes %s") % [cyc, _goods(outs)])
		else:
			t += _row("Work:", tr("every %s it uses %s") % [cyc, _goods(ins)])
	if int(d.get("housing", 0)) > 0:
		t += _row("Homes:", tr("%d people" % int(d.housing)))
	if int(d.get("store", 0)) > 0:
		t += _row("Store:", tr("up to %d of each good" % int(d.store)))
	if int(d.get("garrison", 0)) > 0:
		t += _row("Garrison:", tr("%d soldiers" % int(d.garrison)))
	if int(d.get("radius", 0)) > 0:
		t += _row("Claims land:", tr("%d tiles around" % int(d.radius)))
	if d.has("upgrade_to"):
		var ups = d.upgrade_to
		var up_list: Array = ups if ups is Array else [ups]
		t += _row("Can be upgraded to:", _list(up_list, func(u): return _bld_link(String(u))))
	var from := []
	for o: String in GameData.bld:
		var u = GameData.bld[o].get("upgrade_to", [])
		if (u is Array and (u as Array).has(id)) or (u is String and u == id):
			from.append(o)
	if not from.is_empty():
		t += _row("Upgraded from:", _list(from, func(u): return _bld_link(String(u))))
	t += _health_lines(id)
	var users := []
	for o in outs:
		for o2: String in GameData.bld:
			if (GameData.bld[o2].get("in", {}) as Dictionary).has(o) and not users.has(o2):
				users.append(o2)
	if not users.is_empty():
		t += "\n" + _row("Its goods go to:", _list(users, func(u): return _bld_link(String(u))))
	return t + _feature_note(d)


## What data/health.json says about a building: the smoke it makes, the smoke it takes away, the water.
func _health_lines(id: String) -> String:
	if _health.is_empty():
		return ""
	var age := _age_link(int(_health.get("from_age", 6)))
	var t := ""
	var smog: Dictionary = _health.get("smog", {})
	if smog.has(id):
		t += _row("Smoke:", tr("from the %s age on, it fills the homes within %d tiles with smoke (strength %d%%)") % [age, int(_health.get("smog_radius", 6)), roundi(float(smog[id]) * 100.0)])
	var cl: Dictionary = _health.get("cleaners", {})
	if cl.has(id):
		t += _row("Clean air:", tr("from the %s age on, it takes away %d%% of the smoke of the homes within %d tiles") % [age, roundi(float(cl[id].get("clean", 0.5)) * 100.0), int(cl[id].get("radius", 7))])
	var wa: Dictionary = _health.get("water", {})
	if wa.has(id):
		t += _row("Clean water:", tr("for the homes within %d tiles, while it works") % int(wa[id].get("radius", 10)))
	if t != "":
		t += _row("See:", _feat_link("factory_health"))
	return t


func _res_text(id: String) -> String:
	var r: Dictionary = GameData.res_by_id[id]
	var t := ""
	if String(r.get("info", "")) != "":
		t += "[i]%s[/i]\n\n" % tr(String(r.info))
	if r.has("food"):
		t += _row("Food:", tr("people eat it; one is worth %d%% of a plain meal" % roundi(float(r.food) * 100.0)))
	if r.has("tool"):
		t += _row("Tool:", tr("new %s need one; it wears out with use") % tr(GameData.trade_plural(String(r.tool))))
	var makers := []
	var users := []
	var builds := []
	for b: String in GameData.bld:
		var d: Dictionary = GameData.bld[b]
		if (d.get("out", {}) as Dictionary).has(id):
			makers.append(b)
		if (d.get("in", {}) as Dictionary).has(id):
			users.append(b)
		if (d.get("cost", {}) as Dictionary).has(id):
			builds.append(b)
	if not makers.is_empty():
		t += _row("Made by:", _list(makers, func(u): return _bld_link(String(u))))
	if not users.is_empty():
		t += _row("Used by:", _list(users, func(u): return _bld_link(String(u))))
	if not builds.is_empty():
		if builds.size() <= 12:
			t += _row("Building material for:", _list(builds, func(u): return _bld_link(String(u))))
		else:
			t += _row("Building material for:", tr("%d kinds of building" % builds.size()))
	var want := []
	for c: String in GameData.needs:
		for k: String in GameData.needs[c]:
			if Array(GameData.need_options(k)).has(id) and not want.has(c):
				want.append(c)
	if not want.is_empty():
		t += _row("Wanted at home by:", _list(want, func(c): return tr(_class_name(String(c)))))
	var lux := []
	for c: String in GameData.luxury:
		if (GameData.luxury[c] as Dictionary).has(id):
			lux.append(c)
	if not lux.is_empty():
		t += _row("A luxury for:", tr("%s (each kept raises the taxes they pay)") % _list(lux, func(c): return tr(_class_name(String(c)))))
	if makers.is_empty() and users.is_empty() and builds.is_empty() and want.is_empty() and lux.is_empty() and not r.has("food"):
		t += tr("No building makes or uses it in this game's data.") + "\n"
	return t + _feature_note(r)


func _tech_text(id: String) -> String:
	var d: Dictionary = GameData.techs[id]
	var a := int(d.get("age", 0))
	var t := ""
	if String(d.get("info", "")) != "":
		t += "[i]%s[/i]\n\n" % tr(String(d.info))
	t += _row("Age:", _age_link(a))
	for ln in GameData.lanes:
		if String(ln[0]) == String(d.get("lane", "")):
			t += _row("Branch:", tr(String(ln[1])))
	t += _row("Cost:", tr("%d research points" % int(d.get("cost", 0))))
	var fx := effects(d.get("effects", {}))
	if fx != "":
		t += _row("Effects:", "[color=%s]%s[/color]" % [GOOD, fx])
	var req: Array = d.get("requires", [])
	t += _row("Needs:", _list(req, func(r): return _tech_link(String(r))) if not req.is_empty() else tr("nothing else in its age"))
	if d.get("gate", false):
		t += _row("Opens:", tr("the %s age; it needs %d techs of the %s age first") % [_age_link(a), int(d.get("need", 0)), _age_link(a - 1)])
	var kids := []
	for k: String in GameData.techs:
		if (GameData.techs[k].get("requires", []) as Array).has(id):
			kids.append(k)
	if not kids.is_empty():
		t += _row("Leads to:", _list(kids, func(k): return _tech_link(String(k))))
	var ub := GameData.unlocks(id)
	if not ub.is_empty():
		t += _row("New buildings:", _list(ub, func(b): return _bld_link(String(b))))
	if d.get("final", false):
		t += "\n" + tr("With research victory on, the first realm to finish it wins the game.") + "\n"
	return t + _feature_note(d)


func _rep_text(id: String) -> String:
	var d: Dictionary = GameData.reps[id]
	var t := ""
	if String(d.get("info", "")) != "":
		t += "[i]%s[/i]\n\n" % tr(String(d.info))
	t += _row("Age:", _age_link(int(d.get("age", 0))))
	t += _row("Cost:", tr("%d research points" % int(d.get("cost", 0))))
	var fx := effects(d.get("effects", {}))
	if fx != "":
		t += _row("Each level:", "[color=%s]%s[/color]" % [GOOD, fx])
	t += _row("Levels:", tr("%d; each one costs half the first again" % int(d.get("max", 1))))
	t += "\n" + tr("Mastery studies open when your realm enters their age.") + "\n"
	return t


func _age_text(a: int) -> String:
	var t := _row("Age:", tr("%d of %d" % [a + 1, GameData.ages.size()]))
	if a == 0:
		t += tr("Every game starts in the Bronze Age.") + "\n"
	var gate := GameData.gate_of(a)
	if gate != "":
		t += _row("Opened by the study:", _tech_link(gate))
	if a + 1 < GameData.ages.size():
		t += _row("Next:", _age_link(a + 1))
	var opts: Array = GameData.age_bonuses.get(str(a), [])
	if not opts.is_empty():
		t += "\n" + tr("On entering it, your realm picks one of these:") + "\n"
		for o: Dictionary in opts:
			t += "• [b]%s[/b]: [color=%s]%s[/color]. %s\n" % [tr(String(o.get("name", ""))), GOOD, effects(o.get("effects", {})), tr(String(o.get("info", "")))]
	var ts := []
	var bs := []
	for id: String in GameData.techs:
		if int(GameData.techs[id].get("age", 0)) == a:
			ts.append(id)
			for b in GameData.unlocks(id):
				if not bs.has(b):
					bs.append(b)
	if not ts.is_empty():
		t += "\n" + _row(tr("Techs (%d):" % ts.size()), _list(ts, func(k): return _tech_link(String(k))))
	if not bs.is_empty():
		t += _row("New buildings:", _list(bs, func(b): return _bld_link(String(b))))
	if not _health.is_empty() and a == int(_health.get("from_age", 6)):
		t += "\n" + _row("New troubles:", _feat_link("factory_health"))
	return t


func _law_text(l: Dictionary) -> String:
	var t := ""
	if String(l.get("info", "")) != "":
		t += "[i]%s[/i]\n\n" % tr(String(l.info))
	var fx = LawsScript.new()
	var def := String(l.get("default", ""))
	for o: Dictionary in l.get("options", []):
		var name := tr(String(o.get("name", "")))
		if String(o.id) == def:
			name += " " + tr("(usual, changes nothing)")
		t += "• [b]%s[/b]: %s\n" % [name, fx.effect_text(o)]
	t += "\n" + tr("A law can be changed again %d s after its last change." % int(LawsScript.CHANGE_WAIT)) + "\n"
	t += tr("Laws are set in the Laws window (F8). Rivals choose theirs by their character.") + "\n"
	t += _row("See:", _feat_link("laws"))
	return t


func _feat_text(f: Dictionary) -> String:
	var t := "[i]%s[/i]\n\n" % tr(String(f.info))
	t += _row("At first:", tr("on") if f.default_on else tr("off"))
	t += tr("Game features are turned on or off for a new game, and in Settings.") + "\n"
	if bool(f.get("mod", false)):
		t += tr("This feature comes from a mod.") + "\n"
	var blds := []
	for b: String in GameData.bld:
		if String(GameData.bld[b].get("feature", "")) == String(f.id):
			blds.append(b)
	if not blds.is_empty():
		t += _row("Its buildings:", _list(blds, func(b): return _bld_link(String(b))))
	if String(f.id) == "factory_health" and not _health.is_empty():
		t += "\n" + _row("From:", tr("the %s age") % _age_link(int(_health.get("from_age", 6))))
		var smog: Dictionary = _health.get("smog", {})
		t += _row("Smoky buildings:", _list(smog.keys(), func(b): return _bld_link(String(b))))
		t += tr("Every workshop with a steam engine smokes too. Smoke reaches homes within %d tiles and thins with distance." % int(_health.get("smog_radius", 6))) + "\n"
		var cl: Dictionary = _health.get("cleaners", {})
		if not cl.is_empty():
			t += _row("Clean the air:", _list(cl.keys(), func(b): return _bld_link(String(b))))
		var wa: Dictionary = _health.get("water", {})
		if not wa.is_empty():
			t += _row("Clean water:", _list(wa.keys(), func(b): return _bld_link(String(b))))
		var nd: Dictionary = _health.get("needs", {})
		for c: String in nd:
			var wants := PackedStringArray()
			for w in nd[c]:
				wants.append(tr("clean water") if String(w) == "water" else tr("a park nearby"))
			t += _row(tr("%s want:" % tr(_class_name(c))), ", ".join(wants))
		t += "\n" + tr("Poor health slows work, brings fevers and dysentery, and below half some people die of it.") + "\n"
	if String(f.id) == "laws":
		t += _row("The laws:", _list(LawsScript.law_list(), func(l): return link("law:" + String(l.id), tr(String(l.get("name", ""))))))
	return t
