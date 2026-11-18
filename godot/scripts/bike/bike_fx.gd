class_name BikeFX
extends RefCounted
## Bike finish effects (port of src/bikefx.js):
##  * car_paint(): metallic flake car paint. Tiny flakes (a hash of the object-space position) tilt the
##    base layer's normal so the paint glitters in the highlights, under a smooth, glossy clearcoat.
##  * RotorGlow: brake discs that heat up and glow from the braking track outwards (red -> orange ->
##    yellow), driven by how much energy the brakes have soaked up.

const PAINT_RED := Color8(0xe8, 0x43, 0x2e)

const CAR_PAINT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.91, 0.263, 0.18, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.55;
uniform float roughness : hint_range(0.0, 1.0) = 0.34;
uniform float clearcoat : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.03;
uniform float flake_scale = 625.0;   // 1 / flake size (m)
uniform float sparkle = 0.22;
uniform vec4 color2 : source_color = vec4(1.0, 0.7, 0.0, 1.0);   // pearl: the colour seen at grazing angles
uniform float flip : hint_range(0.0, 1.0) = 0.0;
uniform float deep : hint_range(0.0, 1.0) = 0.0;                    // candy: richer, darker toward the edges

varying vec3 v_flake_p;

vec3 flake_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void vertex() {
	v_flake_p = VERTEX;   // object space
}

void fragment() {
	vec3 fp = v_flake_p * flake_scale;
	vec3 h = flake_hash(floor(fp)) * 2.0 - 1.0;
	// fade the flakes out where one pixel covers many of them (far away): no shimmering noise
	float aa = clamp(1.3 - length(fwidth(fp)) * 0.9, 0.0, 1.0);
	vec3 n = normalize(NORMAL + h * sparkle * aa);
	NORMAL = n;
	// a few flakes catch the light hard: tiny bright glints that twinkle as the bike moves
	// (three.js vViewPosition = -mvPosition: the direction from the surface to the camera)
	vec3 vdir = normalize(-VERTEX);
	float glint = pow(max(0.0, dot(reflect(vdir, n), normalize(vec3(0.3, 0.9, 0.3)))), 60.0);
	glint *= step(0.9, flake_hash(floor(fp) + 7.0).x) * aa;
	// metallic flop, exactly as the three.js shader computes it
	float facing = clamp(dot(normalize(VERTEX), n), 0.0, 1.0);
	float view_k = clamp(dot(-normalize(VERTEX), NORMAL), 0.0, 1.0);
	vec3 col = mix(albedo.rgb, color2.rgb, pow(1.0 - view_k, 1.5) * flip);
	col = mix(col, col * col * 0.9, deep * (1.0 - view_k));
	vec3 base = col * mix(0.62, 1.1, pow(facing, 0.6));
	ALBEDO = base;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	EMISSION = base * glint * 2.0 + vec3(glint * 0.6);
}
"""

const ROTOR_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.25;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float r0 = 0.07;
uniform float r1 = 0.09;

varying float v_rotor_r;

void vertex() {
	v_rotor_r = length(VERTEX.xy);
}

void fragment() {
	// the pads ride on the outer band: it heats first and hottest, the glow creeping inwards as it builds
	float band = smoothstep(r0 + 0.012 * (1.0 - heat), r1, v_rotor_r);
	float h = heat * band;
	vec3 col = mix(vec3(0.5, 0.015, 0.0), vec3(1.0, 0.16, 0.01), smoothstep(0.2, 0.7, h));
	col = mix(col, vec3(1.0, 0.42, 0.08), smoothstep(0.8, 1.0, h));
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb * (1.0 - 0.6 * h);   // hot steel loses its shine to the glow
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = col * h * (0.4 + 1.6 * h);
}
"""

static var _paint_shader: Shader
static var _rotor_shader: Shader


static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s


## Metallic flake + clearcoat car paint. mat: the surface's current material (its albedo colour is
## kept when it is a BaseMaterial3D and opts has no "color"); opts: color, flake (m), sparkle,
## metallic, roughness, clearcoat_roughness. Returns a new ShaderMaterial.
## Defaults are the values carPaint() leaves on the three.js material (metalness .55, roughness .34,
## clearcoat 1 / .03); the paint itself is 0xe8432e.
static func car_paint(mat: Material = null, opts: Dictionary = {}) -> ShaderMaterial:
	if mat is ShaderMaterial and mat.has_meta("car_paint"):
		return mat
	if _paint_shader == null:
		_paint_shader = _shader(CAR_PAINT_SHADER)
	var col: Color = PAINT_RED
	if opts.has("color"):
		col = opts["color"]
	elif mat is BaseMaterial3D and mat.resource_name != "paint":
		col = (mat as BaseMaterial3D).albedo_color
	var m := ShaderMaterial.new()
	m.shader = _paint_shader
	m.resource_name = "paint"
	m.set_meta("car_paint", true)
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("flake_scale", 1.0 / float(opts.get("flake", 0.0016)))
	m.set_shader_parameter("sparkle", float(opts.get("sparkle", 0.22)))
	m.set_shader_parameter("metallic", float(opts.get("metallic", 0.55)))
	m.set_shader_parameter("roughness", float(opts.get("roughness", 0.34)))
	m.set_shader_parameter("clearcoat_roughness", float(opts.get("clearcoat_roughness", 0.03)))
	return m


