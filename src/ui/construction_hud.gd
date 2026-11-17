class_name ConstructionHud
extends Control

var _controller: PlacementController
var _catalog: PanelContainer
var _toggle: Button
var _entries: VBoxContainer


func _input(event: InputEvent) -> void:
	if _catalog != null and _catalog.visible and event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			_catalog.visible = false
			get_viewport().set_input_as_handled()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle = Button.new()
	_toggle.name = "BuildButton"
	_toggle.text = "Construir"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toggle.offset_left = -156.0
	_toggle.offset_top = -60.0
	_toggle.offset_right = -16.0
	_toggle.offset_bottom = -16.0
	_toggle.pressed.connect(_toggle_catalog)
	add_child(_toggle)
	_catalog = PanelContainer.new()
	_catalog.name = "Catalog"
	_catalog.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_catalog.offset_left = -286.0
	_catalog.offset_top = -242.0
	_catalog.offset_right = -16.0
	_catalog.offset_bottom = -68.0
	_catalog.mouse_filter = Control.MOUSE_FILTER_STOP
	_catalog.add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())
	_catalog.visible = false
	add_child(_catalog)
	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	_catalog.add_child(margin)
	_entries = VBoxContainer.new()
	_entries.add_theme_constant_override(&"separation", 8)
	margin.add_child(_entries)


func configure(controller: PlacementController, definitions: Array[BuildingDefinition]) -> void:
	if is_instance_valid(_controller) and _controller.placement_started.is_connected(_on_placement_started):
		_controller.placement_started.disconnect(_on_placement_started)
	_controller = controller
	if is_instance_valid(_controller):
		_controller.placement_started.connect(_on_placement_started)
	for child: Node in _entries.get_children():
		child.queue_free()
	for def: BuildingDefinition in definitions:
		if def == null or not def.is_valid():
			continue
		var entry := Button.new()
		entry.name = String(def.definition_id)
		entry.focus_mode = Control.FOCUS_NONE
		entry.text = "%s\nMadeira: %d   Pedra: %d" % [def.display_name, int(def.costs.get(&"wood", 0)), int(def.costs.get(&"stone", 0))]
		entry.custom_minimum_size.y = 62.0
		entry.pressed.connect(_select_definition.bind(def))
		_entries.add_child(entry)


func _toggle_catalog() -> void:
	_catalog.visible = not _catalog.visible


func _select_definition(definition: BuildingDefinition) -> void:
	_catalog.visible = false
	if is_instance_valid(_controller):
		_controller.start_placement(definition)


func _on_placement_started(_definition: BuildingDefinition) -> void:
	_catalog.visible = false
