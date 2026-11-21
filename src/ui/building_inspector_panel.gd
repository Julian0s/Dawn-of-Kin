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
var _recovery_timer: Timer
var _manager: ConstructionManager
var _d3_begin: Button
var _d3_confirm: Button
var _recovery_open: Button
var _recoveries: OptionButton
var _d3_plan: Dictionary = {}
var _operation_serial: int = 0
var _selection_revision: int = 0
var _tracking_id: StringName
var _last_cancel_id: StringName



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
	_panel.mouse_force_pass_scroll_events = false
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
	_materials.custom_minimum_size.x = 332
	_materials.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workers = _label(column, 12)
	_plan = _label(column, 12)
	_message = _label(column, 12)
	_complement = _button(column, "Complementar materiais")
	_complement.pressed.connect(_begin_confirmation)
	_confirm = _button(column, "Confirmar reserva integral")
	_confirm.pressed.connect(_confirm_complement)
	_cancel = _button(column, "Voltar")
	_cancel.pressed.connect(_cancel_confirmation)
	_d3_begin = _button(column, "Cancelar construção")
	_d3_begin.pressed.connect(_begin_d3)
	_d3_confirm = _button(column, "Confirmar cancelamento")
	_d3_confirm.pressed.connect(_confirm_d3)
	_recoveries = OptionButton.new()
	_recoveries.focus_mode = Control.FOCUS_NONE
	_recoveries.fit_to_longest_item = false
	column.add_child(_recoveries)
	_recoveries.item_selected.connect(_select_recovery)
	var close := _button(column, "Fechar")
	close.pressed.connect(func() -> void: set_site(null))
	_recovery_open = _button(self, "Recuperações")
	_recovery_open.position = Vector2(16, 116)
	_recovery_open.hide()
	_recovery_open.pressed.connect(_open_recovery)
	_recovery_timer = Timer.new()
	_recovery_timer.wait_time = 0.5
	_recovery_timer.ignore_time_scale = true
	_recovery_timer.timeout.connect(_refresh)
	add_child(_recovery_timer)
	_plan.custom_minimum_size.x = 332
	_plan.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 332
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func configure(input_controller: RtsInputController, selection: SelectionManager, d3_manager: ConstructionManager = null) -> void:
	_manager = d3_manager
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
	_selection_revision += 1
	_d3_plan.clear()
	_tracking_id = &""
	_recovery_timer.stop()
	_message.text = ""
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
	_recovery_open.visible = not _last_cancel_id.is_empty()
	if not _tracking_id.is_empty():
		_refresh_recovery()
		return
	_recoveries.hide()
	_progress.show()
	_workers.show()
	_d3_confirm.hide()
	_d3_begin.hide()
	if not is_instance_valid(_site) or not _site.is_inside_tree() or not _site.is_valid() or _site.get_site_state() == ConstructionSite.SiteState.COMPLETED:
		_panel.visible = false
		return
	_panel.visible = true
	_panel.reset_size()
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
	var can_cancel := is_instance_valid(_manager) and _manager.can_offer_site_cancellation(_site)
	if not _d3_plan.is_empty() and not can_cancel:
		_d3_plan.clear()
		_message.text = "O canteiro mudou. Abra uma nova prévia."
	if not _d3_plan.is_empty():
		_complement.hide()
		_confirm.hide()
		_d3_confirm.show()
		_d3_confirm.disabled = _busy
		_cancel.show()
		_plan.show()
		_plan.text = _format_d3_preview(_d3_plan.economics)
		_workers.hide()
		_materials.hide()
		return
	_materials.show()
	_d3_begin.visible = can_cancel and _confirm_site == null
	_d3_begin.disabled = _busy
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
	if not _busy and _d3_plan.is_empty() and is_instance_valid(_site) and _site.get_site_state() == ConstructionSite.SiteState.ACTIVE:
		_confirm_site = _site
		_refresh()


func _cancel_confirmation() -> void:
	_d3_plan.clear()
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


func _begin_d3() -> void:
	if _busy or not _d3_plan.is_empty() or _confirm_site != null or not is_instance_valid(_manager) or not _manager.can_offer_site_cancellation(_site):
		return
	_operation_serial += 1
	var operation := StringName("ui-d3:%d:%d" % [get_instance_id(), _operation_serial])
	var prepared := ReservedWithdrawalCoordinator.prepare_site_cancellation(_site, operation)
	if prepared.ok:
		_d3_plan = prepared
		_message.text = ""
	else:
		_message.text = "Prévia indisponível. Tente novamente quando o canteiro estiver disponível."
	_refresh()


func _confirm_d3() -> void:
	if _busy or _d3_plan.is_empty():
		return
	var plan := _d3_plan
	_d3_plan = {}
	var site := _site
	var selection_revision := _selection_revision
	if not is_instance_valid(_manager) or not _manager.can_offer_site_cancellation(site):
		_message.text = "O canteiro mudou. Abra uma nova prévia."
		_refresh()
		return
	_busy = true
	var result := ReservedWithdrawalCoordinator.execute_site_cancellation(site, plan.operation, plan)
	_busy = false
	if result.ok:
		_last_cancel_id = result.receipt.cancel_id
		if _selection_revision == selection_revision:
			_open_recovery()
		else:
			_refresh()
	elif _selection_revision == selection_revision:
		_message.text = "A previsão mudou ou o canteiro está ocupado. Abra uma nova prévia."
		_refresh()


