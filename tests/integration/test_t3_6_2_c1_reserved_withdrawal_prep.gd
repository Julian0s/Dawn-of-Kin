extends TestCase
## Integration tests for T3.6.2-C1:
## Pure, opt-in, side-effect-free preparation of a site-reserved pile withdrawal
## into a provenance-enabled UnitCarryLoad with matching ConstructionSite claim.
## Verifies ABA resistance, idempotency, DEC-11B, cross-site claims, and zero side effects.

const WOOD_BASE: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_BASE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_BASE: ResourceDefinition = preload("res://data/resources/food.tres")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")

var _managers_to_cleanup: Array[GroundPileManager] = []


func after_each() -> void:
	for manager: GroundPileManager in _managers_to_cleanup:
		if manager != null:
			manager.cleanup()
	_managers_to_cleanup.clear()


func _make_fixture(max_pile_amount: int = 0) -> Dictionary:
	var host := Node3D.new()
	add_test_child(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"c1_test_camp"
	zone.position = Vector3(-8.0, 0.0, -8.0)
	zone.zone_bounds_half_extents = Vector2(8.0, 8.0)
	zone.slot_spacing = 1.5
	zone.min_pile_clearance = 1.0
	zone.max_pile_amount = max_pile_amount
	zone.decay_multiplier = 1.0
	host.add_child(zone)

	var piles_root := Node3D.new()
	piles_root.name = "PilesRoot"
	host.add_child(piles_root)

	var sites_root := Node3D.new()
	sites_root.name = "SitesRoot"
	host.add_child(sites_root)

	var defs: Dictionary = {
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
	cm.configure(sites_root, inventory, defs, zone, null, &"c1_region")

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


func _make_building_def(def_id: StringName, costs: Dictionary, max_builders: int = 2) -> BuildingDefinition:
	var def := BuildingDefinition.new()
	def.definition_id = def_id
	def.display_name = String(def_id)
	def.footprint_size = Vector2(3.0, 3.0)
	def.costs = costs.duplicate()
	def.build_work_required_sec = 10.0
	def.max_builders = max_builders
	def.visual_height = 2.0
	return def


func _spawn_unit(
	parent: Node,
	unit_name: String,
	prov_unit_id: StringName,
	capacity: int = 20,
	pos: Vector3 = Vector3.ZERO
) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = unit_name
	var char_def: CharacterDefinition = LEADER_A_DEF.duplicate() as CharacterDefinition
	char_def.base_carry_capacity = capacity
	u.definition = char_def
	u.position = pos
	parent.add_child(u)
	if not prov_unit_id.is_empty():
		assert_true(u.get_carry_load().enable_provenance(prov_unit_id))
	return u


func _snapshot_all(
	manager: GroundPileManager,
	inventory: SettlementInventory,
	sites: Array[ConstructionSite],
	loads: Array[UnitCarryLoad]
) -> Dictionary:
	var pile_snaps: Array = []
	for pile: GroundResourcePile in manager.get_piles():
		pile_snaps.append({
			"id": pile.pile_id,
			"res": pile.resource_id,
			"amount": pile.amount,
			"elapsed": pile.elapsed_exposure_sec,
			"accum": pile.decay_accumulator_sec,
			"rev": pile.get_transaction_revision(),
			"tier": pile.get_visual_tier(),
			"meshes": pile.get_visible_mesh_count(),
		})
	var site_snaps: Array = []
	for s: ConstructionSite in sites:
		site_snaps.append({
			"id": s.site_id,
			"gen": s.get_generation(),
			"rev": s.get_transaction_revision(),
			"work_serial": s._work_cycle_serial,
			"state": s.get_site_state(),
			"substate": s.get_assembly_substate(),
			"buffer": s._delivered_buffer.duplicate(true),
			"consumed": s._consumed_materials.duplicate(true),
			"pending": s._pending_pickups.duplicate(true),
			"transit_keys": s._transit_claims.keys(),
			"transit": _copy_transit_claims(s),
			"workers": s._assigned_workers.keys(),
			"defs_keys": s._resource_defs.keys(),
		})
	var load_snaps: Array = []
	for cl: UnitCarryLoad in loads:
		load_snaps.append({
			"rev": cl.get_transaction_revision(),
			"cap": cl.get_effective_capacity(),
			"weight": cl.get_current_weight(),
			"prov": cl.provenance_snapshot(),
			"amounts": cl.get_all_amounts(),
		})
	return {
		"piles": pile_snaps,
		"ledger": manager._ledger.snapshot_state(),
		"ledger_rev": manager.get_pile_ledger_revision(),
		"storage_rev": manager.get_transaction_revision(),
		"decayed": manager.get_all_decayed(),
		"inv_rev": inventory.get_transaction_revision(),
		"sites": site_snaps,
		"loads": load_snaps,
	}


func _copy_transit_claims(s: ConstructionSite) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in s._transit_claims.keys():
		var claim: Dictionary = s._transit_claims[k] as Dictionary
		out[k] = (claim.get("amounts", {}) as Dictionary).duplicate(true)
	return out


class SignalSpy extends RefCounted:
	var events: Array[String] = []
	var _connections: Array[Dictionary] = []

	func watch_all(
		manager: GroundPileManager,
		inventory: SettlementInventory,
		sites: Array[ConstructionSite],
		loads: Array[UnitCarryLoad]
	) -> void:
		_connect(manager.storage_changed, func() -> void: events.append("mgr_storage"))
		_connect(manager.reservations_changed, func() -> void: events.append("mgr_res"))
		_connect(manager.reservation_lost_to_decay, func(_r: StringName, _res: StringName, _a: int) -> void: events.append("mgr_decay"))
		_connect(inventory.inventory_changed, func() -> void: events.append("inv_changed"))
		_connect(inventory.reservations_changed, func() -> void: events.append("inv_res"))
		_connect(inventory.reservation_lost_to_decay, func(_r: StringName, _res: StringName, _a: int) -> void: events.append("inv_decay"))
		for s: ConstructionSite in sites:
			_connect(s.state_changed, func(_s: ConstructionSite) -> void: events.append("site_state:" + String(s.site_id)))
			_connect(s.buffer_changed, func(_s: ConstructionSite) -> void: events.append("site_buf:" + String(s.site_id)))
			_connect(s.workers_changed, func(_s: ConstructionSite) -> void: events.append("site_workers:" + String(s.site_id)))
			_connect(s.supply_completed, func(_s: ConstructionSite) -> void: events.append("site_supply:" + String(s.site_id)))
			_connect(s.reservation_lost, func(_s: ConstructionSite, _r: StringName, _a: int) -> void: events.append("site_loss:" + String(s.site_id)))
		for cl: UnitCarryLoad in loads:
			_connect(cl.load_changed, func() -> void: events.append("load_changed"))
			_connect(cl.capacity_changed, func() -> void: events.append("cap_changed"))

	func _connect(sig: Signal, cb: Callable) -> void:
		if not sig.is_connected(cb):
			sig.connect(cb)
			_connections.append({"sig": sig, "cb": cb})

	func cleanup() -> void:
		for item: Dictionary in _connections:
			var sig: Signal = item["sig"] as Signal
			var cb: Callable = item["cb"] as Callable
			if sig.is_connected(cb):
				sig.disconnect(cb)
		_connections.clear()


func test_01_wood_and_stone_reserved_withdrawal_plans_and_zero_side_effects() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 10, slots[0])
	var pile_s: GroundResourcePile = manager.try_create_pile_at(&"stone", 6, slots[1])
	assert_not_null(pile_w)
	assert_not_null(pile_s)

	var site_def: BuildingDefinition = _make_building_def(&"c1_shelter", {&"wood": 8, &"stone": 4})
	var create_res: Dictionary = cm.try_create_site_from_placement(site_def, Vector3(8.0, 0.0, 8.0))
	assert_true(bool(create_res["ok"]))
	var site: ConstructionSite = create_res["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "Worker1", &"worker_1", 20)
	var load1: UnitCarryLoad = u1.get_carry_load()

	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site], [load1])

	var before_snap: Dictionary = _snapshot_all(manager, inventory, [site], [load1])

	# 1. Wood withdrawal plan (weight 2 * 5 = 10 kg)
	var wood_plan: Dictionary = site.prepare_reserved_withdrawal(
		u1,
		pile_w.pile_id,
		&"wood",
		5,
		&"op_wood_1",
		&"lot_wood_1",
		{"site_id": site.site_id, "generation": site.get_generation(), "reservation_id": site.reservation_id, "unit_id": &"worker_1"}
	)
	assert_true(bool(wood_plan["ok"]))
	assert_true(bool(wood_plan["dry_run_only"]))
	assert_false(bool(wood_plan["commit_supported"]))
	assert_eq(wood_plan["lock_order"], ["site", "inventory_storage", "carry_load"])
	var projected_ledger := CarryProvenanceLedger.new()
	assert_true(projected_ledger.restore_transaction_state(wood_plan["carry_plan"]["after_ledger"]))
	assert_true(bool(projected_ledger.validate_aggregate(&"worker_1", wood_plan["carry_plan"]["after_amounts"])["ok"]))

	# Check Pile projection (pile_w has 10 physical, 8 reserved, 2 free)
	assert_eq(int(wood_plan["pile_plan"]["before"]["pile_amount"]), 10)
	assert_eq(int(wood_plan["pile_plan"]["before"]["pile_reserved_for_site"]), 8)
	assert_eq(int(wood_plan["pile_plan"]["before"]["pile_free_amount"]), 2)
	assert_eq(int(wood_plan["pile_plan"]["after"]["pile_amount"]), 5)
	assert_eq(int(wood_plan["pile_plan"]["after"]["pile_reserved_for_site"]), 3)
	assert_eq(int(wood_plan["pile_plan"]["after"]["pile_free_amount"]), 2)
	assert_false(bool(wood_plan["pile_plan"]["after"]["pile_will_remove"]))

	# Check Carry & Provenance projection
	assert_eq(int(wood_plan["carry_plan"]["before_weight"]), 0)
	assert_eq(int(wood_plan["carry_plan"]["after_weight"]), 5 * WOOD_BASE.unit_weight)
	assert_eq(wood_plan["carry_plan"]["after_amounts"], {&"wood": 5})
	assert_eq(wood_plan["carry_plan"]["new_lot"], {
		"lot_id": &"lot_wood_1",
		"unit_id": &"worker_1",
		"resource_id": &"wood",
		"quantity": 5,
		"origin": CarryProvenanceLedger.SITE_RESERVED,
		"site_id": site.site_id,
		"generation": site.get_generation(),
	})

	# Check Claim & Site Accounting projection
	assert_eq(wood_plan["claim_plan"]["before_transit_claim"], {})
	assert_eq(wood_plan["claim_plan"]["after_transit_claim"], {&"wood": 5})
	assert_eq(int(wood_plan["claim_plan"]["before_accounting"]["reserved"]), 8)
	assert_eq(int(wood_plan["claim_plan"]["after_accounting"]["reserved"]), 3)
	assert_eq(int(wood_plan["claim_plan"]["before_accounting"]["in_transit"]), 0)
	assert_eq(int(wood_plan["claim_plan"]["after_accounting"]["in_transit"]), 5)
	assert_eq(int(wood_plan["claim_plan"]["after_accounting"]["sum"]), 8)

	# 2. Stone withdrawal plan (weight 2 * 4 = 8 kg) exhausting full reservation on pile_s
	var stone_plan: Dictionary = site.prepare_reserved_withdrawal(
		u1,
		pile_s.pile_id,
		&"stone",
		4,
		&"op_stone_1",
		&"lot_stone_1"
	)
	assert_true(bool(stone_plan["ok"]))
	assert_eq(int(stone_plan["unit_weight"]), STONE_BASE.unit_weight)
	assert_eq(int(stone_plan["pile_plan"]["before"]["pile_amount"]), 6)
	assert_eq(int(stone_plan["pile_plan"]["after"]["pile_amount"]), 2)
	assert_eq(int(stone_plan["pile_plan"]["after"]["pile_reserved_for_site"]), 0)
	assert_eq(int(stone_plan["pile_plan"]["after"]["pile_free_amount"]), 2)
	assert_eq(int(stone_plan["carry_plan"]["after_weight"]), 4 * STONE_BASE.unit_weight)
	assert_eq(stone_plan["claim_plan"]["after_transit_claim"], {&"stone": 4})

	# Verify exact plan validation succeeds with zero mutations
	assert_true(bool(site.validate_reserved_withdrawal_plan(wood_plan)["ok"]))
	assert_true(bool(site.validate_reserved_withdrawal_plan(stone_plan)["ok"]))

	# Verify zero mutations across all objects and zero signals emitted (13, 14, 15)
	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site], [load1]), before_snap)
	spy.cleanup()


