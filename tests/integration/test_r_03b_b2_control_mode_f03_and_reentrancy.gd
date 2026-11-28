extends TestCase
## Integration tests for R-03B B2:
## - C01: ControlMode state machine transitions & signals (COMMUNITY_FREE, COMMUNITY_WORKING, PERSONAL_ACTIVE)
## - C02 (C02-01..C02-12): F03 revision ownership, pure can_cancel_now(), _transition_seq, reentrancy,
##   single-shot order_finished, committed InterruptionCause, successor protection
## - E02: Recovery T1a/T1b, entry.manual, transactional block, RegionalConservationAudit (D0-A04)
## - F01: Timerless lifecycle, teardown, unit removal, definition downgrade
## - B2-AR01..B2-AR05: Post-commit task_updated and task_assigned callback hardening (B1-R1 audit caveats)

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
		"sel": main.get_selection_manager(),
		"inv": main.get_settlement_inventory(),
		"camp": main.get_camp_storage_zone(),
		"cm": main.get_construction_manager(),
		"units_root": main.get_node("Units"),
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


# ==============================================================================
# C01: ControlMode state machine, personal priority, event-driven return, signals
# ==============================================================================
func test_c01_control_mode_transitions_personal_priority_and_event_return() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var tree: ResourceSource = _find_source(main, &"wood_tree_01")
	var rock: ResourceSource = _find_source(main, &"stone_rock_01")

	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.NONE)
	assert_true(leader_a.is_community_dispatch_eligible())

	var transitions: Array[Dictionary] = []
	leader_a.control_mode_changed.connect(func(n: UnitControlState.ControlMode, p: UnitControlState.ControlMode) -> void:
		transitions.append({"new": n, "prev": p})
	)

	# Keep leader_b busy personally so leader_a takes community work.
	assert_true(leader_b.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0))))
	assert_eq(leader_b.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(leader_b.get_active_order_origin(), UnitOrder.OrderOrigin.PERSONAL)
	assert_false(leader_b.is_community_dispatch_eligible())

	# T1a: COMMUNITY_FREE -> COMMUNITY_WORKING (COMMUNITY origin)
	leader_a.global_position = tree.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg_tree := board.register_gather_task(tree)
	var task_tree: WorkTask = reg_tree["task"] as WorkTask
	disp._flush_dispatch()

	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING, "T1a -> COMMUNITY_WORKING")
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.COMMUNITY)
	assert_false(leader_a.is_community_dispatch_eligible())
	assert_eq(transitions.size(), 1)
	assert_eq(transitions[0]["prev"], UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(transitions[0]["new"], UnitControlState.ControlMode.COMMUNITY_WORKING)
	var comm_order: UnitOrder = leader_a.get_current_order()

	# T4: COMMUNITY_WORKING -> PERSONAL_ACTIVE (sovereign personal MoveOrder interruption)
	var move1 := MoveOrder.new(leader_a.global_position + Vector3(-2.5, 0.0, 0.0))
	assert_true(leader_a.issue_personal_order(move1))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE, "T4 -> PERSONAL_ACTIVE")
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.PERSONAL)
	assert_false(leader_a.is_community_dispatch_eligible())
	assert_eq(comm_order.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_MOVE, "T4 MoveOrder must commit InterruptionCause.PERSONAL_MOVE")
	assert_eq(transitions.size(), 2)
	assert_eq(transitions[1]["prev"], UnitControlState.ControlMode.COMMUNITY_WORKING)
	assert_eq(transitions[1]["new"], UnitControlState.ControlMode.PERSONAL_ACTIVE)

	# Verify community dispatcher CANNOT hijack leader_a while PERSONAL_ACTIVE even when another task is registered.
	var reg_rock := board.register_gather_task(rock)
	var task_rock: WorkTask = reg_rock["task"] as WorkTask
	disp._flush_dispatch()
	assert_eq(leader_a.get_current_order(), move1, "Community dispatcher must NOT hijack PERSONAL_ACTIVE unit")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)

	# T5: PERSONAL_ACTIVE -> PERSONAL_ACTIVE (no redundant control_mode_changed)
	var move2 := MoveOrder.new(rock.global_position + Vector3(-2.0, 0.0, 0.0))
	assert_true(leader_a.issue_personal_order(move2))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(move1.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_MOVE)
	assert_eq(transitions.size(), 2, "T5 PERSONAL_ACTIVE -> PERSONAL_ACTIVE must NOT emit redundant signal")

	# Configure timerless technical wait (0.0) so this B2 state-machine test isolates direct T6b transitions
	# (D-05 timed wait is covered exhaustively in the dedicated B3 suites).
	leader_a.personal_post_move_wait_sec = 0.0

	# T6b: Personal MoveOrder finishes SUCCEEDED with wait=0.0 -> returns directly to COMMUNITY_FREE
	# and event-driven control_mode_changed notifies CommunityTaskDispatcher.
	# Under B0-Q05 B, MoveOrder did NOT exclude leader_a from task_tree (Group 1 FIFO), so leader_a returns to task_tree!
	assert_true(await _until(func() -> bool: return not move2.is_active(), 1800), "Move2 must complete")
	assert_true(move2.is_succeeded())
	assert_eq(move2.get_interruption_cause(), UnitOrder.InterruptionCause.NONE, "Natural completion keeps InterruptionCause.NONE")
	await wait_process_frames(3)
	assert_true(transitions.size() >= 3, "T6b must emit PERSONAL_ACTIVE -> COMMUNITY_FREE")
	assert_eq(transitions[2]["prev"], UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(transitions[2]["new"], UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_false(task_tree.excluded_unit_ids.has(leader_a.get_instance_id()), "B0-Q05 B: MoveOrder interruption must NOT permanently exclude leader_a")
	assert_eq(task_tree.assigned_unit, leader_a, "B0-Q05 B: Event-driven return to COMMUNITY_FREE dispatches back to FIFO task_tree")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING)

	# T3 / T9: cancel_current_order -> COMMUNITY_FREE + InterruptionCause.ADMIN_CANCEL (which DOES exclude task_tree)
	var resumed_order: UnitOrder = leader_a.get_current_order()
	leader_a.cancel_current_order()
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.NONE)
	assert_eq(resumed_order.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL)
	assert_true(resumed_order.was_finished_notified())
	assert_true(task_tree.excluded_unit_ids.has(leader_a.get_instance_id()), "Admin cancel must keep persistent exclusion on task_tree")
	assert_false(task_rock.excluded_unit_ids.has(leader_a.get_instance_id()), "Untouched task_rock keeps empty exclusions")

	await _teardown_isolated_main(ctx)


