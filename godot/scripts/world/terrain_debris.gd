class_name TerrainDebris
extends Node3D
## Rigid-body debris for smashed fences and cacti (replaces the JS debris.js; torn tape is TapeSim):
## Godot physics bodies on layer 4 that only collide with the chunk ground (layer 2). Once a piece has
## come to rest it becomes a plain mesh lying where it fell (the broken fence stays broken), freed
## with its chunk (a reloaded chunk builds the fence whole again) or on respawn / new world.
## Bulletproof against vanishing: thin pieces used to tunnel through the chunk collision and fall for
## ever (then got "laid to rest" 100 m underground). Now every physics tick each piece is held above the
## real terrain height (its rotated box's lowest corner), it never rests below the ground, and when
## too many fly at once the oldest is laid down where it is instead of deleted.

const LAYER := 1 << 3
const MASK := 1 << 1
const LIFE := 8.0         # a piece still moving after this long is laid to rest where it is
const SETTLE := 1.2       # pieces can come to rest after this long
const MAX := 160          # moving pieces
const MAX_WRECK := 2500   # pieces lying on the ground

var _items: Array = []   # [{body, t, chunk, half}]
var _wrecks: Array = []  # [{node, chunk}] pieces at rest (no physics)
var _mats := {}
var _tag := Vector2i(1 << 30, 0)   # chunk of the thing being smashed (set by smash_*)
var _hit := Vector2.ZERO           # where it was hit (probe)
var _spawned := 0                  # pieces made so far (smash_fence reports how many it made)


var _probe_t := 0.0
func _process(delta: float) -> void:
	if Env.s("BMX_DEBRIS_PROBE") != "":
		_probe_t += delta
		if _probe_t > 0.25 and (_items.size() > 0 or _wrecks.size() > 0):
			_probe_t = 0.0
			var lo := 1e9
			for it in _items:
				if is_instance_valid(it["body"]): lo = minf(lo, it["body"].global_position.y)
			print("DEBRIS moving=%d resting=%d lowest_y=%.1f" % [_items.size(), _wrecks.size(), lo])
	_time_stop()
	_step_hinges(delta)
	var keep := []
	for it in _items:
		it["t"] += delta
		var b: RigidBody3D = it["body"]
		if not is_instance_valid(b):
			continue
		var still := b.sleeping or (b.linear_velocity.length_squared() < 0.02 and b.angular_velocity.length_squared() < 0.05)
		if not _frozen and (it["t"] > LIFE or (it["t"] > SETTLE and still)):
			_lay_down(it)
		else:
			keep.append(it)
	_items = keep


func _ground(x: float, z: float) -> float:
	var t = get_parent()
	return t.height(x, z) if t != null and t.has_method("height") else -1e9

## how far the rotated box reaches below its centre
static func _reach_down(basis: Basis, half: Vector3) -> float:
	var b := basis.orthonormalized()
	return absf(b.x.y) * half.x + absf(b.y.y) * half.y + absf(b.z.y) * half.z

## the same for a piece with a convex hull: its lowest hull point
static func _reach(it: Dictionary, basis: Basis) -> float:
	var pts = it.get("pts")
	if pts == null:
		return _reach_down(basis, it["half"])
	var b := basis.orthonormalized()
	var lo := 0.0
	for p in pts:
		lo = maxf(lo, -(b * p).y)
	return lo

## time stopped (photo mode, Engine.time_scale 0): flying pieces are frozen with their speed kept. Stepped with a zero
## time step the physics engine turned a spinning body's rotation axis into NaN and the piece (+ every ground read at
## it) went non-finite.
var _frozen := false
func _time_stop() -> void:
	var stop := Engine.time_scale < 1e-4
	if stop == _frozen:
		return
	_frozen = stop
	for it in _items:
		var b: RigidBody3D = it["body"]
		if not is_instance_valid(b): continue
		if stop:
			it["lv"] = b.linear_velocity
			it["av"] = b.angular_velocity
			b.freeze = true
		else:
			b.freeze = false
			b.linear_velocity = it.get("lv", Vector3.ZERO)
			b.angular_velocity = it.get("av", Vector3.ZERO)


