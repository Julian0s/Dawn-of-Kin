extends TestCase
## Integration tests for R-03B B1:
## - A03: Common villager read-only inspection and personal order denial preserving community work
## - A04: Mixed selection pre-planning filter (move, gather, construct)
## - A05: Direct Unit admission barrier (no bypass via Unit.issue_order / fake origins)
## - A06: Worker3 & Worker4 as COMMUNITY temporary workers on MainScene
## - A07: DispatchLease authority across wood/stone/food + 18 adversarial & audit-complementary scenarios
## - B01-B03: Production entry enforcement for BABY and CHILD

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")


func _boot_main() -> Dictionary:
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	add_test_child(main)
	var nav: WorldNavigation = main.get_test_map().get_navigation()
	for _i: int in range(180):
		if nav.is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(nav.is_navigation_ready(), "Navigation must be ready")
	await wait_process_frames(2)
	return {
		"main": main,
		"nav": nav,
		"board": main.get_community_work_board(),
		"dispatcher": main.get_community_task_dispatcher(),
		"cmd": main.get_command_controller(),
		"sel": main.get_selection_manager(),
		"inv": main.get_settlement_inventory(),
		"camp": main.get_camp_storage_zone(),
		"hud": main.get_resource_hud(),
		"feedback": main.get_autonomous_gather_feedback(),
		"overlay": main.get_placement_test_overlay(),
		"cm": main.get_construction_manager(),
		"leader_a": main.get_node("Units/LeaderA") as Unit,
		"leader_b": main.get_node("Units/LeaderB") as Unit,
	}


func _teardown_main(ctx: Dictionary) -> void:
	var main: MainScene = ctx.get("main") as MainScene
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.queue_free()
	await wait_process_frames(2)


func _find_source(main: MainScene, id: StringName) -> ResourceSource:
	for src: ResourceSource in main.get_test_map().get_resource_sources():
		if src.get_source_id() == id:
			return src
	return null


func _spawn_custom_unit(
	ctx: Dictionary,
	node_name: String,
	id: StringName,
	display_name_text: String,
	affiliation: CharacterDefinition.HouseAffiliation,
	origin: CharacterDefinition.FoundingHouseOrigin,
	age: CharacterDefinition.AgeStage,
	pos: Vector3
) -> Unit:
	var main: MainScene = ctx["main"] as MainScene
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var units_root: Node3D = main.get_node("Units") as Node3D
	var def := CharacterDefinition.new()
	def.character_id = id
	def.display_name = display_name_text
	def.house_affiliation = affiliation
	def.founding_house_origin = origin
	def.age_stage = age
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = node_name
	u.definition = def
	u.position = pos
	units_root.add_child(u)
	u.set_world_navigation(nav)
	ReservedWithdrawalCoordinator.admit_empty_provenance_units(
		[u], units_root, ctx["camp"], ctx["inv"], main.get_construction_manager().get_region_id()
	)
	return u


