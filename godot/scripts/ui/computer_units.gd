class_name ComputerUnits
extends RefCounted
## The bike computers you can mount: different sizes and models, some without navigation.
## `order` = which pages (GaugeView page ids: 0 RIDE, 1 TRIP, 2 EFFORT, 3 AIR, 4 ELEV, 5 MAP) the unit has,
## `nav` = trail alerts (turns / features) and the map page. `scale` = drawn size of the HUD unit.

const UNITS := {
	"edge": {"name": "EDGE 840", "size": "LARGE", "scale": 1.22, "nav": true, "order": [0, 1, 2, 3, 4, 5],
		"body": Color("16181a"), "accent": Color("ffd21f"), "blurb": "Full navigation, every page"},
	"classic": {"name": "CLASSIC 540", "size": "MEDIUM", "scale": 1.0, "nav": true, "order": [0, 1, 2, 3, 4, 5],
		"body": Color("16181a"), "accent": Color("8be36a"), "blurb": "Navigation, map and alerts"},
	"sport": {"name": "SPORT 130", "size": "SMALL", "scale": 0.82, "nav": false, "order": [0, 1, 2, 3, 4],
		"body": Color("1d2b3a"), "accent": Color("5ab8ff"), "blurb": "No navigation, five pages"},
	"mini": {"name": "MINI 20", "size": "TINY", "scale": 0.66, "nav": false, "order": [0, 1],
		"body": Color("3a1618"), "accent": Color("ff6a4d"), "blurb": "No navigation, speed and trip"},
}
const ORDER := ["edge", "classic", "sport", "mini"]
const DEFAULT := "classic"

static func get_unit(id: String) -> Dictionary:
	return UNITS.get(id, UNITS[DEFAULT])

static func current() -> Dictionary:
	return get_unit(GameState.computer_id)

static func spec(id: String) -> String:
	var u := get_unit(id)
	return "%s  ·  %s  ·  %d PAGES" % [u.size, "NAVIGATION" if u.nav else "NO NAVIGATION", u.order.size()]
