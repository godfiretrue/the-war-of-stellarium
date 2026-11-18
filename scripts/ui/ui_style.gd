class_name UiStyle
extends RefCounted
## Shared look for the menu, the HUD and the settings panel.
##
## Centralising the palette and the button styles is what stops the in-game HUD
## from looking like a different program than the main menu. Everything here is
## static: no node, no state.

const BG := Color(0.035, 0.040, 0.075)
const BAR := Color(0.035, 0.042, 0.062, 0.96)
const PANEL := Color(0.043, 0.050, 0.080, 0.97)
const PANEL_SOFT := Color(0.060, 0.069, 0.105, 0.96)

const ACCENT := Color(0.55, 0.62, 1.0)
const GOLD := Color(0.98, 0.83, 0.45)
## Thin trim used on every campaign panel; deliberately duller than GOLD.
const GOLD_TRIM := Color(0.72, 0.58, 0.30, 0.95)
const GOLD_LINE := Color(0.80, 0.67, 0.36, 0.75)
const DANGER := Color(0.86, 0.42, 0.40)

const TEXT := Color(0.86, 0.88, 0.95)
const TEXT_DIM := Color(0.58, 0.61, 0.71)
const TEXT_DISABLED := Color(0.42, 0.44, 0.52)

const HUMAN := Color(0.35, 0.60, 1.0)
const ELVES := Color(0.30, 0.90, 0.50)
const NEUTRAL := Color(0.72, 0.74, 0.80)

# --- One font scale ------------------------------------------------------
# Every game screen picks one of these three sizes so the HUD, the settings
# panel and the menu never drift apart.
const FONT_TITLE := 20
const FONT_BODY := 13
const FONT_SMALL := 11


static func faction_color(faction: int) -> Color:
	match faction:
		Balance.Faction.HUMANS:
			return HUMAN
		Balance.Faction.ELVES:
			return ELVES
	return NEUTRAL


