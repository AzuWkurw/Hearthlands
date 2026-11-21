class_name SimPeople
extends RefCounted
## People: housing, jobs and specialists, homes where people wait, people walking to work and soldiers to their posts, needs and food.
## Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `sim` (sim.gd keeps a one-line wrapper for each, so callers did
## not change).

var sim: Sim


func _init(p_sim: Sim) -> void:
	sim = p_sim


func housing(p: Sim.Player) -> int:
	var c := 0
	for b in sim.realm_blds(p):
		if b.state == "ready":
			c += int(b.def.get("housing", 0))
	return int(c * (1.0 + sim.mod(p, "housing")))


func pop_total(p: Sim.Player) -> int:
	return p.peasant + p.artisan + p.noble


func soldiers(p: Sim.Player) -> int:
	var c := p.reserve
	for b in sim.realm_mil(p.id):
		c += b.garrison
	for a in sim.attacks:
		if a.p == p.id:
			c += a.n
	return c


func idle(p: Sim.Player, cls: String) -> int:
	return p.peasant - p.used_peasant if cls == "peasant" else p.artisan - p.used_artisan


func rate(p: Sim.Player, b: Sim.Bld) -> float:
	var r := p.prod if p.ai else 1.0
	if p.starve > 0:
		r *= 0.5
	if not sim._type_bonus.has(p.id):
		sim._type_bonus[p.id] = {}
	var tb: Dictionary = sim._type_bonus[p.id]
	var bonus: float
	if tb.has(b.ty):
		bonus = tb[b.ty]
	else:
		bonus = sim.mod(p, "speed:" + b.ty) + sim.mod(p, "speed:cat:" + String(b.def.get("cat", ""))) + sim.mod(p, "speed:all") + sim.mod(p, "speed:trade:" + GameData.trade(b.ty))
		tb[b.ty] = bonus
	for f: Feature in sim.features:
		bonus += f.speed_bonus(p, b)
	# spearmen are cheap and quick to train
	if p.age == 2 and String(b.def.get("train", "")) == "soldier":
		bonus += 0.3
	if String(b.def.get("worker", "")) == "artisan":
		r *= 1.0 + 0.25 * float(p.sat.artisan)
		bonus += sim.mod(p, "speed:worker:artisan")
	bonus += guild_bonus(p, b)
	return r * (1.0 + bonus) * (1.0 + Sim.LEVEL_BONUS * (Sim.level(b.wxp, Sim.WORKER_XP) - 1))


## Guilds (build 62): with the Guilds tech, GUILD_MIN or more working buildings of one trade within
## GUILD_R tiles of each other form a guild: each works GUILD_BONUS faster, GUILD_BIG with GUILD_LARGE or
## more. Farms, mines and the like count too; homes, stores and soldiers have no trade.
const GUILD_R := 8
const GUILD_MIN := 3
const GUILD_LARGE := 5
const GUILD_BONUS := 0.1
const GUILD_BIG := 0.15


## How many working buildings of b's trade stand within GUILD_R tiles of it, b counted (0 without a trade).
func guild_size(p: Sim.Player, b: Sim.Bld) -> int:
	var tr := GameData.trade(b.ty)
	if tr == "" or String(b.def.get("worker", "")) == "":
		return 0
	var n := 0
	# (build 76) only the realm's buildings of the same trade, not all of them: each workshop asks
	# when it starts a cycle, hundreds of times a game second on a big map
	var cells: Dictionary = _trade_blds(p, tr)
	for cy in range((b.y - GUILD_R) >> 4, ((b.y + GUILD_R) >> 4) + 1):
		for cx in range((b.x - GUILD_R) >> 4, ((b.x + GUILD_R) >> 4) + 1):
			var lst = cells.get(cx * 4096 + cy)
			if lst == null:
				continue
			for o: Sim.Bld in lst:
				if o.dead or o.state != "ready" or not o.staffed:
					continue
				if absi(o.x - b.x) > GUILD_R or absi(o.y - b.y) > GUILD_R:
					continue
				if (o.x - b.x) * (o.x - b.x) + (o.y - b.y) * (o.y - b.y) <= GUILD_R * GUILD_R and GameData.trade(o.ty) == tr:
					n += 1
	return n


var _gt_src := -2          # SimLogistics._pb_sv of the realm lists the index below was made from
var _gt: Array = []        # per realm: trade -> 16-tile map cell -> its buildings in realm_blds

