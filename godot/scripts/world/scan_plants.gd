class_name ScanPlants
extends RefCounted
## Megascans scans in the world (2026-11-28, user: "bushes are too bad quality", "use all if possible", "for distance use
## billboards from them", grass clumps next to roads, rocks, tree stumps): plants, grass clumps, rocks, ground patches and
## stumps from the user's claimed Fab library (Fab Standard licence: may ship inside the game, the files may NOT be
## redistributed, so assets/plants_scan/ is gitignored; a clone without it keeps the old bushes / rocks). Made by root
## tools/make_scan_plants.py (Blender: <var>_near.glb <= 5000 triangles, <var>_far.glb = Megascans' billboard LOD3 or a
## decimated LOD) + tools/pack_scan_plant_textures.py (col.png colour + opacity, nrm.png normal + translucency,
## bcol.png / bnrm.png the billboard's).
##
## Lists "sp_<short>_<var>": the far mesh everywhere (fade mode 6: to the far fade, the sun-shadow caster; a billboard
## with its own material "sp_<short>_bb", flat ones turned to the camera) + its near twin "<list>_lod0" (mode 4: full to
## 36 m, gone by 48 m; Terrain._plant_twin) in "sp_<short>". Who uses what (TerrainChunkBuilder):
##   bush  - every bush the placement puts (_push -> _scan_plant), by country (`families`)
##   grass - clumps along the trail's edges (_roadside_grass), by country (`grass_families`)
##   rock / patch - part of the world's rocks in tundra / dry country (_push rock routing)
##   stump - forest stumps (_stumps, with colliders)
## Each chunk draws only VARS_PER_CHUNK variants per plant (all of them show across the world, a chunk adds few draws).
## BMX_OLD_PLANTS=1 = off.

const DIR := "res://assets/plants_scan/"
## folder -> [short name, role, solid]
const PLANTS := {
	"blackberry": ["blackberry", "bush", false],
	"boxwood": ["boxwood", "bush", false],
	"downy_willow": ["willow", "bush", false],
	"elderberry": ["elder", "bush", false],
	"bilberry": ["bilberry", "bush", false],
	"bracken_fern": ["bracken", "bush", false],
	"dead_shrubs": ["deadshrub", "bush", false],
	"rhazya": ["rhazya", "bush", false],
	"alpine_bearberry": ["bearberry", "bush", false],
	"crowberry": ["crowberry", "bush", false],
	"lingonberry": ["lingonberry", "bush", false],
	"desert_american_plant_cactus_medium_01": ["cactus_m01", "bush", true],
	"desert_american_plant_cactus_medium_03": ["cactus_m03", "bush", true],
	"desert_american_plant_cactus_small_04": ["cactus_s04", "bush", true],
	"tufted_grass": ["tufted", "grass", false],
	"rough_meadow_grass": ["meadow", "grass", false],
	"wild_grass": ["wildgrass", "grass", false],
	"dry_grass": ["drygrass", "grass", false],
	"marram_grass": ["marram", "grass", false],
	"tundra_grass": ["tundragrass", "grass", false],
	"cotton_grass": ["cottongrass", "grass", false],
	"grass_clumps": ["clumps", "grass", false],
	"grass_clumps_b": ["clumps2", "grass", false],
	"ribbon_grass": ["ribbon", "grass", false],
	"tundra_boulder": ["tboulder", "rock", true],
	"tundra_mossy_boulder": ["tmossboulder", "rock", true],
	"tundra_stone": ["tstone", "rock", true],
	"sandstone_boulder": ["sboulder", "rock", true],
	"desert_western_rock_medium_14": ["drock", "rock", true],
	"tundra_rocky_ground": ["trockground", "patch", true],
	"tundra_nordic_ground_mossy_mixed_large_01": ["tmossground", "patch", true],
	"pine_tree_stump": ["pinestump", "stump", true],
	"spruce_tree_stump": ["sprucestump", "stump", true],
	"broken_stump": ["brokenstump", "stump", true],
}
const VARS_PER_CHUNK := 2
const SPECIES_PER_CHUNK := 2   # (per family: draw calls; every species still shows across the world)
static var ALBEDO_LEAF := float(Env.raw("BMX_PLANT_ALB")) if Env.raw("BMX_PLANT_ALB") != "" else 1.0

## filled by ensure() on the main thread; the chunk builder (worker threads) only reads them
static var LISTS: Array = []          # every list name
static var BUSHY: Array = []          # the leafy bush / grass lists (the close-pass sound: Terrain.bushes_near)
static var VARS := {}                 # short name -> [list names]
static var SIZE := {}                 # list name -> Vector3 real size (m): x / z footprint, y height
static var ROLE := {}                 # short name -> role
static var SOLID := {}                # short name -> true for closed scanned meshes
static var FAR_MAT := {}              # list name -> material name of its far mesh
static var _done := false


