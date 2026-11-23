class_name BikePhysics
extends RefCounted
## The ride: a faithful port of physics() / crashPhysics() from src/main.js.
## Runs at a fixed 1/120 s step (called from Game._physics_process). Everything is in metres / seconds,
## Y up; the bike travels along fwd = (cos heading, 0, -sin heading).
##
## The host (Game) supplies the world and the side effects:
##   host.terrain  : height(), surface(), jump(), colliders_near()
##   host.flash(text), host.burst(pos, n, surf, power), host.flow_up(), host.msg_idle() -> bool,
##   host.smash(c, vel, pos) -> bool (fence / cactus / tape), host.rock_chips(c), host.start_crash(reason),
##   host.dust(...) via emit_fx(), host.susp (Suspension or null), host.pedal_a0 [left, right]

const G := 9.81
const CLIMB := 1.2
const HOP_PUSH := 0.09
const PUMP_STROKE := 0.3      # m, the legs' pumping stroke from bent (-1) to pushed straight (+1)
const PUMP_SPAN := 0.6       # m either side of the bottom bracket the ground's curve is read over (the wheels average a bump)
const PUMP_STROKE_T := 0.16   # s, the quickest a rider makes that whole stroke (~0.4 s a roller at its best: Luginbuhl 2023)
const FLOW_MAX := 5.0
const GETUP_HOLD := 0.25   # seconds holding hop to get up after a crash
const SLOPE_TRANSFER := 0.7   # centre-of-mass height / wheelbase: how much load a slope moves between the tyres

var host
var T: Dictionary          # Tune.v (effective values)
var L := 0.8985
var RWF := 0.261
var RWR := 0.261
var BB_REAR := 0.3331
var SH_R := 0.63
# wheel model: tyre ~1.2 cm squash under half the weight, light wheels, damper knee at 0.6 m/s
# (the numbers are tuning sliders: Ride > Wheels & pump)
var LAND := 1.0
var geared := false
var gear := -1
var cogs: Array = [11, 12, 14, 16, 18, 21, 24]
var ring_k := 1.0   # chainring vs. the stock 34T
var bike_rock := 1.0

# ---- state (st in the JS) ----
var x := 0.0; var z := 0.0; var y := 0.0; var vy := 0.0
var heading := 0.0; var v := 0.0; var steer := 0.0; var steer_in := 0.0; var steer_in_v := 0.0
var lean := 0.0; var lean_v := 0.0; var bike_lean := 0.0; var counter := 0.0; var rock := 0.0
var pitch := 0.0; var pitch_v := 0.0; var hop_nose := 0.0
var wheelie_up := 0.0   # sprint wheelie: how far up (rad) the rider is holding the front
var air := false; var air_time := 0.0; var air_k := 0.0; var cap_bank := 0.0; var lean_lim := 9.0
var compress := 0.0; var compress_v := 0.0; var load := 0.0
var body_y := NAN; var body_v := 0.0; var body_x := 0.0; var hip_shift := 0.0
# the rider's body as its own mass fore / aft: it lags the bike (braking and landings throw it forward,
# drive pushes it back), and in the air the rider leans (W / S) and pulls the bike up (Space)
var body_xv := 0.0; var hip_v := 0.0; var v_last := NAN
var air_lean := 0.0; var air_pull := 0.0; var air_lock_h := false
# air tricks: the rider's input this step, and how far the bike has turned since take-off (rad)
var air_lock_a := false; var _lock_a0 := 0.0
# the player's hands on the air controls (1 = just used, fades ~0.4 s after letting go) and the landing help left
# over for the rider (airAssist x hands off): the player's stick always wins
var _air_own := 0.0; var air_help := 0.0
var flip_in := 0.0; var flip_acc := 0.0; var spin_acc := 0.0
# rotation as real momentum. On the ground the rider's body turns with the bike, smoothed by the arms and
# legs (body_pw), and W / S pressed at a lip throw the body back / forward against the ground (throw_v).
# In the air nothing outside can turn rider + bike: their shared spin (air_w, rad/s at full stretch) is
# conserved; tucking (Space) lowers the inertia so it spins faster. The rider can only tilt the bike
# against their own body (air_tilt, limited) and twist it at the hips (air_tw).
var pump_lift := 0.0   # a lip pump's leg drive still to come at take-off (m/s)
var body_pw := 0.0; var throw_v := 0.0; var lock_tw := false; var lock_ts := false
var air_w := 0.0; var air_inertia := 1.0; var air_tilt := 0.0; var air_tilt_v := 0.0
var air_yaw := 0.0; var air_tw := 0.0; var air_tw_v := 0.0; var land_jolt := 0.0
# pivot: how far a slow-speed pivot (pirouette) has turned the bike
var pivot := 0.0; var pivot_acc := 0.0
# rider body stick (gamepad right stick, any time): body_in = fore / aft (+ = forward over the bars),
# flick_in = side lean (+ = left, like steer). flick = the smoothed side lean (the bike is thrown under
# the body)
var aero_k := 1.0   # air drag scale from the body position (tuck < 1, sat up > 1)
var body_in := 0.0; var body_in_s := 0.0; var flick_in := 0.0; var flick := 0.0
var wheelie_time := 0.0; var wheelie_pedal := false   # how long the current stick wheelie / manual has been held
var lock_sb := false; var lock_sf := false; var flick_kick := 0.0
# balance manual (the only manual / wheelie): man_a = how far the front is up (rad above the ground), man_w its rate. It is
# a tipping balance: below manBalance the front falls back down, past it the bike tips over backwards faster and
# faster (loops out past manLoop). The bar pull / pedal strokes lift it, the rear brake / leaning forward drop it.
# man_zone = in the sweet spot round the balance point (a little speed push, the HUD meter glows)
# the manual starts from a quick pull (centre -> back within manPullTime), not from how far the stick is: a slow lean
# back, however far, is just weight on the rear tyre (cornering). _pull_age = s since the stick left the centre going back
var _man_armed := false; var _pull_age := 0.0; var left_back := 0.0
var _man_pw := 0.0   # power wheelie: weight back + pedalling lifts the front (0..1, eased)
var _man_over := 0.0   # s the front has been held past the loop-out angle (direct manual: then he falls off the back)
var man_a := 0.0; var man_w := 0.0; var man_zone := false; var man_lock := 0.0; var man_zone_t := 0.0
# the pump (the legs' stroke against the ground's push, see _step_drive): pump_push = its push along the way now (m/s², + = gaining),
# pump_gain = km/h won in the current rhythm (shown on the HUD's pump bar, fades out when the rhythm stops),
# pump_press_t = time this hop press spent pumping (the ground pressing or going light: then letting go doesn't hop)
var pump_push := 0.0; var pump_gain := 0.0; var pump_idle := 0.0; var pump_press_t := 0.0; var _pump_release := 0.0
var land_perfect := 0.0   # 1 on a perfect landing, fades (HUD flash)
var man_pull := 0.0       # the body stick pulled back for a manual (0..1): the HUD balance bar shows at once
var _bend_in := 0.0       # what the rider asks of the legs' bend this step (hop held / stick back), before the crouch follows
var _ab_k := 0.0; var _ab_bend := 0.0; var dg_abs := 0.0   # auto-absorb on (eased) / the legs' rest it set (m, + = straighter), see _step_vertical
var pleg := 0.0           # the legs' pump stroke: -1 bent (hop held / stick back) .. +1 pushed straight (stick forward)
var pump_on := false      # hop held on the ground, rolling: the HUD pump bar is up
var _sprint_lift := 0.0   # balance mode: a sprint stamp from slow lifts the front through the balance
# this step's results shared by the stages of _ride_step: the load on each tyre (m/s2 of the bike's weight; _step_loads),
# the rear tyre locked and sliding (_step_drive)
var n_rear := 0.0; var n_front := 0.0; var skid := false
var _man_grace := 0.0     # a little while after a balance manual ends: its loop-out / nose-down isn't judged as a crash
# nose manual / stoppie: the manual's mirror on the front wheel. nose_a = how far the rear is up (rad), nose_w its rate.
# The front brake with the body stick pushed forward tips it up; then it is a tipping balance (stick forward = further
# over, back = down, the front brake tips it on). Past noseBalance + noseLoop the rear is thrown back down (speed lost)
var nose_a := 0.0; var nose_w := 0.0; var nose_zone := false; var nose_lock := 0.0; var nose_push := 0.0
var nose_time := 0.0; var nose_brake_t := 0.0; var _nose_grace := 0.0
# input forgiveness (inputForgive s): how long each throw input has been held, a tapped hop waiting for the landing,
# the part of a lip pump a late press can still have, the ground's hop load / charge kept just past a lip
var _tw_t := 9.0; var _ts_t := 9.0; var _sb_t := 9.0; var _sf_t := 9.0
var _hop_tap_t := 9.0; var _hop_buf := 0.0; var _pop_miss := 0.0; var _pop_miss_t := 0.0; var _gl := 0.0; var _gc := 0.0
# stick hop (right stick back, then snapped forward): time held back, time since, the highest the front got; gest_hop =
# a short while after one fired (the forward snap is not a flip throw)
var _bh_back := 0.0; var _bh_since := 9.0; var _bh_peak := 0.0; var gest_hop := 0.0
# the legs: one push for the hop and for the pop off a lip (see _leg_dv). crouch = how far they are bent ready to push
# (the preload: hop held, or the body stick pulled back), crouch_t = how long ago this crouch began (the rebound's
# timing), rebound = 0..1 how well a pop right now would ride the rebound. pop_wait = a pop started close to a lip, to
# come at its edge (its power). squash = the lip is being absorbed (stick held forward into it). pop_fx / squash_fx =
# 1 as the rider pops / squashes, fading (pose, HUD); pop_q = that pop's power (0..1.25), pop_time = how well the
# player timed it at the lip (0 = not at a lip). _pop_used = the push already spent on this take-off (m/s): the legs
# have one stroke, however it is asked for
const TUCK_SHARE := 0.75   # the rider's share of rider + bike when he pulls the bike up under him in the air
var crouch := 0.0; var crouch_t := 0.0; var rebound := 0.0; var _stick_hold := 0.0; var _cr_rel := 0.0; var _n_grd := 1.0
var pop_wait := 0.0; var _pop_arm_t := 0.0; var squash := 0.0
var _lip_ago := 9.0   # s since a lip was last in sight just ahead
var sus := {}             # the bike's suspension setup (SuspSetup.resolve: fork, shock, tyre pressures); {} = none (the BMX)
var _sus_synced := false
var dg_sag_r := 0.0       # (diagnostics: the rear's sag, on the front's travel scale like dg_xR)
var _su := PackedFloat64Array()   # the two units as floats (_sus_cache): fork [travel, sag, prog, zc, zr, hs, fric, bump], shock the same, psi f / r
var _sag_seen := 1.0
const ANTI_RISE := 0.6     # how much of the rear's rise under its own brake the linkage takes back (and then some)
var _fb_r := 0.0           # the rear brake's deceleration this step (m/s2), like _fb_f
const FRAME_PROG := 0.35   # the ramp-up the reference frame's linkage adds to its shock (BikeBuild.frame_mods scales it per frame)
var _land_hit := 0.0   # the biggest hit of the landing being judged
var _land_pe := 0.0   # the last touch-down's pitch against the ground (rad)
const LIP_SPARE := 0.15   # rad: how much steeper than the lip under the wheels a take-off may leave
const RIM_CLIMB := 4.0   # m/s: the most upward speed a rim strike on a rising edge gives the frame
const TYRE_MAX := 0.045   # m: a tyre squashed this far is on its rim
var _ty_f := 0.0; var _ty_r := 0.0   # each tyre's push last substep (m/s2 of the whole weight)
var _rim_hit := 0.0   # the most speed the frame lost against the ground with nothing left to give, since it was read (m/s)
# landings: land_heavy = how heavy the last one was (0 clean .. 1 just short of a slam), land_fold = how far the rider
# is folded up by it right now (0..1, fades as he gathers himself), _stun = s he can't put power down after a heavy one,
# land_yaw = the sideways speed the tyres had to catch at the last touch-down (m/s)
var land_heavy := 0.0; var land_fold := 0.0; var _stun := 0.0; var land_yaw := 0.0
var _tuck_in := false   # the tuck is held (hop, in the air)
var _graze := false   # the last "landing" was a tyre brushing the lip on the way up
var air_peak := 0.0   # this flight: the highest the bike got over the ground under it (m)
var pop_fx := 0.0; var squash_fx := 0.0; var pop_q := 0.0; var pop_time := 0.0; var _pop_used := 0.0
var whip := 0.0; var whip_hold := 0.0; var whip_side := 0.0; var _whip_t := 0.0; var _whip_flashed := false; var _whip_arm := 0.0   # corner whip / drift (both sticks one way)
var flick_v := 0.0; var _flick_arm := 0.0; var _flick_side := 0.0   # flick spring speed, deliberate-flick detector
const FLICK_VMAX := 6.0      # the bike can be thrown over at most this fast (stick units / s)
const FLICK_WINDOW := 0.18   # centre -> edge within this long = a deliberate flick
var air_stick := Vector2.ZERO   # right stick in the air, eased: x lean (+ left), y nose (+ up)
var edge_s := 0.0   # right stick held at its top / bottom edge in the air: the flip spin, built up gently
var spin_hold := 0.0; var spin_k := 1.0
# flat spins: the right stick held at its left / right edge in the air spins the bike round (180 / 360),
# built up gently and faster the longer it's held, eased out when let go (stick_yaw rad/s on top of air_yaw)
var yaw_edge_s := 0.0; var yaw_hold := 0.0; var stick_yaw := 0.0
var style_air := 0.0   # this jump's tweak: seconds x how far the stick swung the bike about (style points)   # how long it's been held one way, and the spin-rate multiplier that gives
var pad := false
var bank_probe := Env.s("BMX_BANK_PROBE") != ""
var lean_room := NAN   # how steeply the ground rises beside the bike on its lean side (rad, eased)
var _lean_hist := []; var _bank_raw := 0.0   # the player is on a gamepad (Settings.pad_active): triggers don't tilt / throw in the air
var wheel_f := 0.0; var wheel_r := 0.0; var crank := 0.0; var pedal := 0.0; var throttle_in := 0.0   # the raw gas key / trigger this step (pedal is its smoothed version)
var yaw_rate := 0.0; var shake := 0.0
var course := NAN; var slip := 0.0; var since_land := 1.0
# riding backwards (fakie): landing turned ~180 deg from the travel doesn't crash, the bike just rolls on facing
# backwards (v < 0, course = heading). Both sticks pushed towards the pad's centre (left stick right + right
# stick left) swing it round to face forward (turn_off = the visual swing still to come, rad).
var turn_off := 0.0; var rev_cap := 3.0; var _rev_land := false; var _land_fix := false; var _fakie_hold := 0.0
const LAND_CONE := 1.05   # heading within ~60 deg of the travel at touch-down = a normal landing; past it the tyres grab the nearer axis
# tyre grip sim (_grip_step): slip_w = how fast the bike is yawing against its travel (the rear stepping out /
# coming back), grip_r = the rear tyre's sideways grip left (0 locked / spinning .. 1 full), loose = how loose
# the patch of ground under the rear is (0..1), bar_catch = the rider's drawn countersteer into a slide
var slip_w := 0.0; var grip_r := 1.0; var loose := 0.0; var bar_catch := 0.0
var _grip_noise: FastNoiseLite = null; var _grip_rng := RandomNumberGenerator.new(); var _grip_cv := 0.0
var _squirm := 0.0; var _grip_rough := 0.0
# ground sim (2026-11-20): front tyre (front_use = friction it's using, 1 = at its limit; front_push = how far past
# it, pushing wide), the two brake levers (brake_f / brake_r 0..1) and how locked each wheel is, the turn's load
# pressed down through bike + legs (corner_g, m/s² on top of g), the rider's weight in the turn (weight_in:
# + over the outside pedal / bike pushed under, - hanging inside), the lean the grip can't hold (lean_err)
var front_use := 0.0; var front_push := 0.0
var brake_f := 0.0; var brake_r := 0.0; var rear_lock := 0.0; var front_lock := 0.0; var _fb_f := 0.0
var corner_g := 0.0; var weight_in := 0.0; var lean_err := 0.0; var knock := 0.0
var _amax := 99.0; var _amin := -99.0; var bal_k := 0.0; var _b_prev := 0.0; var _f_prev := 0.0; var _circ_f := 1.0; var _brake_feel := true; var _a_rear := 0.0
var berm_k := 0.0   # how much a berm is carrying the turn right now (0..bermAssist)
var bank_lean := 0.0   # the drawn lean into tilted ground (bankLean x bank), bike + body
var bank_sq := 0.0     # how far the body goes into line with the bike on banked ground (0 flat .. bankBody), drawn only
var bank_v := 0.0      # how fast the bank reading is changing (its smoothing spring)
var _load_s := NAN     # the tyres' load factor for grip, eased (relaxation)
var _share_f := NAN    # the front tyre's share of the load, eased the same way
const SURF_MU := [0.72, 0.95, 0.45, 0.5]   # tyre grip by surface: ground, trail, water, sand / dry
var surf_f := 0; var surf_r := 0; var _mu_f := NAN; var _mu_r := NAN   # the ground under each tyre, its eased grip
var _gx_lean := 0.0    # the rest of the ground's drawn lean (body stick, slow steer, whip), eased through jumps
var _bike_lead := 0.0  # how far the bike runs ahead of the rider's lean while it changes (two masses)
var _whip_peak := 0.0  # this jump's biggest air whip (bike twisted against the body, rad)
# ---- crash judge: losing control is a build-up, not a trip-wire. Each soft failure (a slide past its angle, a front
# pushing past its grip, a lean past what the tyres hold, the rear lifting under the front brake) reports how far past
# its line it is (sev: 0 at the line, 1 = clearly past); that fills its trouble meter while it lasts, the rider fights
# it off when back under (riderSave /s), and only a full meter is a crash. Way past (sev >= CRASH_HARD) = down at once.
# Rolling at walking pace nothing soft crashes (the rider dabs a foot). Impacts (walls, bonks, slams, landings on the
# head) stay instant: they're hits, not lost control
var _risk := {}        # reason -> trouble meter (0..1)
var risk := 0.0        # the biggest meter now: the rider's reflexes scale with it (and the HUD may show it)
var _risk_peak := 0.0  # the highest it got since it was last clear: a full recovery from > 0.5 = SAVED!
const CRASH_HARD := 3.0
var _crash_log := Env.s("BMX_CRASH_LOG") != ""
var front_air := false; var rear_air := false; var c_f := true; var c_r := true
var pitch_w := NAN; var stamina := 1.0; var tired := false; var sprint := 0.0
var spin := 0.0; var a_drive := 0.0
var n_f := NAN; var n_r := NAN; var n_ref := NAN
var flow := 0.0; var flow_t := 0.0
var spun_out := false
var bank := NAN; var carve := 0.0; var carve_acc := 0.0; var carve_berm := false
var lat_m := NAN; var lat_a := 0.0; var n_load := G   # (n_load: the ground's push on the tyres, m/s², for the ride log)
var g_pitch := NAN
var w_init := false; var hf_prev := NAN; var hr_prev := NAN
# unsprung wheels: height of each wheel's lowest point + its speed. The ground drives the wheel through a stiff
# tyre; the shock (spring + damper that blows off on sharp hits) is the only thing between wheel and frame
var zw_f := NAN; var zw_r := NAN; var vw_f := 0.0; var vw_r := 0.0
var nose_ref := NAN; var _gpc_last := NAN   # (_gpc_last: the wheel-ground slope the last step both tyres were down)
var w_f := 0.0; var w_r := 0.0; var y_draw := 0.0; var pitch_draw := 0.0
var kick_t := 0.0; var hop_t := 0.0; var hop_load := 0.0; var hop_charge := 0.0; var charge := 0.0
var lift_t := 0.0; var hop_block := false; var hop_held := false
var prep := 0.0; var land_prep := 0.0; var pop_fired := false
var lip_scan := 0; var lip_state := 0; var lip_last := 0.0   # lip_state: 0 unknown, 1 none in sight, 2 lip_last valid
var y_prev := NAN; var pump_acc := 0.0; var brake_heat := 0.0
var foot_down := false    # set by Game: the rider's foot is on the ground (the bike stays put)
var brake_stop := false  # braked to a standstill: held in place while the brake stays on
var brake_back := false   # brake pressed fresh from a standstill: backs the bike up
var chunk_acc := 0.0
var joint_rock = null
var distance := 0.0
# tests (BMX_CLIP_PROBE): suspension bottom-outs (steps) and how rough the ride is on the ground
var probe_bottom := 0; var probe_acc2 := 0.0; var probe_n := 0; var probe_vy := NAN
var probe_g2 := 0.0; var probe_gy := [NAN, NAN]
const LEAN_PROBE := [0.3, 0.5]   # m beside each tyre the lean room is read at
var _tapes_seen: Array = []      # tape spans already tested this step (_step_move)
## diagnostics (playground diag panel, F4): the last physics step's suspension, read only by RideDiag.
## x = shock compression from topped out (m), v = shock speed (m/s, + = compressing), f = spring + damper force,
## ty = tyre force, sq = tyre squash (m): forces per unit mass (/ G = share of the whole weight). bot / blow = this step
## the end bottomed out / the damper blew off past its knee. leg = rider's legs (body - bike, m), leg_f its push
var dg_xF := 0.0; var dg_xR := 0.0; var dg_vF := 0.0; var dg_vR := 0.0; var dg_fF := 0.0; var dg_fR := 0.0
var dg_tyF := 0.0; var dg_tyR := 0.0; var dg_sqF := 0.0; var dg_sqR := 0.0; var dg_botF := false; var dg_botR := false
var dg_blowF := false; var dg_blowR := false; var dg_travel := 0.2; var dg_sag := 0.0; var dg_leg := 0.0; var dg_leg_f := 0.0
var dg_knee := 0.6; var dg_cF := false; var dg_cR := false
var ground_jolt := 0.0   # biggest leg bottom-out on the ground (not a landing) since the test last read it
# what the HUD reads
var skid_fx := false; var surf := 0; var hop_bar := 0.0; var hop_bar_show := false

# ---- crash ----
var crash_on := false; var crash_t := 0.0; var crash_pending := ""; var crash_side := 1.0
var getup_need := GETUP_HOLD   # hold time to get up (longer to revive at zero life, set by the HUD)
var crash_rest := 0.0; var crash_bvy := 0.0; var crash_fall_v := 0.0; var crash_armed := false; var crash_hold := 0.0

func _init(h) -> void:
	host = h

func setup(extras: Dictionary, bike_cfg: Dictionary) -> void:
	L = float(extras.get("wheelbase", 0.8985))
	RWF = float(extras.get("wheelRadius", 0.261))
	RWR = float(extras.get("wheelRadiusRear", RWF))
	BB_REAR = float(extras.get("bbToRearAxle", 0.3331))
	SH_R = (L - BB_REAR) / L
	LAND = float(bike_cfg.get("land", 1.0))
	geared = bool(bike_cfg.get("geared", false))
	var mods: Dictionary = bike_cfg.get("mods", {})
	sus = {} if Env.s("BMX_NO_SUS") != "" else mods.get("susp", {}); _sus_synced = false; _su = PackedFloat64Array()   # (BMX_NO_SUS: tests, the old single spring)
	if mods.has("cogs"):
		cogs = mods.cogs; ring_k = mods.ring_k
		LAND *= float(mods.get("land", 1.0))
	else:
		# no garage build (the BMX): one neutral 16T cog, ratio 1 like the web version -- not the DH cassette
		cogs = [16]; ring_k = 1.0
	if cogs.size() <= 1: geared = false
	# start in the cog nearest the old 16T reference
	gear = start_gear(cogs, ring_k) if geared else -1

## the cog a ride starts in: nearest the old 16T reference (the garage rollers use it too)
static func start_gear(p_cogs: Array, p_ring_k: float) -> int:
	var g := -1
	var best := 1e9
	for i in p_cogs.size():
		if absf(p_cogs[i] * 1.0 / p_ring_k - 16.0) < best: best = absf(p_cogs[i] * 1.0 / p_ring_k - 16.0); g = i
	return g

## crank turn rate (rad/s) for a wheel spinning at w rad/s in gear gk; shared with the garage rollers
static func crank_rate(w: float, gk: float, top_speed: float, p_sprint: float) -> float:
	# a sprint from slow spins the legs up hard (~70 rpm at once), not just at the wheel's rate
	return maxf(w / (2.78 * gk * top_speed), 3.5 + float(Tune.v.get("sprintSpin", 4.0)) * p_sprint * slowness(w * 0.37)) * (1 + 0.3 * p_sprint)

## 1 standing still .. 0 by ~40 km/h (smooth): how hard a sprinting rider fights to get up to speed
static func slowness(va: float) -> float:
	return 1.0 - smooth01(absf(va) / float(Tune.v.get("sprintSlowTo", 11.0)))

## side-to-side rock from pedalling out of the saddle: the bike swings ~6 deg each way under a steady
## body (~10 deg sprinting), most when pushing hard from slow, about a third of that spinning at speed
static func pedal_rock(p_crank: float, p_sprint: float, p_pedal: float, va: float, p_bike_rock: float) -> float:
	var rock_fade: float = 1.0 - 0.65 * smoothstep(5.0, 12.0, va)
	# sprinting from slow: the bike is thrown hard side to side under the rider (~15 deg each way)
	var effort: float = p_sprint * slowness(va)
	return sin(p_crank) * 0.105 * (1 + 0.65 * p_sprint + float(Tune.v.get("sprintRock", 0.3)) * effort) * p_pedal * minf(1.0, va / 2 + 0.3) * rock_fade * p_bike_rock

func gear_k() -> float:
	if gear < 0: return ring_k * 16.0 / float(cogs[0]) if cogs.size() > 0 else 1.0
	return ring_k * 16.0 / float(cogs[gear])

func shift(d: int) -> bool:
	if gear < 0:
		return false
	var g := clampi(gear + d, 0, cogs.size() - 1)
	if g == gear:
		return false
	gear = g
	return true

static func smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func ang_diff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

static func _or(a: float, d: float) -> float:
	return d if is_nan(a) else a

func fwd() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))

# =====================================================================
func reset_at(px: float, pz: float, hd: float) -> void:
	x = px; z = pz; heading = hd
	_reset_motion()

func get_up() -> void:
	_reset_motion()
	hop_block = true   # the hop held to get up doesn't hop

## everything a respawn and a get-up share: the bike stands still on the ground at (x, z), facing heading
## (one list, so a new state variable can't be reset by one and forgotten by the other)
func _reset_motion() -> void:
	crash_on = false; crash_pending = ""; crash_hold = 0.0; crash_armed = false
	v = 0; vy = 0; steer = 0; steer_in = 0; steer_in_v = 0; lean = 0; lean_v = 0; pitch = 0; air = false
	bike_lean = 0; counter = 0; rock = 0; yaw_rate = 0; hop_nose = 0; hop_t = 0; air_time = 0; air_k = 0
	load = 0; compress = 0; compress_v = 0; prep = 0; land_prep = 0; pop_fired = false; spun_out = false; shake = 0
	turn_off = 0.0; rev_cap = 3.0; _fakie_hold = 0.0
	course = heading; slip = 0; slip_w = 0.0; bar_catch = 0.0; w_init = false; front_air = false; rear_air = false; pump_acc = 0; since_land = 1
	pitch_v = 0; c_f = true; c_r = true; wheelie_up = 0.0
	g_pitch = NAN
	y = host.terrain.height(x, z); body_y = y; body_v = 0
	# start lined up with the ground: a bike set down level on a steep slope had one wheel in the air and was
	# judged LOOPED OUT / NOSE DIVE on its first step (a spawn or a get-up on anything past ~35 deg)
	_sample(fwd()); pitch = _g_pitch; g_pitch = _g_pitch; _gpc_last = NAN
	n_f = NAN; n_r = NAN; n_ref = NAN; lip_state = 0; hf_prev = NAN; hr_prev = NAN; zw_f = NAN; zw_r = NAN
	bank = 0; body_x = 0; hip_shift = 0; spin = 0; a_drive = 0; charge = 0; hop_charge = 0; lift_t = 0
	body_xv = 0; hip_v = 0; v_last = NAN; air_lean = 0; air_pull = 0; flip_acc = 0; spin_acc = 0; flip_in = 0
	body_pw = 0; throw_v = 0; air_w = 0; air_inertia = 1; air_tilt = 0; air_tilt_v = 0; air_yaw = 0; air_tw = 0; air_tw_v = 0; land_jolt = 0
	pivot = 0; pivot_acc = 0; body_in_s = 0; flick = 0; flick_v = 0; _flick_arm = 0; _flick_side = 0; flick_kick = 0
	nose_a = 0.0; nose_w = 0.0; nose_zone = false; nose_lock = 0.0; nose_push = 0.0; nose_time = 0.0; nose_brake_t = 0.0; _nose_grace = 0.0
	_tw_t = 9.0; _ts_t = 9.0; _sb_t = 9.0; _sf_t = 9.0; _hop_tap_t = 9.0; _hop_buf = 0.0; _pop_miss = 0.0; _pop_miss_t = 0.0; _gl = 0.0; _gc = 0.0
	_bh_back = 0.0; _bh_since = 9.0; _bh_peak = 0.0; gest_hop = 0.0
	crouch = 0.0; crouch_t = 0.0; rebound = 0.0; _stick_hold = 0.0; _cr_rel = 0.0; _n_grd = 1.0; pop_wait = 0.0; _pop_arm_t = 0.0; squash = 0.0
	pop_fx = 0.0; squash_fx = 0.0; pop_q = 0.0; pop_time = 0.0; _pop_used = 0.0
	land_heavy = 0.0; land_fold = 0.0; _land_hit = 0.0; _land_pe = 0.0; _stun = 0.0; land_yaw = 0.0; _rim_hit = 0.0; _ty_f = 0.0; _ty_r = 0.0; _tuck_in = false
	man_a = 0.0; man_w = 0.0; man_zone = false; man_lock = 0.0; man_zone_t = 0.0; man_pull = 0.0; _man_over = 0.0; _man_armed = false; _pull_age = 0.0; _man_pw = 0.0; _man_grace = 0.0; _sprint_lift = 0.0
	pump_push = 0.0; pump_gain = 0.0; pump_idle = 0.0; pump_press_t = 0.0; _pump_release = 0.0; pump_on = false; pleg = 0.0; pump_lift = 0.0; land_perfect = 0.0
	wheelie_time = 0.0; wheelie_pedal = false; whip = 0; whip_hold = 0; whip_side = 0.0; _whip_arm = 0; _whip_t = 0; _whip_flashed = false; _whip_peak = 0.0
	edge_s = 0.0; spin_hold = 0.0; spin_k = 1.0; yaw_edge_s = 0.0; yaw_hold = 0.0; stick_yaw = 0.0; air_stick = Vector2.ZERO; style_air = 0.0
	brake_stop = false; brake_back = false; lean_lim = 9.0; lean_room = NAN
	sprint = 0; flow = 0; flow_t = 0; lat_m = 0; carve = 0; carve_acc = 0; carve_berm = false
	y_draw = y; pitch_draw = pitch; nose_ref = NAN; pitch_w = NAN; y_prev = NAN; kick_t = 0
	w_f = y; w_r = y
	pedal = 0.0; throttle_in = 0.0; _grip_cv = 0.0; _grip_rough = 0.0; hop_held = false   # (hop_block keeps a held hop from firing)
	_reset_ground_sim()

