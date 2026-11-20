class_name Tokens
extends RefCounted
## Design tokens: every colour, size, gap, corner and border the menus use. UI code reads these (and the
## components in UITheme built from them) instead of writing numbers, so the title menu, the garage and
## the settings windows stay one look. Change a value here and every screen follows.

# ---------------------------------------------------------------- colour
## brand
const ACCENT := Color("ffd21f")        # the yellow: primary actions, the selected thing, highlights
const ACCENT_HOT := Color("ffe05c")    # ... hovered
const ACCENT_DOWN := Color("e8bb00")   # ... pressed
const ACCENT_TINT := Color("fff4c2")   # a yellow wash behind a selected card
## paper (the white cards) and ink (text / outlines on them)
const PAPER := Color("ffffff")
const PAGE := Color("f3f5f9")          # a sunken area / hover on paper
const FILL := Color("e7eaf1")          # a button / field at rest
const FILL_HOT := Color("d6dce8")      # ... hovered
const LINE := Color("d3d9e4")          # hairlines, inactive outlines
const INK := Color("151a23")           # text, outlines, the selected underline
const INK_SOFT := Color("6b7487")      # secondary text: captions, hints, specs
const INK_FAINT := Color("a4acbb")     # disabled
const CLEAR := Color(0, 0, 0, 0)
## on the 3D scene (no card behind)
const ON_SCENE := Color("ffffff")
const ON_SCENE_SOFT := Color(1, 1, 1, 0.6)
const SCENE_SHADOW := Color(0, 0, 0, 0.35)
## overlays
const SHADOW := Color(0, 0, 0, 0.28)   # card drop shadow
const THUMB := Color(0, 0, 0, 0.18)    # scrollbar thumb
const THUMB_HOT := Color(0, 0, 0, 0.4)
const TRACK := Color(0, 0, 0, 0.1)     # meter / slider groove on paper
const PILL := Color(1, 1, 1, 0.92)     # a floating hint pill over the scene

# ---------------------------------------------------------------- space (px, a 4-step scale)
const S1 := 2
const S2 := 4
const S3 := 8
const S4 := 12
const S5 := 16
const S6 := 24
const S7 := 32
const S8 := 48

# ---------------------------------------------------------------- corners / borders / shadow
# flat, Metro-like: no outlines, no shadows, only a hint of a bevel on the corners
const R_SM := 1      # key caps, meters
const R_MD := 2      # buttons, fields, chips
const R_LG := 2      # big buttons, cards in a grid
const R_XL := 3      # the main cards
const R_PILL := 3
const B_HAIR := 1
const B := 2
const B_BOLD := 3
const SHADOW_SIZE := 0     # flat: cards cast no shadow
const SHADOW_Y := 0
const MARK := 4            # a coloured bar marking the selected / focused thing (instead of an outline)

# ---------------------------------------------------------------- type
const T_XS := 12     # specs, version line
const T_SM := 14     # captions, hints, notes
const T_MD := 16     # buttons, rows
const T_LG := 18     # section headings
const T_XL := 22     # tabs, links
const T_2XL := 28    # big names
const T_3XL := 40    # screen titles, hero buttons
const T_DISPLAY := 100   # the game title
const W_MEDIUM := 600
const W_BOLD := 700
const W_BLACK := 800
const SLANT := 0.12        # display type leans forward
const SLANT_TITLE := 0.2
const TRACKING := 1        # extra letter spacing for captions

# ---------------------------------------------------------------- sizes
const H_CHIP := 40       # a small button / chip / field
const H_BTN := 50        # a bottom-bar button
const H_HERO := 80       # RIDE / GO
const H_SUB := 62        # a big button with a second line
const H_ROW_CTL := 200   # min width of a row's control (stepper, slider)
const STEP_ARROW := Vector2(30, 32)
const SLAB := Vector2(4, 16)        # the yellow mark before a heading
const SLAB_WIDE := Vector2(36, 6)   # ... before the tagline
const METER_SEGMENTS := 12
const CARD_W := 410       # the side cards (title menu, garage options)
const CARD_THUMB_H := 156
const CARD_TILE_H := 236
const CARD_TILE_W := 264   # garage part cards: one slidable row, a card and a bit of the next in view
const SCROLL_W := 2       # scrollbar thumb half-width
