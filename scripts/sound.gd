class_name Sound
extends Node
## Music, sound effects and ambience. The sounds are made by tools/make_sounds.py and the music by
## tools/make_music.py (all synthesised, no samples).
##
## Three mixer buses under Master (with a limiter): Music, Effects (a little room echo) and Ambience,
## each with its volume in Settings (kept in user://settings.cfg).
##
## Effects: interface sounds (clicks, windows, building sites placed or refused, news) play in the
## middle; sounds of the world play where they happen on screen, left or right, quieter further off:
## the work of buildings (axes, picks, hammers, saws, spades, nets, mill wheels, building sites), trees
## falling, animals on farms, the chapel bell, battles and volleys, marching columns, thunder.
## Variants of an effect (chop_0, chop_1...) are picked at random, with a little change of pitch.
##
## Ambience: loops faded in and out by what is on screen and the weather where you look: birds over
## meadows, a forest, waves on a shore, wind in winter and over mountains, rain and storms, crickets in
## summer, a town's bustle, the din of a battle and the roar of a burning building.
##
## Music: calm pieces in turn with silence between them in peacetime, a war theme while your land is
## attacked or your soldiers fight, and short cues for a new age, victory and defeat. Alerts duck the
## music for a moment.

const VARIANT_FAMILIES := ["chop", "hammer", "pick", "saw", "build", "dig", "splash", "creak", "road", "clash",
	"thunder", "treefall", "cow", "sheep", "pig"]
const SINGLES := ["voice_low", "voice_mid", "voice_high", "click", "place", "deny", "win_open", "win_close", "done", "research", "coin", "good", "bad",
	"alert", "season", "bell", "demolish", "ignite", "wolf", "horse", "march", "catapult", "shot_0", "shot_1"]
const LOOPS := ["amb_meadow", "amb_forest", "amb_shore", "amb_wind", "amb_mountain", "amb_rain", "amb_storm",
	"amb_summer", "amb_town", "amb_battle", "amb_fire"]
const PEACE := ["peace_morning", "peace_furrow", "peace_hearth", "peace_market"]
const WAR := "war_banners"
const UI_VOICES := 6
const WORLD_VOICES := 14
const MIN_GAP := {"alert": 4.0, "bad": 1.5, "good": 1.0, "done": 0.4, "click": 0.03, "season": 3.0, "coin": 0.5,
	"deny": 0.25, "win_open": 0.08, "win_close": 0.08, "treefall": 0.8, "thunder": 6.0, "bell": 20.0, "wolf": 25.0,
	"cow": 4.0, "sheep": 3.0, "pig": 3.0, "horse": 5.0, "march": 1.5, "road": 0.05, "ignite": 2.0}
## Building types whose animals call now and then: type -> sound
const ANIMAL_OF := {"dairy": "cow", "sheep_farm": "sheep", "pig_farm": "pig", "donkey_farm": "horse"}

var main: Main
var _streams: Dictionary = {}      # id -> stream (families: "chop" -> [streams])
var _ui: Array[AudioStreamPlayer] = []
var _world: Array[AudioStreamPlayer2D] = []
var _listener: AudioListener2D
var _amb: Dictionary = {}          # loop name -> player
var _amb_level: Dictionary = {}    # loop name -> current loudness (0 to 1), eased toward its target
var _amb_want: Dictionary = {}
var _amb_t := 0.0
var _last: Dictionary = {}         # effect -> real time it last played
var _work_t := 0.0
var _life_t := 3.0                 # animals, bells, wolves
var _thunder_t := 8.0
var _rng := RandomNumberGenerator.new()
var _shots: Dictionary = {}        # attack -> last volley times heard, so each volley sounds once
var _started := 0.0                # real time the sound was set up (no window sounds while the game starts)

# music
var _mus: Array[AudioStreamPlayer] = []   # two players, crossfaded
var _mus_cur := 0                  # the one playing
var _mus_level := [0.0, 0.0]       # loudness of each (0 to 1)
var _mus_target := [0.0, 0.0]
var _cue: AudioStreamPlayer
var _mood := ""                    # "menu", "peace", "war", "end"
var _gap := 4.0                    # seconds of silence left before the next piece
var _order: Array = []             # peace pieces still to play this round
var _war_quiet := 0.0              # seconds since the last fighting that concerns you
var _duck := 0.0                   # seconds the music stays lowered for a cue or an alert


