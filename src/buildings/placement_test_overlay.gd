class_name PlacementTestOverlay
extends Control
## Minimal temporary UI trigger, placement feedback, and T3.3 site inspection panel.
## Intentionally temporary for T3.2/T3.3; does not implement the T3.5 build catalog or inspector HUD.

const TOAST_DURATION_SEC: float = 2.8
const VALID_TEXT_COLOR: Color = Color(0.58, 0.80, 0.52, 1.0)
const INVALID_TEXT_COLOR: Color = Color(0.90, 0.45, 0.38, 1.0)
const TOAST_TEXT_COLOR: Color = Color(0.86, 0.88, 0.62, 1.0)

var _placement_controller: PlacementController = null
var _construction_manager: ConstructionManager = null
var _command_controller: CommandController = null
var _selection_manager: SelectionManager = null
var _input_controller: RtsInputController = null
var _selected_site: ConstructionSite = null

var _shelter_def: BuildingDefinition = null
var _depot_def: BuildingDefinition = null

var _bar_panel: PanelContainer = null
var _shelter_btn: Button = null
var _depot_btn: Button = null
var _cancel_btn: Button = null

var _status_panel: PanelContainer = null
var _status_title_label: Label = null
var _status_detail_label: Label = null

var _site_panel: PanelContainer = null
var _site_title_label: Label = null
var _site_state_label: Label = null
var _site_resources_label: Label = null
var _site_workers_label: Label = null
var _site_assign_btn: Button = null
var _site_close_btn: Button = null

var _resolution_service: DisplayResolutionService = DisplayResolutionService.new()
var _test_workers_controller: TemporaryTestWorkersController = null
var _last_requested_resolution: Vector2i = Vector2i.ZERO
var _bound_window: Window = null

var _res_720_btn: Button = null
var _res_1080_btn: Button = null
var _res_status_label: Label = null
var _add_c4_workers_btn: Button = null
var _remove_c4_workers_btn: Button = null

var _toast_remaining_sec: float = 0.0
var _built_ui: bool = false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_build_ui()
	_bind_window_resize()
	_refresh_resolution_label()
	_refresh_test_worker_buttons()


func _exit_tree() -> void:
	_unbind_window_resize()
	_disconnect_controller()
	_disconnect_construction()
	_test_workers_controller = null
	set_inspected_site(null)


func _process(delta: float) -> void:
	if _toast_remaining_sec <= 0.0:
		set_process(false)
		return
	_toast_remaining_sec -= maxf(delta, 0.0)
	if _toast_remaining_sec <= 0.0:
		_toast_remaining_sec = 0.0
		set_process(false)
		if _placement_controller == null or not _placement_controller.is_placement_active():
			if _status_panel != null:
				_status_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _placement_controller == null or not is_instance_valid(_placement_controller):
		return
	if event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			if key_ev.physical_keycode == KEY_F8:
				_bar_panel.visible = not _bar_panel.visible
				_consume_viewport_input()
			elif key_ev.physical_keycode == KEY_F6 and _shelter_def != null:
				_toggle_definition(_shelter_def)
				_consume_viewport_input()
			elif key_ev.physical_keycode == KEY_F7 and _depot_def != null:
				_toggle_definition(_depot_def)
				_consume_viewport_input()


func set_development_controls_visible(enabled: bool) -> void:
	_build_ui()
	_bar_panel.visible = enabled


func use_game_catalog() -> void:
	_build_ui()
	_shelter_btn.visible = false
	_depot_btn.visible = false
	_bar_panel.visible = false


func configure(
	placement_controller: PlacementController,
	shelter_definition: BuildingDefinition,
	depot_definition: BuildingDefinition
) -> void:
	_build_ui()
	_disconnect_controller()
	_placement_controller = placement_controller
	_shelter_def = shelter_definition
	_depot_def = depot_definition

	if _placement_controller != null:
		_placement_controller.placement_started.connect(_on_placement_started)
		_placement_controller.placement_cancelled.connect(_on_placement_cancelled)
		_placement_controller.placement_confirmed.connect(_on_placement_confirmed)
		_placement_controller.placement_rejected.connect(_on_placement_rejected)
		_placement_controller.hover_state_changed.connect(_on_hover_state_changed)

	_sync_button_states()


