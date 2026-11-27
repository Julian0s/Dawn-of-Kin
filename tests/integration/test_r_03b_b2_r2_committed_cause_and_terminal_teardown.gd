extends TestCase
## Focal adversarial tests for R-03B B2-R2:
## - B2-R2-A01 (A01-R01..A01-R06): Definitive committed InterruptionCause after late revalidation,
##   reentrant successor of different nature, post-admission start() failure vs pre-install rejection,
##   cancel() reentrancy, and single-shot order_finished / order_interruption_cause_committed.
## - B2-R2-A02 (A02-R01..A02-R06): Centralized token-authenticated Unit reconciliation during
##   MainScene.request_controlled_teardown() for GatherResourceOrder, ConstructOrder, RecoveryOrder
##   (preflight refusal vs post-settlement), unblocked MoveOrder, re-admission blocking, true
##   queue_free() destruction, regional domain release, and D0-A04 conservation.

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
		"leader_a": main.get_node("Units/LeaderA") as Unit,
		"leader_b": main.get_node("Units/LeaderB") as Unit,
		"region_id": main.get_construction_manager().get_region_id(),
	}


func _teardown_isolated_main(ctx: Dictionary) -> void:
	var main: MainScene = ctx.get("main") as MainScene
	var vp: SubViewport = ctx.get("vp") as SubViewport
	if main != null and is_instance_valid(main) and main.is_inside_tree():
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
# B2-R2-A01 (A01-R01..A01-R06): Committed InterruptionCause & Revalidation
# ==============================================================================
func test_b2_r2_a01_committed_interruption_cause_and_revalidation() -> void:
	var ctx := await _boot_isolated_main(true)
	var main: MainScene = ctx["main"] as MainScene
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var region_id: StringName = ctx["region_id"] as StringName
	var orig_def_a: CharacterDefinition = leader_a.get_definition()

	var rock: ResourceSource = _find_source(main, &"stone_rock_01")
	var tree: ResourceSource = _find_source(main, &"wood_tree_01")
	var bush: ResourceSource = _find_source(main, &"food_bush_01")

	# Keep leader_b occupied personally so leader_a deterministically receives community tasks.
	assert_true(leader_b.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0))))

	var fin_counts: Dictionary = {}
	var cause_events: Array[Dictionary] = []
	var on_fin_track := func(o: UnitOrder) -> void:
		var oid: int = o.get_instance_id()
		fin_counts[oid] = int(fin_counts.get(oid, 0)) + 1
	var on_cause_track := func(o: UnitOrder, c: UnitOrder.InterruptionCause) -> void:
		cause_events.append({"order": o, "cause": c})
	leader_a.order_finished.connect(on_fin_track)
	leader_a.order_interruption_cause_committed.connect(on_cause_track)

	# --- A01-R01: Real community gather -> MoveOrder -> affiliation downgraded to COMMUNITY in order_finished ---
	leader_a.global_position = rock.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg1 := board.register_gather_task(rock)
	var task1: WorkTask = reg1["task"] as WorkTask
	disp._flush_dispatch()
	var comm1: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(comm1, "A01-R01: community gather dispatched via Board/Dispatcher")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING)

	var comm_def := _make_def(&"leader_a", "CommunityA", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.ADULT)
	var cause_seen_inside_fin_1: Array[int] = []
	var on_fin_r01 := func(o: UnitOrder) -> void:
		if o == comm1:
			cause_seen_inside_fin_1.append(int(o.get_interruption_cause()))
			leader_a.definition = comm_def
	leader_a.order_finished.connect(on_fin_r01)
	var mv_r01 := MoveOrder.new(Vector3(4.0, 0.0, 4.0))
	var ok_r01: bool = leader_a.issue_personal_order(mv_r01)
	leader_a.order_finished.disconnect(on_fin_r01)

	assert_false(ok_r01, "A01-R01: MoveOrder MUST be rejected after affiliation downgrade in order_finished")
	assert_null(leader_a.get_current_order(), "A01-R01: MoveOrder not installed and previous order not resurrected")
	assert_true(comm1.is_finished(), "A01-R01: previous community gather finished")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.NONE)
	assert_false(leader_a.has_pending_control_transition())
	assert_eq(cause_seen_inside_fin_1, [int(UnitOrder.InterruptionCause.NONE)], "A01-R01: cause NOT falsely pre-stamped before Check Point 2")
	assert_ne(comm1.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_MOVE, "A01-R01: rejected MoveOrder MUST NOT leave PERSONAL_MOVE")
	assert_eq(comm1.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL, "A01-R01: definitive cause is ADMIN_CANCEL")
	assert_eq(int(fin_counts.get(comm1.get_instance_id(), 0)), 1, "A01-R01: single terminal notification for comm1")
	assert_eq(int(fin_counts.get(mv_r01.get_instance_id(), 0)), 0, "A01-R01: rejected MoveOrder never notified")
	assert_true(comm1.was_interruption_cause_notified())
	assert_eq(cause_events.size(), 1)
	assert_eq(cause_events[0]["order"], comm1)
	assert_eq(cause_events[0]["cause"], UnitOrder.InterruptionCause.ADMIN_CANCEL)
	assert_null(task1.assigned_unit, "A01-R01: dispatcher cleaned old task assignment")
	board.close_task(task1, WorkTask.State.CANCELLED, "cleanup_r01")

	# --- A01-R02a: Age downgrade (ADULT -> BABY) inside order_finished ---
	leader_a.definition = orig_def_a
	cause_events.clear()
	leader_a.global_position = rock.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg2a := board.register_gather_task(rock)
	var task2a: WorkTask = reg2a["task"] as WorkTask
	disp._flush_dispatch()
	var comm2a: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(comm2a)

	var baby_def := _make_def(&"leader_a", "BabyA", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.BABY)
	var on_fin_r02a := func(o: UnitOrder) -> void:
		if o == comm2a:
			leader_a.definition = baby_def
	leader_a.order_finished.connect(on_fin_r02a)
	var mv_r02a := MoveOrder.new(Vector3(5.0, 0.0, 3.0))
	var ok_r02a: bool = leader_a.issue_personal_order(mv_r02a)
	leader_a.order_finished.disconnect(on_fin_r02a)

	assert_false(ok_r02a, "A01-R02a: MoveOrder rejected on BABY downgrade in order_finished")
	assert_null(leader_a.get_current_order())
	assert_eq(comm2a.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL, "A01-R02a: definitive cause is ADMIN_CANCEL, never PERSONAL_MOVE")
	assert_eq(int(fin_counts.get(comm2a.get_instance_id(), 0)), 1)
	assert_eq(cause_events.size(), 1)
	assert_eq(cause_events[0]["cause"], UnitOrder.InterruptionCause.ADMIN_CANCEL)
	board.close_task(task2a, WorkTask.State.CANCELLED, "cleanup_r02a")

	# --- A01-R02b: Supervening economic lock inside order_finished ---
	leader_a.definition = orig_def_a
	cause_events.clear()
	var reg2b := board.register_gather_task(rock)
	var task2b: WorkTask = reg2b["task"] as WorkTask
	disp._flush_dispatch()
	var comm2b: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(comm2b)

	var on_fin_r02b := func(o: UnitOrder) -> void:
		if o == comm2b:
			leader_a.get_carry_load()._coordinator_transaction_locked = true
	leader_a.order_finished.connect(on_fin_r02b)
	var mv_r02b := MoveOrder.new(Vector3(5.0, 0.0, -3.0))
	var ok_r02b: bool = leader_a.issue_personal_order(mv_r02b)
	leader_a.order_finished.disconnect(on_fin_r02b)
	leader_a.get_carry_load()._coordinator_transaction_locked = false

	assert_false(ok_r02b, "A01-R02b: MoveOrder rejected on supervening transaction lock in order_finished")
	assert_null(leader_a.get_current_order())
	assert_eq(leader_a.get_last_order_rejection_reason(), CommandController.REASON_UNIT_TRANSACTION_LOCKED)
	assert_eq(comm2b.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL, "A01-R02b: definitive cause is ADMIN_CANCEL, never PERSONAL_MOVE")
	assert_eq(int(fin_counts.get(comm2b.get_instance_id(), 0)), 1)
	assert_eq(cause_events.size(), 1)
	assert_eq(cause_events[0]["cause"], UnitOrder.InterruptionCause.ADMIN_CANCEL)
	board.close_task(task2b, WorkTask.State.CANCELLED, "cleanup_r02b")

	# --- A01-R03: Outer attempt MoveOrder -> order_finished installs personal GatherResourceOrder (PERSONAL_OTHER) ---
	cause_events.clear()
	leader_a.global_position = tree.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg3 := board.register_gather_task(tree)
	var task3: WorkTask = reg3["task"] as WorkTask
	disp._flush_dispatch()
	var comm3: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(comm3)

	var succ_gather := GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, region_id)
	var on_fin_r03 := func(o: UnitOrder) -> void:
		if o == comm3:
			leader_a.issue_personal_order(succ_gather)
	leader_a.order_finished.connect(on_fin_r03)
	var mv_preempted := MoveOrder.new(Vector3(6.0, 0.0, 6.0))
	var ok_r03: bool = leader_a.issue_personal_order(mv_preempted)
	leader_a.order_finished.disconnect(on_fin_r03)

	assert_false(ok_r03, "A01-R03: preempted outer MoveOrder returns false")
	assert_eq(leader_a.get_current_order(), succ_gather, "A01-R03: legitimate GatherResourceOrder successor preserved")
	assert_true(succ_gather.is_active())
	assert_true(succ_gather.has_reservation())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(comm3.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_OTHER, "A01-R03: committed cause reflects GatherResourceOrder (PERSONAL_OTHER), NOT preempted MoveOrder")
	assert_eq(int(fin_counts.get(comm3.get_instance_id(), 0)), 1)
	assert_eq(int(fin_counts.get(mv_preempted.get_instance_id(), 0)), 0)
	assert_eq(cause_events.size(), 1)
	assert_eq(cause_events[0]["order"], comm3)
	assert_eq(cause_events[0]["cause"], UnitOrder.InterruptionCause.PERSONAL_OTHER)
	leader_a.cancel_current_order()
	board.close_task(task3, WorkTask.State.CANCELLED, "cleanup_r03")

	# --- A01-R04: Legitimate personal MoveOrder interrupting real community gather -> PERSONAL_MOVE ---
	cause_events.clear()
	leader_a.global_position = rock.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg4 := board.register_gather_task(rock)
	var task4: WorkTask = reg4["task"] as WorkTask
	disp._flush_dispatch()
	var comm4: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(comm4)

	var mv_legit := MoveOrder.new(Vector3(-4.0, 0.0, -4.0))
	assert_true(leader_a.issue_personal_order(mv_legit), "A01-R04: legitimate personal MoveOrder admitted")
	assert_eq(leader_a.get_current_order(), mv_legit)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_eq(comm4.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_MOVE, "A01-R04: legitimate MoveOrder MUST commit PERSONAL_MOVE")
	assert_eq(int(fin_counts.get(comm4.get_instance_id(), 0)), 1)
	assert_eq(cause_events.size(), 1)
	assert_eq(cause_events[0]["order"], comm4)
	assert_eq(cause_events[0]["cause"], UnitOrder.InterruptionCause.PERSONAL_MOVE)
	leader_a.cancel_current_order()
	board.close_task(task4, WorkTask.State.CANCELLED, "cleanup_r04")

	# --- A01-R05: Synchronous failure inside start() AFTER admission (distinct from pre-install rejection) ---
	cause_events.clear()
	var reg5 := board.register_gather_task(rock)
	var task5: WorkTask = reg5["task"] as WorkTask
	disp._flush_dispatch()
	var comm5: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(comm5)

	var bad_mv := MoveOrder.new(Vector3(NAN, 0.0, 0.0))
	assert_false(leader_a.issue_personal_order(bad_mv), "A01-R05: invalid MoveOrder fails synchronously inside start()")
	assert_eq(bad_mv.status, UnitOrder.Status.FAILED, "A01-R05: post-admission start() failure yields FAILED (not CANCELLED)")
	assert_eq(int(fin_counts.get(bad_mv.get_instance_id(), 0)), 1, "A01-R05: admitted order failing in start() emits order_finished once")
	assert_eq(comm5.status, UnitOrder.Status.CANCELLED, "A01-R05: previous order is NOT resurrected")
	assert_eq(comm5.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_MOVE, "A01-R05: admitted MoveOrder that failed in start() keeps PERSONAL_MOVE (distinct from pre-install rejection)")
	assert_null(leader_a.get_current_order())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(cause_events.size(), 1)
	assert_eq(cause_events[0]["order"], comm5)
	assert_eq(cause_events[0]["cause"], UnitOrder.InterruptionCause.PERSONAL_MOVE)
	board.close_task(task5, WorkTask.State.CANCELLED, "cleanup_r05")

	# --- A01-R06: Reentrancy during cancel() (worker_slot_released & ConstructOrder workers_changed) ---
	# Subcase 6a: worker_slot_released installs personal GatherResourceOrder -> PERSONAL_OTHER
	cause_events.clear()
	var reg6 := board.register_gather_task(rock)
	var task6: WorkTask = reg6["task"] as WorkTask
	disp._flush_dispatch()
	var comm6: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(comm6)

	var succ6 := GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, region_id)
	var cb6_fired := [false]
	var on_slot_r06 := func(_s: ResourceSource) -> void:
		if not cb6_fired[0]:
			cb6_fired[0] = true
			leader_a.issue_personal_order(succ6)
	rock.worker_slot_released.connect(on_slot_r06)
	assert_false(leader_a.issue_personal_order(MoveOrder.new(Vector3(7.0, 0.0, 7.0))))
	rock.worker_slot_released.disconnect(on_slot_r06)

	assert_true(cb6_fired[0])
	assert_eq(leader_a.get_current_order(), succ6)
	assert_eq(comm6.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_OTHER, "A01-R06a: cancel() callback successor commits PERSONAL_OTHER")
	assert_eq(int(fin_counts.get(comm6.get_instance_id(), 0)), 1)
	assert_eq(cause_events.size(), 1)
	assert_eq(cause_events[0]["cause"], UnitOrder.InterruptionCause.PERSONAL_OTHER)
	leader_a.cancel_current_order()
	board.close_task(task6, WorkTask.State.CANCELLED, "cleanup_r06")

	# Subcase 6b: ConstructOrder.cancel() -> workers_changed installs personal MoveOrder -> PERSONAL_MOVE
	cause_events.clear()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site_res := cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site_res.get("ok", false)))
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	var c_prev := ConstructOrder.new(site, camp, false, true, false)
	assert_true(leader_a.issue_personal_order(c_prev))
	var succ_mv6 := MoveOrder.new(Vector3(3.0, 0.0, -4.0))
	var cb6b_fired := [false]
	var on_workers_r06b := func(_s: ConstructionSite) -> void:
		if not cb6b_fired[0]:
			cb6b_fired[0] = true
			leader_a.issue_personal_order(succ_mv6)
	site.workers_changed.connect(on_workers_r06b)
	# Attempt GatherResourceOrder (PERSONAL_OTHER), preempted by MoveOrder (PERSONAL_MOVE) during ConstructOrder.cancel()!
	var attempt_g6 := GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, region_id)
	assert_false(leader_a.issue_personal_order(attempt_g6))
	site.workers_changed.disconnect(on_workers_r06b)

	assert_true(cb6b_fired[0])
	assert_eq(leader_a.get_current_order(), succ_mv6)
	assert_eq(c_prev.get_interruption_cause(), UnitOrder.InterruptionCause.PERSONAL_MOVE, "A01-R06b: ConstructOrder.cancel() callback MoveOrder commits PERSONAL_MOVE (not preempted Gather)")
	assert_eq(int(fin_counts.get(c_prev.get_instance_id(), 0)), 1)
	assert_eq(cause_events.size(), 1)
	assert_eq(cause_events[0]["order"], c_prev)
	assert_eq(cause_events[0]["cause"], UnitOrder.InterruptionCause.PERSONAL_MOVE)

	leader_a.cancel_current_order()
	leader_b.cancel_current_order()
	leader_a.order_finished.disconnect(on_fin_track)
	leader_a.order_interruption_cause_committed.disconnect(on_cause_track)
	await _teardown_isolated_main(ctx)