func setup(m: Main) -> void:
	main = m
	_rng.randomize()
	_started = Time.get_ticks_msec() / 1000.0
	_make_buses()
	for id in SINGLES + LOOPS + PEACE + [WAR, "cue_age", "cue_victory", "cue_defeat"]:
		var st := _load(id)
		if st != null:
			_streams[id] = st
	for fam in VARIANT_FAMILIES:
		var vars: Array = []
		for k in 8:
			var st := _load("%s_%d" % [fam, k])
			if st != null:
				vars.append(st)
		if not vars.is_empty():
			_streams[fam] = vars
	for i in UI_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_ui.append(p)
	_listener = AudioListener2D.new()
	add_child(_listener)
	_listener.make_current()
	for i in WORLD_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = "Effects"
		p.max_distance = 2600.0
		p.attenuation = 1.4
		p.panning_strength = 1.3
		add_child(p)
		_world.append(p)
	for id in LOOPS:
		var s = _streams.get(id)
		if s == null:
			continue
		s = s.duplicate()
		if s is AudioStreamOggVorbis:
			s.loop = true
		elif s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = s.data.size() / 4
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = "Ambience"
		p.volume_db = -80.0
		add_child(p)
		_amb[id] = p
		_amb_level[id] = 0.0
	for i in 2:
		var mp := AudioStreamPlayer.new()
		mp.bus = "Music"
		mp.volume_db = -80.0
		mp.finished.connect(_on_piece_end.bind(i))
		add_child(mp)
		_mus.append(mp)
	_cue = AudioStreamPlayer.new()
	_cue.bus = "Music"
	add_child(_cue)
	# windows opening and closing
	get_tree().node_added.connect(_on_node_added)
	m.sim.tree_felled.connect(_on_tree_felled)
	m.sim.ended.connect(_on_ended)


func _load(id: String) -> AudioStream:
	for ext in [".ogg", ".wav"]:
		for dir in ["res://sounds/", "res://music/"]:
			if ResourceLoader.exists(dir + id + ext):
				return load(dir + id + ext)
	return null


func _make_buses() -> void:
	if AudioServer.get_bus_index("Effects") >= 0:
		return
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -0.5
	lim.threshold_db = -3.0
	AudioServer.add_bus_effect(0, lim)
	for name in ["Music", "Effects", "Ambience"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.35
	rv.damping = 0.6
	rv.wet = 0.12
	rv.dry = 1.0
	rv.spread = 0.6
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Effects"), rv)


func _db(v: float) -> float:
	return -80.0 if v <= 0.0001 else linear_to_db(v)


## The buses follow the settings.
func _apply_volumes() -> void:
	var st: Settings = main.settings
	var on := st.sound_on
	AudioServer.set_bus_volume_db(0, _db(st.master_vol if on else 0.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), _db(st.sfx_vol))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), _db(st.amb_vol))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _db(st.music_vol))


func _pick(id: String) -> AudioStream:
	var s = _streams.get(id)
	if s is Array:
		return (s as Array)[_rng.randi() % (s as Array).size()]
	if s == null:
		# "chop_2" asked for by name: its family
		var fam := id.get_slice("_", 0)
		if _streams.get(fam) is Array:
			return _pick(fam)
	return s


func _gap_ok(id: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var key := id.get_slice("_", 0) if not _streams.has(id) or _streams[id] is Array else id
	if now - float(_last.get(key, -99.0)) < float(MIN_GAP.get(key, 0.05)):
		return false
	_last[key] = now
	return true


## Plays effect id in the middle (the interface, news) at loudness vol (0 to 1). A family name
## ("chop") picks one of its variants.
func play(id: String, vol := 1.0, pitch_spread := 0.06) -> void:
	if main == null or not main.settings.sound_on:
		return
	var st := _pick(id)
	if st == null or not _gap_ok(id):
		return
	var p: AudioStreamPlayer = null
	for q in _ui:
		if not q.playing:
			p = q
			break
	if p == null:
		return
	p.stream = st
	p.volume_db = _db(vol)
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_spread, pitch_spread)
	p.play()
	if id == "alert" or id == "bad":
		_duck = maxf(_duck, 2.5)


## Plays effect id where tile position `at` is on screen: panned left or right and quieter the further
## from the middle (and not at all when far off screen).
## A short murmur of a voice ("aye", "hm?", "ho") when you pick one of your buildings (build 63);
## lower for soldiers, brighter for artisans, none for empty buildings.
func voice(b: Sim.Bld) -> void:
	if b == null or b.p != 1 or not main.settings.voices:
		return
	var wk := String(b.def.get("worker", ""))
	if b.def.has("garrison"):
		play("voice_low", 0.5, 0.08)
	elif wk == "artisan" or wk == "noble":
		play("voice_high", 0.45, 0.08)
	elif wk != "" and b.staffed:
		play("voice_mid", 0.45, 0.1)


