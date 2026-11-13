class_name Places
extends RefCounted
## Neutral places a hand-made map can hold (set in the map editor):
## - Ruins: the first realm whose land reaches them finds what was left there (planks, stone, gold,
##   tools). Nothing can be built on the ruins themselves.
## - Bandit camps: nobody can build within 3 tiles of one, and every 90 seconds the bandits steal goods
##   from the nearest realm whose land comes within 8 tiles. A realm clears a camp by sending soldiers
##   from a military building within reach (click the camp); they fight the bandits one by one, and
##   whoever wins takes what the camp held. Rivals clear camps near them when they have soldiers to spare.
## Each place is a Dictionary in sim.places (saved with the game):
##   {kind: "ruins"|"bandits", x, y, done: looted or cleared, n: bandits left, raid_t, party: {} or
##    {p, src, n, mix, t0, t1}}

const LOOT := {"planks": 12, "stone": 12, "gold": 6, "axes": 1, "pickaxes": 1}
const CAMP_LOOT := {"gold": 10, "weapons": 3}
const BANDITS := 5
const BLOCK_R := 3
const RAID_R := 8
const RAID_EVERY := 90.0
const WALK := 1.0          # tiles a second
const BANDIT_WIN := 0.45   # a bandit's chance in each duel against a soldier of the first age


## A place as stored, with every field filled in (from a map file's {kind, x, y}).
static func make(kind: String, x: int, y: int) -> Dictionary:
	return {"kind": kind, "x": x, "y": y, "done": false, "n": BANDITS if kind == "bandits" else 0, "raid_t": 0.0, "party": {}}


static func at(sim: Sim, x: int, y: int, r := 0) -> Dictionary:
	for pl: Dictionary in sim.places:
		if absi(int(pl.x) - x) <= r and absi(int(pl.y) - y) <= r:
			return pl
	return {}


## Why nothing can be built at (x, y) because of a place ("" when something can).
static func block(sim: Sim, x: int, y: int) -> String:
	for pl: Dictionary in sim.places:
		var dx := absi(int(pl.x) - x)
		var dy := absi(int(pl.y) - y)
		if pl.kind == "ruins" and dx <= 1 and dy <= 1:
			return "Old ruins stand here"
		if pl.kind == "bandits" and not bool(pl.done) and dx * dx + dy * dy <= BLOCK_R * BLOCK_R:
			return "A bandit camp is too near: send soldiers to clear it first"
	return ""


## Once a second: ruins found, bandits raiding, parties arriving at a camp, rivals clearing camps.
static func tick(sim: Sim) -> void:
	for pl: Dictionary in sim.places:
		var i := sim.idx(int(pl.x), int(pl.y))
		if pl.kind == "ruins":
			if not bool(pl.done) and sim.owner[i] != 0:
				pl.done = true
				var p := sim.players[sim.owner[i] - 1]
				for k in LOOT:
					if p.stock.has(k):
						sim.give(p, k, float(LOOT[k]), i)
				if not p.ai:
					sim.emit_log("Your people searched the old ruins and found %s." % Diplomacy.goods_text(LOOT), Color("e8c870"), Vector2i(int(pl.x), int(pl.y)))
			continue
		if bool(pl.done):
			continue
		var party: Dictionary = pl.party
		if not party.is_empty():
			if sim.time >= float(party.t1):
				_fight(sim, pl)
			continue
		if sim.time >= float(pl.raid_t):
			pl.raid_t = sim.time + RAID_EVERY
			_raid(sim, pl)
		# rivals with soldiers to spare clear a camp in their way
		if int(sim.time) % 15 == 0:
			for p: Sim.Player in sim.players:
				if p.ai and p.alive:
					var src := best_source(sim, p, pl)
					if src != null and sim.own_def(src) - 1 >= int(pl.n) + 2:
						send(sim, p, pl)
						break


## The bandits take a few goods from the nearest realm whose land comes near.
static func _raid(sim: Sim, pl: Dictionary) -> void:
	var cx := int(pl.x)
	var cy := int(pl.y)
	var best := 0
	var bd := 1e9
	for y in range(maxi(0, cy - RAID_R), mini(sim.h - 1, cy + RAID_R) + 1):
		for x in range(maxi(0, cx - RAID_R), mini(sim.w - 1, cx + RAID_R) + 1):
			var o := sim.owner[y * sim.w + x]
			var d := Vector2(x - cx, y - cy).length()
			if o != 0 and d < bd:
				bd = d; best = o
	if best == 0:
		return
	var p := sim.players[best - 1]
	var wants := ["bread", "fish", "meat", "planks", "stone", "beer"]
	var pick := String(wants[sim.rng.randi() % wants.size()])
	var got := sim.take(p, pick, 3.0, sim.idx(cx, cy))
	if got > 0.0 and not p.ai:
		sim.emit_log("Bandits from the camp nearby stole %d %s. Send soldiers to clear the camp (click it)." % [int(got), GameData.res_name(pick).to_lower()], Color("e0b060"), Vector2i(cx, cy))


