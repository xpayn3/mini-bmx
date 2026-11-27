class_name RideLayers
extends Node
## Recorded sound layers driven by the ride, DiRT-style: every layer is its own set of the user's recordings,
## moved by what the physics is doing (rolling surface, stones kicked up, the suspension, close passes, the
## rider's breathing / heartbeat / grunts, ambience). Made by RideAudio; it only sets volumes / pitches and
## starts one-shots (the mixing is Godot's own audio thread: ~20 voices, a few us of script a frame).
##
## Recordings: drop .ogg / .wav files into res://assets/audio/ride/<layer>/ (any names, several = picked at
## random, never the same twice in a row) and let Godot import them. A missing / empty folder = that layer is
## silent (user rule: no synthesised placeholders). LOOPS / SHOTS below list every layer and what drives it.
## Test: BMX_LAYER_PROBE=1 prints LAYERS lines (loop levels, events fired, which folders have clips) whether or
## not any clips exist, so the driving can be checked before the recordings arrive. BMX_LAYERS=0 = off.

const ROOT := "res://assets/audio/ride/"

## loops: folder -> [bus, base dB]. Each plays continuously while its level > 0 (volume = level).
const LOOPS := {
	"roll_ground": ["Wind", -6.0],   # tyre on plain ground / grass (surface 0), level + pitch by speed
	"roll_trail":  ["Wind", -6.0],   # packed trail dirt (surface 1)
	"roll_water":  ["Wind", -6.0],   # through water (surface 2)
	"roll_sand":   ["Wind", -6.0],   # sand / dry dust (surface 3)
	"rattle":      ["Bike", -8.0],   # chain slap / frame rattle: how hard the wheels are being shaken
	"breath_calm": ["Rider", -10.0], # slow nose breathing: coasting, low heart rate
	"breath_work": ["Rider", -8.0],  # steady mouth breathing: pedalling
	"breath_hard": ["Rider", -6.0],  # gasping: sprinting, tired, winded after a crash
	"ambience":    ["World", -14.0], # the place: birds, wind in the trees (ducked a little at speed)
}
## one-shots: folder -> [bus, base dB, 3D]. 3D ones play where it happens (panned / faded from the camera).
const SHOTS := {
	"whoosh":       ["Wind", -2.0, true],    # air past a tree / rock / post that goes by close
	"stones":       ["Bike", -10.0, true],   # a stone kicked up into the frame / rim
	"susp_compress":["Bike", -8.0, true],    # fork / shock taking a quick hit
	"bottom_out":   ["Bike", -4.0, true],    # fork / shock bottoming out (clunk)
	"heartbeat":    ["Rider", -6.0, false],  # ONE beat (lub-dub); fired at the heart rate
	"breath_exhale":["Rider", -6.0, false],  # a breath let out after a jump / a sprint
	"grunt_hop":    ["Rider", -8.0, false],  # the effort of a hop / pop
	"grunt_land":   ["Rider", -6.0, false],  # a hard landing
	"grunt_crash":  ["Rider", -3.0, false],  # crashing ("oof")
}

# whoosh: what counts as a pass
const WH_MIN_V := 5.0      # m/s: slower, no whoosh
const WH_FULL_V := 20.0    # m/s: full loudness
const WH_LAT := 2.5        # m from the bike's line to the object's edge: further, nothing
const WH_MIN_H := 0.45     # m: lower objects (pebbles, roots) don't whoosh
const WH_GAP := 0.06       # s between whooshes (a fence's posts flutter, they don't stack)
# suspension: shock speed (m/s, + = compressing) that counts as a hit
const SU_HIT := 0.9
const SU_FULL := 3.0
const SU_GAP := 0.14
# heart / breath
const HR_CALM := 95.0      # bpm under which the breath is calm
const HR_HARD := 150.0     # bpm over which it is hard

