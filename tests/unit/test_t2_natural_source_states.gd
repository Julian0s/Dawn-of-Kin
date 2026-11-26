extends TestCase
## Unit tests for T2.4.3 natural visual states of resource sources:
## - Trees start standing, trigger felling once (without reversing), and show stump when depleted.
## - Bushes start with all fruits visible, reduce deterministically, keep green vegetation on depletion, and never regenerate.
## - Zero per-frame processing and clean tween/transform lifecycle.

const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const MAT_BUSH_FOLIAGE: Material = preload("res://assets/placeholder/mat_bush_source_foliage.tres")
const MAT_TRUNK_BROWN: Material = preload("res://assets/placeholder/mat_trunk_placeholder.tres")


const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")


func _start_real_tree_cut(tree: ResourceSource) -> Dictionary:
	var cutter: Unit = UNIT_SCENE.instantiate() as Unit
	cutter.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	add_test_child(cutter)
	var radius: float = (tree.get_interaction_radius() + tree.get_solid_radius() + WorldNavigation.DEFAULT_AGENT_RADIUS) * 0.5
	cutter.global_position = tree.global_position + Vector3(-radius, 0.0, 0.0)
	var order := UnitOrder.new()
	order.mark_running()
	cutter._current_order = order
	var auth := RefCounted.new()
	assert_true(tree.reserve_worker(cutter))
	assert_true(tree.begin_tree_cut(cutter, order, cutter.get_order_revision(), auth))
	return {"unit": cutter, "order": order, "auth": auth}


func test_01_tree_initial_standing_one_shot_headless_felling_and_stump_depletion() -> void:
	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	add_test_child(tree)
	await wait_process_frames(1)

	assert_true(tree.is_valid())
	assert_true(tree.is_standing(), "Tree must start standing before any extraction")
	assert_false(tree.is_felling())
	assert_false(tree.is_fallen())
	assert_false(tree.can_extract(1), "D3: standing tree refuses extraction before fall")
	assert_eq(tree.extract(2), 0)
	var pivot: Node3D = tree.get_node_or_null("AvailableVisual/FellingPivot") as Node3D
	assert_not_null(pivot)
	assert_near(pivot.rotation.z, 0.0, 0.001)
	assert_true((tree.get_node("AvailableVisual/StumpBaseMesh") as Node3D).visible)
	assert_false((tree.get_node("DepletedVisual") as Node3D).visible)

	# Bare ResourceSource without FellingPivot transitions cleanly through cut -> FELLING -> FALLEN without stalling
	var bare_wood := ResourceSource.new()
	bare_wood.configure(&"bare_wood", WOOD_RES, 10, 2, 2)
	bare_wood.chop_duration_sec = 0.04
	bare_wood.felling_duration_sec = 0.05
	add_test_child(bare_wood)
	assert_true(bare_wood.is_standing())
	assert_eq(bare_wood.extract(2), 0, "D3: bare standing wood refuses extraction before fall")
	var cut_ctx := _start_real_tree_cut(bare_wood)
	var frames: int = 0
	while not bare_wood.is_fallen() and frames < 60:
		await wait_physics_frames(1)
		frames += 1
	bare_wood.release_worker(cut_ctx["unit"] as Unit)
	assert_false(bare_wood.is_standing())
	assert_false(bare_wood.is_felling())
	assert_true(bare_wood.is_fallen())
	assert_eq(bare_wood.get_remaining_amount(), 10, "D3: zero wood extracted before FALLEN")
	assert_eq(bare_wood.extract(2), 2)
	assert_eq(bare_wood.get_remaining_amount(), 8)
	assert_true(bare_wood.is_fallen())

	# Rock source remains unaffected by tree/bush states
	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	add_test_child(rock)
	assert_false(rock.is_standing())
	assert_false(rock.is_felling())
	assert_false(rock.is_fallen())
	assert_eq(rock.extract(1), 1)
	assert_true((rock.get_node("AvailableVisual") as Node3D).visible)


func test_02_bush_fruits_visible_progressive_reduction_and_green_preserved() -> void:
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.initial_amount = 12
	bush.max_extract_per_operation = 2
	add_test_child(bush)
	await wait_process_frames(1)

	var total_fruits: int = bush.get_total_fruit_count()
	assert_eq(total_fruits, 6)
	assert_eq(bush.get_visible_fruit_count(), 6, "All fruits must start visible on untouched bush")
	assert_true((bush.get_node("AvailableVisual") as Node3D).visible)
	assert_false((bush.get_node("DepletedVisual") as Node3D).visible)

	# Collect progressively and verify monotonic fruit reduction (remaining > 0 always leaves >= 1)
	var prev_count: int = bush.get_visible_fruit_count()
	var saw_intermediate_drop: bool = false
	while bush.get_remaining_amount() > 2:
		assert_eq(bush.extract(2), 2)
		var curr_count: int = bush.get_visible_fruit_count()
		assert_true(curr_count <= prev_count, "Visible fruits must decrease monotonically as berries are picked")
		assert_gt(curr_count, 0, "At least one fruit remains visible while food remains")
		if curr_count < total_fruits:
			saw_intermediate_drop = true
		prev_count = curr_count

	assert_true(saw_intermediate_drop, "Mid-harvest bush must visibly drop fruit count before depletion")
	assert_eq(bush.extract(2), 2)
	assert_true(bush.is_depleted())
	assert_eq(bush.get_visible_fruit_count(), 0, "Depleted bush must hide all fruits")
	assert_false((bush.get_node("AvailableVisual") as Node3D).visible)
	assert_false((bush.get_node("DiscoverabilityBadge") as Node3D).visible)

	var depleted_visual: Node3D = bush.get_node("DepletedVisual") as Node3D
	assert_true(depleted_visual.visible, "Depleted bush must keep green vegetation visible")
	var green_mesh_count: int = 0
	for child: Node in depleted_visual.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			assert_not_null(mi.mesh)
			var mat: Material = mi.mesh.surface_get_material(0)
			assert_eq(mat, MAT_BUSH_FOLIAGE, "Depleted bush must preserve green foliage material")
			assert_ne_mat(mat, MAT_TRUNK_BROWN)
			green_mesh_count += 1
	assert_gt(green_mesh_count, 0, "Depleted bush must contain visible green foliage meshes")