func play_at(id: String, at: Vector2, vol := 1.0, pitch_spread := 0.08) -> void:
	if main == null or not main.settings.sound_on:
		return
	var view: MapView = main.view
	var pos := view.get_global_rect().position + (at - view.cam) * view.zoom + view.size / 2.0
	var vr := view.get_global_rect().grow(view.size.x * 0.25)
	if not vr.has_point(pos):
		return
	var st := _pick(id)
	if st == null or not _gap_ok(id):
		return
	var p: AudioStreamPlayer2D = null
	for q in _world:
		if not q.playing:
			p = q
			break
	if p == null:
		return
	_listener.global_position = view.get_global_rect().get_center()
	p.global_position = pos
	p.stream = st
	p.volume_db = _db(vol)
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_spread, pitch_spread)
	p.play()


## Called for every new line in the event log: news gets its sound.
func on_log(text: String, _col: Color) -> void:
	if text.begins_with("Building a"):
		play("place", 0.8)
	elif text.ends_with(" is finished."):
		play("done", 0.8)
	elif "attacks your" in text:
		play("alert")
	elif "enters the" in text and text.begins_with("Your realm"):
		play_cue("cue_age")
	elif text.begins_with("Research complete"):
		play("research", 0.8)
	elif text.begins_with("Fire:"):
		play("ignite", 0.8)
		play("bad", 0.5)
	elif "has broken out" in text or " died of " in text or "starved" in text or "was lost" in text or "captured a" in text or "has run dry" in text:
		play("bad", 0.7)
	elif text.begins_with("Spring has come") or text.begins_with("Summer:") or text.begins_with("Autumn:") or text.begins_with("Winter has come"):
		play("season", 0.8)
	elif "merchant" in text or "Trade with" in text:
		play("coin", 0.8)
	elif "Festival" in text:
		play("bell", 0.7)
		play("good", 0.6)
	elif "was beaten back" in text or "refugees" in text or "Bumper harvest" in text or "Lucky find" in text or "scholar" in text or "Skilled newcomer" in text or "bandits are driven out" in text or "searched the old ruins" in text:
		play("good", 0.6)
	elif text.begins_with("Rats") or text.begins_with("Bandits") or text.begins_with("Wolves") or text.begins_with("Mine collapse") or text.begins_with("Epidemic") or text.begins_with("Storm damage"):
		play("bad", 0.6)
	elif "soldiers set out" in text:
		play("march", 0.7)


func _on_node_added(n: Node) -> void:
	# real windows only: tooltips and drop-down lists are windows too, but quiet
	if n is Window and not (n is Popup) and n != get_window():
		(n as Window).visibility_changed.connect(func():
			if Time.get_ticks_msec() / 1000.0 - _started > 2.0 and is_instance_valid(n):
				play("win_open" if (n as Window).visible else "win_close", 0.55, 0.03))


func _on_tree_felled(tile: int) -> void:
	var sim: Sim = main.sim
	if main.view.zoom >= 12.0:
		play_at("treefall", Vector2(tile % sim.w + 0.5, tile / sim.w + 0.5), clampf((main.view.zoom - 8.0) / 30.0, 0.3, 0.9))


func _on_ended(win: bool) -> void:
	_set_mood("end")
	play_cue("cue_victory" if win else "cue_defeat", 1.0)


func _process(delta: float) -> void:
	if main == null or main.sim.w == 0:
		return
	_apply_volumes()
	_music(delta)
	_ambience(delta)
	if not main.settings.sound_on or main.paused or main.setup.visible:
		return
	_gunfire()
	_work_t -= delta
	if _work_t <= 0.0:
		_work_t = _rng.randf_range(0.2, 0.5) / sqrt(maxf(1.0, main.speed))
		_work_sound()
	_life_t -= delta
	if _life_t <= 0.0:
		_life_t = _rng.randf_range(2.5, 6.0)
		_life_sound()


func _view_rect() -> Rect2:
	var view: MapView = main.view
	var half := view.size / 2.0 / view.zoom
	return Rect2(view.cam - half, half * 2.0)


