extends TestCase
## Unit tests for T2.0 economic data contracts, UnitCarryLoad, DecayProfile,
## CharacterDefinition carry capacity, SettlementInventory single-authority contract,
## and end-to-end conservation invariants.

const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const LEADER_B_DEF: CharacterDefinition = preload("res://data/characters/leader_b.tres")

var _observer_ctx: Dictionary = {}


func after_each() -> void:
	_observer_ctx.clear()


func _on_record_atomic_snapshot(signal_name: String) -> void:
	var inventory: SettlementInventory = _observer_ctx["inventory"] as SettlementInventory
	var load: UnitCarryLoad = _observer_ctx["load"] as UnitCarryLoad
	var snapshots: Array = _observer_ctx["snapshots"] as Array
	snapshots.append({
		"signal": signal_name,
		"inv_wood": inventory.get_amount(&"wood"),
		"inv_food": inventory.get_amount(&"food"),
		"load_wood": load.get_amount(&"wood"),
		"load_food": load.get_amount(&"food"),
		"load_empty": load.is_empty(),
		"total_wood": inventory.get_amount(&"wood") + load.get_amount(&"wood"),
		"total_food": inventory.get_amount(&"food") + load.get_amount(&"food"),
	})


func _on_attempt_reentrant_delivery() -> void:
	var inventory: SettlementInventory = _observer_ctx["inventory"] as SettlementInventory
	var worker_a: UnitCarryLoad = _observer_ctx["worker_a"] as UnitCarryLoad
	var worker_b: UnitCarryLoad = _observer_ctx["worker_b"] as UnitCarryLoad
	var results: Array = _observer_ctx["results"] as Array
	results.append(inventory.deliver_from_carry_load(worker_a))
	results.append(inventory.deliver_from_carry_load(worker_b))


func _on_increment_counter(counter_key: String) -> void:
	_observer_ctx[counter_key] = int(_observer_ctx.get(counter_key, 0)) + 1


func test_01_total_weight_for_equal_and_mixed_resources() -> void:
	var load := UnitCarryLoad.new(20)
	assert_true(load.is_empty())
	assert_eq(load.get_current_weight(), 0)

	# Same material: 4 wood (weight 2 each) = 8
	assert_true(load.add_units(WOOD_RES, 4))
	assert_eq(load.get_amount(&"wood"), 4)
	assert_eq(load.get_current_weight(), 8)

	# Mixed categories: + 5 food (weight 1) + 2 stone (weight 3) = 8 + 5 + 6 = 19
	assert_true(load.add_units(FOOD_RES, 5))
	assert_true(load.add_units(STONE_RES, 2))
	assert_eq(load.get_amount(&"food"), 5)
	assert_eq(load.get_amount(&"stone"), 2)
	assert_eq(load.get_current_weight(), 19)
	assert_eq(load.get_remaining_capacity(), 1)


func test_02_fill_percentage_zero_to_hundred() -> void:
	var load := UnitCarryLoad.new(20)
	assert_near(load.get_fill_percentage(), 0.0, 0.0001)

	assert_true(load.add_units(WOOD_RES, 5)) # 10 / 20 = 50%
	assert_near(load.get_fill_percentage(), 50.0, 0.0001)

	assert_true(load.add_units(STONE_RES, 3)) # 10 + 9 = 19 / 20 = 95%
	assert_near(load.get_fill_percentage(), 95.0, 0.0001)

	assert_true(load.add_units(FOOD_RES, 1)) # 20 / 20 = 100%
	assert_near(load.get_fill_percentage(), 100.0, 0.0001)
	assert_true(load.is_full())


func test_03_reject_exceeding_capacity_without_state_corruption() -> void:
	var load := UnitCarryLoad.new(20)
	assert_true(load.add_units(WOOD_RES, 9)) # weight 18
	assert_false(load.add_units(WOOD_RES, 2), "Adding +4 weight over 18/20 must be rejected")
	assert_eq(load.get_amount(&"wood"), 9)
	assert_eq(load.get_current_weight(), 18)


func test_04_partial_and_full_resource_removal() -> void:
	var load := UnitCarryLoad.new(20)
	assert_true(load.add_units(STONE_RES, 5)) # weight 15

	var removed_partial: int = load.remove_units(&"stone", 2)
	assert_eq(removed_partial, 2)
	assert_eq(load.get_amount(&"stone"), 3)
	assert_eq(load.get_current_weight(), 9)

	# Requesting more than available removes only what is carried without negative values
	var removed_excess: int = load.remove_units(&"stone", 10)
	assert_eq(removed_excess, 3)
	assert_eq(load.get_amount(&"stone"), 0)
	assert_eq(load.get_current_weight(), 0)
	assert_true(load.is_empty())

	# take_all clears mixed inventory cleanly
	assert_true(load.add_units(FOOD_RES, 3))
	assert_true(load.add_units(WOOD_RES, 2))
	var snapshot: Dictionary = load.take_all()
	assert_eq(int(snapshot.get(&"food", 0)), 3)
	assert_eq(int(snapshot.get(&"wood", 0)), 2)
	assert_true(load.is_empty())
	assert_eq(load.get_current_weight(), 0)


