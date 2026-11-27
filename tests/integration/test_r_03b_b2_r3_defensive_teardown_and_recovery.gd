extends TestCase
## Dedicated focal adversarial tests for R-03B B2-R3:
## - B2-R3-A01 (A01-R01..A01-R04): Explicit defensive handling when controlled teardown finalization fails,
##   token preservation on recoverable transactional locks, classification of failures, prevention of premature
##   domain release and queue_free(), subsequent completion via complete_pending_controlled_teardown(),
##   and clean handling of already-reconciled _exit_tree() orders.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const Audit := preload("res://tests/framework/regional_conservation_audit.gd")


func before_each() -> void:
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0


func _boot_isolated_main() -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(320, 180)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_test_child(vp)

	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = true
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
		"board": main.get_community_work_board(),
		"dispatcher": main.get_community_task_dispatcher(),
		"inv": main.get_settlement_inventory(),
		"camp": main.get_camp_storage_zone(),
		"cm": main.get_construction_manager(),
		"leader_a": main.get_node("Units/LeaderA") as Unit,
		"leader_b": main.get_node("Units/LeaderB") as Unit,
		"region_id": main.get_construction_manager().get_region_id(),
	}


func _find_source(main: MainScene, sid: StringName) -> ResourceSource:
	for s: ResourceSource in main.get_test_map().get_resource_sources():
		if s.get_source_id() == sid:
			return s
	return null


