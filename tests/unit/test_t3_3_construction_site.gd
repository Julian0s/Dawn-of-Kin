extends TestCase
## Unit tests for T3.3 ConstructionSite, BuildSlotPlanner, ConstructionManager,
## targeted pile withdrawals, inventory atomicity, Alternative B decay, and D9 worker roles.

const WOOD_BASE: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_BASE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_BASE: ResourceDefinition = preload("res://data/resources/food.tres")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DEPOT_DEF: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")

var _managers_to_cleanup: Array[GroundPileManager] = []


func after_each() -> void:
	for manager: GroundPileManager in _managers_to_cleanup:
		if manager != null:
			manager.cleanup()
	_managers_to_cleanup.clear()


func _make_def_with_decay(
	base: ResourceDefinition,
	can_decay: bool,
	exposure_sec: float,
	gradual_sec: float
) -> ResourceDefinition:
	var def: ResourceDefinition = base.duplicate() as ResourceDefinition
	var prof := DecayProfile.new()
	prof.can_decay = can_decay
	prof.exposure_duration_sec = exposure_sec
	prof.gradual_unit_interval_sec = gradual_sec
	prof.decay_mode = DecayProfile.DecayMode.GRADUAL_UNITS
	def.decay_profile = prof
	return def


func _make_fixture(
	max_pile_amount: int = 0,
	defs_override: Dictionary = {}
) -> Dictionary:
	var host := Node3D.new()
	add_test_child(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"t33_unit_camp"
	zone.position = Vector3(-4.0, 0.0, -4.0)
	zone.zone_bounds_half_extents = Vector2(4.0, 4.0)
	zone.slot_spacing = 1.2
	zone.min_pile_clearance = 0.85
	zone.max_pile_amount = max_pile_amount
	zone.decay_multiplier = 1.0
	host.add_child(zone)

	var piles_root := Node3D.new()
	piles_root.name = "PilesRoot"
	host.add_child(piles_root)

	var sites_root := Node3D.new()
	sites_root.name = "SitesRoot"
	host.add_child(sites_root)

	var defs: Dictionary = defs_override if not defs_override.is_empty() else {
		&"wood": WOOD_BASE.duplicate(),
		&"stone": STONE_BASE.duplicate(),
		&"food": FOOD_BASE.duplicate(),
	}
	var time_provider := SimulatedWorldTimeProvider.new(0.0)
	var manager := GroundPileManager.new(defs, zone, piles_root, time_provider)
	_managers_to_cleanup.append(manager)
	var inventory := SettlementInventory.new(manager)

	var cm := ConstructionManager.new()
	host.add_child(cm)
	cm.configure(sites_root, inventory, defs, zone, null, &"unit_region")

	return {
		"host": host,
		"zone": zone,
		"piles_root": piles_root,
		"sites_root": sites_root,
		"defs": defs,
		"time": time_provider,
		"manager": manager,
		"inventory": inventory,
		"cm": cm,
	}


func _spawn_dummy_unit(parent: Node, unit_name: String, pos: Vector3 = Vector3.ZERO) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = unit_name
	u.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	u.position = pos
	parent.add_child(u)
	return u


func test_01_targeted_pile_withdrawal_and_carry_load_atomicity() -> void:
	var fx: Dictionary = _make_fixture(8)
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var defs: Dictionary = fx["defs"] as Dictionary
	var wood_def: ResourceDefinition = defs[&"wood"] as ResourceDefinition

	# Split 16 wood across two physical piles of 8 each.
	assert_true(inventory.deposit(&"wood", 16))
	var piles: Array[GroundResourcePile] = manager.get_piles_for_resource(&"wood")
	assert_eq(piles.size(), 2, "max_pile_amount=8 must create 2 physical piles for 16 wood")
	var pile_a: GroundResourcePile = piles[0]
	var pile_b: GroundResourcePile = piles[1]
	assert_eq(pile_a.amount, 8)
	assert_eq(pile_b.amount, 8)

	var res_id := &"res_targeted_test"
	assert_true(inventory.reserve_batch(res_id, {&"wood": 12}))
	var entries: Array[Dictionary] = inventory.get_reserved_pile_entries(res_id, &"wood")
	assert_eq(entries.size(), 2, "12 wood across cap-8 piles must allocate across 2 piles")

	var target_entry: Dictionary = entries[1]
	var target_pile_id: int = int(target_entry["pile_id"])
	var target_reserved: int = int(target_entry["reserved_amount"])
	var other_pile_id: int = int(entries[0]["pile_id"])
	var other_reserved_before: int = int(entries[0]["reserved_amount"])
	var other_amount_before: int = manager.get_pile_by_id(other_pile_id).amount

	var load := UnitCarryLoad.new(20)
	var storage_events: Array[int] = [0]
	inventory.inventory_changed.connect(func() -> void: storage_events[0] += 1)

	# 1. Invalid inputs produce zero side effects and zero spurious signals.
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(0, res_id, wood_def, 2, load), 0)
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(target_pile_id, &"", wood_def, 2, load), 0)
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(target_pile_id, res_id, wood_def, 0, load), 0)
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(target_pile_id, res_id, wood_def, target_reserved + 1, load), 0)
	assert_eq(storage_events[0], 0)
	assert_true(load.is_empty())

	# 2. Targeted withdrawal strictly debits target_pile_id while leaving other_pile_id untouched!
	var taken: int = inventory.withdraw_reserved_from_pile_to_carry_load(
		target_pile_id,
		res_id,
		wood_def,
		target_reserved,
		load
	)
	assert_eq(taken, target_reserved)
	assert_eq(load.get_amount(&"wood"), target_reserved)
	assert_eq(manager.get_pile_by_id(other_pile_id).amount, other_amount_before, "Untargeted pile must remain physically untouched")
	assert_eq(manager.get_pile_by_id(other_pile_id).get_meta(&"unused", 0), 0)
	assert_eq(inventory.get_reservation_amount(res_id, &"wood"), other_reserved_before)
	assert_eq(inventory.get_physical_amount(&"wood"), 16 - target_reserved)
	assert_eq(storage_events[0], 1, "Atomic transfer emits single inventory_changed signal")

	# 3. Attempting to overload remaining capacity on heavy cargo caps cleanly and rejects invalid pile state.
	var load_small := UnitCarryLoad.new(2) # fits only 1 wood (weight 2)
	var capped_take: int = inventory.withdraw_reserved_from_pile_to_carry_load(
		other_pile_id,
		res_id,
		wood_def,
		5,
		load_small
	)
	assert_eq(capped_take, 1, "Carry transfer must cap withdrawal to capacity room")
	assert_eq(load_small.get_amount(&"wood"), 1)
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(other_pile_id, res_id, wood_def, 1, load_small), 0, "Full carry load cannot take extra unit")