func test_05_insufficient_capacity_for_next_unit() -> void:
	var load := UnitCarryLoad.new(20)
	# 6 stones = 18 weight (90%); 7th stone (+3) would be 21 > 20
	assert_eq(load.get_max_additional_units(STONE_RES), 6)
	assert_true(load.add_units(STONE_RES, 6))
	assert_false(load.can_fit_one(STONE_RES), "7th stone cannot fit in 2 remaining weight")
	assert_eq(load.get_max_additional_units(STONE_RES), 0)
	assert_false(load.add_units(STONE_RES, 1))

	# Lighter materials still fit in the remaining 2 weight
	assert_true(load.can_fit_one(WOOD_RES))
	assert_eq(load.get_max_additional_units(WOOD_RES), 1)
	assert_eq(load.get_max_additional_units(FOOD_RES), 2)


func test_06_negative_amounts_invalid_data_and_weight_consistency() -> void:
	var load := UnitCarryLoad.new(20)
	assert_false(load.add_units(null, 1))
	assert_false(load.add_units(FOOD_RES, 0))
	assert_false(load.add_units(FOOD_RES, -3))
	assert_false(load.add_resource(&"", 1, 1))
	assert_false(load.add_resource(&"wood", 0, 1))
	assert_false(load.add_resource(&"wood", -2, 1))
	assert_eq(load.remove_units(&"food", -2), 0)
	assert_eq(load.remove_units(&"", 1), 0)
	assert_false(load.set_base_capacity(-5))

	var invalid_def := ResourceDefinition.new()
	invalid_def.resource_id = &""
	invalid_def.unit_weight = 2
	assert_false(invalid_def.is_valid())
	assert_false(load.add_units(invalid_def, 1))

	# Weight inconsistency guard for same resource_id
	assert_true(load.add_units(WOOD_RES, 2)) # wood weight = 2
	assert_false(load.add_resource(&"wood", 5, 1), "Mismatched unit_weight for active resource_id must fail")
	assert_eq(load.get_max_additional_for(&"wood", 5), 0)
	assert_eq(load.get_amount(&"wood"), 2)


func test_07_capacity_modifiers() -> void:
	var load := UnitCarryLoad.new(20)
	assert_eq(load.get_effective_capacity(), 20)

	assert_true(load.set_capacity_modifier(&"backpack", 10))
	assert_eq(load.get_effective_capacity(), 30)
	assert_true(load.add_units(STONE_RES, 10)) # 30 weight = 100%
	assert_near(load.get_fill_percentage(), 100.0, 0.0001)

	# Negative modifier cannot drop effective capacity below zero
	assert_true(load.set_capacity_modifier(&"exhausted", -50))
	assert_eq(load.get_effective_capacity(), 0)
	assert_true(load.remove_capacity_modifier(&"exhausted"))
	assert_eq(load.get_effective_capacity(), 30)


func test_08_preserve_carried_load_when_capacity_parameters_change() -> void:
	var load := UnitCarryLoad.new(20)
	assert_true(load.set_capacity_modifier(&"cart", 10)) # effective 30
	assert_true(load.add_units(WOOD_RES, 14)) # weight 28

	# Removing modifier or shrinking base capacity must NEVER delete carried items
	assert_true(load.remove_capacity_modifier(&"cart")) # effective 20 while carrying 28
	assert_true(load.is_overloaded(), "Overloaded state must remain observable instead of hidden")
	assert_eq(load.get_amount(&"wood"), 14)
	assert_eq(load.get_current_weight(), 28)
	assert_eq(load.get_remaining_capacity(), 0)
	assert_near(load.get_fill_percentage(), 100.0, 0.0001)
	assert_false(load.can_fit_one(FOOD_RES))

	assert_true(load.set_base_capacity(10))
	assert_true(load.is_overloaded())
	assert_eq(load.get_amount(&"wood"), 14)
	assert_eq(load.get_remaining_capacity(), 0)

	# After unloading enough to get below capacity, additions work again
	assert_eq(load.remove_units(&"wood", 10), 10) # weight 8 / 10
	assert_false(load.is_overloaded())
	assert_eq(load.get_remaining_capacity(), 2)
	assert_true(load.can_fit_one(WOOD_RES))


