class_name TapeSim
extends MeshInstance3D
## Torn race tape (from tape.js TapeSim): ride into a span and it stretches over the bike, then SNAPS at the hit; the two
## halves become light foil ribbons simulated with Verlet that stream and float in the wind from their
## stakes, drape over the ground -- or, now and then (25 %), rip off the stake and blow away.
## All strips are drawn as one double-sided ribbon strip mesh (rebuilt each frame from packed arrays in one
## call), lit like the intact tape. While the bike holds a span it is posed exactly (straight once taut, a
## parabola while slack), not simulated, so it stays on the tyre at any speed.

const SEG := 30                  # TerrainChunkBuilder.TAPE_SEG
const WIDTH := 0.075
const MAX_STRIPS := 40
const SUB := 3
const ITER := 6
const SNAP_STRAIN := 0.07      # the tape tears once stretched 7 % past its length (pulled straight first; was 17 %: too rubbery)
const SUBD := 4                  # drawn: each sim segment is split into 4 along a smooth spline
const RECOIL := 3.5              # m/s: a torn end whips back towards its stake this fast (x how far past SNAP_STRAIN; was 7: it looped and flickered)
const SAG_EASE := 22.0           # 1/s: a held span's sag follows the slack this fast (smooths it pulling taut)
const SETTLE := 1.3              # a released (not torn) tape springs back this long, then is whole again
const LOD_NEAR := 30.0           # strips further than this from the rider step every LOD_EVERY frames ...
const LOD_EVERY := 3             # ... with the frames' time added up (far, small: nobody sees the difference)
const CS := "res://scripts/world/TapeStripCs.cs"

var terrain: Terrain
## a held span tore (speed = the bike's ground speed, m/s): Game pops "SNAP!" then, not at the first touch
signal torn(speed: float)
var strips: Array = []           # [{P, Q, seg, pin, cols, age, tw, last, tr, tk, ta, td, tp, G, V, N}]
var _amesh := ArrayMesh.new()
var _dirty := false
var _warm := false               # a first surface has been made with the strip material (its shader compiled)
var _cs: Object = null           # TapeStripCs (null without C# or with BMX_TAPE_GD=1: the GDScript _step / _ribbon)
var _redraw := false             # a strip moved / came / went this frame: rebuild the mesh
var _frame := 0
var _t := 0.0                    # the wind clock (twist of the ribbons)
var _next_id := 0


func _init() -> void:
	mesh = _amesh
	top_level = true                # strip vertices are in world space
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # JS: receiveShadow only
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/world/tape_strip.gdshader")
	material_override = m
	extra_cull_margin = 16384.0     # JS: frustumCulled = false
	if Env.s("BMX_TAPE_GD") == "":
		_cs = CrashLog.cs_new(CS)


func clear() -> void:
	strips.clear()
	_amesh.clear_surfaces()
	_dirty = false
	_redraw = false


## the bike (velocity vel) ran into span `sp` near `hit` (x, z). The tape doesn't snap at once: the span
## (hidden by the caller) becomes a sim strip pinned at both stakes, its hit point carried on the bike's
## front (`push_at`, set every frame by the game). It pulls taut, stretches, and only when it has stretched
## SNAP_STRAIN past its length does it tear there - the two halves spring back towards their stakes.
## Stop, back off or slide off its end before that and it springs back and is whole again.
func grab(sp: Dictionary, hit: Vector2, vel: Vector3) -> void:
	var pts: PackedVector3Array = sp["pts"]
	var n := pts.size()
	var A := pts[0]
	var B := pts[n - 1]
	var ab := Vector2(B.x - A.x, B.z - A.z).normalized()
	var nrm := Vector2(-ab.y, ab.x)
	var vv := Vector2(vel.x, vel.z)
	var s0 := signf(vv.dot(nrm)) if absf(vv.dot(nrm)) > 0.05 else signf(Vector2(hit.x - A.x, hit.y - A.z).dot(nrm) + 1e-6) * -1.0
	var segs := PackedFloat32Array()
	var rest := 0.0
	for i in n - 1:
		var l := pts[i].distance_to(pts[i + 1])
		segs.append(l)
		rest += l
	var cols := []
	for i in n - 1:
		cols.append((sp["cols"] as Array)[i & 1])
	_add(pts.duplicate(), pts.duplicate(), cols, sp["len"] / SEG, A)
	var st: Dictionary = strips[strips.size() - 1]
	st.merge({"state": "stretch", "pin2": B, "segs": segs, "rest": segs.duplicate(), "rest_len": rest,
		"sp": sp, "nrm": nrm * s0, "grab": -1, "tw_k": 0.0, "vel": vel, "strain": -1.0})


