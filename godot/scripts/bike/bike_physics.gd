class_name BikePhysics
extends RefCounted
## The ride's GDScript FACE. The ride itself is C#: godot/sim/BikeSim.cs (+ BikeSim.Manual.cs), engine-free, through
## scripts/bike/BikePhysicsCs.cs (since 2026-11-28; docs/physics_port.md). **Make physics changes in the C#, not here.**
##
## This object holds the ride's state between steps, so the game (rider pose, HUD, audio, ride log, replay, playground)
## reads it at full GDScript speed as `phys.x`, `phys.lean`... Every call hands over to C#: the state crosses in one
## packed array (_cs_out / _cs_in below), the C# ride does the work, the state crosses back.
##   - the members at the end are GENERATED from BikeSim.cs's fields by `python godot/dev/port/gen_shell.py`: run it after
##     adding / removing / renaming a field in BikeSim.cs (a field the game never reads needs nothing more)
##   - a new call the game makes = a short function here + a case in BikePhysicsCs.Run
##   - the constants / test switches below are copies other scripts read: checked against the C# at the first ride
##
## The host (Game) supplies the world and the side effects (sim/Contracts.cs IRideHost / IGround; RideBridge.cs):
##   host.terrain  : height(), deck_height(), top_height(), surface(), jump_mask(), colliders_near()
##   host.flash(text), host.burst(pos, n, surf, power), host.flow_up(), host.msg_idle() -> bool,
##   host.smash(c, vel, pos) -> bool (fence / cactus / tape), host.rock_chips(c), host.start_crash(reason),
##   host.ride_fx(dt, f, va, in_water), host.susp (Suspension or null), host.pedal_a0 [left, right]

# copies of the C# ride's constants that other scripts read (_check_consts compares them once)
const G := 9.81
const FLOW_MAX := 5.0
const GETUP_HOLD := 0.25   # seconds holding hop to get up after a crash
const BRAKE_MU := [0.54, 0.64, 0.5, 0.4]
const MAN_BAR := 0.42       # rad the bars turn into the turn at full steer on the back wheel (Game._bar_draw)
const DRAG_REAL := 1.69
const SPIN_EDGE := 0.85     # stick to the side this far into a lip = a spin wound up (less = a whip)
static var _OLD_CADENCE := Env.raw("BMX_OLD_CADENCE") != ""
static var _OLD_TUCK := Env.raw("BMX_OLD_TUCK") != ""
static var _OLD_AUTOTUCK := Env.raw("BMX_OLD_AUTOTUCK") != ""
static var _OLD_STICKBIKE := Env.raw("BMX_OLD_STICKBIKE") != ""
static var _checked := false

# the members that aren't plain numbers (the rest are generated at the end)
var host
var T: Dictionary          # Tune.v (effective values); the C# ride reloads it when Tune changes
var cogs: Array = []       # the cassette (teeth per cog), set by setup
var crash_pending := ""
var crash_sim = null       # the crashed bike's body (CrashBikeCs), made by Game.start_crash
var crash_K := Transform3D()    # the model in the sim's body frame (BikeRig.pose_crash draws sim.BodyAt() * crash_K)
var crash_RK := Transform3D()   # ... the rig's root (x, y, z, heading, pitch, lean are read back from it)
var _cb_hit := [0.0, 0.0]       # each wheel's hit last step (a new hit can knock it off)
var _risk := {}        # reason -> trouble meter (0..1)
var prof = null        # the frame profiler's dict while it records (the C# ride adds its stage times to it)
var _cs                # the C# ride (BikePhysicsCs)

func _init(h) -> void:
	host = h
	_cs = load("res://scripts/bike/BikePhysicsCs.cs").new()
	_cs.Init(h)
	_cs.Defaults(self)   # the C# ride's starting values into the members
	if not _checked:
		_checked = true
		_check_consts()

func _check_consts() -> void:
	var copies := {"G": G, "FLOW_MAX": FLOW_MAX, "GETUP_HOLD": GETUP_HOLD, "BRAKE_MU": BRAKE_MU, "MAN_BAR": MAN_BAR,
		"DRAG_REAL": DRAG_REAL, "SPIN_EDGE": SPIN_EDGE, "_OLD_CADENCE": _OLD_CADENCE, "_OLD_TUCK": _OLD_TUCK,
		"_OLD_AUTOTUCK": _OLD_AUTOTUCK, "_OLD_STICKBIKE": _OLD_STICKBIKE}
	for k in copies:
		var mine = copies[k]
		var theirs = _cs.Const(k)
		if typeof(mine) == TYPE_ARRAY:
			mine = Array(mine).map(func(e): return float(e))
		if str(mine) != str(theirs):
			push_error("BikePhysics.%s = %s here but %s in sim/BikeSim.cs: change the copy in bike_physics.gd" % [k, mine, theirs])

## the drawn bike's geometry (glb extras: wheelbase, wheel radii, bottom bracket) and the ride config
## (GameState.bike_config_for: ride values, land, geared, mods = cogs / ring_k / susp)
func setup(extras: Dictionary, bike_cfg: Dictionary) -> void:
	_cs.Setup(self, extras, bike_cfg)

## one physics step. inp: {throttle 0..1, brake 0..1, steer -1..1 (+ = left), hop bool, sprint bool; optional:
## brake_front / brake_rear 0..1 (bare levers), body_fwd / body_lean -1..1 (the right stick), pad bool, ...}
func step(dt: float, inp: Dictionary) -> void:
	_cs.Step(self, dt, inp)

func reset_at(px: float, pz: float, hd: float) -> void: _cs.Run(self, "reset_at", [px, pz, hd])
func get_up() -> void: _cs.Run(self, "get_up", [])
func begin_crash() -> void: _cs.Run(self, "begin_crash", [])
## after a bad step: zero the body / rider state so a NaN there can't keep poisoning the ride
func reset_body() -> void: _cs.Run(self, "reset_body", [])
func flow_up() -> void: _cs.Run(self, "flow_up", [])
func shift(d: int) -> bool: return _cs.Run(self, "shift", [d])
## the same random draws for the same run (the playground's repeatable runs)
func reseed_grip(s: int) -> void: _cs.Run(self, "reseed_grip", [s])
## (tools) the energy probe (BMX_ENERGY_PROBE) prints its line now if _eb_t says it's due
func _e_tick(dt: float, brake: bool) -> void: _cs.Run(self, "e_tick", [dt, brake])
## every number finite? (the frame loop's safety net)
func is_sane() -> bool: return _cs.Run(self, "is_sane", [])
func gear_k() -> float: return _cs.Run(self, "gear_k", [])
func drive_ratio() -> float: return _cs.Run(self, "drive_ratio", [])

## the bike's forward direction on the ground
func fwd() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))

# static functions other scripts use (garage, rider, HUD): the C# ride's, through one shared object
static var _cst = null
static func _c():
	if _cst == null:
		_cst = load("res://scripts/bike/BikePhysicsCs.cs").new()
	return _cst