var game
var _clips := {}           # layer -> Array of AudioStream
var _last := {}            # layer -> index played last
var _loops := {}           # layer -> AudioStreamPlayer
var _lvl := {}             # layer -> smoothed level 0..1
var _pool3: Array = []     # AudioStreamPlayer3D pool for 3D shots
var _p3 := 0
var _pool2: Array = []
var _p2 := 0
var _pass := {}            # object key -> last "along" distance (whoosh)
var _wh_t := 0.0
var _su_t := [0.0, 0.0]
var _bot := [false, false]
var _beat_t := 0.0
var _stone_acc := 0.0
var _pop_prev := 0.0
var _rattle := 0.0
var _sprint_prev := 0.0
var _crash_prev := false
var events := {}           # layer -> count (probe)
# gate whoosh: procedural (PassBySynth.cs), rendered on a worker as a gate comes up, played as the bike passes under it
const GATE_LOOK := 60.0    # m: gates this close are looked at
const GATE_AHEAD := 1.2    # s before the clip must start: the render is queued then (it takes ~20-40 ms)
var _gsyn = null
# vast landscape air: procedural (VastAirSynth.cs), two seamless loops (29 s, 37 s) rendered on a worker at the start,
# faded up by how open the view is (the land falling away round the rider, far and wide)
var _vsyn = null
var _vpl: Array = []
var _vast := 0.0           # 0 closed in .. 1 high over a wide open landscape (measured)
var _vast_lvl := 0.0       # what is playing (eased)
var _vast_t := 0.0
var _gstate := {}          # gate instance id -> 1 queued / 2 played
var _gpl: Array = []
var _gpi := 0
var _g_last := Vector3(INF, 0, 0)   # where the last gate whoosh played (one gate seen twice: neighbouring chunks)
var _g_last_t := 0
var _probe_t := 0.0
var _on := true


func _ready() -> void:
	_on = Env.s("BMX_LAYERS") != "0"
	for k in LOOPS:
		_clips[k] = _scan(k)
		_lvl[k] = 0.0
		if _clips[k].is_empty(): continue
		var p := AudioStreamPlayer.new()
		p.bus = Settings.bus_for(LOOPS[k][0])
		p.stream = _looped(_clips[k][randi() % _clips[k].size()])
		p.volume_db = -80.0
		add_child(p)
		_loops[k] = p
	var need3 := false; var need2 := false
	for k in SHOTS:
		_clips[k] = _scan(k)
		if _clips[k].is_empty(): continue
		if SHOTS[k][2]: need3 = true
		else: need2 = true
	if need3:
		for i in 8:
			var a := AudioStreamPlayer3D.new()
			a.unit_size = 4.0; a.max_distance = 60.0; a.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			a.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			add_child(a); _pool3.append(a)
	var gs = load("res://scripts/game/PassBySynth.cs")
	if gs != null and _on and Env.s("BMX_GATE_WHOOSH") != "0":
		_gsyn = gs.new()
		for i in 2:
			var g := AudioStreamPlayer.new()
			g.bus = Settings.bus_for("Wind")
			add_child(g); _gpl.append(g)
	var vs = load("res://scripts/game/VastAirSynth.cs")
	if vs != null and _on and Env.s("BMX_VAST_AIR") != "0":
		_vsyn = vs.new()
		_vsyn.Start(randi() % 100000)
	if need2:
		for i in 6:
			var b := AudioStreamPlayer.new()
			add_child(b); _pool2.append(b)


## the folder's imported audio (works in an export too: there only the .import / .remap names are listed)
func _scan(layer: String) -> Array:
	var out := []
	var d := DirAccess.open(ROOT + layer)
	if d == null: return out
	var seen := {}
	for f in d.get_files():
		var n := f.trim_suffix(".remap").trim_suffix(".import")
		var e := n.get_extension().to_lower()
		if not (e == "ogg" or e == "wav" or e == "mp3") or seen.has(n): continue
		seen[n] = true
		var path := ROOT + layer + "/" + n
		if ResourceLoader.exists(path):
			var s = load(path)
			if s is AudioStream: out.append(s)
	return out


func _looped(s: AudioStream) -> AudioStream:
	var c: AudioStream = s.duplicate()
	if c is AudioStreamOggVorbis or c is AudioStreamMP3: c.loop = true
	elif c is AudioStreamWAV:
		c.loop_mode = AudioStreamWAV.LOOP_FORWARD; c.loop_begin = 0
		c.loop_end = int(c.get_length() * c.mix_rate)
	return c


func has(layer: String) -> bool:
	return not _clips.get(layer, []).is_empty()


