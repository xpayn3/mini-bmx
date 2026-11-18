class_name RiderCloth
extends Node3D
## The loose parts of the rider's jersey as real cloth (ClothCs.cs): the hem hanging round the waist
## and a cuff on each sleeve. Pinned to the body every step, they catch the airflow (the bike's own
## speed through the air plus the wind), swing with the body, flop in crashes, and are kept out of the
## hips, thighs and arms by capsules. Runs in world space at a fixed 240 Hz; ~0.1 ms a frame.
##
## Reads the rider's joints (Rider.J, its local space) after the rider has been posed this frame,
## so it must sit under the rider (the parent poses first). Needs the .NET build (C#); without it,
## RiderCloth.available() is false and the rider just has no loose cloth.

const HZ := 180.0
const MAX_SUB := 8
# hem: a ring round the waist, hanging over the shorts
const HEM_COLS := 24
const HEM_ROWS := 4
const HEM_DROP := 0.048     # m between rows
# sleeve cuffs: a ring round each upper arm below the pad
const SL_COLS := 12
const SL_ROWS := 4
const SL_DROP := 0.03

var rider: Rider
var wind := Vector3(1.2, 0, 0.6)   # air (m/s, world); set by the game from the terrain wind
var air_extra := Vector3.ZERO      # the garage rollers: airflow as if riding at the preview speed
var drag := 0.9                    # how hard the air pushes the cloth
var damping := 0.985
var iters := 4
var mat: Material

var _pieces := []      # [{sim, mesh_inst, rows, cols, loop, pins_fn}]
var _acc := 0.0
var _prev_pins := {}   # piece index -> pins at the last step
var _ready_ok := false

## the C# solver loads only in the .NET build of Godot
static func available() -> bool:
	if not ResourceLoader.exists("res://scripts/rider/ClothCs.cs"):
		return false
	var s = load("res://scripts/rider/ClothCs.cs")
	return s != null and s.can_instantiate()

func _init(r: Rider, material: Material) -> void:
	rider = r
	mat = material
	name = "Cloth"
	top_level = true   # world space

## built on the first frame the rider has a real pose (at creation every joint is still at the origin,
## which would give every spring a zero rest length and shrink the cloth into rings)
func _build() -> void:
	_fr = []
	_add_piece(HEM_ROWS, HEM_COLS, true, _hem_pins, _hem_rest)
	_add_piece(SL_ROWS, SL_COLS, true, _sleeve_pins.bind(0), _sleeve_rest.bind(0))
	_add_piece(SL_ROWS, SL_COLS, true, _sleeve_pins.bind(1), _sleeve_rest.bind(1))
	_ready_ok = true

func _add_piece(rows: int, cols: int, loop: bool, pins_fn: Callable, rest_fn: Callable) -> void:
	var sim = load("res://scripts/rider/ClothCs.cs").new()
	sim.Setup(rows, cols, loop, rest_fn.call())
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	var idx := PackedInt32Array()
	var cmax := cols if loop else cols - 1
	for r in rows - 1:
		for c in cmax:
			var a := r * cols + c
			var b := r * cols + (c + 1) % cols
			var d := (r + 1) * cols + c
			var e := (r + 1) * cols + (c + 1) % cols
			idx.append_array([a, b, d, b, e, d])
	_pieces.append({"sim": sim, "mi": mi, "rows": rows, "cols": cols, "pins": pins_fn, "rest": rest_fn, "idx": idx})

# ---------------------------------------------------------------- the body, in world space
func _j(i: int) -> Vector3:
	return rider.global_transform * rider.J[i]

var _fr: Array = []
func _frame() -> Array:   # [pelvis, up, right, fwd] (cached for the frame by _process)
	if not _fr.is_empty(): return _fr
	var pel := _j(2)
	var up := (_j(1) - pel).normalized()
	var right := (_j(12) - _j(9))
	right = (right - up * right.dot(up)).normalized()
	var fwd := up.cross(right)
	_fr = [pel, up, right, fwd]
	return _fr

func _hem_pins() -> PackedVector3Array:
	var f := _frame()
	var c: Vector3 = f[0] + f[1] * 0.1
	var out := PackedVector3Array()
	for i in HEM_COLS:
		var a := TAU * i / HEM_COLS
		out.append(c + f[3] * cos(a) * 0.135 + f[2] * sin(a) * 0.165)
	return out

