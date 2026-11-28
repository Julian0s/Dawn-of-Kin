extends TestCase
## Integration tests for R-03B B3:
## - E01-B3: Recovery T1c (auto recovery refused during PERSONAL_POST_MOVE_WAIT preserving timer & entries,
##   forged explicit=true refused, legitimate CancellationRecoveryDispatcher.assign() admitted cancelling wait,
##   entry.manual inviolability before/during/after D-05 expiration, RegionalConservationAudit D0-A04)
## - G01: Event-driven SelectedUnitPanel discrete labels (Trabalho comunitário / Ordem pessoal / Aguardando retorno /
##   Morador — somente leitura), zero polling, zero countdown digits, clean teardown, and D4-A01 banner coexistence at 720p & 1080p.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const Audit := preload("res://tests/framework/regional_conservation_audit.gd")


func before_each() -> void:
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 1.0


func after_each() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0


func _boot_main(wait_sec: float = 0.25, vp_size: Vector2i = Vector2i(1280, 720)) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = vp_size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = true
	main.automatic_cancellation_recovery = true
	main.use_d2_2_hud = false
	main.experimental_personal_post_move_wait_sec = wait_sec
	vp.add_child(main)
	await wait_process_frames(3)
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
		"sel": main.get_selection_manager(),
		"inv": main.get_settlement_inventory(),
		"camp": main.get_camp_storage_zone(),
		"cm": main.get_construction_manager(),
		"hud": main.get_resource_hud(),
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


func _until(predicate: Callable, max_frames: int = 2400) -> bool:
	for _i: int in range(max_frames):
		if predicate.call():
			return true
		await wait_physics_frames(1)
	return predicate.call()


func _find_source(main: MainScene, sid: StringName) -> ResourceSource:
	for s: ResourceSource in main.get_test_map().get_resource_sources():
		if s.get_source_id() == sid:
			return s
	return null


