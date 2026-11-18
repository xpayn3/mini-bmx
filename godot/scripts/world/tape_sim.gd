class_name TapeSim
extends MeshInstance3D
## Torn race tape (1:1 port of tape.js TapeSim): ride through a span and it SNAPS at the hit; the two
## halves become light foil ribbons simulated with Verlet that stream and float in the wind from their
## stakes, drape over the ground -- or, now and then (25 %), rip off the stake and blow away.
## All strips are drawn as one double-sided ribbon strip mesh (rebuilt each frame), lit like the intact tape.

const SEG := 30                  # TerrainChunkBuilder.TAPE_SEG
const WIDTH := 0.075
const MAX_STRIPS := 40
const SUB := 3
const ITER := 6

var terrain: Terrain
var strips: Array = []           # [{P, Q, seg, pin, cols, age, tw, last, tr, tk, ta, td, tp, G, V, N}]
var _imesh := ImmediateMesh.new()
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


## the bike (velocity vel) hit span `sp` near `hit` (x, z): tear it there. The caller hides the span.
func snap(sp: Dictionary, hit: Vector2, vel: Vector3) -> void:
	var pts: PackedVector3Array = sp["pts"]
	var bi := 1
	var bd := INF
	for i in range(1, SEG):   # tear at the point nearest the hit
		var d := Vector2(pts[i].x - hit.x, pts[i].z - hit.y).length()
		if d < bd:
			bd = d
			bi = i
	var seg_len: float = sp["len"] / SEG
	var span_cols: Array = sp["cols"]
	# each half: points from its stake to the tear
	var back := pts.slice(bi)
	back.reverse()
	var halves := [pts.slice(0, bi + 1), back]
	for h in 2:
		var hp: PackedVector3Array = halves[h]
		if hp.size() < 2:
			continue
		var free := randf() < 0.25
		var cols := []
		for i in hp.size() - 1:
			cols.append(span_cols[(SEG - 1 - i if h else i) & 1])
		var n := hp.size()
		var P := hp.duplicate()
		var Q := hp.duplicate()
		for i in n:   # the end near the hit is dragged along with the bike
			var near := float(i) / (n - 1)
			var k := near * near
			Q[i].x -= (vel.x * 0.55 * k + (randf() - .5) * 0.6 * k) / 60.0
			Q[i].y -= (maxf(0.0, vel.y) * 0.3 * k + (0.6 + randf()) * k) / 60.0
			Q[i].z -= (vel.z * 0.55 * k + (randf() - .5) * 0.6 * k) / 60.0
		_add(P, Q, cols, seg_len, null if free else hp[0])


func _add(P: PackedVector3Array, Q: PackedVector3Array, cols: Array, seg_len: float, pin) -> void:
	while strips.size() >= MAX_STRIPS:
		strips.pop_front()
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
	for si in range(strips.size() - 1, -1, -1):
		var s: Dictionary = strips[si]
		s["age"] += dt
		var P: PackedVector3Array = s["P"]
		var far := Vector2(P[0].x - px, P[0].z - pz).length()
		if far > 180 or (s["pin"] == null and s["age"] > 40):
			strips.remove_at(si)
			continue
		if far > 90:   # out of sight: freeze
			continue
		_step(s, h, t, wdir, ws)
		_ribbon(s, t)
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
			var v := (p - q) / h * r
			var a := Vector3((w.x - v.x) * drag, (w.y - v.y) * drag - 9.81 * 0.35, (w.z - v.z) * drag)
			Q[i] = p
			P[i] = p + v * h + a * (h * h)
		for it in ITER:
			if pinned:
				P[0] = pin
			for i in n - 1:
				var a := P[i]
				var b := P[i + 1]
				var d := b - a
				var l := d.length()
				if l == 0.0:
					l = 1e-6
				var diff := (l - seg_len) / l
				var wa := 0.0 if pinned and i == 0 else 0.5
				var wb := 1.0 if pinned and i == 0 else 0.5
				P[i] = a + d * (diff * wa)
				P[i + 1] = b - d * (diff * wb)
		if pinned:
			P[0] = pin
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


# ribbon geometry: the width direction twists slowly along the strip, like real foil tape
func _ribbon(s: Dictionary, t: float) -> void:
	var P: PackedVector3Array = s["P"]
	var tw: PackedFloat32Array = s["tw"]
	var n := P.size()
	var W := WIDTH / 2
	var tr: float = s["tr"]
	var tk: float = s["tk"]
	var ta: float = s["ta"]
	var td: float = s["td"]
	var tp: float = s["tp"]
	var E := PackedVector3Array()
	E.resize(n)
	for i in n:
		var d := (P[mini(n - 1, i + 1)] - P[maxi(0, i - 1)]).normalized()
		var ax := d.cross(Vector3.UP)
		if ax.length_squared() < 1e-4:
			ax = Vector3(1, 0, 0)
		ax = ax.normalized()
		var bx := ax.cross(d)
		var twa := sin(tp + t * tr - i * tk) * ta + sin(t * tr * 0.37 + i * tk * 2.3 + tw[i] * 0.15) * ta * 0.5 + i * td * 0.2 + t * td
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
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in strips:
		var V: PackedVector3Array = s["V"]
		var N: PackedVector3Array = s["N"]
		var cols: Array = s["cols"]
		for k in V.size():
			_imesh.surface_set_color(cols[k / 6])
			_imesh.surface_set_normal(N[k])
			_imesh.surface_add_vertex(V[k])
	_imesh.surface_end()