func _trade_blds(p: Sim.Player, tr: String) -> Dictionary:
	sim.realm_blds(p)      # (made if missing)
	var src: Array = sim.logistics._pb
	# (the lists are made again every second, but hold the same buildings while no building came, went,
	# changed hands or changed kind: then the index stays)
	if int(sim.logistics._pb_sv) != _gt_src or _gt.size() != src.size():
		_gt_src = int(sim.logistics._pb_sv)
		_gt = []
		for lst: Array in src:
			var d := {}
			for o: Sim.Bld in lst:
				var t := GameData.trade(o.ty)
				if t == "":
					continue
				if not d.has(t):
					d[t] = {}
				var ck := (o.x >> 4) * 4096 + (o.y >> 4)
				var cd: Dictionary = d[t]
				if not cd.has(ck):
					cd[ck] = []
				(cd[ck] as Array).append(o)
			_gt.append(d)
	return (_gt[p.id - 1] as Dictionary).get(tr, {})


func guild_bonus(p: Sim.Player, b: Sim.Bld) -> float:
	if not p.techs.has("guilds"):
		return 0.0
	var n := guild_size(p, b)
	return GUILD_BIG if n >= GUILD_LARGE else (GUILD_BONUS if n >= GUILD_MIN else 0.0)


func staffing(p: Sim.Player) -> void:
	var ip := p.peasant - p.away
	var ia := p.artisan - (mini(p.keep_artisans, p.artisan) if p.ai else 0)
	var isc := p.scout - p.scout_out
	var mine := sim.realm_blds(p)
	p.tool_wait = {}
	# worn-out tools wait for new ones too (build 66)
	var tqf = sim.get_feature("tool_quality") if bool(sim.opts.tools) else null
	var held: Dictionary = tqf.held if tqf != null else {}
	var worn_check := not held.is_empty()
	# builders and workers go to high-priority buildings first, then normal, then low; paused get none;
	# within each priority, building types with a lower number in the worker priorities first (ties: as
	# they stood). (Build 78: sorted in one pass over the realm's buildings, which also counts the
	# worn-out tools; the order is the same as before.)
	var ordered: Array = []
	var ranked := not p.work_rank.is_empty()
	var bk := []
	bk.resize(40 if ranked else 4)
	for g in bk.size():
		bk[g] = []
	var any_prio := false
	var wr: Dictionary = p.work_rank
	for b: Sim.Bld in mine:
		if worn_check and b.worker > 0:
			var h = held.get(b.id)
			if h != null and float(h[0]) < 0.0:
				var t := sim.tool_of(b)
				if t != "":
					p.tool_wait[t] = int(p.tool_wait.get(t, 0)) + 1
		var pr := b.prio
		var g := 1
		if pr != Sim.PRIO_NORMAL:
			g = 0 if pr == Sim.PRIO_HIGH else (2 if pr == Sim.PRIO_LOW else (3 if pr == Sim.PRIO_PAUSED else 1))
			if g != 1:
				any_prio = true
		if ranked:
			(bk[g * 10 + clampi(int(wr.get(b.ty, 5)), 0, 9)] as Array).append(b)
		else:
			(bk[g] as Array).append(b)
	if not ranked and not any_prio:
		ordered = mine
	else:
		for row in bk:
			ordered.append_array(row)
	var sites := []
	var readies := []
	for b: Sim.Bld in ordered:
		if b.state == "build":
			sites.append(b)
		elif b.state == "ready":
			readies.append(b)
	for b: Sim.Bld in sites:
		if b.state == "build":
			b.staffed = b.prio != Sim.PRIO_PAUSED and ip > 0
			if b.staffed: ip -= 1
			# the builder walks from a store to the site before work starts; he leaves if taken off it
			if b.staffed and b.builder == 0 and not sim.creative(p):
				if send_from_home(b, p, "builder", "peasant"):
					b.builder = 1
			elif not b.staffed and b.builder != 0:
				b.builder = 0
	# one peasant kept free for the next building site (a setting), so a new site starts at once
	# instead of taking a worker from his job
	var spare := 0
	if p.spare_builder and ip > 0:
		ip -= 1
		spare = 1
	var lim_n := {}
	var limits: Dictionary = p.job_limit
	var any_lim := not limits.is_empty()
	var creative_p := sim.creative(p)
	for b: Sim.Bld in readies:
		if b.state != "ready":
			continue
		var wk := String(b.def.get("worker", ""))
		var was := b.staffed
		# the player's limit on how many of this kind get workers
		var lim_ok := true
		if any_lim and limits.has(b.ty):
			lim_ok = int(lim_n.get(b.ty, 0)) < int(limits[b.ty])
		if wk == "peasant":
			b.staffed = b.prio != Sim.PRIO_PAUSED and lim_ok and ip > 0 and (was or sim._can_hire(p, b))
			if b.staffed: ip -= 1
		elif wk == "artisan":
			b.staffed = b.prio != Sim.PRIO_PAUSED and lim_ok and ia > 0 and (was or sim._can_hire(p, b))
			if b.staffed: ia -= 1
		elif wk == "scout":
			b.staffed = b.prio != Sim.PRIO_PAUSED and isc > 0
			if b.staffed: isc -= 1
		elif wk == "" and b.def.has("in"):
			# a field depot, or a fort's gunpowder, needs nobody inside: carriers fill it unless it is paused
			b.staffed = b.prio != Sim.PRIO_PAUSED
			continue
		if b.staffed:
			b.need_tool = ""
			if wk != "" and any_lim:
				lim_n[b.ty] = int(lim_n.get(b.ty, 0)) + 1
		if was and not b.staffed:
			_release_worker(p, b)
		elif b.staffed and not was:
			_hire_worker(p, b)
		# a newly hired worker walks from his home; one who leaves goes home
		if b.staffed and b.worker == 0 and (wk == "peasant" or wk == "artisan" or wk == "scout"):
			if creative_p or send_from_home(b, p, "worker", wk):
				b.worker = 2 if creative_p else 1
		elif not b.staffed and b.worker != 0:
			b.worker = 0
	p.used_peasant = p.peasant - ip - spare
	p.used_artisan = p.artisan - ia
	# (build 73) a peasant whose workshop waits because the stores are full of what it makes helps the
	# carriers meanwhile: on a big realm the goods otherwise pile up while nobody carries them on
	var full := 0
	for b: Sim.Bld in readies:
		if b.staffed and b.state == "ready" and String(b.def.get("worker", "")) == "peasant" and b.msg.begins_with("Stores are full"):
			full += 1
	p.full_hands = full
	p.used_scout = p.scout - p.scout_out - isc
	_trim_specialists(p, "peasant", p.peasant - p.used_peasant - spare)
	_trim_specialists(p, "artisan", p.artisan - p.used_artisan)


