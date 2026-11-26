extends TestCase
## Unit tests for SourceSelectionModel (R-03A D1).
## Verifies pure visual selection semantics (D1-B, heterogeneous union, idempotency,
## WeakRef + tree_exited/depleted cleanup, region & resource filtering, zero polling).

const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")


func _spawn_source(packed: PackedScene, sid: StringName, amount: int = 12, region_id: StringName = &"default") -> ResourceSource:
	var src: ResourceSource = packed.instantiate() as ResourceSource
	src.source_id = sid
	src.initial_amount = amount
	src.set_meta(&"region_id", region_id)
	add_test_child(src)
	return src


func test_01_single_selection_replacement_and_d1b_deselect() -> void:
	var model := SourceSelectionModel.new()
	var t1 := _spawn_source(TREE_SCENE, &"t1")
	var t2 := _spawn_source(TREE_SCENE, &"t2")
	var r1 := _spawn_source(ROCK_SCENE, &"r1")
	await wait_process_frames(1)

	var changes: Array[int] = [0]
	model.selection_changed.connect(func() -> void: changes[0] += 1)

	assert_true(model.is_empty(), "Starts empty")
	assert_true(model.select_single(t1), "Select t1 succeeds")
	assert_eq(model.get_selected_count(), 1)
	assert_true(model.is_selected(t1))
	assert_eq(changes[0], 1)

	# Idempotent repeat select_single does not emit again.
	assert_false(model.select_single(t1), "Repeating select_single on sole selected source is no-op")
	assert_eq(changes[0], 1)

	# Selecting another unselected source replaces prior selection.
	assert_true(model.select_single(t2), "select_single(t2) replaces t1")
	assert_false(model.is_selected(t1))
	assert_true(model.is_selected(t2))
	assert_eq(changes[0], 2)

	# D1-B: deselect_source removes only that source, preserving others.
	model.add_sources([t1, r1])
	assert_eq(model.get_selected_count(), 3)
	assert_true(model.deselect_source(t2), "D1-B: deselect_source removes t2 only")
	assert_false(model.is_selected(t2))
	assert_true(model.is_selected(t1))
	assert_true(model.is_selected(r1))
	assert_eq(model.get_selected_count(), 2)

	# Deselecting an unselected source is a no-op.
	var prev_changes: int = changes[0]
	assert_false(model.deselect_source(t2))
	assert_eq(changes[0], prev_changes)

	model.teardown()


func test_02_toggle_and_heterogeneous_idempotent_add_sources() -> void:
	var model := SourceSelectionModel.new()
	var t1 := _spawn_source(TREE_SCENE, &"t1")
	var t2 := _spawn_source(TREE_SCENE, &"t2")
	var r1 := _spawn_source(ROCK_SCENE, &"r1")
	var b1 := _spawn_source(BUSH_SCENE, &"b1")
	await wait_process_frames(1)

	var changes: Array[int] = [0]
	model.selection_changed.connect(func() -> void: changes[0] += 1)

	assert_true(model.toggle_source(t1), "Toggle adds t1")
	assert_true(model.toggle_source(r1), "Toggle adds heterogeneous r1")
	assert_true(model.toggle_source(b1), "Toggle adds heterogeneous b1")
	assert_eq(model.get_counts_by_resource(), {&"wood": 1, &"stone": 1, &"food": 1})
	assert_eq(changes[0], 3)

	# add_sources adds only missing sources, preserves existing, never toggles off.
	var added: int = model.add_sources([t1, t2, r1])
	assert_eq(added, 1, "Only t2 should be newly added")
	assert_eq(model.get_count_for_resource(&"wood"), 2)
	assert_eq(model.get_count_for_resource(&"stone"), 1)
	assert_eq(model.get_count_for_resource(&"food"), 1)
	assert_eq(changes[0], 4)

	# Repeating add_sources with already-selected sources emits zero signals.
	var added_again: int = model.add_sources([t1, t2, r1, b1])
	assert_eq(added_again, 0)
	assert_eq(changes[0], 4)

	# Toggle off removes only that source.
	assert_false(model.toggle_source(r1), "Toggle off returns false")
	assert_eq(model.get_count_for_resource(&"stone"), 0)
	assert_eq(model.get_selected_count(), 3)

	# Clear empties all and second clear is no-op.
	model.clear()
	assert_true(model.is_empty())
	var after_clear: int = changes[0]
	model.clear()
	assert_eq(changes[0], after_clear)

	model.teardown()


func test_03_automatic_cleanup_on_depletion_and_tree_exit() -> void:
	var model := SourceSelectionModel.new()
	var t1 := _spawn_source(TREE_SCENE, &"t1", 4)
	var r1 := _spawn_source(ROCK_SCENE, &"r1", 4)
	await wait_process_frames(1)

	model.add_sources([t1, r1])
	assert_eq(model.get_selected_count(), 2)

	var changes: Array[int] = [0]
	model.selection_changed.connect(func() -> void: changes[0] += 1)

	# Depleting t1 removes it automatically via depleted signal (fixture felled per D3).
	t1.set(&"_tree_harvest_stage", ResourceSource.TreeHarvestStage.FALLEN)
	var drain_guard: int = 0
	while not t1.is_depleted() and drain_guard < 16:
		drain_guard += 1
		t1.extract(t1.get_remaining_amount())
	assert_true(t1.is_depleted())
	assert_false(model.is_selected(t1), "Depleted source must be auto-removed from selection")
	assert_eq(model.get_selected_count(), 1)
	assert_eq(changes[0], 1)

	# Depleted source cannot be re-selected.
	assert_false(model.select_single(t1))
	assert_eq(model.get_selected_count(), 1)

	# Removing r1 from tree removes it automatically via tree_exited signal.
	r1.get_parent().remove_child(r1)
	r1.queue_free()
	await wait_process_frames(1)
	assert_true(model.is_empty(), "Freed source must be auto-removed from selection")
	assert_eq(changes[0], 2)

	model.teardown()


func test_04_region_checker_and_supported_resource_filters() -> void:
	var model := SourceSelectionModel.new()
	var t_ok := _spawn_source(TREE_SCENE, &"t_ok", 10, &"default")
	var t_foreign := _spawn_source(TREE_SCENE, &"t_foreign", 10, &"other_region")
	var r_ok := _spawn_source(ROCK_SCENE, &"r_ok", 10, &"default")
	await wait_process_frames(1)

	model.configure(
		func(src: ResourceSource) -> bool:
			return src.get_meta(&"region_id", &"") == &"default",
		PackedStringArray(["wood"])
	)

	assert_true(model.is_source_eligible(t_ok))
	assert_false(model.is_source_eligible(t_foreign), "Foreign region source must be rejected")
	assert_false(model.is_source_eligible(r_ok), "Unsupported resource id must be rejected")

	var added: int = model.add_sources([t_ok, t_foreign, r_ok])
	assert_eq(added, 1)
	assert_eq(model.get_selected_sources(), [t_ok])

	# Teardown clears selection and disconnects signals cleanly.
	model.teardown()
	assert_true(model.is_empty())
	t_ok.set(&"_tree_harvest_stage", ResourceSource.TreeHarvestStage.FALLEN)
	t_ok.extract(10)
	assert_true(model.is_empty())