## the cog a ride starts in: nearest the old 16T reference (the garage rollers use it too)
static func start_gear(p_cogs: Array, p_ring_k: float) -> int: return _c().StartGear(p_cogs, p_ring_k)
static func crank_rate(w: float, gk: float, top_speed: float, p_sprint: float, ratio := -1.0) -> float: return _c().CrankRate(w, gk, top_speed, p_sprint, ratio)
static func ratio_for(gk: float, p_geared: bool) -> float: return _c().RatioFor(gk, p_geared)
static func kb_back_cap() -> float: return _c().KbBackCap()
static func slowness(va: float) -> float: return _c().Slowness(va)
static func pedal_rock(p_crank: float, p_sprint: float, p_pedal: float, va: float, p_bike_rock: float) -> float: return _c().PedalRock(p_crank, p_sprint, p_pedal, va, p_bike_rock)
static func drag_k() -> float: return _c().DragK()
# (plain maths, the same in BikeSim.cs)
static func smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
static func ang_diff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

# --- generated by dev/port/gen_shell.py from sim/BikeSim.cs's fields: do not edit by hand ---
# the C# ride's state, as this object's members (their values come from the C# ride: BikePhysicsCs.Defaults)
var L: float
var RWF: float
var RWR: float
var BB_REAR: float
var SH_R: float
var LAND: float
var geared: bool
var gear: int
var ring_k: float   # chainring vs. the stock 34T
var bike_rock: float
var x: float
var z: float
var y: float
var vy: float
var snow_k: float   # how deep the snow is under the bike, 0..1 (Game, from Terrain.snow_depth_at): ploughing drag
var heading: float
var v: float
var steer: float
var steer_in: float
var steer_in_v: float
var lean: float
var lean_v: float
var bike_lean: float
var counter: float
var rock: float
var pitch: float   # (drawn nose kick of a hop and where it eases to)
var pitch_v: float   # (drawn nose kick of a hop and where it eases to)
var hop_nose: float   # (drawn nose kick of a hop and where it eases to)
var _hop_nose_t: float   # (drawn nose kick of a hop and where it eases to)
var _hop_nose_m: float   # (drawn nose kick of a hop and where it eases to)
var wheelie_up: float   # sprint wheelie: how far up (rad) the rider is holding the front
var air: bool
var air_time: float
var air_k: float
var cap_bank: float
var lean_lim: float
var compress: float
var compress_v: float
var load: float
var body_y: float
var body_v: float
var body_x: float
var hip_shift: float
var body_xv: float
var hip_v: float
var v_last: float
var air_lean: float
var air_pull: float
var air_lock_h: bool
var air_lock_a: bool
var _lock_a0: float
var _air_own: float
var air_help: float
var flip_in: float
var flip_acc: float
var spin_acc: float
var pump_lift: float   # a lip pump's leg drive still to come at take-off (m/s)
var body_pw: float
var throw_v: float
var lock_tw: bool
var lock_ts: bool
var air_w: float
var air_inertia: float
var air_tilt: float
var air_tilt_v: float
var air_yaw: float
var air_tw: float
var air_tw_v: float
var land_jolt: float
var pivot: float
var pivot_acc: float
var aero_k: float   # air drag scale from the body position (tuck < 1, sat up > 1)
var body_in: float
var body_in_s: float
var flick_in: float
var flick: float
var wheelie_time: float   # how long the current stick wheelie / manual has been held
var wheelie_pedal: bool   # how long the current stick wheelie / manual has been held
var lock_sb: bool
var lock_sf: bool
var flick_kick: float
var _man_armed: bool
var _pull_age: float
var left_back: float
var _loop_saved: float   # a weight-back loop-out just caught (s)
var _man_pw: float   # power wheelie: weight back + pedalling lifts the front (0..1, eased)
var _man_over: float   # s the front has been held past the loop-out angle (direct manual: then he falls off the back)
var man_a: float
var man_w: float
var man_zone: bool
var man_lock: float
var man_zone_t: float
var pump_push: float
var pump_gain: float
var pump_idle: float
var pump_press_t: float
var _pump_release: float
var land_perfect: float   # 1 on a perfect landing, fades (HUD flash)
var man_pull: float   # the body stick pulled back for a manual (0..1): the HUD balance bar shows at once
var _bend_in: float   # what the rider asks of the legs' bend this step (hop held / stick back), before the crouch follows
var _ab_k: float   # auto-absorb on (eased) / the legs' rest it set (m, + = straighter), see _step_vertical
var _ab_bend: float   # auto-absorb on (eased) / the legs' rest it set (m, + = straighter), see _step_vertical
var dg_abs: float   # auto-absorb on (eased) / the legs' rest it set (m, + = straighter), see _step_vertical
var pleg: float   # the legs' pump stroke: -1 bent (hop held / stick back) .. +1 pushed straight (stick forward)
var pump_on: bool   # hop held on the ground, rolling: the HUD pump bar is up
var _sprint_lift: float   # balance mode: a sprint stamp from slow lifts the front through the balance
var n_rear: float
var n_front: float
var skid: bool
var _man_grace: float   # a little while after a balance manual ends: its loop-out / nose-down isn't judged as a crash
var nose_a: float
var nose_w: float
var nose_zone: bool
var nose_lock: float
var nose_push: float
var nose_time: float
var nose_brake_t: float
var _nose_grace: float
var _tw_t: float
var _ts_t: float
var _sb_t: float
var _sf_t: float
var _hop_tap_t: float
var _hop_buf: float
var _pop_miss: float
var _pop_miss_t: float
var _gl: float
var _gc: float
var _bh_back: float
var _bh_since: float
var _bh_peak: float
var gest_hop: float
var crouch: float
var crouch_t: float
var rebound: float
var _stick_hold: float
var _cr_rel: float
var _n_grd: float
var pop_wait: float
var _pop_arm_t: float
var squash: float
var _lip_ago: float   # s since a lip was last in sight just ahead
var _sus_synced: bool
var dg_sag_r: float   # (diagnostics: the rear's sag, on the front's travel scale like dg_xR)
var _sag_seen: float
var _fb_r: float   # the rear brake's deceleration this step (m/s2), like _fb_f
var _land_hit: float   # the biggest hit of the landing being judged
var _bog: float   # a bad landing's speed still to lose (m/s) + the rate it goes
var _bog_rate: float   # a bad landing's speed still to lose (m/s) + the rate it goes
var _land_pe: float   # the last touch-down's pitch against the ground (rad)
var _land_up: bool   # ... nose up (back wheel first)
var nose_k: float   # 0..1: how much this lip lets the front come up (steep + slow = all)
var _OLD_AIRBLEND: bool   # (tests: air_k + the drawn parts' raw air flag before 2026-11-26)
var _air_wl: float   # drawing: the air stick's share of the body counter-lean, held after touch-down while it eases out
var _bank_hold: float   # drawing: the bank last read on the ground, held through a skip (the physics' bank falls to flat in the air)
var _OLD_CURB: bool   # (tests: the old per-step edge check, rear stops dead)
var _OLD_RIMKICK: bool
var _rear_up_k: float   # 0..1: how far the rider has let the front lever off because the rear was thrown up
var _ty_f: float   # each tyre's push last substep (m/s2 of the whole weight)
var _ty_r: float   # each tyre's push last substep (m/s2 of the whole weight)
var _rim_hit: float   # the most speed the frame lost against the ground with nothing left to give, since it was read (m/s)
var land_heavy: float
var land_fold: float
var _stun: float
var land_yaw: float
var _tuck_in: bool   # the tuck is held (hop, in the air)
var _graze: bool   # the last "landing" was a tyre brushing the lip on the way up
var air_peak: float   # this flight: the highest the bike got over the ground under it (m)
var pop_fx: float
var squash_fx: float
var pop_q: float
var pop_time: float
var _pop_used: float
var whip: float
var whip_hold: float
var whip_side: float
var _whip_t: float
var _whip_flashed: bool
var _whip_arm: float
var _whip_straight: bool   # this whip started on the straight (no steer) / its widest slip   # corner whip / drift (both sticks one way)
var _whip_ang: float   # this whip started on the straight (no steer) / its widest slip   # corner whip / drift (both sticks one way)
var flick_v: float   # flick spring speed, deliberate-flick detector
var _flick_arm: float   # flick spring speed, deliberate-flick detector
var _flick_side: float   # flick spring speed, deliberate-flick detector
var air_stick: Vector2   # right stick in the air, eased: x lean (+ left), y nose (+ up)
var edge_s: float   # right stick held at its top / bottom edge in the air: the flip spin, built up gently
var spin_hold: float
var spin_k: float
var yaw_edge_s: float
var yaw_hold: float
var stick_yaw: float
var style_air: float   # this jump's tweak: seconds x how far the stick swung the bike about (style points)   # how long it's been held one way, and the spin-rate multiplier that gives
var pad: bool
var bank_probe: bool
var lean_room: float   # how steeply the ground rises beside the bike on its lean side (rad, eased)
var _bank_raw: float   # the player is on a gamepad (Settings.pad_active): triggers don't tilt / throw in the air
var wheel_f: float   # the raw gas key / trigger this step (pedal is its smoothed version)
var wheel_r: float   # the raw gas key / trigger this step (pedal is its smoothed version)
var crank: float   # the raw gas key / trigger this step (pedal is its smoothed version)
var pedal: float   # the raw gas key / trigger this step (pedal is its smoothed version)
var throttle_in: float   # the raw gas key / trigger this step (pedal is its smoothed version)
var yaw_rate: float
var shake: float
var course: float
var slip: float
var since_land: float
var turn_off: float
var rev_cap: float
var _rev_land: bool
var _land_fix: bool
var _fakie_hold: float
var slip_w: float
var grip_r: float
var loose: float
var bar_catch: float
var _grip_cv: float
var _squirm: float
var _grip_rough: float
var front_use: float
var front_push: float
var brake_f: float
var brake_r: float
var rear_lock: float
var front_lock: float
var _fb_f: float
var corner_g: float
var weight_in: float
var lean_err: float
var knock: float
var _amax: float
var _amin: float
var bal_k: float
var _b_prev: float
var _f_prev: float
var _circ_f: float
var _brake_feel: bool
var _a_rear: float
var berm_k: float   # how much a berm is carrying the turn right now (0..bermAssist)
var bank_lean: float   # the drawn lean into tilted ground (bankLean x bank), bike + body
var bank_sq: float   # how far the body goes into line with the bike on banked ground (0 flat .. bankBody), drawn only
var bank_v: float   # how fast the bank reading is changing (its smoothing spring)
var _load_s: float   # the tyres' load factor for grip, eased (relaxation)
var _share_f: float   # the front tyre's share of the load, eased the same way
var _OLD_DIRT: bool
var _brk_r: float   # the levers as squeezed (they take brakeRamp s to bite)
var _brk_f: float   # the levers as squeezed (they take brakeRamp s to bite)
var _feel_r: float   # the grip the rider THINKS each tyre has (lags a loose patch: he gets caught out)
var _feel_f: float   # the grip the rider THINKS each tyre has (lags a loose patch: he gets caught out)
var brk_loose_f: float   # how loose the ground under each tyre is for braking (0..~1.2)
var brk_loose_r: float   # how loose the ground under each tyre is for braking (0..~1.2)
var surf_f: int   # the ground under each tyre, its eased grip
var surf_r: int   # the ground under each tyre, its eased grip
var _mu_f: float   # the ground under each tyre, its eased grip
var _mu_r: float   # the ground under each tyre, its eased grip
var _bmu_f: float   # ...and its eased braking grip (BRAKE_MU)
var _bmu_r: float   # ...and its eased braking grip (BRAKE_MU)
var _OLD_BRAKE: bool   # (tests: the lever-limited brakes before 2026-11-23)
var _gx_lean: float   # the rest of the ground's drawn lean (body stick, slow steer, whip), eased through jumps
var _lock_hold: float   # steering into tilted ground, held LOCK_HOLD s after letting go (bankLock)
var weave_lean: float   # the weave's share of bike_lean this step (read by Game)
var _weave: float   # the bike's own small roll under the rider (step 2)
var _wv_t: float   # the bike's own small roll under the rider (step 2)
var man_lk: float   # back-wheel turn look: 0..1 weight, the eased drawn lean (see _step_steer)
var _man_lean_s: float   # back-wheel turn look: 0..1 weight, the eased drawn lean (see _step_steer)
var _bike_lead: float   # how far the bike runs ahead of the rider's lean while it changes (two masses)
var _lean_peak: float   # this jump's biggest lay-over in the air (tabletop, rad)
var _scrub_k: float   # this take-off was soaked (squash / absorb) - with a lay-over or whip: a scrub
var _whip_peak: float   # this jump's biggest air whip (bike twisted against the body, rad)
var risk: float   # the biggest meter now: the rider's reflexes scale with it (and the HUD may show it)
var _risk_peak: float   # the highest it got since it was last clear: a full recovery from > 0.5 = SAVED!
var _crash_log: bool
var front_air: bool
var rear_air: bool
var c_f: bool
var c_r: bool
var pitch_w: float
var stamina: float
var tired: bool
var sprint: float
var spin: float
var a_drive: float
var a_pedal: float   # a_drive without a brake applied while rolling backwards (what "pedalling" readers use)
var _nR_s: float   # the rear tyre's load as its grip feels it (eased: tyre relaxation, see _grip_step)
var _OLD_GRIP: bool   # (tests: the grip before the off-trail fix)
var n_f: float
var n_r: float
var n_ref: float
var flow: float
var flow_t: float
var spun_out: bool
var bank: float
var carve: float
var carve_acc: float
var carve_berm: bool
var lat_m: float   # (n_load: the ground's push on the tyres, m/s², for the ride log)
var lat_a: float   # (n_load: the ground's push on the tyres, m/s², for the ride log)
var n_load: float   # (n_load: the ground's push on the tyres, m/s², for the ride log)
var g_pitch: float
var w_init: bool
var hf_prev: float
var hr_prev: float
var zw_f: float
var zw_r: float
var vw_f: float
var vw_r: float
var nose_ref: float   # (_gpc_last: the wheel-ground slope the last step both tyres were down)
var _gpc_last: float   # (_gpc_last: the wheel-ground slope the last step both tyres were down)
var w_f: float
var w_r: float
var y_draw: float
var pitch_draw: float
var kick_t: float
var hop_t: float
var hop_load: float
var hop_charge: float
var charge: float
var lift_t: float
var hop_block: bool
var hop_held: bool
var prep: float
var land_prep: float
var pop_fired: bool
var lip_scan: int   # lip_state: 0 unknown, 1 none in sight, 2 lip_last valid
var lip_state: int   # lip_state: 0 unknown, 1 none in sight, 2 lip_last valid
var lip_last: float   # lip_state: 0 unknown, 1 none in sight, 2 lip_last valid
var y_prev: float
var pump_acc: float
var brake_heat: float
var brake_fade: float
var dive: float
var _fade_warn: bool
var _kick_k: float
var _BOB_PROBE: bool
var _bob_n: int
var _bob_s: float
var _bob_q: float
var _OLD_SHORTAIM: bool   # (tests: the same slow hands-off aim on every flight)
var _OLD_FADE: bool   # (tests: before the brakes could fade)
var _OLD_SPEEDTUCK: bool
var speed_tuck: float   # 0..1, eased: how far into the speed tuck
var speed_tuck_auto: float   # the automatic part (by speed)
var _HEAT_HOLD: float
var _OLD_SUSPFX: bool   # (tests: before dive steering, pedal bob and kickback)
var foot_down: bool   # set by Game: the rider's foot is on the ground (the bike stays put)
var brake_stop: bool   # braked to a standstill: held in place while the brake stays on
var _rev_hold: float   # s the brake has been held at a stop (reverse after REV_HOLD)
var rev_on_hold: bool   # (tests that hold the brake to check friction turn it off)
var brake_back: bool   # brake pressed fresh from a standstill: backs the bike up
var chunk_acc: float
var distance: float
var probe_bottom: int
var probe_acc2: float
var probe_n: int
var probe_vy: float
var probe_g2: float
var dg_xF: float
var dg_xR: float
var dg_vF: float
var dg_vR: float
var dg_fF: float
var dg_fR: float
var dg_tyF: float
var dg_tyR: float
var dg_sqF: float
var dg_sqR: float
var dg_botF: bool
var dg_botR: bool
var dg_blowF: bool
var dg_blowR: bool
var dg_travel: float
var dg_sag: float
var dg_leg: float
var dg_leg_f: float
var dg_knee: float
var dg_cF: bool
var dg_cR: bool
var ground_jolt: float   # biggest leg bottom-out on the ground (not a landing) since the test last read it
var skid_fx: bool
var surf: int
var hop_bar: float
var hop_bar_show: bool
var crash_on: bool
var crash_t: float
var crash_side: float
var getup_need: float   # hold time to get up (longer to revive at zero life, set by the HUD)
var crash_rest: float
var crash_bvy: float
var crash_fall_v: float
var crash_armed: bool
var crash_hold: float
var _bal_shoved: bool
var _cb_off_t: float   # tests (BMX_WHEEL_OFF): when the forced wheels came off
var _OLD_CRASHBIKE: bool
var _OLD_RIDERBIKE: bool
var _g_y: float
var _g_pitch: float
var _g_hr: float
var _g_hf: float
var _EPROBE: bool
var _OLD_BOUNCE: bool   # (tests: a one-wheel bounce seeds the flight from the body's spin, as before)
var _e_y: float
var _eb_t: float
var _JOLT_PROBE: bool
var _jp_rim: int
var _jp_t: float
var wr_w: float
var _wr_old: bool
var wr_knock: float   # the biggest one-tick change of the rear wheel's vertical speed since the sound read it (m/s)
var _wr_vr: float
var wr_vib2: float   # sum of squared one-tick changes of the rear wheel's vertical speed (+ how many ticks) since the sound read it
var wr_vibn: int   # sum of squared one-tick changes of the rear wheel's vertical speed (+ how many ticks) since the sound read it
var chain_slip: float   # s left of a skip (0 = the chain holds)
var chain_slip_k: float   # 0..1 how much drive is lost right now (HUD / rumble / tests can read it)
var spin_out_k: float   # 0..1: pushing on the ground at (from ~90 % of) the legs' top cadence, or spun out past it (drawing: head down)
var _air_pull_v: float   # air_pull's speed (its spring)
var spin_load: float   # -1..1: a spin wound up into the lip ahead
var _spin_in: float   # this flight's spin wind-up
var _flip_in: float   # this flight's flip throw (-1..1, + = back)
var _pop_latch: bool
var test_rider: bool   # the playground's test rider is riding (Game.set_demo)
var _land_pitch: float   # the ground's slope where this flight comes down (_landing_slope), NAN on the ground
var _aim_tick: int
var _land_t: float   # s of flight left (from _landing_slope)
var land_vn: float   # m/s: the predicted speed into the landing, square to its slope
var _vn_td: float   # (tests: the last flight's, for the HIT line)
var _reach_td: float   # (tests: the last flight's, for the HIT line)
var land_reach: float   # 0.35..1: how far the legs reach for this landing (by land_vn)
var _air_steer_s: float   # the steered heading offset in use (rad, smoothed), kept for the landing
var aim_off: float
var _air_aim_s: float   # the aim in use (rad, smoothed)
var carve_now: float   # rad: how far the last landing's carve turned the travel (drawing: the bars bite into it, fades)
var whip_load: float   # -1..1: the whip wound up into the lip ahead (signed like the stick)
var _whip_in: float   # this flight's whip load
var lip_h: float   # the lip ahead's height over the ground where it was spotted (m)
var _absorb_k: float   # a hands-off absorb waiting for the rear wheel to leave the lip
var auto_absorb: float   # 0..1: hands off, how much he soaks up the lip ahead instead of popping it
var _pull_k: float   # this step's pull-up (0..1)
var _air_pop: float   # how good this flight's take-off pop was (0..1), when the player pumped it (pro_flight)
var pro_pop: bool   # the pop waiting for the lip is the player's (a timed pop / a held crouch), not the rider's own
var pro_flight: bool   # this flight left off the player's pump: the pro move (bike pulled nose up, then up into him)
var _OLD_LS: bool
var _OLD_RELAX: bool