func _reset_ground_sim() -> void:
	front_use = 0.0; front_push = 0.0; rear_lock = 0.0; front_lock = 0.0; _fb_f = 0.0
	corner_g = 0.0; weight_in = 0.0; lean_err = 0.0; knock = 0.0; _amax = 99.0; _amin = -99.0; bal_k = 0.0
	_b_prev = 0.0; _f_prev = 0.0; _circ_f = 1.0; bank_lean = 0.0; bank_sq = 0.0; _gx_lean = 0.0; berm_k = 0.0
	_mu_f = NAN; _mu_r = NAN; bank_v = 0.0; _load_s = NAN; _share_f = NAN; _bike_lead = 0.0
	_risk.clear(); risk = 0.0; _risk_peak = 0.0

func begin_crash() -> void:
	crash_pending = ""
	flow = 0
	crash_on = true; crash_t = 0; crash_rest = 0; crash_armed = false; crash_hold = 0; wheelie_time = 0.0; wheelie_pedal = false
	crash_side = signf(bike_lean) if absf(bike_lean) > 0.05 else (-1.0 if randf() < 0.5 else 1.0)
	crash_fall_v = crash_side * 1.5
	crash_bvy = vy if air else minf(vy, 0.5)
	air = false; pedal = 0; load = 0; shake = 0.45

# =====================================================================
## inp: {throttle 0..1, brake 0..1, steer -1..1 (+ = left), hop bool, sprint bool; optional: brake_front / brake_rear 0..1
## (bare levers), body_fwd / body_lean -1..1 (the right stick), pad bool}
func step(dt: float, inp: Dictionary) -> void:
	if dt <= 0.0: return   # (time frozen: several rates divide by dt)
	if crash_pending != "":
		host.start_crash(crash_pending)
	if crash_on:
		_crash_step(dt, inp)
		return
	_ride_step(dt, inp)

# ---------------------------------------------------------------------
func _crash_step(dt: float, inp: Dictionary) -> void:
	var terrain = host.terrain
	var rag = host.ragdoll
	crash_t += dt
	var f := fwd()
	v *= exp(-dt * 2.2)
	if absf(v) < 0.05: v = 0
	yaw_rate *= exp(-dt * 3); heading += yaw_rate * dt
	x += f.x * v * dt; z += f.z * v * dt
	for c in terrain.colliders_near(x, z):
		if c.has("top") and c.top < y + 0.45: continue
		if c.get("tape", false): continue
		if c.get("fence", false) and absf(v) > 2 and Vector2(x - c.x, z - c.z).length() < c.r + 0.35:
			host.smash(c, Vector3(f.x * v, 0, f.z * v), Vector3(x, y, z)); continue
		var dx: float = x - c.x
		var dz: float = z - c.z
		var d := sqrt(dx * dx + dz * dz)
		var mn: float = (c.r if c.has("top") else c.r - 0.1) + 0.25
		if d < mn and d > 1e-4:
			x = c.x + dx / d * mn; z = c.z + dz / d * mn; v *= -0.2
	var lim := 1.48
	crash_fall_v += sin(bike_lean if bike_lean != 0.0 else crash_side * 0.05) * 14.0 * dt
	bike_lean += crash_fall_v * dt
	if absf(bike_lean) > lim:
		bike_lean = signf(bike_lean) * lim; crash_fall_v *= -0.25
	counter = 0; rock = 0; pedal = 0
	steer += (crash_side * 0.5 - steer) * minf(1.0, dt * 4)
	var ground: float = terrain.height(x, z) + 0.24 * absf(sin(bike_lean))
	crash_bvy -= G * dt; y += crash_bvy * dt
	if y < ground:
		y = ground; crash_bvy = -crash_bvy * 0.25 if crash_bvy < -2 else 0.0
	var hr: float = terrain.height(x - f.x * BB_REAR, z - f.z * BB_REAR)
	var hf: float = terrain.height(x + f.x * (L - BB_REAR), z + f.z * (L - BB_REAR))
	pitch += (atan2(hf - hr, L) - pitch) * minf(1.0, dt * 6)
	hop_nose *= exp(-dt * 4)
	wheel_f += v / RWF * dt; wheel_r += v / RWR * dt
	body_y = y; body_v = 0; y_draw = y; pitch_draw = pitch
	if rag and rag.active:   # (not while the get-up animation draws the body: Game.getup_anim)
		var P: Vector3 = rag.p[Ragdoll.PELVIS]
		var near: Array = terrain.colliders_near(P.x, P.z)
		for c in near:
			if c.get("tape", false): continue
			if not c.get("fence", false) or rag.speed < 2.5 or Vector2(P.x - c.x, P.z - c.z).length() > c.r + 0.3 or P.y > terrain.height(P.x, P.z) + 1.4: continue
			var Q: Vector3 = rag.q[Ragdoll.PELVIS]
			host.smash(c, (P - Q) / dt * 3.0 * Vector3(1, 0, 1), P - Vector3(0, 0.4, 0))
		rag.step(dt, near)
		crash_rest = crash_rest + dt if rag.speed < 0.6 else 0.0
	if host.getup_anim != null: return   # already getting up
	var holding: bool = crash_armed and inp.hop
	if holding: crash_hold += dt
	else:
		crash_armed = false; crash_hold = maxf(0.0, crash_hold - dt * 3)
	if crash_hold >= getup_need:
		host.begin_getup()

# ---------------------------------------------------------------------
var _g_y := 0.0; var _g_pitch := 0.0; var _g_hr := 0.0; var _g_hf := 0.0
func _sample(f: Vector3) -> void:
	var terrain = host.terrain
	var hr: float = terrain.height(x - f.x * BB_REAR, z - f.z * BB_REAR)
	var hf: float = terrain.height(x + f.x * (L - BB_REAR), z + f.z * (L - BB_REAR))
	_g_hr = hr; _g_hf = hf
	_g_y = hr + (hf - hr) * (BB_REAR / L); _g_pitch = atan2(hf - hr, L)

func _wheel_ground(f: Vector3, x0: float, R: float, cp0: float) -> float:
	var terrain = host.terrain
	var best := -INF
	for k in range(-5, 6):   # 11 points across the contact: a small rock can't slip between them
		var s := k / 5.0 * R
		var d := x0 * cp0 + s
		var hh: float = terrain.height(x + f.x * d, z + f.z * d) + sqrt(R * R - s * s) - R
		if hh > best: best = hh
	return best

## One ride step (120 Hz), stage by stage. The stages share only what is passed here; everything else they read
## and write is the bike's own state (the members above). Order matters: each stage works on what the last one left
## tests (BMX_ENERGY_PROBE=1): where the ride's energy goes. Energy per kg E = v^2 / 2 (+ vy^2 / 2 in the air) + g y. The
## drive stage's own terms (pedal, brakes, pump, rolling drag, air drag, the grade's pull, manual boost) and the change
## across every other stage of the step (steer: slides / scrub; move: what it hits + the height it changes; vertical:
## springs / landings; lip: take-offs). The grade's pull and the height change in `move` are the same energy changing
## form: their sum is the path's own error. Printed every 5 s (J/kg) with the time braking / in the air / crashed
var _EPROBE := OS.get_environment("BMX_ENERGY_PROBE") != ""
var _OLD_BOUNCE := OS.get_environment("BMX_OLD_BOUNCE") != ""   # (tests: a one-wheel bounce seeds the flight from the body's spin, as before)
var _eb := {}
var _e_y := 0.0
var _eb_t := 0.0; var _eb_n := {t = 0.0, brake = 0.0, air = 0.0, dist = 0.0, vmax = 0.0, turn_t = 0.0, turn_bank = 0.0}
func _e_now() -> float:
	return 0.5 * v * v + (0.5 * vy * vy if air else 0.0) + G * y
func _e_add(k: String, e: float) -> void:
	_eb[k] = float(_eb.get(k, 0.0)) + e
	_eb["~" + k] = float(_eb.get("~" + k, 0.0)) + e   # (the drive stage's own terms, to take out of its stage total)
func _e_stage(k: String, e0: float) -> float:
	var e1 := _e_now()
	var d := e1 - e0
	# (the height part of every stage after the drive is the grade's energy changing form: kept apart as "height")
	var dh := G * (y - _e_y)
	_e_y = y
	if k != "drive":
		var hk := "height_air" if air else "height"
		_eb[hk] = float(_eb.get(hk, 0.0)) + dh
		d -= dh
		if air: _eb["S_" + k + "_air"] = float(_eb.get("S_" + k + "_air", 0.0)) + d; d = 0.0
	if k == "drive":   # what the drive stage did beyond its own listed terms
		for t in ["pedal", "grade", "brakes", "pump", "rolling", "air", "manual"]:
			d -= float(_eb.get("~" + t, 0.0)); _eb["~" + t] = 0.0
		k = "drive_rest"
	_eb["S_" + k] = float(_eb.get("S_" + k, 0.0)) + d
	return e1
func _e_tick(dt: float, brake: bool) -> void:
	_eb_n.t += dt; _eb_n.dist += absf(v) * dt; _eb_n.vmax = maxf(_eb_n.vmax, absf(v))
	if brake and not air and v > 0.5: _eb_n.brake += dt
	if air: _eb_n.air += dt
	if not air and absf(lat_a) > 3.0 and not is_nan(bank):   # turning hard: how much bank is under the bike
		_eb_n.turn_t += dt; _eb_n.turn_bank += absf(bank) * dt
	_eb_t += dt
	if _eb_t >= 5.0:
		_eb_t = 0.0
		var ks := _eb.keys().filter(func(k): return not String(k).begins_with("~"))
		ks.sort_custom(func(a, b): return float(_eb[a]) < float(_eb[b]))
		var line := "ENERGY t=%.0fs dist=%.0fm avg=%.1fkmh max=%.1fkmh braking=%.0f%% air=%.0f%% turning: bank=%.1fdeg |" % [_eb_n.t, _eb_n.dist, _eb_n.dist / maxf(_eb_n.t, 0.01) * 3.6, _eb_n.vmax * 3.6, 100.0 * _eb_n.brake / _eb_n.t, 100.0 * _eb_n.air / _eb_n.t, rad_to_deg(_eb_n.turn_bank / maxf(_eb_n.turn_t, 1e-3))]
		for k in ks: line += " %s=%.0f" % [k, float(_eb[k])]
		print(line)

func _ride_step(dt: float, inp: Dictionary) -> void:
	var throttle: float = inp.throttle
	# after a heavy / sideways landing the rider needs a moment before he can put power down again, and unfolds
	# (quickly from a light one, slowly from a heavy one)
	if _stun > 0.0:
		_stun = maxf(0.0, _stun - dt); throttle = 0.0
	land_fold = maxf(0.0, land_fold - dt / (0.45 + 0.9 * land_fold + 1.0 * land_heavy))
	var steer_input: float = inp.steer
	var brake_k := _step_controls(dt, inp, throttle, steer_input)
	var brake := brake_k > 0.1
	var roll_keys: float = 0.0 if (not air or air_lock_a) else steer_input   # A / D in the air, before the body stick is added
	var f := fwd()
	_step_ground(dt, f)
	var in_water := surf == 2
	var slope: float = _or(pitch_w, _g_pitch) if (not air and (front_air or rear_air) and wheelie_up <= 0.0 and nose_a <= 0.0) else _g_pitch   # a wheelie rolls on the ground's slope
	# (rolling on the rear wheel alone, the hill it feels is the ground under that wheel, not the way the frame points:
	# nose-high down the back of a bump it "climbed" and stalled)
	if not air and front_air and not rear_air and wheelie_up <= 0.0 and nose_a <= 0.0:
		slope = _local_slope(f, -BB_REAR, RWR, cos(clampf(pitch, -1.3, 1.3)))
	var rear_down := not air and not rear_air
	skid = false
	_step_sprint(dt, inp, throttle, brake, in_water)
	_step_loads(dt)
	var e0 := _e_now() if _EPROBE else 0.0
	_e_y = y
	var a_long := _step_drive(dt, inp, throttle, brake, in_water, slope, rear_down, n_rear, n_front)
	if _EPROBE: e0 = _e_stage("drive", e0)
	var va := _step_steer(dt, f, brake_k, steer_input, roll_keys, a_long, n_rear, n_front)
	if _EPROBE: e0 = _e_stage("steer", e0)
	f = fwd()   # (the steering turned the bike)
	_step_move(dt, f)
	if _EPROBE: e0 = _e_stage("move", e0)
	_step_vertical(dt, f, throttle, brake)
	if _EPROBE: e0 = _e_stage("vertical", e0)
	_step_hop(dt, inp)
	if _EPROBE: e0 = _e_stage("hop", e0)
	_step_lip(dt, f, brake)
	if _EPROBE: e0 = _e_stage("lip", e0)
	_step_wheels(dt, f, in_water, va)
	if _EPROBE: e0 = _e_stage("wheels", e0); _e_tick(dt, brake)

## stage 1: the controls. Brake levers, the body stick, air control (tilt / spin / tuck inputs) and the lip throw.
## Returns the brake level (0 when S was a flip throw at a lip, not a brake)
func _step_controls(dt: float, inp: Dictionary, throttle: float, steer_input: float) -> float:
	# two levers: "brake" (S / LT) squeezes both (the front by brakeFrontMix), brake_front / brake_rear one each
	brake_r = maxf(float(inp.brake), float(inp.get("brake_rear", 0.0)))
	brake_f = maxf(float(inp.brake) * float(T.get("brakeFrontMix", 0.7)), float(inp.get("brake_front", 0.0)))
	# the brake key is a rider squeezing both with feel: they keep each wheel at the edge of locking (the rear a
	# touch past it, a light skid). The front-only / rear-only keys are the bare levers: lock what you squeeze
	_brake_feel = float(inp.brake) >= maxf(float(inp.get("brake_front", 0.0)), float(inp.get("brake_rear", 0.0)))
	# the rider's reflexes in trouble (riderSkill x how full the crash meters are): ease off the brakes, the front most
	var rfx := float(T.get("riderSkill", 1.0)) * smooth01((risk - 0.15) / 0.5)
	var rb: float = float(T.get("reflexBrake", 0.6))
	brake_f *= 1.0 - rb * rfx; brake_r *= 1.0 - rb * 0.67 * rfx
	var brake_k: float = maxf(maxf(float(inp.brake), brake_r), float(inp.get("brake_front", 0.0)))
	var brake := brake_k > 0.1
	# rider body stick (gamepad right stick): fore / aft weight, side lean. Works the whole ride
	pad = bool(inp.get("pad", false))
	body_in = clampf(float(inp.get("body_fwd", 0.0)), -1.0, 1.0)
	left_back = float(inp.get("left_back", 0.0))
	flick_in = clampf(float(inp.get("body_lean", 0.0)), -1.0, 1.0)
	body_in_s += (body_in - body_in_s) * minf(1.0, dt * 10)
	# air control: W / S tilt the bike nose down / up against the rider's body (limited, see air_tilt; a
	# flip has to be thrown at the lip), A / D lean it left / right, Space tucks (pulls the bike up into the
	# body, spinning faster). W / S work at once; A / D and Space held at take-off count only once pressed
	# again in the air (carving into a jump mustn't lean you).
	if not air:
		air_lock_h = inp.hop; air_lock_a = absf(steer_input) > 0.1; _lock_a0 = steer_input
		_air_own = 0.0
	else:
		if not inp.hop: air_lock_h = false
		# (a steer held off the lip counts again as soon as it's let go OR clearly moved: no waiting for a re-press)
		if absf(steer_input) <= 0.1 or absf(steer_input - _lock_a0) > 0.35: air_lock_a = false
		var used: float = maxf(Vector2(flick_in, body_in).length(), 0.0 if air_lock_a else absf(steer_input))
		if not pad: used = maxf(used, absf(throttle - brake_k))
		_air_own = 1.0 if used > 0.15 else maxf(0.0, _air_own - 2.5 * dt)
	air_help = float(T.get("airAssist", 0.6)) * (1.0 - _air_own) if air else 0.0
	var lean_in := 0.0
	if air:   # W / S act straight away, even if held from the ground (the user wants no re-press)
		# + the body stick (forward = nose down), with a dead band so a light lean held from the ground doesn't
		# spin the bike. On a gamepad the triggers (held pedalling / braking into a jump) don't tilt it at all
		# the right stick doesn't spin the bike, it points it (see air_stick); only pushed right to the top
		# / bottom edge it keeps the bike turning over (flips in the air)
		# The spin builds up gently while the stick is held at the edge (stickSpinBuild /s) and eases out
		# quicker when it comes off the edge: no sudden kick into a flip
		# the longer it's held one way, the faster it spins (like winding it up): spin_hold seconds held,
		# x (1 + stickSpinGrow per second, up to 1.5 s); turning the other way starts over
		var es := _edge_spin(body_in, edge_s, spin_hold, dt)
		edge_s = es.x; spin_hold = es.y
		spin_k = _edge_grow(spin_hold) if absf(edge_s) > 0.01 else 1.0
		lean_in = clampf((0.0 if pad else throttle - brake_k) + edge_s * float(T.get("stickSpinMax", 0.7)), -1.0, 1.0)
		# the same at the left / right edge: a flat spin
		var ys := _edge_spin(flick_in, yaw_edge_s, yaw_hold, dt)
		yaw_edge_s = ys.x; yaw_hold = ys.y
		var y_t: float = yaw_edge_s * float(T.get("stickYawRate", 5.0)) * _edge_grow(yaw_hold)
		if absf(flick_in) < 0.815 and land_prep > 0.2:
			# coming in to land off a spin: the rider twists it the rest of the way straight if it's close
			var off := wrapf(slip, -PI, PI)
			# (landing help: only with the hands off the stick, airAssist of it)
			if absf(off) < 1.2: y_t = lerpf(y_t, clampf(-off * 6.0, -4.0, 4.0), air_help)
		# the spin answers the stick at once and stops soon after it's let go (it used to take ~0.5 s to get going and
		# ran on ~150 deg after the release)
		var y_resp: float = 11.0 if absf(y_t) > absf(stick_yaw) else 10.0
		stick_yaw += (y_t - stick_yaw) * minf(1.0, y_resp * dt)
	else:
		edge_s = 0.0; spin_hold = 0.0; spin_k = 1.0
		yaw_edge_s = 0.0; yaw_hold = 0.0; stick_yaw = 0.0
	flip_in = -lean_in                                          # + = nose up
	# 360° air control with the right stick: x = lay the bike over left / right, y = nose up / down. It sets
	# the bike's attitude (held where the stick points, back to the landing aim when let go), so circling
	# the stick swings the bike round through every mix of tilt and lean
	var stick_raw := Vector2(flick_in, -body_in) if air else Vector2.ZERO
	if stick_raw.length() < 0.08: stick_raw = Vector2.ZERO
	# eased: the bike follows a smoothed stick (stickAirEase /s), so a quick flick of the thumb swings it
	# over smoothly instead of snapping it
	air_stick += (stick_raw - air_stick) * (1.0 - exp(-dt * float(T.get("stickAirEase", 3.5))))
	if not air: air_stick = Vector2.ZERO
	else: style_air += minf(air_stick.length(), 1.0) * dt
	air_lean += (lean_in - air_lean) * minf(1.0, dt * 6)
	# the rider tucks into a flip as well as when Space is held
	_tuck_in = air and inp.hop and not air_lock_h
	var pull_t := maxf(1.0 if _tuck_in else 0.0, 0.7 * absf(flip_in) if air else 0.0)
	# right after take-off the rider lifts the bike up into the body (it moves about the shared centre of
	# mass, the arc stays the same), then lets it down to reach for the landing (land_prep)
	if air:
		var lift_k: float = smooth01((air_time - 0.03) / 0.1) * (1.0 - smooth01((air_time - 0.3) / 0.3)) * (1.0 - land_prep)
		pull_t = maxf(pull_t, T.airLift * lift_k)
		# a pop: the legs are straight at the edge, then the rider pulls the bike up under him (most of a hop's wheel
		# clearance is this, not the centre of mass); a squash: the bike comes right up into the body, then is pushed
		# back down the far side
		pull_t = maxf(pull_t, minf(1.0, 0.55 + 0.45 * pop_q) * smooth01((air_time - 0.02) / 0.08) * smooth01(pop_fx / 0.35) * (1.0 - land_prep))
		pull_t = maxf(pull_t, squash_fx * (1.0 - land_prep))
	air_pull += (pull_t - air_pull) * minf(1.0, dt * 8)
	# the lip throw: W / S pressed fresh as the bike leaves a lip (a jump spotted just ahead, or one wheel
	# already off) throw the rider back / forward, pushing against the bike and through it the ground. That
	# is the only way to start a flip (keys held from before don't count; S there pulls back, it doesn't brake)
	# (not while a balance manual is held: its raised front opened the window, so on keys a fresh S to drop the
	# manual / W to pedal it was a flip throw and S didn't brake)
	var lip_win := not air and not (_balancing() or _man_grace > 0.0 or _nosing() or _nose_grace > 0.0) and (prep > 0.25 or front_air or rear_air)
	# input forgiveness: a throw pressed a moment before the window opens still counts (it used to be locked out as
	# "held from before", so S a tenth of a second early braked into the lip instead of flipping)
	var t_buf: float = float(T.get("inputForgive", 0.12)) * 1.5
	_tw_t = _tw_t + dt if throttle > 0.1 else 0.0
	_ts_t = _ts_t + dt if brake else 0.0
	_sb_t = _sb_t + dt if body_in < -0.05 else 0.0
	_sf_t = _sf_t + dt if body_in > 0.05 else 0.0
	if pad:   # gamepad: the triggers never throw a flip (the right stick does), so brake stays a brake
		lock_tw = true; lock_ts = true
	elif not lip_win:
		lock_tw = throttle > 0.1 and _tw_t > t_buf; lock_ts = brake and _ts_t > t_buf
	else:
		if throttle <= 0.1: lock_tw = false
		if not brake: lock_ts = false
	var throw_in := 0.0
	if lip_win:
		throw_in = (0.0 if lock_ts else brake_k) - (0.0 if lock_tw else throttle)   # + = back (nose up)
		if not lock_ts:
			brake_k = 0.0; brake = false; brake_f = 0.0; brake_r = 0.0
	# the body stick throws too, but only a real yank: pushed past half way, starting from the centre inside
	# the lip window. Any lean held into the lip (riding in the attack position, a manual) never throws -
	# a light forward lean used to throw a front flip at every lip and nose-dive the landing
	if not lip_win:
		lock_sb = body_in < -0.05 and _sb_t > t_buf; lock_sf = body_in > 0.05 and _sf_t > t_buf
	else:
		if body_in >= -0.15: lock_sb = false
		if body_in <= 0.15: lock_sf = false
	# feathering a balance manual into a lip is not a flip throw (each re-pull looked like a fresh one)
	# (nor is working a nose manual, or the forward snap of a stick hop)
	if _balancing() or _man_grace > 0.0 or _nosing() or _nose_grace > 0.0 or gest_hop > 0.0:
		lock_sb = true; lock_sf = true
	# (these three lines were indented under the if above by mistake: the stick throw only ran while it was locked,
	# so it never threw at all)
	var yb := 0.0 if (lock_sb or not lip_win) else clampf((-body_in - 0.5) / 0.4, 0.0, 1.0)
	var yf := 0.0 if (lock_sf or not lip_win) else clampf((body_in - 0.5) / 0.4, 0.0, 1.0)
	throw_in = clampf(throw_in + yb - yf, -1.0, 1.0)
	if not air:
		if absf(throw_in) > 0.05:
			var room := 1.0 - clampf(throw_v * signf(throw_in) / T.flipRate, 0.0, 1.0)
			throw_v += throw_in * T.flipAccel * room * dt
		else:
			throw_v *= exp(-dt * 6)   # a throw can't be held on the ground: the body settles back
	return brake_k

## stage 2: the ground under the bike: heights at both axles, the surface and grip under each tyre
func _step_ground(dt: float, f: Vector3) -> void:
	var terrain = host.terrain
	_sample(f)
	surf = terrain.surface(x, z)
	# each tyre on its own ground (front on the sand at the trail's edge, rear still on the hardpack), its grip easing
	# across a change over ~0.1 s (a hard step from 0.95 to 0.72 at the trail edge used to kick both tyres at once)
	surf_f = terrain.surface(x + f.x * (L - BB_REAR), z + f.z * (L - BB_REAR))
	surf_r = terrain.surface(x - f.x * BB_REAR, z - f.z * BB_REAR)
	var mk := minf(1.0, dt * 12.0)
	_mu_f = SURF_MU[clampi(surf_f, 0, 3)] if is_nan(_mu_f) else lerpf(_mu_f, SURF_MU[clampi(surf_f, 0, 3)], mk)
	_mu_r = SURF_MU[clampi(surf_r, 0, 3)] if is_nan(_mu_r) else lerpf(_mu_r, SURF_MU[clampi(surf_r, 0, 3)], mk)
	if is_nan(course):
		course = heading; slip = 0
	since_land += dt

## stage 3: sprint and stamina
func _step_sprint(dt: float, inp: Dictionary, throttle: float, brake: bool, in_water: bool) -> void:
	var want_sprint: bool = inp.sprint and throttle > 0.1 and not brake and not air
	if stamina <= 0: tired = true
	elif stamina > 0.25: tired = false
	var sprinting := want_sprint and not tired and not in_water
	if sprinting and not air: stamina = maxf(0.0, stamina - dt / T.sprintTime)
	elif not sprinting: stamina = minf(1.0, stamina + dt / T.sprintRecharge)
	sprint += ((1.0 if sprinting else 0.0) - sprint) * minf(1.0, dt * 5)

