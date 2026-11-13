extends TestCase
## Unit tests for SelectionManager state invariants, PickResult factories, and DPI drag threshold.

const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")


func _create_test_harness() -> Dictionary:
	var container := Node3D.new()
	add_test_child(container)

	var manager := SelectionManager.new()
	container.add_child(manager)

	var def_a := CharacterDefinition.new()
	def_a.character_id = &"leader_a"
	var unit_a: Unit = UNIT_SCENE.instantiate() as Unit
	unit_a.definition = def_a
	unit_a.position = Vector3(-2.0, 0.0, 0.0)
	container.add_child(unit_a)

	var def_b := CharacterDefinition.new()
	def_b.character_id = &"leader_b"
	var unit_b: Unit = UNIT_SCENE.instantiate() as Unit
	unit_b.definition = def_b
	unit_b.position = Vector3(2.0, 0.0, 0.0)
	container.add_child(unit_b)

	return {
		"container": container,
		"manager": manager,
		"unit_a": unit_a,
		"unit_b": unit_b,
	}


func _cleanup_harness(harness: Dictionary) -> void:
	var container: Node = harness.get("container") as Node
	if container != null and is_instance_valid(container):
		container.queue_free()
	await wait_process_frames(2)


func test_01_pick_result_factories_and_predicates() -> void:
	var none_res: PickResult = PickResult.none()
	assert_true(none_res.is_none())
	assert_false(none_res.is_unit())
	assert_false(none_res.is_ground())
	assert_false(none_res.is_obstacle())

	var ground_res: PickResult = PickResult.from_ground(Vector3(1.0, 0.0, 2.0), Vector3.UP)
	assert_true(ground_res.is_ground())
	assert_false(ground_res.is_none())
	assert_vec3_near(ground_res.position, Vector3(1.0, 0.0, 2.0), 0.0001)
	assert_vec3_near(ground_res.normal, Vector3.UP, 0.0001)

	var obstacle_res: PickResult = PickResult.from_obstacle(Vector3(3.0, 1.5, -4.0), Vector3.FORWARD)
	assert_true(obstacle_res.is_obstacle())
	assert_false(obstacle_res.is_unit())

	var harness: Dictionary = _create_test_harness()
	var unit_a: Unit = harness["unit_a"] as Unit
	await wait_process_frames(1)

	var unit_res: PickResult = PickResult.from_unit(unit_a, Vector3(-2.0, 1.0, 0.0), Vector3.UP, unit_a.get_selection_area())
	assert_true(unit_res.is_unit())
	assert_eq(unit_res.unit, unit_a)

	await _cleanup_harness(harness)
	assert_false(unit_res.is_unit(), "Freed unit must make PickResult.is_unit() false")


func test_02_drag_threshold_dpi_scaling() -> void:
	assert_near(RtsInputController.compute_drag_threshold_px(96), 6.0, 0.001)
	assert_near(RtsInputController.compute_drag_threshold_px(192), 12.0, 0.001)
	assert_near(RtsInputController.compute_drag_threshold_px(48), 6.0, 0.001, "Scale below 1.0 clamps at base threshold")


func test_03_select_single_and_exclusivity() -> void:
	var harness: Dictionary = _create_test_harness()
	var manager: SelectionManager = harness["manager"] as SelectionManager
	var unit_a: Unit = harness["unit_a"] as Unit
	var unit_b: Unit = harness["unit_b"] as Unit
	await wait_process_frames(1)

	var emissions: Array[int] = []
	var latest_counts: Array[int] = []
	manager.selection_changed.connect(func(units: Array[Unit]) -> void:
		emissions.append(emissions.size() + 1)
		latest_counts.append(units.size())
	)

	assert_true(manager.is_empty())
	manager.select_single(unit_a)
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(unit_a))
	assert_true(unit_a.is_selected())
	assert_false(unit_b.is_selected())
	assert_eq(emissions.size(), 1)

	# Selecting the already-exclusively-selected unit is a no-op for signal emissions.
	manager.select_single(unit_a)
	assert_eq(manager.get_selection_count(), 1)
	assert_eq(emissions.size(), 1)

	manager.select_single(unit_b)
	assert_eq(manager.get_selection_count(), 1)
	assert_false(manager.is_selected(unit_a))
	assert_false(unit_a.is_selected())
	assert_true(manager.is_selected(unit_b))
	assert_true(unit_b.is_selected())
	assert_eq(emissions.size(), 2)
	assert_eq(latest_counts[1], 1)

	await _cleanup_harness(harness)


