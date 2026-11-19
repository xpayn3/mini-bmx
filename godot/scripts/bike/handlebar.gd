class_name Handlebar
extends RefCounted
## Handlebar width / rise / material on the dh.glb "steer" mesh.
##
## The stock bar (in the "black" surface, with the stem and fork crown) is 787 mm wide. Its tube has
## vertex rings at the rise bend (|z| ~0.07..0.13) and under the grips (|z| >= 0.25) with one long
## straight run between. So: past the bend the run is stretched (width) and tilted up (rise) linearly,
## everything from the grips out moves rigidly, and each brake lever (plastic + chrome) moves as one
## piece by the bar's offset at its clamp. The outer bar is split into its own "bar" surface so it can
## take carbon while the stem / crown keep their paint. Meshes are cached per (width, rise).

const STOCK_WIDTH := 787.0     # mm, measured end to end
const STOCK_RISE := 30.0       # mm (our label for the stock bar)
const BEND := 0.125            # |z| where the straight run starts (last tube ring of the bend: 0.12)
const GRIP := 0.255            # |z| where it ends (first tube ring under the grip: ~0.26)
const BAR_Z := 0.105           # past this |z| and above BAR_Y it is bar / bar furniture, not crown
const BAR_Y := 0.10

const WIDTHS := [740, 760, 780, 800, 820]
const RISES := [0, 10, 20, 30, 40, 50]
const MATERIALS := [["alloy", "Alloy (crown paint)"], ["carbon", "Carbon gloss"], ["carbon_matte", "Carbon matte"]]

## popular DH bars (our approximation: width / rise snapped to the sizes above). Picking one sets the
## width, rise and material; touching any of those turns the model back to "custom".
const MODELS := {
	"stock":        {"brand": "GLORY",      "label": "Stock riser",       "width": 780, "rise": 30, "material": "alloy"},
	"fatbar":       {"brand": "RENTHAL",    "label": "Fatbar 35",         "width": 800, "rise": 30, "material": "alloy"},
	"fatbar_c":     {"brand": "RENTHAL",    "label": "Fatbar Carbon 35",  "width": 800, "rise": 30, "material": "carbon_matte"},
	"atlas":        {"brand": "RACE FACE",  "label": "Atlas 35",          "width": 820, "rise": 20, "material": "alloy"},
	"sixc":         {"brand": "RACE FACE",  "label": "SixC 35",           "width": 820, "rise": 20, "material": "carbon"},
	"skywire":      {"brand": "DEITY",      "label": "Skywire Carbon",    "width": 800, "rise": 20, "material": "carbon"},
	"blacklabel":   {"brand": "DEITY",      "label": "Blacklabel 800",    "width": 800, "rise": 40, "material": "alloy"},
	"bza":          {"brand": "CHROMAG",    "label": "BZA 35",            "width": 800, "rise": 50, "material": "alloy"},
	"spike":        {"brand": "SPANK",      "label": "Spike 800 Vibrocore", "width": 800, "rise": 30, "material": "alloy"},
	"oneup":        {"brand": "ONEUP",      "label": "Carbon Bar 35",     "width": 800, "rise": 40, "material": "carbon_matte"},
	"m9":           {"brand": "ENVE",       "label": "M9 DH",             "width": 800, "rise": 10, "material": "carbon"},
	"flat":         {"brand": "SPANK",      "label": "Oozy Flat 760",     "width": 760, "rise": 0,  "material": "alloy"},
}
const MATERIAL_SHORT := {"alloy": "Alloy", "carbon": "Carbon", "carbon_matte": "Carbon matte"}

static var _cache := {}


## fraction of the full offset at |z| = s
static func _ramp(s: float) -> float:
	return clampf((s - BEND) / (GRIP - BEND), 0.0, 1.0)


static func _is_bar(p: Vector3) -> bool:
	return absf(p.z) > BAR_Z and p.y > BAR_Y


