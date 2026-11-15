class_name SimMarket
extends RefCounted
## Market prices that move (build 53). Every good has a price in gold: its worth (GameData.res_value)
## times a factor (Sim.prices) that follows what all realms together have in store: goods that are
## short grow dear (up to MAX_F times their worth), goods everyone has plenty of grow cheap (down to
## MIN_F). Once a minute each factor moves a quarter of the way to where supply puts it; selling pushes
## a price down at once, buying pushes it up. A realm with a market sells at SELL of the price and buys
## at BUY of it (Market window, M). Merchants (events) and the worth of goods in trades between realms
## follow the same prices. Rivals with a market sell what they have too much of and buy stone and
## planks when short. Sim.prices and Sim.price_hist (the last HIST minutes) are saved with the game.

var sim: Sim

const EVERY := 60
const MIN_F := 0.4
const MAX_F := 2.5
const SELL := 0.8
const BUY := 1.25
const HIST := 30
const PUSH := 0.004          # how much one unit sold (bought) moves its price down (up)
const NOT_TRADED := ["gold", "research", "ship", "warship"]


func _init(p_sim: Sim) -> void:
	sim = p_sim


func traded(res: String) -> bool:
	return not NOT_TRADED.has(res) and GameData.res_by_id.has(res)


func factor(res: String) -> float:
	return float(sim.prices.get(res, 1.0))


## The price of one res in gold, before the market's cut.
func price(res: String) -> float:
	return GameData.res_value(res) * factor(res) / maxf(0.5, GameData.res_value("gold"))


func sell_price(res: String, n: int) -> int:
	return maxi(1, floori(price(res) * SELL * n))


func buy_price(res: String, n: int) -> int:
	return maxi(1, ceili(price(res) * BUY * n))


## Where the price was `ago` minutes back (for the trend), or the price now.
func past(res: String, ago: int) -> float:
	var h: Array = sim.price_hist.get(res, [])
	if h.size() <= ago:
		return factor(res)
	return float(h[h.size() - 1 - ago])


## -1 falling, 0 steady, 1 rising (over the last five minutes).
func trend(res: String) -> int:
	var d := factor(res) - past(res, 5)
	return 1 if d > 0.04 else (-1 if d < -0.04 else 0)


func has_market(p: Sim.Player) -> bool:
	for b: Sim.Bld in sim.realm_blds(p):
		if b.ty == "market" and b.state == "ready" and not b.dead:
			return true
	return false


## Once a minute: every price moves toward where supply puts it.
func on_second() -> void:
	if int(sim.time) % EVERY != 0 or sim.time < 1.0:
		return
	var alive := []
	for p in sim.players:
		if p.alive:
			alive.append(p)
	if alive.is_empty():
		return
	var pop := 0.0
	for p: Sim.Player in alive:
		pop += sim.pop_total(p)
	pop /= alive.size()
	for r in GameData.res_by_id:
		if not traded(r):
			continue
		var have := 0.0
		for p: Sim.Player in alive:
			have += float(p.stock.get(r, 0.0))
		have /= alive.size()
		# a realm likes to have about this much of anything; luxuries and late goods less
		var want := (12.0 + pop * 0.08) / maxf(1.0, sqrt(GameData.res_value(r) / 2.0))
		var goal := clampf(sqrt(want / maxf(1.0, have)), MIN_F, MAX_F)
		var f := factor(r)
		f = lerpf(f, goal, 0.25) * (1.0 + (sim.rng.randf() - 0.5) * 0.04)
		sim.prices[r] = snappedf(clampf(f, MIN_F, MAX_F), 0.001)
		var h: Array = sim.price_hist.get(r, [])
		h.append(sim.prices[r])
		if h.size() > HIST:
			h.pop_front()
		sim.price_hist[r] = h
	for p: Sim.Player in alive:
		if p.ai and (int(sim.time) / EVERY + p.id) % 2 == 0:
			ai_trade(p)
		if not p.routes.is_empty():
			run_routes(p)


## Sells n of res from realm p's stores at the market. "" when done, else why not.
func sell(p: Sim.Player, res: String, n: int) -> String:
	if not traded(res):
		return "This cannot be sold"
	if not has_market(p):
		return "You need a market to trade"
	if float(p.stock.get(res, 0.0)) < n:
		return "Not enough %s in store" % GameData.res_name(res).to_lower()
	var gold := sell_price(res, n)
	# gold the stores have no room for would be lost (build 61)
	if sim.capacity(p, "gold") - float(p.stock.get("gold", 0.0)) < gold:
		return "No room in your stores for the gold: build a storehouse or spend some"
	var got := int(sim.take(p, res, float(n)))
	if got < n:
		sim.give(p, res, float(got))
		return "Not enough %s in store" % GameData.res_name(res).to_lower()
	sim.used(p, res, float(n))
	sim.give(p, "gold", float(gold))
	sim.made(p, "gold", float(gold))
	sim.prices[res] = clampf(factor(res) * (1.0 - PUSH * n), MIN_F, MAX_F)
	return ""


