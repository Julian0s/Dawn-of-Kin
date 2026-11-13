extends TestCase
## Unit tests for T2.1: CampStorageZone, GroundResourcePile, GroundPileManager,
## SimulatedWorldTimeProvider, atomic staging/commit with failure rollback,
## single-authority SettlementInventory integration, and centralized decay.

const FOOD_BASE: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_BASE: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_BASE: ResourceDefinition = preload("res://data/resources/stone.tres")

var _observer_ctx: Dictionary = {}
var _managers_to_cleanup: Array[GroundPileManager] = []


func after_each() -> void:
	for manager: GroundPileManager in _managers_to_cleanup:
		if manager != null:
			manager.cleanup()
	_managers_to_cleanup.clear()
	_observer_ctx.clear()


func _make_def_with_decay(
	base: ResourceDefinition,
	can_decay: bool,
	exposure_duration_sec: float,
	gradual_interval_sec: float,
	mode: DecayProfile.DecayMode
) -> ResourceDefinition:
	var def: ResourceDefinition = base.duplicate() as ResourceDefinition
	var profile: DecayProfile = DecayProfile.new()
	profile.can_decay = can_decay
	profile.exposure_duration_sec = exposure_duration_sec
	profile.gradual_unit_interval_sec = gradual_interval_sec
	profile.decay_mode = mode
	def.decay_profile = profile
	return def


