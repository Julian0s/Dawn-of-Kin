extends TestCase
## Unit tests for R-03B B2 — ControlMode state machine (C01 unit), UnitControlState,
## UnitOrder.InterruptionCause, UnitOrder.can_cancel_now(), single-shot _finished_notified,
## and F03 admission/cancellation/reentrancy unit invariants.
## Strictly preserves B2/B3 boundary (no PERSONAL_POST_MOVE_WAIT or D-05 timers).

const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")


class UnknownOrderB2 extends UnitOrder:
	func get_order_name() -> String:
		return "UnknownOrderB2"


class BlockingCancelOrderB2 extends UnitOrder:
	## Deterministic MoveOrder-free test order? Note: rejected by personal permissions.
	## Used only to verify UnitOrder base primitives (can_cancel_now, _finished_notified, InterruptionCause).
	var block_cancel: bool = false

	func can_cancel_now() -> bool:
		return not block_cancel

	func start(_u: CharacterBody3D, _m: UnitMovement, _n: WorldNavigation) -> void:
		mark_running()

	func cancel(movement: UnitMovement, reason: String = REASON_CANCELLED) -> void:
		if block_cancel:
			return
		super.cancel(movement, reason)


func _make_def(
	cid: StringName,
	display: String,
	aff: CharacterDefinition.HouseAffiliation,
	orig: CharacterDefinition.FoundingHouseOrigin,
	age: CharacterDefinition.AgeStage
) -> CharacterDefinition:
	var def := CharacterDefinition.new()
	def.character_id = cid
	def.display_name = display
	def.house_affiliation = aff
	def.founding_house_origin = orig
	def.age_stage = age
	return def


func _spawn_unit(def: CharacterDefinition, node_name: String) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = node_name
	u.definition = def
	add_test_child(u)
	return u


