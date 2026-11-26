extends TestCase
## Runs the real Unit and ResourceSource physics callbacks in an isolated MainScene world.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const TICK: float = 1.0 / 60.0
const STANDING := ResourceSource.TreeHarvestStage.STANDING
const CHOPPING := ResourceSource.TreeHarvestStage.CHOPPING
const FELLING := ResourceSource.TreeHarvestStage.FELLING
const FALLEN := ResourceSource.TreeHarvestStage.FALLEN
const DEPLETED := ResourceSource.TreeHarvestStage.DEPLETED

var _scale: float
var _ticks: int


func before_each() -> void:
	_scale = Engine.time_scale
	_ticks = Engine.physics_ticks_per_second
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = _scale
	Engine.physics_ticks_per_second = _ticks


func _fixture(provenance: bool = true) -> MainScene:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)
	var main := MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = provenance
	view.add_child(main)
	var nav := main.get_test_map().get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 240), "MainScene navigation ready")
	await wait_physics_frames(2)
	return main


func _until(predicate: Callable, limit: int = 900) -> bool:
	for _frame: int in range(limit):
		if predicate.call():
			return true
		await wait_physics_frames(1)
	return predicate.call()


func _source(main: MainScene, id: StringName = &"wood_tree_01") -> ResourceSource:
	for node: Node in get_tree().get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES):
		var candidate := node as ResourceSource
		if candidate != null and candidate.get_world_3d() == main.get_world_3d() and candidate.source_id == id:
			return candidate
	fail("MainScene source missing: %s" % id)
	return null


func _place_in_range(unit: Unit, source: ResourceSource, direction: Vector3) -> void:
	var radius: float = (source.get_interaction_radius() + source.get_solid_radius() + WorldNavigation.DEFAULT_AGENT_RADIUS) / 2.0
	unit.global_position = source.global_position + direction * radius


func _gather_at(main: MainScene, source: ResourceSource, units: Array[Unit]) -> bool:
	main.get_selection_manager().set_selection(units)
	var pick := PickResult.from_resource_source(source, source.global_position, Vector3.UP)
	return main.get_command_controller().command_at(pick)


func _regional_serial(main: MainScene, region: StringName) -> int:
	var domains: Dictionary = main.get_world_3d().get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var authority := domains.get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
	return authority.construction_transfer_serial if authority != null else 0


func test_i01_main_contextual_order_cuts_then_delivers() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	tree.configure(tree.source_id, tree.get_definition(), 2, 2, 2)
	var inventory := main.get_settlement_inventory()
	var stock_before: int = inventory.get_physical_amount(&"wood")
	var stages: Array[int] = []
	var stock_during_fall: Array[int] = []
	tree.tree_harvest_stage_changed.connect(func(_src: ResourceSource, stage: int) -> void:
		stages.append(stage)
		if stage == FELLING or stage == FALLEN:
			stock_during_fall.append(tree.get_remaining_amount())
	)
	main.get_source_selection_model().select_single(tree)
	var action := main.get_community_selection_actions_hud().get_category_button(&"wood")
	assert_true(action != null and action.visible, "Contextual authorization is available")
	if action == null:
		return
	action.pressed.emit()
	var task := main.get_community_work_board().get_active_task_for_source(tree)
	if not assert_not_null(task, "Contextual authorization registered"):
		return
	var serial_before := _regional_serial(main, task.region_id)
	var economic_changes_before_collection: Array[Array] = []
	tree.tree_harvest_stage_changed.connect(func(_src: ResourceSource, stage: int) -> void:
		if stage not in [CHOPPING, FELLING, FALLEN] or task.assigned_order == null:
			return
		var order := task.assigned_order
		economic_changes_before_collection.append([
			int(order.get("_gather_cycle_serial")),
			_regional_serial(main, task.region_id) - serial_before,
			task.assigned_unit.get_carry_load().get_amount(&"wood"),
			order.last_extraction_receipt.size(),
			order.get_active_gather_session() != null,
		])
	)
	var phases: Dictionary = {}
	for _frame: int in range(1400):
		var order := task.assigned_order
		if order != null:
			phases[order.get_phase()] = true
			if order.is_preparing_work():
				phases["preparation"] = true
		if not task.is_active():
			break
		await wait_physics_frames(1)
	assert_true(phases.has(GatherResourceOrder.Phase.APPROACHING_SOURCE), "Unit approaches the tree")
	assert_true(phases.has("preparation"), "Preparation precedes cutting")
	assert_eq(stages, [CHOPPING, FELLING, FALLEN, DEPLETED], "Stage sequence precedes physical collection")
	assert_eq(economic_changes_before_collection, [[0, 0, 0, 0, false], [0, 0, 0, 0, false], [0, 0, 0, 0, false]])
	assert_eq(stock_during_fall, [2, 2], "Forest stock stays intact through fall")
	assert_true(phases.has(GatherResourceOrder.Phase.DELIVERING_TO_CAMP), "Unit physically returns to camp")
	assert_eq(task.state, WorkTask.State.COMPLETED)
	assert_eq(inventory.get_physical_amount(&"wood") - stock_before, 2)
	assert_eq(tree.get_active_worker_count(), 0)



