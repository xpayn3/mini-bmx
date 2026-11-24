class_name StorePage
extends RefCounted
## The SHOP (Garage mode "shop", menu SHOP / --shop): every bike and part the game sells, in the studio
## (StudioSet + HqStill). Tabs from Catalog.TABS along the top; the products of a tab as picture cards along the
## bottom (worst -> best, price tag, OWNED badge); the product's card on the left (what it is, tier, what it does,
## price, your cash, BUY). Picking a card shows it: a complete bike / frameset rolls in, a part is fitted to YOUR
## bike (the one you ride, its saved build) and the camera moves to it. Nothing is saved by looking.
## BUY pays from GameState.money and adds it to GameState.owned, with the celebration (StorePurchase); a part
## bought can then be fitted to your bike right there. Tests: BMX_SHOP_TAB=<tab>, BMX_SHOP_PICK=<key>,
## BMX_SHOP_BUY=1 (buys the pick 2 s in), BMX_MONEY=n.

const VIEW := {   # camera per tab: [orbit, pitch, dist, focus] (as Garage.VIEWS). Aimed low: the card strip covers
	# the bottom third, so the part sits in the open space above it
	"bikes": [0.5, 6.0, 6.4, Vector3(0, 0.3, 0)], "frames": [0.5, 6.0, 6.4, Vector3(0, 0.3, 0)],
	"susp": [1.0, 10.0, 2.8, Vector3(0.1, 0.3, 0)], "wheels": [0.25, 8.0, 2.8, Vector3(0.6, 0.15, 0)],
	"cockpit": [0.9, 14.0, 1.9, Vector3(0.45, 0.75, 0)], "brakes": [2.2, 8.0, 2.2, Vector3(0.45, 0.12, 0)],
	"drive": [-1.3, 8.0, 1.7, Vector3(-0.3, 0.1, 0)], "seat": [-0.6, 12.0, 2.0, Vector3(-0.35, 0.65, 0)],
	"lights": [0.9, 14.0, 1.9, Vector3(0.45, 0.75, 0)],
}
## what a tier step on the trail reads as
const PERF_TEXT := {"brakeGrip": "braking grip", "steerRate": "steering response", "popPower": "pop off lips"}

var g: Garage
var tab := "bikes"
var sel: Dictionary = {}
var base_frame := "dh"         # the player's bike (the one ridden): parts are shown on it, fitted to it
var base_build: Dictionary = {}
var wallet: Label
var _shown_money := 0
var _items: Array = []

func _init(garage: Garage) -> void:
	g = garage
	base_frame = GameState.bike_id if GameState.BIKES[GameState.bike_id].get("garage", false) else "dh"
	base_build = BikeBuild.load_build(base_frame)
	_shown_money = GameState.money

## the cash in the header (counts when it changes)
func make_wallet() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", Tokens.S3)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(UITheme.caption("CASH", Tokens.INK_SOFT, Tokens.T_SM))
	wallet = UITheme.display(Shop.fmt(GameState.money), Tokens.T_2XL, Tokens.INK, Tokens.SLANT)
	box.add_child(wallet)
	return box

func count_wallet(to: int, secs := 1.1) -> void:
	var from := _shown_money
	_shown_money = to
	if wallet == null: return
	var tw := wallet.create_tween()
	tw.tween_method(func(v: float): if is_instance_valid(wallet): wallet.text = Shop.fmt(int(v)), float(from), float(to), secs) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func show_tab(t: String) -> void:
	var first := t != tab or sel.is_empty()
	tab = t
	_items = Catalog.items(t, g)
	var want := ""
	if not first and not sel.is_empty(): want = sel.key
	if want == "" and Env.s("BMX_SHOP_PICK") != "": want = Env.s("BMX_SHOP_PICK")
	if want == "" or not _items.any(func(p): return p.key == want):
		want = _fitted_key()
	if want == "" and not _items.is_empty(): want = _items[0].key
	_fill_strip(want)
	if first:
		var v: Array = VIEW.get(t, VIEW.bikes)
		g.orbit_t = v[0] + round((g.orbit_t - v[0]) / TAU) * TAU
		g.pitch_t = v[1]; g.dist_t = v[2]; g.focus_t = v[3]
	for p in _items:
		if p.key == want:
			select(p, first)
			break