## tear a stretched strip at its grab point: two pinned halves (or one blown free) that recoil
func _snap(s: Dictionary) -> void:
	var P: PackedVector3Array = s["P"]
	var Q: PackedVector3Array = s["Q"]
	var n := P.size()
	var gi: int = s["grab"]
	var span_cols: Array = (s["sp"] as Dictionary)["cols"]
	var vel: Vector3 = s["vel"]
	var h: float = s["last"]
	var over := clampf((float(s["strain"]) + 0.05) / (SNAP_STRAIN + 0.05), 0.5, 1.5)
	var idx := [range(0, gi + 1), range(n - 1, gi - 1, -1)]
	var sp: Dictionary = s["sp"]
	var spd := Vector2(vel.x, vel.z).length()
	torn.emit(spd)
	for side in 2:
		var ii: Array = idx[side]
		var m := ii.size()
		if m < 2:
			continue
		var hp := PackedVector3Array()
		var hq := PackedVector3Array()
		var stake: Vector3 = P[ii[0]]
		for j in m:
			var k := float(j) / (m - 1)
			var p := P[ii[j]]
			# the stored stretch springs back: the torn end whips back past its stake, faster the
			# harder it was pulled; the very end flicks on with the bike a little
			var back := (stake - p)
			back.y = 0.0
			var rv := back.normalized() * (RECOIL * over * k * k) if back.length_squared() > 1e-6 else Vector3.ZERO
			rv += vel * 0.2 * k * k + Vector3(0, 0.8 * k * k * randf(), 0)
			hp.append(p)
			hq.append(p - (rv + (P[ii[j]] - Q[ii[j]]) / h * 0.3) * (1.0 / 60.0))
		var cols := []
		for j in m - 1:
			cols.append(span_cols[(SEG - 1 - j if side else j) & 1])
		# the snap yanks the stake towards where the tape was pulled: the faster, the likelier it leans,
		# snaps off or comes out (the torn half stays tied to it and goes along)
		var pull := P[gi] - stake
		var res := {}
		if terrain:
			res = terrain.stake_yank(sp["kb"] if side else sp["ka"], pull, spd / 11.0 * over * randf_range(0.55, 1.45), vel, sp)
		var pin = res["to"] if res.has("to") else (null if randf() < 0.15 else stake)
		_add(hp, hq, cols, float(s["seg"]), null)
		var t: Dictionary = strips[strips.size() - 1]
		# its own length piece by piece (with the sag it hung with): a uniform span / SEG is shorter, and the first
		# step yanked the points together into loops that spun the ribbon edge-on and back (flicker)
		var rest: PackedFloat32Array = s["rest"]
		var hs := PackedFloat32Array()
		for j in m - 1:
			hs.append(rest[ii[j] if side == 0 else ii[j + 1]])
		t["segs"] = hs
		_set_end(t, 0, pin)
		t["last"] = 1.0 / 60.0
		t["tw_k"] = 0.0


## a whole span let go at one or both stakes (its stake was knocked over / out): a sim strip from its
## stake A end to its B end, each end tied to `ta` / `tb` (Vector3 = fixed, {body, off} = on a flying
## stake, null = loose). The caller has taken the span out of its chunk's mesh.
func hang(sp: Dictionary, ta, tb) -> void:
	var pts: PackedVector3Array = sp["pts"]
	var cols := []
	for i in pts.size() - 1:
		cols.append((sp["cols"] as Array)[i & 1])
	_add(pts.duplicate(), pts.duplicate(), cols, sp["len"] / SEG, null)
	var t: Dictionary = strips[strips.size() - 1]
	var segs := PackedFloat32Array()
	var rest := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		segs.append(l)
		rest += l
	t.merge({"segs": segs, "rest_len": rest, "tw_k": 0.0, "tw_cap": 0.15})   # still a whole tape: hardly twists
	_set_end(t, 0, ta)
	_set_end(t, 1, tb)


