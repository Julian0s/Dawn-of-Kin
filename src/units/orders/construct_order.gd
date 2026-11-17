class_name ConstructOrder
extends UnitOrder
## Order assigning a worker to supply and assemble a ConstructionSite (T3.3/T3.4.3).
## Implements physical targeted pile withdrawal, bounded carrying, perimeter drop-off,
## real perimeter builder slot occupancy, reactive non-polling assembly (BUILDER_ASSEMBLING /
## WAITING_FOR_MATERIALS), D9/DEC-18 worker role promotions, dynamic nav replanning, and safe cargo handling.
## Does not trigger completed-building transmutation (T3.4.4).

enum Phase {
	RETURNING_UNNEEDED_CARGO,
	MOVING_TO_PILE,
	MOVING_TO_SITE_DROPOFF,
	MOVING_TO_BUILDER_SLOT,
	BUILDER_STANDBY,
	BUILDER_ASSEMBLING,
	WAITING_FOR_MATERIALS,
	WAITING_FOR_PEER_SUPPLY,
}

const REASON_INVALID_SITE: String = "invalid_site"
const REASON_SITE_SUPPLIED: String = "site_supplied"
const REASON_NO_WORKER_SLOT: String = "no_worker_slot"
const REASON_SITE_UNREACHABLE: String = "site_unreachable"
const REASON_PILE_UNREACHABLE: String = "pile_unreachable"
const REASON_MISSING_ECONOMY: String = "missing_economy"
const REASON_RESERVATION_UNAVAILABLE: String = "reservation_unavailable"
const REASON_UNNEEDED_CARGO_REJECTED: String = "unneeded_cargo_rejected"
const MAX_APPROACH_RETRIES: int = 2

var site: ConstructionSite = null
var camp_zone: CampStorageZone = null
var force_transporter: bool = false
var resolved_target: Vector3 = Vector3(INF, INF, INF)
var trips_completed: int = 0
var units_delivered_total: int = 0

var _unit: Unit = null
var _movement: UnitMovement = null
var _world_nav: WorldNavigation = null
var _phase: Phase = Phase.MOVING_TO_PILE
var _last_nav_revision: int = -1
var _approach_retries: int = 0
var _replan_requested: bool = false
var _site_signals_bound: bool = false
var _last_known_role: ConstructionSite.WorkerRole = ConstructionSite.WorkerRole.UNASSIGNED

var _target_pile_id: int = 0
var _target_pile: GroundResourcePile = null
var _target_resource_id: StringName = &""
var _target_resource_def: ResourceDefinition = null
var _target_pile_pos: Vector3 = Vector3.ZERO
var _planned_pickup_amount: int = 0
var _deliver_suborder: DeliverToCampOrder = null


func _init(
	p_site: ConstructionSite = null,
	p_camp_zone: CampStorageZone = null,
	p_force_transporter: bool = false
) -> void:
	site = p_site
	camp_zone = p_camp_zone
	force_transporter = p_force_transporter


func get_order_name() -> String:
	return "ConstructOrder"


func get_phase() -> Phase:
	return _phase


func is_preparing_work() -> bool:
	return (
		_phase == Phase.BUILDER_STANDBY
		or _phase == Phase.BUILDER_ASSEMBLING
		or _phase == Phase.WAITING_FOR_MATERIALS
		or _phase == Phase.WAITING_FOR_PEER_SUPPLY
	)


func get_reserved_target() -> Vector3:
	if is_active():
		return resolved_target
	return Vector3(INF, INF, INF)


func get_worker_role() -> ConstructionSite.WorkerRole:
	if not _is_site_valid() or _unit == null or not is_instance_valid(_unit):
		return ConstructionSite.WorkerRole.UNASSIGNED
	return site.get_worker_role(_unit)


func get_target_pile_id() -> int:
	return _target_pile_id


func start(unit_body: CharacterBody3D, movement: UnitMovement, world_nav: WorldNavigation) -> void:
	if is_finished():
		return
	if not (unit_body is Unit) or not unit_body.is_inside_tree():
		mark_failed(REASON_UNIT_NOT_IN_TREE)
		return
	if movement == null:
		mark_failed(REASON_MISSING_MOVEMENT)
		return

	_unit = unit_body as Unit
	_movement = movement
	var nav: WorldNavigation = world_nav if world_nav != null else movement.get_world_navigation()
	if nav == null:
		mark_failed(REASON_MISSING_NAVIGATION)
		return
	if not nav.is_navigation_ready():
		mark_failed(REASON_NAVIGATION_NOT_READY)
		return
	_world_nav = nav
	_last_nav_revision = _world_nav.get_navigation_revision()

	if not _is_site_valid():
		mark_failed(REASON_INVALID_SITE)
		return
	if site.get_inventory() == null:
		mark_failed(REASON_MISSING_ECONOMY)
		return
	if _unit.get_carry_load() == null:
		mark_failed(REASON_MISSING_ECONOMY)
		return

	mark_running()
	var assigned_role: ConstructionSite.WorkerRole = site.register_worker(_unit, self, force_transporter)
	if assigned_role == ConstructionSite.WorkerRole.UNASSIGNED:
		_finish_failed(REASON_NO_WORKER_SLOT)
		return
	_last_known_role = assigned_role

	_bind_site_signals()
	_advance_by_role(_movement)


