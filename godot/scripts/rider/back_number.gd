class_name BackNumber
extends MeshInstance3D
## Race number paper pinned to the rider's back, like a real bib. A small Verlet cloth (same idea as TapeSim):
## light paper, big drag, pulled towards the air velocity. The top corners are safety-pinned; the bottom corners
## are only loosely held, so at speed the lower half lifts, pumps and flaps. Drawn in world space; nothing on
## the jersey changes. The paper's face (header, number, sponsors) is drawn once into a small SubViewport.

const C := 6                    # points across (sideways)
const R := 5                    # points down
const W := 0.24                 # paper size, m
const H := 0.19
const T_TOP := 0.68             # on the spine: 0 hips .. 1 collar
const T_BOT := 0.30
const STAND := 0.009            # the paper floats this far off the jersey (the torso mesh is faceted)
const MAX_STAND := 0.09        # nothing billows further off the jersey than this
const TETHER := 0.12            # how far a bottom corner can lift off its pin spot
const MAX_AWAY := 0.11          # and no point strays further than this from its spot on the back (can't fold up over the neck)
const SUB := 2
const ITER := 5
const DRAG := 5.0
const SAG := 1.06               # paper a bit bigger than the pin spacing: it can bulge
const PX_W := 384
const PX_H := 304

var _imesh := ImmediateMesh.new()
var number := "27"
var header := "RUNOUT  •  DOWNHILL CUP"
var class_line := "ELITE  DOWNHILL"
var _vp: SubViewport
var _vp_frames := 0
var _P := PackedVector3Array()
var _Q := PackedVector3Array()
var _ph := PackedFloat32Array()
var _have := false
var _vs := Vector3.ZERO
var _t := 0.0


func _init() -> void:
	mesh = _imesh
	top_level = false             # drawn in rider space: the renderer carries it with the rider
	process_priority = 100        # after the rider has been posed this frame
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	for i in C * R:
		_ph.append(randf() * 6.28)