## strips tied at `old` (a stake's tie point) are now tied to `to` (its new tie point / flying piece / nothing)
func retarget(old: Vector3, to) -> void:
	for s in strips:
		if s.get("state", "free") == "stretch":
			continue
		for e in 2:
			var p = s.get("pin" if e == 0 else "pin2")
			if p != null and not s.has("pb" if e == 0 else "pb2") and (p as Vector3).distance_squared_to(old) < 0.0064:
				_set_end(s, e, to)


func _set_end(s: Dictionary, e: int, to) -> void:
	var key := "pin" if e == 0 else "pin2"
	var pbk := "pb" if e == 0 else "pb2"
	if to is Dictionary:
		s[pbk] = to
		s[key] = (to["body"] as Node3D).global_transform * (to["off"] as Vector3)
	else:
		s.erase(pbk)
		s[key] = to
	if to != null:
		var P: PackedVector3Array = s["P"]
		P[0 if e == 0 else P.size() - 1] = s[key]
		s["P"] = P


## ends tied to a flying stake follow it; a tape tied at both ends that runs out of length pulls the
## stake back (it swings / drops short), and pulled much further the knot slips off
func _follow(s: Dictionary, dt: float) -> void:
	for e in 2:
		var pbk := "pb" if e == 0 else "pb2"
		if not s.has(pbk):
			continue
		var d: Dictionary = s[pbk]
		var b = d["body"]
		var key := "pin" if e == 0 else "pin2"
		if not is_instance_valid(b) or not (b as Node).is_inside_tree() or (b as Node).is_queued_for_deletion():
			s.erase(pbk)   # come to rest: the tape stays tied where it lies
			continue
		var body := b as RigidBody3D
		var p: Vector3 = body.global_transform * (d["off"] as Vector3)
		s[key] = p
		var other = s.get("pin2" if e == 0 else "pin")
		if other == null or not s.has("rest_len"):
			continue
		var dv: Vector3 = other - p
		var L := dv.length()
		var R: float = s["rest_len"]
		if L > R * 1.35:
			s.erase(pbk)
			s[key] = null
		elif L > R:
			body.apply_impulse(dv / L * minf((L - R) * 90.0 * dt, 1.5) * body.mass, p - body.global_position)


## the drawn bike's front while riding (null = no rider / crashed): {axle, fwd (heading, flat), axis (steering
## axis, up the fork), r (front wheel radius)}, set by Game every frame. Where a span catches on it depends on the
## tape's height: on the tyre's front below the tyre's top, on the front of the fork above it (TapeSim._contact)
var push_at = null


## where the bike holds tape at height y: the tyre's front at that height, or above the tyre the fork's front
## (the steering axis + a stanchion's radius). The tape used to wrap round the tyre's leading edge at axle
## height moved up to 85 cm: a corner hanging in the air half a metre in front of the bars.
func _contact(y: float) -> Vector3:
	var ax: Vector3 = push_at["axle"]
	var fwd: Vector3 = push_at["fwd"]
	var axis: Vector3 = push_at["axis"]
	var r: float = push_at["r"]
	var h := y - ax.y
	if h < r * 0.9:
		var f := sqrt(maxf(r * r - h * h, 0.0))
		return Vector3(ax.x + fwd.x * f, y, ax.z + fwd.z * f)
	var q := ax + axis * (h / maxf(axis.y, 0.3)) + fwd * 0.05
	return Vector3(q.x, y, q.z)


