extends MenuBase
## Credits + licences (title menu CREDITS). Everything a shipped build has to credit lives in CREDITS below:
## add a line when an asset that asks for attribution (CC-BY, MIT, OFL...) goes into the game.
## The "Engine" page prints Godot's own licence and the third-party components inside it (required by its MIT
## licence and theirs); the texts come from the engine itself, so they always match the build.

const GAME := "RUNOUT"
const STUDIO := ""   # your name / studio as it should appear (before release)

const COPYRIGHT := "© 2026 Luka Grcar. All rights reserved."

## shown first on the Licences page
const NOTICE := "RUNOUT is proprietary software. All rights reserved. This game is not free software and is not supposed to be copied, shared, resold or distributed in any form, in whole or in part, without written permission from the author. Third-party components listed here stay under their own licences."

## [section, [[what, who / where, licence], ...]]
const CREDITS := [
	["3D MODELS", [
		["\"DH bike frame\" (Goat DH)", "Once_a_goat_death, sketchfab.com/3d-models/dh-bike-frame-4646f6b0a2c145278bce3d11abb1a0fe. Rigged and adapted for the game.", "CC BY 4.0, creativecommons.org/licenses/by/4.0"],
	]],
	["TEXTURES + LIGHT", [
		["Kloofendal 48d Partly Cloudy (Pure Sky) HDRI", "Poly Haven, polyhaven.com", "CC0"],
		["Kloofendal 43d Clear, Autumn Field, Belfast Sunset, Qwantani Dusk 2 (Pure Sky) and Rogland Clear Night HDRIs", "Poly Haven, polyhaven.com", "CC0"],
		["Painted Concrete 02", "Poly Haven, polyhaven.com", "CC0"],
		["Denim Fabric 06, Poly Wool Herringbone, Ribbed Corduroy, Rough Linen and Cotton Jersey textures", "Poly Haven, polyhaven.com", "CC0"],
		["Broken Brick Wall", "Amal Kumar / Poly Haven, polyhaven.com", "CC0"],
		["Paper003, Metal009, Rubber004", "ambientCG, ambientcg.com", "CC0"],
		["PineNeedles001, LeafSet005 (tree and bush leaves)", "ambientCG, ambientcg.com", "CC0"],
	]],
	["SOUND", [
		["Tires on gravel road", "freesound_community via Pixabay", "Pixabay Content License"],
		["Bicycle forward movement", "freesound_community via Pixabay", "Pixabay Content License"],
		["Crumpling paper", "liecio via Pixabay", "Pixabay Content License"],
	]],
	["FONTS", [
		["Doto", "The Doto Project Authors, github.com/oliverlalan/Doto", "SIL Open Font License 1.1"],
		["Barlow + Barlow Condensed", "The Barlow Project Authors (Jeremy Tribby), github.com/jpt/barlow", "SIL Open Font License 1.1"],
		["Anton", "The Anton Project Authors (Vernon Adams), fonts.google.com/specimen/Anton", "SIL Open Font License 1.1"],
		["Caveat", "The Caveat Project Authors (Impallari Type), github.com/googlefonts/caveat", "SIL Open Font License 1.1"],
		["Noto Sans Symbols + Symbols 2", "The Noto Project Authors, github.com/notofonts", "SIL Open Font License 1.1"],
	]],
	["SOFTWARE", [
		["Godot Engine", "Juan Linietsky, Ariel Manzur and contributors, godotengine.org (see Engine)", "MIT"],
		[".NET runtime", ".NET Foundation and contributors", "MIT"],
		["Steamworks.NET", "Riley Labrecque, github.com/rlabrecque/Steamworks.NET", "MIT"],
		["Steamworks SDK (steam_api64)", "Valve Corporation", "Steamworks SDK Access Agreement"],
		["Debug Draw 3D", "DmitriySalnikov, github.com/DmitriySalnikov/godot_debug_draw_3d", "MIT"],
	]],
]

## full texts of the licences that require their text to ship (shown on the Licences page)
const LICENSE_FILES := [
	["Steamworks.NET", "res://addons/steamworks/Steamworks.NET-LICENSE.txt"],
	["Debug Draw 3D", "res://addons/debug_draw_3d/LICENSE"],
	["Doto font (SIL OFL 1.1)", "res://assets/fonts/Doto-OFL.txt"],
	["Barlow fonts (SIL OFL 1.1)", "res://assets/fonts/Barlow-OFL.txt"],
	["Anton font (SIL OFL 1.1)", "res://assets/fonts/Anton-OFL.txt"],
	["Caveat font (SIL OFL 1.1)", "res://assets/fonts/Caveat-OFL.txt"],
	["Noto Symbols fonts (SIL OFL 1.1)", "res://assets/fonts/NotoSymbols-OFL.txt"],
	["DH bike frame (CC BY 4.0)", "res://assets/dhframe_LICENSE.txt"],
]

func _title() -> String: return "CREDITS"

func _pages() -> Array:
	return [_credits(), _licences(), _engine()]

func _credits() -> Control:
	var p := _page("Credits")
	_section(p, GAME)
	_hint(p, ("Made by " + STUDIO) if STUDIO != "" else "Made with Godot Engine.")
	_hint(p, COPYRIGHT)
	for sec in CREDITS:
		_section(p, sec[0])
		for it in sec[1]:
			var l := _lbl(it[0], 15, INK, true)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			p.add_child(l)
			_hint(p, "%s  ·  %s" % [it[1], it[2]])
	_section(p, "NOTE")
	_hint(p, "All brands, bikes, parts and sponsors in the game are made up. Any likeness to real companies is coincidental.")
	return p

func _licences() -> Control:
	var p := _page("Licences")
	_section(p, "NOT FOR DISTRIBUTION")
	_hint(p, COPYRIGHT)
	_hint(p, NOTICE)
	_section(p, "END USER LICENCE AGREEMENT")
	_hint(p, _read("res://EULA.txt"))
	for lf in LICENSE_FILES:
		_section(p, String(lf[0]).to_upper())
		_hint(p, _read(lf[1]))
	return p

func _engine() -> Control:
	var p := _page("Engine")
	_section(p, "GODOT ENGINE")
	_hint(p, "This game uses Godot Engine, available under the following license:")
	_hint(p, Engine.get_license_text())
	_section(p, "THIRD-PARTY COMPONENTS IN GODOT")
	for c in Engine.get_copyright_info():
		var lines := []
		for part in c.parts:
			lines.append(", ".join(part.copyright) + "  ·  " + String(part.license))
		var l := _lbl(String(c.name), 14, INK, true)
		p.add_child(l)
		_hint(p, "\n".join(lines))
	_section(p, "LICENSE TEXTS")
	var info: Dictionary = Engine.get_license_info()
	for k in info:
		_section(p, String(k))
		_hint(p, String(info[k]))
	return p

static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else "(missing: " + path + ")"
