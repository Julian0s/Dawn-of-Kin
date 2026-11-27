class_name Unit
extends CharacterBody3D
## Independent RTS unit entity composed of a CharacterBody3D, CharacterDefinition identity,
## UnitMovement component, and an active UnitOrder lifecycle.
## Does not read player input or compute navigation queries directly.

const GROUP_SELECTABLE_UNITS: StringName = &"selectable_units"

enum State {
	IDLE,
	MOVING,
	WORKING,
	TRANSPORTING,
}

signal state_changed(new_state: State, previous_state: State)
signal order_finished(order: UnitOrder)

@export var definition: CharacterDefinition = null:
	set(value):
		if _is_definition_mutation_locked():
			return
		if value == null:
			definition = null
			return
		if _carry_load != null and not _carry_load.set_base_capacity(value.base_carry_capacity):
			return
		definition = value
		if is_node_ready():
			_sync_definition()

@export var world_navigation_path: NodePath = NodePath()

@onready var _movement: UnitMovement = $UnitMovement
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual_root: Node3D = $VisualRoot
@onready var _explorer_visual: Node3D = $VisualRoot/ExplorerVisual
@onready var _cloak_visual: Node3D = $VisualRoot/CloakVisual
@onready var _selection_area: Area3D = $SelectionArea
@onready var _selection_indicator: SelectionIndicator = $SelectionIndicator

var _state: State = State.IDLE
var _current_order: UnitOrder = null
var _order_revision: int = 0
var _last_order_rejection_reason: String = ""
## A contribution follows the worker even when its active order changes sites.
var _last_construction_work_frame: int = -1
var _world_navigation: WorldNavigation = null
var _carry_load: UnitCarryLoad = UnitCarryLoad.new()
var _order_state_explicit: bool = false
var _is_selected: bool = false
var _is_hovered: bool = false
var _visual_base_transform: Transform3D = Transform3D.IDENTITY
var _has_visual_base_transform: bool = false
var _visual_cycle_time: float = 0.0


func _ready() -> void:
	add_to_group(GROUP_SELECTABLE_UNITS)
	collision_layer = CollisionLayers.MASK_UNITS
	collision_mask = CollisionLayers.MASK_WORLD_SOLID
	if _visual_root != null:
		_visual_base_transform = _visual_root.transform
		_has_visual_base_transform = true

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
		_movement.set_carry_load(_carry_load)

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

	_update_work_and_load_visuals(delta)


func _exit_tree() -> void:
	if _current_order != null and _current_order.is_active():
		var exiting_order: UnitOrder = _current_order
		_current_order = null
		exiting_order.cancel(_movement, UnitOrder.REASON_UNIT_EXITED)
		_set_state(State.IDLE)
		order_finished.emit(exiting_order)
	reset_work_visuals()


func apply_definition(def: CharacterDefinition) -> void:
	definition = def


func _is_definition_mutation_locked() -> bool:
	if _is_reserved_withdrawal_locked():
		return true
	return _carry_load != null and (
		_carry_load._coordinator_transaction_locked
		or _carry_load._provenance_busy
		or _carry_load._provenance_applying
	)


func _sync_definition() -> void:
	if definition == null or _is_definition_mutation_locked():
		return
	if _carry_load != null and not _carry_load.set_base_capacity(definition.base_carry_capacity):
		return

	if _movement != null:
		_movement.set_carry_load(_carry_load)
		_movement.set_motion_profile(
			definition.move_speed,
			definition.turn_rate,
			definition.work_approach_speed,
			definition.max_load_speed_multiplier
		)

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
	match _state:
		State.IDLE:
			return "IDLE"
		State.MOVING:
			return "MOVING"
		State.WORKING:
			return "WORKING"
		State.TRANSPORTING:
			return "TRANSPORTING"
		_:
			return "IDLE"


func get_carry_load() -> UnitCarryLoad:
	return _carry_load


func set_order_state(order: UnitOrder, new_state: State) -> void:
	if order == null or order != _current_order or not order.is_active():
		return
	_order_state_explicit = true
	_set_state(new_state)


func get_current_order() -> UnitOrder:
	return _current_order


func get_order_revision() -> int:
	return _order_revision


