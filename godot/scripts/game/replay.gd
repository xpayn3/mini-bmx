class_name ReplayMode
extends CanvasLayer
## Instant replay (I / pad L3 / pause > Replay): the whole ride (up to SECS, 6 min), played back with its own cameras.
##
## Nothing is simulated again. While riding, `capture()` (from Game._process, after the bike + rider are posed)
## stores what is DRAWN, HZ times a second: the local transform + visibility of every Node3D of the bike and the
## rider (the rider's own transform in the world: in a crash it hangs off the Game, not the bike), every bone of
## the rider's skeletons, and the small MultiMeshes (the chain's links). Playback (`update()`, the ride frozen at
## time_scale 0 like photo mode) puts them back, interpolated between two samples, so it can run at any speed,
## backwards, paused, and scrubbed. Leaving puts the live state back (`_snap`) and the ride carries on.
##
## A "segment" = one fixed list of nodes; the bike / rider gaining or losing a node (a crash tearing the action cam
## off, a limb, a respawn of the cam...) starts a new one (`_dirty`, from the tree's node_added / node_removed).
## Two samples are only blended inside one segment and when the bike didn't jump (a reset to the trail).
##
## Not recorded (stay as they are now): dust / smoke, mud, tyre tracks,
## and the world (torn tape, smashed fences). The rider's cloth sims (race number, hair, helmet flap, strap tails) are
## stepped by the replay itself with the replay's own time (they see dt 0 while the ride is frozen).
##
## Cameras (C / pad Y): TV (trackside cuts, zoomed on the rider: it knows where he goes next), Chase, Side, Orbit,
## Drone. Mouse drag / right stick looks round, wheel / triggers zoom.
## Tests: BMX_REPLAY=secs opens it (main.gd), BMX_REPLAY_SET=cam=Side,speed=0.5,at=-8,pause=1,
## BMX_REPLAY_SHOTS=dir/prefix (a shot every 0.5 s of real time), BMX_REPLAY_CLOSE=secs, BMX_REPLAY_PROBE=1
## (`REPLAY` lines: frames, nodes, memory, capture / apply cost).

const HZ := 30.0
const SECS := 360.0           # the whole ride, up to 6 min (a respawn / new world starts a new one)
const JUMP := 4.0             # m between two samples = a teleport (reset, respawn): not blended
const CAMS := ["TV", "Chase", "Side", "Orbit", "Detail", "Drone", "Free"]
const SPEEDS := [0.1, 0.25, 0.5, 1.0, 2.0]
const SCRUB := 3.0            # s of replay per s held (rewind / fast forward)
const ST := 13                # floats per node: basis (9) + origin (3) + visible
const BW := 12                # floats per bone: its whole pose (basis + origin)
const SKIP := -12345.0        # first float of a skeleton that wasn't there
const OPEN_BACK := 10.0       # the replay opens this many seconds before the end

var game
var on := false
var frames: Array = []        # [t, seg, data, m (moving nodes stored), focus, fwd, kmh, flags, sound row (`AROW`)]
var aev: Array = []           # one-shot sounds as they played: [t, kind, args] (RideAudio._rec)
var dev: Array = []           # dust bursts as they happened: [t, target ("sim" / "dust"), method, args]
var _dfeed: Array = [[], []]  # the latest rear / front tyre dust feed (RideDust.feed / feed_front args), per sample
const DROW := 9               # frames[DROW] = [rear feed, front feed]; frames[DROW + 1] = fx.t (tyre tracks' clock)
## what the ride sound reads from the physics, per sample: speed, air, crashed, surface, skid, pedal key, pedal, cranks
const AROW := 8
var _astate := AudioState.new()
class AudioState:
	var v := 0.0; var air := false; var crash_on := false; var surf := 0; var skid_fx := false
	var throttle_in := 0.0; var pedal := 0.0; var crank := 0.0; var RWR := 0.36
var _seg = null               # the segment being recorded
var _dirty := true
var _last_t := -1e9
var _snap = null              # the live state when the replay opened: [nodes, transforms, visible, glob, skeleton poses]
var _ap_seg = null            # what the last _apply left on the nodes (only moving ones are set each frame)
var _ap_m := 0
var _marks: Array = []        # timeline marks: [kind (1 crash, 2 air), from, to] (kept as recorded: a 6 min ride has ~11k samples)
var _mk_open := {}            # kind -> the mark still open
var _marks_dirty := false
var _hidden: Array = []       # [node, was_visible] hidden while playing (HUD bits)
var _sims: Array = []         # cloth sims under the rider, stepped by the replay (they see dt 0 while frozen)
const SIM_SCRIPTS := ["back_number.gd", "hair.gd", "helmet_flap.gd", "strap_tail.gd"]
var viewer := false           # playing a replay loaded from disk (the ride was rebuilt only to show it)
var info := {}                # a loaded replay's header (seed, bike, date...)
var status := ""              # "SAVED ..." under the bar for a moment
var _status_t := 0.0
var _save_task := -1
var probe := Env.s("BMX_REPLAY_PROBE") != ""
var _cap_us := 0; var _cap_n := 0; var _app_us := 0; var _app_n := 0

# playback
var tp := 0.0                 # the playhead (recording time)
var playing := true
var speed_i := 3
var cam_i := 0
var ui_on := true
var cam3: Camera3D
var bar: Control
var style_ui: StyleInspector   # T: what the rider's style did (clip layers, events, channels, state)
var hint: PadGlyph.PromptBar
var _hint_pad := false
var _last_us := 0
var _held := 0.0              # how long rewind / forward has been held (s, signed)
var _drag_tl := false
var _drag_look := false
var _was_playing := true
var _yaw := 0.0               # the player's look offset (drag / right stick)
var _pitch := 0.0
var _zoom := 1.0
var _orbit := 0.0
var _cpos := Vector3.ZERO     # camera position / aim, smoothed
var _caim := Vector3.ZERO
var _cfov := 40.0
var _snap_cam := true
var _fwd_s := Vector3(1, 0, 0)
var _shot = null              # TV: [pos, t0, index]
var _shot_n := 0
var _shots_t := 0.0
var _shots_i := 0
var _focus_now := Vector3.ZERO
var _free_pos := Vector3.ZERO   # Free camera: flies anywhere (real time, paused or playing)
var _free_yaw := 0.0
var _free_pitch := 0.0
var _free_fov := 55.0
var _free_init := false
const FREE_SPEED := 6.0         # m/s to start with (the wheel with right mouse held changes it; Shift x3, Alt x0.3)
const FREE_RANGE := 600.0       # m from the replayed rider (the world streams in round the camera)
var _free_speed := FREE_SPEED
var _free_roll := 0.0           # tilt (Dutch angle): LB / RB, Z / X; R / R3 levels it
var _free_vel := Vector3.ZERO
var _rmb := false               # right mouse held: mouselook
var _mmb := false               # middle mouse held: pan
var _orbiting := false          # Alt + left drag: orbit
var _pan_d := Vector2.ZERO
var _orbit_d := Vector2.ZERO
var _dolly_d := 0.0

func _init(g) -> void:
	game = g
	layer = 9
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	get_tree().node_added.connect(_tree_changed)
	get_tree().node_removed.connect(_tree_changed)
	bar = Bar.new()
	bar.rp = self
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bar)
	style_ui = StyleInspector.new()
	style_ui.rp = self
	add_child(style_ui)
	hint = PadGlyph.PromptBar.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -38; hint.offset_bottom = -4
	hint.h = 22; hint.label_size = 13
	add_child(hint)

func _tree_changed(n: Node) -> void:
	if _dirty or on or not (n is Node3D): return
	if (game.rider and (n == game.rider or game.rider.is_ancestor_of(n))) or (game.rig and game.rig.is_ancestor_of(n)):
		_dirty = true
	elif game.flying_cam != null and is_instance_valid(game.flying_cam) and (n == game.flying_cam or game.flying_cam.is_ancestor_of(n)):
		_dirty = true

## forget everything (a respawn / new world: the old ride is somewhere else)
## a one-shot sound while riding (RideAudio._rec): kept to play again at the same moment of the replay
func audio_event(kind: String, args: Array) -> void:
	if on: return
	aev.append([game.t - _t_off, kind, args])

## the dust (RideDust / SmokeSim recorders): a tyre's feed is a state kept per sample, bursts are events
func dust_feed(which: int, args: Array) -> void:
	if not on: _dfeed[which] = args

func dust_event(target: String, method: String, args: Array) -> void:
	if not on: dev.append([game.t - _t_off, target, method, args])

func clear() -> void:
	frames = []
	aev = []
	dev = []
	snaps = []
	_t_off = 0.0
	_marks.clear()
	_mk_open.clear()
	_seg = null
	_dirty = true
	_last_t = -1e9

func duration() -> float:
	return 0.0 if frames.size() < 2 else float(frames[-1][0]) - float(frames[0][0])

func ready_to_play() -> bool:
	return duration() >= 1.0

# ---- recording ------------------------------------------------------------------------------------------------

## the roots and what's under them: rig (not the rider: he is his own root, kept in world space), rider, the
## torn-off action cam. Top-level sims under them (hair, straps) are left out (their meshes are in the world; the
## replay steps them itself). Every node's transform + visibility at the segment's start is its `base`; only nodes
## that have moved since (`moving`, append-only, in the order they first moved) are stored per sample.
func _build_seg() -> Dictionary:
	var nodes: Array = []
	var glob := PackedByteArray()
	var skels: Array = []
	var roots: Array = []
	if game.rig: roots.append(game.rig)
	if game.rider: roots.append(game.rider)
	if game.flying_cam != null and is_instance_valid(game.flying_cam) and game.flying_cam is Node3D: roots.append(game.flying_cam)
	for r in roots:
		nodes.append(r); glob.append(1)
		_walk(r, nodes, glob, skels)
	# each node as root + one step per level ("1/Helmet/#MeshInstance3D:2"), as the tree is NOW: a saved replay finds
	# them again on a ride built the same way. A real name is kept; a generated one ("@MeshInstance3D@123", different
	# every run) becomes its place among its unnamed siblings of the same class
	var paths := PackedStringArray()
	for n in nodes: paths.append(_ipath(roots, n))
	var bones := PackedInt32Array()
	var nb := 0
	for sk in skels:
		bones.append(sk.get_bone_count())
		nb += sk.get_bone_count()
	var base: Array[Transform3D] = []
	var base_v := PackedByteArray()
	var is_mov := PackedByteArray()
	var moving := PackedInt32Array()
	for i in nodes.size():
		var n: Node3D = nodes[i]
		base.append(n.global_transform if glob[i] == 1 else n.transform)
		base_v.append(1 if n.visible else 0)
		is_mov.append(1 if glob[i] == 1 else 0)
		if glob[i] == 1: moving.append(i)   # (the roots always move)
	return {"nodes": nodes, "glob": glob, "skels": skels, "bones": bones, "nbones": nb, "base": base, "base_v": base_v,
		"is_mov": is_mov, "moving": moving, "paths": paths}

static func _ipath(roots: Array, n: Node) -> String:
	var parts := PackedStringArray()
	var c := n
	while c != null and not roots.has(c):
		parts.append(_step_of(c))
		c = c.get_parent()
	if c == null: return ""
	parts.append(str(roots.find(c)))
	parts.reverse()
	return "/".join(parts)