## Sets building b's priority and hands out workers again at once, so the change shows straight away.
func set_priority(b: Sim.Bld, pr: int) -> void:
	b.prio = clampi(pr, Sim.PRIO_PAUSED, Sim.PRIO_HIGH)
	b.retry = 0.0
	b.fails = 0
	staffing(sim.players[b.p - 1])


## The key of the specialist pool for building b's workers: "class:trade".
func spec_key(b: Sim.Bld) -> String:
	return String(b.def.get("worker", "")) + ":" + GameData.trade(b.ty)


## Building b's worker leaves (no worker to spare, or the building is gone). Experience counts only
## in the trade he worked in, so he joins the idle workers as a specialist of that trade.
func _release_worker(p: Sim.Player, b: Sim.Bld) -> void:
	b.retry = 0.0
	if b.wxp >= Sim.WORKER_XP[1]:
		var key := spec_key(b)
		if not p.spec.has(key):
			p.spec[key] = []
		# he keeps his tool (build 66): kept beside him in spec_tool
		var tl := _spec_tools(p, key)
		(p.spec[key] as Array).append(b.wxp)
		tl.append(sim.arms.pack(b))
	b.wxp = 0.0
	b.tool_q = 0


## The tools of a trade's idle specialists, one for each in p.spec[key] (made up for older saves: the
## metal of the age, new).
func _spec_tools(p: Sim.Player, key: String) -> Array:
	var pool: Array = p.spec.get(key, [])
	if not p.spec_tool.has(key):
		p.spec_tool[key] = []
	var tl: Array = p.spec_tool[key]
	while tl.size() < pool.size():
		tl.push_front(float(sim.arms.default_tier(p)))
	while tl.size() > pool.size():
		tl.pop_front()
	return tl


