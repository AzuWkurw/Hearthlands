extends Feature
## Seasons, biomes and weather.
## A year has four seasons of five game minutes each, starting in spring. The map is split into biomes:
## a cold northern taiga, a temperate middle, a dry southern steppe and wetland patches near water.
## Each biome has its own weather, which changes every one to two and a half minutes, and its own
## temperature (season + biome + weather; mountains are colder). Season, biome and weather speed up or
## slow down outdoor work, construction, and how much people eat. Other features (clothes, diseases)
## read the temperature through temp_at() and realm_temp().

const YEAR := 1200.0
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const TEMPERATE := 0
const TAIGA := 1
const STEPPE := 2
const WETLAND := 3
const BIOME_NAMES := ["Temperate land", "Northern taiga", "Southern steppe", "Wetland"]
const BIOME_TEMP := [0.0, -7.0, 5.0, -1.0]
## Ground colour of each biome, laid thinly over the map.
const BIOME_TINT := [Color(0.0, 0.0, 0.0, 0.0), Color(0.12, 0.28, 0.32, 0.20), Color(0.80, 0.62, 0.26, 0.24), Color(0.10, 0.32, 0.26, 0.22)]
const WEATHER := {
	"clear": {"name": "Clear", "dt": 1.0},
	"cloudy": {"name": "Cloudy", "dt": -1.0},
	"rain": {"name": "Rain", "dt": -2.0},
	"storm": {"name": "Storm", "dt": -3.0},
	"snow": {"name": "Snow", "dt": -3.0},
	"blizzard": {"name": "Blizzard", "dt": -6.0},
	"heat": {"name": "Heat wave", "dt": 6.0},
	"fog": {"name": "Fog", "dt": -1.0},
}
## How likely each weather is in each season (before the biome changes it).
const SEASON_WEATHER := [
	{"clear": 4.0, "cloudy": 3.0, "rain": 3.0, "storm": 0.5, "fog": 1.0},
	{"clear": 5.0, "cloudy": 2.0, "rain": 1.5, "storm": 1.0, "heat": 2.0},
	{"clear": 3.0, "cloudy": 3.0, "rain": 3.0, "storm": 1.5, "fog": 2.0},
	{"clear": 3.0, "cloudy": 3.0, "snow": 3.0, "blizzard": 0.7, "fog": 1.0, "rain": 0.5},
]
const BIOME_WEATHER := [
	{},
	{"snow": 2.0, "blizzard": 2.0, "heat": 0.2, "fog": 1.3},
	{"rain": 0.5, "storm": 0.8, "heat": 2.5, "clear": 1.5, "fog": 0.3, "snow": 0.6},
	{"fog": 3.0, "rain": 1.5},
]
## Crops grow in the open; their work follows the seasons most.
const CROPS := ["farm", "orchard", "hop_farm", "vineyard", "flax_farm", "herb_garden", "mulberry_grove", "pepper_garden", "coffee_plantation", "apiary"]
const ANIMALS := ["sheep_farm", "pig_farm", "dairy"]
const WOODS := ["woodcutter", "forester", "charcoal_burner"]
## Other work done outdoors (quarries, pits, salt pans).
const OUTDOOR := ["quarry", "clay_pit", "saltworks", "sand_pit", "well"]

var biome := PackedByteArray()       # biome of each tile
var weather: Array = ["clear", "clear", "clear", "clear"]   # current weather of each biome
var weather_until: Array = [0.0, 0.0, 0.0, 0.0]
## What kind of year each biome has (build 55): "" an ordinary one, "dry" (a drought: more heat, little
## rain, crops and wells do worse) or "wet" (more rain: crops do better, clay pits too). Chosen each
## spring.
var year_kind: Array = ["", "", "", ""]
const YEAR_KINDS := {"dry": ["A dry year", "crops grow 25% slower and wells give less; heat waves come often"], "wet": ["A wet year", "crops grow 10% faster and clay pits do well; rain falls often"]}
var rng := RandomNumberGenerator.new()
var last_season := -1
var _masks: Array = []               # [where each climate lies, one per colour channel] (for the ground shader)
var _ice: ImageTexture
var _snow: Array = [0.0, 0.0, 0.0, 0.0]   # how much snow lies in each biome now (0 to 1), eased
var _parts: Array = []               # rain drops and snow flakes on screen
var _grid: Array = []                # the weather over a 16 x 9 grid of the screen: [weather or "" where unseen]
var _grid_key := ""
const GX := 16
const GY := 9
var _snow_t := 0.0                   # game time the snow was last brought up to date
var _realm_t: Dictionary = {}        # realm id -> temperature at its headquarters, this second
var _cache_season := -1
var _cache: Array = [{}, {}, {}, {}]  # per biome: building type -> work bonus, worked out once a second