func test_i05_range_loss_freezes_a_personal_cut_until_reapproach() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var unit := main.get_units()[0]
	_place_in_range(unit, tree, Vector3.LEFT)
	assert_true(_gather_at(main, tree, [unit]))
	if not assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() >= 0.3, 210)):
		return
	var order := unit.get_current_order() as GatherResourceOrder
	var cut := tree.get_tree_cut_progress_sec()
	unit.global_position += Vector3.LEFT * 3.0
	await wait_physics_frames(6)
	assert_eq(order.get_phase(), GatherResourceOrder.Phase.APPROACHING_SOURCE)
	assert_near(tree.get_tree_cut_progress_sec(), cut, 0.002)
	assert_eq(tree.get_active_worker_count(), 1)
	assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() > cut + 0.15, 360))
	assert_eq(unit.get_current_order(), order)
	unit.cancel_current_order()
	assert_eq(tree.get_tree_harvest_stage(), STANDING)
	assert_near(tree.get_tree_cut_progress_sec(), 0.0)
	assert_eq(tree.get_active_worker_count(), 0)


func test_i06_i11_fall_survives_cancel_pause_tween_loss_and_no_workers() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var unit := main.get_units()[0]
	_place_in_range(unit, tree, Vector3.LEFT)
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var stages: Array[int] = []
	var cancelled: Array[int] = []
	var task := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task):
		return
	tree.tree_harvest_stage_changed.connect(func(_source_node: ResourceSource, stage: int) -> void:
		stages.append(stage)
		if stage == FELLING:
			var result := dispatcher.cancel_tasks_for_sources([tree], &"wood")
			cancelled.append(int(result.get("cancelled_count", 0)))
	)
	if not assert_true(await _until(func() -> bool: return tree.get_tree_harvest_stage() == FELLING, 340)):
		return
	var amount := tree.get_remaining_amount()
	assert_eq(cancelled, [1])
	assert_eq(task.state, WorkTask.State.CANCELLED)
	assert_eq(tree.get_active_worker_count(), 0)
	assert_true(tree._felling_tween != null, "Tree scene has a running visual track")
	if tree._felling_tween != null:
		tree._felling_tween.kill()
	get_tree().paused = true
	await wait_physics_frames(40)
	assert_eq(tree.get_tree_harvest_stage(), FELLING)
	assert_eq(tree.get_remaining_amount(), amount)
	get_tree().paused = false
	await wait_physics_frames(8)
	var during_fall := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(during_fall):
		return
	assert_true(await _until(func() -> bool: return during_fall.assigned_order != null, 12))
	assert_eq(tree.get_tree_harvest_stage(), FELLING)
	assert_eq(dispatcher.cancel_tasks_for_sources([tree], &"wood").get("cancelled_count"), 1)
	assert_eq(during_fall.state, WorkTask.State.CANCELLED)
	assert_eq(tree.get_active_worker_count(), 0)
	assert_true(await _until(func() -> bool: return tree.get_tree_harvest_stage() == FALLEN, 50))
	assert_eq(stages, [CHOPPING, FELLING, FALLEN])
	assert_eq(tree.get_remaining_amount(), amount)
	var fresh_task := board.register_gather_task(tree).get("task") as WorkTask
	assert_true(fresh_task != null and fresh_task != task)
	assert_true(await _until(func() -> bool: return tree.get_active_worker_count() > 0, 90))
	var result := dispatcher.cancel_tasks_for_sources([tree], &"wood")
	assert_eq(result.get("cancelled_count"), 1)
	assert_eq(tree.get_tree_harvest_stage(), FALLEN)
	assert_eq(tree.get_remaining_amount(), amount)
	assert_eq(tree.get_active_worker_count(), 0)