## Building b gets a worker: the most experienced idle specialist of its trade if there is one,
## otherwise a newcomer who starts at level 1.
## (build 73) The tools that make the tools: without axes no charcoal, without pickaxes no ore, without
## tongs no metal, and so no new tools ever. When none is in store, a woodcutter, miner or smith starts
## with a makeshift one (counted as worn out: he works slowly and asks the toolsmith for a proper one),
## so a realm whose tools all wore out can make new ones instead of standing still for good.
const MAKESHIFT := ["axes", "pickaxes", "tongs"]


func _hire_worker(p: Sim.Player, b: Sim.Bld) -> void:
	b.wxp = 0.0
	var pool: Array = p.spec.get(spec_key(b), [])
	if pool.is_empty():
		# a newcomer: he takes his trade's tool from the stores, unless good tool care lets him make do
		var tool := sim.tool_of(b)
		var took := ""
		b.tool_q = 0
		if tool != "" and float(p.stock.get(tool, 0.0)) >= 1.0 and sim.rng.randf() >= sim.mod(p, "tool_save"):
			sim.take(p, tool, 1.0, sim.idx(b.x, b.y))
			sim.used(p, tool, 1.0)
			took = tool
			sim.arms.give_tool(b, sim.arms.take_best(p, tool))
		elif tool != "":
			# good tool care: he makes do with an old one of the age's metal (or, none in store, a
			# makeshift one: see MAKESHIFT)
			sim.arms.give_tool(b, sim.arms.default_tier(p))
		var makeshift := tool in MAKESHIFT and took == "" and float(p.stock.get(tool, 0.0)) < 1.0
		for f: Feature in sim.features:
			f.on_hire(p, b, took)
		if makeshift:
			b.tool_q = 0                          # no metal: nothing comes back as scrap
			var tqf = sim.get_feature("tool_quality")
			if tqf != null:
				tqf.held[b.id] = [-1.0, 0.0]      # worn from the start: slow, and he asks for a proper one
		return
	var best := 0
	for i in pool.size():
		if float(pool[i]) > float(pool[best]):
			best = i
	b.wxp = float(pool[best])
	var tl := _spec_tools(p, spec_key(b))
	if sim.tool_of(b) != "":
		sim.arms.unpack(b, float(tl[best]))
	else:
		b.tool_q = 0
	tl.remove_at(best)
	pool.remove_at(best)
	for f: Feature in sim.features:
		f.on_hire(p, b, "")


## There can't be more idle specialists than idle workers (some were trained into another class,
## starved, or took a job in a different trade). The least experienced lose their specialty first.
func _trim_specialists(p: Sim.Player, cls: String, idle_n: int) -> void:
	var all := []
	for key: String in p.spec:
		if key.begins_with(cls + ":"):
			for i in (p.spec[key] as Array).size():
				all.append([float(p.spec[key][i]), key])
	var extra := all.size() - maxi(0, idle_n)
	if extra <= 0:
		return
	all.sort_custom(func(a, c): return a[0] < c[0])
	for n in extra:
		var pool: Array = p.spec[all[n][1]]
		var tl := _spec_tools(p, String(all[n][1]))
		var i := pool.find(all[n][0])
		if i >= 0:
			pool.remove_at(i)
			tl.remove_at(i)


## How many workers of each trade a realm has, at work and idle, with their levels.
## Returns trade -> {"work": n, "idle": n, "levels": total level of those at work, "spec": specialists at work}.
func trade_summary(p: Sim.Player) -> Dictionary:
	var out := {}
	for b: Sim.Bld in sim.realm_blds(p):
		if b.state != "ready" or not b.staffed or not b.def.has("worker"):
			continue
		var t := GameData.trade(b.ty)
		if not out.has(t):
			out[t] = {"work": 0, "idle": 0, "levels": 0, "spec": 0}
		var lv := Sim.level(b.wxp, Sim.WORKER_XP)
		out[t].work += 1
		out[t].levels += lv
		if lv >= Sim.SPECIALIST:
			out[t].spec += 1
	for key: String in p.spec:
		var t2 := key.split(":")[1]
		if (p.spec[key] as Array).is_empty():
			continue
		if not out.has(t2):
			out[t2] = {"work": 0, "idle": 0, "levels": 0, "spec": 0}
		out[t2].idle += (p.spec[key] as Array).size()
	return out


