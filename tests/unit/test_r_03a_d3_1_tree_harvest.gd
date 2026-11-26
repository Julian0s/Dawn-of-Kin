extends TestCase

const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")
const TREE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
enum Stage { STANDING, CHOPPING, FELLING, FALLEN, DEPLETED }


const UNIT: PackedScene = preload("res://src/units/unit.tscn")


class FaultSource extends ResourceSource:
	var reject_commit: bool = false
	var close_barrier_at_commit: bool = false

	func _before_provenance_transfer_commit() -> bool:
		if close_barrier_at_commit:
			# Inject a changed stage without changing the economic revision.
			set(&"_tree_harvest_stage", Stage.FELLING)
		return not reject_commit


func _tree(amount: int = 8, limit: int = 3, visual: bool = false) -> ResourceSource:
	var source := (TREE.instantiate() as ResourceSource) if visual else FaultSource.new()
	source.configure(&"tree", WOOD, amount, limit, 2)
	add_test_child(source)
	return source


func _worker(source: ResourceSource, x: float = 1.1, reserve: bool = true) -> Unit:
	var worker := UNIT.instantiate() as Unit
	add_test_child(worker)
	worker.set_physics_process(false)
	worker.global_position = source.global_position + Vector3(x, 0, 0)
	_start_test_order(worker)
	if reserve:
		assert_true(source.reserve_worker(worker))
	return worker


func _start_test_order(worker: Unit) -> void:
	worker._order_revision += 1
	worker._current_order = UnitOrder.new()
	worker._current_order.mark_running()


# Dynamic calls let the same suite run against the unchanged baseline.
func _has_stage_api(source: ResourceSource) -> bool:
	return assert_true(source.has_method(&"get_tree_harvest_stage"), "D3.1 harvest state API is required")


func _stage(source: ResourceSource) -> int:
	return int(source.call(&"get_tree_harvest_stage"))


func _progress(source: ResourceSource) -> float:
	return float(source.call(&"get_tree_cut_progress_sec"))


func _begin(source: ResourceSource, worker: Unit, authorization: RefCounted) -> bool:
	return bool(source.call(&"begin_tree_cut", worker, worker.get_current_order(), worker.get_order_revision(), authorization))


func _end(source: ResourceSource, worker: Unit, authorization: RefCounted) -> bool:
	return bool(source.call(&"end_tree_cut", worker, worker.get_current_order(), worker.get_order_revision(), authorization))


func _cancel(source: ResourceSource, authorization: RefCounted) -> bool:
	return bool(source.call(&"cancel_tree_cut_authorization", authorization))


func _reach_fallen(source: ResourceSource) -> void:
	var worker := _worker(source)
	assert_true(_begin(source, worker, RefCounted.new()))
	source.call(&"_physics_process", 2.5)
	source.call(&"_physics_process", 0.5)
	assert_eq(_stage(source), Stage.FALLEN)


func _assert_closed_economy(source: ResourceSource) -> void:
	var legacy := UnitCarryLoad.new(20)
	assert_true(legacy.add_units(STONE, 1))
	var tracked := UnitCarryLoad.new(20)
	assert_true(tracked.enable_provenance(&"worker"))
	var bush := ResourceSource.new()
	bush.configure(&"bush", FOOD, 4, 2)
	assert_eq(bush.transfer_to_carry_load_with_provenance(tracked, &"fruit", &"fruit_lot", 2).extracted, 2)
	bush.free()
	var inventory := SettlementInventory.new(InMemoryStorageSource.new())
	assert_true(inventory.deposit(&"wood", 7))

	var source_before: Array = [source.get_remaining_amount(), source.get(&"_transaction_revision")]
	var legacy_before: Array = [legacy.get_all_amounts(), legacy.get_current_weight(), legacy.get_transaction_revision()]
	var tracked_before: Array = [tracked.provenance_snapshot(), tracked.get_current_weight(), tracked.get_transaction_revision()]
	var inventory_before: Array = [inventory.get_all_physical_amounts(), inventory.get_transaction_revision()]

	assert_true(source.is_available())
	assert_false(source.can_extract())
	assert_eq(source.extract(1), 0)
	assert_eq(source.transfer_to_carry_load(legacy), 0)
	var result := source.transfer_to_carry_load_with_provenance(tracked, &"wood", &"wood_lot", 2)
	assert_false(bool(result.ok))
	assert_eq(result.reason, "tree_not_felled")
	assert_eq(result.extracted, 0)

	assert_eq(source.get_provenance_receipt(&"wood"), {})
	assert_eq([source.get_remaining_amount(), source.get(&"_transaction_revision")], source_before)
	assert_eq([legacy.get_all_amounts(), legacy.get_current_weight(), legacy.get_transaction_revision()], legacy_before)
	assert_eq([tracked.provenance_snapshot(), tracked.get_current_weight(), tracked.get_transaction_revision()], tracked_before)
	assert_eq([inventory.get_all_physical_amounts(), inventory.get_transaction_revision()], inventory_before)


