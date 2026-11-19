class_name Suspension
extends RefCounted
## Visual suspension for a bike exported with tools/export_dh.py (port of src/suspension.js): a fork
## that slides along the steer axis and a Horst-link four-bar rear end (chainstay G1-C1, seatstay
## C1-C2 carrying the axle A, rocker G2-C2-D, shock FE-D). Each end is a damped spring in metres of
## WHEEL travel, measured from sag (+ = deeper into the travel). The sprung part of the bike
## (everything that is not a wheel) is moved so both tyres stay where the ride physics put them.
##
## bike: the imported "dh" Node3D; data: its get_meta("extras") dictionary.

const PART_NAMES := ["fork_lower", "swing", "seatstay", "rocker", "shock_body", "shock_spring", "shock_shaft"]

var bike: Node3D
var n := {}                      # part name -> Node3D (or null)
var axis := Vector3(-0.2546, 0.967, 0.0)
var has_f := false
var has_r := false
var lower0 := Vector3.ZERO
var F := {"min": 0.0, "max": 0.0}
var R := {"min": 0.0, "max": 0.0}
var xF := 0.0
var vF := 0.0
var xR := 0.0
var vR := 0.0
var fax0 := Vector2.ZERO
var slope0 := 0.0
var spring_len := 0.1
var table: Array = []            # [[phi, rise], ...] sorted by rise
var prev_c2 := Vector2.ZERO
var last_stroke := 0.0           # shock stroke (m, + = compressed) of the last apply()
# riding: the frame stays where the ride physics put the bike's body and the wheels move (the travel is
# set from where the ground is, BikeRig.fit_wheels). Off (the garage): the frame moves, the tyres stay
var wheels_follow := false

# four-bar rest pose
var G1 := Vector2.ZERO
var G2 := Vector2.ZERO
var C1 := Vector2.ZERO
var C2 := Vector2.ZERO
var A := Vector2.ZERO
var D := Vector2.ZERO
var FE := Vector2.ZERO
var lCS := 0.0
var lR := 0.0
var lSS := 0.0
var phi0 := 0.0
var ss0 := 0.0
var rk0 := 0.0
var sh0 := 0.0
var L0 := 0.0