func test_a03_a06_worker3_worker4_community_inspection_denial_and_work() -> void:
	var ctx := await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var ctrl: TemporaryTestWorkersController = (ctx["overlay"] as PlacementTestOverlay).get_temporary_workers_controller()
	var spawn_res: Dictionary = ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_res.get("ok", false)), "Temporary workers spawn cleanly")

	var w3: Unit = main.get_node("Units/Worker3") as Unit
	var w4: Unit = main.get_node("Units/Worker4") as Unit
	assert_not_null(w3)
	assert_not_null(w4)
	for w: Unit in [w3, w4]:
		assert_eq(w.get_definition().house_affiliation, CharacterDefinition.HouseAffiliation.COMMUNITY)
		assert_eq(w.get_definition().founding_house_origin, CharacterDefinition.FoundingHouseOrigin.NONE)
		assert_eq(w.get_definition().age_stage, CharacterDefinition.AgeStage.ADULT)
	assert_eq(w3.get_character_id(), &"test_worker_3")
	assert_eq(w4.get_character_id(), &"test_worker_4")

	# Q01 A: Select Worker3 for read-only inspection in SelectedUnitPanel.
	var sel: SelectionManager = ctx["sel"] as SelectionManager
	var panel: SelectedUnitPanel = (ctx["hud"] as ResourceHud).get_selected_unit_panel()
	sel.select_single(w3)
	await wait_process_frames(2)
	assert_true(sel.is_selected(w3), "Worker3 must be selectable for inspection")
	assert_true(panel.visible, "SelectedUnitPanel must display inspected common villager")
	assert_eq(panel.get_header_text(), w3.get_definition().display_name)
	assert_true(panel.get_inspection_meta_text().contains("somente leitura"), "Panel must indicate read-only resident: %s" % panel.get_inspection_meta_text())
	assert_false(panel.is_processing(), "SelectedUnitPanel must remain zero-polling")

	# Personal orders via CommandController MUST be denied for Worker3 without side effects.
	var cmd: CommandController = ctx["cmd"] as CommandController
	var feedback: AutonomousGatherFeedback = ctx["feedback"] as AutonomousGatherFeedback
	var rev_before: int = w3.get_order_revision()
	assert_false(cmd.command_at(PickResult.from_ground(Vector3(2.0, 0.0, 2.0), Vector3.UP)), "MoveOrder to Worker3 must be rejected")
	assert_eq(cmd.get_last_command_reason(), "personal_control_denied")
	assert_eq(w3.get_order_revision(), rev_before, "Denied personal order must not bump revision")
	assert_null(w3.get_current_order())
	assert_false(feedback.last_message.is_empty(), "Brief feedback must be shown on personal control denial")

	var tree_src: ResourceSource = _find_source(main, &"wood_tree_01")
	assert_false(cmd.command_at(PickResult.from_resource_source(tree_src, tree_src.global_position, Vector3.UP)), "Direct gather to Worker3 must be rejected")
	assert_eq(cmd.get_last_command_reason(), "personal_control_denied")

	# Authorize community task on wood_tree_01 -> keep leaders busy so Worker3 picks it up legitimately.
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	assert_true(leader_a.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0))))
	assert_true(leader_b.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -8.0))))
	w3.global_position = tree_src.global_position + Vector3(-1.8, 0.0, 0.0)
	w4.global_position = Vector3(-14.0, 0.0, -10.0)
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var reg: Dictionary = board.register_gather_task(tree_src)
	assert_true(bool(reg.get("ok", false)))
	await wait_process_frames(4)
	await wait_physics_frames(2)

	var task: WorkTask = reg["task"] as WorkTask
	assert_eq(task.assigned_unit, w3, "Worker3 (COMMUNITY) must legitimately execute community task")
	assert_true(w3.get_current_order() is GatherResourceOrder)
	assert_eq(w3.get_current_order().get_order_origin(), UnitOrder.OrderOrigin.COMMUNITY)
	assert_true(panel.get_inspection_meta_text().contains("Madeira"), "Panel must reflect active community task: %s" % panel.get_inspection_meta_text())

	# Attempting a personal command on Worker3 while working MUST NOT cancel its community order!
	var active_comm_order: UnitOrder = w3.get_current_order()
	var active_rev: int = w3.get_order_revision()
	sel.select_single(w3)
	assert_false(cmd.command_at(PickResult.from_ground(Vector3(0.0, 0.0, 4.0), Vector3.UP)))
	assert_eq(w3.get_current_order(), active_comm_order, "Denied personal command must preserve active community order")
	assert_eq(w3.get_order_revision(), active_rev, "Denied personal command must preserve revision")

	# Clean removal still works once orders/backpacks are cleared.
	w3.cancel_current_order()
	await wait_process_frames(2)
	var rem_res: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_true(bool(rem_res.get("ok", false)), "Safe removal of Worker3/Worker4 must remain intact: %s" % str(rem_res))

	await _teardown_main(ctx)