## the ground guard: no piece ever ends up inside / under the terrain
func _physics_process(_delta: float) -> void:
	for it in _items:
		var b: RigidBody3D = it["body"]
		if not is_instance_valid(b) or b.freeze: continue
		var p := b.global_position
		if not p.is_finite():
			continue
		var low := p.y - _reach(it, b.global_basis)
		var g := _ground(p.x, p.z)
		if low < g - 0.005:
			b.global_position = Vector3(p.x, p.y + (g - low), p.z)
			var v := b.linear_velocity
			if v.y < 0.0: v.y = -v.y * 0.2
			v.x *= 0.85; v.z *= 0.85
			b.linear_velocity = v
			b.angular_velocity *= 0.9

## a piece at rest: keep its mesh where it lies, drop the physics body
func _lay_down(it: Dictionary) -> void:
	var b: RigidBody3D = it["body"]
	var mi: MeshInstance3D = null
	for ch in b.get_children():
		if ch is MeshInstance3D: mi = ch
	if Env.s("BMX_DEBRIS_PROBE") != "":
		var pp := b.global_position
		var tr = get_parent()
		var lo := pp.y - _reach(it, b.global_basis)
		print("DEBRIS lay_down y=%.2f t=%.1f low_vs_field=%.3f low_vs_drawn=%.3f from_hit=%.1f m vis=%s" % [pp.y, it["t"], lo - tr.height(pp.x, pp.z), lo - tr.top_height(pp.x, pp.z), Vector2(pp.x - it.get("hx", pp.x), pp.z - it.get("hz", pp.z)).length(), str(b.is_visible_in_tree())])
	if mi != null:
		var xf := mi.global_transform
		# never left inside / under the ground
		var g := _ground(xf.origin.x, xf.origin.z)
		var low := b.global_position.y - _reach(it, b.global_basis)
		if low < g: xf.origin.y += g - low
		b.remove_child(mi)
		add_child(mi)
		mi.global_transform = xf
		while _wrecks.size() >= MAX_WRECK:
			var old = _wrecks.pop_front()
			if is_instance_valid(old["node"]): old["node"].queue_free()
		_wrecks.append({"node": mi, "chunk": it["chunk"]})
	b.queue_free()


## the chunk was unloaded: its fences come back whole when it is built again
func drop_chunk(k: Vector2i) -> void:
	var keep := []
	for w in _wrecks:
		if w["chunk"] == k:
			if is_instance_valid(w["node"]): w["node"].queue_free()
		else:
			keep.append(w)
	_wrecks = keep
	var keep2 := []
	for it in _items:
		if it["chunk"] == k:
			if is_instance_valid(it["body"]): it["body"].queue_free()
		else:
			keep2.append(it)
	_items = keep2


func clear() -> void:
	for it in _items:
		if is_instance_valid(it["body"]):
			it["body"].queue_free()
	_items.clear()
	for w in _wrecks:
		if is_instance_valid(w["node"]):
			w["node"].queue_free()
	_wrecks.clear()
	_hinges.clear()


func _material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b).linear_to_srgb()
	m.roughness = 0.9
	_mats[key] = m
	return m