## stage 4: how the weight sits on the two tyres (slope, rider fore / aft, braking); sets n_rear / n_front / n_load,
## and judges OVER THE BARS
func _step_loads(dt: float) -> void:
	var n_sc := G / _or(n_ref, G)
	# the tyre springs carry the weight straight down; on a slope only g cos(slope) of it presses the tyres onto
	# the ground (what grip, brakes and drive can use), the rest is the pull down the slope
	var n_cos := cos(clampf(_g_pitch, -1.2, 1.2))
	# the tyre springs also carry the turn's load (corner_g, pressed down through the leaned bike); the tyres' grip
	# on the ground is worked out from the tilt of the ground below (_fric / a_max), so take it out here
	n_cos *= G / (G + maxf(0.0, corner_g))
	var nR := 0.0 if air else _or(n_r, G * SH_R) * n_sc * n_cos
	var nF := 0.0 if air else _or(n_f, G * (1 - SH_R)) * n_sc * n_cos
	var n_tot := nR + nF
	# rider weight fore / aft moves load between the tyres (total unchanged): leaning back puts it on the rear
	# (drive + rear sideways grip up, front light and washy), leaning forward does the opposite (rear lets go)
	var lean_fb := 0.0
	if not air:
		lean_fb = clampf(body_in_s + (body_x + hip_shift) * 0.5 / maxf(0.05, T.weightShift), -1.0, 1.0)
		# pumping with the stick is pushing down, not leaning over the bars: the rear keeps its load (it locked and
		# slid out under braking with the pump stick forward)
		if lean_fb > 0.0 and pump_push > 0.05 and body_in > 0.12: lean_fb *= 1.0 - float(T.get("pumpCentred", 0.75))
		var dN: float = -lean_fb * float(T.get("leanTraction", 0.45)) * G
		# and the slope itself: the centre of mass sits ~0.9 m above the ground, so climbing puts weight on the rear
		# and descending on the front (g sin(slope) x height / wheelbase). The rider's own shift up / down a slope
		# (body_x follows the grade) works against it; without this the auto forward lean on a climb took all
		# the load off the rear: wheelspin, no side grip, and a WASHED OUT crash pedalling straight up 15 deg
		dN += G * sin(clampf(_g_pitch, -1.2, 1.2)) * SLOPE_TRANSFER
		# braking throws the weight onto the front by the same lever (last step's brake decel x CoM height /
		# wheelbase): the front brake can then do most of the stopping and the light rear locks easily. Grab so
		# much front that the rear would carry less than nothing and the rear comes up: held, it's over the bars
		# a rider weights the front in a turn (hands and hips pressing it into the ground): leaned over, frontWeight g
		# of the load moves forward, more while the front is in trouble. Without it the front could ride a long turn
		# carrying next to nothing (a climb + weight back) and wash out (the AI rider did, every run at one bend)
		var fw_k: float = float(T.get("riderSkill", 1.0)) * smooth01((absf(lean) - 0.12) / 0.35)
		dN -= G * float(T.get("frontWeight", 0.12)) * fw_k * (1.0 + 3.5 * float(_risk.get("FRONT WASHED OUT!", 0.0)))
		# (rolling backwards, braking loads the rear, not the front)
		var d_brake := -_b_prev * SLOPE_TRANSFER * (1.0 if v >= 0.0 else -1.0)
		# (how far the rear would go below nothing = how hard it's coming up: the crash judge builds on it)
		var lift := (-nR + 0.03 * G) - (dN + d_brake)
		_danger("OVER THE BARS!", lift / (0.25 * G) if (brake_f > 0.4 and v > 3.0 and not _nosing() and nose_push <= 0.0) else -1.0, dt)   # (a stoppie on purpose is the nose balance's)
		dN += d_brake
		dN = clampf(dN, -nR + 0.08 * G, nF - 0.08 * G)
		nR += dN; nF -= dN
	n_load = n_tot
	spin = 0; a_drive = 0
	n_rear = nR; n_front = nF

## stage 5: along the bike: pedalling, the two brakes (sets skid), pumping, drag, speed. Returns a_long, how much of
## the tyres' grip driving / braking is using (m/s2)
func _step_drive(dt: float, inp: Dictionary, throttle: float, brake: bool, in_water: bool, slope: float, rear_down: bool, nR: float, nF: float) -> float:
	var a_long := 0.0
	var sp_k := sprint
	var n_tot := n_load
	var mu_f: float = _mu_f * T.grip
	var mu_r: float = _mu_r * T.grip
	var mu: float = mu_r * SH_R + mu_f * (1.0 - SH_R)
	# --- longitudinal ---
	if not air:
		var vp := maxf(v, 0.5)
		var gk := gear_k()
		# Top speed (Settings > Controls / tuning card): scales the pedalling top speed, with the power
		# to reach it and less drag holding it back (drag-limited top speed scales with it too)
		var ts: float = T.topSpeed
		var p_top: float = (T.pedalTop + T.sprintTop * sp_k) * gk * ts
		# sprinting, the slower the rider is the harder they stamp on it (out of the saddle, full body):
		# all of the extra push from a standstill, less and less as the speed comes back, none by ~40 km/h
		var kick: float = float(T.get("sprintKick", 0.9)) * slowness(v)
		var p_mul: float = (1 + (T.sprintPower - 1 + kick) * sp_k) * ts
		var cad: float = v / (gk * T.pedalTop * ts * 0.7)
		var grind := 1.0 if gear < 0 else 0.35 + 0.65 * smooth01((cad - 0.15) / 0.7)
		var drive: float = (throttle if (rear_down and not (v < -0.3 and rev_cap > 3.0)) else 0.0) * minf(T.pedalLaunch * p_mul / ts / gk, T.pedalPower * p_mul / vp) * grind * clampf((p_top - v) / 2.5, 0, 1)
		var drive_cap := mu_r * nR
		if drive > drive_cap:
			spin = minf(1.0, (drive - drive_cap) / 3); drive = drive_cap + (drive - drive_cap) * 0.15
		a_long = absf(drive)
		var a := drive - G * sin(slope)
		if _EPROBE: _e_add("pedal", drive * v * dt); _e_add("grade", -G * sin(slope) * v * dt)
		# two brakes, each limited by its own tyre: the front does most of the stopping (braking moves the weight onto
		# it, so it can take more), the rear goes light and locks easily. Squeeze a lever past what its tyre can hold
		# and that wheel locks: it slides at ~80 % of the grip (rear = skid / fishtail, front = no steering, and
		# leaned over it washes out, see the front tyre below)
		var fb_r: float = T.brakeForce * float(T.get("brakeRear", 0.6)) * brake_r
		var fb_f: float = T.brakeForce * float(T.get("brakeFront", 0.75)) * brake_f * (0.0 if front_air else 1.0)
		var cap_r: float = maxf(0.05, mu_r * nR)
		var cap_f: float = maxf(0.05, mu_f * nF * float(T.get("frontGrip", 1.0)))
		if _brake_feel:
			# ...and eases the rear off the moment it starts stepping out sideways, so it grips sideways again
			var r_ease := smooth01((absf(slip) - 0.04) / 0.08)
			fb_r = minf(fb_r, cap_r * lerpf(1.0 + 0.25 * float(T.get("brakeSkid", 0.4)), 0.85, r_ease))
			fb_f = minf(fb_f, cap_f * 0.97)
		rear_lock = move_toward(rear_lock, clampf((fb_r - cap_r) / (0.25 * cap_r), 0.0, 1.0) if fb_r > cap_r else 0.0, dt * 8.0)
		front_lock = move_toward(front_lock, clampf((fb_f - cap_f) / (0.25 * cap_f), 0.0, 1.0) if fb_f > cap_f else 0.0, dt * 8.0)
		fb_r = lerpf(minf(fb_r, cap_r), cap_r * 0.8, rear_lock) if rear_down else 0.0
		fb_f = lerpf(minf(fb_f, cap_f), cap_f * 0.8, front_lock)
		_fb_f = fb_f; _fb_r = fb_r
		_a_rear = maxf(0.0, drive) + (fb_r if (brake and rear_down) else 0.0)   # what the REAR tyre carries along the bike
		var b_all := fb_r + fb_f
		# (gated on any tyre down, not on the rear: with the rear bounced up the front brake did nothing; each brake
		# is already zero while its own wheel is off the ground)
		_b_prev = b_all if (brake and not air and absf(v) > 0.3) else 0.0
		if brake and not air and v > 0.3:
			a -= b_all; a_long += b_all; drive -= b_all
			brake_heat += b_all * v * dt / 45.0
			if _EPROBE: _e_add("brakes", -b_all * v * dt)
		elif brake and not air and v < -0.3 and (rev_cap > 3.0 or not brake_back):
			# braking while rolling backwards (after a fakie landing, or sliding back down a climb the brakes
			# can't hold); a fresh press from a standstill backs up on purpose (brake_back) and doesn't brake
			a += b_all; a_long += b_all; drive += b_all
			brake_heat += b_all * -v * dt / 45.0
		else:
			rear_lock = move_toward(rear_lock, 0.0, dt * 8.0); front_lock = move_toward(front_lock, 0.0, dt * 8.0)
		a_drive = drive
		# --- the pump = the legs' stroke (the same legs that hop and pop off a lip). Pumping is work done against the
		# ground's push: straightening the legs while the ground presses harder than standing weight (the dip at the
		# bottom of a roller, a compression) or bending them while it goes light (over a crest) adds that difference x the
		# stroke to the ride's speed; the other way round costs it (holding stiff over a crest, absorbing a dip). Over a
		# rhythm that is +(load in the dips - load at the crests) x stroke per roller: it grows with speed and with how
		# curved the ground is, and on a straight slope, however steep, there is nothing to gain. Hands off the legs keep
		# their length and nothing changes. Hop held / the stick back = legs bent (the crouch); the stick forward = pushed
		# straight; letting the hop go / the stick forward straightens them. (Luginbuhl et al. 2023, Golembiewski et al. 2023)
		pump_push = 0.0
		var btn: bool = inp.hop and not hop_block
		var p_fwd: float = clampf((body_in - 0.12) / 0.6, 0.0, 1.0)
		var p_back: float = clampf((-body_in - 0.12) / maxf(0.05, 0.4 - 0.12), 0.0, 1.0)
		var p_in: float = maxf(1.0 if btn else 0.0, p_fwd * float(T.get("pumpStick", 1.2)))
		# (one wheel down is enough: over a roller's crest the front goes light and leaves the ground for most of the
		# backside; the manual / hop guards keep a wheel up from pumping)
		var ground_ok: bool = not (front_air and rear_air) and hop_t <= 0.0 and v > float(T.get("pumpMinSpeed", 2.0)) and man_a < 0.08
		pump_on = ground_ok and (btn or p_fwd > 0.0 or p_back > 0.0)
		var terrain_pump = host.terrain
		var pl_prev := pleg
		var pl_t: float = clampf(p_fwd - _bend_in, -1.0, 1.0)
		# (a rider straightens or bends the legs at most a whole stroke in PUMP_STROKE_T)
		pleg = move_toward(pleg, pl_t, dt * 2.0 / PUMP_STROKE_T)
		if ground_ok and prep < 0.1 and pop_wait <= 0.0 and kick_t <= 0.0 and since_land > 0.1:
			# how much harder (or lighter) than standing weight the ground pushes on rider + bike along their path: speed²
			# x the ground's curve under the bike, across about the wheelbase (+ in a dip, - over a crest). Not the tyre
			# loads: over a roller's crest the front leaves the ground and the springs ring, which put the timing out by
			# a quarter of a roller. The legs can drive against at most ~2.5 g
			var cx: float = cos(_or(course, heading)) * PUMP_SPAN
			var cz: float = -sin(_or(course, heading)) * PUMP_SPAN
			var h0: float = terrain_pump.deck_height(x, z)
			var kap: float = (terrain_pump.deck_height(x + cx, z + cz) + terrain_pump.deck_height(x - cx, z - cz) - 2.0 * h0) / (PUMP_SPAN * PUMP_SPAN)
			var n_ex: float = clampf(v * v * kap / G, -1.0, 1.5)
			var de: float = clampf(T.riderMass, 0.0, 0.7) * n_ex * G * 0.5 * PUMP_STROKE * (pleg - pl_prev) * float(T.get("pumpLegs", 1.0))
			pump_push = de / (maxf(2.0, v) * dt)
			a += pump_push
			if _EPROBE: _e_add("pump", de)
			if pump_push > 0.0: pump_acc += pump_push * dt
			if btn and absf(n_ex) > 0.15: pump_press_t += dt   # (a press spent pumping doesn't hop when it's let go)
		if absf(pleg - pl_t) < 0.02:
			if pump_acc > 0.35:
				flow_up()
				if host.msg_idle(): host.flash("PUMP +%d km/h" % roundi(pump_acc * 3.6))
			pump_acc = 0.0
		# pumping a berm (Golembiewski et al. 2023, a pump track: the rider's body working against the bike through a
		# steep banked turn drives it on, no pedalling): the pump held (hop / stick forward) while a berm carries the turn
		# - the legs drive the bike into the turn's extra load (corner_g, m/s² on top of g) - pushes it along. Physically
		# small; bermPump scales it (0.12 x ~4 m/s² of load = ~0.5 m/s² through the turn: ~+2-3 km/h out of a good berm)
		var berm_c: float = clampf(berm_k / maxf(0.05, float(T.get("bermAssist", 1.0))), 0.0, 1.0)
		if ground_ok and prep < 0.1 and p_in > 0.0 and berm_c > 0.05 and corner_g > 0.3:
			var bp: float = float(T.get("bermPump", 0.12)) * minf(corner_g, 8.0) * berm_c * minf(p_in, 1.0)
			a += bp; pump_push += bp
			if btn: pump_press_t += dt   # (a press spent pumping the berm doesn't hop when it's let go)
			if _EPROBE: _e_add("pump", bp * v * dt)
		if absf(pump_push) > 0.05:
			pump_gain += pump_push * dt * 3.6; pump_idle = 0.0
		else:
			pump_idle += dt
			if pump_idle > 1.2: pump_gain = move_toward(pump_gain, 0.0, dt * maxf(4.0, absf(pump_gain) * 1.5))
		pump_gain = clampf(pump_gain, -30.0, 60.0)
		# a manual held in the sweet spot keeps the speed rolling (like the games' manual boost)
		if man_zone: a += float(T.get("manBoost", 0.5))
		if man_zone and _EPROBE: _e_add("manual", float(T.get("manBoost", 0.5)) * v * dt)
		var carry: float = 1 - T.flowCarry * flow / FLOW_MAX
		# rolling drag per tyre on its own ground (sand drags, hardpack rolls), weighted by the load like the grip
		var rr_f: float = 0.32 if surf_f == 0 else 0.42 if surf_f == 3 else 0.1
		var rr_r: float = 0.32 if surf_r == 0 else 0.42 if surf_r == 3 else 0.1
		var roll: float = (rr_r * SH_R + rr_f * (1.0 - SH_R)) * T.rollRes * signf(v) * minf(1.0, absf(v) * 4)
		# aerodynamics: the drag is the rider's frontal area. Folded down over the bars (right stick forward)
		# it drops (~40 %: an upright downhill rider vs a race tuck), so the bike runs on and tops out faster;
		# sat up tall (stick back) it catches the wind like an air brake. Pedalling hard spoils the tuck a bit
		var tuck: float = clampf(body_in_s, 0.0, 1.0) * (1.0 - 0.5 * clampf(throttle, 0.0, 1.0))
		var sit_up: float = clampf(-body_in_s, 0.0, 1.0)
		aero_k = 1.0 - float(T.get("tuckDrag", 0.42)) * tuck + float(T.get("upDrag", 0.3)) * sit_up
		a -= (roll + T.airDrag / (ts * ts) * v * absf(v) * aero_k) * carry
		if _EPROBE: _e_add("rolling", -roll * carry * v * dt); _e_add("air", -T.airDrag / (ts * ts) * v * absf(v) * aero_k * carry * v * dt)
		if in_water: a -= 0.7 * v
		v = clampf(v + a * dt, -maxf(3.0, rev_cap), 24 * maxf(1.0, ts))
		rev_cap = maxf(3.0, minf(rev_cap, -v))   # the extra reverse room (fakie landing) only shrinks
		# braked to a stop the brake holds the bike where it is (no creeping, even on a slope) until it's let
		# go; pressing brake again from a standstill backs the bike up
		if not brake:
			brake_stop = false; brake_back = absf(v) < 0.3
		elif absf(v) <= 0.3 and not brake_back:
			brake_stop = true
		# ...but only where the tyres can: past the friction angle (or the brake's own limit) the locked bike
		# slides down the slope like a real one (normal trail grades hold as before)
		if brake_stop and G * absf(sin(slope)) > minf(T.brakeForce * (float(T.get("brakeRear", 0.6)) * brake_r + float(T.get("brakeFront", 0.75)) * brake_f), 0.85 * mu * n_tot):
			brake_stop = false
		if brake_stop or (foot_down and throttle < 0.1 and not (brake and brake_back)):
			v = 0.0   # a foot on the ground holds the bike still (no creeping on a slope)
		elif brake and brake_back and v <= 0.3:
			v += (-1.3 - v) * minf(1.0, dt * 3)
		if throttle < 0.1 and not brake and absf(v) < 0.05 and absf(_g_pitch) < 0.03: v = 0
	else:
		# no pumping in the air (these kept their last ground value through a jump: the HUD pump bar stayed up)
		pump_push = 0.0; pump_on = false; pump_acc = 0.0
		pleg = clampf(clampf((body_in - 0.12) / 0.6, 0.0, 1.0) - _bend_in, -1.0, 1.0)   # (the legs' length carried to the landing)
		# air drag doesn't stop at the lip: the same body area slows the flight (on the full speed, along it).
		# Small (~0.5 m/s off a 1 s jump at 55 km/h) but it was missing, so jumps flew a touch long and fast
		var k_air: float = T.airDrag / (T.topSpeed * T.topSpeed) * aero_k
		var sp_air := sqrt(v * v + vy * vy)
		if _EPROBE: _e_add("air", -k_air * sp_air * (v * v + vy * vy) * dt)
		v -= k_air * sp_air * v * dt; vy -= k_air * sp_air * vy * dt
	if flow > 0:
		flow_t += dt
		if brake and v > 1: flow = maxf(0.0, flow - dt * 3)
		elif flow_t > T.flowTime: flow = maxf(0.0, flow - dt * 1.5)
	skid = brake and rear_down and v > 0.5 and rear_lock > 0.15
	var top_now: float = (T.pedalTop + T.sprintTop * sprint) * gear_k() * T.topSpeed
	if v > top_now + 0.3: spun_out = true
	elif v < top_now - 0.8: spun_out = false
	pedal += ((throttle if (not air and not spun_out) else 0.0) - pedal) * minf(1.0, dt * 6)
	throttle_in = throttle
	return a_long