func test_02_competing_sites_distinct_piles_and_decay_dec_11b() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_p: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w1: GroundResourcePile = manager.try_create_pile_at(&"wood", 8, slots[0])
	var pile_s1: GroundResourcePile = manager.try_create_pile_at(&"stone", 12, slots[1])
	assert_not_null(pile_w1)
	assert_not_null(pile_s1)

	var def_a: BuildingDefinition = _make_building_def(&"c1_comp_a", {&"wood": 6, &"stone": 6})
	var res_a: Dictionary = cm.try_create_site_from_placement(def_a, Vector3(8.0, 0.0, 8.0))
	assert_true(bool(res_a["ok"]))
	var site_a: ConstructionSite = res_a["site"] as ConstructionSite

	# Add second wood pile (4 wood) so Site B spans both Pile 1 (2 wood) and Pile 2 (4 wood).
	var pile_w2: GroundResourcePile = manager.try_create_pile_at(&"wood", 4, slots[2])
	assert_not_null(pile_w2)
	var def_b: BuildingDefinition = _make_building_def(&"c1_comp_b", {&"wood": 6, &"stone": 6})
	var res_b: Dictionary = cm.try_create_site_from_placement(def_b, Vector3(14.0, 0.0, 8.0))
	assert_true(bool(res_b["ok"]))
	var site_b: ConstructionSite = res_b["site"] as ConstructionSite

	assert_eq(manager.get_pile_reservations(pile_w1.pile_id), {site_a.reservation_id: 6, site_b.reservation_id: 2})
	assert_eq(manager.get_pile_reservations(pile_w2.pile_id), {site_b.reservation_id: 4})

	var u1: Unit = _spawn_unit(host, "Worker1", &"worker_1", 20)
	var u2: Unit = _spawn_unit(host, "Worker2", &"worker_2", 20)
	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site_a, site_b], [u1.get_carry_load(), u2.get_carry_load()])
	var snap_competing: Dictionary = _snapshot_all(manager, inventory, [site_a, site_b], [u1.get_carry_load(), u2.get_carry_load()])

	# Concurrent sites on same resource & distinct piles:
	var plan_a_w1: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w1.pile_id, &"wood", 4, &"op_a1", &"lot_a1")
	assert_true(bool(plan_a_w1["ok"]))
	# Projected ledger keeps site_b's 2 wood on pile_w1 untouched!
	assert_eq(int(plan_a_w1["pile_plan"]["after"]["pile_reservations"][site_b.reservation_id]), 2)
	assert_eq(int(plan_a_w1["pile_plan"]["after"]["pile_reservations"][site_a.reservation_id]), 2)

	# Site A cannot withdraw from Pile 2 reserved strictly for Site B:
	var wrong_pile_for_a: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w2.pile_id, &"wood", 1, &"op_a_bad", &"lot_a_bad")
	assert_false(bool(wrong_pile_for_a["ok"]))
	assert_eq(String(wrong_pile_for_a["reason"]), "reservation_belongs_to_other_site")

	# Site B can plan independently from BOTH Pile 1 (2) and Pile 2 (4):
	var plan_b_w1: Dictionary = site_b.prepare_reserved_withdrawal(u2, pile_w1.pile_id, &"wood", 2, &"op_b1", &"lot_b1")
	var plan_b_w2: Dictionary = site_b.prepare_reserved_withdrawal(u2, pile_w2.pile_id, &"wood", 4, &"op_b2", &"lot_b2")
	assert_true(bool(plan_b_w1["ok"]))
	assert_true(bool(plan_b_w2["ok"]))

	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site_a, site_b], [u1.get_carry_load(), u2.get_carry_load()]), snap_competing)

	# Decay Scenario (item 4 & 5 DEC-11B): age Pile 1 to grace (420s), keep Pile 2 fresh (0s), advance +360s (+3 wood decay).
	pile_w1.apply_state(8, 420.0, 0.0)
	time_p.advance(360.0)
	var losses: Dictionary = manager.step_decay()
	assert_eq(int(losses.get(&"wood", 0)), 3)
	assert_eq(int(losses.get(&"stone", 0)), 0)
	# Alternative B reverse order: site_b loses its 2 on Pile 1, site_a loses 1 (5 left).
	assert_eq(pile_w1.amount, 5)
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 5)
	assert_eq(site_a.get_missing_amount(&"wood"), 1)
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 4)
	assert_eq(site_b.get_missing_amount(&"wood"), 2)

	# Add fresh free wood pile Pile 3 (5 wood): DEC-11B prohibits auto-reallocation!
	var pile_w3: GroundResourcePile = manager.try_create_pile_at(&"wood", 5, slots[3])
	assert_not_null(pile_w3)

	spy.events.clear()
	var snap_post_decay: Dictionary = _snapshot_all(manager, inventory, [site_a, site_b], [u1.get_carry_load(), u2.get_carry_load()])

	# Preparing 6 for Site A on Pile 1 fails (only 5 left); preparing 5 succeeds preserving missing == 1.
	var too_much_a: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w1.pile_id, &"wood", 6, &"op_a_over", &"lot_a_over")
	assert_false(bool(too_much_a["ok"]))
	assert_eq(String(too_much_a["reason"]), "insufficient_pile_reservation")

	var valid_post_decay: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w1.pile_id, &"wood", 5, &"op_a_rem", &"lot_a_rem")
	assert_true(bool(valid_post_decay["ok"]))
	assert_eq(int(valid_post_decay["claim_plan"]["after_accounting"]["uncovered_missing"]), 1)

	# Unreserved Pile 3 cannot be prepared before explicit ManualComplementIntent:
	var no_res_w3: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w3.pile_id, &"wood", 1, &"op_a_free", &"lot_a_free")
	assert_false(bool(no_res_w3["ok"]))
	assert_eq(String(no_res_w3["reason"]), "no_site_reservation_on_pile")

	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site_a, site_b], [u1.get_carry_load(), u2.get_carry_load()]), snap_post_decay)

	# Authorize DEC-11B manual complement for Site A's 1 missing wood -> reserves on Pile 3:
	var intent := ManualComplementIntent.create_for_test(self, site_a)
	var comp_res: Dictionary = site_a.authorize_manual_complement(intent, {&"wood": 1}, false)
	assert_true(bool(comp_res["ok"]))
	assert_eq(manager.get_pile_reservations(pile_w3.pile_id), {site_a.reservation_id: 1})

	spy.events.clear()
	var snap_after_comp: Dictionary = _snapshot_all(manager, inventory, [site_a, site_b], [u1.get_carry_load(), u2.get_carry_load()])
	var plan_w3_after_comp: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w3.pile_id, &"wood", 1, &"op_a_comp", &"lot_a_comp")
	assert_true(bool(plan_w3_after_comp["ok"]))
	assert_eq(int(plan_w3_after_comp["pile_plan"]["before"]["pile_free_amount"]), 4)
	assert_eq(int(plan_w3_after_comp["pile_plan"]["after"]["pile_free_amount"]), 4)
	assert_eq(int(plan_w3_after_comp["claim_plan"]["after_accounting"]["uncovered_missing"]), 0)
	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site_a, site_b], [u1.get_carry_load(), u2.get_carry_load()]), snap_after_comp)
	spy.cleanup()


