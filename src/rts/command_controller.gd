class_name CommandController
extends Node
## Translates contextual RTS PickResult commands into individual MoveOrder instances
## for the currently selected units using GroupMovePlanner and updates DestinationMarker.

const REASON_UNIT_TRANSACTION_LOCKED: String = "unit_transaction_locked"

signal command_issued(pick: PickResult, anchor_position: Vector3, unit_count: int, all_reachable: bool)
signal command_rejected(pick: PickResult, reason: String)

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
var _economy_region_id: StringName = &""
var _use_provenance_economy: bool = false
var _economy_admission_reason: String = ""
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
	camp_storage_zone: CampStorageZone,
	region_id: StringName = &"",
	use_provenance: bool = false,
	admission_reason: String = ""
) -> void:
	_settlement_inventory = settlement_inventory
	_camp_storage_zone = camp_storage_zone
	_economy_region_id = region_id
	_use_provenance_economy = use_provenance
	_economy_admission_reason = admission_reason


func get_settlement_inventory() -> SettlementInventory:
	return _settlement_inventory


func get_camp_storage_zone() -> CampStorageZone:
	return _camp_storage_zone


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
		PickResult.Kind.CONSTRUCTION_SITE:
			return _command_supply_construction_site(pick, units)
		_:
			_last_command_reason = "unsupported_pick_kind"
			return false

	if not requested_target.is_finite():
		return false
	for unit: Unit in units:
		if _world_navigation.is_route_blocked_by_pending_building(unit.global_position, requested_target):
			_last_command_reason = _world_navigation.get_pending_route_reason(unit.global_position, requested_target)
			command_rejected.emit(pick, _last_command_reason)
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
	# Validate all members before issuing any order: fallback formation geometry
	# must never bypass a pending blocker or partially replace the group's orders.
	if not _world_navigation._pending_building_blockers.is_empty():
		for idx: int in range(units.size()):
			var origin: Vector3 = units[idx].global_position
			var query: WorldNavigation.PathResult = _world_navigation.find_path(origin, plan.targets[idx])
			if _world_navigation.is_route_blocked_by_pending_building(origin, plan.targets[idx]) or query.reason in ["pending_building_nav_sync", "pending_building_blocker", "navigation_rebake_degraded"]:
				_last_command_reason = query.reason
				command_rejected.emit(pick, _last_command_reason)
				return false
	var started_count: int = 0
	var first_failure_reason: String = ""
	for idx: int in range(units.size()):
		var unit: Unit = units[idx]
		if unit.get_world_navigation() == null:
			unit.set_world_navigation(_world_navigation)
		var order := MoveOrder.new(plan.targets[idx], requested_target, plan.adjusted_for_occupancy)
		unit.issue_order(order)
		if _is_order_accepted(unit, order):
			started_count += 1
		elif first_failure_reason.is_empty():
			first_failure_reason = _resolve_order_rejection_reason(unit, order)

	if started_count <= 0:
		_last_command_reason = first_failure_reason if not first_failure_reason.is_empty() else UnitOrder.REASON_UNREACHABLE
		command_rejected.emit(pick, _last_command_reason)
		return false

	var marker_pos: Vector3 = plan.anchor_position if plan.all_slots_reachable else requested_target
	if units.size() == 1 and plan.all_slots_reachable and plan.adjusted_for_occupancy:
		marker_pos = plan.targets[0]
	if _destination_marker != null and is_instance_valid(_destination_marker):
		_destination_marker.show_at(marker_pos, marker_normal, plan.all_slots_reachable)

	command_issued.emit(pick, marker_pos, started_count, plan.all_slots_reachable)
	return true


func _command_gather_resource(pick: PickResult, units: Array[Unit]) -> bool:
	if pick == null or not pick.is_resource_source() or not is_instance_valid(pick.resource_source):
		_last_command_reason = "invalid_resource_source"
		return false

	var source: ResourceSource = pick.resource_source
	if not _admit_economic_command(pick, units, source):
		return false
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

		if not source.has_worker_slot(unit):
			if first_failure_reason.is_empty():
				first_failure_reason = GatherResourceOrder.REASON_NO_WORKER_SLOT
			continue

		var order := GatherResourceOrder.new(source, _camp_storage_zone, _settlement_inventory, -1.0, -1.0, _use_provenance_economy, _economy_region_id)
		unit.issue_order(order)
		if _is_order_accepted(unit, order):
			started_count += 1
		elif first_failure_reason.is_empty():
			first_failure_reason = _resolve_order_rejection_reason(unit, order)

	if started_count <= 0:
		_last_command_reason = first_failure_reason if not first_failure_reason.is_empty() else GatherResourceOrder.REASON_NO_WORKER_SLOT
		command_rejected.emit(pick, _last_command_reason)
		return false

	var marker_pos: Vector3 = source.global_position
	if _destination_marker != null and is_instance_valid(_destination_marker):
		_destination_marker.show_at(marker_pos, Vector3.UP, true)

	command_issued.emit(pick, marker_pos, started_count, true)
	return true


