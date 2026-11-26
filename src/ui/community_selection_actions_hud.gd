class_name CommunitySelectionActionsHud
extends Control
## D2.2-faithful contextual work bar for selected natural resource sources (R-03A D1 R2 + D2).
## Reuses the homologated D2.2 volcanic basalt command slab ("slab_cmd_basalt" via D2AtlasLibrary),
## D2PolygonalSlab geometry, D2ThemeFactory serif typography, and independent D2.2-aligned work icons.
## Displays icon + selected count per present category (wood/stone/food) plus a contextual
## D2.2 mineral "×" cancel seal above each category that has active cancellable tasks (D2-A).
## Strictly signal-driven (zero _process/_physics_process), polygonal anti-click-through, no global "Parar" button.

signal category_authorize_requested(resource_id: StringName)
signal category_cancel_requested(resource_id: StringName)

const CATEGORY_ORDER: Array[StringName] = [&"wood", &"stone", &"food"]
const ATLAS_REGION_KEY: String = "slab_cmd_basalt"

const ICON_WOOD: Texture2D = preload("res://assets/ui/d2/icons/ico_work_chop.png")
const ICON_STONE: Texture2D = preload("res://assets/ui/d2/icons/ico_work_mine.png")
const ICON_FOOD: Texture2D = preload("res://assets/ui/d2/icons/ico_work_harvest.png")

## Uniform isotropic scale applied to "slab_cmd_basalt" (166x92 outer / 146x72 content / 10px shadow_pad)
## -> 97x54 outer / 85x42 solid basalt stone content (zero aspect-ratio stretching, crisp downsampling).
const SLAB_SCALE: float = 0.583
const SLAB_CONTENT_SIZE: Vector2 = Vector2(85.0, 42.0)
const SLAB_SHADOW_PAD_SCALED: float = 6.0
const SLAB_OUTER_SIZE: Vector2 = Vector2(97.0, 54.0)
const SLAB_GAP_X: float = 8.0
const SLAB_STAGGER_Y: Array[float] = [0.0, 3.0, 1.0]
const BOTTOM_OFFSET_PX: float = 16.0
const ICON_DISPLAY_SIZE: Vector2 = Vector2(22.0, 22.0)
const COUNT_FONT_SIZE: int = 16

## D2-A mineral "×" cancel seal positioned above each category slab with a 6 px transparent pass-through gap
## to the solid stone top edge of the slab (y=4..26 seal, y=26..32 transparent shadow pad, y=32..74 solid slab).
const SEAL_HEADROOM_Y: float = 26.0
const SEAL_TOP_Y: float = 4.0
const SEAL_HEIGHT: float = 22.0
const SEAL_WIDTH_SINGLE: float = 34.0
const SEAL_WIDTH_PARTIAL: float = 44.0
const SEAL_CHAMFER: float = 5.0
const SEAL_FONT_SIZE: int = 12

const STATE_HIDDEN: String = "hidden"
const STATE_AVAILABLE: String = "available"
const STATE_PARTIAL: String = "partial"
const STATE_AUTHORIZED: String = "authorized"
const STATE_BLOCKED_REAUTH: String = "blocked_reauthorization"
const STATE_ECONOMY_BLOCKED: String = "economy_blocked"


