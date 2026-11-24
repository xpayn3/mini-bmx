class_name Hair
extends MeshInstance3D
## Hair for a rider without a helmet, done the way film hair is: a few dozen simulated GUIDE locks (Verlet chains
## that hang from the scalp, trail behind the head, flutter, rest on the head and shoulders) and a few hundred fine
## STRANDS that follow them. The strands are interpolated between the nearest three guides in the vertex shader
## (shaders/hair.gdshader reads the guide positions from a small texture), so the CPU only simulates the guides.
## Styles: "long" (flowing, ~45 cm) and "short" (ordinary short hair that still moves a little).

const G := 28                   # guide locks
const SEG := 9                 # points per lock after the root
const S := 260                  # strands drawn
const STEP := 1.0 / 60.0
const SHADER := "res://shaders/hair.gdshader"
## the skull the hair grows on and rests against, as an ellipsoid in head space (fitted to the custom head)
const HEAD_C := Vector3(0.006, -0.012, 0.0)
const HEAD_R := Vector3(0.12, 0.13, 0.11)
## hair presets: length (m), gravity, sway, bending stiffness, how strongly the scalp end keeps its shape (hold,
## over hold_n points), and short = lies close to the head / sweeps back instead of hanging
const STYLES := {
	"long":  {"label": "Long",  "len": 0.36, "grav": 9.0, "flutter": 0.4, "bend": 0.14, "hold": 0.3, "hold_n": 2, "short": false},
	"bob":   {"label": "Bob",   "len": 0.17, "grav": 8.0, "flutter": 0.3, "bend": 0.22, "hold": 0.5, "hold_n": 4, "short": false},
	"short": {"label": "Short", "len": 0.085, "grav": 4.5, "flutter": 0.2, "bend": 0.3, "hold": 1.0, "hold_n": 99, "short": true},
	"crop":  {"label": "Crop",  "len": 0.04, "grav": 3.0, "flutter": 0.1, "bend": 0.4, "hold": 1.0, "hold_n": 99, "short": true},
	# gathered at one tie point on the back of the head and hanging from it: a rope of locks that swings (it comes out under a helmet too)
	"ponytail": {"label": "Ponytail", "len": 0.3, "grav": 9.0, "flutter": 0.6, "bend": 0.1, "hold": 0.15, "hold_n": 2, "short": false, "tie": true},
	# the same tie point, but plaited: stiffer and heavier, it hangs like a rope and swings less
	# drawn as one low-poly plait (`_braid`), not strands; it swings from the tie like a tail
	"braid": {"label": "Braid", "len": 0.42, "grav": 10.0, "flutter": 0.45, "bend": 0.16, "hold": 0.2, "hold_n": 2, "short": false, "tie": true, "plait": true},
}
## the styles the rider menus offer: the rider always wears a helmet, so these are what comes out under the back of it
## ("short" = nothing shows)
const HELMET_STYLES := [["short", "None"], ["long", "Long"], ["ponytail", "Ponytail"], ["braid", "Braid"]]

var head: Node3D                # the rider's Head: roots and the shape of the hair follow it
var rider: Rider                # the body the hair rests on (spine, shoulders)
var style := "long"
var helmet_mode := false   # under a helmet: only a tuft from the nape, coming out under the back of the shell
var color := Color("#4a3022")

var _roots: Array[Vector3] = []
var _rest: Array[Vector3] = []
var _len := PackedFloat32Array()
var _ph := PackedFloat32Array()
var _P := PackedVector3Array()
var _Q := PackedVector3Array()
var _seg_len := 0.04
var _grav := 6.0
var _hold := 0.6               # how strongly the first points keep the hairstyle's shape
var _flutter := 1.4
var _bend := 0.14
var _hold_n := 2
var _tie := false   # ponytail: a part of the locks is gathered at the tie point
var _have := false
var _t := 0.0
var _img: Image
var _tex: ImageTexture
var _mat: ShaderMaterial
var _built := false
var _plait := false              # braid: the strands are hidden, `_braid` draws the plait along the tail's mean line
var _braid := MeshInstance3D.new()
var _braid_mat := StandardMaterial3D.new()
var _strands: ArrayMesh
var _cs = null   # HairSimCs (C#) or null
var _HPERF := Env.s("BMX_HAIR_PERF") != ""   # tests: HAIRPERF lines, the parts of a hair frame in microseconds
var _hp := [0, 0, 0, 0, 0]
var _hu := [0, 0, 0, 0, 0]

## hand the C# step this style's guides + numbers (after _make_guides) and the points (after a reset)
func _cs_setup() -> void:
	if _cs == null: return
	var lens := PackedFloat32Array(_len); var phs := PackedFloat32Array(_ph)
	_cs.Setup(G, SEG, PackedVector3Array(_roots), PackedVector3Array(_rest), lens, phs, _seg_len, _hold, _hold_n, _bend, _flutter, _plait, PLAIT_R[0], PLAIT_R[1])


