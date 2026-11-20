class_name ContactShadow
extends Node3D
## Contact shadows: soft dark patches on the ground right where the bike and rider touch it, so they
## sit on the trail instead of floating. The sun's shadow map can't do it: its bias (big at golden hour,
## against acne on the grazing-lit ground) lifts the shadow off the tyres, and in shade there is none.
## Three projected Decals on the ground layer only (Terrain.GROUND_LAYER: never the bike / rider): one
## under each tyre's contact patch (stretched along the bike) and a wide soft one under bike + body. Each
## fades out as what casts it rises off the ground (jumps), and with distance.

const TYRE_A := 0.6           # darkness right under a tyre that's on the ground
const TYRE_LEN := 0.32        # m: the tyre patch, along the bike (the darkening under the round tyre)
const TYRE_W := 0.13          # m: across
const TYRE_LIFT := 0.3        # m: tyre bottom this high over the ground = gone
const BODY_A := 0.22          # the wide one under bike + rider
const BODY_LEN := 1.7
const BODY_W := 0.7
const BODY_LIFT := 1.6        # m: bike middle this much higher than when riding = gone
const RIDE_H := 0.55          # m: the bike's middle (between the axles) over the ground, riding

var _tyre: Array[Decal] = []
var _body: Decal
var _tex: Texture2D

func _init() -> void:
	name = "ContactShadow"
	_tex = _blob()
	for i in 2: _tyre.append(_decal(Vector3(TYRE_W, 1.2, TYRE_LEN)))
	_body = _decal(Vector3(BODY_W, 3.0, BODY_LEN))

## a round soft blob (alpha), squeezed into an oval by each decal's size
static func _blob() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 1.0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.15), Color(0, 0, 0, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128; t.height = 128
	return t

func _decal(size: Vector3) -> Decal:
	var d := Decal.new()
	d.texture_albedo = _tex
	d.size = size
	d.cull_mask = Terrain.GROUND_LAYER
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.normal_fade = 0.2
	d.distance_fade_enabled = true
	d.distance_fade_begin = 40.0
	d.distance_fade_length = 15.0
	d.modulate = Color(0, 0, 0, 0)
	add_child(d)
	return d

## wf / wr: the drawn wheels (axle nodes), rf / rr their tyre radii, hd the heading (rad, x = cos, z = -sin),
## body: where the wide one goes (the bike's middle, or the ragdoll's pelvis in a crash), top: ground height
func update(wf: Vector3, wr: Vector3, rf: float, rr: float, hd: float, body: Vector3, body_h: float, top: Callable, gain := 1.0) -> void:
	var fwd := Vector3(cos(hd), 0.0, -sin(hd))
	_place(_tyre[0], wf, fwd, rf, TYRE_LIFT, TYRE_A * gain, top)
	_place(_tyre[1], wr, fwd, rr, TYRE_LIFT, TYRE_A * gain, top)
	_place(_body, body, fwd, body_h, BODY_LIFT, BODY_A * gain, top)

func _place(d: Decal, at: Vector3, fwd: Vector3, rest: float, lift: float, a: float, top: Callable) -> void:
	var gy: float = top.call(at.x, at.z)
	var h := at.y - rest - gy   # how far it is off the ground
	var k := 1.0 - smoothstep(0.0, lift, maxf(h, 0.0))
	d.visible = k > 0.01 and a > 0.0
	if not d.visible: return
	# the ground's slope here, so the patch lies on it (and the projection box isn't cut by a steep face)
	var e := 0.25
	var gx: float = top.call(at.x + e, at.z) - top.call(at.x - e, at.z)
	var gz: float = top.call(at.x, at.z + e) - top.call(at.x, at.z - e)
	var n := Vector3(-gx, 2.0 * e, -gz).normalized()
	var z := (fwd - n * fwd.dot(n)).normalized()
	var x := n.cross(z).normalized()
	d.global_transform = Transform3D(Basis(x, n, z), Vector3(at.x, gy, at.z))
	# a little wider and softer as it lifts (the penumbra grows)
	d.scale = Vector3.ONE * (1.0 + 0.6 * (1.0 - k))
	d.modulate = Color(0, 0, 0, a * k)