func get_last_order_rejection_reason() -> String:
	return _last_order_rejection_reason


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


func _is_reserved_withdrawal_locked() -> bool:
	if _carry_load._coordinator_transaction_locked:
		return true
	# Only construction orders expose a site. Avoid a Unit -> ConstructOrder dependency.
	var assigned_site: Variant = _current_order.get("site") if _current_order != null else null
	return is_instance_valid(assigned_site) and bool(assigned_site.get("_is_preparing_or_transacting"))


func issue_order(order: UnitOrder) -> bool:
	if order == null:
		if _is_reserved_withdrawal_locked():
			_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
			return false
		_last_order_rejection_reason = ""
		return _clear_current_order_for_null_issue()
	return issue_personal_order(order)


func issue_personal_order(order: UnitOrder) -> bool:
	if _is_reserved_withdrawal_locked():
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false
	if order == null:
		_last_order_rejection_reason = UnitControlPermissions.REASON_INVALID_ORDER
		return false
	if order.is_finished() or order.status != UnitOrder.Status.PENDING:
		_last_order_rejection_reason = "order_not_pending"
		return false
	var reject_reason: String = UnitControlPermissions.get_personal_order_rejection_reason_for_order(self, order)
	if not reject_reason.is_empty():
		_last_order_rejection_reason = reject_reason
		return false
	_last_order_rejection_reason = ""
	return _install_admitted_order(order, UnitOrder.OrderOrigin.PERSONAL)


func issue_community_order(
	order: GatherResourceOrder,
	dispatch_lease: CommunityWorkBoard.DispatchLease
) -> bool:
	if _is_reserved_withdrawal_locked():
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false
	if order == null or dispatch_lease == null:
		_last_order_rejection_reason = "invalid_dispatch_lease"
		return false
	var board: CommunityWorkBoard = dispatch_lease.get_board()
	if board == null or not is_instance_valid(board) or not board.is_inside_tree():
		_last_order_rejection_reason = "invalid_dispatch_lease"
		return false
	if not board.validate_dispatch_lease_for_installation(dispatch_lease, self, order):
		_last_order_rejection_reason = "invalid_dispatch_lease"
		return false
	if not board.mark_dispatch_lease_installing(dispatch_lease):
		_last_order_rejection_reason = "invalid_dispatch_lease"
		return false
	_last_order_rejection_reason = ""
	var installed: bool = _install_admitted_order(order, UnitOrder.OrderOrigin.COMMUNITY)
	if not installed and is_instance_valid(board):
		board.abort_task_dispatch(dispatch_lease)
	return installed


func issue_recovery_order(
	order: RecoveryOrder,
	expected_revision: int,
	explicit: bool = false
) -> bool:
	if _is_reserved_withdrawal_locked():
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false
	if order == null or order.status != UnitOrder.Status.PENDING:
		_last_order_rejection_reason = "invalid_recovery_order"
		return false
	if not is_inside_tree() or is_queued_for_deletion():
		_last_order_rejection_reason = UnitOrder.REASON_UNIT_NOT_IN_TREE
		return false
	if not UnitControlPermissions.can_perform_recovery_order(self):
		_last_order_rejection_reason = UnitControlPermissions.REASON_AGE_RESTRICTED_TASK
		return false
	if _order_revision != expected_revision:
		_last_order_rejection_reason = "obsolete_order_revision"
		return false
	var dispatcher: CancellationRecoveryDispatcher = order.get_dispatcher()
	if (
		dispatcher == null
		or not is_instance_valid(dispatcher)
		or not dispatcher.is_inside_tree()
		or not dispatcher.is_admitting_recovery(self, order, explicit)
	):
		_last_order_rejection_reason = "unadmitted_recovery_order"
		return false
	var world: World3D = get_world_3d()
	if world == null:
		_last_order_rejection_reason = "invalid_domain"
		return false
	if ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, order.region_id):
		_last_order_rejection_reason = "regional_transaction_active"
		return false
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = CancellationRecoveryTransaction._record(
		world,
		order.region_id,
		order.cancel_id
	)
	if record == null or not record.has_unsettled_custody():
		_last_order_rejection_reason = "no_unsettled_custody"
		return false
	var id_check: Dictionary = ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(
		world,
		order.region_id,
		self,
		_carry_load,
		get_tree()
	)
	if not bool(id_check.get("ok", false)):
		_last_order_rejection_reason = String(id_check.get("reason", "ambiguous_unit_identity"))
		return false

	# F02: Strict T1a (idle) or T1b (ConstructOrder on this exact CANCELLED site, not transacting).
	if _current_order != null and _current_order.is_active():
		if not (_current_order is ConstructOrder):
			_last_order_rejection_reason = "unit_busy_for_recovery"
			return false
		var c_order: ConstructOrder = _current_order as ConstructOrder
		if (
			c_order.site == null
			or not is_instance_valid(c_order.site)
			or c_order.site.site_id != record.site_id
			or c_order.site.get_site_state() != ConstructionSite.SiteState.CANCELLED
			or c_order.is_transfer_executing_readonly()
		):
			_last_order_rejection_reason = "unit_busy_for_recovery"
			return false
	elif _state != State.IDLE:
		_last_order_rejection_reason = "unit_not_idle"
		return false

	_last_order_rejection_reason = ""
	return _install_admitted_order(order, UnitOrder.OrderOrigin.SYSTEM_RECOVERY)