## stage 6: across the bike: steering, lean and balance, the turn, both tyres' side grip (the grip sim), slides and
## the soft crash meters. Returns the speed it worked with (va)
func _step_steer(dt: float, f: Vector3, brake_k: float, steer_input: float, roll_keys: float, a_long: float, nR: float, nF: float) -> float:
	var terrain = host.terrain
	var n_tot := n_load
	var mu_f: float = _mu_f * T.grip
	var mu_r: float = _mu_r * T.grip
	var mu: float = mu_r * SH_R + mu_f * (1.0 - SH_R)
	# --- steering, countersteer and lean ---
	var va := absf(v)
	var spd_k := smooth01(va / 14.0)
	# body stick side lean: the rider throws the bike under them. Leaning alone turns the bike (the bars
	# follow the lean); leaning with the steer turns harder (more lean, more bite). A quick flick of the
	# stick outwards whips the bike round (flick_kick: a yaw kick, the rear stepping out a little)
	# the bike follows the stick on a critically damped spring (flickSpeed = its natural rate) with a top
	# speed, so a thumb throw left -> right swings the bike over smoothly instead of snapping it
	var fw: float = float(T.get("flickSpeed", 14.0))
	flick_v += ((flick_in - flick) * fw * fw - 2.0 * fw * flick_v) * dt
	flick_v = clampf(flick_v, -FLICK_VMAX, FLICK_VMAX)
	flick = clampf(flick + flick_v * dt, -1.0, 1.0)
	# a deliberate flick (stick thrown from near the centre to the edge within FLICK_WINDOW) whips the bike
	# round once; thumb wobble / holding a lean never does (it used to fire on every outward twitch)
	if absf(flick_in) < 0.35:
		_flick_arm = 0.0; _flick_side = 0.0
	elif _flick_side == 0.0:
		_flick_side = signf(flick_in)
	var flick_thrown := 0.0   # +-1 the step a deliberate flick lands (it may start a corner whip)
	if _flick_side != 0.0 and _flick_arm >= 0.0:
		_flick_arm += dt
		if absf(flick_in) > 0.85 and signf(flick_in) == _flick_side:
			if _flick_arm < FLICK_WINDOW and not air and va > 2.0:
				flick_kick += _flick_side * float(T.get("flickKick", 0.16)) * smooth01((va - 2.0) / 5.0)
				flick_thrown = _flick_side
			_flick_arm = -1.0   # spent until the stick comes back towards the centre
	# the side lean steers too (the bike leaned under you turns that way), but held AGAINST the steer it's the body
	# hanging off the inside: that costs grip (weight_in below), it hardly undoes the turn (it used to halve it)
	var fs_k := 1.0 if (absf(steer_input) < 0.2 or signf(flick) == signf(steer_input)) else 0.25
	var steer_eff := clampf(steer_input + flick * float(T.get("flickSteer", 0.5)) * fs_k, -1.0, 1.0)
	# leaning with the steer: how much the two agree, smooth through zero (no on / off as the steer crosses)
	var agree := clampf(flick * steer_eff * 2.0, 0.0, 1.0) * absf(flick)
	# corner whip: both sticks thrown the same way (steer + body lean) in a tight corner. The rider whips the bike
	# over and the rear steps out into a drift held as long as both stay there (Ride › Body: whip*); let go and
	# the tyres catch it. The lean / drift build in over ~0.25 s and ease out, nothing snaps
	var wtr: float = float(T.get("whipTrigger", 0.6))
	var whip_want := not air and va > float(T.get("whipMinSpeed", 4.0)) and absf(steer_input) > wtr and absf(flick_in) > wtr and signf(steer_input) == signf(flick_in) and float(T.get("whipDrift", 0.42)) > 0.0
	# it only STARTS from a deliberate throw of the right stick (centre -> edge within FLICK_WINDOW) with the steer
	# held the same way: leaning the body into a corner with the stick, however far, just turns harder (it used to
	# start a 20-25 deg drift whenever both sticks passed whipTrigger: "we slide weird when leaning"). Once going
	# it is held while both stay past whipTrigger
	if flick_thrown != 0.0 and absf(steer_input) > wtr and signf(steer_input) == flick_thrown: _whip_arm = 0.25
	else: _whip_arm = maxf(0.0, _whip_arm - dt)
	if whip < 0.05 and _whip_arm <= 0.0: whip_want = false
	if whip_want and whip < 0.05: whip_side = signf(steer_input)
	if whip_want and signf(steer_input) != whip_side: whip_want = false
	whip = minf(1.0, whip + dt * 4.0) if whip_want else maxf(0.0, whip - dt * 3.0)
	if whip_want:
		_whip_t += dt
		if _whip_t > 0.3 and not _whip_flashed:
			_whip_flashed = true
			if host.msg_idle(): host.flash("WHIP!")
	elif whip <= 0.0:
		_whip_t = 0.0; _whip_flashed = false
	# the bars follow the input on a critically damped spring (steerEase = its natural rate), capped at the
	# build-up / release rate: a key press or a stick push starts turning gently and builds (an S-curve, no
	# instant full lock), and a swap from full left to full right swings through over ~0.5 s
	var rate: float = T.steerRate if absf(steer_eff) > 0.01 else T.steerRelease
	var se_w: float = float(T.get("steerEase", 30.0))
	steer_in_v += ((steer_eff - steer_in) * se_w * se_w - 2.0 * se_w * steer_in_v) * dt
	steer_in_v = clampf(steer_in_v, -rate, rate)
	steer_in = clampf(steer_in + steer_in_v * dt, -1.0, 1.0)
	var s_in: float = steer_in * (1 - T.steerCurve + T.steerCurve * absf(steer_in))
	if true:
		var b := 0.0 if air else _bank_at(f)
		_bank_raw = b
		# a sharp edge (berm lip, trail edge) gives a one-frame spike across the 0.7 m: the bank the bike
		# feels changes at most 3 rad/s
		# it follows the ground on a critically damped spring (~0.15 s), its speed capped at 3 rad/s: rough ground
		# and a bank-to-bank changeover read as a step every physics tick, which shook the lean, the grip limits and
		# the drawn rider. The berm itself is metres long, so this doesn't delay it
		var b0: float = _or(bank, b)
		var bw_n: float = 2.15 / maxf(0.01, float(T.get("bankSmooth", 0.15)))
		bank_v += ((clampf(b, -0.9, 0.9) - b0) * bw_n * bw_n - 2.0 * bw_n * bank_v) * dt
		bank_v = clampf(bank_v, -3.0, 3.0)
		bank = b0 + bank_v * dt
	var bk := bank
	var carving := not air and absf(steer_eff) > 0.01 and va > 4 and not skid and absf(slip) < 0.3
	carve = minf(1.0, carve + dt * 2) if carving else maxf(0.0, carve - dt * 5)
	var carve_f := carve * smooth01((va - 4) / 4)
	# the rider's weight in the turn: the body stick into the turn = the bike pushed down under them, weight over the
	# outside pedal (more grip, steadier over bumps); against it = hanging off the inside, the tyres lose bite
	# "into the turn" = the way the tyres push (last step): a turn, or uphill riding across a side slope (leaning
	# the bike into the hill there is weighting it right)
	var turn_dir := signf(_f_prev) if absf(_f_prev) > 0.08 else signf(steer_eff)
	weight_in = 0.0 if air else clampf(flick * turn_dir, -1.0, 1.0)
	var w_grip: float = 1.0 + float(T.get("flickGrip", 0.2)) * agree - float(T.get("weightInside", 0.2)) * maxf(0.0, -weight_in)
	# a berm helps the turn at any speed (it used to fade out below ~30 km/h with spd_k)
	# (the turn-force limit: in practice turnFloor below always wins and the grip decides how tight it turns - a
	# slider sweep, 2026-11-20, found its old sliders turnSlow / turnFast / carveBite / flickTurn moved nothing, so
	# they're fixed numbers now)
	var a_lat_lim: float = maxf(1.2, 9.0 + spd_k * 4.0 + G * tan(bk) * signf(s_in) * smooth01(va / 3.0) + carve_f * 2.0 + agree * 4.0 * spd_k)
	var lock: float = T.steerMax + maxf(0.0, T.slowSteer - T.steerMax) * (1 - smooth01(va / maxf(0.5, T.slowSteerFade)))
	var d_max: float = minf(lock, maxf(atan(a_lat_lim * L / maxf(va * va, 0.01)), atan(T.turnFloor * L / maxf(va, 0.1))))
	var cmd: float = s_in * d_max
	# berms: steering into a banked turn (towards its low, inside edge) the rider leans WITH the bank - the bike about
	# square to its surface - and lets it carry the turn round at the speed it was built for (G tan(bank) of turn: the
	# tyres then need no sideways grip at all). Turning harder than that leans further; a light touch of the steer is
	# enough for the berm to take over (bermAssist). Not on a side slope ridden straight (no steer into it)
	var b_in: float = signf(bk) * steer_eff
	var bw_t: float = 0.0 if air else float(T.get("bermAssist", 0.8)) * smooth01((b_in - 0.03) / 0.25) * smooth01((absf(bk) - 0.04) / 0.08) * smooth01((va - 2.5) / 3.0)
	# eased in / out (~0.25 s): switched on and off between steps it jerked the turn (13 m/s² spikes of lat_a)
	berm_k = 0.0 if air else move_toward(berm_k, bw_t, dt * 4.0)
	var bw := berm_k
	if bw > 0.0:
		# (no tighter than the bars may turn at this speed: at low speed the bank's own turn was full lock)
		var cmd_bank: float = minf(d_max, atan(G * tan(absf(bk)) * L / maxf(va * va, 0.5)))
		var held: float = absf(cmd) if signf(cmd) == signf(bk) else 0.0
		cmd = lerpf(cmd, signf(bk) * maxf(held, cmd_bank), bw)
	var lean_need: float = clampf(atan(v * (v * tan(cmd) / L) / G), -T.leanMax + minf(0.0, bk), T.leanMax + maxf(0.0, bk))
	# (on the back wheel he only leans a little: manLean)
	if _balancing() and not air:
		var ml: float = float(T.get("manLean", 0.42))
		lean_need = clampf(lean_need, -ml, ml)
	# balance (balanceSim): rolling, the bike is balanced, not driven. The rider tips it over (that is what the
	# steer asks for) and the turn follows the lean: the front wheel steers itself into the lean (trail), so the
	# bars end up where the lean needs them, after a short push the other way (countersteer) to start it.
	# At walking pace it's the bars again. The rider leans only as far as the grip can hold
	bal_k = 0.0 if air else float(T.get("balanceSim", 0.4)) * smooth01((va - 2.5) / 4.0)
	if bal_k > 0.0:
		var l_hold: float = atan(maxf(0.0, _amax if lean_need >= 0.0 else -_amin) / G) * 0.97
		lean_need = lerpf(lean_need, signf(lean_need) * minf(absf(lean_need), l_hold), bal_k)
	# reflex: in trouble the rider stands the bike up a little (less asked of the tyres)
	lean_need *= 1.0 - float(T.get("reflexStandUp", 0.3)) * float(T.get("riderSkill", 1.0)) * smooth01((risk - 0.15) / 0.5)
	var tipping_in := absf(steer_eff) > 0.01 and absf(lean_need) > absf(lean) and signf(lean_need) == signf(steer_eff)
	var c_max: float = absf(cmd) * T.counter
	# countersteer: a real bike needs it most at speed (the old one only pushed at slow speed)
	var ctr: float = clampf((lean_need - lean) * T.counter, -c_max, c_max) * minf(1.0, va / 4) * lerpf(1 - spd_k, 1.0, bal_k) if tipping_in else 0.0
	var steer_lean: float = clampf(atan(G * tan(lean) * L / maxf(va * va, 0.5)), -lock, lock)
	var steer_target := lerpf(cmd, steer_lean, bal_k) - ctr
	steer += (steer_target - steer) * (1 - exp(-dt * T.barSpeed))
	# a tyre's grip follows its load only after it has rolled a little (relaxation length): over rough ground the
	# load swings every step and the grip limits (and with them the lean) shook with it. Eased over ~0.04 s
	var load_raw := clampf(pow(maxf(0.0, n_tot / G), 0.7), 0.25, 1.5)
	_load_s = load_raw if (air or is_nan(_load_s)) else _load_s + (load_raw - _load_s) * minf(1.0, dt / maxf(0.005, float(T.get("tyreRelax", 0.04))))
	var load_k: float = _load_s
	var mu_g := mu * G * load_k
	# (the front tyre has its own limit below now; the old rough "light front = less grip" factor is gone)
	var a_grip: float = mu_g * sqrt(maxf(0.05, 1 - pow(a_long / mu_g, 2))) * (0.75 if skid else 1.0) * (1 + T.carveGrip * carve_f) * w_grip
	if not air:
		# front up: no steering, except in a balance manual / wheelie, where the rider carves on the back wheel by
		# leaning and twisting the bike (manTurn of the normal turn); before, a manual into any bend went straight on
		var yaw_cmd := v * tan(steer) / L
		if front_air: yaw_cmd *= float(T.get("manTurn", 0.65)) if _balancing() else 0.0
		# on the back wheel the bars do nothing: the turn is the lean (hips, knees), and a rider only leans a wheelie a
		# little (manLean), so it carves wide arcs: at most the turn that lean gives at this speed
		if front_air and _balancing():
			var y_lim: float = G * tan(float(T.get("manLean", 0.42))) / maxf(absf(v), 2.5)
			yaw_cmd = clampf(yaw_cmd, -y_lim, y_lim)
		var gE := G * load_k
		var mE := a_grip / gE
		var cb := cos(bk)
		var sb := sin(bk)
		var a_max := minf(2.5 * G, gE * (sb + mE * cb) / maxf(0.2, cb - mE * sb))
		var a_min := maxf(-2.5 * G, gE * (sb - mE * cb) / maxf(0.2, cb + mE * sb))
		# (what the rider leans to: the grip a moment ago, not this tick's)
		var ak := minf(1.0, dt * 8.0)
		_amax = a_max if _amax > 90.0 else _amax + (a_max - _amax) * ak
		_amin = a_min if _amin < -90.0 else _amin + (a_min - _amin) * ak
		var yaw_use := yaw_cmd
		if carve_f > 0 and not skid and absf(v) > 0.3:
			var want := v * yaw_cmd
			var cap := (a_max if want >= 0 else a_min) * 0.97
			if absf(want) > absf(cap): yaw_use = yaw_cmd + (cap / v - yaw_cmd) * carve_f
		var a_lat_t := clampf(v * yaw_use, a_min, a_max)
		# the front tyre: it carries its share of the turn (the static split, (1 - SH_R)) on whatever load is on it
		# now. Light (weight back, a climb, a crest) or busy braking (its own friction circle) it runs out first and
		# pushes wide (understeer, front_push); pushed hard and long, or locked while leaned over, it washes out
		var fg: float = float(T.get("frontGrip", 1.0))
		var f_need := _fric(a_lat_t, cb, sb)
		# (its share of the load eased like the grip above: a front going light for one tick over a bump snapped the
		# push in and out - lat_a spikes of 13 m/s² and a 15 deg jolt of the rider's body in quick swaps)
		var share_raw := clampf(nF / maxf(0.1, n_tot), 0.05, 1.0)
		_share_f = share_raw if is_nan(_share_f) else _share_f + (share_raw - _share_f) * minf(1.0, dt / maxf(0.005, float(T.get("tyreRelax", 0.04))))
		var share_f: float = maxf(0.05, _share_f)
		var circ_f := sqrt(maxf(0.05, 1.0 - pow(_fb_f / maxf(0.1, mu_f * nF * fg), 2)))
		_circ_f = circ_f
		var mu_fr: float = mu_f * fg * circ_f * w_grip * (1 + T.carveGrip * carve_f) * lerpf(1.0, 0.7, front_lock)
		front_use = 0.0 if front_air else absf(f_need) * (1.0 - SH_R) / share_f / maxf(0.05, mu_fr)
		if front_use > 1.0:
			var f_cap := f_need / front_use
			var a_cap := G * (f_cap * cb + sb) / maxf(0.2, cb - f_cap * sb)
			# the push comes in over the first 15 % past the limit (a hard switch at exactly 1 flickered step to step)
			var pk := smooth01((front_use - 1.0) / 0.15)
			var a_pushed := minf(a_lat_t, a_cap) if f_need > 0.0 else maxf(a_lat_t, a_cap)
			a_lat_t = lerpf(a_lat_t, a_pushed, pk)
			# pushing wide, the front slides with the travel: the bike turns no tighter than it goes (no oversteer)
			if absf(v) > 0.3: yaw_use = lerpf(yaw_use, a_lat_t / v, pk)
		front_push = maxf(0.0, front_use - 1.0)
		# past frontWashAt the front is losing it: the crash judge builds on how far past (a locked front far faster)
		# Only a LOADED front, LEANED over, washes you out: a light front (just landed, nose up, over a crest) is far past
		# its grip only because it carries nothing - it just doesn't steer, the bike runs on straight (that was half
		# of all test crashes, front_use 1.6-4.4 within 0.6 s of landings)
		var wash_at: float = float(T.get("frontWashAt", 1.7))
		var w_load: float = clampf(share_f / (1.0 - SH_R), 0.0, 1.2)
		var w_lean: float = smooth01((absf(lean) - 0.1) / 0.3)
		# (never at once: a skilled rider always gets the time to save a pushing front, so it is capped under crashHard)
		_danger("FRONT WASHED OUT!", minf(2.2, (front_use - wash_at) / 0.6 * (1.0 + 2.0 * front_lock) * w_load * w_lean) if (va > 3.0 and not _balancing()) else -1.0, dt, float(T.get("frontWashTime", 0.7)))   # (not in a manual: the front is up or barely touching on purpose)
		var tau_y: float = T.turnWeight * (0.4 + 0.6 * spd_k)
		lat_m = _or(lat_m, a_lat_t) + (a_lat_t - _or(lat_m, a_lat_t)) * (1 - exp(-dt / tau_y)) if tau_y > 0.005 else a_lat_t
		var a_lat := clampf(lat_m, a_min, a_max)
		if bank_probe:   # tests: the lean collapsing fast at speed, and what the bank / grip limits were then
			_lean_hist.append(lean)
			if _lean_hist.size() > 12: _lean_hist.pop_front()
			if va > 7.0 and _lean_hist.size() == 12 and absf(lean - _lean_hist[0]) > 0.22 and absf(lean) < absf(_lean_hist[0]):
				print("BANKDROP v=%.1f lean %.2f->%.2f bank=%.2f raw=%.2f lat_m=%.1f a_min=%.1f a_max=%.1f steer_in=%.2f slip=%.2f" % [va, _lean_hist[0], lean, bk, _bank_raw, lat_m, a_min, a_max, steer_in, slip])
				_lean_hist.clear()
		var course_rate := a_lat / v if absf(v) > 0.3 else yaw_use
		var excess := yaw_use - course_rate
		var share: float = 1.0 if skid else T.oversteer
		# how much of the tyres' grip the turn uses, measured against the ground's own tilt: across a side slope
		# riding straight the tyres hold the bike up the hill (it used to count as no load at all, so loose ground,
		# bumps and squirm never moved the rear down a camber), and turning into a berm needs less than on the flat
		_f_prev = _fric(a_lat, cb, sb)
		var u_lat := clampf(_f_prev / maxf(0.05, mE), -1.5, 1.5)
		var margin := 1 - minf(1.0, absf(u_lat))
		var gr := _grip_step(dt, va, mu_r, nR, u_lat)
		# the plain catch (tyre pulling back in line) only works with grip to pull with: a locked / spinning /
		# loose rear barely pulls, so the slide lives on in slip_w (the grip sim) instead of being snapped out
		var catch_k: float = (T.slipRecover * (0.25 + margin) + maxf(0.0, -signf(slip) * steer) * 8) * gr * gr
		# corner whip: the catch lets go and the rear swings out to the drift angle and is held there
		# while held the whip owns the slide (the rider holds it on the throttle of their weight), and for ~1 s after
		# letting go it brings the rear back in line, so a released drift is caught instead of spinning on
		var wk := whip * whip * (3.0 - 2.0 * whip)
		whip_hold = maxf(wk, whip_hold - dt / maxf(0.1, float(T.get("whipCatch", 0.9))))
		catch_k *= 1.0 - 0.85 * whip_hold
		catch_k *= 1.0 + float(T.get("reflexCatch", 1.5)) * float(T.get("riderSkill", 1.0)) * risk   # reflex: fights a slide harder the worse it gets
		var slip_rate := (excess * share + slip_w) * (1.0 - 0.75 * whip_hold) - (slip - _squirm) * catch_k
		if whip_hold > 0.0:
			var drift_t: float = whip_side * minf(float(T.get("whipDrift", 0.42)), T.slipMax * 0.6) * smooth01((va - 3.0) / 4.0) * wk
			slip_rate += clampf((drift_t - slip) * float(T.get("whipSnap", 5.0)), -2.2, 2.2) * whip_hold
		# on the front wheel (nose manual / stoppie) the rear, light or in the air, just trails the front: the bike
		# pivots round the front wheel where the bars point, nothing slides out
		if _nosing() or _nose_grace > 0.0:
			slip_w *= exp(-dt * 10.0); slip_rate = -slip * 6.0
		var slip_was := slip
		slip = clampf(slip + slip_rate * dt, -1.5, 1.5)
		# a side slope pulls the bike down it: the front wheel falls to the low side (gravity on the trail of the
		# fork), gently, more when slow. On a berm that's into the turn: it draws you round. Steer to hold a line
		if v > 0.5:
			course_rate += float(T.get("camberPull", 0.22)) * G * sin(bk) / maxf(va, 3.0) * smooth01((v - 0.5) / 2.0)
		# the front tyre is knocked off its line by whatever slopes sideways under it that isn't the land's own tilt:
		# a rock's flank, a root, a rut's wall (ruts hold the wheel in, rocks kick it out). Not over a smooth berm
		var kn: float = float(T.get("groundKnock", 0.6))
		var knock_t := 0.0
		if kn > 0.0 and not front_air:
			var fwo := L - BB_REAR
			var fx: float = x + f.x * fwo
			var fz: float = z + f.z * fwo
			var ox := f.z * 0.12
			var oz := -f.x * 0.12   # to the left
			var grad: float = (terrain.top_height(fx + ox, fz + oz) - terrain.top_height(fx - ox, fz - oz)) / 0.24
			var loc := clampf(grad + tan(bk), -1.5, 1.5)
			# small ripples don't steer (the ground mesh is never perfectly flat: they were a constant buzz in the bars)
			loc = signf(loc) * maxf(0.0, absf(loc) - 0.08)
			knock_t = clampf(-kn * loc * 1.6 * clampf(nF / maxf(0.1, G * (1.0 - SH_R)), 0.0, 1.5) * smooth01(va / 3.0), -1.2, 1.2)
		# the tyre and the rider's arms take a moment: the knock builds and fades over ~0.08 s instead of kicking the
		# travel round in one step (it was the biggest single source of step-to-step jitter)
		knock += (knock_t - knock) * minf(1.0, dt / maxf(0.005, float(T.get("knockSmooth", 0.08))))
		course_rate += knock
		course += course_rate * dt
		# the rear swings round the front: the front tyre holds its line, so the bike's BB moves sideways as
		# the heading turns against the travel (pivot gripPivot of the way from the BB to the front axle)
		var ds := slip - slip_was
		var pv: float = float(T.get("gripPivot", 0.7)) * (L - BB_REAR) * ds
		var hh := course + slip
		x += pv * sin(hh); z += pv * cos(hh)
		if flick_kick != 0.0:   # a body flick whips the bike round: most of it turns the travel, a little steps the rear out
			var fk := flick_kick * minf(1.0, dt * 10)
			flick_kick -= fk
			course += fk * 0.9; slip = clampf(slip + fk * 0.1, -T.slipMax * 0.8, T.slipMax * 0.8)
		if absf(v) < 1.2:
			var k := minf(1.0, dt * 6); course += slip * k; slip -= slip * k; slip_w -= slip_w * k
		# fakie: both sticks towards the pad's centre (left stick right, right stick left) swing the bike round to
		# face the way it travels: the travel flips at once, the drawn heading swings round (turn_off) in ~0.4 s
		if v < -0.5 and steer_input < -0.6 and flick_in > 0.6: _fakie_hold += dt
		else: _fakie_hold = 0.0
		if _fakie_hold > 0.1:
			_fakie_hold = 0.0
			course += PI; v = -v; turn_off = -PI; rev_cap = 3.0
			host.flash("SWITCH!")
		turn_off -= turn_off * minf(1.0, dt * 7.0)
		if absf(turn_off) < 0.01: turn_off = 0.0
		heading = course + slip + turn_off
		yaw_rate = course_rate + slip_rate
		lat_a = a_lat
		# the turn presses down through the leaned bike: the rider feels sqrt(g² + a²) (1.4 g at 45 deg), the legs
		# and shock sink into it (vertical step). Hard into a berm (more turn than the flat allows) it presses more
		# (eased over ~0.1 s: the body felt every flicker of the turn force as a bob of the head)
		var cg_t: float = float(T.get("cornerLoad", 0.6)) * (sqrt(G * G + a_lat * a_lat) - G)
		corner_g += (cg_t - corner_g) * minf(1.0, dt / maxf(0.005, float(T.get("cornerSmooth", 0.1))))
		# (the first ~1 deg of slip is the tyre's own give, not a slide: the chatter wobble kept a phantom scrub on
		# dead-straight riding, ~15 % more rolling resistance than set)
		var scrub := (mu * G * minf(load_k, 1.5) * maxf(0.0, absf(sin(slip)) - 0.015) * 0.9 + absf(excess) * (1 - share) * absf(v) * 0.15) * (1.0 - float(T.get("whipCarry", 0.6)) * wk)   # a held drift keeps its speed
		v -= signf(v) * minf(absf(v), scrub * dt)
		# a slide past slipMax: the crash judge builds on how far past (it used to crash the moment it crossed). In a
		# manual / wheelie the rider first drops the front to catch it on two wheels
		var wo_sev: float = (absf(slip) - T.slipMax) / 0.25 if va > 3.0 else -1.0
		if _balancing() and (wo_sev > 0.0 or absf(slip) > T.slipMax * float(T.get("manSlideCatch", 0.7))):
			_man_drop(); wo_sev = -1.0
		if _nosing() and rear_air: wo_sev = -1.0   # the rear is in the air: it swings round the front (an endo turn), nothing slides
		_danger("WASHED OUT!", wo_sev, dt)
		var into_bank := maxf(0.0, bk * signf(a_lat))
		if absf(slip) > 0.3: carve_acc = 0
		elif carve > 0.6: carve_acc += absf(a_lat) * dt * (1 + 3 * into_bank)
		elif carve < 0.2 and carve_acc > 0:
			var gain: float = minf(T.carveBoost * (1.0 if (into_bank > 0.1 or carve_berm) else 0.5), carve_acc * 0.08) if carve_acc > 2 else 0.0
			carve_acc = 0
			if gain > 0.05 and v > 3:
				v += gain; flow_up()
				if host.msg_idle(): host.flash("%s +%d km/h" % ["BERM" if carve_berm else "CARVE", roundi(gain * 3.6)])
		carve_berm = (carve_berm or into_bank > 0.15) if carve > 0.6 else (carve_acc > 0 and carve_berm)
	else:
		# yaw in the air: a turn carried off the lip keeps turning rider + bike (nothing outside can stop
		# it). The rider can only twist the bike at the hips, within airTwist, to keep it pointing where
		# they fly; slip is the bike's heading against the travel direction
		var sys_slip := wrapf(slip - air_tw, -PI, PI) + (air_yaw + stick_yaw) * dt
		# air WHIP (rider + bike as two masses): the right stick to the side (short of its edge, which spins) throws the
		# bike sideways under a body that keeps facing where it flies - the hips kick the bike out, the shoulders stay.
		# It comes back as the landing nears (the rider straightens it; held to the end it lands sketchy)
		var whip_t: float = clampf(air_stick.x / 0.8, -1.0, 1.0) * float(T.get("airWhip", 1.1)) * (1.0 - float(T.get("whipReturn", 0.7)) * land_prep * float(T.get("airAssist", 0.6)))
		var tw_lim: float = maxf(T.airTwist, absf(whip_t) + 0.05)
		var tw_t := clampf(-sys_slip + whip_t, -tw_lim, tw_lim)
		# a flat spin turns rider + bike as one: no whip, no hips holding the bike on the travel line (they made the
		# bike snap out ~60 deg, hang while the body turned, then jump round ~130 deg in a tenth of a second)
		tw_t *= 1.0 - clampf(absf(stick_yaw) / 1.2, 0.0, 1.0)
		air_tw_v += (60.0 * (tw_t - air_tw) - 12.0 * air_tw_v) * dt
		air_tw += air_tw_v * dt
		if absf(air_tw) > tw_lim:
			air_tw = signf(air_tw) * tw_lim; air_tw_v = 0.0
		_whip_peak = maxf(_whip_peak, absf(air_tw))
		var slip_new := wrapf(sys_slip + air_tw, -PI, PI)
		yaw_rate = wrapf(slip_new - slip, -PI, PI) / dt
		spin_acc += yaw_rate * dt
		slip = slip_new
		turn_off -= turn_off * minf(1.0, dt * 7.0)
		heading = course + slip + turn_off
		lat_a = 0; lat_m = 0; flick_kick = 0.0; corner_g = 0.0; front_use = 0.0; front_push = 0.0; knock = 0.0
		slip_w = 0.0; grip_r = 1.0; bar_catch += -bar_catch * minf(1.0, dt * 6)
	if not air:
		_pivot_step(dt, steer_input, brake_k)
	# (+ a whip lays the bike flatter the further it's thrown, like the real thing)
	var roll_t: float = roll_keys * T.airRoll + air_stick.x * float(T.get("stickAirRoll", 0.75)) + clampf(air_stick.x / 0.8, -1.0, 1.0) * float(T.get("airWhip", 1.1)) * 0.3
	if air: roll_t *= 1.0 - 0.6 * clampf(absf(stick_yaw) / 1.2, 0.0, 1.0)   # spinning flat: a stylish lean, not laid right over
	var lean_t: float = (roll_t if absf(roll_t) > 0.03 else lean * 0.98) if air else clampf(atan(lat_a / G), -T.leanMax + minf(0.0, bk), T.leanMax + maxf(0.0, bk))
	# slow riding: the rider tips in WITH the steer (towards the lean the asked-for turn needs) instead of waiting for
	# the turn to build, and a slow bike rolls quicker (little speed, little to hold it up). Both fade out with speed
	# (spd_k), so fast riding is as before. Without it a slow turn was a flat pivot with the lean ~0.5 s behind
	var slow_k := 1.0 - spd_k
	if not air:
		# balanced (bal_k): the rider leans to what the steer asks for and the turn follows the lean
		lean_t = lerpf(lean_t, lean_need, maxf(float(T.get("leanLead", 0.5)) * slow_k, bal_k))
	var kL: float = T.leanIn if absf(steer_eff) > 0.01 else T.leanOut
	if not air: kL *= 1.0 + float(T.get("slowRoll", 1.0)) * slow_k
	if air and air_stick.length() > 0.02: kL = 80.0   # the stick lays the bike over in the air (soft, no snap)
	if not air:
		# only the ground pushing on the tyres can change the lean: over a crest or an edge (tyres light) the
		# bike carries its lean on instead of snapping upright with the momentary lack of grip
		kL *= clampf(n_tot / G, 0.12, 1.0)
	lean_v += ((lean_t - lean) * kL - lean_v * 2 * sqrt(kL) * T.leanDamp) * dt
	lean_err = 0.0
	if not air:
		# a balanced bike leaned further than the tyres can turn it falls on over (an inverted pendulum, centre of
		# mass ~1 m up): a loose patch, a brake grabbed mid-corner or a front pushing wide drops it in. Held there
		# past lowsideAngle for 0.3 s it's down (LOWSIDE). The rider only leans as far as the grip held a moment
		# ago (lean_need above), so riding the limit is fine; losing the grip under it isn't
		# (measured against the most the tyres could turn it, not the turn right now: through a left-right swap the
		# lean always runs ahead of the turn, that's how a bike changes direction, not a fall)
		var l_grip: float = atan(maxf(0.0, _amax if lean >= 0.0 else -_amin) / G)
		lean_err = signf(lean) * maxf(0.0, absf(lean) - l_grip)
		# (just landed, the tyres haven't bitten yet and the rider is still bringing a lean carried out of the air
		# round: no falling in / lowside for the first moment, it fades in over 0.4 s)
		var land_k := smooth01((since_land - 0.1) / 0.3)
		var fall: float = float(T.get("balanceFall", 0.5)) * bal_k * land_k
		if fall > 0.0 and lean_err != 0.0:
			lean_v += fall * G * sin(lean_err) * dt
		_danger("LOWSIDE!", (absf(lean_err) - float(T.get("lowsideAngle", 0.3))) / 0.25 if (bal_k > 0.3 and land_k > 0.99 and va > 4.0) else -1.0, dt)
		# a real bike + rider (~100 kg) only rolls so fast: the roll speed eases into a top rate (leanRate,
		# rad/s of the body lean; the bike leans bikeLeanMul x that) instead of whipping from one side to the other.
		# Fast, the spinning wheels hold the bike up and it rolls a little slower (gyroStable)
		var lr: float = float(T.get("leanRate", 6.0)) / (1.0 + float(T.get("gyroStable", 0.25)) * smooth01((va - 8.0) / 12.0))
		lean_v = lr * tanh(lean_v / lr)
	_risk_settle(dt)
	lean += lean_v * dt
	# the body stick throws the bike over under the rider (the body stays upright: counter grows)
	# the lean the ground gives on top of the turn's own (drawn only): the body stick throwing the bike under the
	# rider, slow steering, tilted ground (a berm, a banked bend, a side slope: rider + bike lean into it, part of the way
	# to square with its surface - gravity-upright on a tilted trail looked like being flung off it), the corner whip.
	# It needs the ground: off a lip it is carried into the air and eased out (it used to vanish in one step at take-off,
	# a snap of the bike + rider), and on landing it eases back in
	var gx_t := 0.0
	var bank_t := 0.0
	if not air:
		gx_t = flick * float(T.get("flickLean", 0.35)) * smooth01(va / 1.5)
		gx_t += s_in * float(T.get("slowLean", 0.3)) * slow_k * smooth01(va / 1.2)
		bank_t = float(T.get("bankLean", 0.6)) * bank
		if whip > 0.0: gx_t += whip_side * float(T.get("whipLean", 0.22)) * whip * whip * (3.0 - 2.0 * whip)
	var gx_rate := 1.2 if air else (3.0 if since_land < 0.35 else 60.0)
	_gx_lean = move_toward(_gx_lean, gx_t, gx_rate * dt)
	# (the ground's share eases at most 1.5 rad/s: from one bank straight into the next it swings over, not snaps)
	bank_lean = move_toward(bank_lean, bank_t, minf(gx_rate, float(T.get("bankLeanRate", 1.5))) * dt)
	# rider + bike are two masses, not one block: the bike (~17 kg) is pushed over under the rider (~75 kg) first and
	# the body follows. While the lean is changing the bike runs ahead of it by the roll speed (bikeLead s), the body's
	# target (lean x bodyLean, see counter) doesn't, so in a swap the bike flicks across under a body that comes
	# after it, and settles back as the lean holds. Drawn only (the turn follows the shared lean as before)
	var lead_t: float = 0.0 if air else clampf(lean_v * T.bikeLeanMul * float(T.get("bikeLead", 0.08)), -0.35, 0.35)
	_bike_lead += (lead_t - _bike_lead) * minf(1.0, dt * 20.0)
	var bl: float = lean * T.bikeLeanMul + _gx_lean + bank_lean + _bike_lead
	if not air:
		cap_bank = 0.0 if signf(bk) != signf(bl) else absf(bk)
	else:   # the bank's extra room is carried off the lip, fading over 2 s (the lean must not snap at take-off)
		cap_bank = maxf(0.0, cap_bank - dt * 0.5)
	var cap_b: float = T.bikeLeanCap + cap_bank
	bike_lean = cap_b * tanh(bl / cap_b)
	var lim_t := 9.0
	if not air and absf(bike_lean) > 0.05:
		# what matters for the tyre is its lean against the ground WHERE IT SWINGS TO, not gravity: leaned deep
		# toward ground that rises beside the bike (a trail's edge, the hillside, a berm's lip) the tyre went
		# into it and the drawn bike was shoved 25-38 cm up ("shoots up for a sec"). Look 0.3 / 0.5 m to the
		# lean side at both wheels: the bike leans at most groundLeanMax against the steepest rise there
		var sg := signf(bike_lean)
		# (+ lean = left = (f.z, -f.x), as in _bank_at. This used to look to the OTHER side: in a berm its own face on the
		# outside read as ground rising at the tyre and stood the bike up, 60 deg of lean drawn as 38 on a 21 deg bank,
		# while a lean toward a real rise wasn't limited at all)
		var lx := f.z * sg
		var lz := -f.x * sg   # unit vector to the lean side
		var phi := -0.5
		for k in 2:   # front and rear wheel (no array built per step)
			var wo: float = L - BB_REAR if k == 0 else -BB_REAR
			var wx: float = x + f.x * wo
			var wz: float = z + f.z * wo
			# the land itself (deck_height: no rock / log domes): passing a rock beside the wheel used to clamp
			# the lean down for a moment ("going over something resets the angle")
			var h0: float = terrain.deck_height(wx, wz)
			for d in LEAN_PROBE:
				phi = maxf(phi, atan((terrain.deck_height(wx + lx * d, wz + lz * d) - h0) / d))
		lean_room = _or(lean_room, phi)
		# eased (~0.17 s), not only rate limited: the slope 0.3 m beside a tyre picks up every ripple of the ground, and
		# at 3 rad/s all of it went straight into the lean limit - laid right over at the top of a berm the bike (and
		# the rider on it) shivered +-1-2 deg at ~7 Hz
		lean_room += clampf((phi - lean_room) * (1.0 - exp(-6.0 * dt)), -3.0 * dt, 3.0 * dt)
		# (ground falling away on the lean side, the inside of a berm: half of that as extra room, at most ~9 deg -
		# all of it laid the bike nearly flat, 77 deg, at full stick in a 20 deg berm)
		lim_t = maxf(0.25, float(T.get("groundLeanMax", 1.05)) - (lean_room if lean_room > 0.0 else maxf(lean_room * 0.5, -float(T.get("bermLeanRoom", 0.15)))))
	# the ground's limit on the lean opens / closes over a moment when the bike leaves / meets the ground: it used
	# to switch on and off in a single step (a 0.5-0.8 rad jump of the bike and the rider at take-off and landing)
	if air:
		lean_lim = minf(9.0, lean_lim + 2.5 * dt)
	elif since_land < 0.4:
		lean_lim = maxf(lim_t, lean_lim - 4.0 * dt)
	else:
		lean_lim = lim_t
	if lean_lim < 8.0:
		bike_lean = signf(bike_lean) * minf(absf(bike_lean), lean_lim)
	# the bike leans under the rider: the body always stays a little more upright than the bike (never
	# hangs inside it, or the inside leg cuts through the frame). The body leans ~70 % of the way the
	# rider + bike lean, so in a fast turn the bike tips well under a fairly upright rider
	# (signed: where the ground / the soft cap holds the bike more upright than the body's own target, the body stays
	# 20 % inside the bike. The absolute difference used to flip it: bike held at 31 deg with the body wanting 55 gave a
	# body at 7 deg, or leaning the wrong way - the rider stood up out of every steep berm)
	var b_sg := signf(bike_lean)
	counter = maxf((bike_lean - (lean + bank_lean) * T.bodyLean) * b_sg, absf(bike_lean) * 0.2) * b_sg
	# on a bank the rider goes WITH the bike (drawn only). "Bike under an upright body" is flat-corner technique; in a
	# berm rider and bike are one line, square to its face. The body's target above is measured against gravity, and
	# the body stick's throw (flickLean) goes to the bike alone, so on banked ground with both sticks he stood up out
	# of a laid-over bike. bank_sq (0 flat .. bankBody on banks toward the lean) takes the body that share
	# of the way into line with the bike (the trail's banked bends are only ~4-10 deg: full from ~8.5); game.gd fades the stick's hips-to-the-outside shift by it too
	var sq_t := 0.0
	if not air:
		sq_t = float(T.get("bankBody", 0.7)) * smooth01((bank * signf(bike_lean) - 0.03) / 0.12)
	bank_sq = move_toward(bank_sq, sq_t, (1.2 if air else 3.0) * dt)
	if bank_sq > 0.0:
		counter = lerpf(counter, bike_lean * 0.2, bank_sq)
	# in the air the stick's lean is the rider's doing: they push the bike over with the legs and arms and
	# their body goes the other way a little (counter-lean), staying over the centre of mass
	if air:
		var wl := clampf(absf(air_stick.x) * 2.5, 0.0, 1.0)
		counter = lerpf(counter, bike_lean * (1.0 + float(T.get("stickBodyCounter", 0.25))), wl)
	rock = pedal_rock(crank, sprint, pedal, va, bike_rock)
	return va

