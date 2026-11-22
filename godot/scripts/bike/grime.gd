class_name Grime
extends Node3D
## Mud and water on the bike and rider (port of src/grime.js):
##  * DUST comes first: riding dirt and sand lays a thin film of the ground's (lighter) colour over
##    everything, thickest low down. It builds in ~half a minute.
##  * MUD only piles up on a dusty bike (or a wet one: wet dirt sticks at once), slowly, faster when
##    skidding and landing, taking the colour of the ground it came from. It starts low and creeps upward;
##    riding through water washes both off.
##  * It DRIES: without fresh mud it goes from dark and glossy to a light, matte, cracked crust over ~1.5 min
##    (thin edges first). Dry crust FLAKES: landings and rattling over rough ground knock plates off along the
##    cracks (a faint stain stays) and they fly off the bike as chunks (`take_shed`, spawned by Game).
##  * WET: out of the water everything goes darker and glossy, drops run down and drip off, then it dries.
## Every bike / rider material gets two next_pass overlays (shaders/grime_mud + grime_wet), shared and
## driven by global shader uniforms, so one update moves them all. The passes are only attached while
## there is something to draw, so a clean, dry bike costs nothing.

const MUD_SHADER := preload("res://shaders/grime_mud.gdshader")
const WET_SHADER := preload("res://shaders/grime_wet.gdshader")
const BLOOD_SHADER := preload("res://shaders/grime_blood.gdshader")
## the blood pass is alpha-scissored (opaque pipeline); a sticker's blood stays see-through (masked by the
## sticker's alpha, drawn after it): the same shader with BLOOD_DECAL defined
static var _blood_decal_shader: Shader
static func _blood_decal() -> Shader:
	if _blood_decal_shader == null:
		_blood_decal_shader = Shader.new()
		_blood_decal_shader.code = BLOOD_SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n#define BLOOD_DECAL")
	return _blood_decal_shader
