extends SceneTree

## Writes res://tools/anim_test/test_wave.tscn: a Mixamo-like clip (mixamorig_ bones in centimetres under a 0.01
## scale, T-pose rest facing +Z, left at +X) where the figure lowers its arms, waves the right hand, sways the
## hips and turns the head. For testing RiderAnim without real downloads:
##   ..._console.exe --headless --path godot -s res://tools/make_test_clip.gd
##   BMX_ANIM_DIR=res://tools/anim_test/ ... --garage   (Kit tab) / the ride setup's rider step

const B := [   # name, parent, offset (cm)
	["Hips", "", Vector3(0, 100, 0)], ["Spine", "Hips", Vector3(0, 10, 0)], ["Spine1", "Spine", Vector3(0, 12, 0)],
	["Spine2", "Spine1", Vector3(0, 12, 0)], ["Neck", "Spine2", Vector3(0, 15, 0)], ["Head", "Neck", Vector3(0, 10, 0)],
	["HeadTop_End", "Head", Vector3(0, 18, 0)],
	["LeftShoulder", "Spine2", Vector3(6, 12, 0)], ["LeftArm", "LeftShoulder", Vector3(12, 0, 0)],
	["LeftForeArm", "LeftArm", Vector3(27, 0, 0)], ["LeftHand", "LeftForeArm", Vector3(26, 0, 0)],
	["LeftHandMiddle1", "LeftHand", Vector3(9, 0, 0)],
	["RightShoulder", "Spine2", Vector3(-6, 12, 0)], ["RightArm", "RightShoulder", Vector3(-12, 0, 0)],
	["RightForeArm", "RightArm", Vector3(-27, 0, 0)], ["RightHand", "RightForeArm", Vector3(-26, 0, 0)],
	["RightHandMiddle1", "RightHand", Vector3(-9, 0, 0)],
	["LeftUpLeg", "Hips", Vector3(9, -5, 0)], ["LeftLeg", "LeftUpLeg", Vector3(0, -42, 0)],
	["LeftFoot", "LeftLeg", Vector3(0, -42, 0)], ["LeftToeBase", "LeftFoot", Vector3(0, -8, 14)],
	["RightUpLeg", "Hips", Vector3(-9, -5, 0)], ["RightLeg", "RightUpLeg", Vector3(0, -42, 0)],
	["RightFoot", "RightLeg", Vector3(0, -42, 0)], ["RightToeBase", "RightFoot", Vector3(0, -8, 14)],
]

func _init() -> void:
	var root := Node3D.new(); root.name = "test_wave"
	var arm := Node3D.new(); arm.name = "Armature"; arm.scale = Vector3.ONE * 0.01
	root.add_child(arm); arm.owner = root
	var sk := Skeleton3D.new(); sk.name = "Skeleton3D"
	arm.add_child(sk); sk.owner = root
	for b in B:
		var i := sk.add_bone("mixamorig_" + b[0])
		if b[1] != "": sk.set_bone_parent(i, sk.find_bone("mixamorig_" + b[1]))
		sk.set_bone_rest(i, Transform3D(Basis(), b[2]))
	sk.reset_bone_poses()
	var an := Animation.new()
	an.length = 2.0
	an.loop_mode = Animation.LOOP_LINEAR
	var keys := 17
	var rot := func(bone: String, f: Callable) -> void:
		var tr := an.add_track(Animation.TYPE_ROTATION_3D)
		an.track_set_path(tr, NodePath("Armature/Skeleton3D:mixamorig_" + bone))
		for k in keys:
			var t := 2.0 * k / (keys - 1)
			an.rotation_track_insert_key(tr, t, f.call(t))
	var w := TAU / 2.0
	rot.call("LeftArm", func(t): return Quaternion(Vector3(0, 0, 1), deg_to_rad(-72)))   # arm down at the side
	rot.call("LeftForeArm", func(t): return Quaternion(Vector3(0, 1, 0), deg_to_rad(-15)))
	rot.call("RightArm", func(t): return Quaternion(Vector3(0, 0, 1), deg_to_rad(-40)))     # right arm up
	rot.call("RightForeArm", func(t): return Quaternion(Vector3(0, 0, 1), deg_to_rad(-55 - 25 * sin(t * w * 2))))   # waving
	rot.call("RightHand", func(t): return Quaternion(Vector3(1, 0, 0), deg_to_rad(-80)))   # palm forward
	rot.call("Hips", func(t): return Quaternion(Vector3(0, 0, 1), deg_to_rad(4 * sin(t * w))))
	rot.call("Spine1", func(t): return Quaternion(Vector3(0, 0, 1), deg_to_rad(-4 * sin(t * w))))
	rot.call("Head", func(t): return Quaternion(Vector3(0, 1, 0), deg_to_rad(25 * sin(t * w))))
	rot.call("LeftUpLeg", func(t): return Quaternion(Vector3(0, 0, 1), deg_to_rad(-4 * sin(t * w))))
	rot.call("RightUpLeg", func(t): return Quaternion(Vector3(0, 0, 1), deg_to_rad(-4 * sin(t * w))))
	rot.call("RightLeg", func(t): return Quaternion(Vector3(1, 0, 0), deg_to_rad(10)))
	var lib := AnimationLibrary.new()
	lib.add_animation("mixamo_com", an)
	var ap := AnimationPlayer.new(); ap.name = "AnimationPlayer"
	root.add_child(ap); ap.owner = root
	ap.add_animation_library("", lib)
	var ps := PackedScene.new()
	ps.pack(root)
	DirAccess.make_dir_recursive_absolute("res://tools/anim_test")
	print("save ", ResourceSaver.save(ps, "res://tools/anim_test/test_wave.tscn"))
	quit()
