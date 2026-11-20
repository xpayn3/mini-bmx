class_name ComputerUnits
extends RefCounted
## The bike computers you can mount: different sizes and models, some without navigation.
## `order` = which pages (GaugeView page ids: 0 RIDE, 1 TRIP, 2 EFFORT, 3 AIR, 4 ELEV, 5 MAP, 6 SYSTEM) the unit has
## (every unit has SYSTEM: frame rate + the 3D physics view),
## `nav` = trail alerts (turns / features) and the map page. `scale` = drawn size of the HUD unit.

const UNITS := {
	"edge": {"name": "VISTA 840", "size": "LARGE", "scale": 1.22, "nav": true, "order": [0, 1, 2, 3, 4, 5, 6],
		"body": Color("16181a"), "accent": Color("ffd21f"), "blurb": "Full navigation, every page"},
	"classic": {"name": "CLASSIC 540", "size": "MEDIUM", "scale": 1.0, "nav": true, "order": [0, 1, 2, 3, 4, 5, 6],
		"body": Color("16181a"), "accent": Color("8be36a"), "blurb": "Navigation, map and alerts"},
	"sport": {"name": "SPORT 130", "size": "SMALL", "scale": 0.82, "nav": false, "order": [0, 1, 2, 3, 4, 6],
		"body": Color("1d2b3a"), "accent": Color("5ab8ff"), "blurb": "No navigation, five pages"},
	"mini": {"name": "MINI 20", "size": "TINY", "scale": 0.66, "nav": false, "order": [0, 1, 6],
		"body": Color("3a1618"), "accent": Color("ff6a4d"), "blurb": "No navigation, speed and trip"},
}
const TITLES := ["RIDE", "TRIP", "EFFORT", "AIR", "ELEV", "MAP", "SYSTEM"]
const ORDER :=["edge", "classic", "sport", "mini"]
const DEFAULT := "classic"

static func get_unit(id: String) -> Dictionary:
	return UNITS.get(id, UNITS[DEFAULT])

static func current() -> Dictionary:
	return get_unit(GameState.computer_id)

## Per-device setup (GameState.computer_cfg[id], saved): `pages` = page ids switched off, `alerts` (navigation units),
## `beep` (the piezo), `light` (0 = on a press / alert, 1 = always lit).
const DEFAULTS := {"off": [], "alerts": true, "beep": true, "light": 0}

static func opt(id: String, key: String):
	var c: Dictionary = GameState.computer_cfg.get(id, {})
	return c.get(key, DEFAULTS[key])

static func set_opt(id: String, key: String, v) -> void:
	var c: Dictionary = GameState.computer_cfg.get(id, {}).duplicate()
	c[key] = v
	GameState.computer_cfg[id] = c

## the pages the player left on, in order (RIDE can't be switched off)
static func pages(id: String) -> Array:
	var off: Array = opt(id, "off")
	var out: Array = []
	for p in get_unit(id).order:
		if int(p) == 0 or not (int(p) in off): out.append(p)
	return out

static func spec(id: String) -> String:
	var u := get_unit(id)
	return "%s  ·  %s  ·  %d PAGES" % [u.size, "NAVIGATION" if u.nav else "NO NAVIGATION", u.order.size()]
