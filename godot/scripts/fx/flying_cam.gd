class_name FlyingCam
extends RigidBody3D
## The helmet action cam torn off in a crash (Rider.break_action_cam): the camera body snaps off its
## hinge and tumbles away as a rigid body that bounces on the chunk ground (layer 2, like fence debris).
## Each tick it's held above the real terrain (small things tunnel through the chunk collision), then it
## lies where it landed until `LIFE` runs out or the rider respawns.

const LIFE := 30.0
var terrain
var t := 0.0
var _half := Vector3(0.017, 0.026, 0.036)   # half the body box (depth, height, width)

static func launch(parent: Node, body: Node3D, xf: Transform3D, ter, vel: Vector3, spin: Vector3) -> FlyingCam:
	var f := FlyingCam.new()
	f.terrain = ter
	f.collision_layer = 1 << 3
	f.collision_mask = 1 << 1
	f.mass = 0.15
	f.linear_damp = 0.05
	f.angular_damp = 0.4
	f.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.7
	f.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = f._half * 2.0
	cs.shape = bs
	f.add_child(cs)
	parent.add_child(f)
	# the box centred on the body's middle: the model hangs off the rigid body at its offset
	var mid := xf * Vector3(0, 0.0315, 0)
	f.global_transform = Transform3D(xf.basis.orthonormalized(), mid)
	f.add_child(body)
	body.transform = Transform3D(Basis(), Vector3(0, -0.0315, 0))
	f.linear_velocity = vel
	f.angular_velocity = spin
	return f

func _physics_process(dt: float) -> void:
	t += dt
	if OS.get_environment("BMX_GOPRO_PROBE") != "" and int(t * 4.0) != int((t - dt) * 4.0):   # tests
		var gp: float = terrain.height(global_position.x, global_position.z) if terrain else 0.0
		print("GOPRO t=%.2f pos=%s above_ground=%.3f v=%.2f" % [t, str(global_position), global_position.y - gp, linear_velocity.length()])
	if t > LIFE:
		queue_free()
		return
	if terrain == null: return
	var p := global_position
	var b := global_basis.orthonormalized()
	var reach := absf(b.x.y) * _half.x + absf(b.y.y) * _half.y + absf(b.z.y) * _half.z
	var g: float = terrain.top_height(p.x, p.z) if terrain.has_method("top_height") else terrain.height(p.x, p.z)
	if p.y - reach < g:
		global_position = Vector3(p.x, g + reach, p.z)
		var v := linear_velocity
		if v.y < 0.0: v.y = -v.y * 0.3
		v.x *= 0.8; v.z *= 0.8
		linear_velocity = v
		angular_velocity *= 0.85
