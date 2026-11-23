class_name D2PlacementStatusBar
extends Control
## D2.2 Real-time placement validation bar using canonical atlas region "build_valid_bar".
##
## Design & Architecture Rules (UI-1.3):
## - Anchored top-center (exact visual match to approved G_godot_D2_2_construction_1920x1080
##   and G_godot_D2_2_construction_1280x720 references), dynamically clamped between
##   D2ResourceRocksView and D2TopPlaqueView so it never overlaps any corner HUD panel.
## - Uses D2PolygonalSlab with POLYGON_BUILD_VALID_BAR (10 px shadow_pad pass-through).
## - Truthfully distinguishes all placement states from PlacementController & PlacementValidator:
##   - HIDDEN: inactive / cancelled / confirmed
##   - UNEVALUATED: placement active without a fresh hover result yet (never claims LOCAL VÁLIDO)
##   - CONFIRMING: PlacementController.is_confirm_pending() == true (async NavMesh bake in flight)
##   - VALID: hover validated as valid and not confirming
##   - INVALID: hover or confirm rejected, displaying real reason_text / reason_code
## - Strictly signal-driven; zero per-frame polling; process_mode = PROCESS_MODE_PAUSABLE.

enum StatusMode {
	HIDDEN,
	UNEVALUATED,
	VALID,
	INVALID,
	CONFIRMING,
}

var _atlas: D2AtlasLibrary = null
var _theme_factory: D2ThemeFactory = null
var _placement_controller: PlacementController = null

var _slab: D2PolygonalSlab = null
var _accent_stripe: Panel = null
var _accent_style: StyleBoxFlat = null
var _status_badge: Panel = null
var _status_badge_style: StyleBoxFlat = null
var _status_badge_label: Label = null
var _message_label: Label = null

var _mode: StatusMode = StatusMode.HIDDEN
var _has_evaluation: bool = false
var _last_valid: bool = false
var _last_reason_code: StringName = &""
var _last_reason_text: String = ""
var _is_confirm_pending: bool = false

var _built: bool = false
var _viewport_size: Vector2 = Vector2(1920.0, 1080.0)
var _scale_factor: float = D2Tokens.SCALE_1080P
var _content_rect: Rect2 = Rect2()
var _apply_count: int = 0
var _last_render_key: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	set_physics_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _exit_tree() -> void:
	unbind()


func setup_visuals(
	atlas: D2AtlasLibrary,
	theme_factory: D2ThemeFactory,
	viewport_size: Vector2,
	scale_factor: float = 1.0
) -> void:
	_atlas = atlas
	_theme_factory = theme_factory
	_viewport_size = viewport_size
	_scale_factor = scale_factor
	if not _built:
		_build_nodes()
	apply_layout(_viewport_size, _scale_factor)
	refresh()


func configure(placement_controller: PlacementController) -> void:
	_disconnect_controller()
	_placement_controller = placement_controller
	_reset_state()

	if _placement_controller != null and is_instance_valid(_placement_controller):
		if not _placement_controller.placement_started.is_connected(_on_placement_started):
			_placement_controller.placement_started.connect(_on_placement_started)
		if not _placement_controller.placement_cancelled.is_connected(_on_placement_cancelled):
			_placement_controller.placement_cancelled.connect(_on_placement_cancelled)
		if not _placement_controller.placement_confirmed.is_connected(_on_placement_confirmed):
			_placement_controller.placement_confirmed.connect(_on_placement_confirmed)
		if not _placement_controller.placement_rejected.is_connected(_on_placement_rejected):
			_placement_controller.placement_rejected.connect(_on_placement_rejected)
		if not _placement_controller.hover_state_changed.is_connected(_on_hover_state_changed):
			_placement_controller.hover_state_changed.connect(_on_hover_state_changed)
		if _placement_controller.has_signal("confirm_pending_changed"):
			if not _placement_controller.confirm_pending_changed.is_connected(_on_confirm_pending_changed):
				_placement_controller.confirm_pending_changed.connect(_on_confirm_pending_changed)

		if _placement_controller.is_placement_active():
			_sync_from_controller_snapshot()

	refresh()


func unbind() -> void:
	_disconnect_controller()
	_placement_controller = null
	_reset_state()
	refresh()