class _PolygonalCommandButton:
	extends Button
	## Native Button overlay constrained strictly to the D2.2 basalt stone polygon.
	## Preserves full compatibility with Button API while enforcing polygonal hit-testing,
	## blocking LMB/RMB/MMB/scroll on solid stone and passing transparent margins to the 3D world.

	var _base_polygon: PackedVector2Array = PackedVector2Array()
	var _base_content_size: Vector2 = Vector2.ZERO
	var _shadow_pad: float = D2Tokens.ATLAS_SHADOW_PAD
	var _scaled_polygon: PackedVector2Array = PackedVector2Array()
	var _visual_state: String = STATE_AVAILABLE
	var _is_hovered_visual: bool = false

	func _init() -> void:
		flat = true
		text = ""
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_force_pass_scroll_events = false
		action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		button_mask = MOUSE_BUTTON_MASK_LEFT
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		add_theme_stylebox_override(&"normal", empty)
		add_theme_stylebox_override(&"hover", empty)
		add_theme_stylebox_override(&"pressed", empty)
		add_theme_stylebox_override(&"disabled", empty)
		add_theme_stylebox_override(&"focus", empty)

	func _ready() -> void:
		if not mouse_entered.is_connected(_on_mouse_entered):
			mouse_entered.connect(_on_mouse_entered)
		if not mouse_exited.is_connected(_on_mouse_exited):
			mouse_exited.connect(_on_mouse_exited)
		if not button_down.is_connected(_on_button_state_changed):
			button_down.connect(_on_button_state_changed)
		if not button_up.is_connected(_on_button_state_changed):
			button_up.connect(_on_button_state_changed)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_rebuild_scaled_polygon()
			queue_redraw()

	func configure_polygon(
		content_polygon: Array[Vector2],
		content_size: Vector2,
		shadow_pad: float = D2Tokens.ATLAS_SHADOW_PAD
	) -> void:
		_base_polygon = PackedVector2Array(content_polygon)
		_base_content_size = content_size
		_shadow_pad = maxf(0.0, shadow_pad)
		_rebuild_scaled_polygon()
		queue_redraw()

	func set_scaled_size(target_size: Vector2) -> void:
		custom_minimum_size = target_size
		size = target_size
		_rebuild_scaled_polygon()
		queue_redraw()

	func set_visual_state(state_name: String) -> void:
		if _visual_state == state_name:
			return
		_visual_state = state_name
		if disabled:
			_is_hovered_visual = false
		queue_redraw()

	func get_visual_state() -> String:
		return _visual_state

	func get_scaled_polygon() -> PackedVector2Array:
		return _scaled_polygon.duplicate()

	func contains_local_point(local_point: Vector2) -> bool:
		return _has_point(local_point)

	func contains_global_point(global_point: Vector2) -> bool:
		var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * global_point
		return _has_point(local_point)

	func _has_point(point: Vector2) -> bool:
		if _scaled_polygon.size() < 3:
			return Rect2(Vector2.ZERO, size).has_point(point)
		return Geometry2D.is_point_in_polygon(point, _scaled_polygon)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if disabled or mb.button_index != MOUSE_BUTTON_LEFT:
				accept_event()

	func _draw() -> void:
		if _scaled_polygon.size() < 3:
			return
		var outline := PackedVector2Array(_scaled_polygon)
		outline.append(_scaled_polygon[0])

		var wash := Color(0.0, 0.0, 0.0, 0.0)
		var border := Color(0.0, 0.0, 0.0, 0.0)
		var border_w: float = 1.5

		match _visual_state:
			STATE_ECONOMY_BLOCKED:
				wash = Color(0.055, 0.063, 0.075, 0.44)
				border = Color(D2Tokens.COLOR_FEEDBACK_ERROR_DARK.r, D2Tokens.COLOR_FEEDBACK_ERROR_DARK.g, D2Tokens.COLOR_FEEDBACK_ERROR_DARK.b, 0.80)
				border_w = 1.35
			STATE_BLOCKED_REAUTH:
				wash = Color(0.918, 0.706, 0.392, 0.07 if not _is_hovered_visual else 0.14)
				border = D2Tokens.COLOR_FEEDBACK_AMBER if not is_pressed() else D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT
				border_w = 1.75
			STATE_AUTHORIZED:
				wash = Color(0.647, 0.788, 0.545, 0.06 if not _is_hovered_visual else 0.12)
				border = D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT
				border_w = 1.75
			STATE_PARTIAL:
				wash = Color(0.875, 0.737, 0.447, 0.06 if not _is_hovered_visual else 0.13)
				border = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY if not _is_hovered_visual else D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT
				border_w = 1.6
			_:
				if is_pressed():
					wash = Color(0.875, 0.737, 0.447, 0.18)
					border = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
					border_w = 1.6
				elif _is_hovered_visual:
					wash = Color(0.961, 0.851, 0.588, 0.11)
					border = D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT
					border_w = 1.5

		if wash.a > 0.001:
			draw_colored_polygon(_scaled_polygon, wash)
		if border.a > 0.001:
			draw_polyline(outline, border, border_w, true)

		# Discreet engraved geometric state marks (non-color-only differentiation).
		var tr: Vector2 = _scaled_polygon[1]
		var br: Vector2 = _scaled_polygon[2]
		var bl: Vector2 = _scaled_polygon[3]
		match _visual_state:
			STATE_AUTHORIZED:
				# Small crisp carved check glyph at top-right stone corner.
				var c := Vector2(tr.x - 10.0, tr.y + 8.5)
				var check_pts := PackedVector2Array([
					c + Vector2(-3.5, 0.2),
					c + Vector2(-1.0, 2.8),
					c + Vector2(3.8, -2.6),
				])
				draw_polyline(check_pts, D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT, 1.6, true)
			STATE_PARTIAL:
				# Twin engraved gold suture dashes along lower bevel.
				var y_bar: float = minf(bl.y, br.y) - 3.5
				var mid_x: float = (bl.x + br.x) * 0.5
				draw_line(Vector2(mid_x - 12.0, y_bar), Vector2(mid_x - 2.0, y_bar), D2Tokens.COLOR_ACCENT_GOLD_PRIMARY, 1.8, true)
				draw_line(Vector2(mid_x + 2.0, y_bar), Vector2(mid_x + 12.0, y_bar), Color(D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.r, D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.g, D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.b, 0.40), 1.8, true)
			STATE_BLOCKED_REAUTH:
				# Small crisp amber attention exclamation mark at top-right stone corner.
				var a := Vector2(tr.x - 9.5, tr.y + 7.5)
				draw_line(a + Vector2(0.0, -3.5), a + Vector2(0.0, 1.0), D2Tokens.COLOR_FEEDBACK_AMBER, 1.8, true)
				draw_circle(a + Vector2(0.0, 3.6), 1.15, D2Tokens.COLOR_FEEDBACK_AMBER)
			STATE_ECONOMY_BLOCKED:
				# Small crisp terracotta cross at top-right stone corner.
				var x_pt := Vector2(tr.x - 9.5, tr.y + 8.5)
				var err_col := D2Tokens.COLOR_FEEDBACK_ERROR_ROSE
				draw_line(x_pt + Vector2(-2.6, -2.6), x_pt + Vector2(2.6, 2.6), err_col, 1.5, true)
				draw_line(x_pt + Vector2(2.6, -2.6), x_pt + Vector2(-2.6, 2.6), err_col, 1.5, true)

	func _on_mouse_entered() -> void:
		if not disabled:
			_is_hovered_visual = true
			queue_redraw()

	func _on_mouse_exited() -> void:
		_is_hovered_visual = false
		queue_redraw()

	func _on_button_state_changed() -> void:
		queue_redraw()

	func _rebuild_scaled_polygon() -> void:
		if _base_polygon.size() < 3:
			_scaled_polygon = PackedVector2Array()
			return
		var base_total_w: float = _base_content_size.x + 2.0 * _shadow_pad
		var base_total_h: float = _base_content_size.y + 2.0 * _shadow_pad
		if base_total_w <= 0.0 or base_total_h <= 0.0:
			_scaled_polygon = PackedVector2Array()
			return
		var target_w: float = size.x if size.x > 0.0 else base_total_w
		var target_h: float = size.y if size.y > 0.0 else base_total_h
		var sx: float = target_w / base_total_w
		var sy: float = target_h / base_total_h
		var rebuilt := PackedVector2Array()
		rebuilt.resize(_base_polygon.size())
		for i: int in range(_base_polygon.size()):
			var pt: Vector2 = _base_polygon[i]
			rebuilt[i] = Vector2((pt.x + _shadow_pad) * sx, (pt.y + _shadow_pad) * sy)
		_scaled_polygon = rebuilt