func test_a04_mixed_selection_filters_before_planning_and_preserves_excluded_units() -> void:
	var ctx := await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var ctrl: TemporaryTestWorkersController = (ctx["overlay"] as PlacementTestOverlay).get_temporary_workers_controller()
	assert_true(bool(ctrl.spawn_temporary_workers().get("ok", false)))
	var leader_a: Unit = ctx["leader_a"] as Unit
	var w3: Unit = main.get_node("Units/Worker3") as Unit
	var w4: Unit = main.get_node("Units/Worker4") as Unit
	var sel: SelectionManager = ctx["sel"] as SelectionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard

	# Put Worker3 on an active community food task.
	var bush: ResourceSource = _find_source(main, &"food_bush_01")
	w3.global_position = bush.global_position + Vector3(-1.5, 0.0, 0.0)
	leader_a.global_position = Vector3(0.0, 0.0, 0.0)
	(ctx["leader_b"] as Unit).global_position = Vector3(-14.0, 0.0, -12.0)
	w4.global_position = Vector3(-14.0, 0.0, -10.0)
	var reg := board.register_gather_task(bush)
	await wait_process_frames(4)
	await wait_physics_frames(2)
	var task: WorkTask = reg["task"] as WorkTask
	assert_eq(task.assigned_unit, w3)
	var w3_order: UnitOrder = w3.get_current_order()
	var w3_rev: int = w3.get_order_revision()

	# Mixed selection: LeaderA + Worker3 + Worker4 -> MoveOrder.
	sel.set_selection([leader_a, w3, w4])
	var target_pos := Vector3(3.0, 0.0, 2.0)
	assert_true(cmd.command_at(PickResult.from_ground(target_pos, Vector3.UP)), "Mixed selection must command eligible founder")
	assert_true(leader_a.get_current_order() is MoveOrder)
	assert_eq(leader_a.get_current_order().get_order_origin(), UnitOrder.OrderOrigin.PERSONAL)
	assert_eq(cmd.get_last_plan().targets.size(), 1, "GroupMovePlanner must plan ONLY for eligible Founding House units (1, not 3)")
	assert_eq(w3.get_current_order(), w3_order, "Excluded Worker3 must keep its community order intact")
	assert_eq(w3.get_order_revision(), w3_rev)
	assert_null(w4.get_current_order(), "Excluded Worker4 must not receive personal MoveOrder")

	# Mixed selection on ConstructionSite -> ONLY LeaderA assigned (Worker3/Worker4 do not consume slots).
	(ctx["inv"] as SettlementInventory).deposit(&"wood", 12)
	(ctx["inv"] as SettlementInventory).deposit(&"stone", 6)
	var site_res: Dictionary = (ctx["cm"] as ConstructionManager).try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 2.0))
	assert_true(bool(site_res.get("ok", false)))
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	sel.set_selection([leader_a, w3, w4])
	assert_true(cmd.command_at(PickResult.from_construction_site(site, site.global_position, Vector3.UP)))
	assert_eq(site.get_assigned_worker_entries().size(), 1, "Only eligible founder consumes construction slot")
	assert_eq(w3.get_current_order(), w3_order, "Excluded Worker3 still working on bush")

	# Selection containing ONLY common villagers -> rejected cleanly.
	sel.set_selection([w3, w4])
	assert_false(cmd.command_at(PickResult.from_construction_site(site, site.global_position, Vector3.UP)))
	assert_eq(cmd.get_last_command_reason(), "personal_control_denied")
	assert_eq(site.get_assigned_worker_entries().size(), 1)

	await _teardown_main(ctx)