func _make_fixture(
	max_pile_amount: int = 0,
	zone_half_extents: Vector2 = Vector2(2.5, 2.5),
	slot_spacing: float = 1.2,
	decay_multiplier: float = 1.0,
	defs_override: Dictionary = {}
) -> Dictionary:
	var host := Node3D.new()
	add_test_child(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"test_camp"
	zone.zone_bounds_half_extents = zone_half_extents
	zone.slot_spacing = slot_spacing
	zone.min_pile_clearance = 0.85
	zone.max_pile_amount = max_pile_amount
	zone.decay_multiplier = decay_multiplier
	host.add_child(zone)

	var piles_root := Node3D.new()
	piles_root.name = "PilesRoot"
	host.add_child(piles_root)

	var defs: Dictionary = defs_override if not defs_override.is_empty() else {
		&"wood": WOOD_BASE.duplicate(),
		&"stone": STONE_BASE.duplicate(),
		&"food": FOOD_BASE.duplicate(),
	}
	var time_provider := SimulatedWorldTimeProvider.new(0.0)
	var manager := GroundPileManager.new(defs, zone, piles_root, time_provider)
	_managers_to_cleanup.append(manager)
	var inventory := SettlementInventory.new(manager)

	return {
		"host": host,
		"zone": zone,
		"piles_root": piles_root,
		"defs": defs,
		"time": time_provider,
		"manager": manager,
		"inventory": inventory,
	}


func _on_count_signal(key: String) -> void:
	_observer_ctx[key] = int(_observer_ctx.get(key, 0)) + 1


func _on_attempt_reentrant_ops() -> void:
	var manager: GroundPileManager = _observer_ctx["manager"] as GroundPileManager
	var inventory: SettlementInventory = _observer_ctx["inventory"] as SettlementInventory
	var extra_load: UnitCarryLoad = _observer_ctx["extra_load"] as UnitCarryLoad
	var results: Array = _observer_ctx["results"] as Array
	results.append(manager.deposit(&"wood", 1))
	results.append(manager.withdraw(&"wood", 1))
	results.append(inventory.deliver_from_carry_load(extra_load))
	var decay_res: Dictionary = manager.step_decay()
	results.append(decay_res.is_empty())


func _inject_fail_on_second_pile(
	p_pile_id: int,
	p_definition: ResourceDefinition,
	p_amount: int,
	p_local_pos: Vector3
) -> GroundResourcePile:
	var calls: int = int(_observer_ctx.get("creator_calls", 0)) + 1
	_observer_ctx["creator_calls"] = calls
	if calls >= 2:
		return null
	var pile := GroundResourcePile.new()
	pile.configure_initial(p_pile_id, p_definition, p_amount, p_local_pos)
	return pile


func test_01_create_valid_piles_for_wood_stone_food_and_check_placeholders() -> void:
	var fx: Dictionary = _make_fixture(0, Vector2(3.0, 3.0), 1.2)
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory

	assert_true(manager.deposit_batch({&"wood": 4, &"stone": 8, &"food": 18}))
	assert_eq(manager.get_piles().size(), 3)
	assert_eq(inventory.get_amount(&"wood"), 4)
	assert_eq(inventory.get_amount(&"stone"), 8)
	assert_eq(inventory.get_amount(&"food"), 18)

	var seen_ids: Array[StringName] = []
	for pile: GroundResourcePile in manager.get_piles():
		assert_true(pile.is_valid())
		assert_false(pile.is_processing(), "GroundResourcePile must disable _process")
		assert_false(pile.is_physics_processing(), "GroundResourcePile must disable _physics_process")
		seen_ids.append(pile.resource_id)
		var visual_root: Node = pile.get_node_or_null("VisualRoot")
		assert_not_null(visual_root)
		for child: Node in visual_root.get_children():
			assert_true(child is MeshInstance3D)
			var mi: MeshInstance3D = child as MeshInstance3D
			assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	assert_true(seen_ids.has(&"wood"))
	assert_true(seen_ids.has(&"stone"))
	assert_true(seen_ids.has(&"food"))


func test_02_merge_respects_max_pile_amount_and_exposure_age_policy() -> void:
	var food_def: ResourceDefinition = _make_def_with_decay(
		FOOD_BASE, true, 20.0, 0.0, DecayProfile.DecayMode.EXPIRE_ALL
	)
	var fx: Dictionary = _make_fixture(10, Vector2(3.0, 3.0), 1.2, 1.0, {&"food": food_def})
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var time_provider: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider

	assert_true(manager.deposit(&"food", 8))
	time_provider.advance(10.0)
	manager.step_decay()

	var piles_before: Array[GroundResourcePile] = manager.get_piles_for_resource(&"food")
	assert_eq(piles_before.size(), 1)
	assert_near(piles_before[0].elapsed_exposure_sec, 10.0, 0.001)

	# Adding 5 splits cleanly: 2 merge into pile 1 (max=10), 3 create pile 2.
	# Under WEIGHTED_AVERAGE, pile 1 becomes (8*10 + 2*0)/10 = 8.0s (never reset to 0s).
	assert_true(manager.deposit(&"food", 5))
	var piles_after: Array[GroundResourcePile] = manager.get_piles_for_resource(&"food")
	assert_eq(piles_after.size(), 2)
	assert_eq(piles_after[0].amount, 10)
	assert_near(piles_after[0].elapsed_exposure_sec, 8.0, 0.001)
	assert_eq(piles_after[1].amount, 3)
	assert_near(piles_after[1].elapsed_exposure_sec, 0.0, 0.001)

	# Under KEEP_OLDEST, adding to pile 2 keeps its exact elapsed time untouched.
	time_provider.advance(4.0)
	manager.step_decay()
	var age_before: float = piles_after[1].elapsed_exposure_sec
	manager.merge_exposure_policy = GroundPileManager.MergeExposurePolicy.KEEP_OLDEST
	assert_true(manager.deposit(&"food", 2))
	assert_eq(piles_after[1].amount, 5)
	assert_near(piles_after[1].elapsed_exposure_sec, age_before, 0.001)


func test_03_single_authority_sync_and_multi_pile_withdraw_cleanup() -> void:
	var fx: Dictionary = _make_fixture(5, Vector2(3.0, 3.0), 1.2)
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory

	assert_true(manager.deposit(&"wood", 12)) # 5 + 5 + 2
	assert_eq(manager.get_piles_for_resource(&"wood").size(), 3)
	assert_eq(inventory.get_amount(&"wood"), 12)

	# Withdraw across 2+ piles (5 + 3 = 8 consumed -> 4 remaining across 2 piles: 2 + 2)
	assert_true(inventory.withdraw(&"wood", 8))
	assert_eq(inventory.get_amount(&"wood"), 4)
	assert_eq(manager.get_amount(&"wood"), 4)
	assert_eq(manager.get_piles_for_resource(&"wood").size(), 2)
	var all_amounts: Dictionary = inventory.get_all_amounts()
	assert_eq(int(all_amounts.get(&"wood", 0)), 4)

	# Over-withdraw is rejected cleanly with no partial change
	assert_false(inventory.withdraw(&"wood", 5))
	assert_eq(inventory.get_amount(&"wood"), 4)

	# Exact depletion frees the remaining pile
	assert_true(inventory.withdraw(&"wood", 4))
	assert_eq(inventory.get_amount(&"wood"), 0)
	assert_eq(manager.get_piles().size(), 0)


func test_04_position_validation_rejects_invalid_and_overlapping_positions() -> void:
	var fx: Dictionary = _make_fixture(0, Vector2(2.0, 2.0), 1.2)
	var manager: GroundPileManager = fx["manager"] as GroundPileManager

	# Out of bounds
	assert_null(manager.try_create_pile_at(&"wood", 3, Vector3(3.5, 0.0, 0.0)))
	# Non-finite
	assert_null(manager.try_create_pile_at(&"wood", 3, Vector3(NAN, 0.0, 0.0)))
	assert_null(manager.try_create_pile_at(&"wood", 3, Vector3(INF, 0.0, 0.0)))

	# Valid placement at zone origin
	var p1: GroundResourcePile = manager.try_create_pile_at(&"wood", 3, Vector3(0.0, 0.0, 0.0))
	assert_not_null(p1)

	# Too close / overlapping (< min_pile_clearance 0.85)
	assert_null(manager.try_create_pile_at(&"stone", 3, Vector3(0.4, 0.0, 0.0)))
	# Clear valid distance inside bounds
	var p2: GroundResourcePile = manager.try_create_pile_at(&"stone", 3, Vector3(1.2, 0.0, 0.0))
	assert_not_null(p2)
	assert_eq(manager.get_piles().size(), 2)


func test_05_carry_load_delivery_accepts_or_preserves_load_on_rejection() -> void:
	# Tight zone: slot_spacing 1.2 within half_extents (0.7, 0.7) -> only 1 slot (center 0,0)
	var fx: Dictionary = _make_fixture(0, Vector2(0.7, 0.7), 1.2)
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory

	var worker_load := UnitCarryLoad.new(20)
	assert_true(worker_load.add_units(WOOD_BASE, 2))
	assert_true(worker_load.add_units(STONE_BASE, 2))

	# Batch needs 2 slots (wood + stone), but zone only has 1 slot -> must reject atomically
	var failed_delivery: Dictionary = inventory.deliver_from_carry_load(worker_load)
	assert_true(failed_delivery.is_empty(), "Impossible multi-resource delivery must fail cleanly")
	assert_eq(worker_load.get_amount(&"wood"), 2, "CarryLoad wood must remain intact after rejection")
	assert_eq(worker_load.get_amount(&"stone"), 2, "CarryLoad stone must remain intact after rejection")
	assert_eq(inventory.get_amount(&"wood"), 0)
	assert_eq(inventory.get_amount(&"stone"), 0)
	assert_eq(manager.get_piles().size(), 0)

	# Single-resource delivery fits in the 1 available slot and empties CarryLoad
	var single_load := UnitCarryLoad.new(20)
	assert_true(single_load.add_units(WOOD_BASE, 3))
	var ok_delivery: Dictionary = inventory.deliver_from_carry_load(single_load)
	assert_eq(int(ok_delivery.get(&"wood", 0)), 3)
	assert_true(single_load.is_empty())
	assert_eq(inventory.get_amount(&"wood"), 3)


func test_06_mid_commit_failure_rolls_back_merges_created_piles_and_signals() -> void:
	var wood_def: ResourceDefinition = _make_def_with_decay(
		WOOD_BASE, true, 50.0, 10.0, DecayProfile.DecayMode.GRADUAL_UNITS
	)
	var fx: Dictionary = _make_fixture(
		0, Vector2(3.0, 3.0), 1.2, 1.0,
		{
			&"wood": wood_def,
			&"stone": STONE_BASE.duplicate(),
			&"food": FOOD_BASE.duplicate(),
		}
	)
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_provider: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider

	# Seed an existing wood pile with non-zero elapsed exposure so rollback must restore exact age
	assert_true(manager.deposit(&"wood", 4))
	time_provider.advance(12.0)
	manager.step_decay()
	var existing_wood: GroundResourcePile = manager.get_piles_for_resource(&"wood")[0]
	var saved_elapsed: float = existing_wood.elapsed_exposure_sec
	var saved_accum: float = existing_wood.decay_accumulator_sec
	assert_near(saved_elapsed, 12.0, 0.001)

	# Connect signal counters AFTER initial seed
	_observer_ctx["signal_count"] = 0
	manager.storage_changed.connect(Callable(self, "_on_count_signal").bind("signal_count"))

	# Inject failure on 2nd new pile creation during multi-resource delivery (merges wood + creates food, fails stone)
	manager.pile_creator_override = Callable(self, "_inject_fail_on_second_pile")

	var load := UnitCarryLoad.new(30)
	assert_true(load.add_units(WOOD_BASE, 2))
	assert_true(load.add_units(FOOD_BASE, 3))
	assert_true(load.add_units(STONE_BASE, 1))

	var delivered: Dictionary = inventory.deliver_from_carry_load(load)
	assert_true(delivered.is_empty(), "Injected mid-commit failure must abort entire batch")
	assert_eq(int(_observer_ctx.get("creator_calls", 0)), 2)
	assert_eq(int(_observer_ctx.get("signal_count", 0)), 0, "Aborted commit must emit zero signals")

	# CarryLoad intact
	assert_eq(load.get_amount(&"wood"), 2)
	assert_eq(load.get_amount(&"food"), 3)
	assert_eq(load.get_amount(&"stone"), 1)

	# Existing wood pile restored to exact pre-commit state; 1st newly created pile cleaned up
	assert_eq(manager.get_piles().size(), 1)
	assert_eq(existing_wood.amount, 4)
	assert_near(existing_wood.elapsed_exposure_sec, saved_elapsed, 0.0001)
	assert_near(existing_wood.decay_accumulator_sec, saved_accum, 0.0001)
	assert_eq(inventory.get_amount(&"wood"), 4)
	assert_eq(inventory.get_amount(&"food"), 0)
	assert_eq(inventory.get_amount(&"stone"), 0)


func test_07_reentrancy_blocked_during_delivery_and_decay_notifications() -> void:
	var food_def: ResourceDefinition = _make_def_with_decay(
		FOOD_BASE, true, 5.0, 0.0, DecayProfile.DecayMode.EXPIRE_ALL
	)
	var fx: Dictionary = _make_fixture(0, Vector2(3.0, 3.0), 1.2, 1.0, {
		&"food": food_def,
		&"wood": WOOD_BASE.duplicate(),
	})
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_provider: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider

	var extra_load := UnitCarryLoad.new(10)
	assert_true(extra_load.add_units(WOOD_BASE, 2))
	var results: Array = []

	_observer_ctx["manager"] = manager
	_observer_ctx["inventory"] = inventory
	_observer_ctx["extra_load"] = extra_load
	_observer_ctx["results"] = results
	inventory.inventory_changed.connect(Callable(self, "_on_attempt_reentrant_ops"))

	# During delivery callback, deposit/withdraw/deliver return false and step_decay returns empty
	var first_load := UnitCarryLoad.new(10)
	assert_true(first_load.add_units(FOOD_BASE, 5))
	var res: Dictionary = inventory.deliver_from_carry_load(first_load)
	assert_eq(int(res.get(&"food", 0)), 5)
	assert_eq(results.size(), 4)
	assert_false(results[0] as bool)
	assert_false(results[1] as bool)
	assert_true((results[2] as Dictionary).is_empty())
	assert_true(results[3] as bool)
	assert_eq(extra_load.get_amount(&"wood"), 2)

	# During decay callback, reentrant mutations/step_decay are also blocked
	results.clear()
	time_provider.advance(6.0)
	var losses: Dictionary = manager.step_decay()
	assert_eq(int(losses.get(&"food", 0)), 5)
	assert_eq(results.size(), 4)
	assert_false(results[0] as bool)
	assert_false(results[1] as bool)
	assert_true((results[2] as Dictionary).is_empty())
	assert_true(results[3] as bool)


func test_08_gradual_decay_and_audit_counter_with_simulated_pause() -> void:
	var food_def: ResourceDefinition = _make_def_with_decay(
		FOOD_BASE, true, 10.0, 2.0, DecayProfile.DecayMode.GRADUAL_UNITS
	)
	var fx: Dictionary = _make_fixture(0, Vector2(3.0, 3.0), 1.2, 1.0, {&"food": food_def})
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_provider: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider

	assert_true(manager.deposit(&"food", 4))

	# Grace period = 10s: advancing 9s loses 0 units
	time_provider.advance(9.0)
	assert_true(manager.step_decay().is_empty())
	assert_eq(inventory.get_amount(&"food"), 4)

	# Paused time advance does nothing
	time_provider.set_paused(true)
	time_provider.advance(20.0)
	assert_true(manager.step_decay().is_empty())
	assert_eq(inventory.get_amount(&"food"), 4)
	time_provider.set_paused(false)

	# +5s puts elapsed = 14.0 -> 4.0s past grace -> 4.0 / 2.0 = 2 units lost
	time_provider.advance(5.0)
	var step1: Dictionary = manager.step_decay()
	assert_eq(int(step1.get(&"food", 0)), 2)
	assert_eq(inventory.get_amount(&"food"), 2)
	assert_eq(inventory.get_total_decayed(&"food"), 2)

	# +4s loses remaining 2 units and deletes pile automatically
	time_provider.advance(4.0)
	var step2: Dictionary = manager.step_decay()
	assert_eq(int(step2.get(&"food", 0)), 2)
	assert_eq(inventory.get_amount(&"food"), 0)
	assert_eq(manager.get_piles().size(), 0)
	assert_eq(inventory.get_total_decayed(&"food"), 4)
	assert_eq(int(inventory.get_all_decayed().get(&"food", 0)), 4)


func test_09_expire_all_and_protected_storage_preserve_invariants() -> void:
	var food_def: ResourceDefinition = _make_def_with_decay(
		FOOD_BASE, true, 15.0, 0.0, DecayProfile.DecayMode.EXPIRE_ALL
	)
	var stone_def: ResourceDefinition = _make_def_with_decay(
		STONE_BASE, false, 5.0, 1.0, DecayProfile.DecayMode.GRADUAL_UNITS
	)
	var fx: Dictionary = _make_fixture(0, Vector2(3.0, 3.0), 1.2, 1.0, {
		&"food": food_def,
		&"stone": stone_def,
	})
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var time_provider: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider

	assert_true(manager.deposit_batch({&"food": 6, &"stone": 5}))

	# Protected zone (decay_multiplier = 0.0 simulation for T3 warehouse) prevents all decay
	zone.decay_multiplier = 0.0
	time_provider.advance(100.0)
	assert_true(manager.step_decay().is_empty())
	assert_eq(inventory.get_amount(&"food"), 6)
	assert_eq(inventory.get_amount(&"stone"), 5)

	# Re-expose zone: food expires all at once when elapsed >= 15s; stone (can_decay=false) stays intact
	zone.decay_multiplier = 1.0
	time_provider.advance(15.0)
	var losses: Dictionary = manager.step_decay()
	assert_eq(int(losses.get(&"food", 0)), 6)
	assert_eq(int(losses.get(&"stone", 0)), 0)
	assert_eq(inventory.get_amount(&"food"), 0)
	assert_eq(inventory.get_amount(&"stone"), 5)
	assert_eq(inventory.get_total_decayed(&"food"), 6)
	assert_eq(inventory.get_total_decayed(&"stone"), 0)