## The military building of realm p within reach of the camp with the most soldiers to spare.
static func best_source(sim: Sim, p: Sim.Player, pl: Dictionary) -> Sim.Bld:
	var best: Sim.Bld = null
	for b: Sim.Bld in sim.mil_list():
		if b.p != p.id or b.state != "ready" or b.dead:
			continue
		if Vector2(b.x - int(pl.x), b.y - int(pl.y)).length() > Sim.RANGE:
			continue
		if best == null or sim.own_def(b) > sim.own_def(best):
			best = b
	return best


## Realm p sends soldiers (all but one) from its best building within reach to clear camp pl.
## Returns "" or why not.
static func send(sim: Sim, p: Sim.Player, pl: Dictionary) -> String:
	if pl.kind != "bandits" or bool(pl.done):
		return "There is nothing to clear here"
	if not (pl.party as Dictionary).is_empty():
		return "Soldiers are already on their way to this camp"
	var src := best_source(sim, p, pl)
	if src == null:
		return "None of your military buildings is within %d tiles of the camp" % int(Sim.RANGE)
	var n := sim.own_def(src) - 1
	if n < 1:
		return "Your nearest building has only the soldier who stays home"
	var mix: Array = Sim.mix_take_best(sim.military.mix_of(src), n)
	if src.ty == "hq":
		p.reserve -= n
	else:
		src.garrison -= n
		src.blunt = mini(src.blunt, src.garrison)
	var dist := Vector2(src.x - int(pl.x), src.y - int(pl.y)).length()
	pl.party = {"p": p.id, "src": src.id, "n": n, "mix": mix, "t0": sim.time, "t1": sim.time + dist / WALK + 1.0}
	if not p.ai:
		sim.emit_log("%d soldiers set out to clear the bandit camp." % n, Color("d8aa4a"), Vector2i(int(pl.x), int(pl.y)))
	return ""


## The party reached the camp: soldier against bandit until one side is gone; survivors go home.
static func _fight(sim: Sim, pl: Dictionary) -> void:
	var party: Dictionary = pl.party
	var p := sim.players[int(party.p) - 1]
	var mix: Array = party.mix
	var n := int(party.n)
	var bandits := int(pl.n)
	var era := Sim.mix_avg(mix)
	while n > 0 and bandits > 0:
		if sim.rng.randf() < BANDIT_WIN - 0.06 * era:
			Sim.mix_remove(mix, Sim.mix_pick(mix, sim.rng))
			n -= 1
		else:
			bandits -= 1
	pl.n = bandits
	pl.party = {}
	var where := Vector2i(int(pl.x), int(pl.y))
	if bandits == 0:
		pl.done = true
		for k in CAMP_LOOT:
			if p.stock.has(k):
				sim.give(p, k, float(CAMP_LOOT[k]), sim.idx(where.x, where.y))
		if not p.ai:
			sim.emit_log("The bandits are driven out! Their camp held %s. %d of your soldiers go home." % [Diplomacy.goods_text(CAMP_LOOT), n], Color("86ad5c"), where)
	elif not p.ai:
		sim.emit_log("Your soldiers fell fighting the bandits; %d bandits are left in the camp." % bandits, Color("e08a6a"), where)
	# the survivors go back to the building they came from (or to headquarters)
	if n > 0:
		var src: Sim.Bld = sim.by_id.get(int(party.src))
		if src != null and not src.dead and src.p == p.id and src.ty != "hq":
			Sim.mix_add(sim.gmix_of(src), mix)
			src.garrison += n
			src.sera = Sim.mix_avg(src.gmix)
		else:
			Sim.mix_add(sim.rmix_of(p), mix)
			p.reserve += n
			p.res_era = Sim.mix_avg(p.rmix)


## Where a party on its way is now (tiles), or (-1, -1).
static func party_pos(sim: Sim, pl: Dictionary) -> Vector2:
	var party: Dictionary = pl.party
	if party.is_empty():
		return Vector2(-1, -1)
	var src: Sim.Bld = sim.by_id.get(int(party.src))
	var a := Vector2(src.x, src.y) if src != null else Vector2(int(pl.x), int(pl.y))
	var f := clampf((sim.time - float(party.t0)) / maxf(0.1, float(party.t1) - float(party.t0)), 0.0, 1.0)
	return a.lerp(Vector2(int(pl.x), int(pl.y)) + Vector2(0.6, 0.3), f)
