extends TestCase
## Unit tests for T2.3 worker transfer contracts:
## - ResourceSource.transfer_to_carry_load() atomicity and capacity clamping
## - Post-state notification conservation & reentrancy blocking
## - Unit.State enum backward compatibility (IDLE=0, MOVING=1, WORKING=2, TRANSPORTING=3)
## - UnitCarryLoad synchronization with CharacterDefinition and GatherSlotPlanner invariants.

const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")

var _ctx: Dictionary = {}


func after_each() -> void:
	_ctx.clear()


func _on_source_or_load_changed_check_reentrancy(
	_arg1: Variant = null,
	_arg2: Variant = null,
	_arg3: Variant = null
) -> void:
	var src: ResourceSource = _ctx["source"] as ResourceSource
	var load: UnitCarryLoad = _ctx["load"] as UnitCarryLoad
	var initial_total: int = int(_ctx["initial_total"])
	var events: Array = _ctx["events"] as Array
	events.append({
		"remaining": src.get_remaining_amount(),
		"carried": load.get_amount(src.get_resource_id()),
		"sum": src.get_remaining_amount() + load.get_amount(src.get_resource_id()),
		"initial": initial_total,
	})
	if _ctx.get("try_reentrant", false) as bool:
		var re_transfer: int = src.transfer_to_carry_load(load, 1)
		var re_extract: int = src.extract(1)
		_ctx["reentrant_results"] = [re_transfer, re_extract]


func test_01_atomic_transfer_to_carry_load_respects_weight_cap_and_noops_when_full() -> void:
	var src := ResourceSource.new()
	src.configure(&"stone_test", STONE_RES, 10, 2, 2) # weight 3
	add_test_child(src)

	var load := UnitCarryLoad.new(7) # max 2 stone (weight 6), leaving 1 weight free
	assert_eq(src.transfer_to_carry_load(load, 2), 2)
	assert_eq(src.get_remaining_amount(), 8)
	assert_eq(load.get_amount(&"stone"), 2)
	assert_eq(load.get_current_weight(), 6)
	assert_false(load.can_fit_one(STONE_RES))

	# Cannot fit +1 stone (remaining cap 1 < weight 3): must be zero drain and zero mutation
	assert_eq(src.transfer_to_carry_load(load, 2), 0)
	assert_eq(src.get_remaining_amount(), 8)
	assert_eq(load.get_amount(&"stone"), 2)

	# Increasing capacity allows clamped transfer (requested 5 -> capped by max_extract_per_operation=2)
	assert_true(load.set_base_capacity(20))
	assert_eq(src.transfer_to_carry_load(load, 5), 2)
	assert_eq(src.get_remaining_amount(), 6)
	assert_eq(load.get_amount(&"stone"), 4)


func test_02_transfer_commits_both_sides_before_signals_and_blocks_reentrancy() -> void:
	var src := ResourceSource.new()
	src.configure(&"wood_test", WOOD_RES, 3, 3, 2) # weight 2
	add_test_child(src)

	var load := UnitCarryLoad.new(20)
	var events: Array = []
	_ctx["source"] = src
	_ctx["load"] = load
	_ctx["initial_total"] = 3
	_ctx["events"] = events
	_ctx["try_reentrant"] = true

	load.load_changed.connect(Callable(self, "_on_source_or_load_changed_check_reentrancy"))
	src.amount_changed.connect(Callable(self, "_on_source_or_load_changed_check_reentrancy"))
	src.depleted.connect(Callable(self, "_on_source_or_load_changed_check_reentrancy"))

	var transferred: int = src.transfer_to_carry_load(load, 3)
	assert_eq(transferred, 3)
	assert_eq(src.get_remaining_amount(), 0)
	assert_true(src.is_depleted())
	assert_eq(load.get_amount(&"wood"), 3)

	assert_eq(events.size(), 3, "load_changed, amount_changed, and depleted must all fire once")
	for ev_var: Variant in events:
		var ev: Dictionary = ev_var as Dictionary
		assert_eq(int(ev["sum"]), 3, "Exact conservation must hold at every observer signal")

	var re_results: Array = _ctx.get("reentrant_results", [-1, -1]) as Array
	assert_eq(int(re_results[0]), 0, "Reentrant transfer_to_carry_load must be blocked")
	assert_eq(int(re_results[1]), 0, "Reentrant extract must be blocked during transfer emission")