func configure_construction(
	construction_manager: ConstructionManager,
	command_controller: CommandController = null,
	selection_manager: SelectionManager = null,
	input_controller: RtsInputController = null
) -> void:
	_build_ui()
	_disconnect_construction()
	_construction_manager = construction_manager
	_command_controller = command_controller
	_selection_manager = selection_manager
	_input_controller = input_controller

	if _construction_manager != null and is_instance_valid(_construction_manager):
		_construction_manager.site_created.connect(_on_site_created)
		_construction_manager.site_creation_rejected.connect(_on_site_creation_rejected)
	if _input_controller != null and is_instance_valid(_input_controller):
		_input_controller.construction_site_picked.connect(_on_construction_site_picked)
	if _command_controller != null and is_instance_valid(_command_controller):
		_command_controller.command_rejected.connect(_on_command_rejected)
	if _selection_manager != null and is_instance_valid(_selection_manager):
		_selection_manager.selection_changed.connect(_on_selection_changed_for_site_ui)
	_refresh_site_panel()


func configure_test_workers(controller: TemporaryTestWorkersController) -> void:
	_build_ui()
	_test_workers_controller = controller
	_refresh_test_worker_buttons()


func set_inspected_site(site: ConstructionSite) -> void:
	if _selected_site != null and is_instance_valid(_selected_site):
		if _selected_site.state_changed.is_connected(_on_inspected_site_updated):
			_selected_site.state_changed.disconnect(_on_inspected_site_updated)
		if _selected_site.buffer_changed.is_connected(_on_inspected_site_updated):
			_selected_site.buffer_changed.disconnect(_on_inspected_site_updated)
		if _selected_site.workers_changed.is_connected(_on_inspected_site_updated):
			_selected_site.workers_changed.disconnect(_on_inspected_site_updated)
	_selected_site = site if (site != null and is_instance_valid(site) and site.is_valid()) else null
	if _selected_site != null:
		if not _selected_site.state_changed.is_connected(_on_inspected_site_updated):
			_selected_site.state_changed.connect(_on_inspected_site_updated)
		if not _selected_site.buffer_changed.is_connected(_on_inspected_site_updated):
			_selected_site.buffer_changed.connect(_on_inspected_site_updated)
		if not _selected_site.workers_changed.is_connected(_on_inspected_site_updated):
			_selected_site.workers_changed.connect(_on_inspected_site_updated)
	_refresh_site_panel()


func get_inspected_site() -> ConstructionSite:
	return _selected_site


func get_assign_workers_button() -> Button:
	return _site_assign_btn


func get_shelter_button() -> Button:
	return _shelter_btn


func get_depot_button() -> Button:
	return _depot_btn


func get_cancel_button() -> Button:
	return _cancel_btn


func get_status_title_text() -> String:
	return _status_title_label.text if _status_title_label != null else ""


func get_status_detail_text() -> String:
	return _status_detail_label.text if _status_detail_label != null else ""


func is_status_visible() -> bool:
	return _status_panel != null and _status_panel.visible


func is_site_panel_visible() -> bool:
	return _site_panel != null and _site_panel.visible


func get_resolution_720_button() -> Button:
	return _res_720_btn


func get_resolution_1080_button() -> Button:
	return _res_1080_btn


func get_resolution_status_text() -> String:
	return _res_status_label.text if _res_status_label != null else ""


func get_add_c4_workers_button() -> Button:
	return _add_c4_workers_btn


func get_remove_c4_workers_button() -> Button:
	return _remove_c4_workers_btn


