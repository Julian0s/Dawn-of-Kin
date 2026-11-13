extends TestCase
## Unit tests for T2.4.2 gathering pace profiles, continuous weight-based speed,
## overloaded safety, dynamic load transitions, and speed-aware stuck thresholds.

const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")

const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const LEADER_B_DEF: CharacterDefinition = preload("res://data/characters/leader_b.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")


func test_01_resource_source_prefabs_expose_distinct_real_pace_timings() -> void:
	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	add_test_child(tree)
	add_test_child(rock)
	add_test_child(bush)

	assert_true(tree.is_valid())
	assert_true(rock.is_valid())
	assert_true(bush.is_valid())

	assert_near(bush.get_gather_operation_duration_sec(), 1.5, 0.01)
	assert_near(tree.get_gather_operation_duration_sec(), 2.5, 0.01)
	assert_near(rock.get_gather_operation_duration_sec(), 3.5, 0.01)
	assert_lt(bush.get_gather_operation_duration_sec(), tree.get_gather_operation_duration_sec())
	assert_lt(tree.get_gather_operation_duration_sec(), rock.get_gather_operation_duration_sec())

	assert_near(bush.get_gather_prepare_duration_sec(), 0.25, 0.01)
	assert_near(tree.get_gather_prepare_duration_sec(), 0.35, 0.01)
	assert_near(rock.get_gather_prepare_duration_sec(), 0.40, 0.01)

	tree.gather_operation_duration_sec = 0.0
	assert_false(tree.is_valid(), "Operation duration <= 0 must invalidate ResourceSource")
	tree.gather_operation_duration_sec = 2.5
	tree.gather_prepare_duration_sec = -0.1
	assert_false(tree.is_valid(), "Negative prepare duration must invalidate ResourceSource")


func test_02_character_definition_pace_fields_preserve_t1_and_validate_bounds() -> void:
	assert_true(LEADER_A_DEF.is_valid())
	assert_true(LEADER_B_DEF.is_valid())
	assert_near(LEADER_A_DEF.move_speed, 4.8, 0.001, "T1 normal move speed must remain unchanged")
	assert_near(LEADER_B_DEF.move_speed, 4.8, 0.001, "T1 normal move speed must remain unchanged")
	assert_near(LEADER_A_DEF.work_approach_speed, 2.5, 0.001)
	assert_near(LEADER_A_DEF.max_load_speed_multiplier, 0.60, 0.001)

	var invalid_def: CharacterDefinition = LEADER_A_DEF.duplicate() as CharacterDefinition
	invalid_def.work_approach_speed = 0.0
	assert_false(invalid_def.is_valid())

	invalid_def = LEADER_A_DEF.duplicate() as CharacterDefinition
	invalid_def.max_load_speed_multiplier = 1.2
	assert_false(invalid_def.is_valid())

	invalid_def.max_load_speed_multiplier = 0.0
	assert_false(invalid_def.is_valid())


