class_name UITheme
extends RefCounted

## Programmatic Motorsport UI Theme with CJK-capable SystemFont and sleek dark-glass styling.

const BG_DARK := Color(0.055, 0.072, 0.115, 0.86)
const BG_CARD := Color(0.082, 0.105, 0.162, 0.90)
const BG_CARD_HOVER := Color(0.125, 0.160, 0.245, 0.96)
const ACCENT_RED := Color(1.0, 0.20, 0.34)
const ACCENT_CYAN := Color(0.0, 0.88, 1.0)
const ACCENT_GOLD := Color(1.0, 0.78, 0.14)
const TEXT_PRIMARY := Color(0.96, 0.97, 0.99)
const TEXT_MUTED := Color(0.66, 0.72, 0.82)
const BORDER_SUBTLE := Color(0.24, 0.30, 0.44, 0.75)

static var _cached_theme: Theme = null
static var _cached_font: SystemFont = null


static func get_font() -> Font:
	if _cached_font != null:
		return _cached_font
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"PingFang SC",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Hiragino Sans GB",
		"WenQuanYi Micro Hei",
		"Source Han Sans SC",
		"Segoe UI",
		"DejaVu Sans",
		"sans-serif"
	])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_cached_font = sf
	return _cached_font


static func build_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme
	var th := Theme.new()
	var font := get_font()
	th.default_font = font
	th.default_font_size = 16

	# Panel container
	th.set_stylebox("panel", "PanelContainer", make_panel_box(BG_DARK, BORDER_SUBTLE, 12, 1))
	th.set_stylebox("panel", "Panel", make_panel_box(BG_DARK, BORDER_SUBTLE, 12, 1))

	# Buttons
	th.set_stylebox("normal", "Button", make_panel_box(BG_CARD, BORDER_SUBTLE, 8, 1, 14, 9))
	th.set_stylebox("hover", "Button", make_panel_box(BG_CARD_HOVER, ACCENT_CYAN, 8, 2, 14, 9))
	th.set_stylebox("pressed", "Button", make_panel_box(Color(0.16, 0.22, 0.34, 0.98), ACCENT_RED, 8, 2, 14, 9))
	th.set_stylebox("focus", "Button", make_panel_box(BG_CARD_HOVER, ACCENT_CYAN, 8, 2, 14, 9))
	th.set_color("font_color", "Button", TEXT_PRIMARY)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", ACCENT_CYAN)

	# Labels
	th.set_color("font_color", "Label", TEXT_PRIMARY)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))

	# Progress bars
	th.set_stylebox("background", "ProgressBar", make_panel_box(Color(0.08, 0.10, 0.15, 0.92), BORDER_SUBTLE, 6, 1, 0, 0))
	th.set_stylebox("fill", "ProgressBar", make_panel_box(ACCENT_CYAN, Color.TRANSPARENT, 6, 0, 0, 0))

	_cached_theme = th
	return th


static func make_panel_box(
	bg: Color,
	border: Color = Color.TRANSPARENT,
	radius: int = 10,
	border_w: int = 1,
	pad_x: int = 12,
	pad_y: int = 10
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


static func style_primary_button(btn: Button, accent: Color = ACCENT_RED) -> void:
	btn.add_theme_stylebox_override("normal", make_panel_box(accent, accent.lightened(0.25), 10, 2, 22, 12))
	btn.add_theme_stylebox_override("hover", make_panel_box(accent.lightened(0.12), Color.WHITE, 10, 2, 22, 12))
	btn.add_theme_stylebox_override("pressed", make_panel_box(accent.darkened(0.15), Color.WHITE, 10, 2, 22, 12))
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color.WHITE)


static func style_selected_chip(btn: Button, is_selected: bool) -> void:
	if is_selected:
		btn.add_theme_stylebox_override("normal", make_panel_box(Color(0.14, 0.24, 0.36, 0.96), ACCENT_CYAN, 8, 2, 12, 8))
		btn.add_theme_stylebox_override("hover", make_panel_box(Color(0.18, 0.28, 0.42, 0.98), ACCENT_CYAN, 8, 2, 12, 8))
		btn.add_theme_color_override("font_color", Color.WHITE)
	else:
		btn.add_theme_stylebox_override("normal", make_panel_box(BG_CARD, BORDER_SUBTLE, 8, 1, 12, 8))
		btn.add_theme_stylebox_override("hover", make_panel_box(BG_CARD_HOVER, ACCENT_CYAN, 8, 1, 12, 8))
		btn.add_theme_color_override("font_color", TEXT_MUTED)
