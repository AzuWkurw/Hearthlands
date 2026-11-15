extends Feature
## Random events: every four to seven minutes something happens to each realm, good or bad: a bumper
## harvest, rats in the granary, a fire, a mine collapse, a travelling merchant, refugees, a festival,
## a lucky find, wolves, a skilled newcomer, storm damage, bandits, a wandering scholar, an epidemic.
## Rivals get them too. Switch them off in Settings > Game features ("Random events"); each event can
## also be switched off on its own in the Events list window (F6).

const FIRST := 300.0
const GAP := [240.0, 420.0]
const CROPS := ["farm", "orchard", "hop_farm", "vineyard", "flax_farm", "herb_garden", "mulberry_grove", "pepper_garden", "coffee_plantation"]
## id: [name, weight, good?]
const EVENTS := {
	"harvest": ["Bumper harvest", 3.0, true],
	"rats": ["Rats in the granary", 2.0, false],
	"fire": ["Fire", 2.0, false],
	"collapse": ["Mine collapse", 1.5, false],
	"merchant": ["Travelling merchant", 2.5, true],
	"refugees": ["Refugees", 2.0, true],
	"festival": ["Festival", 2.0, true],
	"find": ["Lucky find", 2.0, true],
	"wolves": ["Wolves", 1.5, false],
	"master": ["Skilled newcomer", 2.0, true],
	"storm": ["Storm damage", 1.5, false],
	"bandits": ["Bandits", 1.5, false],
	"scholar": ["Wandering scholar", 2.0, true],
	"epidemic": ["Epidemic", 1.0, false],
	# events that ask you to choose (rivals choose at once)
	"pilgrims": ["Pilgrims at the gate", 1.5, true],
	"comet": ["A comet", 1.0, true],
	"grumbling": ["Grumbling over taxes", 1.2, false],
	"strange_ship": ["A strange ship", 1.0, true],
	# disasters that ask you to choose (build 55)
	"great_fire": ["A great fire", 0.8, false],
	"plague": ["Plague in the land", 0.6, false],
	"revolt": ["Peasant revolt", 1.0, false],
}

## The events that ask for a choice: what happened, and the answers [label, what it does].
const CHOICES := {
	"pilgrims": ["A band of pilgrims on their way to a distant shrine asks for food and shelter.",
		[["Take them in (10 food)", "Some may stay as peasants."], ["Ask a toll and let them pass", "A little gold."], ["Send them on", "Nothing happens."]]],
	"comet": ["A comet with a fiery tail hangs over the realm, and the people whisper of omens.",
		[["Hold a day of prayers (10 candles or beer)", "All work faster for 2 minutes."], ["Let the scholars study it", "Research points."], ["Tell the people it means nothing", "Uneasy people work slower for a minute."]]],
	"grumbling": ["The peasants grumble that the lords' taxes are too heavy.",
		[["Ease the taxes for a while (15 gold)", "Content people work faster for 2 minutes."], ["Send soldiers to keep order (needs a soldier in reserve)", "Calm returns."], ["Do nothing", "Work goes slower for 2 minutes."]]],
	"strange_ship": ["A ship from far away anchors off your coast. Its sailors look pale and some are coughing, but its hold is full of goods.",
		[["Let them land and trade", "Rare goods, but maybe sickness."], ["Turn them away", "Nothing happens."]]],
	"great_fire": ["A fire has broken out among your workshops, and the wind is fanning it toward the next roofs.",
		[["Everyone to the buckets", "The fire is put out at once, but all work stops for 40 seconds."], ["Pull down the burning building", "It is lost, but the fire spreads no further."], ["Leave it to the wells and fire stations", "Work goes on; the fire may spread."]]],
	"plague": ["Travellers bring word of plague in the towns beyond your borders. It will be at your gates soon.",
		[["Close the gates for 5 minutes", "No newcomers and no merchants for a while, but the plague stays out."], ["Send for healers (10 medicine)", "It comes, but the healers keep it small."], ["Carry on as usual", "Trade goes on; the plague comes in full."]]],
	"revolt": ["Hungry, tired and unhappy, the peasants have downed tools and gather outside the headquarters.",
		[["Give them a feast (20 bread, 10 beer)", "They go back content: all work faster for 2 minutes."], ["Send the soldiers (3 waiting at the headquarters)", "Order returns at once, but blood is spilled: a soldier and 2 peasants die."], ["Wait until they tire", "Work goes 30% slower for 2 minutes and 3 peasants leave."]]],
}
const CHOICE_WAIT := 120.0     # an unanswered question takes its last answer after this long (game seconds)

