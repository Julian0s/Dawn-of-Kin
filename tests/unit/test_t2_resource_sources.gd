extends TestCase
## Unit tests for T2.2 ResourceSource, placeholder prefabs, finite extraction safety,
## post-state signal emission, worker slot reservation, and PickResult resource contract.

const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")

var _observer_ctx: Dictionary = {}


func after_each() -> void:
	_observer_ctx.clear()


func _on_record_source_change(source: ResourceSource, remaining: int, delta: int) -> void:
	var events: Array = _observer_ctx["events"] as Array
	events.append({
		"signal": "amount_changed",
		"remaining_arg": remaining,
		"delta_arg": delta,
		"live_remaining": source.get_remaining_amount(),
		"live_depleted": source.is_depleted(),
		"live_available": source.is_available(),
	})


func _on_record_source_depleted(source: ResourceSource) -> void:
	var events: Array = _observer_ctx["events"] as Array
	events.append({
		"signal": "depleted",
		"live_remaining": source.get_remaining_amount(),
		"live_depleted": source.is_depleted(),
		"live_available": source.is_available(),
	})
	if _observer_ctx.get("attempt_reentrant_extract", false) as bool:
		_observer_ctx["reentrant_result"] = source.extract(1)


func _make_source(def: ResourceDefinition, amount: int, max_op: int = 2) -> ResourceSource:
	var src := ResourceSource.new()
	src.configure(&"test_src", def, amount, max_op, 2)
	add_test_child(src)
	return src


func test_01_extraction_sufficient_capped_and_insufficient() -> void:
	var src: ResourceSource = _make_source(WOOD_RES, 10, 3)
	assert_true(src.is_valid())
	assert_true(src.is_available())
	assert_false(src.is_depleted())
	assert_eq(src.get_initial_amount(), 10)
	assert_eq(src.get_remaining_amount(), 10)

	# Request below cap
	assert_eq(src.extract(2), 2)
	assert_eq(src.get_remaining_amount(), 8)

	# Request above per-operation cap clamps cleanly to max_extract_per_operation (3)
	assert_eq(src.extract(7), 3)
	assert_eq(src.get_remaining_amount(), 5)

	# Request remaining with partial extraction near end
	assert_eq(src.extract(3), 3)
	assert_eq(src.get_remaining_amount(), 2)
	assert_eq(src.extract(5), 2)
	assert_eq(src.get_remaining_amount(), 0)
	assert_true(src.is_depleted())
	assert_false(src.is_available())


func test_02_exact_depletion_and_double_last_unit_attempt() -> void:
	var src: ResourceSource = _make_source(STONE_RES, 1, 1)
	var events: Array = []
	_observer_ctx["events"] = events
	_observer_ctx["attempt_reentrant_extract"] = true
	src.amount_changed.connect(Callable(self, "_on_record_source_change"))
	src.depleted.connect(Callable(self, "_on_record_source_depleted"))

	var first_take: int = src.extract(1)
	var second_take: int = src.extract(1)

	assert_eq(first_take, 1)
	assert_eq(second_take, 0, "Second attempt on depleted source must yield 0")
	assert_eq(int(_observer_ctx.get("reentrant_result", -1)), 0, "Reentrant attempt during depleted signal must yield 0")
	assert_eq(src.get_remaining_amount(), 0, "Remaining must never go negative")
	assert_true(src.is_depleted())
	assert_false(src.can_extract(1))
	assert_eq(events.size(), 2, "Depleted signal and amount_changed must emit only once")


func test_03_invalid_extractions_rejected_without_signals() -> void:
	var src: ResourceSource = _make_source(FOOD_RES, 5, 2)
	var events: Array = []
	_observer_ctx["events"] = events
	src.amount_changed.connect(Callable(self, "_on_record_source_change"))
	src.depleted.connect(Callable(self, "_on_record_source_depleted"))

	assert_eq(src.extract(0), 0)
	assert_eq(src.extract(-3), 0)
	assert_eq(src.get_remaining_amount(), 5)
	assert_eq(events.size(), 0)

	var invalid_src := ResourceSource.new()
	add_test_child(invalid_src)
	assert_false(invalid_src.is_valid())
	assert_eq(invalid_src.extract(1), 0)