static func _step_of(c: Node) -> String:
	var nm := String(c.name)
	if not nm.begins_with("@"): return nm
	var cls := c.get_class()
	var k := 0
	for sib in c.get_parent().get_children():
		if sib == c: break
		if String(sib.name).begins_with("@") and sib.get_class() == cls: k += 1
	return "#%s:%d" % [cls, k]

static func _from_ipath(roots: Array, p: String) -> Node:
	if p == "": return null
	var parts := p.split("/")
	var ri := int(parts[0])
	if ri >= roots.size() or roots[ri] == null: return null
	var c: Node = roots[ri]
	for k in range(1, parts.size()):
		var st := parts[k]
		var nx: Node = null
		if st.begins_with("#"):
			var cp := st.substr(1).split(":")
			var want := int(cp[1]) if cp.size() > 1 else 0
			var j := 0
			for sib in c.get_children():
				if String(sib.name).begins_with("@") and sib.get_class() == cp[0]:
					if j == want: nx = sib; break
					j += 1
		else:
			for sib in c.get_children():
				if String(sib.name) == st: nx = sib; break
		if nx == null: return null
		c = nx
	return c

func _walk(n: Node, nodes: Array, glob: PackedByteArray, skels: Array) -> void:
	for c in n.get_children():
		if c == game.rider: continue   # (his own root)
		if not (c is Node3D) or (c as Node3D).top_level:
			continue
		nodes.append(c); glob.append(0)
		if c is Skeleton3D: skels.append(c)
		_walk(c, nodes, glob, skels)

## one sample of what's drawn now, at ride time t (Game._process, after posing)
func capture(t: float) -> void:
	if on: return
	t -= _t_off   # (after a "ride from here" the recording carries on from that moment)
	if t < _last_t: clear()
	if t - _last_t < 1.0 / HZ - 1e-4: return
	var t0 := Time.get_ticks_usec()
	_last_t = t
	if _dirty or _seg == null:
		_seg = _build_seg()
		_dirty = false
	var d := _record(_seg)
	var st = game.phys
	var focus := _focus_live()
	var f: Vector3 = game.rig.global_basis.x if game.rig else Vector3(1, 0, 0)
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 1e-6 else Vector3(1, 0, 0)
	var flags := (1 if st.crash_on else 0) | (2 if st.air else 0)
	var arow := PackedFloat32Array([st.v, 1.0 if st.air else 0.0, 1.0 if st.crash_on else 0.0, float(st.surf), 1.0 if st.skid_fx else 0.0,
		float(st.throttle_in), float(st.pedal), float(st.crank)])
	frames.append([t, _seg, d, (_seg.moving as PackedInt32Array).size(), focus, f, absf(st.v) * 3.6, flags, arow,
		[_dfeed[0], _dfeed[1]], float(game.fx.t) if game.fx else 0.0, game.style_row.duplicate(), game.style_names])
	if float(frames[-1][0]) - float(frames[0][0]) > SECS + 5.0:   # (trimmed in batches: pop_front shifts the whole list)
		var cut := _at(float(frames[-1][0]) - SECS)
		frames = frames.slice(cut)
		var t_lo := float(frames[0][0])
		aev = aev.filter(func(ev): return float(ev[0]) >= t_lo)
		dev = dev.filter(func(ev): return float(ev[0]) >= t_lo)
		_marks_dirty = true
	_mark_add(frames[-1])
	if probe:
		_cap_us += Time.get_ticks_usec() - t0; _cap_n += 1
		if _cap_n % 300 == 0: _print_probe()

func _focus_live() -> Vector3:
	var r = game.rider
	if r and r.skeleton:
		return r.global_transform * (r.skeleton.bone_rider("Hips") as Transform3D).origin
	return (game.rig.global_position if game.rig else Vector3.ZERO) + Vector3(0, 0.9, 0)

## the moving nodes (a node that moved for the first time joins them), then every bone
func _record(s: Dictionary) -> PackedFloat32Array:
	var nodes: Array = s.nodes
	var glob: PackedByteArray = s.glob
	var base: Array[Transform3D] = s.base
	var base_v: PackedByteArray = s.base_v
	var is_mov: PackedByteArray = s.is_mov
	var moving: PackedInt32Array = s.moving
	for ni in nodes.size():
		if is_mov[ni] == 1: continue
		var n = nodes[ni]
		if is_instance_valid(n) and (n.transform != base[ni] or (1 if n.visible else 0) != base_v[ni]):
			is_mov[ni] = 1
			moving.append(ni)
	s.is_mov = is_mov
	s.moving = moving
	var d := PackedFloat32Array()
	d.resize(moving.size() * ST + int(s.nbones) * BW)
	var i := 0
	for ni in moving:
		var n = nodes[ni]
		if is_instance_valid(n):
			var tr: Transform3D = n.global_transform if glob[ni] == 1 else n.transform
			var b := tr.basis
			d[i] = b.x.x; d[i + 1] = b.x.y; d[i + 2] = b.x.z
			d[i + 3] = b.y.x; d[i + 4] = b.y.y; d[i + 5] = b.y.z
			d[i + 6] = b.z.x; d[i + 7] = b.z.y; d[i + 8] = b.z.z
			d[i + 9] = tr.origin.x; d[i + 10] = tr.origin.y; d[i + 11] = tr.origin.z
			d[i + 12] = 1.0 if n.visible else 0.0
		else:
			d[i + 12] = -1.0
		i += ST
	var skels: Array = s.skels
	for si in skels.size():
		var sk = skels[si]
		var nb: int = s.bones[si]
		if is_instance_valid(sk) and sk.get_bone_count() == nb:
			for bi in nb:
				var tr: Transform3D = sk.get_bone_pose(bi)
				var b := tr.basis
				d[i] = b.x.x; d[i + 1] = b.x.y; d[i + 2] = b.x.z
				d[i + 3] = b.y.x; d[i + 4] = b.y.y; d[i + 5] = b.y.z
				d[i + 6] = b.z.x; d[i + 7] = b.z.y; d[i + 8] = b.z.z
				d[i + 9] = tr.origin.x; d[i + 10] = tr.origin.y; d[i + 11] = tr.origin.z
				i += BW
		else:
			d[i] = SKIP   # (marker: skip this skeleton)
			i += nb * BW
	return d

static func _tr(d: PackedFloat32Array, i: int) -> Transform3D:
	return Transform3D(Basis(Vector3(d[i], d[i + 1], d[i + 2]), Vector3(d[i + 3], d[i + 4], d[i + 5]), Vector3(d[i + 6], d[i + 7], d[i + 8])),
		Vector3(d[i + 9], d[i + 10], d[i + 11]))

static func _put(n: Node3D, glob: bool, tr: Transform3D, vis: bool) -> void:
	if glob: n.global_transform = tr
	elif n.transform != tr: n.transform = tr
	if n.visible != vis: n.visible = vis

## put sample `a` (blended k of the way to `b`, same segment) back onto the nodes. Nodes that hadn't moved yet at
## `a` get their base; only what can differ from the last apply is touched
func _apply(a: Array, b, k: float) -> void:
	var t0 := Time.get_ticks_usec()
	var s: Dictionary = a[1]
	var nodes: Array = s.nodes
	var glob: PackedByteArray = s.glob
	var base: Array[Transform3D] = s.base
	var base_v: PackedByteArray = s.base_v
	var moving: PackedInt32Array = s.moving
	var d: PackedFloat32Array = a[2]
	var ma: int = a[3]
	var blend: bool = b != null and k > 0.001
	var d2: PackedFloat32Array = b[2] if blend else PackedFloat32Array()
	var mb: int = b[3] if blend else ma
	if _ap_seg != s:   # a new segment: every node to its base first
		for ni in nodes.size():
			if is_instance_valid(nodes[ni]): _put(nodes[ni], glob[ni] == 1, base[ni], base_v[ni] == 1)
		_ap_seg = s
		_ap_m = 0
	elif _ap_m > mb:   # (scrubbed back to before some nodes first moved: those go back to their base)
		for j in range(mb, _ap_m):
			var nj: int = moving[j]
			if is_instance_valid(nodes[nj]): _put(nodes[nj], glob[nj] == 1, base[nj], base_v[nj] == 1)
	_ap_m = mb
	for j in mb:
		var ni: int = moving[j]
		var n = nodes[ni]
		if not is_instance_valid(n): continue
		var i := j * ST
		var tr: Transform3D
		var vis: bool
		if j < ma:
			if d[i + 12] < 0.0: continue
			tr = _tr(d, i)
			vis = d[i + 12] > 0.5
		else:   # (still at its base in a, moving in b)
			tr = base[ni]
			vis = base_v[ni] == 1
		if blend and d2[i + 12] >= 0.0:
			var tr2 := _tr(d2, i)
			if tr2 != tr: tr = tr.interpolate_with(tr2, k)
			if k >= 0.5: vis = d2[i + 12] > 0.5
		_put(n, glob[ni] == 1, tr, vis)
	var skels: Array = s.skels
	var i := ma * ST
	var i2 := mb * ST
	for si in skels.size():
		var sk = skels[si]
		var nb: int = s.bones[si]
		if d[i] != SKIP and is_instance_valid(sk) and sk.get_bone_count() == nb:
			# (the whole bone transform, blended element by element: the spine bones carry the torso's length and a skew,
			# which a rotation + scale blend would lose; two samples 1/30 s apart are close enough for a straight blend)
			var bl: bool = blend and d2[i2] != SKIP
			for bi in nb:
				var tr := _tr(d, i)
				if bl:
					var t2 := _tr(d2, i2)
					tr = Transform3D(Basis(tr.basis.x.lerp(t2.basis.x, k), tr.basis.y.lerp(t2.basis.y, k), tr.basis.z.lerp(t2.basis.z, k)), tr.origin.lerp(t2.origin, k))
				sk.set_bone_pose(bi, tr)
				i += BW; i2 += BW
			_fit_skin_boxes(sk)
		else:
			i += nb * BW; i2 += nb * BW
	# the chain redraws itself every frame from the replayed parts; it only needs the crank angle (BikeChain)
	if game.rig and game.rig.crank_n: game.rig.crank_angle = -game.rig.crank_n.rotation.z
	if probe:
		_app_us += Time.get_ticks_usec() - t0; _app_n += 1

## skinned meshes' culling boxes sit in the mesh's own space and were set for where the LIVE body is (Rider.set_spine,
## fingers); a replayed body can be elsewhere (a crash far back, a saved replay), so the torso got culled = "body missing".
## Box the bones' own spot each time they are replayed.
var _skin_meshes := {}
func _fit_skin_boxes(sk: Skeleton3D) -> void:
	var key := sk.get_instance_id()
	if not _skin_meshes.has(key):
		var list: Array = []
		var par := sk.get_parent()
		if par:
			for c in par.get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).skeleton != NodePath() and c.get_node_or_null((c as MeshInstance3D).skeleton) == sk:
					list.append(c)
		_skin_meshes[key] = list
	var list2: Array = _skin_meshes[key]
	var n := sk.get_bone_count()
	if list2.is_empty() or n == 0: return
	var ctr := Vector3.ZERO
	for bi in n: ctr += sk.get_bone_pose(bi).origin
	ctr /= n
	for mi in list2:
		if is_instance_valid(mi): mi.custom_aabb = AABB(ctr - Vector3(3, 3, 3), Vector3(6, 6, 6))

## the live state (to put back on leaving): every node of a fresh segment + the bones
func _live() -> Array:
	var s := _build_seg()
	var poses: Array = []
	for sk in s.skels:
		var pp: Array = []
		for bi in sk.get_bone_count(): pp.append(sk.get_bone_pose(bi))
		poses.append(pp)
	return [s, poses, game.rig.crank_angle if game.rig else 0.0]