func physics_update(movement: UnitMovement, delta: float) -> void:
	if status != Status.RUNNING:
		return
	if _unit == null or not is_instance_valid(_unit) or not _unit.is_inside_tree():
		_finish_failed(REASON_UNIT_NOT_IN_TREE)
		return
	if movement == null:
		_finish_failed(REASON_MISSING_MOVEMENT)
		return
	_movement = movement

	if site != null and is_instance_valid(site) and site.is_completed_or_completing():
		movement.stop_movement()
		_finish_succeeded()
		return
	if not _is_site_valid():
		_finish_failed(REASON_INVALID_SITE)
		return
	if _world_nav == null:
		_finish_failed(REASON_MISSING_NAVIGATION)
		return

	if not _world_nav.is_navigation_ready():
		# Wait briefly if a dynamic rebake is syncing rather than failing immediately.
		return

	var current_rev: int = _world_nav.get_navigation_revision()
	if current_rev != _last_nav_revision or _replan_requested:
		_last_nav_revision = current_rev
		_replan_requested = false
		_advance_by_role(movement)
		if is_finished():
			return

	match _phase:
		Phase.RETURNING_UNNEEDED_CARGO:
			_update_returning_unneeded_cargo(movement, delta)
		Phase.MOVING_TO_PILE:
			_update_moving_to_pile(movement)
		Phase.MOVING_TO_SITE_DROPOFF:
			_update_moving_to_site_dropoff(movement)
		Phase.MOVING_TO_BUILDER_SLOT:
			_update_moving_to_builder_slot(movement)
		Phase.BUILDER_STANDBY:
			_update_builder_standby(movement)
		Phase.BUILDER_ASSEMBLING:
			_update_builder_assembling(movement, delta)
		Phase.WAITING_FOR_MATERIALS:
			_update_waiting_for_materials(movement)
		Phase.WAITING_FOR_PEER_SUPPLY:
			_update_waiting_for_peer_supply(movement)


func cancel(movement: UnitMovement, reason: String = REASON_CANCELLED) -> void:
	if _deliver_suborder != null and _deliver_suborder.is_active():
		_deliver_suborder.cancel(movement, reason)
	_deliver_suborder = null
	_clear_pickup_target()
	resolved_target = Vector3(INF, INF, INF)
	_unbind_site_signals()
	if site != null and is_instance_valid(site) and _unit != null and is_instance_valid(_unit):
		site.release_pickup_claim(_unit)
		site.unregister_worker(_unit, self)
	if movement != null:
		movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	super.cancel(movement, reason)


func _advance_by_role(movement: UnitMovement) -> void:
	if site != null and is_instance_valid(site) and site.is_completed_or_completing():
		if movement != null:
			movement.stop_movement()
			movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
		_finish_succeeded()
		return
	if not _is_site_valid():
		_finish_failed(REASON_INVALID_SITE)
		return

	var role: ConstructionSite.WorkerRole = site.get_worker_role(_unit)
	_last_known_role = role
	if role == ConstructionSite.WorkerRole.UNASSIGNED:
		_finish_failed(REASON_NO_WORKER_SLOT)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	var site_claim: Dictionary = site.get_transit_claim_for_unit(_unit)
	var has_usable_site_cargo: bool = _has_any_deliverable_claim(site_claim, carry_load)

	if role == ConstructionSite.WorkerRole.BUILDER:
		_clear_pickup_target()
		site.release_pickup_claim(_unit)
		if has_usable_site_cargo:
			_start_moving_to_site_dropoff(movement)
			return
		_start_moving_to_builder_slot(movement)
		return

	# Transporter or Solo Supplier role:
	if site.is_fully_supplied():
		_clear_pickup_target()
		site.release_pickup_claim(_unit)
		if not force_transporter:
			var post_supply_role: ConstructionSite.WorkerRole = site.rebalance_for_assembly_on_supply_complete(_unit)
			_last_known_role = post_supply_role
			if post_supply_role == ConstructionSite.WorkerRole.BUILDER:
				_start_moving_to_builder_slot(movement)
				return
		if movement != null:
			movement.stop_movement()
			movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
		_finish_succeeded()
		return

	if has_usable_site_cargo:
		_clear_pickup_target()
		site.release_pickup_claim(_unit)
		_start_moving_to_site_dropoff(movement)
		return

	var unneeded: Dictionary = site.get_unneeded_cargo_for_unit(_unit, carry_load)
	if not unneeded.is_empty():
		_clear_pickup_target()
		site.release_pickup_claim(_unit)
		_start_returning_unneeded_cargo(movement)
		return

	_select_and_approach_next_pile(movement)


func _has_any_deliverable_claim(site_claim: Dictionary, carry_load: UnitCarryLoad) -> bool:
	if site_claim.is_empty() or carry_load == null:
		return false
	for res_key: Variant in site_claim.keys():
		var res_id: StringName = res_key as StringName
		if int(site_claim[res_id]) > 0 and carry_load.get_amount(res_id) > 0 and site.get_remaining_need_for_dropoff(res_id) > 0:
			return true
	return false