const _CS_SLOTS := 443

func _cs_out() -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(443)
	a[0] = L
	a[1] = RWF
	a[2] = RWR
	a[3] = BB_REAR
	a[4] = SH_R
	a[5] = LAND
	a[6] = 1.0 if geared else 0.0
	a[7] = gear
	a[8] = ring_k
	a[9] = bike_rock
	a[10] = x
	a[11] = z
	a[12] = y
	a[13] = vy
	a[14] = snow_k
	a[15] = heading
	a[16] = v
	a[17] = steer
	a[18] = steer_in
	a[19] = steer_in_v
	a[20] = lean
	a[21] = lean_v
	a[22] = bike_lean
	a[23] = counter
	a[24] = rock
	a[25] = pitch
	a[26] = pitch_v
	a[27] = hop_nose
	a[28] = _hop_nose_t
	a[29] = _hop_nose_m
	a[30] = wheelie_up
	a[31] = 1.0 if air else 0.0
	a[32] = air_time
	a[33] = air_k
	a[34] = cap_bank
	a[35] = lean_lim
	a[36] = compress
	a[37] = compress_v
	a[38] = load
	a[39] = body_y
	a[40] = body_v
	a[41] = body_x
	a[42] = hip_shift
	a[43] = body_xv
	a[44] = hip_v
	a[45] = v_last
	a[46] = air_lean
	a[47] = air_pull
	a[48] = 1.0 if air_lock_h else 0.0
	a[49] = 1.0 if air_lock_a else 0.0
	a[50] = _lock_a0
	a[51] = _air_own
	a[52] = air_help
	a[53] = flip_in
	a[54] = flip_acc
	a[55] = spin_acc
	a[56] = pump_lift
	a[57] = body_pw
	a[58] = throw_v
	a[59] = 1.0 if lock_tw else 0.0
	a[60] = 1.0 if lock_ts else 0.0
	a[61] = air_w
	a[62] = air_inertia
	a[63] = air_tilt
	a[64] = air_tilt_v
	a[65] = air_yaw
	a[66] = air_tw
	a[67] = air_tw_v
	a[68] = land_jolt
	a[69] = pivot
	a[70] = pivot_acc
	a[71] = aero_k
	a[72] = body_in
	a[73] = body_in_s
	a[74] = flick_in
	a[75] = flick
	a[76] = wheelie_time
	a[77] = 1.0 if wheelie_pedal else 0.0
	a[78] = 1.0 if lock_sb else 0.0
	a[79] = 1.0 if lock_sf else 0.0
	a[80] = flick_kick
	a[81] = 1.0 if _man_armed else 0.0
	a[82] = _pull_age
	a[83] = left_back
	a[84] = _loop_saved
	a[85] = _man_pw
	a[86] = _man_over
	a[87] = man_a
	a[88] = man_w
	a[89] = 1.0 if man_zone else 0.0
	a[90] = man_lock
	a[91] = man_zone_t
	a[92] = pump_push
	a[93] = pump_gain
	a[94] = pump_idle
	a[95] = pump_press_t
	a[96] = _pump_release
	a[97] = land_perfect
	a[98] = man_pull
	a[99] = _bend_in
	a[100] = _ab_k
	a[101] = _ab_bend
	a[102] = dg_abs
	a[103] = pleg
	a[104] = 1.0 if pump_on else 0.0
	a[105] = _sprint_lift
	a[106] = n_rear
	a[107] = n_front
	a[108] = 1.0 if skid else 0.0
	a[109] = _man_grace
	a[110] = nose_a
	a[111] = nose_w
	a[112] = 1.0 if nose_zone else 0.0
	a[113] = nose_lock
	a[114] = nose_push
	a[115] = nose_time
	a[116] = nose_brake_t
	a[117] = _nose_grace
	a[118] = _tw_t
	a[119] = _ts_t
	a[120] = _sb_t
	a[121] = _sf_t
	a[122] = _hop_tap_t
	a[123] = _hop_buf
	a[124] = _pop_miss
	a[125] = _pop_miss_t
	a[126] = _gl
	a[127] = _gc
	a[128] = _bh_back
	a[129] = _bh_since
	a[130] = _bh_peak
	a[131] = gest_hop
	a[132] = crouch
	a[133] = crouch_t
	a[134] = rebound
	a[135] = _stick_hold
	a[136] = _cr_rel
	a[137] = _n_grd
	a[138] = pop_wait
	a[139] = _pop_arm_t
	a[140] = squash
	a[141] = _lip_ago
	a[142] = 1.0 if _sus_synced else 0.0
	a[143] = dg_sag_r
	a[144] = _sag_seen
	a[145] = _fb_r
	a[146] = _land_hit
	a[147] = _bog
	a[148] = _bog_rate
	a[149] = _land_pe
	a[150] = 1.0 if _land_up else 0.0
	a[151] = nose_k
	a[152] = 1.0 if _OLD_AIRBLEND else 0.0
	a[153] = _air_wl
	a[154] = _bank_hold
	a[155] = 1.0 if _OLD_CURB else 0.0
	a[156] = 1.0 if _OLD_RIMKICK else 0.0
	a[157] = _rear_up_k
	a[158] = _ty_f
	a[159] = _ty_r
	a[160] = _rim_hit
	a[161] = land_heavy
	a[162] = land_fold
	a[163] = _stun
	a[164] = land_yaw
	a[165] = 1.0 if _tuck_in else 0.0
	a[166] = 1.0 if _graze else 0.0
	a[167] = air_peak
	a[168] = pop_fx
	a[169] = squash_fx
	a[170] = pop_q
	a[171] = pop_time
	a[172] = _pop_used
	a[173] = whip
	a[174] = whip_hold
	a[175] = whip_side
	a[176] = _whip_t
	a[177] = 1.0 if _whip_flashed else 0.0
	a[178] = _whip_arm
	a[179] = 1.0 if _whip_straight else 0.0
	a[180] = _whip_ang
	a[181] = flick_v
	a[182] = _flick_arm
	a[183] = _flick_side
	a[184] = air_stick.x
	a[185] = air_stick.y
	a[186] = edge_s
	a[187] = spin_hold
	a[188] = spin_k
	a[189] = yaw_edge_s
	a[190] = yaw_hold
	a[191] = stick_yaw
	a[192] = style_air
	a[193] = 1.0 if pad else 0.0
	a[194] = 1.0 if bank_probe else 0.0
	a[195] = lean_room
	a[196] = _bank_raw
	a[197] = wheel_f
	a[198] = wheel_r
	a[199] = crank
	a[200] = pedal
	a[201] = throttle_in
	a[202] = yaw_rate
	a[203] = shake
	a[204] = course
	a[205] = slip
	a[206] = since_land
	a[207] = turn_off
	a[208] = rev_cap
	a[209] = 1.0 if _rev_land else 0.0
	a[210] = 1.0 if _land_fix else 0.0
	a[211] = _fakie_hold
	a[212] = slip_w
	a[213] = grip_r
	a[214] = loose
	a[215] = bar_catch
	a[216] = _grip_cv
	a[217] = _squirm
	a[218] = _grip_rough
	a[219] = front_use
	a[220] = front_push
	a[221] = brake_f
	a[222] = brake_r
	a[223] = rear_lock
	a[224] = front_lock
	a[225] = _fb_f
	a[226] = corner_g
	a[227] = weight_in
	a[228] = lean_err
	a[229] = knock
	a[230] = _amax
	a[231] = _amin
	a[232] = bal_k
	a[233] = _b_prev
	a[234] = _f_prev
	a[235] = _circ_f
	a[236] = 1.0 if _brake_feel else 0.0
	a[237] = _a_rear
	a[238] = berm_k
	a[239] = bank_lean
	a[240] = bank_sq
	a[241] = bank_v
	a[242] = _load_s
	a[243] = _share_f
	a[244] = 1.0 if _OLD_DIRT else 0.0
	a[245] = _brk_r
	a[246] = _brk_f
	a[247] = _feel_r
	a[248] = _feel_f
	a[249] = brk_loose_f
	a[250] = brk_loose_r
	a[251] = surf_f
	a[252] = surf_r
	a[253] = _mu_f
	a[254] = _mu_r
	a[255] = _bmu_f
	a[256] = _bmu_r
	a[257] = 1.0 if _OLD_BRAKE else 0.0
	a[258] = _gx_lean
	a[259] = _lock_hold
	a[260] = weave_lean
	a[261] = _weave
	a[262] = _wv_t
	a[263] = man_lk
	a[264] = _man_lean_s
	a[265] = _bike_lead
	a[266] = _lean_peak
	a[267] = _scrub_k
	a[268] = _whip_peak
	a[269] = risk
	a[270] = _risk_peak
	a[271] = 1.0 if _crash_log else 0.0
	a[272] = 1.0 if front_air else 0.0
	a[273] = 1.0 if rear_air else 0.0
	a[274] = 1.0 if c_f else 0.0
	a[275] = 1.0 if c_r else 0.0
	a[276] = pitch_w
	a[277] = stamina
	a[278] = 1.0 if tired else 0.0
	a[279] = sprint
	a[280] = spin
	a[281] = a_drive
	a[282] = a_pedal
	a[283] = _nR_s
	a[284] = 1.0 if _OLD_GRIP else 0.0
	a[285] = n_f
	a[286] = n_r
	a[287] = n_ref
	a[288] = flow
	a[289] = flow_t
	a[290] = 1.0 if spun_out else 0.0
	a[291] = bank
	a[292] = carve
	a[293] = carve_acc
	a[294] = 1.0 if carve_berm else 0.0
	a[295] = lat_m
	a[296] = lat_a
	a[297] = n_load
	a[298] = g_pitch
	a[299] = 1.0 if w_init else 0.0
	a[300] = hf_prev
	a[301] = hr_prev
	a[302] = zw_f
	a[303] = zw_r
	a[304] = vw_f
	a[305] = vw_r
	a[306] = nose_ref
	a[307] = _gpc_last
	a[308] = w_f
	a[309] = w_r
	a[310] = y_draw
	a[311] = pitch_draw
	a[312] = kick_t
	a[313] = hop_t
	a[314] = hop_load
	a[315] = hop_charge
	a[316] = charge
	a[317] = lift_t
	a[318] = 1.0 if hop_block else 0.0
	a[319] = 1.0 if hop_held else 0.0
	a[320] = prep
	a[321] = land_prep
	a[322] = 1.0 if pop_fired else 0.0
	a[323] = lip_scan
	a[324] = lip_state
	a[325] = lip_last
	a[326] = y_prev
	a[327] = pump_acc
	a[328] = brake_heat
	a[329] = brake_fade
	a[330] = dive
	a[331] = 1.0 if _fade_warn else 0.0
	a[332] = _kick_k
	a[333] = 1.0 if _BOB_PROBE else 0.0
	a[334] = _bob_n
	a[335] = _bob_s
	a[336] = _bob_q
	a[337] = 1.0 if _OLD_SHORTAIM else 0.0
	a[338] = 1.0 if _OLD_FADE else 0.0
	a[339] = 1.0 if _OLD_SPEEDTUCK else 0.0
	a[340] = speed_tuck
	a[341] = speed_tuck_auto
	a[342] = _HEAT_HOLD
	a[343] = 1.0 if _OLD_SUSPFX else 0.0
	a[344] = 1.0 if foot_down else 0.0
	a[345] = 1.0 if brake_stop else 0.0
	a[346] = _rev_hold
	a[347] = 1.0 if rev_on_hold else 0.0
	a[348] = 1.0 if brake_back else 0.0
	a[349] = chunk_acc
	a[350] = distance
	a[351] = probe_bottom
	a[352] = probe_acc2
	a[353] = probe_n
	a[354] = probe_vy
	a[355] = probe_g2
	a[356] = dg_xF
	a[357] = dg_xR
	a[358] = dg_vF
	a[359] = dg_vR
	a[360] = dg_fF
	a[361] = dg_fR
	a[362] = dg_tyF
	a[363] = dg_tyR
	a[364] = dg_sqF
	a[365] = dg_sqR
	a[366] = 1.0 if dg_botF else 0.0
	a[367] = 1.0 if dg_botR else 0.0
	a[368] = 1.0 if dg_blowF else 0.0
	a[369] = 1.0 if dg_blowR else 0.0
	a[370] = dg_travel
	a[371] = dg_sag
	a[372] = dg_leg
	a[373] = dg_leg_f
	a[374] = dg_knee
	a[375] = 1.0 if dg_cF else 0.0
	a[376] = 1.0 if dg_cR else 0.0
	a[377] = ground_jolt
	a[378] = 1.0 if skid_fx else 0.0
	a[379] = surf
	a[380] = hop_bar
	a[381] = 1.0 if hop_bar_show else 0.0
	a[382] = 1.0 if crash_on else 0.0
	a[383] = crash_t
	a[384] = crash_side
	a[385] = getup_need
	a[386] = crash_rest
	a[387] = crash_bvy
	a[388] = crash_fall_v
	a[389] = 1.0 if crash_armed else 0.0
	a[390] = crash_hold
	a[391] = 1.0 if _bal_shoved else 0.0
	a[392] = _cb_off_t
	a[393] = 1.0 if _OLD_CRASHBIKE else 0.0
	a[394] = 1.0 if _OLD_RIDERBIKE else 0.0
	a[395] = _g_y
	a[396] = _g_pitch
	a[397] = _g_hr
	a[398] = _g_hf
	a[399] = 1.0 if _EPROBE else 0.0
	a[400] = 1.0 if _OLD_BOUNCE else 0.0
	a[401] = _e_y
	a[402] = _eb_t
	a[403] = 1.0 if _JOLT_PROBE else 0.0
	a[404] = _jp_rim
	a[405] = _jp_t
	a[406] = wr_w
	a[407] = 1.0 if _wr_old else 0.0
	a[408] = wr_knock
	a[409] = _wr_vr
	a[410] = wr_vib2
	a[411] = wr_vibn
	a[412] = chain_slip
	a[413] = chain_slip_k
	a[414] = spin_out_k
	a[415] = _air_pull_v
	a[416] = spin_load
	a[417] = _spin_in
	a[418] = _flip_in
	a[419] = 1.0 if _pop_latch else 0.0
	a[420] = 1.0 if test_rider else 0.0
	a[421] = _land_pitch
	a[422] = _aim_tick
	a[423] = _land_t
	a[424] = land_vn
	a[425] = _vn_td
	a[426] = _reach_td
	a[427] = land_reach
	a[428] = _air_steer_s
	a[429] = aim_off
	a[430] = _air_aim_s
	a[431] = carve_now
	a[432] = whip_load
	a[433] = _whip_in
	a[434] = lip_h
	a[435] = _absorb_k
	a[436] = auto_absorb
	a[437] = _pull_k
	a[438] = _air_pop
	a[439] = 1.0 if pro_pop else 0.0
	a[440] = 1.0 if pro_flight else 0.0
	a[441] = 1.0 if _OLD_LS else 0.0
	a[442] = 1.0 if _OLD_RELAX else 0.0
	return a