func _restore(l: Array) -> void:
	var s: Dictionary = l[0]
	for ni in s.nodes.size():
		if is_instance_valid(s.nodes[ni]): _put(s.nodes[ni], s.glob[ni] == 1, s.base[ni], s.base_v[ni] == 1)
	for si in s.skels.size():
		var sk = s.skels[si]
		if not is_instance_valid(sk) or sk.get_bone_count() != (l[1][si] as Array).size(): continue
		for bi in sk.get_bone_count():
			sk.set_bone_pose(bi, l[1][si][bi])
	if game.rig: game.rig.crank_angle = l[2]

func _mark_add(f: Array) -> void:
	if _marks_dirty:
		_marks_dirty = false
		var t_lo := t0()
		_marks = _marks.filter(func(m): return float(m[2]) >= t_lo)
	var fl: int = f[7]
	for kind in [1, 2]:
		if (fl & kind) != 0:
			var m = _mk_open.get(kind)
			if m == null:
				m = [kind, f[0], f[0]]
				_marks.append(m)
				_mk_open[kind] = m
			else:
				m[2] = f[0]
		else:
			_mk_open.erase(kind)

static func clock(secs: float) -> String:
	var a := absf(secs)
	return "%s%d:%04.1f" % ["-" if secs < 0.0 else "", int(a) / 60, fmod(a, 60.0)] if a >= 60.0 else "%.1f s" % secs

func mem_bytes() -> int:
	var bytes := 0
	for f in frames: bytes += (f[2] as PackedFloat32Array).size() * 4
	return bytes

func _print_probe() -> void:
	var nn: int = _seg.nodes.size() if _seg else 0
	var mb := mem_bytes() / 1048576.0
	print("REPLAY frames=%d secs=%.1f nodes=%d moving=%d bones=%d mem=%.2f MB (%.2f MB/min) capture_us=%.0f apply_us=%.0f" % [frames.size(), duration(), nn,
		(_seg.moving as PackedInt32Array).size() if _seg else 0, int(_seg.nbones) if _seg else 0, mb, mb / maxf(duration() / 60.0, 0.01),
		float(_cap_us) / maxf(_cap_n, 1), float(_app_us) / maxf(_app_n, 1)])

# ---- saved replays (%APPDATA%\\Mini BMX\\replays) -----------------------------------------------------------------

const VER := 5
static func dir() -> String:
	# (test runs write beside the player's, never into the list)
	return "user://replays/tests/" if Settings._no_save else "user://replays/"

## write the recording to disk: a header (what to rebuild: seed, bike + build, rider look + pose, level) then the
## segments (node paths, bases) and the samples. Built here, compressed + written on a worker
func save() -> String:
	if frames.size() < 2 or viewer: return ""
	DirAccess.make_dir_recursive_absolute(dir())
	var path := dir() + "ride_%s.replay" % Time.get_datetime_string_from_system().replace(":", "-")
	var segs: Array = []
	var seg_i := {}
	var fr: Array = []
	var sty_sets: Array = []
	var sty_i := {}
	for f in frames:
		var sg: Dictionary = f[1]
		if not seg_i.has(sg):
			seg_i[sg] = segs.size()
			var base := PackedFloat32Array()
			for ni in sg.nodes.size():
				var tr: Transform3D = sg.base[ni]
				var b := tr.basis
				base.append_array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, tr.origin.x, tr.origin.y, tr.origin.z, float(sg.base_v[ni])])
			var sk_i := PackedInt32Array()
			for sk in sg.skels: sk_i.append(sg.nodes.find(sk))
			segs.append({"paths": sg.paths, "glob": sg.glob, "base": base, "moving": sg.moving, "bones": sg.bones, "skel": sk_i})
		var si := -1   # the style row's names: one list per library state, shared between frames
		if f.size() > 12 and f[12] is PackedStringArray:
			if not sty_i.has(f[12]):
				sty_i[f[12]] = sty_sets.size()
				sty_sets.append(f[12])
			si = sty_i[f[12]]
		fr.append([f[0], seg_i[sg], f[2], f[3], f[4], f[5], f[6], f[7], f[AROW] if f.size() > AROW else PackedFloat32Array(),
			f[DROW] if f.size() > DROW else [[], []], f[11] if f.size() > 11 else PackedFloat32Array(), si])
	var st = game.phys
	var head := {"ver": VER, "date": Time.get_datetime_string_from_system(), "seed": GameState.seed, "bike": GameState.bike_id,
		"level": game.level, "build": game.bike_cfg.get("build", {}), "look": game.rider.look.duplicate(true) if game.rider else {},
		"pose": game.rider.style.duplicate(true) if game.rider else {}, "secs": duration(),
		"light": LightSettings.current.duplicate(true), "hour": game.tod}
	var body := {"segs": segs, "frames": fr, "aev": aev.duplicate(true), "dev": dev.duplicate(true), "sty_sets": sty_sets}
	if _save_task >= 0: WorkerThreadPool.wait_for_task_completion(_save_task)
	_save_task = WorkerThreadPool.add_task(func():
		var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		if f == null: return
		f.store_var(head)
		f.store_var(body)
		f.close())
	status = "SAVED · " + path.get_file().to_upper()
	_status_t = 4.0
	if probe: print("REPLAY saved %s segs=%d frames=%d" % [path, segs.size(), fr.size()])
	return path

func _exit_tree() -> void:
	if _save_task >= 0: WorkerThreadPool.wait_for_task_completion(_save_task); _save_task = -1

static func list_saved() -> Array:
	var out: Array = []
	var d := DirAccess.open(dir())
	if d == null: return out
	for fn in d.get_files():
		if fn.ends_with(".replay"): out.append(dir() + fn)
	out.sort()
	out.reverse()   # newest first (dated names)
	return out

