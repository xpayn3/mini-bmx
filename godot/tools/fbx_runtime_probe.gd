extends SceneTree
## -s probe: can a Mixamo FBX be loaded at run time (no editor import)? prints the skeleton / animation found
func _init() -> void:
	var path := "res://assets/anim/mixamo/bored.fbx"
	var doc := FBXDocument.new()
	var st := FBXState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), st)
	print("FBXPROBE append err=", err)
	var n: Node = doc.generate_scene(st)
	print("FBXPROBE scene=", n, " skel=", n.find_children("*", "Skeleton3D", true, false).size(), " player=", n.find_children("*", "AnimationPlayer", true, false).size())
	for a in n.find_children("*", "AnimationPlayer", true, false):
		print("FBXPROBE anims=", (a as AnimationPlayer).get_animation_list())
	for s in n.find_children("*", "Skeleton3D", true, false):
		print("FBXPROBE bones=", (s as Skeleton3D).get_bone_count(), " first=", (s as Skeleton3D).get_bone_name(0))
	quit()