func is_bound_to_controller(controller: PlacementController) -> bool:
	if controller == null or _placement_controller != controller:
		return false
	return controller.hover_state_changed.is_connected(_on_hover_state_changed)


func refresh() -> void:
	if _placement_controller == null or not is_instance_valid(_placement_controller) or not _placement_controller.is_placement_active():
		_mode = StatusMode.HIDDEN
		_render_current()
		return

	_is_confirm_pending = _placement_controller.is_confirm_pending()
	if _is_confirm_pending:
		_mode = StatusMode.CONFIRMING
	elif not _has_evaluation:
		var last_hover: PlacementValidator.ValidationResult = _placement_controller.get_last_hover_result()
		if last_hover != null:
			_has_evaluation = true
			_last_valid = last_hover.valid
			_last_reason_code = last_hover.reason_code
			_last_reason_text = last_hover.reason_text
			_mode = StatusMode.VALID if _last_valid else StatusMode.INVALID
		else:
			_mode = StatusMode.UNEVALUATED
	else:
		_mode = StatusMode.VALID if _last_valid else StatusMode.INVALID

	_render_current()


func apply_layout(viewport_size: Vector2, scale_factor: float) -> void:
	_viewport_size = viewport_size
	_scale_factor = scale_factor
	if not _built or _atlas == null:
		return

	var s: float = _scale_factor
	var w: float = _viewport_size.x

	# Compute exact top-center clearance between top-left resource rocks and top-right plaque
	var left_limit: float = (
		D2Tokens.ROCK_ORIGIN.x
		+ 3.0 * D2Tokens.ROCK_CONTENT_SIZE.x
		+ 2.0 * D2Tokens.ROCK_GAP_X
		+ D2Tokens.STATUS_BAR_SIDE_CLEARANCE_X
	) * s
	var right_limit: float = w - (
		D2Tokens.PLAQUE_MARGIN_RIGHT
		+ D2Tokens.PLAQUE_CONTENT_SIZE.x
		+ D2Tokens.STATUS_BAR_SIDE_CLEARANCE_X
	) * s
	var available_w: float = maxf(240.0 * s, right_limit - left_limit)
	var bar_w: float = minf(D2Tokens.STATUS_BAR_DISPLAY_SIZE.x * s, available_w)
	var bar_h: float = D2Tokens.STATUS_BAR_DISPLAY_SIZE.y * s
	var bar_x: float = (w - bar_w) * 0.5
	if bar_x < left_limit:
		bar_x = left_limit
	if bar_x + bar_w > right_limit:
		bar_x = maxf(left_limit, right_limit - bar_w)
	var bar_y: float = D2Tokens.STATUS_BAR_MARGIN_TOP * s

	_content_rect = Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, bar_h))

	var meta: Dictionary = _atlas.get_region_metadata("build_valid_bar")
	var pad: float = float(meta.get("pad", D2Tokens.ATLAS_SHADOW_PAD))
	var base_cw: float = float(meta.get("content_w", D2Tokens.STATUS_BAR_BASE_CONTENT_SIZE.x))
	var base_ch: float = float(meta.get("content_h", D2Tokens.STATUS_BAR_BASE_CONTENT_SIZE.y))
	var sx: float = bar_w / base_cw
	var sy: float = bar_h / base_ch

	_slab.position = Vector2(bar_x - pad * sx, bar_y - pad * sy)
	_slab.set_scaled_size(Vector2(float(meta.get("w", 660.0)) * sx, float(meta.get("h", 58.0)) * sy))

	_accent_stripe.position = Vector2(bar_x + 12.0 * s, bar_y + 7.0 * s)
	_accent_stripe.size = Vector2(maxf(3.0, 4.0 * s), bar_h - 14.0 * s)

	var badge_w: float = 82.0 * s
	var badge_h: float = 20.0 * s
	_status_badge.position = Vector2(bar_x + 22.0 * s, bar_y + (bar_h - badge_h) * 0.5)
	_status_badge.size = Vector2(badge_w, badge_h)
	_status_badge_label.position = Vector2.ZERO
	_status_badge_label.size = Vector2(badge_w, badge_h)
	_apply_font(_status_badge_label, false, true, maxi(9, int(round(9.5 * s))))

	_layout_message_label()