func test_04_signals_emit_only_after_final_state_updated() -> void:
	var src: ResourceSource = _make_source(WOOD_RES, 4, 2)
	var events: Array = []
	_observer_ctx["events"] = events
	src.amount_changed.connect(Callable(self, "_on_record_source_change"))
	src.depleted.connect(Callable(self, "_on_record_source_depleted"))

	assert_eq(src.extract(2), 2)
	assert_eq(events.size(), 1)
	var e0: Dictionary = events[0] as Dictionary
	assert_eq(e0["signal"] as String, "amount_changed")
	assert_eq(e0["remaining_arg"] as int, 2)
	assert_eq(e0["live_remaining"] as int, 2)
	assert_false(e0["live_depleted"] as bool)
	assert_true(e0["live_available"] as bool)

	assert_eq(src.extract(2), 2)
	assert_eq(events.size(), 3)
	var e1: Dictionary = events[1] as Dictionary
	var e2: Dictionary = events[2] as Dictionary
	assert_eq(e1["live_remaining"] as int, 0)
	assert_true(e1["live_depleted"] as bool)
	assert_false(e1["live_available"] as bool)
	assert_eq(e2["signal"] as String, "depleted")
	assert_eq(e2["live_remaining"] as int, 0)
	assert_true(e2["live_depleted"] as bool)


func test_05_placeholder_prefabs_expose_three_categories_and_visual_states() -> void:
	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	add_test_child(tree)
	add_test_child(rock)
	add_test_child(bush)

	assert_not_null(tree)
	assert_not_null(rock)
	assert_not_null(bush)
	assert_true(tree.is_valid())
	assert_true(rock.is_valid())
	assert_true(bush.is_valid())

	assert_eq(tree.get_resource_id(), &"wood")
	assert_eq(tree.get_category(), int(ResourceDefinition.Category.WOOD))
	assert_eq(rock.get_resource_id(), &"stone")
	assert_eq(rock.get_category(), int(ResourceDefinition.Category.STONE))
	assert_eq(bush.get_resource_id(), &"food")
	assert_eq(bush.get_category(), int(ResourceDefinition.Category.FOOD))

	for src: ResourceSource in [tree, rock, bush]:
		assert_false(src.is_processing(), "ResourceSource must disable _process")
		assert_false(src.is_physics_processing(), "ResourceSource must disable _physics_process")
		var area: Area3D = src.get_node_or_null("InteractionArea") as Area3D
		assert_not_null(area)
		assert_eq(area.collision_layer, CollisionLayers.MASK_RESOURCES)
		assert_eq((src.get_node("AvailableVisual") as Node3D).visible, true)
		assert_eq((src.get_node("DepletedVisual") as Node3D).visible, false)

	assert_eq((tree.get_node("SolidBody") as StaticBody3D).collision_layer, CollisionLayers.MASK_OBSTACLES)
	assert_eq((rock.get_node("SolidBody") as StaticBody3D).collision_layer, CollisionLayers.MASK_OBSTACLES)

	# Drain tree completely and check depleted visual toggle
	tree.max_extract_per_operation = 50
	assert_eq(tree.extract(20), 20)
	assert_true(tree.is_depleted())
	assert_eq((tree.get_node("AvailableVisual") as Node3D).visible, false)
	assert_eq((tree.get_node("DepletedVisual") as Node3D).visible, true)


func test_06_worker_reservation_slots_and_pick_result_contracts() -> void:
	var src: ResourceSource = _make_source(WOOD_RES, 10, 1)
	var worker_a := Node3D.new()
	var worker_b := Node3D.new()
	var worker_c := Node3D.new()
	add_test_child(worker_a)
	add_test_child(worker_b)
	add_test_child(worker_c)

	assert_true(src.has_worker_slot())
	assert_true(src.reserve_worker(worker_a))
	assert_true(src.reserve_worker(worker_a), "Idempotent reserve for same worker")
	assert_eq(src.get_active_worker_count(), 1)
	assert_true(src.reserve_worker(worker_b))
	assert_eq(src.get_active_worker_count(), 2)
	assert_false(src.has_worker_slot(worker_c))
	assert_false(src.reserve_worker(worker_c))

	src.release_worker(worker_a)
	assert_eq(src.get_active_worker_count(), 1)
	assert_true(src.has_worker_slot(worker_c))

	var pick: PickResult = PickResult.from_resource_source(src, Vector3(1, 0, 2), Vector3.UP)
	assert_true(pick.is_resource_source())
	assert_true(pick.is_available_resource_source())
	assert_eq(pick.resource_source, src)

	src.max_extract_per_operation = 10
	src.extract(10)
	assert_true(pick.is_resource_source())
	assert_false(pick.is_available_resource_source())
	assert_false(src.reserve_worker(worker_c), "Depleted source rejects worker reservations")