static func enabled() -> bool:
	return Env.raw("BMX_OLD_PLANTS") != "1" and not LISTS.is_empty()

static func has(short: String) -> bool:
	return VARS.has(short)

## whether a list casts the sun's shadow (grass clumps and flat ground patches don't: draw calls in every cascade)
static func casts(list: String) -> bool:
	var short := list.substr(3).rsplit("_", true, 1)[0]
	var role: String = ROLE.get(short, "")
	return role != "grass" and role != "patch"


## find the exported scans, register their meshes + materials in TerrainGeo (call from TerrainGeo.ensure)
static func ensure(MESH: Dictionary, MAT: Dictionary) -> void:
	if _done:
		return
	_done = true
	if Env.raw("BMX_OLD_PLANTS") == "1":
		return
	for folder in PLANTS:
		var short: String = PLANTS[folder][0]
		var solid: bool = PLANTS[folder][2]
		var base: String = DIR + folder + "/"
		if not ResourceLoader.exists(base + "col.png"):
			continue
		var bb := ResourceLoader.exists(base + "bcol.png")
		var flat_any := false
		var names: Array = []
		for k in 12:
			var v := "ABCDEFGHIJKL"[k]
			if not (ResourceLoader.exists(base + v + "_near.glb") and ResourceLoader.exists(base + v + "_far.glb")):
				continue
			var ln := "sp_%s_%s" % [short, v.to_lower()]
			var far := TerrainGeo._glb_mesh(base + v + "_far.glb")
			var near := TerrainGeo._glb_mesh(base + v + "_near.glb")
			if far == null or near == null:
				continue
			var box := near.get_aabb()
			if not solid and Env.raw("BMX_PLANT_RAWNRM") != "1":
				near = _volume(near, box)
				if not bb:
					far = _volume(far, box)
			var fb := far.get_aabb()
			var flat := bb and minf(fb.size.x, fb.size.z) < 0.03 * maxf(maxf(fb.size.x, fb.size.z), 0.01)
			flat_any = flat_any or flat
			MESH[ln] = far
			MESH[ln + "_lod0"] = near
			SIZE[ln] = box.size
			FAR_MAT[ln] = "sp_" + short + ("_bb" if bb else "")
			names.append(ln)
		if names.is_empty():
			continue
		MAT["sp_" + short] = _material(base + "col.png", base + "nrm.png", solid, false)
		if bb:
			MAT["sp_" + short + "_bb"] = _material(base + "bcol.png", base + "bnrm.png", false, flat_any)
		VARS[short] = names
		ROLE[short] = PLANTS[folder][1]
		SOLID[short] = solid
		LISTS.append_array(names)
		if not solid and (ROLE[short] == "bush" or ROLE[short] == "grass"):
			BUSHY.append_array(names)


## the list's far mesh's material (a billboard's own, or the plant's)
static func material_of(list: String) -> String:
	return FAR_MAT.get(list, near_material_of(list))

## the near twin's material: the plant's own
static func near_material_of(list: String) -> String:
	return "sp_" + list.substr(3).rsplit("_", true, 1)[0]


## Leafy plants light as one volume (as the card bushes / crowns do): every normal is bent NORMAL_BEND of the way out
## from the plant's middle (a scanned leaf's own normal faces any way: the ones facing the ground went black under the
## sky), and the vertex colour holds a baked "deeper inside = darker" AO. The same box for both LODs (no pop).
const NORMAL_BEND := 0.65

static func _volume(mesh: Mesh, box: AABB) -> ArrayMesh:
	var out := ArrayMesh.new()
	var c := box.get_center()
	c.y = box.position.y + box.size.y * 0.42
	var r := Vector3(maxf(box.size.x * 0.5, 0.05), maxf(box.size.y * 0.55, 0.05), maxf(box.size.z * 0.5, 0.05))
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var C := PackedColorArray()
		C.resize(V.size())
		for i in V.size():
			var o := (V[i] - c) / r
			var d := clampf(o.length(), 0.0, 1.0)
			var oo := o.normalized() if o.length() > 0.001 else Vector3.UP
			N[i] = (N[i] * (1.0 - NORMAL_BEND) + oo * NORMAL_BEND).normalized()
			var hy := clampf((V[i].y - box.position.y) / maxf(box.size.y, 0.05), 0.0, 1.0)
			var ao := (0.45 + 0.55 * smoothstep(0.1, 1.0, d)) * (0.75 + 0.25 * hy)
			C[i] = Color(ao, ao, ao, 1.0)
		arr[Mesh.ARRAY_NORMAL] = N
		arr[Mesh.ARRAY_COLOR] = C
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


