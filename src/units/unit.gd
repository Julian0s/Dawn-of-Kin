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
signal order_interruption_cause_committed(order: UnitOrder, cause: UnitOrder.InterruptionCause)
signal control_mode_changed(new_mode: UnitControlState.ControlMode, previous_mode: UnitControlState.ControlMode)

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
var _control_state: UnitControlState = UnitControlState.new()
var _transition_seq: int = 0
var _pending_transition_seq: int = 0
var _pending_target_mode: UnitControlState.ControlMode = UnitControlState.ControlMode.COMMUNITY_FREE
var _pending_target_origin: UnitOrder.OrderOrigin = UnitOrder.OrderOrigin.NONE
var _cancelling_order: UnitOrder = null
var _awaiting_interruption_cause_order: UnitOrder = null
var _controlled_teardown_token: RefCounted = null
var _is_exiting_tree: bool = false
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


func _enter_tree() -> void:
	_is_exiting_tree = false
	_controlled_teardown_token = null


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
		var active_order: UnitOrder = _current_order
		var active_rev: int = _order_revision
		active_order.physics_update(_movement, delta)
		if active_order.is_finished():
			_finalize_order_completion(active_order, active_rev)

	_update_work_and_load_visuals(delta)


func _exit_tree() -> void:
	_is_exiting_tree = true
	_transition_seq += 1
	_pending_transition_seq = 0
	if _awaiting_interruption_cause_order != null and _awaiting_interruption_cause_order.is_finished():
		var pending_cause_order: UnitOrder = _awaiting_interruption_cause_order
		_commit_interruption_cause(pending_cause_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
		_emit_interruption_cause_committed_once(pending_cause_order)
	_awaiting_interruption_cause_order = null
	if _current_order != null and _current_order.is_active():
		var exiting_order: UnitOrder = _current_order
		_current_order = null
		_cancelling_order = exiting_order
		exiting_order.cancel(_movement, UnitOrder.REASON_UNIT_EXITED)
		if _cancelling_order == exiting_order:
			_cancelling_order = null
		if exiting_order.is_finished():
			_controlled_teardown_token = null
			if exiting_order.status == UnitOrder.Status.CANCELLED:
				_commit_interruption_cause(exiting_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
			_order_revision += 1
			_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
			_set_state(State.IDLE)
			_publish_control_mode_if_changed()
			_emit_order_finished_once(exiting_order)
			_emit_interruption_cause_committed_once(exiting_order)
		else:
			# Cancellation was refused by an active transactional lock/transfer: preserve revision,
			# ownership, and any controlled teardown token without emitting a false order_finished.
			_current_order = exiting_order
	else:
		_controlled_teardown_token = null
		_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
		_publish_control_mode_if_changed()
	reset_work_visuals()


func _begin_controlled_teardown(token: RefCounted) -> Dictionary:
	if token == null or _is_exiting_tree or not is_inside_tree() or is_queued_for_deletion():
		return {}
	if _current_order == null or not _current_order.is_active():
		return {}
	_controlled_teardown_token = token
	return {
		"unit": self,
		"order": _current_order,
		"revision": _order_revision,
	}


func _clear_controlled_teardown_token(token: RefCounted) -> void:
	if token != null and _controlled_teardown_token == token:
		_controlled_teardown_token = null


func _finalize_controlled_teardown_order(
	token: RefCounted,
	expected_order: UnitOrder,
	expected_revision: int
) -> bool:
	if token == null or _controlled_teardown_token != token:
		return false
	_controlled_teardown_token = null
	if not _is_exiting_tree or is_inside_tree():
		return false
	if expected_order == null or _current_order != expected_order or _order_revision != expected_revision:
		return false
	if not expected_order.is_active():
		return false
	if _is_reserved_withdrawal_locked() or not expected_order.can_cancel_now():
		return false

	_transition_seq += 1
	_pending_transition_seq = 0
	_current_order = null
	_cancelling_order = expected_order
	expected_order.cancel(_movement, UnitOrder.REASON_UNIT_EXITED)
	if _cancelling_order == expected_order:
		_cancelling_order = null

	if not expected_order.is_finished():
		_current_order = expected_order
		return false

	if expected_order.status == UnitOrder.Status.CANCELLED:
		_commit_interruption_cause(expected_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
	_order_revision += 1
	_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
	_set_state(State.IDLE)
	reset_work_visuals()
	_publish_control_mode_if_changed()
	_emit_order_finished_once(expected_order)
	_emit_interruption_cause_committed_once(expected_order)
	return true


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
	_reconcile_active_order_after_definition_change()


func _reconcile_active_order_after_definition_change() -> void:
	if _is_exiting_tree or not is_inside_tree() or _current_order == null or not _current_order.is_active():
		return
	var incompatible: bool = false
	match _current_order.get_order_origin():
		UnitOrder.OrderOrigin.PERSONAL:
			incompatible = not UnitControlPermissions.can_receive_personal_order_for_order(self, _current_order)
		UnitOrder.OrderOrigin.COMMUNITY:
			incompatible = not UnitControlPermissions.can_participate_in_community_work_for_order(self, _current_order)
		UnitOrder.OrderOrigin.SYSTEM_RECOVERY:
			incompatible = not UnitControlPermissions.can_perform_recovery_order(self)
	if incompatible:
		cancel_current_order("definition_permission_changed")


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


func get_control_mode() -> UnitControlState.ControlMode:
	return _control_state.get_mode()


func get_control_mode_name() -> String:
	return _control_state.get_mode_name()


func get_active_order_origin() -> UnitOrder.OrderOrigin:
	return _control_state.get_active_origin()


func has_pending_control_transition() -> bool:
	return _pending_transition_seq != 0


func is_community_dispatch_eligible() -> bool:
	return (
		is_inside_tree()
		and not _is_exiting_tree
		and not is_queued_for_deletion()
		and _pending_transition_seq == 0
		and _cancelling_order == null
		and _control_state.get_mode() == UnitControlState.ControlMode.COMMUNITY_FREE
		and _current_order == null
		and _state == State.IDLE
		and not _is_reserved_withdrawal_locked()
	)


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
		if _current_order != null and _current_order.is_active() and not _current_order.can_cancel_now():
			_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
			return false
		_last_order_rejection_reason = ""
		return _clear_current_order_for_null_issue()
	return issue_personal_order(order)


func issue_personal_order(order: UnitOrder) -> bool:
	if _is_exiting_tree or not is_inside_tree() or is_queued_for_deletion():
		_last_order_rejection_reason = UnitOrder.REASON_UNIT_NOT_IN_TREE
		return false
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
	if _current_order != null and _current_order.is_active() and not _current_order.can_cancel_now():
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false
	_last_order_rejection_reason = ""
	return _install_admitted_order(order, UnitOrder.OrderOrigin.PERSONAL)


func issue_community_order(
	order: GatherResourceOrder,
	dispatch_lease: CommunityWorkBoard.DispatchLease
) -> bool:
	if _is_exiting_tree or not is_inside_tree() or is_queued_for_deletion():
		_last_order_rejection_reason = UnitOrder.REASON_UNIT_NOT_IN_TREE
		return false
	if _is_reserved_withdrawal_locked():
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false
	if not is_community_dispatch_eligible():
		_last_order_rejection_reason = "unit_not_community_free"
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
	var installed: bool = _install_admitted_order(order, UnitOrder.OrderOrigin.COMMUNITY, {}, dispatch_lease)
	if not installed and is_instance_valid(board):
		board.abort_task_dispatch(dispatch_lease)
	return installed


func issue_recovery_order(
	order: RecoveryOrder,
	expected_revision: int,
	explicit: bool = false
) -> bool:
	if _is_exiting_tree or not is_inside_tree() or is_queued_for_deletion():
		_last_order_rejection_reason = UnitOrder.REASON_UNIT_NOT_IN_TREE
		return false
	if _is_reserved_withdrawal_locked():
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false
	if _pending_transition_seq != 0 or _cancelling_order != null:
		_last_order_rejection_reason = "transition_in_progress"
		return false
	if order == null or order.status != UnitOrder.Status.PENDING:
		_last_order_rejection_reason = "invalid_recovery_order"
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

	# F02: Strict T1a (COMMUNITY_FREE + IDLE) or T1b (ConstructOrder on this exact CANCELLED site, cancelable).
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
			or not c_order.can_cancel_now()
		):
			_last_order_rejection_reason = "unit_busy_for_recovery"
			return false
	elif _state != State.IDLE or _control_state.get_mode() != UnitControlState.ControlMode.COMMUNITY_FREE:
		_last_order_rejection_reason = "unit_not_idle"
		return false

	_last_order_rejection_reason = ""
	var recovery_ctx: Dictionary = {
		"dispatcher": dispatcher,
		"explicit": explicit,
		"world": world,
		"region_id": order.region_id,
		"cancel_id": order.cancel_id,
	}
	return _install_admitted_order(order, UnitOrder.OrderOrigin.SYSTEM_RECOVERY, recovery_ctx)


func _has_mutation_authority(my_seq: int, issued_revision: int) -> bool:
	return (
		_transition_seq == my_seq
		and _order_revision == issued_revision
		and is_inside_tree()
		and not _is_exiting_tree
		and not is_queued_for_deletion()
	)


func _emit_order_finished_once(order: UnitOrder) -> void:
	if order == null or not order.is_finished() or order.was_finished_notified():
		return
	order.mark_finished_notified()
	order_finished.emit(order)


func _commit_interruption_cause(target: UnitOrder, cause: UnitOrder.InterruptionCause) -> void:
	if target == null or cause == UnitOrder.InterruptionCause.NONE:
		return
	target.set_interruption_cause(cause)
	if _awaiting_interruption_cause_order == target:
		_awaiting_interruption_cause_order = null


func _emit_interruption_cause_committed_once(order: UnitOrder) -> void:
	if (
		order == null
		or not order.is_finished()
		or order.get_interruption_cause() == UnitOrder.InterruptionCause.NONE
		or order.was_interruption_cause_notified()
	):
		return
	order.mark_interruption_cause_notified()
	order_interruption_cause_committed.emit(order, order.get_interruption_cause())


func _publish_control_mode_if_changed() -> void:
	var delta: Dictionary = _control_state._commit_published_mode()
	if bool(delta["changed"]):
		control_mode_changed.emit(
			delta["new_mode"] as UnitControlState.ControlMode,
			delta["previous_mode"] as UnitControlState.ControlMode
		)


static func _interruption_cause_for(order: UnitOrder, origin: UnitOrder.OrderOrigin) -> UnitOrder.InterruptionCause:
	if origin == UnitOrder.OrderOrigin.SYSTEM_RECOVERY:
		return UnitOrder.InterruptionCause.SYSTEM_RECOVERY
	if origin == UnitOrder.OrderOrigin.PERSONAL:
		if order is MoveOrder:
			return UnitOrder.InterruptionCause.PERSONAL_MOVE
		return UnitOrder.InterruptionCause.PERSONAL_OTHER
	return UnitOrder.InterruptionCause.ADMIN_CANCEL


func _finalize_order_completion(finished_order: UnitOrder, expected_rev: int) -> void:
	if finished_order == null:
		return
	var owns_active: bool = (
		_current_order == finished_order
		and _order_revision == expected_rev
		and _pending_transition_seq == 0
	)
	if owns_active:
		_current_order = null
		_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
		_set_state(State.IDLE)
		if (
			_order_revision == expected_rev
			and _current_order == null
			and _pending_transition_seq == 0
			and is_inside_tree()
			and not _is_exiting_tree
			and not is_queued_for_deletion()
		):
			_publish_control_mode_if_changed()
	_emit_order_finished_once(finished_order)


func _clear_current_order_for_null_issue() -> bool:
	return _perform_administrative_cancel(UnitOrder.REASON_REPLACED)


func _perform_administrative_cancel(reason: String) -> bool:
	if _is_reserved_withdrawal_locked():
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false
	if _current_order != null and _current_order.is_active() and not _current_order.can_cancel_now():
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false

	# Reentrant administrative cancel while an outer transition is cancelling or finalizing an order:
	# supersede the outer transition cleanly without recursively invoking cancel() on the same order.
	if _current_order == null and (_cancelling_order != null or _awaiting_interruption_cause_order != null):
		var target_cause_order: UnitOrder = _awaiting_interruption_cause_order if _awaiting_interruption_cause_order != null else _cancelling_order
		_transition_seq += 1
		var my_reent_seq: int = _transition_seq
		_pending_transition_seq = 0
		_commit_interruption_cause(target_cause_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
		_order_revision += 1
		var reent_rev: int = _order_revision
		_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
		if _movement != null:
			_movement.stop_movement()
		_set_state(State.IDLE)
		reset_work_visuals()
		if _has_mutation_authority(my_reent_seq, reent_rev) and _current_order == null:
			_publish_control_mode_if_changed()
		if target_cause_order != null and target_cause_order.is_finished():
			_emit_interruption_cause_committed_once(target_cause_order)
		return true

	if _current_order == null:
		_transition_seq += 1
		var my_idle_seq: int = _transition_seq
		_pending_transition_seq = 0
		var idle_rev: int = _order_revision
		_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
		if _movement != null:
			_movement.stop_movement()
		_set_state(State.IDLE)
		reset_work_visuals()
		if _has_mutation_authority(my_idle_seq, idle_rev) and _current_order == null:
			_publish_control_mode_if_changed()
		return true

	# Stage 1: silent reservation via _transition_seq (do NOT increment _order_revision yet).
	_transition_seq += 1
	var my_seq: int = _transition_seq
	_pending_transition_seq = my_seq
	_pending_target_mode = UnitControlState.ControlMode.COMMUNITY_FREE
	_pending_target_origin = UnitOrder.OrderOrigin.NONE

	# Stage 2: cancel active order while _order_revision still belongs to cancelled_order.
	var cancelled_order: UnitOrder = _current_order
	_current_order = null
	_cancelling_order = cancelled_order
	cancelled_order.cancel(_movement, reason)
	if _cancelling_order == cancelled_order:
		_cancelling_order = null

	if not cancelled_order.is_finished():
		if _transition_seq == my_seq:
			if _current_order == null:
				_current_order = cancelled_order
			if _pending_transition_seq == my_seq:
				_pending_transition_seq = 0
		_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
		return false

	var committed_rev: int = _order_revision
	if _transition_seq == my_seq:
		_commit_interruption_cause(cancelled_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
		_order_revision += 1
		committed_rev = _order_revision
		_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
		if _pending_transition_seq == my_seq:
			_pending_transition_seq = 0
		if _movement != null:
			_movement.stop_movement()
		_set_state(State.IDLE)
		reset_work_visuals()
		if _has_mutation_authority(my_seq, committed_rev) and _current_order == null:
			_publish_control_mode_if_changed()
	elif _pending_transition_seq == my_seq:
		_pending_transition_seq = 0

	# Always deliver legitimate single-shot order_finished even if a callback installed a successor.
	_emit_order_finished_once(cancelled_order)
	if cancelled_order.get_interruption_cause() == UnitOrder.InterruptionCause.NONE:
		_commit_interruption_cause(cancelled_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
	_emit_interruption_cause_committed_once(cancelled_order)
	return _transition_seq == my_seq and _order_revision == committed_rev


func _install_admitted_order(
	order: UnitOrder,
	origin: UnitOrder.OrderOrigin,
	recovery_ctx: Dictionary = {},
	dispatch_lease: CommunityWorkBoard.DispatchLease = null
) -> bool:
	var target_mode: UnitControlState.ControlMode = UnitControlState.mode_for_origin(origin)

	# Stage 1: silent internal reservation via _transition_seq (never bump _order_revision before cancel succeeds).
	_transition_seq += 1
	var my_seq: int = _transition_seq
	_pending_transition_seq = my_seq
	_pending_target_mode = target_mode
	_pending_target_origin = origin

	var issued_revision: int = _order_revision
	var cause_target: UnitOrder = null

	# Stage 2: cancel previous active order (while _order_revision still belongs to previous_order).
	if _current_order != null and _current_order.is_active():
		var previous_order: UnitOrder = _current_order
		_current_order = null
		_cancelling_order = previous_order
		_awaiting_interruption_cause_order = previous_order
		previous_order.cancel(_movement, UnitOrder.REASON_REPLACED)
		if _cancelling_order == previous_order:
			_cancelling_order = null

		if not previous_order.is_finished():
			# Stage 2A: refusal preserves _order_revision and all external consumers 100% intact.
			if _awaiting_interruption_cause_order == previous_order:
				_awaiting_interruption_cause_order = null
			if _transition_seq == my_seq:
				if _current_order == null:
					_current_order = previous_order
				if _pending_transition_seq == my_seq:
					_pending_transition_seq = 0
			order.mark_cancelled(UnitOrder.REASON_REPLACED)
			_last_order_rejection_reason = CommandController.REASON_UNIT_TRANSACTION_LOCKED
			return false

		# Check Point 1 (B2-A01): Revalidate permissions/locks/authority immediately after cancel().
		# Do NOT commit PERSONAL_MOVE/PERSONAL_OTHER yet: keep cause uncommitted until Check Point 2 passes.
		var pre_reval_reason: String = ""
		if _transition_seq == my_seq:
			pre_reval_reason = _revalidate_admitted_order_before_install(order, origin, recovery_ctx, dispatch_lease)
			if pre_reval_reason.is_empty():
				_order_revision += 1
				issued_revision = _order_revision
				_control_state._apply_internal(target_mode, origin)
			else:
				_commit_interruption_cause(previous_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
				_order_revision += 1
				issued_revision = _order_revision
				_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
				if _pending_transition_seq == my_seq:
					_pending_transition_seq = 0
				_set_state(State.IDLE)
				if _has_mutation_authority(my_seq, issued_revision) and _current_order == null:
					_publish_control_mode_if_changed()
				_emit_order_finished_once(previous_order)
				_emit_interruption_cause_committed_once(previous_order)
				order.mark_cancelled(UnitOrder.REASON_REPLACED)
				_last_order_rejection_reason = pre_reval_reason
				return false

		_emit_order_finished_once(previous_order)

		if not _has_mutation_authority(my_seq, issued_revision):
			if _pending_transition_seq == my_seq:
				_pending_transition_seq = 0
			if previous_order.get_interruption_cause() == UnitOrder.InterruptionCause.NONE:
				_commit_interruption_cause(previous_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
			_emit_interruption_cause_committed_once(previous_order)
			order.mark_cancelled(UnitOrder.REASON_REPLACED)
			_last_order_rejection_reason = UnitOrder.REASON_REPLACED
			return false

		# Check Point 2 (B2-A01 / B2-R2-A01): Revalidate current permissions, locks, and F01/F02 authority
		# immediately before effective installation. Only after Check Point 2 approves is the replacement
		# interruption cause definitively committed (write-once).
		var post_reval_reason: String = _revalidate_admitted_order_before_install(order, origin, recovery_ctx, dispatch_lease)
		if not post_reval_reason.is_empty():
			if _pending_transition_seq == my_seq:
				_pending_transition_seq = 0
			_commit_interruption_cause(previous_order, UnitOrder.InterruptionCause.ADMIN_CANCEL)
			_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
			_set_state(State.IDLE)
			if _has_mutation_authority(my_seq, issued_revision) and _current_order == null:
				_publish_control_mode_if_changed()
			_emit_interruption_cause_committed_once(previous_order)
			order.mark_cancelled(UnitOrder.REASON_REPLACED)
			_last_order_rejection_reason = post_reval_reason
			return false

		cause_target = previous_order
	else:
		# No active previous order -> commit revision & internal target state directly.
		# If admitted reentrantly during an outer cancel() or order_finished(), this order becomes
		# the definitive interruption cause of the outer awaiting order at Stage 3 entry.
		_order_revision += 1
		issued_revision = _order_revision
		_control_state._apply_internal(target_mode, origin)
		if _awaiting_interruption_cause_order != null:
			cause_target = _awaiting_interruption_cause_order

	# Stage 3: point of no return — commit definitive write-once InterruptionCause, install order, and start().
	if cause_target != null:
		_commit_interruption_cause(cause_target, _interruption_cause_for(order, origin))

	order._set_order_origin(origin)
	if _world_navigation == null and _movement != null:
		_world_navigation = _movement.get_world_navigation()

	_visual_cycle_time = 0.0
	_current_order = order
	_order_state_explicit = false
	order.start(self, _movement, _world_navigation)

	if not _has_mutation_authority(my_seq, issued_revision) or _current_order != order:
		if _pending_transition_seq == my_seq:
			_pending_transition_seq = 0
		if order.is_finished():
			_emit_order_finished_once(order)
		if cause_target != null and cause_target.is_finished():
			_emit_interruption_cause_committed_once(cause_target)
		return false

	# Stage 4: stabilize final state and publish control_mode_changed at most once.
	if _pending_transition_seq == my_seq:
		_pending_transition_seq = 0

	if order.is_finished():
		_current_order = null
		_control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_FREE, UnitOrder.OrderOrigin.NONE)
		_set_state(State.IDLE)
		if _has_mutation_authority(my_seq, issued_revision) and _current_order == null and _pending_transition_seq == 0:
			_publish_control_mode_if_changed()
		_emit_order_finished_once(order)
		if cause_target != null and cause_target.is_finished():
			_emit_interruption_cause_committed_once(cause_target)
		if order.is_succeeded():
			return true
		_last_order_rejection_reason = order.failure_reason
		return false

	if not _order_state_explicit:
		_set_state(State.MOVING)
	if _has_mutation_authority(my_seq, issued_revision) and _current_order == order and _pending_transition_seq == 0:
		_publish_control_mode_if_changed()
	if cause_target != null and cause_target.is_finished():
		_emit_interruption_cause_committed_once(cause_target)
	return true


func _revalidate_admitted_order_before_install(
	order: UnitOrder,
	origin: UnitOrder.OrderOrigin,
	recovery_ctx: Dictionary,
	dispatch_lease: CommunityWorkBoard.DispatchLease
) -> String:
	if _is_exiting_tree or not is_inside_tree() or is_queued_for_deletion():
		return UnitOrder.REASON_UNIT_NOT_IN_TREE
	if _is_reserved_withdrawal_locked():
		return CommandController.REASON_UNIT_TRANSACTION_LOCKED
	if order == null or order.is_finished() or order.status != UnitOrder.Status.PENDING:
		return "order_not_pending"

	match origin:
		UnitOrder.OrderOrigin.PERSONAL:
			return UnitControlPermissions.get_personal_order_rejection_reason_for_order(self, order)
		UnitOrder.OrderOrigin.COMMUNITY:
			if not (order is GatherResourceOrder):
				return "invalid_dispatch_lease"
			if not UnitControlPermissions.can_participate_in_community_work_for_order(self, order):
				return UnitControlPermissions.REASON_AGE_RESTRICTED_TASK
			if dispatch_lease == null:
				return "invalid_dispatch_lease"
			var board: CommunityWorkBoard = dispatch_lease.get_board()
			if board == null or not is_instance_valid(board) or not board.is_inside_tree():
				return "invalid_dispatch_lease"
			if not board.is_dispatch_lease_valid_for_commit(dispatch_lease):
				return "invalid_dispatch_lease"
			return ""
		UnitOrder.OrderOrigin.SYSTEM_RECOVERY:
			if not UnitControlPermissions.can_perform_recovery_order(self):
				return UnitControlPermissions.REASON_AGE_RESTRICTED_TASK
			if not _revalidate_recovery_authority_post_cancel(order, recovery_ctx):
				return "unadmitted_recovery_order"
			return ""
		_:
			return UnitControlPermissions.REASON_INVALID_ORDER


func _revalidate_recovery_authority_post_cancel(order: UnitOrder, recovery_ctx: Dictionary) -> bool:
	if _is_reserved_withdrawal_locked():
		return false
	var rec_order: RecoveryOrder = order as RecoveryOrder
	if rec_order == null:
		return false
	var dispatcher: CancellationRecoveryDispatcher = recovery_ctx.get("dispatcher") as CancellationRecoveryDispatcher
	var explicit: bool = bool(recovery_ctx.get("explicit", false))
	if dispatcher == null or not is_instance_valid(dispatcher) or not dispatcher.is_inside_tree():
		return false
	if not dispatcher.is_admitting_recovery(self, rec_order, explicit):
		return false
	var world: World3D = get_world_3d()
	if world == null or world != recovery_ctx.get("world"):
		return false
	var region_id: StringName = recovery_ctx.get("region_id", &"") as StringName
	var cancel_id: StringName = recovery_ctx.get("cancel_id", &"") as StringName
	if ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, region_id):
		return false
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = CancellationRecoveryTransaction._record(
		world,
		region_id,
		cancel_id
	)
	if record == null or not record.has_unsettled_custody():
		return false
	var id_check: Dictionary = ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(
		world,
		region_id,
		self,
		_carry_load,
		get_tree()
	)
	return bool(id_check.get("ok", false))


func cancel_current_order(reason: String = UnitOrder.REASON_CANCELLED) -> void:
	_perform_administrative_cancel(reason)


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
