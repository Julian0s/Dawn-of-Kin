class_name Unit
extends CharacterBody3D
## Independent RTS unit entity composed of a CharacterBody3D, CharacterDefinition identity,
## UnitMovement component, and an active UnitOrder lifecycle.
## Does not read player input or compute navigation queries directly.

enum State {
	IDLE,
	MOVING,
}

signal state_changed(new_state: State, previous_state: State)
signal order_finished(order: UnitOrder)

@export var definition: CharacterDefinition = null:
	set(value):
		definition = value
		if is_node_ready():
			_sync_definition()

@export var world_navigation_path: NodePath = NodePath()

@onready var _movement: UnitMovement = $UnitMovement
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _explorer_visual: Node3D = $VisualRoot/ExplorerVisual
@onready var _cloak_visual: Node3D = $VisualRoot/CloakVisual
@onready var _selection_area: Area3D = $SelectionArea
@onready var _selection_indicator: SelectionIndicator = $SelectionIndicator

var _state: State = State.IDLE
var _current_order: UnitOrder = null
var _world_navigation: WorldNavigation = null
var _is_selected: bool = false
var _is_hovered: bool = false


func _ready() -> void:
	collision_layer = CollisionLayers.MASK_UNITS
	collision_mask = CollisionLayers.MASK_WORLD_SOLID

	if _selection_area != null:
		_selection_area.collision_layer = CollisionLayers.MASK_SELECTION
		_selection_area.collision_mask = 0
		_selection_area.monitoring = false
		_selection_area.monitorable = true

	if _selection_indicator != null:
		_selection_indicator.set_selected(_is_selected)
		_selection_indicator.set_hovered(_is_hovered)

	if _movement != null:
		_movement.configure(self, _agent)

	if not world_navigation_path.is_empty():
		var nav_node: WorldNavigation = get_node_or_null(world_navigation_path) as WorldNavigation
		if nav_node != null:
			set_world_navigation(nav_node)

	_sync_definition()


func _physics_process(delta: float) -> void:
	if _movement != null:
		_movement.step_movement(delta)

	if _current_order != null:
		_current_order.physics_update(_movement, delta)
		if _current_order != null and _current_order.is_finished():
			var finished_order: UnitOrder = _current_order
			_current_order = null
			_set_state(State.IDLE)
			order_finished.emit(finished_order)


func _exit_tree() -> void:
	if _current_order != null and _current_order.is_active():
		var exiting_order: UnitOrder = _current_order
		_current_order = null
		exiting_order.cancel(_movement, UnitOrder.REASON_UNIT_EXITED)
		_set_state(State.IDLE)
		order_finished.emit(exiting_order)


func apply_definition(def: CharacterDefinition) -> void:
	definition = def
	if is_node_ready():
		_sync_definition()


func _sync_definition() -> void:
	if definition == null:
		return

	if _movement != null:
		_movement.set_motion_profile(definition.move_speed, definition.turn_rate)

	_apply_visual_definition(definition)


func set_world_navigation(world_nav: WorldNavigation) -> void:
	_world_navigation = world_nav
	if _movement != null:
		_movement.set_world_navigation(world_nav)


func get_world_navigation() -> WorldNavigation:
	if _world_navigation != null:
		return _world_navigation
	if _movement != null:
		return _movement.get_world_navigation()
	return null


func get_movement() -> UnitMovement:
	return _movement


func get_navigation_agent() -> NavigationAgent3D:
	return _agent


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return "MOVING" if _state == State.MOVING else "IDLE"


func get_current_order() -> UnitOrder:
	return _current_order


func get_definition() -> CharacterDefinition:
	return definition


func get_character_id() -> StringName:
	return definition.character_id if definition != null else &""


func set_selected(selected: bool) -> void:
	_is_selected = selected
	if _selection_indicator != null:
		_selection_indicator.set_selected(selected)


func is_selected() -> bool:
	return _is_selected


func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	if _selection_indicator != null:
		_selection_indicator.set_hovered(hovered)


func is_hovered() -> bool:
	return _is_hovered


func get_selection_area() -> Area3D:
	return _selection_area


func get_selection_indicator() -> SelectionIndicator:
	return _selection_indicator


func issue_order(order: UnitOrder) -> void:
	if _current_order != null and _current_order.is_active():
		var previous_order: UnitOrder = _current_order
		_current_order = null
		previous_order.cancel(_movement, UnitOrder.REASON_REPLACED)
		order_finished.emit(previous_order)

	if order == null:
		if _movement != null:
			_movement.stop_movement()
		_set_state(State.IDLE)
		return

	if _world_navigation == null and _movement != null:
		_world_navigation = _movement.get_world_navigation()

	_current_order = order
	order.start(self, _movement, _world_navigation)

	if order.is_finished():
		var finished_order: UnitOrder = _current_order
		_current_order = null
		_set_state(State.IDLE)
		order_finished.emit(finished_order)
		return

	_set_state(State.MOVING)


func cancel_current_order(reason: String = UnitOrder.REASON_CANCELLED) -> void:
	if _current_order == null:
		if _movement != null:
			_movement.stop_movement()
		_set_state(State.IDLE)
		return

	var cancelled_order: UnitOrder = _current_order
	_current_order = null
	cancelled_order.cancel(_movement, reason)
	_set_state(State.IDLE)
	order_finished.emit(cancelled_order)


func _set_state(new_state: State) -> void:
	if new_state == _state:
		return
	var previous: State = _state
	_state = new_state
	state_changed.emit(new_state, previous)


func _apply_visual_definition(def: CharacterDefinition) -> void:
	if _explorer_visual == null or _cloak_visual == null:
		return

	var is_cloak: bool = def.silhouette_kind == CharacterDefinition.SilhouetteKind.CLOAK_SCOUT
	_explorer_visual.visible = not is_cloak
	_cloak_visual.visible = is_cloak

	var primary_mat := StandardMaterial3D.new()
	primary_mat.albedo_color = def.primary_color
	primary_mat.roughness = 0.72

	var secondary_mat := StandardMaterial3D.new()
	secondary_mat.albedo_color = def.secondary_color
	secondary_mat.roughness = 0.82

	var active_visual: Node3D = _cloak_visual if is_cloak else _explorer_visual
	_assign_materials_recursive(active_visual, primary_mat, secondary_mat)


func _assign_materials_recursive(node: Node, primary_mat: StandardMaterial3D, secondary_mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if mesh_inst.name.ends_with("_Secondary"):
			mesh_inst.material_override = secondary_mat
		else:
			mesh_inst.material_override = primary_mat

	for child: Node in node.get_children():
		_assign_materials_recursive(child, primary_mat, secondary_mat)