class _PolygonalCancelSealButton:
	extends Button
	## Chamfered volcanic basalt D2.2 mineral "×" cancel seal positioned above a category slab (R-03A D2-A).
	## Enforces polygonal hit-testing (transparent corners pass through), blocks RMB/MMB/scroll on solid stone,
	## and activates strictly on LMB release inside the polygon.

	var _polygon: PackedVector2Array = PackedVector2Array()
	var _is_hovered_visual: bool = false
	var _glyph_label: Label = null
	var _last_glyph_color: Color = Color(-1.0, -1.0, -1.0, -1.0)

	func _init() -> void:
		flat = true
		text = ""
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_force_pass_scroll_events = false
		action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		button_mask = MOUSE_BUTTON_MASK_LEFT
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		add_theme_stylebox_override(&"normal", empty)
		add_theme_stylebox_override(&"hover", empty)
		add_theme_stylebox_override(&"pressed", empty)
		add_theme_stylebox_override(&"disabled", empty)
		add_theme_stylebox_override(&"focus", empty)

	func _ready() -> void:
		if not mouse_entered.is_connected(_on_mouse_entered):
			mouse_entered.connect(_on_mouse_entered)
		if not mouse_exited.is_connected(_on_mouse_exited):
			mouse_exited.connect(_on_mouse_exited)
		if not button_down.is_connected(_on_button_state_changed):
			button_down.connect(_on_button_state_changed)
		if not button_up.is_connected(_on_button_state_changed):
			button_up.connect(_on_button_state_changed)

	func setup_glyph_label(font: Font) -> void:
		if _glyph_label != null:
			return
		_glyph_label = Label.new()
		_glyph_label.name = "Glyph"
		_glyph_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_glyph_label.add_theme_font_size_override(&"font_size", SEAL_FONT_SIZE)
		if font != null:
			_glyph_label.add_theme_font_override(&"font", font)
		_glyph_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_FEEDBACK_ERROR_ROSE)
		_glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_glyph_label)

	func set_seal_size(target_size: Vector2) -> void:
		if _polygon.size() >= 3 and size.is_equal_approx(target_size) and custom_minimum_size.is_equal_approx(target_size):
			return
		custom_minimum_size = target_size
		size = target_size
		_rebuild_polygon()
		queue_redraw()

	func set_glyph_text(glyph_text: String) -> void:
		var changed: bool = false
		if _glyph_label != null and _glyph_label.text != glyph_text:
			_glyph_label.text = glyph_text
			changed = true
		if _sync_glyph_color() or changed:
			queue_redraw()

	func get_glyph_text() -> String:
		return _glyph_label.text if _glyph_label != null else ""

	func get_polygon() -> PackedVector2Array:
		return _polygon.duplicate()

	func contains_local_point(local_point: Vector2) -> bool:
		return _has_point(local_point)

	func contains_global_point(global_point: Vector2) -> bool:
		var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * global_point
		return _has_point(local_point)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_rebuild_polygon()
			queue_redraw()

	func _has_point(point: Vector2) -> bool:
		if _polygon.size() < 3:
			return Rect2(Vector2.ZERO, size).has_point(point)
		return Geometry2D.is_point_in_polygon(point, _polygon)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if disabled or mb.button_index != MOUSE_BUTTON_LEFT:
				accept_event()

	func _draw() -> void:
		if _polygon.size() < 3:
			return
		var shadow_poly := PackedVector2Array()
		shadow_poly.resize(_polygon.size())
		for i: int in range(_polygon.size()):
			shadow_poly[i] = _polygon[i] + Vector2(0.0, 1.2)
		draw_colored_polygon(shadow_poly, Color(0.02, 0.022, 0.028, 0.48))

		var fill_col: Color = Color(
			D2Tokens.COLOR_SURFACE_BASALT_DEEP.r,
			D2Tokens.COLOR_SURFACE_BASALT_DEEP.g,
			D2Tokens.COLOR_SURFACE_BASALT_DEEP.b,
			0.95
		)
		var border_col: Color = D2Tokens.COLOR_FEEDBACK_ERROR_DARK
		var border_w: float = 1.35
		if is_pressed():
			fill_col = Color(0.115, 0.072, 0.070, 0.98)
			border_col = D2Tokens.COLOR_FEEDBACK_ERROR_ROSE
			border_w = 1.75
		elif _is_hovered_visual:
			fill_col = Color(0.165, 0.102, 0.098, 0.96)
			border_col = D2Tokens.COLOR_FEEDBACK_ERROR_ROSE
			border_w = 1.60

		draw_colored_polygon(_polygon, fill_col)
		var outline := PackedVector2Array(_polygon)
		outline.append(_polygon[0])
		draw_polyline(outline, border_col, border_w, true)

		# Subtle mineral top bevel highlight for D2.2 carved-stone continuity.
		if _polygon.size() >= 2:
			var top_l: Vector2 = _polygon[0] + Vector2(1.5, 1.5)
			var top_r: Vector2 = _polygon[1] + Vector2(-1.5, 1.5)
			if top_r.x > top_l.x:
				draw_line(top_l, top_r, Color(D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.r, D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.g, D2Tokens.COLOR_ACCENT_GOLD_PRIMARY.b, 0.18), 1.0, true)

	func _on_mouse_entered() -> void:
		if not disabled:
			_is_hovered_visual = true
			_sync_glyph_color()
			queue_redraw()

	func _on_mouse_exited() -> void:
		_is_hovered_visual = false
		_sync_glyph_color()
		queue_redraw()

	func _on_button_state_changed() -> void:
		_sync_glyph_color()
		queue_redraw()

	func _sync_glyph_color() -> bool:
		if _glyph_label == null:
			return false
		var col: Color = D2Tokens.COLOR_TEXT_PRIMARY_IVORY if (_is_hovered_visual or is_pressed()) else D2Tokens.COLOR_FEEDBACK_ERROR_ROSE
		if _last_glyph_color == col:
			return false
		_last_glyph_color = col
		_glyph_label.add_theme_color_override(&"font_color", col)
		return true

	func _rebuild_polygon() -> void:
		var w: float = maxf(size.x, 2.0)
		var h: float = maxf(size.y, 2.0)
		var c: float = minf(SEAL_CHAMFER, minf(w, h) * 0.35)
		_polygon = PackedVector2Array([
			Vector2(c, 0.0),
			Vector2(w - c, 0.0),
			Vector2(w, c),
			Vector2(w, h - c),
			Vector2(w - c, h),
			Vector2(c, h),
			Vector2(0.0, h - c),
			Vector2(0.0, c),
		])