## stage 7: move along the travel direction, then everything it can run into (rocks, trees, fences, tape, walls)
func _step_move(dt: float, f: Vector3) -> void:
	var terrain = host.terrain
	# --- move ---
	var px := x
	var pz := z
	var g_prev: float = terrain.deck_height(px, pz)   # (the JS meant this: its duplicate surface() shadowed it)
	# on the ground v is the speed along the slope (the tyres carry the bike up / down it, so only its
	# horizontal part moves it across the map); in the air v is the horizontal speed
	var v_h := v if air else v * cos(_g_pitch)
	x += cos(course) * v_h * dt; z -= sin(course) * v_h * dt
	distance += absf(v) * dt
	if true:
		var stp := maxf(absf(v) * dt, 1e-3)
		var g_new: float = terrain.deck_height(x, z)
		var wall := g_new > y + 0.35 if air else ((g_new - g_prev) / stp > 1.6 and g_new - g_prev > 0.05)
		if wall and not air:
			# a steep edge is only a wall if it's taller than a tyre rolls up: a 12 cm curb / root step used to stop
			# the bike dead ("BONK!", or a SMACK crash above 6 m/s). Look a little further along the travel so a
			# real face (that keeps rising) still is one; the tyres + suspension ride the small ones
			var sv := signf(v) if v != 0.0 else 1.0
			var g_ahead: float = terrain.deck_height(x + cos(course) * 0.3 * sv, z - sin(course) * 0.3 * sv)
			wall = maxf(g_new, g_ahead) - g_prev > 0.5 * minf(RWF, RWR)
		if wall:
			x = px; z = pz
			if absf(v) > 6: _crash("SMACK! Hit the cliff")
			else:
				if absf(v) > 1.5:
					shake = 0.3; host.flash("BONK!")
				v *= -0.25

	# --- obstacles ---
	var FRONT := L - BB_REAR
	# race tape: a swept test (the front tyre's leading edge this step vs each span's line), so a fast bike
	# never slips between the span's hit points
	var tf := FRONT + RWF
	var a0 := Vector2(px + f.x * tf, pz + f.z * tf)
	var a1 := Vector2(x + f.x * tf, z + f.z * tf)
	var near: Array = terrain.colliders_near(x, z)   # one grid walk for tape + obstacles (it was done twice a step)
	_tapes_seen.clear()   # (one member array + a plain loop: no array / lambda per step)
	for c in near:
		if not c.get("tape", false): continue
		var sp: Dictionary = c["tape"]
		if sp["broken"]: continue
		var seen := false
		for o in _tapes_seen:
			if is_same(o, sp): seen = true; break
		if seen: continue
		_tapes_seen.append(sp)
		var tp: PackedVector3Array = sp["pts"]
		var tA := Vector2(tp[0].x, tp[0].z)
		var tB := Vector2(tp[tp.size() - 1].x, tp[tp.size() - 1].z)
		var dm := a1 - a0
		var dt_ab := tB - tA
		var den := dm.cross(dt_ab)
		if absf(den) < 1e-9: continue
		var sm := (tA - a0).cross(dt_ab) / den   # along the tyre's move
		var su := (tA - a0).cross(dm) / den      # along the tape
		if sm < 0.0 or sm > 1.0 or su < 0.0 or su > 1.0: continue
		var tape_y: float = tp[clampi(roundi(su * (tp.size() - 1)), 0, tp.size() - 1)].y
		if y > tape_y - 0.05:   # the wheels are over it
			if Env.s("BMX_TAPE_PROBE") != "": print("TAPESKIP over y=%.2f tape_y=%.2f air=%s" % [y, tape_y, air])
			continue
		var hp := tA + dt_ab * su
		if Env.s("BMX_TAPE_PROBE") != "": print("TAPECROSS su=%.2f v=%.1f" % [su, v])
		if host.smash(c, Vector3(f.x * v, vy, f.z * v), Vector3(hp.x, tape_y, hp.y)):
			v *= 0.97   # ("SNAP!" pops when it tears: TapeSim.torn -> Game._on_tape_torn)
	for c in near:
		if c.get("tape", false): continue   # handled above
		var fx0 := x + f.x * FRONT
		var fz0 := z + f.z * FRONT
		var fdx: float = fx0 - c.x
		var fdz: float = fz0 - c.z
		var fd := sqrt(fdx * fdx + fdz * fdz)
		var cdx: float = x - c.x
		var cdz: float = z - c.z
		var cd := sqrt(cdx * cdx + cdz * cdz)
		var f_min: float = c.r + 0.05
		var c_min: float = c.r + 0.16
		var hit_f := fd < f_min
		var hit_c := cd < c_min
		if not hit_f and not hit_c: continue
		var dx := fdx if hit_f else cdx
		var dz := fdz if hit_f else cdz
		var d := maxf(1e-4, fd if hit_f else cd)
		var mn := f_min if hit_f else c_min
		var vel := Vector3(f.x * v, vy, f.z * v)
		if c.get("cactus", false) and absf(v) > 2.5 and not (air and y > c.get("ceil", INF)):
			if host.smash(c, vel, Vector3(x, y, z)):
				v *= 0.8; shake = maxf(shake, 0.35); host.flash("OUCH! CACTUS!")
			continue
		if c.get("fence", false) and (absf(v) > 2.2 or (air and vy < -2)) and not (air and y > terrain.height(c.x, c.z) + 1.2):
			if host.smash(c, vel, Vector3(x, y, z)):
				v *= 0.86; shake = maxf(shake, 0.3); host.flash("CRUNCH!" if c.get("fence_style", "") == "picket" else "SMASH!")
			continue
		if c.has("top"):
			# how tall the rock stands: over the bike's own height, but never more than over the ground it sits on. On a
			# climb, a bank or leaned in a turn the rock's ground is higher than the bike's middle, and a 15 cm stone
			# measured from there read as a wall: BONK, the bike thrown backwards off a rock it rolls over
			var clear: float = minf(c.top - y, c.top - float(c.get("base", y)))
			if clear < CLIMB * RWF: continue
			if not hit_f or fd > c.r * 0.85: continue
			if (f.x * fdx + f.z * fdz) / fd >= 0: continue
			if absf(v) > 2 and joint_rock != c:
				joint_rock = c
				host.rock_chips(c)
			var back: float = (c.r * 0.85 - fd) / fd
			x += fdx * back; z += fdz * back
			var head := (f.x * fdx + f.z * fdz) / fd
			# over the bars only when the hit could really throw you: the taller the rock against the wheel, the less
			# speed it takes (a rock just past rolling height ~12 m/s, a boulder ~6); a front already unweighted /
			# in the air (a hop, a manual) rides up it. It used to be 6 m/s head-on for any rock past rolling height
			var tall := clampf((clear - CLIMB * RWF) / (RWF * 0.8), 0.0, 1.0)
			var bb: float = float(T.get("bonkBoulder", 6.0))
			var bonk_v: float = bb + (float(T.get("bonkSmall", 12.0)) - bb) * (1.0 - tall)
			if head < -0.77 and -v * head > bonk_v and not front_air:
				_crash("BONK! Over the bars")
				if Env.s("BMX_MAN_PROBE") != "": print("BONKROCK top=%.2f y=%.2f r=%.2f hit_f=%s front_air=%s w_f=%.2f keys=%s" % [c.top, y, c.r, hit_f, front_air, w_f, c.keys()])
			elif head < -0.3 and v > 1.5:
				host.burst(Vector3(fx0, y + 0.3, fz0), 16, 0, 1.2); v *= -0.25; shake = 0.35; host.flash("BONK!")
			else: v *= exp(-3.6 * dt)   # rubbing past it (0.97 a step at 120 Hz, the same at any rate)
			continue
		if air:
			var ceil_h: float = c.ceil if c.has("ceil") else terrain.height(c.x, c.z) + (1.2 if c.get("fence", false) else 3.2)
			if y > ceil_h: continue
		var push := (mn - d) / d
		x += dx * push; z += dz * push
		var hd := (f.x * dx + f.z * dz) / d
		if hd < -0.77 and -v * hd > 6 and not front_air:   # a front already up (manual, hop) rides into it, like rocks
			_crash("BONK! Over the bars")
			if Env.s("BMX_MAN_PROBE") != "": print("BONKOBJ y=%.2f r=%.2f hit_f=%s front_air=%s w_f=%.2f g=%.2f keys=%s" % [y, c.r, hit_f, front_air, w_f, terrain.height(c.x, c.z), c.keys()])
		elif hd < -0.3 and v > 1.5:
			host.burst(Vector3(fx0, y + 0.3, fz0), 16, 0, 1.2); v *= -0.25; shake = 0.35; host.flash("BONK!")
		else: v *= exp(-3.6 * dt)