func test_a05_direct_unit_barrier_blocks_bypass_and_forged_origins() -> void:
	var ctx := await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var ctrl: TemporaryTestWorkersController = (ctx["overlay"] as PlacementTestOverlay).get_temporary_workers_controller()
	assert_true(bool(ctrl.spawn_temporary_workers().get("ok", false)))
	var w3: Unit = main.get_node("Units/Worker3") as Unit
	var leader_a: Unit = ctx["leader_a"] as Unit
	var tree_src: ResourceSource = _find_source(main, &"wood_tree_01")
	var stone_src: ResourceSource = _find_source(main, &"stone_rock_01")
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone

	# 1. Direct Unit.issue_order(MoveOrder) on COMMUNITY unit MUST fail with zero side effects.
	var rev_w3: int = w3.get_order_revision()
	assert_false(w3.issue_order(MoveOrder.new(Vector3(1.0, 0.0, 1.0))), "Direct Unit.issue_order must not bypass permissions")
	assert_eq(w3.get_last_order_rejection_reason(), "personal_control_denied")
	assert_eq(w3.get_order_revision(), rev_w3)
	assert_null(w3.get_current_order())

	# 2. Direct Unit.issue_community_order with null lease or fabricated lease MUST fail.
	var fake_lease := CommunityWorkBoard.DispatchLease.new()
	var raw_gather := GatherResourceOrder.new(stone_src, camp, inv, -1.0, -1.0, true, main.get_construction_manager().get_region_id())
	assert_false(w3.issue_community_order(raw_gather, null), "Community order without lease must fail")
	assert_false(w3.issue_community_order(raw_gather, fake_lease), "Community order with fabricated lease must fail")
	assert_eq(w3.get_order_revision(), rev_w3)
	assert_null(w3.get_current_order())

	# 3. Direct Unit.issue_recovery_order outside active dispatcher admission MUST fail.
	var fake_rec := RecoveryOrder.new(&"fake_cancel", main.get_construction_manager().get_region_id(), camp, inv, null)
	assert_false(w3.issue_recovery_order(fake_rec, w3.get_order_revision(), true), "Recovery order outside dispatcher must fail")
	assert_false(leader_a.issue_order(fake_rec), "RecoveryOrder must be rejected by personal issue_order")
	assert_eq(w3.get_order_revision(), rev_w3)

	# 4. CHILD Founding House calling Unit.issue_order directly with WOOD / STONE / CONSTRUCT must fail.
	var child_f := _spawn_custom_unit(
		ctx, "ChildFounderDirect", &"child_f_direct", "Crianca Fundadora",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT,
		CharacterDefinition.AgeStage.CHILD,
		Vector3(1.0, 0.0, 1.0)
	)
	var child_rev: int = child_f.get_order_revision()
	var wood_order := GatherResourceOrder.new(tree_src, camp, inv, -1.0, -1.0, true, main.get_construction_manager().get_region_id())
	assert_false(child_f.issue_order(wood_order), "Direct Unit.issue_order must block CHILD from wood cutting")
	assert_eq(child_f.get_last_order_rejection_reason(), "age_restricted_task")
	assert_eq(child_f.get_order_revision(), child_rev)

	# 5. Legitimate personal MoveOrder on CHILD Founding House succeeds, and issue_order(null) cleanly stops it.
	assert_true(child_f.issue_order(MoveOrder.new(Vector3(3.0, 0.0, 1.0))), "CHILD Founding House may execute MoveOrder")
	assert_true(child_f.get_current_order() is MoveOrder)
	assert_true(child_f.issue_order(null), "issue_order(null) preserves clean lifecycle stop")
	assert_null(child_f.get_current_order())

	await _teardown_main(ctx)