## River ice (build 78). From a minute into winter to the first day of spring the narrow water of the
## taiga (rivers, lake shores and bays: water within ICE_REACH tiles of land) freezes hard: soldiers
## march over it and roads cross it without a bridge. At the thaw the ice roads melt away, and soldiers
## still on the ice drown.
const ICE_FROM := 0.80               # share of the year when the ice forms (0.75 is the first day of winter)
const ICE_REACH := 3
const ICE_WARN := 25.0               # seconds before the thaw when the ice is told to be thinning
var ice_on := false                  # whether the rivers are frozen now (saved, so the thaw comes once)
var ice_warned := false              # the thinning ice has been told this winter
var _ice_known := false              # a loaded game had ice_on in its save
var _freeze := PackedByteArray()     # 1 on each water tile that freezes in winter
var _freeze_n := 0
var _ice_vis := 0.0                  # how thick the ice looks now, eased (only for drawing)
var _ice_t := 0.0


func _init() -> void:
	id = "seasons"
	title = "Seasons, biomes and weather"
	info = "Four seasons a year, northern taiga, southern steppe and wetlands with their own weather and temperature. Crops grow best in summer and stall in winter."
	default_on = true


func on_start(loaded: bool) -> void:
	_make_biomes()
	_make_freeze()
	# a new game, or a save from before the river ice: frozen or not as the time of year says
	if not loaded or not _ice_known:
		ice_on = frozen_now()
		ice_warned = ice_on and thaw_in() <= ICE_WARN
	sim.ice = _freeze.duplicate() if ice_on and _freeze_n > 0 else PackedByteArray()
	_ice_vis = 1.0 if ice_on else 0.0
	# a new game, or a save from before this feature existed
	if not loaded or rng.seed == 0:
		rng.seed = (sim.seed_str + ":weather").hash()
		for k in 4:
			weather_until[k] = 0.0
		last_season = season()
	_make_textures()
	for k in 4:
		_snow[k] = _snow_target(k)
	# a loaded game keeps the temperatures of its last whole second (saved), so it goes on the same
	if not loaded or _realm_t.is_empty():
		_update_realm_temps()


# ---------------------------------------------------------------- climate

## Where in the year we are, 0 to 1 (0 = the first day of spring).
func phase() -> float:
	return fmod(sim.time, YEAR) / YEAR


func season() -> int:
	return int(phase() * 4.0) % 4


func year() -> int:
	return int(sim.time / YEAR) + 1


## Temperature of a biome before the weather: a smooth curve over the year, warmest in mid summer
## (about 23 C in temperate land) and coldest in mid winter (about -3 C).
func base_temp(k: int) -> float:
	return 10.0 + 13.0 * sin(TAU * (phase() - 0.125)) + float(BIOME_TEMP[k])


func biome_temp(k: int) -> float:
	return base_temp(k) + float(WEATHER[weather[k]].dt)


## Temperature on tile i, in degrees Celsius.
func temp_at(i: int) -> float:
	if i < 0 or i >= biome.size():
		return biome_temp(TEMPERATE)
	return biome_temp(biome[i]) - (5.0 if sim.ter[i] == Sim.MOUNT else 0.0)


## Temperature where realm p lives (at its headquarters).
func realm_temp(p: Sim.Player) -> float:
	return float(_realm_t.get(p.id, biome_temp(TEMPERATE)))


func biome_at(x: int, y: int) -> int:
	if not sim.inb(x, y):
		return TEMPERATE
	return biome[sim.idx(x, y)]


func biome_of(p: Sim.Player) -> int:
	return biome_at(p.hq.x, p.hq.y) if p.hq != null else TEMPERATE


## Splits the map into biomes from the map seed: north and south bands with ragged edges,
## wetland patches near water in between.
func _make_biomes() -> void:
	var w := sim.w
	var h := sim.h
	biome = PackedByteArray()
	biome.resize(w * h)
	var n := FastNoiseLite.new()
	n.seed = (sim.seed_str + ":biomes").hash() & 0x7fffffff
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0 / 22.0
	var wet := FastNoiseLite.new()
	wet.seed = n.seed + 77
	wet.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wet.frequency = 1.0 / 12.0
	var painted := sim.map_biome.size() == w * h
	for y in h:
		for x in w:
			var i := y * w + x
			# the climate the map's maker painted here (0: left to the game)
			if painted and sim.map_biome[i] > 0:
				biome[i] = sim.map_biome[i] - 1
				continue
			var v := float(y) / h + n.get_noise_2d(x, y) * 0.12
			var k := TEMPERATE
			if v < 0.30:
				k = TAIGA
			elif v > 0.70:
				k = STEPPE
			elif sim.ter[i] != Sim.MOUNT and wet.get_noise_2d(x, y) > 0.25 and _water_near(x, y, 3) >= 5:
				k = WETLAND
			biome[i] = k