## stage 8: up / down and pitch: tyre + suspension springs, the rider on their legs, the balance (manual / nose
## manual), the air, take-off and landing
func _step_vertical(dt: float, f: Vector3, throttle: float, brake: bool) -> void:
	var terrain = host.terrain
	# --- vertical + pitch: spring physics ---
	_sample(f)
	var natural: bool
	var dP := _g_pitch - _or(g_pitch, _g_pitch)
	if true:
		var v_pre := v
		if not air and dP > 0.02 and v > 0: v *= cos(minf(dP, 1.2))
		var proj_dv := v - v_pre   # speed lost to the ground kinking up this step (a rock's edge, a curb)
		g_pitch = _g_pitch
		natural = terrain.jump_mask(x, z) < 0.05
		var climb_max := absf(v) * 0.9 + 0.3
		var XF := L - BB_REAR
		var XR := -BB_REAR
		var cp0 := cos(clampf(pitch, -1.3, 1.3))
		var hfC := _wheel_ground(f, XF, RWF, cp0)
		var hrC := _wheel_ground(f, XR, RWR, cp0)
		if not w_init or is_nan(hf_prev):
			hf_prev = hfC; hr_prev = hrC; pitch_v = 0; w_init = true
		if not is_finite(zw_f + zw_r + vw_f + vw_r):
			zw_f = hfC; zw_r = hrC; vw_f = 0.0; vw_r = 0.0
		var hfP := hf_prev
		var hrP := hr_prev
		var vgF := minf((hfC - hfP) / dt, climb_max)
		var vgR := minf((hrC - hrP) / dt, climb_max)
		hf_prev = hfC; hr_prev = hrC
		var shF := 1 - SH_R
		var shR := SH_R
		var IK := 0.32
		var coupled := not air and not (hop_t > 0) and not (lift_t > 0)
		var PHI: float = clampf(T.riderMass, 0, 0.7) if coupled else 0.0
		var mB := 1 - PHI
		var Kb: float = pow(2 * PI * T.tyreHz, 2)
		var K := Kb * mB
		var C: float = 2 * T.tyreDamp * sqrt(Kb) * mB
		# legs stiffen as the rider crouches into a lip, and brace (work hard against the fall) for the
		# first moments after a landing
		var brace := 1.0 - smooth01(since_land / 0.35)
		var kB: float = T.legStiff * (1 + 5 * prep + 4 * brace)
		# --- the rider soaks up the ground by himself (auto-absorb). A crest the bike can't follow at this speed (v^2 x the
		# ground's curve past -g: it would fly) is seen coming: on the face before it, where the ground presses up anyway,
		# the legs bend, so that from the crest on they have their whole stroke to push the bike down onto the ground
		# falling away (the rider's weight through straightening legs holds the light bike down). The bend is only the
		# leg spring's rest moving (rel_t, within the legs' travel): nothing pushes the ride along, so it gains no speed;
		# pumping on purpose (pleg, _step_drive) still does. Bending AT the crest (the body on a smoothed line) was tried:
		# it lightened the bike just where it needed the weight and it flew more. Off where the rider does something else
		# with his legs: a lip / built jump (the pop), the pump, a hop, a manual, braced for a landing
		var rel_t := 0.0
		var ab: float = float(T.get("autoAbsorb", 0.0))
		var ab_on: bool = ab > 0.0 and not air and prep < 0.1 and natural and not (hop_t > 0) and kick_t <= 0.0 and man_a < 0.05 and nose_a < 0.05 and absf(pleg) < 0.1 and since_land > 0.3
		_ab_k = move_toward(_ab_k, 1.0 if ab_on else 0.0, dt * 6.0)
		if _ab_k > 0.0 and absf(v) > 4.0:
			var worst := 0.0   # the hardest throw-off ahead, in g past standing (the crest's v^2 curve + g; < 0 = it flies)
			var here := 0.0    # the same under the bike now
			for q in 4:
				var dq: float = 0.0 if q == 0 else signf(v) * absf(v) * (0.02 + 0.1 * q)   # (0.12 .. 0.32 s ahead)
				# (the curve read over about an eighth of a second of travel: bumps quicker than that the tyres and
				# suspension take, a rider can't bend for each of a string of short rollers)
				var sp: float = clampf(absf(v) * 0.12, 0.7, 3.0)
				var hq: float = terrain.deck_height(x + f.x * dq, z + f.z * dq)
				var kq: float = (terrain.deck_height(x + f.x * (dq + sp), z + f.z * (dq + sp)) + terrain.deck_height(x + f.x * (dq - sp), z + f.z * (dq - sp)) - 2.0 * hq) / (sp * sp)
				if q == 0: here = minf(0.0, 1.0 + v * v * kq / G)
				else: worst = minf(worst, 1.0 + v * v * kq / G)
			# bend for the crest coming (from 0.3 g short of flying); on it the legs come back to their rest and straighten
			# as the ground falls away. (An extra active push off the crest, with the legs' damper let off, was tried: no
			# better on the rough test)
			var on_it: float = smooth01(-here / 0.6)
			_ab_bend = move_toward(_ab_bend, smooth01((0.3 - worst) / 0.8) * (1.0 - on_it), dt * 5.0)
			rel_t = -0.85 * T.legComp * _ab_bend * minf(1.0, ab) * _ab_k
			kB *= 1.0 + 1.5 * _ab_k * minf(1.0, ab)   # (working legs, not hanging ones)
		else:
			_ab_bend = 0.0
		dg_abs = rel_t
		var cB: float = 2 * sqrt(kB) * T.legDamp
		var press: float = T.legPress * G if (natural and not (hop_t > 0) and not (lift_t > 0)) else 0.0
		# (a bike with a real suspension setup needs much less of this to stay on the ground: its rebound damping does
		# that. All of it sat the bike 12 % deeper into its travel on natural ground than its sag was set to)
		if not sus.is_empty(): press *= 0.35
		n_ref = _or(n_ref, G + press) + (G + press - _or(n_ref, G + press)) * minf(1.0, dt * 2 * PI * T.tyreHz * 0.6)
		var TRAVEL: float = T.travel
		var WHEEL_M: float = float(T.get("wheelMass", 0.03))
		var BLOW_V: float = float(T.get("damperKnee", 0.6))
		var BLOW_K: float = float(T.get("damperBlow", 0.2))
		# ---- the two ends, each its own suspension unit (SuspSetup: the garage build's fork and rear shock). Per end:
		# travel (tr), spring rate (k) with its ramp-up (pg: F = k x (1 + pg (x / tr)^2), air ramps, coil barely), the
		# compression it rests at under the bike (s0: its sag), damping in compression (cc; past the knee BLOW_V only
		# hs of it is left) and in rebound (cr, its own setting), seal friction (fr), the bump stop's strength (bs),
		# and its tyre's stiffness (ty, from the pressure). A bike with no setup (the BMX: rigid, its "suspension" is
		# tyres and arms) keeps the one simple spring it always had, the same at both ends
		var trF := TRAVEL; var trR := TRAVEL
		var kF := shF * K; var kR := shR * K
		var pgF := 0.0; var pgR := 0.0
		var ccF := shF * C; var ccR := shR * C; var crF := ccF; var crR := ccR
		var hsF := BLOW_K; var hsR := BLOW_K
		var frF := 0.0; var frR := 0.0
		var bsF := 6.0; var bsR := 6.0
		var sq_cm: float = float(T.get("tyreSquash", 1.2)) * 0.01
		var tyKF: float = 0.5 * G / sq_cm; var tyKR := tyKF
		var s0F := (G + press) / K; var s0R := s0F
		if not sus.is_empty():
			if _su.size() != 18: _sus_cache()   # (the units' numbers as plain floats: this runs 120 times a second)
			# (the Ride sliders still work on top of the setup: spring rate, damping, sag, rebound, ramp-up as multipliers)
			var k_mul: float = (T.tyreHz / 2.4) * (T.tyreHz / 2.4)
			var d_mul: float = T.tyreDamp / 0.39
			var sag_mul: float = float(T.get("suspSag", 1.0))
			var pg_mul: float = float(T.get("suspProg", 1.0))
			var rb_mul: float = float(T.get("suspRebound", 1.0))
			trF = _su[0]; trR = _su[8]
			if host.susp != null and host.susp.wheels_follow:   # never more than the drawn fork / rear end can move
				if host.susp.has_f: trF = minf(trF, float(host.susp.F["max"]) - float(host.susp.F["min"]))
				if host.susp.has_r: trR = minf(trR, float(host.susp.R["max"]) - float(host.susp.R["min"]))
			trF = maxf(trF, 0.03); trR = maxf(trR, 0.03)
			pgF = _su[2] * pg_mul; pgR = (_su[10] + FRAME_PROG * float(T.get("shockProg", 1.0))) * pg_mul   # (+ the frame's linkage: its leverage falls through the travel)
			var sgF: float = clampf(_su[1] * sag_mul, 0.1, 0.5)
			var sgR: float = clampf(_su[9] * sag_mul, 0.1, 0.5)
			# the rate that sits this end at its sag under its share of the weight
			kF = shF * G / (sgF * trF * (1.0 + pgF * sgF * sgF)) * k_mul
			kR = shR * G / (sgR * trR * (1.0 + pgR * sgR * sgR)) * k_mul
			var ccrF := 2.0 * sqrt(kF * shF * mB)
			var ccrR := 2.0 * sqrt(kR * shR * mB)
			ccF = _su[3] * ccrF * d_mul; ccR = _su[11] * ccrR * d_mul
			crF = _su[4] * ccrF * d_mul * rb_mul; crR = _su[12] * ccrR * d_mul * rb_mul
			hsF = clampf(_su[5] * BLOW_K / 0.4, 0.05, 1.0); hsR = clampf(_su[13] * BLOW_K / 0.4, 0.05, 1.0)
			frF = _su[6] * shF * G; frR = _su[14] * shR * G
			bsF = _su[7]; bsR = _su[15]
			tyKF = 0.5 * G / (sq_cm * SuspSetup.PSI_REF / _su[16]); tyKR = 0.5 * G / (sq_cm * SuspSetup.PSI_REF / _su[17])
			s0F = SuspSetup.rest(shF * (G + press), kF, trF, pgF); s0R = SuspSetup.rest(shR * (G + press), kR, trR, pgR)
			if not _sus_synced and host.susp != null:   # the drawn fork / rear end sit at the same sag
				_sus_synced = true
				if host.susp.has_method("set_sag"): host.susp.set_sag(SuspSetup.rest(shF * G, kF, trF, pgF) / trF, SuspSetup.rest(shR * G, kR, trR, pgR) / trR)
			if absf(sag_mul - _sag_seen) > 0.001:   # (the sag slider moved: the drawn ends follow)
				_sag_seen = sag_mul; _sus_synced = false
		elif host.susp != null and host.susp.wheels_follow:
			if host.susp.has_f: trF = clampf(s0F + float(host.susp.F["max"]), 0.05, TRAVEL)
			if host.susp.has_r: trR = clampf(s0R + float(host.susp.R["max"]), 0.05, TRAVEL)
		var tyCF: float = 0.5 * sqrt(tyKF * WHEEL_M); var tyCR: float = 0.5 * sqrt(tyKR * WHEEL_M)
		# ---- what the step can integrate. A wheel is a small mass between two springs (tyre, suspension) and a damper,
		# stepped explicitly at dt / 4: past stiffness x step^2 / mass ~ 4, or damping x step / mass ~ 2, it would
		# ring up and blow apart instead of settling. Any setup or slider (a very light wheel, rock-hard tyres, rebound
		# wound right in, a huge bump stop) is held inside that: the stiffnesses share k_cap, each damping rate is at
		# most c_cap. The stock setup is far inside both (spring + tyre at their stiffest ~2900 of 8400, damping ~4 of 13)
		var h_sub: float = dt / 4.0
		var k_cap: float = WHEEL_M * (1.1 / h_sub) * (1.1 / h_sub)
		var c_cap: float = 0.9 * WHEEL_M / h_sub
		ccF = minf(ccF, c_cap); ccR = minf(ccR, c_cap); crF = minf(crF, c_cap); crR = minf(crR, c_cap)
		var fr_w: float = maxf(0.04, maxf(frF, frR) / maxf(0.3 * c_cap, 1e-6))   # (the friction's ease through zero is a damper too)
		var ks_cap: float = 0.35 * k_cap
		var kt_cap: float = 0.65 * k_cap
		tyKF = minf(tyKF, kt_cap); tyKR = minf(tyKR, kt_cap)
		tyCF = minf(tyCF, 0.5 * c_cap); tyCR = minf(tyCR, 0.5 * c_cap)
		# ---- the suspension's geometry: where a wheel moves as it compresses decides what braking and pedalling do to
		# it, on top of the plain weight transfer.
		#   Fork: it slides along the steering axis, tilted back by the head angle, so the wheel moves up AND back. A
		#     brake force at the front tyre pushes it back along that line = into the fork: the spring carries the
		#     tyre's load + brake x tan(tilt). That is brake dive (a slack fork dives more).
		#   Rear: the axle swings about the linkage's pivot. The chain / drive force's line passes above the contact
		#     patch, which holds the rear up under power: anti-squat (AS = 1 cancels the squat the weight transfer
		#     gives, less = it squats, more = it stands up). The rear brake's force does the opposite through the same
		#     geometry: anti-rise (the rear sits down under its brake instead of standing up).
		# dvF / dvR = that extra push on each spring (m/s2 of the whole weight; + = compresses: frame down, wheel up).
		# The tyre's load on the ground is not changed by it, only how far the spring is pressed.
		var dvF := 0.0
		var dvR := 0.0
		if not sus.is_empty() and not air and v > 0.3:
			var geo: float = float(T.get("suspGeo", 1.0))
			var tan_f := 0.5
			if host.susp != null and host.susp.axis.y > 0.3: tan_f = clampf(absf(host.susp.axis.x) / host.susp.axis.y, 0.2, 0.75)
			var braking := _b_prev > 0.0
			if braking: dvF = _fb_f * tan_f * geo
			var h_l: float = T.loadHeight / maxf(L, 0.5)   # (the same lever the weight transfer's pitch torque uses)
			var a_sq: float = float(T.get("antiSquat", 0.9))
			dvR = (((_fb_r * ANTI_RISE) if braking else 0.0) - maxf(0.0, a_drive) * a_sq) * h_l * geo
			if Env.s("BMX_GEO_PROBE") != "" and int(since_land * 4.0) != int((since_land - dt) * 4.0) and (braking or a_drive > 1.0):   # tests
				print("GEO v=%.1f brake f=%.2f r=%.2f drive=%.2f tan=%.2f AS=%.2f dive=%.2f rear=%+.2f fork=%d%% shock=%d%%" % [v, _fb_f if braking else 0.0, _fb_r if braking else 0.0, a_drive, tan_f, a_sq, dvF, dvR, roundi(100.0 * dg_xF / maxf(dg_travel, 0.01)), roundi(100.0 * dg_xR / maxf(dg_travel, 0.01))])
		var bal_max: float = T.riderBalance * G * BB_REAR / IK
		# rolling off an edge at speed the rider holds the bike level with his weight (the front is unsupported for
		# only a moment): the faster, the more he can hold. (At walking pace the nose still drops.) A 1 m drop at
		# 23 km/h used to tip 40 deg nose down before it landed
		var edge_k := 0.0
		if front_air and not rear_air and not air and wheelie_up <= 0.0 and nose_a <= 0.0:
			# (only where the ground really falls away under the front wheel: over a roller's crest the front is a
			# few cm off the ground, and held up there the bike "climbed" down the back side and stalled)
			# and only off level ground (a drop's deck): going over a crest or off a lip the rear is still on a slope,
			# and there the bike follows the ground / keeps its take-off attitude
			edge_k = smooth01((absf(v) - 2.0) / 5.0) * smooth01((zw_f - hfC - 0.15) / 0.25) * (1.0 - smooth01((absf(_local_slope(f, XR, RWR, cp0)) - 0.05) / 0.1))
			bal_max *= 1.0 + 2.5 * edge_k
		if true:
			var R: float = T.weightShift
			var x_brake: float = -0.8 * R * (1.0 if (brake and not air) else 0.0) + 0.5 * R * clampf(a_drive / 4, 0, 1)
			var xT: float = 0.0 if air else x_brake + R * clampf(_g_pitch * 2.2, -1, 1)
			# in the air the rider leans where they choose (W forward, S back)
			if air:
				xT = air_lean * R
			var hT: float = air_lean * R if air else x_brake
			# the body stick moves the rider fore / aft on the ground too, further than the auto shift reaches
			var reach: float = R * float(T.get("stickShift", 1.7))
			var R2 := maxf(R, absf(body_in_s) * reach)   # stick idle: exactly the old limits
			if not air:
				xT = clampf(xT, -R, R) + body_in_s * reach; hT = clampf(hT, -R, R) + body_in_s * reach
			else:   # in the air the body shifts with the stick too (the bike tilts against it)
				xT += body_in_s * reach * 0.7; hT += body_in_s * reach * 0.7
			# a damped spring to where the rider wants to be, pushed by the bike's own speed changes:
			# the body carries on when the bike slows (braking, a landing, a root) and lags when it surges
			var a_body := 0.0
			if not is_nan(v_last) and not air:
				# (not the kink loss above: over a rock that is a one-step spike of 10-40 m/s2, and the body was thrown
				# forward and back by every stone - "the whole rider leans back and forth")
				a_body = clampf((v - v_last - proj_dv) / maxf(dt, 1e-4), -40.0, 40.0)
			# (not through a flight: the landing re-projects v onto the slope / flips it for a fakie, which read as a
			# 40 m/s2 jolt of the body on the first ground step)
			v_last = NAN if air else v
			var kx: float = T.bodyStiff
			var cx := 2 * sqrt(kx) * 0.75
			var push: float = -a_body * T.bodyInertia
			body_xv += (kx * (clampf(xT, -R2, R2) - body_x) - cx * body_xv + push) * dt
			body_x = clampf(body_x + body_xv * dt, -R2 * 1.4, R2 * 1.4)
			hip_v += (kx * (clampf(hT, -R2, R2) - hip_shift) - cx * hip_v + push) * dt
			hip_shift = clampf(hip_shift + hip_v * dt, -R2 * 1.6, R2 * 1.6)
		var tq: float = a_drive * T.loadHeight
		# sprint wheelie (like a motorbike): stamping on the pedals from slow, the rider hauls on the bars
		# with every stroke and the front comes up. Once it's up they keep pulling as long as sprint is
		# held (and stop balancing it), so it climbs on until it loops out; let go and it drops back down
		# sprint wheelie: stamping on the pedals from slow lifts the front into the balance manual (manSprintLift);
		# the rider balances it from there like any manual (the old self-holding wheelie / manual is gone)
		var pulling: bool = sprint > 0.5 and not air and throttle > 0.1 and not brake
		_sprint_lift = sprint * minf(throttle, 1.0) * slowness(v) if pulling else 0.0
		# the balance, either end (_balance_step): manual / wheelie on the back wheel (man_a), nose manual / stoppie on
		# the front (nose_a)
		var pedalling := throttle > 0.1 and not brake
		_balance_step(dt, pedalling, throttle, brake)
		# style: a wheelie / manual held a while scores when it comes down
		if man_a > 0.12 and front_air and not rear_air:
			wheelie_time += dt; wheelie_pedal = wheelie_pedal or pedalling
		elif man_a < 0.05 and wheelie_time > 0.0:
			if wheelie_time > 1.0 and host.has_method("on_style"):
				host.on_style(roundi(wheelie_time * 220.0), "%s %.1f s" % ["WHEELIE" if wheelie_pedal else "MANUAL", wheelie_time])
			wheelie_time = 0.0; wheelie_pedal = false
		# (wheelie_up = the front's hold in the vertical step: man_a, set down no faster than wheelieDrop when the
		# balance lets go of it at once: a loop-out, a hop)
		wheelie_up = maxf(man_a, wheelie_up - float(T.get("wheelieDrop", 1.6)) * (1.0 + 3.0 * float(T.get("manDirect", 1.0))) * dt)
		if nose_a > 0.12 and rear_air and not front_air:
			nose_time += dt
			if brake: nose_brake_t += dt
		elif nose_a < 0.05 and nose_time > 0.0:
			if nose_time > 0.8 and host.has_method("on_style"):
				host.on_style(roundi(nose_time * 260.0), "%s %.1f s" % ["STOPPIE" if nose_brake_t > nose_time * 0.6 else "NOSE MANUAL", nose_time])
			nose_time = 0.0; nose_brake_t = 0.0
		# a held manual / wheelie follows the ground it rolls onto (nose_ref was the slope where the front came up,
		# so over a crest or into a dip the front was held at the old slope's angle)
		if (wheelie_up > 0.0 or nose_a > 0.0) and not air and not is_nan(nose_ref):
			nose_ref = lerpf(nose_ref, _g_pitch, minf(1.0, dt * 6.0))
		if wheelie_up > 0.0 or nose_a > 0.0:
			bal_max = maxf(bal_max, 30.0)   # the whole body holds a wheelie, not just the hands
		# (on the front wheel the whole weight is ~twice as far from the contact: the hold takes more)
		if nose_a > 0.0: bal_max = maxf(bal_max, 75.0)
		var was_air := air
		var g_jolt := 0.0   # legs bottomed out on the ground this step (a compression, not a landing): the hit taken
		var vy_in := vy
		var was_f := c_f
		var was_r := c_r
		var cF := false
		var cR := false
		var sumF := 0.0
		var sumR := 0.0
		if not is_finite(body_y):
			body_y = y; body_v = vy
		var N := 4
		var h := dt / N
		for i in range(1, N + 1):
			var u := float(i) / N
			var gF := hfP + (hfC - hfP) * u
			var gR := hrP + (hrC - hrP) * u
			var cs := cos(pitch)
			var sn := sin(pitch)
			var dF := zw_f - (y + XF * sn) + s0F
			var dR := zw_r - (y + XR * sn) + s0R
			var pvF := vy + XF * cs * pitch_v
			var pvR := vy + XR * cs * pitch_v
			# touching the ground = the tyre is squashed by it (the wheel can hang topped out above a drop)
			cF = gF > zw_f; cR = gR > zw_r
			# shock damper: full strength up to a knee, then it blows off (shim stack opens) so sharp small hits
			# go into the wheel, not the frame; rebound stays fully damped
			var relF := vw_f - pvF
			var relR := vw_r - pvR
			# (compression: the low-speed rate up to the knee, then only hs of it. Rebound: its own rate. Plus the
			# seals' friction, eased through zero)
			var cdF := (ccF * (relF if relF <= BLOW_V else BLOW_V + hsF * (relF - BLOW_V)) if relF >= 0.0 else crF * relF) + frF * clampf(relF / fr_w, -1.0, 1.0)
			var cdR := (ccR * (relR if relR <= BLOW_V else BLOW_V + hsR * (relR - BLOW_V)) if relR >= 0.0 else crR * relR) + frR * clampf(relR / fr_w, -1.0, 1.0)
			# the last fifth of the travel is the bump stop: the spring rate climbs steeply (to 7x), so an end slows into
			# its stop instead of hitting a wall in one step
			# (a bump stop is rubber: it pushes back hard only while it is being squeezed, and gives little of that back.
			# As a plain spring it threw a bike set down deep in its travel back into the air)
			var bpF := maxf(0.0, dF / trF - 0.8) * 5.0 * smooth01(relF / 0.3)
			var bpR := maxf(0.0, dR / trR - 0.8) * 5.0 * smooth01(relR / 0.3)
			var uF := dF / trF
			var uR := dR / trR
			var FF := maxf(0.0, minf(kF * (1.0 + pgF * uF * uF) * (1.0 + bsF * bpF * bpF), ks_cap) * dF + cdF) if dF > 0.0 else 0.0
			var FR := maxf(0.0, minf(kR * (1.0 + pgR * uR * uR) * (1.0 + bsR * bpR * bpR), ks_cap) * dR + cdR) if dR > 0.0 else 0.0
			# on the stop (100 %: it never goes past) the tyre's push goes straight into the frame
			if dF >= trF - 0.0005: FF = maxf(FF, _ty_f)
			if dR >= trR - 0.0005: FR = maxf(FR, _ty_r)
			sumF += maxf(0.0, FF - (dvF if cF else 0.0)); sumR += maxf(0.0, FR - (dvR if cR else 0.0))   # (the tyres' loads: the spring forces less the geometry's part)
			if i == 1:
				dg_botF = false; dg_botR = false; dg_blowF = false; dg_blowR = false
			dg_xF = dF; dg_xR = dR; dg_vF = relF; dg_vR = relR; dg_fF = FF; dg_fR = FR
			dg_blowF = dg_blowF or relF > BLOW_V; dg_blowR = dg_blowR or relR > BLOW_V
			var leg_f := 0.0
			# a turn's load presses down through the leaned bike (corner_g): the body sinks into the legs, the
			# bike into its suspension, and both come back up as the turn ends (the pump out of a berm)
			var cg := 0.0 if was_air else corner_g
			if not was_air:
				var f_leg := kB * (y + rel_t - body_y) - cB * (body_v - vy)
				body_v += (f_leg - cg) * h; body_y += body_v * h
				leg_f = PHI * (G + f_leg)
				dg_leg_f = f_leg
			var geoF := dvF if cF else 0.0
			var geoR := dvR if cR else 0.0
			var alpha := ((FF - geoF) * XF + (FR - geoR) * XR - leg_f * body_x) * cs / IK + (tq / IK if (cF or cR) else 0.0)
			var w_up := wheelie_up > 0.0 and cR
			var e_up := nose_a > 0.0 and cF and not w_up   # a nose manual: the same hold, about the front wheel
			if cF != cR or w_up or e_up:
				var ref := _or(nose_ref, _g_pitch) + (wheelie_up if cR else 0.0) - (nose_a if e_up else 0.0)
				var wk := 8.0 if e_up else (4.0 if w_up else 1.0 + 5.0 * edge_k)   # holding a wheelie: the whole body works it
				alpha += clampf(30 * wk * (ref - pitch) - 9 * sqrt(wk) * pitch_v, -bal_max, bal_max)
				# the rider's weight is over the front axle in a nose manual: the fork's push doesn't lever the bike
				# back level (without this it only dived on its fork, the rear never left the ground)
				if e_up: alpha -= FF * XF * cs / IK * smooth01(nose_a / 0.15)
			vy += (FF + FR - geoF - geoR - (press if (cF or cR) else 0.0) - mB * (G + cg) - leg_f) / mB * h
			pitch_v += alpha * h
			if not cF and not cR and was_air:
				# in the air: no outside torque. The shared spin air_w only changes with the inertia (tuck),
				# the bike turns with it plus whatever tilt the rider gives it against their own body:
				# W / S tilt it on purpose, hands off the rider aims it at the landing slope
				var I_new: float = 1.0 - T.riderShare * T.tuckSpin * air_pull
				air_w *= air_inertia / I_new; air_inertia = I_new
				# arcade air control (old side-on bike games): holding W / S spins the bike at a steady rate,
				# letting go eases the spin out. The flight arc itself stays real; airArcade 0 = pure physics
				var arc: float = T.airArcade
				if arc > 0.0:
					if absf(flip_in) > 0.05:
						air_w += (flip_in * T.airSpinRate * spin_k - air_w) * minf(1.0, T.airSpinResp * h) * arc
					else:
						air_w *= 1.0 - minf(1.0, T.airSpinStop * h) * arc
				var tgt: float
				var kt_base := 70.0
				if absf(flip_in) > 0.05:
					tgt = flip_in * T.airTilt
				else:
					var hh := maxf(0.0, y - _g_y)
					var tg := (vy + sqrt(vy * vy + 2 * G * hh)) / G
					tgt = wrapf(_g_pitch - (pitch - air_tilt + air_w * minf(tg, 1.0)), -PI, PI)
					# hands off the rider doesn't snap the bike to the landing slope the moment he leaves the ground: he holds
					# the attitude he took off with for airAimDelay s, then eases the bike round softly, and reaches for the
					# landing (stiffer) only in the last moments
					# (a bike that has turned well away from the landing slope is brought back at once)
					var off_k := clampf((absf(tgt) - 0.3) / 0.3, 0.0, 1.0)
					var aim_k: float = maxf(maxf(smooth01((air_time - float(T.get("airAimDelay", 1.0))) / 0.5), land_prep), off_k)
					tgt *= aim_k * air_help   # landing help: hands off only, airAssist of it
					kt_base = lerpf(lerpf(float(T.get("airAimSpeed", 14.0)), 45.0, off_k), 70.0, land_prep)
				tgt = clampf(tgt, -T.airTilt, T.airTilt)
				# right stick: the nose goes where it points, on top of the landing aim
				var st_t: float = float(T.get("stickAirTilt", 0.55))
				tgt += air_stick.y * st_t
				var t_lim: float = T.airTilt + absf(air_stick.y) * st_t
				# the rider's arms and legs move the bike: quick when they aim it at the landing on their own,
				# softer (it takes the whole body) when the stick swings it round
				var soft: float = clampf(air_stick.length() * 3.0 + absf(edge_s) * 2.0, 0.0, 1.0)
				var kt: float = lerpf(kt_base, 50.0, soft)
				air_tilt_v += (kt * (tgt - air_tilt) - 2.0 * sqrt(kt) * 0.85 * air_tilt_v) * h
				air_tilt += air_tilt_v * h
				if absf(air_tilt) > t_lim:
					air_tilt = signf(air_tilt) * t_lim
					if air_tilt_v * air_tilt > 0: air_tilt_v = 0.0
				pitch_v = air_w + air_tilt_v
			y += vy * h; pitch += pitch_v * h
			# wheels: tyre spring from the ground, the shock's reaction, gravity. Stops at full extension
			# (a tyre squashed deep gets much stiffer: the casing, then the rim)
			var sqF := gF - zw_f
			var sqR := gR - zw_r
			var tyF := maxf(0.0, minf(tyKF * (1.0 + minf(5.0, sqF * sqF / 0.0009)), kt_cap) * sqF + tyCF * (vgF - vw_f)) if sqF > 0.0 else 0.0
			var tyR := maxf(0.0, minf(tyKR * (1.0 + minf(5.0, sqR * sqR / 0.0009)), kt_cap) * sqR + tyCR * (vgR - vw_r)) if sqR > 0.0 else 0.0
			_ty_f = tyF; _ty_r = tyR
			vw_f += ((tyF - FF + (dvF if sqF > 0.0 else 0.0)) / WHEEL_M - G) * h; zw_f += vw_f * h
			vw_r += ((tyR - FR + (dvR if sqR > 0.0 else 0.0)) / WHEEL_M - G) * h; zw_r += vw_r * h
			dg_tyF = tyF; dg_tyR = tyR; dg_sqF = maxf(0.0, gF - zw_f); dg_sqR = maxf(0.0, gR - zw_r)
			var wsn := sin(pitch)
			var wcs := cos(pitch)
			var topF := y + XF * wsn - s0F
			var topR := y + XR * wsn - s0R
			if zw_f < topF: zw_f = topF; vw_f = maxf(vw_f, vy + XF * wcs * pitch_v)
			if zw_r < topR: zw_r = topR; vw_r = maxf(vw_r, vy + XR * wcs * pitch_v)
			# ... and at full compression: the wheel never goes further into the frame than its travel
			if zw_f > topF + trF: zw_f = topF + trF; vw_f = minf(vw_f, vy + XF * wcs * pitch_v)
			if zw_r > topR + trR: zw_r = topR + trR; vw_r = minf(vw_r, vy + XR * wcs * pitch_v)
			if not cF and not cR:   # in the air the bike can go all the way round (flips)
				flip_acc += pitch_v * h
				pitch = wrapf(pitch, -PI, PI)
			# the very end: suspension on its stop AND the tyre flat on the rim (TYRE_MAX). Nothing gives any more: the
			# frame is stopped by the ground. The speed lost here is the hit that got through everything (_rim_hit)
			for wi in 2:
				var xx := XF if wi == 0 else XR
				var gg := gF if wi == 0 else gR
				var vg := vgF if wi == 0 else vgR
				var c2 := cos(pitch)
				var dd := gg - (y + xx * sin(pitch) - (s0F if wi == 0 else s0R) + (trF if wi == 0 else trR)) - TYRE_MAX
				if dd <= 0: continue
				probe_bottom += 1
				if wi == 0: dg_botF = true
				else: dg_botR = true
				var lx := xx * c2
				var m_inv := 1 / mB + lx * lx / IK
				var dq := dd / m_inv
				y += dq / mB; pitch += dq * lx / IK
				var vpp := vy + lx * pitch_v
				# (riding into a rock or a kerb on the rim: the frame is carried up over it - the position, above - but it
				# is thrown up at no more than RIM_CLIMB of the edge's rise. Matched to all of it, up to 12 m/s at trail
				# speed, a stone met mid-corner launched the bike and slammed the rider. Coming down onto ground - a
				# landing - is not touched: there the ground's speed under the wheel is zero or falling away)
				vg = minf(vg, RIM_CLIMB)
				if vpp < vg:
					var j := (vg - vpp) / m_inv
					vy += j / mB; pitch_v += j * lx / IK
					_rim_hit = maxf(_rim_hit, j / mB)   # (what it did to the bike as a whole: a wheel far from the middle slapping down mostly turns it)
				if wi == 0: cF = true
				else: cR = true
			# (the rim is as far as a tyre squashes: the wheel sits on it)
			zw_f = maxf(zw_f, gF - TYRE_MAX); zw_r = maxf(zw_r, gR - TYRE_MAX)
			# ... but never further into the frame than its travel: that limit has the last word. (Hung on a wall with
			# one wheel up on it and the other 9 m down - the stress test's cliff - the ground can't be reached by any
			# wheel position: the fork read 374 % of its travel there)
			var endF := y + XF * sin(pitch) - s0F + trF
			var endR := y + XR * sin(pitch) - s0R + trR
			if zw_f > endF: zw_f = endF; vw_f = minf(vw_f, vy + XF * cos(pitch) * pitch_v)
			if zw_r > endR: zw_r = endR; vw_r = minf(vw_r, vy + XR * cos(pitch) * pitch_v)
			dg_sqF = maxf(0.0, gF - zw_f); dg_sqR = maxf(0.0, gR - zw_r)
			if not was_air:
				var rel := body_y - y
				if rel < -T.legComp:
					body_y = y - T.legComp
					# legs bottomed out: the speed the body still had into the bike is the hit the rider takes
					if body_v < vy and since_land < 0.6 and land_jolt >= 0: land_jolt = maxf(land_jolt, vy - body_v)
					if body_v < vy and since_land >= 0.6: g_jolt = maxf(g_jolt, vy - body_v)
					if body_v < vy:
						var vc := PHI * body_v + mB * vy if coupled else vy
						body_v = vc; vy = vc
				elif rel > T.legExt:
					body_y = y + T.legExt
					if body_v > vy:
						var vc := PHI * body_v + mB * vy if coupled else vy
						body_v = vc; vy = vc
		# (the graphs read both ends against one travel: the rear's compression is given on the front's scale)
		dg_xR *= trF / trR
		dg_travel = trF; dg_sag = s0F; dg_sag_r = s0R * trF / trR; dg_knee = BLOW_V; dg_cF = cF; dg_cR = cR
		dg_leg = body_y - y if not was_air else 0.0
		var kN := minf(1.0, dt * 30)
		n_f = _or(n_f, shF * G) + (sumF / N - _or(n_f, shF * G)) * kN
		n_r = _or(n_r, shR * G) + (sumR / N - _or(n_r, shR * G)) * kN
		var now_air := not cF and not cR
		front_air = not now_air and not cF; rear_air = not now_air and not cR
		var gpC := asin(clampf((hfC - hrC) / L, -1, 1))
		# looped out: on the back wheel past what the rider can hold, or still rotating back well past
		# the balance point (a back-wheel landing itself is caught, see _land_trick)
		var back_up := pitch - _local_slope(f, XR, RWR, cp0) if cR and not cF and pitch - gpC > 0.6 else 0.0
		if _balancing() or _man_grace > 0.0: pass   # the balance manual handles its own loop-out (no crash)
		elif back_up > T.landBack + 0.1 or (back_up > 1.15 and pitch_v > 0.5 and not was_air): _crash("LOOPED OUT!")
		elif _nosing() or _nose_grace > 0.0: pass   # so does the nose manual
		elif cF and not cR and gpC - pitch > 0.6 and _local_slope(f, XF, RWF, cp0) - pitch > 1.15: _crash("NOSE DIVE!")
		# (not on the touch-down step: the clamp ran before the landing verdict, so a flip that came down upside
		# down was clamped to 1.45 and rarely read as UNDER- / OVER-ROTATED)
		if absf(pitch) > 1.45 and (cF or cR) and not was_air:   # on the ground only: in the air flips go all the way round
			pitch = signf(pitch) * 1.45; pitch_v = 0
		# one wheel just left the ground: the rider holds the bike at the slope it was on with both wheels down
		# (last step's wheel-ground slope). It was gpC - dP, with dP from the axle point samples: rolling off a
		# ledge those jump a whole step before the round tyre does and the reference came out ~1 rad nose up,
		# so every drop off an edge was an instant NOSE DIVE
		if not now_air and (front_air or rear_air) and was_f and was_r: nose_ref = _or(_gpc_last, gpC)
		_gpc_last = gpC if (cF and cR) else _gpc_last
		if front_air and pitch - _or(nose_ref, _g_pitch) < -T.noseDive and not _balancing() and _man_grace <= 0.0: _crash("NOSE DIVE!")
		var snN := sin(pitch)
		w_f = hfC if cF else y + XF * snN
		w_r = hrC if cR else y + XR * snN
		pitch_w = pitch
		if host.susp != null:
			y_draw = y; pitch_draw = pitch
		else:
			y_draw = w_r + (w_f - w_r) * (BB_REAR / L); pitch_draw = asin(clampf((w_f - w_r) / L, -1, 1))
		if not was_air and not now_air and not was_f and cF:
			var slap := maxf(0.0, vgF - (vy_in + XF * cos(pitch) * pitch_v))
			if slap > 2:
				compress_v -= minf(1.5, slap * 0.25)   # (no camera shake: at speed it rattled all the time)
				if slap > 3.5: host.burst(Vector3(x + f.x * XF, _g_hf + 0.03, z + f.z * XF), 10, surf, 0.8)
		c_f = cF; c_r = cR
		if not now_air:
			# the rider's body turns with the bike, smoothed by the arms and legs
			body_pw += (pitch_v - body_pw) * minf(1.0, dt * 4)
		if now_air and not was_air:
			if since_land < 0.5 and Env.s("BMX_TRICK") != "": print("BOUNCE %.2fs after landing vy=%.2f pitch=%.2f" % [since_land, vy, pitch])   # tests
			air = true; air_time = 0; air_peak = 0.0; flip_acc = 0.0; spin_acc = 0.0; style_air = 0.0; _whip_peak = 0.0
			# rider + bike fly off at the speed of their shared centre of mass: a bike kicked up by a roller
			# while the body (on soft legs) lags behind doesn't launch the rider with it. In the air the
			# two then move together (the legs only shift them about that centre)
			if coupled and not is_nan(body_v): vy = PHI * body_v + mB * vy
			# never off steeper than the lip itself. Hitting a steep face fast, the front left it, the frame tipped
			# to ~83 deg on its back wheel and the rear spring kept pushing the bike up after ground it read as
			# rising near-vertically (the wheel's ground probe swings up the face as the frame tips): 59 km/h into a
			# 43 deg face took off at 72 deg with more climb speed (16.4 m/s) than the bike had at all (15.4) and
			# flew 15 m high. The climb is held to the lip's own angle (+ LIP_SPARE: the legs, the spring) and so
			# never exceeds the speed along the ground; the frame can't leave pointing far above that
			if not _balancing() and _man_grace <= 0.0 and vy > 0.0:
				var lip_a := maxf(_or(_gpc_last, gpC), _local_slope(f, XR, RWR, cp0))
				var up_max := minf(lip_a + LIP_SPARE, 1.2)
				var vy_cap := maxf(absf(v) * sin(up_max), 2.5)   # (a bounce / small hop off a crest or down a slope: never cut)
				if Env.s("BMX_LIP_PROBE") != "": print("LIPCAP v=%.2f vy=%.2f cap=%.2f lip=%.2f pitch=%.2f" % [v, vy, vy_cap, lip_a, pitch])   # tests
				# (the same tip-up leaves the frame pointing 60-80 deg nose up and still turning back: a loop / SLAM every
				# time. Where the climb had to be cut, the frame leaves along its flight, turning no faster than a lip throws)
				if vy > vy_cap:
					vy = vy_cap
					pitch = minf(pitch, up_max + 0.15); pitch_v = minf(pitch_v, 0.6); body_pw = minf(body_pw, 0.6)
				elif pitch > up_max + 0.5:
					pitch = up_max + 0.5; pitch_v = minf(pitch_v, 1.0); body_pw = minf(body_pw, 1.0)
			# the speed along the lip splits into the horizontal part (v from now on) and the climb (vy): by the way the
			# bike is really going. (It was cos(the ground's slope under the two axles): with the front already past the
			# lip that is the backside's slope, and a rear wheel touching once more as it left took the cut twice)
			v *= cos(asin(clampf(vy / maxf(absf(v), 0.5), -0.94, 0.94)))
			# the legs: a pop that was waiting for this edge goes now; or the lip is squashed (absorbed)
			var pop := 0.0
			if kick_t <= 0.0: _pop_used = 0.0
			if since_land > 0.6: _land_hit = 0.0   # (a new jump: not a bounce off the last landing)
			if _graze: _graze = false   # (the same take-off, after a brush with the lip: the legs have had their say)
			elif pop_wait > 0.0:
				pop = maxf(0.0, _leg_dv(pop_wait) - _pop_used); pop_q = pop_wait; pop_wait = 0.0
				_pop_apply(pop); _pop_used += pop; pop_fx = 1.0
				if pop_time > 0.9 and pop_q > 0.85 and host.msg_idle(): host.flash("PERFECT POP")
			elif squash > 0.05 and vy > 0.3 and kick_t <= 0.0:
				# the legs let the bike come up into the body: the centre of mass flies a flatter line than the lip's. The
				# speed is kept, only its direction turns (low and fast)
				var sq_d: float = minf(T.popPower * 0.7 * squash, 0.45 * vy)
				var sp2 := v * v + vy * vy
				vy -= sq_d
				v = signf(v) * sqrt(maxf(0.0, sp2 - vy * vy))
				squash_fx = clampf(squash, 0.0, 1.0)
				if squash > 0.6 and sq_d > 0.8 and host.msg_idle(): host.flash("SQUASH")
				if Env.s("BMX_TRICK") != "": print("SQUASH k=%.2f dvy=-%.2f" % [squash, sq_d])   # tests
			# the legs push off along the ground's surface: off a lip tilted sideways (a berm's lip, a banked kicker)
			# part of the pop throws rider + bike towards its low side. The bike keeps pointing where it did
			if pop > 0.0 and absf(bank) > 0.03 and absf(v) > 1.0:
				var dc_t := atan(pop * sin(bank) / absf(v)) * signf(v)
				course += dc_t; slip -= dc_t
			# the spin rider + bike leave with: mostly the rider's (they're most of the inertia), plus the
			# throw. Whatever the bike turns on its own beyond that is relative motion the arms and legs soak up
			var sh: float = T.riderShare
			# leaving the ground from ONE wheel (the other already up: the front bouncing along with the rear in the air
			# after a crest, or the rear after the front) is a bounce, not a take-off the body set up: it flies on with the
			# gentler of the bike's own spin and the body's. Seeded from the body's smoothed spin alone, the front bouncing
			# with the rear up got back the nose-down rotation it had a moment before at every bounce and rode on like that
			# for metres until it met a dip on a bottomed fork; the bike's own spin alone nose-dived big rollers (it was
			# turning down with the ground's crest)
			if was_f != was_r and not _balancing() and not _OLD_BOUNCE and absf(pitch_v) < absf(body_pw): body_pw = pitch_v
			if _man_grace > 0.0 or _balancing(): pitch_v = clampf(pitch_v, -0.8, 0.8); body_pw = clampf(body_pw, -0.8, 0.8)
			air_w = (1 - sh) * pitch_v + sh * body_pw + throw_v
			air_tilt = 0.0; air_tilt_v = sh * (pitch_v - body_pw)
			air_inertia = 1.0
			pitch_v = air_w + air_tilt_v
			throw_v = 0.0
			air_yaw = yaw_rate; air_tw = 0.0; air_tw_v = 0.0
			if Env.s("BMX_TRICK") != "": print("TAKEOFF v=%.1f vy=%.2f pitch_v=%.2f spin=%.2f natural=%s at=(%.0f,%.0f) slope=%.2f" % [v, vy, pitch_v, air_w, natural, x, z, _g_pitch])   # tests
			host.on_takeoff()
		elif not now_air and was_air:
			# the ground it comes down on, tilt and all (the bank reading eased back to flat during the flight, so a
			# berm or side-slope landing was taken as flat)
			var b_land := _bank_at(f)
			bank = b_land; _bank_raw = b_land
			# how fast the bike comes down into the slope (the speed along it is kept: the tyres just roll on). On a
			# landing tilted sideways the fall meets the ground at an angle: only cos(tilt) of it is the hit...
			var impact: float = maxf(0.0, v * sin(_g_pitch) - vy_in * cos(_g_pitch)) * cos(b_land)
			# ...and the rest slides rider + bike towards the low side (the tyres then have to catch it: a slide on
			# loose ground, a crash if it's huge). The bike keeps pointing where it did
			if vy_in < 0.0 and absf(b_land) > 0.03 and absf(v) > 0.5:
				var s_lat := -vy_in * cos(_g_pitch) * sin(b_land) * float(T.get("landSlide", 1.0))
				var dc_l := atan(s_lat / absf(v)) * signf(v)
				course += dc_l; slip -= dc_l
				v = signf(v) * sqrt(v * v + s_lat * s_lat)
			var at := air_time
			if Env.s("BMX_FORGIVE_PROBE") != "" and at > 0.1: print("LANDED air=%.2f peak=%.2f pop=%.2f" % [at, air_peak, pop_q])   # tests
			var back_land: bool = cR and not cF and wrapf(pitch - _g_pitch, -PI, PI) > 0.4
			_land_pe = absf(wrapf(pitch - _g_pitch, -PI, PI))   # (how square to the ground it came down: the verdict's forgiveness)
			_rev_land = false; _land_fix = false
			_land_trick(at)
			if _land_fix:
				# the tyres grab the nearer axis: the bike keeps its heading, the travel is dragged round to within
				# slipMax of it (what's left decays as a normal slide), speed lost by the angle dragged through.
				# Past 90 deg that axis is backwards: speed runs negative (fakie)
				var base: float = wrapf(slip - PI, -PI, PI) if _rev_land else wrapf(slip, -PI, PI)
				var keep: float = minf(absf(base), 0.9 * T.slipMax)
				var sl: float = signf(base) * keep
				var drag_a: float = absf(base) - keep
				v = (-v if _rev_land else v) * cos(minf(drag_a, 1.4))
				course = heading - sl; slip = sl; slip_w = 0.0; turn_off = 0.0
				if _rev_land: rev_cap = maxf(3.0, -v)
				_rev_land = false; _land_fix = false
			air = false; since_land = 0; land_jolt = 0.0; _rim_hit = 0.0; land_heavy = 0.0
			body_v = vy_in
			body_pw = air_w
			nose_ref = _g_pitch
			# the velocity into the slope is stopped by the tyres, suspension and legs; along the slope it carries on
			# (a tyre brushing the lip's edge on the way up, a moment after take-off, is not a landing: all of the speed
			# carries on. Projected onto the "slope" there - the backside, under the front axle - it lost half of it)
			_graze = vy_in > 0.3 and at < 0.2
			if _graze: v = signf(v) * sqrt(v * v + vy_in * vy_in)
			else: v = v * cos(_g_pitch) + vy_in * sin(_g_pitch)
			# landed turned to the way it is going: the tyres point one way, the bike travels another. The speed along
			# the tyres rolls on; the speed across them has to be stopped by their grip. In the moment of the landing
			# they can take mu x the push of the landing itself (the impact + a moment of weight): that much is caught at
			# once (speed gone, a kick through the bike: land_yaw), what is left over is a slide the tyres go on fighting.
			# The first few degrees (landYawFree) cost nothing. More than landYawCrash m/s caught at once is a highside.
			# (It used to cost nothing at all up to 60 deg: 43 deg sideways at 47 km/h rode on at full speed)
			land_yaw = 0.0
			var a_y := wrapf(slip, -PI, PI)
			var yaw_free: float = float(T.get("landYawFree", 0.12))
			if not _graze and at > 0.2 and absf(v) > 2.0 and absf(a_y) > yaw_free and absf(a_y) < 1.35 and crash_pending == "":
				var v_abs := absf(v)
				var v_lat := v_abs * sin(absf(a_y) - yaw_free)
				var v_lon := v_abs * cos(absf(a_y) - yaw_free)
				var catch_v: float = _or(_mu_r, 0.8) * (impact * 0.8 + 2.5) * float(T.get("landYawGrip", 1.0))
				var rem := maxf(0.0, v_lat - catch_v)
				land_yaw = v_lat - rem
				var a_new := signf(a_y) * (atan2(rem, maxf(v_lon, 0.1)) + yaw_free * minf(1.0, rem / 0.5))
				v = signf(v) * sqrt(v_lon * v_lon + rem * rem)
				course = heading - a_new; slip = a_new; slip_w = 0.0
				shake = maxf(shake, minf(0.25, land_yaw * 0.035))
				if land_yaw > float(T.get("landYawCrash", 5.5)): _crash("HIGHSIDE!")
				elif land_yaw > 1.8:
					land_fold = maxf(land_fold, minf(0.8, land_yaw / 5.0)); _stun = maxf(_stun, 0.15 + 0.07 * land_yaw)
					if host.msg_idle(): host.flash("SIDEWAYS!" if land_yaw > 3.5 else "SKETCHY!")
				if Env.s("BMX_TRICK") != "" or Env.s("BMX_LAND_PROBE") != "": print("YAWLAND angle=%.0fdeg side=%.1f caught=%.1f left=%.1f v=%.1f -> %.1f %s" % [rad_to_deg(absf(a_y)), v_lat, land_yaw, rem, v_abs, absf(v), crash_pending])   # tests
			# the rider folds into the landing by how hard it is (his knees and elbows take it), then gathers himself
			if not _graze and at > 0.2: land_fold = maxf(land_fold, clampf((impact - 1.5) / 5.5, 0.0, 1.0))
			# perfect landing: a real jump landed with the bike in line with the slope and pointing down the trail (both
			# tyres meet it together). On a downslope the rider pumps it: part of the fall comes back as speed (landBoost
			# at most, none on flat ground: there is nothing to pump). It used to be a flat +6 km/h from nowhere
			var land_err := absf(wrapf(pitch - _g_pitch, -PI, PI))
			if at > float(T.get("landPerfectAir", 0.45)) and crash_pending == "" and land_err < float(T.get("landPerfect", 0.14)) and absf(slip) < 0.25 and v > 1.0:
				var boost: float = float(T.get("landBoost", 1.6)) * clampf(-sin(_g_pitch) / 0.3, 0.0, 1.0) * clampf(impact / 2.5, 0.0, 1.0)
				v += boost; land_perfect = 1.0
				if host.msg_idle(): host.flash(("PERFECT LANDING +%d km/h" % roundi(boost * 3.6)) if boost > 0.4 else "PERFECT LANDING")
			if Env.s("BMX_TRICK") != "": print("LANDERR %.3f perfect=%s" % [land_err, land_perfect >= 1.0])   # tests
			compress_v -= minf(2.2, impact * 0.35) + (minf(1.2, impact * 0.2 + 0.4) if back_land else 0.0)
			if host.susp != null: host.susp.land(maxf(0.0, -vy_in) * cos(_g_pitch) * 0.5 + impact * (0.57 if back_land else 0.4), front_air, rear_air)
			if Env.s("BMX_TRICK") != "": print("LAND impact=%.1f back=%s v_after=%.1f" % [impact, back_land, v])   # tests
			# only a real landing shakes the camera (rollers at speed give lots of tiny hops)
			if at > 0.4 and impact > 3.0: shake = maxf(shake, minf(0.2, (impact - 3.0) * 0.04))
			if at > 0.15: host.burst(Vector3(x, y + 0.03, z), roundi(10 + minf(30, impact * 6)), surf, 0.8 + minf(1.5, impact * 0.25))
			if at > 0.45 and impact < 5: flow_up()
			host.on_landing(at, impact)
		# ride roughness: the body's vertical acceleration vs the ground's under it (riding, not landing)
		var gy_now := hrC + (hfC - hrC) * (BB_REAR / L)
		if not air and not was_air and since_land > 0.6 and not is_nan(probe_vy) and not is_nan(probe_gy[1]):
			var ay := (vy - probe_vy) / dt
			var ag: float = (gy_now - 2.0 * probe_gy[0] + probe_gy[1]) / (dt * dt)
			probe_acc2 += ay * ay; probe_g2 += ag * ag; probe_n += 1
		probe_vy = vy; probe_gy[1] = probe_gy[0]; probe_gy[0] = gy_now   # (in place: no array per step)
		# a compression on the ground (a steep chute slamming into flat, a wall ride into a ledge) is judged like a
		# landing: the legs can only take so much. It used to be ignored, so 45 deg into flat at 55 km/h rode on
		ground_jolt = maxf(ground_jolt, g_jolt)
		if not air and g_jolt > 0.0 and since_land >= 0.6:
			if g_jolt > T.slamJolt * LAND: _crash("SLAM!")
			elif g_jolt > T.slamJolt * LAND * 0.6 and host.msg_idle(): host.flash("OOF!")
		if air:
			air_time += dt; air_peak = maxf(air_peak, y - _g_y)
		elif land_jolt >= 0 and since_land < 0.6:
			# the landing's verdict, from what got through: the speed the body still had into the bike when the legs
			# ran out (land_jolt) and the speed the frame lost against the ground with suspension and tyres on their
			# stops (_rim_hit; nothing softens that, it counts 1.3x). Past what the rider can take
			# (slamJolt) it throws him down; from landHeavy of that it is a heavy landing: speed lost, and he needs a
			# moment to gather himself (land_heavy 0..1: the pose, the pedals)
			# (the two together: legs that were still folded AND a bike on its rims is worse than either)
			var hit := sqrt(maxf(land_jolt, 0.0) * maxf(land_jolt, 0.0) + _rim_hit * _rim_hit * 1.69)
			# (the landing's biggest: a little bounce after it re-lands and clears land_jolt / _rim_hit, so a hit forgiven
			# as clean then counted as nothing at all)
			_land_hit = maxf(_land_hit, hit); hit = _land_hit
			# a landing square to the ground (within ~10 deg) is forgiven a much bigger hit: it costs speed and a wobble
			# (heavy landing), not the crash. Like the arcade bike games: the angle decides, the size of the drop mostly
			# costs flow. (7 m to flat at 63 km/h, landed 12 deg off, read SLAM every time)
			var clean := 1.0 - smoothstep(0.18, 0.6, _land_pe)
			var slam0: float = T.slamJolt * LAND
			var slam: float = slam0 * (1.0 + float(T.get("landForgive", 1.0)) * clean)
			if hit > slam:
				if Env.s("BMX_TRICK") != "" or Env.s("BMX_LAND_PROBE") != "": print("HIT legs=%.2f rim=%.2f hit=%.2f of %.2f pe=%.2f SLAM" % [land_jolt, _rim_hit, hit, slam, _land_pe])   # tests
				_crash("SLAM!"); land_jolt = -1.0
			elif since_land > 0.4:
				var hv: float = float(T.get("landHeavy", 0.6))
				# (heavy from the plain limit up: a clean landing's bigger allowance is all heavy landing, worse the nearer the crash)
				if hit > slam0 * hv:
					land_heavy = clampf((hit - slam0 * hv) / maxf(0.05, slam - slam0 * hv), 0.0, 1.0)
					v *= 1.0 - 0.12 * land_heavy   # (it was 22 %: at trail speed every built jump is overshot onto the flat, and each one took a fifth of the speed)
					land_fold = maxf(land_fold, 0.3 + 0.3 * land_heavy)   # (he stays down: no second dip, a slower way back up)
					_stun = 0.15 + 0.45 * land_heavy
					shake = maxf(shake, 0.1 + 0.15 * land_heavy)
					if host.msg_idle(): host.flash("HEAVY LANDING" if land_heavy > 0.5 else "OOF!")
				if Env.s("BMX_TRICK") != "" or Env.s("BMX_LAND_PROBE") != "": print("HIT legs=%.2f rim=%.2f hit=%.2f of %.2f pe=%.2f heavy=%.2f v=%.1f" % [land_jolt, _rim_hit, hit, slam, _land_pe, land_heavy, v])   # tests
				land_jolt = -1.0   # one verdict per landing
		kick_t = maxf(0.0, kick_t - dt)