func assert_ne_mat(a: Material, b: Material) -> void:
	assert_false(a == b, "Depleted bush must never turn into brown wood material")


func test_03_no_extraction_and_no_regeneration_after_depletion() -> void:
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.initial_amount = 4
	bush.max_extract_per_operation = 4
	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	tree.initial_amount = 4
	tree.max_extract_per_operation = 4
	add_test_child(bush)
	add_test_child(tree)

	var time_provider := SimulatedWorldTimeProvider.new()
	var clock := EconomyClockController.new()
	clock.configure(null, time_provider)
	add_test_child(clock)
	await wait_process_frames(1)

	assert_eq(bush.extract(4), 4)
	# D3 contract: standing tree refuses extraction; fell fixture before testing post-depletion invariants.
	assert_eq(tree.extract(4), 0)
	tree.set(&"_tree_harvest_stage", ResourceSource.TreeHarvestStage.FALLEN)
	assert_eq(tree.extract(4), 4)
	assert_true(bush.is_depleted())
	assert_true(tree.is_depleted())
	assert_eq(bush.extract(1), 0)
	assert_eq(tree.extract(1), 0)
	assert_false(bush.can_extract(1))
	assert_false(tree.can_extract(1))

	var carry := UnitCarryLoad.new(20)
	assert_eq(bush.transfer_to_carry_load(carry, 1), 0)
	assert_eq(tree.transfer_to_carry_load(carry, 1), 0)

	# Simulate elapsed game time and frames -> zero free regeneration
	for _step: int in range(6):
		time_provider.advance(120.0)
		await wait_process_frames(2)

	assert_eq(bush.get_remaining_amount(), 0)
	assert_eq(tree.get_remaining_amount(), 0)
	assert_eq(bush.get_visible_fruit_count(), 0)
	assert_true(bush.is_depleted())
	assert_true(tree.is_depleted())
	assert_true((bush.get_node("DepletedVisual") as Node3D).visible)
	assert_true((tree.get_node("DepletedVisual") as Node3D).visible)


func test_04_zero_per_frame_processing_and_clean_felling_tween_lifecycle() -> void:
	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	tree.initial_amount = 10
	tree.max_extract_per_operation = 2
	tree.felling_duration_sec = 0.14
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	add_test_child(tree)
	add_test_child(bush)
	add_test_child(rock)
	await wait_process_frames(1)

	for src: ResourceSource in [tree, bush, rock]:
		assert_false(src.is_processing())
		assert_false(src.is_physics_processing())

	# D3 contract: progressive cut transitions to single FELLING state with zero pre-fall extraction.
	tree.chop_duration_sec = 0.05
	var cut_1 := _start_real_tree_cut(tree)
	var frames: int = 0
	while not tree.is_felling() and frames < 60:
		await wait_physics_frames(1)
		frames += 1
	assert_true(tree.is_felling())
	assert_false(tree.is_processing(), "Tree felling must never use _process")
	assert_eq(tree.extract(2), 0, "D3: zero wood extracted while tree is still falling")
	assert_eq(tree.get_remaining_amount(), 10)
	assert_true(tree.is_felling())

	frames = 0
	while tree.is_felling() and frames < 60:
		await wait_physics_frames(1)
		frames += 1
	tree.release_worker(cut_1["unit"] as Unit)

	assert_true(tree.is_fallen(), "Tree felling tween must settle into FALLEN state cleanly")
	assert_false(tree.is_felling())
	assert_false(tree.is_standing())
	assert_false(tree.is_physics_processing(), "Idle fallen tree disables _physics_process")
	var pivot: Node3D = tree.get_node("AvailableVisual/FellingPivot") as Node3D
	assert_lt(pivot.rotation.z, -1.35, "Fallen tree pivot must rest tilted near horizontal")

	# Subsequent extract keeps tree fallen cleanly without standing up again
	var fallen_rot_z: float = pivot.rotation.z
	assert_eq(tree.extract(2), 2)
	await wait_process_frames(3)
	assert_true(tree.is_fallen())
	assert_near(pivot.rotation.z, fallen_rot_z, 0.01)

	# Configure resets pose cleanly; exit tree clears any active felling tween cleanly
	tree.configure(&"tree_reset", WOOD_RES, 10, 2, 2)
	tree.chop_duration_sec = 0.04
	assert_true(tree.is_standing())
	assert_near(pivot.rotation.z, 0.0, 0.001)
	var _cut_2 := _start_real_tree_cut(tree)
	frames = 0
	while not tree.is_felling() and frames < 60:
		await wait_physics_frames(1)
		frames += 1
	assert_true(tree.is_felling())
	tree.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(tree))