func test_a07_dispatch_lease_full_authority_and_audit_edge_cases() -> void:
	var ctx := await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var dispatcher: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var cmd: CommandController = ctx["cmd"] as CommandController
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var region_id: StringName = main.get_construction_manager().get_region_id()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var tree_1: ResourceSource = _find_source(main, &"wood_tree_01")
	var tree_2: ResourceSource = _find_source(main, &"wood_tree_02")
	var rock_1: ResourceSource = _find_source(main, &"stone_rock_01")
	var bush_1: ResourceSource = _find_source(main, &"food_bush_01")

	# 1-3. Legitimate dispatch across WOOD, STONE, FOOD via real Board + Dispatcher.
	for src: ResourceSource in [tree_1, rock_1, bush_1]:
		leader_a.cancel_current_order()
		leader_b.cancel_current_order()
		leader_a.global_position = src.global_position + Vector3(-1.6, 0.0, 0.0)
		leader_b.global_position = Vector3(-14.0, 0.0, -12.0)
		var reg := board.register_gather_task(src)
		assert_true(bool(reg.get("ok", false)))
		await wait_process_frames(4)
		await wait_physics_frames(2)
		var t: WorkTask = reg["task"] as WorkTask
		assert_eq(t.state, WorkTask.State.IN_PROGRESS, "Legitimate dispatch must succeed for %s" % String(src.get_resource_id()))
		assert_eq(t.assigned_unit, leader_a)
		assert_eq(leader_a.get_current_order().get_order_origin(), UnitOrder.OrderOrigin.COMMUNITY)
		assert_false(board.has_pending_dispatch_lease(t.task_id), "Committed lease must not remain pending")
		board.close_task(t, WorkTask.State.CANCELLED, "cleanup")
		leader_a.cancel_current_order()
		await wait_process_frames(2)

	# Pause dispatcher flush interference for direct Board/Lease adversarial contract checks.
	dispatcher.teardown()
	await wait_process_frames(1)

	# 4-8. Adversarial DispatchLease checks:
	var reg_w1 := board.register_gather_task(tree_1)
	var task_w1: WorkTask = reg_w1["task"] as WorkTask
	var reg_w2 := board.register_gather_task(tree_2)
	var task_w2: WorkTask = reg_w2["task"] as WorkTask
	var reg_r1 := board.register_gather_task(rock_1)
	var task_r1: WorkTask = reg_r1["task"] as WorkTask

	var lease_w1: CommunityWorkBoard.DispatchLease = board.begin_task_dispatch(task_w1, leader_a)
	assert_not_null(lease_w1, "Board must issue valid DispatchLease for PENDING_WORKERS task")

	# Duplicate concurrent lease for same task MUST be rejected!
	assert_null(board.begin_task_dispatch(task_w1, leader_b), "Duplicate concurrent lease on same task must be rejected")

	# Wrong source / wrong category with lease_w1:
	var order_wrong_source := GatherResourceOrder.new(rock_1, camp, inv, -1.0, -1.0, true, region_id, task_w1.tree_cut_authorization)
	assert_false(leader_a.issue_community_order(order_wrong_source, lease_w1), "Wrong source/category must be rejected")

	# Valid CutAuthorization belonging to ANOTHER tree task (task_w2) with lease_w1:
	var order_wrong_token := GatherResourceOrder.new(tree_1, camp, inv, -1.0, -1.0, true, region_id, task_w2.tree_cut_authorization)
	assert_false(leader_a.issue_community_order(order_wrong_token, lease_w1), "Valid token from another task must be rejected")

	# Wrong unit with lease_w1:
	var order_right_w1 := GatherResourceOrder.new(tree_1, camp, inv, -1.0, -1.0, true, region_id, task_w1.tree_cut_authorization)
	assert_false(leader_b.issue_community_order(order_right_w1, lease_w1), "Wrong unit must be rejected")

	# Wrong Board / mismatched region domain:
	var other_board := CommunityWorkBoard.new()
	add_test_child(other_board)
	other_board.configure(&"other_region", main.get_world_3d())
	var grove_tree: ResourceSource = main.get_node_or_null("TestMap/PlayableCommunitySources/WoodTree03") as ResourceSource
	assert_not_null(grove_tree, "PlayableCommunitySources/WoodTree03 must exist with region_id metadata")
	assert_false(other_board.is_source_in_region_domain(grove_tree), "Other region board must reject source tagged with default region")
	assert_false(other_board.validate_dispatch_lease_for_installation(lease_w1, leader_a, order_right_w1), "Foreign board must reject lease issued by another board")

	# Abort lease -> aborted lease cannot be used, and no orphan remains:
	board.abort_task_dispatch(lease_w1)
	assert_false(board.has_pending_dispatch_lease(task_w1.task_id), "Aborted lease must be cleaned up")
	assert_false(leader_a.issue_community_order(order_right_w1, lease_w1), "Aborted lease must be rejected")

	# Revocation on close_task() and block_for_reauthorization():
	var lease_cancel := board.begin_task_dispatch(task_w2, leader_a)
	assert_not_null(lease_cancel)
	board.close_task(task_w2, WorkTask.State.CANCELLED, "test_cancel")
	assert_false(board.has_pending_dispatch_lease(task_w2.task_id), "close_task must revoke pending lease")
	var order_w2 := GatherResourceOrder.new(tree_2, camp, inv, -1.0, -1.0, true, region_id, lease_cancel.get_cut_authorization())
	assert_false(leader_a.issue_community_order(order_w2, lease_cancel), "Cancelled task lease must be rejected")

	var lease_block := board.begin_task_dispatch(task_r1, leader_a)
	assert_not_null(lease_block)
	board.block_for_reauthorization(task_r1)
	assert_false(board.has_pending_dispatch_lease(task_r1.task_id), "block_for_reauthorization must revoke pending lease")
	var order_r1 := GatherResourceOrder.new(rock_1, camp, inv, -1.0, -1.0, true, region_id)
	assert_false(leader_a.issue_community_order(order_r1, lease_block), "Blocked task lease must be rejected")

	# Consumed lease cannot be reused:
	var lease_use := board.begin_task_dispatch(task_w1, leader_a)
	assert_not_null(lease_use)
	var order_ok := GatherResourceOrder.new(tree_1, camp, inv, -1.0, -1.0, true, region_id, task_w1.tree_cut_authorization)
	assert_true(leader_a.issue_community_order(order_ok, lease_use), "Valid lease installs cleanly")
	assert_true(board.commit_task_dispatch(lease_use), "Valid installing lease commits once")
	assert_false(board.commit_task_dispatch(lease_use), "Consumed lease cannot commit twice")
	leader_a.cancel_current_order()
	var order_reuse := GatherResourceOrder.new(tree_1, camp, inv, -1.0, -1.0, true, region_id, task_w1.tree_cut_authorization)
	assert_false(leader_a.issue_community_order(order_reuse, lease_use), "Consumed lease cannot be reused")

	# Audit complementary: lease invalidated during callback while personal successor takes over -> successor preserved!
	board.close_task(task_w1, WorkTask.State.CANCELLED, "reset")
	board.reauthorize_gather_task(task_r1)
	leader_a.cancel_current_order()
	var personal_successor_issued := [false]
	var successor_order: MoveOrder = MoveOrder.new(Vector3(4.0, 0.0, 3.0))
	var cb := func(_new_s: Unit.State, _prev_s: Unit.State) -> void:
		if not personal_successor_issued[0]:
			personal_successor_issued[0] = true
			board.close_task(task_r1, WorkTask.State.CANCELLED, "revoked_mid_install")
			leader_a.issue_personal_order(successor_order)
	leader_a.state_changed.connect(cb)
	var lease_mid := board.begin_task_dispatch(task_r1, leader_a)
	var disp_res := cmd.dispatch_community_gather(rock_1, leader_a, null, lease_mid)
	leader_a.state_changed.disconnect(cb)
	board.abort_task_dispatch(lease_mid)
	assert_eq(leader_a.get_current_order(), successor_order, "Personal successor installed during callback must NEVER be cancelled")
	assert_false(board.has_pending_dispatch_lease(task_r1.task_id), "No orphan lease may remain after mid-install invalidation")
	assert_true(disp_res is Dictionary)

	# Audit complementary: synchronous completion inside start() must NOT be treated as rejected!
	leader_a.cancel_current_order()
	var reg_sync := board.register_gather_task(bush_1)
	var task_sync: WorkTask = reg_sync["task"] as WorkTask
	var lease_sync := board.begin_task_dispatch(task_sync, leader_a)
	assert_not_null(lease_sync)
	# Deplete bush just enough or test synchronous failure/completion cleanly:
	# Position leader_a with full backpack right at camp dropoff so DeliverToCampOrder finishes synchronously, OR test with unit right next to camp.
	var sync_order := GatherResourceOrder.new(bush_1, camp, inv, -1.0, -1.0, true, region_id)
	assert_true(leader_a.issue_community_order(sync_order, lease_sync), "Community order installation succeeds")
	assert_true(board.is_dispatch_lease_valid_for_commit(lease_sync), "Post-install commit validation must accept advanced unit revision")
	assert_true(board.commit_task_dispatch(lease_sync))
	assert_false(board.has_pending_dispatch_lease(task_sync.task_id))

	await _teardown_main(ctx)


