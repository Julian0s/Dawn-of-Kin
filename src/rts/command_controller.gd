class_name CommandController
extends Node
## Translates contextual RTS PickResult commands into individual MoveOrder instances
## for the currently selected units using GroupMovePlanner and updates DestinationMarker.

signal command_issued(pick: PickResult, anchor_position: Vector3, unit_count: int, all_reachable: bool)

@export var selection_manager_path: NodePath = NodePath()
@export var world_navigation_path: NodePath = NodePath()
@export var destination_marker_path: NodePath = NodePath()
@export var camp_storage_zone_path: NodePath = NodePath()
@export var formation_clearance: float = GroupMovePlanner.DEFAULT_CLEARANCE

var _selection_manager: SelectionManager = null
var _world_navigation: WorldNavigation = null
var _destination_marker: DestinationMarker = null
var _settlement_inventory: SettlementInventory = null
var _camp_storage_zone: CampStorageZone = null
var _last_plan: GroupMovePlanner.PlanResult = null
var _last_command_reason: String = ""


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


func configure_economy(
	settlement_inventory: SettlementInventory,
	camp_storage_zone: CampStorageZone
) -> void:
	_settlement_inventory = settlement_inventory
	_camp_storage_zone = camp_storage_zone


func get_last_plan() -> GroupMovePlanner.PlanResult:
	return _last_plan


func get_last_command_reason() -> String:
	return _last_command_reason


func command_at(pick: PickResult) -> bool:
	_resolve_dependencies()
	_last_command_reason = ""

	if pick == null or pick.is_none() or not pick.position.is_finite():
		_last_command_reason = "invalid_pick"
		return false
	if _selection_manager == null or _selection_manager.is_empty():
		_last_command_reason = "empty_selection"
		return false
	if _world_navigation == null or not is_instance_valid(_world_navigation):
		_last_command_reason = "missing_navigation"
		return false
	if not _world_navigation.is_navigation_ready():
		_last_command_reason = "navigation_not_ready"
		return false

	var units: Array[Unit] = _collect_commandable_units()
	if units.is_empty():
		_last_command_reason = "no_commandable_units"
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
		PickResult.Kind.RESOURCE_SOURCE:
			return _command_gather_resource(pick, units)
		_:
			_last_command_reason = "unsupported_pick_kind"
			return false

	if not requested_target.is_finite():
		return false

	var unit_positions: Array[Vector3] = []
	for unit: Unit in units:
		unit_positions.append(unit.global_position)

	var occupied_positions: Array[Vector3] = _collect_occupied_positions(units)
	var snap_cb := Callable(_world_navigation, "snap_to_navmesh")
	var reach_cb := Callable(_world_navigation, "is_position_reachable")
	var plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		unit_positions,
		requested_target,
		WorldNavigation.DEFAULT_AGENT_RADIUS,
		formation_clearance,
		snap_cb,
		reach_cb,
		allow_snapped_anchor,
		occupied_positions
	)
	_last_plan = plan
	if not plan.valid or plan.targets.size() != units.size():
		return false

	for idx: int in range(units.size()):
		var unit: Unit = units[idx]
		if unit.get_world_navigation() == null:
			unit.set_world_navigation(_world_navigation)
		unit.issue_order(MoveOrder.new(plan.targets[idx], requested_target, plan.adjusted_for_occupancy))

	var marker_pos: Vector3 = plan.anchor_position if plan.all_slots_reachable else requested_target
	if units.size() == 1 and plan.all_slots_reachable and plan.adjusted_for_occupancy:
		marker_pos = plan.targets[0]
	if _destination_marker != null and is_instance_valid(_destination_marker):
		_destination_marker.show_at(marker_pos, marker_normal, plan.all_slots_reachable)

	command_issued.emit(pick, marker_pos, units.size(), plan.all_slots_reachable)
	return true


func _command_gather_resource(pick: PickResult, units: Array[Unit]) -> bool:
	if pick == null or not pick.is_resource_source() or not is_instance_valid(pick.resource_source):
		_last_command_reason = "invalid_resource_source"
		return false

	var source: ResourceSource = pick.resource_source
	if source.is_depleted():
		_last_command_reason = "resource_source_depleted"
		return false
	if not source.is_available():
		_last_command_reason = "invalid_resource_source"
		return false

	if _settlement_inventory == null or _camp_storage_zone == null or not is_instance_valid(_camp_storage_zone) or not _camp_storage_zone.is_valid():
		_last_command_reason = GatherResourceOrder.REASON_MISSING_ECONOMY
		return false

	var started_count: int = 0
	var first_failure_reason: String = ""

	for unit: Unit in units:
		if unit.get_world_navigation() == null:
			unit.set_world_navigation(_world_navigation)

		var existing_order: UnitOrder = unit.get_current_order()
		var replacing_same_source: bool = (existing_order is GatherResourceOrder and (existing_order as GatherResourceOrder).source == source)
		if not replacing_same_source and not source.has_worker_slot(unit):
			if first_failure_reason.is_empty():
				first_failure_reason = GatherResourceOrder.REASON_NO_WORKER_SLOT
			continue

		var order := GatherResourceOrder.new(source, _camp_storage_zone, _settlement_inventory)
		unit.issue_order(order)
		if order.is_active():
			started_count += 1
		elif first_failure_reason.is_empty():
			first_failure_reason = order.failure_reason

	if started_count <= 0:
		_last_command_reason = first_failure_reason if not first_failure_reason.is_empty() else GatherResourceOrder.REASON_NO_WORKER_SLOT
		return false

	var marker_pos: Vector3 = source.global_position
	if _destination_marker != null and is_instance_valid(_destination_marker):
		_destination_marker.show_at(marker_pos, Vector3.UP, true)

	command_issued.emit(pick, marker_pos, started_count, true)
	return true


func _collect_occupied_positions(commanded_units: Array[Unit]) -> Array[Vector3]:
	var occupied: Array[Vector3] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return occupied

	for node: Node in tree.get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
		if not (node is Unit):
			continue
		var other: Unit = node as Unit
		if not is_instance_valid(other) or not other.is_inside_tree():
			continue
		if commanded_units.has(other):
			continue

		if other.get_state() != Unit.State.IDLE:
			var other_order: UnitOrder = other.get_current_order()
			if other_order is MoveOrder:
				var reserved: Vector3 = (other_order as MoveOrder).resolved_target
				if reserved.is_finite():
					occupied.append(reserved)
					continue
			elif other_order != null and other_order.has_method("get_reserved_target"):
				var reserved_work: Variant = other_order.call("get_reserved_target")
				if reserved_work is Vector3 and (reserved_work as Vector3).is_finite():
					occupied.append(reserved_work as Vector3)
					continue
		occupied.append(other.global_position)

	return occupied


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
	if _camp_storage_zone == null and not camp_storage_zone_path.is_empty():
		_camp_storage_zone = get_node_or_null(camp_storage_zone_path) as CampStorageZone