var _selection_model: SourceSelectionModel = null
var _board: CommunityWorkBoard = null
var _use_provenance_economy: bool = true
var _economy_admission_reason: String = ""

var _atlas: D2AtlasLibrary = null
var _theme_factory: D2ThemeFactory = null

var _panel: Control = null
var _category_slots: Dictionary = {}
var _category_slabs: Dictionary = {}
var _category_buttons: Dictionary = {}
var _category_cancel_buttons: Dictionary = {}
var _category_icons: Dictionary = {}
var _category_count_labels: Dictionary = {}
var _category_states: Dictionary = {}
var _category_cancel_counts: Dictionary = {}
var _panel_content_rect: Rect2 = Rect2()
var _ui_built: bool = false
var _batch_refresh_depth: int = 0
var _batch_refresh_dirty: bool = false
var _refresh_invocation_count: int = 0
var _last_batch_refresh_count: int = 0
var _last_layout_visible_ids: Array[StringName] = []


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
	_batch_refresh_depth = 0
	_batch_refresh_dirty = false
	_last_batch_refresh_count = 0
	_last_layout_visible_ids.clear()
	_category_states.clear()
	_category_cancel_counts.clear()
	for res_id: StringName in CATEGORY_ORDER:
		var cancel_btn: _PolygonalCancelSealButton = _category_cancel_buttons.get(res_id) as _PolygonalCancelSealButton
		if cancel_btn != null:
			cancel_btn.visible = false
	_panel_content_rect = Rect2()
	if _panel != null:
		_panel.visible = false