func _start_returning_unneeded_cargo(movement: UnitMovement) -> void:
	var inventory: SettlementInventory = site.get_inventory()
	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid() or inventory == null:
		_finish_failed(REASON_UNNEEDED_CARGO_REJECTED)
		return
	_phase = Phase.RETURNING_UNNEEDED_CARGO
	_deliver_suborder = DeliverToCampOrder.new(camp_zone, inventory)
	_deliver_suborder.start(_unit, movement, _world_nav)
	if _deliver_suborder.is_finished():
		if _deliver_suborder.is_succeeded():
			_deliver_suborder = null
			_advance_by_role(movement)
		else:
			var sub_reason: String = _deliver_suborder.failure_reason
			_deliver_suborder = null
			_finish_failed(sub_reason if not sub_reason.is_empty() else REASON_UNNEEDED_CARGO_REJECTED)
		return
	resolved_target = _deliver_suborder.get_reserved_target()


func _update_returning_unneeded_cargo(movement: UnitMovement, delta: float) -> void:
	if _deliver_suborder == null:
		_advance_by_role(movement)
		return
	_deliver_suborder.physics_update(movement, delta)
	resolved_target = _deliver_suborder.get_reserved_target()
	if not _deliver_suborder.is_finished():
		return
	if _deliver_suborder.is_succeeded():
		_deliver_suborder = null
		_advance_by_role(movement)
		return
	var reason: String = _deliver_suborder.failure_reason
	_deliver_suborder = null
	_finish_failed(reason if not reason.is_empty() else REASON_UNNEEDED_CARGO_REJECTED)


func _select_and_approach_next_pile(movement: UnitMovement) -> void:
	_clear_pickup_target()
	site.release_pickup_claim(_unit)

	var occupied: Array[Vector3] = BuildSlotPlanner.collect_other_unit_positions(_unit, true)
	var candidate: Dictionary = BuildSlotPlanner.find_best_pickup_candidate(
		_unit,
		_unit.global_position,
		site,
		_world_nav,
		occupied
	)

	if not bool(candidate.get("found", false)):
		var fail_reason: String = str(candidate.get("reason", "no_reserved_piles"))
		if fail_reason == "pile_unreachable":
			_finish_failed(REASON_PILE_UNREACHABLE)
			return
		# DEC-18: SOLO_SUPPLIER transitions to BUILDER only once no more deliveries are possible
		# and consumable materials already exist in the site buffer.
		if (
			not force_transporter
			and site.get_worker_role(_unit) == ConstructionSite.WorkerRole.SOLO_SUPPLIER
			and site.has_consumable_work_available()
			and site.try_promote_solo_to_builder(_unit)
		):
			_last_known_role = ConstructionSite.WorkerRole.BUILDER
			_start_moving_to_builder_slot(movement)
			return
		# Distinguish an active peer transporter currently supplying this site from orphaned/interrupted claims.
		if site.has_active_peer_transport_for_site(_unit):
			_start_waiting_for_peer_supply(movement)
		else:
			_finish_failed(REASON_RESERVATION_UNAVAILABLE)
		return

	var pile_id: int = int(candidate["pile_id"])
	var res_id: StringName = candidate["resource_id"] as StringName
	var desired: int = int(candidate["available_claim"])
	var reserved_on_pile: int = int(candidate["reserved_on_pile"])

	var claimed: int = site.claim_pickup(_unit, pile_id, res_id, desired, reserved_on_pile)
	if claimed <= 0:
		_finish_failed(REASON_RESERVATION_UNAVAILABLE)
		return

	_target_pile_id = pile_id
	_target_pile = candidate["pile"] as GroundResourcePile
	_target_resource_id = res_id
	_target_resource_def = candidate["resource_def"] as ResourceDefinition
	_target_pile_pos = candidate["pile_pos"] as Vector3
	_planned_pickup_amount = claimed
	_approach_retries = 0

	var slot_pos: Vector3 = candidate["slot_pos"] as Vector3
	_phase = Phase.MOVING_TO_PILE
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)

	if BuildSlotPlanner.is_unit_in_pile_reach(
		_unit.global_position,
		_target_pile_pos,
		ConstructionSite.DEFAULT_PILE_PICKUP_REACH,
		_get_world_3d()
	):
		movement.stop_movement()
		_execute_pile_withdrawal(movement)
		return

	resolved_target = slot_pos
	if not movement.begin_move_to(resolved_target):
		site.release_pickup_claim(_unit)
		_clear_pickup_target()
		_finish_failed(REASON_PILE_UNREACHABLE)
		return
	_unit.set_order_state(self, Unit.State.MOVING)

	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		movement.stop_movement()
		_handle_pile_arrival(movement)


func _update_moving_to_pile(movement: UnitMovement) -> void:
	if not _is_target_pile_still_reserved():
		_advance_by_role(movement)
		return

	match movement.get_move_state():
		UnitMovement.MoveState.MOVING:
			return
		UnitMovement.MoveState.ARRIVED:
			movement.stop_movement()
			_handle_pile_arrival(movement)
		UnitMovement.MoveState.FAILED_STUCK, UnitMovement.MoveState.FAILED_INVALID:
			movement.stop_movement()
			site.release_pickup_claim(_unit)
			_clear_pickup_target()
			_finish_failed(REASON_PILE_UNREACHABLE)
		UnitMovement.MoveState.IDLE:
			_handle_pile_arrival(movement)