func test_02_construction_manager_creation_rejection_and_rollback() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var rejected_reasons: Array[String] = []
	var created_sites: Array[ConstructionSite] = []
	cm.site_creation_rejected.connect(func(r: String, _m: String, _d: BuildingDefinition, _p: Vector3) -> void:
		rejected_reasons.append(r)
	)
	cm.site_created.connect(func(s: ConstructionSite) -> void:
		created_sites.append(s)
	)

	# 1. Partial stock missing stone: atomic rejection, zero partial reservations.
	assert_true(inventory.deposit(&"wood", 15))
	assert_true(inventory.deposit(&"stone", 4)) # Shelter needs 12 wood, 6 stone
	var res_fail: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(6.0, 0.0, 6.0))
	assert_false(bool(res_fail["ok"]))
	assert_eq(res_fail["reason"], "insufficient_resources")
	assert_eq(inventory.get_reserved_amount(&"wood"), 0, "Rejected creation must leave zero partial wood reservation")
	assert_eq(inventory.get_reserved_amount(&"stone"), 0)
	assert_eq(cm.get_sites().size(), 0)

	# 2. Deposit missing stone & succeed on Shelter.
	assert_true(inventory.deposit(&"stone", 6)) # free stock: 15 wood, 10 stone
	var res_ok: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(6.0, 0.0, 6.0))
	assert_true(bool(res_ok["ok"]))
	var site1: ConstructionSite = res_ok["site"] as ConstructionSite
	assert_not_null(site1)
	assert_true(site1.is_valid())
	assert_eq(created_sites.size(), 1)
	assert_eq(inventory.get_reserved_amount(&"wood"), 12)
	assert_eq(inventory.get_reserved_amount(&"stone"), 6)
	assert_eq(inventory.get_available_amount(&"wood"), 3)
	assert_eq(inventory.get_available_amount(&"stone"), 4)

	# 3. Duplicate / overlap and CampStorageZone overlap rejections keep reserves unchanged.
	var res_overlap: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(7.0, 0.0, 7.0))
	assert_false(bool(res_overlap["ok"]))
	assert_eq(res_overlap["reason"], "site_overlap")

	var res_camp: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-4.0, 0.0, -4.0))
	assert_false(bool(res_camp["ok"]))
	assert_eq(res_camp["reason"], "camp_overlap")

	# 4. Forced site instantiation failure AFTER reserve_batch triggers atomic release rollback!
	var rollback_cm := ConstructionManager.new()
	host.add_child(rollback_cm)
	rollback_cm.configure(fx["sites_root"] as Node3D, inventory, fx["defs"] as Dictionary, fx["zone"] as CampStorageZone, null, &"rb_region")
	rollback_cm.site_creator_override = func(_sid: StringName, _rid: StringName, _def: BuildingDefinition, _pos: Vector3) -> Variant:
		return null
	# Free stock currently: 3 wood, 4 stone -> deposit enough for 2nd shelter (need +9 wood, +2 stone)
	assert_true(inventory.deposit(&"wood", 9))
	assert_true(inventory.deposit(&"stone", 2))
	var rb_res: Dictionary = rollback_cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-10.0, 0.0, 6.0))
	assert_false(bool(rb_res["ok"]))
	assert_eq(rb_res["reason"], "site_instantiation_failed")
	assert_eq(inventory.get_reserved_amount(&"wood"), 12, "Post-reserve instantiation failure must release new wood reservation")
	assert_eq(inventory.get_reserved_amount(&"stone"), 6, "Post-reserve instantiation failure must release new stone reservation")
	assert_eq(inventory.get_available_amount(&"wood"), 12)
	assert_eq(inventory.get_available_amount(&"stone"), 6)
	rollback_cm.site_creator_override = Callable()

	var bad_site := ConstructionSite.new()
	assert_false(bad_site.configure(&"bad", &"res_bad", null, inventory))
	bad_site.free()