func _clear_current_order_for_null_issue() -> bool:
	_order_revision += 1
	var issued_revision := _order_revision
	if _current_order != null and _current_order.is_active():
		var previous_order: UnitOrder = _current_order
		_current_order = null
		previous_order.cancel(_movement, UnitOrder.REASON_REPLACED)
		if not previous_order.is_finished():
			if _current_order == null and _order_revision == issued_revision:
				_current_order = previous_order
			_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
			return false
		order_finished.emit(previous_order)
		if _order_revision != issued_revision:
			return false
	if _movement != null:
		_movement.stop_movement()
	_set_state(State.IDLE)
	return true


func _install_admitted_order(order: UnitOrder, origin: UnitOrder.OrderOrigin) -> bool:
	_order_revision += 1
	var issued_revision := _order_revision
	if _current_order != null and _current_order.is_active():
		var previous_order: UnitOrder = _current_order
		_current_order = null
		previous_order.cancel(_movement, UnitOrder.REASON_REPLACED)
		if not previous_order.is_finished():
			if _current_order == null and _order_revision == issued_revision:
				_current_order = previous_order
			order.mark_cancelled(UnitOrder.REASON_REPLACED)
			_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
			return false
		order_finished.emit(previous_order)
		if _order_revision != issued_revision:
			# A callback accepted a newer command. Do not stop or overwrite its movement.
			order.mark_cancelled(UnitOrder.REASON_REPLACED)
			_last_order_rejection_reason = UnitOrder.REASON_REPLACED
			return false

	order._set_order_origin(origin)
	if _world_navigation == null and _movement != null:
		_world_navigation = _movement.get_world_navigation()

	_visual_cycle_time = 0.0
	_current_order = order
	_order_state_explicit = false
	order.start(self, _movement, _world_navigation)
	if _order_revision != issued_revision or _current_order != order:
		return false

	if order.is_finished():
		var finished_order: UnitOrder = _current_order
		_current_order = null
		_set_state(State.IDLE)
		order_finished.emit(finished_order)
		if finished_order.is_succeeded():
			return true
		_last_order_rejection_reason = finished_order.failure_reason
		return false

	if not _order_state_explicit:
		_set_state(State.MOVING)
	return true


func cancel_current_order(reason: String = UnitOrder.REASON_CANCELLED) -> void:
	if _is_reserved_withdrawal_locked():
		return
	_order_revision += 1
	var cancelled_revision := _order_revision
	if _current_order == null:
		if _movement != null:
			_movement.stop_movement()
		_set_state(State.IDLE)
		reset_work_visuals()
		return

	var cancelled_order: UnitOrder = _current_order
	_current_order = null
	cancelled_order.cancel(_movement, reason)
	if _order_revision != cancelled_revision:
		order_finished.emit(cancelled_order)
		return
	if not cancelled_order.is_finished():
		if _current_order == null:
			_current_order = cancelled_order
		return
	_set_state(State.IDLE)
	reset_work_visuals()
	order_finished.emit(cancelled_order)


