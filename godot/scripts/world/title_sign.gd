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
## `base_y` = height of the letters' feet (world y): the ground often falls away, so the letters stand on a steel beam
## held up by posts that run down to the hillside (a billboard gantry)
func build(ground: Callable, center: Vector2, to_cam: Vector3, h: float, base_y: float) -> void:
	var font: Font = UITheme.file("BarlowCondensed-Black")
	var yaw := atan2(to_cam.x, to_cam.z)
	var right := Vector3(to_cam.z, 0.0, -to_cam.x)   # the sign's own +X (seen from the camera, left to right)
	var pitch := h * STEP
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.94, 0.9)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.88)
	mat.emission_energy_multiplier = 1.1   # the sun is ahead of the camera, so the face is in shade: the glow keeps it a clean white against the golden sky
	mat.disable_fog = true   # the golden-hour haze washed the white letters into the sky; the sign is the title, it reads crisp
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.33, 0.36)
	steel.roughness = 0.7
	steel.disable_fog = true
	var n := WORD.length()
	var span := (n - 1) * pitch + h * 0.7
	var beam := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(span, 1.0, 1.6)
	beam.mesh = bmesh
	beam.material_override = steel
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	beam.position = Vector3(center.x, base_y - 0.5, center.y)
	beam.rotation.y = yaw
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
		holder.position = Vector3(at.x, base_y, at.z)
		add_child(holder)
		# two posts from the hillside up to the beam under this letter, crossed by a brace
		var foot_l: float = ground.call(at.x - right.x * w * 0.3, at.z - right.z * w * 0.3)
		var foot_r: float = ground.call(at.x + right.x * w * 0.3, at.z + right.z * w * 0.3)
		_strut(holder, steel, Vector3(-w * 0.3, 0.0, -SLAB), Vector3(-w * 0.3, foot_l - 1.0 - base_y, -SLAB), 0.9)
		_strut(holder, steel, Vector3(w * 0.3, 0.0, -SLAB), Vector3(w * 0.3, foot_r - 1.0 - base_y, -SLAB), 0.9)
		_strut(holder, steel, Vector3(-w * 0.3, (foot_l - base_y) * 0.15, -SLAB), Vector3(w * 0.3, (foot_r - base_y) * 0.55, -SLAB), 0.45)
		holder.add_child(mi)
		# two braces from the back of the letter down to the hill
		for sx in [-0.28, 0.28]:
			_strut(holder, steel, Vector3(sx * w, h * 0.72, -SLAB * 0.5), Vector3(sx * w * 1.2, 0.0, -h * 0.42))

func _strut(parent: Node3D, m: Material, a: Vector3, b: Vector3, thick := 0.45) -> void:
	var bm := BoxMesh.new()
	var len := a.distance_to(b)
	bm.size = Vector3(thick, thick, len)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	mi.look_at_from_position(mi.position, b, Vector3.UP)
