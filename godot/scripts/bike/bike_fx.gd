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
uniform float flake_scale = 4000.0;  // 1 / flake spacing (m): 0.25 mm, real metal-flake paint
uniform float sparkle = 0.22;        // how far a flake is tilted off the surface (rad-ish)
uniform float flake_rough = 0.12;    // the flakes are tiny mirrors
uniform vec4 color2 : source_color = vec4(1.0, 0.7, 0.0, 1.0);   // pearl: the colour seen at grazing angles
uniform float flip : hint_range(0.0, 1.0) = 0.0;
uniform float deep : hint_range(0.0, 1.0) = 0.0;                    // candy: richer, darker toward the edges

varying vec3 v_flake_p;

vec3 flake_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// One level of flakes: every cell holds one round platelet (a sphere cut by the surface, so the
// discs come in all sizes), jittered, tilted at random. Returns the tilt (xyz) and coverage (w).
vec4 flake_level(vec3 p, float lvl) {
	vec3 c = floor(p);
	vec3 h = flake_hash(c + lvl * 17.0);
	vec3 centre = c + 0.3 + 0.4 * h;
	float d = length(p - centre);
	float r = 0.36;
	float cover = 1.0 - smoothstep(r - 0.12, r, d);
	vec3 tilt = flake_hash(c + lvl * 17.0 + 7.31) * 2.0 - 1.0;
	return vec4(tilt, cover);
}

void vertex() {
	// object space in metres (whatever the model's import scale), so the flakes stay glued to the part
	v_flake_p = VERTEX * length(MODEL_MATRIX[0].xyz);
}

void fragment() {
	vec3 fp = v_flake_p * flake_scale;
	// Level of detail: flakes are never drawn smaller than ~2 pixels. Further away a cell gathers 4^l
	// flakes whose tilts average out (amplitude / 2^l, like a real sparkle seen from afar); the part
	// that can no longer be resolved widens the gloss instead. Two levels blended: no popping.
	float px = max(length(fwidth(fp)), 1e-6);
	float lod = max(0.0, log2(px * 2.2));
	float l0 = floor(lod);
	float t = lod - l0;
	vec4 fa = flake_level(fp / exp2(l0), l0);
	vec4 fb = flake_level(fp / exp2(l0 + 1.0), l0 + 1.0);
	float ka = 1.0 / exp2(l0);
	float kb = 0.5 * ka;
	vec3 tilt = mix(fa.xyz * fa.w * ka, fb.xyz * fb.w * kb, t);
	float cover = mix(fa.w * ka, fb.w * kb, t);       // how much of this pixel is a resolved mirror flake
	vec3 n0 = NORMAL;
	vec3 n = normalize(n0 + tilt * sparkle);
	NORMAL = n;
	// the flakes that can't be seen one by one scatter the base layer's highlight
	float unresolved = sparkle * (1.0 - ka) * 0.9;
	float base_rough = sqrt(roughness * roughness + unresolved * unresolved);
	// metallic flop, as the three.js shader computes it
	float view_k = clamp(dot(-normalize(VERTEX), n0), 0.0, 1.0);
	float facing = clamp(dot(-normalize(VERTEX), n), 0.0, 1.0);
	vec3 col = mix(albedo.rgb, color2.rgb, pow(1.0 - view_k, 1.5) * flip);
	col = mix(col, col * col * 0.9, deep * (1.0 - view_k));
	vec3 base = col * mix(0.7, 1.05, pow(facing, 0.6));
	float flake_k = sparkle > 0.001 ? clamp(cover * 1.6, 0.0, 1.0) : 0.0;
	ALBEDO = mix(base, col * 1.08, flake_k * 0.5);
	// COLOR = baked AO (bike/bike_ao.gd; white without it): applied once, as AO (it used to darken the albedo
	// as well); a part of it on the direct light too, so the joints keep their depth
	AO = COLOR.r;
	AO_LIGHT_AFFECT = 0.3;
	METALLIC = mix(metallic, max(metallic, 0.9), flake_k);
	ROUGHNESS = mix(min(base_rough, 1.0), flake_rough, flake_k);
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
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
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail = 0.0;   // 1 = MetalFinish's brushed scan, ground in rings round the axle

varying float v_rotor_r;
varying vec2 v_rotor_p;

void vertex() {
	v_rotor_r = length(VERTEX.xy);
	v_rotor_p = VERTEX.xy;
}

void fragment() {
	// the pads ride on the outer band: it heats first and hottest, the glow creeping inwards as it builds
	float band = smoothstep(r0 + 0.012 * (1.0 - heat), r1, v_rotor_r);
	float h = heat * band;
	vec3 col = mix(vec3(0.5, 0.015, 0.0), vec3(1.0, 0.16, 0.01), smoothstep(0.2, 0.7, h));
	col = mix(col, vec3(1.0, 0.42, 0.08), smoothstep(0.8, 1.0, h));
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb * (1.0 - 0.6 * h) * COLOR.rgb;   // COLOR = baked AO   // hot steel loses its shine to the glow
	METALLIC = metallic;
	// grinding marks: the scan's brushing laid round the disc (4 tiles per turn: no seam), 16 cm across
	vec2 puv = vec2(atan(v_rotor_p.y, v_rotor_p.x) / 6.2831853 * 4.0, v_rotor_r / 0.16);
	float rt = mix(0.47, texture(rough_tex, puv).r, detail) / 0.47;
	ROUGHNESS = clamp(roughness * rt, 0.0, 1.0);
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
	m.set_shader_parameter("flake_scale", 1.0 / float(opts.get("flake", 0.00025)))
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
		da = flat_arrays(da)
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

	## the arrays of a triangle surface with every triangle on its own vertices and its own flat normal (faceted shading:
	## smoothed normals made the rotor's flat plate and slot edges look pillowy)
	static func flat_arrays(arr: Array) -> Array:
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		var col = arr[Mesh.ARRAY_COLOR]
		var uv = arr[Mesh.ARRAY_TEX_UV]
		var nv := PackedVector3Array(); var nn := PackedVector3Array()
		var nc := PackedColorArray(); var nu := PackedVector2Array()
		for t in range(0, idx.size() - 2, 3):
			var a := v[idx[t]]; var b := v[idx[t + 1]]; var c := v[idx[t + 2]]
			var n := (b - a).cross(c - a).normalized()
			for k in 3:
				var i := idx[t + k]
				nv.append(v[i]); nn.append(n)
				if col != null and (col as PackedColorArray).size() > i: nc.append((col as PackedColorArray)[i])
				if uv != null and (uv as PackedVector2Array).size() > i: nu.append((uv as PackedVector2Array)[i])
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = nv
		out[Mesh.ARRAY_NORMAL] = nn
		if not nc.is_empty(): out[Mesh.ARRAY_COLOR] = nc
		if not nu.is_empty(): out[Mesh.ARRAY_TEX_UV] = nu
		return out

	## heat: 0 cold .. 1 glowing hot
	func set_heat(k: float) -> void:
		heat = clampf(k, 0.0, 1.0)
		material.set_shader_parameter("heat", heat)