## Whether building b's worker walks there from his home (not soldiers' buildings, nor stores).
func walks_to_work(b: Sim.Bld) -> bool:
	var wk := String(b.def.get("worker", ""))
	return wk == "peasant" or wk == "artisan" or wk == "scout"


## How many idle people of class cls building b holds at most (0: none wait there).
func home_cap(b: Sim.Bld, cls: String) -> int:
	if b.dead or b.state != "ready":
		return 0
	if b.ty == "hq":
		return 1 << 30
	var tr := String(b.def.get("train", ""))
	if tr != "":
		return 12 if tr == cls else 0
	if cls == "peasant" or cls == "artisan":
		return int(b.def.get("residence", b.def.get("housing", 0)))
	return 0


## Who waits where in realm p right now: {class: {building id: count}}, worked out once per tick.
func home_avail(p: Sim.Player) -> Dictionary:
	if int(sim._avail_at.get(p.id, -1)) == sim._ticks and sim._avail.has(p.id):
		return sim._avail[p.id]
	var idle_n := {"peasant": maxi(0, p.peasant - p.used_peasant), "artisan": maxi(0, p.artisan - p.used_artisan),
		"scout": maxi(0, p.scout - p.used_scout - p.scout_out), "soldier": maxi(0, p.reserve)}
	var trainers := []
	var homes := []
	for b in sim.realm_blds(p):
		if b.dead or b.state != "ready" or b.ty == "hq":
			continue
		if String(b.def.get("train", "")) != "":
			trainers.append(b)
		elif int(b.def.get("residence", b.def.get("housing", 0))) > 0:
			homes.append(b)
	var out := {"peasant": {}, "artisan": {}, "scout": {}, "soldier": {}}
	# the trained wait where they were trained
	for b: Sim.Bld in trainers:
		var cls := String(b.def.train)
		if out.has(cls) and int(idle_n[cls]) > 0:
			var n := mini(12, int(idle_n[cls]))
			out[cls][b.id] = n
			idle_n[cls] = int(idle_n[cls]) - n
	# lodges first (they are built to keep workers close to work), then homes; a home's room is shared
	homes.sort_custom(func(a: Sim.Bld, c: Sim.Bld): return (a.def.has("residence") and not c.def.has("residence")) or (a.def.has("residence") == c.def.has("residence") and a.id < c.id))
	for b: Sim.Bld in homes:
		var room := int(b.def.get("residence", b.def.get("housing", 0)))
		for cls in ["peasant", "artisan"]:
			var n := mini(room, int(idle_n[cls]))
			if n > 0:
				out[cls][b.id] = n
				idle_n[cls] = int(idle_n[cls]) - n
				room -= n
	if p.hq != null and not p.hq.dead:
		for cls in idle_n:
			if int(idle_n[cls]) > 0:
				out[cls][p.hq.id] = int(out[cls].get(p.hq.id, 0)) + int(idle_n[cls])
	sim._avail[p.id] = out
	sim._avail_at[p.id] = sim._ticks
	return out


## The nearest building by road from building b where someone of class cls waits: [home, road from b
## to it, walking time], or [] if none can be reached.
func nearest_home(p: Sim.Player, b: Sim.Bld, cls: String) -> Array:
	var avail: Dictionary = home_avail(p).get(cls, {})
	if avail.is_empty():
		return []
	sim._stamp += 1
	var st := sim._stamp
	var s := sim.idx(b.x, b.y)
	var hp := Sim.MinHeap.new()
	sim._gs[s] = 0.0; sim._came[s] = -1; sim._seen[s] = st
	hp.push(0.0, s)
	var nodes := 0
	while hp.size() > 0:
		var cur := hp.pop()
		if sim._closed[cur] == st:
			continue
		sim._closed[cur] = st
		if cur != s and sim.bmap[cur] != 0:
			var hb: Sim.Bld = sim.by_id.get(sim.bmap[cur])
			if hb != null and hb.p == p.id and int(avail.get(hb.id, 0)) > 0:
				var path := PackedInt32Array()
				var c := cur
				while c != -1:
					path.append(c)
					c = sim._came[c]
				path.reverse()
				return [hb, path, sim._gs[cur]]
			if not sim.logistics.is_store(hb):
				continue
		nodes += 1
		if nodes > 6000:
			break
		var cx := cur % sim.w
		var cy := cur / sim.w
		for dd in 4:
			var nx := cx + (1 if dd == 0 else (-1 if dd == 1 else 0))
			var ny := cy + (1 if dd == 2 else (-1 if dd == 3 else 0))
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var ni := ny * sim.w + nx
			if sim._closed[ni] == st or sim.owner[ni] != p.id:
				continue
			if sim.bmap[ni] != 0:
				var nb: Sim.Bld = sim.by_id.get(sim.bmap[ni])
				if nb == null or nb.p != p.id:
					continue
			elif sim.road[ni] != p.id:
				continue
			if not sim.links(cur, ni):
				continue
			var ng := sim._gs[cur] + sim.logistics.step_cost(cur, ni)
			if sim._seen[ni] != st or ng < sim._gs[ni]:
				sim._seen[ni] = st; sim._gs[ni] = ng; sim._came[ni] = cur
				hp.push(ng, ni)
	return []