func test_01_all_economic_paths_closed_in_standing() -> void:
	_assert_closed_economy(_tree())


func test_02_complete_stages_and_atomic_depletion_without_visuals() -> void:
	var source := _tree(2, 2)
	if not _has_stage_api(source):
		return
	var initial_revision: Variant = source.get(&"_transaction_revision")
	var worker := _worker(source)
	assert_eq(_stage(source), Stage.STANDING)
	assert_true(_begin(source, worker, RefCounted.new()))
	source.call(&"_physics_process", 1.0)
	assert_eq(_stage(source), Stage.CHOPPING)
	_assert_closed_economy(source)
	source.call(&"_physics_process", 1.5)
	assert_eq(_stage(source), Stage.FELLING)
	_assert_closed_economy(source)
	source.call(&"_physics_process", 0.49)
	assert_eq(_stage(source), Stage.FELLING)
	source.call(&"_physics_process", 0.01)
	assert_eq(_stage(source), Stage.FALLEN)
	assert_eq(source.get_remaining_amount(), 2)
	assert_eq(source.get(&"_transaction_revision"), initial_revision)
	assert_true(source.can_extract())
	var events: Array[Array] = []
	source.amount_changed.connect(func(tree: ResourceSource, remaining: int, _delta: int) -> void:
		events.append([_stage(tree), remaining, tree.can_extract(), tree.extract(1)]))
	source.depleted.connect(func(tree: ResourceSource) -> void:
		events.append([_stage(tree), tree.get_remaining_amount()]))
	assert_eq(source.extract(2), 2)
	assert_eq(events, [[Stage.DEPLETED, 0, false, 0], [Stage.DEPLETED, 0]])
	assert_true(source.is_fallen())
	assert_false(source.is_available())
	assert_false(source.is_physics_processing())


func test_03_cancel_before_threshold_and_reenter_after_commit() -> void:
	var source := _tree()
	if not _has_stage_api(source):
		return
	var worker := _worker(source)
	var revision: Variant = source.get(&"_transaction_revision")
	var auth := RefCounted.new()
	assert_true(_begin(source, worker, auth))
	source.call(&"_physics_process", 2.49)
	assert_true(_cancel(source, auth))
	assert_false(_cancel(source, auth))
	assert_false(_begin(source, worker, auth), "Revoked authorization cannot rejoin")
	assert_eq(_stage(source), Stage.STANDING)
	assert_eq(_progress(source), 0.0)

	var next := RefCounted.new()
	assert_true(_begin(source, worker, next))
	var events: Array[Array] = []
	source.connect(&"tree_harvest_stage_changed", func(tree: ResourceSource, stage: int) -> void:
		if stage == Stage.FELLING:
			events.append([_stage(tree), tree.get_remaining_amount(), tree.extract(1)])
			_cancel(tree, next)
			tree.release_worker(worker)
			tree.call(&"_physics_process", 30.0)
			events.append([_stage(tree), tree.get_remaining_amount()]))
	source.call(&"_physics_process", 2.5)
	assert_eq(events, [[Stage.FELLING, 8, 0], [Stage.FELLING, 8]])
	assert_eq(source.get_active_worker_count(), 0)
	source.call(&"_physics_process", 0.5)
	assert_eq(_stage(source), Stage.FALLEN)
	assert_eq(source.get_remaining_amount(), 8)
	assert_eq(source.get(&"_transaction_revision"), revision)