func reset_work_visuals() -> void:
	_visual_cycle_time = 0.0
	if _visual_root != null and _has_visual_base_transform:
		_visual_root.transform = _visual_base_transform


func _set_state(new_state: State) -> void:
	if new_state == State.IDLE:
		_visual_cycle_time = 0.0
		if _current_order == null:
			if _movement != null:
				_movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
			reset_work_visuals()
	if new_state == _state:
		return
	var previous: State = _state
	_state = new_state
	state_changed.emit(new_state, previous)


func _update_work_and_load_visuals(delta: float) -> void:
	if _visual_root == null or not _has_visual_base_transform or delta <= 0.0:
		return

	var target_tf: Transform3D = _visual_base_transform
	var waiting_to_work: bool = _current_order != null and _current_order.is_waiting_to_work()
	if _state == State.WORKING and not waiting_to_work:
		_visual_cycle_time += delta
		var target_offset := Vector3.ZERO
		var target_euler := Vector3.ZERO
		if _current_order != null and _current_order.is_preparing_work():
			target_offset = Vector3(0.0, -0.025 + 0.012 * sin(_visual_cycle_time * 4.0), 0.0)
			target_euler = Vector3(-0.08, 0.04 * sin(_visual_cycle_time * 3.0), 0.0)
		else:
			var category: int = _current_order.get_work_category() if _current_order != null else -1
			match category:
				ResourceDefinition.Category.WOOD:
					var phase: float = _visual_cycle_time * 3.8
					var strike: float = pow(maxf(sin(phase), 0.0), 2.0)
					target_offset = Vector3(0.0, -0.045 * strike, -0.03 * strike)
					target_euler = Vector3(-0.18 * strike + 0.05 * (1.0 - strike), 0.08 * cos(phase), -0.06 * sin(phase))
				ResourceDefinition.Category.STONE:
					var phase: float = _visual_cycle_time * 2.6
					var strike: float = pow(maxf(sin(phase), 0.0), 3.0)
					target_offset = Vector3(0.0, -0.06 * strike, -0.02 * strike)
					target_euler = Vector3(-0.22 * strike + 0.04, 0.05 * cos(phase), 0.05 * sin(phase))
				ResourceDefinition.Category.FOOD:
					var phase: float = _visual_cycle_time * 5.2
					target_offset = Vector3(0.03 * cos(phase * 0.5), -0.055 + 0.025 * sin(phase), -0.02)
					target_euler = Vector3(-0.16 + 0.05 * sin(phase), 0.07 * sin(phase * 0.5), 0.04 * cos(phase * 0.5))
				_:
					var phase: float = _visual_cycle_time * 3.5
					target_offset = Vector3(0.0, -0.03 * absf(sin(phase)), 0.0)
					target_euler = Vector3(-0.10 * absf(sin(phase)), 0.0, 0.0)
		target_tf = Transform3D(
			_visual_base_transform.basis * Basis.from_euler(target_euler),
			_visual_base_transform.origin + target_offset
		)
	elif _state == State.TRANSPORTING or (_state == State.MOVING and _carry_load.get_current_weight() > 0):
		var fill_ratio: float = clampf(_carry_load.get_fill_percentage() / 100.0, 0.0, 1.0)
		if _carry_load.is_overloaded() or (_carry_load.get_effective_capacity() <= 0 and _carry_load.get_current_weight() > 0):
			fill_ratio = 1.0
		if fill_ratio > 0.0:
			_visual_cycle_time += delta * (4.2 - 1.4 * fill_ratio)
			var effort_offset := Vector3(0.0, -0.055 * fill_ratio + 0.018 * absf(sin(_visual_cycle_time)), 0.0)
			var effort_euler := Vector3(
				-0.15 * fill_ratio,
				0.03 * fill_ratio * sin(_visual_cycle_time),
				0.05 * fill_ratio * cos(_visual_cycle_time)
			)
			target_tf = Transform3D(
				_visual_base_transform.basis * Basis.from_euler(effort_euler),
				_visual_base_transform.origin + effort_offset
			)
	else:
		_visual_cycle_time = 0.0

	var alpha: float = clampf(1.0 - exp(-14.0 * delta), 0.0, 1.0)
	_visual_root.transform = _visual_root.transform.interpolate_with(target_tf, alpha)


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
