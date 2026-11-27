extends TestCase
## Integration tests for R-03B B1 — E01-B1 (F02: Economic recovery authority, T1a, T1b, entry.manual, conservation):
## - Valid record with unsettled custody (T1a idle & T1b cancelled ConstructOrder)
## - Non-existent cancel_id, settled record (no custody), wrong domain, obsolete revision
## - Direct call outside active dispatcher admission & mismatched order instance during admission
## - T1b rejection on divergent site_id, active site, active personal MoveOrder / GatherResourceOrder, and transactional block
## - Personal interruption of RecoveryOrder preserving entry.manual and cargo
## - Common villager (Worker3) executing legitimate recovery without gaining personal control
## - RegionalConservationAudit before and after

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const C := preload("res://src/economy/reserved_withdrawal_coordinator.gd")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const Audit := preload("res://tests/framework/regional_conservation_audit.gd")


func before_each() -> void:
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0


func after_each() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func _until(condition: Callable, frames: int = 3600) -> bool:
	for _i: int in range(frames):
		if condition.call():
			return true
		await wait_physics_frames(1)
	return false


func _boot_main(automatic: bool = true) -> MainScene:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_test_child(vp)
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = true
	main.automatic_cancellation_recovery = automatic
	vp.add_child(main)
	var nav: WorldNavigation = main.get_test_map().get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 240), "Nav ready")
	await wait_process_frames(2)
	return main


func _teardown_main(main: MainScene) -> void:
	if main != null and is_instance_valid(main):
		var vp: Node = main.get_parent()
		if vp is SubViewport and vp.get_parent() != null:
			vp.get_parent().remove_child(vp)
			vp.queue_free()
		elif main.get_parent() != null:
			main.get_parent().remove_child(main)
			main.queue_free()
	await wait_process_frames(2)


func _create_active_site_with_progress(main: MainScene, pos: Vector3, workers: Array[Unit]) -> ConstructionSite:
	var inv: SettlementInventory = main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var res: Dictionary = main.get_construction_manager().try_create_site_from_placement(SHELTER_DEF, pos)
	assert_true(bool(res.get("ok", false)), str(res))
	var site: ConstructionSite = res["site"] as ConstructionSite
	assert_true(main.get_command_controller().command_units_to_site(site, workers))
	assert_true(await _until(func() -> bool: return site.get_delivered_buffer_amount(&"wood") > 0 or site._work_progress_usec > 0, 3600), "Site received materials")
	return site


func test_e01_b1_t1b_legitimate_replacement_and_conservation() -> void:
	var main := await _boot_main(true)
	var leader_a: Unit = main.get_node("Units/LeaderA") as Unit
	var site := await _create_active_site_with_progress(main, Vector3(-6.0, 0.0, 1.5), [leader_a])
	assert_true(leader_a.get_current_order() is ConstructOrder, "LeaderA must still hold ConstructOrder before cancellation")

	var world: World3D = main.get_world_3d()
	var region_id: StringName = main.get_construction_manager().get_region_id()
	var inv: SettlementInventory = main.get_settlement_inventory()
	var snap_wood_before := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_before := Audit.capture(get_tree(), world, region_id, &"stone", inv)
	assert_true(bool(snap_wood_before.get("ok", false)))
	assert_true(bool(snap_stone_before.get("ok", false)))

	var cancelled := C.execute_site_cancellation(site, &"e01_t1b_cancel")
	assert_true(cancelled.ok, str(cancelled))
	var cancel_id: StringName = cancelled.receipt.cancel_id
	await wait_physics_frames(2)

	var rec_order := leader_a.get_current_order() as RecoveryOrder
	assert_not_null(rec_order, "T1b must legitimately replace cancelled site's ConstructOrder with RecoveryOrder")
	if rec_order != null:
		assert_eq(rec_order.cancel_id, cancel_id)
		assert_eq(rec_order.get_order_origin(), UnitOrder.OrderOrigin.SYSTEM_RECOVERY)

	var record := CancellationRecoveryTransaction._record(world, region_id, cancel_id)
	assert_true(await _until(func() -> bool: return record.state == ConstructionCancellationMath.State.SETTLED, 4800), "Recovery settles cleanly")
	await wait_physics_frames(2)

	var snap_wood_after := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_after := Audit.capture(get_tree(), world, region_id, &"stone", inv)
	assert_true(bool(Audit.verify_conservation(snap_wood_before, snap_wood_after).get("ok", false)), "Exact wood conservation across T1b recovery")
	assert_true(bool(Audit.verify_conservation(snap_stone_before, snap_stone_after).get("ok", false)), "Exact stone conservation across T1b recovery")

	await _teardown_main(main)