## Someone of class cls walks from the nearest place he waits to building b: a "worker", "builder" or
## "soldier" (n: the soldier's kind). False when nobody can reach it.
func send_from_home(b: Sim.Bld, p: Sim.Player, kind: String, cls: String, n := 0) -> bool:
	var hm := nearest_home(p, b, cls)
	if hm.is_empty():
		return false
	var home: Sim.Bld = hm[0]
	var avail: Dictionary = home_avail(p)[cls]
	avail[home.id] = int(avail[home.id]) - 1
	if int(avail[home.id]) <= 0:
		avail.erase(home.id)
	var speed := 1.15 if kind == "soldier" else 1.0
	var t := Sim.Trip.new()
	t.p = p.id; t.kind = kind; t.res = "@" + kind; t.n = n; t.site = b.id
	t.t0 = sim.time; t.t1 = sim.time + float(hm[2]) / (speed * (1.0 + sim.mod(p, "carry"))) + 0.5; t.t2 = t.t1
	t.path = hm[1]
	sim.trips.append(t)
	return true


## A builder or soldier sets out from the nearest store to building b along the roads. False when
## no road leads there. n: the soldier's kind.
func send_walker(b: Sim.Bld, p: Sim.Player, kind: String, n: int) -> bool:
	var path := sim.logistics.store_path(b)
	if path.size() < 2:
		return false
	var speed := 1.15 if kind == "soldier" else 1.0
	var one_way := sim.logistics.net_dist(b.p, sim.idx(b.x, b.y)) / (speed * (1.0 + sim.mod(p, "carry")))
	var t := Sim.Trip.new()
	t.p = p.id; t.kind = kind; t.res = "@" + kind; t.n = n; t.site = b.id
	t.t0 = sim.time; t.t1 = sim.time + one_way + 0.5; t.t2 = t.t1
	t.path = path
	sim.trips.append(t)
	return true


## A builder or soldier reached his building. A builder starts work there. A soldier joins the
## garrison (the first one in claims the building's land); if the building is gone or was taken
## meanwhile, he goes back to the reserve.
func _walker_arrival(t: Sim.Trip, p: Sim.Player) -> void:
	var b: Sim.Bld = sim.by_id.get(t.site) if t.site != 0 else null
	if t.kind == "builder":
		if b != null and not b.dead and b.p == t.p and b.state == "build" and b.builder == 1:
			b.builder = 2
			b.retry = 0.0
		return
	if t.kind == "worker":
		if b != null and not b.dead and b.p == t.p and b.state == "ready" and b.worker == 1:
			b.worker = 2
			b.retry = 0.0
		return
	if b != null and b.p == t.p:
		b.walking = maxi(0, b.walking - 1)
	if b != null and not b.dead and b.p == t.p and b.state == "ready" and b.def.has("garrison"):
		b.sxp = Sim.mix_xp(b.sxp, b.garrison, p.res_xp, 1)
		if t.n >= 0:
			sim.gmix_of(b)[t.n] += 1
		b.garrison += 1
		b.sera = Sim.mix_avg(sim.gmix_of(b))
		if b.garrison == 1:
			sim.recompute_territory()
		return
	if p.alive:
		p.reserve += 1
		if t.n >= 0:
			sim.rmix_of(p)[t.n] += 1
		p.res_era = Sim.mix_avg(sim.rmix_of(p))