func test_03_mixed_carry_load_multi_site_claims_and_unreconciled_detection() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 10, slots[0])
	var pile_s: GroundResourcePile = manager.try_create_pile_at(&"stone", 8, slots[1])
	assert_not_null(pile_w)
	assert_not_null(pile_s)

	var def_a: BuildingDefinition = _make_building_def(&"c1_mix_a", {&"wood": 6, &"stone": 2})
	var def_b: BuildingDefinition = _make_building_def(&"c1_mix_b", {&"wood": 2, &"stone": 4})
	var site_a: ConstructionSite = cm.try_create_site_from_placement(def_a, Vector3(8.0, 0.0, 8.0))["site"] as ConstructionSite
	var site_b: ConstructionSite = cm.try_create_site_from_placement(def_b, Vector3(14.0, 0.0, 8.0))["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "MixedUnit", &"mixed_unit", 20)
	var load1: UnitCarryLoad = u1.get_carry_load()

	# 1. Gather 2 FREE_GATHERED wood from a real ResourceSource
	var wood_source := ResourceSource.new()
	host.add_child(wood_source)
	wood_source.configure(&"src_w", WOOD_BASE.duplicate(), 5, 5, 2)
	var gather_res: Dictionary = wood_source.transfer_to_carry_load_with_provenance(load1, &"op_free_g", &"lot_free_g", 2)
	assert_true(bool(gather_res["ok"]))

	# 2. Seed valid existing SITE_RESERVED cargo for Site B (1 stone, weight 2) and Site A (1 wood, weight 1)
	assert_true(manager.withdraw_reserved_from_pile(pile_s.pile_id, site_b.reservation_id, &"stone", 1))
	assert_true(bool(load1.add_with_provenance(&"op_b_prev", &"lot_b_prev", &"stone", STONE_BASE.unit_weight, 1, CarryProvenanceLedger.SITE_RESERVED, site_b.site_id, site_b.get_generation())["ok"]))
	site_b.record_withdrawn_for_site(u1, &"stone", 1)

	assert_true(manager.withdraw_reserved_from_pile(pile_w.pile_id, site_a.reservation_id, &"wood", 1))
	assert_true(bool(load1.add_with_provenance(&"op_a_prev", &"lot_a_prev", &"wood", WOOD_BASE.unit_weight, 1, CarryProvenanceLedger.SITE_RESERVED, site_a.site_id, site_a.get_generation())["ok"]))
	site_a.record_withdrawn_for_site(u1, &"wood", 1)

	# Current weight: 2*2 + 1*3 + 1*2 = 9 / 20 kg. Wood total = 3 (2 FREE, 1 SITE_A). Stone total = 1 (SITE_B).
	assert_eq(load1.get_current_weight(), 9)
	assert_eq(site_a.get_transit_claim_for_unit(u1), {&"wood": 1})
	assert_eq(site_b.get_transit_claim_for_unit(u1), {&"stone": 1})

	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site_a, site_b], [load1])
	var before_snap: Dictionary = _snapshot_all(manager, inventory, [site_a, site_b], [load1])

	# Plan adding 4 more wood for Site A:
	var plan_mix: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 4, &"op_a_next", &"lot_a_next")
	assert_true(bool(plan_mix["ok"]))
	assert_eq(plan_mix["carry_plan"]["after_amounts"], {&"wood": 7, &"stone": 1})
	assert_eq(int(plan_mix["carry_plan"]["after_weight"]), 17)
	assert_eq(plan_mix["claim_plan"]["before_transit_claim"], {&"wood": 1})
	assert_eq(plan_mix["claim_plan"]["after_transit_claim"], {&"wood": 5})
	assert_eq(plan_mix["carry_plan"]["after_ledger"]["lots"][&"lot_free_g"]["origin"], CarryProvenanceLedger.FREE_GATHERED)
	assert_eq(plan_mix["carry_plan"]["after_ledger"]["lots"][&"lot_b_prev"]["site_id"], site_b.site_id)
	assert_eq(int(plan_mix["carry_plan"]["after_ledger"]["lots"][&"lot_b_prev"]["quantity"]), 1)

	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site_a, site_b], [load1]), before_snap)

	# Cross-site reservation misuse (attempting to pass site_b.reservation_id to site_a):
	var wrong_res_id: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_x", &"lot_x", {"reservation_id": site_b.reservation_id})
	assert_false(bool(wrong_res_id["ok"]))
	assert_eq(String(wrong_res_id["reason"]), "reservation_mismatch")

	# Detect divergence between site_b claim and site_b lot:
	# Withdraw 1 stone for site_b in storage headroom, while u2 physically carries ONLY FREE_GATHERED stone:
	var u2: Unit = _spawn_unit(host, "DesyncUnit", &"desync_unit", 20)
	var load2: UnitCarryLoad = u2.get_carry_load()
	var stone_source := ResourceSource.new()
	host.add_child(stone_source)
	stone_source.configure(&"src_s", STONE_BASE.duplicate(), 5, 5, 2)
	assert_true(bool(stone_source.transfer_to_carry_load_with_provenance(load2, &"op_f_s", &"lot_f_s", 1)["ok"]))
	assert_true(manager.withdraw_reserved_from_pile(pile_s.pile_id, site_b.reservation_id, &"stone", 1))
	site_b.record_withdrawn_for_site(u2, &"stone", 1)
	assert_eq(site_b.get_transit_claim_for_unit(u2), {&"stone": 1})
	var conflict_res: Dictionary = site_a.prepare_reserved_withdrawal(u2, pile_w.pile_id, &"wood", 1, &"op_c1", &"lot_c1")
	assert_false(bool(conflict_res["ok"]))
	assert_eq(String(conflict_res["reason"]), "conflicting_site_claims")

	# Detect physical/lot mismatch (`unreconciled_cargo`): inject raw _amounts mismatch into load2
	load2._amounts[&"wood"] = 9
	var unrec_res: Dictionary = site_a.prepare_reserved_withdrawal(u2, pile_w.pile_id, &"wood", 1, &"op_c2", &"lot_c2")
	assert_false(bool(unrec_res["ok"]))
	assert_eq(String(unrec_res["reason"]), "unreconciled_cargo")

	# Detect own-site claim/lot mismatch (`unreconciled_site_claim`):
	# Withdraw 1 wood from site_a reservation so site_a records claim, while u3 carries only FREE_GATHERED wood:
	var u3: Unit = _spawn_unit(host, "SelfDesyncUnit", &"self_desync", 20)
	var load3: UnitCarryLoad = u3.get_carry_load()
	assert_true(bool(wood_source.transfer_to_carry_load_with_provenance(load3, &"op_f_w3", &"lot_f_w3", 1)["ok"]))
	assert_true(manager.withdraw_reserved_from_pile(pile_w.pile_id, site_a.reservation_id, &"wood", 1))
	site_a.record_withdrawn_for_site(u3, &"wood", 1)
	assert_eq(site_a.get_transit_claim_for_unit(u3), {&"wood": 1})
	var self_desync_res: Dictionary = site_a.prepare_reserved_withdrawal(u3, pile_w.pile_id, &"wood", 1, &"op_c3", &"lot_c3")
	assert_false(bool(self_desync_res["ok"]))
	assert_eq(String(self_desync_res["reason"]), "unreconciled_site_claim")

	spy.cleanup()