func test_i07_blocked_task_reauthorizes_with_a_new_token() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var units := main.get_units()
	_place_in_range(units[0], tree, Vector3.LEFT)
	_place_in_range(units[1], tree, Vector3.RIGHT)
	var board := main.get_community_work_board()
	var task := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task):
		return
	if not assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() >= 0.25, 230)):
		return
	var previous_token := task.tree_cut_authorization
	var first := task.assigned_unit
	first.cancel_current_order()
	if not assert_true(await _until(func() -> bool: return task.assigned_unit != null and task.assigned_unit != first, 180)):
		return
	assert_eq(task.tree_cut_authorization, previous_token, "Assignment change preserves the same token")
	task.assigned_unit.cancel_current_order()
	assert_true(await _until(task.is_blocked_reauthorization, 180))
	assert_false(previous_token.is_valid_for(tree))
	assert_null(task.tree_cut_authorization)
	assert_eq(tree.get_tree_harvest_stage(), STANDING)
	assert_near(tree.get_tree_cut_progress_sec(), 0.0)
	assert_true(bool(board.reauthorize_gather_task(task).get("ok")))
	assert_true(task.tree_cut_authorization != previous_token and task.tree_cut_authorization.is_valid_for(tree))
	if not assert_true(await _until(func() -> bool: return task.assigned_order != null, 90)):
		return
	var new_unit := task.assigned_unit
	assert_false(tree.begin_tree_cut(new_unit, task.assigned_order, task.assigned_order_revision, previous_token), "Late admission with revoked token rejected")
	assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() > 0.0, 150))


func test_i08_slot_release_callback_keeps_same_tree_personal_successor() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var units := main.get_units()
	_place_in_range(units[0], tree, Vector3.LEFT)
	var board := main.get_community_work_board()
	var task := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task):
		return
	if not assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() > 0.15, 240)):
		return
	var unit := task.assigned_unit
	var previous_order := task.assigned_order
	var successors: Array[UnitOrder] = []
	tree.worker_slot_released.connect(func(_src: ResourceSource) -> void:
		if task.state == WorkTask.State.CANCELLED and _gather_at(main, tree, [unit]):
			successors.append(unit.get_current_order())
	, CONNECT_ONE_SHOT)
	var cancellation := main.get_community_task_dispatcher().cancel_tasks_for_sources([tree], &"wood")
	assert_eq(cancellation.get("cancelled_count"), 1)
	if not assert_eq(successors.size(), 1):
		return
	assert_eq(unit.get_current_order(), successors[0])
	assert_eq(tree.get_active_worker_count(), 1)
	assert_near(tree.get_tree_cut_progress_sec(), 0.0)
	assert_true(previous_order.is_finished())
	previous_order.cancel(unit.get_movement())
	assert_eq(unit.get_current_order(), successors[0])
	assert_eq(tree.get_active_worker_count(), 1)
	assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() > 0.0, 150))


func test_i09_existing_cargo_leaves_during_fall_and_cancel_stops_return() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var units := main.get_units()
	var cutter := units[0]
	var carrier := units[1]
	_place_in_range(cutter, tree, Vector3.LEFT)
	_place_in_range(carrier, tree, Vector3.RIGHT)
	var load := carrier.get_carry_load()
	var carry_fixture := preload("res://tests/framework/carry_provenance_fixture.gd")
	var cargo: int = load.get_effective_capacity()
	assert_true(bool(carry_fixture.add_lot(load, &"i09_existing_op", &"i09_existing_lot", &"food", 1, cargo, CarryProvenanceLedger.FREE_GATHERED).get("ok")))
	var inventory := main.get_settlement_inventory()
	var food_before: int = inventory.get_physical_amount(&"food")
	assert_true(_gather_at(main, tree, [cutter]))
	if not assert_true(await _until(func() -> bool: return tree.get_tree_harvest_stage() == FELLING, 300)):
		return
	var board := main.get_community_work_board()
	var task := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task):
		return
	if not assert_true(await _until(func() -> bool: return task.assigned_order != null, 24)):
		return
	var order := task.assigned_order
	assert_eq(task.assigned_unit, carrier)
	assert_eq(tree.get_tree_harvest_stage(), FELLING)
	assert_eq(order.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP)
	assert_eq(inventory.get_physical_amount(&"food"), food_before)
	assert_eq(load.get_amount(&"food"), cargo)
	var cancellation := main.get_community_task_dispatcher().cancel_tasks_for_sources([tree], &"wood")
	assert_eq(cancellation.get("delivering_count"), 1)
	assert_eq(cutter.get_current_order().status, UnitOrder.Status.RUNNING)
	cutter.cancel_current_order()
	assert_true(await _until(order.is_finished, 900))
	assert_true(order.is_succeeded())
	assert_eq(order.get_delivered_trips(), 1)
	assert_eq(inventory.get_physical_amount(&"food") - food_before, cargo)
	assert_eq(load.get_amount(&"food"), 0)
	assert_eq(load.get_amount(&"wood"), 0)
	assert_eq(order.get_total_extracted_units(), 0)
	assert_eq(tree.get_tree_harvest_stage(), FALLEN)
	assert_eq(tree.get_active_worker_count(), 0)
	assert_eq(task.state, WorkTask.State.CANCELLED)