## Which water freezes: taiga water within ICE_REACH tiles of land (eight ways), so rivers and lakes
## freeze from shore to shore while the open sea stays open past its coastal ice.
func _make_freeze() -> void:
	var w := sim.w
	var n := w * sim.h
	_freeze = PackedByteArray()
	_freeze.resize(n)
	_freeze_n = 0
	var dist := PackedByteArray()
	dist.resize(n)
	dist.fill(255)
	var q := PackedInt32Array()
	for i in n:
		if sim.ter[i] != Sim.WATER:
			dist[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var cur := q[head]
		head += 1
		var dc := int(dist[cur])
		if dc >= ICE_REACH:
			continue
		var cx := cur % w
		var cy := cur / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= sim.h:
					continue
				var ni := ny * w + nx
				if dist[ni] == 255:
					dist[ni] = dc + 1
					q.append(ni)
	for i in n:
		if sim.ter[i] == Sim.WATER and dist[i] != 255 and biome[i] == TAIGA:
			_freeze[i] = 1
			_freeze_n += 1


## Whether the time of year has the rivers frozen.
func frozen_now() -> bool:
	return phase() >= ICE_FROM


## Seconds until the ice breaks up (the first day of spring), while it lies.
func thaw_in() -> float:
	return (1.0 - phase()) * YEAR


## Seconds until the rivers freeze, while they are open.
func freeze_in() -> float:
	var ph := phase()
	return ((ICE_FROM - ph) if ph < ICE_FROM else (1.0 + ICE_FROM - ph)) * YEAR


## Whether water tile i freezes in winter.
func freezes(i: int) -> bool:
	return i >= 0 and i < _freeze.size() and _freeze[i] != 0


## The river ice forms, thins and breaks up, once a second.
func _ice_second() -> void:
	var now := frozen_now()
	if now and not ice_on:
		ice_on = true
		ice_warned = false
		if _freeze_n > 0:
			sim.ice = _freeze.duplicate()
			sim.emit_log("The northern rivers have frozen hard: soldiers can march over the ice, and roads cross it without a bridge (ice roads melt in spring: keep planks for bridges).", Color("9fd0e8"))
	elif ice_on and not now:
		ice_on = false
		var mask := sim.ice
		sim.ice = PackedByteArray()
		if not mask.is_empty():
			sim.military.ice_breaks(mask)
			var melted := sim.logistics.melt_ice_roads(mask)
			if sim.logistics.thaw_cut > 0:
				sim.emit_log("The river ice breaks up: your ice roads have melted, and %d buildings are cut off from the stores. Join them up again with roads and bridges." % sim.logistics.thaw_cut, Color("e0b060"))
				sim.logistics.thaw_cut = 0
			elif melted > 0:
				sim.emit_log("The river ice breaks up: %d tiles of your ice roads have melted away." % melted, Color("9fd0e8"))
			else:
				sim.emit_log("The river ice breaks up.", Color("9fd0e8"))
	elif ice_on and not ice_warned and thaw_in() <= ICE_WARN:
		ice_warned = true
		if not sim.ice.is_empty():
			sim.emit_log("The river ice is thinning: it breaks up in %d seconds. Soldiers still on it then will drown." % roundi(thaw_in()), Color("e0b060"))
			sim.military.ice_recall()


func _water_near(x: int, y: int, r: int) -> int:
	var c := 0
	for yy in range(maxi(0, y - r), mini(sim.h - 1, y + r) + 1):
		for xx in range(maxi(0, x - r), mini(sim.w - 1, x + r) + 1):
			if sim.ter[yy * sim.w + xx] == Sim.WATER:
				c += 1
	return c


func on_second() -> void:
	var s := season()
	if s != last_season:
		last_season = s
		var lines := [
			"Spring has come. Fields start growing again.",
			"Summer: crops grow fastest. Heat waves are likely in the south.",
			"Autumn: orchards and vineyards bring in the harvest; hunters do well.",
			"Winter has come: wheat, vegetables and orchards stand idle; only winter rye grows. Fishing and building slow down, people eat more, and snow slows carriers on unpaved roads.",
		]
		var line: String = lines[s]
		if s == 0:
			# a new year: dry, wet or ordinary, each biome on its own (the steppe dries out more often)
			for k in 4:
				var r := rng.randf()
				var dry := 0.35 if k == STEPPE else (0.1 if k == WETLAND else 0.2)
				year_kind[k] = "dry" if r < dry else ("wet" if r < dry + 0.2 else "")
			if not sim.players.is_empty():
				var yk: String = year_kind[biome_of(sim.human())]
				if yk != "":
					line += " %s where you live: %s." % [String(YEAR_KINDS[yk][0]), String(YEAR_KINDS[yk][1])]
		if s == 3 and not sim.players.is_empty() and not Crops.known(sim, sim.human(), "rye"):
			line += " (Study Heavy plough for winter rye seed.)"
		sim.emit_log(line, Color("9fd0e8"))
	_ice_second()
	var home := biome_of(sim.human()) if not sim.players.is_empty() else TEMPERATE
	for k in 4:
		if sim.time >= float(weather_until[k]):
			var before: String = weather[k]
			weather[k] = _pick_weather(k)
			weather_until[k] = sim.time + rng.randf_range(60.0, 150.0)
			if k == home and weather[k] != before and weather[k] in ["storm", "blizzard", "heat", "snow"]:
				sim.emit_log("%s where you live (%s): %s." % [String(WEATHER[weather[k]].name), String(BIOME_NAMES[k]).to_lower(), _weather_effect_text(weather[k])], Color("9fd0e8"))
	_update_realm_temps()
	for k in 4:
		(_cache[k] as Dictionary).clear()
	if int(sim.time) % 60 == 0:
		_paved.clear()


## Snow on the roads: in winter, where the realm is cold, carriers are slower on unpaved roads (up to a
## quarter slower when none are paved). The paved share is looked at once a game minute.
var _paved := {}

func _paved_share(p: Sim.Player) -> float:
	var n := 0
	var pv := 0
	for i in sim.owned(p.id)[0]:
		if sim.road[i] == p.id:
			n += 1
			if sim.pave[i] == 1:
				pv += 1
	return float(pv) / maxf(1.0, n)


func snowy(p: Sim.Player) -> bool:
	return season() == 3 and realm_temp(p) < 4.0


func carry_factor(p: Sim.Player) -> float:
	if not snowy(p):
		return 1.0
	if not _paved.has(p.id):
		_paved[p.id] = _paved_share(p)
	return 1.0 - 0.25 * (1.0 - float(_paved[p.id]))


func _update_realm_temps() -> void:
	_realm_t.clear()
	for p: Sim.Player in sim.players:
		if p.hq != null:
			_realm_t[p.id] = temp_at(sim.idx(p.hq.x, p.hq.y))


func _pick_weather(k: int) -> String:
	var wts: Dictionary = (SEASON_WEATHER[season()] as Dictionary).duplicate()
	var bw: Dictionary = BIOME_WEATHER[k]
	for key in wts:
		wts[key] = float(wts[key]) * float(bw.get(key, 1.0))
	match String(year_kind[k]):
		"dry":
			for key in ["rain", "storm", "snow"]:
				if wts.has(key): wts[key] = float(wts[key]) * 0.3
			if wts.has("heat"): wts["heat"] = float(wts["heat"]) * 2.5
			wts["clear"] = float(wts.get("clear", 0.0)) * 1.5
		"wet":
			for key in ["rain", "storm"]:
				if wts.has(key): wts[key] = float(wts[key]) * 2.0
			if wts.has("heat"): wts["heat"] = float(wts["heat"]) * 0.4
	var total := 0.0
	for key in wts:
		total += float(wts[key])
	var r := rng.randf() * total
	var pick := "clear"
	for key in wts:
		r -= float(wts[key])
		if r <= 0.0:
			pick = key
			break
	# rain falls as snow in the frost, and snow as rain in a thaw
	var t := base_temp(k)
	if t < 0.0:
		pick = {"rain": "snow", "storm": "blizzard"}.get(pick, pick)
	elif t > 3.0:
		pick = {"snow": "rain", "blizzard": "storm"}.get(pick, pick)
	if pick == "heat" and t < 18.0:
		pick = "clear"
	return pick


func _weather_effect_text(wx: String) -> String:
	match wx:
		"storm": return "fishermen stay ashore, outdoor work and building slow down"
		"blizzard": return "almost no outdoor work or building"
		"heat": return "crops wilt, workers tire"
		"snow": return "outdoor work and building slow down"
		"rain": return "crops grow a little faster"
		"fog": return "fishermen and hunters find little"
	return "fine weather"


# ---------------------------------------------------------------- effects

## Extra work speed from season, biome and weather for building b.
func speed_bonus(_p: Sim.Player, b: Sim.Bld) -> float:
	if biome.is_empty():
		return 0.0
	var k: int = biome[b.y * sim.w + b.x]
	# the season turns on the clock, between two seconds: a loaded game starts with an empty cache, so
	# the cache must never outlive its season (build 57)
	var sn := season()
	if sn != _cache_season:
		_cache_season = sn
		for j in 4:
			(_cache[j] as Dictionary).clear()
	var c: Dictionary = _cache[k]
	var key := b.ty if b.ty != "farm" else "farm:" + Crops.now(sim, b)
	if not c.has(key):
		c[key] = _bonus(key, k)
	return float(c[key])


func _bonus(key: String, k: int) -> float:
	var ty := key.get_slice(":", 0)
	var s := season()
	var wx: String = weather[k]
	var crop := ty in CROPS
	var animal := ty in ANIMALS
	var outdoor := crop or animal or ty in WOODS or ty in OUTDOOR or ty == "fisher" or ty == "hunter"
	var bonus := 0.0
	# the season
	if key.begins_with("farm:"):
		bonus += maxf(-0.6, float(Crops.LIST[key.get_slice(":", 1)].season[s]))
	elif crop:
		bonus += [0.10, 0.25, 0.10, -0.60][s]
		if s == 2 and (ty == "orchard" or ty == "vineyard"):
			bonus += 0.25
	elif animal and s == 3:
		bonus -= 0.20
	match ty:
		"fisher": bonus += [0.0, 0.10, 0.0, -0.30][s]
		"hunter": bonus += [0.0, 0.0, 0.15, -0.10][s]
		"forester": bonus += -0.50 if s == 3 else 0.0
	if s == 3 and ty in OUTDOOR:
		bonus -= 0.15
	# the biome
	match k:
		TAIGA:
			if ty in WOODS or ty == "hunter": bonus += 0.20
			if crop: bonus -= 0.25
			if animal: bonus -= 0.10
		STEPPE:
			if crop: bonus += 0.10
			if ty == "sheep_farm" or ty == "dairy": bonus += 0.20
			if ty == "forester": bonus -= 0.30
			if ty == "woodcutter": bonus -= 0.10
			if ty == "saltworks": bonus += 0.20
		WETLAND:
			if ty == "fisher": bonus += 0.20
			if ty == "clay_pit": bonus += 0.25
			if ty == "herb_garden": bonus += 0.30
			elif crop: bonus -= 0.10
		TEMPERATE:
			if crop: bonus += 0.10
	# the kind of year
	match String(year_kind[k]):
		"dry":
			if crop: bonus -= 0.25
			if ty == "well": bonus -= 0.20
		"wet":
			if crop: bonus += 0.10
			if ty == "clay_pit": bonus += 0.15
	# the weather
	match wx:
		"rain":
			if crop: bonus += 0.10
			if ty == "fisher": bonus -= 0.10
			elif outdoor: bonus -= 0.05
		"storm":
			if ty == "fisher": bonus -= 0.60
			elif outdoor: bonus -= 0.25
		"snow":
			if outdoor: bonus -= 0.15
		"blizzard":
			if ty == "fisher": bonus -= 0.80
			elif outdoor: bonus -= 0.40
		"heat":
			if crop: bonus -= 0.40 if k == STEPPE else 0.25
			else: bonus -= 0.05
		"fog":
			if ty == "fisher": bonus -= 0.20
			if ty == "hunter": bonus -= 0.25
	return maxf(bonus, -0.85)


func build_factor(_p: Sim.Player, b: Sim.Bld) -> float:
	if biome.is_empty():
		return 1.0
	var f := 0.8 if season() == 3 else 1.0
	match String(weather[biome_at(b.x, b.y)]):
		"rain": f *= 0.9
		"storm": f *= 0.7
		"snow": f *= 0.8
		"blizzard": f *= 0.5
	return f


## People eat more in the cold: 1.5% more for each degree below 5 C.
func food_factor(p: Sim.Player) -> float:
	var t := realm_temp(p)
	return 1.0 + maxf(0.0, 5.0 - t) * 0.015


# ---------------------------------------------------------------- AI

## Rivals in the cold north plant fewer crops and hunt more; nothing else changes for them.
func ai_steps(p: Sim.Player, have: Callable) -> Array:
	if biome_of(p) == TAIGA:
		return [["hunter", 2], ["fisher", 2]]
	return []


# ---------------------------------------------------------------- interface

func top_text(p: Sim.Player) -> String:
	var k := biome_of(p)
	return "%s, year %d  %d°C %s" % [SEASONS[season()], year(), roundi(realm_temp(p)), String(WEATHER[weather[k]].name).to_lower()]


func panel_lines(p: Sim.Player) -> PackedStringArray:
	var k := biome_of(p)
	var left := int((1.0 - fmod(phase() * 4.0, 1.0)) * YEAR / 4.0)
	var out := PackedStringArray(["Climate  [b]%s[/b], %s for %d:%02d more, %s" % [String(BIOME_NAMES[k]), SEASONS[season()].to_lower(), left / 60, left % 60, String(WEATHER[weather[k]].name).to_lower()]])
	if year_text(p) != "":
		out.append("[color=#e0c070]%s[/color]" % year_text(p))
	if snowy(p):
		out.append("[color=#9fd0e8]Snow on the roads: carriers %d%% slower (paved roads stay clear)[/color]" % roundi((1.0 - carry_factor(p)) * 100.0))
	if not sim.ice.is_empty():
		var tl := int(thaw_in())
		out.append("[color=#bfe4f4]Rivers frozen: armies cross the ice, roads cross it free; it breaks up in %d:%02d[/color]" % [tl / 60, tl % 60])
	return out


func building_lines(b: Sim.Bld) -> PackedStringArray:
	var k := biome_at(b.x, b.y)
	var out := PackedStringArray()
	var line := "Climate: %s, %d°C, %s" % [String(BIOME_NAMES[k]), roundi(temp_at(sim.idx(b.x, b.y))), String(WEATHER[weather[k]].name).to_lower()]
	if b.state == "build":
		var f := build_factor(sim.players[b.p - 1], b)
		if absf(f - 1.0) > 0.01:
			line += " (building %d%% speed)" % roundi(f * 100.0)
	elif b.cyc > 0.0:
		var sb := speed_bonus(sim.players[b.p - 1], b)
		if absf(sb) > 0.005:
			line += " ([color=%s]%+d%% work[/color])" % ["#a0d070" if sb > 0 else "#f0a090", roundi(sb * 100.0)]
	out.append(line)
	return out


func tile_lines(i: int) -> PackedStringArray:
	if i < 0 or i >= biome.size():
		return PackedStringArray()
	var k: int = biome[i]
	var out := PackedStringArray(["%s: %d°C, %s" % [String(BIOME_NAMES[k]), roundi(temp_at(i)), String(WEATHER[weather[k]].name).to_lower()]])
	if sim.icy(i):
		var tl := int(thaw_in())
		out.append("Frozen river: soldiers can march over it and a road can cross it with no planks, until the ice breaks up in %d:%02d." % [tl / 60, tl % 60])
	elif freezes(i):
		var tf := int(freeze_in())
		out.append("This water freezes hard in deep winter (in %d:%02d), and soldiers can then cross it." % [tf / 60, tf % 60])
	return out


var _win: Window
var _txt: RichTextLabel


func build_ui(main: Main) -> void:
	main.add_feature_button(self, "Climate", _toggle_window)
	main.add_feature_key(self, KEY_F4, _toggle_window, "Climate window")
	_win = main.add_feature_window(self, "Climate (F4)", Vector2i(560, 400))
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.95))
	_win.add_child(bg)
	_txt = RichTextLabel.new()
	_txt.bbcode_enabled = true
	_txt.add_theme_font_size_override("normal_font_size", 14)
	_txt.add_theme_font_size_override("bold_font_size", 14)
	bg.add_child(_txt)