## a random clip of the layer, not the last one again
func _pick(layer: String) -> AudioStream:
	var l: Array = _clips.get(layer, [])
	if l.is_empty(): return null
	var i := randi() % l.size()
	if l.size() > 1 and i == _last.get(layer, -1): i = (i + 1) % l.size()
	_last[layer] = i
	return l[i]


## fire a one-shot: k = 0..1 loudness, at = world position for 3D layers
func shot(layer: String, k: float, at = null, pitch := 1.0) -> void:
	events[layer] = events.get(layer, 0) + 1
	if not _on or k <= 0.01: return
	var s := _pick(layer)
	if s == null: return
	var spec: Array = SHOTS[layer]
	var db: float = spec[1] + linear_to_db(clampf(k, 0.0, 1.5)) + _rider_db(spec[0])
	if spec[2] and not _pool3.is_empty():
		var a: AudioStreamPlayer3D = _pool3[_p3]; _p3 = (_p3 + 1) % _pool3.size()
		a.bus = Settings.bus_for(spec[0]); a.stream = s; a.volume_db = db; a.pitch_scale = pitch
		a.global_position = at if at != null else _bike_pos()
		a.play()
	elif not _pool2.is_empty():
		var b: AudioStreamPlayer = _pool2[_p2]; _p2 = (_p2 + 1) % _pool2.size()
		b.bus = Settings.bus_for(spec[0]); b.stream = s; b.volume_db = db; b.pitch_scale = pitch
		b.play()


## the rider's own sounds are close on the helmet cam, further off on the chase cams
func _rider_db(bus: String) -> float:
	if bus != "Rider" or game == null or game.cam == null: return 0.0
	var m := String(game.cam.mode)
	if m == "helmet": return 4.0
	if m == "trail" or m == "chase": return -2.0
	return -8.0


func _bike_pos() -> Vector3:
	var p = game.phys
	return Vector3(p.x, p.y + 0.4, p.z)


# ------------------------------------------------------------------ events from RideAudio / Game
func on_landing(impact: float, air_time: float) -> void:
	if impact > 4.0: shot("grunt_land", clampf((impact - 4.0) / 5.0, 0.3, 1.0))
	elif air_time > 0.45: shot("breath_exhale", clampf(air_time / 1.2, 0.4, 1.0))

func on_crash() -> void:
	shot("grunt_crash", 1.0)