func test_i10_i12_legacy_tree_and_mixed_resources_keep_physical_delivery() -> void:
	var main := await _fixture(false)
	var unit := main.get_units()[0]
	var inventory := main.get_settlement_inventory()
	var source_ids: Array[StringName] = [&"wood_tree_01", &"stone_rock_01", &"food_bush_01"]
	for source_id: StringName in source_ids:
		var source := _source(main, source_id)
		if source == null:
			return
		var resource_id := source.get_resource_id()
		source.configure(source_id, source.get_definition(), 2, 2, 2)
		var before := inventory.get_physical_amount(resource_id)
		_place_in_range(unit, source, Vector3.LEFT)
		assert_true(_gather_at(main, source, [unit]))
		var order := unit.get_current_order() as GatherResourceOrder
		if not assert_not_null(order):
			return
		assert_false(order.is_provenance_mode())
		if resource_id == &"wood":
			assert_true(await _until(source.is_felling, 260))
			assert_eq(source.get_remaining_amount(), 2)
			assert_eq(unit.get_carry_load().get_amount(resource_id), 0)
		assert_true(await _until(order.is_finished, 1300))
		assert_true(order.is_succeeded(), "Legacy order completes: %s" % source_id)
		assert_eq(inventory.get_physical_amount(resource_id) - before, 2)
		assert_eq(source.get_remaining_amount(), 0)
		assert_eq(unit.get_carry_load().get_amount(resource_id), 0)


func test_i02_i03_two_rts_workers_share_the_source_clock() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var units := main.get_units()
	_place_in_range(units[0], tree, Vector3.LEFT)
	_place_in_range(units[1], tree, Vector3.RIGHT)
	assert_true(_gather_at(main, tree, units), "RTS group gather accepted")
	for unit: Unit in units:
		assert_true(unit.get_current_order() is GatherResourceOrder)
	assert_eq(tree.get_active_worker_count(), 2)
	if not assert_true(await _until(func() -> bool: return tree.get_tree_harvest_stage() == CHOPPING, 180), "Group begins to cut"):
		return
	var before: float = tree.get_tree_cut_progress_sec()
	await wait_physics_frames(6)
	assert_near(tree.get_tree_cut_progress_sec() - before, 6.0 * TICK * 1.5, 0.002, "Two workers advance one shared clock at 1.5x")
	units[0].cancel_current_order()
	before = tree.get_tree_cut_progress_sec()
	await wait_physics_frames(6)
	assert_near(tree.get_tree_cut_progress_sec() - before, 6.0 * TICK, 0.002, "Independent worker keeps the cut at 1x")
	assert_eq(tree.get_active_worker_count(), 1)
	assert_eq(units[1].get_carry_load().get_amount(&"wood"), 0)


func test_i04_session_rejects_a_standing_tree_before_creating_intent() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var unit := main.get_units()[0]
	var session := GatherTransferSession.new()
	var region := main.get_test_map().get_navigation().get_region_id()
	var inventory := main.get_settlement_inventory()
	var camp := main.get_camp_storage_zone()
	var amount := tree.get_remaining_amount()
	var result := session.initialize_cycle(inventory, camp, tree, unit, region, get_instance_id(), 1, 1)
	assert_false(bool(result.get("ok", false)), "Standing wood must reject new extraction intent")
	assert_eq(result.get("reason"), "tree_not_felled")
	if bool(result.get("ok", false)):
		session.execute_or_retry(inventory, camp, tree, unit, region, get_instance_id(), true)
	assert_eq(session.get_cycle_index(), 0)
	assert_eq(session.get_operation_id(), &"")
	assert_eq(session.get_lot_id(), &"")
	assert_eq(tree.get_remaining_amount(), amount)
	assert_eq(unit.get_carry_load().get_amount(&"wood"), 0)


