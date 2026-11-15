class_name SandboxGoals
extends RefCounted
## Sandbox goals (build 63): in endless games (no mission), a chain of goals to aim for, one at a time,
## from a first village to the last age. Each gives some gold from the treasury when reached. The goal
## being worked on is Player.goal_i (saved with the game); Sim._goals_check ticks them off, the guide's
## box shows them (Settings: "Goals to aim for in endless games").
##
## A goal: {"kind", "n", "text", "tip", "gold"} with the kinds of mission goals (pop, build + "ty",
## soldiers, tech + "id", land, stock + "res", trades) and a few of its own: age, techs, festivals,
## quarter (percent of homes), wonders, buildings.

const LIST := [
	{"kind": "pop", "n": 30, "text": "Grow to 30 people", "tip": "Houses and food bring newcomers.", "gold": 5},
	{"kind": "build", "ty": "sawmill", "n": 2, "text": "Run two sawmills", "tip": "Planks build almost everything.", "gold": 5},
	{"kind": "land", "n": 600, "text": "Hold 600 tiles of land", "tip": "Guard huts and towers push your border out.", "gold": 5},
	{"kind": "techs", "n": 5, "text": "Study 5 techs", "tip": "Scriptoriums make research (R).", "gold": 8},
	{"kind": "build", "ty": "tavern", "n": 1, "text": "Open a tavern", "tip": "Beer and bread for it: a hop farm, a brewery, a bakery.", "gold": 8},
	{"kind": "festivals", "n": 1, "text": "Hold a festival", "tip": "A tavern that serves a good part of your homes, and beer and bread to spare.", "gold": 10},
	{"kind": "pop", "n": 100, "text": "Grow to 100 people", "tip": "", "gold": 10},
	{"kind": "age", "n": 2, "text": "Reach the Middle Ages", "tip": "Study the age's gate once you know enough Roman techs.", "gold": 15},
	{"kind": "soldiers", "n": 20, "text": "Have 20 soldiers", "tip": "Barracks train them from weapons and an idle artisan.", "gold": 10},
	{"kind": "build", "ty": "market", "n": 1, "text": "Build a market", "tip": "Sell and buy at the market (M), or set standing orders.", "gold": 10},
	{"kind": "quarter", "n": 25, "text": "A quarter of your homes in town quarters", "tip": "Homes near a working tavern, chapel and market.", "gold": 15},
	{"kind": "stock", "res": "gold", "n": 50, "text": "Keep 50 gold in store", "tip": "Nobles pay tax; a mint makes coins.", "gold": 0},
	{"kind": "wonders", "n": 1, "text": "Build a wonder", "tip": "Each age has one; it is built once.", "gold": 20},
	{"kind": "pop", "n": 250, "text": "Grow to 250 people", "tip": "", "gold": 20},
	{"kind": "age", "n": 3, "text": "Reach the Renaissance", "tip": "", "gold": 25},
	{"kind": "buildings", "n": 150, "text": "Have 150 buildings", "tip": "", "gold": 20},
	{"kind": "trades", "n": 10, "text": "Make 10 trades with other realms", "tip": "Diplomacy (G): offer goods to realms at peace.", "gold": 20},
	{"kind": "age", "n": 4, "text": "Reach the Age of Reason", "tip": "", "gold": 30},
	{"kind": "land", "n": 4000, "text": "Hold 4,000 tiles of land", "tip": "", "gold": 30},
	{"kind": "pop", "n": 500, "text": "Grow to 500 people", "tip": "", "gold": 40},
	{"kind": "age", "n": 5, "text": "Reach the Industrial age", "tip": "", "gold": 40},
	{"kind": "wonders", "n": 3, "text": "Build three wonders", "tip": "", "gold": 50},
	{"kind": "age", "n": 6, "text": "Reach the Modern age", "tip": "", "gold": 60},
	{"kind": "wonders", "n": 5, "text": "Build all five wonders", "tip": "With the peaceful victory on, that wins the game.", "gold": 100},
]


## [how far, how far it must get] for goal g of the human realm.
static func progress(sim: Sim, g: Dictionary) -> Array:
	var me := sim.human()
	var n := int(g.get("n", 1))
	match String(g.get("kind", "")):
		"age":
			return [me.age, n]
		"techs":
			return [me.techs.size(), n]
		"festivals":
			var ct = sim.get_feature("contentment")
			return [int(ct.feasts.get(me.id, 0)) if ct != null else n, n]
		"quarter":
			var ct2 = sim.get_feature("contentment")
			return [roundi(ct2.quarter_share(me) * 100.0) if ct2 != null else n, n]
		"wonders":
			return [sim.wonders_of(me).size(), n]
		"buildings":
			return [sim.realm_blds(me).size(), n]
	return sim.goal_progress(g)