func _init() -> void:
	top_level = true
	process_priority = 100        # after the rider has been posed this frame
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_meta("grime_pass", true)   # the bike's mud / wet overlay (bike/grime.gd) must leave the hair alone: its extra pass breaks the strands
	material_override = _mat
	_P.resize(G * (SEG + 1))
	_Q.resize(G * (SEG + 1))
	_ph.resize(G)
	_len.resize(G)
	_braid_mat.vertex_color_use_as_albedo = true
	_braid_mat.vertex_color_is_srgb = true
	_braid_mat.roughness = 0.75
	_braid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_braid_mat.set_meta("grime_pass", true)
	_braid.material_override = _braid_mat
	_braid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_braid.visible = false
	add_child(_braid)
	if Env.s("BMX_HAIR_GD") == "":   # the sim step in C# (HairSimCs: ~10x cheaper); GDScript `_step` stays the fallback
		var sc = load("res://scripts/rider/HairSimCs.cs") if ClassDB.class_exists("CSharpScript") else null
		_cs = sc.new() if sc else null
	set_style("long")


func set_color(c: Color) -> void:
	color = c
	_mat.set_shader_parameter("hair_col", Vector3(c.r, c.g, c.b))


func set_style(s: String, helmet := false) -> void:
	if not STYLES.has(s): s = "long"
	if s == style and helmet == helmet_mode and _built: return
	style = s
	helmet_mode = helmet
	var P: Dictionary = STYLES[style]
	var short: bool = P.short
	_seg_len = float(P.len) / SEG
	_grav = P.grav          # heavy: it hangs, it does not float
	_hold = P.hold
	_hold_n = mini(int(P.hold_n), SEG)
	_bend = P.bend
	_flutter = P.flutter     # a faint sway, not a flap
	_tie = bool(P.get("tie", false))
	_plait = bool(P.get("plait", false))
	_make_guides(short)
	_cs_setup()
	_make_strands(short)
	_strands = mesh
	mesh = ArrayMesh.new() if _plait else _strands   # a braid: no strands, the plait mesh instead
	_braid.visible = _plait
	_built = true
	_have = false


## a random spot on the scalp (head space) that is allowed to grow hair for this style, and which way it falls.
## The hairline runs over the forehead (high at the centre, low at the temples); hair never grows on the face or under the jaw.
func _spot(rng: RandomNumberGenerator, short: bool, tail := false) -> Array:
	if tail:   # the ponytail: every lock leaves the tie point on the back of the head (lower, under the shell, when a helmet is on)
		var tie := Vector3(-0.108, -0.035 if helmet_mode else 0.025, 0.0)
		var p := tie + Vector3(rng.randf_range(-0.004, 0.004), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.036, 0.036))
		return [p, Vector3(-0.6, -1.0, 0.0).normalized()]
	for tries in 400:
		var ct := rng.randf_range(-0.3, 1.0)
		var st := sqrt(maxf(0.0, 1.0 - ct * ct))
		var phi := rng.randf_range(0.0, TAU)
		var d := Vector3(st * cos(phi), ct, st * sin(phi))
		var p := HEAD_C + Vector3(d.x * HEAD_R.x, d.y * HEAD_R.y, d.z * HEAD_R.z) * 1.03
		var hairline := 0.056 - clampf(absf(p.z) / 0.095, 0.0, 1.0) * 0.07
		if p.x > 0.0 and p.y < hairline: continue          # not on the face: below the hairline
		if ct < 0.0 and p.x > -0.03: continue               # nothing under the jaw / in front of the ears at neck height
		if helmet_mode and not (p.x < -0.03 and p.y < 0.0 and p.y > -0.1): continue   # under a helmet: only the nape, below the shell
		var front := clampf(p.x / 0.06, 0.0, 1.0)           # 1 at the hairline, 0 from the crown backwards
		# a lock leaves the scalp OUTWARD and then falls over the head under gravity (so it never starts inside it);
		# the front is swept back and a little to the side, over the head, not down over the eyes
		var out := ((d * 0.9 + Vector3(-0.25, -0.1, 0.0)) if not short else (d * 0.95 + Vector3(-0.1, -0.2, 0.0))).normalized()
		var swept := (d * 0.3 + Vector3(-0.9, 0.25, signf(p.z) * 0.35)).normalized()
		if helmet_mode: out = (d * 0.25 + Vector3(-0.25, -1.0, 0.0)).normalized()   # straight down over the neck / back
		return [p, out.lerp(swept, front).normalized()]
	return [Vector3(-0.08, 0.02, 0), Vector3(-0.6, -1.0, 0).normalized()]