func spawn(mesh: Mesh, mesh_scale: Vector3, col: Color, xf: Transform3D, size: Vector3, v: Vector3, w: Vector3, mass: float = 1.0,
		damp: float = 0.05, grav: float = 1.0, shape: Shape3D = null, mat: Material = null, mask: int = MASK) -> RigidBody3D:
	while _items.size() >= MAX:   # too many flying: the oldest lies down where it is (never just vanishes)
		var old = _items.pop_front()
		if is_instance_valid(old["body"]):
			_lay_down(old)
	var b := RigidBody3D.new()
	b.collision_layer = LAYER
	b.collision_mask = mask
	b.mass = mass
	b.linear_damp = damp
	b.angular_damp = 0.3
	b.gravity_scale = grav
	b.continuous_cd = true
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = mesh_scale
	mi.material_override = mat if mat != null else _material(col)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	if shape != null:
		cs.shape = shape
	else:
		var bs := BoxShape3D.new()
		bs.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
		cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_transform = xf
	b.linear_velocity = v
	b.angular_velocity = w
	var half := Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02)) * 0.5
	var it := {"body": b, "t": 0.0, "chunk": _tag, "half": half, "hx": _hit.x, "hz": _hit.y}
	if shape is ConvexPolygonShape3D:
		it["pts"] = shape.points
	_items.append(it)
	_spawned += 1
	return b


## one loose piece (a tape stake knocked out): a thin box body with its own mesh + material
func fling(mesh: Mesh, mat: Material, xf: Transform3D, size: Vector3, v: Vector3, w: Vector3, chunk = null) -> RigidBody3D:
	_tag = chunk if chunk is Vector2i else Vector2i(1 << 30, 0)
	_hit = Vector2(xf.origin.x, xf.origin.z)
	return spawn(mesh, Vector3.ONE, Color.WHITE, xf, size, v, w, 0.3, 0.05, 1.0, null, mat)


static func _rs() -> float:
	return randf() - 0.5


## the debris piece's material: printed plates / the sign stick keep their look (null = a plain colour material;
## fence pieces fly in their own colour: their wood shader reads its tint from the MultiMesh)
static func _part_mat(panel: Dictionary, kind: String) -> Material:
	match kind:
		"signboard": return SignTex.for_plate(panel["plate"])
		"pole": return TerrainGeo.MAT["signpole"]
	return null


## a smashed fence span: rails and pickets go, a post only when the bike hit right at it fast (a post is dug in: it
## takes a hard hit square on to snap / rip it out). Deterministic: terrain.gd asks the same question to hide parts.
## BMX_OLD_FENCEBREAK=1 = the old break (any hit within 0.7 m took the post, rail halves always flew).
static var OLD_BREAK := Env.raw("BMX_OLD_FENCEBREAK") == "1"
const POST_HIT_R := 0.3
const POST_HIT_V := 9.0
## a ranch / picket fence (not a sign or billboard, which share the parts)
static func is_fence(panel: Dictionary) -> bool:
	return panel.get("style", "") in ["ranch", "picket"]


static func fence_part_goes(part: Dictionary, hit: Vector2, sp := 99.0, fence := false) -> bool:
	if part["kind"] != "post":
		return true
	var o: Vector3 = part["xform"].origin
	var d := Vector2(o.x - hit.x, o.z - hit.y).length()
	if OLD_BREAK or not fence:   # signs / billboards: a hit takes their stick with them
		return d < 0.7
	return d < POST_HIT_R and sp > POST_HIT_V