func test_04_frozen_progress_resumes_and_definitive_cancel_resets() -> void:
	var source := _tree()
	if not _has_stage_api(source):
		return
	var worker := _worker(source)
	var auth := RefCounted.new()
	assert_true(_begin(source, worker, auth))
	source.call(&"_physics_process", 1.0)
	assert_true(_end(source, worker, auth))
	assert_false(_end(source, worker, auth))
	assert_false(source.is_physics_processing())
	assert_eq(_stage(source), Stage.CHOPPING)
	source.call(&"_physics_process", 1.0)
	assert_near(_progress(source), 1.0)
	assert_true(_begin(source, worker, auth))
	source.call(&"_physics_process", 0.25)
	assert_near(_progress(source), 1.25)
	assert_true(_end(source, worker, auth))
	assert_true(_cancel(source, auth))
	assert_eq(_stage(source), Stage.STANDING)
	assert_eq(_progress(source), 0.0)
	assert_eq(source.get_remaining_amount(), 8)


func test_05_two_cutters_one_clock_in_either_registration_order() -> void:
	for reverse_order: bool in [false, true]:
		var source := _tree()
		if not _has_stage_api(source):
			return
		var a := _worker(source, 1.0)
		var b := _worker(source, -1.0)
		var aa := RefCounted.new()
		var ab := RefCounted.new()
		source.call(&"_physics_process", 1.0)
		assert_eq(_progress(source), 0.0, "Reservations alone must not cut")
		if reverse_order:
			assert_true(_begin(source, b, ab))
			assert_true(_begin(source, a, aa))
		else:
			assert_true(_begin(source, a, aa))
			assert_true(_begin(source, b, ab))
		assert_false(_begin(source, a, aa))
		source.call(&"_physics_process", 1.0)
		assert_near(_progress(source), 1.5)
		assert_true(_cancel(source, aa))
		assert_eq(_stage(source), Stage.CHOPPING)
		source.call(&"_physics_process", 0.99)
		assert_eq(_stage(source), Stage.CHOPPING)
		source.call(&"_physics_process", 0.01)
		assert_eq(_stage(source), Stage.FELLING)


func test_06_invalid_stale_and_out_of_range_participants() -> void:
	var source := _tree()
	if not _has_stage_api(source):
		return
	var worker := _worker(source, 1.0, false)
	var auth := RefCounted.new()
	assert_false(_begin(source, worker, auth))
	assert_true(source.reserve_worker(worker))
	assert_false(_begin(source, worker, null))
	var pre_cancelled := RefCounted.new()
	assert_true(_cancel(source, pre_cancelled))
	assert_false(_begin(source, worker, pre_cancelled))
	var old_order := worker.get_current_order()
	var old_revision := worker.get_order_revision()
	assert_true(_begin(source, worker, auth))
	source.call(&"_physics_process", 0.5)
	_start_test_order(worker)
	assert_false(bool(source.call(&"begin_tree_cut", worker, old_order, old_revision, auth)))
	assert_true(_begin(source, worker, auth), "Current order may take over stale participation")
	assert_false(bool(source.call(&"end_tree_cut", worker, old_order, old_revision, auth)))
	source.call(&"_physics_process", 0.5)
	assert_near(_progress(source), 1.0)
	assert_true(_cancel(source, RefCounted.new()))
	assert_near(_progress(source), 1.0, 0.001, "Cancelling an unadmitted authorization cannot reset an independent cut")
	worker.global_position.x += 10.0
	source.call(&"_physics_process", 1.0)
	assert_near(_progress(source), 1.0)
	assert_false(_begin(source, worker, auth))
	assert_false(source.is_physics_processing())
	worker.global_position.x -= 10.0
	assert_true(_begin(source, worker, auth))
	source.release_worker(worker)
	assert_false(source.is_physics_processing())
	assert_near(_progress(source), 1.0)