func get_display_resolution_service() -> DisplayResolutionService:
	return _resolution_service


func get_temporary_workers_controller() -> TemporaryTestWorkersController:
	return _test_workers_controller


func apply_test_resolution(requested_size: Vector2i) -> Dictionary:
	_last_requested_resolution = requested_size
	var win: Window = get_window()
	var res: Dictionary = _resolution_service.apply_resolution(win, requested_size)
	_refresh_resolution_label()
	if bool(res.get("ok", false)) and _status_panel != null:
		var eff: Vector2i = res.get("effective_size", Vector2i.ZERO) as Vector2i
		if bool(res.get("was_clamped", false)):
			_show_toast(
				"Resolução ajustada aos limites do monitor",
				"Aplicada: %d×%d (solicitada: %d×%d)" % [eff.x, eff.y, requested_size.x, requested_size.y],
				TOAST_TEXT_COLOR
			)
		else:
			_show_toast(
				"Resolução aplicada",
				"Janela atualizada para %d×%d sem reiniciar a partida" % [eff.x, eff.y],
				VALID_TEXT_COLOR
			)
	return res


func _build_ui() -> void:
	if _built_ui:
		return
	_built_ui = true

	layout_mode = 1
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bar_panel = PanelContainer.new()
	_bar_panel.name = "TemporaryPlacementBar"
	_bar_panel.anchor_left = 1.0
	_bar_panel.anchor_top = 1.0
	_bar_panel.anchor_right = 1.0
	_bar_panel.anchor_bottom = 1.0
	_bar_panel.offset_left = -476.0
	_bar_panel.offset_top = -152.0
	_bar_panel.offset_right = -16.0
	_bar_panel.offset_bottom = -16.0
	_bar_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_panel.add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())
	add_child(_bar_panel)

	var bar_margin := MarginContainer.new()
	bar_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_margin.add_theme_constant_override(&"margin_left", 10)
	bar_margin.add_theme_constant_override(&"margin_top", 6)
	bar_margin.add_theme_constant_override(&"margin_right", 10)
	bar_margin.add_theme_constant_override(&"margin_bottom", 8)
	_bar_panel.add_child(bar_margin)

	var bar_vbox := VBoxContainer.new()
	bar_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_vbox.add_theme_constant_override(&"separation", 4)
	bar_margin.add_child(bar_vbox)

	var header := Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.text = "Construção e testes temporários (T3.2/T3.3)"
	header.add_theme_font_size_override(&"font_size", 11)
	header.add_theme_color_override(&"font_color", HudStyle.TEXT_MUTED_COLOR)
	bar_vbox.add_child(header)

	var btn_row := HBoxContainer.new()
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_theme_constant_override(&"separation", 6)
	bar_vbox.add_child(btn_row)

	_shelter_btn = _create_button("Abrigo 4×4 [F6]")
	_shelter_btn.pressed.connect(func() -> void: _toggle_definition(_shelter_def))
	btn_row.add_child(_shelter_btn)

	_depot_btn = _create_button("Depósito 5×4 [F7]")
	_depot_btn.pressed.connect(func() -> void: _toggle_definition(_depot_def))
	btn_row.add_child(_depot_btn)

	_cancel_btn = _create_button("Cancelar")
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)

	var res_row := HBoxContainer.new()
	res_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res_row.add_theme_constant_override(&"separation", 6)
	bar_vbox.add_child(res_row)

	var res_prefix := Label.new()
	res_prefix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res_prefix.text = "Resolução:"
	res_prefix.add_theme_font_size_override(&"font_size", 11)
	res_prefix.add_theme_color_override(&"font_color", HudStyle.TEXT_MUTED_COLOR)
	res_row.add_child(res_prefix)

	_res_720_btn = _create_button("1280×720")
	_res_720_btn.pressed.connect(func() -> void: apply_test_resolution(DisplayResolutionService.PRESET_1280X720))
	res_row.add_child(_res_720_btn)

	_res_1080_btn = _create_button("1920×1080")
	_res_1080_btn.pressed.connect(func() -> void: apply_test_resolution(DisplayResolutionService.PRESET_1920X1080))
	res_row.add_child(_res_1080_btn)

	_res_status_label = Label.new()
	_res_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_res_status_label.text = "Atual: --"
	_res_status_label.add_theme_font_size_override(&"font_size", 11)
	_res_status_label.add_theme_color_override(&"font_color", HudStyle.TEXT_SECONDARY_COLOR)
	res_row.add_child(_res_status_label)

	var c4_row := HBoxContainer.new()
	c4_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c4_row.add_theme_constant_override(&"separation", 6)
	bar_vbox.add_child(c4_row)

	_add_c4_workers_btn = _create_button("Adicionar 2 trabalhadores de teste — C4")
	_add_c4_workers_btn.pressed.connect(_on_add_c4_workers_pressed)
	c4_row.add_child(_add_c4_workers_btn)

	_remove_c4_workers_btn = _create_button("Remover temporários")
	_remove_c4_workers_btn.pressed.connect(_on_remove_c4_workers_pressed)
	c4_row.add_child(_remove_c4_workers_btn)

	_status_panel = PanelContainer.new()
	_status_panel.name = "PlacementStatusBanner"
	_status_panel.anchor_left = 0.5
	_status_panel.anchor_right = 0.5
	_status_panel.offset_left = -280.0
	_status_panel.offset_top = 16.0
	_status_panel.offset_right = 280.0
	_status_panel.offset_bottom = 72.0
	_status_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.visible = false
	_status_panel.add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())
	add_child(_status_panel)

	var status_margin := MarginContainer.new()
	status_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_margin.add_theme_constant_override(&"margin_left", 14)
	status_margin.add_theme_constant_override(&"margin_top", 8)
	status_margin.add_theme_constant_override(&"margin_right", 14)
	status_margin.add_theme_constant_override(&"margin_bottom", 8)
	_status_panel.add_child(status_margin)

	var status_vbox := VBoxContainer.new()
	status_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_vbox.add_theme_constant_override(&"separation", 3)
	status_margin.add_child(status_vbox)

	_status_title_label = Label.new()
	_status_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_title_label.add_theme_font_size_override(&"font_size", 13)
	_status_title_label.add_theme_color_override(&"font_color", HudStyle.TEXT_PRIMARY_COLOR)
	status_vbox.add_child(_status_title_label)

	_status_detail_label = Label.new()
	_status_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_detail_label.add_theme_font_size_override(&"font_size", 13)
	_status_detail_label.add_theme_color_override(&"font_color", VALID_TEXT_COLOR)
	status_vbox.add_child(_status_detail_label)

	_site_panel = PanelContainer.new()
	_site_panel.name = "TemporarySitePanel"
	_site_panel.anchor_left = 0.0
	_site_panel.anchor_top = 0.0
	_site_panel.offset_left = 16.0
	_site_panel.offset_top = 68.0
	_site_panel.offset_right = 348.0
	_site_panel.offset_bottom = 260.0
	_site_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_site_panel.visible = false
	_site_panel.add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())
	add_child(_site_panel)

	var site_margin := MarginContainer.new()
	site_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	site_margin.add_theme_constant_override(&"margin_left", 10)
	site_margin.add_theme_constant_override(&"margin_top", 8)
	site_margin.add_theme_constant_override(&"margin_right", 10)
	site_margin.add_theme_constant_override(&"margin_bottom", 8)
	_site_panel.add_child(site_margin)

	var site_vbox := VBoxContainer.new()
	site_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	site_vbox.add_theme_constant_override(&"separation", 4)
	site_margin.add_child(site_vbox)

	var site_header := Label.new()
	site_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	site_header.text = "Canteiro T3.3 (UI temporária)"
	site_header.add_theme_font_size_override(&"font_size", 11)
	site_header.add_theme_color_override(&"font_color", HudStyle.TEXT_MUTED_COLOR)
	site_vbox.add_child(site_header)

	_site_title_label = Label.new()
	_site_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_site_title_label.add_theme_font_size_override(&"font_size", 13)
	_site_title_label.add_theme_color_override(&"font_color", HudStyle.TEXT_PRIMARY_COLOR)
	site_vbox.add_child(_site_title_label)

	_site_state_label = Label.new()
	_site_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_site_state_label.add_theme_font_size_override(&"font_size", 12)
	_site_state_label.add_theme_color_override(&"font_color", VALID_TEXT_COLOR)
	site_vbox.add_child(_site_state_label)

	_site_resources_label = Label.new()
	_site_resources_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_site_resources_label.add_theme_font_size_override(&"font_size", 12)
	_site_resources_label.add_theme_color_override(&"font_color", HudStyle.TEXT_SECONDARY_COLOR)
	site_vbox.add_child(_site_resources_label)

	_site_workers_label = Label.new()
	_site_workers_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_site_workers_label.add_theme_font_size_override(&"font_size", 12)
	_site_workers_label.add_theme_color_override(&"font_color", HudStyle.TEXT_SECONDARY_COLOR)
	site_vbox.add_child(_site_workers_label)

	var site_btn_row := HBoxContainer.new()
	site_btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	site_btn_row.add_theme_constant_override(&"separation", 6)
	site_vbox.add_child(site_btn_row)

	_site_assign_btn = _create_button("Designar selecionados")
	_site_assign_btn.pressed.connect(_on_assign_selected_pressed)
	site_btn_row.add_child(_site_assign_btn)

	_site_close_btn = _create_button("Fechar")
	_site_close_btn.pressed.connect(func() -> void: set_inspected_site(null))
	site_btn_row.add_child(_site_close_btn)