var next_t: Dictionary = {}      # realm id -> game time of its next event
var boosts: Array = []           # [realm id, what ("crops", "all", "hunter", "build"), bonus, until]
var blocked: Dictionary = {}     # building id -> [until, reason]
var off: Dictionary = {}         # event id -> true when switched off
var history: Array = []          # [time, realm id, event id, text] of the last events
var rng := RandomNumberGenerator.new()
var pending: Dictionary = {}     # realm id -> [event id, time asked]: a question waiting for your answer


func _init() -> void:
	id = "events"
	title = "Random events"
	info = "Every few minutes something happens to each realm: harvests, fires, merchants, refugees, rats, bandits and more. Each event can be switched off on its own (F6)."
	default_on = true


func on_start(loaded: bool) -> void:
	if not loaded or rng.seed == 0:
		rng.seed = (sim.seed_str + ":events").hash()
	for p: Sim.Player in sim.players:
		if not next_t.has(p.id):
			next_t[p.id] = maxf(sim.time, FIRST) + rng.randf_range(0.0, 120.0)
	# the player's choice of events, kept between games
	var cf := ConfigFile.new()
	if cf.load(Settings.PATH) == OK:
		var saved = cf.get_value("events", "off", {})
		if saved is Dictionary:
			off = saved


func on_second() -> void:
	for i in range(boosts.size() - 1, -1, -1):
		if sim.time >= float(boosts[i][3]):
			boosts.remove_at(i)
	for k in blocked.keys():
		if sim.time >= float(blocked[k][0]):
			blocked.erase(k)
	for pid in pending.keys():
		if sim.time - float(pending[pid][1]) > CHOICE_WAIT:
			var q: Array = pending[pid]
			var opts: Array = CHOICES[q[0]][1]
			answer(sim.players[int(pid) - 1], opts.size() - 1)
	for p: Sim.Player in sim.players:
		if not p.alive:
			continue
		if sim.time >= float(next_t.get(p.id, FIRST)):
			next_t[p.id] = sim.time + rng.randf_range(GAP[0], GAP[1])
			_happen(p)


func _crops(p: Sim.Player) -> int:
	var n := 0
	for b: Sim.Bld in sim.realm_blds(p):
		if b.ty in CROPS and b.state == "ready":
			n += 1
	return n


func _pick_bld(p: Sim.Player, ok: Callable) -> Sim.Bld:
	var c := []
	for b: Sim.Bld in sim.realm_blds(p):
		if b.state == "ready" and ok.call(b):
			c.append(b)
	if c.is_empty():
		return null
	return c[rng.randi() % c.size()]


## Which events can happen to realm p now.
func _possible(p: Sim.Player) -> Array:
	var out := []
	var food := 0.0
	for r in ["grain", "flour", "bread", "apples", "fish", "meat"]:
		food += float(p.stock.get(r, 0.0))
	var cl = sim.get_feature("seasons")
	for k: String in EVENTS:
		if off.get(k, false):
			continue
		var ok := true
		match k:
			"harvest": ok = _crops(p) > 0
			"rats": ok = food >= 15.0
			"collapse": ok = sim.realm_blds(p).any(func(b): return b.def.has("mine") and b.state == "ready")
			"refugees": ok = sim.housing(p) - sim.pop_total(p) >= 3 and sim.time >= p.gates_until
			"merchant": ok = sim.time >= p.gates_until
			"wolves": ok = sim.realm_blds(p).any(func(b): return b.ty in ["sheep_farm", "pig_farm", "dairy", "hunter"])
			"master": ok = sim.realm_blds(p).any(func(b): return b.staffed and b.cyc > 0.0)
			"storm": ok = cl != null and String(cl.weather[cl.biome_of(p)]) in ["storm", "blizzard"] and sim.realm_blds(p).any(func(b): return b.state == "build")
			"bandits": ok = float(p.stock.get("gold", 0.0)) >= 5.0
			"epidemic": ok = sim.feature_on("diseases") and sim.pop_total(p) >= 30
			"pilgrims": ok = food >= 20.0 and not pending.has(p.id) and sim.time >= p.gates_until
			"comet": ok = not pending.has(p.id)
			"grumbling": ok = p.noble > 0 and p.peasant >= 20 and not pending.has(p.id)
			"strange_ship": ok = p.age >= 3 and not pending.has(p.id) and sim.realm_blds(p).any(func(b): return b.ty in ["harbour", "fisher", "saltworks"])
			"great_fire":
				var fires = sim.get_feature("fires")
				ok = not pending.has(p.id) and fires != null and sim.realm_blds(p).filter(func(b): return b.state == "ready" and b.cyc > 0.0 and fires.flammable(b)).size() >= 8
			"plague": ok = not pending.has(p.id) and sim.feature_on("diseases") and sim.pop_total(p) >= 60 and sim.time > 20 * 60.0
			"revolt":
				var con = sim.get_feature("contentment")
				ok = not pending.has(p.id) and con != null and con.mood(p) < 0.4 and p.peasant >= 30 and sim.time > 15 * 60.0
		if ok:
			out.append(k)
	return out