func get_status_mode() -> StatusMode:
	return _mode


func get_displayed_text() -> String:
	return _message_label.text if _message_label != null else ""


func get_badge_text() -> String:
	return _status_badge_label.text if _status_badge_label != null else ""


func get_last_reason_code() -> StringName:
	return _last_reason_code


func get_last_reason_text() -> String:
	return _last_reason_text


func get_slab() -> D2PolygonalSlab:
	return _slab


func get_content_bounds() -> Rect2:
	return _content_rect


func get_apply_count() -> int:
	return _apply_count


static func fallback_reason_for_code(code: StringName) -> String:
	match code:
		PlacementValidator.REASON_CAMP_RESERVED:
			return "Posição inválida: área reservada para pilhas do acampamento."
		PlacementValidator.REASON_OBSTACLE_OVERLAP:
			return "Posição inválida: há obstáculos ou construções na área."
		PlacementValidator.REASON_RESOURCE_OVERLAP:
			return "Posição inválida: área intercepta recurso natural."
		PlacementValidator.REASON_PILE_OVERLAP:
			return "Posição inválida: área intercepta pilha de recursos."
		PlacementValidator.REASON_UNIT_OVERLAP:
			return "Posição inválida: há unidade ocupando a área."
		PlacementValidator.REASON_INVALID_TERRAIN:
			return "Posição inválida: terreno ausente ou irregular para construção."
		PlacementValidator.REASON_OUT_OF_BOUNDS:
			return "Posição inválida: fora dos limites válidos da região."
		PlacementValidator.REASON_PERIMETER_UNREACHABLE:
			return "Posição inválida: sem acesso válido ao perímetro de montagem."
		PlacementValidator.REASON_CORRIDOR_BLOCKED:
			return "Posição inválida: bloquearia corredor ou acesso de navegação."
		PlacementValidator.REASON_NAV_NOT_READY:
			return "Posição inválida: navegação da região ainda não está pronta."
		PlacementValidator.REASON_NAVIGATION_STALE:
			return "Posição inválida: a navegação da região alterou durante a validação."
		_:
			return "Posição inválida."


func _build_nodes() -> void:
	_built = true

	_slab = D2PolygonalSlab.new()
	_slab.name = "PlacementStatusSlab"
	_slab.texture = _atlas.get_region_texture("build_valid_bar")
	_slab.configure_polygon(
		D2Tokens.POLYGON_BUILD_VALID_BAR,
		D2Tokens.STATUS_BAR_BASE_CONTENT_SIZE,
		D2Tokens.ATLAS_SHADOW_PAD
	)
	add_child(_slab)

	_accent_stripe = Panel.new()
	_accent_stripe.name = "PlacementStatusAccent"
	_accent_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_accent_style = StyleBoxFlat.new()
	_accent_style.bg_color = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
	_accent_stripe.add_theme_stylebox_override(&"panel", _accent_style)
	add_child(_accent_stripe)

	_status_badge = Panel.new()
	_status_badge.name = "PlacementStatusBadge"
	_status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_badge_style = StyleBoxFlat.new()
	_status_badge_style.bg_color = D2Tokens.COLOR_SURFACE_BASALT_BASE
	_status_badge_style.set_border_width_all(1)
	_status_badge_style.border_color = D2Tokens.COLOR_FEEDBACK_ERROR_DARK
	_status_badge.add_theme_stylebox_override(&"panel", _status_badge_style)
	_status_badge.visible = false
	add_child(_status_badge)

	_status_badge_label = Label.new()
	_status_badge_label.name = "PlacementStatusBadgeLabel"
	_status_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_badge.add_child(_status_badge_label)

	_message_label = Label.new()
	_message_label.name = "PlacementStatusMessage"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.clip_text = true
	_message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message_label)


