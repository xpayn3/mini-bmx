class_name SunSky
extends RefCounted
## The light of a clear day from physics (2026-11-26, user: "realistic values, realistic super nice light"; research notes in
## docs/research/lighting.md). Everything comes from the sun's elevation:
##  - the sun's direct light and colour: extra-terrestrial sun dimmed per RGB channel by the air it crosses
##    (Kasten-Young airmass x Rayleigh + aerosol + ozone optical depths), so a low sun is DIMMER and redder, never brighter
##  - the sky's light on flat ground (IES clear-sky fit by day, ~10x per 2.6 deg of twilight under the horizon)
##  - the moon (a full moon ~0.15 lux, its sky lit the same way as the day's) + starlight / airglow
##  - exposure from that illuminance (not from what the camera sees: Ghost of Tsushima, Advances 2021), with only partial
##    adaptation below sunset so dusk / night are really darker but still readable
## Out comes engine light: lux x `scale`, where `scale` folds in the exposure's adaptation, so the tonemap exposure stays
## one constant all day (lamps, LEDs and screens keep the brightness they were tuned at). Pure maths: no nodes, cheap.

const E_SC := 127500.0                  # lux, the sun's direct light above the air
## zenith optical depth per channel (650 / 550 / 450 nm): Rayleigh + ozone, and the aerosol (x LightLab turbidity);
## at turbidity 1 they add up to the research's 0.153 / 0.224 / 0.355
const TAU_CLEAN := Vector3(0.073, 0.124, 0.225)
const TAU_AEROSOL := Vector3(0.080, 0.100, 0.130)
const LUM := Vector3(0.2126, 0.7152, 0.0722)
const MOON_DNI := 0.15                  # lux, a full moon's direct light at its height (~15 deg)
const MOON_EL := 15.0
const STARS := 0.002                    # lux, starlight + airglow
const NOON_METER := 66000.0             # the meter illuminance at the noon sun (62 deg): the reference exposure
const G_ENGINE := 1.36                  # engine units for that: noon sun energy ~2.0, its sky ~0.3
const EV_FULL := 12.0                   # above this the eye / camera adapts fully (day -> golden hour)
const EV_SUNSET := 7.6

## Kasten-Young relative airmass (el in degrees)
static func airmass(el: float) -> float:
	var e := maxf(el, -1.0)
	return 1.0 / (sin(deg_to_rad(e)) + 0.50572 * pow(e + 6.07995, -1.6364))

## the sun's direct light at this elevation: rgb transmittance (linear) and lux (normal to the beam)
static func sun_transmit(el: float) -> Vector3:
	var m := airmass(el)
	var tau := TAU_CLEAN + TAU_AEROSOL * LightLab.v("turbidity")
	return Vector3(exp(-tau.x * m), exp(-tau.y * m), exp(-tau.z * m))

static func sun_dni(el: float) -> float:
	var vis := smoothstep(-0.9, 0.4, el)     # the disc goes under the horizon
	return E_SC * sun_transmit(el).dot(LUM) * vis

## the clear sky's light on flat ground (lux): IES fit by day, falling ~10x per 2.6 deg in twilight (3.4 lux at -6, ~0.01 at -12)
static func sky_lux(el: float) -> float:
	var k := LightLab.v("sky_ratio")
	if el >= 0.0: return (800.0 + 15500.0 * sqrt(sin(deg_to_rad(el)))) * k
	return 800.0 * pow(10.0, el / 2.6) * k

## the exposure's adaptation in stops below the noon look, from the metered EV100 (incident: EV = log2(E / 2.5)):
## full adaptation over the day, ~0.9 stop darker by sunset, then 0.25 stop per EV into the night (moonlight ~4 stops under:
## the research's 3-5, readable with the bike's lamp)
## (the slopes and EV_FULL are LightLab knobs: adapt_dusk 0.2, adapt_night 0.25, ev_full 12)
static func adapt_stops(ev: float) -> float:
	var full := LightLab.v("ev_full")
	var dusk := LightLab.v("adapt_dusk")
	var sunset := minf(EV_SUNSET, full)
	if ev >= full: return 0.0
	if ev >= sunset: return -dusk * (full - ev)
	return -dusk * (full - sunset) - LightLab.v("adapt_night") * (sunset - ev)

## the whole light for a sun elevation. L = LightSettings values (sun, sky, moon, warmth multipliers)
static func state(el: float, L: Dictionary) -> Dictionary:
	var se := deg_to_rad(maxf(el, 0.0))
	var dni := sun_dni(el)
	var sky := sky_lux(el)
	var me := deg_to_rad(MOON_EL)
	var moon := LightLab.v("moon_lux")
	var moon_sky := moon * 0.12 * 2.0 * LightLab.v("sky_ratio")   # its sky: the day's diffuse / direct ratio at 15 deg (x2: no sun-side glare clamp)
	var night_sky := moon_sky + STARS
	# the meter: flat ground + upright things at any heading (avg 1/pi of the beam), the way a camera sees a scene
	var meter := sky + night_sky + dni * (0.5 * sin(se) + 0.16 * cos(se)) + moon * (0.5 * sin(me) + 0.16 * cos(me))
	var ev := log(meter / 2.5) / log(2.0)
	var ev_noon := log(NOON_METER / 2.5) / log(2.0)
	var stops := adapt_stops(minf(ev, ev_noon))
	var scale := G_ENGINE * pow(2.0, stops) / meter      # engine units per lux
	var t := sun_transmit(el)
	var tn := t / maxf(t.x, 1e-6)                        # colour: brightest channel = 1
	var warm := float(L.get("warmth", 1.0))
	var col_lin := Vector3.ONE.lerp(tn, clampf(warm, 0.0, 2.0)).clamp(Vector3(0.002, 0.002, 0.002), Vector3(1, 1, 1))
	var col_y := col_lin.dot(LUM)
	var sun_on := el > -1.0
	return {
		"el": el, "ev": ev, "stops": stops, "scale": scale,
		"sun_on": sun_on,
		# the key light: the sun while it is up, the moon after (both are DirectionalLight energies on a white surface facing it)
		"sun_energy": dni * scale / maxf(col_y, 0.05) * float(L.get("sun", 1.0)),
		"sun_color": Color(col_lin.x, col_lin.y, col_lin.z).linear_to_srgb(),
		"moon_energy": moon * scale * float(L.get("moon", 1.0)),
		# the sky's light on flat ground the sky shader must give (engine units; the sky meter sets its brightness to this)
		"sky_irr": (sky + night_sky) * scale * float(L.get("sky", 1.0)),
		"lux_sun": dni, "lux_sky": sky + night_sky, "lux_meter": meter,
	}
