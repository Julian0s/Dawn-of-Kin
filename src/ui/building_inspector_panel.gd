class_name BuildingInspectorPanel
extends Control
## Contextual view of ConstructionSite; reservations remain owned by the economy.

var _site: ConstructionSite
var _inventory: SettlementInventory
var _input_controller: RtsInputController
var _selection: SelectionManager
var _panel: PanelContainer
var _title: Label
var _state: Label
var _progress: ProgressBar
var _materials: Label
var _workers: Label
var _plan: Label
var _message: Label
var _complement: Button
var _confirm: Button
var _cancel: Button
var _confirm_site: ConstructionSite
var _busy: bool = false
var _refresh_timer: Timer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = true
	_refresh_timer.wait_time = 0.2
	_refresh_timer.ignore_time_scale = true
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)
	_panel = PanelContainer.new()
	_panel.name = "Inspector"
	_panel.position = Vector2(16, 150)
	_panel.custom_minimum_size = Vector2(350, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())
	_panel.visible = false
	add_child(_panel)
	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 5)
	margin.add_child(column)
	_title = _label(column, 15)
	_state = _label(column, 13)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.show_percentage = true
	_progress.custom_minimum_size.y = 20
	column.add_child(_progress)
	_materials = _label(column, 12)
	_workers = _label(column, 12)
	_plan = _label(column, 12)
	_message = _label(column, 12)
	_complement = _button(column, "Complementar materiais")
	_complement.pressed.connect(_begin_confirmation)
	_confirm = _button(column, "Confirmar reserva integral")
	_confirm.pressed.connect(_confirm_complement)
	_cancel = _button(column, "Voltar")
	_cancel.pressed.connect(_cancel_confirmation)
	var close := _button(column, "Fechar")
	close.pressed.connect(func() -> void: set_site(null))


func configure(input_controller: RtsInputController, selection: SelectionManager) -> void:
	_input_controller = input_controller
	_selection = selection
	if is_instance_valid(_input_controller):
		_input_controller.construction_site_picked.connect(set_site)
	if is_instance_valid(_selection):
		_selection.selection_changed.connect(_selection_changed)


func _exit_tree() -> void:
	set_site(null)
	if is_instance_valid(_input_controller) and _input_controller.construction_site_picked.is_connected(set_site):
		_input_controller.construction_site_picked.disconnect(set_site)
	if is_instance_valid(_selection) and _selection.selection_changed.is_connected(_selection_changed):
		_selection.selection_changed.disconnect(_selection_changed)


func set_site(site: ConstructionSite) -> void:
	_disconnect_site()
	_site = site if is_instance_valid(site) and site.is_inside_tree() and site.is_valid() else null
	_confirm_site = null
	if _site != null:
		_inventory = _site.get_inventory()
		_site.state_changed.connect(_site_changed)
		_site.buffer_changed.connect(_site_changed)
		_site.workers_changed.connect(_site_changed)
		_site.tree_exiting.connect(_site_exiting)
		if _inventory != null:
			_inventory.inventory_changed.connect(_inventory_changed)
			_inventory.reservations_changed.connect(_inventory_changed)
	_refresh()


func _disconnect_site() -> void:
	if is_instance_valid(_site):
		if _site.state_changed.is_connected(_site_changed): _site.state_changed.disconnect(_site_changed)
		if _site.buffer_changed.is_connected(_site_changed): _site.buffer_changed.disconnect(_site_changed)
		if _site.workers_changed.is_connected(_site_changed): _site.workers_changed.disconnect(_site_changed)
		if _site.tree_exiting.is_connected(_site_exiting): _site.tree_exiting.disconnect(_site_exiting)
	if _inventory != null:
		if _inventory.inventory_changed.is_connected(_inventory_changed): _inventory.inventory_changed.disconnect(_inventory_changed)
		if _inventory.reservations_changed.is_connected(_inventory_changed): _inventory.reservations_changed.disconnect(_inventory_changed)
	_inventory = null


func _selection_changed(units: Array[Unit]) -> void:
	if not units.is_empty(): set_site(null)


func _site_exiting() -> void:
	set_site(null)


func _site_changed(_changed: ConstructionSite) -> void:
	_queue_refresh()


func _inventory_changed() -> void:
	_queue_refresh()


func _queue_refresh() -> void:
	if _refresh_timer != null and _refresh_timer.is_stopped():
		_refresh_timer.start()