func _create_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override(&"font_size", 12)
	return btn


func _toggle_definition(def: BuildingDefinition) -> void:
	if _placement_controller == null or def == null:
		return
	if _placement_controller.is_placement_active() and _placement_controller.get_active_definition() == def:
		_placement_controller.cancel_placement()
		return
	_placement_controller.start_placement(def)


func _on_cancel_pressed() -> void:
	if _placement_controller != null:
		_placement_controller.cancel_placement()


func _on_placement_started(def: BuildingDefinition) -> void:
	_toast_remaining_sec = 0.0
	set_process(false)
	_sync_button_states()
	if _status_panel != null and def != null:
		_status_title_label.text = "Posicionando: %s (%.1f × %.1f m) — Esq.: confirmar | Dir./Esc: cancelar" % [
			def.display_name,
			def.footprint_size.x,
			def.footprint_size.y,
		]
		_status_detail_label.text = "Mova o cursor sobre o terreno"
		_status_detail_label.add_theme_color_override(&"font_color", HudStyle.TEXT_SECONDARY_COLOR)
		_status_panel.visible = true


func _on_placement_cancelled(_def: BuildingDefinition) -> void:
	_toast_remaining_sec = 0.0
	set_process(false)
	_sync_button_states()
	if _status_panel != null:
		_status_panel.visible = false