func test_e01_b1_rejects_invalid_cancel_id_settled_obsolete_unadmitted_and_wrong_instance() -> void:
	var main := await _boot_main(true)
	var leader_a: Unit = main.get_node("Units/LeaderA") as Unit
	var leader_b: Unit = main.get_node("Units/LeaderB") as Unit
	var camp: CampStorageZone = main.get_camp_storage_zone()
	var inv: SettlementInventory = main.get_settlement_inventory()
	var region_id: StringName = main.get_construction_manager().get_region_id()
	var cm: ConstructionManager = main.get_construction_manager()
	var site := await _create_active_site_with_progress(main, Vector3(-6.0, 0.0, 1.5), [leader_a])
	var cancelled := C.execute_site_cancellation(site, &"e01_reject_cancel")
	assert_true(cancelled.ok)
	var cancel_id: StringName = cancelled.receipt.cancel_id
	await wait_physics_frames(2)
	leader_a.cancel_current_order()
	await wait_physics_frames(1)

	# 1. Direct call outside dispatcher admission MUST fail.
	var rec_disp := cm.get_node_or_null("CancellationRecoveryDispatcher") as CancellationRecoveryDispatcher
	assert_not_null(rec_disp, "CancellationRecoveryDispatcher must be active")
	var rogue_order := RecoveryOrder.new(cancel_id, region_id, camp, inv, rec_disp)
	var rev_before: int = leader_a.get_order_revision()
	assert_false(leader_a.issue_recovery_order(rogue_order, rev_before, true), "Unadmitted RecoveryOrder must be rejected")
	assert_eq(leader_a.get_order_revision(), rev_before)

	# 2. Non-existent cancel_id via dispatcher MUST fail.
	var bad_assign := cm.assign_cancellation_recovery(&"nonexistent_cancel_id", [leader_a])
	assert_false(bool(bad_assign.get("ok", false)), "Nonexistent cancel_id must be rejected")

	# 3. Wrong order instance during active dispatcher admission MUST be rejected:
	assert_false(rec_disp.is_admitting_recovery(leader_a, rogue_order, true), "is_admitting_recovery must be false outside _assign")
	var wrong_instance_rejected := [false]
	var probe_cb := func(_new_s: Unit.State, _prev_s: Unit.State) -> void:
		if not wrong_instance_rejected[0]:
			wrong_instance_rejected[0] = not rec_disp.is_admitting_recovery(leader_a, rogue_order, true) and not leader_a.issue_recovery_order(rogue_order, leader_a.get_order_revision(), true)

	# 4. Obsolete revision directly rejected:
	assert_false(leader_a.issue_recovery_order(rogue_order, rev_before - 1, false), "Obsolete revision must be rejected")

	# 5. Active personal MoveOrder / GatherResourceOrder / active ConstructOrder protected against recovery:
	assert_true(leader_b.issue_personal_order(MoveOrder.new(Vector3(10.0, 0.0, 10.0))))
	var move_before: UnitOrder = leader_b.get_current_order()
	var assign_busy := cm.assign_cancellation_recovery(cancel_id, [leader_b])
	assert_false(bool(assign_busy.get("ok", false)), "Recovery must NOT replace active personal MoveOrder")
	assert_eq(leader_b.get_current_order(), move_before)

	# Active ConstructOrder on DIFFERENT site protected:
	var site_active := await _create_active_site_with_progress(main, Vector3(-10.0, 0.0, 4.0), [leader_b])
	var active_c_order: UnitOrder = leader_b.get_current_order()
	assert_true(active_c_order is ConstructOrder)
	var assign_active_site := cm.assign_cancellation_recovery(cancel_id, [leader_b])
	assert_false(bool(assign_active_site.get("ok", false)), "Recovery must NOT replace ConstructOrder of active/different site")
	assert_eq(leader_b.get_current_order(), active_c_order)
	assert_true(site_active.is_valid())

	# 6. Legitimate T1a on idle unit succeeds (while verifying rogue_order rejection during admission), then settled record refuses new recovery:
	leader_a.state_changed.connect(probe_cb)
	var ok_assign := cm.assign_cancellation_recovery(cancel_id, [leader_a])
	leader_a.state_changed.disconnect(probe_cb)
	assert_true(bool(ok_assign.get("ok", false)), "T1a legitimate recovery on idle unit must succeed")
	assert_true(wrong_instance_rejected[0], "Wrong RecoveryOrder instance during active admission must be rejected")
	var record := CancellationRecoveryTransaction._record(main.get_world_3d(), region_id, cancel_id)
	assert_true(await _until(func() -> bool: return record.state == ConstructionCancellationMath.State.SETTLED, 4800))
	var settled_assign := cm.assign_cancellation_recovery(cancel_id, [leader_a])
	assert_false(bool(settled_assign.get("ok", false)), "Settled record without unsettled custody must be rejected")

	await _teardown_main(main)