## fences.js breakFence, reworked: rails snap AT the hit, the wood torn along its grain (the two halves' fibres
## interlock: a splintered, uneven break, matching on both halves). Each half stays nailed to its post and swings away
## with the bike / droops toward the ground on its nail; a fast hit or a short stub tears it off the nail and it flies.
## Pickets near the hit fly, far ones topple; untouched posts stay in the ground.
func smash_fence(panel: Dictionary, vel: Vector3, hit: Vector2, chunk = null) -> int:
	_tag = chunk if chunk is Vector2i else Vector2i(1 << 30, 0)
	_hit = hit
	var sp := Vector2(vel.x, vel.z).length()
	var dir := Vector3(vel.x, 0, vel.z).normalized() if sp > 0.1 else Vector3.ZERO
	var n0 := _spawned
	var fence := is_fence(panel)
	var posts_gone := []   # a rail half nailed to a post that went flies with it
	for part in panel["parts"]:
		if part["kind"] == "post" and fence_part_goes(part, hit, sp, fence):
			posts_gone.append(part["xform"].origin)
	for part in panel["parts"]:
		if not fence_part_goes(part, hit, sp, fence):
			continue
		var xf: Transform3D = part["xform"]
		var kind: String = part["kind"]
		var scl: Vector3 = part["scale"]
		var rot := xf.basis.orthonormalized()
		var mp := xf.origin
		var base_size: Vector3 = TerrainGeo.FENCE_SIZE[kind]
		var near := 1.0 / (1.0 + Vector2(mp.x - hit.x, mp.z - hit.y).length() * 0.8)
		if kind == "rail" and fence and not OLD_BREAK:
			_break_rail(part, rot, mp, scl, hit, dir, sp, posts_gone)
			continue
		if kind == "rail":
			var ax := rot.x
			var L := scl.x
			# where along the rail the bike went through
			var edge := minf(0.25, L * 0.3)   # short rails too: never a half with no length
			var t := clampf((hit.x - mp.x) * ax.x + (hit.y - mp.z) * ax.z, -L / 2 + edge, L / 2 - edge)
			for k in 2:
				var a := -L / 2 if k == 0 else t
				var b := t if k == 0 else L / 2
				var len := maxf(0.05, b - a - 0.03)
				var c := mp + ax * ((a + b) / 2)
				var side := -1.0 if k == 0 else 1.0
				# the broken end is pushed along with the bike, the far end lags: a swing about the far end
				var v := dir * sp * (0.35 + randf() * 0.2) + Vector3(_rs() * 0.6, 0.6 + randf() * (0.6 + sp * 0.08), _rs() * 0.6)
				var swing := ax.cross(dir).normalized() * side * (1.5 + sp * 0.35) if dir != Vector3.ZERO else Vector3.ZERO
				var w := swing + Vector3(_rs(), _rs(), _rs()) * (1.0 + sp * 0.2)
				spawn(TerrainGeo.MESH[kind], Vector3(len, scl.y, scl.z), part["col"], Transform3D(rot, c), base_size * Vector3(len, scl.y, scl.z), v, w, 0.6)
			# splinters from the break
			var bp := mp + ax * t
			for k in 3:
				var ss := Vector3(0.12 + randf() * 0.18, scl.y * (0.25 + randf() * 0.3), scl.z * 0.6)
				var v2 := dir * sp * (0.5 + randf() * 0.4) + Vector3(_rs() * 2.5, 1.0 + randf() * 2.0, _rs() * 2.5)
				var w2 := Vector3(_rs(), _rs(), _rs()) * (6 + sp)
				spawn(TerrainGeo.MESH[kind], ss, part["col"], Transform3D(rot, bp + Vector3(_rs() * 0.1, _rs() * 0.06, _rs() * 0.1)), base_size * ss, v2, w2, 0.15)
			continue
		var fling := (0.45 + 0.6 * near) * (0.75 + randf() * 0.35)
		var v := Vector3(vel.x * fling + _rs() * 1.2, maxf(0, vel.y) * 0.4 + 0.8 + randf() * (1 + sp * 0.18) * near, vel.z * fling + _rs() * 1.2)
		var spin := 2 + sp * 0.9 * near
		var w := Vector3(_rs() * spin, _rs() * spin, _rs() * spin)
		spawn(TerrainGeo.MESH[kind], scl, part["col"], Transform3D(rot, mp), base_size * scl, v, w, 0.6, 0.05, 1.0, null,
			_part_mat(panel, kind))
	return _spawned - n0


# ---------------- broken rails ----------------
const NAIL_IN := 0.06          # the rail runs this far past its post's middle (TerrainChunkBuilder: L + 0.12)
const TEAR_FROM := 7.0         # m/s: below this a half always stays on its nail
const TEAR_FULL := 16.0        # m/s: at this a half tears off half the time
const STUB_MIN := 0.3          # a half shorter than this (hit near a post) is pulled off its nail
var _hinges: Array = []        # [{node, rot0, push, droop, t, w}] rail halves swinging on their nail