func _on_placement_confirmed(
	def: BuildingDefinition,
	world_pos: Vector3,
	_result: PlacementValidator.ValidationResult
) -> void:
	_sync_button_states()
	if _status_panel != null and def != null and _construction_manager == null:
		_status_title_label.text = "Posição válida confirmada: %s em (%.1f, %.1f)" % [
			def.display_name,
			world_pos.x,
			world_pos.z,
		]
		_status_detail_label.text = "Simulação T3.2 concluída — nenhuma obra ou reserva criada"
		_status_detail_label.add_theme_color_override(&"font_color", TOAST_TEXT_COLOR)
		_status_panel.visible = true
		_toast_remaining_sec = TOAST_DURATION_SEC
		set_process(true)


func _on_placement_rejected(
	_def: BuildingDefinition,
	_world_pos: Vector3,
	result: PlacementValidator.ValidationResult
) -> void:
	_sync_button_states()
	if _status_panel != null and result != null:
		_status_detail_label.text = result.reason_text if not result.reason_text.is_empty() else "Posição inválida."
		_status_detail_label.add_theme_color_override(&"font_color", INVALID_TEXT_COLOR)
		_status_panel.visible = true


func _on_hover_state_changed(valid: bool, reason_text: String, _world_pos: Vector3) -> void:
	if _placement_controller == null or not _placement_controller.is_placement_active():
		return
	if _status_panel == null:
		return
	_status_panel.visible = true
	if valid:
		_status_detail_label.text = "Posição válida (clique esquerdo para validar malha e confirmar)"
		_status_detail_label.add_theme_color_override(&"font_color", VALID_TEXT_COLOR)
	else:
		_status_detail_label.text = reason_text if not reason_text.is_empty() else "Posição inválida."
		_status_detail_label.add_theme_color_override(&"font_color", INVALID_TEXT_COLOR)