func _render_current() -> void:
	if not _built:
		visible = (_mode != StatusMode.HIDDEN)
		return

	if _mode == StatusMode.HIDDEN:
		var hide_key: String = "HIDDEN"
		if hide_key != _last_render_key:
			_last_render_key = hide_key
			_apply_count += 1
		visible = false
		_message_label.text = ""
		_status_badge_label.text = ""
		_status_badge.visible = false
		return

	var active_def: BuildingDefinition = _placement_controller.get_active_definition() if (_placement_controller != null and is_instance_valid(_placement_controller)) else null
	var def_name: String = active_def.display_name if active_def != null else "Edificação"
	var dim_str: String = _format_dimensions(active_def)

	var show_badge: bool = false
	var badge_text: String = ""
	var badge_text_col: Color = D2Tokens.COLOR_TEXT_PRIMARY_IVORY
	var badge_border_col: Color = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
	var accent_col: Color = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
	var msg_text: String = ""
	var msg_col: Color = D2Tokens.COLOR_TEXT_ON_ALABASTER_INK

	match _mode:
		StatusMode.VALID:
			accent_col = D2Tokens.COLOR_FEEDBACK_VALID_GREEN
			msg_col = D2Tokens.COLOR_FEEDBACK_VALID_GREEN
			msg_text = "LOCAL VÁLIDO · Maquete: %s (%s) · Clique esq. assentar · Esc soltar" % [def_name, dim_str]
		StatusMode.INVALID:
			show_badge = true
			badge_text = "INVÁLIDO"
			badge_text_col = D2Tokens.COLOR_FEEDBACK_ERROR_ROSE
			badge_border_col = D2Tokens.COLOR_FEEDBACK_ERROR_DARK
			accent_col = D2Tokens.COLOR_FEEDBACK_ERROR_DARK
			msg_col = D2Tokens.COLOR_TEXT_ON_ALABASTER_INK
			var reason: String = _last_reason_text.strip_edges()
			if reason.is_empty():
				reason = fallback_reason_for_code(_last_reason_code)
			msg_text = "%s · Esc soltar" % reason
		StatusMode.CONFIRMING:
			show_badge = true
			badge_text = "VALIDANDO"
			badge_text_col = D2Tokens.COLOR_FEEDBACK_AMBER
			badge_border_col = D2Tokens.COLOR_FEEDBACK_AMBER
			accent_col = D2Tokens.COLOR_FEEDBACK_AMBER
			msg_col = D2Tokens.COLOR_TEXT_ON_ALABASTER_INK
			msg_text = "Verificando conectividade de %s (%s) · Esc cancelar" % [def_name, dim_str]
		StatusMode.UNEVALUATED:
			accent_col = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
			msg_col = D2Tokens.COLOR_TEXT_ON_ALABASTER_SUB
			msg_text = "AGUARDANDO TERRENO · Maquete: %s (%s) · Mova o cursor · Esc soltar" % [def_name, dim_str]

	var render_key: String = "%d|%s|%s" % [int(_mode), badge_text, msg_text]
	visible = true
	if render_key == _last_render_key:
		return
	_last_render_key = render_key
	_apply_count += 1

	_accent_style.bg_color = accent_col
	_status_badge.visible = show_badge
	_status_badge_style.border_color = badge_border_col
	_status_badge_label.text = badge_text
	_status_badge_label.add_theme_color_override(&"font_color", badge_text_col)

	_message_label.text = msg_text
	_message_label.add_theme_color_override(&"font_color", msg_col)
	_layout_message_label()


func _layout_message_label() -> void:
	if not _built or _message_label == null:
		return
	var s: float = _scale_factor
	var bar_x: float = _content_rect.position.x
	var bar_y: float = _content_rect.position.y
	var bar_w: float = _content_rect.size.x
	var bar_h: float = _content_rect.size.y
	var left_pad: float = (112.0 * s) if _status_badge.visible else (24.0 * s)
	var right_pad: float = 20.0 * s
	_message_label.position = Vector2(bar_x + left_pad, bar_y + 4.0 * s)
	_message_label.size = Vector2(maxf(80.0 * s, bar_w - left_pad - right_pad), bar_h - 8.0 * s)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _status_badge.visible else HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(_message_label, false, true, maxi(10, int(round(11.4 * s))))


func _reset_state() -> void:
	_mode = StatusMode.HIDDEN
	_has_evaluation = false
	_last_valid = false
	_last_reason_code = &""
	_last_reason_text = ""
	_is_confirm_pending = false