static func read_header(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null: return {}
	var h = f.get_var()
	return h if h is Dictionary and int(h.get("ver", 0)) == VER else {}

static func read_file(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null: return {}
	var h = f.get_var()
	var b = f.get_var()
	if not (h is Dictionary and b is Dictionary) or int(h.get("ver", 0)) != VER: return {}
	return {"head": h, "body": b}

## put a saved replay on this ride's bike + rider (rebuilt from its header) and get ready to play it
func load_saved(rd: Dictionary) -> bool:
	var roots: Array = [game.rig, game.rider, null]
	var segs: Array = []
	var miss := 0
	for sd in rd.body.segs:
		var paths: PackedStringArray = sd.paths
		var nodes: Array = []
		var base: Array[Transform3D] = []
		var base_v := PackedByteArray()
		var bd: PackedFloat32Array = sd.base
		for ni in paths.size():
			var n := _from_ipath(roots, paths[ni])
			if not (n is Node3D):
				if probe and miss < 40: print("REPLAY missing %s" % paths[ni])
				n = null; miss += 1
			nodes.append(n)
			base.append(_tr(bd, ni * ST))
			base_v.append(1 if bd[ni * ST + 12] > 0.5 else 0)
		var skels: Array = []
		var nbt := 0
		for k in (sd.skel as PackedInt32Array).size():
			var si: int = sd.skel[k]
			skels.append(nodes[si] if si >= 0 and nodes[si] is Skeleton3D else null)
			nbt += int(sd.bones[k])
		segs.append({"nodes": nodes, "glob": sd.glob, "skels": skels, "bones": sd.bones, "nbones": nbt, "base": base, "base_v": base_v,
			"is_mov": PackedByteArray(), "moving": sd.moving, "paths": paths})
	if probe:   # parts that never move: the rebuilt one should sit where the saved one did (else: matched wrong)
		for sg in segs.slice(0, 1):
			var mv := {}
			for q in sg.moving: mv[q] = true
			for ni in sg.nodes.size():
				var n = sg.nodes[ni]
				if n == null or mv.has(ni) or sg.glob[ni] == 1: continue
				var bt: Transform3D = sg.base[ni]
				var lt: Transform3D = n.transform
				if bt.origin.distance_to(lt.origin) > 0.002 or (bt.basis.get_scale() - lt.basis.get_scale()).length() > 0.01:
					print("REPLAY static differs %s %s saved o=%s s=%s now o=%s s=%s" % [sg.paths[ni], n.get_class(), str(bt.origin), str(bt.basis.get_scale()), str(lt.origin), str(lt.basis.get_scale())])
	clear()
	var sty_sets: Array = rd.body.get("sty_sets", [])
	for f in rd.body.frames:
		var sn := PackedStringArray()
		if f.size() > 11 and int(f[11]) >= 0 and int(f[11]) < sty_sets.size(): sn = sty_sets[int(f[11])]
		frames.append([f[0], segs[int(f[1])], f[2], f[3], f[4], f[5], f[6], f[7], f[8] if f.size() > 8 else PackedFloat32Array(),
			f[9] if f.size() > 9 else [[], []], 0.0, f[10] if f.size() > 10 else PackedFloat32Array(), sn])
		_mark_add(frames[-1])
	aev = rd.body.get("aev", [])
	dev = rd.body.get("dev", [])
	viewer = true
	info = rd.head
	if probe: print("REPLAY loaded segs=%d frames=%d secs=%.1f missing_nodes=%d" % [segs.size(), frames.size(), duration(), miss])
	return frames.size() >= 2

# ---- playback --------------------------------------------------------------------------------------------------

func open() -> void:
	if on or not ready_to_play(): return
	on = true
	visible = true
	# the live state, to put back on leaving
	_snap = _live()
	_ap_seg = null
	_tracks_open()
	if game.dust and game.dust.sim: game.dust.sim.reset()
	_hidden.clear()
	# the rider's cloth sims (race number, hair, helmet flap, strap tails) step themselves in _process, which gets
	# dt 0 while time is frozen: the replay steps them with its own time instead, so they stay on the replayed body
	_sims.clear()
	if game.rider: _find_sims(game.rider)
	for n in [game.wasted, game.contact, game.cam.osd if game.cam else null, game.area_title.view if game.area_title else null]:
		if n != null and is_instance_valid(n): _hidden.append([n, n.visible]); n.visible = false
	if cam3 == null:
		cam3 = Camera3D.new()
		cam3.name = "ReplayCam"
		game.add_child(cam3)
	var c: Camera3D = game.cam
	cam3.attributes = c.attributes
	cam3.environment = c.environment
	cam3.compositor = c.compositor
	cam3.cull_mask = c.cull_mask
	cam3.near = c.near; cam3.far = c.far
	cam3.make_current()
	# the ride is frozen: spend the frame time on the picture (the garage's showcase quality), Settings back on leaving
	if Env.s("BMX_REPLAY_LOWQ") == "": Garage.showcase_quality(get_viewport(), true, false)
	# no live speed feel in a replay: the side blur / streaks (the ride sets them again every frame after)
	var gm := game.grade_rect.material as ShaderMaterial if game.grade_rect else null
	if gm:
		gm.set_shader_parameter("blur", 0.0)
		gm.set_shader_parameter("speed", 0.0)
	tp = maxf(float(frames[0][0]), float(frames[-1][0]) - OPEN_BACK)   # (the last moments; Home = the start)
	playing = true
	hl_on = false
	speed_i = 3
	_held = 0.0
	_yaw = 0.0; _pitch = 0.0; _zoom = 1.0
	_snap_cam = true
	_shot = null
	_last_us = Time.get_ticks_usec()
	_shots_t = 0.0
	if Env.s("BMX_REPLAY_SET") != "": _test_set(Env.s("BMX_REPLAY_SET"))
	_refresh_hint()
	# the world round where the replay starts, built now (it may be far from where the ride is)
	var f0 := focus_at(tp)
	game.terrain.update_stream(f0.x, f0.z, INF, 1)
	update(0.0)
	if probe: _print_probe()

func close() -> void:
	if not on: return
	if exporting: _export_end()
	on = false
	if game.audio: game.audio.src = null
	AudioServer.playback_speed_scale = 1.0
	if _rmb: _set_mouselook(false)
	_mmb = false; _orbiting = false
	visible = false
	if _snap != null:
		_restore(_snap)
		_snap = null
	_tracks_close()
	if game.dust and game.dust.sim: game.dust.sim.reset()
	_ap_seg = null
	for h in _hidden:
		if is_instance_valid(h[0]): h[0].visible = h[1]
	_hidden.clear()
	if game.cam: game.cam.make_current()
	if Env.s("BMX_REPLAY_LOWQ") == "":
		Garage.showcase_quality(get_viewport(), false)
		game._apply_settings()
	# streamed decorations fade round the rider again (Game._process sets it every frame from here)
	var st = game.phys
	game.terrain.update_stream(st.x, st.z, 4.0)
	if probe: _print_probe()

func _find_sims(n: Node) -> void:
	for c in n.get_children():
		var sc = c.get_script()
		if sc != null and String(sc.resource_path).get_file() in SIM_SCRIPTS: _sims.append(c)
		_find_sims(c)

func focus_now() -> Vector3: return _focus_now

## photo mode on this frame (O): the ride camera goes where the replay camera is, playback holds, the bar hides
func photo_begin() -> void:
	playing = false
	visible = false
	if _rmb: _set_mouselook(false)
	var c: Camera3D = game.cam
	c.global_transform = cam3.global_transform
	c.fov = cam3.fov
	c.make_current()
	if game.audio: game.audio.src = null

func photo_end() -> void:
	visible = true
	cam3.make_current()

# ---- ride from here (rewind) ----------------------------------------------------------------------------------

## every physics value of the bike (BikePhysics' own variables, as PlaygroundLab.fresh copies them), SNAP_HZ a
## second for the last SNAP_SECS: "ride from here" puts one back and the ride carries on from that moment
const SNAP_HZ := 4.0
const SNAP_SECS := 120.0
const SNAP_KEEP := ["host", "T", "L", "RWF", "RWR", "BB_REAR", "SH_R", "LAND", "geared", "cogs", "ring_k", "bike_rock", "distance", "bank_probe", "sus", "_sus_synced", "_su", "_sag_seen"]
var snaps: Array = []          # [t, crashed, values]
var _snap_keys := PackedStringArray()
var _t_off := 0.0              # ride time - recording time (grows by what a "ride from here" cut away)
var _snap_last := -1e9

func phys_snap() -> void:
	if on or viewer: return
	var ph = game.phys
	var t: float = game.t - _t_off
	if t - _snap_last < 1.0 / SNAP_HZ: return
	_snap_last = t
	if _snap_keys.is_empty():
		for p in ph.get_property_list():
			if not (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
			var k: String = p.name
			if k in SNAP_KEEP or typeof(ph.get(k)) == TYPE_OBJECT: continue
			_snap_keys.append(k)
	var vals: Array = []
	vals.resize(_snap_keys.size())
	for i in _snap_keys.size():
		var v = ph.get(_snap_keys[i])
		vals[i] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	snaps.append([t, ph.crash_on, vals, game._line_n])
	if snaps.size() > int(SNAP_SECS * SNAP_HZ) + 20: snaps = snaps.slice(20)

## the newest snapshot at or before the playhead that isn't in a crash
func _snap_at(t: float) -> Variant:
	for i in range(snaps.size() - 1, -1, -1):
		if float(snaps[i][0]) <= t + 1e-4 and not snaps[i][1]: return snaps[i]
	return null

func can_ride_from_here() -> bool:
	return not viewer and _snap_at(tp) != null

## Enter / pad X: leave the replay and ride on from the playhead (the nearest snapshot before it). What came after
## is dropped from the recording; the world (torn tape, smashed fences) stays as it is
func ride_from_here() -> void:
	var sn = _snap_at(tp)
	if sn == null or viewer:
		status = "NOTHING TO RIDE FROM HERE" if viewer else "TOO FAR BACK TO RIDE FROM"
		_status_t = 2.0
		return
	game.exit_replay()
	ride_from_snap(sn)
	game.line_truncate(int(sn[3]) if sn.size() > 3 else -1)
	game.line_stop()


## re-ride: the same, but the recorded inputs from there on are fed in again (L). The old tail of the line is kept for it
func reride_from_here() -> void:
	var sn = _snap_at(tp)
	if sn == null or viewer or sn.size() < 4 or not game.line_has(int(sn[3])):
		status = "NO RECORDED INPUTS FROM HERE"; _status_t = 2.0
		return
	var line: Dictionary = game.line_extract(int(sn[3]))
	game.exit_replay()
	ride_from_snap(sn)
	game.line_truncate(int(sn[3]))
	game.line_start(line, sn)


## put a snapshot's physics back and let the recording carry on from that moment (shared by ride from here / re-ride / restart)
func ride_from_snap(sn: Array) -> void:
	var ts: float = sn[0]
	game._end_crash()   # (crashed now: back on the bike first)
	var ph = game.phys
	var vals: Array = sn[2]
	for i in _snap_keys.size():
		var v = vals[i]
		ph.set(_snap_keys[i], v.duplicate(true) if (v is Array or v is Dictionary) else v)
	ph.crash_pending = ""
	game._reset_draw_state()
	if game.rider: game.rider.reset_pose()
	game._snap_prev()
	game.terrain.update_stream(ph.x, ph.z, INF, 1)
	# the recording carries on from that moment
	frames = frames.slice(0, _at(ts) + 1)
	aev = aev.filter(func(ev): return float(ev[0]) <= ts)
	dev = dev.filter(func(ev): return float(ev[0]) <= ts)
	snaps = snaps.filter(func(s): return float(s[0]) <= ts)
	_marks.clear(); _mk_open.clear()
	for f in frames: _mark_add(f)
	_mk_open.clear()
	_t_off += (game.t - _t_off) - ts
	_last_t = ts
	_snap_last = ts
	_dirty = true
	game.flash("RIDE ON")
	if probe: print("REPLAY ride from t=%.2f at (%.1f, %.1f, %.1f) v=%.1f crash=%s frames_left=%d snaps=%d" % [ts, ph.x, ph.y, ph.z, ph.v, ph.crash_on, frames.size(), snaps.size()])

# ---- clip export (a video file) -----------------------------------------------------------------------------------

## [ / ] set the clip's in / out on the timeline (Del clears them), V exports it: the replay is played through at an
## even EX_FPS frames a second of video, at the chosen speed (slow motion clips), on the current camera, with the bar
## hidden; every frame a JPEG into an AVI (AviWriter) in %APPDATA%\Mini BMX\videos. No in / out: the highlights
## (when on) or the 10 s from the playhead. No sound in the file (yet)
const EX_FPS := 30
const EX_Q := 0.9
var clip_in := -1.0
var clip_out := -1.0
var exporting := false
var _ex: AviWriter
var _ex_end := 0.0
var _ex_first := true
var _ex_path := ""
var _ex_hid: Array = []
var _ex_start := 0.0

static func video_dir() -> String:
	return "user://videos/tests/" if Settings._no_save else "user://videos/"

func export_clip() -> void:
	if exporting or frames.size() < 2: return
	var a := clip_in if clip_in >= 0.0 else tp
	var b := clip_out if clip_out > a else minf(t1(), a + 10.0)
	_ex_start = a
	if hl_on and clip_in < 0.0 and not _hl.is_empty(): a = float(_hl[0][0]); b = float(_hl[-1][1])
	if b - a < 0.2: return
	DirAccess.make_dir_recursive_absolute(video_dir())
	_ex_path = video_dir() + "clip_%s.avi" % Time.get_datetime_string_from_system().replace(":", "-")
	var vs := get_viewport().get_visible_rect().size
	_ex = AviWriter.new()
	if not _ex.open(_ex_path, int(vs.x), int(vs.y), EX_FPS):
		status = "COULDN'T WRITE THE VIDEO"; _status_t = 3.0
		return
	exporting = true
	_ex_first = true
	_ex_end = b
	tp = a
	if hl_on: _hl_i = 0
	playing = true
	_snap_cam = true; _shot = null
	if _rmb: _set_mouselook(false)
	# nothing but the picture: the replay bar, the corner fullscreen button
	_ex_hid.clear()
	for n in [bar, hint] + get_tree().root.find_children("*", "CanvasLayer", true, false).filter(func(c): return c.get_script() != null and String(c.get_script().resource_path).ends_with("fullscreen_button.gd")):
		_ex_hid.append([n, n.visible]); n.visible = false
	AudioServer.set_bus_mute(0, true)
	if probe: print("REPLAY export %s %.2f..%.2f %dx%d" % [_ex_path, a, b, int(vs.x), int(vs.y)])

## one video frame: grab what the last frame drew, then step the replay one frame of video
func _export_step() -> float:
	if not _ex_first:
		var img := get_viewport().get_texture().get_image()
		if img != null: _ex.add_jpeg(img.save_jpg_to_buffer(EX_Q))
	_ex_first = false
	status = "EXPORTING · %d FRAMES" % _ex.frames
	if tp >= _ex_end - 1e-4 or (hl_on and _hl_i == _hl.size() - 1 and tp >= float(_hl[-1][1]) - 1e-4):
		_export_end()
		return 0.0
	return 1.0 / EX_FPS

func _export_end() -> void:
	exporting = false
	var n := _ex.frames
	_ex.close()
	_ex = null
	for h in _ex_hid:
		if is_instance_valid(h[0]): h[0].visible = h[1]
	_ex_hid.clear()
	AudioServer.set_bus_mute(0, false)
	playing = false
	status = "VIDEO SAVED · %s (%.1f s)" % [_ex_path.get_file().to_upper(), n / float(EX_FPS)]
	_status_t = 5.0
	if probe or Env.s("BMX_REPLAY_EXPORT") != "": print("REPLAY exported %s frames=%d" % [_ex_path, n])

# ---- highlights ------------------------------------------------------------------------------------------------

## G / pad R3: only the moments worth watching, each from a little before to a little after (airs over HL_AIR s,
## crashes), cut with the TV camera; airs at half speed, a crash at a third round its start
const HL_AIR := 0.45
var hl_on := false
var _hl: Array = []            # [from, to, kind (1 crash / 2 air), crash time]
var _hl_i := 0

func _hl_build() -> void:
	var w: Array = []
	for m in _marks:
		var a := float(m[1]); var b := float(m[2])
		if int(m[0]) == 2 and b - a >= HL_AIR: w.append([a - 1.3, b + 1.0, 2, -1.0])
		elif int(m[0]) == 1: w.append([a - 2.2, a + 3.2, 1, a])
	w.sort_custom(func(x, y): return x[0] < y[0])
	_hl = []
	for x in w:
		x[0] = maxf(float(x[0]), t0()); x[1] = minf(float(x[1]), t1())
		if not _hl.is_empty() and float(x[0]) <= float(_hl[-1][1]):
			_hl[-1][1] = maxf(float(_hl[-1][1]), float(x[1]))
			if int(x[2]) == 1: _hl[-1][2] = 1; _hl[-1][3] = x[3]
		else: _hl.append(x)

func toggle_highlights() -> void:
	hl_on = not hl_on
	if hl_on:
		_hl_build()
		if _hl.is_empty():
			hl_on = false
			status = "NO HIGHLIGHTS YET (BIG AIRS, CRASHES)"; _status_t = 2.5
			return
		cam_i = CAMS.find("TV")
		_hl_i = 0
		_hl_jump(0)
		playing = true
	status = ("HIGHLIGHTS · %d MOMENTS" % _hl.size()) if hl_on else "WHOLE RIDE"
	if probe: print("REPLAY highlights on=%s %s" % [hl_on, str(_hl.map(func(w): return "%s %.1f..%.1f" % ["crash" if int(w[2]) == 1 else "air", float(w[0]) - t1(), float(w[1]) - t1()]))])
	_status_t = 2.0
	_refresh_hint()

func _hl_jump(i: int) -> void:
	_hl_i = i % _hl.size()
	tp = float(_hl[_hl_i][0])
	_shot = null
	_snap_cam = true

## inside a highlight: the slow motion there; past its end: the next one (round again after the last)
func _hl_rate() -> float:
	if not hl_on or _hl.is_empty(): return 1.0
	var w: Array = _hl[_hl_i]
	if tp > float(w[1]) or tp < float(w[0]) - 0.05:
		var nxt := _hl_i + 1
		for j in _hl.size():
			if float(_hl[j][0]) > tp - 0.01 and tp <= float(_hl[j][1]): nxt = j; break
		_hl_jump(nxt if tp > float(w[1]) else _hl_i)
		w = _hl[_hl_i]
	if int(w[2]) == 1 and tp >= float(w[3]) - 0.5 and tp <= float(w[3]) + 2.0: return 0.35
	if (int(frames[_at(tp)][7]) & 2) != 0: return 0.55
	return 1.0

## index of the last sample at or before t
func _at(t: float) -> int:
	var lo := 0
	var hi := frames.size() - 1
	if t <= float(frames[0][0]): return 0
	if t >= float(frames[hi][0]): return hi
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if float(frames[mid][0]) <= t: lo = mid
		else: hi = mid
	return lo

func _frame_k(t: float) -> Array:
	var i := _at(t)
	var a: Array = frames[i]
	if i + 1 >= frames.size(): return [a, null, 0.0]
	var b: Array = frames[i + 1]
	var dt := float(b[0]) - float(a[0])
	if b[1] != a[1] or dt <= 0.0 or (a[4] as Vector3).distance_to(b[4]) > JUMP: return [a, null, 0.0]
	return [a, b, clampf((t - float(a[0])) / dt, 0.0, 1.0)]

func focus_at(t: float) -> Vector3:
	var fk := _frame_k(t)
	if fk[1] == null: return fk[0][4]
	return (fk[0][4] as Vector3).lerp(fk[1][4], fk[2])

func fwd_at(t: float) -> Vector3:
	var fk := _frame_k(t)
	if fk[1] == null: return fk[0][5]
	return (fk[0][5] as Vector3).lerp(fk[1][5], fk[2]).normalized()

func t0() -> float: return float(frames[0][0]) if frames.size() > 0 else 0.0
func t1() -> float: return float(frames[-1][0]) if frames.size() > 0 else 0.0

## real-time step while the replay is up (Game._process, the ride frozen)
func update(rdt: float) -> void:
	if not on or frames.size() < 2: return
	if exporting:   # (an even video frame step, whatever the real frame time)
		rdt = _export_step()
		if rdt <= 0.0: rdt = 1.0 / EX_FPS
	else:
		_poll(rdt)
	if _status_t > 0.0:
		_status_t -= rdt
		if _status_t <= 0.0: status = ""
	var prev_tp := tp
	var scrubbing := absf(_held) >= TAP and not exporting
	if scrubbing:
		# (held longer = faster: 3x, doubling every 0.6 s up to 48x, so a 6 min ride is crossed in seconds)
		tp += signf(_held) * SCRUB * pow(2.0, clampf((absf(_held) - TAP) / 0.6, 0.0, 4.0)) * rdt
	elif _held != 0.0:
		pass   # (maybe a tap: decided on release)
	elif playing and not _drag_tl:
		tp += rdt * SPEEDS[speed_i] * _hl_rate()
	if tp > t1():
		if playing and not scrubbing and not _drag_tl:
			tp = t0(); _shot = null; _snap_cam = true   # loop
		else: tp = t1()
	if tp < t0(): tp = t0()
	if absf(tp - prev_tp) > 1.0: _snap_cam = true
	var fk := _frame_k(tp)
	_apply(fk[0], fk[1], fk[2])
	_focus_now = focus_at(tp)
	_sound(prev_tp, rdt, fk)
	_dust(prev_tp, fk)
	_tracks(fk)
	if probe: _vis_probe()
	# (as much sim time as the replay moved, so slow motion is slow for the paper too; a little while paused so it
	# settles on the body; a big jump resets them by itself)
	var sdt := clampf(absf(tp - prev_tp), 0.002, 1.0 / 30.0)
	for sm in _sims:
		if is_instance_valid(sm): sm._process(sdt)
	# the world round the replayed rider: chunks, the decoration fade band
	# (Free: round the camera, which may be far from him)
	var sc: Vector3 = cam3.global_position if (CAMS[cam_i] == "Free" and cam3 != null and _free_init) else _focus_now
	game.terrain.update_stream(sc.x, sc.z, 4.0)
	RenderingServer.global_shader_parameter_set("deco_fade", Vector4(sc.x, sc.z, game._deco_band.x, game._deco_band.y))
	if game.far_hills: game.far_hills.follow(sc)
	_camera(rdt)
	bar.visible = ui_on and not exporting
	hint.visible = ui_on and not exporting
	if _hint_pad != Settings.pad_active: _refresh_hint()
	bar.queue_redraw()
	if style_ui.visible: style_ui.queue_redraw()
	if Env.s("BMX_REPLAY_SHOTS") != "":   # tests: a shot every 0.5 s of real time
		_shots_t += rdt
		if _shots_t >= 0.5 and _shots_i < 16:
			_shots_t = 0.0
			var path := "%s_%02d.png" % [Env.s("BMX_REPLAY_SHOTS"), _shots_i]
			get_viewport().get_texture().get_image().save_png(path)
			print("REPLAYSHOT %s tp=%.2f cam=%s speed=%.2f kmh=%.0f fps=%.0f tracks_hidden=%d dust_events=%d sound_events=%d" % [path, tp - t1(), CAMS[cam_i], SPEEDS[speed_i], _kmh_at(tp), Engine.get_frames_per_second(), _trk_hid, dev.size(), aev.size()])
			_shots_i += 1
			if viewer and _shots_i >= int(Env.s("BMX_REPLAY_NSHOTS") if Env.s("BMX_REPLAY_NSHOTS") != "" else "16"): game.exit_replay()   # (tests: BMX_REPLAY_WATCH)

## the ride sound follows the replay: playing forwards it hears the recorded state (interpolated) and the one-shots
## whose moment the playhead just crossed; slow motion slows and lowers the whole mix (like the crash slow motion);
## paused, rewinding or scrubbing fast = quiet
func _sound(prev_tp: float, rdt: float, fk: Array) -> void:
	var au = game.audio
	if au == null: return
	var dtp := tp - prev_tp
	var rate := dtp / rdt if rdt > 0.0 else 0.0
	if rdt <= 0.0 or dtp <= 0.0 or rate > 3.0 or not playing and absf(_held) < TAP:
		au.src = null
		AudioServer.playback_speed_scale = 1.0
		return
	var a: Array = fk[0]
	var ra: PackedFloat32Array = a[AROW] if a.size() > AROW else PackedFloat32Array()
	if ra.size() < 8:
		au.src = null
		return
	var rb: PackedFloat32Array = fk[1][AROW] if (fk[1] != null and fk[1].size() > AROW) else ra
	var k: float = fk[2]
	var s := _astate
	s.v = lerpf(ra[0], rb[0], k); s.air = ra[1] > 0.5; s.crash_on = ra[2] > 0.5; s.surf = int(ra[3]); s.skid_fx = ra[4] > 0.5
	s.throttle_in = lerpf(ra[5], rb[5], k); s.pedal = lerpf(ra[6], rb[6], k); s.crank = lerpf(ra[7], rb[7], k)
	s.RWR = float(game.phys.RWR) if game.phys else 0.36
	au.src = s
	AudioServer.playback_speed_scale = clampf(rate, 0.35, 1.5)
	if dtp < 0.5:   # (a loop / a jump: no burst of every sound in between)
		for ev in aev:
			var et := float(ev[0])
			if et > prev_tp and et <= tp: au.callv(String(ev[1]), ev[2])

## the dust plays again: the tyres' feeds of the sample + the bursts the playhead crossed, the smoke sim stepped by
## the replay's own time (paused = the cloud hangs still; a jump back clears it: smoke can't run backwards)
func _dust(prev_tp: float, fk: Array) -> void:
	var du = game.dust
	if du == null or du.sim == null: return
	var dtp := tp - prev_tp
	if dtp < 0.0 or dtp > 0.5:
		du.sim.reset()
		return
	if dtp == 0.0: return
	var a: Array = fk[0]
	if a.size() > DROW:
		var fd: Array = a[DROW]
		if (fd[0] as Array).size() == 6: du.callv("feed", fd[0])
		if (fd[1] as Array).size() == 4: du.callv("feed_front", fd[1])
	for ev in dev:
		var et := float(ev[0])
		if et > prev_tp and et <= tp:
			(du.sim if ev[1] == "sim" else du).callv(String(ev[2]), ev[3])
	du.sim_step(dtp, _focus_now, fwd_at(tp), game.atmos.wind)

## tyre tracks: the marks laid after the replayed moment are hidden (their colour bytes zeroed, the ring's newest
## segments), so they appear behind the bike as it rides; all put back on leaving. Not for a saved replay (a fresh
## world has none)
var _trk_attr := PackedByteArray()   # the tracks' whole attribute buffer as the ride left it
var _trk_hid := 0                    # how many of the newest segments are hidden now
func _tracks(fk: Array) -> void:
	var fx = game.fx
	if fx == null or viewer or _trk_attr.is_empty(): return
	var a: Array = fk[0]
	if a.size() <= DROW + 1: return
	var cut := float(a[DROW + 1])
	if fk[1] != null and (fk[1] as Array).size() > DROW + 1: cut = lerpf(cut, float(fk[1][DROW + 1]), fk[2])
	# the newest segment is at seg_next - 1, older ones behind it: find how many are newer than the cut
	var n: int = fx.SEG_MAX
	var lo := 0
	var hi := n
	while lo < hi:   # smallest k whose segment is no newer than the cut
		var mid := (lo + hi) >> 1
		if float(fx.seg_birth[posmod(int(fx.seg_next) - 1 - mid, n)]) > cut: lo = mid + 1
		else: hi = mid
	var h := lo
	if h == _trk_hid: return
	var rid: RID = fx.track_mesh.get_rid()
	var sb: int = 6 * int(fx._a_stride)
	var k0 := mini(h, _trk_hid)
	var k1 := maxi(h, _trk_hid)
	var zero := PackedByteArray()
	if h > _trk_hid: zero.resize(sb)
	for k in range(k0, k1):   # (a few segments a frame at riding speed)
		var i := posmod(int(fx.seg_next) - 1 - k, n)
		RenderingServer.mesh_surface_update_attribute_region(rid, 0, i * sb, zero if h > _trk_hid else _trk_attr.slice(i * sb, (i + 1) * sb))
	_trk_hid = h

func _tracks_open() -> void:
	_trk_hid = 0
	_trk_attr = PackedByteArray()
	var fx = game.fx
	if fx == null or viewer or fx.track_mesh == null: return
	var sd: Dictionary = RenderingServer.mesh_get_surface(fx.track_mesh.get_rid(), 0)
	_trk_attr = sd.get("attribute_data", PackedByteArray())

func _tracks_close() -> void:
	var fx = game.fx
	if fx != null and not _trk_attr.is_empty() and _trk_hid > 0:
		RenderingServer.mesh_surface_update_attribute_region(fx.track_mesh.get_rid(), 0, 0, _trk_attr)
	_trk_attr = PackedByteArray()
	_trk_hid = 0

## tests: frames where the rider (or a big part of him) isn't drawn while the replay plays
var _vis_bad := 0
var _vis_live := {}
var _vis_n := 0
func _vis_probe() -> void:
	var r = game.rider
	if r == null: return
	_vis_n += 1
	var hidden := PackedStringArray()
	if not r.is_visible_in_tree(): hidden.append("rider")
	if _vis_live.is_empty() and _snap != null:   # (what is hidden in the live ride too: left out)
		var ls: Dictionary = _snap[0]
		for ni in ls.nodes.size():
			if ls.base_v[ni] == 0: _vis_live[ls.nodes[ni]] = true
	for c in r.find_children("*", "GeometryInstance3D", true, false):
		if not (c as Node3D).visible and not _vis_live.has(c):
			hidden.append("%s(%s)" % [String(c.name), String(c.get_parent().name)])
	var dist: float = cam3.global_position.distance_to(r.global_position) if cam3 else 0.0
	if hidden.size() > 0 or r.global_position.distance_to(_focus_now) > 3.0:
		_vis_bad += 1
		if _vis_bad < 12: print("REPLAYVIS tp=%.2f hidden=%s rider_to_focus=%.2f cam_dist=%.1f" % [tp - t1(), ",".join(hidden), r.global_position.distance_to(_focus_now), dist])
	if _vis_n % 120 == 0: print("REPLAYVIS frames=%d bad=%d" % [_vis_n, _vis_bad])

func _kmh_at(t: float) -> float:
	return float(frames[_at(t)][6])

# ---- cameras ---------------------------------------------------------------------------------------------------

func _ground(p: Vector3) -> float:
	return game.terrain.top_height(p.x, p.z)

func _camera(rdt: float) -> void:
	var f := _focus_now
	var fw := fwd_at(tp)
	_fwd_s = fw if _snap_cam else _fwd_s.slerp(fw, 1.0 - exp(-rdt * 3.0)).normalized()
	var fs := _fwd_s
	var side := fs.cross(Vector3.UP).normalized()
	var want := Vector3.ZERO
	var aim := f
	var fov := 45.0
	var follow := 6.0
	match CAMS[cam_i]:
		"TV":
			_tv_shot(f, fs)
			want = _shot[0]
			var dd := maxf(want.distance_to(f), 1.0)
			fov = clampf(rad_to_deg(2.0 * atan(2.6 / dd)) / _zoom, 6.0, 60.0)
			aim = f + (fw * 0.6)
			follow = 1000.0   # (a fixed camera: it doesn't move, it turns)
		"Chase":
			want = f - fs * 5.5 * _zoom + Vector3(0, 1.7 * _zoom, 0)
			aim = f + fs * 2.5
			fov = 52.0
		"Side":
			want = f + side * 7.5 * _zoom + Vector3(0, 1.1, 0) - fs * 0.8
			fov = 40.0
		"Orbit":
			_orbit += rdt * 0.22
			var oq := Basis(Vector3.UP, _orbit)
			want = f + oq * (-fs * 6.5 * _zoom) + Vector3(0, 1.8 * _zoom, 0)
			fov = 45.0
		"Detail":   # round the bike itself, close (zoom in to ~40 cm), slowly turning until you take it
			var bc := _bike_centre()
			aim = bc
			if not _touched: _orbit += rdt * 0.3
			var dq := Basis(Vector3.UP, _orbit + PI * 0.5)
			want = bc + dq * (-fs * 2.4 * _zoom) + Vector3(0, 0.45 * _zoom, 0)
			fov = 40.0
			follow = 14.0
		"Drone":
			want = f - fs * 10.0 * _zoom + Vector3(0, 8.0 * _zoom, 0)
			aim = f + fs * 3.0
			fov = 50.0
	if CAMS[cam_i] == "Free":
		_free_cam(rdt)
		return
	cam3.near = 0.03 if CAMS[cam_i] == "Detail" else game.cam.near
	# the player's look offset swings the camera round the rider (TV: turns the lens instead)
	if CAMS[cam_i] != "TV" and (_yaw != 0.0 or _pitch != 0.0):
		var off := want - f
		off = Basis(Vector3.UP, _yaw) * off
		var r := off.cross(Vector3.UP).normalized()
		if r.length_squared() > 0.5: off = Basis(r, clampf(_pitch, -1.0, 1.2)) * off
		want = f + off
	want.y = maxf(want.y, _ground(want) + 0.45)
	if _snap_cam or follow > 999.0:
		_cpos = want
	else:
		_cpos = _cpos.lerp(want, 1.0 - exp(-rdt * follow))
		_cpos.y = maxf(_cpos.y, _ground(_cpos) + 0.4)
	_caim = aim if _snap_cam else _caim.lerp(aim, 1.0 - exp(-rdt * (14.0 if CAMS[cam_i] == "TV" else 9.0)))
	_cfov = fov if _snap_cam else lerpf(_cfov, fov, 1.0 - exp(-rdt * 4.0))
	_snap_cam = false
	var look := _caim
	if CAMS[cam_i] == "TV" and (_yaw != 0.0 or _pitch != 0.0):
		var dv := look - _cpos
		look = _cpos + Basis(Vector3.UP, _yaw) * dv + Vector3(0, _pitch * dv.length() * 0.5, 0)
	if _cpos.distance_squared_to(look) > 1e-4:
		cam3.look_at_from_position(_cpos, look, Vector3.UP)
	cam3.fov = _cfov

func _bike_centre() -> Vector3:
	var r = game.rig
	if r == null: return _focus_now
	return (r.wheel_f.global_position + r.wheel_r.global_position) * 0.5 + Vector3(0, 0.12, 0)

## Free: an editor fly camera (Unity / Unreal scene view). Right mouse held = mouselook (cursor hidden) with WASD
## flying where it looks, Q / E down / up, Shift x3, Alt slow, the wheel (right held) = fly speed; middle drag = pan;
## Alt + left drag = orbit the rider; wheel = dolly, Ctrl + wheel = lens; F = frame the rider. Pad: left stick fly,
## right stick look, triggers down / up. Works paused or playing; the world streams in round the camera
func _free_cam(rdt: float) -> void:
	if not _free_init:
		_free_init = true
		_free_pos = cam3.global_position
		_free_look_from(-cam3.global_basis.z)
		_free_fov = cam3.fov
		_free_vel = Vector3.ZERO
		_free_roll = 0.0
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mv.z -= 1.0
	if Input.is_key_pressed(KEY_S): mv.z += 1.0
	if Input.is_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_key_pressed(KEY_D): mv.x += 1.0
	var up := 0.0
	if Input.is_key_pressed(KEY_E): up += 1.0
	if Input.is_key_pressed(KEY_Q): up -= 1.0
	var lx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(lx) > 0.15: mv.x += lx
	if absf(ly) > 0.15: mv.z += ly
	up += Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var sp := _free_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else (0.3 if Input.is_key_pressed(KEY_ALT) and not _orbiting else 1.0))
	# look: mouse (right held / left drag) + right stick
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.15: _yaw_d -= rx * rdt * 2.0
	if absf(ry) > 0.15: _pitch_d -= ry * rdt * 1.5
	var pivot := _focus_now
	if _orbit_d != Vector2.ZERO:   # Alt + drag: round the rider, looking at him
		var off := _free_pos - pivot
		off = Basis(Vector3.UP, -_orbit_d.x) * off
		var rt := off.cross(Vector3.UP).normalized()
		var pit := Basis(rt, _orbit_d.y) * off
		if absf(pit.normalized().y) < 0.97: off = pit
		_free_pos = pivot + off
		_free_look_from(-off)
		_orbit_d = Vector2.ZERO
	_free_yaw += _yaw_d
	_free_pitch = clampf(_free_pitch + _pitch_d, -1.55, 1.55)
	_yaw_d = 0.0; _pitch_d = 0.0
	if Env.s("BMX_REPLAY_FLYTEST") != "":   # tests: fly forward + up, turn, tilt, pan, dolly, then orbit
		mv.z -= 1.0; up += 0.3; _yaw_d += rdt * 0.4
		_pan_d += Vector2(40.0, 0.0) * rdt; _dolly_d += rdt
		if int(Time.get_ticks_msec() / 1500) % 2 == 1: _orbit_d += Vector2(0.6, 0.0) * rdt
	var rl := 0.0
	if Env.s("BMX_REPLAY_FLYTEST") != "": rl += 0.5
	if Input.is_key_pressed(KEY_Z) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER): rl += 1.0
	if Input.is_key_pressed(KEY_X) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER): rl -= 1.0
	_free_roll = clampf(_free_roll + rl * rdt * 0.9, -PI * 0.5, PI * 0.5)
	var bas := Basis(Vector3.UP, _free_yaw) * Basis(Vector3.RIGHT, _free_pitch) * Basis(Vector3.BACK, _free_roll)
	# fly: along where it looks (W climbs when looking up, like the editors), eased in / out
	var want := (bas * Vector3(mv.x, 0.0, mv.z) + Vector3(0, up, 0)) * sp
	_free_vel = _free_vel.lerp(want, 1.0 - exp(-rdt * 10.0))
	_free_pos += _free_vel * rdt
	# pan (middle drag) and dolly (wheel): the further from the rider, the bigger the step
	var reach := clampf(_free_pos.distance_to(pivot), 1.5, 200.0)
	if _pan_d != Vector2.ZERO:
		_free_pos += (-bas.x * _pan_d.x + bas.y * _pan_d.y) * reach * 0.0018
		_pan_d = Vector2.ZERO
	if _dolly_d != 0.0:
		_free_pos += -bas.z * _dolly_d * maxf(reach * 0.12, 0.25)
		_dolly_d = 0.0
	var off2 := _free_pos - pivot
	if off2.length() > FREE_RANGE: _free_pos = pivot + off2.normalized() * FREE_RANGE
	_free_pos.y = maxf(_free_pos.y, _ground(_free_pos) + 0.15)
	cam3.global_transform = Transform3D(bas, _free_pos)
	cam3.fov = clampf(_free_fov, 6.0, 110.0)
	cam3.near = 0.03

