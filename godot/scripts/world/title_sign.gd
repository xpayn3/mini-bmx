class_name TitleSign
extends Node3D
## The game's name as a Hollywood-style hillside sign behind the rider on the title screen: big white block letters, each its own
## upright slab (embedded Barlow Condensed Black, extruded TextMesh) standing on the ground at its own height, braced from behind
## with steel struts, facing the camera. Visual only, no collision. Made / freed by Game.set_scenic.

const WORD := "RUNOUT"
const SLAB := 1.1           # thickness
const STEP := 0.74          # letter pitch as a share of the height
const FONT_PX := 100
const PIX := 0.01           # 100 px * 0.01 = a 1 m em: the mesh is scaled up to LETTER_H

## `center` = the middle of the sign on the ground (x, z); `to_cam` = unit vector (xz) from the sign to the camera
func build(ground: Callable, center: Vector2, to_cam: Vector3, h: float) -> void:
	var font: Font = UITheme.file("BarlowCondensed-Black")
	var yaw := atan2(to_cam.x, to_cam.z)
	var right := Vector3(to_cam.z, 0.0, -to_cam.x)   # the sign's own +X (seen from the camera, left to right)
	var pitch := h * STEP
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.94, 0.9)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.86, 0.7)
	mat.emission_energy_multiplier = 0.5   # the sun is ahead of the camera, so the face is in shade: a little glow keeps it readable
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.33, 0.36)
	steel.roughness = 0.7
	var n := WORD.length()
	for i in n:
		var off := (i - (n - 1) * 0.5) * pitch
		var at := Vector3(center.x, 0.0, center.y) + right * off
		var tm := TextMesh.new()
		tm.text = WORD[i]
		tm.font = font
		tm.font_size = FONT_PX
		tm.pixel_size = PIX
		tm.depth = SLAB / h * 1.0
		tm.curve_step = 0.2
		var bb := tm.get_aabb()
		var k := h / maxf(bb.size.y, 0.001)   # scale so the letter is exactly h tall
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# sits with its foot at y 0 and its middle over the pivot
		mi.position = Vector3(-(bb.position.x + bb.size.x * 0.5) * k, -bb.position.y * k, 0.0)
		mi.scale = Vector3.ONE * k
		var holder := Node3D.new()
		holder.rotation.y = yaw
		# foot on the lowest of five ground reads across the letter (a slope steps each letter up the hill), a little sunk
		var w := bb.size.x * k
		var low := INF
		for s in 5:
			var p := at + right * (s / 4.0 - 0.5) * w
			low = minf(low, ground.call(p.x, p.z))
		holder.position = Vector3(at.x, low - 0.6, at.z)
		add_child(holder)
		holder.add_child(mi)
		# two braces from the back of the letter down to the hill
		for sx in [-0.28, 0.28]:
			_strut(holder, steel, Vector3(sx * w, h * 0.72, -SLAB * 0.5), Vector3(sx * w * 1.2, 0.0, -h * 0.42))

func _strut(parent: Node3D, m: Material, a: Vector3, b: Vector3) -> void:
	var bm := BoxMesh.new()
	var len := a.distance_to(b)
	bm.size = Vector3(0.45, 0.45, len)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	mi.look_at_from_position(mi.position, b, Vector3.UP)