# ------------------------------------------------------------------ every frame
func update(dt: float, st, va: float, on_ground: bool, live: bool) -> void:
	if dt <= 0.0: return
	var p = game.phys
	var k := minf(1.0, dt * 6.0)
	var hud = game.hud
	var hr: float = float(hud.hr) if hud != null and "hr" in hud else 80.0
	var life: float = float(hud.life) if hud != null and "life" in hud else 1.0
	var crashed: bool = st.crash_on
	# rolling, per surface (the tyre on the ground under the rear wheel)
	var sp := clampf(va / 14.0, 0.0, 1.2)
	for i in 4:
		var key: String = ["roll_ground", "roll_trail", "roll_water", "roll_sand"][i]
		_set_loop(key, (sp if (on_ground and int(st.surf) == i and va > 0.5) else 0.0), k, 0.8 + 0.35 * clampf(va / 16.0, 0, 1))
	# rattle: the wheels' vertical shake (smoothed), only rolling
	var shake := (absf(float(p.vw_f)) + absf(float(p.vw_r))) if live else 0.0
	_rattle += (clampf(shake / 3.0, 0.0, 1.0) * (1.0 if on_ground and va > 2.0 else 0.0) - _rattle) * minf(1.0, dt * 10.0)
	_set_loop("rattle", _rattle, 1.0, 0.95 + 0.1 * _rattle)
	# breathing: calm / work / hard by the heart rate, held in the air (half), winded while crashed
	var e := clampf((hr - HR_CALM) / (HR_HARD - HR_CALM), 0.0, 1.0)
	if st.tired or crashed: e = 1.0
	var bw := [clampf(1.0 - e * 2.0, 0, 1), 1.0 - absf(e - 0.5) * 2.0, clampf(e * 2.0 - 1.0, 0, 1)]
	var hold := 0.35 if (st.air and not crashed) else 1.0
	var br := 0.0 if not live else 1.0
	var bp := 0.96 + 0.08 * e
	_set_loop("breath_calm", bw[0] * hold * br, minf(1.0, dt * 2.0), bp)
	_set_loop("breath_work", bw[1] * hold * br, minf(1.0, dt * 2.0), bp)
	_set_loop("breath_hard", bw[2] * hold * br, minf(1.0, dt * 2.0), bp)
	# a breath let out when a sprint ends
	var spr := float(st.sprint)
	if live and _sprint_prev > 0.6 and spr < 0.2: shot("breath_exhale", 0.8)
	_sprint_prev = spr
	# ambience: always there, a little lower at speed (the wind takes over)
	_set_loop("ambience", (1.0 - 0.5 * clampf(va / 20.0, 0, 1)) if live else 0.0, minf(1.0, dt * 1.5), 1.0)
	_vast_air(dt, p, va, live)
	# heartbeat: only when it means something (tired, hurt, lying after a crash, flat out)
	var hk := 0.0
	if st.tired: hk = maxf(hk, 0.6)
	hk = maxf(hk, clampf((0.6 - life) / 0.5, 0.0, 1.0))
	if crashed: hk = maxf(hk, 0.5)
	hk = maxf(hk, clampf((hr - 170.0) / 20.0, 0.0, 0.4))
	_beat_t -= dt
	if live and hk > 0.05 and _beat_t <= 0.0:
		_beat_t = 60.0 / clampf(hr, 50.0, 200.0)
		shot("heartbeat", hk)
	elif hk <= 0.05: _beat_t = minf(_beat_t, 0.3)
	if not live: return
	# hop / pop effort
	var pf := float(st.pop_fx) if "pop_fx" in st else 0.0
	if pf > 0.6 and _pop_prev < 0.3: shot("grunt_hop", clampf(pf, 0.4, 1.0))
	_pop_prev = pf
	if crashed and not _crash_prev: on_crash()
	_crash_prev = crashed
	if crashed: return
	_whoosh(dt, p, va)
	_gates(p, va)
	_stones(dt, p, va, on_ground)
	_suspension(dt, p)


func _set_loop(key: String, level: float, k: float, pitch: float) -> void:
	_lvl[key] = float(_lvl[key]) + (level - float(_lvl[key])) * k
	var pl: AudioStreamPlayer = _loops.get(key)
	if pl == null: return
	var l: float = _lvl[key] if _on else 0.0
	if l < 0.003:
		if pl.playing: pl.stop()
		return
	if not pl.playing: pl.play(randf() * maxf(0.0, pl.stream.get_length() - 0.1))
	pl.volume_db = float(LOOPS[key][1]) + linear_to_db(l) + _rider_db(LOOPS[key][0])
	pl.pitch_scale = pitch


## an object that goes past the bike within WH_LAT of its line: one whoosh, at the object
func _whoosh(dt: float, p, va: float) -> void:
	_wh_t -= dt
	if va < WH_MIN_V or game.terrain == null:
		_pass.clear(); return
	var f: Vector3 = p.fwd()
	var seen := {}
	for c in game.terrain.colliders_near(p.x, p.z):
		if c.has("tape"): continue
		var base: float = float(c.get("base", p.y))
		var top: float = float(c.get("ceil", c.get("top", base + 1.0)))
		var h := top - base
		if c.has("fence"): h = 1.0
		if h < WH_MIN_H: continue
		var dx: float = float(c.x) - p.x; var dz: float = float(c.z) - p.z
		var along := dx * f.x + dz * f.z
		var lat := absf(dx * f.z - dz * f.x) - float(c.r)
		var key := Vector2i(roundi(float(c.x) * 50.0), roundi(float(c.z) * 50.0))
		seen[key] = along
		var prev = _pass.get(key)
		if prev != null and float(prev) > 0.0 and along <= 0.0 and lat < WH_LAT and _wh_t <= 0.0:
			var near := pow(clampf(1.0 - lat / WH_LAT, 0.0, 1.0), 1.2)
			var fast := clampf((va - WH_MIN_V) / (WH_FULL_V - WH_MIN_V), 0.15, 1.0)
			var tall := clampf(h / 2.0, 0.5, 1.0) * (0.55 if c.has("fence") else 1.0)
			shot("whoosh", near * fast * tall, Vector3(float(c.x), p.y + minf(h, 1.4) * 0.6, float(c.z)),
				0.9 + 0.25 * fast + randf_range(-0.05, 0.05))
			_wh_t = WH_GAP
	_pass = seen