func test_07_pausable_clock_and_interrupted_visual_tween() -> void:
	var source := _tree(8, 3, true)
	if not _has_stage_api(source):
		return
	var worker := _worker(source)
	assert_true(_begin(source, worker, RefCounted.new()))
	source.call(&"_physics_process", 2.5)
	source.release_worker(worker)
	source.call(&"_physics_process", 0.1)
	var pivot := source.get_node("AvailableVisual/FellingPivot") as Node3D
	var visual_tween: Tween = source.get(&"_felling_tween") as Tween
	if assert_not_null(visual_tween):
		visual_tween.kill()
	var scene := get_tree()
	scene.paused = true
	await wait_physics_frames(34)
	assert_eq(_stage(source), Stage.FELLING)
	assert_eq(source.get_remaining_amount(), 8)
	scene.paused = false
	await wait_physics_frames(34)
	assert_eq(_stage(source), Stage.FALLEN)
	assert_near(pivot.rotation.z, -1.525, 0.001)
	assert_false(source.is_physics_processing())


func test_08_teardown_rejects_late_participation() -> void:
	var source := _tree()
	if not _has_stage_api(source):
		return
	var worker := _worker(source)
	var auth := RefCounted.new()
	assert_true(_begin(source, worker, auth))
	source.call(&"_physics_process", 2.5)
	remove_child(source)
	assert_false(source.is_physics_processing())
	assert_false(_begin(source, worker, auth))
	source.call(&"_physics_process", 10.0)
	assert_eq(_stage(source), Stage.FELLING)
	assert_eq(source.get_remaining_amount(), 8)
	add_child(source)
	assert_false(_begin(source, worker, auth))
	source.call(&"_physics_process", 0.5)
	assert_eq(_stage(source), Stage.FALLEN)

	var partial := _tree()
	var partial_worker := _worker(partial)
	var partial_auth := RefCounted.new()
	assert_true(_begin(partial, partial_worker, partial_auth))
	partial.call(&"_physics_process", 1.0)
	remove_child(partial)
	assert_eq(_stage(partial), Stage.STANDING)
	assert_eq(_progress(partial), 0.0)
	add_child(partial)
	assert_false(_begin(partial, partial_worker, partial_auth))


func test_09_capacity_competition_local_balance_replay_and_rollback() -> void:
	var source := _tree(3, 4)
	if not _has_stage_api(source):
		return
	var a := UnitCarryLoad.new(5)
	var b := UnitCarryLoad.new(20)
	assert_true(a.enable_provenance(&"a"))
	assert_true(b.enable_provenance(&"b"))
	var rock := ResourceSource.new()
	rock.configure(&"rock", STONE, 6, 3)
	assert_eq(rock.transfer_to_carry_load_with_provenance(a, &"stone", &"stone_lot", 1).extracted, 1)
	rock.free()

	_reach_fallen(source)
	var fault := source as FaultSource
	fault.reject_commit = true
	var before := a.provenance_snapshot()
	var revision: Variant = source.get(&"_transaction_revision")
	assert_eq(source.transfer_to_carry_load_with_provenance(a, &"take_a", &"lot_a", 4).reason, "stale_or_aborted")
	assert_eq(source.get_remaining_amount(), 3)
	assert_eq(source.get(&"_transaction_revision"), revision)
	assert_eq(source.get_provenance_receipt(&"take_a"), {})
	assert_eq(a.provenance_snapshot(), before)

	fault.reject_commit = false
	fault.close_barrier_at_commit = true
	assert_eq(source.transfer_to_carry_load_with_provenance(a, &"take_a", &"lot_a", 4).reason, "stale_or_aborted")
	assert_eq(source.get_remaining_amount(), 3)
	assert_eq(source.get(&"_transaction_revision"), revision)
	assert_eq(source.get_provenance_receipt(&"take_a"), {})
	assert_eq(a.provenance_snapshot(), before)
	fault.close_barrier_at_commit = false
	source.set(&"_tree_harvest_stage", Stage.FALLEN)

	assert_eq(source.transfer_to_carry_load_with_provenance(a, &"take_a", &"lot_a", 4).extracted, 1)
	assert_eq(a.get_current_weight(), 5)
	assert_eq(a.get_amount(&"stone"), 1)
	var events: Array[Array] = []
	b.load_changed.connect(func() -> void:
		events.append([_stage(source), source.get_remaining_amount(), b.get_amount(&"wood")]))
	assert_eq(source.transfer_to_carry_load_with_provenance(b, &"take_b", &"lot_b", 4).extracted, 2)
	assert_eq(events, [[Stage.DEPLETED, 0, 2]])
	assert_eq(source.get_remaining_amount() + a.get_amount(&"wood") + b.get_amount(&"wood"), 3)
	assert_true(a.validate_provenance())
	assert_true(b.validate_provenance())
	var after := b.provenance_snapshot()
	var replay := source.transfer_to_carry_load_with_provenance(b, &"take_b", &"lot_b", 4)
	assert_true(bool(replay.replayed))
	assert_eq(replay.extracted, 0)
	assert_eq(replay.committed_amount, 2)
	assert_eq(source.transfer_to_carry_load_with_provenance(b, &"take_b", &"other", 4).reason, "operation_conflict")
	assert_eq(b.provenance_snapshot(), after)