## stage 9: the hop and the pump button
func _step_hop(dt: float, inp: Dictionary) -> void:
	var terrain = host.terrain
	# --- hop / pump ---
	if hop_block and not inp.hop: hop_block = false
	var space: bool = inp.hop and not hop_block
	# --- the crouch (preload): hop held, or the body stick pulled back. The legs bend over crouchTime; let go without
	# a pop they stay bent a moment (the stick is on its way forward), then ease up ---
	var back_in: float = clampf((-body_in - 0.25) / 0.45, 0.0, 1.0)
	_stick_hold = _stick_hold + dt if back_in > 0.05 else 0.0
	# (the stick held back a long while is weight back, not a crouch held ready)
	var pre_in: float = maxf(1.0 if space else 0.0, back_in * (1.0 - smooth01((_stick_hold - 0.9) / 0.6)))
	if air: pre_in = 0.0
	_bend_in = pre_in
	if pre_in >= crouch - 0.01:
		crouch = minf(pre_in, crouch + dt / maxf(0.08, float(T.get("crouchTime", 0.25)))); _cr_rel = 0.0
	else:
		_cr_rel += dt
		if _cr_rel > 0.22: crouch = maxf(pre_in, crouch - dt * 5.0)
	crouch_t = crouch_t + dt if crouch > 0.05 else 0.0
	# a pop that comes as the legs and the suspension rebound from a quick dip gets more out of it (the preload's timing)
	rebound = smooth01((crouch_t - 0.08) / 0.12) * (1.0 - smooth01((crouch_t - 0.5) / 0.45))
	load = crouch
	# (how hard the ground presses just now, 1 = standing weight: the tyre loads against their own resting level)
	if not air: _n_grd += (clampf((_or(n_f, 0.0) + _or(n_r, 0.0)) / maxf(1.0, _or(n_ref, G)), 0.0, 3.0) - _n_grd) * minf(1.0, dt * 10.0)
	# a lip absorbed: the stick held forward into it (held a while: a fresh push at a lip is a front flip throw)
	var sq_in: float = clampf((body_in - 0.25) / 0.45, 0.0, 1.0) * float(T.get("squashPower", 1.0)) if (_sf_t > 0.25 and gest_hop <= 0.0 and not _nosing()) else 0.0
	if not air: squash += (sq_in - squash) * minf(1.0, dt * 10.0)
	else: squash = maxf(0.0, squash - dt * 4.0)
	pop_fx = maxf(0.0, pop_fx - dt / 0.45); squash_fx = maxf(0.0, squash_fx - dt / 0.5)
	if pop_wait > 0.0:
		_pop_arm_t -= dt
		if _pop_arm_t <= 0.0: pop_wait = 0.0   # the lip never came (braked, turned off it)
	var backside: bool = not air and _g_pitch < -0.06 and terrain.jump_mask(x, z) > 0.05
	# a press spent pumping a downhill is let go of on the next face without a hop (unless a lip is right there)
	# (not with the front up: in a manual the legs aren't pumping, a hop let go there is the hop out of the manual)
	# (a roller's backside lasts only 0.15-0.4 s at speed: a press that spent most of its time pumping one counts too)
	var pumped: bool = (_pump_release > 0.25 or (_pump_release > 0.08 and _pump_release > 0.5 * _hop_tap_t)) and prep < 0.1 and man_a < 0.08
	_pump_release = pump_press_t if space else _pump_release
	# (reset whenever hop is up, in the air too: let go mid-jump it used to carry over and eat the next hop)
	if not inp.hop: pump_press_t = 0.0
	# --- the pop (one move, the legs' one push: _pop_now). Started by letting go of hop, by the stick (back, then
	# snapped forward), or both; its power = the crouch (_crouch_power) and the scoop (the front already up when it
	# starts: out of a manual), see _hop_power. inputForgive s of slack on the timing ---
	var fgv: float = float(T.get("inputForgive", 0.12))
	var let_go: bool = not space and hop_held
	_hop_tap_t = 0.0 if (space and not hop_held) else _hop_tap_t + dt
	_hop_buf = maxf(0.0, _hop_buf - dt)
	gest_hop = maxf(0.0, gest_hop - dt)
	# the stick: held back (the legs load; out of a quick pull the front comes up through the balance manual), then
	# snapped forward
	if body_in < -0.5 and not air:
		_bh_back += dt; _bh_since = 0.0; _bh_peak = maxf(_bh_peak, man_a)
	else:
		_bh_since += dt
		if _bh_since > 0.3:
			_bh_back = 0.0; _bh_peak = 0.0
	var snapped: bool = _bh_back > 0.04 and body_in > 0.3 and _bh_since < 0.22 and float(T.get("stickHop", 1.0)) > 0.0
	var can_hop: bool = not air and not rear_air and not _nosing() and not (hop_t > 0) and kick_t <= 0.0
	if snapped and can_hop and v > 1.0:
		# (a slow snap is a weaker one; even a bare tap of the stick hops a little)
		var q_snap: float = 1.0 - 0.6 * smooth01((_bh_since - 0.06) / 0.16)
		var scoop: float = _scoop_k(maxf(man_a, _bh_peak))
		var pw := _hop_power(maxf(0.45, _crouch_power()), scoop) * q_snap
		_bh_back = 0.0; _bh_peak = 0.0; gest_hop = 0.4
		throw_v = 0.0   # (the pull back was the preload, not a back flip throw)
		if space: hop_block = true   # the button's crouch went into this pop: letting go doesn't pop again
		if Env.s("BMX_FORGIVE_PROBE") != "": print("STICKHOP power=%.2f scoop=%.2f snap=%.2f man=%.2f v=%.1f lip=%s" % [pw, scoop, q_snap, man_a, v, lip_last if lip_state == 2 else -1.0])   # tests
		_pop_now(pw)
	elif let_go and not air and not _nosing() and crouch > 0.1 and not (hop_t > 0) and not backside and not pumped:
		var pw2 := _hop_power(maxf(0.45, _crouch_power()), _scoop_k(man_a))
		if Env.s("BMX_FORGIVE_PROBE") != "" and man_a > 0.05: print("SCOOPHOP power=%.2f crouch=%.2f man=%.2f" % [pw2, crouch, man_a])   # tests
		_pop_now(pw2)
	elif let_go and not air and (pumped or backside):
		_cr_rel = 1.0   # a pumping press let go: the legs straighten now (that is the push), no pop
	elif (let_go or (snapped and _bh_since < 0.22)) and air and not pumped:
		if air_time <= fgv and crouch > 0.1 and kick_t <= 0.0:
			# coyote time: let go a moment after the wheels left the lip still pops (what the legs have left)
			if snapped: _bh_back = 0.0; gest_hop = 0.4
			pop_time = 0.75
			_hop_pop(0.5, maxf(0.45, _crouch_power())); crouch = 0.0
			if Env.s("BMX_FORGIVE_PROBE") != "": print("FORGIVE coyote pop air=%.3f vy=%.2f" % [air_time, vy])   # tests
		elif let_go and _hop_tap_t < 0.25 and fgv > 0.0:
			_hop_buf = fgv * 1.25   # a tap just before touch-down: the hop comes as the tyres land
	elif _hop_buf > 0.0 and can_hop and not space:
		_hop_buf = 0.0
		_pop_now(0.45)
		if Env.s("BMX_FORGIVE_PROBE") != "": print("FORGIVE buffered hop since_land=%.3f" % since_land)   # tests
	if hop_t > 0:
		hop_t -= dt
		hop_nose = maxf(hop_nose, (0.22 + 0.15 * hop_load) * 0.6 * (1 - maxf(0.0, hop_t) / HOP_PUSH))
		if hop_t <= 0 or air:
			hop_t = 0
			_hop_pop(hop_load, hop_charge)
			hop_charge = 0; lift_t = 0.12
	if lift_t > 0: lift_t = 0.0 if air else maxf(0.0, lift_t - dt)
	hop_bar_show = not air and crouch > 0.12 and (space or back_in > 0.05 or _cr_rel < 0.2)
	hop_bar = _crouch_power()   # (it peaks on the rebound, then sags while the crouch is held: pop at the peak)
	hop_held = space
	hop_nose *= exp(-dt * 3.5)
	land_perfect = maxf(0.0, land_perfect - dt * 1.2)

## stage 10: reading the trail (a lip ahead: crouch, pop), the legs' compression
func _step_lip(dt: float, f: Vector3, brake: bool) -> void:
	var terrain = host.terrain
	# --- reading the trail: spot a lip ahead ---
	var lip_t := INF
	lip_scan = (lip_scan + 1) % 3
	if lip_scan != 0 and not air and v > 3 and lip_state != 0:
		lip_t = INF if lip_state == 1 else maxf(0.0, lip_last - dt)
	elif not air and v > 3:
		var stp := 0.3
		var n := mini(36, ceili(v * (T.prepTime + 0.1) / stp))
		var h_prev: float = terrain.height(x, z)
		var s_prev := NAN
		for i in range(1, n + 1):
			var d := i * stp
			var sx := x + f.x * d
			var sz := z + f.z * d
			var hh: float = terrain.height(sx, sz)
			var sl := (hh - h_prev) / stp
			if not is_nan(s_prev) and s_prev > 0.15 and (s_prev - sl) * v * v / stp > 2.5 * G and terrain.jump_mask(sx, sz) > 0.05:
				lip_t = (d - stp) / v; break
			s_prev = sl; h_prev = hh
	if air or v <= 3: lip_state = 0
	elif lip_t == INF: lip_state = 1
	else:
		lip_state = 2; lip_last = lip_t
	_lip_ago = 0.0 if lip_state == 2 else _lip_ago + dt
	var prep_t: float = smooth01(1 - lip_t / T.prepTime) if lip_t < T.prepTime else 0.0
	prep = maxf(0.0, prep - dt * 4) if air else prep + (prep_t - prep) * minf(1.0, dt * 8)
	var popping := lip_t < 0.14
	if popping and not pop_fired:
		# hands off, the rider gives the lip a little push of his own (autoPump of a full one). A crouch still held
		# into the lip (hop / stick held, never let go) is timed for the player, at popAssist of what letting go on
		# time gives. A lip being squashed gets no push
		var p_auto: float = float(T.autoPump) * 0.6 * prep
		if crouch > 0.1: p_auto = maxf(p_auto, _crouch_power() * float(T.get("popAssist", 0.6)))
		if squash > 0.2: p_auto = 0.0
		pop_fired = true
		if p_auto > pop_wait:
			pop_wait = p_auto; _pop_arm_t = 0.5
		compress_v += 2.5 * prep * p_auto
		if Env.s("BMX_TRICK") != "": print("POP auto prep=%.2f crouch=%.2f power=%.2f squash=%.2f" % [prep, crouch, p_auto, squash])   # tests
	if not air and lip_t == INF: pop_fired = false
	var lp := 0.0
	var tuck := 0.0
	if air:
		var hh := maxf(0.0, y - _g_y)
		var tg := (vy + sqrt(vy * vy + 2 * G * hh)) / G
		lp = smooth01(1 - tg / T.landPrepTime) if vy < 0 else 0.0
		if _tuck_in: lp *= 0.25   # the tuck held into the ground: the legs are still folded, with little left to take the hit
		tuck = smooth01((air_time - 0.08) / 0.2) * (1 - lp)
	land_prep = lp
	var cT: float
	if air: cT = -0.12 * tuck
	elif pop_wait > 0.0 or hop_t > 0: cT = 0.05 + 0.05 * minf(1.0, pop_wait)   # the legs drive straight through the edge
	elif popping and squash < 0.2: cT = 0.03
	else: cT = -0.15 * crouch - 0.06 * carve - T.prepDepth * prep * (1.0 - 0.7 * crouch) - 0.08 * squash
	compress_v += ((cT - compress) * 120 - compress_v * 14) * dt
	compress = clampf(compress + compress_v * dt, -0.28, 0.1)
	air_k += ((1.0 if (air and air_time > 0.12) else 0.0) - air_k) * minf(1.0, dt * 6)
	if host.susp != null and not host.susp.wheels_follow:   # in a ride the tyres follow the ground (BikeRig.fit_wheels)
		var sp := sin(pitch)
		host.susp.update(dt, {"air": air, "load": maxf(load, -compress * 2.5), "brake": 1.0 if (brake and not air) else 0.0,
			"bumpF": 0.0 if air else w_f - (y + (L - BB_REAR) * sp), "bumpR": 0.0 if air else w_r - (y - BB_REAR * sp)})

## stage 11: wheels and cranks turning, the body in the air, effects
func _step_wheels(dt: float, f: Vector3, in_water: bool, va: float) -> void:
	# --- wheels / cranks ---
	var w := v / RWF
	wheel_f += w * dt
	if not skid: wheel_r += v / RWR * dt
	if v < -0.05 and not air and not skid:
		# rolling backwards the freewheel's pawls catch: the chain turns the cranks back with the wheel
		crank += v / RWR / (2.78 * gear_k() * T.topSpeed) * dt
	elif pedal > 0.05:
		crank += crank_rate(w, gear_k(), T.topSpeed, sprint) * pedal * dt
	elif not air:
		var aL: float = host.pedal_a0[0]
		var aR: float = host.pedal_a0[1]
		var tgt: float
		var period := TAU
		if lean > 0.12: tgt = aR + PI / 2
		elif lean < -0.12: tgt = aL + PI / 2
		else:
			tgt = aL; period = PI
		tgt += period * round((crank - tgt) / period)
		crank += (tgt - crank) * minf(1.0, dt * 3.5)
	if air:
		# legs reach for the landing; holding Space tucks the bike up into the body instead
		var rel_t: float = T.legExt * land_prep - (T.legComp * 0.85 + 0.07 * smooth01(pop_fx / 0.35) * pop_q) * air_pull * (1 - land_prep)
		# on the take-off step the leg spring already moved body_y alongside y; after that body_y is
		# last step's bike height + rel
		var rel := _or(body_y, y) - (y if air_time <= dt * 1.5 else _or(y_prev, y))
		var nrel := rel + (rel_t - rel) * (1 - exp(-dt * 12))
		# body and bike push apart about their shared centre of mass, which flies on undisturbed:
		# tucking lifts the bike, reaching down for the landing drops it
		y -= TUCK_SHARE * (nrel - rel)
		body_y = y + nrel; body_v = vy
	y_prev = y

	skid_fx = skid or spin > 0.3 or (not air and va > 1.5 and (absf(slip - _squirm) > 0.1 or (grip_r < 0.45 and absf(slip_w) > 0.3)))
	host.ride_fx(dt, f, va, in_water)


## the right stick held at an edge in the air (one axis, -1..1): the spin it asks for builds up gently towards the edge
## (stickSpinBuild /s, eases out quicker at 4 /s) and how long it's been held that way grows (back to 0 at 3 /s).
## Returns Vector2(eased edge, held seconds)
func _edge_spin(axis: float, s: float, hold: float, dt: float) -> Vector2:
	var edge := signf(axis) * clampf((absf(axis) - 0.8) / 0.15, 0.0, 1.0)
	var rate: float = float(T.get("stickSpinBuild", 2.5)) if absf(edge) > absf(s) else 10.0   # let go = the spin stops soon (4 /s ran on ~120 deg)
	s = move_toward(s, edge, rate * dt)
	if absf(edge) > 0.5 and signf(edge) == signf(s): hold += dt
	else: hold = maxf(0.0, hold - dt * 3.0)
	return Vector2(s, hold)

## the spin-rate multiplier for an edge held that long (x (1 + stickSpinGrow per second), up to 1.5 s)
func _edge_grow(hold: float) -> float:
	return 1.0 + float(T.get("stickSpinGrow", 0.8)) * minf(hold, 1.5)

func _balancing() -> bool:
	return man_a > 0.05

## the front is set down (a slide caught in a manual, the rider bailing out of it)
func _man_drop() -> void:
	if man_w > -2.0: man_w = -2.0
	man_lock = maxf(man_lock, 0.35)

func _nosing() -> bool:
	return nose_a > 0.05

## One step of a tipping balance, the same for both ends of the bike: the manual / wheelie (the front up, on the back
## wheel) and the nose manual / stoppie (the rear up, on the front wheel). a = how far that wheel is up, w its rate.
## Gravity pulls it back down below the balance point b and on over past it (unstable both ways, so it has to be
## feathered); drive is everything the rider adds (rad/s2: + lifts, - drops). Returns (a, w)
func _tip(a: float, w: float, b: float, grav: float, drive: float, dt: float) -> Vector2:
	w += (grav * sin(a - b) + drive - float(T.get("manDamp", 1.6)) * w) * dt
	a += w * dt
	if a <= 0.0:
		a = 0.0; w = maxf(0.0, w)
	return Vector2(a, w)

## gone too far over (either end): the rider saves it by slamming that wheel back down, most of the speed gone. No crash
func _tip_over(b: float, msg: String) -> Vector2:
	v *= float(T.get("manLoopKeep", 0.72)); shake = maxf(shake, 0.25)
	host.flash(msg)
	return Vector2(b * 0.45, -2.5)