func mil_fill(p: Sim.Player) -> bool:
	var changed := false
	var order: Array = []
	for b: Sim.Bld in sim.realm_mil(p.id):
		if b.state == "ready" and b.def.has("garrison"):
			order.append(b)
	if p.border_first:
		# buildings near the border first (the list keeps its order within each group)
		var front := order.filter(func(x): return x.border)
		var back := order.filter(func(x): return not x.border)
		order = front + back
	for b: Sim.Bld in order:
		if b.def.get("needs_noble", false) and p.noble < 1:
			continue
		var cap := garrison_wanted(b)
		# soldiers leave the reserve and walk there along the roads; they join the garrison on arrival
		# (_walker_arrival), and an empty building claims its land only once the first one is in
		while b.garrison + b.walking < cap and p.reserve > (0 if b.garrison + b.walking == 0 else 2):
			var rm := sim.rmix_of(p)
			var best := _newest_allowed(b, rm)
			if best < 0 and b.garrison + b.walking > 0:
				break                       # no soldier of an allowed kind at headquarters
			if best < 0:
				best = Sim.mix_newest(rm)       # an empty building takes anyone rather than stand empty
			if not send_from_home(b, p, "soldier", "soldier", best) and not send_walker(b, p, "soldier", best):
				break                       # no road to it
			if best >= 0:
				rm[best] -= 1
			b.walking += 1; p.reserve -= 1
			p.res_era = Sim.mix_avg(sim.rmix_of(p))
		# the player's garrison settings: extra soldiers go home, kinds not wanted are swapped
		if b.want_n >= 0 or not b.want_kinds.is_empty() or b.garrison > cap:
			_garrison_settle(b, p, cap)
	return changed


## Soldiers building b should hold: the player's choice, at least 1, at most what it holds.
func garrison_wanted(b: Sim.Bld) -> int:
	var cap := int(b.def.get("garrison", 0))
	if b.want_n >= 0:
		return clampi(b.want_n, 1, cap)
	# buildings away from the border hold the share the realm has set (at least one soldier)
	var p := sim.players[b.p - 1]
	if not b.border and p.inner_pct < 100 and b.ty != "hq":
		return clampi(ceili(cap * p.inner_pct / 100.0), 1, cap)
	return cap


## Whether soldiers of kind k may serve in building b.
func kind_allowed(b: Sim.Bld, k: int) -> bool:
	return b.want_kinds.is_empty() or k >= b.want_kinds.size() or bool(b.want_kinds[k])


func _newest_allowed(b: Sim.Bld, m: Array) -> int:
	for k in range(m.size() - 1, -1, -1):
		if int(m[k]) > 0 and kind_allowed(b, k):
			return k
	return -1


## Sends extra soldiers back to headquarters (kinds not wanted first, then the oldest) and swaps
## kinds not wanted for wanted ones waiting at headquarters, one at a time.
func _garrison_settle(b: Sim.Bld, p: Sim.Player, want: int) -> void:
	var gm := sim.gmix_of(b)
	while b.garrison > want:
		var k := -1
		for kk in gm.size():
			if int(gm[kk]) > 0 and not kind_allowed(b, kk):
				k = kk; break
		if k < 0:
			k = Sim.mix_oldest(gm)
		if k < 0 or k >= gm.size():
			break
		gm[k] -= 1
		sim.rmix_of(p)[k] += 1
		p.res_xp = Sim.mix_xp(p.res_xp, p.reserve, b.sxp, 1)
		b.garrison -= 1; p.reserve += 1
	for kk in gm.size():
		if int(gm[kk]) > 0 and not kind_allowed(b, kk):
			var rm := sim.rmix_of(p)
			var j := _newest_allowed(b, rm)
			if j < 0:
				break
			gm[kk] -= 1; rm[kk] += 1
			rm[j] -= 1; gm[j] += 1
			break
	b.sera = Sim.mix_avg(sim.gmix_of(b))
	p.res_era = Sim.mix_avg(sim.rmix_of(p))