func test_i05_i07_community_assignment_can_change_without_losing_the_cut() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var units := main.get_units()
	_place_in_range(units[0], tree, Vector3.LEFT)
	_place_in_range(units[1], tree, Vector3.RIGHT)
	var board := main.get_community_work_board()
	var task := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task):
		return
	if not assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() >= 0.5, 240), "Community worker contributes"):
		return
	var first := task.assigned_unit
	if not assert_not_null(first):
		return
	var order := task.assigned_order
	var before: float = tree.get_tree_cut_progress_sec()
	var personal_move := MoveOrder.new(first.global_position + Vector3(0.0, 0.0, 5.0))
	first.issue_order(personal_move)
	assert_eq(first.get_current_order(), personal_move)
	assert_eq(tree.get_tree_harvest_stage(), CHOPPING)
	assert_near(tree.get_tree_cut_progress_sec(), before, 0.001)
	assert_true(await _until(func() -> bool: return task.assigned_unit != null and task.assigned_unit != first, 240))
	assert_true(task.assigned_order != order)
	assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() >= before + 0.1, 240))
	var result := main.get_community_task_dispatcher().cancel_tasks_for_sources([tree], &"wood")
	assert_eq(result.get("cancelled_count"), 1)
	assert_eq(tree.get_tree_harvest_stage(), STANDING, "Definitive cancellation resets the abandoned cut")
	assert_near(tree.get_tree_cut_progress_sec(), 0.0, 0.001)
	assert_eq(tree.get_active_worker_count(), 0)



func test_i06_i08_community_cancel_keeps_independent_personal_cutter() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var units := main.get_units()
	_place_in_range(units[0], tree, Vector3.LEFT)
	_place_in_range(units[1], tree, Vector3.RIGHT)
	var task := main.get_community_work_board().register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task):
		return
	if not assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() >= 0.3, 180)):
		return
	var personal := units[0] if task.assigned_unit != units[0] else units[1]
	assert_true(_gather_at(main, tree, [personal]))
	var personal_order := personal.get_current_order() as GatherResourceOrder
	if not assert_not_null(personal_order):
		return
	await wait_physics_frames(30)
	var before := tree.get_tree_cut_progress_sec()
	var result := main.get_community_task_dispatcher().cancel_tasks_for_sources([tree], &"wood")
	assert_eq(result.get("cancelled_count"), 1)
	assert_eq(task.state, WorkTask.State.CANCELLED)
	assert_eq(tree.get_tree_harvest_stage(), CHOPPING)
	assert_near(tree.get_tree_cut_progress_sec(), before)
	assert_eq(personal.get_current_order(), personal_order)
	assert_eq(tree.get_active_worker_count(), 1)
	await wait_physics_frames(6)
	assert_near(tree.get_tree_cut_progress_sec() - before, 6.0 * TICK, 0.002)


func test_i11_source_teardown_removes_participation_and_preserves_economy() -> void:
	var main := await _fixture()
	var tree := _source(main)
	if tree == null:
		return
	var unit := main.get_units()[0]
	_place_in_range(unit, tree, Vector3.LEFT)
	var task := main.get_community_work_board().register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task):
		return
	if not assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() > 0.15, 240)):
		return
	var order := task.assigned_order
	var token := task.tree_cut_authorization
	var inventory := main.get_settlement_inventory()
	var stock_before := inventory.get_physical_amount(&"wood")
	tree.free()
	assert_true(await _until(order.is_finished, 90))
	assert_true(await _until(func() -> bool: return not task.is_active(), 90))
	assert_eq(task.state, WorkTask.State.FAILED)
	assert_null(task.tree_cut_authorization)
	assert_true(token.is_revoked())
	assert_eq(inventory.get_physical_amount(&"wood"), stock_before)
	assert_eq(unit.get_carry_load().get_amount(&"wood"), 0)
