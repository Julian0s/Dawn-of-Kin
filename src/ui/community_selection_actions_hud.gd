class_name CommunitySelectionActionsHud
extends Control
## Minimal D2.2-consistent contextual action bar for selected natural resource sources (R-03A D1).
## Displays only icon + selected count per present category (wood/stone/food).
## Strictly signal-driven (zero _process/_physics_process), anti-click-through, no "Parar" button in D1.

signal category_authorize_requested(resource_id: StringName)

const CATEGORY_ORDER: Array[StringName] = [&"wood", &"stone", &"food"]

const ICON_WOOD: Texture2D = preload("res://assets/ui/d2/icons/ico_work_chop.png")
const ICON_STONE: Texture2D = preload("res://assets/ui/d2/icons/ico_work_mine.png")
const ICON_FOOD: Texture2D = preload("res://assets/ui/d2/icons/ico_work_harvest.png")

const PANEL_MARGIN_H: int = 10
const PANEL_MARGIN_V: int = 6
const BUTTON_MIN_SIZE: Vector2 = Vector2(68.0, 36.0)
const BUTTON_SEPARATION: int = 8
const BOTTOM_OFFSET_PX: float = 16.0

const STATE_HIDDEN: String = "hidden"
const STATE_AVAILABLE: String = "available"
const STATE_PARTIAL: String = "partial"
const STATE_AUTHORIZED: String = "authorized"
const STATE_BLOCKED_REAUTH: String = "blocked_reauthorization"
const STATE_ECONOMY_BLOCKED: String = "economy_blocked"

var _selection_model: SourceSelectionModel = null
var _board: CommunityWorkBoard = null
var _use_provenance_economy: bool = true
var _economy_admission_reason: String = ""

var _panel: PanelContainer = null
var _buttons_row: HBoxContainer = null
var _category_buttons: Dictionary = {}
var _category_count_labels: Dictionary = {}
var _category_states: Dictionary = {}
var _styles_by_state: Dictionary = {}
var _ui_built: bool = false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_ui_built()
	refresh()


func _exit_tree() -> void:
	unbind()


func configure(
	p_selection_model: SourceSelectionModel,
	p_board: CommunityWorkBoard,
	p_use_provenance_economy: bool = true,
	p_economy_admission_reason: String = ""
) -> void:
	unbind()
	_ensure_ui_built()
	_selection_model = p_selection_model
	_board = p_board
	_use_provenance_economy = p_use_provenance_economy
	_economy_admission_reason = p_economy_admission_reason

	if _selection_model != null:
		if not _selection_model.selection_changed.is_connected(_on_selection_or_board_changed):
			_selection_model.selection_changed.connect(_on_selection_or_board_changed)
	if _board != null and is_instance_valid(_board):
		if not _board.task_registered.is_connected(_on_board_task_changed):
			_board.task_registered.connect(_on_board_task_changed)
		if not _board.task_updated.is_connected(_on_board_task_changed):
			_board.task_updated.connect(_on_board_task_changed)
		if not _board.task_closed.is_connected(_on_board_task_changed):
			_board.task_closed.connect(_on_board_task_changed)

	refresh()


func unbind() -> void:
	if _selection_model != null:
		if _selection_model.selection_changed.is_connected(_on_selection_or_board_changed):
			_selection_model.selection_changed.disconnect(_on_selection_or_board_changed)
	if _board != null and is_instance_valid(_board):
		if _board.task_registered.is_connected(_on_board_task_changed):
			_board.task_registered.disconnect(_on_board_task_changed)
		if _board.task_updated.is_connected(_on_board_task_changed):
			_board.task_updated.disconnect(_on_board_task_changed)
		if _board.task_closed.is_connected(_on_board_task_changed):
			_board.task_closed.disconnect(_on_board_task_changed)
	_selection_model = null
	_board = null
	_category_states.clear()
	if _panel != null:
		_panel.visible = false