## the product of this tab your bike carries now (picked first), "" if none
func _fitted_key() -> String:
	var sku: Dictionary = base_build.get("sku", {})
	for p in _items:
		if p.kind == "frame" and p.id == base_frame: return p.key
		if sku.get(p.kind, "") == p.id: return p.key
		match p.kind:
			"fork": if base_build.suspension.get("fork_model", "") == p.id: return p.key
			"shock": if base_build.suspension.get("shock_model", "") == p.id: return p.key
			"rim": if base_build.wheels.get("rim_model", "") == p.id: return p.key
			"tyre": if base_build.wheels.get("tyre_model", "") == p.id: return p.key
			"bar": if base_build.bars.get("model", "") == p.id: return p.key
			"cassette": if base_build.drive.get("cassette", "") == p.id: return p.key
	return ""

func _fill_strip(want: String) -> void:
	for c in g._show_strip.row.get_children(): c.queue_free()
	var cards := []
	for p in _items:
		var c: Dictionary = p.duplicate()
		c.spec = "%s  ·  %s  ·  %s" % [BikeBuild.star_text(p.tier), Catalog.TIER_NAMES[p.tier], _no_stars(p.spec)]
		if GameState.owns(p.key): c.badge = "OWNED"
		cards.append(c)
	g._cards(cards, want, func(k):
		for p in _items:
			if p.key == k:
				select(p, false)
				_fill_strip.call_deferred(k)
				return, false, g._show_strip, Garage.SHOW_CARD)

## show a product: on the stand (bike / frameset) or fitted to your bike
func select(p: Dictionary, quiet := false) -> void:
	var was := sel
	sel = p
	if p.kind in ["edition", "frame"]:
		g.shop_show(p.frame, (p.build as Dictionary).duplicate(true), not quiet and not was.is_empty() and was.get("key") != p.key)
	else:
		var b := base_build.duplicate(true)
		Catalog.apply(b, p)
		g.shop_show(base_frame, b, false)
	details()

func details() -> void:
	var p := sel
	for c in g.body.get_children(): c.queue_free()
	var B := g.body
	var kicker := "%s  ·  %s" % [String(Catalog.KIND_LABEL.get(p.kind, p.kind)).to_upper(), p.brand] if p.kind != "edition" else String(p.brand)
	B.add_child(UITheme.caption(kicker, Tokens.INK_SOFT, Tokens.T_SM))
	var nm := UITheme.display(String(p.name).to_upper(), Tokens.T_3XL, Tokens.INK, Tokens.SLANT_TITLE)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	B.add_child(nm)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S3)
	var st := UITheme.text(BikeBuild.star_text(p.tier), Color("e9a400"), Tokens.T_2XL)
	row.add_child(st)
	var tier := UITheme.display(Catalog.TIER_NAMES[p.tier], Tokens.T_LG, Tokens.INK, 0.0)
	var ts := UITheme.btn_box(_tier_col(p.tier), Tokens.CLEAR, 0, Tokens.R_SM, Tokens.S3)
	ts.content_margin_top = 0; ts.content_margin_bottom = 0
	tier.add_theme_stylebox_override("normal", ts)
	tier.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tier)
	B.add_child(row)
	var sp := UITheme.text(_no_stars(p.spec), Tokens.INK_SOFT, Tokens.T_MD)
	sp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	B.add_child(sp)
	var perf := _perf_line(p)
	if perf != "":
		var pl := UITheme.text(perf, Tokens.INK, Tokens.T_MD)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		B.add_child(pl)
	var where := "A complete bike, ready to ride." if p.kind == "edition" else \
		("The frame with its shock: build it up in the garage." if p.kind == "frame" else
		"Shown on your %s." % String(GameState.BIKES[base_frame].label))
	var wl := UITheme.caption(where, Tokens.INK_SOFT, Tokens.T_SM)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	B.add_child(wl)
	var gap := Control.new(); gap.custom_minimum_size.y = Tokens.S5
	B.add_child(gap)
	# price + cash
	B.add_child(UITheme.caption("PRICE", Tokens.INK_SOFT, Tokens.T_SM))
	B.add_child(UITheme.display(Shop.fmt(p.price), Tokens.T_3XL + 16, Tokens.INK, Tokens.SLANT))
	var owned := GameState.owns(p.key)
	var short := int(p.price) - GameState.money
	if not owned:
		var after := HBoxContainer.new()
		after.add_theme_constant_override("separation", Tokens.S3)
		after.add_child(UITheme.caption("YOUR CASH  " + Shop.fmt(GameState.money), Tokens.INK_SOFT, Tokens.T_SM))
		if short <= 0: after.add_child(UITheme.caption("→  " + Shop.fmt(GameState.money - int(p.price)), Tokens.INK, Tokens.T_SM))
		B.add_child(after)
	var gap2 := Control.new(); gap2.custom_minimum_size.y = Tokens.S4
	B.add_child(gap2)
	var buy: Button
	if owned:
		buy = UITheme.make_button("✓  OWNED", func(): pass, "secondary", Tokens.T_XL)
		buy.disabled = true
	elif short > 0:
		buy = UITheme.make_button("NEED %s MORE" % Shop.fmt(short), func(): pass, "secondary", Tokens.T_XL)
		buy.disabled = true
	else:
		buy = UITheme.make_button("BUY  ·  %s" % Shop.fmt(p.price), _buy, "primary", Tokens.T_XL)
	buy.custom_minimum_size.y = Tokens.H_BTN + 8
	B.add_child(buy)
	if owned and p.kind not in ["edition", "frame"] and _fitted_key() != p.key:
		var fit := UITheme.make_button("FIT TO MY %s" % String(GameState.BIKES[base_frame].label).to_upper(), fit_sel, "secondary", Tokens.T_LG)
		fit.custom_minimum_size.y = Tokens.H_BTN
		B.add_child(fit)