func command_units_to_site(site: ConstructionSite, units: Array[Unit] = []) -> bool:
	_resolve_dependencies()
	_last_command_reason = ""
	if site == null or not is_instance_valid(site) or not site.is_valid():
		_last_command_reason = ConstructOrder.REASON_INVALID_SITE
		return false
	if _world_navigation == null or not is_instance_valid(_world_navigation):
		_last_command_reason = "missing_navigation"
		return false
	if not _world_navigation.is_navigation_ready():
		_last_command_reason = "navigation_not_ready"
		return false
	var target_units: Array[Unit] = []
	var source_units: Array[Unit] = units
	if source_units.is_empty():
		source_units = _collect_commandable_units()
	for unit: Unit in source_units:
		if unit != null and is_instance_valid(unit) and unit.is_inside_tree():
			target_units.append(unit)
	if target_units.is_empty():
		_last_command_reason = "no_commandable_units"
		return false
	var pick := PickResult.from_construction_site(site, site.global_position, Vector3.UP)
	return _command_supply_construction_site(pick, target_units)


func _command_supply_construction_site(pick: PickResult, units: Array[Unit]) -> bool:
	if pick == null or not pick.is_construction_site():
		_last_command_reason = ConstructOrder.REASON_INVALID_SITE
		return false

	var site: ConstructionSite = pick.construction_site
	if site == null or not is_instance_valid(site) or not site.is_valid():
		_last_command_reason = ConstructOrder.REASON_INVALID_SITE
		return false

	if not _admit_economic_command(pick, units, site):
		return false
	var started_count: int = 0
	var first_failure_reason: String = ""
	for unit: Unit in units:
		if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
			continue
		if unit.get_world_navigation() == null:
			unit.set_world_navigation(_world_navigation)

		var order := ConstructOrder.new(site, _camp_storage_zone, false, _use_provenance_economy, _use_provenance_economy)
		unit.issue_order(order)
		if _is_order_accepted(unit, order):
			started_count += 1
		elif first_failure_reason.is_empty():
			first_failure_reason = _resolve_order_rejection_reason(unit, order)

	if started_count <= 0:
		_last_command_reason = first_failure_reason if not first_failure_reason.is_empty() else ConstructOrder.REASON_NO_WORKER_SLOT
		command_rejected.emit(pick, _last_command_reason)
		return false

	var marker_pos: Vector3 = site.global_position if site.is_inside_tree() else pick.position
	if _destination_marker != null and is_instance_valid(_destination_marker):
		_destination_marker.show_at(marker_pos, Vector3.UP, true)

	command_issued.emit(pick, marker_pos, started_count, true)
	return true


func _admit_economic_command(pick: PickResult, units: Array[Unit], target: Node3D) -> bool:
	if not _use_provenance_economy:
		return true
	var reason := _economy_admission_reason
	if reason.is_empty():
		reason = _inspect_economic_command(units, target)
	if reason.is_empty():
		return true
	_last_command_reason = reason
	command_rejected.emit(pick, reason)
	return false


func _inspect_economic_command(units: Array[Unit], target: Node3D) -> String:
	if not target.is_inside_tree() or not is_instance_valid(_camp_storage_zone) or not _camp_storage_zone.is_inside_tree() or not _camp_storage_zone.is_valid():
		return "invalid_domain"
	var world := _camp_storage_zone.get_world_3d()
	var storage := _settlement_inventory.get_storage_source() as GroundPileManager if _settlement_inventory != null else null
	if storage == null or storage.get_camp_zone() != _camp_storage_zone or target.get_world_3d() != world:
		return "invalid_domain"
	if target is ConstructionSite:
		var site := target as ConstructionSite
		if site.region_id != _economy_region_id or site.get_inventory() != _settlement_inventory:
			return "invalid_domain"
	var domain := ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(world, _economy_region_id, _settlement_inventory, storage, &"", get_tree())
	if not domain.ok:
		return domain.reason
	for unit: Unit in units:
		if unit.get_meta(&"region_id", &"") != _economy_region_id:
			return "unit_not_admitted"
		var load := unit.get_carry_load()
		var identity := ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(world, _economy_region_id, unit, load, get_tree())
		if not identity.ok:
			return identity.reason
		if not load.validate_provenance():
			return "unreconciled_cargo"
	return ""


func _is_order_accepted(unit: Unit, order: UnitOrder) -> bool:
	if order == null:
		return false
	if order.is_succeeded():
		return true
	return unit != null and is_instance_valid(unit) and unit.get_current_order() == order and order.is_active()


func _resolve_order_rejection_reason(unit: Unit, order: UnitOrder) -> String:
	if order != null and not order.failure_reason.is_empty():
		return order.failure_reason
	if unit != null and is_instance_valid(unit) and (unit._is_reserved_withdrawal_locked() or (order != null and order.status == UnitOrder.Status.PENDING)):
		return REASON_UNIT_TRANSACTION_LOCKED
	return ""


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