# ==============================================================================
# C02-01..C02-04 & C02-11: Refused cancel preserves _order_revision across ALL 5 consumers
# ==============================================================================
func test_c02_01_to_04_refused_cancel_preserves_revision_and_consumers() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var tree: ResourceSource = _find_source(main, &"wood_tree_01")

	leader_b.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	leader_a.global_position = tree.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg := board.register_gather_task(tree)
	var task: WorkTask = reg["task"] as WorkTask
	disp._flush_dispatch()

	var g_order := leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(g_order)
	# Wait until leader_a enters chopping on the tree so ResourceSource cutter.revision is active too!
	assert_true(await _until(func() -> bool: return tree.get_tree_harvest_stage() == ResourceSource.TreeHarvestStage.CHOPPING, 600), "LeaderA must enter CHOPPING")
	var rev_before: int = leader_a.get_order_revision()
	assert_eq(task.assigned_order_revision, rev_before)

	var mode_events: Array[Dictionary] = []
	var fin_events: Array[UnitOrder] = []
	leader_a.control_mode_changed.connect(func(n: UnitControlState.ControlMode, p: UnitControlState.ControlMode) -> void:
		mode_events.append({"new": n, "prev": p})
	)
	leader_a.order_finished.connect(func(o: UnitOrder) -> void:
		fin_events.append(o)
	)

	# Lock GatherResourceOrder with active provenance transfer session -> can_cancel_now() == false.
	var sess := GatherTransferSession.new()
	sess.is_executing = true
	g_order._active_gather_session = sess
	assert_false(g_order.can_cancel_now())

	# C02-01, C02-02, C02-03, C02-11: MoveOrder refused -> ZERO revision bump, WorkTask & cutter & slot intact, ZERO exclusion!
	var refused_move := MoveOrder.new(Vector3(5.0, 0.0, 5.0))
	assert_false(leader_a.issue_personal_order(refused_move), "C02-01: MoveOrder must be refused during active gather transfer")
	assert_eq(leader_a.get_order_revision(), rev_before, "C02-01: _order_revision MUST NOT increment on refused cancel")
	assert_eq(leader_a.get_current_order(), g_order, "C02-01: GatherResourceOrder stays active")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING)
	assert_eq(task.assigned_order_revision, rev_before, "C02-02: WorkTask.assigned_order_revision remains coherent")
	assert_eq(task.assigned_unit, leader_a)
	assert_false(task.excluded_unit_ids.has(leader_a.get_instance_id()), "C02-11: refused MoveOrder must NOT add exclusion")
	assert_eq(g_order.get_interruption_cause(), UnitOrder.InterruptionCause.NONE, "C02-11: refused MoveOrder must NOT set InterruptionCause")
	assert_eq(mode_events.size(), 0, "C02-01: no control_mode_changed on refusal")
	assert_eq(fin_events.size(), 0, "C02-01: no order_finished on refusal")
	assert_true(g_order.has_reservation(), "C02-03: worker slot preserved")
	assert_eq(tree.get_tree_harvest_stage(), ResourceSource.TreeHarvestStage.CHOPPING, "C02-03: cutter state preserved")

	# Also verify cancel_current_order() and issue_order(null) refuse cleanly without bumping revision!
	leader_a.cancel_current_order()
	assert_eq(leader_a.get_order_revision(), rev_before, "cancel_current_order() must NOT bump revision when can_cancel_now()==false")
	assert_eq(leader_a.get_current_order(), g_order)
	assert_false(leader_a.issue_order(null), "issue_order(null) must return false when can_cancel_now()==false")
	assert_eq(leader_a.get_order_revision(), rev_before)
	assert_eq(leader_a.get_current_order(), g_order)
	assert_eq(fin_events.size(), 0)

	# Release session -> verify tree cutter still recognizes leader_a's intact revision!
	g_order._active_gather_session = null
	await wait_physics_frames(2)
	assert_eq(tree.get_tree_harvest_stage(), ResourceSource.TreeHarvestStage.CHOPPING, "C02-03: cutter still active with intact revision")
	assert_eq(leader_a.get_current_order(), g_order)
	assert_eq(leader_a.get_order_revision(), rev_before)

	# Now unlock allows legitimate cancel.
	leader_a.cancel_current_order()
	assert_null(leader_a.get_current_order())
	assert_eq(fin_events.size(), 1)
	assert_eq(fin_events[0], g_order)
	await _teardown_isolated_main(ctx)


