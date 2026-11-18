extends TestCase
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")

class FaultSource extends ResourceSource:
	var reject: bool = false
	var mutate_load: UnitCarryLoad = null
	func _before_provenance_transfer_commit() -> bool:
		if mutate_load != null:
			mutate_load.set_base_capacity(19)
			mutate_load.set_base_capacity(20)
		return not reject

func source(def: ResourceDefinition, amount: int, limit: int = 3) -> FaultSource:
	var obj := FaultSource.new()
	add_test_child(obj)
	obj.configure(&"test_source", def, amount, limit, 2)
	return obj

func test_real_resources_conservation_replay_and_legacy() -> void:
	for def: ResourceDefinition in [WOOD, STONE, FOOD]:
		var s := source(def, 5)
		var load := UnitCarryLoad.new(100)
		assert_true(load.enable_provenance(&"worker"))
		var first: Dictionary = s.transfer_to_carry_load_with_provenance(load, "one", "lot1", 4)
		assert_true(first.ok)
		assert_eq(first.extracted, 3)
		assert_eq(s.get_remaining_amount() + load.get_amount(def.resource_id), 5)
		assert_true(load.validate_provenance())
		var second: Dictionary = s.transfer_to_carry_load_with_provenance(load, "two", "lot2", 3)
		assert_true(second.ok)
		assert_eq(second.extracted, 2)
		assert_eq(s.get_remaining_amount(), 0)
		var before: Dictionary = load.provenance_snapshot()
		var replay: Dictionary = s.transfer_to_carry_load_with_provenance(load, "two", "lot2", 3)
		assert_true(replay.ok)
		assert_true(replay.replayed)
		assert_eq(replay.extracted, 0)
		assert_eq(replay.committed_amount, 2)
		assert_eq(load.provenance_snapshot(), before)
		assert_false(s.transfer_to_carry_load_with_provenance(load, "two", "different", 3).ok)
		assert_eq(s.get_remaining_amount(), 0)
	var legacy := source(WOOD, 4)
	var old := UnitCarryLoad.new(20)
	assert_eq(legacy.transfer_to_carry_load(old, 2), 2)
	assert_eq(old.get_amount(WOOD.resource_id), 2)
	var controlled := UnitCarryLoad.new(20)
	assert_true(controlled.enable_provenance(&"worker"))
	assert_eq(legacy.transfer_to_carry_load(controlled, 1), 0)
	assert_eq(legacy.get_remaining_amount(), 2)

func test_failures_and_stale_revision_leave_materials_unchanged() -> void:
	var s := source(WOOD, 8)
	var load := UnitCarryLoad.new(20)
	assert_true(load.enable_provenance(&"unit"))
	var before: Dictionary = load.provenance_snapshot()
	assert_false(s.transfer_to_carry_load_with_provenance(load, "", "lot", 1).ok)
	s.reject = true
	assert_false(s.transfer_to_carry_load_with_provenance(load, "op", "lot", 2).ok)
	assert_eq(s.get_remaining_amount(), 8)
	assert_eq(load.provenance_snapshot(), before)
	s.reject = false
	s.mutate_load = load
	assert_false(s.transfer_to_carry_load_with_provenance(load, "op", "lot", 2).ok)
	s.mutate_load = null
	assert_eq(s.get_remaining_amount(), 8)
	assert_eq(load.provenance_snapshot(), before)
	assert_true(s.transfer_to_carry_load_with_provenance(load, "op", "lot", 2).ok)
	before = load.provenance_snapshot()
	assert_false(s.transfer_to_carry_load_with_provenance(load, "op2", "lot", 1).ok)
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(s.get_remaining_amount(), 6)

func test_signals_are_consistent_and_reentry_rejected() -> void:
	var s := source(WOOD, 5)
	var load := UnitCarryLoad.new(20)
	assert_true(load.enable_provenance(&"unit"))
	var observations: Array = []
	var on_load := func() -> void:
		observations.append([s.get_remaining_amount(), load.get_amount(WOOD.resource_id), load.validate_provenance(), s.transfer_to_carry_load_with_provenance(load, "other", "other", 1).ok])
	var on_source := func(_s: ResourceSource, _left: int, _delta: int) -> void:
		observations.append([s.get_remaining_amount(), load.get_amount(WOOD.resource_id), load.validate_provenance(), s.transfer_to_carry_load_with_provenance(load, "other", "other", 1).ok])
	load.load_changed.connect(on_load)
	s.amount_changed.connect(on_source)
	assert_true(s.transfer_to_carry_load_with_provenance(load, "op", "lot", 2).ok)
	assert_eq(observations, [[3, 2, true, false], [3, 2, true, false]])
	load.load_changed.disconnect(on_load)
	s.amount_changed.disconnect(on_source)

func test_capacity_weight_and_failures_do_not_notify() -> void:
	var s := source(WOOD, 8, 8)
	var load := UnitCarryLoad.new(WOOD.unit_weight * 2)
	assert_true(load.enable_provenance(&"unit"))
	var calls: Array = []
	var on_load := func() -> void: calls.append("load")
	var on_source := func(_s: ResourceSource, _left: int, _delta: int) -> void: calls.append("source")
	load.load_changed.connect(on_load)
	s.amount_changed.connect(on_source)
	var result: Dictionary = s.transfer_to_carry_load_with_provenance(load, "first", "l1", 8)
	assert_true(result.ok)
	assert_eq(result.extracted, 2)
	assert_eq(s.get_remaining_amount(), 6)
	assert_eq(load.get_current_weight(), WOOD.unit_weight * 2)
	assert_eq(calls, ["load", "source"])
	var before: Dictionary = load.provenance_snapshot()
	calls.clear()
	assert_false(s.transfer_to_carry_load_with_provenance(load, "full", "l2", 1).ok)
	assert_false(s.transfer_to_carry_load_with_provenance(load, "bad", "", 1).ok)
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(s.get_remaining_amount(), 6)
	assert_eq(calls, [])
	load.load_changed.disconnect(on_load)
	s.amount_changed.disconnect(on_source)
	var mismatch: ResourceDefinition = WOOD.duplicate()
	mismatch.unit_weight = WOOD.unit_weight + 1
	var other := source(mismatch, 2)
	load.set_base_capacity(100)
	before = load.provenance_snapshot()
	assert_false(other.transfer_to_carry_load_with_provenance(load, "mismatch", "l3", 1).ok)
	assert_eq(other.get_remaining_amount(), 2)
	assert_eq(load.provenance_snapshot(), before)