## the balance, both ends (only one can be up at a time). Back wheel: the body stick pulled back past manualFrom, a
## sprint stamp from slow and pedal strokes lift the front; the rear brake and leaning forward drop it. Front wheel:
## the front brake with the stick pushed forward past noseFrom tips the rear up; once up the rider's weight over the
## bars holds it (no brake needed), the brake tips it further, the stick back sets it down
func _balance_step(dt: float, pedalling: bool, throttle: float, brake: bool) -> void:
	var zone: float = float(T.get("manZone", 0.14))
	# --- back wheel: manual / wheelie ---
	var b: float = float(T.get("manBalance", 0.55))
	var m_from: float = float(T.get("manualFrom", 0.4))
	var lift: float = float(T.get("manLift", 9.0))
	man_lock = maxf(0.0, man_lock - dt)
	_man_grace = 0.5 if man_a > 0.05 else maxf(0.0, _man_grace - dt)
	var pull: float = clampf((-body_in - m_from) / maxf(0.05, 1.0 - m_from), 0.0, 1.0)
	var pull_t: float = float(T.get("manPullTime", 0.25))
	_pull_age = 0.0 if -body_in < 0.15 else _pull_age + dt
	if -body_in < 0.12: _man_armed = false                        # back at the centre: it has to be pulled again
	# (manBothSticks: on a pad the left stick has to be pulled back with it too)
	# corner gate: the front only comes up from riding roughly straight (manGate = most lean). Leaned into a corner,
	# weight back is weight back (it changes the corner), whatever the stick or the pedals do. Once up it stays up
	var gate_ok: bool = absf(lean) < float(T.get("manGate", 0.2))
	var straight: bool = gate_ok or man_a > 0.05
	# (not with a lip right ahead: there the pull back is the preload for the pop)
	if not _man_armed and gate_ok and lip_state != 2 and not air and -body_in >= 0.5 and _pull_age <= pull_t and (not pad or float(T.get("manBothSticks", 0.0)) < 0.5 or left_back >= 0.5): _man_armed = true
	# power wheelie, like a motocross game: weight back + pedalling lifts the front with no pull at all, as far as the
	# pedals have the power for (all of it slow, none by manPowerSpeed); stop pedalling and it comes down
	var vp: float = maxf(1.0, float(T.get("manPowerSpeed", 9.0)))
	var pw_t: float = float(T.get("manPower", 1.0)) * minf(throttle, 1.0) * (1.0 - smooth01((absf(v) - 0.5 * vp) / (0.5 * vp))) if (pedalling and straight and not air) else 0.0
	_man_pw += (pw_t - _man_pw) * minf(1.0, dt * (6.0 if pw_t > _man_pw else 3.0))
	if not straight: _man_pw = 0.0   # leaned into a corner with the front down: nothing left over lifts it
	if float(T.get("manDirect", 1.0)) >= 0.5 and pull_t > 0.0: 
		# (the pedals alone lift it to the balance point at most: only a pull can take it over the back)
		var p_cap: float = b / (b + float(T.get("manLoop", 0.42)) + 0.08)
		pull = maxf(pull if _man_armed else 0.0, minf(pull, p_cap) * minf(1.0, _man_pw))
	elif not straight: pull = 0.0   # the corner gate holds in every mode (old tipping balance, manPullTime 0 too)
	var can: bool = not air and not _nosing() and v > (0.6 if pedalling else 1.5) and throw_v <= 0.5
	man_pull = pull if can else 0.0
	if not can:
		# in the air or too slow the balance is let go (the air control owns the pitch)
		man_w = 0.0; man_a = move_toward(man_a, 0.0, 3.0 * dt)
		man_zone = false; man_zone_t = 0.0
	else:
		var drive := 0.0
		if man_lock <= 0.0:
			drive += lift * pull
			# a sprint stamp from slow hauls the front up too, as a lift into the balance
			drive += lift * float(T.get("manSprintLift", 1.1)) * _sprint_lift * (0.55 + 0.45 * absf(sin(crank)))
			# pedalling while pulling = a wheelie: each stroke helps lift (the stick is still what holds it)
			if pedalling and pull > 0.0:
				drive += float(T.get("manPedal", 3.0)) * pull * minf(throttle, 1.0) * (0.4 + 0.6 * absf(sin(crank)))
		# (the REAR brake drops a manual: the bare front lever, its wheel in the air, does nothing)
		if brake and brake_r > 0.1 and man_a > 0.0: drive -= float(T.get("manBrake", 12.0))
		drive -= lift * 0.8 * clampf((body_in - 0.2) / 0.6, 0.0, 1.0)
		var t := _tip(man_a, man_w, b, float(T.get("manGravity", 7.0)), drive, dt)
		# DIRECT manual (manDirect 1; 0 = the old tipping balance above): the stick IS the front's height. Pulled a
		# little it lifts a little, about two thirds back it sits on the balance point, right at the edge it is past
		# the loop-out. The front follows on a soft spring (manFollow), so it is smooth and never runs away from
		# the stick: easing the stick forward always brings it back
		var direct: float = clampf(float(T.get("manDirect", 1.0)), 0.0, 1.0)
		var loop_at: float = b + float(T.get("manLoop", 0.42))
		if direct > 0.0:
			var tgt: float = pull * (loop_at + 0.08) if man_lock <= 0.0 else 0.0
			tgt = maxf(tgt, 0.35 * float(T.get("manSprintLift", 1.1)) * _sprint_lift)
			if brake and brake_r > 0.1: tgt *= 1.0 - minf(1.0, brake_r * 1.5)   # the rear brake sets it down
			tgt *= 1.0 - clampf((body_in - 0.2) / 0.6, 0.0, 1.0)
			var kf: float = float(T.get("manFollow", 40.0))
			var acc: float = kf * (tgt - man_a) - 2.0 * sqrt(kf) * 0.9 * man_w
			if pedalling and pull > 0.0 and man_lock <= 0.0:   # a wheelie: each stroke nudges the front
				acc += 0.35 * float(T.get("manPedal", 3.0)) * pull * minf(throttle, 1.0) * absf(sin(crank))
			var w2: float = man_w + acc * dt
			var a2: float = man_a + w2 * dt
			if a2 <= 0.0:
				a2 = 0.0; w2 = maxf(0.0, w2)
			t = Vector2(lerpf(t.x, a2, direct), lerpf(t.y, w2, direct))
		if t.x > loop_at:
			if direct >= 0.5:
				# pulled too far and kept there: he goes off the back (manFall; 0 = the front just floats at the top)
				_man_over += dt
				if float(T.get("manFall", 1.0)) < 0.5:
					t = Vector2(loop_at, minf(t.y, 0.0))
				elif _man_over > 0.2:
					_crash("LOOPED OUT!"); _man_over = 0.0
			else:
				t = _tip_over(b, "LOOPED OUT!"); man_lock = 0.6
		else:
			_man_over = maxf(0.0, _man_over - dt * 2.0)
		man_a = t.x; man_w = t.y
		man_zone = man_a > 0.15 and absf(man_a - b) < zone
		man_zone_t = man_zone_t + dt if man_zone else 0.0
		if Env.s("BMX_MAN_PROBE") != "" and Engine.get_physics_frames() % 15 == 0:   # tests
			print("MAN a=%.2f pull=%.2f pitch=%.2f gp=%.2f v=%.1f stick=%.2f armed=%s pw=%.2f lean=%.2f" % [man_a, pull, pitch, _g_pitch, v, body_in, _man_armed, _man_pw, lean])
	# --- front wheel: nose manual / stoppie ---
	var nb: float = float(T.get("noseBalance", 0.5))
	var n_from: float = float(T.get("noseFrom", 0.6))
	var n_lift: float = float(T.get("noseLift", 9.0))
	nose_lock = maxf(0.0, nose_lock - dt)
	_nose_grace = 0.5 if nose_a > 0.05 else maxf(0.0, _nose_grace - dt)
	var push: float = clampf((body_in - n_from) / maxf(0.05, 1.0 - n_from), 0.0, 1.0)
	var grab: float = minf(1.0, (brake_f if (brake and not front_air) else 0.0) * 1.8)
	var n_can: bool = n_lift > 0.0 and not air and not front_air and not _balancing() and v > (1.0 if nose_a > 0.05 else 2.5) and gest_hop <= 0.0
	nose_push = push * grab if n_can else 0.0
	if not n_can:
		nose_w = 0.0; nose_a = move_toward(nose_a, 0.0, 3.0 * dt)
		nose_zone = false
	else:
		var n_drive := 0.0
		if nose_lock <= 0.0:
			n_drive += n_lift * push * (grab if nose_a < 0.08 else maxf(grab, 0.6))
			if nose_a > 0.08: n_drive += float(T.get("noseBrake", 4.0)) * grab
		n_drive -= n_lift * 0.8 * clampf((-body_in - 0.15) / 0.6, 0.0, 1.0)
		var nt := _tip(nose_a, nose_w, nb, float(T.get("noseGravity", 7.0)), n_drive, dt)
		var n_direct: float = clampf(float(T.get("manDirect", 1.0)), 0.0, 1.0)
		if n_direct > 0.0:
			# the same on the front wheel: the stick forward is how far the rear is up (the brake only starts it); it
			# tops out just past the balance point, it never throws him over
			var n_tgt: float = push * (nb + 0.12) * (grab if nose_a < 0.08 else 1.0) if nose_lock <= 0.0 else 0.0
			n_tgt *= 1.0 - clampf((-body_in - 0.15) / 0.6, 0.0, 1.0)
			var nk: float = float(T.get("manFollow", 40.0))
			var nw2: float = nose_w + (nk * (n_tgt - nose_a) - 2.0 * sqrt(nk) * 0.9 * nose_w) * dt
			var na2: float = nose_a + nw2 * dt
			if na2 <= 0.0:
				na2 = 0.0; nw2 = maxf(0.0, nw2)
			nt = Vector2(lerpf(nt.x, na2, n_direct), lerpf(nt.y, nw2, n_direct))
		if nt.x > nb + float(T.get("noseLoop", 0.4)):
			nt = _tip_over(nb, "TOO FAR!"); nose_lock = 0.6
		nose_a = nt.x; nose_w = nt.y
		nose_zone = nose_a > 0.15 and absf(nose_a - nb) < zone
		if Env.s("BMX_NOSE_PROBE") != "" and Engine.get_physics_frames() % 15 == 0:   # tests
			print("NOSE a=%.2f w=%.2f push=%.2f grab=%.2f zone=%s pitch=%.2f gp=%.2f v=%.1f rear_air=%s slip=%.2f" % [nose_a, nose_w, push, grab, nose_zone, pitch, _g_pitch, v, rear_air, slip])

# --- the hop: one move, however it is started (hop let go, the stick snapped forward, both) ---
## the legs' push out of the crouch they are in, 0..1 of the best one. The speed out of a stroke goes with its root;
## only a pop that rides the rebound of a quick dip (rebound) gets all of it, a crouch held still gives popRebound
## less: preload, then go
func _crouch_power() -> float:
	return sqrt(clampf(crouch, 0.0, 1.0)) * (1.0 - float(T.get("popRebound", 0.18)) * (1.0 - rebound))

## the suspension setup's numbers out of its dictionaries, once (the vertical step reads them 120 times a second)
func _sus_cache() -> void:
	_su.resize(18)
	var i := 0
	for e in ["f", "r"]:
		var u: Dictionary = sus[e]
		for key in ["travel", "sag", "prog", "zc", "zr", "hs", "fric", "bump"]:
			_su[i] = float(u[key]); i += 1
	_su[16] = clampf(float(sus.psi_f), 5.0, 80.0); _su[17] = clampf(float(sus.psi_r), 5.0, 80.0)

## the speed one push of the legs adds to rider + bike (m/s), along the ground's normal. About 2.3 x body weight over
## the ~33 cm from a deep crouch to straight gives a 75 kg rider 2.9 m/s; shared with a 17 kg bike that is 2.4 m/s
## (popKick; a heavier bike gets less: BikeBuild). It is the one budget for the hop and the pop off a lip. Pressed
## into the ground by a compression (a tight transition at speed) the legs have less left to push with
func _leg_dv(power: float) -> float:
	return T.popPower * clampf(power, 0.0, 1.15) * (1.0 - 0.45 * clampf(_n_grd - 1.0, 0.0, 1.4))

## the push leaves along the ground's normal = square to the way the bike is going (in the air: its velocity). So it
## adds its own energy, dv^2 / 2, and nothing else. (Added straight up it also added dv x the climb speed: ~20 J/kg
## off a lip, as much as climbing 2 m, and tables were cleared twice over)
func _pop_apply(dv: float) -> void:
	var th := clampf(atan2(vy, maxf(absf(v), 0.5)), -0.6, 1.2)
	vy += dv * cos(th); v -= signf(v) * minf(absf(v), dv * sin(th))

## the legs go. Close to a lip the push runs through it and leaves at its edge (pop_wait; best started in the last
## ~0.12 s, earlier part of the stroke is spent before the edge); anywhere else it is a hop, now
func _pop_now(pw: float) -> void:
	var win: float = float(T.get("popWindow", 0.24))
	crouch = 0.0
	# (the front wheel already off the edge with the rear still on the face is the lip too: the classic moment)
	var edge: bool = front_air and not rear_air and _lip_ago < 0.35
	if ((lip_state == 2 and lip_last < win) or edge) and not rear_air and v > 3.0:
		var lt: float = 0.0 if (edge or lip_state != 2) else lip_last
		pop_time = 1.0 - 0.4 * smooth01((lt - 0.12) / maxf(0.02, win - 0.12))
		pop_wait = maxf(pop_wait, pw * pop_time); _pop_arm_t = lt + 0.3; pop_fired = true
		compress_v += 2.0 * pw
		if man_a > 0.05: man_lock = maxf(man_lock, 0.3)
		if Env.s("BMX_TRICK") != "" or Env.s("BMX_FORGIVE_PROBE") != "": print("POP lip in %.2fs power=%.2f timing=%.2f edge=%s" % [lt, pw, pop_time, edge])   # tests
	else:
		pop_time = 0.0
		_hop_begin(0.5 + 0.5 * minf(1.0, pw), pw)

## the scoop of a real bunny hop: hopping with the front already up (out of a manual, or the stick just pulled back),
## the rear is scooped up after it. Best with the front well up but short of the balance point; hauled right back
## to the loop-out it's a weak one. front = how far the front is up (rad)
func _scoop_k(front: float) -> float:
	var b: float = float(T.get("manBalance", 0.55))
	return smooth01(front / 0.3) * (1.0 - 0.6 * smooth01((front - b) / 0.3)) * float(T.get("stickHop", 1.0))

## a hop's power from the button charge and the scoop: the better of the two, plus a quarter of the other (both together
## beat either alone, up to 1.25 of a fully charged hop)
func _hop_power(charge_k: float, scoop: float) -> float:
	return minf(1.15, maxf(charge_k, scoop) + 0.15 * minf(charge_k, scoop))

## the legs start their push (HOP_PUSH s); the pop comes at its end (_hop_pop)
func _hop_begin(load_k: float, power: float) -> void:
	hop_t = HOP_PUSH; hop_load = maxf(load_k, 0.5); hop_charge = power
	compress_v = maxf(compress_v, (0.05 - compress) / HOP_PUSH)
	body_v = vy + (T.legExt - minf(0.0, _or(body_y, y) - y)) / HOP_PUSH
	if man_a > 0.05:
		# out of a manual: the scoop brings the front back down, the balance lets go
		man_lock = maxf(man_lock, 0.3)
		if man_a > float(T.get("manBalance", 0.55)): man_w = minf(man_w, -3.0)

func _hop_pop(load_k: float, power: float) -> void:
	var dv := _leg_dv(power)
	if air:
		# (just past a lip: late. The edge is gone, so three quarters of the push at most, less what the legs gave it)
		dv = maxf(0.0, 0.75 * dv - _pop_used)
		_pop_apply(dv)
	else:
		_pop_used = 0.0
		var th := clampf(_g_pitch, -0.6, 0.8)
		# (the climb the bike already has up a slope is kept; the frame coming up as the front is pulled into a manual
		# is the bike turning about its rear wheel, not rider + bike rising: it used to add ~0.9 m/s to every scooped hop)
		vy = clampf(vy, 0.0, maxf(0.0, v * sin(th)) + 0.2) + dv * cos(th); v -= signf(v) * minf(absf(v), dv * tan(th))
	_pop_used += dv; pop_q = power; pop_fx = 1.0
	kick_t = 0.3; hop_nose = 0.22 + 0.15 * load_k + 0.08 * power
	body_v = vy
	if Env.s("BMX_FORGIVE_PROBE") != "": print("HOP power=%.2f dv=%.2f vy=%.2f air=%s n=%.2f legs=%.2f v=%.1f slope=%.2f" % [power, dv, vy, air, _n_grd, T.popPower, v, _g_pitch])   # tests

## touch-down after a jump: the bike must meet the slope roughly lined up and facing down the trail,
## or the rider goes down
func _land_trick(at: float) -> void:
	slip = wrapf(slip, -PI, PI)
	if Env.s("BMX_TRICK") != "":   # tests
		print("TRICK air=%.2fs v=%.1f flip=%.0fdeg spin=%.0fdeg pitch_err=%.0fdeg twist=%.0fdeg" % [at, v, rad_to_deg(flip_acc),
			rad_to_deg(spin_acc), rad_to_deg(absf(wrapf(pitch - _g_pitch, -PI, PI))), rad_to_deg(absf(slip))])
	if at < 0.2:
		return
	# Everything else (nose-dive, loop-out, a slide that washes out, a hit the legs can't take) is decided
	# by the ground physics after touch-down. Only geometry is checked here: turned so far that the
	# wheels can't be what meets the ground, the rider or the bars hit first
	var perr_s := wrapf(pitch - _g_pitch, -PI, PI)   # + = nose up (back wheel first)
	if absf(perr_s) > 1.45:
		# (a flip short of all the way round lands turned against the spin, one too far lands turned with it)
		_crash("UNDER-ROTATED!" if absf(flip_acc) > 3.0 and signf(perr_s) != signf(flip_acc) else
			"OVER-ROTATED!" if absf(flip_acc) > 3.0 else "LOOPED OUT!" if perr_s > 0 else "BAD LANDING!")
		return
	# Graded landing zone instead of a hard cut: within ~60 deg of the travel it is a normal landing; past that
	# the bike lands sideways-ish and the tyres grab the nearer axis (forward, or backwards = fakie past 90 deg),
	# dragging the travel round and scrubbing speed by how far (applied at touch-down, see _ride_step)
	var a_s := absf(slip)
	if a_s > LAND_CONE:
		_rev_land = a_s > PI * 0.5
		_land_fix = true
		host.flash("FAKIE!" if _rev_land else "SKETCHY!")
	var flips := roundi(absf(flip_acc) / TAU)
	var turns := int((absf(spin_acc) + 0.6) / TAU)   # flat spins landed facing forward again (within ~35 deg): 360, 720...
	# a whip thrown (bike kicked > ~35 deg sideways under the body) and brought back straight for the landing
	var whipped := _whip_peak > 0.6 and turns == 0 and absf(slip) < 0.35
	if flips >= 1 or turns >= 1 or whipped:
		var trick := ""
		if whipped: trick = "WHIP" if _whip_peak < 0.95 else "BIG WHIP"
		if turns >= 1: trick = "%d" % (turns * 360)
		if flips >= 1:
			var kind := "BACKFLIP" if flip_acc > 0 else "FRONTFLIP"
			trick = (trick + " " if trick != "" else "") + (["", "", "DOUBLE ", "TRIPLE "][mini(flips, 3)] if flips > 1 else "") + kind
		host.flash(trick + "!")
		if host.has_method("on_trick"): host.on_trick(trick)
		flow_up()
	_style_points(at, flips, turns)

## style points for a landed jump: air time, spins, flips, tweaking the bike about with the stick, and a
## clean (straight) landing bonus. The HUD chains them into combos and drops them if the rider goes down
func _style_points(at: float, flips: int, turns: int) -> void:
	if at < 0.35 or not host.has_method("on_style"): return
	var pts := roundi(at * 250.0) + turns * 600 + flips * 1000 + roundi(minf(style_air, 3.0) * 400.0)
	var parts := []
	if turns >= 1: parts.append("%d" % (turns * 360))
	if flips >= 1: parts.append(("%dx " % flips if flips > 1 else "") + ("BACKFLIP" if flip_acc > 0 else "FRONTFLIP"))
	var whip_ok := _whip_peak > 0.6 and turns == 0 and absf(wrapf(slip, -PI, PI)) < 0.35
	if whip_ok:   # an air whip brought back for the landing: more the further it was thrown
		pts += roundi(500.0 * clampf(_whip_peak, 0.6, 1.3))
		parts.append("WHIP" if _whip_peak < 0.95 else "BIG WHIP")
	elif style_air > 0.35: parts.append("TWEAK")
	if parts.is_empty(): parts.append("BIG AIR" if at > 1.0 else "AIR")
	var clean := absf(wrapf(slip, -PI, PI)) < 0.2 and absf(wrapf(pitch - _g_pitch, -PI, PI)) < 0.15
	if clean:
		pts = roundi(pts * 1.5)
		parts.append("CLEAN")
	host.on_style(pts, " + ".join(parts))

## Pivot (pirouette): slow, brake held and steering -> the rear swings round the front wheel, as far as you like
func _pivot_step(dt: float, steer_input: float, brake_k: float) -> void:
	var on := absf(v) < 2.5 and brake_k > 0.3 and absf(steer_input) > 0.1 and not front_air and not rear_air
	if not on:
		pivot = maxf(0.0, pivot - dt * 5)
		if pivot == 0.0: pivot_acc = 0.0
		return
	pivot = minf(1.0, pivot + dt * 5)
	var FRONT := L - BB_REAR
	var fx := x + cos(heading) * FRONT
	var fz := z - sin(heading) * FRONT
	var dh: float = signf(steer_input) * T.pivotRate * pivot * dt
	var n0 := floori(absf(pivot_acc) / PI)
	pivot_acc += dh
	course += dh; heading += dh
	x = fx - cos(heading) * FRONT; z = fz + sin(heading) * FRONT
	v = move_toward(v, 0.0, 10.0 * dt)
	yaw_rate = dh / dt
	var n1 := floori(absf(pivot_acc) / PI)
	if n1 > n0:
		host.flash("%d PIVOT!" % (n1 * 180))
		if n1 % 2 == 0: flow_up()

## Tyre grip sim (ground only). The bike's yaw against its travel (slip) is a real second-order motion:
## the rear tyre's sideways grip pulls it back in line, the front tyre (ahead of the centre of mass) pushes
## it further round, the rider catches it (countersteer + weight). The rear's sideways grip is what's left
## of its friction circle after braking / driving, times the load on it and the patch of ground under it:
## lock the rear and the front wins -> the rear swings out and fishtails until let go / caught; wheelspin
## steps it out in a turn; loose patches, bumps and pedal strokes keep nudging it so the bike never runs
## dead straight. Sets slip_w, grip_r, loose, _squirm, bar_catch; returns grip_r (0..~1.2).
## crash judge (see _risk): sev = how far past the line this step (<= 0 = within it). Builds over crashTime at sev 1
## (faster the further past), drains at riderSave /s once back under; a full meter or sev >= CRASH_HARD = the crash
func _danger(reason: String, sev: float, dt: float, t_build := -1.0) -> void:
	var r: float = float(_risk.get(reason, 0.0))
	if sev > 0.0 and absf(v) > 2.5:
		if sev >= float(T.get("crashHard", 3.0)): r = 1.0
		else: r += dt / maxf(0.05, t_build if t_build > 0.0 else float(T.get("crashTime", 0.4))) * sev * (0.5 + 0.5 * sev)
	else:
		r = maxf(0.0, r - dt * float(T.get("riderSave", 1.2)))
	_risk[reason] = r
	if r >= 1.0: _crash(reason)

## a crash this step: the first reason found is the one reported (later checks in the same step don't overwrite it)
func _crash(reason: String) -> void:
	if crash_pending == "": crash_pending = reason

## once a step, after every _danger: the biggest meter (risk) and a SAVED! when a real scare was fought off
func _risk_settle(dt: float) -> void:
	if air:   # (the ground-only checks don't run in the air: their meters drain there)
		for k in _risk: _risk[k] = maxf(0.0, float(_risk[k]) - dt * float(T.get("riderSave", 1.2)))
	risk = 0.0
	for k in _risk: risk = maxf(risk, float(_risk[k]))
	_risk_peak = maxf(_risk_peak, risk)
	if risk < 0.02:
		if _risk_peak > 0.5 and crash_pending == "" and not crash_on:
			if _crash_log: print("SAVED peak=%.2f v=%.1f" % [_risk_peak, v])   # tests (BMX_CRASH_LOG)
			if host.msg_idle(): host.flash("SAVED!")
			if host.has_method("on_style"): host.on_style(roundi(300.0 * _risk_peak), "SAVE")
		_risk_peak = 0.0

## the ground's sideways tilt under the bike (rad, + = rising to the right): the lay of the land (berms, cambers,
## wooden decks) WITHOUT the rock / log domes - a rock under one side read as a 30 deg berm and threw the lean about
## (the wheels still ride over the rock). Read across both axles, +-0.5 m, so a sharp trail edge isn't a sudden berm
func _bank_at(f: Vector3) -> float:
	var w := 0.5
	var lx := f.z * w
	var lz := -f.x * w
	var dh := 0.0
	for k in 2:   # front and rear axle
		var wo: float = L - BB_REAR if k == 0 else -BB_REAR
		var mx: float = x + f.x * wo
		var mz: float = z + f.z * wo
		dh += host.terrain.deck_height(mx - lx, mz - lz) - host.terrain.deck_height(mx + lx, mz + lz)
	return atan(dh * 0.5 / (2 * w))

## the sideways friction (force / normal) the tyres need for a horizontal turn a_lat (+ = left) on ground
## tilted bk (+ = rising to the right): 0 = the ground's tilt carries it all, + = the tyres push left
static func _fric(a_lat: float, cb: float, sb: float) -> float:
	return (a_lat * cb - G * sb) / maxf(0.2 * G, G * cb + a_lat * sb)

func _grip_step(dt: float, va: float, mu: float, nR: float, u_lat_in: float) -> float:
	if _grip_noise == null:
		_grip_noise = FastNoiseLite.new()
		_grip_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_grip_noise.frequency = 0.22; _grip_noise.fractal_octaves = 2; _grip_noise.seed = 913
		_grip_rng.seed = 4711
	var spd := smooth01((va - 1.0) / 5.0)
	# the ground under the rear tyre: loose patches a few metres across (gravel, dust over hardpack)
	var rx := x - cos(heading) * BB_REAR
	var rz := z + sin(heading) * BB_REAR
	var s_loose: float = 1.0 if surf_r == 0 else 0.2 if surf_r == 1 else 0.7 if surf_r == 2 else 1.4
	var n := 0.5 + 0.5 * _grip_noise.get_noise_2d(rx, rz)
	loose = smooth01((n - 0.4) / 0.45) * s_loose
	var patch: float = 1.0 - float(T.get("gripLoose", 0.5)) * 0.4 * loose
	# the rear tyre's friction circle: what braking / driving uses along the bike isn't there sideways
	var lock: float = rear_lock   # the rear brake past what the tyre holds (the brakes, longitudinal step)
	var r_cap := maxf(0.3, mu * nR)
	var use := clampf(_a_rear / r_cap, 0.0, 1.0)   # its own drive / brake only (the front brake is the front's)
	use = maxf(use, lock)
	if spin > 0.0: use = maxf(use, 0.85 + 0.15 * spin)
	var lat_k := sqrt(maxf(0.0, 1.0 - use * use))
	lat_k = lerpf(lat_k, 0.12, lock)   # a sliding tyre still drags a little sideways
	var load_r := clampf(nR / (G * SH_R), 0.0, 1.4)   # a light rear (bumps, nose-heavy braking) grips less
	var g := clampf(lat_k * patch * sqrt(load_r), 0.0, 1.2)
	grip_r = g
	# tyre squirm: in a turn the tyres run a few degrees of slip angle, more as they near the limit
	var u_lat := clampf(u_lat_in, -1.0, 1.0)   # + = the tyres pushing left (a left turn, or holding up a slope falling right)
	var a_lat := u_lat   # (only its sign is used below: which way the rear is thrown)
	_squirm = float(T.get("gripSquirm", 1.0)) * (0.025 * u_lat + 0.07 * u_lat * u_lat * u_lat) * spd * (1.0 + 0.5 * loose)
	# yaw against the travel: rear tyre stiffness vs the front pushing it round, the rider catching it
	var catch_r: float = float(T.get("gripCatch", 0.6))
	var k_r := 15.0 * g
	# (the front can only swing the rear round with sideways grip it has left: braking hard on it too, it has
	# little, so a locked rear behind a braking front stays nearly in line - why both brakes together are stable)
	var k_f: float = 18.0 * float(T.get("gripRearLock", 1.0)) * spd * _circ_f
	var k := k_r - k_f + 4.0 * catch_r
	var c := 2.2 + 3.0 * g + 1.5 * catch_r
	var acc := -k * (sin(slip) - _squirm) - c * slip_w
	# wheelspin in a turn: the spinning rear is thrown out of the turn
	var pw: float = float(T.get("gripPower", 1.0))
	acc += pw * spin * signf(a_lat) * 6.0 * spd
	# pedal strokes on loose ground: each stamp nudges the rear (alternating sides)
	acc += pw * sin(crank * 2.0) * clampf(a_drive / r_cap, 0.0, 1.0) * (1.25 - minf(1.0, g)) * 3.0 * spd
	slip_w += acc * dt
	# bumps: rough ground (suspension working hard, smoothed over ~0.2 s) makes a rear that's cornering near
	# its limit drift out of the turn - a gentle push, never a kick (instant kicks per rock made the bike
	# twitch about on rocky ground). The bump's real effect is already in load_r: an unloaded rear grips less
	# weight over the outside pedal keeps the rear planted over bumps; hanging inside it skips about more
	var bmp: float = float(T.get("gripBumps", 1.0)) * (1.0 - float(T.get("weightSteady", 0.5)) * maxf(0.0, weight_in) + 0.5 * maxf(0.0, -weight_in))
	var jolt := minf(absf(compress_v - _grip_cv) / maxf(dt, 1e-4), 60.0)
	_grip_cv = compress_v
	_grip_rough += (jolt - _grip_rough) * minf(1.0, dt * 5.0)
	var lim_k := smooth01((absf(u_lat) - 0.5) / 0.5)   # only near the grip limit
	slip_w += bmp * signf(a_lat) * lim_k * minf(_grip_rough / 30.0, 1.0) * 1.2 * spd * dt
	# chatter: pebbles, ruts - a small smooth random wander, bigger on loose ground / sliding
	slip_w += bmp * _grip_rng.randfn(0.0, 1.0) * sqrt(dt) * spd * (0.1 + 0.45 * loose + 0.8 * (1.0 - minf(1.0, g)))
	slip_w = clampf(slip_w, -4.0, 4.0)
	# drawn: the rider steers into the slide (front pointing along the travel) - catch strength sets how much
	var bc := clampf(-(slip - _squirm) * (0.5 + 0.4 * catch_r) - slip_w * 0.06, -0.55, 0.55) * spd
	bar_catch += (bc - bar_catch) * minf(1.0, dt * 14.0)
	return g

func _local_slope(f: Vector3, xx: float, R: float, cp0: float) -> float:
	return atan((_wheel_ground(f, xx + 0.05 / cp0, R, cp0) - _wheel_ground(f, xx - 0.05 / cp0, R, cp0)) / 0.1)

func flow_up() -> void:
	flow = minf(FLOW_MAX, floorf(flow) + 1); flow_t = 0

## Every float field finite? (the frame loop's safety net)
func is_sane() -> bool:
	for k in ["x", "z", "y", "vy", "v", "heading", "pitch", "pitch_v", "lean", "lean_v", "steer", "steer_in", "steer_in_v", "slip", "slip_w", "course", "compress", "compress_v",
			"body_x", "body_xv", "hip_shift", "hip_v", "air_lean", "air_pull", "a_drive",
			"body_y", "body_v", "air_w", "air_tilt", "air_tilt_v", "bike_lean", "counter", "flick", "flick_v", "man_a", "man_w", "bank", "corner_g"]:
		if not is_finite(get(k)):
			return false
	return true

## after a bad step: zero the body / rider state so a NaN there can't keep poisoning the ride
func reset_body() -> void:
	body_v = 0; body_y = y; body_x = 0; body_xv = 0; hip_shift = 0; hip_v = 0; v_last = NAN
	air_lean = 0; air_pull = 0; a_drive = 0; pitch_v = 0; compress_v = 0; lean_v = 0; steer_in_v = 0
	air_w = 0; air_tilt = 0; air_tilt_v = 0; flick = 0; flick_v = 0; bike_lean = 0; counter = 0
	man_a = 0.0; man_w = 0.0; bank = 0.0; bank_v = 0.0; corner_g = 0.0
	nose_a = 0.0; nose_w = 0.0; gest_hop = 0.0; _hop_buf = 0.0; _pop_miss = 0.0
	# (is_sane checks slip_w / steer_in too: left NaN they failed every later step and froze the bike until a respawn)
	slip_w = 0.0; steer_in = 0.0; knock = 0.0; _gx_lean = 0.0; bank_lean = 0.0; bank_sq = 0.0; _bike_lead = 0.0
	_amax = 99.0; _amin = -99.0; yaw_rate = 0.0