## Convenience: give every surface whose material is named "paint" under `root` the car paint
## (one shared material, as main.js does with its single red `paint`). Returns that material.
static func apply_paint(root: Node, opts: Dictionary = {}) -> ShaderMaterial:
	var paint := car_paint(null, opts)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var o: Node = stack.pop_back()
		stack.append_array(o.get_children())
		if o is MeshInstance3D and o.mesh:
			var mi := o as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(s)
				if sm and sm.resource_name == "paint":
					mi.set_surface_override_material(s, paint)
	return paint


## Finds the brake disc of a wheel and makes it glow. Null if the wheel has none.
static func find_rotor(wheel: MeshInstance3D) -> RotorGlow:
	return RotorGlow.find(wheel)


class RotorGlow:
	extends RefCounted
	var mesh_instance: MeshInstance3D
	var material: ShaderMaterial
	var heat := 0.0

	## Finds the disc rotor in a wheel mesh (a thin flat slab of verts, 6-15 cm radius, off-centre in Z),
	## moves its triangles into their own mesh (a child of the wheel) and gives it a heat-glow material.
	## The wheel's mesh is replaced by a copy without the disc (the imported resource stays untouched).
	static func find(wheel: MeshInstance3D) -> RotorGlow:
		if wheel == null or wheel.mesh == null:
			return null
		var src: Mesh = wheel.mesh
		var best := {}
		for s in src.get_surface_count():
			if src.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := src.surface_get_arrays(s)
			var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var slabs := {}   # round(z * 200) -> [count, max r]
			for p in P:
				var r := Vector2(p.x, p.y).length()
				if absf(p.z) < 0.02 or r > 0.15:
					continue
				var key := roundi(p.z * 200.0)
				var sl = slabs.get(key)
				if sl == null:
					slabs[key] = [1, r]
				else:
					sl[0] += 1
					sl[1] = maxf(sl[1], r)
			for key in slabs:
				var sl = slabs[key]
				if sl[0] > 50 and sl[1] > 0.06 and (best.is_empty() or sl[0] > best["n"]):
					best = {"surface": s, "z": key / 200.0, "n": sl[0], "r": sl[1]}
		if best.is_empty():
			return null
		return RotorGlow.new(wheel, best["surface"], best["z"], best["r"])

	func _init(wheel: MeshInstance3D, surface: int, z: float, r: float) -> void:
		var src: Mesh = wheel.mesh
		var arr := src.surface_get_arrays(surface)
		var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(P.size())
			for i in P.size():
				idx[i] = i
		var on := PackedByteArray()
		on.resize(P.size())
		for i in P.size():
			var p := P[i]
			on[i] = 1 if absf(p.z - z) < 0.006 and Vector2(p.x, p.y).length() < r + 0.004 else 0
		var keep := PackedInt32Array()
		var disc := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			if on[a] and on[b] and on[c]:
				disc.append_array([a, b, c])
			else:
				keep.append_array([a, b, c])
		# a copy of the wheel mesh without the disc
		var nm := ArrayMesh.new()
		for s in src.get_surface_count():
			var sa := src.surface_get_arrays(s)
			if s == surface:
				sa[Mesh.ARRAY_INDEX] = keep
			nm.add_surface_from_arrays(src.surface_get_primitive_type(s), sa)
			nm.surface_set_material(s, src.surface_get_material(s))
			if src is ArrayMesh:
				nm.surface_set_name(s, (src as ArrayMesh).surface_get_name(s))
		wheel.mesh = nm
		# the disc: same vertex arrays, only its triangles
		var da := arr.duplicate()
		da[Mesh.ARRAY_INDEX] = disc
		var dm := ArrayMesh.new()
		dm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, da)
		if BikeFX._rotor_shader == null:
			BikeFX._rotor_shader = BikeFX._shader(BikeFX.ROTOR_SHADER)
		material = ShaderMaterial.new()
		material.shader = BikeFX._rotor_shader
		material.resource_name = "rotor"
		var base := wheel.get_surface_override_material(surface)
		if base == null:
			base = src.surface_get_material(surface)
		if base is BaseMaterial3D:
			var bm := base as BaseMaterial3D
			material.set_shader_parameter("albedo", bm.albedo_color)
			material.set_shader_parameter("metallic", bm.metallic)
			material.set_shader_parameter("roughness", bm.roughness)
			if bm.albedo_texture:
				material.set_shader_parameter("albedo_texture", bm.albedo_texture)
		material.set_shader_parameter("r0", r * 0.7)
		material.set_shader_parameter("r1", r * 0.86)
		material.set_shader_parameter("heat", 0.0)
		dm.surface_set_material(0, material)
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "rotor"
		mesh_instance.mesh = dm
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		wheel.add_child(mesh_instance)

	## heat: 0 cold .. 1 glowing hot
	func set_heat(k: float) -> void:
		heat = clampf(k, 0.0, 1.0)
		material.set_shader_parameter("heat", heat)