func _is_target_pile_still_reserved() -> bool:
	if _target_pile_id <= 0 or _target_resource_id.is_empty():
		return false
	if _target_pile == null or not is_instance_valid(_target_pile):
		return false
	var inventory: SettlementInventory = site.get_inventory()
	if inventory == null:
		return false
	var entries: Array[Dictionary] = inventory.get_reserved_pile_entries(
		site.reservation_id,
		_target_resource_id
	)
	for entry: Dictionary in entries:
		if int(entry["pile_id"]) == _target_pile_id and int(entry["reserved_amount"]) > 0:
			_target_pile_pos = entry["world_pos"] as Vector3
			return true
	return false


func _handle_pile_arrival(movement: UnitMovement) -> void:
	if not _is_target_pile_still_reserved():
		_advance_by_role(movement)
		return

	if BuildSlotPlanner.is_unit_in_pile_reach(
		_unit.global_position,
		_target_pile_pos,
		ConstructionSite.DEFAULT_PILE_PICKUP_REACH,
		_get_world_3d()
	):
		_execute_pile_withdrawal(movement)
		return

	_retry_pile_approach_or_fail(movement)


func _retry_pile_approach_or_fail(movement: UnitMovement) -> void:
	if _approach_retries < MAX_APPROACH_RETRIES:
		_approach_retries += 1
		var occupied: Array[Vector3] = BuildSlotPlanner.collect_other_unit_positions(_unit, true)
		var slot_res: Dictionary = BuildSlotPlanner.compute_pile_approach_slot(
			_unit.global_position,
			_target_pile_pos,
			_world_nav,
			occupied
		)
		if bool(slot_res.get("valid", false)):
			resolved_target = slot_res["position"] as Vector3
			if movement.begin_move_to(resolved_target):
				_unit.set_order_state(self, Unit.State.MOVING)
				return

	site.release_pickup_claim(_unit)
	_clear_pickup_target()
	_finish_failed(REASON_PILE_UNREACHABLE)


func _execute_pile_withdrawal(movement: UnitMovement) -> void:
	if not _is_target_pile_still_reserved():
		_advance_by_role(movement)
		return
	if not BuildSlotPlanner.is_unit_in_pile_reach(
		_unit.global_position,
		_target_pile_pos,
		ConstructionSite.DEFAULT_PILE_PICKUP_REACH,
		_get_world_3d()
	):
		_retry_pile_approach_or_fail(movement)
		return

	var inventory: SettlementInventory = site.get_inventory()
	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if inventory == null or carry_load == null or _target_resource_def == null:
		_finish_failed(REASON_MISSING_ECONOMY)
		return

	var live_reserved_on_pile: int = 0
	var entries: Array[Dictionary] = inventory.get_reserved_pile_entries(
		site.reservation_id,
		_target_resource_id
	)
	for entry: Dictionary in entries:
		if int(entry["pile_id"]) == _target_pile_id:
			live_reserved_on_pile = int(entry["reserved_amount"])
			break

	var still_needed: int = site.get_remaining_supply_to_claim(_target_resource_id, _unit)
	var room: int = carry_load.get_max_additional_units(_target_resource_def)
	var take_amt: int = mini(mini(_planned_pickup_amount, still_needed), mini(live_reserved_on_pile, room))
	if take_amt <= 0:
		_advance_by_role(movement)
		return

	var withdrawn: int = inventory.withdraw_reserved_from_pile_to_carry_load(
		_target_pile_id,
		site.reservation_id,
		_target_resource_def,
		take_amt,
		carry_load
	)
	if withdrawn <= 0:
		_advance_by_role(movement)
		return

	site.record_withdrawn_for_site(_unit, _target_resource_id, withdrawn)
	_clear_pickup_target()
	_start_moving_to_site_dropoff(movement)


func _start_moving_to_site_dropoff(movement: UnitMovement) -> void:
	_phase = Phase.MOVING_TO_SITE_DROPOFF
	_approach_retries = 0
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)

	if BuildSlotPlanner.is_unit_in_site_dropoff_range(
		_unit.global_position,
		site,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
		_get_world_3d()
	):
		movement.stop_movement()
		_execute_site_dropoff(movement)
		return

	var occupied: Array[Vector3] = BuildSlotPlanner.collect_other_unit_positions(_unit, true)
	var slot_res: Dictionary = BuildSlotPlanner.compute_site_perimeter_slot(
		_unit.global_position,
		site,
		_world_nav,
		occupied
	)
	if not bool(slot_res.get("valid", false)):
		_finish_failed(REASON_SITE_UNREACHABLE)
		return

	resolved_target = slot_res["position"] as Vector3
	if not movement.begin_move_to(resolved_target):
		_finish_failed(REASON_SITE_UNREACHABLE)
		return
	_unit.set_order_state(self, Unit.State.TRANSPORTING)

	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		movement.stop_movement()
		_handle_site_dropoff_arrival(movement)


func _update_moving_to_site_dropoff(movement: UnitMovement) -> void:
	match movement.get_move_state():
		UnitMovement.MoveState.MOVING:
			return
		UnitMovement.MoveState.ARRIVED:
			movement.stop_movement()
			_handle_site_dropoff_arrival(movement)
		UnitMovement.MoveState.FAILED_STUCK:
			movement.stop_movement()
			_handle_site_dropoff_arrival(movement)
		UnitMovement.MoveState.FAILED_INVALID:
			movement.stop_movement()
			_finish_failed(REASON_SITE_UNREACHABLE)
		UnitMovement.MoveState.IDLE:
			_handle_site_dropoff_arrival(movement)


