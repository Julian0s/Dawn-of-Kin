class_name TreeWorkMenu
extends PanelContainer

@onready var main := get_parent().get_parent() as MainScene
const RING := preload("res://src/units/selection_indicator.tscn")
var highlights: Array[SelectionIndicator] = []
var workers: Array[Unit] = []
var tree_source: ResourceSource
var anchor: Node3D
var choosing_target := false
var title := Label.new()
var options := VBoxContainer.new()
var action := Button.new()
var message := Label.new()


func _ready() -> void:
	add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())
	var column := VBoxContainer.new()
	add_child(column)
	column.add_child(title)
	column.add_child(options)
	action.text = "Cortar madeira"
	column.add_child(action)
	column.add_child(message)
	action.pressed.connect(_confirm)
	main.get_node("PlacementController").placement_started.connect(func(_d: BuildingDefinition) -> void: close_menu())
	close_menu()


func close_menu() -> void:
	hide()
	set_process(false)
	choosing_target = false
	tree_source = null
	anchor = null
	workers.clear()
	_clear_highlights()
	for child in options.get_children():
		options.remove_child(child)
		child.queue_free()


func _clear_highlights() -> void:
	for ring in highlights:
		if is_instance_valid(ring):
			ring.hide()
			ring.queue_free()
	highlights.clear()


func _highlight(source: ResourceSource) -> void:
	var ring := RING.instantiate() as SelectionIndicator
	source.add_child(ring)
	ring.scale = Vector3.ONE * 1.7
	ring.set_selected(true)
	highlights.append(ring)


func _show_at(target: Node3D) -> void:
	anchor = target
	message.text = ""
	action.disabled = false
	action.show()
	show()
	set_process(true)
	reset_size()
	_process(0.0)


func _process(_delta: float) -> void:
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		close_menu()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or not camera.is_position_in_frustum(anchor.global_position):
		close_menu()
		return
	var screen := camera.unproject_position(anchor.global_position + Vector3.UP)
	var bounds := get_viewport_rect().size
	var desired := screen + Vector2(30, 8)
	if desired.x + size.x > bounds.x:
		desired.x = screen.x - size.x - 30
	position = desired.clamp(Vector2.ZERO, (bounds - size).max(Vector2.ZERO))
	if is_instance_valid(tree_source):
		title.text = "Árvore · %d madeiras" % tree_source.get_remaining_amount()


func choose_people(units: Array[Unit]) -> void:
	close_menu()
	if units.is_empty():
		return
	workers.assign(units)
	title.text = units[0].get_definition().display_name if units.size() == 1 else "%d habitantes" % units.size()
	_show_at(units[0])


func choose_tree(source: ResourceSource) -> void:
	if choosing_target:
		tree_source = source
		anchor = source
		_dispatch()
		return
	close_menu()
	tree_source = source
	_show_at(source)
	_highlight(source)
	var candidates := main.get_units()
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.global_position.distance_squared_to(source.global_position) < b.global_position.distance_squared_to(source.global_position))
	for unit: Unit in candidates:
		var option := CheckBox.new()
		option.text = unit.get_definition().display_name
		options.add_child(option)
		var reason := _worker_problem(unit)
		option.disabled = not reason.is_empty()
		if option.disabled:
			option.text += " · " + reason
		elif workers.is_empty():
			option.button_pressed = true
			workers.append(unit)
		option.toggled.connect(_toggle_worker.bind(unit))
	if source.is_depleted() or workers.is_empty():
		action.disabled = true
		if source.is_depleted():
			message.text = "Árvore esgotada."
		elif source.get_active_worker_count() >= source.max_simultaneous_workers:
			message.text = "Todas as vagas desta árvore estão ocupadas."
		else:
			message.text = "Nenhum habitante disponível."


func _worker_problem(unit: Unit) -> String:
	if not is_instance_valid(unit) or not unit.is_inside_tree():
		return "indisponível"
	if unit.get_current_order() != null and unit.get_current_order().is_active():
		return "ocupado"
	if not unit.get_carry_load().is_empty():
		return "com carga"
	if not tree_source.has_worker_slot(unit):
		return "sem vaga"
	var slot := GatherSlotPlanner.compute_source_approach_slot(unit.global_position, tree_source,
			unit.get_world_navigation(), GatherSlotPlanner.collect_other_unit_positions(unit, true))
	return "" if slot.valid else "sem acesso"


func _toggle_worker(enabled: bool, unit: Unit) -> void:
	if enabled:
		workers.append(unit)
	else:
		workers.erase(unit)
	action.disabled = workers.is_empty()


func _confirm() -> void:
	if is_instance_valid(tree_source):
		_dispatch()
	else:
		choosing_target = true
		for source in main.get_test_map().get_resource_sources():
			if source.get_resource_id() == &"wood" and source.is_available() and not source.is_depleted():
				_highlight(source)
		action.hide()
		message.text = "Clique na árvore. Esc para voltar."


func _dispatch() -> void:
	action.show()
	_clear_highlights()
	if is_instance_valid(tree_source):
		_highlight(tree_source)
	choosing_target = false
	if not is_instance_valid(tree_source) or tree_source.is_depleted():
		message.text = "Árvore esgotada."
		action.disabled = true
		return
	for unit in workers:
		var issue := _worker_problem(unit)
		if not issue.is_empty():
			message.text = "Equipe indisponível · " + issue
			action.show()
			return
	if workers.is_empty() or workers.size() > tree_source.max_simultaneous_workers - tree_source.get_active_worker_count():
		message.text = "Confira as vagas disponíveis na árvore."
		return
	var pick := PickResult.from_resource_source(tree_source, tree_source.global_position, Vector3.UP)
	main.get_selection_manager().set_selection(workers)
	if main.get_command_controller().command_at(pick):
		var assigned := 0
		for unit in workers:
			var order := unit.get_current_order() as GatherResourceOrder
			if order != null and order.source == tree_source and order.is_active():
				assigned += 1
		if assigned == workers.size():
			close_menu()
		else:
			action.disabled = true
			message.text = "%d de %d iniciaram o corte." % [assigned, workers.size()]
	else:
		action.show()
		message.text = "Coleta recusada · " + main.get_command_controller().get_last_command_reason()