# ==============================================================================
# E01-B3: Recovery T1c, forged explicit refusal, timer preservation, entry.manual, D0-A04
# ==============================================================================
func test_e01_b3_recovery_t1c_auto_refusal_forged_refusal_explicit_admission_and_entry_manual() -> void:
	var ctx := await _boot_main(2.0, Vector2i(320, 180))
	var main: MainScene = ctx["main"] as MainScene
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var world: World3D = main.get_world_3d()
	var region_id: StringName = ctx["region_id"] as StringName

	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var snap_wood_0 := Audit.capture(get_tree(), world, region_id, &"wood", inv)
	var snap_stone_0 := Audit.capture(get_tree(), world, region_id, &"stone", inv)

	# Keep leader_b busy personally so leader_a is the sole candidate for recovery tests.
	assert_true(leader_b.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0))))

	var res := cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(res.get("ok", false)))
	var site: ConstructionSite = res["site"] as ConstructionSite
	assert_true(cmd.command_units_to_site(site, [leader_a]))
	Engine.time_scale = 3.0
	assert_true(await _until(func() -> bool: return site.get_delivered_buffer_amount(&"wood") > 0 or site._work_progress_usec > 0, 2400), "Site received materials")
	Engine.time_scale = 1.0

	# Put leader_a into PERSONAL_POST_MOVE_WAIT BEFORE cancelling site!
	leader_a.personal_post_move_wait_sec = 2.0
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	var wait_token_0: int = leader_a.get_personal_wait_token_id()
	var wait_rev_0: int = leader_a.get_order_revision()

	# Cancel site -> automatic recovery flush MUST refuse leader_a while in PERSONAL_POST_MOVE_WAIT!
	var cancelled := ReservedWithdrawalCoordinator.execute_site_cancellation(site, &"b3_t1c_cancel")
	assert_true(cancelled.ok)
	var cancel_id: StringName = cancelled.receipt.cancel_id
	var rec_disp: CancellationRecoveryDispatcher = cm._recovery_dispatcher
	assert_not_null(rec_disp)
	rec_disp._flush()
	await wait_process_frames(2)

	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "E01-B3 #1: auto recovery MUST NOT interrupt PERSONAL_POST_MOVE_WAIT")
	assert_null(leader_a.get_current_order())
	assert_true(leader_a.is_personal_wait_timer_active(), "E01-B3 #1: wait timer preserved intact")
	assert_eq(leader_a.get_personal_wait_token_id(), wait_token_0)
	assert_eq(leader_a.get_order_revision(), wait_rev_0)

	# Forged direct call issue_recovery_order(..., explicit=true) outside dispatcher.assign() MUST be rejected!
	var forged_order := RecoveryOrder.new(cancel_id, region_id, camp, inv, rec_disp)
	assert_false(leader_a.issue_recovery_order(forged_order, leader_a.get_order_revision(), true), "E01-B3 #2: forged explicit=true outside assign() MUST be rejected")
	assert_eq(leader_a.get_last_order_rejection_reason(), "unadmitted_recovery_order")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "Forged recovery preserves PERSONAL_POST_MOVE_WAIT")
	assert_true(leader_a.is_personal_wait_timer_active())
	assert_eq(leader_a.get_personal_wait_token_id(), wait_token_0)

	# Legitimate explicit CancellationRecoveryDispatcher.assign() via cm.assign_cancellation_recovery() -> ADMITTED (T1c)!
	var t1c_modes: Array[Dictionary] = []
	var on_t1c_mode := func(n: UnitControlState.ControlMode, p: UnitControlState.ControlMode) -> void:
		t1c_modes.append({"new": n, "prev": p})
	leader_a.control_mode_changed.connect(on_t1c_mode)
	var exp_res := cm.assign_cancellation_recovery(cancel_id, [leader_a])
	leader_a.control_mode_changed.disconnect(on_t1c_mode)

	assert_true(bool(exp_res.get("ok", false)), "E01-B3 #3: explicit recovery T1c admitted during PERSONAL_POST_MOVE_WAIT")
	assert_true(leader_a.get_current_order() is RecoveryOrder)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_WORKING, "T1c -> COMMUNITY_WORKING")
	assert_eq(leader_a.get_active_order_origin(), UnitOrder.OrderOrigin.SYSTEM_RECOVERY, "T1c origin == SYSTEM_RECOVERY")
	assert_false(leader_a.is_personal_wait_timer_active(), "T1c invalidates wait timer")
	assert_eq(t1c_modes.size(), 1)
	assert_eq(t1c_modes[0]["prev"], UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	assert_eq(t1c_modes[0]["new"], UnitControlState.ControlMode.COMMUNITY_WORKING)

	# E01-B3 #4: Interrupt RecoveryOrder with personal MoveOrder -> sets entry.manual = true;
	# verify entry.manual remains inviolable BEFORE, DURING, and AFTER D-05 wait expiration!
	leader_a.personal_post_move_wait_sec = 0.08
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	rec_disp._on_safe_event()
	await wait_process_frames(2)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "entry.manual blocks auto recovery during wait")
	await get_tree().create_timer(0.18).timeout
	await wait_process_frames(3)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D-05 expired -> COMMUNITY_FREE")
	rec_disp._on_safe_event()
	await wait_process_frames(3)
	assert_null(leader_a.get_current_order(), "E01-B3 #4: entry.manual remains inviolable AFTER D-05 expiration")

	# Explicitly settle custody and verify D0-A04 regional conservation!
	var settle_res := cm.assign_cancellation_recovery(cancel_id, [leader_a])
	assert_true(bool(settle_res.get("ok", false)))
	var record := CancellationRecoveryTransaction._record(world, region_id, cancel_id)
	Engine.time_scale = 3.0
	assert_true(await _until(func() -> bool: return record.state == ConstructionCancellationMath.State.SETTLED, 3600), "Custody settled cleanly")
	assert_true(await _until(func() -> bool: return leader_a.get_current_order() == null, 200))
	Engine.time_scale = 1.0
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_false(leader_a.is_personal_wait_timer_active())

	assert_true(bool(Audit.verify_conservation(snap_wood_0, Audit.capture(get_tree(), world, region_id, &"wood", inv)).get("ok", false)), "D0-A04 wood")
	assert_true(bool(Audit.verify_conservation(snap_stone_0, Audit.capture(get_tree(), world, region_id, &"stone", inv)).get("ok", false)), "D0-A04 stone")

	await _teardown_main(ctx)