func _cs_in(a: PackedFloat64Array) -> void:
	L = a[0]
	RWF = a[1]
	RWR = a[2]
	BB_REAR = a[3]
	SH_R = a[4]
	LAND = a[5]
	geared = a[6] != 0.0
	gear = int(a[7])
	ring_k = a[8]
	bike_rock = a[9]
	x = a[10]
	z = a[11]
	y = a[12]
	vy = a[13]
	snow_k = a[14]
	heading = a[15]
	v = a[16]
	steer = a[17]
	steer_in = a[18]
	steer_in_v = a[19]
	lean = a[20]
	lean_v = a[21]
	bike_lean = a[22]
	counter = a[23]
	rock = a[24]
	pitch = a[25]
	pitch_v = a[26]
	hop_nose = a[27]
	_hop_nose_t = a[28]
	_hop_nose_m = a[29]
	wheelie_up = a[30]
	air = a[31] != 0.0
	air_time = a[32]
	air_k = a[33]
	cap_bank = a[34]
	lean_lim = a[35]
	compress = a[36]
	compress_v = a[37]
	load = a[38]
	body_y = a[39]
	body_v = a[40]
	body_x = a[41]
	hip_shift = a[42]
	body_xv = a[43]
	hip_v = a[44]
	v_last = a[45]
	air_lean = a[46]
	air_pull = a[47]
	air_lock_h = a[48] != 0.0
	air_lock_a = a[49] != 0.0
	_lock_a0 = a[50]
	_air_own = a[51]
	air_help = a[52]
	flip_in = a[53]
	flip_acc = a[54]
	spin_acc = a[55]
	pump_lift = a[56]
	body_pw = a[57]
	throw_v = a[58]
	lock_tw = a[59] != 0.0
	lock_ts = a[60] != 0.0
	air_w = a[61]
	air_inertia = a[62]
	air_tilt = a[63]
	air_tilt_v = a[64]
	air_yaw = a[65]
	air_tw = a[66]
	air_tw_v = a[67]
	land_jolt = a[68]
	pivot = a[69]
	pivot_acc = a[70]
	aero_k = a[71]
	body_in = a[72]
	body_in_s = a[73]
	flick_in = a[74]
	flick = a[75]
	wheelie_time = a[76]
	wheelie_pedal = a[77] != 0.0
	lock_sb = a[78] != 0.0
	lock_sf = a[79] != 0.0
	flick_kick = a[80]
	_man_armed = a[81] != 0.0
	_pull_age = a[82]
	left_back = a[83]
	_loop_saved = a[84]
	_man_pw = a[85]
	_man_over = a[86]
	man_a = a[87]
	man_w = a[88]
	man_zone = a[89] != 0.0
	man_lock = a[90]
	man_zone_t = a[91]
	pump_push = a[92]
	pump_gain = a[93]
	pump_idle = a[94]
	pump_press_t = a[95]
	_pump_release = a[96]
	land_perfect = a[97]
	man_pull = a[98]
	_bend_in = a[99]
	_ab_k = a[100]
	_ab_bend = a[101]
	dg_abs = a[102]
	pleg = a[103]
	pump_on = a[104] != 0.0
	_sprint_lift = a[105]
	n_rear = a[106]
	n_front = a[107]
	skid = a[108] != 0.0
	_man_grace = a[109]
	nose_a = a[110]
	nose_w = a[111]
	nose_zone = a[112] != 0.0
	nose_lock = a[113]
	nose_push = a[114]
	nose_time = a[115]
	nose_brake_t = a[116]
	_nose_grace = a[117]
	_tw_t = a[118]
	_ts_t = a[119]
	_sb_t = a[120]
	_sf_t = a[121]
	_hop_tap_t = a[122]
	_hop_buf = a[123]
	_pop_miss = a[124]
	_pop_miss_t = a[125]
	_gl = a[126]
	_gc = a[127]
	_bh_back = a[128]
	_bh_since = a[129]
	_bh_peak = a[130]
	gest_hop = a[131]
	crouch = a[132]
	crouch_t = a[133]
	rebound = a[134]
	_stick_hold = a[135]
	_cr_rel = a[136]
	_n_grd = a[137]
	pop_wait = a[138]
	_pop_arm_t = a[139]
	squash = a[140]
	_lip_ago = a[141]
	_sus_synced = a[142] != 0.0
	dg_sag_r = a[143]
	_sag_seen = a[144]
	_fb_r = a[145]
	_land_hit = a[146]
	_bog = a[147]
	_bog_rate = a[148]
	_land_pe = a[149]
	_land_up = a[150] != 0.0
	nose_k = a[151]
	_OLD_AIRBLEND = a[152] != 0.0
	_air_wl = a[153]
	_bank_hold = a[154]
	_OLD_CURB = a[155] != 0.0
	_OLD_RIMKICK = a[156] != 0.0
	_rear_up_k = a[157]
	_ty_f = a[158]
	_ty_r = a[159]
	_rim_hit = a[160]
	land_heavy = a[161]
	land_fold = a[162]
	_stun = a[163]
	land_yaw = a[164]
	_tuck_in = a[165] != 0.0
	_graze = a[166] != 0.0
	air_peak = a[167]
	pop_fx = a[168]
	squash_fx = a[169]
	pop_q = a[170]
	pop_time = a[171]
	_pop_used = a[172]
	whip = a[173]
	whip_hold = a[174]
	whip_side = a[175]
	_whip_t = a[176]
	_whip_flashed = a[177] != 0.0
	_whip_arm = a[178]
	_whip_straight = a[179] != 0.0
	_whip_ang = a[180]
	flick_v = a[181]
	_flick_arm = a[182]
	_flick_side = a[183]
	air_stick.x = a[184]
	air_stick.y = a[185]
	edge_s = a[186]
	spin_hold = a[187]
	spin_k = a[188]
	yaw_edge_s = a[189]
	yaw_hold = a[190]
	stick_yaw = a[191]
	style_air = a[192]
	pad = a[193] != 0.0
	bank_probe = a[194] != 0.0
	lean_room = a[195]
	_bank_raw = a[196]
	wheel_f = a[197]
	wheel_r = a[198]
	crank = a[199]
	pedal = a[200]
	throttle_in = a[201]
	yaw_rate = a[202]
	shake = a[203]
	course = a[204]
	slip = a[205]
	since_land = a[206]
	turn_off = a[207]
	rev_cap = a[208]
	_rev_land = a[209] != 0.0
	_land_fix = a[210] != 0.0
	_fakie_hold = a[211]
	slip_w = a[212]
	grip_r = a[213]
	loose = a[214]
	bar_catch = a[215]
	_grip_cv = a[216]
	_squirm = a[217]
	_grip_rough = a[218]
	front_use = a[219]
	front_push = a[220]
	brake_f = a[221]
	brake_r = a[222]
	rear_lock = a[223]
	front_lock = a[224]
	_fb_f = a[225]
	corner_g = a[226]
	weight_in = a[227]
	lean_err = a[228]
	knock = a[229]
	_amax = a[230]
	_amin = a[231]
	bal_k = a[232]
	_b_prev = a[233]
	_f_prev = a[234]
	_circ_f = a[235]
	_brake_feel = a[236] != 0.0
	_a_rear = a[237]
	berm_k = a[238]
	bank_lean = a[239]
	bank_sq = a[240]
	bank_v = a[241]
	_load_s = a[242]
	_share_f = a[243]
	_OLD_DIRT = a[244] != 0.0
	_brk_r = a[245]
	_brk_f = a[246]
	_feel_r = a[247]
	_feel_f = a[248]
	brk_loose_f = a[249]
	brk_loose_r = a[250]
	surf_f = int(a[251])
	surf_r = int(a[252])
	_mu_f = a[253]
	_mu_r = a[254]
	_bmu_f = a[255]
	_bmu_r = a[256]
	_OLD_BRAKE = a[257] != 0.0
	_gx_lean = a[258]
	_lock_hold = a[259]
	weave_lean = a[260]
	_weave = a[261]
	_wv_t = a[262]
	man_lk = a[263]
	_man_lean_s = a[264]
	_bike_lead = a[265]
	_lean_peak = a[266]
	_scrub_k = a[267]
	_whip_peak = a[268]
	risk = a[269]
	_risk_peak = a[270]
	_crash_log = a[271] != 0.0
	front_air = a[272] != 0.0
	rear_air = a[273] != 0.0
	c_f = a[274] != 0.0
	c_r = a[275] != 0.0
	pitch_w = a[276]
	stamina = a[277]
	tired = a[278] != 0.0
	sprint = a[279]
	spin = a[280]
	a_drive = a[281]
	a_pedal = a[282]
	_nR_s = a[283]
	_OLD_GRIP = a[284] != 0.0
	n_f = a[285]
	n_r = a[286]
	n_ref = a[287]
	flow = a[288]
	flow_t = a[289]
	spun_out = a[290] != 0.0
	bank = a[291]
	carve = a[292]
	carve_acc = a[293]
	carve_berm = a[294] != 0.0
	lat_m = a[295]
	lat_a = a[296]
	n_load = a[297]
	g_pitch = a[298]
	w_init = a[299] != 0.0
	hf_prev = a[300]
	hr_prev = a[301]
	zw_f = a[302]
	zw_r = a[303]
	vw_f = a[304]
	vw_r = a[305]
	nose_ref = a[306]
	_gpc_last = a[307]
	w_f = a[308]
	w_r = a[309]
	y_draw = a[310]
	pitch_draw = a[311]
	kick_t = a[312]
	hop_t = a[313]
	hop_load = a[314]
	hop_charge = a[315]
	charge = a[316]
	lift_t = a[317]
	hop_block = a[318] != 0.0
	hop_held = a[319] != 0.0
	prep = a[320]
	land_prep = a[321]
	pop_fired = a[322] != 0.0
	lip_scan = int(a[323])
	lip_state = int(a[324])
	lip_last = a[325]
	y_prev = a[326]
	pump_acc = a[327]
	brake_heat = a[328]
	brake_fade = a[329]
	dive = a[330]
	_fade_warn = a[331] != 0.0
	_kick_k = a[332]
	_BOB_PROBE = a[333] != 0.0
	_bob_n = int(a[334])
	_bob_s = a[335]
	_bob_q = a[336]
	_OLD_SHORTAIM = a[337] != 0.0
	_OLD_FADE = a[338] != 0.0
	_OLD_SPEEDTUCK = a[339] != 0.0
	speed_tuck = a[340]
	speed_tuck_auto = a[341]
	_HEAT_HOLD = a[342]
	_OLD_SUSPFX = a[343] != 0.0
	foot_down = a[344] != 0.0
	brake_stop = a[345] != 0.0
	_rev_hold = a[346]
	rev_on_hold = a[347] != 0.0
	brake_back = a[348] != 0.0
	chunk_acc = a[349]
	distance = a[350]
	probe_bottom = int(a[351])
	probe_acc2 = a[352]
	probe_n = int(a[353])
	probe_vy = a[354]
	probe_g2 = a[355]
	dg_xF = a[356]
	dg_xR = a[357]
	dg_vF = a[358]
	dg_vR = a[359]
	dg_fF = a[360]
	dg_fR = a[361]
	dg_tyF = a[362]
	dg_tyR = a[363]
	dg_sqF = a[364]
	dg_sqR = a[365]
	dg_botF = a[366] != 0.0
	dg_botR = a[367] != 0.0
	dg_blowF = a[368] != 0.0
	dg_blowR = a[369] != 0.0
	dg_travel = a[370]
	dg_sag = a[371]
	dg_leg = a[372]
	dg_leg_f = a[373]
	dg_knee = a[374]
	dg_cF = a[375] != 0.0
	dg_cR = a[376] != 0.0
	ground_jolt = a[377]
	skid_fx = a[378] != 0.0
	surf = int(a[379])
	hop_bar = a[380]
	hop_bar_show = a[381] != 0.0
	crash_on = a[382] != 0.0
	crash_t = a[383]
	crash_side = a[384]
	getup_need = a[385]
	crash_rest = a[386]
	crash_bvy = a[387]
	crash_fall_v = a[388]
	crash_armed = a[389] != 0.0
	crash_hold = a[390]
	_bal_shoved = a[391] != 0.0
	_cb_off_t = a[392]
	_OLD_CRASHBIKE = a[393] != 0.0
	_OLD_RIDERBIKE = a[394] != 0.0
	_g_y = a[395]
	_g_pitch = a[396]
	_g_hr = a[397]
	_g_hf = a[398]
	_EPROBE = a[399] != 0.0
	_OLD_BOUNCE = a[400] != 0.0
	_e_y = a[401]
	_eb_t = a[402]
	_JOLT_PROBE = a[403] != 0.0
	_jp_rim = int(a[404])
	_jp_t = a[405]
	wr_w = a[406]
	_wr_old = a[407] != 0.0
	wr_knock = a[408]
	_wr_vr = a[409]
	wr_vib2 = a[410]
	wr_vibn = int(a[411])
	chain_slip = a[412]
	chain_slip_k = a[413]
	spin_out_k = a[414]
	_air_pull_v = a[415]
	spin_load = a[416]
	_spin_in = a[417]
	_flip_in = a[418]
	_pop_latch = a[419] != 0.0
	test_rider = a[420] != 0.0
	_land_pitch = a[421]
	_aim_tick = int(a[422])
	_land_t = a[423]
	land_vn = a[424]
	_vn_td = a[425]
	_reach_td = a[426]
	land_reach = a[427]
	_air_steer_s = a[428]
	aim_off = a[429]
	_air_aim_s = a[430]
	carve_now = a[431]
	whip_load = a[432]
	_whip_in = a[433]
	lip_h = a[434]
	_absorb_k = a[435]
	auto_absorb = a[436]
	_pull_k = a[437]
	_air_pop = a[438]
	pro_pop = a[439] != 0.0
	pro_flight = a[440] != 0.0
	_OLD_LS = a[441] != 0.0
	_OLD_RELAX = a[442] != 0.0
# --- end of generated members ---