func _toggle_window() -> void:
	if _win == null:
		return
	_win.visible = not _win.visible
	if _win.visible:
		_fill_window()


func refresh_ui(_main: Main) -> void:
	if _win != null and _win.visible:
		_fill_window()


func _fill_window() -> void:
	var p := sim.human()
	var t := "[b][color=#d8aa4a]%s of year %d[/color][/b]   (a season lasts 5 minutes)\n\n" % [SEASONS[season()], year()]
	t += "[b]Biome            Weather        Temperature[/b]\n"
	for k in 4:
		var mine := " (you)" if k == biome_of(p) else ""
		t += "%s%s: %s, %d°C\n" % [BIOME_NAMES[k], mine, String(WEATHER[weather[k]].name).to_lower(), roundi(biome_temp(k))]
	t += "\n[b][color=#d8aa4a]Seasons[/color][/b]\n"
	t += "Crops (farms, orchards, hop, flax and herb gardens, vineyards, apiaries): +10% spring, +25% summer, +10% autumn, -60% winter. Orchards and vineyards +25% more in autumn.\n"
	t += "Winter: animal farms -20%, fishers -30%, hunters -10%, foresters -50%, quarries and pits -15%, building -20%. People eat more below 5°C.\n"
	t += "River ice: from a minute into winter until spring the rivers and lake shores of the taiga freeze hard. Soldiers march over the ice, and a road laid over it needs no planks (an ice road), but at the thaw the ice roads melt and half of any soldiers still on the ice drown.\n"
	t += "\n[b][color=#d8aa4a]Biomes[/color][/b]\n"
	t += "Northern taiga (cold): woodcutters, foresters, charcoal burners and hunters +20%; crops -25%.\n"
	t += "Southern steppe (warm, dry): crops +10%, sheep farms and dairies +20%, saltworks +20%; foresters -30%. Heat waves hit crops hard.\n"
	t += "Wetland (by the water): fishers +20%, clay pits +25%, herb gardens +30%; other crops -10%.\n"
	t += "Temperate land: crops +10%.\n"
	t += "\n[b][color=#d8aa4a]Weather[/color][/b]\n"
	t += "Rain: crops +10%. Storm: fishers -60%, outdoor work -25%, building -30%. Snow: outdoor work -15%, building -20%. Blizzard: outdoor work -40%, building -50%. Heat wave: crops -25% (-40% in the steppe). Fog: fishers -20%, hunters -25%.\n"
	t += "\n[color=#9a9c88]Click a building to see how the climate changes its work right now.[/color]"
	_txt.text = t


