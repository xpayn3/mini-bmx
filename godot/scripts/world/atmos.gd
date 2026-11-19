class_name Atmos
extends RefCounted
## Drives the weather every shader shares (shaders/atmos.gdshaderinc) through global shader uniforms:
## wind gusts rolling over the land, the bike parting the grass, drifting cloud shadows.
## cloud_shade() is the shader's function bit for bit (integer hash), so the sun light can be dimmed
## by exactly the shade at the rider: bike and rider go into the shadow of a cloud with the ground.

const CLOUD_DEPTH := 0.3
const CLOUD_DRIFT := 4.0   # m/s

var cloud_off := Vector2.ZERO
var wind_on := true
var gain := 1.0            # wind strength multiplier (the title screen runs a slight breeze)
var clouds_on := true
var shade := 1.0           # cloud shade at the rider this frame (1 = full sun)
var wind := Vector2.ZERO   # direction * gust strength (0..1) this frame

func update(t: float, dt: float, rider: Vector3, push: float) -> void:
	# the wind slowly swings round and its strength breathes
	var a := 0.62 + sin(t * 0.013) * 0.35
	var w := Vector2(cos(a), sin(a))
	var ws := (0.75 + 0.25 * sin(t * 0.05)) * gain if wind_on else 0.0
	wind = w * ws
	RenderingServer.global_shader_parameter_set("atm_wind", Vector4(w.x, w.y, t, ws))
	RenderingServer.global_shader_parameter_set("atm_pusher", Vector4(rider.x, rider.y, rider.z, push))
	cloud_off -= w * CLOUD_DRIFT * dt
	if cloud_off.length_squared() > 1e8: cloud_off = Vector2.ZERO   # keep the float offset small over hours
	var depth := CLOUD_DEPTH if clouds_on else 0.0
	shade = cloud_shade(rider.x, rider.z, depth)
	RenderingServer.global_shader_parameter_set("atm_cloud", Vector4(cloud_off.x, cloud_off.y, depth, shade))

static func _hash(cx: int, cy: int) -> float:
	var h := ((cx * 1597334673) & 0xffffffff) ^ ((cy * 3812015801) & 0xffffffff)
	h = ((h ^ (h >> 16)) * 2246822519) & 0xffffffff
	h ^= h >> 13
	return float(h & 16777215) / 16777215.0

static func _noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var ix := int(i.x)
	var iy := int(i.y)
	return lerpf(lerpf(_hash(ix, iy), _hash(ix + 1, iy), f.x), lerpf(_hash(ix, iy + 1), _hash(ix + 1, iy + 1), f.x), f.y)

func cloud_shade(x: float, z: float, depth: float) -> float:
	if depth <= 0.0: return 1.0
	var p := (Vector2(x, z) + cloud_off) * 0.03
	var n := _noise(p) * 0.62 + _noise(p * 2.2 + Vector2(5.3, 5.3)) * 0.28 + _noise(p * 5.1 - Vector2(2.1, 2.1)) * 0.10
	return 1.0 - depth * smoothstep(0.5, 0.66, n)
