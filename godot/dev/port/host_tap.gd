extends RefCounted
## (dev) Stands in for Game as BikePhysics' host during a lockstep tick (BMX_PHYS=cmp): everything goes through to the
## game, and the answers the physics gets back (msg_idle, smash) are kept so the C# twin gets the same ones.

var game
var answers: Array = []
var smashed := false   # something broke this tick: the twin, stepping after, sees the world changed (not compared)

func _init(g) -> void:
	game = g

# (what the physics reads off its host; a _get() returning null counts as "no such property")
var terrain:
	get: return game.terrain
var susp:
	get: return game.susp
var ragdoll:
	get: return game.ragdoll
var getup_anim:
	get: return game.getup_anim
var pedal_a0:
	get: return game.pedal_a0

func msg_idle() -> bool:
	var r: bool = game.msg_idle()
	answers.append(r)
	return r

func smash(c: Dictionary, vel: Vector3, pos: Vector3) -> bool:
	var r: bool = game.smash(c, vel, pos)
	answers.append(r)
	if r: smashed = true
	return r

func flash(text: String) -> void: game.flash(text)
func flow_up() -> void: game.flow_up()
func burst(pos: Vector3, n: int, s: int, power: float, with_dust := true) -> void: game.burst(pos, n, s, power, with_dust)
func rock_chips(c: Dictionary) -> void: game.rock_chips(c)
func start_crash(reason: String) -> void: game.start_crash(reason)
func begin_getup() -> void: game.begin_getup()
func on_trick(trick: String) -> void: game.on_trick(trick)
func on_style(points: int, label: String) -> void: game.on_style(points, label)
func on_takeoff() -> void: game.on_takeoff()
func on_bad_landing(sev: float) -> void: game.on_bad_landing(sev)
func on_landing(air_time: float, impact: float) -> void: game.on_landing(air_time, impact)
func ride_fx(dt: float, f: Vector3, va: float, in_water: bool) -> void: game.ride_fx(dt, f, va, in_water)
