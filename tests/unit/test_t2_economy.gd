extends TestCase
## Unit tests for T2.0 economic data contracts, UnitCarryLoad, DecayProfile,
## CharacterDefinition carry capacity, SettlementInventory single-authority contract,
## and end-to-end conservation invariants.

const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const LEADER_B_DEF: CharacterDefinition = preload("res://data/characters/leader_b.tres")


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
	assert_eq(load.get_amount(&"wood"), 14)
	assert_eq(load.get_current_weight(), 28)
	assert_eq(load.get_remaining_capacity(), 0)
	assert_near(load.get_fill_percentage(), 100.0, 0.0001)
	assert_false(load.can_fit_one(FOOD_RES))

	assert_true(load.set_base_capacity(10))
	assert_eq(load.get_amount(&"wood"), 14)
	assert_eq(load.get_remaining_capacity(), 0)

	# After unloading enough to get below capacity, additions work again
	assert_eq(load.remove_units(&"wood", 10), 10) # weight 8 / 10
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