func begin_batch_refresh() -> void:
	_batch_refresh_depth += 1


func end_batch_refresh() -> void:
	if _batch_refresh_depth <= 0:
		_batch_refresh_depth = 0
		return
	_batch_refresh_depth -= 1
	if _batch_refresh_depth == 0 and _batch_refresh_dirty:
		_batch_refresh_dirty = false
		var before_count: int = _refresh_invocation_count
		refresh()
		_last_batch_refresh_count = _refresh_invocation_count - before_count


func get_refresh_invocation_count() -> int:
	return _refresh_invocation_count


func get_last_refresh_count() -> int:
	return _last_batch_refresh_count


func refresh() -> void:
	_ensure_ui_built()
	_refresh_invocation_count += 1
	if _selection_model == null:
		_category_states.clear()
		_category_cancel_counts.clear()
		_last_layout_visible_ids.clear()
		for res_id: StringName in CATEGORY_ORDER:
			var cancel_btn_empty: _PolygonalCancelSealButton = _category_cancel_buttons.get(res_id) as _PolygonalCancelSealButton
			if cancel_btn_empty != null and cancel_btn_empty.visible:
				cancel_btn_empty.visible = false
		_panel_content_rect = Rect2()
		if _panel.visible:
			_panel.visible = false
		return

	var selected_sources: Array[ResourceSource] = _selection_model.get_selected_sources()
	var grouped_sources: Dictionary = {}
	for src: ResourceSource in selected_sources:
		var src_res_id: StringName = src.get_resource_id()
		if not grouped_sources.has(src_res_id):
			var arr: Array[ResourceSource] = []
			grouped_sources[src_res_id] = arr
		(grouped_sources[src_res_id] as Array[ResourceSource]).append(src)

	var empty_sources: Array[ResourceSource] = []
	var visible_ids: Array[StringName] = []
	for res_id: StringName in CATEGORY_ORDER:
		var slot: Control = _category_slots.get(res_id) as Control
		var btn: _PolygonalCommandButton = _category_buttons.get(res_id) as _PolygonalCommandButton
		var cancel_btn: _PolygonalCancelSealButton = _category_cancel_buttons.get(res_id) as _PolygonalCancelSealButton
		var icon_rect: TextureRect = _category_icons.get(res_id) as TextureRect
		var count_lbl: Label = _category_count_labels.get(res_id) as Label
		if slot == null or btn == null or cancel_btn == null or icon_rect == null or count_lbl == null:
			continue
		var cat_sources: Array[ResourceSource] = grouped_sources.get(res_id, empty_sources) as Array[ResourceSource]
		var count: int = cat_sources.size()
		if count <= 0:
			if slot.visible:
				slot.visible = false
			if btn.visible:
				btn.visible = false
			if cancel_btn.visible:
				cancel_btn.visible = false
			if cancel_btn.get_glyph_text() != "":
				cancel_btn.set_glyph_text("")
			if cancel_btn.tooltip_text != "":
				cancel_btn.tooltip_text = ""
			_category_states[res_id] = STATE_HIDDEN
			_category_cancel_counts[res_id] = 0
			continue

		visible_ids.append(res_id)
		if not slot.visible:
			slot.visible = true
		if not btn.visible:
			btn.visible = true
		var count_text: String = str(count)
		if count_lbl.text != count_text:
			count_lbl.text = count_text

		var cat_info: Dictionary = _compute_category_state_and_cancel_count(res_id, cat_sources)
		var visual_state: String = String(cat_info["visual_state"])
		_category_states[res_id] = visual_state
		_apply_button_visual_state(btn, icon_rect, count_lbl, res_id, count, visual_state)

		var cancellable_count: int = int(cat_info["cancellable_count"])
		_category_cancel_counts[res_id] = cancellable_count
		if cancellable_count > 0:
			var is_partial: bool = cancellable_count < count
			var seal_text: String = ("×%d" % cancellable_count) if is_partial else "×"
			var seal_w: float = SEAL_WIDTH_PARTIAL if is_partial else SEAL_WIDTH_SINGLE
			var seal_pos := Vector2((SLAB_OUTER_SIZE.x - seal_w) * 0.5, SEAL_TOP_Y)
			var seal_tooltip: String = "Cancelar %s (%d)" % [_action_verb(res_id), cancellable_count]
			if not cancel_btn.visible:
				cancel_btn.visible = true
			if cancel_btn.disabled:
				cancel_btn.disabled = false
			cancel_btn.set_seal_size(Vector2(seal_w, SEAL_HEIGHT))
			cancel_btn.set_glyph_text(seal_text)
			if not cancel_btn.position.is_equal_approx(seal_pos):
				cancel_btn.position = seal_pos
			if cancel_btn.tooltip_text != seal_tooltip:
				cancel_btn.tooltip_text = seal_tooltip
		else:
			if cancel_btn.visible:
				cancel_btn.visible = false
			if cancel_btn.get_glyph_text() != "":
				cancel_btn.set_glyph_text("")
			if cancel_btn.tooltip_text != "":
				cancel_btn.tooltip_text = ""

	if visible_ids.is_empty():
		_last_layout_visible_ids.clear()
		_panel_content_rect = Rect2()
		if _panel.visible:
			_panel.visible = false
		return

	if not _panel.visible:
		_panel.visible = true
	_layout_slabs_bottom_center(visible_ids)