func _sync_from_controller_snapshot() -> void:
	if _placement_controller == null or not is_instance_valid(_placement_controller):
		return
	_is_confirm_pending = _placement_controller.is_confirm_pending()
	var last_hover: PlacementValidator.ValidationResult = _placement_controller.get_last_hover_result()
	if last_hover != null:
		_has_evaluation = true
		_last_valid = last_hover.valid
		_last_reason_code = last_hover.reason_code
		_last_reason_text = last_hover.reason_text
	else:
		_has_evaluation = false
		_last_valid = false
		_last_reason_code = &""
		_last_reason_text = ""


func _on_placement_started(_definition: BuildingDefinition) -> void:
	_reset_state()
	refresh()


func _on_placement_cancelled(_definition: BuildingDefinition) -> void:
	_reset_state()
	refresh()


func _on_placement_confirmed(
	_definition: BuildingDefinition,
	_world_position: Vector3,
	_result: PlacementValidator.ValidationResult
) -> void:
	_reset_state()
	refresh()


func _on_placement_rejected(
	_definition: BuildingDefinition,
	_world_position: Vector3,
	result: PlacementValidator.ValidationResult
) -> void:
	_is_confirm_pending = false
	_has_evaluation = true
	_last_valid = false
	if result != null:
		_last_reason_code = result.reason_code
		_last_reason_text = result.reason_text
	else:
		_last_reason_code = &""
		_last_reason_text = "Posição inválida."
	refresh()


func _on_hover_state_changed(valid: bool, reason_text: String, _world_position: Vector3) -> void:
	if _placement_controller == null or not is_instance_valid(_placement_controller) or not _placement_controller.is_placement_active():
		return
	_has_evaluation = true
	_last_valid = valid
	_last_reason_text = reason_text
	var last_hover: PlacementValidator.ValidationResult = _placement_controller.get_last_hover_result()
	if last_hover != null and last_hover.valid == valid:
		_last_reason_code = last_hover.reason_code
		if _last_reason_text.is_empty():
			_last_reason_text = last_hover.reason_text
	elif valid:
		_last_reason_code = &""
	refresh()


func _on_confirm_pending_changed(pending: bool) -> void:
	_is_confirm_pending = pending
	refresh()


func _disconnect_controller() -> void:
	if _placement_controller != null and is_instance_valid(_placement_controller):
		if _placement_controller.placement_started.is_connected(_on_placement_started):
			_placement_controller.placement_started.disconnect(_on_placement_started)
		if _placement_controller.placement_cancelled.is_connected(_on_placement_cancelled):
			_placement_controller.placement_cancelled.disconnect(_on_placement_cancelled)
		if _placement_controller.placement_confirmed.is_connected(_on_placement_confirmed):
			_placement_controller.placement_confirmed.disconnect(_on_placement_confirmed)
		if _placement_controller.placement_rejected.is_connected(_on_placement_rejected):
			_placement_controller.placement_rejected.disconnect(_on_placement_rejected)
		if _placement_controller.hover_state_changed.is_connected(_on_hover_state_changed):
			_placement_controller.hover_state_changed.disconnect(_on_hover_state_changed)
		if _placement_controller.has_signal("confirm_pending_changed"):
			if _placement_controller.confirm_pending_changed.is_connected(_on_confirm_pending_changed):
				_placement_controller.confirm_pending_changed.disconnect(_on_confirm_pending_changed)


static func _format_dimensions(definition: BuildingDefinition) -> String:
	if definition == null:
		return "--"
	var w_s: String = "%d" % int(round(definition.footprint_size.x)) if is_equal_approx(definition.footprint_size.x, round(definition.footprint_size.x)) else "%.1f" % definition.footprint_size.x
	var d_s: String = "%d" % int(round(definition.footprint_size.y)) if is_equal_approx(definition.footprint_size.y, round(definition.footprint_size.y)) else "%.1f" % definition.footprint_size.y
	return "%s×%s m" % [w_s, d_s]


func _apply_font(lbl: Label, serif: bool, bold: bool, font_px: int) -> void:
	lbl.add_theme_font_size_override(&"font_size", font_px)
	if _theme_factory == null:
		return
	var f: Font = _theme_factory.get_serif_font(bold) if serif else _theme_factory.get_sans_font(bold)
	if f != null:
		lbl.add_theme_font_override(&"font", f)
