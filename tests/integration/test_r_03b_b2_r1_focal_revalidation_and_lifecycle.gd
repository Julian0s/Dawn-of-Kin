extends TestCase
## Focal adversarial tests for R-03B B2-R1:
## - B2-A01 (A01-R01..A01-R05): Post-callback permission, age, lock & recovery authority revalidation
## - B2-A02 (A02-R01..A02-R04): Terminal notification invariant & transaction-safe tree removal + D0-A04
## - B2-A03 (A03-R01..A03-R04): Order-internal ownership after synchronous callbacks & order-owned claims/slots

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const Audit := preload("res://tests/framework/regional_conservation_audit.gd")


func before_each() -> void:
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0


func _boot_isolated_main(use_provenance: bool = true) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(320, 180)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_test_child(vp)

	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = use_provenance
	main.automatic_cancellation_recovery = true
	main.use_d2_2_hud = false
	vp.add_child(main)
	await wait_process_frames(2)
	await wait_physics_frames(2)

	var nav: WorldNavigation = main.get_test_map().get_navigation()
	for _i: int in range(360):
		if nav.is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(nav.is_navigation_ready(), "Navigation must be ready in isolated MainScene")

	return {
		"vp": vp,
		"main": main,
		"nav": nav,
		"board": main.get_community_work_board(),
		"dispatcher": main.get_community_task_dispatcher(),
		"cmd": main.get_command_controller(),
		"inv": main.get_settlement_inventory(),
		"camp": main.get_camp_storage_zone(),
		"cm": main.get_construction_manager(),
		"overlay": main.get_placement_test_overlay(),
		"leader_a": main.get_node("Units/LeaderA") as Unit,
		"leader_b": main.get_node("Units/LeaderB") as Unit,
		"region_id": main.get_construction_manager().get_region_id(),
	}


func _teardown_isolated_main(ctx: Dictionary) -> void:
	var main: MainScene = ctx.get("main") as MainScene
	var vp: SubViewport = ctx.get("vp") as SubViewport
	if main != null and is_instance_valid(main):
		main.request_controlled_teardown()
	if vp != null and is_instance_valid(vp):
		if vp.get_parent() != null:
			vp.get_parent().remove_child(vp)
		vp.queue_free()
	await wait_process_frames(2)


func _find_source(main: MainScene, sid: StringName) -> ResourceSource:
	for s: ResourceSource in main.get_test_map().get_resource_sources():
		if s.get_source_id() == sid:
			return s
	return null


func _until(predicate: Callable, max_frames: int = 1800) -> bool:
	for _i: int in range(max_frames):
		if predicate.call():
			return true
		await wait_physics_frames(1)
	return predicate.call()


func _make_def(
	cid: StringName,
	display: String,
	aff: CharacterDefinition.HouseAffiliation,
	orig: CharacterDefinition.FoundingHouseOrigin,
	age: CharacterDefinition.AgeStage
) -> CharacterDefinition:
	var d := CharacterDefinition.new()
	d.character_id = cid
	d.display_name = display
	d.house_affiliation = aff
	d.founding_house_origin = orig
	d.age_stage = age
	return d