func _happen(p: Sim.Player) -> void:
	var can := _possible(p)
	if can.is_empty():
		return
	var total := 0.0
	for k in can:
		total += float(EVENTS[k][1])
	var r := rng.randf() * total
	var pick: String = can[0]
	for k in can:
		r -= float(EVENTS[k][1])
		if r <= 0.0:
			pick = k
			break
	if CHOICES.has(pick):
		if p.ai:
			_answer(p, pick, _ai_answer(p, pick))
		else:
			pending[p.id] = [pick, sim.time]
			sim.emit_log("%s: %s Choose what to do." % [String(EVENTS[pick][0]), String(CHOICES[pick][0])], Color("e0c070"))
		return
	var text := _apply(p, pick)
	if text == "":
		return
	history.append([sim.time, p.id, pick, text])
	if history.size() > 60:
		history.pop_front()
	if not p.ai:
		var good: bool = EVENTS[pick][2]
		sim.emit_log("%s: %s" % [String(EVENTS[pick][0]), text], Color("a0d070") if good else Color("f0b070"))


func _apply(p: Sim.Player, k: String) -> String:
	match k:
		"harvest":
			boosts.append([p.id, "crops", 0.30, sim.time + 120.0])
			return "the fields are heavy with grain. Crops grow 30% faster for 2 minutes."
		"rats":
			var lost := 0
			for r in ["grain", "flour", "bread", "apples"]:
				var n := floorf(float(p.stock.get(r, 0.0)) * 0.15)
				if n > 0.0:
					n = sim.take(p, r, n)
					sim.used(p, r, n)
					lost += int(n)
			return "rats ate %d of your stored grain, flour, bread and apples." % lost
		"fire":
			var b := _pick_bld(p, func(b): return b.ty != "hq" and not sim.is_mil(b) and not sim.is_store(b) and b.cyc > 0.0)
			if b == null:
				return ""
			# with spreading fires on, it is a real fire (see fires.gd)
			var fires = sim.get_feature("fires")
			if fires != null and fires.flammable(b):
				fires.ignite(b)
				return "a fire broke out in the %s!" % String(b.def.name).to_lower()
			blocked[b.id] = [sim.time + 90.0, "Repairing fire damage"]
			var pl := minf(2.0, float(p.stock.get("planks", 0.0)))
			if pl > 0.0:
				pl = sim.take(p, "planks", pl, sim.idx(b.x, b.y))
				sim.used(p, "planks", pl)
			return "the %s caught fire. It stops for 90 seconds while it is repaired%s." % [String(b.def.name).to_lower(), (" with %d planks" % int(pl)) if pl > 0.0 else ""]
		"collapse":
			var b := _pick_bld(p, func(b): return b.def.has("mine"))
			if b == null:
				return ""
			blocked[b.id] = [sim.time + 120.0, "Clearing a collapsed tunnel"]
			return "a tunnel of the %s fell in. It stops for 2 minutes." % String(b.def.name).to_lower()
		"merchant":
			var gold := rng.randi_range(4, 10)
			var goods := ["iron", "salt", "cloth", "leather", "bricks"]
			# from the High Medieval age on, merchants bring a taste of the luxuries from far away
			if p.age >= 3:
				goods.append_array(["spices", "silk", "porcelain", "coffee"])
			var g: String = goods[rng.randi() % goods.size()]
			var n := rng.randi_range(3, 6)
			sim.give(p, "gold", gold)
			sim.give(p, g, n)
			sim.made(p, "gold", gold)
			sim.made(p, g, n)
			var txt := "a merchant paid %d gold for lodging and left %d %s" % [gold, n, GameData.res_name(g).to_lower()]
			# and buys from what you have most of (not food, tools or weapons), at four fifths of the market price
			var best := ""
			var most := 60.0
			for r in GameData.res_by_id:
				var rd: Dictionary = GameData.res_by_id[r]
				if rd.has("tool") or GameData.food_ids.has(r) or r in ["gold", "weapons", "armor"]:
					continue
				if float(p.stock.get(r, 0.0)) > most:
					most = float(p.stock.get(r, 0.0)); best = r
			if best != "":
				var nbuy := 10
				var pay := maxi(1, roundi(sim.market.price(best) * nbuy * 0.8))
				var got := sim.take(p, best, float(nbuy))
				if got >= 1.0:
					sim.give(p, "gold", pay)
					sim.made(p, "gold", pay)
					txt += ", and bought %d %s for %d gold" % [int(got), GameData.res_name(best).to_lower(), pay]
			return txt + "."
		"refugees":
			var n := mini(rng.randi_range(3, 6), sim.housing(p) - sim.pop_total(p))
			p.peasant += n
			return "%d refugees settled in your realm as peasants." % n
		"festival":
			boosts.append([p.id, "all", 0.10, sim.time + 90.0])
			return "a feast day lifts everyone's spirits. All work goes 10% faster for 90 seconds."
		"find":
			var what := "stone" if rng.randf() < 0.5 else "ore_iron"
			var n := rng.randi_range(4, 8)
			sim.give(p, what, n)
			sim.made(p, what, n)
			return "workers turned up %d %s." % [n, GameData.res_name(what).to_lower()]
		"wolves":
			var lost := []
			for r in ["meat", "wool"]:
				var n := minf(float(p.stock.get(r, 0.0)), float(rng.randi_range(2, 4)))
				if n > 0.0:
					n = sim.take(p, r, n)
					sim.used(p, r, n)
					lost.append("%d %s" % [int(n), GameData.res_name(r).to_lower()])
			boosts.append([p.id, "hunter", 0.25, sim.time + 120.0])
			return "wolves raided the farms%s. Hunters go after them: +25%% hunting for 2 minutes." % ((" and took " + ", ".join(lost)) if not lost.is_empty() else "")
		"master":
			var b := _pick_bld(p, func(b): return b.staffed and b.cyc > 0.0 and Sim.level(b.wxp, Sim.WORKER_XP) < 5)
			if b == null:
				return ""
			var lv := Sim.level(b.wxp, Sim.WORKER_XP)
			b.wxp = maxf(b.wxp, float(Sim.WORKER_XP[lv]))
			return "a skilled %s joined the %s: its worker is now level %d." % [GameData.trade_title(GameData.trade(b.ty)), String(b.def.name).to_lower(), lv + 1]
		"storm":
			boosts.append([p.id, "build", -0.5, sim.time + 60.0])
			return "the storm tore at the scaffolding. Construction goes at half speed for a minute."
		"bandits":
			var mil := sim.realm_blds(p).filter(func(b): return sim.is_mil(b) and b.state == "ready").size()
			if mil >= 4:
				return "bandits came, but your soldiers drove them off."
			var n := floorf(float(p.stock.gold) * 0.15)
			n = sim.take(p, "gold", n)
			sim.used(p, "gold", n)
			return "bandits stole %d gold. More military buildings would keep them away." % int(n)
		"scholar":
			var rp := 20.0 + sim.time / 60.0
			p.rp += rp
			p.rp_total += rp
			return "a wandering scholar shared his learning: +%d research points." % int(rp)
		"epidemic":
			var dz = sim.get_feature("diseases")
			if dz == null:
				return ""
			var kind: String = "flu" if rng.randf() < 0.6 else "dysentery"
			dz.outbreak(p, kind)
			return "travellers brought sickness with them."
	return ""