func _handle_site_dropoff_arrival(movement: UnitMovement) -> void:
	if BuildSlotPlanner.is_unit_in_site_dropoff_range(
		_unit.global_position,
		site,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
		_get_world_3d()
	):
		_execute_site_dropoff(movement)
		return

	_retry_site_dropoff_or_fail(movement)


func _retry_perimeter_slot_move(movement: UnitMovement, target_state: Unit.State) -> bool:
	if _approach_retries >= MAX_APPROACH_RETRIES:
		return false
	_approach_retries += 1
	var occupied: Array[Vector3] = BuildSlotPlanner.collect_other_unit_positions(_unit, true)
	var slot_res: Dictionary = BuildSlotPlanner.compute_site_perimeter_slot(
		_unit.global_position,
		site,
		_world_nav,
		occupied
	)
	if not bool(slot_res.get("valid", false)):
		return false
	resolved_target = slot_res["position"] as Vector3
	if not movement.begin_move_to(resolved_target):
		return false
	_unit.set_order_state(self, target_state)
	return true


func _retry_site_dropoff_or_fail(movement: UnitMovement) -> void:
	if _retry_perimeter_slot_move(movement, Unit.State.TRANSPORTING):
		return
	_finish_failed(REASON_SITE_UNREACHABLE)


func _execute_site_dropoff(movement: UnitMovement) -> void:
	if not BuildSlotPlanner.is_unit_in_site_dropoff_range(
		_unit.global_position,
		site,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
		_get_world_3d()
	):
		_retry_site_dropoff_or_fail(movement)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	var dropped: Dictionary = site.accept_delivery_from_carry_load(_unit, carry_load)
	if not dropped.is_empty():
		trips_completed += 1
		for k: Variant in dropped.keys():
			units_delivered_total += int(dropped[k])
	resolved_target = Vector3(INF, INF, INF)
	_advance_by_role(movement)


func _resolve_or_assign_builder_anchor(slot_idx: int) -> Vector3:
	var existing: Dictionary = site.get_assigned_builder_slot_position(_unit)
	if not existing.is_empty() and int(existing.get("slot_idx", -1)) == slot_idx:
		var existing_pos: Vector3 = existing.get("position", Vector3(INF, INF, INF)) as Vector3
		if existing_pos.is_finite() and BuildSlotPlanner.is_unit_in_site_dropoff_range(
			existing_pos,
			site,
			ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
			_get_world_3d()
		):
			return existing_pos

	var occupied: Array[Vector3] = BuildSlotPlanner.collect_other_unit_positions(_unit, true)
	var slot_res: Dictionary = BuildSlotPlanner.compute_site_perimeter_slot(
		_unit.global_position,
		site,
		_world_nav,
		occupied,
		WorldNavigation.DEFAULT_AGENT_RADIUS,
		ConstructionSite.DEFAULT_DROPOFF_OUTWARD_MARGIN,
		slot_idx
	)
	if not bool(slot_res.get("valid", false)):
		return Vector3(INF, INF, INF)

	var resolved_pos: Vector3 = slot_res["position"] as Vector3
	if not site.assign_builder_slot_position(_unit, slot_idx, resolved_pos):
		return Vector3(INF, INF, INF)
	return resolved_pos


func _start_moving_to_builder_slot(movement: UnitMovement) -> void:
	_phase = Phase.MOVING_TO_BUILDER_SLOT
	_approach_retries = 0
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)

	var slot_idx: int = site.get_builder_slot_index(_unit)
	if slot_idx < 0:
		_replan_requested = true
		return

	var anchor_pos: Vector3 = _resolve_or_assign_builder_anchor(slot_idx)
	if not anchor_pos.is_finite():
		_finish_failed(REASON_SITE_UNREACHABLE)
		return

	resolved_target = anchor_pos
	if (
		_unit.global_position.distance_to(resolved_target) <= UnitMovement.ARRIVAL_TOLERANCE_XZ + 0.05
		and BuildSlotPlanner.is_unit_at_assigned_builder_slot(_unit.global_position, site, resolved_target)
		and BuildSlotPlanner.is_unit_in_site_dropoff_range(
			_unit.global_position,
			site,
			ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
			_get_world_3d()
		)
	):
		movement.stop_movement()
		_enter_builder_slot_ready(movement)
		return

	if not movement.begin_move_to(resolved_target):
		_finish_failed(REASON_SITE_UNREACHABLE)
		return
	_unit.set_order_state(self, Unit.State.MOVING)

	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		movement.stop_movement()
		_handle_builder_slot_arrival(movement)


func _retry_builder_slot_move(movement: UnitMovement, slot_idx: int) -> bool:
	if _approach_retries >= MAX_APPROACH_RETRIES:
		return false
	_approach_retries += 1
	var occupied: Array[Vector3] = BuildSlotPlanner.collect_other_unit_positions(_unit, true)
	var slot_res: Dictionary = BuildSlotPlanner.compute_site_perimeter_slot(
		_unit.global_position,
		site,
		_world_nav,
		occupied,
		WorldNavigation.DEFAULT_AGENT_RADIUS,
		ConstructionSite.DEFAULT_DROPOFF_OUTWARD_MARGIN,
		slot_idx
	)
	if not bool(slot_res.get("valid", false)):
		return false
	var new_anchor: Vector3 = slot_res["position"] as Vector3
	if not site.assign_builder_slot_position(_unit, slot_idx, new_anchor):
		return false
	resolved_target = new_anchor
	if not movement.begin_move_to(resolved_target):
		return false
	_unit.set_order_state(self, Unit.State.MOVING)
	return true