func _sync_button_states() -> void:
	var active_def: BuildingDefinition = _placement_controller.get_active_definition() if _placement_controller != null else null
	var is_active: bool = _placement_controller != null and _placement_controller.is_placement_active()
	if _cancel_btn != null:
		_cancel_btn.visible = is_active
	if _shelter_btn != null:
		_shelter_btn.text = ("[Abrigo 4×4]" if (is_active and active_def == _shelter_def) else "Abrigo 4×4 [F6]")
	if _depot_btn != null:
		_depot_btn.text = ("[Depósito 5×4]" if (is_active and active_def == _depot_def) else "Depósito 5×4 [F7]")


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
	_placement_controller = null


func _disconnect_construction() -> void:
	if _construction_manager != null and is_instance_valid(_construction_manager):
		if _construction_manager.site_created.is_connected(_on_site_created):
			_construction_manager.site_created.disconnect(_on_site_created)
		if _construction_manager.site_creation_rejected.is_connected(_on_site_creation_rejected):
			_construction_manager.site_creation_rejected.disconnect(_on_site_creation_rejected)
	if _input_controller != null and is_instance_valid(_input_controller):
		if _input_controller.construction_site_picked.is_connected(_on_construction_site_picked):
			_input_controller.construction_site_picked.disconnect(_on_construction_site_picked)
	if _command_controller != null and is_instance_valid(_command_controller):
		if _command_controller.command_rejected.is_connected(_on_command_rejected):
			_command_controller.command_rejected.disconnect(_on_command_rejected)
	if _selection_manager != null and is_instance_valid(_selection_manager):
		if _selection_manager.selection_changed.is_connected(_on_selection_changed_for_site_ui):
			_selection_manager.selection_changed.disconnect(_on_selection_changed_for_site_ui)
	_construction_manager = null
	_command_controller = null
	_selection_manager = null
	_input_controller = null


func _on_site_created(site: ConstructionSite) -> void:
	if site != null and is_instance_valid(site):
		set_inspected_site(site)
	if _status_panel != null and site != null and site.definition != null:
		_status_title_label.text = "Canteiro criado: %s (%s)" % [site.definition.display_name, String(site.site_id)]
		_status_detail_label.text = "Recursos reservados; designe trabalhadores com clique direito no canteiro"
		_status_detail_label.add_theme_color_override(&"font_color", VALID_TEXT_COLOR)
		_status_panel.visible = true
		_toast_remaining_sec = TOAST_DURATION_SEC
		set_process(true)