## Now and then, the sound of one of the busy buildings on screen (or a fight, or a marching column).
func _work_sound() -> void:
	var view: MapView = main.view
	var z := view.zoom
	if z < 12.0:
		return
	var r := _view_rect()
	var vol := clampf((z - 8.0) / 30.0, 0.25, 1.0)
	var sim: Sim = main.sim
	for a in sim.attacks:
		var at: Vector2 = sim.military.column_pos(a)
		if (a.fighting or a.field != 0) and r.has_point(at):
			play_at("clash", at, vol * 0.8, 0.1)
			return
		if not a.fighting and r.has_point(at) and _rng.randf() < 0.3:
			play_at("march", at, vol * 0.5, 0.05)
	var cands := []
	for b: Sim.Bld in sim.blds:
		if b.x < r.position.x or b.y < r.position.y or b.x > r.end.x or b.y > r.end.y:
			continue
		if b.state == "build" and b.staffed:
			cands.append(["build", b])
		elif b.working:
			var s := _work_kind(b)
			if s != "":
				cands.append([s, b])
	if cands.is_empty():
		return
	var c: Array = cands[_rng.randi() % cands.size()]
	var b: Sim.Bld = c[1]
	play_at(String(c[0]), Vector2(b.x + 0.5, b.y + 0.5), vol * 0.75, 0.08)


func _work_kind(b: Sim.Bld) -> String:
	match String(b.def.get("act", "")):
		"cut_tree": return "chop"
		"cut_rock": return "pick"
		"dig_clay", "plant": return "dig"
		"fish": return "splash"
	if b.def.has("mine"):
		return "pick"
	if b.ty == "mill" or b.ty == "paper_mill" or b.ty == "textile_mill":
		return "creak"
	if Crops.is_farm(b):
		return "dig"
	if b.ty == "catapult":
		return "catapult"
	match GameData.trade(b.ty):
		"metal": return "hammer"
		"woodwork": return "saw"
		"kilns": return "hammer"
	return ""


## Animals on the farms on screen, the chapel bell, a wolf far off, thunder in a storm.
func _life_sound() -> void:
	var view: MapView = main.view
	var sim: Sim = main.sim
	if view.zoom < 10.0:
		return
	var r := _view_rect()
	var vol := clampf((view.zoom - 6.0) / 30.0, 0.25, 0.85)
	var cands := []
	for b: Sim.Bld in sim.blds:
		if b.state != "ready" or not r.has_point(Vector2(b.x, b.y)):
			continue
		if ANIMAL_OF.has(b.ty):
			cands.append([ANIMAL_OF[b.ty], b])
		elif b.ty == "chapel" and b.staffed and _rng.randf() < 0.15:
			cands.append(["bell", b])
	if not cands.is_empty():
		var c: Array = cands[_rng.randi() % cands.size()]
		var b: Sim.Bld = c[1]
		play_at(String(c[0]), Vector2(b.x + 0.5, b.y + 0.5), vol * (0.55 if c[0] == "bell" else 0.7), 0.1)
	var wl = sim.get_feature("wildlife")
	if wl != null and _rng.randf() < 0.2:
		for a in wl.animals:
			if String(a[0]) == "wolf" and r.grow(10).has_point(Vector2(float(a[1]), float(a[2]))):
				play_at("wolf", Vector2(float(a[1]), float(a[2])), vol * 0.6, 0.05)
				break


## Volleys of musketeers and riflemen on screen: a musket boom or a rifle crack, once per volley.
func _gunfire() -> void:
	var view: MapView = main.view
	var r := _view_rect().grow(4)
	var seen := {}
	for a in main.sim.attacks:
		var key := a.get_instance_id()
		seen[key] = true
		var last: Array = _shots.get(key, [a.shot_t, a.dshot_t])
		if (a.shot_t > float(last[0]) or a.dshot_t > float(last[1])) and r.has_point(a.to):
			var rifles := a.amix.size() > 6 and int(a.amix[6]) > 0
			play_at("shot_1" if rifles else "shot_0", a.to, clampf((view.zoom - 6.0) / 30.0, 0.3, 1.0), 0.1)
		_shots[key] = [a.shot_t, a.dshot_t]
	for k in _shots.keys():
		if not seen.has(k):
			_shots.erase(k)


# ---------------------------------------------------------------- ambience