## Depth precision gets coarse with distance, so a paper 9 mm off the jersey would z-fight from far away.
## The vertex shader slides each vertex towards the camera along the view ray (no change on screen, only in
## depth) by an amount that grows with distance.
const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(CAMERA_POSITION_WORLD - wp);
	vec3 to_cam = (CAMERA_POSITION_WORLD - wp) / max(d, 0.001);
	vec3 push = to_cam * (0.003 + 0.0035 * d);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
}
// the game's mud (bike/grime.gd) drives these: grime.x = how muddy the bike is 0..1, grime.y = wet, mud_col
global uniform vec4 grime;
global uniform vec4 mud_col : source_color;
uniform vec2 paper_m = vec2(0.24, 0.19);   // paper size in metres: the mud noise lives on the paper, not the screen
float gr_hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float gr_noise(vec3 x) {
	vec3 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gr_hash(i), gr_hash(i + vec3(1,0,0)), f.x), mix(gr_hash(i + vec3(0,1,0)), gr_hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(gr_hash(i + vec3(0,0,1)), gr_hash(i + vec3(1,0,1)), f.x), mix(gr_hash(i + vec3(0,1,1)), gr_hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	// slightly negative LOD bias keeps the number sharp from far away; some self-light keeps the white paper
	// white under the warm low sun instead of turning brown
	vec3 c = texture(tex, UV, -0.8).rgb;
	// mud: builds up from the bottom edge with the bike's mud level, first as flecks, then as splotches.
	// Capped so the number always stays readable; the finest speckle fades out with distance (no shimmer)
	float dist = length(VERTEX);
	vec3 p = vec3(UV * paper_m, 0.37);
	float cover = min(grime.x * (0.04 + 0.6 * UV.y * UV.y), 0.55);
	float n = gr_noise(p * 26.0) * 0.6 + gr_noise(p * 71.0) * 0.4;
	float fine = 1.0 - smoothstep(2.5, 9.0, dist);
	float fleck = gr_noise(p * 190.0);
	float m = smoothstep(1.0 - cover, 1.08 - cover, n);
	m = max(m, fine * smoothstep(1.0 - cover * 0.35, 1.04 - cover * 0.35, fleck));
	vec3 mc = mud_col.rgb * (0.8 + 0.4 * gr_noise(p * 9.0)) * (1.0 - grime.y * 0.43);
	ALBEDO = mix(c * (1.0 - grime.y * 0.12), mc, m);
	EMISSION = c * 0.5 * (1.0 - m);
	ROUGHNESS = mix(0.9, mix(0.93, 0.3, grime.y), m);
}
"""


func _ready() -> void:
	_vp = _build_face()
	add_child(_vp)
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", _vp.get_texture())
	# the mud overlay (bike/grime.gd) must leave the paper alone: its extra pass doesn't get this shader's depth
	# nudge (flicker up close) and its mud mask is pinned to a part that moves through the world (a brown cover
	# from far away). The paper does its own mud above, from the same global values. Grime skips tagged materials.
	m.set_meta("grime_pass", true)
	material_override = m


## change what is printed (the number, the header line); the face is drawn again and baked again
func set_content(n: String, h: String) -> void:
	if n == number and h == header: return
	number = n
	header = h
	if material_override == null: return   # not in the tree yet: _ready draws it with these
	if _vp != null: _vp.queue_free()
	_vp = _build_face()
	add_child(_vp)
	_vp_frames = 0
	(material_override as ShaderMaterial).set_shader_parameter("tex", _vp.get_texture())


# ---------------- the printed paper ----------------

static func _label(parent: Control, text: String, rect: Rect2, size: int, color: Color, black := true) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = UITheme.font(black)
	ls.font_size = size
	ls.font_color = color
	l.label_settings = ls
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


static func _box(parent: Control, rect: Rect2, bg: Color, border: Color, bw: int, radius: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	return p


func _build_face() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(PX_W, PX_H)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var root := Control.new()
	root.size = Vector2(PX_W, PX_H)
	vp.add_child(root)
	var ink := Color("#14161a")
	var red := Color("#d8232a")
	_box(root, Rect2(0, 0, PX_W, PX_H), Color("#f6f4ec"), ink, 5, 10)
	# header band
	_box(root, Rect2(5, 5, PX_W - 10, 50), red, red, 0, 6)
	_label(root, header, Rect2(5, 5, PX_W - 10, 50), 25 if header.length() <= 24 else maxi(13, int(25.0 * 24.0 / header.length())), Color.WHITE)
	var nfs := 178 if number.length() <= 2 else 124
	# the number: a soft grey offset behind it, then the black digits
	_label(root, number, Rect2(6, 54, PX_W, 166), nfs, Color(0, 0, 0, 0.16))
	_label(root, number, Rect2(0, 50, PX_W, 166), nfs, ink)
	_label(root, class_line, Rect2(0, 212, PX_W, 24), 17, Color("#3a3d44"))
	# sponsor row
	_box(root, Rect2(12, 240, PX_W - 24, 2), ink, ink, 0, 0)
	var sx := [12.0, 102.0, 192.0, 282.0]
	var logos := [
		["RUNOUT", Color("#d8232a"), Color.WHITE, Color("#d8232a"), 20],
		["KOMODO", Color.WHITE, ink, ink, 20],
		["GRIPWELL", ink, Color.WHITE, ink, 16],
		["MONTELLI", Color.WHITE, red, red, 16],
	]
	for i in 4:
		var L: Array = logos[i]
		var r := Rect2(sx[i], 250, 90.0 if i < 3 else 90.0, 44)
		_box(root, r, L[1], L[3], 3, 6)
		_label(root, L[0], r, L[4], L[2])
	# the KOMODO mark gets an orange underline
	_box(root, Rect2(sx[1] + 18, 282, 54, 5), Color("#ff7a1a"), Color("#ff7a1a"), 0, 2)
	# safety-pin holes at the corners
	var holes := Control.new()
	holes.size = Vector2(PX_W, PX_H)
	root.add_child(holes)
	holes.draw.connect(func() -> void:
		for p in [Vector2(20, 22), Vector2(PX_W - 20, 22), Vector2(20, PX_H - 22), Vector2(PX_W - 20, PX_H - 22)]:
			holes.draw_circle(p, 8, Color("#14161a"))
			holes.draw_circle(p, 5.5, Color("#b9b7ae")))
	return vp


# ---------------- the cloth ----------------
# Bulletproof: the cloth lives in the back's own frame (built every frame from the four pin spots), not in world
# space. So the paper is carried rigidly with the back however fast the rider goes, turns, crashes or teleports:
# the pins are exact and nothing trails behind. The ride's motion only comes in as a bounded inertial push
# (-acceleration) plus the speed-driven flap. Drawn in the rider's space as a normal child (not top_level), so
# the renderer moves it with the rider even if the rider is moved after this ran.

# per sample on the back: [bone k, weight w, torso-local point m]; points 0..C*R-1 = the grid, then the
# 4 corners (TL, TR, BL, BR) and one point inside the chest (to tell out from in)
var _bk := PackedInt32Array()
var _bw := PackedFloat32Array()
var _bm := PackedVector3Array()
var _Bp: Array[Transform3D] = []
var _prev_o := Vector3.INF      # last world position of the back frame
var _acc := Vector3.ZERO        # smoothed world acceleration of the back
var _N := PackedVector3Array()
var _UV := PackedVector2Array()


func _sample(t: float, z: float, off: float) -> void:
	var m := Vector3(-RiderGear.torso_back_x(t, z) - off, t - 0.5, z)
	var u := clampf(t, 0.0, 1.0) * (Rider.SPINE_BONES - 1)
	var k := mini(int(u), Rider.SPINE_BONES - 2)
	_bk.append(k)
	_bw.append(u - k)
	_bm.append(m)


func _setup_samples() -> void:
	for r in R:
		for c in C:
			_sample(lerpf(T_TOP, T_BOT, float(r) / (R - 1)), lerpf(-W / 2, W / 2, float(c) / (C - 1)), 0.0)
	for tz in [[T_TOP, -W / 2], [T_TOP, W / 2], [T_BOT, -W / 2], [T_BOT, W / 2]]:
		_sample(tz[0], tz[1], STAND)
	_sample(0.55, 0.0, -0.1)
	_N.resize(C * R)
	for r in R:
		for c in C:
			_UV.append(Vector2(float(c) / (C - 1), float(r) / (R - 1)))


## every sample point in rider space, 5 bone reads a frame (back_point did 2 per point)
func _surface(rider: Rider) -> PackedVector3Array:
	if _bk.is_empty():
		_setup_samples()
	_Bp.resize(Rider.SPINE_BONES)
	for k in Rider.SPINE_BONES:
		_Bp[k] = rider.spine_skel.get_bone_pose(k)
	var out := PackedVector3Array()
	out.resize(_bk.size())
	for i in _bk.size():
		var k := _bk[i]
		var w := _bw[i]
		out[i] = (_Bp[k] * _bm[i]) * (1.0 - w) + (_Bp[k + 1] * _bm[i]) * w
	return out


func _reset() -> void:
	# flat paper between the pins, in the frame: pins at (0,0,0) and (pw,0,0); rows go down +y
	_P.resize(C * R)
	_Q.resize(C * R)
	_have = true
	_prev_o = Vector3.INF
	_acc = Vector3.ZERO
	_vs = Vector3.ZERO


func _process(dt: float) -> void:
	if _vp != null and _vp_frames >= 0:   # the face is drawn once (a few frames for fonts / layout), then frozen
		_vp_frames += 1
		if _vp_frames > 4:   # bake it into a mipmapped texture (no shimmer from far away) and drop the viewport
			var img := _vp.get_texture().get_image()
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				(material_override as ShaderMaterial).set_shader_parameter("tex", ImageTexture.create_from_image(img))
				_vp.queue_free()
				_vp = null
			else:
				_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_vp_frames = -1
	var rider := get_parent() as Rider
	if rider == null or rider.spine_skel == null or not rider.is_visible_in_tree() or not is_visible_in_tree() or dt <= 0.0:   # bib off = no cloth sim
		return
	dt = minf(dt, 1.0 / 30.0)
	_t += dt
	var Sl := _surface(rider)           # rider space
	var n0 := C * R
	var a0 := Sl[n0]; var a1 := Sl[n0 + 1]; var a2 := Sl[n0 + 2]; var a3 := Sl[n0 + 3]
	# the back frame: x across the pins, y down the back, z out of the back
	var ex := a1 - a0
	var pw := ex.length()
	if pw < 1e-4 or not pw == pw:
		return
	ex /= pw
	var ey := (a2 - a0) - ex * (a2 - a0).dot(ex)
	if ey.length_squared() < 1e-8:
		return
	ey = ey.normalized()
	var ez := ex.cross(ey)
	if ez.dot((a0 + a1 + a2 + a3) * 0.25 - Sl[n0 + 4]) < 0.0:
		ez = -ez
	var F := Transform3D(Basis(ex, ey, ez), a0)      # back frame -> rider space
	var Fi := F.affine_inverse()
	var Fw := rider.global_transform * F             # back frame -> world
	var to_f := Fw.basis.inverse()                   # world vectors into the frame
	# the back's world motion: speed for the flap, acceleration for a bounded inertial push
	var o := Fw.origin
	if _prev_o == Vector3.INF or o.distance_to(_prev_o) > 2.0 or not o.is_finite():   # first frame / respawn / crash switch
		_vs = Vector3.ZERO
		_acc = Vector3.ZERO
	else:
		var vi := (o - _prev_o) / dt
		var nv := _vs + (vi - _vs) * (1.0 - exp(-dt / 0.08))
		var ai := (nv - _vs) / dt
		_acc += (ai - _acc) * (1.0 - exp(-dt / 0.06))
		_vs = nv
	_prev_o = o
	if _acc.length() > 40.0:
		_acc = _acc.normalized() * 40.0
	var speed := minf(_vs.length(), 30.0)
	var push := to_f * (-_acc * 0.35 + Vector3(0, -9.81 * 0.5, 0))   # inertia + a little paper weight, in the frame
	# frame-space pins and the jersey under every point
	var A := [Vector3.ZERO, Fi * a1, Fi * a2, Fi * a3]
	var S := PackedVector3Array()
	S.resize(n0)
	for i in n0:
		S[i] = Fi * Sl[i]
	if not _have or _P.size() != n0:
		_reset()
		for r in R:
			for c in C:
				var u := float(c) / (C - 1)
				var v := float(r) / (R - 1)
				var p: Vector3 = (A[0] as Vector3).lerp(A[1], u).lerp((A[2] as Vector3).lerp(A[3], u), v)
				_P[r * C + c] = p
				_Q[r * C + c] = p
	var cw := pw / (C - 1) * SAG
	var ch := (A[2] as Vector3).length() / (R - 1) * SAG
	var dg := sqrt(cw * cw + ch * ch)
	var h := dt / SUB
	var gust := clampf(speed / 4.0, 0.0, 1.0)   # nothing much at a walk, full flap from ~20 km/h
	var flap := minf(speed, 14.0)               # flap strength stops growing past ~50 km/h
	for sub in SUB:
		for r in R:
			var low := 0.25 + 0.75 * float(r) / (R - 1)   # the loose lower half flaps most
			for c in C:
				var i := r * C + c
				if i == 0 or i == C - 1:
					continue
				var tu := _t * 19.0 + _ph[i] + r * 0.9 + c * 1.3
				# the wake pumps the paper in and out (z) and rattles it sideways (x)
				var pump := 0.4 + 0.9 * sin(tu) + 0.5 * sin(tu * 1.9 + 2.0) + 0.3 * sin(_t * 52.0 + _ph[i] * 3.0)
				var w := Vector3(sin(tu * 1.4 + 1.0) * flap * 0.25 * low * gust, 0.0, flap * pump * low * gust * 0.8)
				var p := _P[i]
				var v := (p - _Q[i]) / h
				var acc := (w - v) * DRAG + push
				_Q[i] = p
				_P[i] = p + v * h + acc * (h * h)
		for it in ITER:
			_P[0] = A[0]
			_P[C - 1] = A[1]
			for r in R:
				for c in C:
					var i := r * C + c
					if c < C - 1:
						_link(i, i + 1, cw)
					if r < R - 1:
						_link(i, i + C, ch)
						if c < C - 1:
							_link(i, i + C + 1, dg)
						if c > 0:
							_link(i, i + C - 1, dg)
		_P[0] = A[0]
		_P[C - 1] = A[1]
		# the bottom corners are only loosely pinned
		for k in 2:
			var j := (R - 1) * C if k == 0 else R * C - 1
			var d: Vector3 = _P[j] - A[2 + k]
			if d.length() > TETHER:
				_P[j] = A[2 + k] + d.normalized() * TETHER
		for i in n0:   # never through the body: stay outside the (curved) back surface under each point
			var d := _P[i].z - S[i].z
			if d < STAND:
				_P[i].z += STAND - d
			elif d > MAX_STAND:
				_P[i].z -= d - MAX_STAND
			var away := _P[i] - S[i]
			if away.length() > MAX_AWAY:
				_P[i] = S[i] + away.normalized() * MAX_AWAY
	# anything gone bad (NaN from a broken pose): start flat again next frame
	for i in n0:
		if not _P[i].is_finite():
			_have = false
			return
	_draw(F)


func _link(a: int, b: int, rest: float) -> void:
	var d := _P[b] - _P[a]
	var l := maxf(d.length(), 1e-6)
	var diff := (l - rest) / l
	var pin_a := a == 0 or a == C - 1
	var pin_b := b == 0 or b == C - 1
	var wa := 0.0 if pin_a else (1.0 if pin_b else 0.5)
	var wb := 0.0 if pin_b else (1.0 if pin_a else 0.5)
	_P[a] += d * (diff * wa)
	_P[b] -= d * (diff * wb)


## drawn in rider space (frame F), so the mesh moves with the rider node itself
func _draw(F: Transform3D) -> void:
	_imesh.clear_surfaces()
	for r in R:
		for c in C:
			var l := _P[r * C + maxi(c - 1, 0)]
			var rt := _P[r * C + mini(c + 1, C - 1)]
			var up := _P[maxi(r - 1, 0) * C + c]
			var dn := _P[mini(r + 1, R - 1) * C + c]
			var n := (rt - l).cross(dn - up).normalized()
			if n.z < 0.0:
				n = -n
			_N[r * C + c] = F.basis * n
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in R - 1:
		for c in C - 1:
			var i0 := r * C + c
			for k in [i0, i0 + 1, i0 + C, i0 + 1, i0 + C + 1, i0 + C]:
				_imesh.surface_set_normal(_N[k])
				_imesh.surface_set_uv(_UV[k])
				_imesh.surface_add_vertex(F * _P[k])
	_imesh.surface_end()