static func _v(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


# transform of `node` in the bike's space (works before the bike is in the scene tree)
func _rel_xform(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var o: Node = node
	while o != null and o != bike:
		if o is Node3D:
			t = (o as Node3D).transform * t
		o = o.get_parent()
	return t


func _pos(name: String) -> Vector2:
	var o := bike.find_child(name, true, false) as Node3D
	if o == null:
		return Vector2.ZERO
	var w := _rel_xform(o).origin
	return Vector2(w.x, w.y)


func _init(p_bike: Node3D, data: Dictionary) -> void:
	bike = p_bike
	var s: Dictionary = data.get("suspension", {})
	for k in PART_NAMES:
		n[k] = bike.find_child(k, true, false)
	if data.has("steerAxis"):
		var a = data["steerAxis"]
		axis = Vector3(float(a[0]), float(a[1]), float(a[2])).normalized()
	# either end may be rigid (a hardtail, a rigid fork): it then just stays at 0
	var f = s.get("fork", null)
	var r = s.get("rear", null)
	has_f = f != null and n["fork_lower"] != null
	has_r = r != null and n["swing"] != null
	if has_f:
		lower0 = (n["fork_lower"] as Node3D).position
		F = {"min": -float(f["sag"]) * float(f["travel"]), "max": (1.0 - float(f["sag"])) * float(f["travel"])}
	if has_r:
		R = {"min": -float(r["sag"]) * float(r["travel"]), "max": (1.0 - float(r["sag"])) * float(r["travel"])}
	fax0 = _pos("wheel_front")
	if not has_r:
		A = _pos("wheel_rear")
		slope0 = atan2(fax0.y - A.y, fax0.x - A.x)
		return
	# ---- four-bar, rest pose ----
	G1 = _v(r["G1"]); G2 = _v(r["G2"]); C1 = _v(r["C1"]); C2 = _v(r["C2"])
	A = _v(r["A"]); D = _v(r["D"]); FE = _v(r["FE"])
	lCS = C1.distance_to(G1); lR = C2.distance_to(G2); lSS = C2.distance_to(C1)
	phi0 = atan2(C1.y - G1.y, C1.x - G1.x)
	ss0 = atan2(C2.y - C1.y, C2.x - C1.x)
	rk0 = atan2(C2.y - G2.y, C2.x - G2.x)
	sh0 = atan2(D.y - FE.y, D.x - FE.x)
	L0 = D.distance_to(FE)
	spring_len = float(r["springLen"])
	# table: chainstay angle -> axle rise (relative to the frame). Walk both ways from rest.
	var rows: Array = []
	for dir in [-1, 1]:
		var c2 := C2
		for i in range(1 if dir < 0 else 0, 400):
			var phi: float = phi0 + dir * i * 0.002
			var p = solve(phi, c2)
			if p == null:
				break
			c2 = p["C2"]
			rows.append([phi, (p["A"] as Vector2).y - A.y])
	rows.sort_custom(func(a, b): return a[1] < b[1])
	table = rows
	slope0 = atan2(fax0.y - A.y, fax0.x - A.x)
	prev_c2 = C2


## the linkage at chainstay angle phi (prev: last C2, picks the branch of the circle intersection).
## Returns {C1, C2, A, D, ss, rk} or null when the links can't close.
func solve(phi: float, prev: Vector2):
	var c1 := Vector2(G1.x + lCS * cos(phi), G1.y + lCS * sin(phi))
	var d := c1.distance_to(G2)
	if d > lR + lSS or d < absf(lR - lSS):
		return null
	var a := (lR * lR - lSS * lSS + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, lR * lR - a * a))
	var ex := (c1.x - G2.x) / d
	var ey := (c1.y - G2.y) / d
	var mx := G2.x + a * ex
	var my := G2.y + a * ey
	var s1 := Vector2(mx - h * ey, my + h * ex)
	var s2 := Vector2(mx + h * ey, my - h * ex)
	var c2 := s1 if s1.distance_squared_to(prev) < s2.distance_squared_to(prev) else s2
	var ss := atan2(c2.y - c1.y, c2.x - c1.x)
	var rk := atan2(c2.y - G2.y, c2.x - G2.x)
	var pa := c1 + (A - C1).rotated(ss - ss0)
	var pd := G2 + (D - G2).rotated(rk - rk0)
	return {"C1": c1, "C2": c2, "A": pa, "D": pd, "ss": ss, "rk": rk}


func phi_for(rise: float) -> float:   # invert the table (monotonic in the working range)
	var t := table
	if rise <= t[0][1]:
		return t[0][0]
	if rise >= t[t.size() - 1][1]:
		return t[t.size() - 1][0]
	var lo := 0
	var hi := t.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) >> 1
		if t[m][1] < rise:
			lo = m
		else:
			hi = m
	var u: float = (rise - t[lo][1]) / (t[hi][1] - t[lo][1])
	return t[lo][0] + (t[hi][0] - t[lo][0]) * u


## landing: v = how fast the bike came down (m/s), shared between the ends by which one touched
func land(v: float, front_air: bool, rear_air: bool) -> void:
	if not is_finite(v) or wheels_follow:
		return
	var kF := 1.2 if rear_air else (0.3 if front_air else 0.9)
	var kR := 1.2 if front_air else (0.3 if rear_air else 1.0)
	vF += v * 1.15 * kF
	vR += v * 0.95 * kR   # a 1 m drop to flat uses ~70-80 % of the travel


static func _fin(v) -> float:   # inputs not set up yet (just spawned) count as 0
	if v == null:
		return 0.0
	var f := float(v)
	return f if is_finite(f) else 0.0