## the rail's wood torn across: the cross-section cut into fibres (uneven columns up the board, each split once across
## its thickness), every fibre breaking at its own place ("off", metres either side of the break) with a pointed,
## off-centre tip. Both halves are made from the same fibres, so their splinters interlock.
static func _fibres(h: float, th: float) -> Array:
	var cols := 3 + randi() % 2
	var ws := []
	var tot := 0.0
	for i in cols:
		var w := 0.6 + randf() * 0.8
		ws.append(w)
		tot += w
	var out := []
	var y := -h / 2
	for i in cols:
		var y1: float = y + h * ws[i] / tot
		var zs := -th / 2 + th * (0.3 + randf() * 0.4)
		# fibres in the middle of the board run longest (wood tears in a V, greenstick), the edges snap shorter
		var mid := 1.0 - absf((y + y1) / 2) / (h / 2)
		for zz in [[-th / 2, zs], [zs, th / 2]]:
			out.append({"y0": y, "y1": y1, "z0": zz[0], "z1": zz[1], "off": (randf() - 0.5) * 0.22 * (0.5 + mid),
				"tip": 0.03 + randf() * 0.09, "tx": randf(), "ty": randf()})
		y = y1
	return out


## one half of a broken rail as a mesh in metres: x from 0 (the far, nailed end) to the break (len); sgn flips the
## fibre offsets for the other half (a fibre that runs long on one half is short on the other)
static func _half_mesh(len: float, fib: Array, sgn: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (b - a).cross(c - a).normalized()
		for p in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(p)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		tri.call(a, b, c)
		tri.call(a, c, d)
	for f in fib:
		var y0: float = f["y0"]
		var y1: float = f["y1"]
		var z0: float = f["z0"]
		var z1: float = f["z1"]
		var e := maxf(0.04, len + float(f["off"]) * sgn)   # where this fibre's full section ends
		var P := Vector3(e + float(f["tip"]), lerpf(y0, y1, 0.2 + 0.6 * float(f["ty"])), lerpf(z0, z1, 0.2 + 0.6 * float(f["tx"])))
		var a0 := Vector3(0, y0, z0)
		var a1 := Vector3(0, y1, z0)
		var a2 := Vector3(0, y1, z1)
		var a3 := Vector3(0, y0, z1)
		var b0 := Vector3(e, y0, z0)
		var b1 := Vector3(e, y1, z0)
		var b2 := Vector3(e, y1, z1)
		var b3 := Vector3(e, y0, z1)
		quad.call(a0, a1, a2, a3)          # the nailed end (facing -x)
		quad.call(a0, b0, b1, a1)          # z0 side (-z)
		quad.call(a2, b2, b3, a3)          # z1 side (+z)
		quad.call(a1, b1, b2, a2)          # top (+y)
		quad.call(a3, b3, b0, a0)          # bottom (-y)
		tri.call(b0, P, b1)                # the pointed break
		tri.call(b1, P, b2)
		tri.call(b2, P, b3)
		tri.call(b3, P, b0)
	return st.commit()


var _wood_mats := {}
func _wood_mat(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if _wood_mats.has(key):
		return _wood_mats[key]
	var m: ShaderMaterial = TerrainGeo.MAT["fenceRail"].duplicate()
	m.set_shader_parameter("use_tint", true)
	m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	_wood_mats[key] = m
	return m


func _break_rail(part: Dictionary, rot: Basis, mp: Vector3, scl: Vector3, hit: Vector2, dir: Vector3, sp: float, posts_gone: Array) -> void:
	var ax := rot.x
	var L := scl.x
	var h := scl.y
	var th := scl.z
	var edge := minf(0.2, L * 0.25)
	var t := clampf((hit.x - mp.x) * ax.x + (hit.y - mp.z) * ax.z, -L / 2 + edge, L / 2 - edge)
	var fib := _fibres(h, th)
	var mat := _wood_mat(part["col"])
	for k in 2:
		# half k: its far (nailed) end, and the way from there to the break
		var s := -1.0 if k == 0 else 1.0
		var end := mp + ax * (s * L / 2)
		var len := L / 2 - s * t
		var to_break := -ax * s
		var b := Basis(to_break, rot.y, to_break.cross(rot.y)).orthonormalized()   # x = to the break, y = up the board
		var mesh := _half_mesh(len, fib, -s)
		var nail := end + to_break * NAIL_IN
		var post_went := false
		for pg in posts_gone:
			if Vector2(pg.x - nail.x, pg.z - nail.z).length() < 0.25:
				post_went = true
		var tear := clampf((sp - TEAR_FROM) / (TEAR_FULL - TEAR_FROM), 0.0, 1.0) * 0.5
		if post_went or len < STUB_MIN or randf() < tear:
			# torn off its nail: it flies, the broken end pushed with the bike
			var c := end + to_break * (len / 2)
			var v := dir * sp * (0.3 + randf() * 0.25) + Vector3(_rs() * 0.6, 0.5 + randf() * (0.5 + sp * 0.07), _rs() * 0.6)
			var w := Vector3.ZERO
			if dir != Vector3.ZERO:
				w = to_break.cross(dir).normalized() * (1.5 + sp * 0.3)
			w += Vector3(_rs(), _rs(), _rs()) * (1.0 + sp * 0.2)
			var body := spawn(mesh, Vector3.ONE, part["col"], Transform3D(b, c), Vector3(len, h, th), v, w, 0.5, 0.05, 1.0, null, mat)
			for ch in body.get_children():
				if ch is MeshInstance3D:
					ch.position = Vector3(-len / 2, 0, 0)
			continue
		# stays on its nail: a node at the nail, the board hanging off it, swinging with the push and drooping
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.global_transform = Transform3D(b, nail)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(-NAIL_IN, 0, 0)
		pivot.add_child(mi)
		# push: about the board's up axis, the broken end going the bike's way (more the faster; a nail only gives so far)
		var push := 0.0
		if dir != Vector3.ZERO:
			var across := b.z.dot(dir)
			push = -signf(across) * clampf(0.25 + sp * 0.06, 0.3, 1.25) * (0.75 + randf() * 0.5) * absf(across)
		# droop: the broken end falls toward the ground, the nail holding it part way
		var g := _ground(nail.x + b.x.x * len, nail.z + b.x.z * len)
		var drop := nail.y - g - h * 0.5
		var droop := asin(clampf(drop / maxf(len - NAIL_IN, 0.05), 0.0, 1.0)) * (0.55 + randf() * 0.4)
		_hinges.append({"node": pivot, "rot0": b, "push": push, "droop": minf(droop, 1.35), "t": 0.0, "w": 7.0 + randf() * 4.0})
		_wrecks.append({"node": pivot, "chunk": _tag})
		_spawned += 1
	# a few splinters off the break
	var bp := mp + ax * t
	for k in 3 + randi() % 3:
		var ss := Vector3(0.05 + randf() * 0.16, h * (0.1 + randf() * 0.2), th * (0.3 + randf() * 0.4))
		var v2 := dir * sp * (0.5 + randf() * 0.4) + Vector3(_rs() * 2.5, 1.0 + randf() * 2.0, _rs() * 2.5)
		var w2 := Vector3(_rs(), _rs(), _rs()) * (6 + sp)
		spawn(TerrainGeo.MESH["rail"], ss, part["col"], Transform3D(rot, bp + Vector3(_rs() * 0.1, _rs() * 0.06, _rs() * 0.1)), ss, v2, w2, 0.1,
			0.05, 1.0, null, mat)


## the halves on their nails: an underdamped swing to where they settle (the droop a moment after the push)
static func _resp(t: float, w: float) -> float:
	if t <= 0.0:
		return 0.0
	var z := 0.3
	var wd := w * sqrt(1.0 - z * z)
	return 1.0 - exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t))