# ==============================================================================
# B2-A01: Post-callback revalidation of permissions, age, locks, recovery & successors
# ==============================================================================
func test_b2_a01_revalidation_after_callbacks_personal_and_recovery() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var tree: ResourceSource = _find_source(main, &"wood_tree_01")
	var rock: ResourceSource = _find_source(main, &"stone_rock_01")
	var orig_def_a: CharacterDefinition = leader_a.get_definition()
	var region_id: StringName = ctx["region_id"] as StringName

	# --- A01-R01: Loss of FOUNDING_HOUSE affiliation during order_finished ---
	var mv_prev_1 := MoveOrder.new(Vector3(-6.0, 0.0, -6.0))
	assert_true(leader_a.issue_personal_order(mv_prev_1))
	var fin_seen_1: Array[UnitOrder] = []
	var comm_def := _make_def(&"leader_a", "Demoted", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.ADULT)
	var on_fin_1 := func(o: UnitOrder) -> void:
		fin_seen_1.append(o)
		if o == mv_prev_1:
			leader_a.definition = comm_def
	leader_a.order_finished.connect(on_fin_1)
	var mv_stale_1 := MoveOrder.new(Vector3(4.0, 0.0, 4.0))
	var ok_1: bool = leader_a.issue_personal_order(mv_stale_1)
	leader_a.order_finished.disconnect(on_fin_1)

	assert_false(ok_1, "A01-R01: personal order MUST be rejected when affiliation downgraded to COMMUNITY in order_finished")
	assert_null(leader_a.get_current_order(), "A01-R01: no stale personal order installed and previous order not resurrected")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.NONE)
	assert_false(leader_a.has_pending_control_transition(), "A01-R01: _pending_transition_seq must not leak")
	assert_eq(leader_a.get_last_order_rejection_reason(), UnitControlPermissions.REASON_PERSONAL_CONTROL_DENIED)
	assert_eq(fin_seen_1.size(), 1, "A01-R01: only previously active order emitted order_finished (not rejected order)")
	assert_eq(fin_seen_1[0], mv_prev_1)
	assert_false(mv_stale_1.was_finished_notified())

	# Restore adult founder definition
	leader_a.definition = orig_def_a

	# --- A01-R02a: Age downgrade ADULT -> CHILD during order_finished when replacing with GatherResourceOrder(WOOD) ---
	var mv_prev_2 := MoveOrder.new(Vector3(-5.0, 0.0, -5.0))
	assert_true(leader_a.issue_personal_order(mv_prev_2))
	var child_def := _make_def(&"leader_a", "ChildA", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.CHILD)
	var on_fin_2 := func(o: UnitOrder) -> void:
		if o == mv_prev_2:
			leader_a.definition = child_def
	leader_a.order_finished.connect(on_fin_2)
	var wood_stale := GatherResourceOrder.new(tree, camp, inv, -1.0, -1.0, true, region_id)
	var ok_2: bool = leader_a.issue_personal_order(wood_stale)
	leader_a.order_finished.disconnect(on_fin_2)

	assert_false(ok_2, "A01-R02: CHILD must NOT receive GatherResourceOrder(WOOD) after downgrade in order_finished")
	assert_null(leader_a.get_current_order())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_false(leader_a.has_pending_control_transition())
	assert_eq(leader_a.get_last_order_rejection_reason(), UnitControlPermissions.REASON_AGE_RESTRICTED_TASK)

	# --- A01-R02b: Age downgrade ADULT -> BABY inside previous_order.cancel() (worker_slot_released) ->
	# rejected MoveOrder MUST NOT stamp InterruptionCause.PERSONAL_MOVE! ---
	leader_a.definition = orig_def_a
	var g_prev := GatherResourceOrder.new(rock, camp, inv, -1.0, -1.0, true, region_id)
	assert_true(leader_a.issue_personal_order(g_prev))
	var baby_def := _make_def(&"leader_a", "BabyA", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.BABY)
	var baby_downgraded := [false]
	var on_slot_baby := func(_src: ResourceSource) -> void:
		if not baby_downgraded[0]:
			baby_downgraded[0] = true
			leader_a.definition = baby_def
	rock.worker_slot_released.connect(on_slot_baby)
	var mv_rejected_baby := MoveOrder.new(Vector3(3.0, 0.0, 3.0))
	var ok_baby: bool = leader_a.issue_personal_order(mv_rejected_baby)
	rock.worker_slot_released.disconnect(on_slot_baby)

	assert_true(baby_downgraded[0], "A01-R02b: callback inside cancel() fired")
	assert_false(ok_baby, "A01-R02b: BABY must NOT receive MoveOrder after downgrade during cancel()")
	assert_null(leader_a.get_current_order())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_false(leader_a.has_pending_control_transition())
	assert_ne(g_prev.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_MOVE, "A01-R02b: rejected MoveOrder must NOT stamp PERSONAL_MOVE")
	assert_eq(g_prev.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL)

	# --- A01-R03: Supervening economic transaction lock during order_finished ---
	leader_a.definition = orig_def_a
	var mv_prev_3 := MoveOrder.new(Vector3(-4.0, 0.0, -4.0))
	assert_true(leader_a.issue_personal_order(mv_prev_3))
	var on_fin_3 := func(o: UnitOrder) -> void:
		if o == mv_prev_3:
			leader_a.get_carry_load()._coordinator_transaction_locked = true
	leader_a.order_finished.connect(on_fin_3)
	var mv_locked := MoveOrder.new(Vector3(5.0, 0.0, 5.0))
	var ok_3: bool = leader_a.issue_personal_order(mv_locked)
	leader_a.order_finished.disconnect(on_fin_3)
	leader_a.get_carry_load()._coordinator_transaction_locked = false

	assert_false(ok_3, "A01-R03: supervening transaction lock during order_finished must reject installation")
	assert_null(leader_a.get_current_order())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_false(leader_a.has_pending_control_transition())
	assert_eq(leader_a.get_last_order_rejection_reason(), CommandController.REASON_UNIT_TRANSACTION_LOCKED)

	# --- A01-R04: Recovery T1b authority invalidated during order_finished (age -> CHILD) ---
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site_res := cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site_res.get("ok", false)))
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	assert_true(cmd.command_units_to_site(site, [leader_a]))
	assert_true(await _until(func() -> bool: return site.get_delivered_buffer_amount(&"wood") > 0 or site._work_progress_usec > 0, 3600))
	var c_order := leader_a.get_current_order() as ConstructOrder
	assert_not_null(c_order)
	var cancelled := ReservedWithdrawalCoordinator.execute_site_cancellation(site, &"a01_r04_cancel")
	assert_true(cancelled.ok)
	var cancel_id: StringName = cancelled.receipt.cancel_id
	var rec_downgraded := [false]
	var on_fin_rec := func(o: UnitOrder) -> void:
		if o == c_order and not rec_downgraded[0]:
			rec_downgraded[0] = true
			leader_a.definition = child_def
	leader_a.order_finished.connect(on_fin_rec)
	cm._recovery_dispatcher._flush()
	leader_a.order_finished.disconnect(on_fin_rec)

	assert_true(rec_downgraded[0], "A01-R04: callback during T1b order_finished fired")
	assert_null(leader_a.get_current_order(), "A01-R04: CHILD must NOT receive RecoveryOrder after downgrade during T1b")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_false(leader_a.has_pending_control_transition())

	# Restore adult founder and settle custody cleanly via explicit recovery
	leader_a.definition = orig_def_a
	var exp_res := cm.assign_cancellation_recovery(cancel_id, [leader_a])
	assert_true(bool(exp_res.get("ok", false)))
	var record := CancellationRecoveryTransaction._record(main.get_world_3d(), region_id, cancel_id)
	assert_true(await _until(func() -> bool: return record.state == ConstructionCancellationMath.State.SETTLED, 4800))
	await _until(func() -> bool: return leader_a.get_current_order() == null, 120)

	# --- A01-R05: Valid successor installed during order_finished preserved intact ---
	var mv_prev_5 := MoveOrder.new(Vector3(-3.0, 0.0, -3.0))
	assert_true(leader_b.issue_personal_order(mv_prev_5))
	var succ_5 := MoveOrder.new(Vector3(6.0, 0.0, -4.0))
	var on_fin_5 := func(o: UnitOrder) -> void:
		if o == mv_prev_5:
			leader_b.issue_personal_order(succ_5)
	leader_b.order_finished.connect(on_fin_5)
	var outer_5 := MoveOrder.new(Vector3(-8.0, 0.0, 8.0))
	var ok_5: bool = leader_b.issue_personal_order(outer_5)
	leader_b.order_finished.disconnect(on_fin_5)

	assert_false(ok_5)
	assert_eq(leader_b.get_current_order(), succ_5, "A01-R05: legitimate successor preserved intact")
	assert_eq(leader_b.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(leader_b.get_movement().get_move_state(), UnitMovement.MoveState.MOVING)
	assert_false(leader_b.has_pending_control_transition())

	leader_b.cancel_current_order()
	await _teardown_isolated_main(ctx)


# ==============================================================================
# B2-A02: Terminal notification invariant & transaction-safe tree removal + D0-A04
# ==============================================================================
func test_b2_a02_exit_tree_terminal_notification_and_conservation() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var ctrl: TemporaryTestWorkersController = (ctx["overlay"] as PlacementTestOverlay).get_temporary_workers_controller()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var rock: ResourceSource = _find_source(main, &"stone_rock_01")
	var world: World3D = main.get_world_3d()
	var region_id: StringName = ctx["region_id"] as StringName

	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var snap_wood_before := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_before := Audit.capture(get_tree(), world, region_id, &"stone", inv)
	assert_true(bool(snap_wood_before.get("ok", false)))
	assert_true(bool(snap_stone_before.get("ok", false)))

	# --- A02-R01: GatherResourceOrder with active transfer session (can_cancel_now()==false) ---
	var spawn_res := ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_res.get("ok", false)))
	var w3: Unit = main.get_node("Units/Worker3") as Unit
	var w4: Unit = main.get_node("Units/Worker4") as Unit
	leader_a.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	leader_b.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -8.0)))
	w4.global_position = Vector3(-14.0, 0.0, -10.0)
	w3.global_position = rock.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg := board.register_gather_task(rock)
	var task: WorkTask = reg["task"] as WorkTask
	disp._flush_dispatch()
	var g_order := w3.get_current_order() as GatherResourceOrder
	assert_not_null(g_order)

	var gs := GatherTransferSession.new()
	gs.is_executing = true
	g_order._active_gather_session = gs
	assert_false(g_order.can_cancel_now())

	# Controlled removal MUST refuse while transfer is active!
	var rem_blocked := ctrl.remove_temporary_workers_safely()
	assert_false(bool(rem_blocked.get("ok", false)), "A02-R01: controlled removal must refuse during active gather transfer")

	# Forced tree exit while cancel is refused MUST NOT emit false order_finished or bump revision!
	var w3_fin_events: Array[UnitOrder] = []
	var on_w3_fin := func(o: UnitOrder) -> void: w3_fin_events.append(o)
	w3.order_finished.connect(on_w3_fin)
	var w3_rev_before: int = w3.get_order_revision()
	var w3_parent: Node = w3.get_parent()
	w3_parent.remove_child(w3)

	assert_true(g_order.is_active(), "A02-R01: protected gather order stayed active")
	assert_eq(w3_fin_events.size(), 0, "A02-R01: MUST NOT emit false order_finished for still-active order on _exit_tree")
	assert_false(g_order.was_finished_notified(), "A02-R01: MUST NOT mark _finished_notified on still-active order")
	assert_eq(w3.get_order_revision(), w3_rev_before, "A02-R01: MUST NOT advance _order_revision when cancel refused on _exit_tree")
	assert_eq(w3.get_current_order(), g_order, "A02-R01: still-active order remains owned, never orphaned")

	# Re-attach, release transfer lock, verify clean cancellation and controlled removal.
	w3_parent.add_child(w3)
	g_order._active_gather_session = null
	w3.cancel_current_order()
	w3.order_finished.disconnect(on_w3_fin)
	assert_eq(w3_fin_events.size(), 1, "A02-R01: after unlock and cancel, order_finished fires exactly once")
	assert_true(g_order.is_finished())
	board.close_task(task, WorkTask.State.CANCELLED, "cleanup_a02_r01")
	var rem_ok := ctrl.remove_temporary_workers_safely()
	assert_true(bool(rem_ok.get("ok", false)))
	leader_a.cancel_current_order()
	leader_b.cancel_current_order()

	# --- A02-R02: ConstructOrder with active provenance transfer -> forced _exit_tree preserves revision, worker, claim & materials ---
	var site_res := cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site_res.get("ok", false)))
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	assert_true(cmd.command_units_to_site(site, [leader_a]))
	assert_true(await _until(func() -> bool: return site.get_delivered_buffer_amount(&"wood") > 0 or site._work_progress_usec > 0, 3600))
	var c_order := leader_a.get_current_order() as ConstructOrder
	assert_not_null(c_order)
	var c_rev_before: int = leader_a.get_order_revision()
	var c_fin_events: Array[UnitOrder] = []
	var on_c_fin := func(o: UnitOrder) -> void: c_fin_events.append(o)
	leader_a.order_finished.connect(on_c_fin)
	c_order._provenance_transfer.is_executing = true
	var la_parent: Node = leader_a.get_parent()
	la_parent.remove_child(leader_a)

	assert_true(c_order.is_active(), "A02-R02: protected ConstructOrder stayed active")
	assert_eq(c_fin_events.size(), 0, "A02-R02: ZERO false order_finished on _exit_tree")
	assert_false(c_order.was_finished_notified())
	assert_eq(leader_a.get_order_revision(), c_rev_before, "A02-R02: revision preserved")
	assert_eq(leader_a.get_current_order(), c_order)
	assert_true(site._assigned_workers.has(leader_a.get_instance_id()), "A02-R02: _exit_tree did NOT unregister protected worker from site")

	la_parent.add_child(leader_a)
	assert_ne(site.get_worker_role(leader_a), ConstructionSite.WorkerRole.UNASSIGNED, "A02-R02: site worker registration intact after re-attach")
	c_order._provenance_transfer.is_executing = false
	leader_a.order_finished.disconnect(on_c_fin)

	# --- A02-R03: RecoveryOrder with locked custody -> forced _exit_tree produces ZERO false finish & does NOT settle custody ---
	var cancelled := ReservedWithdrawalCoordinator.execute_site_cancellation(site, &"a02_r03_cancel")
	assert_true(cancelled.ok)
	var cancel_id: StringName = cancelled.receipt.cancel_id
	cm._recovery_dispatcher._flush()
	var rec_order := leader_a.get_current_order() as RecoveryOrder
	assert_not_null(rec_order)
	var rec_record := CancellationRecoveryTransaction._record(world, region_id, cancel_id)
	assert_true(rec_record.has_unsettled_custody())

	var r_fin_events: Array[UnitOrder] = []
	var on_r_fin := func(o: UnitOrder) -> void: r_fin_events.append(o)
	leader_a.order_finished.connect(on_r_fin)
	var r_rev_before: int = leader_a.get_order_revision()
	leader_a.get_carry_load()._coordinator_transaction_locked = true
	la_parent.remove_child(leader_a)

	assert_true(rec_order.is_active(), "A02-R03: locked RecoveryOrder stayed active")
	assert_eq(r_fin_events.size(), 0, "A02-R03: ZERO false order_finished on locked RecoveryOrder")
	assert_false(rec_order.was_finished_notified())
	assert_eq(leader_a.get_order_revision(), r_rev_before)
	assert_true(rec_record.has_unsettled_custody(), "A02-R03: custody NOT artificially settled")

	la_parent.add_child(leader_a)
	leader_a.get_carry_load()._coordinator_transaction_locked = false
	leader_a.order_finished.disconnect(on_r_fin)
	assert_true(await _until(func() -> bool: return rec_record.state == ConstructionCancellationMath.State.SETTLED, 4800), "A02-R03: recovery settles cleanly after unlock")
	await _until(func() -> bool: return leader_a.get_current_order() == null, 120)

	# --- A02-R04: Normal cancellable order removed -> terminal, notified once, no re-admission during _exit_tree ---
	var mv_exit := MoveOrder.new(Vector3(-8.0, 0.0, -8.0))
	assert_true(leader_b.issue_personal_order(mv_exit))
	var b_fin_count := [0]
	var b_readmit := [true]
	leader_b.order_finished.connect(func(o: UnitOrder) -> void:
		if o == mv_exit:
			b_fin_count[0] += 1
			b_readmit[0] = leader_b.issue_personal_order(MoveOrder.new(Vector3.ZERO))
	)
	var lb_parent: Node = leader_b.get_parent()
	lb_parent.remove_child(leader_b)
	assert_true(mv_exit.is_finished(), "A02-R04: cancellable order reaches terminal state")
	assert_eq(b_fin_count[0], 1, "A02-R04: notified exactly once")
	assert_false(b_readmit[0], "A02-R04: re-admission blocked during _exit_tree")
	lb_parent.add_child(leader_b)

	# Regional conservation check (D0-A04) across all A02 scenarios!
	var snap_wood_after := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_after := Audit.capture(get_tree(), world, region_id, &"stone", inv)
	assert_true(bool(Audit.verify_conservation(snap_wood_before, snap_wood_after).get("ok", false)), "A02: D0-A04 wood conservation")
	assert_true(bool(Audit.verify_conservation(snap_stone_before, snap_stone_after).get("ok", false)), "A02: D0-A04 stone conservation")
	assert_not_null(camp)
	await _teardown_isolated_main(ctx)