func _hem_rest() -> PackedVector3Array:
	var f := _frame()
	var pins := _hem_pins()
	var out := PackedVector3Array()
	for r in HEM_ROWS:
		for c in HEM_COLS:
			var p: Vector3 = pins[c]
			var outward: Vector3 = p - (f[0] + f[1] * 0.1)
			out.append(p - f[1] * HEM_DROP * r + outward.normalized() * 0.006 * r)
	return out

func _arm(side: int) -> Array:   # [shoulder, axis, perp1, perp2]
	var sh := _j(3 + side * 3)
	var el := _j(4 + side * 3)
	var ax := (el - sh).normalized()
	var f := _frame()
	var p1: Vector3 = ax.cross(f[3])
	if p1.length() < 1e-4: p1 = ax.cross(f[1])
	p1 = p1.normalized()
	var p2 := ax.cross(p1).normalized()
	return [sh, ax, p1, p2]

func _sleeve_pins(side: int) -> PackedVector3Array:
	var a := _arm(side)
	var c: Vector3 = a[0] + a[1] * 0.1
	var out := PackedVector3Array()
	for i in SL_COLS:
		var t := TAU * i / SL_COLS
		out.append(c + a[2] * cos(t) * 0.072 + a[3] * sin(t) * 0.072)
	return out

func _sleeve_rest(side: int) -> PackedVector3Array:
	var a := _arm(side)
	var pins := _sleeve_pins(side)
	var out := PackedVector3Array()
	for r in SL_ROWS:
		for c in SL_COLS:
			var p: Vector3 = pins[c]
			out.append(p + a[1] * SL_DROP * r + (p - (a[0] + a[1] * 0.1)).normalized() * 0.004 * r)
	return out

func _capsules() -> Array:   # [PackedVector3Array pairs, PackedFloat32Array radii]
	var caps := PackedVector3Array()
	var rad := PackedFloat32Array()
	var f := _frame()
	caps.append_array([f[0] - f[1] * 0.12, _j(1) - f[1] * 0.05]); rad.append(0.125)   # hips / belly
	for s in 2:
		caps.append_array([_j(9 + s * 3), _j(10 + s * 3)]); rad.append(0.085)      # thighs
		caps.append_array([_j(3 + s * 3), _j(4 + s * 3)]); rad.append(0.058)       # upper arms
	return [caps, rad]

# ---------------------------------------------------------------- simulate + draw
func _process(dt: float) -> void:
	if not is_instance_valid(rider) or not rider.is_visible_in_tree() or rider.J.size() < 15:
		return
	if not _ready_ok:
		if rider.J[1].distance_to(rider.J[2]) < 0.2:   # not posed yet
			return
		_build()
	dt = minf(dt, 0.1)
	_fr = []
	var cap := _capsules()
	var air := wind + air_extra
	# pins at the end of this frame; between steps they slide from where they were (no tearing at speed)
	var targets := []
	for p in _pieces:
		targets.append(p.pins.call())
	var teleport := false
	for k in _pieces.size():
		if _prev_pins.has(k) and (targets[k][0] as Vector3).distance_to(_prev_pins[k][0]) > 2.0:
			teleport = true
	if teleport or _prev_pins.is_empty():
		for k in _pieces.size():
			_pieces[k].sim.Reset(_pieces[k].rest.call())
			_prev_pins[k] = targets[k]
	_acc += dt
	var n := mini(int(_acc * HZ), MAX_SUB)
	if n > 0:
		_acc -= n / HZ
		_acc = minf(_acc, 1.0 / HZ)
		for k in _pieces.size():
			_pieces[k].sim.StepFrame(1.0 / HZ, n, _prev_pins[k], targets[k], air, cap[0], cap[1], drag, damping, iters)
		for k in _pieces.size():
			_prev_pins[k] = targets[k]
	for p in _pieces:
		if not p.sim.IsFinite():   # never let a bad step blow up the picture
			p.sim.Reset(p.rest.call())
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = p.sim.Positions()
		arr[Mesh.ARRAY_NORMAL] = p.sim.Normals()
		arr[Mesh.ARRAY_INDEX] = p.idx
		var m: ArrayMesh = p.mi.mesh if p.mi.mesh is ArrayMesh else ArrayMesh.new()
		m.clear_surfaces()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		p.mi.mesh = m
