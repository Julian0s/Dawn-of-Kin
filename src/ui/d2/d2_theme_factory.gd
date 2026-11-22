class_name D2ThemeFactory
extends RefCounted
## Builds the native Godot Theme and SystemFont pairs for D2.2 (DT-03 provisional typography).
## Never bundles proprietary OS font files or depends on hardcoded C:/Windows/Fonts/ paths.

const SERIF_FONT_NAMES: Array[String] = [
	"Palatino Linotype",
	"Book Antiqua",
	"Georgia",
	"TeX Gyre Pagella",
	"Liberation Serif",
	"DejaVu Serif",
]

const SANS_FONT_NAMES: Array[String] = [
	"Segoe UI",
	"Inter",
	"Noto Sans",
	"Liberation Sans",
	"DejaVu Sans",
]

var _serif_regular: SystemFont = null
var _serif_bold: SystemFont = null
var _sans_regular: SystemFont = null
var _sans_bold: SystemFont = null
var _theme: Theme = null


func build_theme() -> Theme:
	if _theme != null:
		return _theme
	_ensure_fonts()
	_theme = Theme.new()
	_theme.default_font = _sans_regular
	_theme.default_font_size = 13
	_theme.set_color(&"font_color", &"Label", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
	return _theme


func get_serif_font(bold: bool = false) -> Font:
	_ensure_fonts()
	return _serif_bold if bold else _serif_regular


func get_sans_font(bold: bool = false) -> Font:
	_ensure_fonts()
	return _sans_bold if bold else _sans_regular


func _ensure_fonts() -> void:
	if _serif_regular != null:
		return
	_serif_regular = _make_system_font(SERIF_FONT_NAMES, 400)
	_serif_bold = _make_system_font(SERIF_FONT_NAMES, 700)
	_sans_regular = _make_system_font(SANS_FONT_NAMES, 400)
	_sans_bold = _make_system_font(SANS_FONT_NAMES, 700)


static func _make_system_font(names: Array[String], weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return font