func _handle_builder_slot_arrival(movement: UnitMovement) -> void:
	var slot_idx: int = site.get_builder_slot_index(_unit)
	if slot_idx < 0:
		_advance_by_role(movement)
		return
	var anchor: Dictionary = site.get_assigned_builder_slot_position(_unit)
	var anchor_pos: Vector3 = anchor.get("position", Vector3(INF, INF, INF)) as Vector3
	if (
		not anchor.is_empty()
		and int(anchor.get("slot_idx", -1)) == slot_idx
		and anchor_pos.is_finite()
		and BuildSlotPlanner.is_unit_at_assigned_builder_slot(_unit.global_position, site, anchor_pos)
		and BuildSlotPlanner.is_unit_in_site_dropoff_range(
			_unit.global_position,
			site,
			ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
			_get_world_3d()
		)
	):
		resolved_target = anchor_pos
		_enter_builder_slot_ready(movement)
		return

	if _retry_builder_slot_move(movement, slot_idx):
		return
	_finish_failed(REASON_SITE_UNREACHABLE)


func _update_moving_to_builder_slot(movement: UnitMovement) -> void:
	match movement.get_move_state():
		UnitMovement.MoveState.MOVING:
			return
		UnitMovement.MoveState.ARRIVED:
			movement.stop_movement()
			_handle_builder_slot_arrival(movement)
		UnitMovement.MoveState.FAILED_STUCK:
			movement.stop_movement()
			if site.get_worker_role(_unit) != ConstructionSite.WorkerRole.BUILDER:
				_advance_by_role(movement)
			else:
				_handle_builder_slot_arrival(movement)
		UnitMovement.MoveState.FAILED_INVALID:
			movement.stop_movement()
			_finish_failed(REASON_SITE_UNREACHABLE)
		UnitMovement.MoveState.IDLE:
			var slot_idx: int = site.get_builder_slot_index(_unit)
			var anchor: Dictionary = site.get_assigned_builder_slot_position(_unit)
			var anchor_pos: Vector3 = anchor.get("position", Vector3(INF, INF, INF)) as Vector3
			if (
				slot_idx >= 0
				and not anchor.is_empty()
				and int(anchor.get("slot_idx", -1)) == slot_idx
				and anchor_pos.is_finite()
				and BuildSlotPlanner.is_unit_at_assigned_builder_slot(_unit.global_position, site, anchor_pos)
				and BuildSlotPlanner.is_unit_in_site_dropoff_range(
					_unit.global_position,
					site,
					ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
					_get_world_3d()
				)
			):
				_enter_builder_slot_ready(movement)
			else:
				_replan_requested = true


func _can_unit_assemble_now() -> bool:
	if not _is_site_valid() or not site.is_active():
		return false
	if _unit == null or not is_instance_valid(_unit) or not _unit.is_inside_tree():
		return false
	if site.get_worker_role(_unit) != ConstructionSite.WorkerRole.BUILDER:
		return false
	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load != null and not carry_load.is_empty():
		return false
	var slot_idx: int = site.get_builder_slot_index(_unit)
	var anchor: Dictionary = site.get_assigned_builder_slot_position(_unit)
	if slot_idx < 0 or anchor.is_empty() or int(anchor.get("slot_idx", -1)) != slot_idx:
		return false
	var anchor_pos: Vector3 = anchor.get("position", Vector3(INF, INF, INF)) as Vector3
	if not BuildSlotPlanner.is_unit_at_assigned_builder_slot(_unit.global_position, site, anchor_pos):
		return false
	return BuildSlotPlanner.is_unit_in_site_dropoff_range(
		_unit.global_position,
		site,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
		_get_world_3d()
	)


func _hold_builder_station(movement: UnitMovement) -> void:
	if movement != null:
		movement.stop_movement()
		movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	if _unit != null and is_instance_valid(_unit) and _is_site_valid():
		if BuildSlotPlanner.is_unit_in_site_dropoff_range(
			_unit.global_position,
			site,
			ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
			_get_world_3d()
		):
			var site_pos: Vector3 = site.global_position
			if _unit.global_position.distance_squared_to(site_pos) > 0.01:
				var look_dir := Vector3(site_pos.x - _unit.global_position.x, 0.0, site_pos.z - _unit.global_position.z)
				if look_dir.length_squared() > 0.001:
					_unit.rotation.y = atan2(-look_dir.x, -look_dir.z)
		_unit.set_order_state(self, Unit.State.WORKING)


func _enter_builder_slot_ready(movement: UnitMovement) -> void:
	if site.is_completed_or_completing():
		if movement != null:
			movement.stop_movement()
		_finish_succeeded()
		return
	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load != null and not carry_load.is_empty():
		_enter_builder_standby(movement)
		return
	if site.get_work_progress_sec() == 0.0 and not site.has_any_received_materials():
		_enter_builder_standby(movement)
		return
	if site.has_consumable_work_available():
		_enter_builder_assembling(movement)
		return
	_enter_waiting_for_materials(movement)