# ==============================================================================
# C02-05..C02-10: Reentrancy callbacks, single-shot order_finished, committed cause
# ==============================================================================
func test_c02_05_to_10_reentrant_callbacks_single_notification_and_committed_cause() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var rock: ResourceSource = _find_source(main, &"stone_rock_01")
	var bush: ResourceSource = _find_source(main, &"food_bush_01")
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone

	leader_b.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	leader_a.global_position = rock.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg := board.register_gather_task(rock)
	var task: WorkTask = reg["task"] as WorkTask
	disp._flush_dispatch()

	var old_comm: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(old_comm)

	# Case 1 (C02-05, C02-06, C02-07, C02-10):
	# During old_comm.cancel() triggered by a MoveOrder (attempt A), worker_slot_released fires synchronously
	# and installs a personal GatherResourceOrder on bush (successor B)!
	# Verify:
	# - NO recursive cancel of old_comm
	# - Successor B (GatherResourceOrder) owns leader_a, keeps its movement/revision/slot, PERSONAL_ACTIVE
	# - Attempt A (MoveOrder) is discarded cleanly without touching successor B
	# - old_comm receives order_finished EXACTLY ONCE (notified despite successor!)
	# - old_comm's InterruptionCause is PERSONAL_OTHER (from committed successor B), NOT PERSONAL_MOVE (preempted attempt A)!
	var fin_counts: Dictionary = {}
	var on_fin := func(o: UnitOrder) -> void:
		var oid: int = o.get_instance_id()
		fin_counts[oid] = int(fin_counts.get(oid, 0)) + 1
	leader_a.order_finished.connect(on_fin)

	var succ_gather := GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, ctx["region_id"] as StringName)
	var reentrant_fired := [false]
	var on_slot_rel := func(_src: ResourceSource) -> void:
		if not reentrant_fired[0]:
			reentrant_fired[0] = true
			leader_a.issue_personal_order(succ_gather)
	rock.worker_slot_released.connect(on_slot_rel)

	var preempted_move := MoveOrder.new(Vector3(6.0, 0.0, 6.0))
	var attempt_a_ok: bool = leader_a.issue_personal_order(preempted_move)
	rock.worker_slot_released.disconnect(on_slot_rel)

	assert_true(reentrant_fired[0], "worker_slot_released callback must have fired inside cancel()")
	assert_false(attempt_a_ok, "Preempted outer attempt A must return false")
	assert_eq(leader_a.get_current_order(), succ_gather, "C02-05: Successor B must own unit")
	assert_true(succ_gather.is_active(), "C02-05: Successor B remains active")
	assert_true(succ_gather.has_reservation(), "C02-05: Successor B keeps its worker slot")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.PERSONAL)
	assert_eq(int(fin_counts.get(old_comm.get_instance_id(), 0)), 1, "C02-06/C02-07: old_comm notified EXACTLY ONCE even after successor takeover")
	assert_eq(int(fin_counts.get(preempted_move.get_instance_id(), 0)), 0, "Preempted unadmitted order must NOT emit false order_finished")
	assert_eq(old_comm.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_OTHER, "C02-10: committed cause must reflect successor B (PERSONAL_OTHER), not preempted MoveOrder")
	assert_null(task.assigned_unit, "CommunityTaskDispatcher must have cleaned old_comm assignment via order_finished")

	# Case 2: Callback on order_finished installs successor C -> successor C preserved, ZERO duplicate notification.
	var succ_c := MoveOrder.new(Vector3(-4.0, 0.0, -4.0))
	var fin_cb_fired := [false]
	var on_fin_install_c := func(o: UnitOrder) -> void:
		if o == succ_gather and not fin_cb_fired[0]:
			fin_cb_fired[0] = true
			leader_a.issue_personal_order(succ_c)
	leader_a.order_finished.connect(on_fin_install_c)
	var attempt_d := MoveOrder.new(Vector3(9.0, 0.0, 9.0))
	var d_ok: bool = leader_a.issue_personal_order(attempt_d)
	leader_a.order_finished.disconnect(on_fin_install_c)

	assert_true(fin_cb_fired[0])
	assert_false(d_ok, "Outer attempt D preempted by order_finished callback must return false")
	assert_eq(leader_a.get_current_order(), succ_c, "Successor C installed in order_finished must be preserved intact")
	assert_true(succ_c.is_active())
	assert_eq(leader_a.get_movement().get_move_state(), UnitMovement.MoveState.MOVING, "Successor C movement must NOT be stopped")
	assert_eq(int(fin_counts.get(succ_gather.get_instance_id(), 0)), 1, "C02-07: succ_gather notified EXACTLY ONCE")

	# Case 3 (C02-08): Synchronous completion of personal MoveOrder (already at target) with wait=0.0 -> COMMUNITY_FREE,
	# single order_finished, NO spurious PERSONAL_ACTIVE emission when starting from COMMUNITY_FREE.
	leader_a.personal_post_move_wait_sec = 0.0
	leader_a.cancel_current_order()
	var mode_events_sync: Array[Dictionary] = []
	leader_a.control_mode_changed.connect(func(n: UnitControlState.ControlMode, p: UnitControlState.ControlMode) -> void:
		mode_events_sync.append({"new": n, "prev": p})
	)
	var sync_move := MoveOrder.new(leader_a.global_position)
	assert_true(leader_a.issue_personal_order(sync_move), "C02-08: synchronous MoveOrder at current pos succeeds")
	assert_true(sync_move.is_succeeded())
	assert_null(leader_a.get_current_order())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(int(fin_counts.get(sync_move.get_instance_id(), 0)), 1, "C02-08: sync completion emits order_finished once")
	assert_eq(mode_events_sync.size(), 0, "C02-08: sync completion from COMMUNITY_FREE emits zero transient PERSONAL_ACTIVE")

	# Case 4 (C02-09): New order fails synchronously inside start() AFTER replacing an active order ->
	# previous order is NOT resurrected; unit stabilizes in COMMUNITY_FREE + IDLE, one net control_mode_changed.
	var active_mv := MoveOrder.new(Vector3(-8.0, 0.0, -8.0))
	assert_true(leader_a.issue_personal_order(active_mv))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	mode_events_sync.clear()
	var bad_mv := MoveOrder.new(Vector3(NAN, 0.0, 0.0))
	assert_false(leader_a.issue_personal_order(bad_mv), "C02-09: invalid target fails synchronously in start()")
	assert_eq(bad_mv.status, UnitOrder.Status.FAILED)
	assert_eq(active_mv.status, UnitOrder.Status.CANCELLED, "C02-09: previously cancelled order is NOT resurrected")
	assert_null(leader_a.get_current_order())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(mode_events_sync.size(), 1, "C02-09: exactly ONE net PERSONAL_ACTIVE -> COMMUNITY_FREE signal")
	assert_eq(mode_events_sync[0]["prev"], UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(mode_events_sync[0]["new"], UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(int(fin_counts.get(active_mv.get_instance_id(), 0)), 1)
	assert_eq(int(fin_counts.get(bad_mv.get_instance_id(), 0)), 1)

	# Case 5: Callback on control_mode_changed installs personal successor -> preserved without re-corrupting mode.
	var cb_succ := MoveOrder.new(Vector3(-3.0, 0.0, 3.0))
	var cm_fired := [false]
	var on_cm := func(n: UnitControlState.ControlMode, _p: UnitControlState.ControlMode) -> void:
		if n == UnitControlState.ControlMode.COMMUNITY_FREE and not cm_fired[0]:
			cm_fired[0] = true
			leader_a.issue_personal_order(cb_succ)
	leader_a.control_mode_changed.connect(on_cm)
	assert_true(leader_a.issue_personal_order(MoveOrder.new(Vector3(-6.0, 0.0, -6.0))))
	leader_a.cancel_current_order()
	leader_a.control_mode_changed.disconnect(on_cm)
	assert_true(cm_fired[0])
	assert_eq(leader_a.get_current_order(), cb_succ, "Successor installed in control_mode_changed must be preserved")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)

	leader_a.order_finished.disconnect(on_fin)
	await _teardown_isolated_main(ctx)


# ==============================================================================
# E02 + C02-04 + C02-12: Recovery authority, ControlMode, transactional block, D0-A04
# ==============================================================================
func test_e02_and_c02_12_recovery_control_mode_transactional_block_and_conservation() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var world: World3D = main.get_world_3d()
	var region_id: StringName = ctx["region_id"] as StringName

	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var snap_wood_before := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_before := Audit.capture(get_tree(), world, region_id, &"stone", inv)
	assert_true(bool(snap_wood_before.get("ok", false)))
	assert_true(bool(snap_stone_before.get("ok", false)))

	var res := cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(res.get("ok", false)))
	var site: ConstructionSite = res["site"] as ConstructionSite
	assert_true(cmd.command_units_to_site(site, [leader_a]))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.PERSONAL)
	assert_true(await _until(func() -> bool: return site.get_delivered_buffer_amount(&"wood") > 0 or site._work_progress_usec > 0, 3600), "Site received materials")

	# C02-04 (ConstructOrder): active provenance transfer blocks personal cancel WITHOUT bumping revision or mutating _replan_requested.
	var c_order := leader_a.get_current_order() as ConstructOrder
	assert_not_null(c_order)
	var c_rev: int = leader_a.get_order_revision()
	c_order._replan_requested = false
	c_order._provenance_transfer.is_executing = true
	assert_false(c_order.can_cancel_now())
	assert_false(leader_a.issue_personal_order(MoveOrder.new(Vector3(3.0, 0.0, 3.0))))
	assert_eq(leader_a.get_order_revision(), c_rev, "ConstructOrder refused cancel must preserve _order_revision")
	assert_false(c_order._replan_requested, "can_cancel_now() must NOT mutate _replan_requested")
	assert_eq(leader_a.get_current_order(), c_order)
	c_order._provenance_transfer.is_executing = false

	# Cancel site -> legitimate T1b transitions PERSONAL_ACTIVE -> COMMUNITY_WORKING (SYSTEM_RECOVERY) with InterruptionCause.SYSTEM_RECOVERY!
	var cancelled := ReservedWithdrawalCoordinator.execute_site_cancellation(site, &"b2_e02_cancel")
	assert_true(cancelled.ok)
	var cancel_id: StringName = cancelled.receipt.cancel_id
	assert_true(c_order.is_active(), "ConstructOrder must still be active right after cancellation commit so T1b replaces it directly")
	cm._recovery_dispatcher._flush()

	assert_eq(c_order.get_interruption_cause(), UnitOrder.InterruptionCause.SYSTEM_RECOVERY, "T1b must record InterruptionCause.SYSTEM_RECOVERY on ConstructOrder")
	var rec_order := leader_a.get_current_order() as RecoveryOrder
	assert_not_null(rec_order, "T1b must install RecoveryOrder")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING, "T1b -> COMMUNITY_WORKING")
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.SYSTEM_RECOVERY, "T1b origin == SYSTEM_RECOVERY")
	assert_false(leader_a.is_community_dispatch_eligible())

	# C02-04 (RecoveryOrder): transactional lock preserves recovery revision, order, custody & ControlMode!
	var rec_rev: int = leader_a.get_order_revision()
	leader_a.get_carry_load()._coordinator_transaction_locked = true
	assert_false(rec_order.can_cancel_now())
	assert_false(leader_a.issue_personal_order(MoveOrder.new(Vector3(2.0, 0.0, 2.0))))
	assert_eq(leader_a.get_order_revision(), rec_rev, "C02-04: refused cancel on RecoveryOrder must preserve revision")
	assert_eq(leader_a.get_current_order(), rec_order)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING)
	leader_a.get_carry_load()._coordinator_transaction_locked = false

	# E02: Personal MoveOrder interrupts RecoveryOrder -> PERSONAL_ACTIVE, manual_interruption=true, entry.manual=true, single notification.
	leader_a.personal_post_move_wait_sec = 0.0
	var rec_fin_count := [0]
	var on_rec_fin := func(o: UnitOrder) -> void:
		if o == rec_order:
			rec_fin_count[0] += 1
	leader_a.order_finished.connect(on_rec_fin)
	var interrupt_mv := MoveOrder.new(leader_a.global_position + Vector3(-1.5, 0.0, 0.0))
	assert_true(leader_a.issue_personal_order(interrupt_mv))
	leader_a.order_finished.disconnect(on_rec_fin)
	assert_eq(rec_fin_count[0], 1, "Interrupted RecoveryOrder must notify order_finished exactly once")
	assert_true(rec_order.manual_interruption)
	assert_eq(rec_order.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_MOVE)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_true(await _until(func() -> bool: return not interrupt_mv.is_active(), 1200))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)

	# Trigger safe event -> entry.manual must prevent automatic restart!
	var rec_disp: CancellationRecoveryDispatcher = cm._recovery_dispatcher
	assert_not_null(rec_disp)
	rec_disp._on_safe_event()
	await wait_process_frames(3)
	assert_null(leader_a.get_current_order(), "E02: entry.manual must block automatic recovery restart")

	# Explicit assign settles custody cleanly, then verify D0-A04 regional conservation!
	var exp_res := cm.assign_cancellation_recovery(cancel_id, [leader_a])
	assert_true(bool(exp_res.get("ok", false)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING)
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.SYSTEM_RECOVERY)
	var record := CancellationRecoveryTransaction._record(world, region_id, cancel_id)
	assert_true(await _until(func() -> bool: return record.state == ConstructionCancellationMath.State.SETTLED, 4800), "Explicit recovery must settle custody")
	assert_true(await _until(func() -> bool: return leader_a.get_current_order() == null, 120))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)

	var snap_wood_after := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_after := Audit.capture(get_tree(), world, region_id, &"stone", inv)
	assert_true(bool(Audit.verify_conservation(snap_wood_before, snap_wood_after).get("ok", false)), "D0-A04 wood conservation")
	assert_true(bool(Audit.verify_conservation(snap_stone_before, snap_stone_after).get("ok", false)), "D0-A04 stone conservation")
	await _teardown_isolated_main(ctx)