func test_03_site_buffer_pickup_claims_transit_conservation_and_double_dropoff_guard() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var defs: Dictionary = fx["defs"] as Dictionary
	var wood_def: ResourceDefinition = defs[&"wood"] as ResourceDefinition
	var stone_def: ResourceDefinition = defs[&"stone"] as ResourceDefinition

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(6.0, 0.0, 6.0))
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite

	var w1: Unit = _spawn_dummy_unit(host, "W1", Vector3(2.0, 0.0, 2.0))
	var w2: Unit = _spawn_dummy_unit(host, "W2", Vector3(2.5, 0.0, 2.0))

	# Accounting equation right after creation: required=12, delivered=0, reserved=12, in_transit=0 -> missing=0.
	assert_eq(site.get_required_amount(&"wood"), 12)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)
	assert_eq(site.get_in_transit_amount(&"wood"), 0)
	assert_eq(site.get_missing_amount(&"wood"), 0)
	assert_false(site.is_fully_supplied())

	# Two workers cannot double-claim the same remaining pile units.
	var wood_piles: Array[Dictionary] = inventory.get_reserved_pile_entries(site.reservation_id, &"wood")
	var pile_id: int = int(wood_piles[0]["pile_id"])
	var claim_1: int = site.claim_pickup(w1, pile_id, &"wood", 10, 12)
	var claim_2: int = site.claim_pickup(w2, pile_id, &"wood", 10, 12)
	assert_eq(claim_1, 10)
	assert_eq(claim_2, 2, "Second worker claim must clamp to remaining 2 reserved units on pile")

	# W1 withdraws 10 wood and records transit claim; external load clearance shrinks transit automatically.
	var taken1: int = inventory.withdraw_reserved_from_pile_to_carry_load(pile_id, site.reservation_id, wood_def, 10, w1.get_carry_load())
	assert_eq(taken1, 10)
	site.record_withdrawn_for_site(w1, &"wood", taken1)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 2)
	assert_eq(site.get_in_transit_amount(&"wood"), 10)
	assert_eq(site.get_missing_amount(&"wood"), 0)

	# Drop off at site and guard against double dropoff.
	var dropped1: Dictionary = site.accept_delivery_from_carry_load(w1, w1.get_carry_load())
	assert_eq(int(dropped1.get(&"wood", 0)), 10)
	assert_true(w1.get_carry_load().is_empty())
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 10)
	assert_eq(site.get_in_transit_amount(&"wood"), 0)
	assert_true(site.accept_delivery_from_carry_load(w1, w1.get_carry_load()).is_empty(), "Repeated dropoff must do nothing")

	# Finish remaining 2 wood + 6 stone, verify overflow protection and supply_completed.
	var completed_count: Array[int] = [0]
	site.supply_completed.connect(func(_s: ConstructionSite) -> void: completed_count[0] += 1)

	var taken2: int = inventory.withdraw_reserved_from_pile_to_carry_load(pile_id, site.reservation_id, wood_def, 2, w2.get_carry_load())
	assert_eq(taken2, 2)
	site.record_withdrawn_for_site(w2, &"wood", taken2)
	var stone_piles: Array[Dictionary] = inventory.get_reserved_pile_entries(site.reservation_id, &"stone")
	var stone_pile_id: int = int(stone_piles[0]["pile_id"])
	var taken_stone: int = inventory.withdraw_reserved_from_pile_to_carry_load(stone_pile_id, site.reservation_id, stone_def, 6, w1.get_carry_load())
	assert_eq(taken_stone, 6)
	site.record_withdrawn_for_site(w1, &"stone", taken_stone)

	# Extra free wood in W2's pack must NOT push buffer past 12/12!
	assert_true(inventory.deposit(&"wood", 3))
	assert_true(w2.get_carry_load().add_units(wood_def, 3))
	var dropped2: Dictionary = site.accept_delivery_from_carry_load(w2, w2.get_carry_load())
	assert_eq(int(dropped2.get(&"wood", 0)), 2, "Dropoff must cap strictly to remaining site need (2), leaving surplus 3 in pack")
	assert_eq(w2.get_carry_load().get_amount(&"wood"), 3)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 12)

	var dropped_stone: Dictionary = site.accept_delivery_from_carry_load(w1, w1.get_carry_load())
	assert_eq(int(dropped_stone.get(&"stone", 0)), 6)
	assert_true(site.is_fully_supplied())
	assert_eq(completed_count[0], 1)