func test_09_economic_and_character_data_integrity() -> void:
	assert_true(FOOD_RES.is_valid())
	assert_eq(FOOD_RES.resource_id, &"food")
	assert_eq(FOOD_RES.unit_weight, 1)

	assert_true(WOOD_RES.is_valid())
	assert_eq(WOOD_RES.resource_id, &"wood")
	assert_eq(WOOD_RES.unit_weight, 2)

	assert_true(STONE_RES.is_valid())
	assert_eq(STONE_RES.resource_id, &"stone")
	assert_eq(STONE_RES.unit_weight, 3)

	assert_true(LEADER_A_DEF.is_valid())
	assert_true(LEADER_B_DEF.is_valid())
	assert_eq(LEADER_A_DEF.base_carry_capacity, 20)
	assert_eq(LEADER_B_DEF.base_carry_capacity, 20)

	var decay := DecayProfile.new()
	assert_true(decay.is_valid())
	decay.exposure_duration_sec = -1.0
	assert_false(decay.is_valid())


func test_10_settlement_inventory_single_authority_contract() -> void:
	var source := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(source)

	# Starts completely empty (no free resources)
	assert_eq(inventory.get_amount(&"food"), 0)
	assert_eq(inventory.get_amount(&"wood"), 0)
	assert_eq(inventory.get_amount(&"stone"), 0)

	# Changes in underlying source are reflected directly without duplicate balance
	assert_true(source.deposit(&"wood", 12))
	assert_eq(inventory.get_amount(&"wood"), 12)
	assert_true(inventory.has_amount(&"wood", 12))
	assert_false(inventory.has_amount(&"wood", 13))

	# Withdrawals mutate the single source directly and reject negatives/overdraws
	assert_false(inventory.withdraw(&"wood", 15))
	assert_false(inventory.withdraw(&"wood", -2))
	assert_false(inventory.deposit(&"wood", 0))
	assert_true(inventory.withdraw(&"wood", 5))
	assert_eq(source.get_amount(&"wood"), 7)
	assert_eq(inventory.get_amount(&"wood"), 7)


func test_11_conservation_across_sources_carry_loads_and_future_piles() -> void:
	var source_wood_remaining: int = 30
	var storage := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(storage)
	var worker_a := UnitCarryLoad.new(LEADER_A_DEF.base_carry_capacity)
	var worker_b := UnitCarryLoad.new(LEADER_B_DEF.base_carry_capacity)

	# 1. Gathering moves units from source to UnitCarryLoad; inventory stays 0
	var gather_a: int = 10
	source_wood_remaining -= gather_a
	assert_true(worker_a.add_units(WOOD_RES, gather_a))
	assert_eq(inventory.get_amount(&"wood"), 0, "Gathering must never credit SettlementInventory")

	var gather_b: int = 6
	source_wood_remaining -= gather_b
	assert_true(worker_b.add_units(WOOD_RES, gather_b))
	assert_eq(inventory.get_amount(&"wood"), 0)

	# 2. Deliver worker_a to camp storage; worker_b keeps load (e.g., cancelled order)
	var delivered_a: Dictionary = inventory.deliver_from_carry_load(worker_a)
	assert_eq(int(delivered_a.get(&"wood", 0)), 10)
	assert_true(worker_a.is_empty())
	assert_eq(inventory.get_amount(&"wood"), 10)
	assert_eq(worker_b.get_amount(&"wood"), 6)

	# 3. Simulate consumption and intentional deterioration in storage
	var consumed: int = 3
	assert_true(inventory.withdraw(&"wood", consumed))
	var decayed: int = storage.record_intentional_decay(&"wood", 2)
	assert_eq(decayed, 2)
	assert_eq(inventory.get_amount(&"wood"), 5)
	assert_eq(inventory.get_total_decayed(&"wood"), 2)

	# Strict conservation equation: initial(30) == source + loads + stock + consumed + decayed
	var total_accounted: int = (
		source_wood_remaining
		+ worker_a.get_amount(&"wood")
		+ worker_b.get_amount(&"wood")
		+ inventory.get_amount(&"wood")
		+ consumed
		+ inventory.get_total_decayed(&"wood")
	)
	assert_eq(total_accounted, 30)


class RejectingStorageSource:
	extends SettlementStorageSource

	func can_deposit_batch(_amounts: Dictionary) -> bool:
		return false