func _stretch(s: Dictionary, dt: float) -> String:
	var A: Vector3 = s["pin"]
	var B: Vector3 = s["pin2"]
	var n: int = (s["P"] as PackedVector3Array).size()
	if push_at == null:
		return "release"
	var rp: PackedVector3Array = (s["sp"] as Dictionary)["pts"]
	var ab := Vector2(B.x - A.x, B.z - A.z)
	var L2 := ab.length_squared()
	# the tape's height where the bike is: from the span as it hung (the axle's spot along it is near enough)
	var ax: Vector3 = push_at["axle"]
	var t0 := clampf(Vector2(ax.x - A.x, ax.z - A.z).dot(ab) / L2, 0.0, 1.0)
	var fi := t0 * (n - 1)
	var i0 := mini(int(fi), n - 2)
	var pa := _contact(lerpf(rp[i0].y, rp[i0 + 1].y, fi - i0))
	var t := clampf(Vector2(pa.x - A.x, pa.z - A.z).dot(ab) / L2, -1.0, 2.0)
	var nrm: Vector2 = s["nrm"]
	var d := Vector2(pa.x - A.x, pa.z - A.z).dot(nrm)
	# caught by the tyre's leading edge, the fork reaches the tape a little later: the tape stays as it hung till
	# then. Backing out from where it was caught (or a crash) lets it go; otherwise it stretches and snaps, also
	# when the bike runs along it to a stake (it used to let go at a span's end: "it ignores it")
	if not s.has("d0"): s["d0"] = minf(d, 0.0)
	if d < float(s["d0"]) - 0.35:
		if Env.s("BMX_TAPE_PROBE") != "": print("TAPEREL t=%.2f d=%.2f strain=%.3f age=%.2f" % [t, d, float(s.get("strain", 0.0)), float(s["age"])])
		return "release"
	var base := A.lerp(B, t)
	var c := Vector3(base.x + nrm.x * maxf(d, 0.0), pa.y, base.z + nrm.y * maxf(d, 0.0))
	var la := maxf(A.distance_to(c), 1e-3)
	var lb := maxf(c.distance_to(B), 1e-3)
	# the tape slides over the fork / tyre, so both sides stretch alike: each gets its share of the length by
	# how far its stake is (a split by a fixed point stretched one side's stripes long and bunched the other's)
	var rest_len: float = s["rest_len"]
	var ra := rest_len * la / (la + lb)
	var rb := rest_len - ra
	s["strain"] = (la + lb) / rest_len - 1.0
	_pose_held(s, A, c, B, ra, rb, la, lb, dt)
	# the point nearest the corner: where it tears (_snap splits the strip there)
	var rest: PackedFloat32Array = s["rest"]
	var cum := 0.0
	var gi := 1
	var best := INF
	for i in n:
		if absf(cum - ra) < best:
			best = absf(cum - ra)
			gi = i
		if i < n - 1: cum += rest[i]
	s["grab"] = clampi(gi, 1, n - 2)
	s["grab_at"] = c
	if Env.s("BMX_TAPE_PROBE") != "":   # the held tape's points' acceleration (m/s^2): glitches = big jumps in it
		var P: PackedVector3Array = s["P"]
		var P1: PackedVector3Array = s.get("_p1", PackedVector3Array())
		var P2: PackedVector3Array = s.get("_p2", PackedVector3Array())
		var d1: float = s.get("_d1", dt)
		if P2.size() == P.size() and dt > 0.0 and d1 > 0.0:
			var j := 0.0
			for i in P.size():
				var aa := ((P[i] - P1[i]) / dt - (P1[i] - P2[i]) / d1).length() / dt
				j = maxf(j, aa)
			var acc: Array = s.get("_acc", [])
			acc.append(j)

			s["_acc"] = acc
		s["_p2"] = P1
		s["_p1"] = P.duplicate()
		s["_d1"] = dt
	return "snap" if float(s["strain"]) > SNAP_STRAIN else ""


