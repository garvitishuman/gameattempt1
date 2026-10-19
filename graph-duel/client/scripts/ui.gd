extends RefCounted
# Shared theme + small widget helpers.

const BG := Color("0b0d1a")
const PANEL := Color("12162e")
const PANEL2 := Color("1a1f40")
const BORDER := Color("3a418a")
const TEXT := Color("e8ebff")
const MUTED := Color("8f96c8")
const ACCENT := Color("4da3ff")
const GOOD := Color("5be39a")
const BAD := Color("ff4d6d")
const WARN := Color("ffb04d")

const PLAYER_COLORS := [
	Color("4da3ff"), Color("ffb04d"), Color("5be39a"), Color("ff6b9d"),
	Color("b06cff"), Color("f2e04d"), Color("4de3e3"), Color("ff7b4d"),
]

static func sb(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, r: int = 6, m: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(r)
	s.content_margin_left = m + 2
	s.content_margin_right = m + 2
	s.content_margin_top = m - 2
	s.content_margin_bottom = m - 2
	return s

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	for cls in ["Button", "OptionButton", "CheckBox"]:
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color("5b618f"))
	t.set_stylebox("normal", "Button", sb(PANEL2, BORDER, 1))
	t.set_stylebox("hover", "Button", sb(Color("252b57"), ACCENT, 1))
	t.set_stylebox("pressed", "Button", sb(Color("2f3a78"), ACCENT, 1))
	t.set_stylebox("disabled", "Button", sb(Color("151a33"), Color("2a2f5c"), 1))
	t.set_stylebox("focus", "Button", sb(Color(0, 0, 0, 0), ACCENT, 2))
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(st, "OptionButton", t.get_stylebox(st, "Button"))
	t.set_stylebox("normal", "LineEdit", sb(Color("0e1126"), BORDER, 1))
	t.set_stylebox("focus", "LineEdit", sb(Color("0e1126"), ACCENT, 2))
	t.set_stylebox("read_only", "LineEdit", sb(Color("0e1126"), Color("2a2f5c"), 1))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color("5b618f"))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("panel", "PanelContainer", sb(PANEL, BORDER, 1, 10, 12))
	t.set_stylebox("background", "ProgressBar", sb(Color("0e1126"), Color("2a2f5c"), 1, 4, 2))
	t.set_stylebox("fill", "ProgressBar", sb(GOOD, Color(0, 0, 0, 0), 0, 4, 2))
	t.set_stylebox("panel", "PopupPanel", sb(PANEL, BORDER, 1, 8, 10))
	t.set_stylebox("panel", "AcceptDialog", sb(PANEL, BORDER, 1, 8, 10))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", sb(Color("0e1126"), Color("2a2f5c"), 1, 6, 6))
	t.set_stylebox("panel", "PopupMenu", sb(PANEL, BORDER, 1, 6, 4))
	return t

static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, min_h: float = 36.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.focus_mode = Control.FOCUS_NONE
	return b

static func full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func color_for(order: Array, id: int) -> Color:
	var i: int = order.find(id)
	if i < 0:
		return MUTED
	return PLAYER_COLORS[i % PLAYER_COLORS.size()]