class PartialRejectingStorageSource:
	extends InMemoryStorageSource

	var rejected_resource_id: StringName = &"stone"

	func deposit(resource_id: StringName, amount: int) -> bool:
		if resource_id == rejected_resource_id:
			return false
		return super.deposit(resource_id, amount)


func test_12_observer_sees_atomic_final_state_across_all_signals() -> void:
	var storage := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(storage)
	var load := UnitCarryLoad.new(20)
	assert_true(load.add_units(WOOD_RES, 4))
	assert_true(load.add_units(FOOD_RES, 5))

	var snapshots: Array = []
	_observer_ctx = {
		"inventory": inventory,
		"load": load,
		"snapshots": snapshots,
	}

	storage.storage_changed.connect(_on_record_atomic_snapshot.bind("storage_changed"))
	inventory.inventory_changed.connect(_on_record_atomic_snapshot.bind("inventory_changed"))
	load.load_changed.connect(_on_record_atomic_snapshot.bind("load_changed"))

	var delivered: Dictionary = inventory.deliver_from_carry_load(load)
	assert_eq(int(delivered.get(&"wood", 0)), 4)
	assert_eq(int(delivered.get(&"food", 0)), 5)

	# Exactly one notification per object even with two categories delivered
	assert_eq(snapshots.size(), 3)
	for entry_var: Variant in snapshots:
		var entry: Dictionary = entry_var as Dictionary
		assert_true(bool(entry["load_empty"]), "Observer '%s' saw non-empty intermediate carry load" % entry["signal"])
		assert_eq(int(entry["inv_wood"]), 4, "Observer '%s' saw partial wood in inventory" % entry["signal"])
		assert_eq(int(entry["inv_food"]), 5, "Observer '%s' saw partial food in inventory" % entry["signal"])
		assert_eq(int(entry["load_wood"]), 0)
		assert_eq(int(entry["load_food"]), 0)
		assert_eq(int(entry["total_wood"]), 4, "Conservation violated during '%s'" % entry["signal"])
		assert_eq(int(entry["total_food"]), 5, "Conservation violated during '%s'" % entry["signal"])


func test_13_reentrant_delivery_inside_signal_callback_cannot_duplicate() -> void:
	var storage := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(storage)
	var worker_a := UnitCarryLoad.new(20)
	var worker_b := UnitCarryLoad.new(20)
	assert_true(worker_a.add_units(WOOD_RES, 6))
	assert_true(worker_b.add_units(FOOD_RES, 3))

	var reentrant_results: Array = []
	_observer_ctx = {
		"inventory": inventory,
		"worker_a": worker_a,
		"worker_b": worker_b,
		"results": reentrant_results,
	}
	inventory.inventory_changed.connect(_on_attempt_reentrant_delivery)
	worker_a.load_changed.connect(_on_attempt_reentrant_delivery)

	var delivered: Dictionary = inventory.deliver_from_carry_load(worker_a)
	assert_eq(int(delivered.get(&"wood", 0)), 6)
	assert_eq(inventory.get_amount(&"wood"), 6)
	assert_eq(inventory.get_amount(&"food"), 0, "Reentrant delivery of another load during callback must be blocked")
	assert_true(worker_a.is_empty())
	assert_eq(worker_b.get_amount(&"food"), 3)
	assert_eq(reentrant_results.size(), 4)
	for res_var: Variant in reentrant_results:
		var res: Dictionary = res_var as Dictionary
		assert_true(res.is_empty(), "All reentrant delivery calls must return empty Dictionary")

	# Normal delivery of worker_b succeeds after transaction completes
	var delivered_b: Dictionary = inventory.deliver_from_carry_load(worker_b)
	assert_eq(int(delivered_b.get(&"food", 0)), 3)
	assert_eq(inventory.get_amount(&"food"), 3)
	assert_true(worker_b.is_empty())