## a bike's spec line starts with its own stars ("★★☆☆☆  ·  FREERIDE ..."): the store shows them already
static func _no_stars(spec: String) -> String:
	if spec.begins_with("★") or spec.begins_with("☆"): return spec.substr(5).strip_edges().trim_prefix("·").strip_edges()
	return spec

static func _tier_col(t: int) -> Color:
	return [Tokens.FILL, Color("d9dde5"), Color("bfe3c6"), Color("bcd7f5"), Color("e3c9f5"), Tokens.ACCENT][clampi(t, 0, 5)]

func _perf_line(p: Dictionary) -> String:
	if not Catalog.PERF.has(p.kind): return ""
	var d := (int(p.tier) - 3) * float(Catalog.PERF[p.kind][1]) * 100.0
	if absf(d) < 0.1: return "On the trail: the reference %s." % PERF_TEXT.get(Catalog.PERF[p.kind][0], "")
	return "On the trail: %+.1f %% %s." % [d, PERF_TEXT.get(Catalog.PERF[p.kind][0], "")]

func _buy() -> void:
	var p := sel
	var before := GameState.money
	if Env.s("BMX_SHOP_PROBE") != "": print("SHOPBUY %s price=%d cash=%d" % [p.key, int(p.price), before])
	if not GameState.buy(p.key, int(p.price)): return
	if p.kind == "edition":   # a complete bike comes with everything on it
		for k in GameState.build_keys(p.frame, p.build): GameState.owned[k] = GameState.owned.get(k, Time.get_unix_time_from_system())
		GameState.save()
	count_wallet(GameState.money, 1.4)
	var pop := StorePurchase.new()
	pop.setup(g, p, before, GameState.money, p.kind not in ["edition", "frame"])
	pop.fit_requested.connect(fit_sel)
	pop.closed.connect(func(): details(); _fill_strip(p.key))
	g.ui.get_child(0).add_child(pop)
	details()

## puts the selected (owned) part on the player's bike and saves that build
func fit_sel() -> void:
	var p := sel
	if p.kind in ["edition", "frame"]: return
	var b := BikeBuild.load_build(base_frame)
	Catalog.apply(b, p)
	BikeBuild.save_build(b, base_frame)
	base_build = b
	g._toast("FITTED TO YOUR %s" % String(GameState.BIKES[base_frame].label).to_upper())
	details()
	_fill_strip(p.key)