# ==============================================================================
# B2-A03: Order-internal ownership after synchronous callbacks & order-owned claims/slots
# ==============================================================================
func test_b2_a03_order_internal_ownership_and_claim_protection() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var rock: ResourceSource = _find_source(main, &"stone_rock_01")
	var world: World3D = main.get_world_3d()
	var region_id: StringName = ctx["region_id"] as StringName

	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var snap_wood_before := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_before := Audit.capture(get_tree(), world, region_id, &"stone", inv)

	var site_res := cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site_res.get("ok", false)))
	var site: ConstructionSite = site_res["site"] as ConstructionSite

	# --- A03-R01: ConstructOrder.start() replaced synchronously during site.register_worker() -> workers_changed ---
	var succ_mv := MoveOrder.new(Vector3(7.0, 0.0, -6.0))
	var cb1_fired := [false]
	var on_workers_1 := func(_s: ConstructionSite) -> void:
		if not cb1_fired[0]:
			cb1_fired[0] = true
			leader_a.issue_personal_order(succ_mv)
	site.workers_changed.connect(on_workers_1)
	var stale_c1 := ConstructOrder.new(site, camp, false, true, false)
	var c1_ok: bool = leader_a.issue_personal_order(stale_c1)
	site.workers_changed.disconnect(on_workers_1)

	assert_true(cb1_fired[0], "A03-R01: workers_changed callback fired synchronously inside ConstructOrder.start()")
	assert_false(c1_ok, "A03-R01: superseded ConstructOrder returns false")
	assert_eq(leader_a.get_current_order(), succ_mv, "A03-R01: MoveOrder successor owns unit")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(leader_a.get_movement().get_move_state(), UnitMovement.MoveState.MOVING, "A03-R01: successor movement NOT overwritten by stale _advance_by_role()")
	assert_lt(leader_a.get_movement().get_target_position().distance_to(succ_mv.resolved_target), 0.25, "A03-R01: movement target still belongs to MoveOrder successor")
	assert_false(stale_c1._site_signals_bound, "A03-R01: stale ConstructOrder must NOT leak site signal bindings after replacement")
	assert_false(site.workers_changed.is_connected(stale_c1._on_site_workers_changed), "A03-R01: no leaked workers_changed handler")
	assert_eq(site.get_worker_role(leader_a), ConstructionSite.WorkerRole.UNASSIGNED, "A03-R01: stale worker registration cleaned")
	leader_a.cancel_current_order()

	# --- A03-R02: Order-owned pickup claim & unregister_worker order-identity protection on SAME site ---
	var c_old := ConstructOrder.new(site, camp, false, true, false)
	var c_new := ConstructOrder.new(site, camp, false, true, false)
	assert_true(leader_a.issue_personal_order(c_old))
	# Acquire a real pickup claim for c_old, then replace with c_new on SAME site!
	var c_new_installed := [false]
	var c_new_claimed := [0]
	var on_workers_2 := func(_s: ConstructionSite) -> void:
		if not c_new_installed[0]:
			c_new_installed[0] = true
			leader_a.issue_personal_order(c_new)
			# Ensure c_new holds a pickup claim on this exact site
			c_new_claimed[0] = site.claim_pickup(leader_a, 999991, &"wood", 2, 10, c_new)
	site.workers_changed.connect(on_workers_2)
	# Trigger c_old finish via _finish_failed -> site.unregister_worker(leader_a, c_old) fires workers_changed!
	# Even simpler: directly verify site.unregister_worker(leader_a, c_old) and release_pickup_claim(leader_a, c_old)
	# do NOT erase c_new's registration or c_new's claim!
	site.workers_changed.disconnect(on_workers_2)
	assert_true(leader_a.issue_personal_order(c_new))
	var claimed_new: int = site.claim_pickup(leader_a, 999991, &"wood", 2, 10, c_new)
	assert_eq(claimed_new, 2, "A03-R02: successor ConstructOrder acquired pickup claim on same site")
	var c_new_rev: int = leader_a.get_order_revision()
	# Simulate stale c_old attempting cleanup after c_new already took over the SAME site!
	site.release_pickup_claim(leader_a, c_old)
	site.unregister_worker(leader_a, c_old)
	assert_eq(site.get_pending_pickup_amount(999991, &"wood"), 2, "A03-R02: stale old order MUST NOT wipe successor's pickup claim")
	assert_ne(site.get_worker_role(leader_a), ConstructionSite.WorkerRole.UNASSIGNED, "A03-R02: stale old order MUST NOT unregister successor worker")
	assert_eq(leader_a.get_current_order(), c_new)
	assert_eq(leader_a.get_order_revision(), c_new_rev)

	# Also verify finish callback installing MoveOrder successor does NOT stop successor's movement!
	var finish_succ := MoveOrder.new(Vector3(6.0, 0.0, 4.0))
	var fin_cb_fired := [false]
	var on_workers_fin := func(_s: ConstructionSite) -> void:
		if not fin_cb_fired[0]:
			fin_cb_fired[0] = true
			leader_a.issue_personal_order(finish_succ)
	site.workers_changed.connect(on_workers_fin)
	c_new._finish_failed("a03_r02_test_finish")
	site.workers_changed.disconnect(on_workers_fin)
	assert_true(fin_cb_fired[0])
	assert_eq(leader_a.get_current_order(), finish_succ, "A03-R02: MoveOrder installed during ConstructOrder finish preserved")
	assert_eq(leader_a.get_movement().get_move_state(), UnitMovement.MoveState.MOVING, "A03-R02: finish cleanup MUST NOT stop successor movement")
	leader_a.cancel_current_order()

	# --- A03-R03: GatherResourceOrder replaced during state_changed(MOVING) inside start() ---
	var gather_succ := MoveOrder.new(Vector3(-8.0, 0.0, 6.0))
	var g_cb_fired := [false]
	var on_g_state := func(ns: Unit.State, _ps: Unit.State) -> void:
		if ns == Unit.State.MOVING and not g_cb_fired[0]:
			g_cb_fired[0] = true
			leader_b.issue_personal_order(gather_succ)
	leader_b.state_changed.connect(on_g_state)
	var stale_gather := GatherResourceOrder.new(rock, camp, inv, -1.0, -1.0, true, region_id)
	var g_ok: bool = leader_b.issue_personal_order(stale_gather)
	leader_b.state_changed.disconnect(on_g_state)
	assert_true(g_cb_fired[0])
	assert_false(g_ok)
	assert_eq(leader_b.get_current_order(), gather_succ, "A03-R03: successor preserved during GatherResourceOrder.start()")
	assert_eq(leader_b.get_movement().get_move_state(), UnitMovement.MoveState.MOVING)
	assert_lt(leader_b.get_movement().get_target_position().distance_to(gather_succ.resolved_target), 0.25)
	leader_b.cancel_current_order()

	# --- A03-R04: DeliverToCampOrder & RecoveryOrder state_changed callback installing successor ---
	# Subcase 4a: Legacy DeliverToCampOrder standing on camp -> state_changed(TRANSPORTING) installs MoveOrder successor ->
	# stale DeliverToCampOrder MUST NOT stop successor movement or execute delivery!
	var ctx_leg := await _boot_isolated_main(false)
	var la_leg: Unit = ctx_leg["leader_a"] as Unit
	var camp_leg: CampStorageZone = ctx_leg["camp"] as CampStorageZone
	var inv_leg: SettlementInventory = ctx_leg["inv"] as SettlementInventory
	assert_true(la_leg.get_carry_load().add_units(MainScene.WOOD_DEFINITION, 4))
	la_leg.global_position = camp_leg.global_position
	var del_succ := MoveOrder.new(Vector3(-8.0, 0.0, -6.0))
	var del_cb_fired := [false]
	var on_del_state := func(ns: Unit.State, _ps: Unit.State) -> void:
		if ns == Unit.State.TRANSPORTING and not del_cb_fired[0]:
			del_cb_fired[0] = true
			la_leg.issue_personal_order(del_succ)
	la_leg.state_changed.connect(on_del_state)
	var stale_del := DeliverToCampOrder.new(camp_leg, inv_leg)
	var del_ok: bool = la_leg.issue_personal_order(stale_del)
	la_leg.state_changed.disconnect(on_del_state)
	assert_true(del_cb_fired[0], "A03-R04: DeliverToCampOrder state_changed(TRANSPORTING) callback fired")
	assert_false(del_ok)
	assert_eq(la_leg.get_current_order(), del_succ, "A03-R04: MoveOrder successor preserved over DeliverToCampOrder")
	assert_eq(la_leg.get_movement().get_move_state(), UnitMovement.MoveState.MOVING, "A03-R04: stale DeliverToCampOrder must NOT stop successor movement")
	assert_eq(inv_leg.get_physical_amount(&"wood"), 0, "A03-R04: stale DeliverToCampOrder must NOT execute delivery after replacement")
	assert_eq(la_leg.get_carry_load().get_amount(&"wood"), 4, "A03-R04: cargo conserved in backpack")
	la_leg.cancel_current_order()
	await _teardown_isolated_main(ctx_leg)

	# Subcase 4b: RecoveryOrder replaced during state_changed(TRANSPORTING) inside start() ->
	# successor MoveOrder preserved intact, custody remains unsettled, then settles cleanly with D0-A04!
	assert_true(leader_a.issue_personal_order(ConstructOrder.new(site, camp, false, true, false)))
	assert_true(await _until(func() -> bool: return site.get_delivered_buffer_amount(&"wood") > 0 and leader_a.get_state() != Unit.State.TRANSPORTING, 3600))
	var cancel_s := ReservedWithdrawalCoordinator.execute_site_cancellation(site, &"a03_r04_cancel")
	assert_true(cancel_s.ok)
	var rec_cancel_id: StringName = cancel_s.receipt.cancel_id
	var rec_succ := MoveOrder.new(Vector3(-9.0, 0.0, -5.0))
	var rec_cb_fired := [false]
	var on_rec_state := func(ns: Unit.State, _ps: Unit.State) -> void:
		if ns == Unit.State.TRANSPORTING and not rec_cb_fired[0]:
			rec_cb_fired[0] = true
			leader_a.issue_personal_order(rec_succ)
	leader_a.state_changed.connect(on_rec_state)
	cm._recovery_dispatcher._flush()
	leader_a.state_changed.disconnect(on_rec_state)
	assert_true(rec_cb_fired[0], "A03-R04b: RecoveryOrder start() callback fired")
	assert_eq(leader_a.get_current_order(), rec_succ, "A03-R04b: MoveOrder successor preserved over RecoveryOrder")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(leader_a.get_movement().get_move_state(), UnitMovement.MoveState.MOVING)
	leader_a.cancel_current_order()
	# Explicitly recover and verify conservation across entire A03 suite!
	assert_true(bool(cm.assign_cancellation_recovery(rec_cancel_id, [leader_a]).get("ok", false)))
	var rec_record := CancellationRecoveryTransaction._record(world, region_id, rec_cancel_id)
	assert_true(await _until(func() -> bool: return rec_record.state == ConstructionCancellationMath.State.SETTLED, 4800))
	await _until(func() -> bool: return leader_a.get_current_order() == null, 120)

	var snap_wood_after := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_after := Audit.capture(get_tree(), world, region_id, &"stone", inv)
	assert_true(bool(Audit.verify_conservation(snap_wood_before, snap_wood_after).get("ok", false)), "A03: D0-A04 wood conservation")
	assert_true(bool(Audit.verify_conservation(snap_stone_before, snap_stone_after).get("ok", false)), "A03: D0-A04 stone conservation")
	await _teardown_isolated_main(ctx)