func refresh() -> void:
	_ensure_ui_built()
	if _selection_model == null:
		_category_states.clear()
		_panel.visible = false
		return

	var counts: Dictionary = _selection_model.get_counts_by_resource()
	var visible_count: int = 0
	for res_id: StringName in CATEGORY_ORDER:
		var btn: Button = _category_buttons.get(res_id) as Button
		var count_lbl: Label = _category_count_labels.get(res_id) as Label
		if btn == null or count_lbl == null:
			continue
		var count: int = int(counts.get(res_id, 0))
		if count <= 0:
			btn.visible = false
			_category_states[res_id] = STATE_HIDDEN
			continue

		visible_count += 1
		btn.visible = true
		count_lbl.text = str(count)

		var visual_state: String = _compute_category_visual_state(res_id)
		_category_states[res_id] = visual_state
		_apply_button_visual_state(btn, count_lbl, res_id, count, visual_state)

	if visible_count == 0:
		_panel.visible = false
		return

	_panel.visible = true
	_layout_panel_bottom_center(visible_count)


func has_stop_button() -> bool:
	return false


func is_panel_visible() -> bool:
	return _panel != null and _panel.visible


func get_panel_rect() -> Rect2:
	if _panel == null or not _panel.visible:
		return Rect2()
	return _panel.get_global_rect()


func get_category_button(resource_id: StringName) -> Button:
	return _category_buttons.get(resource_id) as Button


func get_category_count_text(resource_id: StringName) -> String:
	var lbl: Label = _category_count_labels.get(resource_id) as Label
	return lbl.text if lbl != null else ""


func get_category_visual_state(resource_id: StringName) -> String:
	return String(_category_states.get(resource_id, STATE_HIDDEN))


func get_visible_category_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for res_id: StringName in CATEGORY_ORDER:
		var btn: Button = _category_buttons.get(res_id) as Button
		if btn != null and btn.visible:
			result.append(res_id)
	return result


func _is_economy_blocked() -> bool:
	return _use_provenance_economy and not _economy_admission_reason.is_empty()


func _compute_category_visual_state(resource_id: StringName) -> String:
	if _is_economy_blocked():
		return STATE_ECONOMY_BLOCKED
	if _selection_model == null:
		return STATE_HIDDEN
	var sources: Array[ResourceSource] = _selection_model.get_selected_by_resource(resource_id)
	if sources.is_empty():
		return STATE_HIDDEN
	if _board == null or not is_instance_valid(_board):
		return STATE_AVAILABLE

	var active_authorized: int = 0
	var blocked_reauth: int = 0
	var unassigned: int = 0
	for src: ResourceSource in sources:
		var task: WorkTask = _board.get_active_task_for_source(src)
		if task == null:
			unassigned += 1
		elif task.is_blocked_reauthorization():
			blocked_reauth += 1
		else:
			active_authorized += 1

	if blocked_reauth > 0 and unassigned == 0:
		return STATE_BLOCKED_REAUTH
	if unassigned == 0 and active_authorized == sources.size():
		return STATE_AUTHORIZED
	if active_authorized > 0 or blocked_reauth > 0:
		return STATE_PARTIAL
	return STATE_AVAILABLE


func _ensure_ui_built() -> void:
	if _ui_built:
		return
	_ui_built = true
	_build_button_styles()

	_panel = PanelContainer.new()
	_panel.name = "ActionsPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(&"panel", _create_container_panel_style())
	_panel.visible = false
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", PANEL_MARGIN_H)
	margin.add_theme_constant_override(&"margin_right", PANEL_MARGIN_H)
	margin.add_theme_constant_override(&"margin_top", PANEL_MARGIN_V)
	margin.add_theme_constant_override(&"margin_bottom", PANEL_MARGIN_V)
	_panel.add_child(margin)

	_buttons_row = HBoxContainer.new()
	_buttons_row.name = "CategoryButtons"
	_buttons_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons_row.add_theme_constant_override(&"separation", BUTTON_SEPARATION)
	margin.add_child(_buttons_row)

	for res_id: StringName in CATEGORY_ORDER:
		var btn := Button.new()
		btn.name = "Authorize_%s" % String(res_id)
		btn.custom_minimum_size = BUTTON_MIN_SIZE
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.text = ""
		btn.visible = false
		btn.pressed.connect(_on_category_button_pressed.bind(res_id))
		_buttons_row.add_child(btn)

		var inner := HBoxContainer.new()
		inner.name = "Content"
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override(&"separation", 6)
		btn.add_child(inner)

		var icon_rect := TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.texture = _icon_for_resource(res_id)
		icon_rect.custom_minimum_size = Vector2(22.0, 22.0)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon_rect)

		var count_lbl := Label.new()
		count_lbl.name = "Count"
		count_lbl.text = "0"
		count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_lbl.add_theme_font_size_override(&"font_size", 14)
		count_lbl.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(count_lbl)

		_category_buttons[res_id] = btn
		_category_count_labels[res_id] = count_lbl