## What is on screen, sampled on a grid: [water near land, trees, mountain, open land] (shares 0 to 1).
func _screen_mix() -> Array:
	var sim: Sim = main.sim
	var r := _view_rect()
	var shore := 0
	var trees := 0
	var mtn := 0
	var open := 0
	var n := 0
	var gx := 20
	var gy := 12
	for j in gy:
		for i in gx:
			var x := int(r.position.x + r.size.x * (i + 0.5) / gx)
			var y := int(r.position.y + r.size.y * (j + 0.5) / gy)
			if not sim.inb(x, y):
				continue
			n += 1
			var k := sim.idx(x, y)
			var t := sim.ter[k]
			if t == Sim.WATER:
				# water with land within two tiles: a shore
				for o in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
					if sim.inb(x + o.x, y + o.y) and sim.ter[sim.idx(x + o.x, y + o.y)] != Sim.WATER:
						shore += 1
						break
			elif t == Sim.MOUNT:
				mtn += 1
			elif sim.deco[k] == Sim.D_TREE:
				trees += 1
			else:
				open += 1
	if n == 0:
		return [0.0, 0.0, 0.0, 0.0]
	return [float(shore) / n, float(trees) / n, float(mtn) / n, float(open) / n]


func _ambience(delta: float) -> void:
	var st: Settings = main.settings
	_amb_t -= delta
	if _amb_t <= 0.0:
		_amb_t = 0.5
		_amb_want = _ambience_targets()
	for id in _amb:
		var lv := move_toward(float(_amb_level[id]), float(_amb_want.get(id, 0.0)), delta * 0.35)
		_amb_level[id] = lv
		var p: AudioStreamPlayer = _amb[id]
		p.volume_db = _db(lv)
		if lv > 0.001 and not p.playing and st.sound_on:
			p.play(_rng.randf() * 20.0)
		elif (lv <= 0.001 or not st.sound_on) and p.playing:
			p.stop()


func _ambience_targets() -> Dictionary:
	var want := {}
	if not main.settings.sound_on or main.setup.visible:
		return want
	var view: MapView = main.view
	var sim: Sim = main.sim
	var center := Vector2i(floori(view.cam.x), floori(view.cam.y))
	var cl = sim.get_feature("seasons")
	var season := 1
	var wx := "clear"
	if cl != null and sim.inb(center.x, center.y):
		season = cl.season()
		wx = String(cl.weather[cl.biome_at(center.x, center.y)])
	var far := clampf((20.0 - view.zoom) / 12.0, 0.0, 1.0)      # 0 close up, 1 far out
	var near := 1.0 - far
	var mx := _screen_mix()
	var rain := wx in ["rain", "storm"]
	var cold := season == 3 or wx in ["snow", "blizzard"]
	var calm := not rain and not cold
	want.amb_rain = 0.7 if wx == "rain" else 0.0
	want.amb_storm = 0.9 if wx == "storm" else 0.0
	want.amb_wind = maxf(0.85 if wx == "blizzard" else (0.6 if cold else 0.0), far * 0.35)
	want.amb_mountain = clampf(float(mx[2]) * 2.0, 0.0, 0.8) * (1.0 if not rain else 0.5)
	want.amb_shore = clampf(float(mx[0]) * 3.5, 0.0, 0.9) * (0.6 + 0.4 * near)
	want.amb_forest = clampf(float(mx[1]) * 2.2, 0.0, 0.85) * (1.0 if calm else 0.25)
	want.amb_meadow = clampf(float(mx[3]) * 1.4, 0.0, 0.7) * (1.0 if calm else 0.0) * (1.0 - far * 0.5)
	want.amb_summer = 0.45 * clampf(float(mx[3]) * 2.0, 0.0, 1.0) if season == 1 and calm else 0.0
	# a town's bustle, battles and fires: close up, by how much of it there is on screen
	var r := _view_rect()
	var blds := 0
	for b: Sim.Bld in sim.blds:
		if r.has_point(Vector2(b.x, b.y)):
			blds += 1
	want.amb_town = clampf(blds / 25.0, 0.0, 0.6) * near
	var fight := 0.0
	for a in sim.attacks:
		if (a.fighting or a.field != 0) and r.grow(3).has_point(sim.military.column_pos(a)):
			fight += a.n
	want.amb_battle = clampf(fight / 12.0, 0.0, 0.8) * (0.5 + 0.5 * near)
	var fires = sim.get_feature("fires")
	var heat := 0.0
	if fires != null:
		for bid in fires.burning:
			var b: Sim.Bld = sim.by_id.get(bid)
			if b != null and r.grow(2).has_point(Vector2(b.x, b.y)):
				heat += float(fires.burning[bid].get("heat", 0.5))
	want.amb_fire = clampf(heat, 0.0, 0.85) * (0.4 + 0.6 * near)
	# thunder in a storm
	_thunder_t -= 0.5
	if wx == "storm" and _thunder_t <= 0.0 and not main.paused:
		_thunder_t = _rng.randf_range(9.0, 25.0)
		play("thunder", _rng.randf_range(0.5, 0.9), 0.1)
	return want