func test_c01_unit_control_state_enums_defaults_and_mode_mapping() -> void:
	var cs := UnitControlState.new()
	assert_eq(cs.get_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "Initial ControlMode must be COMMUNITY_FREE")
	assert_eq(cs.get_mode_name(), "COMMUNITY_FREE")
	assert_eq(cs.get_active_origin(), UnitOrder.OrderOrigin.NONE)
	assert_eq(cs.get_last_published_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_true(cs.is_community_free())
	assert_false(cs.is_personal_active())

	# B3 introduces PERSONAL_POST_MOVE_WAIT as the 4th ControlMode while preserving 0..2 ordinals.
	assert_eq(UnitControlState.ControlMode.size(), 4, "B3 exposes the 4 canonical ControlMode states")
	assert_true(UnitControlState.ControlMode.has("PERSONAL_POST_MOVE_WAIT"), "B3 adds PERSONAL_POST_MOVE_WAIT")

	assert_eq(UnitControlState.mode_for_origin(UnitOrder.OrderOrigin.NONE), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(UnitControlState.mode_for_origin(UnitOrder.OrderOrigin.COMMUNITY), UnitControlState.ControlMode.COMMUNITY_WORKING)
	assert_eq(UnitControlState.mode_for_origin(UnitOrder.OrderOrigin.SYSTEM_RECOVERY), UnitControlState.ControlMode.COMMUNITY_WORKING)
	assert_eq(UnitControlState.mode_for_origin(UnitOrder.OrderOrigin.PERSONAL), UnitControlState.ControlMode.PERSONAL_ACTIVE)


func test_f03_unit_order_primitives_can_cancel_notified_and_interruption_cause() -> void:
	var base := UnitOrder.new()
	assert_true(base.can_cancel_now(), "Default UnitOrder.can_cancel_now() must be true")
	assert_false(base.was_finished_notified(), "Fresh order must not be marked notified")
	assert_eq(base.get_interruption_cause(), UnitOrder.InterruptionCause.NONE)

	base.mark_finished_notified()
	assert_true(base.was_finished_notified())

	# InterruptionCause is write-once when non-NONE: obsolete outer transitions cannot overwrite it.
	base.set_interruption_cause(UnitOrder.InterruptionCause.PERSONAL_OTHER)
	assert_eq(base.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_OTHER)
	base.set_interruption_cause(UnitOrder.InterruptionCause.PERSONAL_MOVE)
	assert_eq(base.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_OTHER, "Committed InterruptionCause must be immutable")
	base.set_interruption_cause(UnitOrder.InterruptionCause.ADMIN_CANCEL)
	assert_eq(base.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_OTHER)
	base.set_interruption_cause(UnitOrder.InterruptionCause.NONE)
	assert_eq(base.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_OTHER)

	# Concrete order can_cancel_now() checks (pure, zero side effects).
	var move := MoveOrder.new(Vector3.ZERO)
	assert_true(move.can_cancel_now())

	var deliver := DeliverToCampOrder.new(null, null, true, &"reg")
	deliver.mark_running()
	assert_true(deliver.can_cancel_now())
	deliver._selective_session.is_executing = true
	assert_false(deliver.can_cancel_now(), "DeliverToCampOrder must report can_cancel_now()==false during selective transfer")
	deliver._selective_session.is_executing = false
	assert_true(deliver.can_cancel_now())

	var construct := ConstructOrder.new(null, null, false, true, false)
	construct._replan_requested = false
	assert_true(construct.can_cancel_now())
	construct._provenance_transfer.is_executing = true
	assert_false(construct.can_cancel_now(), "ConstructOrder.can_cancel_now() must mirror is_transfer_executing_readonly()")
	assert_false(construct._replan_requested, "ConstructOrder.can_cancel_now() MUST be pure and NEVER mutate _replan_requested")
	construct._provenance_transfer.is_executing = false
	assert_true(construct.can_cancel_now())

	var gather := GatherResourceOrder.new(null, null, null, -1.0, -1.0, true, &"reg")
	gather.mark_running()
	assert_true(gather.can_cancel_now())
	var gs := GatherTransferSession.new()
	gs.is_executing = true
	gather._active_gather_session = gs
	assert_false(gather.can_cancel_now(), "GatherResourceOrder.can_cancel_now() must return false during active provenance session")
	gather._active_gather_session = null
	assert_true(gather.can_cancel_now())

	var rec := RecoveryOrder.new(&"c1", &"reg", null, null, self)
	rec.mark_running()
	assert_true(rec.can_cancel_now())
	rec._delegate = deliver
	deliver._selective_session.is_executing = true
	assert_false(rec.can_cancel_now(), "RecoveryOrder.can_cancel_now() must respect active selective delegate transfer")
	deliver._selective_session.is_executing = false
	assert_true(rec.can_cancel_now())


func test_c01_unit_initial_state_rejection_t0_and_sync_failure_no_spurious_signal() -> void:
	var founder := _spawn_unit(LEADER_A_DEF, "FounderU")
	var common := _spawn_unit(
		_make_def(&"common_u", "Common U", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.ADULT),
		"CommonU"
	)
	await wait_process_frames(1)

	assert_eq(founder.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(founder.get_control_mode_name(), "COMMUNITY_FREE")
	assert_eq(founder.get_active_order_origin(), UnitOrder.OrderOrigin.NONE)
	assert_false(founder.has_pending_control_transition())
	assert_true(founder.is_community_dispatch_eligible())

	var mode_events: Array[Dictionary] = []
	founder.control_mode_changed.connect(func(n: UnitControlState.ControlMode, p: UnitControlState.ControlMode) -> void:
		mode_events.append({"new": n, "prev": p})
	)
	var fin_events: Array[UnitOrder] = []
	founder.order_finished.connect(func(o: UnitOrder) -> void:
		fin_events.append(o)
	)

	# T0: rejected unknown personal order -> zero revision bump, zero signal, zero order_finished.
	var rev0: int = founder.get_order_revision()
	var unk := UnknownOrderB2.new()
	assert_false(founder.issue_personal_order(unk))
	assert_eq(founder.get_last_order_rejection_reason(), UnitControlPermissions.REASON_UNSUPPORTED_PERSONAL_ORDER)
	assert_eq(founder.get_order_revision(), rev0)
	assert_eq(founder.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(mode_events.size(), 0)
	assert_eq(fin_events.size(), 0, "Rejected unadmitted order must NOT emit order_finished")
	assert_false(unk.was_finished_notified())

	# T0: rejected personal order on COMMUNITY unit.
	var common_modes: Array[Dictionary] = []
	common.control_mode_changed.connect(func(n: UnitControlState.ControlMode, p: UnitControlState.ControlMode) -> void:
		common_modes.append({"new": n, "prev": p})
	)
	assert_false(common.issue_personal_order(MoveOrder.new(Vector3.ONE)))
	assert_eq(common.get_last_order_rejection_reason(), UnitControlPermissions.REASON_PERSONAL_CONTROL_DENIED)
	assert_eq(common.get_order_revision(), 0)
	assert_eq(common.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(common_modes.size(), 0)

	# Synchronous failure inside start() (no nav configured) -> returns false, stabilizes COMMUNITY_FREE,
	# ZERO spurious transient PERSONAL_ACTIVE control_mode_changed, exactly ONE order_finished, InterruptionCause.NONE.
	var fail_move := MoveOrder.new(Vector3(3.0, 0.0, 3.0))
	assert_false(founder.issue_personal_order(fail_move))
	assert_eq(fail_move.status, UnitOrder.Status.FAILED)
	assert_eq(founder.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(founder.get_active_order_origin(), UnitOrder.OrderOrigin.NONE)
	assert_false(founder.has_pending_control_transition())
	assert_eq(mode_events.size(), 0, "Synchronous start() failure from COMMUNITY_FREE must NOT emit transient PERSONAL_ACTIVE signal")
	assert_eq(fin_events.size(), 1, "Admitted order failing synchronously in start() must emit order_finished exactly once")
	assert_eq(fin_events[0], fail_move)
	assert_true(fail_move.was_finished_notified())
	assert_eq(fail_move.get_interruption_cause(), UnitOrder.InterruptionCause.NONE)

	# issue_order(null) and cancel_current_order() on already idle unit -> clean, no spurious signals.
	var rev_before_null: int = founder.get_order_revision()
	assert_true(founder.issue_order(null))
	assert_eq(founder.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(mode_events.size(), 0)
	assert_eq(fin_events.size(), 1)
	founder.cancel_current_order()
	assert_eq(founder.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(mode_events.size(), 0)
	assert_eq(fin_events.size(), 1)
	assert_true(founder.get_order_revision() >= rev_before_null)

	# Admission rejected after unit exits tree (_exit_tree invalidation).
	founder.get_parent().remove_child(founder)
	assert_false(founder.issue_personal_order(MoveOrder.new(Vector3(1.0, 0.0, 1.0))))
	assert_false(founder.is_community_dispatch_eligible())
	founder.queue_free()