## returns the reshaped mesh (stock mesh -> new ArrayMesh with an extra "bar" surface)
static func build(stock: Mesh, width_mm: float, rise_mm: float) -> ArrayMesh:
	var key := "%d|%d|%d" % [stock.get_instance_id(), roundi(width_mm), roundi(rise_mm)]
	if _cache.has(key):
		return _cache[key]
	var dw := (width_mm - STOCK_WIDTH) / 2000.0
	var dy := (rise_mm - STOCK_RISE) / 1000.0
	# the brake levers (plastic bodies, chrome blades) sit on the straight run: each side moves as one
	# piece, out with the grip and up by the tube's rise at the lever's mean |z|
	var lever_f := [1.0, 1.0]
	for si in stock.get_surface_count():
		var m := stock.surface_get_material(si)
		if m == null or m.resource_name != "plastic": continue
		var acc := [0.0, 0.0]
		var cnt := [0, 0]
		for p in stock.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			if _is_bar(p):
				var k := 1 if p.z > 0.0 else 0
				acc[k] += absf(p.z); cnt[k] += 1
		for k in 2:
			if cnt[k] > 0: lever_f[k] = _ramp(acc[k] / cnt[k])
	var out := ArrayMesh.new()
	for si in stock.get_surface_count():
		var arr := stock.surface_get_arrays(si)
		var mat := stock.surface_get_material(si)
		var mname := mat.resource_name if mat else ""
		var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in P.size():
			var p := P[i]
			if not _is_bar(p):
				continue
			var k := 1 if p.z > 0.0 else 0
			var fw := _ramp(absf(p.z))     # the tube: stretched / tilted along the straight run
			var fy := fw
			if mname == "rubber":
				fw = 1.0; fy = 1.0
			elif mname == "plastic" or mname == "chrome":
				fw = 1.0; fy = lever_f[k]
			P[i] = Vector3(p.x, p.y + dy * fy, p.z + signf(p.z) * dw * fw)
		arr[Mesh.ARRAY_VERTEX] = P
		if mname != "black" or arr[Mesh.ARRAY_INDEX] == null:
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			continue
		# split the black surface: triangles wholly on the outer bar -> their own "bar" surface
		var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		var bar := PackedInt32Array()
		var S: PackedVector3Array = stock.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]   # undeformed: same test as above
		for t in range(0, I.size(), 3):
			var on_bar := _is_bar(S[I[t]]) and _is_bar(S[I[t + 1]]) and _is_bar(S[I[t + 2]])
			(bar if on_bar else keep).append_array(PackedInt32Array([I[t], I[t + 1], I[t + 2]]))
		arr[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mat)
		if not bar.is_empty():
			var arr2 := arr.duplicate()
			arr2[Mesh.ARRAY_INDEX] = bar
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
			var bm: Material = mat.duplicate() if mat else StandardMaterial3D.new()
			bm.resource_name = "bar"
			out.surface_set_material(out.get_surface_count() - 1, bm)
	_cache[key] = out
	return out


## reshape the rig's steer mesh and give the bar its material (call after the paint is applied)
static func apply(steer: MeshInstance3D, bars: Dictionary) -> void:
	if steer == null or steer.mesh == null:
		return
	var w := float(bars.get("width", STOCK_WIDTH))
	var r := float(bars.get("rise", STOCK_RISE))
	var mat: String = bars.get("material", "alloy")
	# keep any paint overrides by surface name across the swap
	var over := {}
	for i in steer.mesh.get_surface_count():
		var m := steer.mesh.surface_get_material(i)
		if m and steer.get_surface_override_material(i):
			over[m.resource_name] = steer.get_surface_override_material(i)
	steer.mesh = build(steer.mesh, w, r)
	for i in steer.mesh.get_surface_count():
		var nm := steer.mesh.surface_get_material(i).resource_name
		var o = over.get("black" if nm == "bar" else nm)
		steer.set_surface_override_material(i, o)
		if nm == "bar" and mat.begins_with("carbon"):
			var cm: StandardMaterial3D = WheelGen.carbon_material("bar", mat == "carbon", Vector3(70, 70, 70))
			cm.uv1_triplanar = true
			steer.set_surface_override_material(i, cm)
