class_name HudStyle
extends RefCounted
## Shared natural, low-contrast survival palette and StyleBox builders for T2.5 HUD panels.
## Uses lightweight StyleBoxFlat resources (no heavy textures or neon/glow effects).

const PANEL_BG_COLOR: Color = Color(0.11, 0.12, 0.10, 0.85)
const PANEL_BORDER_COLOR: Color = Color(0.40, 0.36, 0.28, 0.90)
const SEPARATOR_COLOR: Color = Color(0.32, 0.30, 0.24, 0.65)

const TEXT_PRIMARY_COLOR: Color = Color(0.94, 0.91, 0.83, 1.0)
const TEXT_SECONDARY_COLOR: Color = Color(0.75, 0.74, 0.67, 1.0)
const TEXT_MUTED_COLOR: Color = Color(0.56, 0.56, 0.50, 1.0)

const WOOD_COLOR: Color = Color(0.64, 0.44, 0.25, 1.0)
const STONE_COLOR: Color = Color(0.66, 0.69, 0.71, 1.0)
const FOOD_COLOR: Color = Color(0.80, 0.56, 0.24, 1.0)

const EXPOSURE_PROTECTED_COLOR: Color = Color(0.58, 0.72, 0.48, 1.0)
const EXPOSURE_IDLE_COLOR: Color = Color(0.76, 0.71, 0.58, 1.0)
const EXPOSURE_ACTIVE_COLOR: Color = Color(0.84, 0.65, 0.32, 1.0)

const BAR_BG_COLOR: Color = Color(0.07, 0.08, 0.06, 0.90)
const BAR_BORDER_COLOR: Color = Color(0.30, 0.28, 0.22, 0.85)
const BAR_FILL_NORMAL_COLOR: Color = Color(0.42, 0.58, 0.31, 1.0)
const BAR_FILL_HIGH_COLOR: Color = Color(0.76, 0.56, 0.24, 1.0)
const BAR_FILL_OVERLOAD_COLOR: Color = Color(0.74, 0.32, 0.24, 1.0)


static func create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 5
	return style


static func create_progress_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BAR_BG_COLOR
	style.border_color = BAR_BORDER_COLOR
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style


static func create_progress_fill_style(fill_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_right = 2
	style.corner_radius_bottom_left = 2
	return style


static func apply_mouse_filter_ignore_recursive(root_control: Control) -> void:
	if root_control == null:
		return
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in root_control.get_children():
		if child is Control:
			apply_mouse_filter_ignore_recursive(child as Control)