func test_03_continuous_load_multiplier_curve_and_overload_safety() -> void:
	assert_near(UnitMovement.compute_load_speed_multiplier(0.0, 0.60), 1.00, 0.0001)
	assert_near(UnitMovement.compute_load_speed_multiplier(0.25, 0.60), 0.90, 0.0001)
	assert_near(UnitMovement.compute_load_speed_multiplier(0.50, 0.60), 0.80, 0.0001)
	assert_near(UnitMovement.compute_load_speed_multiplier(0.75, 0.60), 0.70, 0.0001)
	assert_near(UnitMovement.compute_load_speed_multiplier(1.00, 0.60), 0.60, 0.0001)
	assert_near(UnitMovement.compute_load_speed_multiplier(1.50, 0.60), 0.60, 0.0001)
	assert_near(UnitMovement.compute_load_speed_multiplier(NAN, 0.60), 1.00, 0.0001)

	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.definition = LEADER_A_DEF
	add_test_child(unit)
	await wait_physics_frames(1)

	var movement: UnitMovement = unit.get_movement()
	var carry: UnitCarryLoad = unit.get_carry_load()
	var agent: NavigationAgent3D = unit.get_navigation_agent()

	# NORMAL context (T1 empty = 4.8 m/s -> 100% food/wood = 2.88 m/s)
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	assert_near(movement.get_target_move_speed(), 4.80, 0.01)
	assert_near(agent.max_speed, 4.80, 0.01)

	# WORK context (empty = 2.5 m/s -> 25%..100% scaling down to 1.50 m/s)
	movement.set_speed_context(UnitMovement.SpeedContext.WORK)
	assert_near(movement.get_target_move_speed(), 2.50, 0.01)

	assert_true(carry.add_units(FOOD_RES, 5)) # 5/20 = 25%
	assert_near(movement.get_target_move_speed(), 2.25, 0.01)
	assert_true(carry.add_units(FOOD_RES, 5)) # 10/20 = 50%
	assert_near(movement.get_target_move_speed(), 2.00, 0.01)
	assert_true(carry.add_units(FOOD_RES, 5)) # 15/20 = 75%
	assert_near(movement.get_target_move_speed(), 1.75, 0.01)
	assert_true(carry.add_units(FOOD_RES, 5)) # 20/20 = 100%
	assert_near(movement.get_target_move_speed(), 1.50, 0.01)
	assert_near(agent.max_speed, 1.50, 0.01)

	# Overloaded via negative capacity modifier stays safe and >= 1.50
	assert_true(carry.set_capacity_modifier(&"penalty", -10)) # 20 carried vs 10 cap = overloaded
	assert_true(carry.is_overloaded())
	assert_near(movement.get_target_move_speed(), 1.50, 0.01)
	assert_gt(movement.get_effective_move_speed(), 0.5)


func test_04_dynamic_capacity_and_unload_updates_target_speed_and_agent_max_speed() -> void:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.definition = LEADER_A_DEF
	add_test_child(unit)
	await wait_physics_frames(1)

	var movement: UnitMovement = unit.get_movement()
	var carry: UnitCarryLoad = unit.get_carry_load()
	var agent: NavigationAgent3D = unit.get_navigation_agent()
	movement.set_speed_context(UnitMovement.SpeedContext.WORK)

	assert_true(carry.add_units(WOOD_RES, 5)) # weight 10 / cap 20 = 50% -> 2.00 m/s
	assert_near(movement.get_target_move_speed(), 2.00, 0.01)

	# Increasing capacity reduces fill ratio to 10/40 = 25% -> 2.25 m/s
	assert_true(carry.set_capacity_modifier(&"pack", 20))
	assert_near(movement.get_target_move_speed(), 2.25, 0.01)
	assert_near(agent.max_speed, 2.25, 0.01)

	# Clearing load restores full 2.50 m/s WORK / 4.80 m/s NORMAL speed
	carry.take_all()
	assert_near(movement.get_target_move_speed(), 2.50, 0.01)
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	assert_near(movement.get_target_move_speed(), 4.80, 0.01)


func test_05_stuck_window_preserves_normal_baseline_and_scales_when_slow_loaded() -> void:
	assert_near(UnitMovement.compute_stuck_window_sec(4.8), UnitMovement.STUCK_WINDOW_SEC, 0.001)
	assert_near(UnitMovement.compute_stuck_window_sec(2.5), UnitMovement.STUCK_WINDOW_SEC, 0.001)

	var loaded_window: float = UnitMovement.compute_stuck_window_sec(1.5)
	assert_near(loaded_window, 2.5, 0.01)
	assert_gt(loaded_window, UnitMovement.STUCK_WINDOW_SEC)

	var extreme_window: float = UnitMovement.compute_stuck_window_sec(0.1)
	assert_near(extreme_window, UnitMovement.STUCK_WINDOW_SEC * UnitMovement.STUCK_WINDOW_MAX_SCALE, 0.001)
