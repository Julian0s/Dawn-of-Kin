class_name CommandController
extends Node
## Translates contextual RTS PickResult commands into individual MoveOrder instances
## for the currently selected units using GroupMovePlanner and updates DestinationMarker.

signal command_issued(pick: PickResult, anchor_position: Vector3, unit_count: int, all_reachable: bool)

@export var selection_manager_path: NodePath = NodePath()
@export var world_navigation_path: NodePath = NodePath()
@export var destination_marker_path: NodePath = NodePath()
@export var formation_clearance: float = GroupMovePlanner.DEFAULT_CLEARANCE

var _selection_manager: SelectionManager = null
var _world_navigation: WorldNavigation = null
var _destination_marker: DestinationMarker = null
var _last_plan: GroupMovePlanner.PlanResult = null


func _ready() -> void:
	_resolve_dependencies()


func configure(
	selection_manager: SelectionManager,
	world_navigation: WorldNavigation,
	destination_marker: DestinationMarker = null
) -> void:
	_selection_manager = selection_manager
	_world_navigation = world_navigation
	if destination_marker != null:
		_destination_marker = destination_marker


func set_world_navigation(world_navigation: WorldNavigation) -> void:
	_world_navigation = world_navigation


func get_last_plan() -> GroupMovePlanner.PlanResult:
	return _last_plan


func command_at(pick: PickResult) -> bool:
	_resolve_dependencies()

	if pick == null or pick.is_none() or not pick.position.is_finite():
		return false
	if _selection_manager == null or _selection_manager.is_empty():
		return false
	if _world_navigation == null or not is_instance_valid(_world_navigation):
		return false
	if not _world_navigation.is_navigation_ready():
		return false

	var units: Array[Unit] = _collect_commandable_units()
	if units.is_empty():
		return false

	var requested_target: Vector3 = pick.position
	var allow_snapped_anchor: bool = false
	var marker_normal: Vector3 = Vector3.UP

	match pick.kind:
		PickResult.Kind.GROUND:
			requested_target = pick.position
			allow_snapped_anchor = false
			marker_normal = pick.normal
		PickResult.Kind.OBSTACLE:
			requested_target = pick.position
			allow_snapped_anchor = true
			marker_normal = Vector3.UP
		PickResult.Kind.UNIT:
			# Safe provisional T1 handling when right-clicking a unit: move toward its ground position without altering selection.
			if pick.unit != null and is_instance_valid(pick.unit) and pick.unit.is_inside_tree():
				requested_target = pick.unit.global_position
			else:
				requested_target = pick.position
			allow_snapped_anchor = true
			marker_normal = Vector3.UP
		_:
			return false

	if not requested_target.is_finite():
		return false

	var unit_positions: Array[Vector3] = []
	for unit: Unit in units:
		unit_positions.append(unit.global_position)

	var snap_cb := Callable(_world_navigation, "snap_to_navmesh")
	var reach_cb := Callable(_world_navigation, "is_position_reachable")
	var plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		unit_positions,
		requested_target,
		WorldNavigation.DEFAULT_AGENT_RADIUS,
		formation_clearance,
		snap_cb,
		reach_cb,
		allow_snapped_anchor
	)
	_last_plan = plan
	if not plan.valid or plan.targets.size() != units.size():
		return false

	for idx: int in range(units.size()):
		var unit: Unit = units[idx]
		if unit.get_world_navigation() == null:
			unit.set_world_navigation(_world_navigation)
		unit.issue_order(MoveOrder.new(plan.targets[idx]))

	var marker_pos: Vector3 = plan.anchor_position if plan.all_slots_reachable else requested_target
	if _destination_marker != null and is_instance_valid(_destination_marker):
		_destination_marker.show_at(marker_pos, marker_normal, plan.all_slots_reachable)

	command_issued.emit(pick, marker_pos, units.size(), plan.all_slots_reachable)
	return true


func _collect_commandable_units() -> Array[Unit]:
	var result: Array[Unit] = []
	if _selection_manager == null:
		return result
	for unit: Unit in _selection_manager.get_selected_units():
		if unit != null and is_instance_valid(unit) and unit.is_inside_tree():
			result.append(unit)
	return result


func _resolve_dependencies() -> void:
	if _selection_manager == null and not selection_manager_path.is_empty():
		_selection_manager = get_node_or_null(selection_manager_path) as SelectionManager
	if _world_navigation == null and not world_navigation_path.is_empty():
		_world_navigation = get_node_or_null(world_navigation_path) as WorldNavigation
	if _destination_marker == null and not destination_marker_path.is_empty():
		_destination_marker = get_node_or_null(destination_marker_path) as DestinationMarker