func _layout_panel_bottom_center(visible_count: int) -> void:
	var panel_w: float = float(PANEL_MARGIN_H * 2) + float(visible_count) * BUTTON_MIN_SIZE.x + float(maxi(visible_count - 1, 0) * BUTTON_SEPARATION)
	var panel_h: float = float(PANEL_MARGIN_V * 2) + BUTTON_MIN_SIZE.y
	var half_w: float = panel_w * 0.5
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -half_w
	_panel.offset_right = half_w
	_panel.offset_bottom = -BOTTOM_OFFSET_PX
	_panel.offset_top = -(BOTTOM_OFFSET_PX + panel_h)
	_panel.size = Vector2(panel_w, panel_h)


func _apply_button_visual_state(
	btn: Button,
	count_lbl: Label,
	resource_id: StringName,
	count: int,
	visual_state: String
) -> void:
	var is_blocked_econ: bool = visual_state == STATE_ECONOMY_BLOCKED
	btn.disabled = is_blocked_econ
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW if is_blocked_econ else Control.CURSOR_POINTING_HAND

	var palette: Dictionary = _styles_by_state.get(visual_state, _styles_by_state[STATE_AVAILABLE]) as Dictionary
	btn.add_theme_stylebox_override(&"normal", palette["normal"] as StyleBoxFlat)
	btn.add_theme_stylebox_override(&"hover", palette["hover"] as StyleBoxFlat)
	btn.add_theme_stylebox_override(&"pressed", palette["pressed"] as StyleBoxFlat)
	btn.add_theme_stylebox_override(&"disabled", palette["disabled"] as StyleBoxFlat)
	btn.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())

	var text_color: Color = D2Tokens.COLOR_TEXT_PRIMARY_IVORY
	match visual_state:
		STATE_ECONOMY_BLOCKED:
			text_color = D2Tokens.COLOR_DISABLED_TEXT
		STATE_AUTHORIZED:
			text_color = D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT
		STATE_BLOCKED_REAUTH:
			text_color = D2Tokens.COLOR_FEEDBACK_AMBER
		_:
			text_color = D2Tokens.COLOR_TEXT_PRIMARY_IVORY
	count_lbl.add_theme_color_override(&"font_color", text_color)

	var verb: String = _action_verb(resource_id)
	match visual_state:
		STATE_ECONOMY_BLOCKED:
			btn.tooltip_text = "Economia regional bloqueada"
		STATE_BLOCKED_REAUTH:
			btn.tooltip_text = "Reautorizar %s (%d)" % [verb, count]
		STATE_AUTHORIZED:
			btn.tooltip_text = "%s autorizado (%d)" % [verb, count]
		STATE_PARTIAL:
			btn.tooltip_text = "Autorizar %s restantes (%d)" % [verb, count]
		_:
			btn.tooltip_text = "Autorizar %s (%d)" % [verb, count]


