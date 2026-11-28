extends TestCase
## Integration tests for R-03B B3:
## - D03: Automatic community return after D-05 wait (wood, stone, food), returning to SAME still-authorized task (B0-Q05 B),
##   CutAuthorization preservation, non-reactivation of CANCELLED / BLOCKED_REAUTHORIZATION, PERSONAL_OTHER & ADMIN_CANCEL exclusions
## - EV01..EV08: Ratified B2-R2 two-event correlation (order_finished vs order_interruption_cause_committed)
## - Strict 4-category eligibility classification (BABY / CHILD structural before temporary, D4-R2 A02-02 manually_overridden preserved)
## - E02: RegionalConservationAudit (D0-A04) across interruption and automatic return.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const Audit := preload("res://tests/framework/regional_conservation_audit.gd")


func before_each() -> void:
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 1.0


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0


func _boot_main(wait_sec: float = 0.10) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(320, 180)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_test_child(vp)

	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = true
	main.automatic_cancellation_recovery = true
	main.use_d2_2_hud = false
	main.experimental_personal_post_move_wait_sec = wait_sec
	vp.add_child(main)
	await wait_process_frames(2)
	await wait_physics_frames(2)

	var nav: WorldNavigation = main.get_test_map().get_navigation()
	for _i: int in range(360):
		if nav.is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(nav.is_navigation_ready(), "Navigation ready")

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
		"leader_a": main.get_node("Units/LeaderA") as Unit,
		"leader_b": main.get_node("Units/LeaderB") as Unit,
		"region_id": main.get_construction_manager().get_region_id(),
	}


func _teardown_main(ctx: Dictionary) -> void:
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


func _until(predicate: Callable, max_frames: int = 1200) -> bool:
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
	var def := CharacterDefinition.new()
	def.character_id = cid
	def.display_name = display
	def.house_affiliation = aff
	def.founding_house_origin = orig
	def.age_stage = age
	return def