func update_needs(p: Sim.Player) -> void:
	for cls in GameData.needs:
		var count := p.artisan if cls == "artisan" else (p.noble if cls == "noble" else (p.peasant if cls == "peasant" else soldiers(p)))
		var list: Dictionary = GameData.needs[cls]
		var ok := 0
		for res in list:
			var key := String(cls) + ":" + String(res)
			var m := float(p.need_meter.get(key, 0.0)) + count * float(list[res]) * maxf(0.3, 1.0 + sim.mod(p, "need"))
			if m >= 1.0:
				m -= 1.0
				# "wine|beer" means either will do: the first one in store is used
				for alt in String(res).split("|"):
					if float(p.stock.get(alt, 0.0)) >= 1.0:
						sim.take(p, alt, 1.0)
						sim.used(p, alt, 1.0)
						p.need_ok[key] = 90.0
						break
			p.need_meter[key] = m
			var left := float(p.need_ok.get(key, 0.0)) - 1.0
			p.need_ok[key] = left
			if left > 0.0:
				ok += 1
		p.sat[cls] = float(ok) / maxf(1.0, list.size()) if count > 0 else 0.0
	# luxuries: not needed, but every kind the nobles have had in the last 90 seconds raises their tax
	p.lux = 0
	for cls in GameData.luxury:
		var count2 := p.artisan if cls == "artisan" else (p.noble if cls == "noble" else p.peasant)
		var ll: Dictionary = GameData.luxury[cls]
		for res in ll:
			var key := "lux:" + String(cls) + ":" + String(res)
			var m := float(p.need_meter.get(key, 0.0)) + count2 * float(ll[res])
			if m >= 1.0:
				m -= 1.0
				if float(p.stock.get(res, 0.0)) >= 1.0:
					sim.take(p, String(res), 1.0)
					sim.used(p, String(res), 1.0)
					p.need_ok[key] = 90.0
			p.need_meter[key] = m
			var left := float(p.need_ok.get(key, 0.0)) - 1.0
			p.need_ok[key] = left
			if left > 0.0 and cls == "noble":
				p.lux += 1


func food_total(p: Sim.Player) -> float:
	var t := 0.0
	for f in GameData.food_ids:
		t += float(p.stock[f])
	return t


## Takes the cheapest food item. Returns its food value, or 0 if there is none.
func take_food(p: Sim.Player, at := -1) -> float:
	for f in GameData.food_ids:
		if p.stock[f] >= 1.0:
			if sim.logistics.take(p, f, 1.0, at) < 1.0:
				continue
			sim.used(p, f, 1.0)
			return GameData.food_value(f)
	return 0.0


# ---------------------------------------------------------------- families (build 53)
## Families have children: while there is food and room in the homes, every grown person adds BIRTH
## of a child a minute. A child eats a little, takes half a place in a home and grows up after GROW
## seconds: with a school at work (a teacher, and bread for the pupils' lunch) it comes out an artisan
## (while there are at least twice as many peasants), otherwise a peasant.
const BIRTH := 0.006
const GROW := 300.0


func families(p: Sim.Player) -> void:
	var adults := p.peasant + p.artisan + p.noble
	if p.starve == 0 and sim.food_total(p) >= 10.0 + pop_total(p) * 0.2 and pop_total(p) + p.kids.size() / 2 < housing(p):
		p.born += adults * BIRTH / 60.0
		if p.born >= 1.0:
			p.born -= 1.0
			p.kids.append(sim.time)
	while not p.kids.is_empty() and sim.time - float(p.kids[0]) >= GROW:
		p.kids.pop_front()
		var sc := _school_with_lunch(p)
		if sc != null and p.peasant >= (p.artisan + 1) * 2:
			p.artisan += 1
			p.schooled += 1
			if not p.ai:
				sim.emit_log("A child finished school and became an artisan.", Color("86ad5c"), Vector2i(sc.x, sc.y))
		else:
			p.peasant += 1


## A school of realm p at work with bread for a pupil's lunch (the bread is eaten), or null.
func _school_with_lunch(p: Sim.Player) -> Sim.Bld:
	for b: Sim.Bld in sim.realm_blds(p):
		if b.ty != "school" or b.dead or b.state != "ready" or not b.staffed:
			continue
		if int(b.inbuf.get("bread", 0)) >= 1:
			b.inbuf["bread"] = int(b.inbuf["bread"]) - 1
			if int(b.inbuf["bread"]) <= 0:
				b.inbuf.erase("bread")
			sim.used(p, "bread", 1.0)
			return b
	return null


## Children at school age (the older half) and all children, for the side panel.
func kids_text(p: Sim.Player) -> String:
	if p.kids.is_empty():
		return "none yet"
	var older := 0
	for t in p.kids:
		if sim.time - float(t) >= GROW * 0.5:
			older += 1
	return "%d (%d of school age)" % [p.kids.size(), older]