func _build_button_styles() -> void:
	_styles_by_state = {
		STATE_AVAILABLE: {
			"normal": _make_btn_style(Color(0.11, 0.12, 0.13, 0.92), Color(0.875, 0.737, 0.447, 0.52), 1),
			"hover": _make_btn_style(Color(0.20, 0.19, 0.15, 0.96), D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 1),
			"pressed": _make_btn_style(Color(0.27, 0.24, 0.17, 0.98), D2Tokens.COLOR_ACCENT_GOLD_PRIMARY, 1),
			"disabled": _make_btn_style(D2Tokens.COLOR_DISABLED_FILL, D2Tokens.COLOR_DISABLED_BORDER, 1),
		},
		STATE_PARTIAL: {
			"normal": _make_btn_style(Color(0.16, 0.16, 0.13, 0.94), D2Tokens.COLOR_ACCENT_GOLD_PRIMARY, 1),
			"hover": _make_btn_style(Color(0.24, 0.22, 0.16, 0.96), D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 1),
			"pressed": _make_btn_style(Color(0.30, 0.26, 0.18, 0.98), D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 1),
			"disabled": _make_btn_style(D2Tokens.COLOR_DISABLED_FILL, D2Tokens.COLOR_DISABLED_BORDER, 1),
		},
		STATE_AUTHORIZED: {
			"normal": _make_btn_style(Color(0.13, 0.19, 0.12, 0.94), Color(0.647, 0.788, 0.545, 0.78), 1),
			"hover": _make_btn_style(Color(0.17, 0.24, 0.15, 0.96), D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT, 1),
			"pressed": _make_btn_style(Color(0.20, 0.28, 0.17, 0.98), D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT, 1),
			"disabled": _make_btn_style(D2Tokens.COLOR_DISABLED_FILL, D2Tokens.COLOR_DISABLED_BORDER, 1),
		},
		STATE_BLOCKED_REAUTH: {
			"normal": _make_btn_style(Color(0.21, 0.16, 0.10, 0.95), Color(0.918, 0.706, 0.392, 0.85), 1),
			"hover": _make_btn_style(Color(0.28, 0.21, 0.13, 0.97), D2Tokens.COLOR_FEEDBACK_AMBER, 1),
			"pressed": _make_btn_style(Color(0.34, 0.25, 0.15, 0.98), D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 1),
			"disabled": _make_btn_style(D2Tokens.COLOR_DISABLED_FILL, D2Tokens.COLOR_DISABLED_BORDER, 1),
		},
		STATE_ECONOMY_BLOCKED: {
			"normal": _make_btn_style(Color(0.14, 0.11, 0.11, 0.88), Color(0.776, 0.416, 0.345, 0.55), 1),
			"hover": _make_btn_style(Color(0.14, 0.11, 0.11, 0.88), Color(0.776, 0.416, 0.345, 0.55), 1),
			"pressed": _make_btn_style(Color(0.14, 0.11, 0.11, 0.88), Color(0.776, 0.416, 0.345, 0.55), 1),
			"disabled": _make_btn_style(Color(0.14, 0.11, 0.11, 0.88), Color(0.776, 0.416, 0.345, 0.55), 1),
		},
	}


static func _create_container_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(D2Tokens.COLOR_SURFACE_BASALT_DEEP.r, D2Tokens.COLOR_SURFACE_BASALT_DEEP.g, D2Tokens.COLOR_SURFACE_BASALT_DEEP.b, 0.92)
	style.border_color = Color(D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.r, D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.g, D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.b, 0.62)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	return style


static func _make_btn_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_w
	style.border_width_top = border_w
	style.border_width_right = border_w
	style.border_width_bottom = border_w
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style


static func _icon_for_resource(resource_id: StringName) -> Texture2D:
	match resource_id:
		&"stone":
			return ICON_STONE
		&"food":
			return ICON_FOOD
		_:
			return ICON_WOOD


static func _action_verb(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "mineração"
		&"food":
			return "colheita"
		_:
			return "corte de madeira"


func _on_selection_or_board_changed() -> void:
	refresh()


func _on_board_task_changed(_task: WorkTask) -> void:
	refresh()


func _on_category_button_pressed(resource_id: StringName) -> void:
	if _is_economy_blocked():
		return
	category_authorize_requested.emit(resource_id)