# ==============================================================================
# B2-AR01..B2-AR05: Post-commit task_updated & task_assigned callback hardening
# ==============================================================================
func test_b2_ar01_to_ar05_post_commit_dispatcher_callbacks() -> void:
	# --- B2-AR01: task_assigned callback installs personal successor ---
	var ctx1 := await _boot_isolated_main(true)
	var main1: MainScene = ctx1["main"] as MainScene
	var board1: CommunityWorkBoard = ctx1["board"] as CommunityWorkBoard
	var disp1: CommunityTaskDispatcher = ctx1["dispatcher"] as CommunityTaskDispatcher
	var la1: Unit = ctx1["leader_a"] as Unit
	var lb1: Unit = ctx1["leader_b"] as Unit
	var bush1: ResourceSource = _find_source(main1, &"food_bush_01")
	lb1.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	la1.global_position = bush1.global_position + Vector3(-1.8, 0.0, 0.0)

	var fb1: Array[String] = []
	var succ1 := MoveOrder.new(Vector3(-4.0, 0.0, -4.0))
	var on_fb1 := func(m: String) -> void: fb1.append(m)
	var on_asg1 := func(_t: WorkTask, u: Unit, _o: UnitOrder) -> void:
		u.issue_personal_order(succ1)
	disp1.task_feedback.connect(on_fb1)
	disp1.task_assigned.connect(on_asg1)
	var reg1 := board1.register_gather_task(bush1)
	var task1: WorkTask = reg1["task"] as WorkTask
	disp1._flush_dispatch()
	disp1.task_assigned.disconnect(on_asg1)
	disp1.task_feedback.disconnect(on_fb1)

	assert_eq(la1.get_current_order(), succ1, "B2-AR01: personal successor preserved")
	assert_eq(la1.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_null(task1.assigned_unit, "B2-AR01: old assignment cleaned")
	# Under B0-Q05 B, MoveOrder leaves task1 legitimately waiting (personal_control_active) instead of manually_overridden;
	# assert strictly ZERO obsolete dispatch feedback ("indo colher") is emitted after personal takeover.
	for fb_msg: String in fb1:
		assert_false(fb_msg.contains("indo colher"), "B2-AR01: ZERO obsolete dispatch feedback emitted after personal takeover (got '%s')" % fb_msg)
	await _teardown_isolated_main(ctx1)

	# --- B2-AR02: task_assigned callback triggers dispatcher.teardown() ---
	var ctx2 := await _boot_isolated_main(true)
	var main2: MainScene = ctx2["main"] as MainScene
	var board2: CommunityWorkBoard = ctx2["board"] as CommunityWorkBoard
	var disp2: CommunityTaskDispatcher = ctx2["dispatcher"] as CommunityTaskDispatcher
	var la2: Unit = ctx2["leader_a"] as Unit
	var lb2: Unit = ctx2["leader_b"] as Unit
	var bush2: ResourceSource = _find_source(main2, &"food_bush_01")
	lb2.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	la2.global_position = bush2.global_position + Vector3(-1.8, 0.0, 0.0)
	var fb2: Array[String] = []
	var on_fb2 := func(m: String) -> void: fb2.append(m)
	var on_asg2 := func(_t: WorkTask, _u: Unit, _o: UnitOrder) -> void:
		disp2.teardown()
	disp2.task_feedback.connect(on_fb2)
	disp2.task_assigned.connect(on_asg2)
	var reg2 := board2.register_gather_task(bush2)
	var task2: WorkTask = reg2["task"] as WorkTask
	disp2._flush_dispatch()
	if disp2.task_assigned.is_connected(on_asg2):
		disp2.task_assigned.disconnect(on_asg2)
	if disp2.task_feedback.is_connected(on_fb2):
		disp2.task_feedback.disconnect(on_fb2)

	assert_null(task2.assigned_unit, "B2-AR02: assignment reconciled on teardown in task_assigned")
	assert_null(la2.get_current_order(), "B2-AR02: no orphan community order left running")
	assert_eq(la2.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(fb2.size(), 0, "B2-AR02: no obsolete feedback after teardown")
	await _teardown_isolated_main(ctx2)

	# --- B2-AR03: task_assigned callback reconfigures Dispatcher with a new Board ---
	var ctx3 := await _boot_isolated_main(true)
	var main3: MainScene = ctx3["main"] as MainScene
	var board3_old: CommunityWorkBoard = ctx3["board"] as CommunityWorkBoard
	var disp3: CommunityTaskDispatcher = ctx3["dispatcher"] as CommunityTaskDispatcher
	var la3: Unit = ctx3["leader_a"] as Unit
	var lb3: Unit = ctx3["leader_b"] as Unit
	var bush3: ResourceSource = _find_source(main3, &"food_bush_01")
	var board3_new := CommunityWorkBoard.new()
	main3.add_child(board3_new)
	board3_new.configure(ctx3["region_id"] as StringName, main3.get_world_3d())
	lb3.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	la3.global_position = bush3.global_position + Vector3(-1.8, 0.0, 0.0)
	var fb3: Array[String] = []
	var on_fb3 := func(m: String) -> void: fb3.append(m)
	var on_asg3 := func(_t: WorkTask, _u: Unit, _o: UnitOrder) -> void:
		disp3.configure(
			board3_new, ctx3["cmd"] as CommandController, ctx3["nav"] as WorldNavigation,
			ctx3["units_root"] as Node, ctx3["camp"] as CampStorageZone, ctx3["inv"] as SettlementInventory,
			ctx3["region_id"] as StringName, true, ""
		)
	disp3.task_feedback.connect(on_fb3)
	disp3.task_assigned.connect(on_asg3)
	var reg3 := board3_old.register_gather_task(bush3)
	var task3: WorkTask = reg3["task"] as WorkTask
	disp3._flush_dispatch()
	if disp3.task_assigned.is_connected(on_asg3):
		disp3.task_assigned.disconnect(on_asg3)
	if disp3.task_feedback.is_connected(on_fb3):
		disp3.task_feedback.disconnect(on_fb3)

	assert_null(task3.assigned_unit, "B2-AR03: old board task cleaned")
	assert_null(la3.get_current_order(), "B2-AR03: old community order cancelled")
	assert_eq(board3_new.get_all_tasks().size(), 0, "B2-AR03: new board completely untouched")
	assert_eq(fb3.size(), 0, "B2-AR03: zero obsolete feedback emitted")
	board3_new.teardown()
	await _teardown_isolated_main(ctx3)

	# --- B2-AR04: task_assigned callback queues removal of chosen_unit ---
	var ctx4 := await _boot_isolated_main(true)
	var main4: MainScene = ctx4["main"] as MainScene
	var board4: CommunityWorkBoard = ctx4["board"] as CommunityWorkBoard
	var disp4: CommunityTaskDispatcher = ctx4["dispatcher"] as CommunityTaskDispatcher
	var la4: Unit = ctx4["leader_a"] as Unit
	var lb4: Unit = ctx4["leader_b"] as Unit
	var bush4: ResourceSource = _find_source(main4, &"food_bush_01")
	lb4.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	la4.global_position = bush4.global_position + Vector3(-1.8, 0.0, 0.0)
	var fb4: Array[String] = []
	var on_fb4 := func(m: String) -> void: fb4.append(m)
	var on_asg4 := func(_t: WorkTask, u: Unit, _o: UnitOrder) -> void:
		u.queue_free()
	disp4.task_feedback.connect(on_fb4)
	disp4.task_assigned.connect(on_asg4)
	var reg4 := board4.register_gather_task(bush4)
	var task4: WorkTask = reg4["task"] as WorkTask
	disp4._flush_dispatch()
	disp4.task_assigned.disconnect(on_asg4)
	disp4.task_feedback.disconnect(on_fb4)

	assert_null(task4.assigned_unit, "B2-AR04: task assignment cleaned when unit queued for deletion")
	for msg4: String in fb4:
		assert_false(msg4.contains("indo colher"), "B2-AR04: zero obsolete dispatch feedback after unit removal (got: %s)" % msg4)
	await wait_process_frames(2)
	await _teardown_isolated_main(ctx4)

	# --- B2-AR05: task_updated callback immediately after commit triggers teardown() ---
	var ctx5 := await _boot_isolated_main(true)
	var main5: MainScene = ctx5["main"] as MainScene
	var board5: CommunityWorkBoard = ctx5["board"] as CommunityWorkBoard
	var disp5: CommunityTaskDispatcher = ctx5["dispatcher"] as CommunityTaskDispatcher
	var la5: Unit = ctx5["leader_a"] as Unit
	var lb5: Unit = ctx5["leader_b"] as Unit
	var bush5: ResourceSource = _find_source(main5, &"food_bush_01")
	lb5.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	la5.global_position = bush5.global_position + Vector3(-1.8, 0.0, 0.0)
	var assigned5 := [0]
	var fb5: Array[String] = []
	var reg5 := board5.register_gather_task(bush5)
	var task5: WorkTask = reg5["task"] as WorkTask
	var td5_fired := [false]
	var on_upd5 := func(t: WorkTask) -> void:
		if t == task5 and t.state == WorkTask.State.IN_PROGRESS and not td5_fired[0]:
			td5_fired[0] = true
			disp5.teardown()
	var on_asg5 := func(_t: WorkTask, _u: Unit, _o: UnitOrder) -> void: assigned5[0] += 1
	var on_fb5 := func(m: String) -> void: fb5.append(m)
	board5.task_updated.connect(on_upd5)
	disp5.task_assigned.connect(on_asg5)
	disp5.task_feedback.connect(on_fb5)
	disp5._flush_dispatch()
	if board5.task_updated.is_connected(on_upd5):
		board5.task_updated.disconnect(on_upd5)
	disp5.task_assigned.disconnect(on_asg5)
	disp5.task_feedback.disconnect(on_fb5)

	assert_true(td5_fired[0], "B2-AR05: task_updated callback fired")
	assert_null(task5.assigned_unit, "B2-AR05: task assignment cleared after teardown in task_updated")
	assert_eq(task5.state, WorkTask.State.PENDING_WORKERS)
	assert_null(la5.get_current_order(), "B2-AR05: ZERO orphan community work left running")
	assert_eq(la5.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(assigned5[0], 0, "B2-AR05: task_assigned NOT emitted after teardown")
	assert_eq(fb5.size(), 0, "B2-AR05: task_feedback NOT emitted after teardown")
	await _teardown_isolated_main(ctx5)


# ==============================================================================
# F01: Timerless lifecycle, unit removal, definition downgrade & controlled teardown
# ==============================================================================
func test_f01_timerless_lifecycle_removal_definition_downgrade_and_teardown() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var world: World3D = main.get_world_3d()
	var region_id: StringName = ctx["region_id"] as StringName

	# Active personal order -> runtime definition downgrade to COMMUNITY cancels incompatible personal order cleanly!
	assert_true(leader_a.issue_personal_order(MoveOrder.new(Vector3(-8.0, 0.0, -8.0))))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	var downgraded := CharacterDefinition.new()
	downgraded.character_id = &"leader_a"
	downgraded.display_name = "Downgraded"
	downgraded.house_affiliation = CharacterDefinition.HouseAffiliation.COMMUNITY
	downgraded.founding_house_origin = CharacterDefinition.FoundingHouseOrigin.NONE
	downgraded.age_stage = CharacterDefinition.AgeStage.ADULT
	leader_a.definition = downgraded
	assert_null(leader_a.get_current_order(), "Downgrading Founding House -> COMMUNITY must cancel active personal order")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)

	# Unit removal during PERSONAL_ACTIVE cancels order once and blocks re-admission during _exit_tree!
	var b_mv := MoveOrder.new(Vector3(-10.0, 0.0, -8.0))
	assert_true(leader_b.issue_personal_order(b_mv))
	var b_fin := [0]
	var b_readmit := [true]
	leader_b.order_finished.connect(func(o: UnitOrder) -> void:
		if o == b_mv:
			b_fin[0] += 1
			b_readmit[0] = leader_b.issue_personal_order(MoveOrder.new(Vector3.ZERO))
	)
	leader_b.get_parent().remove_child(leader_b)
	assert_eq(b_fin[0], 1, "_exit_tree must emit order_finished once")
	assert_false(b_readmit[0], "Re-admission during _exit_tree MUST be rejected")
	assert_eq(leader_b.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	leader_b.queue_free()

	# Controlled MainScene teardown releases regional domain cleanly.
	var td_res: Dictionary = main.request_controlled_teardown()
	assert_true(bool(td_res.get("ok", false)), "MainScene controlled teardown must succeed cleanly: %s" % str(td_res))
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, region_id))

	var vp: SubViewport = ctx["vp"] as SubViewport
	if vp != null and is_instance_valid(vp):
		if vp.get_parent() != null:
			vp.get_parent().remove_child(vp)
		vp.queue_free()
	await wait_process_frames(2)