# ---------------------------------------------------------------- music

## A short cue (new age, victory, defeat) over the music, which ducks under it.
func play_cue(id: String, vol := 0.9) -> void:
	var st: AudioStream = _streams.get(id)
	if st == null or main == null:
		return
	_cue.stream = st
	_cue.volume_db = _db(vol)
	_cue.play()
	_duck = maxf(_duck, st.get_length() + 0.5)


func _set_mood(m: String) -> void:
	if m == _mood:
		return
	var was := _mood
	_mood = m
	match m:
		"war":
			_start_piece(WAR, 2.0)
		"peace", "menu":
			# out of a war: the war theme fades and the next calm piece comes after a short silence
			_fade_out()
			_gap = 6.0 if was == "war" else (1.5 if m == "menu" else 4.0)
		"end":
			_fade_out()
			_gap = 1e9


func _fade_out() -> void:
	_mus_target = [0.0, 0.0]


func _start_piece(id: String, _fade := 2.0) -> void:
	var st: AudioStream = _streams.get(id)
	if st == null:
		return
	# crossfade: the other player takes the new piece
	var nxt := 1 - _mus_cur
	_mus_target[_mus_cur] = 0.0
	_mus_cur = nxt
	var p := _mus[nxt]
	p.stream = st
	p.play()
	_mus_level[nxt] = 0.0
	_mus_target[nxt] = 1.0


## The calm pieces for the age your realm is in (build 63): the early ones alone in the first three ages,
## the court dance joining from the Renaissance, the foundry in the Industrial age (and the oldest leaving).
func _peace_for_age() -> Array:
	var age := main.sim.human().age if main.sim != null and not main.sim.players.is_empty() else 1
	if age >= 6:
		return ["peace_foundry", "peace_court", "peace_market", "peace_foundry"]
	if age >= 4:
		return ["peace_court", "peace_hearth", "peace_market", "peace_furrow", "peace_court"]
	return PEACE


func _next_peace() -> void:
	if _order.is_empty() or _order_age != _age_now():
		_order_age = _age_now()
		_order = _peace_for_age().duplicate()
		_order.shuffle()
	_start_piece(String(_order.pop_front()))


var _order_age := -1

func _age_now() -> int:
	return main.sim.human().age if main.sim != null and not main.sim.players.is_empty() else 1


func _on_piece_end(i: int) -> void:
	if i != _mus_cur:
		return
	_mus_target[i] = 0.0
	_mus_level[i] = 0.0
	if _mood == "war":
		_start_piece(WAR)
	else:
		# silence between the calm pieces, as in The Settlers
		_gap = _rng.randf_range(20.0, 60.0)


func _music(delta: float) -> void:
	var sim: Sim = main.sim
	# what the music should be
	if main.setup.visible:
		_set_mood("menu")
	elif sim.over:
		_set_mood("end")
	else:
		var fighting := false
		for a in sim.attacks:
			if a.p == 1:
				fighting = true
				break
			var t: Sim.Bld = sim.by_id.get(a.tgt)
			if t != null and t.p == 1:
				fighting = true
				break
		_war_quiet = 0.0 if fighting else _war_quiet + delta
		if fighting:
			_set_mood("war")
		elif _mood == "war" and _war_quiet > 20.0:
			_set_mood("peace")
		elif _mood != "war":
			_set_mood("peace")
	if (_mood == "peace" or _mood == "menu") and not _mus[0].playing and not _mus[1].playing:
		_gap -= delta
		if _gap <= 0.0:
			if _mood == "menu":
				_start_piece(PEACE[0])
			else:
				_next_peace()
	_duck = maxf(0.0, _duck - delta)
	var duck_f := 0.35 if _duck > 0.0 else 1.0
	for i in 2:
		_mus_level[i] = move_toward(float(_mus_level[i]), float(_mus_target[i]), delta / 2.5)
		var p := _mus[i]
		p.volume_db = _db(float(_mus_level[i]) * duck_f * 0.8)
		if _mus_level[i] <= 0.0 and _mus_target[i] <= 0.0 and p.playing:
			p.stop()
