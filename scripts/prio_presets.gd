class_name PrioPresets
extends RefCounted
## Ready-made sets of priorities (build 54): transport numbers (Player.carry_rank) and worker numbers
## (Player.work_rank) together. The player's own sets are kept in the settings (Settings.prio_presets);
## rivals pick one of these as their situation changes (SimAI._ai_priorities).

## The built-in sets: name -> [what it is for, carry ranks, work ranks]. Kinds of building and goods
## not in the data are left out when a set is used.
const BUILT_IN := {
	"Build up": ["Building materials first: planks, stone and bricks to the sites, builders and wood and stone workers first.",
		{"planks": 1, "stone": 1, "bricks": 2, "wood": 2, "clay": 3},
		{"woodcutter": 1, "sawmill": 1, "quarry": 1, "forester": 2, "brickworks": 2, "clay_pit": 3}],
	"War": ["Arms first: weapons and armour, iron and coal to the smithies, and their workers first.",
		{"weapons": 1, "armor": 1, "iron": 2, "coal": 2, "ore_iron": 3, "food": 3},
		{"weaponsmith": 1, "armorer": 1, "barracks": 1, "iron_smelter": 2, "iron_mine": 2, "coal_mine": 2}],
	"Feed everyone": ["Food first: any food, grain, flour and fish first, and farms, fishers, mills and bakeries get workers first.",
		{"food": 1, "grain": 2, "flour": 2, "bread": 2, "fish": 2, "meat": 2, "water": 3},
		{"farm": 1, "fisher": 1, "bakery": 1, "mill": 2, "hunter": 2, "well": 2, "orchard": 2, "butcher": 3}],
	"Research": ["Learning first: paper and beer to the libraries and universities, and their scholars first.",
		{"paper": 1, "beer": 2, "quills": 2},
		{"scriptorium": 1, "library": 1, "university": 1, "paper_mill": 2}],
}


## Puts set (carry, work) on realm p, keeping only goods and kinds the game has. Every other number
## goes back to 5.
static func apply(p: Sim.Player, carry: Dictionary, work: Dictionary) -> void:
	p.carry_rank = {}
	for k in carry:
		if k == "food" or GameData.res_by_id.has(k):
			if int(carry[k]) != SimLogistics.RANK_DEFAULT:
				p.carry_rank[k] = clampi(int(carry[k]), 1, 9)
	p.work_rank = {}
	for k in work:
		if GameData.bld.has(k):
			if int(work[k]) != SimLogistics.RANK_DEFAULT:
				p.work_rank[k] = clampi(int(work[k]), 1, 9)


static func apply_named(p: Sim.Player, name: String) -> bool:
	if not BUILT_IN.has(name):
		return false
	var e: Array = BUILT_IN[name]
	apply(p, e[1], e[2])
	return true


## Which built-in set realm p's numbers are now, or "".
static func current(p: Sim.Player) -> String:
	for name in BUILT_IN:
		var e: Array = BUILT_IN[name]
		var c := {}
		var w := {}
		for k in e[1]:
			if (k == "food" or GameData.res_by_id.has(k)) and int(e[1][k]) != SimLogistics.RANK_DEFAULT: c[k] = int(e[1][k])
		for k in e[2]:
			if GameData.bld.has(k) and int(e[2][k]) != SimLogistics.RANK_DEFAULT: w[k] = int(e[2][k])
		if c == p.carry_rank and w == p.work_rank:
			return name
	return ""