func has_stop_button() -> bool:
	return false


func get_category_cancel_button(resource_id: StringName) -> Button:
	return _category_cancel_buttons.get(resource_id) as Button


func is_category_cancel_visible(resource_id: StringName) -> bool:
	var btn: Button = _category_cancel_buttons.get(resource_id) as Button
	return btn != null and btn.visible


func get_category_cancel_count(resource_id: StringName) -> int:
	return int(_category_cancel_counts.get(resource_id, 0))


func get_category_cancel_text(resource_id: StringName) -> String:
	var btn: _PolygonalCancelSealButton = _category_cancel_buttons.get(resource_id) as _PolygonalCancelSealButton
	return btn.get_glyph_text() if btn != null else ""


func get_atlas_region_key() -> String:
	return ATLAS_REGION_KEY


func is_atlas_loaded() -> bool:
	return _atlas != null and _atlas.is_valid()


func is_panel_visible() -> bool:
	return _panel != null and _panel.visible


func get_panel_rect() -> Rect2:
	if _panel == null or not _panel.visible:
		return Rect2()
	if _panel_content_rect.size.x > 0.0 and _panel_content_rect.size.y > 0.0:
		return _panel_content_rect
	return _panel.get_global_rect()


func get_category_slab(resource_id: StringName) -> D2PolygonalSlab:
	return _category_slabs.get(resource_id) as D2PolygonalSlab


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


func _count_cancellable_tasks_for_category(resource_id: StringName) -> int:
	if _selection_model == null or _board == null or not is_instance_valid(_board):
		return 0
	var selected_sources: Array[ResourceSource] = _selection_model.get_selected_by_resource(resource_id)
	if selected_sources.is_empty():
		return 0
	return _board.get_cancellable_tasks_for_sources(selected_sources, resource_id).size()