func test_03_unit_state_enum_and_carry_load_contract() -> void:
	assert_eq(int(Unit.State.IDLE), 0)
	assert_eq(int(Unit.State.MOVING), 1)
	assert_eq(int(Unit.State.WORKING), 2)
	assert_eq(int(Unit.State.TRANSPORTING), 3)

	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	var custom_def: CharacterDefinition = LEADER_A_DEF.duplicate() as CharacterDefinition
	custom_def.base_carry_capacity = 14
	unit.definition = custom_def
	add_test_child(unit)
	await wait_process_frames(1)

	assert_eq(unit.get_state_name(), "IDLE")
	var carry: UnitCarryLoad = unit.get_carry_load()
	assert_not_null(carry)
	assert_eq(carry.get_effective_capacity(), 14)

	# Reducing definition capacity keeps pre-existing cargo safely (overloaded rather than discarding)
	assert_true(carry.add_units(FOOD_RES, 10))
	var small_def: CharacterDefinition = LEADER_A_DEF.duplicate() as CharacterDefinition
	small_def.base_carry_capacity = 6
	unit.apply_definition(small_def)
	assert_eq(carry.get_effective_capacity(), 6)
	assert_eq(carry.get_amount(&"food"), 10)
	assert_true(carry.is_overloaded())


func test_04_resource_source_solid_radius_and_planner_guards() -> void:
	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	add_test_child(rock)
	add_test_child(tree)
	add_test_child(bush)
	await wait_process_frames(1)

	assert_gt(rock.get_solid_radius(), 0.85)
	assert_gt(tree.get_solid_radius(), 0.30)
	assert_near(bush.get_solid_radius(), 0.0, 0.001)

	var invalid_res: Dictionary = GatherSlotPlanner.compute_source_approach_slot(Vector3.ZERO, null, null)
	assert_false(bool(invalid_res["valid"]))
	var invalid_camp: Dictionary = GatherSlotPlanner.compute_camp_dropoff_slot(Vector3.ZERO, null, null)
	assert_false(bool(invalid_camp["valid"]))


func test_05_repeated_reserve_release_and_two_workers_single_last_slot_contract() -> void:
	var src := ResourceSource.new()
	src.configure(&"food_slot_test", FOOD_RES, 10, 2, 1)
	var worker_a := Node3D.new()
	var worker_b := Node3D.new()
	add_test_child(src)
	add_test_child(worker_a)
	add_test_child(worker_b)

	assert_false(src.is_worker_reserved(worker_a))
	assert_true(src.reserve_worker(worker_a))
	assert_true(src.reserve_worker(worker_a), "Repeated reserve for same worker must be idempotent")
	assert_true(src.is_worker_reserved(worker_a))
	assert_eq(src.get_active_worker_count(), 1)

	# Second worker racing for occupied single slot fails cleanly without overflowing max_simultaneous_workers
	assert_false(src.has_worker_slot(worker_b))
	assert_false(src.reserve_worker(worker_b))
	assert_false(src.is_worker_reserved(worker_b))
	assert_eq(src.get_active_worker_count(), 1)

	# Repeated releases are safe no-ops after count drops to 0
	src.release_worker(worker_a)
	src.release_worker(worker_a)
	assert_false(src.is_worker_reserved(worker_a))
	assert_eq(src.get_active_worker_count(), 0)

	# Now worker_b acquires cleanly
	assert_true(src.has_worker_slot(worker_b))
	assert_true(src.reserve_worker(worker_b))
	assert_true(src.is_worker_reserved(worker_b))
	assert_eq(src.get_active_worker_count(), 1)
