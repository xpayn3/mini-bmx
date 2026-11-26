class_name Dev
## The bridge to the developer tools. Every dev-only script lives in res://dev/ (tuning cards, Pose Lab, Style
## Inspector, Anim Studio, frame profiler, physics overlay, render probe, demo AI, the test playground + its dev
## view / lab / suite / ramp editor). The "Windows Desktop" release preset leaves res://dev/ (and the editor addons)
## out of the exported game, so a release build has none of their code. The "Windows Dev" preset keeps them and
## adds the "dev" feature tag.
##
## Rules for game code (everything outside res://dev/):
##   - never name a dev class (PoseLab, TuneCard, PlaygroundTerrain, DemoPilot, ...): a release export would not
##     compile. Keep dev objects in untyped variables and make them with Dev.make("pose_lab.gd") / Dev.script(...).
##   - check Dev.on (or a null from make / script) before using one.
## Dev scripts may use game classes freely.

## ON in the editor and its test runs, and in exports from the "Windows Dev" preset (feature tag "dev"); OFF in a
## release export. BMX_DEV=0 turns it off in the editor (to check what a release looks like).
static var on: bool = _pick()

## input actions that only drive dev tools (left out of Settings > Controls when off)
const ACTIONS := ["tune", "pose_panel", "look_panel", "debug_draw", "profiler", "diag", "demo"]

static func _pick() -> bool:
	if not (OS.has_feature("editor") or OS.has_feature("dev")): return false
	return OS.get_environment("BMX_DEV") != "0"

## a dev script by its path under res://dev/ ("pose_lab.gd", "playground/playground_terrain.gd"); null when off
static func script(rel: String) -> Script:
	if not on: return null
	return load("res://dev/" + rel) as Script

## a new instance of a dev script (up to 3 constructor arguments); null when off
static func make(rel: String, args: Array = []):
	var s := script(rel)
	if s == null: return null
	match args.size():
		0: return s.new()
		1: return s.new(args[0])
		2: return s.new(args[0], args[1])
		_: return s.new(args[0], args[1], args[2])

## the physics overlay (Debug Draw 3D), or null
static func overlay() -> Script:
	return script("debug_overlay.gd")