## The question waiting for realm p's answer: {id, title, text, options: [[label, hint]...], left}, or {}.
func question(p: Sim.Player) -> Dictionary:
	if not pending.has(p.id):
		return {}
	var k: String = pending[p.id][0]
	return {"id": k, "title": String(EVENTS[k][0]), "text": String(CHOICES[k][0]), "options": CHOICES[k][1],
		"left": maxf(0.0, CHOICE_WAIT - (sim.time - float(pending[p.id][1])))}


## Realm p answers its waiting question with option i.
func answer(p: Sim.Player, i: int) -> void:
	if not pending.has(p.id):
		return
	var k: String = pending[p.id][0]
	pending.erase(p.id)
	_answer(p, k, i)


func _ai_answer(p: Sim.Player, k: String) -> int:
	match k:
		"pilgrims": return 1
		"comet": return 1
		"grumbling": return 0 if float(p.stock.get("gold", 0.0)) >= 20.0 else (1 if p.reserve > 0 else 2)
		"strange_ship": return 1
		"great_fire": return 1
		"plague": return 1 if float(p.stock.get("medicine", 0.0)) >= 10.0 else 0
		"revolt": return 0 if float(p.stock.get("bread", 0.0)) >= 20.0 and float(p.stock.get("beer", 0.0)) >= 10.0 else (1 if p.reserve >= 3 else 2)
	return 0


