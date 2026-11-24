@tool
class_name LevelLayers
extends Resource
## A level's hand-made ground, saved next to its scene (levels/<name>_layers.res, binary): an imported land (heights
## from a stretch of the procedural world, "Import world trail"; replaces the slope), sculpting (an offset on top,
## the 3D view's brushes) and surface paint (dirt / sand / rock). Grids are 1 m, each with its own origin.

@export var import_h := PackedFloat32Array()
@export var import_x0 := 0.0
@export var import_z0 := 0.0
@export var import_nx := 0
@export var import_nz := 0

@export var sculpt := PackedFloat32Array()   # m added to the land
@export var paint := PackedByteArray()       # 0 none, 1 dirt, 2 sand, 3 rock
@export var grid_x0 := 0.0
@export var grid_z0 := 0.0
@export var grid_nx := 0
@export var grid_nz := 0

const PAINT_NAMES := ["none", "dirt", "sand", "rock"]


## the sculpt / paint grid covering [x0, x0 + nx) x [z0, z0 + nz) at 1 m, keeping what is already painted / sculpted
func fit(x0: float, z0: float, nx: int, nz: int) -> void:
	if grid_nx == nx and grid_nz == nz and is_equal_approx(grid_x0, x0) and is_equal_approx(grid_z0, z0) and sculpt.size() == nx * nz: return
	var s2 := PackedFloat32Array(); s2.resize(nx * nz)
	var p2 := PackedByteArray(); p2.resize(nx * nz)
	for j in nz:
		for i in nx:
			var oi := i + int(round(x0 - grid_x0)); var oj := j + int(round(z0 - grid_z0))
			if oi >= 0 and oj >= 0 and oi < grid_nx and oj < grid_nz and sculpt.size() == grid_nx * grid_nz:
				s2[j * nx + i] = sculpt[oj * grid_nx + oi]
				p2[j * nx + i] = paint[oj * grid_nx + oi]
	sculpt = s2; paint = p2
	grid_x0 = x0; grid_z0 = z0; grid_nx = nx; grid_nz = nz


## what LevelField reads (plain data, also saved in a bake)
func data() -> Dictionary:
	return {"import_h": import_h, "import_x0": import_x0, "import_z0": import_z0, "import_nx": import_nx, "import_nz": import_nz,
		"sculpt": sculpt, "paint": paint, "grid_x0": grid_x0, "grid_z0": grid_z0, "grid_nx": grid_nx, "grid_nz": grid_nz}


func content_hash() -> int:
	return hash([hash(import_h), hash(sculpt), hash(paint), import_x0, import_z0, import_nx, grid_x0, grid_z0, grid_nx])