## a held span, posed exactly every frame: each side runs from its stake to the corner c on the bike, straight
## (and stretched evenly) once it's pulled taut, sagging in a parabola of the right length while it's slack. The
## points are laid by their length along the tape (ra of it on A's side), so the corner sits between two points
## and moves smoothly (pinning the nearest point made it hop ~25 cm as that changed).
## Q keeps last frame's points so the strip carries its velocity on when it's let go or tears.
func _pose_held(s: Dictionary, A: Vector3, c: Vector3, B: Vector3, ra: float, rb: float, la: float, lb: float, dt: float) -> void:
	var P: PackedVector3Array = s["P"]
	var Q: PackedVector3Array = s["Q"]
	var rest: PackedFloat32Array = s["rest"]
	var n := P.size()
	var G := _ground(s, 0.0025)   # held: re-read every 5 cm (a slack side lying on the ground stepped with a 20 cm cache)
	var sag_a := sqrt(3.0 * la * (ra - la) / 8.0) if ra > la else 0.0
	var sag_b := sqrt(3.0 * lb * (rb - lb) / 8.0) if rb > lb else 0.0
	# that sag goes with sqrt(slack): just before it pulls taut it falls steeply, and the middle snapped up into
	# line in a frame or two (a twitch). Eased instead (~SAG_EASE), from the sag it had when it was caught
	if s.has("sga"):
		var k := 1.0 - exp(-dt * SAG_EASE)
		sag_a = lerpf(float(s["sga"]), sag_a, k)
		sag_b = lerpf(float(s["sgb"]), sag_b, k)
	s["sga"] = sag_a
	s["sgb"] = sag_b
	var cum := 0.0
	for i in n:
		var p: Vector3
		if cum <= ra:
			var u := cum / ra
			p = A.lerp(c, u) - Vector3(0, sag_a * 4.0 * u * (1.0 - u), 0)
		else:
			var u := (cum - ra) / rb
			p = c.lerp(B, u) - Vector3(0, sag_b * 4.0 * u * (1.0 - u), 0)
		p.y = maxf(p.y, G[i] + 0.01)
		Q[i] = P[i]
		P[i] = p
		if i < n - 1: cum += rest[i]
	s["P"] = P
	s["Q"] = Q
	s["last"] = maxf(dt, 1e-4)


## the ground under each point, re-read only for points that moved sqrt(tol2) (0.2 m) sideways (height() is costly)
func _ground(s: Dictionary, tol2 := 0.04) -> PackedFloat32Array:
	var P: PackedVector3Array = s["P"]
	var n := P.size()
	var G: PackedFloat32Array = s["G"]
	var GP: PackedVector2Array = s.get("GP", PackedVector2Array())
	if G.size() != n or GP.size() != n:
		G.resize(n)
		GP.resize(n)
		for i in n: GP[i] = Vector2(INF, INF)
	for i in n:
		var q := Vector2(P[i].x, P[i].z)
		if q.distance_squared_to(GP[i]) > tol2:
			GP[i] = q
			G[i] = terrain.height(q.x, q.y)
	s["G"] = G
	s["GP"] = GP
	return G


func _add(P: PackedVector3Array, Q: PackedVector3Array, cols: Array, seg_len: float, pin) -> void:
	while strips.size() >= MAX_STRIPS:
		var old: Dictionary = strips.pop_front()
		if old.has("sp") and terrain: terrain.restore_tape(old["sp"])
	var tw := PackedFloat32Array()
	for i in P.size():
		tw.append(randf() * 6.28)
	# each strip twists its own way: rate, how quickly the twist turns along it, how far, a slow drift
	_next_id += 1
	strips.append({"id": _next_id, "tb": _t, "P": P, "Q": Q, "seg": seg_len, "pin": pin, "cols": cols, "age": 0.0, "tw": tw, "last": 1.0 / 60.0,
		"tr": 1.5 + randf() * 5, "tk": 0.1 + randf() * 0.6, "ta": 0.5 + randf() * 1.4, "td": (randf() - .5) * 1.2,
		"tp": randf() * 6.28, "G": PackedFloat32Array(), "V": PackedVector3Array(), "N": PackedVector3Array()})
	_dirty = true
	_redraw = true


## t: wind clock, wdir: unit wind direction (y = 0), ws: wind speed (WIND.speed * gust * 1.5)
## BMX_TAPE_PERF=1: `TAPEPERF` once a second (strips, main-thread us per frame: average / worst)
var _pf := [0, 0, 0]
func update(dt: float, px: float, pz: float, t: float, wdir: Vector3, ws: float) -> void:
	if Env.s("BMX_TAPE_PERF") == "":
		_update(dt, px, pz, t, wdir, ws)
		return
	var t0 := Time.get_ticks_usec()
	_update(dt, px, pz, t, wdir, ws)
	var us := Time.get_ticks_usec() - t0
	_pf[0] += 1; _pf[1] += us; _pf[2] = maxi(_pf[2], us)
	if _pf[0] >= 60:
		print("TAPEPERF strips=%d avg_us=%d max_us=%d cs=%s" % [strips.size(), _pf[1] / _pf[0], _pf[2], _cs != null])
		_pf = [0, 0, 0]