func _compute_category_state_and_cancel_count(
	resource_id: StringName,
	sources: Array[ResourceSource]
) -> Dictionary:
	if _is_economy_blocked():
		var blocked_cancellable: int = 0
		if _board != null and is_instance_valid(_board) and not sources.is_empty():
			blocked_cancellable = _board.get_cancellable_tasks_for_sources(sources, resource_id).size()
		return {"visual_state": STATE_ECONOMY_BLOCKED, "cancellable_count": blocked_cancellable}
	if sources.is_empty():
		return {"visual_state": STATE_HIDDEN, "cancellable_count": 0}
	if _board == null or not is_instance_valid(_board):
		return {"visual_state": STATE_AVAILABLE, "cancellable_count": 0}

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

	var cancellable_count: int = 0
	if (active_authorized + blocked_reauth) > 0:
		cancellable_count = _board.get_cancellable_tasks_for_sources(sources, resource_id).size()

	var visual_state: String = STATE_AVAILABLE
	if blocked_reauth > 0 and unassigned == 0:
		visual_state = STATE_BLOCKED_REAUTH
	elif unassigned == 0 and active_authorized == sources.size():
		visual_state = STATE_AUTHORIZED
	elif active_authorized > 0 or blocked_reauth > 0:
		visual_state = STATE_PARTIAL

	return {"visual_state": visual_state, "cancellable_count": cancellable_count}


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

	_atlas = D2AtlasLibrary.new()
	_atlas.load_all()
	_theme_factory = D2ThemeFactory.new()

	var slab_tex: AtlasTexture = _atlas.get_region_texture(ATLAS_REGION_KEY)
	var slab_meta: Dictionary = _atlas.get_region_metadata(ATLAS_REGION_KEY)
	var shadow_pad: float = float(slab_meta.get("pad", D2Tokens.ATLAS_SHADOW_PAD))
	var serif_bold: Font = _theme_factory.get_serif_font(true)

	_panel = Control.new()
	_panel.name = "ActionsPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)

	var slot_size := Vector2(SLAB_OUTER_SIZE.x, SLAB_OUTER_SIZE.y + SEAL_HEADROOM_Y)
	for res_id: StringName in CATEGORY_ORDER:
		var slot := Control.new()
		slot.name = "Slot_%s" % String(res_id)
		slot.custom_minimum_size = slot_size
		slot.size = slot_size
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.visible = false
		_panel.add_child(slot)

		var cancel_btn := _PolygonalCancelSealButton.new()
		cancel_btn.name = "Cancel_%s" % String(res_id)
		cancel_btn.setup_glyph_label(serif_bold)
		cancel_btn.set_seal_size(Vector2(SEAL_WIDTH_SINGLE, SEAL_HEIGHT))
		cancel_btn.position = Vector2((SLAB_OUTER_SIZE.x - SEAL_WIDTH_SINGLE) * 0.5, SEAL_TOP_Y)
		cancel_btn.visible = false
		cancel_btn.pressed.connect(_on_category_cancel_button_pressed.bind(res_id))
		slot.add_child(cancel_btn)

		var slab := D2PolygonalSlab.new()
		slab.name = "Slab_%s" % String(res_id)
		slab.texture = slab_tex
		slab.configure_polygon(
			D2Tokens.POLYGON_SLAB_CMD_BASALT,
			D2Tokens.ACTION_SLAB_CMD_SIZE,
			shadow_pad
		)
		slab.position = Vector2(0.0, SEAL_HEADROOM_Y)
		slab.set_scaled_size(SLAB_OUTER_SIZE)
		slot.add_child(slab)

		var btn := _PolygonalCommandButton.new()
		btn.name = "Authorize_%s" % String(res_id)
		btn.configure_polygon(
			D2Tokens.POLYGON_SLAB_CMD_BASALT,
			D2Tokens.ACTION_SLAB_CMD_SIZE,
			shadow_pad
		)
		btn.position = Vector2(0.0, SEAL_HEADROOM_Y)
		btn.set_scaled_size(SLAB_OUTER_SIZE)
		btn.visible = false
		btn.pressed.connect(_on_category_button_pressed.bind(res_id))
		slot.add_child(btn)

		var inner := HBoxContainer.new()
		inner.name = "Content"
		inner.position = Vector2(SLAB_SHADOW_PAD_SCALED, SLAB_SHADOW_PAD_SCALED)
		inner.size = SLAB_CONTENT_SIZE
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override(&"separation", 7)
		btn.add_child(inner)

		var icon_rect := TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.texture = _icon_for_resource(res_id)
		icon_rect.custom_minimum_size = ICON_DISPLAY_SIZE
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon_rect)

		var count_lbl := Label.new()
		count_lbl.name = "Count"
		count_lbl.text = "0"
		count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_lbl.add_theme_font_size_override(&"font_size", COUNT_FONT_SIZE)
		if serif_bold != null:
			count_lbl.add_theme_font_override(&"font", serif_bold)
		count_lbl.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(count_lbl)

		_category_slots[res_id] = slot
		_category_slabs[res_id] = slab
		_category_buttons[res_id] = btn
		_category_cancel_buttons[res_id] = cancel_btn
		_category_icons[res_id] = icon_rect
		_category_count_labels[res_id] = count_lbl