static func _material(col: String, nrm: String, solid: bool, face_cam: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/world/deco_cards.gdshader")
	m.set_shader_parameter("leaf_tex", load(col))
	m.set_shader_parameter("nrm_tex", load(nrm))
	m.set_shader_parameter("use_nrm", Env.raw("BMX_PLANT_NONRM") != "1")
	m.set_shader_parameter("nrm_depth", 0.7)
	m.set_shader_parameter("specular", 0.15)
	m.set_shader_parameter("albedo", Vector3.ONE * (1.0 if solid else ALBEDO_LEAF))
	m.set_shader_parameter("face_cam", face_cam)
	if solid:
		m.set_shader_parameter("cutoff", 0.0)
		m.set_shader_parameter("sway", 0.0)
		m.set_shader_parameter("flutter", 0.0)
		m.set_shader_parameter("backlight", 0.05)
		m.set_shader_parameter("scatter", 0.1)
		m.set_shader_parameter("roughness", 0.8)
	else:
		m.set_shader_parameter("volume_normals", true)
		m.set_shader_parameter("cutoff", 0.45)
		m.set_shader_parameter("sway", 0.03)
		m.set_shader_parameter("flutter", 0.004)
		m.set_shader_parameter("backlight", 0.35)
		m.set_shader_parameter("scatter", 0.75)
		m.set_shader_parameter("roughness", 0.75)
	return m


## which bushes grow where (biome weights from TerrainField.biome, read by the caller): short names, repeats = weight
static func families(dry: float, cold: float, wet: float, forest: float) -> Array:
	if dry > 0.45 and cold < 0.4:
		return ["deadshrub", "rhazya", "rhazya", "deadshrub"] + (["cactus_m01", "cactus_m03", "cactus_s04"] if dry > 0.6 else [])
	if cold > 0.4:
		return ["willow", "willow", "crowberry", "lingonberry", "bearberry", "bilberry"]
	if wet > 0.4:
		return ["willow", "willow", "elder", "blackberry"]
	if forest > 0.45:
		return ["bilberry", "blackberry", "bracken", "bracken", "boxwood", "elder"]
	return ["blackberry", "blackberry", "elder", "boxwood", "willow"]


## grass clumps along the trail's edges
static func grass_families(dry: float, cold: float, wet: float, forest: float) -> Array:
	if dry > 0.45 and cold < 0.4:
		return ["drygrass", "drygrass", "marram"] if dry < 0.7 else ["marram", "marram", "drygrass"]
	if cold > 0.4:
		return ["tundragrass", "tundragrass", "cottongrass"]
	if wet > 0.4:
		return ["cottongrass", "meadow", "ribbon", "tufted"]
	if forest > 0.45:
		return ["clumps", "clumps2", "ribbon", "wildgrass"]
	return ["tufted", "meadow", "wildgrass", "clumps", "clumps2", "ribbon"]


## the list + uniform scale for a thing the old placement wanted `want` metres wide; h = 0..1 hash of the spot,
## ch = 0..1 hash of the chunk (which few variants it uses); [] = none of these exported
static func pick(fam: Array, want: float, h: float, ch: float) -> Array:
	var avail: Array = []
	for s in fam:
		if VARS.has(s) and not avail.has(s):
			avail.append(s)
	if avail.is_empty():
		return []
	if avail.size() > SPECIES_PER_CHUNK:   # this chunk's few species, picked by the chunk
		var k0 := int(ch * 7919.0) % avail.size()
		var sub: Array = []
		for i in SPECIES_PER_CHUNK:
			sub.append(avail[(k0 + i) % avail.size()])
		avail = sub
	# repeats in the family weigh the pick (a species listed twice turns up twice as often)
	var wl: Array = []
	for s in fam:
		if avail.has(s):
			wl.append(s)
	avail = wl
	var short: String = avail[int(h * 997.0) % avail.size()]
	var vs: Array = VARS[short]
	var n := mini(VARS_PER_CHUNK, vs.size())
	var start := int(ch * 1009.0 + short.hash() % 97) % vs.size()
	var best := ""
	var bd := INF
	for i in n:
		var ln: String = vs[(start + i) % vs.size()]
		var sz: Vector3 = SIZE[ln]
		var w := maxf(sz.x, sz.z)
		var d := absf(log(maxf(w, 0.05) / maxf(want, 0.05)))
		if d < bd:
			bd = d
			best = ln
	var sz2: Vector3 = SIZE[best]
	var role: String = ROLE[short]
	# plants keep about their real size; rocks / patches / stumps are scaled to the size asked for
	var lo := 0.75 if role == "bush" or role == "grass" else 0.12
	var hi := 1.3 if role == "bush" or role == "grass" else 1.6
	var s := clampf(want / maxf(maxf(sz2.x, sz2.z), 0.05), lo, hi)
	return [best, s]