# ==============================================================================
# D03 + E02: Automatic return to SAME task across wood/stone/food + Q05-B boundaries + D0-A04
# ==============================================================================
func test_d03_automatic_return_to_same_task_across_all_resources_and_boundaries() -> void:
	var ctx := await _boot_main(0.10)
	var main: MainScene = ctx["main"] as MainScene
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var world: World3D = main.get_world_3d()
	var region_id: StringName = ctx["region_id"] as StringName

	var tree: ResourceSource = _find_source(main, &"wood_tree_01")
	var rock: ResourceSource = _find_source(main, &"stone_rock_01")
	var bush: ResourceSource = _find_source(main, &"food_bush_01")

	var snap_wood_0 := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_0 := Audit.capture(get_tree(), world, region_id, &"stone", inv)
	var snap_food_0 := Audit.capture(get_tree(), world, region_id, &"food", inv)

	# Keep leader_b occupied personally so leader_a owns each community task alone.
	leader_b.personal_post_move_wait_sec = 5.0
	assert_true(leader_b.issue_personal_order(MoveOrder.new(leader_b.global_position)))
	assert_eq(leader_b.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)

	# 1-3: Verify B0-Q05 B return to the SAME task across WOOD, STONE, and FOOD!
	var sources: Array[ResourceSource] = [tree, rock, bush]
	for src: ResourceSource in sources:
		leader_a.global_position = src.global_position + Vector3(-1.8, 0.0, 0.0)
		var reg := board.register_gather_task(src)
		var task: WorkTask = reg["task"] as WorkTask
		disp._flush_dispatch()
		assert_eq(task.assigned_unit, leader_a, "LeaderA assigned to %s" % String(src.source_id))
		var orig_auth := task.tree_cut_authorization
		var orig_task_id: int = task.task_id

		# Interrupt with personal MoveOrder (sync at current position -> enters PERSONAL_POST_MOVE_WAIT)
		assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
		assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
		assert_null(task.assigned_unit, "Assignment cleared immediately on personal MoveOrder")
		assert_false(task.excluded_unit_ids.has(leader_a.get_instance_id()), "B0-Q05 B: MoveOrder does NOT exclude worker on %s" % String(src.source_id))
		assert_eq(task.tree_cut_authorization, orig_auth, "CutAuthorization preserved across MoveOrder")
		assert_eq(disp.get_pending_interruption_classification_count(), 0, "Pending correlation consumed cleanly")

		# During wait, dispatcher MUST NOT prematurely reassign leader_a!
		disp._flush_dispatch()
		assert_null(task.assigned_unit, "Dispatcher respects PERSONAL_POST_MOVE_WAIT")
		assert_eq(task.state, WorkTask.State.PENDING_WORKERS, "Task waits temporarily while worker is in PERSONAL_POST_MOVE_WAIT (not BLOCKED)")

		# After D-05 expiration -> LeaderA automatically returns to the SAME task!
		await get_tree().create_timer(0.18).timeout
		await wait_process_frames(3)
		await wait_physics_frames(1)
		assert_eq(task.task_id, orig_task_id, "Same task_id preserved")
		assert_eq(task.assigned_unit, leader_a, "B0-Q05 B: LeaderA returned automatically to the SAME %s task" % String(src.source_id))
		assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING)
		assert_eq(task.tree_cut_authorization, orig_auth, "Same CutAuthorization reused on wood return")

		# Close task cleanly via selective cancellation so next resource starts clean.
		var c_res := disp.cancel_tasks_for_sources([src], src.get_resource_id())
		assert_true(bool(c_res.get("ok", false)))
		await wait_process_frames(2)

	# 4: CANCELLED task is NEVER reactivated by D-05 expiration!
	leader_a.global_position = rock.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg_c := board.register_gather_task(rock)
	var task_c: WorkTask = reg_c["task"] as WorkTask
	disp._flush_dispatch()
	assert_eq(task_c.assigned_unit, leader_a)
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	disp.cancel_tasks_for_sources([rock], &"stone")
	assert_eq(task_c.state, WorkTask.State.CANCELLED)
	await get_tree().create_timer(0.18).timeout
	await wait_process_frames(3)
	assert_eq(task_c.state, WorkTask.State.CANCELLED, "D-05 expiration never reactivates CANCELLED task")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_null(leader_a.get_current_order())

	# 5: Productive personal order (PERSONAL_OTHER) DOES exclude worker; D-05 expiration NEVER unblocks BLOCKED_REAUTHORIZATION!
	var reg_p := board.register_gather_task(rock)
	var task_p: WorkTask = reg_p["task"] as WorkTask
	disp._flush_dispatch()
	assert_eq(task_p.assigned_unit, leader_a)
	var personal_bush := GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, region_id)
	assert_true(leader_a.issue_personal_order(personal_bush))
	assert_true(task_p.excluded_unit_ids.has(leader_a.get_instance_id()), "PERSONAL_OTHER must exclude worker from interrupted task")
	# Cancel leader_a's personal gather and exclude leader_b too -> task_p enters BLOCKED_REAUTHORIZATION
	leader_a.cancel_current_order()
	leader_b.cancel_current_order()
	disp._flush_dispatch()
	if task_p.assigned_unit == leader_b:
		leader_b.cancel_current_order()
		disp._flush_dispatch()
	await wait_process_frames(3)
	assert_true(task_p.is_blocked_reauthorization(), "Task enters BLOCKED_REAUTHORIZATION when all workers excluded")

	# Enter and expire PERSONAL_POST_MOVE_WAIT on leader_a -> BLOCKED_REAUTHORIZATION stays untouched!
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	await get_tree().create_timer(0.18).timeout
	await wait_process_frames(3)
	assert_true(task_p.is_blocked_reauthorization(), "D-05 expiration must NEVER unblock BLOCKED_REAUTHORIZATION")
	assert_null(task_p.assigned_unit)

	# E02: D0-A04 regional conservation audit across wood/stone/food
	assert_true(bool(Audit.verify_conservation(snap_wood_0, Audit.capture(get_tree(), world, region_id, &"wood", inv)).get("ok", false)))
	assert_true(bool(Audit.verify_conservation(snap_stone_0, Audit.capture(get_tree(), world, region_id, &"stone", inv)).get("ok", false)))
	assert_true(bool(Audit.verify_conservation(snap_food_0, Audit.capture(get_tree(), world, region_id, &"food", inv)).get("ok", false)))

	await _teardown_main(ctx)