func test_04_site_states_capacity_weights_and_invalid_or_conflicting_ids() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 8, slots[0])
	var pile_s: GroundResourcePile = manager.try_create_pile_at(&"stone", 6, slots[1])
	var pile_f: GroundResourcePile = manager.try_create_pile_at(&"food", 4, slots[2])
	assert_not_null(pile_w)
	assert_not_null(pile_s)
	assert_not_null(pile_f)

	var site_def: BuildingDefinition = _make_building_def(&"c1_state_def", {&"wood": 6, &"stone": 4})
	var site: ConstructionSite = cm.try_create_site_from_placement(site_def, Vector3(8.0, 0.0, 8.0))["site"] as ConstructionSite

	# Small-capacity unit (3 kg): wood=1kg, stone=2kg
	var u1: Unit = _spawn_unit(host, "SmallUnit", &"small_unit", 3)
	var load1: UnitCarryLoad = u1.get_carry_load()
	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site], [load1])

	# 1. Capacity failures (wood 4 > 3 kg; stone 2 -> 4 > 3 kg)
	var cap_w: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 4, &"op_cap_w", &"lot_cap_w")
	assert_false(bool(cap_w["ok"]))
	assert_eq(String(cap_w["reason"]), "capacity")
	var cap_s: Dictionary = site.prepare_reserved_withdrawal(u1, pile_s.pile_id, &"stone", 2, &"op_cap_s", &"lot_cap_s")
	assert_false(bool(cap_s["ok"]))
	assert_eq(String(cap_s["reason"]), "capacity")

	# Raise capacity for remaining checks:
	load1.set_base_capacity(20)
	spy.events.clear()

	# 2. Resource & weight mismatches
	var wrong_res: Dictionary = site.prepare_reserved_withdrawal(u1, pile_f.pile_id, &"food", 1, &"op_food", &"lot_food")
	assert_false(bool(wrong_res["ok"]))
	assert_eq(String(wrong_res["reason"]), "resource_not_required")

	var wrong_pile_res: Dictionary = site.prepare_reserved_withdrawal(u1, pile_s.pile_id, &"wood", 1, &"op_m1", &"lot_m1")
	assert_false(bool(wrong_pile_res["ok"]))
	assert_eq(String(wrong_pile_res["reason"]), "pile_resource_mismatch")

	var wrong_opt_w: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_w1", &"lot_w1", {"unit_weight": 9})
	assert_false(bool(wrong_opt_w["ok"]))
	assert_eq(String(wrong_opt_w["reason"]), "resource_or_weight_mismatch")

	# Separate unit holding wood with incompatible registered weight in carry load (1 != WOOD_BASE.unit_weight 2):
	var u_bad_w: Unit = _spawn_unit(host, "BadWeightUnit", &"bad_weight_unit", 20)
	assert_true(bool(u_bad_w.get_carry_load().add_with_provenance(&"op_bw", &"lot_bw", &"wood", 1, 1, CarryProvenanceLedger.FREE_GATHERED)["ok"]))
	var bad_load_w: Dictionary = site.prepare_reserved_withdrawal(u_bad_w, pile_w.pile_id, &"wood", 1, &"op_bw2", &"lot_bw2")
	assert_false(bool(bad_load_w["ok"]))
	assert_eq(String(bad_load_w["reason"]), "resource_or_weight_mismatch")

	# Preload wood with matching WOOD_BASE.unit_weight on u1 to test operation/lot conflicts
	assert_true(bool(load1.add_with_provenance(&"op_w_seed", &"lot_w_seed", &"wood", WOOD_BASE.unit_weight, 1, CarryProvenanceLedger.FREE_GATHERED)["ok"]))
	# Attempting to register op_w_seed again -> operation_conflict; reusing lot_w_seed -> duplicate_lot
	var op_reuse: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_w_seed", &"lot_new")
	assert_false(bool(op_reuse["ok"]))
	assert_eq(String(op_reuse["reason"]), "operation_conflict")
	var lot_reuse: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_new", &"lot_w_seed")
	assert_false(bool(lot_reuse["ok"]))
	assert_eq(String(lot_reuse["reason"]), "duplicate_lot")

	# Invalid inputs:
	assert_eq(String(site.prepare_reserved_withdrawal(null, pile_w.pile_id, &"wood", 1, &"o", &"l")["reason"]), "invalid_unit")
	assert_eq(String(site.prepare_reserved_withdrawal(u1, 0, &"wood", 1, &"o", &"l")["reason"]), "invalid_pile")
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 0, &"o", &"l")["reason"]), "invalid_amount")
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", -2, &"o", &"l")["reason"]), "invalid_amount")
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"", &"l")["reason"]), "invalid_operation")
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"o", &"  ")["reason"]), "invalid_lot")
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"o", &"l", {"site_id": &"other"})["reason"]), "site_mismatch")
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"o", &"l", {"generation": 99})["reason"]), "invalid_generation")
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"o", &"l", {"unit_id": &"wrong"})["reason"]), "unit_mismatch")

	# Conflicting prior_plan checks:
	var valid_p: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 2, &"op_ok_1", &"lot_ok_1")
	assert_true(bool(valid_p["ok"]))
	var conflict_amt: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_ok_1", &"lot_ok_1", {"prior_plan": valid_p})
	assert_false(bool(conflict_amt["ok"]))
	assert_eq(String(conflict_amt["reason"]), "operation_conflict")
	var conflict_lot_p: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 2, &"op_ok_2", &"lot_ok_1", {"prior_plan": valid_p})
	assert_false(bool(conflict_lot_p["ok"]))
	assert_eq(String(conflict_lot_p["reason"]), "duplicate_lot")

	# Ambiguous unit identity: two distinct units sharing same provenance unit_id on same site
	var u_dup: Unit = _spawn_unit(host, "DupUnit", &"small_unit", 20)
	site._pending_pickups[u_dup.get_instance_id()] = {"unit": u_dup, "pile_id": pile_w.pile_id, "resource_id": &"wood", "amount": 1}
	var ambig_res: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_amb", &"lot_amb")
	assert_false(bool(ambig_res["ok"]))
	assert_eq(String(ambig_res["reason"]), "ambiguous_unit_identity")
	site._pending_pickups.erase(u_dup.get_instance_id())

	# Claim eligibility checks: pending pickup cap/pile mismatch, peer pending claim headroom, and BUILDER role
	var u_other: Unit = _spawn_unit(host, "PeerUnit", &"peer_unit", 20)
	assert_eq(site.claim_pickup(u_other, pile_w.pile_id, &"wood", 4), 4)
	# pile_w has 6 reserved for site; u_other holds pending claim for 4 -> u1 requesting 3 exceeds available 2
	var peer_cap_res: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_elig1", &"lot_elig1")
	assert_false(bool(peer_cap_res["ok"]))
	assert_eq(String(peer_cap_res["reason"]), "claim_not_eligible")
	site.release_pickup_claim(u_other)

	# Pending pickup owned by u1 with amount < requested or mismatched pile:
	assert_eq(site.claim_pickup(u1, pile_w.pile_id, &"wood", 1), 1)
	var under_pending: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 2, &"op_elig2", &"lot_elig2")
	assert_false(bool(under_pending["ok"]))
	assert_eq(String(under_pending["reason"]), "claim_not_eligible")
	site.release_pickup_claim(u1)

	# Worker registered with BUILDER role cannot withdraw reserved cargo as transporter:
	var dummy_order := UnitOrder.new()
	dummy_order.mark_running()
	site._assigned_workers[u1.get_instance_id()] = {
		"unit": u1,
		"order": dummy_order,
		"role": ConstructionSite.WorkerRole.BUILDER,
		"force_transporter": false,
		"solo_promoted_builder": false,
	}
	site._worker_order_ids.append(u1.get_instance_id())
	var builder_role_res: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_elig3", &"lot_elig3")
	assert_false(bool(builder_role_res["ok"]))
	assert_eq(String(builder_role_res["reason"]), "claim_not_eligible")
	site._assigned_workers.erase(u1.get_instance_id())
	site._worker_order_ids.erase(u1.get_instance_id())

	# Indirect getter side-effect check: stale worker left in _assigned_workers must NOT trigger _prune_stale_state()
	var u_stale: Unit = _spawn_unit(host, "StaleWorker", &"stale_worker", 20)
	host.remove_child(u_stale)
	var stale_uid: int = u_stale.get_instance_id()
	site._assigned_workers[stale_uid] = {"unit": u_stale, "order": null, "role": ConstructionSite.WorkerRole.BUILDER}
	site._worker_order_ids.append(stale_uid)
	spy.events.clear()
	var stale_part_res: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_stale_p", &"lot_stale_p")
	assert_false(bool(stale_part_res["ok"]))
	assert_eq(String(stale_part_res["reason"]), "stale_site_participants")
	assert_true(site._assigned_workers.has(stale_uid))
	assert_eq(spy.events, [])
	site._assigned_workers.erase(stale_uid)
	site._worker_order_ids.erase(stale_uid)
	u_stale.free()

	# Reentrancy / busy rejections:
	site._is_preparing_or_transacting = true
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_busy1", &"lot_busy1")["reason"]), "busy")
	site._is_preparing_or_transacting = false
	load1._provenance_busy = true
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_busy2", &"lot_busy2")["reason"]), "busy")
	load1._provenance_busy = false
	manager.begin_batch()
	assert_eq(String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_busy3", &"lot_busy3")["reason"]), "busy")
	manager.end_batch(true)

	# 3. Site non-ACTIVE states (COMPLETING, COMPLETION_FAILED_RETRYABLE, COMPLETION_BLOCKED_ERROR, COMPLETED)
	spy.events.clear()
	for bad_state: ConstructionSite.SiteState in [
		ConstructionSite.SiteState.COMPLETING,
		ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE,
		ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR,
		ConstructionSite.SiteState.COMPLETED,
	]:
		site._site_state = bad_state
		var state_res: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_st", &"lot_st")
		assert_false(bool(state_res["ok"]))
		assert_eq(String(state_res["reason"]), "site_not_active")
	site._site_state = ConstructionSite.SiteState.ACTIVE
	assert_eq(spy.events, [])
	spy.cleanup()


func test_05_idempotent_repeated_preparation_stale_revisions_and_aba() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 10, slots[0])
	var pile_s: GroundResourcePile = manager.try_create_pile_at(&"stone", 6, slots[1])
	assert_not_null(pile_w)
	assert_not_null(pile_s)

	var site_def: BuildingDefinition = _make_building_def(&"c1_aba_def", {&"wood": 6, &"stone": 4})
	var site: ConstructionSite = cm.try_create_site_from_placement(site_def, Vector3(8.0, 0.0, 8.0))["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "AbaWorker", &"aba_worker", 20)
	var load1: UnitCarryLoad = u1.get_carry_load()
	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site], [load1])

	var snap_init: Dictionary = _snapshot_all(manager, inventory, [site], [load1])

	# Idempotent repeated preparation produces equal detached plans with zero side effects:
	var p1: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_idemp", &"lot_idemp")
	var p2: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_idemp", &"lot_idemp")
	var p3: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_idemp", &"lot_idemp", {"prior_plan": p1})
	assert_true(bool(p1["ok"]))
	assert_eq(p2, p1)
	assert_eq(p3, p1)
	assert_true(bool(site.validate_reserved_withdrawal_plan(p1)["ok"]))
	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site], [load1]), snap_init)

	# ABA Scenario 1: UnitCarryLoad capacity modified 10 -> 20 back to original value
	load1.set_base_capacity(10)
	load1.set_base_capacity(20)
	var val_aba_cap: Dictionary = site.validate_reserved_withdrawal_plan(p1)
	assert_false(bool(val_aba_cap["ok"]))
	assert_eq(String(val_aba_cap["reason"]), "stale_revision")
	assert_eq(String(val_aba_cap["dependency"]), "revisions")

	# ABA Scenario 2: Reservation released & re-complemented back to exact same {wood: 6, stone: 4}
	var p_aba_res: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_aba2", &"lot_aba2")
	assert_true(bool(p_aba_res["ok"]))
	assert_true(inventory.release_batch(site.reservation_id, {&"wood": 1}))
	assert_true(inventory.complement_reservation(site.reservation_id, {&"wood": 1}))
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 6)
	var val_aba_res: Dictionary = site.validate_reserved_withdrawal_plan(p_aba_res)
	assert_false(bool(val_aba_res["ok"]))
	assert_eq(String(val_aba_res["reason"]), "stale_revision")

	# ABA Scenario 3: GroundResourcePile node mutated directly & restored back to identical physical values
	var p_aba_pile: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_aba3", &"lot_aba3")
	assert_true(bool(p_aba_pile["ok"]))
	pile_w.apply_state(9, 0.0, 0.0)
	pile_w.apply_state(10, 0.0, 0.0)
	var val_aba_pile: Dictionary = site.validate_reserved_withdrawal_plan(p_aba_pile)
	assert_false(bool(val_aba_pile["ok"]))
	assert_eq(String(val_aba_pile["reason"]), "stale_revision")

	# ABA Scenario 4: ConstructionSite pending pickup claimed and released back to empty
	var p_aba_site: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_aba4", &"lot_aba4")
	assert_true(bool(p_aba_site["ok"]))
	assert_eq(site.claim_pickup(u1, pile_w.pile_id, &"wood", 2), 2)
	site.release_pickup_claim(u1)
	var val_aba_site: Dictionary = site.validate_reserved_withdrawal_plan(p_aba_site)
	assert_false(bool(val_aba_site["ok"]))
	assert_eq(String(val_aba_site["reason"]), "stale_revision")

	# Tampered plan payload rejected cleanly:
	var p_fresh: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_tamper", &"lot_tamper")
	assert_true(bool(p_fresh["ok"]))
	var tampered: Dictionary = p_fresh.duplicate(true)
	(tampered["pile_plan"]["after"] as Dictionary)["pile_amount"] = 999
	var val_tampered: Dictionary = site.validate_reserved_withdrawal_plan(tampered)
	assert_false(bool(val_tampered["ok"]))
	assert_eq(String(val_tampered["reason"]), "tampered_or_stale_plan")

	# Ensure valid plan validation remains side-effect-free on fresh plan:
	spy.events.clear()
	var snap_before_val: Dictionary = _snapshot_all(manager, inventory, [site], [load1])
	assert_true(bool(site.validate_reserved_withdrawal_plan(p_fresh)["ok"]))
	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site], [load1]), snap_before_val)

	# Silent exposure advance via step_decay (0 units lost, 0 signals) still invalidates revision:
	(fx["time"] as SimulatedWorldTimeProvider).advance(10.0)
	assert_eq(manager.step_decay(), {})
	assert_eq(pile_w.amount, 10)
	assert_eq(spy.events, [])
	var val_silent_decay: Dictionary = site.validate_reserved_withdrawal_plan(p_fresh)
	assert_false(bool(val_silent_decay["ok"]))
	assert_eq(String(val_silent_decay["reason"]), "stale_revision")
	spy.cleanup()
