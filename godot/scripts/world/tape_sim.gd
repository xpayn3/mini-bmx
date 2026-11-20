class_name TapeSim
extends MeshInstance3D
## Torn race tape (from tape.js TapeSim): ride into a span and it stretches over the bike, then SNAPS at the hit; the two
## halves become light foil ribbons simulated with Verlet that stream and float in the wind from their
## stakes, drape over the ground -- or, now and then (25 %), rip off the stake and blow away.
## All strips are drawn as one double-sided ribbon strip mesh (rebuilt each frame), lit like the intact tape.

const SEG := 30                  # TerrainChunkBuilder.TAPE_SEG
const WIDTH := 0.075
const MAX_STRIPS := 40
const SUB := 3
const ITER := 6
const SNAP_STRAIN := 0.17      # the tape tears once stretched 17 % past its length (pulled straight first)
const SUBD := 4                  # drawn: each sim segment is split into 4 along a smooth spline
const SETTLE := 1.3              # a released (not torn) tape springs back this long, then is whole again

var terrain: Terrain
var strips: Array = []           # [{P, Q, seg, pin, cols, age, tw, last, tr, tk, ta, td, tp, G, V, N}]
var _imesh := ArrayMesh.new()   # rebuilt each frame from packed arrays (ImmediateMesh took 3 calls per vertex)
var _dirty := false


func _init() -> void:
	mesh = _imesh
	top_level = true                # strip vertices are in world space
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # JS: receiveShadow only
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/world/tape_strip.gdshader")
	material_override = m
	extra_cull_margin = 16384.0     # JS: frustumCulled = false


func clear() -> void:
	strips.clear()
	_imesh.clear_surfaces()
	_dirty = false


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
			var rv := back.normalized() * (7.0 * over * k * k) if back.length_squared() > 1e-6 else Vector3.ZERO
			rv += vel * 0.25 * k * k + Vector3(0, 1.5 * k * k * randf(), 0)
			hp.append(p)
			hq.append(p - (rv + (P[ii[j]] - Q[ii[j]]) / h * 0.3) * (1.0 / 60.0))
		var cols := []
		for j in m - 1:
			cols.append(span_cols[(SEG - 1 - j if side else j) & 1])
		var free := randf() < 0.25
		_add(hp, hq, cols, float(s["seg"]), null if free else stake)
		var t: Dictionary = strips[strips.size() - 1]
		t["last"] = 1.0 / 60.0
		t["tw_k"] = 0.0


## the bike's front, at tape height, while riding (null = no rider / crashed)
var push_at = null


func _stretch(s: Dictionary) -> String:
	var A: Vector3 = s["pin"]
	var B: Vector3 = s["pin2"]
	var n: int = (s["P"] as PackedVector3Array).size()
	if push_at == null:
		return "release"
	var pa: Vector3 = push_at
	var ab := Vector2(B.x - A.x, B.z - A.z)
	var L2 := ab.length_squared()
	var t := clampf(Vector2(pa.x - A.x, pa.z - A.z).dot(ab) / L2, -1.0, 2.0)
	var nrm: Vector2 = s["nrm"]
	var d := Vector2(pa.x - A.x, pa.z - A.z).dot(nrm)
	if t < 0.03 or t > 0.97 or d < -0.35:
		return "release"   # backed off, or slid off its end
	var rp: PackedVector3Array = (s["sp"] as Dictionary)["pts"]
	var gi := clampi(roundi(t * (n - 1)), 1, n - 2)
	var base := A.lerp(B, t)
	var c := Vector3(base.x + nrm.x * maxf(d, 0.0), rp[gi].y, base.z + nrm.y * maxf(d, 0.0))
	s["grab"] = gi
	s["grab_at"] = c
	var la := A.distance_to(c)
	var lb := c.distance_to(B)
	var rest: PackedFloat32Array = s["rest"]
	var segs: PackedFloat32Array = s["segs"]
	var ra := 0.0
	for i in gi: ra += rest[i]
	var rb: float = float(s["rest_len"]) - ra
	s["strain"] = (la + lb) / float(s["rest_len"]) - 1.0
	# each side stretches evenly once it's pulled straight (slack sag first)
	var ka := maxf(1.0, la / ra) * 0.995
	var kb := maxf(1.0, lb / rb) * 0.995
	for i in n - 1:
		segs[i] = rest[i] * (ka if i < gi else kb)
	s["segs"] = segs
	return "snap" if float(s["strain"]) > SNAP_STRAIN else ""