func _enter_builder_standby(movement: UnitMovement) -> void:
	_phase = Phase.BUILDER_STANDBY
	_hold_builder_station(movement)


func _enter_builder_assembling(movement: UnitMovement) -> void:
	_phase = Phase.BUILDER_ASSEMBLING
	_hold_builder_station(movement)


func _enter_waiting_for_materials(movement: UnitMovement) -> void:
	_phase = Phase.WAITING_FOR_MATERIALS
	_hold_builder_station(movement)


func _update_builder_standby(movement: UnitMovement) -> void:
	if site.is_completed_or_completing():
		movement.stop_movement()
		_finish_succeeded()
		return
	if site.get_worker_role(_unit) != ConstructionSite.WorkerRole.BUILDER:
		_advance_by_role(movement)
		return
	if site.has_consumable_work_available() and _can_unit_assemble_now():
		_enter_builder_assembling(movement)


func _update_builder_assembling(movement: UnitMovement, delta: float) -> void:
	if site.is_completed_or_completing():
		movement.stop_movement()
		_finish_succeeded()
		return
	if site.get_worker_role(_unit) != ConstructionSite.WorkerRole.BUILDER:
		_advance_by_role(movement)
		return
	if not _can_unit_assemble_now():
		var carry_load: UnitCarryLoad = _unit.get_carry_load()
		if carry_load != null and not carry_load.is_empty():
			_enter_builder_standby(movement)
		else:
			_start_moving_to_builder_slot(movement)
		return
	if not is_finite(delta) or delta <= 0.0:
		return

	var step_delta: float = minf(delta, ConstructionSite.MAX_WORK_DELTA_SEC)
	var work_res: Dictionary = site.contribute_work(_unit, step_delta)
	if bool(work_res.get("completed", false)) or site.is_completed_or_completing():
		movement.stop_movement()
		_finish_succeeded()
		return
	if not bool(work_res.get("ok", false)):
		var reason: String = str(work_res.get("reason", ""))
		if reason == "site_completing_or_completed":
			movement.stop_movement()
			_finish_succeeded()
			return
		if reason == "worker_not_builder" or reason == "worker_not_registered" or reason == "invalid_builder_slot":
			_advance_by_role(movement)
			return
		if reason == "builder_slot_position_not_assigned" or reason == "worker_not_in_assigned_slot" or reason == "worker_out_of_reach":
			_start_moving_to_builder_slot(movement)
			return
		return
	if bool(work_res.get("starved", false)) or site.get_assembly_substate() == ConstructionSite.AssemblySubstate.PAUSED_STARVED:
		_enter_waiting_for_materials(movement)


func _update_waiting_for_materials(movement: UnitMovement) -> void:
	if movement != null and movement.get_move_state() == UnitMovement.MoveState.MOVING:
		movement.stop_movement()
	_unit.set_order_state(self, Unit.State.WORKING)


func _start_waiting_for_peer_supply(movement: UnitMovement) -> void:
	_phase = Phase.WAITING_FOR_PEER_SUPPLY
	_approach_retries = 0
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)

	if BuildSlotPlanner.is_unit_in_site_dropoff_range(
		_unit.global_position,
		site,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
		_get_world_3d()
	):
		movement.stop_movement()
		resolved_target = Vector3(INF, INF, INF)
		_unit.set_order_state(self, Unit.State.WORKING)
		return

	var occupied: Array[Vector3] = BuildSlotPlanner.collect_other_unit_positions(_unit, true)
	var slot_res: Dictionary = BuildSlotPlanner.compute_site_perimeter_slot(
		_unit.global_position,
		site,
		_world_nav,
		occupied
	)
	if not bool(slot_res.get("valid", false)):
		_finish_failed(REASON_SITE_UNREACHABLE)
		return

	resolved_target = slot_res["position"] as Vector3
	if not movement.begin_move_to(resolved_target):
		_finish_failed(REASON_SITE_UNREACHABLE)
		return
	_unit.set_order_state(self, Unit.State.MOVING)

	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		movement.stop_movement()
		_unit.set_order_state(self, Unit.State.WORKING)


func _update_waiting_for_peer_supply(movement: UnitMovement) -> void:
	match movement.get_move_state():
		UnitMovement.MoveState.MOVING:
			return
		UnitMovement.MoveState.ARRIVED:
			movement.stop_movement()
			resolved_target = Vector3(INF, INF, INF)
			_unit.set_order_state(self, Unit.State.WORKING)
		UnitMovement.MoveState.FAILED_STUCK:
			movement.stop_movement()
			if not site.has_active_peer_transport_for_site(_unit):
				_advance_by_role(movement)
			elif not _retry_perimeter_slot_move(movement, Unit.State.MOVING):
				_finish_failed(REASON_SITE_UNREACHABLE)
		UnitMovement.MoveState.FAILED_INVALID:
			movement.stop_movement()
			_finish_failed(REASON_SITE_UNREACHABLE)
		UnitMovement.MoveState.IDLE:
			if not site.has_active_peer_transport_for_site(_unit):
				_advance_by_role(movement)


func _has_claimable_reserved_piles() -> bool:
	if not _is_site_valid():
		return false
	var required: Dictionary = site.get_required_amounts()
	for res_key: Variant in required.keys():
		var res_id: StringName = res_key as StringName
		if site.get_remaining_supply_to_claim(res_id, _unit) > 0 and site.get_reserved_in_piles_amount(res_id) > 0:
			return true
	return false