func _answer(p: Sim.Player, k: String, i: int) -> void:
	var text := ""
	match k:
		"pilgrims":
			match i:
				0:
					var fed := 0
					for n in 10:
						if sim.take_food(p) > 0.0:
							fed += 1
					var stay := mini(2 + rng.randi() % 3, maxi(0, sim.housing(p) - sim.pop_total(p))) if fed >= 8 else 0
					p.peasant += stay
					text = "you fed the pilgrims (%d food)%s." % [fed, (" and %d of them stayed as peasants" % stay) if stay > 0 else ""]
				1:
					var g := 3 + rng.randi() % 4
					sim.give(p, "gold", g); sim.made(p, "gold", g)
					text = "the pilgrims paid %d gold to pass." % g
				_: text = "the pilgrims walked on."
		"comet":
			match i:
				0:
					var what := "candles" if float(p.stock.get("candles", 0.0)) >= 10.0 else ("beer" if float(p.stock.get("beer", 0.0)) >= 10.0 else "")
					if what != "":
						var got := sim.take(p, what, 10.0)
						sim.used(p, what, got)
						boosts.append([p.id, "all", 0.12, sim.time + 120.0])
						text = "a day of prayers (10 %s) lifts every heart: all work 12%% faster for 2 minutes." % what
					else:
						boosts.append([p.id, "all", -0.05, sim.time + 60.0])
						text = "there were no candles or beer for the prayers, and the people are uneasy: all work 5% slower for a minute."
				1:
					var rpts := 40.0 + 15.0 * maxi(0, p.age - 1)
					p.rp += rpts
					text = "your scholars measured the comet's path: %d research points." % roundi(rpts)
				_:
					boosts.append([p.id, "all", -0.05, sim.time + 60.0])
					text = "the people are uneasy: all work 5% slower for a minute."
		"grumbling":
			match i:
				0:
					if float(p.stock.get("gold", 0.0)) >= 15.0:
						var got := sim.take(p, "gold", 15.0)
						sim.used(p, "gold", got)
						boosts.append([p.id, "all", 0.06, sim.time + 120.0])
						text = "you eased the taxes (15 gold); the peasants work 6% faster for 2 minutes."
					else:
						boosts.append([p.id, "all", -0.10, sim.time + 120.0])
						text = "there was no gold to ease the taxes: work goes 10% slower for 2 minutes."
				1:
					if p.reserve > 0:
						text = "soldiers kept order; the grumbling stopped."
					else:
						boosts.append([p.id, "all", -0.10, sim.time + 120.0])
						text = "no soldiers to spare: work goes 10% slower for 2 minutes."
				_:
					boosts.append([p.id, "all", -0.10, sim.time + 120.0])
					text = "the grumbling spread: work goes 10% slower for 2 minutes."
		"great_fire":
			var fires = sim.get_feature("fires")
			var b := _pick_bld(p, func(bb): return bb.ty != "hq" and not sim.is_mil(bb) and not sim.is_store(bb) and bb.cyc > 0.0 and fires != null and fires.flammable(bb))
			if b == null or fires == null:
				text = "the fire burned out on its own."
			else:
				var nm := String(b.def.name).to_lower()
				match i:
					0:
						boosts.append([p.id, "all", -0.9, sim.time + 40.0])
						text = "everyone ran with buckets and the fire at the %s was put out; all work stopped for 40 seconds." % nm
					1:
						sim.destroy(b, "pulled down to stop a fire")
						text = "the burning %s was pulled down; the fire went no further." % nm
					_:
						fires.ignite(b)
						# the wind carries sparks to the nearest wooden roof
						var near: Sim.Bld = null
						var nd := 1e9
						for o: Sim.Bld in sim.realm_blds(p):
							if o != b and o.state == "ready" and fires.flammable(o):
								var d := Vector2(o.x - b.x, o.y - b.y).length()
								if d < nd:
									nd = d; near = o
						if near != null and nd <= 6.0:
							fires.ignite(near)
						text = "the %s is burning%s; the wells and fire stations fight it." % [nm, (" and sparks set the %s alight" % String(near.def.name).to_lower()) if near != null and nd <= 6.0 else ""]
		"plague":
			var dz = sim.get_feature("diseases")
			match i:
				0:
					p.gates_until = sim.time + 300.0
					text = "the gates are shut for 5 minutes: no newcomers, no merchants, and the plague stays out."
				1:
					if float(p.stock.get("medicine", 0.0)) >= 10.0 and dz != null:
						var got := sim.take(p, "medicine", 10.0)
						sim.used(p, "medicine", got)
						dz.outbreak(p, "plague")
						dz.cure(p, 6.0)
						text = "the healers came with 10 medicine: the plague came, but they kept it small."
					else:
						if dz != null:
							dz.outbreak(p, "plague"); dz.outbreak(p, "plague")
						text = "there was no medicine for the healers, and the plague came in full."
				_:
					if dz != null:
						dz.outbreak(p, "plague"); dz.outbreak(p, "plague")
					text = "trade went on, and the plague came in with it."
		"revolt":
			match i:
				0:
					if float(p.stock.get("bread", 0.0)) >= 20.0 and float(p.stock.get("beer", 0.0)) >= 10.0:
						sim.used(p, "bread", sim.take(p, "bread", 20.0))
						sim.used(p, "beer", sim.take(p, "beer", 10.0))
						boosts.append([p.id, "all", 0.08, sim.time + 120.0])
						text = "a feast of 20 bread and 10 beer: the peasants went back content, and all work 8% faster for 2 minutes."
					else:
						boosts.append([p.id, "all", -0.30, sim.time + 120.0])
						p.peasant = maxi(4, p.peasant - 3)
						text = "there was not enough bread and beer for a feast: work goes 30% slower for 2 minutes and 3 peasants left."
				1:
					if p.reserve >= 3:
						p.reserve -= 1
						Sim.mix_remove(sim.rmix_of(p), Sim.mix_pick(sim.rmix_of(p), rng))
						p.peasant = maxi(4, p.peasant - 2)
						boosts.append([p.id, "all", -0.05, sim.time + 120.0])
						text = "the soldiers broke up the crowd; a soldier and 2 peasants died, and the people work 5% slower for 2 minutes."
					else:
						boosts.append([p.id, "all", -0.30, sim.time + 120.0])
						p.peasant = maxi(4, p.peasant - 3)
						text = "there were not enough soldiers at the headquarters: work goes 30% slower for 2 minutes and 3 peasants left."
				_:
					boosts.append([p.id, "all", -0.30, sim.time + 120.0])
					p.peasant = maxi(4, p.peasant - 3)
					text = "the peasants tired at last: work went 30% slower for 2 minutes and 3 of them left."
		"strange_ship":
			if i == 0:
				var goods := ["spices", "silk", "porcelain", "coffee", "glass", "jewelry"]
				var g: String = goods[rng.randi() % goods.size()]
				var n := 6 + rng.randi() % 5
				sim.give(p, g, n); sim.made(p, g, n)
				text = "the sailors traded %d %s" % [n, GameData.res_name(g).to_lower()]
				if sim.feature_on("diseases") and rng.randf() < 0.5:
					var sick := _apply(p, "epidemic")
					text += "; but " + (sick if sick != "" else "some fell ill") 
				text += "."
			else:
				text = "the ship sailed on."
	history.append([sim.time, p.id, k, text])
	if history.size() > 60:
		history.pop_front()
	if not p.ai:
		sim.emit_log("%s: %s" % [String(EVENTS[k][0]), text], Color("a0d070"))