# one damped-spring step; returns Vector2(x, v)
static func _step(dt: float, x: float, v: float, lim: Dictionary, tgt: float, hz: float, zeta: float) -> Vector2:
	var w := TAU * hz
	var z := zeta * 1.6 if v < 0.0 else zeta   # rebound damped harder than compression, like a real damper
	v += (w * w * (tgt - x) - 2.0 * z * w * v) * dt
	x += v * dt
	if x > lim["max"]:
		x = lim["max"]; v = minf(0.0, v)
	if x < lim["min"]:
		x = lim["min"]; v = maxf(0.0, v)
	return Vector2(x, v)


## inp: air (bool), load (0..1 crouch / pump), brake (0/1), bumpF / bumpR (m the ground under each
## tyre sits above where the bike body expects it)
func update(dt: float, inp: Dictionary) -> void:
	if wheels_follow:
		return
	if not is_finite(xF + vF + xR + vR):
		xF = 0.0; vF = 0.0; xR = 0.0; vR = 0.0
	var tF: float
	var tR: float
	if inp.get("air", false):   # topped out in the air
		tF = F["min"]; tR = R["min"]
	else:
		var ld := _fin(inp.get("load"))
		var brake := _fin(inp.get("brake"))
		tF = 0.03 * ld + 0.035 * brake + clampf(_fin(inp.get("bumpF")), -0.06, 0.12)
		tR = 0.035 * ld - 0.01 * brake + clampf(_fin(inp.get("bumpR")), -0.06, 0.12)
	var a := _step(dt, xF, vF, F, tF, 2.4, 0.5)
	xF = a.x; vF = a.y
	var b := _step(dt, xR, vR, R, tR, 2.1, 0.5)
	xR = b.x; vR = b.y


func apply() -> void:
	# fork: the lowers (and the wheel on them) slide up the steer axis
	if has_f:
		(n["fork_lower"] as Node3D).position = lower0 + axis * xF
	var pA: Vector2 = pose_rear()["A"] if has_r else A
	if wheels_follow:
		bike.rotation.z = 0.0
		bike.position = Vector3.ZERO
		return
	# keep both tyres where they were: rotate + shift the whole bike so its axles land back on
	# their rest heights (the wheels then sit on the ground the physics put them on)
	var pF := Vector2(fax0.x + axis.x * xF, fax0.y + axis.y * xF)
	var th := slope0 - atan2(pF.y - pA.y, pF.x - pA.x)
	var rA := pA.rotated(th)
	bike.rotation.z = th
	bike.position = Vector3(A.x - rA.x, A.y - rA.y, 0.0)


func pose_rear() -> Dictionary:   # four-bar at the angle that lifts the axle by xR
	var p = solve(phi_for(xR), prev_c2)
	if p == null:
		p = solve(phi0, C2)
	prev_c2 = p["C2"]
	var pc1: Vector2 = p["C1"]
	var pd: Vector2 = p["D"]
	var phi := atan2(pc1.y - G1.y, pc1.x - G1.x)
	(n["swing"] as Node3D).rotation.z = phi - phi0
	if n["seatstay"]:
		n["seatstay"].position = Vector3(pc1.x, pc1.y, 0.0)
		n["seatstay"].rotation.z = p["ss"] - ss0
	if n["rocker"]:
		n["rocker"].rotation.z = p["rk"] - rk0
	var sh := atan2(pd.y - FE.y, pd.x - FE.x)
	if n["shock_body"]:
		n["shock_body"].rotation.z = sh - sh0
	if n["shock_shaft"]:
		n["shock_shaft"].position = Vector3(pd.x, pd.y, 0.0)
		n["shock_shaft"].rotation.z = sh - sh0
	last_stroke = L0 - pd.distance_to(FE)
	if n["shock_spring"]:
		n["shock_spring"].scale.y = maxf(0.3, (spring_len - last_stroke) / spring_len)
	return p


## shock stroke used at the rear's full travel (for checking the export)
func stroke() -> float:
	if not has_r:
		return 0.0
	var p = solve(phi_for(R["max"]), C2)
	return L0 - (p["D"] as Vector2).distance_to(FE)