# ---------------------------------------------------------------- drawing

func _make_textures() -> void:
	# one pass over the map fills all five pictures (the land of each climate, and the water that freezes)
	var w := sim.w
	var h := sim.h
	var n := w * h
	var datas: Array = []
	for k in 5:
		var d := PackedByteArray()
		d.resize(n * 2)
		datas.append(d)
	var d0: PackedByteArray = datas[0]
	var d1: PackedByteArray = datas[1]
	var d2: PackedByteArray = datas[2]
	var d3: PackedByteArray = datas[3]
	var di: PackedByteArray = datas[4]
	for i in n:
		var j := i * 2
		d0[j] = 255; d1[j] = 255; d2[j] = 255; d3[j] = 255; di[j] = 255
		var b := biome[i]
		if sim.ter[i] == Sim.WATER:
			if _freeze.size() == n and _freeze[i] != 0:
				di[j + 1] = 255
		else:
			match b:
				0: d0[j + 1] = 255
				1: d1[j + 1] = 255
				2: d2[j + 1] = 255
				3: d3[j + 1] = 255
	# for the ground shader: the four climates in the four channels of one picture, the ice in another
	var md := PackedByteArray()
	md.resize(n * 4)
	var idd := PackedByteArray()
	idd.resize(n)
	for i in n:
		md[i * 4] = d0[i * 2 + 1]; md[i * 4 + 1] = d1[i * 2 + 1]; md[i * 4 + 2] = d2[i * 2 + 1]; md[i * 4 + 3] = d3[i * 2 + 1]
		idd[i] = di[i * 2 + 1]
	_masks = [ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, md))]
	_ice = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_R8, idd))