func _format_d3_preview(rows: Dictionary) -> String:
	var lines: Array[String] = [
		"O cancelamento é definitivo.",
		"S: liberado nas pilhas após confirmar.",
		"T/B/K: requer transporte e descarga física.",
		"D: perdido. M: déficit sem cobertura.",
	]
	for id: StringName in rows:
		var row: Dictionary = rows[id]
		lines.append("%s  S %d  T %d  B %d  K %d  D %d  M %d" % [
			_resource_name(id), row.reservation_release, row.in_transit, row.buffer,
			row.incorporated_recovered, row.demolition_loss, row.missing])
	lines.append("T: mochila · B: canteiro · K: incorporado recuperável")
	return "\n".join(lines)


func _open_recovery() -> void:
	set_site(null)
	_tracking_id = _last_cancel_id
	_refresh()
	if not _tracking_id.is_empty():
		_recovery_timer.start()


func _select_recovery(index: int) -> void:
	_tracking_id = _recoveries.get_item_metadata(index)
	_refresh_recovery()


func _refresh_recovery() -> void:
	if not is_instance_valid(_manager) or not is_instance_valid(_manager._sites_root) or not _manager._sites_root.is_inside_tree():
		set_site(null)
		return
	var world := _manager._sites_root.get_world_3d()
	var region := _manager._region_id
	var result := ReservedWithdrawalCoordinator.get_cancellation_custody_readonly(world, region, _tracking_id)
	if not result.ok:
		set_site(null)
		return
	var ids := ReservedWithdrawalCoordinator.get_open_cancellation_ids_readonly(world, region)
	for id: StringName in [_tracking_id, _last_cancel_id]:
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	var displayed: Array[StringName] = []
	for i: int in range(_recoveries.item_count):
		displayed.append(_recoveries.get_item_metadata(i))
	if displayed != ids and not _recoveries.get_popup().visible:
		_recoveries.clear()
		for id: StringName in ids:
			_recoveries.add_item(String(id).trim_prefix("cancel:"))
			_recoveries.set_item_metadata(_recoveries.item_count - 1, id)
		_recoveries.select(ids.find(_tracking_id))
	_recoveries.visible = ids.size() > 1
	_panel.show()
	_panel.reset_size()
	_title.text = "Recuperação • %s" % result.snapshot.site_id
	_state.text = _recovery_state_text(result.snapshot.state)
	_progress.hide()
	_workers.hide()
	_complement.hide()
	_confirm.hide()
	_cancel.hide()
	_plan.hide()
	_d3_begin.hide()
	_d3_confirm.hide()
	_materials.show()
	var snap: Dictionary = result.snapshot
	var lines: Array[String] = ["Material: no local (A) | em trânsito (H) | devolvido (E) | perdido (D)"]
	for id: StringName in snap.required_amounts:
		lines.append("%s: %d | %d | %d | %d" % [
			_resource_name(id), int(snap.local_buffer_remaining.get(id, 0)) + int(snap.local_incorporated_remaining.get(id, 0)),
			snap.in_transit_remaining.get(id, 0), snap.delivered_to_camp.get(id, 0), snap.demolition_loss.get(id, 0)])
	_materials.text = "\n".join(lines)
	_message.text = _recovery_diagnostic(snap.diagnostic_reason) if snap.state == ConstructionCancellationMath.State.RETURN_BLOCKED else ""


func _resource_name(id: StringName) -> String:
	match id:
		&"wood": return "Madeira"
		&"stone": return "Pedra"
		&"food": return "Alimentos"
	var definition := _manager._resource_defs.get(id) as ResourceDefinition
	return definition.display_name if definition != null else String(id)


func _recovery_state_text(state: int) -> String:
	match state:
		ConstructionCancellationMath.State.SETTLED: return "Recuperação concluída"
		ConstructionCancellationMath.State.RETURNING: return "Trabalhadores devolvendo materiais"
		ConstructionCancellationMath.State.RETURN_BLOCKED: return "Recuperação bloqueada"
		_: return "Recuperação pendente"


func _recovery_diagnostic(reason: String) -> String:
	match reason:
		"manual_override": return "O trabalhador recebeu uma ordem manual."
		"navigation_not_ready": return "A navegação ainda está sendo preparada."
		"recovery_unreachable_or_slot_occupied", "unreachable", "stuck": return "O ponto de retirada está inacessível ou ocupado."
		"no_valid_camp_slot", "camp_unreachable", "out_of_camp_dropoff_range": return "O acampamento está sem espaço ou acesso para a entrega."
		"capacity_exhausted": return "A mochila está cheia."
		"": return "Os materiais continuam aguardando recuperação."
		_: return "O retorno foi interrompido (%s)." % reason


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