func _on_site_workers_changed(_changed_site: ConstructionSite) -> void:
	if status != Status.RUNNING or site == null or not is_instance_valid(site):
		return
	var cur_role: ConstructionSite.WorkerRole = site.get_worker_role(_unit)
	var role_changed: bool = cur_role != _last_known_role
	if _phase == Phase.WAITING_FOR_MATERIALS or _phase == Phase.BUILDER_STANDBY or _phase == Phase.BUILDER_ASSEMBLING:
		if site.is_completed_or_completing() or role_changed:
			_replan_requested = true
			return
		if cur_role == ConstructionSite.WorkerRole.BUILDER:
			var slot_idx: int = site.get_builder_slot_index(_unit)
			var anchor: Dictionary = site.get_assigned_builder_slot_position(_unit)
			if slot_idx < 0 or anchor.is_empty() or int(anchor.get("slot_idx", -1)) != slot_idx:
				_replan_requested = true
				return
			if (_phase == Phase.WAITING_FOR_MATERIALS or _phase == Phase.BUILDER_STANDBY) and site.has_consumable_work_available() and _can_unit_assemble_now():
				_enter_builder_assembling(_movement)
		return
	_replan_requested = true


func _on_site_buffer_changed(_changed_site: ConstructionSite) -> void:
	if status != Status.RUNNING or site == null or not is_instance_valid(site):
		return
	if site.is_completed_or_completing():
		_replan_requested = true
		return
	if (_phase == Phase.WAITING_FOR_MATERIALS or _phase == Phase.BUILDER_STANDBY) and _can_unit_assemble_now() and site.has_consumable_work_available():
		_enter_builder_assembling(_movement)
	elif _phase == Phase.WAITING_FOR_PEER_SUPPLY and site.is_fully_supplied():
		_replan_requested = true


func _on_site_state_changed(_changed_site: ConstructionSite) -> void:
	if status != Status.RUNNING or site == null or not is_instance_valid(site):
		return
	if site.is_completed_or_completing():
		_replan_requested = true
		return
	var cur_role: ConstructionSite.WorkerRole = site.get_worker_role(_unit)
	if cur_role != _last_known_role:
		_replan_requested = true
		return
	if (_phase == Phase.WAITING_FOR_MATERIALS or _phase == Phase.BUILDER_STANDBY) and _can_unit_assemble_now() and site.has_consumable_work_available():
		_enter_builder_assembling(_movement)
		return
	if _phase == Phase.WAITING_FOR_PEER_SUPPLY:
		if site.is_fully_supplied() or not site.has_active_peer_transport_for_site(_unit) or _has_claimable_reserved_piles():
			_replan_requested = true


func _bind_site_signals() -> void:
	if _site_signals_bound or not _is_site_valid():
		return
	if not site.workers_changed.is_connected(_on_site_workers_changed):
		site.workers_changed.connect(_on_site_workers_changed)
	if not site.buffer_changed.is_connected(_on_site_buffer_changed):
		site.buffer_changed.connect(_on_site_buffer_changed)
	if not site.state_changed.is_connected(_on_site_state_changed):
		site.state_changed.connect(_on_site_state_changed)
	_site_signals_bound = true


func _unbind_site_signals() -> void:
	if not _site_signals_bound:
		return
	if site != null and is_instance_valid(site):
		if site.workers_changed.is_connected(_on_site_workers_changed):
			site.workers_changed.disconnect(_on_site_workers_changed)
		if site.buffer_changed.is_connected(_on_site_buffer_changed):
			site.buffer_changed.disconnect(_on_site_buffer_changed)
		if site.state_changed.is_connected(_on_site_state_changed):
			site.state_changed.disconnect(_on_site_state_changed)
	_site_signals_bound = false


func _get_world_3d() -> World3D:
	if _unit != null and is_instance_valid(_unit) and _unit.is_inside_tree():
		return _unit.get_world_3d()
	if _world_nav != null and is_instance_valid(_world_nav) and _world_nav.is_inside_tree():
		return _world_nav.get_world_3d()
	return null


func _clear_pickup_target() -> void:
	_target_pile_id = 0
	_target_pile = null
	_target_resource_id = &""
	_target_resource_def = null
	_target_pile_pos = Vector3.ZERO
	_planned_pickup_amount = 0


func _is_site_valid() -> bool:
	return site != null and is_instance_valid(site) and site.is_inside_tree() and site.is_valid()


func _finish_succeeded() -> void:
	_clear_pickup_target()
	resolved_target = Vector3(INF, INF, INF)
	_unbind_site_signals()
	if site != null and is_instance_valid(site) and _unit != null and is_instance_valid(_unit):
		site.release_pickup_claim(_unit)
		site.unregister_worker(_unit, self)
	if _movement != null:
		_movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	mark_succeeded()


func _finish_failed(reason: String) -> void:
	_clear_pickup_target()
	resolved_target = Vector3(INF, INF, INF)
	_unbind_site_signals()
	if site != null and is_instance_valid(site) and _unit != null and is_instance_valid(_unit):
		site.release_pickup_claim(_unit)
		site.unregister_worker(_unit, self)
	if _movement != null:
		_movement.stop_movement()
		_movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	mark_failed(reason)