func test_b2_r3_a01_teardown_failure_guards_token_preservation_and_completion() -> void:
	# --- A01-R01a + A01-R03 + A01-R04: Recoverable transfer lock during request_controlled_teardown() ---
	var ctx1 := await _boot_isolated_main()
	var main1: MainScene = ctx1["main"] as MainScene
	var board1: CommunityWorkBoard = ctx1["board"] as CommunityWorkBoard
	var disp1: CommunityTaskDispatcher = ctx1["dispatcher"] as CommunityTaskDispatcher
	var inv1: SettlementInventory = ctx1["inv"] as SettlementInventory
	var la1: Unit = ctx1["leader_a"] as Unit
	var lb1: Unit = ctx1["leader_b"] as Unit
	var rock1: ResourceSource = _find_source(main1, &"stone_rock_01")
	var world1: World3D = main1.get_world_3d()
	var region1: StringName = ctx1["region_id"] as StringName

	var cm1: ConstructionManager = ctx1["cm"] as ConstructionManager
	assert_true(inv1.deposit(&"wood", 12), "deposit wood")
	assert_true(inv1.deposit(&"stone", 6), "deposit stone")
	var bind_site_res := cm1.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(bind_site_res.get("ok", false)), "create site to bind regional authority")
	var bind_cancel := ReservedWithdrawalCoordinator.execute_site_cancellation(bind_site_res["site"] as ConstructionSite, &"b2_r3_bind_auth")
	assert_true(bind_cancel.ok, "empty site cancellation binds regional authority and settles cleanly")
	var storage1: GroundPileManager = inv1.get_storage_source() as GroundPileManager
	var snap1_before := Audit.capture(get_tree(), world1, region1, &"wood", inv1)
	assert_true(bool(snap1_before.get("ok", false)), "capture initial conservation snapshot")
	assert_not_null(CancellationRecoveryTransaction._authority(world1, region1), "Regional authority bound before teardown")

	# LeaderB runs a normal unblocked MoveOrder (A01-R03: reconciled in _exit_tree -> ZERO duplicate notification).
	var mv_b := MoveOrder.new(Vector3(-12.0, 0.0, -10.0))
	assert_true(lb1.issue_personal_order(mv_b))
	var lb_fin_cnt := [0]
	lb1.order_finished.connect(func(o: UnitOrder) -> void:
		if o == mv_b:
			lb_fin_cnt[0] += 1
	)

	# LeaderA runs real community GatherResourceOrder with empty carry load (preflight ok)
	# and active provenance GatherTransferSession (can_cancel_now() == false after teardown unlock!).
	la1.global_position = rock1.global_position + Vector3(-1.8, 0.0, 0.0)
	board1.register_gather_task(rock1)
	disp1._flush_dispatch()
	var g1 := la1.get_current_order() as GatherResourceOrder
	assert_not_null(g1)
	var gs := GatherTransferSession.new()
	gs.is_executing = true
	g1._active_gather_session = gs

	var la_rev_before: int = la1.get_order_revision()
	var la_fin_cnt := [0]
	var la_cause_cnt := [0]
	la1.order_finished.connect(func(o: UnitOrder) -> void:
		if o == g1:
			la_fin_cnt[0] += 1
	)
	la1.order_interruption_cause_committed.connect(func(o: UnitOrder, _c: UnitOrder.InterruptionCause) -> void:
		if o == g1:
			la_cause_cnt[0] += 1
	)

	# A01-R04: Conservation holds at stable pre-teardown boundary
	var snap1_pre := Audit.capture(get_tree(), world1, region1, &"wood", inv1)
	assert_true(bool(Audit.verify_conservation(snap1_before, snap1_pre).get("ok", false)))

	var td_fail: Dictionary = main1.request_controlled_teardown()
	assert_false(bool(td_fail.get("ok", false)), "A01-R01a: MainScene MUST NOT report ok=true when order finalization failed")
	assert_eq(String(td_fail.get("reason", "")), "order_still_active_locked")
	var failures: Array = td_fail.get("failures", []) as Array
	assert_eq(failures.size(), 1)
	assert_eq(String(failures[0].get("classification", "")), "transactional_finalization_refused")
	assert_false(main1.is_queued_for_deletion(), "A01-R01a: MainScene MUST NOT call queue_free() when active order remains")
	assert_true(g1.is_active(), "A01-R01a: GatherResourceOrder stayed active")
	assert_eq(la1.get_current_order(), g1)
	assert_eq(la1.get_order_revision(), la_rev_before, "A01-R01a: revision preserved")
	assert_eq(la_fin_cnt[0], 0, "A01-R01a: ZERO false order_finished")
	assert_eq(la_cause_cnt[0], 0)
	assert_false(g1.was_finished_notified())
	assert_eq(g1.get_interruption_cause(), UnitOrder.InterruptionCause.NONE)
	assert_false(storage1._is_shut_down, "A01-R01a: storage MUST NOT shut down on finalization failure")
	assert_not_null(CancellationRecoveryTransaction._authority(world1, region1), "A01-R01a: regional authority NOT released prematurely")
	assert_not_null(la1._controlled_teardown_token, "A01-R01a: recoverable refusal MUST preserve _controlled_teardown_token for legitimate completion")
	assert_eq(lb_fin_cnt[0], 1, "A01-R03: unblocked order still finished cleanly once in _exit_tree")

	# Wait 2 frames -> confirm MainScene and LeaderA were NOT destroyed while locked!
	await wait_process_frames(2)
	assert_true(is_instance_valid(main1) and is_instance_valid(la1), "A01-R01a: scene/unit remain intact until legitimately reconciled")
	assert_eq(lb_fin_cnt[0], 1, "A01-R03: unblocked order receives ZERO duplicate notifications across retry")

	# Now unlock secondary gather session and run legitimate completion!
	g1._active_gather_session = null
	var td_retry: Dictionary = main1.complete_pending_controlled_teardown()
	assert_true(bool(td_retry.get("ok", false)), "A01-R01a: complete_pending_controlled_teardown succeeds once unlocked")
	assert_true(g1.is_finished())
	assert_eq(g1.status, UnitOrder.Status.CANCELLED)
	assert_eq(g1.failure_reason, UnitOrder.REASON_UNIT_EXITED)
	assert_eq(g1.get_interruption_cause(), UnitOrder.InterruptionCause.ADMIN_CANCEL)
	assert_null(la1.get_current_order())
	assert_eq(la1.get_order_revision(), la_rev_before + 1)
	assert_eq(la1.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(la_fin_cnt[0], 1, "A01-R01a: finalized order emits order_finished EXACTLY ONCE")
	assert_eq(la_cause_cnt[0], 1, "A01-R01a: cause committed EXACTLY ONCE")
	assert_eq(lb_fin_cnt[0], 1, "A01-R03: retry does NOT re-notify already-reconciled MoveOrder")
	assert_true(storage1._is_shut_down, "A01-R01a: storage shut down after full reconciliation")
	assert_true(bool(main1._last_domain_release_result.get("ok", false)), "A01-R01a: domain release succeeded after reconciliation")
	assert_true(bool(main1._last_domain_release_result.get("released", false)), "A01-R01a: regional authority released == true")
	assert_null(CancellationRecoveryTransaction._authority(world1, region1), "A01-R01a: regional authority released after reconciliation")

	var vp1: SubViewport = ctx1["vp"] as SubViewport
	await wait_process_frames(3)
	assert_false(is_instance_valid(main1), "A01-R01a: MainScene freed after full reconciliation")
	assert_false(is_instance_valid(la1), "A01-R01a: Unit freed after full reconciliation")
	if is_instance_valid(vp1):
		if vp1.get_parent() != null:
			vp1.get_parent().remove_child(vp1)
		vp1.queue_free()
	await wait_process_frames(2)

	# --- A01-R01b: Identity / token mismatch failure blocks destruction & classifies as incompatible_identity ---
	var ctx2 := await _boot_isolated_main()
	var main2: MainScene = ctx2["main"] as MainScene
	var inv2: SettlementInventory = ctx2["inv"] as SettlementInventory
	var camp2: CampStorageZone = ctx2["camp"] as CampStorageZone
	var cm2: ConstructionManager = ctx2["cm"] as ConstructionManager
	var la2: Unit = ctx2["leader_a"] as Unit

	assert_true(inv2.deposit(&"wood", 12))
	assert_true(inv2.deposit(&"stone", 6))
	var site2_res := cm2.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site2_res.get("ok", false)))
	var site2: ConstructionSite = site2_res["site"] as ConstructionSite
	var c2 := ConstructOrder.new(site2, camp2, false, true, false)
	assert_true(la2.issue_personal_order(c2))
	c2._provenance_transfer.is_executing = true

	var td2_fail: Dictionary = main2.request_controlled_teardown()
	assert_false(bool(td2_fail.get("ok", false)), "A01-R01b: ConstructOrder active transfer prevents premature teardown")
	assert_false(main2.is_queued_for_deletion())

	# Wipe token externally to force an incompatible_identity mismatch on pending completion attempt
	la2._clear_controlled_teardown_token(main2._pending_controlled_teardown["token"] as RefCounted)
	var td2_mismatch: Dictionary = main2.complete_pending_controlled_teardown()
	assert_false(bool(td2_mismatch.get("ok", false)), "A01-R01b: token mismatch must NOT report ok=true")
	assert_eq(String(td2_mismatch.get("reason", "")), "teardown_token_mismatch")
	assert_eq(String((td2_mismatch.get("failures", []) as Array)[0].get("classification", "")), "incompatible_identity")
	assert_false(main2.is_queued_for_deletion(), "A01-R01b: identity mismatch must NOT trigger queue_free()")
	assert_true(c2.is_active())

	# Clean up test scene safely after verifying refusal invariants
	c2._provenance_transfer.is_executing = false
	var cleanup_tok := RefCounted.new()
	la2._controlled_teardown_token = cleanup_tok
	main2._pending_controlled_teardown["token"] = cleanup_tok
	assert_true(bool(main2.complete_pending_controlled_teardown().get("ok", false)), "A01-R01b: cleanup complete_pending_controlled_teardown succeeds after unlocking and restoring token")
	var vp2: SubViewport = ctx2["vp"] as SubViewport
	await wait_process_frames(3)
	assert_false(is_instance_valid(main2), "A01-R01b: MainScene destroyed after cleanup")
	if is_instance_valid(vp2):
		if vp2.get_parent() != null:
			vp2.get_parent().remove_child(vp2)
		vp2.queue_free()
	await wait_process_frames(2)