## how open the land is round the rider: at 16 headings x 60 / 150 / 320 m, how far below the horizon the ground
## lies (a drop of a quarter of the distance = 14 deg = full); hemmed in by slopes counts against it
func _openness(p) -> float:
	var t = game.terrain
	if t == null or not t.has_method("deck_height"): return 0.0
	var sum := 0.0; var cnt := 0
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dx := cos(a); var dz := sin(a)
		for d: float in [60.0, 150.0, 320.0]:
			var h: float = t.deck_height(p.x + dx * d, p.z + dz * d)
			sum += clampf((p.y - h) / (d * 0.25), -1.0, 1.0)
			cnt += 1
	return clampf(sum / cnt * 1.3 + 0.15, 0.0, 1.0)


func _vast_air(dt: float, p, va: float, live: bool) -> void:
	if _vsyn == null: return
	if _vpl.is_empty():
		var got: Array = _vsyn.Take()
		if got.size() < 2: return
		for d in got:
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS; w.stereo = true; w.mix_rate = 48000; w.data = d
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD; w.loop_begin = 0; w.loop_end = (d as PackedByteArray).size() / 4
			var a := AudioStreamPlayer.new()
			a.bus = Settings.bus_for("World"); a.stream = w; a.volume_db = -80.0
			add_child(a)
			a.play(randf() * 20.0)
			_vpl.append(a)
	_vast_t -= dt
	if _vast_t <= 0.0:
		_vast_t = 0.5
		_vast = _openness(p)
	# the ride's own wind covers it at speed; quiet while it isn't the live ride (replay, photo, map)
	var want := (_vast * (1.0 - 0.5 * clampf(va / 18.0, 0.0, 1.0))) if live else 0.0
	_vast_lvl += (want - _vast_lvl) * minf(1.0, dt * 0.4)
	for i in _vpl.size():
		(_vpl[i] as AudioStreamPlayer).volume_db = -9.0 + linear_to_db(maxf(_vast_lvl, 0.001) * (0.8 if i == 0 else 0.6))


## riding under a gate (sponsor gantry, race gate): its pass-by is worked out for this pass (speed, how far off
## the middle, how high the banner is) on a worker ~1 s ahead, then played so its loudest moment is under the banner
func _gates(p, va: float) -> void:
	if _gsyn == null: return
	if va < 4.0:
		_gstate.clear(); return
	var f: Vector3 = p.fwd()
	var b := Vector3(p.x, p.y, p.z)
	var keep := {}
	for g in get_tree().get_nodes_in_group("pass_gate"):
		var m: Dictionary = g.get_meta("pass", {})
		if m.is_empty(): continue
		var at: Vector3 = m.at
		var d := at - b
		if absf(d.x) > GATE_LOOK or absf(d.z) > GATE_LOOK: continue
		var dir: Vector3 = m.dir
		var c := f.x * dir.x + f.z * dir.z   # riding with (+) or against (-) the gate's way
		if absf(c) < 0.35: continue
		var sg := signf(c)
		var ahead := (d.x * dir.x + d.z * dir.z) * sg      # m to the gate's plane
		var right := Vector3(-dir.z, 0, dir.x) * sg        # the rider's right through the gate
		# + = bike right of the middle, where it will CROSS the gate's line (it is still ~10 m off when this is read)
		var lat := -(d.x * right.x + d.z * right.z) + maxf(0.0, (d.x * dir.x + d.z * dir.z) * sg) / absf(c) * (f.x * right.x + f.z * right.z)
		var half: float = m.half
		var id := g.get_instance_id()
		var st: int = _gstate.get(id, 0)
		if ahead < -6.0: continue                          # (forgotten: passed)
		keep[id] = st
		if absf(lat) > half + 2.5: continue
		var v := va * absf(c)
		var tt := ahead / maxf(v, 0.1)                     # s until under it
		if st == 0 and ahead > 0.0 and tt < PassBySynthPeak() + GATE_AHEAD:
			var clear := maxf(1.5, float(m.clear) + at.y - p.y - 1.4) if float(m.clear) > 0.0 else 0.0   # banner over the head (0 = none)
			_gsyn.Queue(id, id % 100000, v, half, clear, lat, float(m.depth), float(m.flap), 0.8)
			keep[id] = 1
		elif st == 1 and tt <= PassBySynthPeak():
			if at.distance_to(_g_last) < 8.0 and Time.get_ticks_msec() - _g_last_t < 1500:
				keep[id] = 2; _gsyn.Forget(id); continue
			var pcm: PackedByteArray = _gsyn.Take(id)
			if pcm.is_empty():
				if ahead < 0.0: keep[id] = 2   # it came too late: let it go
				continue
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS; w.stereo = true; w.mix_rate = 48000; w.data = pcm
			var a: AudioStreamPlayer = _gpl[_gpi]; _gpi = (_gpi + 1) % _gpl.size()
			a.stream = w
			a.volume_db = (-4.0 if float(m.clear) > 0.0 else -7.0) + linear_to_db(clampf((v - 3.0) / 15.0, 0.2, 1.1))   # (flags on poles: lighter)
			a.play()
			events["gate_whoosh"] = events.get("gate_whoosh", 0) + 1
			_g_last = at; _g_last_t = Time.get_ticks_msec()
			if Env.s("BMX_LAYER_PROBE") != "":
				print("GATEWHOOSH v=%.1f lat=%.2f half=%.1f ahead=%.1f t_left=%.2f" % [v, lat, half, ahead, tt])
			keep[id] = 2
	for id in _gstate:
		if not keep.has(id) and int(_gstate[id]) == 1: _gsyn.Forget(id)
	_gstate = keep


