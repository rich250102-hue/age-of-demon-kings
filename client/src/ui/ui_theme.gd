class_name UiTheme
extends RefCounted
## Thème commun de l'interface : boutons opaques, lisibles sur n'importe quel décor.
## Appliqué à la fenêtre, il vaut pour tous les écrans (forêt, bastion, futurs menus).

const BG := Color("2a2230")
const BG_HOVER := Color("3a2f42")
const BG_PRESSED := Color("5a3d2a")
const BG_DISABLED := Color("1c1720")
const BORDER := Color("6b5640")
const BORDER_ACTIVE := Color("e0b060")
const TEXT := Color("f2e8d8")
const TEXT_DISABLED := Color("8a8090")


static func build() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", _box(BG, BORDER))
	t.set_stylebox("hover", "Button", _box(BG_HOVER, BORDER))
	t.set_stylebox("pressed", "Button", _box(BG_PRESSED, BORDER_ACTIVE))
	t.set_stylebox("hover_pressed", "Button", _box(BG_PRESSED, BORDER_ACTIVE))
	t.set_stylebox("disabled", "Button", _box(BG_DISABLED, BORDER.darkened(0.4)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DISABLED)
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(8)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	return s