## A white picture, 4 pixels per tile, from data (white and opacity per tile), with soft edges.
func _mask_tex(data: PackedByteArray) -> ImageTexture:
	var img := Image.create_from_data(sim.w, sim.h, false, Image.FORMAT_LA8, data)
	img.convert(Image.FORMAT_RGBA8)
	img.resize(sim.w * 4, sim.h * 4, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


## Whether snow lies in any climate now (the map view skips the roofs otherwise).
func any_snow() -> bool:
	for v in _snow:
		if float(v) > 0.03:
			return true
	return false


## How much snow lies on tile i now (0 none .. 1 a full cover), for the snow on roofs.
func snow_at(i: int) -> float:
	if biome.is_empty() or i < 0 or i >= biome.size():
		return 0.0
	return float(_snow[biome[i]])


## How much snow should lie in biome k: from nothing above 1 C to a full cover at -7 C.
func _snow_target(k: int) -> float:
	var t := biome_temp(k)
	var s := clampf((2.0 - t) / 7.0, 0.0, 1.0)
	if weather[k] == "snow" or weather[k] == "blizzard":
		s = maxf(s, 0.6)
	return s


func draw_map(view: CanvasItem, _rect: Rect2i) -> void:
	if _masks.is_empty() or not view.has_method("set_season"):
		return
	var s := season()
	var ph := fmod(phase() * 4.0, 1.0)
	# a warm, golden-brown cast through autumn, strongest in its middle
	var autumn := sin(ph * PI) if s == 2 else 0.0
	# the fresh green of early summer
	var green := sin(ph * PI) * 0.5 if s == 1 else 0.0
	var snow := Vector4.ZERO
	for k in 4:
		# snow settles and melts over about half a game minute, however fast the game runs
		_snow[k] = lerpf(float(_snow[k]), _snow_target(k), clampf((sim.time - _snow_t) / 30.0, 0.0, 1.0))
		snow[k] = 0.6 * float(_snow[k])
	_snow_t = sim.time
	# the river ice: it sets over about twenty game seconds once the rivers freeze, and grows grey and
	# cracked as the thaw draws near; the snow on it follows the taiga's snow
	var frozen := not sim.ice.is_empty()
	_ice_vis = lerpf(_ice_vis, 1.0 if frozen else 0.0, clampf((sim.time - _ice_t) / (20.0 if frozen else 5.0), 0.0, 1.0))
	_ice_t = sim.time
	var ice := Color(0.86, 0.93, 0.98, 0.95 * _ice_vis)
	var thin := clampf(1.0 - thaw_in() / (ICE_WARN * 1.6), 0.0, 1.0) if frozen else 1.0
	# laid on by the ground shader (so it lines up with raised ground and looks the same in OpenGL
	# and Vulkan, which drew the old see-through overlays solid)
	view.set_season(_masks[0], _ice, {
		"tint0": BIOME_TINT[0], "tint1": BIOME_TINT[1], "tint2": BIOME_TINT[2], "tint3": BIOME_TINT[3],
		"autumn_col": Color(0.85, 0.48, 0.12, 0.16 * autumn), "green_col": Color(0.35, 0.75, 0.25, 0.08 * green),
		"snow_amt": snow, "ice_col": ice, "ice_thin": thin, "ice_snow": float(_snow[TAIGA])})


func draw_overlay(view: CanvasItem, to_tile: Callable) -> void:
	if biome.is_empty():
		return
	var sz: Vector2 = (view as Control).size
	if _parts.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = 7
		for n in 260:
			_parts.append(Vector3(r.randf(), r.randf(), r.randf()))
	var t := Time.get_ticks_msec() / 1000.0
	# storms darken the sky over the middle of the view, and lightning flashes now and then
	var mid: Vector2i = to_tile.call(sz / 2.0)
	var cw := String(weather[biome_at(mid.x, mid.y)])
	if cw == "storm" or cw == "blizzard":
		view.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.07, 0.12, 0.16))
		if cw == "storm" and fmod(t, 9.7) < 0.12:
			view.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.22))
	elif cw == "heat":
		view.draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 0.6, 0.2, 0.07))
	elif cw == "cloudy" or cw == "rain":
		view.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.1, 0.12, 0.16, 0.06))
	var fog = sim.get_feature("fog")
	# what falls where: the weather over a coarse grid of the screen, worked out five times a second
	# (or when the view moves) instead of for every drop every frame
	var c0: Vector2i = to_tile.call(Vector2.ZERO)
	var c1: Vector2i = to_tile.call(sz)
	var key := "%d,%d,%d,%d,%d,%d" % [c0.x, c0.y, c1.x, c1.y, Time.get_ticks_msec() / 200, weather.hash()]
	if key != _grid_key:
		_grid_key = key
		_grid = []
		for gy in GY:
			for gx in GX:
				var tl: Vector2i = to_tile.call(Vector2((gx + 0.5) * sz.x / GX, (gy + 0.5) * sz.y / GY))
				var wv := ""
				if sim.inb(tl.x, tl.y) and (fog == null or fog.explored_at(tl.y * sim.w + tl.x)):
					wv = String(weather[biome_at(tl.x, tl.y)])
				_grid.append(wv)
	for q: Vector3 in _parts:
		var x0 := q.x * sz.x
		var spd := 0.6 + q.z * 0.6
		# the weather of the biome under the drop's column decides what falls there
		var wx := String(_grid[mini(GY - 1, int(q.y * GY)) * GX + mini(GX - 1, int(q.x * GX))])
		if wx == "":
			continue
		var at := Vector2.ZERO
		match wx:
			"rain", "storm":
				var fall := fmod(q.y * sz.y + t * 900.0 * spd, sz.y + 40.0) - 20.0
				var drift := (t * 120.0 * spd) if wx == "storm" else t * 40.0
				at = Vector2(fmod(x0 + drift, sz.x), fall)
			"snow", "blizzard":
				var fall2 := fmod(q.y * sz.y + t * (60.0 if wx == "snow" else 200.0) * spd, sz.y + 10.0) - 5.0
				var sway := sin(t * 1.5 + q.z * 9.0) * 12.0 + (t * 160.0 * spd if wx == "blizzard" else 0.0)
				at = Vector2(fmod(x0 + sway + sz.x, sz.x), fall2)
			"fog":
				at = Vector2(fmod(x0 + t * 8.0 * spd, sz.x + 200.0) - 100.0, q.y * sz.y)
			_:
				continue
		# nothing falls on land you have never seen (or off the map)
		if at.x < 0.0 or at.y < 0.0 or at.x >= sz.x or at.y >= sz.y:
			if wx != "fog":
				continue
		elif String(_grid[mini(GY - 1, int(at.y / sz.y * GY)) * GX + mini(GX - 1, int(at.x / sz.x * GX))]) == "":
			continue
		match wx:
			"rain", "storm":
				view.draw_line(at, at + Vector2(5.0 if wx == "storm" else 2.0, 16.0), Color(0.72, 0.8, 0.95, 0.38), 1.2)
			"snow", "blizzard":
				view.draw_circle(at, 1.4 + q.z * 1.6, Color(1, 1, 1, 0.8))
			"fog":
				view.draw_circle(at, 70.0 + q.z * 50.0, Color(0.85, 0.88, 0.9, 0.035))


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	return {"weather": weather, "until": weather_until, "rng": rng.state, "seed": rng.seed, "season": last_season, "paved": _paved, "year": year_kind, "realm_t": _realm_t, "ice": ice_on, "ice_warned": ice_warned}