## Flat rounded box with an optional accent bar on the left edge.
static func box(fill: Color, border: Color, bar_width: int = 4,
		margin_left: float = 16.0, margin_v: float = 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.border_width_left = bar_width
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	box.content_margin_left = margin_left
	box.content_margin_right = 12.0
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box


static func flat(fill: Color, border: Color, radius: int = 3) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	return box


static func panel_box() -> StyleBoxFlat:
	var box := flat(PANEL, Color(0.22, 0.25, 0.40, 0.85), 4)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	return box


static func capsule(fill: Color, border: Color) -> StyleBoxFlat:
	# Radius stays below half the pill height: a radius that exactly reaches the
	# mid-line makes StyleBoxFlat's border arcs overlap into visible notches.
	var box := flat(fill, border, 9)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box


## The large, left-aligned buttons of the main menu.
static func apply_menu_button(button: Button) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	button.add_theme_stylebox_override("normal", box(Color(0.08, 0.09, 0.16, 0.55), Color(0.3, 0.33, 0.5, 0.6)))
	button.add_theme_stylebox_override("hover", box(Color(0.16, 0.18, 0.36, 0.8), ACCENT))
	button.add_theme_stylebox_override("focus", box(Color(0.16, 0.18, 0.36, 0.8), ACCENT))
	button.add_theme_stylebox_override("pressed", box(Color(0.22, 0.25, 0.5, 0.9), Color.WHITE))
	button.add_theme_stylebox_override("disabled", box(Color(0.06, 0.07, 0.11, 0.4), Color(0.2, 0.21, 0.28, 0.5)))


## Compact HUD button: same language as the menu, tighter padding.
static func apply_hud_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	button.add_theme_font_size_override("font_size", 12)
	var normal := box(Color(0.09, 0.10, 0.17, 0.90), Color(0.26, 0.29, 0.45, 0.9), 3, 12.0, 6.0)
	var hover := box(Color(0.16, 0.18, 0.33, 0.95), ACCENT, 3, 12.0, 6.0)
	var pressed := box(Color(0.22, 0.25, 0.48, 0.95), Color.WHITE, 3, 12.0, 6.0)
	var disabled := box(Color(0.06, 0.07, 0.11, 0.55), Color(0.18, 0.19, 0.26, 0.7), 3, 12.0, 6.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)


## The one action the player is expected to take next (end turn, or march when
## a move is armed).
static func apply_primary_button(button: Button) -> void:
	apply_hud_button(button)
	button.add_theme_color_override("font_color", Color(0.10, 0.09, 0.05))
	button.add_theme_color_override("font_hover_color", Color(0.06, 0.05, 0.02))
	button.add_theme_color_override("font_pressed_color", Color(0.06, 0.05, 0.02))
	button.add_theme_color_override("font_disabled_color", Color(0.35, 0.33, 0.27))
	button.add_theme_stylebox_override("normal", box(GOLD, Color(1.0, 0.90, 0.60), 3, 12.0, 6.0))
	button.add_theme_stylebox_override("hover", box(Color(1.0, 0.90, 0.58), Color.WHITE, 3, 12.0, 6.0))
	button.add_theme_stylebox_override("pressed", box(Color(0.92, 0.76, 0.38), Color.WHITE, 3, 12.0, 6.0))
	button.add_theme_stylebox_override("disabled", box(Color(0.20, 0.19, 0.16, 0.7), Color(0.24, 0.23, 0.20, 0.8), 3, 12.0, 6.0))


## Quiet, text-only button for save/menu/settings.
static func apply_ghost_button(button: Button) -> void:
	apply_hud_button(button)
	button.add_theme_color_override("font_color", TEXT_DIM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", box(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 10.0, 6.0))
	button.add_theme_stylebox_override("hover", box(Color(0.16, 0.18, 0.33, 0.75), ACCENT, 2, 10.0, 6.0))
	button.add_theme_stylebox_override("pressed", box(Color(0.22, 0.25, 0.48, 0.9), Color.WHITE, 2, 10.0, 6.0))
	button.add_theme_stylebox_override("disabled", box(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 10.0, 6.0))


## Small tab/header button: same family as the HUD buttons, gold-edged.
static func apply_tab_button(button: Button) -> void:
	apply_hud_button(button)
	button.add_theme_stylebox_override(
		"normal", box(Color(0.055, 0.065, 0.100, 0.96), GOLD_TRIM, 3, 9.0, 4.0)
	)
	button.add_theme_stylebox_override(
		"hover", box(Color(0.13, 0.15, 0.25, 0.98), GOLD, 3, 9.0, 4.0)
	)


# --- Campaign theme ------------------------------------------------------

## The campaign HUD theme: flat dark-navy panels with a thin gold trim, one
## font scale and one tooltip look. Node overrides still add accents, but every
## default comes from here so the pieces share one recipe.
static func hud_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_BODY
	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", FONT_BODY)

	var panel := hud_panel()
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	var tip := flat(Color(0.025, 0.030, 0.050, 0.98), GOLD_TRIM, 3)
	tip.set_border_width_all(2)
	tip.set_content_margin_all(8.0)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", FONT_SMALL)

	# Scrollbars only appear when a queue or report is long. Keep them thin and
	# quiet so they never compete with the rows they scroll.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	track.content_margin_left = 2.0
	track.content_margin_right = 2.0
	var grabber := flat(Color(0.26, 0.30, 0.42, 0.85), Color(0.0, 0.0, 0.0, 0.0), 3)
	var grabber_hot := flat(GOLD_TRIM, Color(0.0, 0.0, 0.0, 0.0), 3)
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hot)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_hot)
	return theme


## Main campaign panel: dark navy, thin gold trim, small corner radius.
static func hud_panel() -> StyleBoxFlat:
	var box := flat(PANEL, GOLD_TRIM, 5)
	box.set_border_width_all(1)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	return box


## Slimmer box for nested rows (order queue, battle entries).
static func row_box() -> StyleBoxFlat:
	var box := flat(Color(0.070, 0.080, 0.120, 0.92), Color(0.22, 0.25, 0.38, 0.75), 3)
	box.set_content_margin_all(4.0)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	return box


static func row_hover_box() -> StyleBoxFlat:
	var box := flat(Color(0.12, 0.15, 0.26, 0.96), GOLD_TRIM, 3)
	box.set_content_margin_all(4.0)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	return box


## Unit card in the garrison strip: faction-edged tile.
static func unit_card_box(faction: int) -> StyleBoxFlat:
	var accent := faction_color(faction)
	accent.a = 0.85
	var box := flat(Color(0.075, 0.085, 0.125, 0.96), accent, 3)
	box.set_content_margin_all(5.0)
	box.content_margin_left = 7.0
	box.content_margin_right = 7.0
	return box