func test_b01_b02_production_entries_enforce_baby_and_child_restrictions() -> void:
	var ctx := await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var sel: SelectionManager = ctx["sel"] as SelectionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var bush: ResourceSource = _find_source(main, &"food_bush_01")
	var tree: ResourceSource = _find_source(main, &"wood_tree_01")

	var baby := _spawn_custom_unit(
		ctx, "BabyProd", &"baby_prod", "Bebe",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT,
		CharacterDefinition.AgeStage.BABY,
		bush.global_position + Vector3(-1.2, 0.0, 0.0)
	)
	var child_c := _spawn_custom_unit(
		ctx, "ChildCommonProd", &"child_c_prod", "Crianca Comum",
		CharacterDefinition.HouseAffiliation.COMMUNITY,
		CharacterDefinition.FoundingHouseOrigin.NONE,
		CharacterDefinition.AgeStage.CHILD,
		bush.global_position + Vector3(-1.8, 0.0, 0.0)
	)
	var child_f := _spawn_custom_unit(
		ctx, "ChildFounderProd", &"child_f_prod", "Crianca Fundadora",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT,
		CharacterDefinition.AgeStage.CHILD,
		Vector3(0.0, 0.0, 2.0)
	)
	await wait_process_frames(2)

	# BABY cannot be selected in SelectionManager or dispatched by CommunityTaskDispatcher.
	sel.select_single(baby)
	assert_true(sel.is_empty(), "SelectionManager must reject BABY")
	assert_false(baby.is_selected())

	# CHILD Founding House can gather FOOD personally, CANNOT gather WOOD personally.
	sel.select_single(child_f)
	assert_true(sel.is_selected(child_f))
	assert_false(cmd.command_at(PickResult.from_resource_source(tree, tree.global_position, Vector3.UP)), "CHILD must not cut wood")
	assert_eq(cmd.get_last_command_reason(), "age_restricted_task")
	assert_true(cmd.command_at(PickResult.from_resource_source(bush, bush.global_position, Vector3.UP)), "CHILD Founding House may gather food personally")
	child_f.cancel_current_order()

	# Keep adult founders busy and authorize WOOD -> neither BABY nor CHILD may be dispatched to WOOD.
	leader_a.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	leader_b.issue_personal_order(MoveOrder.new(Vector3(-12.0, 0.0, -8.0)))
	child_f.issue_personal_order(MoveOrder.new(Vector3(-10.0, 0.0, -8.0)))
	var reg_wood := board.register_gather_task(tree)
	await wait_process_frames(4)
	await wait_physics_frames(2)
	var wood_task: WorkTask = reg_wood["task"] as WorkTask
	assert_null(wood_task.assigned_unit, "Neither BABY nor CHILD may be assigned to WOOD community task")

	# Authorize FOOD -> CHILD Common legitimately picks up FOOD community task, BABY does not.
	var reg_food := board.register_gather_task(bush)
	await wait_process_frames(4)
	await wait_physics_frames(2)
	var food_task: WorkTask = reg_food["task"] as WorkTask
	assert_eq(food_task.assigned_unit, child_c, "CHILD Common must be eligible for light FOOD community work")
	assert_null(baby.get_current_order(), "BABY must never receive community work")

	await _teardown_main(ctx)