# ==============================================================================
# G01: Minimal Event-Driven HUD Labels, Zero Polling, Zero Countdown, D4-A01 Banner Non-Overlap
# ==============================================================================
func test_g01_event_driven_hud_discrete_labels_zero_polling_and_layout_coexistence() -> void:
	var ctx := await _boot_main(0.14, Vector2i(1280, 720))
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main: MainScene = ctx["main"] as MainScene
	var sel: SelectionManager = ctx["sel"] as SelectionManager
	var hud: ResourceHud = ctx["hud"] as ResourceHud
	var panel: SelectedUnitPanel = hud.get_selected_unit_panel()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var tree: ResourceSource = _find_source(main, &"wood_tree_01")

	assert_false(main.use_d2_2_hud, "G01: use_d2_2_hud remains false")
	assert_false(panel.is_processing(), "G01: SelectedUnitPanel zero process polling")
	assert_false(panel.is_physics_processing(), "G01: SelectedUnitPanel zero physics polling")

	var digit_re := RegEx.new()
	digit_re.compile("[0-9]")

	# 1. Select LeaderA in COMMUNITY_FREE -> "Trabalho comunitário"
	sel.select_single(leader_a)
	await wait_process_frames(2)
	assert_true(panel.visible)
	assert_true(panel.is_bound_to_unit(leader_a), "Panel bound to state_changed + control_mode_changed")
	assert_eq(panel.get_inspection_meta_text(), "Trabalho comunitário")

	# 2. Issue personal MoveOrder (far) -> PERSONAL_ACTIVE -> "Ordem pessoal"
	assert_true(leader_a.issue_personal_order(MoveOrder.new(Vector3(-10.0, 0.0, -10.0))))
	await wait_process_frames(1)
	assert_eq(panel.get_inspection_meta_text(), "Ordem pessoal")
	assert_null(digit_re.search(panel.get_inspection_meta_text()))

	# 3. Complete sync MoveOrder -> PERSONAL_POST_MOVE_WAIT -> "Aguardando retorno" (ZERO countdown/digits!)
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	await wait_process_frames(1)
	assert_eq(panel.get_inspection_meta_text(), "Aguardando retorno")
	assert_null(digit_re.search(panel.get_inspection_meta_text()), "G01: zero countdown digits in HUD")
	var apply_count_during_wait: int = panel.get_apply_count()
	await wait_process_frames(4)
	assert_eq(panel.get_apply_count(), apply_count_during_wait, "G01: zero polling re-renders while waiting")

	# 4. Wait expires -> COMMUNITY_FREE -> event-driven update back to "Trabalho comunitário"!
	await get_tree().create_timer(0.22).timeout
	await wait_process_frames(2)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(panel.get_inspection_meta_text(), "Trabalho comunitário")

	# 5. Spawn read-only Worker3 via TemporaryTestWorkersController and inspect -> "Morador — somente leitura"
	var twc: TemporaryTestWorkersController = main._test_workers_controller
	assert_not_null(twc)
	var spawn_res: Dictionary = twc.spawn_temporary_workers()
	assert_true(bool(spawn_res.get("ok", false)))
	var workers: Array = spawn_res.get("workers", []) as Array
	assert_gt(workers.size(), 0)
	var worker3: Unit = workers[0] as Unit
	sel.select_single(worker3)
	await wait_process_frames(2)
	assert_true(panel.get_inspection_meta_text().contains("Morador — somente leitura"), "Read-only resident label preserved")

	# Trigger AutonomousGatherFeedback & verify D4-A01 top banner non-overlap + corner bounds at 1280x720 and 1920x1080
	var feedback: AutonomousGatherFeedback = main.get_node("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	var pto: PlacementTestOverlay = main.get_node("UiLayer/PlacementTestOverlay") as PlacementTestOverlay
	board.register_gather_task(tree)
	disp._flush_dispatch()
	feedback.show_message("Corte de madeira autorizado.")
	var status_banner: Control = pto.get_status_banner_control()
	if status_banner != null:
		status_banner.visible = true
	await wait_process_frames(3)

	for sz: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		vp.size = sz
		await wait_process_frames(3)
		var vp_rect: Rect2 = vp.get_visible_rect()
		var unit_rect: Rect2 = panel.get_global_rect()
		var stock_rect: Rect2 = hud.get_stockpile_panel().get_global_rect()
		assert_true(vp_rect.encloses(unit_rect), "Unit panel fits at %s" % str(sz))
		assert_false(unit_rect.intersects(stock_rect), "Unit panel & stockpile do not overlap at %s" % str(sz))
		if status_banner != null and status_banner.visible and feedback.visible:
			var fb_panel: Control = feedback.get_node_or_null("Panel") as Control
			if fb_panel != null and fb_panel.visible:
				assert_false(fb_panel.get_global_rect().intersects(status_banner.get_global_rect()), "D4-A01: top banners do not overlap at %s" % str(sz))

	# Deselection & teardown clean signal disconnection
	sel.clear_selection()
	await wait_process_frames(1)
	assert_false(panel.is_bound_to_unit(worker3))
	assert_false(worker3.control_mode_changed.is_connected(panel._on_unit_control_mode_changed))
	await _teardown_main(ctx)