func _on_site_creation_rejected(
	_reason: String,
	message: String,
	definition: BuildingDefinition,
	_world_position: Vector3
) -> void:
	if _status_panel != null:
		var def_name: String = definition.display_name if definition != null else "Edificação"
		_status_title_label.text = "Não foi possível criar canteiro: %s" % def_name
		_status_detail_label.text = message if not message.is_empty() else "Operação rejeitada."
		_status_detail_label.add_theme_color_override(&"font_color", INVALID_TEXT_COLOR)
		_status_panel.visible = true
		_toast_remaining_sec = TOAST_DURATION_SEC
		set_process(true)


func _on_construction_site_picked(site: ConstructionSite) -> void:
	set_inspected_site(site)


func _on_selection_changed_for_site_ui(_selected: Array[Unit]) -> void:
	_refresh_site_panel()


func _on_inspected_site_updated(_site: ConstructionSite, _extra_a: Variant = null, _extra_b: Variant = null) -> void:
	_refresh_site_panel()


func _on_assign_selected_pressed() -> void:
	if _selected_site == null or not is_instance_valid(_selected_site) or _command_controller == null:
		return
	var ok: bool = _command_controller.command_units_to_site(_selected_site)
	if not ok:
		_show_command_rejection_banner(_command_controller.get_last_command_reason())
	_refresh_site_panel()


func _on_command_rejected(pick: PickResult, reason: String) -> void:
	if pick != null and pick.is_construction_site():
		_show_command_rejection_banner(reason)


func _show_command_rejection_banner(reason: String) -> void:
	_show_toast("Designação não aplicada", _format_command_rejection_reason(reason), INVALID_TEXT_COLOR)


func _format_command_rejection_reason(reason: String) -> String:
	match reason:
		ConstructOrder.REASON_NO_WORKER_SLOT:
			return "Motivo: Canteiro sem vaga disponível (1 transportador + máx. 2 construtores — no_worker_slot)"
		ConstructOrder.REASON_SITE_SUPPLIED:
			return "Motivo: Canteiro já está completamente suprido (site_supplied)"
		ConstructOrder.REASON_SITE_UNREACHABLE:
			return "Motivo: Canteiro inacessível na malha de navegação (site_unreachable)"
		_:
			return "Motivo: %s" % (reason if not reason.is_empty() else "operação recusada")


func _show_toast(title_text: String, detail_text: String, detail_color: Color) -> void:
	if _status_panel == null:
		return
	_status_title_label.text = title_text
	_status_detail_label.text = detail_text
	_status_detail_label.add_theme_color_override(&"font_color", detail_color)
	_status_panel.visible = true
	_toast_remaining_sec = TOAST_DURATION_SEC
	set_process(true)


func _on_add_c4_workers_pressed() -> void:
	if _test_workers_controller == null:
		return
	var res: Dictionary = _test_workers_controller.spawn_temporary_workers()
	_refresh_test_worker_buttons()
	if bool(res.get("ok", false)):
		_show_toast("Trabalhadores temporários C4 prontos", str(res.get("message", "")), VALID_TEXT_COLOR)
	else:
		_show_toast("Trabalhadores C4", str(res.get("message", "")), TOAST_TEXT_COLOR)


func _on_remove_c4_workers_pressed() -> void:
	if _test_workers_controller == null:
		return
	var res: Dictionary = _test_workers_controller.remove_temporary_workers_safely()
	_refresh_test_worker_buttons()
	if bool(res.get("ok", false)):
		_show_toast("Trabalhadores temporários removidos", str(res.get("message", "")), VALID_TEXT_COLOR)
	else:
		_show_toast("Remoção bloqueada por segurança", str(res.get("message", "")), INVALID_TEXT_COLOR)


func _refresh_test_worker_buttons() -> void:
	var has_ctrl: bool = _test_workers_controller != null
	var has_workers: bool = has_ctrl and _test_workers_controller.has_temporary_workers()
	if _add_c4_workers_btn != null:
		_add_c4_workers_btn.disabled = (not has_ctrl) or has_workers
	if _remove_c4_workers_btn != null:
		_remove_c4_workers_btn.disabled = (not has_ctrl) or (not has_workers)


