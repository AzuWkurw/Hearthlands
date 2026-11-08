class_name Sound
extends Node
## Sound effects and ambience. The sounds are made by tools/make_sounds.py (synthesised, no samples).
## Effects: button clicks, placing and finishing buildings, research, good and bad news, attacks, and the
## work of buildings on screen (axes, picks, hammers, saws, building sites, battles) when zoomed in.
## Ambience loops, faded in and out by what is on screen: birdsong in the warm seasons, wind in winter,
## rain when it rains where you look (with the seasons feature), and a town murmur close up.
## Volumes are in Settings and kept in user://settings.cfg.

const EFFECTS := ["click", "place", "done", "research", "coin", "good", "bad", "alert", "season", "build",
	"saw", "demolish", "chop_0", "chop_1", "chop_2", "hammer_0", "hammer_1", "hammer_2",
	"pick_0", "pick_1", "pick_2", "clash_0", "clash_1", "shot_0", "shot_1"]
const LOOPS := ["amb_meadow", "amb_wind", "amb_rain", "amb_town"]
const VOICES := 10                 # effects that can sound at once
const MIN_GAP := {"alert": 4.0, "bad": 1.5, "good": 1.0, "done": 0.4, "click": 0.03, "season": 3.0, "coin": 0.5}

var main: Main
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _amb: Dictionary = {}          # loop name -> player
var _amb_level: Dictionary = {}    # loop name -> current loudness (0 to 1), eased toward its target
var _last: Dictionary = {}         # effect -> real time it last played
var _work_t := 0.0
var _rng := RandomNumberGenerator.new()
var _shots: Dictionary = {}        # attack -> last volley times heard, so each volley sounds once


func setup(m: Main) -> void:
	main = m
	for id in EFFECTS + LOOPS:
		var path := "res://sounds/%s.wav" % id
		if ResourceLoader.exists(path):
			_streams[id] = load(path)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for id in LOOPS:
		var s: AudioStreamWAV = _streams.get(id)
		if s == null:
			continue
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2      # 16-bit mono: two bytes a sample
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		_amb[id] = p
		_amb_level[id] = 0.0


func _vol(base: float) -> float:
	var st: Settings = main.settings
	if not st.sound_on or base <= 0.0:
		return -80.0
	return linear_to_db(base * st.master_vol)


## Plays effect id at loudness vol (0 to 1). Several variants (chop_0, chop_1...) are picked at random
## when id names the family ("chop").
func play(id: String, vol := 1.0, pitch_spread := 0.06) -> void:
	if main == null or not main.settings.sound_on:
		return
	var key := id
	if not _streams.has(id):
		var vars := []
		for k in _streams:
			if String(k).begins_with(id + "_"):
				vars.append(k)
		if vars.is_empty():
			return
		key = vars[_rng.randi() % vars.size()]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(id, -99.0)) < float(MIN_GAP.get(id, 0.05)):
		return
	_last[id] = now
	var p: AudioStreamPlayer = null
	for q in _pool:
		if not q.playing:
			p = q
			break
	if p == null:
		return
	p.stream = _streams[key]
	p.volume_db = _vol(vol * main.settings.sfx_vol)
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
	elif text.begins_with("Research complete") or "enters the" in text:
		play("research", 0.8)
	elif "has broken out" in text or " died of " in text or "starved" in text or "was lost" in text or "captured a" in text or "has run dry" in text:
		play("bad", 0.7)
	elif text.begins_with("Spring has come") or text.begins_with("Summer:") or text.begins_with("Autumn:") or text.begins_with("Winter has come"):
		play("season", 0.8)
	elif "merchant" in text or "Trade with" in text:
		play("coin", 0.8)
	elif "was beaten back" in text or "refugees" in text or "Bumper harvest" in text or "Festival" in text or "Lucky find" in text or "scholar" in text or "Skilled newcomer" in text:
		play("good", 0.6)
	elif text.begins_with("Fire:") or text.begins_with("Rats") or text.begins_with("Bandits") or text.begins_with("Wolves") or text.begins_with("Mine collapse") or text.begins_with("Epidemic") or text.begins_with("Storm damage"):
		play("bad", 0.6)