# ==============================================================================
# B2-R2-A02 (A02-R01..A02-R06): Controlled MainScene Teardown Reconciliation
# ==============================================================================
func test_b2_r2_a02_controlled_teardown_reconciliation_and_destruction() -> void:
	# --- A02-R01 + A02-R04 + A02-R05 + A02-R06:
	# Real MainScene.request_controlled_teardown() with:
	# - LeaderA executing provenance GatherResourceOrder (deferred during teardown locks -> finalized centrally after unlock)
	# - LeaderB executing unblocked MoveOrder (finalized in _exit_tree -> zero duplicate notification)
	# - Callback inside LeaderA's terminal order_finished trying personal & community re-admission -> both blocked!
	# - True destruction after queue_free() + release_regional_domain ok + D0-A04 pre-teardown snapshot!
	var ctx1 := await _boot_isolated_main(true)
	var main1: MainScene = ctx1["main"] as MainScene
	var board1: CommunityWorkBoard = ctx1["board"] as CommunityWorkBoard
	var disp1: CommunityTaskDispatcher = ctx1["dispatcher"] as CommunityTaskDispatcher
	var inv1: SettlementInventory = ctx1["inv"] as SettlementInventory
	var la1: Unit = ctx1["leader_a"] as Unit
	var lb1: Unit = ctx1["leader_b"] as Unit
	var rock1: ResourceSource = _find_source(main1, &"stone_rock_01")
	var tree1: ResourceSource = _find_source(main1, &"wood_tree_01")
	var region1: StringName = ctx1["region_id"] as StringName

	var snap1_before := Audit.capture(get_tree(), main1.get_world_3d(), region1, &"stone", inv1)
	assert_true(bool(snap1_before.get("ok", false)))

	var mv_b := MoveOrder.new(Vector3(-12.0, 0.0, -10.0))
	assert_true(lb1.issue_personal_order(mv_b))
	la1.global_position = rock1.global_position + Vector3(-1.8, 0.0, 0.0)
	var reg_r1 := board1.register_gather_task(rock1)
	var _task_r1: WorkTask = reg_r1["task"] as WorkTask
	disp1._flush_dispatch()
	var g_a: GatherResourceOrder = la1.get_current_order() as GatherResourceOrder
	assert_not_null(g_a, "A02-R01: provenance GatherResourceOrder active before controlled teardown")
	assert_true(g_a.has_reservation())

	var rev_a_before: int = la1.get_order_revision()
	var rev_b_before: int = lb1.get_order_revision()

	# Forged external call to _finalize_controlled_teardown_order while in-tree MUST be rejected!
	var forged_tok := RefCounted.new()
	assert_false(la1._finalize_controlled_teardown_order(forged_tok, g_a, rev_a_before), "A02-R01: forged teardown token must be rejected")
	assert_eq(la1.get_current_order(), g_a)
	assert_eq(la1.get_order_revision(), rev_a_before)

	var ev_log: Array[String] = []
	var la_fin_count := [0]
	var la_cause_count := [0]
	var lb_fin_count := [0]
	var readmit_personal_ok := [true]
	var readmit_comm_ok := [true]
	la1.order_finished.connect(func(o: UnitOrder) -> void:
		if o == g_a:
			la_fin_count[0] += 1
			ev_log.append("la_order_finished")
			# A02-R05: Attempt personal & community re-admission during terminal teardown notification!
			readmit_personal_ok[0] = la1.issue_personal_order(MoveOrder.new(Vector3.ZERO))
			var bogus_g := GatherResourceOrder.new(tree1, ctx1["camp"] as CampStorageZone, inv1, -1.0, -1.0, true, region1)
			readmit_comm_ok[0] = la1.issue_community_order(bogus_g, null)
	)
	la1.order_interruption_cause_committed.connect(func(o: UnitOrder, _c: UnitOrder.InterruptionCause) -> void:
		if o == g_a:
			la_cause_count[0] += 1
			ev_log.append("la_cause_committed")
	)
	lb1.order_finished.connect(func(o: UnitOrder) -> void:
		if o == mv_b:
			lb_fin_count[0] += 1
			ev_log.append("lb_order_finished")
	)

	var snap1_pre_td := Audit.capture(get_tree(), main1.get_world_3d(), region1, &"stone", inv1)
	assert_true(bool(Audit.verify_conservation(snap1_before, snap1_pre_td).get("ok", false)), "A02-R01: D0-A04 conservation at stable pre-teardown boundary")

	var td1: Dictionary = main1.request_controlled_teardown()
	assert_true(bool(td1.get("ok", false)), "A02-R01: controlled teardown succeeded")

	# Verify A02-R01 (GatherResourceOrder deferred by teardown locks -> reconciled via Unit)
	assert_true(g_a.is_finished(), "A02-R01: GatherResourceOrder reached terminal state")
	assert_eq(g_a.status, UnitOrder.Status.CANCELLED)
	assert_eq(g_a.failure_reason, UnitOrder.REASON_UNIT_EXITED)
	assert_eq(g_a.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL, "A02-R01: ADMIN_CANCEL committed")
	assert_null(la1.get_current_order(), "A02-R01: _current_order reconciled to null")
	assert_eq(la1.get_order_revision(), rev_a_before + 1, "A02-R01: _order_revision incremented once")
	assert_eq(la1.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "A02-R01: ControlMode reconciled to COMMUNITY_FREE")
	assert_eq(la1.get_active_order_origin(), UnitOrder.OrderOrigin.NONE)
	assert_eq(la1.get_state(), Unit.State.IDLE)
	assert_eq(la_fin_count[0], 1, "A02-R01: order_finished emitted EXACTLY ONCE")
	assert_eq(la_cause_count[0], 1, "A02-R01: order_interruption_cause_committed emitted EXACTLY ONCE")
	assert_true(g_a.was_finished_notified())
	assert_false(g_a.has_reservation(), "A02-R01: resource source slot released")

	# Verify A02-R04 (Unblocked MoveOrder finished in _exit_tree -> ZERO duplicate notification!)
	assert_true(mv_b.is_finished())
	assert_null(lb1.get_current_order())
	assert_eq(lb1.get_order_revision(), rev_b_before + 1)
	assert_eq(lb_fin_count[0], 1, "A02-R04: unblocked order notified EXACTLY ONCE (zero duplicate)")

	# Verify A02-R05 (Re-admission blocked during teardown callback)
	assert_false(readmit_personal_ok[0], "A02-R05: personal re-admission blocked during teardown")
	assert_false(readmit_comm_ok[0], "A02-R05: community re-admission blocked during teardown")
	assert_true(board1.get_active_tasks().is_empty(), "A02-R05: torn-down board stays empty")

	# Verify event ordering: unblocked lb finishes in _exit_tree before unlocked la finishes post-unlock
	assert_eq(ev_log, ["lb_order_finished", "la_order_finished", "la_cause_committed"], "A02-R06: deterministic teardown event order")

	# Verify legitimate regional domain release
	assert_true(bool(main1._last_domain_release_result.get("ok", false)), "A02-R06: release_regional_domain succeeded")

	# Verify A02-R06: Scene & units are truly freed after queue_free() processing!
	var vp1: SubViewport = ctx1["vp"] as SubViewport
	await wait_process_frames(3)
	assert_false(is_instance_valid(main1), "A02-R06: MainScene truly destroyed after queue_free()")
	assert_false(is_instance_valid(la1), "A02-R06: Unit truly destroyed after queue_free()")
	if is_instance_valid(vp1):
		if vp1.get_parent() != null:
			vp1.get_parent().remove_child(vp1)
		vp1.queue_free()
	await wait_process_frames(2)

	# --- A02-R02: Active ConstructOrder with empty carry load (preflight allowed) ---
	var ctx2 := await _boot_isolated_main(true)
	var main2: MainScene = ctx2["main"] as MainScene
	var inv2: SettlementInventory = ctx2["inv"] as SettlementInventory
	var camp2: CampStorageZone = ctx2["camp"] as CampStorageZone
	var cm2: ConstructionManager = ctx2["cm"] as ConstructionManager
	var la2: Unit = ctx2["leader_a"] as Unit
	var region2: StringName = ctx2["region_id"] as StringName

	assert_true(inv2.deposit(&"wood", 12))
	assert_true(inv2.deposit(&"stone", 6))
	var snap2_w_before := Audit.capture(get_tree(), main2.get_world_3d(), region2, &"wood", inv2)
	var site2_res := cm2.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site2_res.get("ok", false)))
	var site2: ConstructionSite = site2_res["site"] as ConstructionSite
	var c_order2 := ConstructOrder.new(site2, camp2, false, true, false)
	assert_true(la2.issue_personal_order(c_order2))
	assert_true(la2.get_carry_load().is_empty(), "A02-R02: carry load empty so preflight legitimately allows teardown")
	assert_ne(site2.get_worker_role(la2), ConstructionSite.WorkerRole.UNASSIGNED)

	var c2_fin_count := [0]
	la2.order_finished.connect(func(o: UnitOrder) -> void:
		if o == c_order2:
			c2_fin_count[0] += 1
	)
	var snap2_w_pre := Audit.capture(get_tree(), main2.get_world_3d(), region2, &"wood", inv2)
	assert_true(bool(Audit.verify_conservation(snap2_w_before, snap2_w_pre).get("ok", false)), "A02-R02: D0-A04 conservation before teardown")

	var td2: Dictionary = main2.request_controlled_teardown()
	assert_true(bool(td2.get("ok", false)), "A02-R02: controlled teardown allowed with active ConstructOrder and empty carry")
	assert_true(c_order2.is_finished())
	assert_null(la2.get_current_order())
	assert_eq(la2.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(c_order2.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL)
	assert_eq(c2_fin_count[0], 1, "A02-R02: ConstructOrder notified EXACTLY ONCE")
	assert_false(site2._assigned_workers.has(la2.get_instance_id()), "A02-R02: worker unregistered from site")
	assert_false(site2._pending_pickups.has(la2.get_instance_id()), "A02-R02: pickup claim released")
	assert_true(bool(main2._last_domain_release_result.get("ok", false)))
	var vp2: SubViewport = ctx2["vp"] as SubViewport
	await wait_process_frames(3)
	assert_false(is_instance_valid(main2), "A02-R02: MainScene destroyed after queue_free()")
	if is_instance_valid(vp2):
		if vp2.get_parent() != null:
			vp2.get_parent().remove_child(vp2)
		vp2.queue_free()
	await wait_process_frames(2)

	# --- A02-R03a & A02-R03b: RecoveryOrder preflight refusal (unsettled) vs post-settlement lock deferral ---
	var ctx3 := await _boot_isolated_main(true)
	var main3: MainScene = ctx3["main"] as MainScene
	var inv3: SettlementInventory = ctx3["inv"] as SettlementInventory
	var cm3: ConstructionManager = ctx3["cm"] as ConstructionManager
	var cmd3: CommandController = ctx3["cmd"] as CommandController
	var la3: Unit = ctx3["leader_a"] as Unit
	var world3: World3D = main3.get_world_3d()
	var region3: StringName = ctx3["region_id"] as StringName

	assert_true(inv3.deposit(&"wood", 12))
	assert_true(inv3.deposit(&"stone", 6))
	var snap3_w_before := Audit.capture(get_tree(), world3, region3, &"wood", inv3)
	var site3_res := cm3.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site3_res.get("ok", false)))
	var site3: ConstructionSite = site3_res["site"] as ConstructionSite
	assert_true(cmd3.command_units_to_site(site3, [la3]))
	assert_true(await _until(func() -> bool: return site3.get_delivered_buffer_amount(&"wood") > 0 or site3._work_progress_usec > 0, 3600))
	var cancel3 := ReservedWithdrawalCoordinator.execute_site_cancellation(site3, &"a02_r03_cancel")
	assert_true(cancel3.ok)
	var cancel_id3: StringName = cancel3.receipt.cancel_id
	cm3._recovery_dispatcher._flush()
	var rec3: RecoveryOrder = la3.get_current_order() as RecoveryOrder
	assert_not_null(rec3, "A02-R03a: RecoveryOrder active on LeaderA")
	var rec_record3 := CancellationRecoveryTransaction._record(world3, region3, cancel_id3)
	assert_true(rec_record3.has_unsettled_custody())

	# A02-R03a: Teardown MUST be refused by preflight_economic_teardown() while custody is unsettled!
	var td3_refused: Dictionary = main3.request_controlled_teardown()
	assert_false(bool(td3_refused.get("ok", false)), "A02-R03a: teardown MUST be refused while cancellation custody is unsettled")
	assert_eq(String(td3_refused.get("reason", "")), "pending_cancellation_custody")
	assert_true(main3.is_inside_tree(), "A02-R03a: MainScene preserved intact")
	assert_eq(la3.get_current_order(), rec3, "A02-R03a: RecoveryOrder preserved intact")

	# A02-R03b: Settle custody legitimately, then confirm clean controlled teardown after natural completion.
	assert_true(await _until(func() -> bool: return rec_record3.state == ConstructionCancellationMath.State.SETTLED, 4800), "A02-R03b: recovery legitimately settles custody")
	var snap3_w_after := Audit.capture(get_tree(), world3, region3, &"wood", inv3)
	assert_true(bool(Audit.verify_conservation(snap3_w_before, snap3_w_after).get("ok", false)), "A02-R03b: D0-A04 wood conservation after settlement")
	assert_true(await _until(func() -> bool: return la3.get_current_order() == null, 60), "A02-R03b: single worker finishes RecoveryOrder cleanly")
	var td3_post: Dictionary = main3.request_controlled_teardown()
	assert_true(bool(td3_post.get("ok", false)), "A02-R03b: teardown succeeds cleanly once custody is settled")
	assert_true(bool(main3._last_domain_release_result.get("ok", false)))

	var vp3: SubViewport = ctx3["vp"] as SubViewport
	await wait_process_frames(3)
	assert_false(is_instance_valid(main3), "A02-R03b: MainScene truly destroyed after queue_free()")
	if is_instance_valid(vp3):
		if vp3.get_parent() != null:
			vp3.get_parent().remove_child(vp3)
		vp3.queue_free()
	await wait_process_frames(2)

	# --- A02-R03c (B2-R3-A02): Deterministic two-worker RecoveryOrder still ACTIVE when custody reaches SETTLED ---
	# Proves the exact deferred-lock finalization path for RecoveryOrder without conditional branching!
	var ctx3c := await _boot_isolated_main(true)
	var main3c: MainScene = ctx3c["main"] as MainScene
	var inv3c: SettlementInventory = ctx3c["inv"] as SettlementInventory
	var cm3c: ConstructionManager = ctx3c["cm"] as ConstructionManager
	var cmd3c: CommandController = ctx3c["cmd"] as CommandController
	var la3c: Unit = ctx3c["leader_a"] as Unit
	var lb3c: Unit = ctx3c["leader_b"] as Unit
	var world3c: World3D = main3c.get_world_3d()
	var region3c: StringName = ctx3c["region_id"] as StringName

	assert_true(inv3c.deposit(&"wood", 12))
	assert_true(inv3c.deposit(&"stone", 6))
	var snap3c_w_before := Audit.capture(get_tree(), world3c, region3c, &"wood", inv3c)
	var site3c_res := cm3c.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site3c_res.get("ok", false)))
	var site3c: ConstructionSite = site3c_res["site"] as ConstructionSite
	assert_true(cmd3c.command_units_to_site(site3c, [la3c, lb3c]))
	assert_true(await _until(func() -> bool:
		return site3c.get_delivered_buffer_amount(&"wood") > 0 and site3c._assigned_workers.has(la3c.get_instance_id()) and site3c._assigned_workers.has(lb3c.get_instance_id())
	, 3600), "A02-R03c: both founders assigned to site with delivered custody")

	var cancel3c := ReservedWithdrawalCoordinator.execute_site_cancellation(site3c, &"a02_r03c_cancel")
	assert_true(cancel3c.ok)
	var cancel_id3c: StringName = cancel3c.receipt.cancel_id
	cm3c._recovery_dispatcher._flush()
	var rec_a3c := la3c.get_current_order() as RecoveryOrder
	var rec_b3c := lb3c.get_current_order() as RecoveryOrder
	assert_not_null(rec_a3c, "A02-R03c: LeaderA holds active RecoveryOrder")
	assert_not_null(rec_b3c, "A02-R03c: LeaderB holds active RecoveryOrder")
	var rec_record3c := CancellationRecoveryTransaction._record(world3c, region3c, cancel_id3c)

	assert_true(await _until(func() -> bool:
		if rec_record3c.state != ConstructionCancellationMath.State.SETTLED:
			return false
		var a_act: bool = rec_a3c.is_active() and la3c.get_current_order() == rec_a3c
		var b_act: bool = rec_b3c.is_active() and lb3c.get_current_order() == rec_b3c
		return a_act or b_act
	, 4800), "A02-R03c: custody settles while peer RecoveryOrder is still legitimately active")

	var snap3c_w_after := Audit.capture(get_tree(), world3c, region3c, &"wood", inv3c)
	assert_true(bool(Audit.verify_conservation(snap3c_w_before, snap3c_w_after).get("ok", false)), "A02-R03c: D0-A04 wood conservation")
	var pre3c: Dictionary = main3c.preflight_economic_teardown()
	assert_true(bool(pre3c.get("ok", false)), "A02-R03c: preflight_economic_teardown permits teardown once settled")

	var peer_unit: Unit = la3c if (rec_a3c.is_active() and la3c.get_current_order() == rec_a3c) else lb3c
	var peer_rec: RecoveryOrder = rec_a3c if peer_unit == la3c else rec_b3c
	assert_true(peer_rec.is_active(), "A02-R03c: peer RecoveryOrder MUST still be active right before teardown")
	var peer_rev_before: int = peer_unit.get_order_revision()
	var peer_fin_count := [0]
	var peer_cause_count := [0]
	peer_unit.order_finished.connect(func(o: UnitOrder) -> void:
		if o == peer_rec:
			peer_fin_count[0] += 1
	)
	peer_unit.order_interruption_cause_committed.connect(func(o: UnitOrder, _c: UnitOrder.InterruptionCause) -> void:
		if o == peer_rec:
			peer_cause_count[0] += 1
	)

	var td3c: Dictionary = main3c.request_controlled_teardown()
	assert_true(bool(td3c.get("ok", false)), "A02-R03c: teardown finalizes settled peer RecoveryOrder after unlock")
	assert_true(peer_rec.is_finished(), "A02-R03c: peer RecoveryOrder reached terminal state")
	assert_eq(peer_rec.status, UnitOrder.Status.CANCELLED)
	assert_eq(peer_rec.failure_reason, UnitOrder.REASON_UNIT_EXITED)
	assert_eq(peer_rec.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL)
	assert_null(peer_unit.get_current_order(), "A02-R03c: no remaining active order on unit")
	assert_eq(peer_unit.get_order_revision(), peer_rev_before + 1, "A02-R03c: revision incremented once")
	assert_eq(peer_unit.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(peer_unit.get_state(), Unit.State.IDLE)
	assert_eq(peer_fin_count[0], 1, "A02-R03c: RecoveryOrder notified EXACTLY ONCE")
	assert_eq(peer_cause_count[0], 1, "A02-R03c: interruption cause committed EXACTLY ONCE")
	assert_true(bool(main3c._last_domain_release_result.get("ok", false)), "A02-R03c: regional domain released legitimately")

	var vp3c: SubViewport = ctx3c["vp"] as SubViewport
	await wait_process_frames(3)
	assert_false(is_instance_valid(main3c), "A02-R03c: MainScene truly destroyed after queue_free()")
	assert_false(is_instance_valid(peer_unit), "A02-R03c: peer Unit truly destroyed after queue_free()")
	if is_instance_valid(vp3c):
		if vp3c.get_parent() != null:
			vp3c.get_parent().remove_child(vp3c)
		vp3c.queue_free()
	await wait_process_frames(2)