func _boost(p: Sim.Player, what: String) -> float:
	var s := 0.0
	for b in boosts:
		if int(b[0]) == p.id and b[1] == what:
			s += float(b[2])
	return s


func speed_bonus(p: Sim.Player, b: Sim.Bld) -> float:
	if boosts.is_empty():
		return 0.0
	var s := _boost(p, "all")
	if b.ty in CROPS:
		s += _boost(p, "crops")
	if b.ty == "hunter":
		s += _boost(p, "hunter")
	return s


func build_factor(p: Sim.Player, _b: Sim.Bld) -> float:
	if boosts.is_empty():
		return 1.0
	return maxf(0.2, 1.0 + _boost(p, "build"))


func work_block(_p: Sim.Player, b: Sim.Bld) -> String:
	if blocked.has(b.id):
		return String(blocked[b.id][1])
	return ""


func building_lines(b: Sim.Bld) -> PackedStringArray:
	if blocked.has(b.id):
		return PackedStringArray(["[color=#f0b070]%s: %d s left.[/color]" % [String(blocked[b.id][1]), ceili(float(blocked[b.id][0]) - sim.time)]])
	return PackedStringArray()


func panel_lines(p: Sim.Player) -> PackedStringArray:
	var bits := []
	for b in boosts:
		if int(b[0]) == p.id:
			var what := {"crops": "crops", "all": "all work", "hunter": "hunting", "build": "building"}[b[1]] as String
			bits.append("%s %+d%% (%d s)" % [what, roundi(float(b[2]) * 100.0), ceili(float(b[3]) - sim.time)])
	if bits.is_empty():
		return PackedStringArray()
	return PackedStringArray(["Events  " + ", ".join(bits)])