func _add(P: PackedVector3Array, Q: PackedVector3Array, cols: Array, seg_len: float, pin) -> void:
	while strips.size() >= MAX_STRIPS:
		var old: Dictionary = strips.pop_front()
		if old.has("sp") and terrain: terrain.restore_tape(old["sp"])
	var tw := PackedFloat32Array()
	for i in P.size():
		tw.append(randf() * 6.28)
	# each strip twists its own way: rate, how quickly the twist turns along it, how far, a slow drift
	strips.append({"P": P, "Q": Q, "seg": seg_len, "pin": pin, "cols": cols, "age": 0.0, "tw": tw, "last": 1.0 / 60.0,
		"tr": 1.5 + randf() * 5, "tk": 0.1 + randf() * 0.6, "ta": 0.5 + randf() * 1.4, "td": (randf() - .5) * 1.2,
		"tp": randf() * 6.28, "G": PackedFloat32Array(), "V": PackedVector3Array(), "N": PackedVector3Array()})
	_dirty = true


## t: wind clock, wdir: unit wind direction (y = 0), ws: wind speed (WIND.speed * gust * 1.5)
func update(dt: float, px: float, pz: float, t: float, wdir: Vector3, ws: float) -> void:
	if strips.is_empty():
		if _dirty:
			_imesh.clear_surfaces()
			_dirty = false
		return
	var h := dt / SUB
	if h <= 0.0:
		return
	var snapped: Array = []   # torn this frame: _snap adds strips (and may drop the oldest), so after the loop
	for si in range(strips.size() - 1, -1, -1):
		var s: Dictionary = strips[si]
		s["age"] += dt
		var P: PackedVector3Array = s["P"]
		var far := Vector2(P[0].x - px, P[0].z - pz).length()
		if far > 180 and s.get("state", "free") != "free":
			strips.remove_at(si)
			if terrain: terrain.restore_tape(s["sp"])
			continue
		if far > 180 or (s["pin"] == null and s["age"] > 40):
			strips.remove_at(si)
			continue
		var state: String = s.get("state", "free")
		if state == "stretch":
			match _stretch(s):
				"snap":
					strips.remove_at(si)
					snapped.append(s)
					continue
				"release":
					s["state"] = "settle"
					s["age"] = 0.0
					s["grab"] = -1
					s["segs"] = (s["rest"] as PackedFloat32Array).duplicate()
		elif state == "settle" and s["age"] > SETTLE:
			strips.remove_at(si)
			if terrain: terrain.restore_tape(s["sp"])
			continue
		elif far > 90:   # out of sight: freeze
			continue
		if state == "free": s["tw_k"] = minf(1.0, float(s.get("tw_k", 1.0)) + dt * 1.5)   # the foil starts twisting once torn
		_step(s, h, t, wdir, ws)
		_ribbon(s, t)
	for s in snapped: _snap(s)
	_draw()


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
	var G := PackedFloat32Array()
	G.resize(n)
	for i in n:   # once a frame (height() is costly)
		G[i] = terrain.height(P[i].x, P[i].z)
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
		var twa := (sin(tp + t * tr - fi * tk) * ta + sin(t * tr * 0.37 + fi * tk * 2.3 + tw[mini(n0 - 1, int(fi))] * 0.15) * ta * 0.5 + fi * td * 0.2 + t * td) * twk
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
	_imesh.clear_surfaces()
	var any := false
	for s in strips:
		if (s["V"] as PackedVector3Array).size() > 0:
			any = true
			break
	_dirty = any
	if not any:
		return
	var AV := PackedVector3Array()
	var AN := PackedVector3Array()
	var AC := PackedColorArray()
	for s in strips:
		var V: PackedVector3Array = s["V"]
		if V.is_empty(): continue
		var cols: Array = s["cols"]
		var o := AC.size()
		AV.append_array(V)
		AN.append_array(s["N"])
		AC.resize(o + V.size())
		var per := 6 * SUBD   # one colour per sim segment
		for k0 in range(0, V.size(), per):
			var c: Color = cols[mini(cols.size() - 1, k0 / per)]
			for k in range(k0, mini(k0 + per, V.size())):
				AC[o + k] = c
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = AV
	arr[Mesh.ARRAY_NORMAL] = AN
	arr[Mesh.ARRAY_COLOR] = AC
	_imesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