func test_04_add_remove_toggle_no_duplicates() -> void:
	var harness: Dictionary = _create_test_harness()
	var manager: SelectionManager = harness["manager"] as SelectionManager
	var unit_a: Unit = harness["unit_a"] as Unit
	var unit_b: Unit = harness["unit_b"] as Unit
	await wait_process_frames(1)

	var signal_counts: Array[int] = [0]
	manager.selection_changed.connect(func(_units: Array[Unit]) -> void:
		signal_counts[0] += 1
	)

	manager.add_unit(unit_a)
	manager.add_unit(unit_a)
	assert_eq(manager.get_selection_count(), 1)
	assert_eq(signal_counts[0], 1)

	manager.add_unit(unit_b)
	assert_eq(manager.get_selection_count(), 2)
	assert_true(manager.is_selected(unit_a))
	assert_true(manager.is_selected(unit_b))
	assert_eq(signal_counts[0], 2)

	manager.toggle_unit(unit_a)
	assert_eq(manager.get_selection_count(), 1)
	assert_false(manager.is_selected(unit_a))
	assert_false(unit_a.is_selected())
	assert_true(manager.is_selected(unit_b))

	manager.toggle_unit(unit_a)
	assert_eq(manager.get_selection_count(), 2)
	assert_true(manager.is_selected(unit_a))

	manager.remove_unit(unit_b)
	assert_eq(manager.get_selection_count(), 1)
	assert_false(unit_b.is_selected())

	manager.clear_selection()
	assert_true(manager.is_empty())
	assert_false(unit_a.is_selected())
	var count_after_clear: int = signal_counts[0]
	manager.clear_selection()
	assert_eq(signal_counts[0], count_after_clear, "Repeated clear_selection on empty selection must not emit")

	await _cleanup_harness(harness)


func test_05_set_selection_deduplication_and_noop() -> void:
	var harness: Dictionary = _create_test_harness()
	var manager: SelectionManager = harness["manager"] as SelectionManager
	var unit_a: Unit = harness["unit_a"] as Unit
	var unit_b: Unit = harness["unit_b"] as Unit
	await wait_process_frames(1)

	var signal_counts: Array[int] = [0]
	manager.selection_changed.connect(func(_units: Array[Unit]) -> void:
		signal_counts[0] += 1
	)

	var batch: Array[Unit] = [unit_a, unit_a, unit_b]
	manager.set_selection(batch)
	assert_eq(manager.get_selection_count(), 2)
	assert_eq(signal_counts[0], 1)

	var identical: Array[Unit] = [unit_a, unit_b]
	manager.set_selection(identical)
	assert_eq(signal_counts[0], 1, "Identical set_selection should be a no-op")

	var empty: Array[Unit] = []
	manager.set_selection(empty)
	assert_true(manager.is_empty())
	assert_false(unit_a.is_selected())
	assert_false(unit_b.is_selected())
	assert_eq(signal_counts[0], 2)

	await _cleanup_harness(harness)


func test_06_tree_exit_and_invalid_unit_cleanup() -> void:
	var harness: Dictionary = _create_test_harness()
	var container: Node = harness["container"] as Node
	var manager: SelectionManager = harness["manager"] as SelectionManager
	var unit_a: Unit = harness["unit_a"] as Unit
	var unit_b: Unit = harness["unit_b"] as Unit
	await wait_process_frames(1)

	var signal_counts: Array[int] = [0]
	manager.selection_changed.connect(func(_units: Array[Unit]) -> void:
		signal_counts[0] += 1
	)

	manager.add_unit(unit_a)
	manager.add_unit(unit_b)
	assert_eq(manager.get_selection_count(), 2)
	var before_exit_signals: int = signal_counts[0]

	container.remove_child(unit_a)
	unit_a.queue_free()
	await wait_process_frames(2)

	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(unit_b))
	assert_gt(signal_counts[0], before_exit_signals, "Removing selected unit from SceneTree must update selection and notify")

	var orphan_unit: Unit = UNIT_SCENE.instantiate() as Unit
	manager.add_unit(orphan_unit)
	assert_eq(manager.get_selection_count(), 1, "Unparented unit outside SceneTree must not be selectable")
	orphan_unit.free()

	manager.select_single(null)
	assert_true(manager.is_empty())
	assert_false(unit_b.is_selected())

	await _cleanup_harness(harness)


func test_07_add_units_batch_deduplication_and_noop() -> void:
	var harness: Dictionary = _create_test_harness()
	var manager: SelectionManager = harness["manager"] as SelectionManager
	var unit_a: Unit = harness["unit_a"] as Unit
	var unit_b: Unit = harness["unit_b"] as Unit
	await wait_process_frames(1)

	var signal_counts: Array[int] = [0]
	manager.selection_changed.connect(func(_units: Array[Unit]) -> void:
		signal_counts[0] += 1
	)

	manager.select_single(unit_a)
	assert_eq(signal_counts[0], 1)

	# Empty batch preserves existing selection and emits no redundant signal.
	var empty: Array[Unit] = []
	manager.add_units(empty)
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(unit_a))
	assert_eq(signal_counts[0], 1)

	# Duplicate + new unit adds only unit_b and emits once.
	var mixed: Array[Unit] = [unit_a, unit_b, unit_b]
	manager.add_units(mixed)
	assert_eq(manager.get_selection_count(), 2)
	assert_true(manager.is_selected(unit_a))
	assert_true(manager.is_selected(unit_b))
	assert_eq(signal_counts[0], 2)

	# Adding already-selected units emits nothing.
	manager.add_units([unit_a, unit_b])
	assert_eq(signal_counts[0], 2)

	await _cleanup_harness(harness)