# ---------------------------------------------------------------- the events window (F6)

var _win: Window
var _box: VBoxContainer
var _main: Main


func build_ui(main: Main) -> void:
	_main = main
	main.add_feature_key(self, KEY_F6, _toggle)
	_win = main.add_feature_window(self, "Random events (F6)", Vector2i(520, 460))
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.95))
	_win.add_child(bg)
	var sc := ScrollContainer.new()
	bg.add_child(sc)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_box)


func _toggle() -> void:
	_win.visible = not _win.visible
	if _win.visible:
		_fill()


func _fill() -> void:
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(_main._label("Events that can happen (untick to switch one off):", 14, _main.BRASS))
	for k: String in EVENTS:
		var cb := CheckBox.new()
		cb.text = String(EVENTS[k][0]) + ("" if EVENTS[k][2] else "  (bad)")
		cb.button_pressed = not off.get(k, false)
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on):
			if on:
				off.erase(k)
			else:
				off[k] = true
			var cf := ConfigFile.new()
			cf.load(Settings.PATH)
			cf.set_value("events", "off", off)
			cf.save(Settings.PATH))
		_box.add_child(cb)
	_box.add_child(_main._label("Your recent events:", 14, _main.BRASS))
	var me := sim.human()
	var any := false
	for i in range(history.size() - 1, -1, -1):
		var h: Array = history[i]
		if int(h[1]) != me.id:
			continue
		any = true
		var l := _main._label(tr("%02d:%02d %s: %s") % [int(h[0]) / 60, int(h[0]) % 60, String(EVENTS[h[2]][0]), String(h[3])], 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(480, 0)
		_box.add_child(l)
	if not any:
		_box.add_child(_main._label("None yet. The first comes after about five minutes.", 13, _main.DIM))


func save_state() -> Dictionary:
	return {"next": next_t, "boosts": boosts, "blocked": blocked, "history": history, "rng": rng.state, "seed": rng.seed, "pending": pending}


func load_state(d: Dictionary) -> void:
	next_t = {}
	for k in d.get("next", {}):
		next_t[int(k)] = float(d.next[k])
	boosts = d.get("boosts", [])
	blocked = {}
	for k in d.get("blocked", {}):
		blocked[int(k)] = d.blocked[k]
	history = d.get("history", [])
	pending = {}
	for k in d.get("pending", {}):
		pending[int(k)] = d.pending[k]
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng", 0))