func _update(dt: float, px: float, pz: float, t: float, wdir: Vector3, ws: float) -> void:
	if strips.is_empty():
		if _dirty:
			_amesh.clear_surfaces()
			_dirty = false
		elif not _warm:
			# one tiny triangle far underground with the strip material: its pipeline is made now, at the
			# start of the ride, not on the first tape you hit (a hitch right at the moment of impact)
			_warm = true
			if _cs: _cs.call("Warm")
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			var o := Vector3(px, -2000.0, pz)
			arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([o, o + Vector3(0.01, 0, 0), o + Vector3(0, 0, 0.01)])
			arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
			arr[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
			_amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			_dirty = true
		return
	if dt <= 0.0:
		return
	_frame += 1
	_t = t
	var snapped: Array = []   # torn this frame: _snap adds strips (and may drop the oldest), so after the loop
	for si in range(strips.size() - 1, -1, -1):
		var s: Dictionary = strips[si]
		s["age"] += dt
		var P: PackedVector3Array = s["P"]
		var far := Vector2(P[0].x - px, P[0].z - pz).length()
		if far > 180 and s.get("state", "free") != "free":
			strips.remove_at(si)
			_redraw = true
			if terrain: terrain.restore_tape(s["sp"])
			continue
		if far > 180 or (s["pin"] == null and s.get("pin2") == null and s["age"] > 40):
			strips.remove_at(si)
			_redraw = true
			continue
		var state: String = s.get("state", "free")
		if state == "stretch":
			match _stretch(s, dt):
				"snap":
					if Env.s("BMX_TAPE_PROBE") != "":
						var acc: Array = s.get("_acc", [0.0])
						acc.sort()
						print("TAPESNAP age=%.2f acc_median=%.0f acc_max=%.0f frames=%d" % [float(s["age"]), acc[acc.size() / 2], acc[-1], acc.size()])
					strips.remove_at(si)
					snapped.append(s)
					continue
				"release":
					s["state"] = "settle"
					s["age"] = 0.0
					s["grab"] = -1
					s["segs"] = (s["rest"] as PackedFloat32Array).duplicate()
				_:
					_ribbon_any(s, t)   # held: posed exactly by _stretch, nothing to simulate
					continue
		elif state == "settle" and s["age"] > SETTLE:
			strips.remove_at(si)
			_redraw = true
			if terrain: terrain.restore_tape(s["sp"])
			continue
		elif far > 90:   # out of sight: freeze
			continue
		var acc: float = float(s.get("acc", 0.0)) + dt   # time this strip hasn't been stepped yet
		if far > LOD_NEAR and (_frame + si) % LOD_EVERY != 0 and acc < 0.1:
			s["acc"] = acc
			continue
		s["acc"] = 0.0
		if state == "free": s["tw_k"] = minf(s.get("tw_cap", 1.0), float(s.get("tw_k", 1.0)) + acc * 1.5)   # the foil starts twisting once torn
		if s.has("pb") or s.has("pb2"): _follow(s, acc)
		_step_any(s, acc / SUB, t, wdir, ws)
		_ribbon_any(s, t)
	for s in snapped: _snap(s)
	if _redraw:
		_redraw = false
		_draw()


## one frame of the strip's sim: C# (TapeStripCs.Step) when there is one, else _step
func _step_any(s: Dictionary, h: float, t: float, wdir: Vector3, ws: float) -> void:
	if _cs == null:
		_step(s, h, t, wdir, ws)
		return
	var ratio: float = h / s["last"]
	s["last"] = h
	var pin = s["pin"]
	var pin2 = s.get("pin2")
	var r: Array = _cs.call("Step", s["P"], s["Q"], _ground(s), s.get("segs", PackedFloat32Array()), float(s["seg"]),
		h, ratio, SUB, ITER, pin != null, pin if pin != null else Vector3.ZERO, pin2 != null,
		pin2 if pin2 != null else Vector3.ZERO, int(s.get("grab", -1)), s.get("grab_at", Vector3.ZERO), t,
		(s["tw"] as PackedFloat32Array)[0], wdir, ws)
	s["P"] = r[0]
	s["Q"] = r[1]


## the strip's drawn ribbon is out of date (C#: rebuilt in _draw, GDScript: now)
func _ribbon_any(s: Dictionary, t: float) -> void:
	_redraw = true
	if _cs == null:
		_ribbon(s, t)
	else:
		s["redo"] = true


func _step(s: Dictionary, h: float, t: float, wdir: Vector3, ws: float) -> void:
	var P: PackedVector3Array = s["P"]
	var Q: PackedVector3Array = s["Q"]
	var tw: PackedFloat32Array = s["tw"]
	var n := P.size()
	var ratio: float = h / s["last"]
	s["last"] = h
	var seg_len: float = s["seg"]
	var pinned: bool = s["pin"] != null
	var pin: Vector3 = s["pin"] if pinned else Vector3.ZERO
	var pinned2: bool = s.get("pin2") != null
	var pin2: Vector3 = s["pin2"] if pinned2 else Vector3.ZERO
	var segs: PackedFloat32Array = s.get("segs", PackedFloat32Array())
	var gi: int = s.get("grab", -1)
	var gat: Vector3 = s.get("grab_at", Vector3.ZERO)
	var taut := pinned2   # a whole span: stiffer, the wind only ripples it
	var G := _ground(s)
	var drag := 3.2
	for sub in SUB:
		var r := ratio if sub == 0 else 1.0
		for i in n:
			var p := P[i]
			var q := Q[i]
			# foil: tiny mass, huge drag -- it moves towards the local wind velocity instead of falling.
			# Each point sees its own turbulent wind, so the ribbon ripples and flaps.
			var tu := t * 3 + i * 0.55 + tw[0]
			var w := wdir * (ws * (0.8 + 0.35 * sin(tu * 1.7)))
			w.x += sin(tu * 2.3 + i) * ws * 0.35
			w.z += cos(tu * 2.9 - i) * ws * 0.35
			var alt := clampf(1.0 - (p.y - G[i]) / 9.0, 0.0, 1.0)   # soars, but tops out ~9 m up
			w.y = ws * (0.16 * alt + 0.3 * sin(tu * 1.3 + i * 0.7))   # lift: foil floats and soars
			if taut: w *= 0.25
			var v := (p - q) / h * r
			var a := Vector3((w.x - v.x) * drag, (w.y - v.y) * drag - 9.81 * 0.35, (w.z - v.z) * drag)
			Q[i] = p
			P[i] = p + v * h + a * (h * h)
		for it in ITER + (6 if taut else 0):
			if pinned:
				P[0] = pin
			if pinned2:
				P[n - 1] = pin2
			if gi > 0:
				P[gi] = gat
			for i in n - 1:
				var a := P[i]
				var b := P[i + 1]
				var d := b - a
				var l := d.length()
				if l == 0.0:
					l = 1e-6
				var sl: float = segs[i] if segs.size() == n - 1 else seg_len
				var diff := (l - sl) / l
				# fixed points (stakes, the bike's grip) don't move: the other end takes it all
				var fa := (pinned and i == 0) or (gi == i)
				var fb := (pinned2 and i + 1 == n - 1) or (gi == i + 1)
				var wa := 0.0 if fa else (1.0 if fb else 0.5)
				var wb := 0.0 if fb else (1.0 if fa else 0.5)
				P[i] = a + d * (diff * wa)
				P[i + 1] = b - d * (diff * wb)
		if pinned:
			P[0] = pin
		if pinned2:
			P[n - 1] = pin2
		if gi > 0:
			P[gi] = gat
		# the ground: rest on it with friction (it can still lift off when a gust gets under it)
		for i in n:
			var p := P[i]
			var g := G[i] + 0.01
			if p.y < g:
				p.y = g
				P[i] = p
				var q := Q[i]
				q.x += (p.x - q.x) * 0.5
				q.z += (p.z - q.z) * 0.5
				q.y = p.y
				Q[i] = q
	s["P"] = P
	s["Q"] = Q


# ribbon geometry: the width direction twists slowly along the strip, like real foil tape. The sim's points
# are drawn through a Catmull-Rom spline, SUBD pieces per segment, so a floating strip bends smoothly
func _ribbon(s: Dictionary, t: float) -> void:
	var P0: PackedVector3Array = s["P"]
	var tw: PackedFloat32Array = s["tw"]
	var n0 := P0.size()
	var P := PackedVector3Array()
	P.resize((n0 - 1) * SUBD + 1)
	for i in n0 - 1:
		var pa := P0[maxi(0, i - 1)]
		var pb := P0[i]
		var pc := P0[i + 1]
		var pd := P0[mini(n0 - 1, i + 2)]
		for j in SUBD:
			var u := float(j) / SUBD
			var u2 := u * u
			var u3 := u2 * u
			P[i * SUBD + j] = 0.5 * (2.0 * pb + (pc - pa) * u + (2.0 * pa - 5.0 * pb + 4.0 * pc - pd) * u2 + (3.0 * pb - pa - 3.0 * pc + pd) * u3)
	P[P.size() - 1] = P0[n0 - 1]
	var n := P.size()
	var W := WIDTH / 2
	var tr: float = s["tr"]
	var tk: float = s["tk"]
	var ta: float = s["ta"]
	var td: float = s["td"]
	var tp: float = s["tp"]
	var twk: float = s.get("tw_k", 1.0)
	var E := PackedVector3Array()
	E.resize(n)
	for i in n:
		var fi := float(i) / SUBD   # position along the strip in sim points
		var d := (P[mini(n - 1, i + 1)] - P[maxi(0, i - 1)]).normalized()
		var ax := d.cross(Vector3.UP)
		if ax.length_squared() < 1e-4:
			ax = Vector3(1, 0, 0)
		ax = ax.normalized()
		var bx := ax.cross(d)
		var twa := (sin(tp + t * tr - fi * tk) * ta + sin(t * tr * 0.37 + fi * tk * 2.3 + tw[mini(n0 - 1, int(fi))] * 0.15) * ta * 0.5 + fi * td * 0.2 + (t - float(s.get("tb", t))) * td) * twk
		E[i] = bx * (cos(twa) * W) + ax * (sin(twa) * W)
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	V.resize((n - 1) * 6)
	N.resize((n - 1) * 6)
	var v := 0
	for i in n - 1:
		var p0 := P[i]
		var p1 := P[i + 1]
		var e0 := E[i]
		var e1 := E[i + 1]
		var nn := (p1 - p0).cross(e0).normalized()
		# the JS quad order, with each triangle's last two corners swapped: Godot's front faces are
		# clockwise, so this keeps `nn` on the front side
		V[v] = p0 + e0; V[v + 1] = p1 + e1; V[v + 2] = p0 - e0
		V[v + 3] = p1 + e1; V[v + 4] = p1 - e1; V[v + 5] = p0 - e0
		for k in 6:
			N[v + k] = nn
		v += 6
	s["V"] = V
	s["N"] = N


func _draw() -> void:
	if _cs != null:
		_dirty = int(_cs.call("Draw", _amesh, strips, _t, WIDTH, SUBD)) > 0
		return
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	for s in strips:
		var sv: PackedVector3Array = s["V"]
		if sv.is_empty():
			continue
		var sc: PackedColorArray = s.get("C", PackedColorArray())
		if sc.size() != sv.size():   # the colours never change: made once per strip
			var cols: Array = s["cols"]
			sc = PackedColorArray()
			sc.resize(sv.size())
			for k in sv.size():
				sc[k] = cols[mini(cols.size() - 1, k / (6 * SUBD))]
			s["C"] = sc
		V.append_array(sv)
		N.append_array(s["N"])
		C.append_array(sc)
	_amesh.clear_surfaces()
	_dirty = not V.is_empty()
	if not _dirty:
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	_amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