func test_04_decay_alternative_b_updates_reserved_and_missing_without_reallocation() -> void:
	var wood_decay: ResourceDefinition = _make_def_with_decay(WOOD_BASE, true, 1.0, 1.0)
	var stone_fixed: ResourceDefinition = STONE_BASE.duplicate() as ResourceDefinition
	var defs: Dictionary = {
		&"wood": wood_decay,
		&"stone": stone_fixed,
		&"food": FOOD_BASE.duplicate(),
	}
	var fx: Dictionary = _make_fixture(12, defs)
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_p: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	# Pile 1: 12 wood (will be reserved for site). Later deposit Pile 2: 10 free wood (must NOT be auto-reallocated).
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(6.0, 0.0, 6.0))
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite

	assert_true(inventory.deposit(&"wood", 10))
	assert_eq(inventory.get_available_amount(&"wood"), 10)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)
	assert_eq(site.get_missing_amount(&"wood"), 0)

	var lost_events: Array[Dictionary] = []
	site.reservation_lost.connect(func(_s: ConstructionSite, r_id: StringName, amt: int) -> void:
		lost_events.append({"res_id": r_id, "amount": amt})
	)

	# Advance 4.0s (1.0s grace + 3.0s -> 3 units decay on every wood pile; reserved Pile 1 loses 3 -> 9 left).
	time_p.advance(4.0)
	manager.step_decay()

	assert_eq(lost_events.size(), 1)
	assert_eq(lost_events[0]["res_id"], &"wood")
	assert_eq(int(lost_events[0]["amount"]), 3)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 9)
	assert_eq(site.get_missing_amount(&"wood"), 3, "Lost reserved units must show accurately as missing without fabrication")
	assert_eq(inventory.get_available_amount(&"wood"), 7, "Free stock (10 - 3 decayed) must NEVER be silently auto-reallocated")