func _make_guides(short: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_roots.clear()
	_rest.clear()
	for i in G:
		var tail := _tie and (helmet_mode or i < G * 6 / 10)   # a ponytail: 60 % of the guides are the tail, the rest hold the hair on the head
		var sp := _spot(rng, short or _tie, tail)
		_roots.append(sp[0])
		_rest.append(sp[1])
		_len[i] = rng.randf_range(0.85, 1.15) * (1.0 if (tail or not _tie) else 0.2)
		_ph[i] = rng.randf() * TAU
	_img = Image.create(SEG + 1, G, false, Image.FORMAT_RGBF)
	_tex = ImageTexture.create_from_image(_img)
	_mat.set_shader_parameter("guides", _tex)
	_mat.set_shader_parameter("seg", SEG)


func _make_strands(short: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	for s in S:
		var tail := _tie and (helmet_mode or s % 5 < 3)
		var sp := _spot(rng, short or _tie, tail)
		var root: Vector3 = sp[0]
		# the three nearest guide roots, weighted by distance
		var best := [[1e9, 0], [1e9, 0], [1e9, 0]]
		for g in G:
			var d := root.distance_squared_to(_roots[g])
			for slot in 3:
				if d < best[slot][0]:
					for m in range(2, slot, -1): best[m] = best[m - 1]
					best[slot] = [d, g]
					break
		var ws := []
		var tot := 0.0
		for slot in 3:
			var w: float = 1.0 / (best[slot][0] + 0.0004)
			ws.append(w); tot += w
		var avg_root := Vector3.ZERO
		for slot in 3:
			ws[slot] /= tot
			avg_root += (_roots[best[slot][1]] as Vector3) * ws[slot]
		var off := root - avg_root          # where this strand starts relative to the blend of its guides
		var lf := rng.randf_range(0.82, 1.0)
		var shade := rng.randf_range(0.82, 1.14)
		var width := rng.randf_range(0.0065, 0.0105) * (1.5 if tail else 1.0)   # a ponytail is a thick bundle
		var ph := rng.randf() * TAU
		for k in SEG + 1:
			var f := float(k) / SEG
			for side in [-1.0, 1.0]:
				verts.append(Vector3(best[0][1], best[1][1], best[2][1]))
				c0.append_array([ws[0], ws[1], ws[2], ph])
				c1.append_array([off.x, off.y, off.z, width])
				uvs.append(Vector2(side, f))
				cols.append(Color(shade, shade, shade, lf))
		for k in SEG:
			var a := (s * (SEG + 1) + k) * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	mesh = am


func _reset(ht: Transform3D) -> void:
	for i in G:
		var b := i * (SEG + 1)
		var root := ht.basis * _roots[i]
		var dir := ht.basis * _rest[i]
		for j in SEG + 1:
			_P[b + j] = root + dir * (_seg_len * _len[i] * j)
			_Q[b + j] = _P[b + j]
	_o = ht.origin
	_hb = ht.basis
	_vs = Vector3.ZERO
	_as = Vector3.ZERO
	_hprev = H_MAX
	_have = true
	if _cs != null: _cs.SetState(_P, _Q, _hprev)


## The sim runs in a frame that moves WITH the head (world axes, origin on the head): _P / _Q are offsets from the
## head, so riding fast carries no world speed into the locks. The ride's motion comes in only as forces: the air
## streaming past (`STREAM_*`, grows with speed, capped), a bounded inertial push from the head's smoothed
## acceleration (`INERTIA`, `ACC_MAX`) and a flutter that livens up a little with speed. It steps every drawn frame
## (sub-steps of at most H_MAX), so the hair is never left behind the head for a frame.
## (It used to be a world-space sim stepped at a fixed 1/60 s: above 60 fps a third of the frames drew no step and
## at speed the locks were left ~20 cm behind the head, then snapped back: the braid "glitched". Head bumps came in
## undamped too.)
const H_MAX := 1.0 / 120.0
const DAMP := 2.0          # /s: the locks' own damping against the head (air + friction in the plait)
const STREAM_K := 1.0      # air streaming past: m/s^2 per m/s of speed ...
const STREAM_MAX := 13.0   # ... up to this (a heavy plait lifts towards horizontal but never stands straight out)
const INERTIA := 0.5       # share of the head's acceleration felt as a push
const ACC_MAX := 7.0       # m/s^2: bumps / landings beyond this don't throw the hair further
const V_EASE := 0.05       # s: the head's speed is smoothed this much before it is read for the push / the air
const A_EASE := 0.15       # s: and its acceleration this much: the drawn head's bob / bump shake (tens of m/s^2,
                           # many times a second) shook the plait; braking, turns, landings come through
var _o := Vector3.ZERO           # the head's position last frame
var _vs := Vector3.ZERO          # its smoothed velocity
var _as := Vector3.ZERO          # its smoothed acceleration
var _hb := Basis.IDENTITY        # the head's turn last frame (sub-steps turn the roots smoothly between the two)
var _hprev := STEP               # last sub-step's length (Verlet with varying steps)
var _W := PackedVector3Array()   # world positions of the guide points (for the shader / the plait)

func _process(dt: float) -> void:
	if head == null or not is_visible_in_tree() or dt <= 0.0:
		return
	var _h0 := Time.get_ticks_usec()
	global_transform = Transform3D.IDENTITY
	dt = minf(dt, 1.0 / 30.0)
	var ht := head.global_transform
	if not _have or ht.origin.distance_to(_o) > 3.0:
		_reset(ht)
	# the head's motion: smoothed speed + acceleration; a jump of over a metre in a frame (respawn, get-up) is no speed
	var jump := ht.origin.distance_to(_o) > 1.0
	var v_now := Vector3.ZERO if jump else (ht.origin - _o) / dt
	if jump: _vs = Vector3.ZERO
	var k := 1.0 - exp(-dt / V_EASE)
	var vs_new := _vs.lerp(v_now, k)
	var a_now := (vs_new - _vs) / dt
	_as = _as.lerp(a_now, 1.0 - exp(-dt / A_EASE))
	_vs = vs_new
	_o = ht.origin
	# the strands are placed by the shader, so the mesh itself has no real extent: tell the engine where the hair is
	# (a box round the head, in world space - the node sits at the origin), or it is culled whenever the rider is far from the origin
	custom_aabb = AABB(ht.origin - Vector3(1.5, 1.5, 1.5), Vector3(3, 3, 3))
	var _h1 := Time.get_ticks_usec()
	var solids := _solids(ht)
	var _h2 := Time.get_ticks_usec()
	for s in solids: s[0] = (s[0] as Vector3) - ht.origin            # the body, head-relative too
	var push := -_as * INERTIA
	if push.length() > ACC_MAX: push = push.normalized() * ACC_MAX
	var spd := _vs.length()
	var air := Vector3.ZERO if spd < 0.05 else -_vs / spd * minf(spd * STREAM_K, STREAM_MAX)
	var force := Vector3(0, -_grav, 0) + push + air
	var lively := 1.0 + minf(spd / 12.0, 1.0)                        # a touch more flutter at speed, never a flap
	var hb := ht.basis
	var n := maxi(1, ceili(dt / H_MAX - 0.01))
	var h := dt / n
	var steps := 0   # (the probe's "stale" count: frames drawn without a sim step; always 0 now)
	var sph := PackedFloat32Array()
	if _cs != null:
		sph.resize(solids.size() * 4)
		for si in solids.size():
			var c: Vector3 = solids[si][0]
			sph[4 * si] = c.x; sph[4 * si + 1] = c.y; sph[4 * si + 2] = c.z; sph[4 * si + 3] = float(solids[si][1])
	for i in n:
		_t += h
		var q := _hb.get_rotation_quaternion().slerp(hb.get_rotation_quaternion(), float(i + 1) / n)
		if _cs != null: _cs.Step(Basis(q) * Basis.from_scale(hb.get_scale()), sph, h, force, lively, _t)
		else: _step(Basis(q) * Basis.from_scale(hb.get_scale()), solids, h, force, lively)
		steps += 1
	if _cs != null: _P = _cs.GetP()
	var _h3 := Time.get_ticks_usec()
	_hb = hb
	_W.resize(_P.size())
	for i in _P.size(): _W[i] = _P[i] + ht.origin
	var _u1 := Time.get_ticks_usec()
	# the guides go to the shader as a float texture, the head's transform with them
	_img.set_data(SEG + 1, G, false, Image.FORMAT_RGBF, _W.to_byte_array())
	var _u2 := Time.get_ticks_usec()
	_tex.update(_img)
	var _u3 := Time.get_ticks_usec()
	_mat.set_shader_parameter("head_xf", ht)
	if _HPERF:
		_hu[0] += _u1 - _h3; _hu[1] += _u2 - _u1; _hu[2] += _u3 - _u2; _hu[3] += Time.get_ticks_usec() - _u3; _hu[4] = maxi(_hu[4], _u3 - _u2)
		if _hp[4] == 299: print("HAIRUP us/frame w=%d set_data=%d update=%d (max %d) param=%d" % [_hu[0] / 300, _hu[1] / 300, _hu[2] / 300, _hu[4], _hu[3] / 300]); _hu = [0, 0, 0, 0, 0]
	if _plait:
		_braid.custom_aabb = custom_aabb
		if _cs != null:   # (C#: refills one mesh in place)
			if not (_braid.mesh is ArrayMesh) or _braid.mesh == _strands: _braid.mesh = ArrayMesh.new()
			_cs.PlaitFromSim(_braid.mesh, ht.origin, helmet_mode, ht.basis.z, color, PLAIT_R[0], PLAIT_R[1])
			if Env.s("BMX_HAIR_CMP") != "" and Engine.get_process_frames() % 240 == 0:   # tests: C# braid vs the GDScript one
				var g := _plait_mesh(ht).surface_get_arrays(0)
				var c := (_braid.mesh as ArrayMesh).surface_get_arrays(0)
				var gv: PackedVector3Array = g[Mesh.ARRAY_VERTEX]; var cv: PackedVector3Array = c[Mesh.ARRAY_VERTEX]
				var gn: PackedVector3Array = g[Mesh.ARRAY_NORMAL]; var cn: PackedVector3Array = c[Mesh.ARRAY_NORMAL]
				var dmax := 0.0; var nmax := 0.0
				for vi in mini(gv.size(), cv.size()):
					dmax = maxf(dmax, gv[vi].distance_to(cv[vi])); nmax = maxf(nmax, gn[vi].distance_to(cn[vi]))
				print("HAIRCMP verts gd=%d cs=%d max_pos_diff_mm=%.4f max_normal_diff=%.5f" % [gv.size(), cv.size(), dmax * 1000.0, nmax])
		else: _braid.mesh = _plait_mesh(ht)
	if _HPERF:
		var _h4 := Time.get_ticks_usec()
		_hp[0] += _h1 - _h0; _hp[1] += _h2 - _h1; _hp[2] += _h3 - _h2; _hp[3] += _h4 - _h3; _hp[4] += 1
		if _hp[4] >= 300:
			print("HAIRPERF us/frame head=%.0f solids=%.0f step=%.0f upload=%.0f" % [_hp[0] / _hp[4], _hp[1] / _hp[4], _hp[2] / _hp[4], _hp[3] / _hp[4]])
			_hp = [0, 0, 0, 0, 0]
	if _probe_on: _probe(ht, dt, steps)


# ---------------------------------------------------------------- probe (BMX_HAIR_PROBE=1)
## Per drawn frame, in the head's frame: how far the tail's mid / tip points jump (2nd difference, mm), how often that
## jump reverses (a back-and-forth flicker), frames drawn without a sim step, the plait's width axis flipping, and
## the tip's angle back from hanging. One HAIRPROBE line a second.
var _probe_on := Env.s("BMX_HAIR_PROBE") != ""
var _pb := {}

func _probe(ht: Transform3D, dt: float, steps: int) -> void:
	var line := _plait_line()
	var hinv := ht.affine_inverse()
	var tip := hinv * line[SEG]
	var mid := hinv * line[SEG / 2]
	if _pb.is_empty():
		_pb = {"t": 0.0, "n": 0, "j2": 0.0, "jmax": 0.0, "flip": 0, "stale": 0, "wflip": 0, "ang": 0.0, "v": 0.0,
			"tip1": tip, "tip2": tip, "mid1": mid, "mid2": mid, "d1": Vector3.ZERO, "w": Vector3.ZERO, "o": ht.origin}
	var dd: Vector3 = tip - 2.0 * (_pb.tip1 as Vector3) + (_pb.tip2 as Vector3)
	var dm: Vector3 = mid - 2.0 * (_pb.mid1 as Vector3) + (_pb.mid2 as Vector3)
	var j := maxf(dd.length(), dm.length()) * 1000.0
	_pb.j2 += j * j; _pb.jmax = maxf(_pb.jmax, j); _pb.n += 1
	var tw := line[SEG] - ht.origin   # the tip from the head, world axes: the head's own turning left out
	var dw: Vector3 = tw - 2.0 * (_pb.get("tw1", tw) as Vector3) + (_pb.get("tw2", tw) as Vector3)
	_pb.w2 = float(_pb.get("w2", 0.0)) + dw.length_squared() * 1e6
	_pb.tw2 = _pb.get("tw1", tw); _pb.tw1 = tw
	if dd.length() > 0.004 and dd.dot(_pb.d1) < 0.0: _pb.flip += 1
	_pb.d1 = dd
	if steps == 0: _pb.stale += 1
	var ws := PackedVector3Array()   # the plait's width axis per segment, transported down it as `_plait_mesh` does
	var w := ht.basis.z.normalized()
	for s in SEG:
		var tg := (line[s + 1] - line[s]).normalized()
		var wn := w - tg * w.dot(tg)
		if wn.length_squared() > 1e-8: w = wn.normalized()
		ws.append(w)
	var prev: PackedVector3Array = _pb.get("ws", PackedVector3Array())
	if prev.size() == ws.size():
		for s in SEG:
			if prev[s].dot(ws[s]) < 0.3: _pb.wflip += 1
	_pb.ws = ws
	var down := (hinv.basis * (line[SEG] - line[0])).normalized()
	_pb.ang += rad_to_deg(down.angle_to(Vector3(0, -1, 0)))
	_pb.v += (ht.origin - (_pb.o as Vector3)).length() / maxf(dt, 1e-4)
	_pb.o = ht.origin
	_pb.tip2 = _pb.tip1; _pb.tip1 = tip; _pb.mid2 = _pb.mid1; _pb.mid1 = mid
	_pb.t += dt
	if _pb.t >= 1.0:
		var n := maxf(1.0, _pb.n)
		print("HAIRPROBE v_kmh=%.0f fps=%.0f jerk_rms_mm=%.1f max=%.1f wjerk_rms_mm=%.1f flips=%d stale=%d wflip=%d tip_back_deg=%.0f" % [
			_pb.v / n * 3.6, n / _pb.t, sqrt(_pb.j2 / n), _pb.jmax, sqrt(_pb.w2 / n), _pb.flip, _pb.stale, _pb.wflip, _pb.ang / n])
		for k in ["t", "j2", "jmax", "ang", "v", "w2"]: _pb[k] = 0.0
		for k in ["n", "flip", "stale", "wflip"]: _pb[k] = 0


# ---------------------------------------------------------------- the braid
const PLAIT_PERIODS := 4     # full weaves of the three strands down the braid
const PLAIT_STEPS := 8       # tube rings per weave
const PLAIT_SIDES := 6       # low poly: six faces round
const PLAIT_R := [0.032, 0.017]   # half thickness at the tie / the end (m)
const PLAIT_TAB := 32        # steps of the width axis' transport down the plait

## the braid's centre line: the mean of the tail guides, point by point down the lock
func _plait_line() -> PackedVector3Array:
	var line := PackedVector3Array()
	line.resize(SEG + 1)
	var n := 0
	for i in G:
		if not (helmet_mode or i < G * 6 / 10): continue
		n += 1
		for j in SEG + 1: line[j] += _W[i * (SEG + 1) + j]
	for j in SEG + 1: line[j] /= maxf(1.0, n)
	return line

## a point on the centre line at f (0 = tie, 1 = end), Catmull-Rom between the sim points
static func _cr(line: PackedVector3Array, f: float) -> Vector3:
	var x := clampf(f, 0.0, 1.0) * (line.size() - 1)
	var i := mini(int(x), line.size() - 2)
	var t := x - i
	var p0 := line[maxi(i - 1, 0)]; var p1 := line[i]; var p2 := line[i + 1]; var p3 := line[mini(i + 2, line.size() - 1)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)

## the plait as flat-shaded low-poly lobes, alternating left / right and tilted into a chevron, a band at the tie
## and a little flared tuft at the end. Rebuilt every frame from the swinging tail.
func _plait_mesh(ht: Transform3D) -> ArrayMesh:
	var line := _plait_line()
	var V := []; var N := []; var C := []   # plain Arrays: the lambdas below append to them (packed arrays would be copied)
	var side_ref: Vector3 = ht.basis.z.normalized()   # the head's left-right: the plait's lobes alternate across it
	var base := color
	var tri := func(a: Vector3, b: Vector3, c: Vector3, col: Color, mid: Vector3):
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14: return
		n = n.normalized()
		if n.dot((a + b + c) / 3.0 - mid) < 0.0: n = -n   # face outward (both sides drawn)
		V.append_array([a, b, c]); N.append_array([n, n, n]); C.append_array([col, col, col])
	# rings: [centre, axis, w, h, colour] in order; consecutive rings are joined by quads
	var tube := func(rings: Array):
		for r in range(rings.size() - 1):
			var A: Array = rings[r]; var B: Array = rings[r + 1]
			var mid: Vector3 = (A[0] + B[0]) * 0.5
			for k in PLAIT_SIDES:
				var a0: Vector3 = A[k + 5]; var a1: Vector3 = A[(k + 1) % PLAIT_SIDES + 5]
				var b0: Vector3 = B[k + 5]; var b1: Vector3 = B[(k + 1) % PLAIT_SIDES + 5]
				tri.call(a0, b0, a1, B[4], mid); tri.call(a1, b0, b1, B[4], mid)
	var ring := func(c: Vector3, t: Vector3, w: Vector3, rw: float, rh: float, col: Color, twist: float) -> Array:
		var h := t.cross(w).normalized()
		var r := [c, t, rw, rh, col]
		for k in PLAIT_SIDES:
			var a := TAU * (float(k) + 0.5) / PLAIT_SIDES + twist
			r.append(c + w * cos(a) * rw + h * sin(a) * rh)
		return r
	# the width axis is the head's left-right at the tie, carried down the plait by parallel transport: picking it
	# fresh from the head at every point flipped it (and the lobes / strands with it) wherever the plait swung sideways
	var wt := PackedVector3Array()
	wt.resize(PLAIT_TAB + 1)
	var w_run := side_ref
	for m in PLAIT_TAB + 1:
		var fm := float(m) / PLAIT_TAB
		var tm := (_cr(line, fm + 0.02) - _cr(line, fm - 0.02)).normalized()
		var wn := w_run - tm * w_run.dot(tm)
		if wn.length_squared() > 1e-8: w_run = wn.normalized()
		wt[m] = w_run
	var frame := func(f: float) -> Array:   # [point, tangent, width axis]
		var p := _cr(line, f)
		var t := (_cr(line, f + 0.02) - _cr(line, f - 0.02)).normalized()
		var x := clampf(f, 0.0, 1.0) * PLAIT_TAB
		var i := mini(int(x), PLAIT_TAB - 1)
		var w := wt[i].lerp(wt[i + 1], x - i)
		w = (w - t * w.dot(t)).normalized()
		return [p, t, w]
	# the tie: a dark band where the plait starts
	var f0: Array = frame.call(0.0)
	var band := base.darkened(0.55)
	var r0: float = PLAIT_R[0]
	tube.call([ring.call(f0[0] - f0[1] * 0.004, f0[1], f0[2], r0 * 0.75, r0 * 0.75, band, 0.0),
		ring.call(f0[0] + f0[1] * 0.012, f0[1], f0[2], r0 * 0.75, r0 * 0.75, band, 0.0)])
	# the lobes: each spans a bit more than its step so they overlap like crossing strands
	# three strands, each a low-poly tube that swings across the plait and passes over / under the others
	# (lateral = cos, depth = sin, the strands a third of a turn apart): a real 3-strand braid
	var end_f := 0.9
	var samples := PLAIT_PERIODS * PLAIT_STEPS
	for s in 3:
		var shade := base.lightened(0.1) if s == 0 else (base if s == 1 else base.darkened(0.12))
		var rings := []
		for m in samples + 1:
			var u := float(m) / samples
			var f := 0.03 + end_f * u
			var F: Array = frame.call(f)
			var w: Vector3 = F[2]
			var h: Vector3 = (F[1] as Vector3).cross(w).normalized()
			var r: float = lerpf(PLAIT_R[0], PLAIT_R[1], f)
			var ph := TAU * PLAIT_PERIODS * u + TAU * s / 3.0
			var grow := minf(1.0, u * 8.0)   # the strands gather into the tie
			var c: Vector3 = F[0] + (w * cos(ph) + h * sin(ph) * 0.8) * r * 0.62 * grow
			rings.append(ring.call(c, F[1], w, r * 0.38, r * 0.38, shade, 0.0))
		tube.call(rings)
	# the end: a small band, then a flared tuft to a point
	var fe: Array = frame.call(end_f + 0.03)
	var r1: float = PLAIT_R[1]
	var tip: Vector3 = _cr(line, 1.0) + (fe[1] as Vector3) * 0.02
	tube.call([ring.call(fe[0], fe[1], fe[2], r1 * 0.6, r1 * 0.6, band, 0.0),
		ring.call(fe[0] + fe[1] * 0.01, fe[1], fe[2], r1 * 0.6, r1 * 0.6, band, 0.0),
		ring.call(fe[0] + fe[1] * 0.025, fe[1], fe[2], r1 * 1.25, r1 * 1.0, base, 0.5),
		ring.call(tip.lerp(fe[0], 0.25), fe[1], fe[2], r1 * 0.8, r1 * 0.6, base.darkened(0.05), 0.2),
		ring.call(tip, fe[1], fe[2], r1 * 0.05, r1 * 0.05, base.darkened(0.1), 0.0)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(V); arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(N); arr[Mesh.ARRAY_COLOR] = PackedColorArray(C)
	var am := ArrayMesh.new()
	if V.size() > 0: am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## the solid things hair rests on, as [world centre, radius]: the neck, spheres down the spine (back, chest, hips)
## and the shoulders. Taken from the posed rider, so they follow a hunched, leaning or tumbling body.
func _solids(ht: Transform3D) -> Array:
	var out: Array = [[ht * Vector3(-0.01, -0.17, 0), 0.055]]   # the neck
	if rider != null and rider.spine_skel != null:
		var xf := rider.global_transform
		for t in [0.95, 0.75, 0.55, 0.35]:
			out.append([xf * rider.back_point(t, 0.0, -0.09), 0.10])                # the middle of the body
			out.append([xf * rider.back_point(t, -0.115, -0.06), 0.065])           # and its two sides
			out.append([xf * rider.back_point(t, 0.115, -0.06), 0.065])
		for sp in rider.shoulder_sph:
			if sp != null: out.append([sp.global_position, 0.078])
		for ua in rider.upper_arm:
			if ua != null: out.append([ua.global_position, 0.055])
	else:
		out.append([ht * Vector3(-0.02, -0.2, 0), 0.15])
		out.append([ht * Vector3(-0.1, -0.32, 0), 0.17])
	return out


## a pull that was tuned as "this much per 1/60 s step", for a step of h
static func _rate(a: float, h: float) -> float:
	return 1.0 - pow(1.0 - minf(a, 0.999), h * 60.0)


## one sub-step of length h, all in the head-relative frame (`hb` = the head's turn now, `force` = gravity + air + push)
func _step(hb: Basis, spheres: Array, h: float, force: Vector3, lively: float) -> void:
	var h2 := h * h
	var hinv := hb.inverse()
	var keep := (h / _hprev) * maxf(0.0, 1.0 - DAMP * h)
	var bend := _rate(_bend, h)
	var slide := _rate(0.7, h)
	for i in G:
		var b := i * (SEG + 1)
		var root := hb * _roots[i]
		_P[b] = root
		_Q[b] = root
		var L := _seg_len * _len[i]
		for j in range(1, SEG + 1):
			var k := b + j
			var v := (_P[k] - _Q[k]) * keep
			_Q[k] = _P[k]
			var f := float(j) / SEG
			# slow breathing sway through the whole length (a wave that travels down the lock), not a twitch
			var sway := Vector3(sin(_t * 1.7 + _ph[i] * 0.5 - j * 0.45), sin(_t * 1.3 + _ph[i] - j * 0.35) * 0.4,
				cos(_t * 1.5 + _ph[i] * 0.8 - j * 0.4)) * sqrt(f)
			_P[k] += v + (force + sway * _flutter * 2.0 * lively) * h2
		# the first points keep the hairstyle's shape (volume at the scalp)
		for j in range(1, _hold_n + 1):
			var target := root + hb * _rest[i] * (L * j)
			var moved := _P[b + j].lerp(target, _rate(minf(1.0, _hold / j), h))
			_Q[b + j] += moved - _P[b + j]
			_P[b + j] = moved
		for it in 2:
			for j in range(1, SEG + 1):
				var a := _P[b + j - 1]
				var d := _P[b + j] - a
				var l := d.length()
				if l > 1e-6: _P[b + j] = a + d * (L / l)
		for j in range(1, SEG + 1):
			var f_j := float(j) / SEG
			var lp := hinv * _P[b + j] - HEAD_C                      # head space, centred on the head
			var q := Vector3(lp.x / HEAD_R.x, lp.y / HEAD_R.y, lp.z / HEAD_R.z)
			var ql := q.length()
			if ql < 1.07 and ql > 1e-4:                                # push out to just above the scalp
				q *= 1.07 / ql
				_P[b + j] = hb * (Vector3(q.x * HEAD_R.x, q.y * HEAD_R.y, q.z * HEAD_R.z) + HEAD_C)
				_Q[b + j] = _Q[b + j].lerp(_P[b + j], slide)          # sliding on the scalp: speed is lost, nothing is kicked out
			elif _P[b + j].y < -0.1:                                    # below the head: the body
				for s in spheres:
					var dd: Vector3 = _P[b + j] - (s[0] as Vector3)
					# a plait is thick: its drawn tubes reach PLAIT_R from the line, so keep that much clear of the body
					var thick := lerpf(PLAIT_R[0], PLAIT_R[1], f_j) + 0.004 if _plait else 0.006
					var r: float = float(s[1]) + thick
					var l2 := dd.length_squared()
					if l2 < r * r and l2 > 1e-9:
						_P[b + j] = (s[0] as Vector3) + dd / sqrt(l2) * r
						_Q[b + j] = _Q[b + j].lerp(_P[b + j], slide)
		for j in range(2, SEG + 1):                                     # bending stiffness: a lock curves, it does not kink or flap
			var dir := (_P[b + j - 1] - _P[b + j - 2]).normalized()
			var moved := _P[b + j].lerp(_P[b + j - 1] + dir * L, bend)
			_Q[b + j] += moved - _P[b + j]
			_P[b + j] = moved
		for j in range(1, SEG + 1):                                     # last: keep the lengths
			var a := _P[b + j - 1]
			var d := _P[b + j] - a
			var l := d.length()
			if l > 1e-6: _P[b + j] = a + d * (L / l)
	_hprev = h


## The hair-coloured cap under the strands: from the crown down to the hairline (high on the forehead, low at the
## temples and the nape), with a soft edge (the vertex alpha fades out over the last ring) so there is no hard line.
static func scalp_mesh() -> ArrayMesh:
	const P := 40
	const R := 12
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for k in P:
		var phi := TAU * float(k) / P
		var cp := cos(phi)
		var sp := absf(sin(phi))
		var side := 0.056 - sp * 0.07                       # hairline height at the front / temples
		var t := clampf(-cp, 0.0, 1.0)                      # towards the back of the head
		var yb := side * (1.0 - t) + (-0.085) * t          # ... down to the nape
		var ctb := clampf((yb - HEAD_C.y) / HEAD_R.y, -0.7, 0.99)
		for i in R + 1:
			var ct := lerpf(1.0, ctb, float(i) / R)
			var st := sqrt(maxf(0.0, 1.0 - ct * ct))
			var d := Vector3(st * cos(phi), ct, st * sin(phi))
			verts.append(HEAD_C + Vector3(d.x * HEAD_R.x, d.y * HEAD_R.y, d.z * HEAD_R.z) * 1.02)
			norms.append(Vector3(d.x / HEAD_R.x, d.y / HEAD_R.y, d.z / HEAD_R.z).normalized())
			var a := 1.0 if i < R - 2 else (0.7 if i == R - 2 else (0.35 if i == R - 1 else 0.0))
			cols.append(Color(1, 1, 1, a))
	for k in P:
		var k2 := (k + 1) % P
		for i in R:
			var a := k * (R + 1) + i
			var b := k2 * (R + 1) + i
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am