## the rider light match on its own (no water): the wet pass's roll-off only, unshaded, no lighting / gloss.
## Same blend + depth compare as grime_wet.gdshader, so it looks the same.
const TRIM_CODE := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back;
global uniform float rider_trim;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
const float TRIM_KNEE = 0.45;
const float TRIM_SOFT = 0.5;
void vertex() {
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += 0.00008 * POSITION.w;
}
void fragment() {
	vec3 lit = texture(screen_tex, SCREEN_UV).rgb;
	float lmax = max(max(lit.r, lit.g), max(lit.b, 1e-4));
	float over = max(lmax - TRIM_KNEE, 0.0);
	float kept = (min(lmax, TRIM_KNEE) + over / (1.0 + over / TRIM_SOFT)) / lmax;
	float trim = rider_trim * (1.0 - kept);
	vec4 scn = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	if (-VERTEX.z + scn.z / scn.w > 0.001) trim = 0.0;
	if (trim < 0.002) discard;
	ALBEDO = vec3(0.0);
	ALPHA = trim;
}
"""
## how fast mud builds up (1 = the web version: fully caked after ~40 s of fast dirt riding; 0.25 = ~2.5 min)
const MUD_RATE := 0.25

var roots: Array[Node] = []       # the bike rig + the rider (the rider leaves the rig in a crash)
var mud := 0.0
var dust := 0.0                   # the thin film that comes before the mud, 0..1
var dry := 0.0                    # 0 fresh, wet mud .. 1 a dry crust (shader: per splotch around this)
var flake := 0.0                  # how much of the dry crust has been knocked off, 0..1
var _shed := 0.0                  # dry chunks waiting to fly off the bike (take_shed)
const DRY_T := 90.0               # seconds for fresh mud to dry out
static var _PROBE := OS.get_environment("BMX_GRIME_PROBE") != ""
var _vw := Vector2(NAN, NAN)      # last wheel vertical speeds (rattle)
const GROUND_FOLLOW := 6.0   # s of riding new ground until the dust film has its colour (mud: 2.5x)
var dust_col := Color(0.6, 0.53, 0.43)
var wet := 0.0
var blood := 0.0                  # blood stains on the rider + bike: builds with every crash, stays until a death + revive
var _blood_on := false
var enabled := true
## light match (set by Game every frame, 0..1): the wet pass rolls off whatever on the rider + bike came out far
## brighter than the scene (bright kit facing a low sun), so it sits in the light instead of glowing out of it
var trim := 0.0
var mud_col := Color(0.22, 0.145, 0.08)
var _mats := {}                   # base material -> mud pass material (by bias)
var _mud_by_bias := {}
var _decal_muds := {}             # sticker material -> its own mud pass (see _decal_mud)
var _wet_mat: ShaderMaterial
var _trim_mat: ShaderMaterial    # the light match alone (dry bike): cheap, unshaded
var _mud_on := false              # the mud (+ blood) passes are chained
var _tail: Material = null        # last pass: _wet_mat (wet), _trim_mat (light match only) or none
var _scan_t := 0.0
var _t := 0.0
var drips: GPUParticles3D
var warm_frames := 0              # > 0: passes attached (but invisible) so their pipelines compile up front

func _init() -> void:
	name = "Grime"
	if OS.get_environment("BMX_BLOOD_COAT") != "": blood = float(OS.get_environment("BMX_BLOOD_COAT"))   # tests: start bloody
	if OS.get_environment("BMX_DUST_COAT") != "": dust = float(OS.get_environment("BMX_DUST_COAT"))   # tests: start dusty
	if OS.get_environment("BMX_MUD_DRY") != "": dry = float(OS.get_environment("BMX_MUD_DRY"))   # tests: start dried
	if OS.get_environment("BMX_MUD_FLAKE") != "": flake = float(OS.get_environment("BMX_MUD_FLAKE"))
	if OS.get_environment("BMX_MUD_COAT") != "": mud = float(OS.get_environment("BMX_MUD_COAT"))   # start muddy (not held)
	_wet_mat = ShaderMaterial.new()
	_wet_mat.shader = WET_SHADER
	_wet_mat.render_priority = 4   # last: over the mud, the stickers and the blood
	var ts := Shader.new()
	ts.code = TRIM_CODE
	_trim_mat = ShaderMaterial.new()
	_trim_mat.shader = ts
	_trim_mat.render_priority = 4
	_build_drips()

## many base materials are shared (glb imports, the paint / wheel caches): take our passes off them when
## the ride ends, or the next ride skips them as "already layered" and the garage bike keeps the mud
func _exit_tree() -> void:
	if _cav_task != -1:
		WorkerThreadPool.wait_for_task_completion(_cav_task)   # never leave a task running at quit
		_cav_task = -1
	for m in _mats:
		if is_instance_valid(m) and (m.next_pass == _mats[m] or m.next_pass == _wet_mat or m.next_pass == _trim_mat):
			m.next_pass = null
	_mats.clear()
	_decal_muds.clear()
	RenderingServer.global_shader_parameter_set("grime", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("grime_dust", Vector4.ZERO)

var rider_root: Node3D           # its parts get pinned mud (see _pin)
var _bike_root: Node3D

## pin: the node's parts move against the bike (the rider) -> their mud is pinned to each part
func watch(n: Node, pin := false) -> void:
	roots.append(n)
	if pin: rider_root = n
	_scan_t = 0.0

## The mud pass picks splotches from each part's own vertices, and lets mud creep up from the ground by
## height above the bike. On the rider both would follow the pose (legs pedalling, the spine bending,
## a ragdoll), so the mud would slide over the body: instead each rider part gets, once, its height as a
## fixed function of its own vertex, taken from the riding pose, and the skinned torso its rest shape.
func _pin() -> void:
	if rider_root == null or _bike_root == null or not is_instance_valid(rider_root): return
	if not _bike_root.is_ancestor_of(rider_root): return   # crashed: wait for the riding pose
	var inv := _bike_root.global_transform.affine_inverse()
	var stack: Array[Node] = [rider_root]
	while not stack.is_empty():
		var o: Node = stack.pop_back()
		stack.append_array(o.get_children())
		if not (o is MeshInstance3D) or o.has_meta("grime_pinned"): continue
		var mi := o as MeshInstance3D
		if not mi.is_visible_in_tree(): continue
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skin else null
		if skel and mi.skin and skel.name != "Spine":
			# skinned on the rider skeleton (glove fingers): rest shape in CUSTOM0, height = the hand's
			var hb := mi.skin.get_bind_bone(0)
			var hy := (inv * (skel.global_transform * skel.get_bone_global_pose(maxi(hb, 0)).origin)).y
			mi.set_instance_shader_parameter("grime_hrow", Vector4(0, 0, 0, hy))
			mi.set_instance_shader_parameter("grime_pin", 2.0)
		elif skel and skel.get_bone_count() > 1:
			# rest y -0.5 .. 0.5 runs from the first bone to the last (rider._skin_torso)
			var nb := skel.get_bone_count()
			var h0 := (inv * (skel.global_transform * skel.get_bone_global_pose(0) * Vector3(0, -0.5, 0))).y
			var h1 := (inv * (skel.global_transform * skel.get_bone_global_pose(nb - 1) * Vector3(0, 0.5, 0))).y
			mi.set_instance_shader_parameter("grime_hrow", Vector4(0, h1 - h0, 0, (h0 + h1) * 0.5))
			mi.set_instance_shader_parameter("grime_pin", 2.0)
		else:
			_pin_rows(mi, inv * mi.global_transform)
		mi.set_meta("grime_pinned", true)
	# the bike's own parts: pinned the same way (the swingarm swinging, the fork steering, a rim spinning
	# carry their dirt with them), and the crevice map is baked from them in this pose
	var fresh := false
	stack = [_bike_root]
	while not stack.is_empty():
		var o: Node = stack.pop_back()
		if o == rider_root: continue
		stack.append_array(o.get_children())
		if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null or o.has_meta("grime_pinned"): continue
		var mi := o as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.skin: continue
		_pin_rows(mi, inv * mi.global_transform)
		mi.set_meta("grime_pinned", true)
		_bike_parts.append(mi)
		fresh = true
	if fresh: _bake_cavity(inv)

## the part's rest transform (part -> bike root) as three rows: the mud pass works out where each vertex
## sat on the bike from them (height above the ground, the tyre spray, the crevice map)
static func _pin_rows(mi: MeshInstance3D, t: Transform3D) -> void:
	var b := t.basis
	mi.set_instance_shader_parameter("grime_r0", Vector4(b.x.x, b.y.x, b.z.x, t.origin.x))
	mi.set_instance_shader_parameter("grime_hrow", Vector4(b.x.y, b.y.y, b.z.y, t.origin.y))
	mi.set_instance_shader_parameter("grime_r2", Vector4(b.x.z, b.y.z, b.z.z, t.origin.z))
	mi.set_instance_shader_parameter("grime_pin", 1.0)

# ---------------- crevice map: where dirt packs in (joints, corners, between parts) ----------------
# All bike triangles (in their pinned pose, bike-root space, spokes left out) are dropped into a 2.5 cm
# occupancy grid, box-blurred over 12.5 cm and stored x4 in an R8 3D texture. The mud pass samples it 7 cm
# out from the surface, past the reach of the surface itself: what it reads there is other geometry close by
# (an inside corner, a joint, a tube running near another, the frame beside the tyre).
const CAV_CELL := 0.025
const CAV_R := 2
var _bike_parts: Array[MeshInstance3D] = []
var _cav_task := -1
var _cav_out := {}
var _cav_again := false
var cav_tex: ImageTexture3D
var cav_min := Vector3.ZERO
var cav_size := Vector3.ONE

func _bake_cavity(inv: Transform3D) -> void:
	if _cav_task != -1:
		_cav_again = true   # parts came in while baking: bake once more after
		return
	var parts: Array = []
	var live: Array[MeshInstance3D] = []
	for mi in _bike_parts:
		if not is_instance_valid(mi) or not mi.is_inside_tree(): continue
		live.append(mi)
		var mesh := mi.mesh
		if not (mesh is ArrayMesh or mesh is PrimitiveMesh): continue
		var t := inv * mi.global_transform
		for si in mesh.get_surface_count():
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES: continue
			# spokes fill the wheel's disc with fine lines: they'd read as one big crevice
			var sname := (mesh as ArrayMesh).surface_get_name(si) if mesh is ArrayMesh else ""
			var smat := mesh.surface_get_material(si)
			if "spoke" in sname.to_lower() or (smat and "spoke" in smat.resource_name.to_lower()): continue
			var arr := mesh.surface_get_arrays(si)
			parts.append([t, arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()])
	_bike_parts = live
	_cav_out = {}
	var out := _cav_out
	_cav_task = WorkerThreadPool.add_task(func(): _cav_work(parts, out), false, "grime cavity")

static func _cav_work(parts: Array, out: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var tris: Array = []   # per part: transformed vertex array
	for pt in parts:
		var t: Transform3D = pt[0]
		var v: PackedVector3Array = pt[1]
		var w := PackedVector3Array()
		w.resize(v.size())
		for i in v.size():
			var q := t * v[i]
			w[i] = q
			lo = lo.min(q); hi = hi.max(q)
		tris.append(w)
	if lo.x > hi.x: return
	lo -= Vector3.ONE * 0.1
	hi += Vector3.ONE * 0.1
	var nx := mini(int(ceil((hi.x - lo.x) / CAV_CELL)), 160)
	var ny := mini(int(ceil((hi.y - lo.y) / CAV_CELL)), 160)
	var nz := mini(int(ceil((hi.z - lo.z) / CAV_CELL)), 64)
	var cell := Vector3((hi.x - lo.x) / nx, (hi.y - lo.y) / ny, (hi.z - lo.z) / nz)
	var occ := PackedFloat32Array()
	occ.resize(nx * ny * nz)
	var inv_c := Vector3.ONE / cell
	for k in parts.size():
		var w: PackedVector3Array = tris[k]
		var idx: PackedInt32Array = parts[k][2]
		var nt := idx.size() / 3 if idx.size() > 0 else w.size() / 3
		for f in nt:
			var a: Vector3; var b: Vector3; var c: Vector3
			if idx.size() > 0:
				a = w[idx[f * 3]]; b = w[idx[f * 3 + 1]]; c = w[idx[f * 3 + 2]]
			else:
				a = w[f * 3]; b = w[f * 3 + 1]; c = w[f * 3 + 2]
			var e := maxf(maxf(a.distance_to(b), b.distance_to(c)), c.distance_to(a))
			var n := clampi(int(e / (CAV_CELL * 0.7)) + 1, 1, 24)
			for i in n + 1:
				for j in n + 1 - i:
					var u := float(i) / n
					var vv := float(j) / n
					var q := (a + (b - a) * u + (c - a) * vv - lo) * inv_c
					var x := int(q.x); var y := int(q.y); var z := int(q.z)
					if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz: continue
					occ[(z * ny + y) * nx + x] = 1.0
	# three running-sum box blurs, one per axis: window 2 * CAV_R + 1 cells
	for axis in 3:
		occ = _blur_axis(occ, nx, ny, nz, axis)
	var win := float(2 * CAV_R + 1)
	var norm := 1.0 / (win * win * win)
	var images: Array[Image] = []
	for z in nz:
		var data := PackedByteArray()
		data.resize(nx * ny)
		for y in ny:
			for x in nx:
				data[y * nx + x] = int(clampf(occ[(z * ny + y) * nx + x] * norm * 4.0, 0.0, 1.0) * 255.0)
		images.append(Image.create_from_data(nx, ny, false, Image.FORMAT_R8, data))
	out["images"] = images
	out["dims"] = Vector3i(nx, ny, nz)
	out["min"] = lo
	out["size"] = Vector3(cell.x * nx, cell.y * ny, cell.z * nz)
	out["ms"] = Time.get_ticks_msec() - t0

static func _blur_axis(src: PackedFloat32Array, nx: int, ny: int, nz: int, axis: int) -> PackedFloat32Array:
	var dst := PackedFloat32Array()
	dst.resize(src.size())
	var n := [nx, ny, nz][axis] as int
	var step := [1, nx, nx * ny][axis] as int
	var o1 := [ny, nx, nx][axis] as int
	var o2 := [nz, nz, ny][axis] as int
	var s1 := [nx, 1, 1][axis] as int
	var s2 := [nx * ny, nx * ny, nx][axis] as int
	for b in o2:
		for a in o1:
			var base := a * s1 + b * s2
			var acc := 0.0
			for i in mini(CAV_R, n):
				acc += src[base + i * step]
			for i in n:
				if i + CAV_R < n: acc += src[base + (i + CAV_R) * step]
				if i - CAV_R - 1 >= 0: acc -= src[base + (i - CAV_R - 1) * step]
				dst[base + i * step] = acc
	return dst

func _cav_poll() -> void:
	if _cav_task == -1 or not WorkerThreadPool.is_task_completed(_cav_task): return
	WorkerThreadPool.wait_for_task_completion(_cav_task)
	_cav_task = -1
	if _cav_out.has("images"):
		var d: Vector3i = _cav_out["dims"]
		cav_tex = ImageTexture3D.new()
		cav_tex.create(Image.FORMAT_R8, d.x, d.y, d.z, false, _cav_out["images"])
		cav_min = _cav_out["min"]
		cav_size = _cav_out["size"]
		if OS.get_environment("BMX_GRIME_PROBE") != "":
			print("GRIME cavity %dx%dx%d in %d ms, parts=%d min=%s size=%s" % [d.x, d.y, d.z, _cav_out["ms"], _bike_parts.size(), cav_min, cav_size])
			var rig := _bike_root as BikeRig
			var inv := _bike_root.global_transform.affine_inverse()
			print("GRIME wheels f=%s r=%s" % [inv * rig.wheel_f.global_position, inv * rig.wheel_r.global_position])
			for mi in _bike_parts.slice(0, 12):
				print("GRIME part %s at %s" % [mi.name, inv * mi.global_position])
		for mm in _all_muds(): _cav_apply(mm)
	_cav_out = {}
	if _cav_again and _bike_root:
		_cav_again = false
		_bake_cavity(_bike_root.global_transform.affine_inverse())

func _cav_apply(m: ShaderMaterial) -> void:
	m.set_shader_parameter("cav_on", 1.0 if cav_tex else 0.0)
	if cav_tex:
		m.set_shader_parameter("cav_tex", cav_tex)
		m.set_shader_parameter("cav_min", cav_min)
		m.set_shader_parameter("cav_size", cav_size)

func clean() -> void:
	mud = 0.0; wet = 0.0; dust = 0.0; dry = 0.0; flake = 0.0; _shed = 0.0

## dry chunks knocked off since the last call (Game flings that many bits of dirt off the bike)
func take_shed() -> int:
	var n := int(_shed)
	_shed -= n
	return n

## the colour of dried mud (lighter, a little toward the dust): for the chunks it sheds
func dry_color() -> Color:
	return mud_col.lerp(dust_col, 0.35) * 1.35

## a knock on the bike (landing, rattle): dry crust breaks off. k ~ 1 for a hard landing
func _knock(k: float) -> void:
	var crust := dry * dry * mud
	if crust < 0.002 or k <= 0.0: return
	var lost := minf(1.0, k * 0.12)
	flake = minf(0.9, flake + lost * dry * dry * (1.0 - flake))
	mud = maxf(0.0, mud - mud * lost * 0.08 * dry * dry)
	_shed += lost * crust * 120.0

## a crash leaves blood on the rider and the bike (more for a harder one); only a death + revive washes it off
func add_blood(amount: float) -> void:
	blood = minf(1.0, blood + amount)

## how readily a part collects mud (tyres soak it up, the helmet hardly any)
static func _bias_for(mat: Material, mi: Node) -> float:
	var n := ("%s %s %s" % [mat.resource_name, mi.name, mi.get_parent().name if mi.get_parent() else ""]).to_lower()
	for k in ["rubber", "tyre", "tire", "wheel"]:
		if k in n: return 1.8
	for k in ["lens", "goggle"]:
		if k in n: return 0.35
	for k in ["helmet", "shell", "peak", "visor"]:
		if k in n: return 0.5
	for k in ["chrome", "gold"]:
		if k in n: return 0.8
	return 1.0

## a tyre: rubber on a wheel (not the grips). Its mud starts on the tread and spreads to the sidewalls.
static func _is_tyre(mat: Material, mi: Node) -> bool:
	var n := mat.resource_name.to_lower()
	if not ("rubber" in n or "tyre" in n or "tire" in n): return false
	var p := mi
	for i in 4:
		if p == null: break
		if "wheel" in String(p.name).to_lower(): return true
		p = p.get_parent()
	return false

## a part of a wheel that isn't the tyre (rim, hub, spokes, rotor): it turns, sits inside the tyre's spray and
## right beside the tyre, so it gets its own patchy pattern instead of the dirt map
static func _is_wheel_part(mi: Node) -> bool:
	var p := mi
	for i in 4:
		if p == null: break
		if "wheel" in String(p.name).to_lower(): return true
		p = p.get_parent()
	return false

func _mud_mat(bias: float, tyre := false, wheel := false) -> ShaderMaterial:
	var key := -1.0 if tyre else (bias + 100.0 if wheel else bias)
	if not _mud_by_bias.has(key):
		_mud_by_bias[key] = _new_mud(bias, tyre, wheel)
	return _mud_by_bias[key]

func _new_mud(bias: float, tyre: bool, wheel: bool, decal := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = MUD_SHADER
	m.set_shader_parameter("bias", bias)
	m.set_shader_parameter("tyre", tyre)
	m.set_shader_parameter("wheel", wheel)
	var bm := ShaderMaterial.new()   # the blood pass that follows this mud pass (opaque, alpha scissor;
	bm.shader = _blood_decal() if decal else BLOOD_SHADER   # a sticker's: see-through, masked by it)
	bm.set_shader_parameter("bias", clampf(bias, 0.4, 1.0))
	bm.set_shader_parameter("tyre", tyre)
	bm.render_priority = 3   # see-through like the stickers: drawn after them
	m.set_meta("blood", bm)
	_cav_apply(m)
	if OS.get_environment("BMX_GRIME_MAP") != "": m.set_shader_parameter("debug_map", true)
	return m

## a sticker (logo / lettering decal, bike/decals.gd): see-through, drawn over its part, so the part's own
## mud ends up under it. It gets its own mud + blood passes, masked by the sticker's alpha and drawn after it.
## Its mesh is in the part's own space, so the pattern lines up with the part's mud exactly.
func _decal_mud(m: BaseMaterial3D, mi: MeshInstance3D) -> ShaderMaterial:
	var part := mi.get_parent() as MeshInstance3D
	var ty := part != null and part.mesh != null and _is_tyre(m, part)
	var mm := _new_mud(_bias_for(m, part if part else mi), ty, not ty and _is_wheel_part(mi), true)
	mm.set_shader_parameter("decal", true)
	mm.set_shader_parameter("decal_tex", (m as BaseMaterial3D).albedo_texture)
	mm.render_priority = 2
	(mm.get_meta("blood") as ShaderMaterial).set_shader_parameter("decal", true)
	(mm.get_meta("blood") as ShaderMaterial).set_shader_parameter("decal_tex", (m as BaseMaterial3D).albedo_texture)
	_decal_muds[m] = mm
	return mm

func _all_muds() -> Array:
	return _mud_by_bias.values() + _decal_muds.values()

func _scan() -> void:
	var stack: Array[Node] = []
	stack.append_array(roots)
	while not stack.is_empty():
		var o: Node = stack.pop_back()
		if not is_instance_valid(o): continue
		stack.append_array(o.get_children())
		if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null: continue
		var mi := o as MeshInstance3D
		var list: Array[Material] = []
		if mi.material_override: list.append(mi.material_override)
		else:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(s)
				if m == null: m = mi.mesh.surface_get_material(s)
				if m: list.append(m)
		for m in list:
			if _mats.has(m) or m == _wet_mat or m == _trim_mat or m.get_meta("grime_pass", false): continue
			if m.next_pass != null: continue   # already layered by something else: leave it alone
			var mm: ShaderMaterial
			if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				if not (String(mi.name).begins_with("decal") and (m as BaseMaterial3D).albedo_texture): continue
				mm = _decal_mud(m as BaseMaterial3D, mi)
			else:
				var ty := _is_tyre(m, mi)
				mm = _mud_mat(_bias_for(m, mi), ty, not ty and _is_wheel_part(mi))
			mm.set_meta("grime_pass", true)
			_mats[m] = mm
			_chain(mm)
			_set_pass(m)
	# lettering textures are swapped for their baked version a frame or two after they're made
	for dm in _decal_muds:
		if not is_instance_valid(dm): continue
		var tex: Texture2D = (dm as BaseMaterial3D).albedo_texture
		var mm: ShaderMaterial = _decal_muds[dm]
		if mm.get_shader_parameter("decal_tex") != tex:
			mm.set_shader_parameter("decal_tex", tex)
			(mm.get_meta("blood") as ShaderMaterial).set_shader_parameter("decal_tex", tex)

func _chain(mm: ShaderMaterial) -> void:
	var bm: Material = mm.get_meta("blood")
	bm.next_pass = _tail
	mm.next_pass = bm if _blood_on else _tail

## base -> mud -> (blood) -> tail while there's dirt; a clean bike chains the tail (wet / light match) straight
## off the base material, so the mud pass costs nothing
func _set_pass(m: Material) -> void:
	m.next_pass = _mats[m] if _mud_on else _tail

## per physics step. surf: 0 grass, 1 dirt, 2 water, 3 sand. col = colour of the ground here
func feed(dt: float, surf: int, speed: float, skid: bool, air: bool, landed: float, col: Color, vw := Vector2.ZERO) -> void:
	# rattle: how hard the wheels are being kicked up and down (their vertical speed changing)
	var rattle := 0.0
	if not air and not is_nan(_vw.x):
		rattle = (absf(vw.x - _vw.x) + absf(vw.y - _vw.y)) / maxf(dt, 1e-4)
	_vw = vw if not air else Vector2(NAN, NAN)
	if landed > 0.0: _knock(landed)
	if rattle > 25.0: _knock(minf((rattle - 25.0) / 120.0, 1.0) * dt * 3.0)
	if speed > 12.0 and not air: _knock((speed - 12.0) * 0.004 * dt)   # the wind and buzz at speed
	if surf == 2:   # riding through water washes the mud off and soaks everything
		dry = maxf(0.0, dry - dt * 2.0)   # what's left is soaked again
		mud = maxf(0.0, mud - dt * (0.12 + speed * 0.05))
		dust = maxf(0.0, dust - dt * (0.6 + speed * 0.1))   # dust rinses off at once
		wet = minf(1.0, wet + dt * 3.0)
		return
	var rate := 0.0
	if not air and speed > 0.5:
		if surf == 1: rate = speed * 0.0025 + (0.08 if skid else 0.0)
		elif surf == 3: rate = speed * 0.0016 + (0.05 if skid else 0.0)
		else: rate = 0.01 if skid else 0.0
	# dust first: a film of the ground builds in ~30 s of riding dirt / sand (skids and landings throw more)
	var drate := 0.0
	if not air and speed > 0.5:
		if surf == 1: drate = speed * 0.0032 + (0.05 if skid else 0.0)
		elif surf == 3: drate = speed * 0.0045 + (0.06 if skid else 0.0)
	var dgain := drate * dt + (0.04 * landed if landed > 0.0 and surf != 0 else 0.0)
	if dgain > 0.0:
		var dt_col := Color(col.r, col.g, col.b, 1.0)   # the dust IS the ground it came off: the same colour
		# new dust covers the old: the film follows the ground's colour within ~GROUND_FOLLOW s of riding it
		dust_col = dust_col.lerp(dt_col, maxf(minf(1.0, dgain / (dust + dgain + 0.02)), 1.0 - exp(-dt / GROUND_FOLLOW)))
		dust = minf(1.0, dust + dgain)
	# then mud: it only piles up on a dusty bike; a wet one picks it up at once, and much faster
	var ready := smoothstep(0.4, 0.95, dust)
	if wet > 0.3:
		rate *= 2.5
		ready = 1.0
	var gain := (rate * dt + (0.05 * landed if landed > 0.0 and surf != 0 else 0.0)) * MUD_RATE * ready
	if gain > 0.0:
		# the colour shifts toward the ground it's picking up now (darker: damp, packed dirt)
		var target := col * (0.8 if surf == 3 else 0.68)   # the same ground, damp and packed: a shade darker, same hue
		target.a = 1.0
		var fresh := minf(1.0, gain / (mud + gain + 0.02))
		mud_col = mud_col.lerp(target, maxf(fresh, 1.0 - exp(-dt / (GROUND_FOLLOW * 2.5))))   # fresh mud covers the old
		mud = minf(1.0, mud + gain)
		dry = maxf(0.0, dry - fresh * 1.5)       # fresh mud on top: wet again
		flake = maxf(0.0, flake - fresh * 2.0)   # and the gaps fill in
	wet *= exp(-dt / 7.0)   # dries off over a few seconds
	# the mud dries while nothing fresh lands on it (not while it's soaked)
	if mud > 0.002 and wet < 0.3:
		dry = minf(1.0, dry + dt / DRY_T * (1.0 - wet * 2.5))

## per frame. bike_root: world -> bike-root transform source (the rig: y = height above the ground)
func update(dt: float, bike_root: Node3D) -> void:
	_t += dt
	_bike_root = bike_root
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 1.5   # catches parts that load later (helmet, drivetrain)
		_scan()
	_cav_poll()
	if _PROBE and int(_t) != int(_t - dt):
		print("GRIME t=%.0f mud=%.3f dust=%.2f dry=%.2f flake=%.2f wet=%.2f" % [_t, mud, dust, dry, flake, wet])
	if _t > 0.3 and int(_t * 4.0) != int((_t - dt) * 4.0):
		_pin()   # once the rider is posed on the bike; new parts (helmet, kit) get pinned as they appear
	var m := mud if enabled else 0.0
	var w := wet if enabled else 0.0
	var b := blood if enabled else 0.0
	var d := dust if enabled else 0.0
	# the dust film only shows from ~0.03 (and dust only washes off in water): below that the mud pass stays off
	var mon := m > 0.002 or b > 0.002 or d > 0.03 or warm_frames > 0
	var tail: Material = null
	if w > 0.01 or warm_frames > 0: tail = _wet_mat
	elif trim > 0.01: tail = _trim_mat
	var bon := b > 0.002 or warm_frames > 0
	var warm_trim := false
	if warm_frames > 0:
		warm_frames -= 1
		drips.emitting = true
		warm_trim = warm_frames == 1   # the last warm-up frame shows the light-match pass instead (compiles it too)
		if warm_trim: tail = _trim_mat
	if mon != _mud_on or tail != _tail or bon != _blood_on:
		_mud_on = mon
		_tail = tail
		_blood_on = bon
		for mm in _all_muds(): _chain(mm)   # base -> mud -> blood -> tail
		for mat in _mats: _set_pass(mat)
	RenderingServer.global_shader_parameter_set("grime", Vector4(m, w, _t, b))
	RenderingServer.global_shader_parameter_set("mud_col", mud_col)
	RenderingServer.global_shader_parameter_set("rider_trim", trim)
	RenderingServer.global_shader_parameter_set("grime_age", Vector4(dry, flake, 0.0, 0.0))
	var dl := dust_col.srgb_to_linear()   # a plain vec4 global: no colour conversion is done for us (sRGB numbers read
	RenderingServer.global_shader_parameter_set("grime_dust", Vector4(dl.r, dl.g, dl.b, d))   # as linear made the film pale / chalky)
	var inv := bike_root.global_transform.affine_inverse()
	RenderingServer.global_shader_parameter_set("grime_root", Projection(inv))
	# the tyres in bike-root space, for the spray they throw (xyz axle, w radius)
	var rig := bike_root as BikeRig
	if rig and rig.wheel_f and rig.wheel_r:
		RenderingServer.global_shader_parameter_set("grime_wf", _wheel_v(inv * rig.wheel_f.global_position, rig.wheel_rf))
		RenderingServer.global_shader_parameter_set("grime_wr", _wheel_v(inv * rig.wheel_r.global_position, rig.wheel_rr))
	# drips off the bike while it is still wet
	drips.global_position = bike_root.global_position + Vector3(0, 0.55, 0)
	drips.global_basis = bike_root.global_basis
	drips.emitting = w > 0.12 or warm_frames > 0
	drips.amount_ratio = clampf((w - 0.1) * 1.3, 0.0, 1.0)

static func _wheel_v(p: Vector3, r: float) -> Vector4:
	return Vector4(p.x, p.y, p.z, r)

func _build_drips() -> void:
	drips = GPUParticles3D.new()
	drips.name = "Drips"
	drips.amount = 60
	drips.lifetime = 0.7
	drips.local_coords = false
	drips.emitting = false
	drips.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.7, 0.35, 0.12)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	drips.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.045)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.93, 1.0, 0.55)
	q.material = mat
	drips.draw_pass_1 = q
	add_child(drips)