func _bind_window_resize() -> void:
	var win: Window = get_window()
	if win == _bound_window:
		return
	_unbind_window_resize()
	if win != null and is_instance_valid(win):
		_bound_window = win
		if not _bound_window.size_changed.is_connected(_on_window_size_changed):
			_bound_window.size_changed.connect(_on_window_size_changed)


func _unbind_window_resize() -> void:
	if _bound_window != null and is_instance_valid(_bound_window):
		if _bound_window.size_changed.is_connected(_on_window_size_changed):
			_bound_window.size_changed.disconnect(_on_window_size_changed)
	_bound_window = null


func _on_window_size_changed() -> void:
	_refresh_resolution_label()


func _refresh_resolution_label() -> void:
	if _res_status_label == null:
		return
	_res_status_label.text = DisplayResolutionService.format_resolution_status(get_window(), _last_requested_resolution)


func _refresh_site_panel() -> void:
	if _site_panel == null:
		return
	if _selected_site == null or not is_instance_valid(_selected_site) or not _selected_site.is_valid():
		_site_panel.visible = false
		return

	_site_panel.visible = true
	var snap: Dictionary = _selected_site.get_status_snapshot()
	var display_name: String = str(snap.get("display_name", "Canteiro"))
	_site_title_label.text = "%s [%s]" % [display_name, String(_selected_site.site_id)]

	var fully_supplied: bool = bool(snap.get("is_fully_supplied", false))
	if fully_supplied:
		_site_state_label.text = "Estado: Suprido e pronto para construção (T3.4)"
		_site_state_label.add_theme_color_override(&"font_color", VALID_TEXT_COLOR)
	else:
		_site_state_label.text = "Estado: Aguardando suprimento físico (T3.3)"
		_site_state_label.add_theme_color_override(&"font_color", TOAST_TEXT_COLOR)

	var req: Dictionary = snap.get("required", {}) as Dictionary
	var buf: Dictionary = snap.get("delivered_buffer", {}) as Dictionary
	var res_piles: Dictionary = snap.get("reserved_in_piles", {}) as Dictionary
	var transit: Dictionary = snap.get("in_transit", {}) as Dictionary
	var missing: Dictionary = snap.get("missing", {}) as Dictionary
	var res_lines: Array[String] = []
	var keys: Array[StringName] = []
	for k: Variant in req.keys():
		keys.append(k as StringName)
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for res_id: StringName in keys:
		var r_def: ResourceDefinition = _selected_site.get_resource_definition(res_id)
		var label: String = r_def.display_name if (r_def != null and not r_def.display_name.is_empty()) else String(res_id)
		res_lines.append("%s: Buf %d/%d | Res %d | Tr %d | Falt %d" % [
			label,
			int(buf.get(res_id, 0)),
			int(req.get(res_id, 0)),
			int(res_piles.get(res_id, 0)),
			int(transit.get(res_id, 0)),
			int(missing.get(res_id, 0)),
		])
	_site_resources_label.text = "\n".join(res_lines)

	var workers: Array = snap.get("workers", []) as Array
	if workers.is_empty():
		_site_workers_label.text = "Trabalhadores: nenhum designado (máx. constr.: %d)" % int(snap.get("max_builders", 2))
	else:
		var w_lines: Array[String] = ["Trabalhadores (%d):" % workers.size()]
		for w: Dictionary in workers:
			w_lines.append("- %s: %s" % [str(w.get("name", "?")), str(w.get("role_label", "?"))])
		_site_workers_label.text = "\n".join(w_lines)

	if _site_assign_btn != null:
		var sel_count: int = _selection_manager.get_selected_units().size() if _selection_manager != null else 0
		_site_assign_btn.disabled = (sel_count <= 0 or _command_controller == null)
		_site_assign_btn.text = "Designar selecionados (%d)" % sel_count if sel_count > 0 else "Designar selecionados"


func _consume_viewport_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