func _free_look_from(dir: Vector3) -> void:
	var d := dir.normalized()
	_free_yaw = atan2(-d.x, -d.z)
	_free_pitch = asin(clampf(d.y, -1.0, 1.0))

## F: the camera a few metres off the rider, looking at him
func _free_frame() -> void:
	var fs := fwd_at(tp)
	var side := fs.cross(Vector3.UP).normalized()
	_free_pos = _focus_now - fs * 3.0 + side * 2.2 + Vector3(0, 1.2, 0)
	_free_pos.y = maxf(_free_pos.y, _ground(_free_pos) + 0.4)
	_free_look_from(_focus_now - _free_pos)
	_free_vel = Vector3.ZERO
	_free_roll = 0.0

func _set_mouselook(on: bool) -> void:
	_rmb = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

## TV director: a fixed trackside camera ahead of where the rider will be, cut to a new one once he is past it
func _tv_shot(f: Vector3, fs: Vector3) -> void:
	var need: bool = _shot == null or tp < float(_shot[1]) - 0.05
	if not need:
		var sp: Vector3 = _shot[0]
		var rel := f - sp
		var flat := Vector2(rel.x, rel.z)
		var passed: bool = rel.dot(fs) > 6.0 and flat.length() > 11.0
		need = passed or flat.length() > 40.0 or tp - float(_shot[1]) > 8.0 or not _seen(sp, f)
	if not need: return
	_shot_n += 1
	var lead := minf(2.4, maxf(t1() - tp, 0.0))
	var p := focus_at(tp + lead)
	var pf := fwd_at(tp + lead)
	if lead < 1.0: p += pf * 10.0
	var ps := pf.cross(Vector3.UP).normalized()
	var best = null
	for tryi in 6:
		var h := hash(_shot_n * 7 + tryi)
		var s: float = (1.0 if (h & 1) == 0 else -1.0) * (5.0 + float((h >> 1) % 50) / 10.0)
		var back := float((h >> 7) % 30) / 10.0
		var cand := p + ps * s + pf * back
		cand.y = maxf(_ground(cand) + 0.9 + float((h >> 12) % 14) / 10.0, p.y - 0.5)
		if _seen(cand, f) and _seen(cand, p):
			best = cand; break
	if best == null:
		best = f - fs * 6.0 + Vector3(0, 2.0, 0)
		best.y = maxf(best.y, _ground(best) + 0.8)
	_shot = [best, tp, _shot_n]
	_snap_cam = true