## Buys n of res for realm p with gold from its stores. "" when done, else why not.
func buy(p: Sim.Player, res: String, n: int) -> String:
	if not traded(res):
		return "This cannot be bought"
	if not has_market(p):
		return "You need a market to trade"
	var cost := buy_price(res, n)
	if float(p.stock.get("gold", 0.0)) < cost:
		return "Not enough gold (%d needed)" % cost
	if sim.capacity(p, res) - float(p.stock.get(res, 0.0)) < n:
		return "No room in your stores"
	sim.take(p, "gold", float(cost))
	sim.used(p, "gold", float(cost))
	sim.give(p, res, float(n))
	sim.made(p, res, float(n))
	sim.prices[res] = clampf(factor(res) * (1.0 + PUSH * n), MIN_F, MAX_F)
	return ""


# ---------------------------------------------------------------- standing orders (build 61)
## A standing order: {"res", "sell": true to sell / false to buy, "n": how many each time, "every":
## minutes between, "keep": sell only while more than this stays in store / buy only up to this,
## "done": how many went so far, "gold": gold made (+) or spent (-)}. Merchants carry the goods to and
## from the market each time it is due.
const ROUTE_MAX := 12
const ROUTE_EVERY := [1, 2, 5, 10]
const ROUTE_N := [10, 25, 50]


func add_route(p: Sim.Player, res: String, sell_it: bool, n: int, every: int, keep: int) -> String:
	if not traded(res):
		return "This cannot be traded"
	if p.routes.size() >= ROUTE_MAX:
		return "At most %d standing orders" % ROUTE_MAX
	p.routes.append({"res": res, "sell": sell_it, "n": maxi(1, n), "every": maxi(1, every), "keep": maxi(0, keep), "done": 0, "gold": 0})
	return ""


func remove_route(p: Sim.Player, i: int) -> void:
	if i >= 0 and i < p.routes.size():
		p.routes.remove_at(i)


## Once a minute: the standing orders that are due go through, while the stores allow.
func run_routes(p: Sim.Player) -> void:
	if not has_market(p):
		return
	var minute := int(sim.time / 60.0)
	var said := []
	for r: Dictionary in p.routes:
		if minute % int(r.every) != 0:
			continue
		var res := String(r.res)
		var n := int(r.n)
		var have := float(p.stock.get(res, 0.0))
		var g0 := float(p.stock.get("gold", 0.0))
		var why := ""
		if bool(r.sell):
			why = ("Keeping %d" % int(r.keep)) if have - n < int(r.keep) else sell(p, res, n)
		else:
			why = ("%d in store already" % int(have)) if have + n > int(r.keep) else buy(p, res, n)
		r.why = why
		if why != "":
			continue
		var dg := int(float(p.stock.get("gold", 0.0)) - g0)
		r.done = int(r.done) + n
		r.gold = int(r.gold) + dg
		said.append("%s %d %s (%+d gold)" % ["sold" if bool(r.sell) else "bought", n, GameData.res_name(res).to_lower(), dg])
	if not said.is_empty() and not p.ai:
		sim.emit_log("Standing orders at your market: %s." % ", ".join(said), Color("d8aa4a"))


## A rival with a market sells 10 of what it has most of and buys stone or planks when short.
func ai_trade(p: Sim.Player) -> void:
	if not has_market(p):
		return
	var best := ""
	var most := 80.0
	for r in GameData.res_by_id:
		var rd: Dictionary = GameData.res_by_id[r]
		if not traded(r) or rd.has("tool") or GameData.food_ids.has(r) or r in ["weapons", "armor"]:
			continue
		if float(p.stock.get(r, 0.0)) > most:
			most = float(p.stock.get(r, 0.0)); best = r
	if best != "":
		sell(p, best, 10)
	for r in Sim.BASIC:
		if float(p.stock.get(r, 0.0)) < 6.0 and float(p.stock.get("gold", 0.0)) >= buy_price(r, 10) + 5:
			buy(p, r, 10)
			return
	# what its workshops stand idle for (build 60): the good most of them need, if it is not dear
	var lack := {}
	for b: Sim.Bld in sim.realm_blds(p):
		if b.state == "ready" and not b.dead and b.msg.begins_with("Needs "):
			for k in b.def.get("in", {}):
				if GameData.res_by_id.has(k) and traded(k) and float(p.stock.get(k, 0.0)) < 1.0:
					lack[k] = int(lack.get(k, 0)) + 1
	var want := ""
	var n := 0
	for k in lack:
		if int(lack[k]) > n or (int(lack[k]) == n and String(k) < want):
			n = int(lack[k]); want = k
	if want != "" and factor(want) < 1.8 and float(p.stock.get("gold", 0.0)) >= buy_price(want, 10) * 1.5:
		buy(p, want, 10)