func test_14_rejected_delivery_preserves_load_and_emits_no_signals() -> void:
	var rejecting := RejectingStorageSource.new()
	var inv_rejected := SettlementInventory.new(rejecting)
	var load_a := UnitCarryLoad.new(20)
	assert_true(load_a.add_units(WOOD_RES, 4))
	assert_true(load_a.add_units(FOOD_RES, 2))

	_observer_ctx = {"count_a": 0, "count_b": 0}
	inv_rejected.inventory_changed.connect(_on_increment_counter.bind("count_a"))
	load_a.load_changed.connect(_on_increment_counter.bind("count_a"))

	var delivered_a: Dictionary = inv_rejected.deliver_from_carry_load(load_a)
	assert_true(delivered_a.is_empty())
	assert_eq(int(_observer_ctx["count_a"]), 0, "Rejected delivery must not emit any signals")
	assert_eq(load_a.get_amount(&"wood"), 4)
	assert_eq(load_a.get_amount(&"food"), 2)
	assert_eq(load_a.get_current_weight(), 10)
	assert_eq(inv_rejected.get_amount(&"wood"), 0)

	# Mid-batch rejection (wood succeeds individually, stone rejects) must roll back wood cleanly
	var partial_reject := PartialRejectingStorageSource.new()
	var inv_partial := SettlementInventory.new(partial_reject)
	var load_b := UnitCarryLoad.new(20)
	assert_true(load_b.add_units(WOOD_RES, 3))
	assert_true(load_b.add_units(STONE_RES, 2))

	partial_reject.storage_changed.connect(_on_increment_counter.bind("count_b"))
	inv_partial.inventory_changed.connect(_on_increment_counter.bind("count_b"))
	load_b.load_changed.connect(_on_increment_counter.bind("count_b"))

	var delivered_b: Dictionary = inv_partial.deliver_from_carry_load(load_b)
	assert_true(delivered_b.is_empty())
	assert_eq(int(_observer_ctx["count_b"]), 0, "Rolled-back partial batch must emit zero signals")
	assert_eq(partial_reject.get_amount(&"wood"), 0, "Rolled-back batch must leave zero partial wood in storage")
	assert_eq(partial_reject.get_amount(&"stone"), 0)
	assert_eq(load_b.get_amount(&"wood"), 3, "Rolled-back batch must preserve wood in carry load")
	assert_eq(load_b.get_amount(&"stone"), 2, "Rolled-back batch must preserve stone in carry load")
	assert_true(load_b.add_units(WOOD_RES, 1), "Weight registry must remain intact after rollback")


func test_15_repeated_delivery_after_emptying_does_not_duplicate() -> void:
	var storage := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(storage)
	var load := UnitCarryLoad.new(20)
	assert_true(load.add_units(STONE_RES, 4))

	_observer_ctx = {"inv_signals": 0}
	inventory.inventory_changed.connect(_on_increment_counter.bind("inv_signals"))

	var first: Dictionary = inventory.deliver_from_carry_load(load)
	assert_eq(int(first.get(&"stone", 0)), 4)
	assert_eq(int(_observer_ctx["inv_signals"]), 1)

	var second: Dictionary = inventory.deliver_from_carry_load(load)
	assert_true(second.is_empty())
	assert_eq(int(_observer_ctx["inv_signals"]), 1)
	assert_eq(inventory.get_amount(&"stone"), 4)
	assert_true(load.is_empty())


func test_16_delivered_report_matches_removed_and_conservation_across_transfers() -> void:
	var source_food: int = 25
	var source_wood: int = 18
	var source_stone: int = 12

	var storage := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(storage)
	var load := UnitCarryLoad.new(20)

	source_food -= 4
	source_wood -= 5
	assert_true(load.add_units(FOOD_RES, 4))
	assert_true(load.add_units(WOOD_RES, 5))

	var expected_before: Dictionary = load.get_all_amounts()
	var delivered_1: Dictionary = inventory.deliver_from_carry_load(load)
	assert_eq(delivered_1, expected_before)

	# Second mixed load including stone
	source_stone -= 4
	source_wood -= 4
	assert_true(load.add_units(STONE_RES, 4))
	assert_true(load.add_units(WOOD_RES, 4))

	var expected_second: Dictionary = load.get_all_amounts()
	var delivered_2: Dictionary = inventory.deliver_from_carry_load(load)
	assert_eq(delivered_2, expected_second)

	assert_eq(source_food + load.get_amount(&"food") + inventory.get_amount(&"food"), 25)
	assert_eq(source_wood + load.get_amount(&"wood") + inventory.get_amount(&"wood"), 18)
	assert_eq(source_stone + load.get_amount(&"stone") + inventory.get_amount(&"stone"), 12)


func test_17_overloaded_carry_load_delivers_atomically_without_loss() -> void:
	var storage := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(storage)
	var load := UnitCarryLoad.new(20)
	assert_true(load.set_capacity_modifier(&"pack", 10))
	assert_true(load.add_units(WOOD_RES, 12)) # 24 weight
	assert_true(load.remove_capacity_modifier(&"pack")) # effective 20 < 24

	assert_true(load.is_overloaded())
	assert_eq(load.get_current_weight(), 24)

	var delivered: Dictionary = inventory.deliver_from_carry_load(load)
	assert_eq(int(delivered.get(&"wood", 0)), 12)
	assert_eq(inventory.get_amount(&"wood"), 12)
	assert_false(load.is_overloaded())
	assert_true(load.is_empty())