## nothing of the land between the camera and the rider
func _seen(a: Vector3, b: Vector3) -> bool:
	for i in range(1, 8):
		var p := a.lerp(b, i / 8.0)
		if _ground(p) > p.y - 0.25: return false
	return true

# ---- input -----------------------------------------------------------------------------------------------------

func _poll(rdt: float) -> void:
	var free: bool = CAMS[cam_i] == "Free"   # (there WASD / the left stick fly the camera: rewind = arrows / D-pad)
	var back := Input.is_key_pressed(KEY_LEFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT) or (not free and (Input.is_key_pressed(KEY_A) or Input.get_joy_axis(0, JOY_AXIS_LEFT_X) < -0.5))
	var fwd := Input.is_key_pressed(KEY_RIGHT) or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT) or (not free and (Input.is_key_pressed(KEY_D) or Input.get_joy_axis(0, JOY_AXIS_LEFT_X) > 0.5))
	if back != fwd:
		var d := -1.0 if back else 1.0
		if signf(_held) != d: _held = 0.0
		_held += d * rdt
	else:
		# a tap (let go within TAP) steps one sample while paused, a second while playing; held it scrubs
		if _held != 0.0 and absf(_held) < TAP:
			tp = clampf(tp + signf(_held) * ((1.0 / HZ) if not playing else 1.0), t0(), t1())
		_held = 0.0
	if free: return
	# right stick / triggers: look and zoom
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.15: _yaw -= rx * rdt * 1.8
	if absf(ry) > 0.15: _pitch += ry * rdt * 1.2
	var zt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(zt) > 0.1: _zoom = clampf(_zoom * exp(-zt * rdt * 1.2), ZOOM_MIN, 2.5)
	if absf(rx) > 0.15 or absf(ry) > 0.15: _touched = true