# ==============================================================================
# EV01..EV08: Ratified B2-R2 two-event correlation & edge cases
# ==============================================================================
func test_ev01_to_ev08_ratified_two_event_correlation_contract() -> void:
	var ctx := await _boot_main(0.25)
	var main: MainScene = ctx["main"] as MainScene
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var region_id: StringName = ctx["region_id"] as StringName
	var rock: ResourceSource = _find_source(main, &"stone_rock_01")
	var bush: ResourceSource = _find_source(main, &"food_bush_01")
	var tree: ResourceSource = _find_source(main, &"wood_tree_01")

	leader_b.personal_post_move_wait_sec = 5.0
	assert_true(leader_b.issue_personal_order(MoveOrder.new(leader_b.global_position)))

	# EV01: Observe mid-transition between order_finished (cause==NONE -> pending==1) and order_interruption_cause_committed (PERSONAL_MOVE -> pending==0, no exclusion).
	leader_a.global_position = rock.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg1 := board.register_gather_task(rock)
	var task1: WorkTask = reg1["task"] as WorkTask
	disp._flush_dispatch()
	var comm1: UnitOrder = leader_a.get_current_order()
	var mid_pending_seen := [-1]
	var mid_cause_seen := [-1]
	var on_fin_probe := func(o: UnitOrder) -> void:
		if o == comm1:
			mid_pending_seen[0] = disp.get_pending_interruption_classification_count()
			mid_cause_seen[0] = int(o.get_interruption_cause())
	leader_a.order_finished.connect(on_fin_probe)
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	leader_a.order_finished.disconnect(on_fin_probe)
	assert_eq(mid_cause_seen[0], int(UnitOrder.InterruptionCause.NONE), "EV01: cause is still NONE at Stage 2 order_finished (ratified B2-R2)")
	assert_eq(mid_pending_seen[0], 1, "EV01: dispatcher recorded pending order-level correlation at order_finished")
	assert_eq(disp.get_pending_interruption_classification_count(), 0, "EV01: pending correlation consumed on order_interruption_cause_committed")
	assert_false(task1.excluded_unit_ids.has(leader_a.get_instance_id()), "EV01: PERSONAL_MOVE does not exclude")
	disp.cancel_tasks_for_sources([rock], &"stone")
	leader_a.cancel_current_order()

	# EV02: Reentrant successor (GatherResourceOrder on bush inside worker_slot_released) preempts MoveOrder -> PERSONAL_OTHER -> excludes!
	var reg2 := board.register_gather_task(rock)
	var task2: WorkTask = reg2["task"] as WorkTask
	disp._flush_dispatch()
	var comm2: UnitOrder = leader_a.get_current_order()
	var succ_bush := GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, region_id)
	var ev02_fired := [false]
	var on_slot_ev02 := func(_s: ResourceSource) -> void:
		if not ev02_fired[0]:
			ev02_fired[0] = true
			leader_a.issue_personal_order(succ_bush)
	rock.worker_slot_released.connect(on_slot_ev02)
	assert_false(leader_a.issue_personal_order(MoveOrder.new(Vector3(4.0, 0.0, 4.0))))
	rock.worker_slot_released.disconnect(on_slot_ev02)
	assert_true(ev02_fired[0])
	assert_eq(comm2.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_OTHER)
	assert_true(task2.excluded_unit_ids.has(leader_a.get_instance_id()), "EV02: committed successor PERSONAL_OTHER excludes worker despite preempted MoveOrder")
	assert_eq(disp.get_pending_interruption_classification_count(), 0)
	leader_a.cancel_current_order()
	disp.cancel_tasks_for_sources([rock], &"stone")

	# EV03: Late Check Point 2 rejection of MoveOrder (transaction lock set inside order_finished) -> ADMIN_CANCEL -> excludes!
	var reg3 := board.register_gather_task(rock)
	var task3: WorkTask = reg3["task"] as WorkTask
	disp._flush_dispatch()
	var comm3: UnitOrder = leader_a.get_current_order()
	var ev03_locked := [false]
	var on_fin_ev03 := func(o: UnitOrder) -> void:
		if o == comm3 and not ev03_locked[0]:
			ev03_locked[0] = true
			leader_a.get_carry_load()._coordinator_transaction_locked = true
	leader_a.order_finished.connect(on_fin_ev03)
	assert_false(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)), "EV03: MoveOrder rejected at Check Point 2")
	leader_a.order_finished.disconnect(on_fin_ev03)
	leader_a.get_carry_load()._coordinator_transaction_locked = false
	assert_true(ev03_locked[0])
	assert_eq(comm3.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL, "EV03: Check Point 2 rejection commits ADMIN_CANCEL")
	assert_true(task3.excluded_unit_ids.has(leader_a.get_instance_id()), "EV03: ADMIN_CANCEL excludes worker (NOT treated as PERSONAL_MOVE)")
	assert_eq(disp.get_pending_interruption_classification_count(), 0)
	disp.cancel_tasks_for_sources([rock], &"stone")

	# EV04: cancel_current_order() excludes; structural REASON_UNIT_EXITED does NOT exclude!
	var reg4 := board.register_gather_task(rock)
	var task4: WorkTask = reg4["task"] as WorkTask
	disp._flush_dispatch()
	leader_a.cancel_current_order()
	assert_true(task4.excluded_unit_ids.has(leader_a.get_instance_id()), "EV04: ADMIN_CANCEL excludes worker")
	assert_eq(disp.get_pending_interruption_classification_count(), 0)
	disp.cancel_tasks_for_sources([rock], &"stone")

	# EV05: Task closed as CANCELLED inside order_finished BEFORE order_interruption_cause_committed -> pending purged, zero mutation!
	var reg5 := board.register_gather_task(tree)
	var task5: WorkTask = reg5["task"] as WorkTask
	disp._flush_dispatch()
	var comm5: UnitOrder = leader_a.get_current_order()
	var on_fin_ev05 := func(o: UnitOrder) -> void:
		if o == comm5:
			board.close_task(task5, WorkTask.State.CANCELLED, "ev05_closed_mid_transition")
	leader_a.order_finished.connect(on_fin_ev05)
	assert_true(leader_a.issue_personal_order(GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, region_id)))
	leader_a.order_finished.disconnect(on_fin_ev05)
	assert_eq(task5.state, WorkTask.State.CANCELLED)
	assert_false(task5.excluded_unit_ids.has(leader_a.get_instance_id()), "EV05: closed task never mutated by late cause signal")
	assert_eq(disp.get_pending_interruption_classification_count(), 0)
	leader_a.cancel_current_order()

	# EV06: Dispatcher teardown inside order_finished BEFORE order_interruption_cause_committed -> pending cleared, zero mutation!
	var reg6 := board.register_gather_task(rock)
	var task6: WorkTask = reg6["task"] as WorkTask
	disp._flush_dispatch()
	var comm6: UnitOrder = leader_a.get_current_order()
	var on_fin_ev06 := func(o: UnitOrder) -> void:
		if o == comm6:
			disp.teardown()
	leader_a.order_finished.connect(on_fin_ev06)
	assert_true(leader_a.issue_personal_order(GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, region_id)))
	leader_a.order_finished.disconnect(on_fin_ev06)
	assert_false(task6.excluded_unit_ids.has(leader_a.get_instance_id()), "EV06: torn-down dispatcher ignores late cause signal")
	assert_eq(disp.get_pending_interruption_classification_count(), 0)

	# Re-configure dispatcher for EV07 + EV08
	leader_a.cancel_current_order()
	disp.configure(board, ctx["cmd"] as CommandController, ctx["nav"] as WorldNavigation, main.get_node("Units"), camp, inv, region_id, true, "")
	disp.cancel_tasks_for_sources([rock], &"stone")

	# EV07: Natural SUCCEEDED order never creates orphan pending correlation!
	bush.configure(bush.source_id, bush.get_definition(), 1, 1, 1)
	bush.set_gather_cycle_timings(0.02, 0.0)
	leader_a.global_position = bush.global_position + Vector3(-1.5, 0.0, 0.0)
	var reg7 := board.register_gather_task(bush)
	var task7: WorkTask = reg7["task"] as WorkTask
	disp._flush_dispatch()
	assert_true(await _until(func() -> bool: return not task7.is_active(), 1200), "EV07 natural completion finishes")
	assert_eq(disp.get_pending_interruption_classification_count(), 0, "EV07: zero orphan pending correlations after natural finish")

	# EV08: Duplicate/late order_interruption_cause_committed is idempotent!
	var reg8 := board.register_gather_task(rock)
	var task8: WorkTask = reg8["task"] as WorkTask
	disp._flush_dispatch()
	var comm8: UnitOrder = leader_a.get_current_order()
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_false(task8.excluded_unit_ids.has(leader_a.get_instance_id()))
	# Replay spurious late PERSONAL_OTHER on already-consumed order -> MUST be ignored!
	disp._on_unit_order_interruption_cause_committed(comm8, UnitOrder.InterruptionCause.PERSONAL_OTHER, leader_a.get_instance_id())
	assert_false(task8.excluded_unit_ids.has(leader_a.get_instance_id()), "EV08: duplicate/late cause emission is strictly idempotent")
	assert_eq(disp.get_pending_interruption_classification_count(), 0)

	await _teardown_main(ctx)