func test_05_d9_worker_roles_max_builders_promotion_and_excess_rejection() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(6.0, 0.0, 6.0))
	var site: ConstructionSite = res["site"] as ConstructionSite

	var w1: Unit = _spawn_dummy_unit(host, "W1")
	var w2: Unit = _spawn_dummy_unit(host, "W2")
	var w3: Unit = _spawn_dummy_unit(host, "W3")
	var w4: Unit = _spawn_dummy_unit(host, "W4")
	var w5: Unit = _spawn_dummy_unit(host, "W5")

	# Use lightweight active UnitOrder stubs to isolate ConstructionSite D9 role state machine.
	var o1 := UnitOrder.new(); o1.mark_running()
	var o2 := UnitOrder.new(); o2.mark_running()
	var o3 := UnitOrder.new(); o3.mark_running()
	var o4 := UnitOrder.new(); o4.mark_running()
	var o5 := UnitOrder.new(); o5.mark_running()

	# 1 worker -> SOLO_SUPPLIER
	assert_eq(site.register_worker(w1, o1, false), ConstructionSite.WorkerRole.SOLO_SUPPLIER)
	assert_eq(site.get_worker_role(w1), ConstructionSite.WorkerRole.SOLO_SUPPLIER)

	# 2 workers -> W1 = TRANSPORTER, W2 = BUILDER (slot 0)
	assert_eq(site.register_worker(w2, o2, false), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(site.get_worker_role(w1), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site.get_worker_role(w2), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(site.get_builder_slot_index(w2), 0)

	# 3 workers -> W1 = TRANSPORTER, W2 = BUILDER (slot 0), W3 = BUILDER (slot 1)
	assert_eq(site.register_worker(w3, o3, false), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(site.get_worker_role(w1), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site.get_worker_role(w3), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(site.get_builder_slot_index(w3), 1)

	# 4th worker in AUTO_D9 -> rejected (respecting 1 transporter + max_builders=2)
	assert_eq(site.register_worker(w4, o4, false), ConstructionSite.WorkerRole.UNASSIGNED)
	assert_eq(site.get_assigned_worker_entries().size(), 3)

	# Forced transporter bypasses builder cap cleanly when explicitly requested.
	assert_eq(site.register_worker(w5, o5, true), ConstructionSite.WorkerRole.TRANSPORTER)
	site.unregister_worker(w5, o5)

	# Unregister W1 -> W2 automatically promotes to TRANSPORTER, W3 remains BUILDER!
	site.unregister_worker(w1, o1)
	assert_eq(site.get_worker_role(w2), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site.get_worker_role(w3), ConstructionSite.WorkerRole.BUILDER)

	# Unregister W3 -> W2 becomes SOLO_SUPPLIER!
	site.unregister_worker(w3, o3)
	assert_eq(site.get_worker_role(w2), ConstructionSite.WorkerRole.SOLO_SUPPLIER)
