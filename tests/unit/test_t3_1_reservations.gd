extends TestCase
## Unit tests for T3.1: reservation accounting, atomic batch withdrawals,
## Alternative B direct decay on reservations, and T2 flow compatibility.

const FOOD_BASE: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_BASE: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_BASE: ResourceDefinition = preload("res://data/resources/stone.tres")

var _managers_to_cleanup: Array[GroundPileManager] = []
var _observer_ctx: Dictionary = {}


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
	defs_override: Dictionary = {}
) -> Dictionary:
	var host := Node3D.new()
	add_test_child(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"test_camp"
	zone.zone_bounds_half_extents = Vector2(3.5, 3.5)
	zone.slot_spacing = 1.2
	zone.min_pile_clearance = 0.85
	zone.max_pile_amount = max_pile_amount
	zone.decay_multiplier = 1.0
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


func _assert_pile_invariants(manager: GroundPileManager) -> void:
	for pile: GroundResourcePile in manager.get_piles():
		var res_on_pile: int = manager.get_pile_reserved_amount(pile.pile_id)
		var avail_on_pile: int = manager.get_pile_available_amount(pile.pile_id)
		assert_true(res_on_pile >= 0)
		assert_true(avail_on_pile >= 0)
		assert_true(res_on_pile <= pile.amount, "Reserved on pile must never exceed physical pile amount")
		assert_eq(res_on_pile + avail_on_pile, pile.amount)

	for res_id: StringName in [&"wood", &"stone", &"food", &"iron"]:
		var phys: int = manager.get_physical_amount(res_id)
		var resv: int = manager.get_reserved_amount(res_id)
		var free: int = manager.get_available_amount(res_id)
		assert_eq(free, manager.get_amount(res_id))
		assert_eq(free + resv, phys, "Invariant: free + reserved == physical")


func _on_count_signal(key: String) -> void:
	_observer_ctx[key] = int(_observer_ctx.get(key, 0)) + 1


func _on_record_decay_loss(
	reservation_id: StringName,
	resource_id: StringName,
	lost_amount: int
) -> void:
	var events: Array = _observer_ctx.get("decay_losses", []) as Array
	events.append({
		"reservation_id": reservation_id,
		"resource_id": resource_id,
		"lost_amount": lost_amount,
	})
	_observer_ctx["decay_losses"] = events


func _on_attempt_reentrant_reservation() -> void:
	var inv: SettlementInventory = _observer_ctx["inventory"] as SettlementInventory
	var results: Array = _observer_ctx["results"] as Array
	results.append(inv.reserve_batch(&"reentrant_site", {&"wood": 1}))
	results.append(inv.release_batch(&"site_a"))
	results.append(inv.withdraw_reserved(&"site_a", &"wood", 1))
	results.append(inv.withdraw_batch({&"wood": 1}))


class FailingSecondWithdrawManager:
	extends GroundPileManager

	var fail_on_entry_index: int = 2
	var _attempt_count: int = 0

	func _commit_withdraw_entry(
		entry: Dictionary,
		deduct_reservation_id: StringName
	) -> bool:
		_attempt_count += 1
		if _attempt_count == fail_on_entry_index:
			return false
		return super._commit_withdraw_entry(entry, deduct_reservation_id)


class FailingSecondInMemorySource:
	extends InMemoryStorageSource

	var fail_resource: StringName = &"stone"

	func withdraw(resource_id: StringName, amount: int) -> bool:
		if resource_id == fail_resource:
			return false
		return super.withdraw(resource_id, amount)


func test_01_simple_reservation_and_balance_breakdown() -> void:
	var fix: Dictionary = _make_fixture()
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory

	assert_true(inv.deposit(&"wood", 15))
	assert_eq(inv.get_physical_amount(&"wood"), 15)
	assert_eq(inv.get_reserved_amount(&"wood"), 0)
	assert_eq(inv.get_available_amount(&"wood"), 15)

	assert_true(inv.reserve_batch(&"site_shelter_1", {&"wood": 6}))
	assert_true(inv.has_reservation(&"site_shelter_1"))
	assert_eq(inv.get_physical_amount(&"wood"), 15)
	assert_eq(inv.get_reserved_amount(&"wood"), 6)
	assert_eq(inv.get_available_amount(&"wood"), 9)
	assert_eq(inv.get_amount(&"wood"), 9)
	assert_eq(inv.get_reservation_amount(&"site_shelter_1", &"wood"), 6)
	assert_eq(inv.get_reservation_amounts(&"site_shelter_1"), {&"wood": 6})
	_assert_pile_invariants(manager)


func test_02_composite_reservation_and_extensible_categories() -> void:
	var iron_def: ResourceDefinition = WOOD_BASE.duplicate() as ResourceDefinition
	iron_def.resource_id = &"iron"
	iron_def.display_name = "Iron"
	iron_def.unit_weight = 4

	var defs: Dictionary = {
		&"wood": WOOD_BASE.duplicate(),
		&"stone": STONE_BASE.duplicate(),
		&"food": FOOD_BASE.duplicate(),
		&"iron": iron_def,
	}
	var fix: Dictionary = _make_fixture(0, defs)
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory

	assert_true(manager.deposit_batch({&"wood": 14, &"stone": 8, &"iron": 5}))
	assert_true(inv.reserve_batch(&"site_forge_1", {&"wood": 12, &"stone": 6, &"iron": 3}))

	assert_eq(inv.get_physical_amount(&"wood"), 14)
	assert_eq(inv.get_reserved_amount(&"wood"), 12)
	assert_eq(inv.get_available_amount(&"wood"), 2)

	assert_eq(inv.get_physical_amount(&"stone"), 8)
	assert_eq(inv.get_reserved_amount(&"stone"), 6)
	assert_eq(inv.get_available_amount(&"stone"), 2)

	assert_eq(inv.get_physical_amount(&"iron"), 5)
	assert_eq(inv.get_reserved_amount(&"iron"), 3)
	assert_eq(inv.get_available_amount(&"iron"), 2)
	assert_eq(inv.get_reservation_amounts(&"site_forge_1"), {&"wood": 12, &"stone": 6, &"iron": 3})
	_assert_pile_invariants(manager)


func test_03_concurrent_reservations_across_multiple_sites() -> void:
	var fix: Dictionary = _make_fixture()
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory

	assert_true(manager.deposit_batch({&"wood": 20, &"stone": 12}))
	assert_true(inv.reserve_batch(&"site_a", {&"wood": 12, &"stone": 6}))
	assert_true(inv.reserve_batch(&"site_b", {&"wood": 8, &"stone": 5}))

	assert_eq(inv.get_physical_amount(&"wood"), 20)
	assert_eq(inv.get_reserved_amount(&"wood"), 20)
	assert_eq(inv.get_available_amount(&"wood"), 0)

	assert_eq(inv.get_physical_amount(&"stone"), 12)
	assert_eq(inv.get_reserved_amount(&"stone"), 11)
	assert_eq(inv.get_available_amount(&"stone"), 1)

	# A third site cannot reserve units already claimed by site_a/site_b
	assert_false(inv.reserve_batch(&"site_c", {&"wood": 1, &"stone": 1}))
	assert_false(inv.has_reservation(&"site_c"))
	assert_eq(inv.get_all_reservation_ids(), [&"site_a", &"site_b"])
	_assert_pile_invariants(manager)


func test_04_reject_insufficient_balance_atomically() -> void:
	var fix: Dictionary = _make_fixture()
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory

	assert_true(manager.deposit_batch({&"wood": 12, &"stone": 5}))
	_observer_ctx = {"inv_signals": 0, "res_signals": 0}
	inv.inventory_changed.connect(_on_count_signal.bind("inv_signals"))
	inv.reservations_changed.connect(_on_count_signal.bind("res_signals"))

	# Stone short by 1 (5 < 6) -> entire composite reservation must abort cleanly
	assert_false(inv.can_reserve_batch(&"site_a", {&"wood": 12, &"stone": 6}))
	assert_false(inv.reserve_batch(&"site_a", {&"wood": 12, &"stone": 6}))
	assert_false(inv.has_reservation(&"site_a"))
	assert_eq(inv.get_reserved_amount(&"wood"), 0)
	assert_eq(inv.get_reserved_amount(&"stone"), 0)
	assert_eq(inv.get_available_amount(&"wood"), 12)
	assert_eq(inv.get_available_amount(&"stone"), 5)
	assert_eq(int(_observer_ctx["inv_signals"]), 0)
	assert_eq(int(_observer_ctx["res_signals"]), 0)
	_assert_pile_invariants(manager)


func test_05_partial_and_full_reservation_release() -> void:
	var fix: Dictionary = _make_fixture()
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory

	assert_true(manager.deposit_batch({&"wood": 12, &"stone": 6}))
	assert_true(inv.reserve_batch(&"site_a", {&"wood": 10, &"stone": 4}))

	# Invalid partial over-release must abort atomically
	assert_false(inv.release_batch(&"site_a", {&"wood": 5, &"stone": 9}))
	assert_eq(inv.get_reservation_amounts(&"site_a"), {&"wood": 10, &"stone": 4})

	# Valid partial release
	assert_true(inv.release_batch(&"site_a", {&"wood": 4, &"stone": 4}))
	assert_true(inv.has_reservation(&"site_a"))
	assert_eq(inv.get_reservation_amounts(&"site_a"), {&"wood": 6})
	assert_eq(inv.get_physical_amount(&"wood"), 12)
	assert_eq(inv.get_reserved_amount(&"wood"), 6)
	assert_eq(inv.get_available_amount(&"wood"), 6)
	assert_eq(inv.get_reserved_amount(&"stone"), 0)
	assert_eq(inv.get_available_amount(&"stone"), 6)

	# Full release clears remaining amounts
	assert_true(inv.release_batch(&"site_a"))
	assert_false(inv.has_reservation(&"site_a"))
	assert_eq(inv.get_reserved_amount(&"wood"), 0)
	assert_eq(inv.get_available_amount(&"wood"), 12)
	_assert_pile_invariants(manager)


func test_06_withdraw_reserved_from_real_piles() -> void:
	var fix: Dictionary = _make_fixture(8)
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory

	# Creates two physical wood piles (8 + 4 = 12)
	assert_true(inv.deposit(&"wood", 12))
	assert_eq(manager.get_piles_for_resource(&"wood").size(), 2)
	assert_true(inv.reserve_batch(&"site_a", {&"wood": 10}))
	assert_eq(inv.get_available_amount(&"wood"), 2)

	# Owner can withdraw against its reservation without touching unreserved free balance (2)
	assert_true(inv.withdraw_reserved(&"site_a", &"wood", 6))
	assert_eq(inv.get_physical_amount(&"wood"), 6)
	assert_eq(inv.get_reserved_amount(&"wood"), 4)
	assert_eq(inv.get_available_amount(&"wood"), 2)

	# Cannot withdraw more than remaining reserved or using wrong ID
	assert_false(inv.withdraw_reserved(&"site_a", &"wood", 5))
	assert_false(inv.withdraw_reserved(&"site_other", &"wood", 1))

	# Withdraw remaining reserved units; free balance of 2 stays untouched
	assert_true(inv.withdraw_reserved(&"site_a", &"wood", 4))
	assert_false(inv.has_reservation(&"site_a"))
	assert_eq(inv.get_physical_amount(&"wood"), 2)
	assert_eq(inv.get_reserved_amount(&"wood"), 0)
	assert_eq(inv.get_available_amount(&"wood"), 2)
	assert_eq(manager.get_piles_for_resource(&"wood").size(), 1)
	_assert_pile_invariants(manager)


func test_07_common_withdraw_cannot_consume_reserved_quantities() -> void:
	var fix: Dictionary = _make_fixture()
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory

	assert_true(inv.deposit(&"wood", 10))
	assert_true(inv.reserve_batch(&"site_a", {&"wood": 8}))
	assert_eq(inv.get_available_amount(&"wood"), 2)

	# Common withdraw exceeding free balance (3 > 2) must fail despite 10 physical existing
	assert_false(inv.withdraw(&"wood", 3))
	assert_eq(inv.get_physical_amount(&"wood"), 10)
	assert_eq(inv.get_reserved_amount(&"wood"), 8)

	# Consuming exactly free balance (2) succeeds and leaves all 8 reserved intact
	assert_true(inv.withdraw(&"wood", 2))
	assert_eq(inv.get_physical_amount(&"wood"), 8)
	assert_eq(inv.get_reserved_amount(&"wood"), 8)
	assert_eq(inv.get_available_amount(&"wood"), 0)
	assert_false(inv.withdraw(&"wood", 1))
	_assert_pile_invariants(manager)


func test_08_batch_withdraw_intermediate_failure_rolls_back_atomically() -> void:
	# Part A: Validation abort on 2nd resource in GroundPileManager
	var fix: Dictionary = _make_fixture()
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory
	assert_true(manager.deposit_batch({&"wood": 10, &"stone": 3}))
	assert_false(inv.can_withdraw_batch({&"wood": 4, &"stone": 4}))
	assert_false(inv.withdraw_batch({&"wood": 4, &"stone": 4}))
	assert_eq(inv.get_physical_amount(&"wood"), 10)
	assert_eq(inv.get_physical_amount(&"stone"), 3)

	# Part B: Mid-commit failure injection across piles on FailingSecondWithdrawManager
	var host := fix["host"] as Node3D
	var zone := fix["zone"] as CampStorageZone
	var piles_root := Node3D.new()
	host.add_child(piles_root)
	var fail_mgr := FailingSecondWithdrawManager.new(fix["defs"] as Dictionary, zone, piles_root)
	_managers_to_cleanup.append(fail_mgr)
	assert_true(fail_mgr.deposit_batch({&"wood": 6, &"stone": 5}))
	var signal_ctx := {"count": 0}
	fail_mgr.storage_changed.connect(func() -> void: signal_ctx["count"] = int(signal_ctx["count"]) + 1)

	# Batch will process entry #1 (stone or wood) and abort on entry #2 -> exact rollback
	assert_false(fail_mgr.withdraw_batch({&"wood": 4, &"stone": 3}))
	assert_eq(fail_mgr.get_physical_amount(&"wood"), 6)
	assert_eq(fail_mgr.get_physical_amount(&"stone"), 5)
	assert_eq(int(signal_ctx["count"]), 0, "Failed batch rollback must emit zero signals")
	_assert_pile_invariants(fail_mgr)

	# Part C: Base SettlementStorageSource rollback via FailingSecondInMemorySource
	var mem_src := FailingSecondInMemorySource.new()
	assert_true(mem_src.deposit_batch({&"wood": 6, &"stone": 5}))
	var mem_signals := {"count": 0}
	mem_src.storage_changed.connect(func() -> void: mem_signals["count"] = int(mem_signals["count"]) + 1)
	assert_false(mem_src.withdraw_batch({&"wood": 4, &"stone": 3}))
	assert_eq(mem_src.get_physical_amount(&"wood"), 6)
	assert_eq(mem_src.get_physical_amount(&"stone"), 5)
	assert_eq(int(mem_signals["count"]), 0)


func test_09_decay_on_unreserved_pile_preserves_zero_reservations() -> void:
	var wood_gradual: ResourceDefinition = _make_def_with_decay(
		WOOD_BASE,
		true,
		0.0,
		2.0,
		DecayProfile.DecayMode.GRADUAL_UNITS
	)
	var fix: Dictionary = _make_fixture(0, {&"wood": wood_gradual})
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory
	var time_provider: SimulatedWorldTimeProvider = fix["time"] as SimulatedWorldTimeProvider

	assert_true(inv.deposit(&"wood", 5))
	time_provider.advance(4.0)
	var losses: Dictionary = manager.step_decay()
	assert_eq(int(losses.get(&"wood", 0)), 2)
	assert_eq(inv.get_physical_amount(&"wood"), 3)
	assert_eq(inv.get_reserved_amount(&"wood"), 0)
	assert_eq(inv.get_available_amount(&"wood"), 3)
	assert_eq(inv.get_total_decayed(&"wood"), 2)
	_assert_pile_invariants(manager)


func test_10_alternative_b_direct_decay_loss_without_reanchoring() -> void:
	var wood_gradual: ResourceDefinition = _make_def_with_decay(
		WOOD_BASE,
		true,
		0.0,
		2.0,
		DecayProfile.DecayMode.GRADUAL_UNITS
	)
	var fix: Dictionary = _make_fixture(10, {&"wood": wood_gradual})
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory
	var time_provider: SimulatedWorldTimeProvider = fix["time"] as SimulatedWorldTimeProvider

	# Create Pile 1 (oldest exposure) with 10 wood and Pile 2 (newer) with 10 wood
	assert_true(inv.deposit(&"wood", 10))
	time_provider.advance(1.0)
	# Ensure Pile 1 stays intact long enough for setup? Advance 1s -> 0 lost because interval is 2s.
	assert_true(inv.deposit(&"wood", 10))
	assert_eq(manager.get_piles_for_resource(&"wood").size(), 2)

	# Reserve 7 for site_a (allocated on Pile 1, leaving free=3 on Pile 1, free=10 on Pile 2)
	assert_true(inv.reserve_batch(&"site_a", {&"wood": 7}))
	_observer_ctx = {"decay_losses": []}
	inv.reservation_lost_to_decay.connect(_on_record_decay_loss)

	# Advance +2s (Pile 1 elapsed=3s -> loses 1 unit -> remaining=9; Pile 2 elapsed=2s -> loses 1 -> remaining=9)
	# On Pile 1: reserved(7) <= remaining(9), so unreserved free absorbs loss cleanly (site_a stays 7!)
	time_provider.advance(2.0)
	manager.step_decay()
	assert_eq(inv.get_reservation_amount(&"site_a", &"wood"), 7)
	assert_eq((_observer_ctx["decay_losses"] as Array).size(), 0)

	# Advance +6s (Pile 1 loses 3 more -> remaining=6; Pile 2 loses 3 more -> remaining=6)
	# Alternative B: Pile 1 has 6 physical < 7 reserved -> site_a drops directly from 7 to 6!
	# MUST NOT re-anchor that 1 missing unit onto Pile 2 even though Pile 2 has 6 free units!
	time_provider.advance(6.0)
	manager.step_decay()
	assert_eq(inv.get_physical_amount(&"wood"), 12)
	assert_eq(inv.get_reserved_amount(&"wood"), 6)
	assert_eq(inv.get_reservation_amount(&"site_a", &"wood"), 6)
	assert_eq(inv.get_available_amount(&"wood"), 6)
	assert_eq(inv.get_total_decayed(&"wood"), 8)
	assert_eq((_observer_ctx["decay_losses"] as Array).size(), 1)
	var ev: Dictionary = (_observer_ctx["decay_losses"] as Array)[0] as Dictionary
	assert_eq(ev["reservation_id"], &"site_a")
	assert_eq(ev["resource_id"], &"wood")
	assert_eq(ev["lost_amount"], 1)
	_assert_pile_invariants(manager)


func test_10b_deterministic_trimming_when_multiple_sites_share_decayed_pile() -> void:
	var wood_gradual: ResourceDefinition = _make_def_with_decay(
		WOOD_BASE,
		true,
		0.0,
		1.0,
		DecayProfile.DecayMode.GRADUAL_UNITS
	)
	var fix: Dictionary = _make_fixture(0, {&"wood": wood_gradual})
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory
	var time_provider: SimulatedWorldTimeProvider = fix["time"] as SimulatedWorldTimeProvider

	assert_true(inv.deposit(&"wood", 10))
	assert_true(inv.reserve_batch(&"site_first", {&"wood": 5}))
	assert_true(inv.reserve_batch(&"site_second", {&"wood": 5}))

	# Lose 3 units -> remaining 7 -> newest reservation (site_second) trimmed by 3 to 2; site_first keeps 5
	time_provider.advance(3.0)
	manager.step_decay()
	assert_eq(inv.get_physical_amount(&"wood"), 7)
	assert_eq(inv.get_reservation_amount(&"site_first", &"wood"), 5)
	assert_eq(inv.get_reservation_amount(&"site_second", &"wood"), 2)
	assert_eq(inv.get_reserved_amount(&"wood"), 7)
	assert_eq(inv.get_available_amount(&"wood"), 0)
	_assert_pile_invariants(manager)


func test_11_reserved_pile_reaches_zero_and_is_removed_on_decay() -> void:
	var food_expire: ResourceDefinition = _make_def_with_decay(
		FOOD_BASE,
		true,
		5.0,
		0.0,
		DecayProfile.DecayMode.EXPIRE_ALL
	)
	var fix: Dictionary = _make_fixture(0, {&"food": food_expire})
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory
	var time_provider: SimulatedWorldTimeProvider = fix["time"] as SimulatedWorldTimeProvider

	assert_true(inv.deposit(&"food", 8))
	assert_true(inv.reserve_batch(&"site_rations", {&"food": 8}))
	_observer_ctx = {"decay_losses": []}
	inv.reservation_lost_to_decay.connect(_on_record_decay_loss)

	time_provider.advance(5.0)
	var losses: Dictionary = manager.step_decay()
	assert_eq(int(losses.get(&"food", 0)), 8)
	assert_eq(manager.get_piles().size(), 0)
	assert_eq(inv.get_physical_amount(&"food"), 0)
	assert_eq(inv.get_reserved_amount(&"food"), 0)
	assert_eq(inv.get_available_amount(&"food"), 0)
	assert_false(inv.has_reservation(&"site_rations"))
	assert_eq(inv.get_total_decayed(&"food"), 8)
	assert_eq((_observer_ctx["decay_losses"] as Array).size(), 1)
	assert_eq(((_observer_ctx["decay_losses"] as Array)[0] as Dictionary)["lost_amount"], 8)


func test_12_invalid_ids_duplicate_reservations_and_repeated_releases() -> void:
	var fix: Dictionary = _make_fixture()
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory
	assert_true(manager.deposit_batch({&"wood": 10, &"stone": 6}))

	# Invalid IDs / batches
	assert_false(inv.reserve_batch(&"", {&"wood": 2}))
	assert_false(inv.reserve_batch(&"site_x", {}))
	assert_false(inv.reserve_batch(&"site_x", {&"wood": 0}))
	assert_false(inv.reserve_batch(&"site_x", {&"wood": -3}))
	assert_false(inv.reserve_batch(&"site_x", {&"wood": 2.5}))
	assert_false(inv.reserve_batch(&"site_x", {&"unknown_res": 1}))
	assert_false(inv.reserve_batch(&"site_x", {"": 2}))
	assert_false(inv.reserve_batch(&"site_x", {123: 2}))

	# Duplicate reservation ID rejected cleanly (no double reserve)
	assert_true(inv.reserve_batch(&"site_dup", {&"wood": 4}))
	assert_false(inv.reserve_batch(&"site_dup", {&"wood": 4}))
	assert_false(inv.reserve_batch(&"site_dup", {&"stone": 2}))
	assert_eq(inv.get_reservation_amounts(&"site_dup"), {&"wood": 4})

	# Repeated releases: 1st succeeds, 2nd fails cleanly without side effects
	assert_false(inv.release_batch(&"nonexistent"))
	assert_true(inv.release_batch(&"site_dup"))
	assert_false(inv.release_batch(&"site_dup"))
	assert_eq(inv.get_reserved_amount(&"wood"), 0)
	assert_eq(inv.get_available_amount(&"wood"), 10)
	_assert_pile_invariants(manager)


func test_13_global_conservation_and_t2_delivery_compatibility() -> void:
	var wood_gradual: ResourceDefinition = _make_def_with_decay(
		WOOD_BASE,
		true,
		0.0,
		10.0,
		DecayProfile.DecayMode.GRADUAL_UNITS
	)
	var fix: Dictionary = _make_fixture(0, {&"wood": wood_gradual, &"stone": STONE_BASE.duplicate()})
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory
	var time_provider: SimulatedWorldTimeProvider = fix["time"] as SimulatedWorldTimeProvider

	var tree := ResourceSource.new()
	tree.source_id = &"wood_tree_01"
	tree.definition = wood_gradual
	tree.initial_amount = 30
	tree.max_extract_per_operation = 10
	(fix["host"] as Node3D).add_child(tree)

	var carry := UnitCarryLoad.new(20)
	var withdrawn_total: int = 0

	# Gather 10 wood and deliver physically via T2 flow
	var ext1: int = tree.transfer_to_carry_load(carry, 10)
	assert_eq(ext1, 10)
	assert_false(inv.deliver_from_carry_load(carry).is_empty())
	assert_true(carry.is_empty())

	# Reserve 8 wood
	assert_true(inv.reserve_batch(&"site_a", {&"wood": 8}))
	assert_eq(inv.get_available_amount(&"wood"), 2)

	# Gather & deliver 6 MORE wood while reservation exists -> merges cleanly, increases free balance
	var ext2: int = tree.transfer_to_carry_load(carry, 6)
	assert_eq(ext2, 6)
	assert_false(inv.deliver_from_carry_load(carry).is_empty())
	assert_eq(inv.get_physical_amount(&"wood"), 16)
	assert_eq(inv.get_reserved_amount(&"wood"), 8)
	assert_eq(inv.get_available_amount(&"wood"), 8)

	# Reserved withdraw of 5 + common withdraw of 3
	assert_true(inv.withdraw_reserved(&"site_a", &"wood", 5))
	withdrawn_total += 5
	assert_true(inv.withdraw(&"wood", 3))
	withdrawn_total += 3

	# Advance time to lose 1 unit via decay
	time_provider.advance(10.0)
	manager.step_decay()

	# Release remainder of site_a
	assert_true(inv.release_batch(&"site_a"))

	var total_accounted: int = (
		tree.get_remaining_amount()
		+ carry.get_amount(&"wood")
		+ inv.get_physical_amount(&"wood")
		+ withdrawn_total
		+ inv.get_total_decayed(&"wood")
	)
	assert_eq(total_accounted, 30, "Zero duplication/loss across T2+T3.1 lifecycle")
	_assert_pile_invariants(manager)


func test_14_reentrancy_blocked_during_reservation_notifications() -> void:
	var fix: Dictionary = _make_fixture()
	var manager: GroundPileManager = fix["manager"] as GroundPileManager
	var inv: SettlementInventory = fix["inventory"] as SettlementInventory

	assert_true(manager.deposit_batch({&"wood": 10}))
	var results: Array = []
	_observer_ctx = {
		"inventory": inv,
		"results": results,
	}
	inv.reservations_changed.connect(_on_attempt_reentrant_reservation)

	assert_true(inv.reserve_batch(&"site_a", {&"wood": 4}))
	assert_eq(results, [false, false, false, false], "Reentrant mutations inside signal callbacks must fail safely")
	assert_eq(inv.get_reservation_amounts(&"site_a"), {&"wood": 4})
	assert_eq(inv.get_available_amount(&"wood"), 6)
	_assert_pile_invariants(manager)