const TAP := 0.22
const ZOOM_MIN := 0.15
var _touched := false        # Detail: the player turned it (stops the slow auto turn)
var _yaw_d := 0.0            # Free: mouse look this frame
var _pitch_d := 0.0

func _input(e: InputEvent) -> void:
	if not on or game.photo: return   # (photo mode on a replay frame takes the input)
	if exporting:   # (Esc stops it, keeping what's done)
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE: _export_end()
		get_viewport().set_input_as_handled()
		return
	if style_ui != null and style_ui.visible and e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT 			and (e as InputEventMouseButton).pressed and style_ui.has_point((e as InputEventMouseButton).position):
		style_ui.click((e as InputEventMouseButton).position)
		get_viewport().set_input_as_handled()
		return
	var used := true
	var free: bool = CAMS[cam_i] == "Free"
	if e is InputEventKey and free and e.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_Z, KEY_X, KEY_SHIFT, KEY_ALT, KEY_CTRL]:
		get_viewport().set_input_as_handled()
		return
	if free and _free_input(e):
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE, KEY_K: _toggle_play()
			KEY_C: _next_cam()
			KEY_Q, KEY_DOWN: _speed(-1)
			KEY_E, KEY_UP: _speed(1)
			KEY_S: save()
			KEY_G: toggle_highlights()
			KEY_BRACKETLEFT: clip_in = tp; status = "CLIP IN " + clock(tp - t1()); _status_t = 1.5
			KEY_BRACKETRIGHT: clip_out = tp; status = "CLIP OUT " + clock(tp - t1()); _status_t = 1.5
			KEY_DELETE: clip_in = -1.0; clip_out = -1.0; status = "CLIP CLEARED"; _status_t = 1.5
			KEY_V: export_clip()
			KEY_ENTER, KEY_KP_ENTER: ride_from_here()
			KEY_INSERT: _pose_from_here()
			KEY_L: reride_from_here()
			KEY_T: style_ui.visible = not style_ui.visible
			KEY_Y: style_ui.cycle_window()
			KEY_HOME: tp = t0(); _shot = null; _snap_cam = true
			KEY_END: tp = t1()
			KEY_H, KEY_F1: ui_on = not ui_on
			KEY_R: _yaw = 0.0; _pitch = 0.0; _zoom = 1.0; _free_roll = 0.0
			KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D: pass
			_:
				if e.is_action_pressed("replay"): game.exit_replay()
				elif e.is_action_pressed("screenshot") or e.is_action_pressed("pause"): used = false   # (main / the shot key)
				else: used = false
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_A: _toggle_play()
			JOY_BUTTON_Y: _next_cam()
			JOY_BUTTON_LEFT_SHOULDER: if not free: _speed(-1)   # (Free: the shoulders tilt the camera)
			JOY_BUTTON_RIGHT_SHOULDER: if not free: _speed(1)
			JOY_BUTTON_DPAD_DOWN: _speed(-1)
			JOY_BUTTON_DPAD_UP: _speed(1)
			JOY_BUTTON_B, JOY_BUTTON_LEFT_STICK: game.exit_replay()
			JOY_BUTTON_X: ride_from_here()
			JOY_BUTTON_RIGHT_STICK: toggle_highlights()
			JOY_BUTTON_BACK: save()
			JOY_BUTTON_START: used = false
			_: pass
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if free: _free_fov /= 1.08
			else: _zoom = clampf(_zoom / 1.1, ZOOM_MIN, 2.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if free: _free_fov *= 1.08
			else: _zoom = clampf(_zoom * 1.1, ZOOM_MIN, 2.5)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			var hit: String = bar.hit(mb.position) if ui_on else ""
			if mb.pressed:
				if hit == "timeline":
					_drag_tl = true; _was_playing = playing; _scrub_to(mb.position.x)
				elif hit == "play": _toggle_play()
				elif hit == "cam": _next_cam()
				elif hit == "slower": _speed(-1)
				elif hit == "faster": _speed(1)
				elif hit == "exit": game.exit_replay()
				elif hit == "save": save()
				else: _drag_look = true
			else:
				_drag_tl = false; _drag_look = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag_look = mb.pressed
		else: used = false
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _drag_tl: _scrub_to(mm.position.x)
		elif _drag_look:
			_touched = true
			if free:
				_yaw_d -= mm.relative.x * 0.004
				_pitch_d -= mm.relative.y * 0.004
			else:
				_yaw -= mm.relative.x * 0.006
				_pitch += mm.relative.y * 0.004
		else: used = false
	else:
		used = false
	if used: get_viewport().set_input_as_handled()

## the editor fly camera's mouse (true = used). The timeline / bar buttons still take a plain left click
func _free_input(e: InputEvent) -> bool:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F:
		_free_frame(); return true
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_set_mouselook(mb.pressed); return true
			MOUSE_BUTTON_MIDDLE:
				_mmb = mb.pressed; return true
			MOUSE_BUTTON_LEFT:
				if mb.pressed and mb.alt_pressed: _orbiting = true; return true
				if not mb.pressed and _orbiting: _orbiting = false; return true
				return false   # (bar buttons / timeline / plain drag look: the usual handling)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not mb.pressed: return true
				var d := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				if _rmb:   # fly speed, like the editors
					_free_speed = clampf(_free_speed * (1.25 if d > 0.0 else 0.8), 0.5, 120.0)
					status = "FLY SPEED %.1f M/S" % _free_speed; _status_t = 1.5
				elif mb.ctrl_pressed: _free_fov *= (1.0 / 1.08 if d > 0.0 else 1.08)
				else: _dolly_d += d
				return true
	if e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _rmb:
			_yaw_d -= mm.relative.x * 0.0035
			_pitch_d -= mm.relative.y * 0.0035
			return true
		if _mmb:
			_pan_d += mm.relative
			return true
		if _orbiting:
			_orbit_d += mm.relative * 0.006
			return true
	return false

## Pose Lab from the replay: rewind to the moment, press Insert: the ride carries on from there (ride from here) and
## the Lab opens with the physics paused, so the jump can be posed / keyed in place
func _pose_from_here() -> void:
	if viewer or not can_ride_from_here():
		status = "NO POINT TO POSE FROM HERE"; _status_t = 1.5
		return
	var g = game
	var pick: String = style_ui.sel if style_ui != null else ""
	var at_t := -1.0
	if pick != "":
		var fk := _frame_k(tp)
		at_t = style_ui.val(fk[0], "clip|%s|t" % pick, -1.0)
	ride_from_here()
	if g.pose_lab == null or not g.pose_lab.is_open(): g.toggle_pose_lab()
	else: g.pose_hold = true
	if pick != "":   # the clip picked in the Style Inspector, at the very moment of the replay
		for ci in PoseKeys.clips.size():
			if str(PoseKeys.clips[ci].name) == pick:
				PoseKeys.select(ci)
				g.pose_lab._clip_switched()
				if at_t >= 0.0: g.pose_lab.preview_t = at_t
				g.pose_lab._pull()
				break


func _scrub_to(x: float) -> void:
	var r: Rect2 = bar.timeline_rect()
	var k := clampf((x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
	var nt := lerpf(t0(), t1(), k)
	if absf(nt - tp) > 1.0:
		_snap_cam = true
		_shot = null
	tp = nt

func _toggle_play() -> void:
	if not playing and tp >= t1() - 0.01: tp = t0(); _shot = null; _snap_cam = true
	playing = not playing

func _next_cam() -> void:
	if _rmb: _set_mouselook(false)
	_mmb = false; _orbiting = false
	cam_i = (cam_i + 1) % CAMS.size()
	_free_init = false
	_touched = false
	_refresh_hint()
	_shot = null
	_snap_cam = true
	_yaw = 0.0; _pitch = 0.0

func _speed(d: int) -> void:
	speed_i = clampi(speed_i + d, 0, SPEEDS.size() - 1)

func _refresh_hint() -> void:
	_hint_pad = Settings.pad_active
	if CAMS[cam_i] == "Free":
		if _hint_pad:
			hint.set_items([[["LS"], "Fly"], [["RS"], "Look"], [["LT", "RT"], "Down / up"], [["LB", "RB"], "Tilt"], [["A"], "Play"],
				[["D-Left", "D-Right"], "Rewind"], [["Y"], "Camera"], [["B"], "Back"]])
		else:
			hint.set_items([[["MOUSE"], "Right: look"], [["K:W", "K:A", "K:S", "K:D"], "Fly"], [["K:Q", "K:E"], "Down / up"], [["MOUSE"], "Middle: pan"],
				[["K:ALT"], "+ drag: orbit"], [["K:Z", "K:X"], "Tilt"], [["K:F"], "Frame"], [["K:C"], "Camera"]])
		return
	if _hint_pad:
		hint.set_items([[["A"], "Play"], [["D-Left", "D-Right"], "Rewind"], [["LB", "RB"], "Speed"], [["Y"], "Camera"],
			[["R3"], "Highlights"]] + ([] if viewer else [[["X"], "Ride from here"], [["VIEW"], "Save"]]) + [[["B"], "Back"]])
	else:
		hint.set_items([[["K:SPACE"], "Play"], [["K:A", "K:D"], "Rewind"], [["K:Q", "K:E"], "Speed"], [["K:C"], "Camera"],
			[["K:G"], "Highlights"], [["K:T"], "Style"], [["K:L"], "Ride the line again"], [["K:O"], "Photo"], [["K:[", "K:]", "K:V"], "Clip"]] + ([] if viewer else [[["K:ENTER"], "Ride from here"], [["K:INS"], "Pose Lab here"], [["K:S"], "Save"]])
			+ [[["K:ESC"], "Back"]])

func _test_set(spec: String) -> void:
	for kv in spec.split(",", false):
		var p := kv.split("=")
		if p.size() < 2: continue
		match p[0]:
			"cam": cam_i = maxi(CAMS.find(p[1]), 0)
			"speed": speed_i = maxi(SPEEDS.find(float(p[1])), 0)
			"at": tp = clampf(t1() + float(p[1]), t0(), t1()) if float(p[1]) <= 0.0 else clampf(t0() + float(p[1]), t0(), t1())
			"pause": playing = p[1] != "1"
			"ui": ui_on = p[1] != "0"
			"style": style_ui.visible = p[1] != "0"   # tests: the Style Inspector
			"pick": style_ui.sel = p[1]
			"win": style_ui.win = float(p[1])
			"hl": if p[1] == "1": toggle_highlights.call_deferred()
			"in": clip_in = clampf(t1() + float(p[1]), t0(), t1())
			"out": clip_out = clampf(t1() + float(p[1]), t0(), t1())
			"export": if p[1] == "1": export_clip.call_deferred()
			"ride": if p[1] == "1": ride_from_here.call_deferred()
			"reride": if p[1] == "1": reride_from_here.call_deferred()   # tests: ride the line again from the playhead


## the bar along the bottom: REPLAY, the timeline (crashes red, airs gold), time, speed, camera
class Bar extends Control:
	var rp
	const H := 112.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func timeline_rect() -> Rect2:
		var x0 := 260.0
		var x1 := size.x - 300.0
		return Rect2(x0, size.y - H + 34.0, maxf(x1 - x0, 50.0), 6.0)

	func _btn_rects() -> Dictionary:
		var y := size.y - H + 20.0
		var xr := size.x - 284.0
		return {
			"play": Rect2(196, y, 34, 34),
			"slower": Rect2(xr, y, 30, 34), "faster": Rect2(xr + 82, y, 30, 34),
			"cam": Rect2(xr + 124, y, 110, 34), "exit": Rect2(size.x - 44, y, 30, 34), "save": Rect2(140, y, 40, 34)}

	func hit(p: Vector2) -> String:
		var tl := timeline_rect().grow_individual(0, 14, 0, 14)
		if tl.has_point(p): return "timeline"
		var br := _btn_rects()
		for k in br:
			if (br[k] as Rect2).has_point(p): return k
		return ""

	func _draw() -> void:
		if rp == null or rp.frames.size() < 2: return
		var W := size.x
		var y0 := size.y - H
		var f := UITheme.font(true)
		var df := UITheme.display_font(800, 0.18)
		# a soft dark band, darker to the bottom
		draw_rect(Rect2(0, y0 - 30, W, 30), Color(0, 0, 0, 0.0))
		for i in 12:
			var a := 0.62 * float(i + 1) / 12.0
			draw_rect(Rect2(0, y0 - 24 + i * 2, W, 2), Color(0.02, 0.02, 0.03, a * 0.5))
		draw_rect(Rect2(0, y0, W, H), Color(0.02, 0.02, 0.03, 0.62))
		# REPLAY with a blinking red dot
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
		var cy := y0 + 37.0
		if blink or not rp.playing: draw_circle(Vector2(30, cy), 7.0, Color(0.92, 0.12, 0.1), true, -1.0, true)
		draw_string(df, Vector2(46, cy + 11), "REPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.96))
		# play / pause
		var br := _btn_rects()
		var pr: Rect2 = br.play
		var pc := pr.get_center()
		if rp.playing:
			draw_rect(Rect2(pc.x - 8, pc.y - 10, 5, 20), Color.WHITE)
			draw_rect(Rect2(pc.x + 3, pc.y - 10, 5, 20), Color.WHITE)
		else:
			draw_colored_polygon(PackedVector2Array([pc + Vector2(-7, -11), pc + Vector2(11, 0), pc + Vector2(-7, 11)]), Color.WHITE)
		# timeline
		var r := timeline_rect()
		draw_rect(r, Color(1, 1, 1, 0.18))
		var t0: float = rp.t0()
		var t1: float = rp.t1()
		var span := maxf(t1 - t0, 0.01)
		for m in rp._marks:
			var xa: float = r.position.x + (float(m[1]) - t0) / span * r.size.x
			var xb: float = r.position.x + (float(m[2]) - t0) / span * r.size.x
			if int(m[0]) == 2:
				draw_rect(Rect2(xa, r.position.y - 3, maxf(xb - xa, 1.5), r.size.y + 6), Color(1.0, 0.78, 0.2, 0.85))
			else:
				draw_rect(Rect2(xa - 1.5, r.position.y - 9, 3, r.size.y + 18), Color(0.95, 0.15, 0.12))
		if rp.hl_on:   # the highlights: light bands over the line
			for w in rp._hl:
				var ha: float = r.position.x + (float(w[0]) - t0) / span * r.size.x
				var hb: float = r.position.x + (float(w[1]) - t0) / span * r.size.x
				draw_rect(Rect2(ha, r.position.y + r.size.y + 4, maxf(hb - ha, 2.0), 3), Color(0.45, 0.8, 1.0, 0.9))
		if rp.clip_in >= 0.0 or rp.clip_out >= 0.0:   # the clip to export: brackets and a band
			var ca: float = r.position.x + (maxf(rp.clip_in, t0) - t0) / span * r.size.x
			var cb: float = r.position.x + ((rp.clip_out if rp.clip_out > rp.clip_in else t1) - t0) / span * r.size.x
			draw_rect(Rect2(ca, r.position.y - 6, cb - ca, 3), Color(1, 1, 1, 0.75))
			draw_rect(Rect2(ca - 1, r.position.y - 10, 2, r.size.y + 20), Color.WHITE)
			draw_rect(Rect2(cb - 1, r.position.y - 10, 2, r.size.y + 20), Color.WHITE)
		var k: float = (rp.tp - t0) / span
		var px: float = r.position.x + k * r.size.x
		draw_rect(Rect2(r.position.x, r.position.y, px - r.position.x, r.size.y), Color(1, 1, 1, 0.85))
		draw_circle(Vector2(px, r.get_center().y), 8.0, Color.WHITE, true, -1.0, true)
		# time (how far back from now) + the speed then
		var ago: float = rp.tp - t1
		draw_string(f, Vector2(r.position.x, r.position.y + 28), ReplayMode.clock(ago), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
		var kmh: float = rp._kmh_at(rp.tp)
		var units := int(Settings.get_v("units"))
		var spd := "%d %s" % [roundi(kmh / (1.609 if units == 1 else 1.0)), "MPH" if units == 1 else "KM/H"]
		draw_string(f, Vector2(r.end.x - 120, r.position.y + 28), spd, HORIZONTAL_ALIGNMENT_RIGHT, 120, 16, Color(1, 1, 1, 0.85))
		draw_string(f, Vector2(r.position.x, r.position.y - 12), ReplayMode.clock(-span), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))
		draw_string(f, Vector2(r.end.x - 60, r.position.y - 12), "NOW", HORIZONTAL_ALIGNMENT_RIGHT, 60, 12, Color(1, 1, 1, 0.45))
		# speed - / +, camera, exit
		var sl: Rect2 = br.slower
		var fa: Rect2 = br.faster
		_arrow(sl.get_center(), -1)
		_arrow(fa.get_center(), 1)
		var sp: float = ReplayMode.SPEEDS[rp.speed_i]
		var st := ("%d" % int(sp) if sp >= 1.0 else String.num(sp)) + "x"
		draw_string(df, Vector2(sl.end.x, sl.get_center().y + 9), st, HORIZONTAL_ALIGNMENT_CENTER, fa.position.x - sl.end.x, 24, Color(1, 1, 1, 0.95))
		var cr: Rect2 = br.cam
		draw_string(f, Vector2(cr.position.x, cr.position.y + 2), "CAMERA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		draw_string(df, Vector2(cr.position.x, cr.end.y), String(ReplayMode.CAMS[rp.cam_i]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
		if not rp.viewer:   # SAVE: a floppy-ish box with a down arrow
			var sv: Rect2 = br.save
			var scn := sv.get_center()
			draw_rect(Rect2(scn.x - 10, scn.y - 10, 20, 20), Color(1, 1, 1, 0.9), false, 2.0)
			draw_line(scn + Vector2(0, -6), scn + Vector2(0, 4), Color.WHITE, 2.0, true)
			draw_colored_polygon(PackedVector2Array([scn + Vector2(-5, 1), scn + Vector2(5, 1), scn + Vector2(0, 6)]), Color.WHITE)
		if rp.status != "":
			draw_string(f, Vector2(24, y0 - 12), rp.status, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.3))
		elif rp.viewer and not rp.info.is_empty():
			draw_string(f, Vector2(24, y0 - 12), "%s  ·  WORLD %s  ·  %s" % [String(rp.info.get("date", "")).replace("T", "  "), str(rp.info.get("seed", "")),
				String(GameState.BIKES.get(rp.info.get("bike", ""), {}).get("label", "")).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
		var ex: Rect2 = br.exit
		var ec := ex.get_center()
		draw_line(ec + Vector2(-8, -8), ec + Vector2(8, 8), Color.WHITE, 3.0, true)
		draw_line(ec + Vector2(-8, 8), ec + Vector2(8, -8), Color.WHITE, 3.0, true)

	func _arrow(c: Vector2, d: int) -> void:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-6 * d, -9), c + Vector2(7 * d, 0), c + Vector2(-6 * d, 9)]), Color(1, 1, 1, 0.9))