func PassBySynthPeak() -> float:
	return 0.6   # PassBySynth.PEAK: the clip's loudest moment


## stones kicked up: a random rate by speed and how loose the ground is, more in a skid
func _stones(dt: float, p, va: float, on_ground: bool) -> void:
	if not on_ground or va < 3.0: return
	var loose: float = [0.6, 0.35, 0.0, 0.25][int(p.surf)]
	var rate := va * loose * 0.18 * (2.5 if p.skid_fx else 1.0)   # per second
	_stone_acc += rate * dt
	while _stone_acc > 1.0:
		_stone_acc -= randf_range(0.6, 1.6)
		var f: Vector3 = p.fwd()
		var at := Vector3(p.x, p.y + 0.3, p.z) - f * randf_range(0.0, 0.6)
		shot("stones", randf_range(0.3, 1.0) * clampf(va / 12.0, 0.4, 1.0), at, randf_range(0.85, 1.2))


## fork / shock: a quick hit, and the clunk when it bottoms out
func _suspension(dt: float, p) -> void:
	var f: Vector3 = p.fwd()
	for e in 2:
		_su_t[e] -= dt
		var v: float = float(p.dg_vF if e == 0 else p.dg_vR)
		var bot: bool = bool(p.dg_botF if e == 0 else p.dg_botR)
		var at := Vector3(p.x, p.y + 0.3, p.z) + f * (0.6 if e == 0 else -0.5)
		if bot and not _bot[e]: shot("bottom_out", 1.0, at)
		elif v > SU_HIT and _su_t[e] <= 0.0:
			shot("susp_compress", clampf((v - SU_HIT) / (SU_FULL - SU_HIT), 0.25, 1.0), at, randf_range(0.92, 1.08))
			_su_t[e] = SU_GAP
		_bot[e] = bot


func probe(dt: float) -> void:
	_probe_t += dt
	if _probe_t < 1.0: return
	_probe_t = 0.0
	var lv := []
	for k in LOOPS:
		if float(_lvl[k]) > 0.01: lv.append("%s=%.2f" % [k, _lvl[k]])
	var have := []
	for k in _clips:
		if not _clips[k].is_empty(): have.append("%s:%d" % [k, _clips[k].size()])
	print("LAYERS loops[%s] events%s clips[%s] vast=%.2f/%.2f" % [" ".join(lv), str(events), " ".join(have), _vast, _vast_lvl])