func _refresh() -> void:
	if _panel == null: return
	if not is_instance_valid(_site) or not _site.is_inside_tree() or not _site.is_valid() or _site.get_site_state() == ConstructionSite.SiteState.COMPLETED:
		_panel.visible = false
		return
	_panel.visible = true
	var snap: Dictionary = _site.get_status_snapshot()
	_title.text = "%s — %s" % [str(snap.display_name), String(_site.site_id)]
	_state.text = _state_text()
	_progress.value = clampf(_site.get_progress_ratio() * 100.0, 0.0, 100.0)
	var lines: Array[String] = ["Material: necessário | incorporado | buffer | reserva | transporte | déficit"]
	for key: Variant in (snap.required as Dictionary).keys():
		var id := StringName(key)
		var def: ResourceDefinition = _site.get_resource_definition(id)
		var label := def.display_name if def != null else String(id)
		lines.append("%s: %d | %d | %d | %d | %d | %d" % [label, int(snap.required.get(id, 0)), int(snap.consumed.get(id, 0)), int(snap.delivered_buffer.get(id, 0)), int(snap.reserved_in_piles.get(id, 0)), int(snap.in_transit.get(id, 0)), int(snap.missing.get(id, 0))])
	_materials.text = "\n".join(lines)
	var worker_lines: Array[String] = ["Trabalhadores (máx. construtores: %d)" % int(snap.max_builders)]
	for worker: Dictionary in snap.workers:
		worker_lines.append("%s: %s" % [str(worker.name), str(worker.role_label)])
	if (snap.workers as Array).is_empty(): worker_lines.append("Nenhum designado")
	_workers.text = "\n".join(worker_lines)
	var missing: Dictionary = _site.get_complementable_missing_amounts()
	var active: bool = _site.get_site_state() == ConstructionSite.SiteState.ACTIVE
	_complement.visible = active and not missing.is_empty() and _confirm_site == null
	_confirm.visible = _confirm_site == _site
	_cancel.visible = _confirm.visible
	_plan.visible = _confirm.visible
	if _confirm.visible:
		var plan: Dictionary = _site.can_authorize_manual_complement({}, false)
		var detail: Array[String] = []
		for key: Variant in missing.keys():
			var id := StringName(key)
			var amount := int(missing[id])
			var available := _inventory.get_available_amount(id)
			var resource_def: ResourceDefinition = _site.get_resource_definition(id)
			var name_text: String = resource_def.display_name if resource_def != null else String(id)
			detail.append("%s: faltam %d, livres %d, proposta %d, restam %d" % [name_text, amount, available, amount if bool(plan.ok) else 0, 0 if bool(plan.ok) else amount])
		_plan.text = "\n".join(detail)
		_confirm.disabled = not bool(plan.ok) or _busy
		_message.text = "" if bool(plan.ok) else "Estoque livre insuficiente para completar integralmente."


func _state_text() -> String:
	match _site.get_site_state():
		ConstructionSite.SiteState.COMPLETING: return "Conclusão em processamento"
		ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE: return "Falha na conclusão; aguardando retentativa"
		ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR: return "Conclusão bloqueada por erro"
	match _site.get_assembly_substate():
		ConstructionSite.AssemblySubstate.ASSEMBLING: return "Montagem em andamento"
		ConstructionSite.AssemblySubstate.PAUSED_STARVED: return "Pausado por falta de materiais"
		ConstructionSite.AssemblySubstate.PAUSED_NO_WORKERS: return "Pausado por ausência de construtores"
		_: return "Aguardando materiais ou trabalhadores"


func _begin_confirmation() -> void:
	if not _busy and is_instance_valid(_site) and _site.get_site_state() == ConstructionSite.SiteState.ACTIVE:
		_confirm_site = _site
		_refresh()


func _cancel_confirmation() -> void:
	_confirm_site = null
	_message.text = ""
	_refresh()


func _confirm_complement() -> void:
	if _busy or not is_instance_valid(_site) or _site != _confirm_site or _site.is_queued_for_deletion() or not _site.is_inside_tree() or not _site.is_valid(): return
	var target: ConstructionSite = _site
	var missing: Dictionary = target.get_complementable_missing_amounts()
	if missing.is_empty() or not bool(target.can_authorize_manual_complement(missing, false).ok):
		_message.text = "Estoque livre insuficiente ou déficit já resolvido."
		_refresh()
		return
	_busy = true
	_confirm_site = null
	var intent: ManualComplementIntent = ManualComplementIntent.create_from_player_ui(self, target)
	var result: Dictionary = target.authorize_manual_complement(intent, missing, false)
	_busy = false
	if _site == target:
		_message.text = "Materiais reservados; transporte físico necessário." if bool(result.ok) else "Não foi possível reservar os materiais."
		_refresh()


func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", HudStyle.TEXT_PRIMARY_COLOR)
	parent.add_child(label)
	return label


func _button(parent: Node, caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button