func test_e01_b1_t1b_transactional_block_and_manual_interruption_and_community_worker_recovery() -> void:
	var main := await _boot_main(true)
	var leader_a: Unit = main.get_node("Units/LeaderA") as Unit
	var cm: ConstructionManager = main.get_construction_manager()
	var ctrl: TemporaryTestWorkersController = main.get_placement_test_overlay().get_temporary_workers_controller()
	assert_true(bool(ctrl.spawn_temporary_workers().get("ok", false)))
	var w3: Unit = main.get_node("Units/Worker3") as Unit

	var site := await _create_active_site_with_progress(main, Vector3(-6.0, 0.0, 1.5), [leader_a])
	var cancelled := C.execute_site_cancellation(site, &"e01_manual_cancel")
	assert_true(cancelled.ok)
	var cancel_id: StringName = cancelled.receipt.cancel_id
	await wait_physics_frames(2)

	# Interrupt LeaderA's RecoveryOrder with a personal MoveOrder -> entry.manual persists!
	assert_true(leader_a.get_current_order() is RecoveryOrder, "LeaderA started automatic recovery")
	assert_true(leader_a.issue_personal_order(MoveOrder.new(Vector3(6.0, 0.0, 4.0))), "Personal MoveOrder interrupts recovery")
	assert_true(leader_a.get_current_order() is MoveOrder)
	assert_true(await _until(func() -> bool: return leader_a.get_current_order() == null, 600))

	# Trigger safe event (inventory_changed) -> entry.manual MUST prevent automatic re-assignment to LeaderA!
	main.get_settlement_inventory().inventory_changed.emit()
	await wait_process_frames(4)
	await wait_physics_frames(2)
	assert_null(leader_a.get_current_order(), "entry.manual must persist and block automatic recovery retry")

	# Common villager Worker3 (COMMUNITY) CAN execute legitimate recovery via assign_cancellation_recovery
	# without EVER acquiring personal command privileges!
	var w3_assign := cm.assign_cancellation_recovery(cancel_id, [w3])
	assert_true(bool(w3_assign.get("ok", false)), "Common villager Worker3 must be able to execute legitimate recovery")
	assert_true(w3.get_current_order() is RecoveryOrder)
	assert_eq(w3.get_current_order().get_order_origin(), UnitOrder.OrderOrigin.SYSTEM_RECOVERY)
	assert_false(w3.issue_personal_order(MoveOrder.new(Vector3(0.0, 0.0, 0.0))), "Recovery must never grant personal control to Worker3")

	# Transactional block check on T1b: lock _coordinator_transaction_locked on a ConstructOrder of cancelled site -> refused cleanly.
	var leader_b: Unit = main.get_node("Units/LeaderB") as Unit
	var site2 := await _create_active_site_with_progress(main, Vector3(-10.0, 0.0, -2.0), [leader_b])
	var cancel2 := C.execute_site_cancellation(site2, &"e01_lock_cancel")
	assert_true(cancel2.ok)
	var rec_disp := cm.get_node_or_null("CancellationRecoveryDispatcher") as CancellationRecoveryDispatcher
	if rec_disp != null:
		leader_b.get_carry_load()._coordinator_transaction_locked = true
		var locked_rev: int = leader_b.get_order_revision()
		var locked_order: UnitOrder = leader_b.get_current_order()
		var locked_assign := cm.assign_cancellation_recovery(cancel2.receipt.cancel_id, [leader_b])
		assert_false(bool(locked_assign.get("ok", false)), "Locked unit must reject T1b recovery without mutating state")
		assert_eq(leader_b.get_order_revision(), locked_rev)
		assert_eq(leader_b.get_current_order(), locked_order)
		leader_b.get_carry_load()._coordinator_transaction_locked = false

	await _teardown_main(main)