func test_10_legacy_minus_one_and_depleted_scene_nodes() -> void:
	var source := _tree(4, 4, true)
	if not _has_stage_api(source):
		return
	_reach_fallen(source)
	var legacy := UnitCarryLoad.new(20)
	assert_true(legacy.add_units(WOOD, 1))
	assert_true(legacy.add_units(FOOD, 2))
	assert_eq(source.transfer_to_carry_load(legacy, -1), 4)
	assert_eq(source.get_remaining_amount() + legacy.get_amount(&"wood"), 5)
	assert_eq(legacy.get_current_weight(), 12)
	assert_eq(_stage(source), Stage.DEPLETED)
	assert_true((source.get_node("DepletedVisual") as Node3D).visible)
	assert_false((source.get_node("AvailableVisual") as Node3D).visible)
	assert_ne((source.get_node("SolidBody") as StaticBody3D).collision_layer, 0)
	assert_true((source.get_node("InteractionArea") as Area3D).monitorable)


func test_11_stone_and_food_keep_existing_extraction() -> void:
	for definition: ResourceDefinition in [STONE, FOOD]:
		var source := ResourceSource.new()
		add_test_child(source)
		source.configure(&"nonwood", definition, 5, 2)
		assert_true(source.can_extract())
		assert_eq(source.extract(1), 1)
		var legacy := UnitCarryLoad.new(20)
		assert_eq(source.transfer_to_carry_load(legacy, -1), 2)
		var tracked := UnitCarryLoad.new(20)
		assert_true(tracked.enable_provenance(&"worker"))
		assert_eq(source.transfer_to_carry_load_with_provenance(tracked, &"take", &"lot", 3).extracted, 2)
		assert_true(source.is_depleted())
		assert_false(source.is_felling())
		assert_false(source.is_fallen())
		assert_false(source.is_physics_processing())


func test_12_reentrant_depletion_publishes_stages_in_commit_order() -> void:
	var source := _tree(1, 1)
	if not _has_stage_api(source):
		return
	var worker := _worker(source)
	var observed: Array[int] = []
	source.connect(&"tree_harvest_stage_changed", func(tree: ResourceSource, stage: int) -> void:
		if stage == Stage.FALLEN:
			assert_eq(tree.extract(1), 1))
	source.connect(&"tree_harvest_stage_changed", func(_tree_node: ResourceSource, stage: int) -> void:
		observed.append(stage))
	assert_true(_begin(source, worker, RefCounted.new()))
	source.call(&"_physics_process", 0.5)
	source.call(&"_physics_process", 2.0)
	source.call(&"_physics_process", 0.5)
	assert_eq(observed, [Stage.CHOPPING, Stage.FELLING, Stage.FALLEN, Stage.DEPLETED])
	assert_eq(source.get_remaining_amount(), 0)