func _process(delta: float) -> void:
	if main == null or main.sim.w == 0:
		return
	_ambience(delta)
	if not main.settings.sound_on or main.paused or main.setup.visible:
		return
	_gunfire()
	_work_t -= delta
	if _work_t <= 0.0:
		_work_t = _rng.randf_range(0.25, 0.6) / sqrt(maxf(1.0, main.speed))
		_work_sound()


## Now and then, the sound of one of the busy buildings on screen.
func _work_sound() -> void:
	var view: MapView = main.view
	var z := view.zoom
	if z < 14.0:
		return
	var half := view.size / 2.0 / z
	var r := Rect2(view.cam - half, half * 2.0)
	var vol := clampf((z - 10.0) / 30.0, 0.25, 1.0)
	var sim: Sim = main.sim
	for a in sim.attacks:
		if (a.fighting or a.field != 0) and r.has_point(sim.military.column_pos(a)):
			play("clash", vol * 0.8, 0.1)
			return
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
	# the nearer the middle of the screen, the louder
	var b: Sim.Bld = c[1]
	var off := (Vector2(b.x, b.y) - view.cam).length() / maxf(1.0, half.length())
	play(String(c[0]), vol * clampf(1.1 - off * 0.6, 0.35, 1.0) * 0.7, 0.08)


func _work_kind(b: Sim.Bld) -> String:
	match String(b.def.get("act", "")):
		"cut_tree": return "chop"
		"cut_rock", "dig_clay": return "pick"
	if b.def.has("mine"):
		return "pick"
	match GameData.trade(b.ty):
		"metal": return "hammer"
		"woodwork": return "saw"
		"kilns": return "hammer"
	return ""


func _ambience(delta: float) -> void:
	var st: Settings = main.settings
	var want := {"amb_meadow": 0.0, "amb_wind": 0.0, "amb_rain": 0.0, "amb_town": 0.0}
	if st.sound_on and not main.setup.visible:
		var view: MapView = main.view
		var center := Vector2i(floori(view.cam.x), floori(view.cam.y))
		var cl = main.sim.get_feature("seasons")
		var season := 1
		var wx := "clear"
		if cl != null:
			season = cl.season()
			wx = String(cl.weather[cl.biome_at(center.x, center.y)])
		var far := clampf((20.0 - view.zoom) / 12.0, 0.0, 1.0)
		var rain := wx in ["rain", "storm"]
		var cold := season == 3 or wx in ["snow", "blizzard"]
		want.amb_rain = (1.0 if wx == "storm" else 0.8) if rain else 0.0
		want.amb_wind = maxf(0.9 if cold else (0.5 if wx == "storm" else 0.0), far * 0.6)
		want.amb_meadow = 0.0 if (cold or rain) else 0.8 * (1.0 - far * 0.5)
		want.amb_town = 0.5 * clampf((view.zoom - 12.0) / 20.0, 0.0, 1.0)
	for id in _amb:
		var lv := move_toward(float(_amb_level[id]), float(want.get(id, 0.0)), delta * 0.4)
		_amb_level[id] = lv
		var p: AudioStreamPlayer = _amb[id]
		p.volume_db = _vol(lv * st.amb_vol)
		if lv > 0.001 and not p.playing:
			p.play(_rng.randf() * 10.0)
		elif lv <= 0.001 and p.playing:
			p.stop()


## Volleys of musketeers and riflemen on screen: a musket boom or a rifle crack, once per volley.
func _gunfire() -> void:
	var view: MapView = main.view
	var half := view.size / 2.0 / view.zoom
	var r := Rect2(view.cam - half - Vector2(4, 4), half * 2.0 + Vector2(8, 8))
	var seen := {}
	for a in main.sim.attacks:
		var key := a.get_instance_id()
		seen[key] = true
		var last: Array = _shots.get(key, [a.shot_t, a.dshot_t])
		if (a.shot_t > float(last[0]) or a.dshot_t > float(last[1])) and r.has_point(a.to):
			var rifles := a.amix.size() > 5 and int(a.amix[5]) > 0
			play("shot_1" if rifles else "shot_0", clampf((view.zoom - 6.0) / 30.0, 0.3, 1.0), 0.1)
		_shots[key] = [a.shot_t, a.dshot_t]
	for k in _shots.keys():
		if not seen.has(k):
			_shots.erase(k)