func _step_hinges(delta: float) -> void:
	if _hinges.is_empty():
		return
	var keep := []
	for hg in _hinges:
		var n: Node3D = hg["node"]
		if not is_instance_valid(n):
			continue
		hg["t"] += delta
		var t: float = hg["t"]
		var w: float = hg["w"]
		var a: float = hg["push"] * _resp(t, w)
		var d: float = hg["droop"] * minf(1.0, _resp(t - 0.05, w * 0.8))   # never swings back up past where it lies
		var rot0: Basis = hg["rot0"]
		n.global_transform = Transform3D(rot0 * Basis(Vector3.UP, a) * Basis(Vector3.BACK, -d), n.global_position)
		if t < 3.0:
			keep.append(hg)
	_hinges = keep


## a smashed cactus breaks along its precomputed Voronoi cells (CactusGeo): the chunks round the hit
## are flung with the bike and burst outward, the ones above lose their support and topple / tumble
## down; the chunks knock into each other (convex hulls), spines and flowers go with their chunk.
func smash_cactus(rec: Dictionary, vel: Vector3, hit: Vector3, chunk = null) -> void:
	_tag = chunk if chunk is Vector2i else Vector2i(1 << 30, 0)
	var xf: Transform3D = rec["xform"]
	var rot := xf.basis.orthonormalized()
	var scl := xf.basis.get_scale()
	var sp := Vector2(vel.x, vel.z).length()
	var dir := Vector3(vel.x, 0, vel.z) / sp if sp > 0.1 else Vector3.ZERO
	var mat := _cactus_material(rec["col"])
	# a cactus is a plant, not a rock: the arms (pads, pipes) snap off and the trunk falls; the harder the hit, the more
	# often the trunk breaks across too, leaving the rooted lower part standing
	var half := randf() < clampf(0.12 + sp * 0.035, 0.12, 0.6) or Env.s("BMX_CACTUS_HALF") != ""
	for pc in CactusGeo.pieces(rec.get("kind", 0), "half" if half else "arms"):
		var c: Vector3 = xf * pc["at"]
		var size: Vector3 = pc["size"] * scl
		var rel := c - hit
		var near := exp(-rel.length() / 0.45)       # 1 at the hit, ~0 a metre away
		var out := Vector3(rel.x, 0, rel.z).normalized() if Vector2(rel.x, rel.z).length() > 0.01 else Vector3(_rs(), 0, _rs()).normalized()
		var v := dir * sp * (0.12 + 0.62 * near) + out * (0.4 + sp * 0.22) * near 			+ Vector3(_rs() * 0.5, (0.3 + randf() * 1.6) * near + 0.15, _rs() * 0.5)
		# the top falls the way the bike pushed the bottom out: a tip-over spin
		var tip := Vector3.UP.cross(dir) * (-0.6 - sp * 0.08) * (1.0 - near) if dir != Vector3.ZERO else Vector3.ZERO
		var spin := 1.0 + sp * 0.8 * near
		var w := tip + Vector3(_rs(), _rs(), _rs()) * spin
		if pc.get("stump", false):   # the rooted lower part stays where it grew
			v = dir * sp * 0.04
			w = Vector3.ZERO
		var hull := ConvexPolygonShape3D.new()
		var pts: PackedVector3Array = pc["pts"]
		var sp_pts := PackedVector3Array()
		sp_pts.resize(pts.size())
		for k in pts.size():
			sp_pts[k] = pts[k] * scl
		hull.points = sp_pts
		var m := clampf(size.x * size.y * size.z * 350.0, 0.08, 6.0)
		spawn(pc["mesh"], scl, rec["col"], Transform3D(rot, c), size, v, w, m, 0.08, 1.0, hull, mat, MASK | LAYER)


var _cmats := {}
func _cactus_material(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if _cmats.has(key):
		return _cmats[key]
	var m: ShaderMaterial = TerrainGeo.MAT["cactus"].duplicate()
	m.set_shader_parameter("use_instance", false)
	m.set_shader_parameter("albedo", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("sway", 0.0)
	_cmats[key] = m
	return m