func load_state(d: Dictionary) -> void:
	weather = d.get("weather", weather)
	weather_until = d.get("until", weather_until)
	year_kind = d.get("year", ["", "", "", ""])
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng", 0))
	last_season = int(d.get("season", -1))
	_ice_known = d.has("ice")
	ice_on = bool(d.get("ice", false))
	ice_warned = bool(d.get("ice_warned", false))
	_paved = {}
	var pv: Dictionary = d.get("paved", {})
	for k in pv:
		_paved[int(k)] = float(pv[k])
	# the temperatures of the last whole second (each realm's turn within the second uses them)
	_realm_t = {}
	if d.has("realm_t"):
		var rt: Dictionary = d.realm_t
		for k in rt:
			_realm_t[int(k)] = float(rt[k])


## Whether a storm (or a blizzard) blows at tile (x, y): ships and boats stay in harbour (build 55).
func storm_at(x: int, y: int) -> bool:
	if biome.is_empty():
		return false
	return String(weather[biome_at(x, y)]) in ["storm", "blizzard"]


## The year where realm p lives, for the side panel: "" when ordinary.
func year_text(p: Sim.Player) -> String:
	var yk: String = year_kind[biome_of(p)]
	return "" if yk == "" else "%s: %s" % [String(YEAR_KINDS[yk][0]), String(YEAR_KINDS[yk][1])]