# ==============================================================================
# Strict 4-Category Eligibility Classification (Structural > Manual > Temporary > Reachable)
# ==============================================================================
func test_strict_four_category_eligibility_classification_and_d4_r2_precedence() -> void:
	var ctx := await _boot_main(1.0)
	var main: MainScene = ctx["main"] as MainScene
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var tree: ResourceSource = _find_source(main, &"wood_tree_01")

	# Add a Founding House CHILD and BABY into Units.
	var child_u: Unit = UNIT_SCENE.instantiate() as Unit
	child_u.name = "ChildEligibilityB3"
	child_u.definition = _make_def(&"child_elig_b3", "Crianca B3", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.CHILD)
	child_u.position = tree.global_position + Vector3(0.0, 0.0, 2.0)
	main.get_node("Units").add_child(child_u)
	child_u.set_world_navigation(ctx["nav"] as WorldNavigation)

	var baby_u: Unit = UNIT_SCENE.instantiate() as Unit
	baby_u.name = "BabyEligibilityB3"
	baby_u.definition = _make_def(&"baby_elig_b3", "Bebe B3", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.BABY)
	baby_u.position = tree.global_position + Vector3(0.0, 0.0, -2.0)
	main.get_node("Units").add_child(baby_u)
	baby_u.set_world_navigation(ctx["nav"] as WorldNavigation)

	ReservedWithdrawalCoordinator.admit_empty_provenance_units(
		[child_u, baby_u], main.get_node("Units"), ctx["camp"] as CampStorageZone, ctx["inv"] as SettlementInventory, ctx["region_id"] as StringName
	)

	# Put CHILD on a personal MoveOrder -> in PERSONAL_POST_MOVE_WAIT!
	child_u.personal_post_move_wait_sec = 3.0
	assert_true(child_u.issue_personal_order(MoveOrder.new(child_u.global_position)))
	assert_eq(child_u.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)

	# Register wood task: CHILD is structurally incompatible (age_restricted_task), NOT personal_control_active!
	var reg := board.register_gather_task(tree)
	var task: WorkTask = reg["task"] as WorkTask
	assert_eq(disp._check_pre_nav_eligibility(baby_u, task), "community_work_denied", "BABY classified structurally first")
	assert_eq(disp._check_pre_nav_eligibility(child_u, task), UnitControlPermissions.REASON_AGE_RESTRICTED_TASK, "CHILD on wood classified structurally BEFORE personal_control_active")

	# Exclude both adults (even while leader_a is in PERSONAL_POST_MOVE_WAIT -> D4-R2 A02-02: manually_overridden BEFORE temporary!)
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	assert_eq(disp._check_pre_nav_eligibility(leader_a, task), "personal_control_active", "Eligible adult in PERSONAL_POST_MOVE_WAIT -> temporary personal_control_active")
	task.excluded_unit_ids[leader_a.get_instance_id()] = true
	task.excluded_unit_ids[leader_b.get_instance_id()] = true
	assert_eq(disp._check_pre_nav_eligibility(leader_a, task), "manually_overridden", "D4-R2 A02-02: manually_overridden takes precedence over temporary personal_control_active")

	# Evaluate unassigned wood task -> MUST enter BLOCKED_REAUTHORIZATION despite CHILD being in PERSONAL_POST_MOVE_WAIT!
	disp._flush_dispatch()
	assert_true(task.is_blocked_reauthorization(), "Wood task enters BLOCKED_REAUTHORIZATION when all adults excluded even if CHILD is in PERSONAL_POST_MOVE_WAIT")

	await _teardown_main(ctx)