func _layout_slabs_bottom_center(visible_ids: Array[StringName]) -> void:
	var count: int = visible_ids.size()
	var content_w: float = float(count) * SLAB_CONTENT_SIZE.x + float(maxi(count - 1, 0)) * SLAB_GAP_X
	var max_stagger: float = 0.0
	if count > 1:
		for i: int in range(count):
			max_stagger = maxf(max_stagger, SLAB_STAGGER_Y[i % SLAB_STAGGER_Y.size()])
	var content_h: float = SLAB_CONTENT_SIZE.y + max_stagger
	var panel_w: float = content_w + SLAB_SHADOW_PAD_SCALED * 2.0
	var panel_h: float = SEAL_HEADROOM_Y + content_h + SLAB_SHADOW_PAD_SCALED * 2.0
	var half_w: float = panel_w * 0.5
	var layout_changed: bool = _last_layout_visible_ids != visible_ids
	if layout_changed:
		_last_layout_visible_ids = visible_ids.duplicate()
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
		_panel.anchor_top = 1.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = -half_w
		_panel.offset_right = half_w
		_panel.offset_bottom = -(BOTTOM_OFFSET_PX - SLAB_SHADOW_PAD_SCALED)
		_panel.offset_top = -(BOTTOM_OFFSET_PX - SLAB_SHADOW_PAD_SCALED + panel_h)
		_panel.size = Vector2(panel_w, panel_h)

	var slot_size := Vector2(SLAB_OUTER_SIZE.x, SLAB_OUTER_SIZE.y + SEAL_HEADROOM_Y)
	var any_cancel_visible: bool = false
	var min_seal_slot_y: float = INF
	for i: int in range(count):
		var res_id: StringName = visible_ids[i]
		var slot: Control = _category_slots.get(res_id) as Control
		if slot == null:
			continue
		var sx: float = float(i) * (SLAB_CONTENT_SIZE.x + SLAB_GAP_X)
		var sy: float = SLAB_STAGGER_Y[i % SLAB_STAGGER_Y.size()] if count > 1 else 0.0
		if layout_changed:
			slot.position = Vector2(sx, sy)
			slot.size = slot_size
		if is_category_cancel_visible(res_id):
			any_cancel_visible = true
			min_seal_slot_y = minf(min_seal_slot_y, sy)

	var vp: Viewport = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp != null else size
	if vp_size.x > 0.0 and vp_size.y > 0.0:
		var left_x: float = (vp_size.x - content_w) * 0.5
		var bottom_y: float = vp_size.y - BOTTOM_OFFSET_PX
		var top_y: float = bottom_y - content_h
		if any_cancel_visible and is_finite(min_seal_slot_y):
			var panel_top_y: float = vp_size.y - (BOTTOM_OFFSET_PX - SLAB_SHADOW_PAD_SCALED + panel_h)
			top_y = minf(top_y, panel_top_y + min_seal_slot_y + SEAL_TOP_Y)
		_panel_content_rect = Rect2(Vector2(left_x, top_y), Vector2(content_w, bottom_y - top_y))
	else:
		_panel_content_rect = Rect2()


func _apply_button_visual_state(
	btn: _PolygonalCommandButton,
	icon_rect: TextureRect,
	count_lbl: Label,
	resource_id: StringName,
	count: int,
	visual_state: String
) -> void:
	var is_blocked_econ: bool = visual_state == STATE_ECONOMY_BLOCKED
	if btn.disabled != is_blocked_econ:
		btn.disabled = is_blocked_econ
	var desired_cursor: Control.CursorShape = Control.CURSOR_ARROW if is_blocked_econ else Control.CURSOR_POINTING_HAND
	if btn.mouse_default_cursor_shape != desired_cursor:
		btn.mouse_default_cursor_shape = desired_cursor
	btn.set_visual_state(visual_state)

	var text_color: Color = D2Tokens.COLOR_TEXT_PRIMARY_IVORY
	var icon_modulate: Color = Color.WHITE
	match visual_state:
		STATE_ECONOMY_BLOCKED:
			text_color = D2Tokens.COLOR_DISABLED_TEXT
			icon_modulate = Color(0.75, 0.72, 0.68, 0.45)
		STATE_AUTHORIZED:
			text_color = D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT
			icon_modulate = Color(1.0, 1.0, 1.0, 0.96)
		STATE_BLOCKED_REAUTH:
			text_color = D2Tokens.COLOR_FEEDBACK_AMBER
			icon_modulate = Color(1.0, 0.94, 0.82, 0.94)
		_:
			text_color = D2Tokens.COLOR_TEXT_PRIMARY_IVORY
			icon_modulate = Color.WHITE
	if count_lbl.get_theme_color(&"font_color") != text_color:
		count_lbl.add_theme_color_override(&"font_color", text_color)
	if icon_rect.modulate != icon_modulate:
		icon_rect.modulate = icon_modulate

	var verb: String = _action_verb(resource_id)
	var desired_tooltip: String = ""
	match visual_state:
		STATE_ECONOMY_BLOCKED:
			desired_tooltip = "Economia regional bloqueada"
		STATE_BLOCKED_REAUTH:
			desired_tooltip = "Reautorizar %s (%d)" % [verb, count]
		STATE_AUTHORIZED:
			desired_tooltip = "%s autorizado (%d)" % [verb, count]
		STATE_PARTIAL:
			desired_tooltip = "Autorizar %s restantes (%d)" % [verb, count]
		_:
			desired_tooltip = "Autorizar %s (%d)" % [verb, count]
	if btn.tooltip_text != desired_tooltip:
		btn.tooltip_text = desired_tooltip


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
	if _batch_refresh_depth > 0:
		_batch_refresh_dirty = true
		return
	refresh()


func _on_board_task_changed(_task: WorkTask) -> void:
	if _batch_refresh_depth > 0:
		_batch_refresh_dirty = true
		return
	refresh()


func _on_category_button_pressed(resource_id: StringName) -> void:
	if _is_economy_blocked():
		return
	category_authorize_requested.emit(resource_id)


func _on_category_cancel_button_pressed(resource_id: StringName) -> void:
	if _count_cancellable_tasks_for_category(resource_id) <= 0:
		return
	category_cancel_requested.emit(resource_id)
