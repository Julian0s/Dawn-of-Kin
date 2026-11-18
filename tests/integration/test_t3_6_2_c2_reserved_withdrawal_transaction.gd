extends TestCase
## Adversarial integration tests for T3.6.2-C2:
## ReservedWithdrawalCoordinator atomic reserved withdrawal transaction:
## pile + ledger reservation -> carry load + SITE_RESERVED provenance -> site transit claim & pending pickup.
## Covers all 30 mandatory scenarios: happy paths, mixed carry loads, capacity/reach/weight rejections,
## multi-stage fault injection rollbacks (including exhausted pile deferral), idempotent replay & conflicts,
## ABA/peer invalidation, signal-callback reentrancy, world/region/generation mismatches, legacy bypass
## blocking on provenance loads, and legacy flow regression when provenance is disabled.

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


func _make_fixture(max_pile_amount: int = 0, parent: Node = null, region: StringName = &"c2_region") -> Dictionary:
	if parent == null:
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		add_test_child(viewport)
		parent = viewport
	var host := Node3D.new()
	parent.add_child(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"c2_test_camp"
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
	cm.configure(sites_root, inventory, defs, zone, null, region)

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


func _assign_transporter_and_claim(
	site: ConstructionSite,
	unit: Unit,
	pile: GroundResourcePile,
	resource_id: StringName,
	claim_amount: int,
	place_at_pile: bool = true
) -> ConstructOrder:
	var order := ConstructOrder.new(site, null, true)
	order.mark_running()
	unit._current_order = order
	var role: ConstructionSite.WorkerRole = site.register_worker(unit, order, true)
	assert_eq(role, ConstructionSite.WorkerRole.TRANSPORTER)
	if place_at_pile and pile != null:
		unit.global_position = pile.global_position + Vector3(0.4, 0.0, 0.0)
	var claimed: int = site.claim_pickup(unit, pile.pile_id, resource_id, claim_amount)
	assert_eq(claimed, claim_amount)
	return order


func _copy_transit_claims(s: ConstructionSite) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in s._transit_claims.keys():
		var claim: Dictionary = s._transit_claims[k] as Dictionary
		out[k] = (claim.get("amounts", {}) as Dictionary).duplicate(true)
	return out


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
			"load_conn_count": cl.load_changed.get_connections().size(),
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


func test_01_02_03_04_happy_paths_partial_site_exhaustion_pile_exhaustion_empty_load() -> void:
	# Scenarios 1, 2, 3, 4
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	# Pile W1: 10 wood; Site A takes 6, leaving 2 reserved for Site B and 2 free!
	var pile_w1: GroundResourcePile = manager.try_create_pile_at(&"wood", 10, slots[0])
	# Pile S1: 4 stone; Site A takes all 4, exhausting physical Pile S1 to 0!
	var pile_s1: GroundResourcePile = manager.try_create_pile_at(&"stone", 4, slots[1])
	assert_not_null(pile_w1)
	assert_not_null(pile_s1)

	var site_a: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_site_a", {&"wood": 6, &"stone": 4}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite
	var site_b: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_site_b", {&"wood": 2}),
		Vector3(14.0, 0.0, 8.0)
	)["site"] as ConstructionSite
	assert_eq(manager.get_pile_reservations(pile_w1.pile_id), {site_a.reservation_id: 6, site_b.reservation_id: 2})
	assert_eq(manager.get_pile_reservations(pile_s1.pile_id), {site_a.reservation_id: 4})

	# Scenario 1 & 4: Partial withdrawal into empty provenance load (3 of 6 wood)
	var u1: Unit = _spawn_unit(host, "W1", &"w1", 40)
	var load1: UnitCarryLoad = u1.get_carry_load()
	_assign_transporter_and_claim(site_a, u1, pile_w1, &"wood", 6)

	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site_a, site_b], [load1])

	var res1: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w1.pile_id, &"wood", 3, &"op_1", &"lot_1")
	assert_true(bool(res1["ok"]))
	assert_false(bool(res1["replayed"]))
	assert_eq(int(res1["withdrawn"]), 3)
	assert_eq(int(res1["committed_amount"]), 3)
	assert_eq(pile_w1.amount, 7)
	assert_eq(manager.get_pile_reservations(pile_w1.pile_id), {site_a.reservation_id: 3, site_b.reservation_id: 2})
	assert_eq(load1.get_amount(&"wood"), 3)
	assert_eq(load1.get_current_weight(), 3 * WOOD_BASE.unit_weight)
	assert_true(load1.validate_provenance())
	assert_eq(site_a.get_transit_claim_for_unit(u1), {&"wood": 3})
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 3)
	assert_eq(site_a.get_in_transit_amount(&"wood"), 3)
	assert_false(site_a._pending_pickups.has(u1.get_instance_id()))
	assert_true(site_a.verify_accounting_invariant())
	assert_true(coord.has_receipt(&"op_1"))
	assert_true(spy.events.has("mgr_res"))
	assert_true(spy.events.has("inv_res"))
	assert_true(spy.events.has("mgr_storage"))
	assert_true(spy.events.has("inv_changed"))
	assert_true(spy.events.has("load_changed"))
	assert_eq(spy.events.count("site_state:" + String(site_a.site_id)), 1)
	assert_false(spy.events.has("site_state:" + String(site_b.site_id)))

	# Scenario 2: Remaining 3 of Site A's reservation on Pile W1, preserving Site B (2) & free stock (2)
	spy.events.clear()
	assert_eq(site_a.claim_pickup(u1, pile_w1.pile_id, &"wood", 3), 3)
	var res2: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w1.pile_id, &"wood", 3, &"op_2", &"lot_2")
	assert_true(bool(res2["ok"]))
	assert_eq(int(res2["withdrawn"]), 3)
	assert_eq(pile_w1.amount, 4)
	assert_eq(manager.get_pile_reservations(pile_w1.pile_id), {site_b.reservation_id: 2})
	assert_eq(manager.get_pile_available_amount(pile_w1.pile_id), 2)
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(site_a.get_in_transit_amount(&"wood"), 6)
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 2)
	assert_eq(load1.get_amount(&"wood"), 6)

	# Scenario 3: Physical pile exhaustion (4 stone -> 0, node removed & freed only at commit)
	spy.events.clear()
	var pile_s1_id: int = pile_s1.pile_id
	_assign_transporter_and_claim(site_a, u1, pile_s1, &"stone", 4)
	var res3: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_s1_id, &"stone", 4, &"op_3", &"lot_3")
	assert_true(bool(res3["ok"]))
	assert_eq(int(res3["withdrawn"]), 4)
	assert_null(manager.get_pile_by_id(pile_s1_id))
	assert_false(is_instance_valid(pile_s1))
	assert_eq(load1.get_amount(&"stone"), 4)
	assert_eq(load1.get_current_weight(), 6 * WOOD_BASE.unit_weight + 4 * STONE_BASE.unit_weight)
	assert_eq(site_a.get_transit_claim_for_unit(u1), {&"wood": 6, &"stone": 4})
	assert_true(load1.validate_provenance())
	assert_true(site_a.verify_accounting_invariant())
	spy.cleanup()


func test_05_06_07_08_mixed_carry_loads_free_and_multi_site_preservation() -> void:
	# Scenarios 5, 6, 7, 8
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 10, slots[0])
	var pile_s: GroundResourcePile = manager.try_create_pile_at(&"stone", 6, slots[1])

	var site_a: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_mix_a", {&"wood": 6}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite
	var site_b: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_mix_b", {&"stone": 4}),
		Vector3(14.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "MixedU1", &"mixed_u1", 50)
	var load1: UnitCarryLoad = u1.get_carry_load()

	# Gather FREE_GATHERED wood (2) and FREE_GATHERED food (1)
	var wood_src := ResourceSource.new()
	host.add_child(wood_src)
	wood_src.configure(&"src_w", WOOD_BASE.duplicate(), 5, 5, 2)
	assert_true(bool(wood_src.transfer_to_carry_load_with_provenance(load1, &"fg_w", &"lot_fg_w", 2)["ok"]))

	var food_src := ResourceSource.new()
	host.add_child(food_src)
	food_src.configure(&"src_f", FOOD_BASE.duplicate(), 5, 5, 2)
	assert_true(bool(food_src.transfer_to_carry_load_with_provenance(load1, &"fg_f", &"lot_fg_f", 1)["ok"]))

	# Scenario 5 & 6: Add SITE_RESERVED wood (2) to load containing FREE_GATHERED wood & food
	_assign_transporter_and_claim(site_a, u1, pile_w, &"wood", 2)
	var r_a1: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w.pile_id, &"wood", 2, &"op_a1", &"lot_a1")
	assert_true(bool(r_a1["ok"]))
	assert_eq(load1.get_amount(&"wood"), 4)
	assert_eq(load1.get_amount(&"food"), 1)
	assert_eq(site_a.get_transit_claim_for_unit(u1), {&"wood": 2})

	# Scenario 7: Second withdrawal of SITE_RESERVED wood (3) for SAME site & SAME generation
	assert_eq(site_a.claim_pickup(u1, pile_w.pile_id, &"wood", 3), 3)
	var r_a2: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w.pile_id, &"wood", 3, &"op_a2", &"lot_a2")
	assert_true(bool(r_a2["ok"]))
	assert_eq(load1.get_amount(&"wood"), 7) # 2 FREE + 2 SITE_A + 3 SITE_A
	assert_eq(site_a.get_transit_claim_for_unit(u1), {&"wood": 5})

	# Scenario 8: Unit now withdraws SITE_RESERVED stone (3) for Site B, keeping Site A & FREE intact
	_assign_transporter_and_claim(site_b, u1, pile_s, &"stone", 3)
	var spy := SignalSpy.new()
	spy.watch_all(manager, fx["inventory"], [site_a, site_b], [load1])
	var r_b1: Dictionary = coord.execute_reserved_withdrawal(site_b, u1, pile_s.pile_id, &"stone", 3, &"op_b1", &"lot_b1")
	assert_true(bool(r_b1["ok"]))
	assert_eq(site_a.get_transit_claim_for_unit(u1), {&"wood": 5})
	assert_eq(site_b.get_transit_claim_for_unit(u1), {&"stone": 3})
	assert_eq(load1.get_amount(&"wood"), 7)
	assert_eq(load1.get_amount(&"stone"), 3)
	assert_eq(load1.get_amount(&"food"), 1)
	assert_true(load1.validate_provenance())
	assert_true(site_a.verify_accounting_invariant())
	assert_true(site_b.verify_accounting_invariant())
	assert_false(spy.events.has("site_state:" + String(site_a.site_id)))
	assert_eq(spy.events.count("site_state:" + String(site_b.site_id)), 1)
	spy.cleanup()


func test_09_10_11_12_13_14_precondition_rejections_zero_mutations_zero_signals() -> void:
	# Scenarios 9, 10, 11, 12, 13, 14
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 6, slots[0])
	var pile_w2: GroundResourcePile = manager.try_create_pile_at(&"wood", 4, slots[1])
	assert_not_null(pile_w)
	assert_not_null(pile_w2)

	var site_b: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_rej_b", {&"wood": 2}),
		Vector3(14.0, 0.0, 8.0)
	)["site"] as ConstructionSite
	# pile_w now has 2 reserved for site_b, 4 free. Add second stone pile exclusively for site_b or separate stone pile:
	var site_a: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_rej_a", {&"wood": 6}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite
	# site_a has 4 wood reserved on pile_w + 2 wood reserved on pile_w2 (total need = 6)
	var pile_s_b: GroundResourcePile = manager.try_create_pile_at(&"stone", 3, slots[2])
	var site_c: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_rej_c", {&"stone": 3}),
		Vector3(18.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	# Small unit with 4 kg capacity (wood = 2 kg/u -> max 2 wood)
	var u1: Unit = _spawn_unit(host, "RejU1", &"rej_u1", 4)
	var load1: UnitCarryLoad = u1.get_carry_load()
	_assign_transporter_and_claim(site_a, u1, pile_w, &"wood", 5)

	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site_a, site_b, site_c], [load1])
	var before: Dictionary = _snapshot_all(manager, inventory, [site_a, site_b, site_c], [load1])

	# Scenario 9: requested_amount (5) > reserved_for_site_on_pile (4 on pile_w, though site_a needs 6 total)
	var r_over_res: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w.pile_id, &"wood", 5, &"op_r9", &"lot_r9")
	assert_false(bool(r_over_res["ok"]))
	assert_eq(String(r_over_res["reason"]), "insufficient_pile_reservation")
	assert_eq(_snapshot_all(manager, inventory, [site_a, site_b, site_c], [load1]), before)
	assert_eq(spy.events, [])

	# Scenario 10: requested_amount > pile.amount (simulate pile physical < requested with larger claim/cap)
	var prev_rev: int = pile_w.get_transaction_revision()
	pile_w.amount = 3
	var r_over_phys: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w.pile_id, &"wood", 4, &"op_r10", &"lot_r10")
	assert_false(bool(r_over_phys["ok"]))
	assert_true(String(r_over_phys["reason"]) in ["unreconciled_pile_reservations", "insufficient_pile_physical"])
	pile_w.amount = 6
	pile_w._transaction_revision = prev_rev
	assert_eq(_snapshot_all(manager, inventory, [site_a, site_b, site_c], [load1]), before)
	assert_eq(spy.events, [])

	# Scenario 11: Pile reserved exclusively for site_b, requested by site_a (pile_s_b reserved strictly for site_c!)
	site_a._required_amounts[&"stone"] = 2
	site_a._delivered_buffer[&"stone"] = 0
	site_a._consumed_materials[&"stone"] = 0
	site_a.claim_pickup(u1, pile_s_b.pile_id, &"stone", 2, 3)
	var r_other_site: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_s_b.pile_id, &"stone", 2, &"op_r11", &"lot_r11")
	assert_false(bool(r_other_site["ok"]))
	assert_eq(String(r_other_site["reason"]), "reservation_belongs_to_other_site")
	site_a._required_amounts.erase(&"stone")
	site_a._delivered_buffer.erase(&"stone")
	site_a._consumed_materials.erase(&"stone")

	# Scenario 12: Carry capacity insufficient (cap 4 kg, request 3 wood = 6 kg)
	assert_eq(site_a.claim_pickup(u1, pile_w.pile_id, &"wood", 3), 3)
	var r_cap: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w.pile_id, &"wood", 3, &"op_r12", &"lot_r12")
	assert_false(bool(r_cap["ok"]))
	assert_eq(String(r_cap["reason"]), "capacity")

	# Scenario 13: Divergent unit_weight (via options AND via mismatched weight in carry_load)
	assert_eq(site_a.claim_pickup(u1, pile_w.pile_id, &"wood", 1), 1)
	var r_wt_opt: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w.pile_id, &"wood", 1, &"op_r13a", &"lot_r13a", {"unit_weight": 9})
	assert_false(bool(r_wt_opt["ok"]))
	assert_eq(String(r_wt_opt["reason"]), "resource_or_weight_mismatch")

	var u_bad_w: Unit = _spawn_unit(host, "BadW", &"bad_w", 20, pile_w.global_position)
	assert_true(bool(u_bad_w.get_carry_load().add_with_provenance(&"op_bw_seed", &"lot_bw_seed", &"wood", 1, 1, CarryProvenanceLedger.FREE_GATHERED)["ok"]))
	_assign_transporter_and_claim(site_a, u_bad_w, pile_w, &"wood", 1, true)
	var r_wt_load: Dictionary = coord.execute_reserved_withdrawal(site_a, u_bad_w, pile_w.pile_id, &"wood", 1, &"op_r13b", &"lot_r13b")
	assert_false(bool(r_wt_load["ok"]))
	assert_eq(String(r_wt_load["reason"]), "resource_or_weight_mismatch")
	site_a.release_pickup_claim(u_bad_w)
	site_a.unregister_worker(u_bad_w)

	# Scenario 14: Unit out of physical pile reach (initial call AND moved away after prepare)
	u1.global_position = pile_w.global_position + Vector3(0.4, 0.0, 0.0)
	var prep_at_pile: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_r14", &"lot_r14")
	assert_true(bool(prep_at_pile["ok"]))
	# Now move u1 horizontally out of reach AND test vertical out of reach:
	u1.global_position = pile_w.global_position + Vector3(10.0, 0.0, 0.0)
	spy.events.clear()
	var snap_reach: Dictionary = _snapshot_all(manager, inventory, [site_a, site_b, site_c], [load1])
	var r_far: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w.pile_id, &"wood", 1, &"op_r14a", &"lot_r14a")
	assert_false(bool(r_far["ok"]))
	assert_eq(String(r_far["reason"]), "out_of_pile_reach")
	var r_commit_far: Dictionary = coord.commit_prepared_withdrawal(site_a, u1, prep_at_pile)
	assert_false(bool(r_commit_far["ok"]))
	assert_eq(String(r_commit_far["reason"]), "out_of_pile_reach")
	u1.global_position = pile_w.global_position + Vector3(0.2, 2.0, 0.0)
	var r_high: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w.pile_id, &"wood", 1, &"op_r14b", &"lot_r14b")
	assert_false(bool(r_high["ok"]))
	assert_eq(String(r_high["reason"]), "out_of_pile_reach")
	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site_a, site_b, site_c], [load1]), snap_reach)
	assert_false(coord.has_receipt(&"op_r14a"))
	assert_false(coord.has_receipt(&"op_r14"))
	spy.cleanup()


func _assert_snapshot_data_equal_modulo_revisions(after: Dictionary, before: Dictionary) -> void:
	# State fields (amounts, ledger, pending, transit, buffer, consumed) must match identically,
	# while revisions may advance monotonically against ABA.
	assert_eq(after["ledger"], before["ledger"])
	assert_eq(after["decayed"], before["decayed"])
	assert_eq(after["piles"].size(), before["piles"].size())
	for i: int in range(before["piles"].size()):
		var pb: Dictionary = before["piles"][i] as Dictionary
		var pa: Dictionary = after["piles"][i] as Dictionary
		assert_eq(pa["id"], pb["id"])
		assert_eq(pa["res"], pb["res"])
		assert_eq(pa["amount"], pb["amount"])
		assert_eq(pa["tier"], pb["tier"])
		assert_eq(pa["meshes"], pb["meshes"])
	assert_eq(after["sites"].size(), before["sites"].size())
	for i: int in range(before["sites"].size()):
		var sb: Dictionary = before["sites"][i] as Dictionary
		var sa: Dictionary = after["sites"][i] as Dictionary
		assert_eq(sa["pending"], sb["pending"])
		assert_eq(sa["transit"], sb["transit"])
		assert_eq(sa["transit_keys"], sb["transit_keys"])
		assert_eq(sa["buffer"], sb["buffer"])
		assert_eq(sa["consumed"], sb["consumed"])
	assert_eq(after["loads"].size(), before["loads"].size())
	for i: int in range(before["loads"].size()):
		var lb: Dictionary = before["loads"][i] as Dictionary
		var la: Dictionary = after["loads"][i] as Dictionary
		assert_eq(la["weight"], lb["weight"])
		assert_eq(la["amounts"], lb["amounts"])
		assert_eq(la["prov"], lb["prov"])
		assert_eq(la["load_conn_count"], lb["load_conn_count"])


func test_15_16_17_18_19_23_fault_injection_rollbacks_and_retry_after_abort() -> void:
	# Scenarios 15, 16, 17, 18, 19 (with pile exhaustion + corruption invariant fail), and 23
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	# Exact 5 wood on Pile W (so withdrawing 5 hits full physical pile exhaustion case in Point 5!)
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 5, slots[0])
	assert_not_null(pile_w)

	var site: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_rb_site", {&"wood": 5}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "RbWorker", &"rb_worker", 30)
	var load1: UnitCarryLoad = u1.get_carry_load()
	_assign_transporter_and_claim(site, u1, pile_w, &"wood", 5)

	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site], [load1])

	var stages: Array[String] = [
		"before_pile_deduction",
		"after_pile_deduction",
		"after_carry_add",
		"after_claim_update",
		"during_final_invariants",
	]

	for stage: String in stages:
		spy.events.clear()
		var before_snap: Dictionary = _snapshot_all(manager, inventory, [site], [load1])
		var seen_partial: Dictionary = {}
		coord.fault_injection_hook = func(hit_stage: String, ctx: Dictionary) -> Variant:
			if hit_stage == stage:
				if stage == "after_pile_deduction":
					# Verify pile amount reached 0 transiently, yet node is STILL alive before commit boundary!
					seen_partial["pile_valid"] = is_instance_valid(ctx["pile"])
					seen_partial["pile_amt"] = (ctx["pile"] as GroundResourcePile).amount
				return false
			return true

		# Test reusing the SAME op_abort and lot_abort across aborts -> Scenario 23 proves aborted IDs aren't leaked!
		var res: Dictionary = coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 5, &"op_retryable", &"lot_retryable")
		assert_false(bool(res["ok"]), "Expected abort at stage " + stage)
		assert_eq(String(res["reason"]), "aborted_" + stage)
		assert_eq(int(res["withdrawn"]), 0)
		assert_eq(spy.events, [], "Aborted transaction must emit zero signals at stage " + stage)
		assert_false(coord.has_receipt(&"op_retryable"))
		assert_false(coord._last_authority().committed_lots.has(&"lot_retryable"))
		assert_true(is_instance_valid(pile_w), "Exhausted pile node must stay alive & valid on rollback at " + stage)
		assert_true(pile_w.is_inside_tree())
		assert_eq(manager.get_pile_by_id(pile_w.pile_id), pile_w)
		assert_eq(pile_w.amount, 5)
		assert_eq(manager.get_pile_reservations(pile_w.pile_id), {site.reservation_id: 5})
		var after_snap: Dictionary = _snapshot_all(manager, inventory, [site], [load1])
		_assert_snapshot_data_equal_modulo_revisions(after_snap, before_snap)
		if stage == "after_pile_deduction":
			assert_true(bool(seen_partial.get("pile_valid", false)))
			assert_eq(int(seen_partial.get("pile_amt", -1)), 0)

	# Scenario 19b: Real post-mutation invariant failure inside during_final_invariants (corrupt carry amount) triggers full rollback!
	spy.events.clear()
	var before_corr: Dictionary = _snapshot_all(manager, inventory, [site], [load1])
	coord.fault_injection_hook = func(hit_stage: String, ctx: Dictionary) -> Variant:
		if hit_stage == "during_final_invariants":
			(ctx["carry_load"] as UnitCarryLoad)._amounts[&"wood"] = 99
		return true # Hook returns true; coordinator's invariant check must detect corruption and roll back!
	var res_corr: Dictionary = coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 5, &"op_retryable", &"lot_retryable")
	assert_false(bool(res_corr["ok"]))
	assert_eq(String(res_corr["reason"]), "invariant_violation_aborted")
	assert_eq(spy.events, [])
	assert_false(coord.has_receipt(&"op_retryable"))
	assert_true(is_instance_valid(pile_w))
	assert_eq(pile_w.amount, 5)
	_assert_snapshot_data_equal_modulo_revisions(_snapshot_all(manager, inventory, [site], [load1]), before_corr)

	# Scenario 18b: Rollback at after_claim_update when unit ALREADY had a prior claim on the SAME site
	coord.fault_injection_hook = Callable()
	assert_eq(site.claim_pickup(u1, pile_w.pile_id, &"wood", 2), 2)
	var pre_ok: Dictionary = coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 2, &"op_pre", &"lot_pre")
	assert_true(bool(pre_ok["ok"]))
	assert_eq(site.get_transit_claim_for_unit(u1), {&"wood": 2})

	assert_eq(site.claim_pickup(u1, pile_w.pile_id, &"wood", 3), 3)
	spy.events.clear()
	var before_existing: Dictionary = _snapshot_all(manager, inventory, [site], [load1])
	coord.fault_injection_hook = func(hit_stage: String, _ctx: Dictionary) -> Variant:
		return hit_stage != "after_claim_update"
	var res_existing_abort: Dictionary = coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 3, &"op_retryable", &"lot_retryable")
	assert_false(bool(res_existing_abort["ok"]))
	assert_eq(spy.events, [])
	assert_eq(site.get_transit_claim_for_unit(u1), {&"wood": 2})
	_assert_snapshot_data_equal_modulo_revisions(_snapshot_all(manager, inventory, [site], [load1]), before_existing)

	# Scenario 23: Re-executing with the exact SAME previously aborted op_id & lot_id now succeeds cleanly!
	coord.fault_injection_hook = Callable()
	spy.events.clear()
	var pile_w_id: int = pile_w.pile_id
	var res_success: Dictionary = coord.execute_reserved_withdrawal(site, u1, pile_w_id, &"wood", 3, &"op_retryable", &"lot_retryable")
	assert_true(bool(res_success["ok"]))
	assert_false(bool(res_success["replayed"]))
	assert_eq(int(res_success["withdrawn"]), 3)
	assert_null(manager.get_pile_by_id(pile_w_id))
	assert_false(is_instance_valid(pile_w))
	assert_eq(load1.get_amount(&"wood"), 5)
	assert_eq(site.get_transit_claim_for_unit(u1), {&"wood": 5})
	assert_true(coord.has_receipt(&"op_retryable"))
	spy.cleanup()


func test_20_21_22_idempotent_replay_operation_conflict_and_duplicate_lot() -> void:
	# Scenarios 20, 21, 22
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 3, slots[0])
	var pile_w2: GroundResourcePile = manager.try_create_pile_at(&"wood", 4, slots[1])
	var pile_s: GroundResourcePile = manager.try_create_pile_at(&"stone", 4, slots[2])

	var site_a: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_idemp_a", {&"wood": 7, &"stone": 4}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "IdempU1", &"idemp_u1", 40)
	var u2: Unit = _spawn_unit(host, "IdempU2", &"idemp_u2", 40)
	var load1: UnitCarryLoad = u1.get_carry_load()
	_assign_transporter_and_claim(site_a, u1, pile_w, &"wood", 3)

	# Prepare plan before commit so we can also test replay via commit_prepared_withdrawal!
	var prep: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_idemp", &"lot_idemp")
	assert_true(bool(prep["ok"]))

	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site_a], [load1])

	# Commit via commit_prepared_withdrawal (exhausts pile_w!)
	var pile_w_id: int = pile_w.pile_id
	var commit1: Dictionary = coord.commit_prepared_withdrawal(site_a, u1, prep)
	assert_true(bool(commit1["ok"]))
	assert_false(bool(commit1["replayed"]))
	assert_eq(int(commit1["withdrawn"]), 3)
	assert_eq(int(commit1["committed_amount"]), 3)
	assert_null(manager.get_pile_by_id(pile_w_id))

	# Scenario 20: Replay with identical payload (even after pile_w was exhausted & u1 moved!)
	u1.global_position = Vector3(20.0, 0.0, 20.0)
	spy.events.clear()
	var snap_after_commit: Dictionary = _snapshot_all(manager, inventory, [site_a], [load1])
	var replay1: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w_id, &"wood", 3, &"op_idemp", &"lot_idemp")
	assert_true(bool(replay1["ok"]))
	assert_true(bool(replay1["replayed"]))
	assert_eq(int(replay1["withdrawn"]), 0)
	assert_eq(int(replay1["committed_amount"]), 3)
	var replay2: Dictionary = coord.commit_prepared_withdrawal(site_a, u1, prep)
	assert_true(bool(replay2["ok"]))
	assert_true(bool(replay2["replayed"]))
	assert_eq(int(replay2["withdrawn"]), 0)
	assert_eq(int(replay2["committed_amount"]), 3)
	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site_a], [load1]), snap_after_commit)

	# Scenario 21: Same operation_id with conflicting payload parameters -> operation_conflict
	assert_eq(coord.execute_reserved_withdrawal(site_a, u1, pile_w_id, &"wood", 3, &"op_idemp", &"lot_diff")["reason"], "operation_conflict")
	assert_eq(coord.execute_reserved_withdrawal(site_a, u1, pile_w2.pile_id, &"wood", 3, &"op_idemp", &"lot_idemp")["reason"], "operation_conflict")
	assert_eq(coord.execute_reserved_withdrawal(site_a, u1, pile_w_id, &"stone", 3, &"op_idemp", &"lot_idemp")["reason"], "operation_conflict")
	assert_eq(coord.execute_reserved_withdrawal(site_a, u1, pile_w_id, &"wood", 2, &"op_idemp", &"lot_idemp")["reason"], "operation_conflict")
	assert_eq(coord.execute_reserved_withdrawal(site_a, u2, pile_w_id, &"wood", 3, &"op_idemp", &"lot_idemp")["reason"], "operation_conflict")

	# Scenario 22: New operation_id trying to reuse already committed lot_id -> duplicate_lot
	_assign_transporter_and_claim(site_a, u1, pile_w2, &"wood", 2, true)
	_assign_transporter_and_claim(site_a, u2, pile_s, &"stone", 2, true)
	spy.events.clear()
	var snap_before_dup: Dictionary = _snapshot_all(manager, inventory, [site_a], [load1])
	var dup_lot_res: Dictionary = coord.execute_reserved_withdrawal(site_a, u1, pile_w2.pile_id, &"wood", 2, &"op_new_id", &"lot_idemp")
	assert_false(bool(dup_lot_res["ok"]))
	assert_eq(String(dup_lot_res["reason"]), "duplicate_lot")

	# Also test duplicate_lot against another unit:
	var dup_lot_u2: Dictionary = coord.execute_reserved_withdrawal(site_a, u2, pile_s.pile_id, &"stone", 2, &"op_u2", &"lot_idemp")
	assert_false(bool(dup_lot_u2["ok"]))
	assert_eq(String(dup_lot_u2["reason"]), "duplicate_lot")
	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site_a], [load1]), snap_before_dup)
	spy.cleanup()


func test_24_25_26_concurrent_invalidation_and_aba_detection() -> void:
	# Scenarios 24, 25, 26
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 10, slots[0])
	var pile_s: GroundResourcePile = manager.try_create_pile_at(&"stone", 6, slots[1])

	var site_a: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_aba_a", {&"wood": 6}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite
	var site_b: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_aba_b", {&"stone": 4}),
		Vector3(14.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "AbaWorker", &"aba_worker", 40)
	var load1: UnitCarryLoad = u1.get_carry_load()
	_assign_transporter_and_claim(site_a, u1, pile_w, &"wood", 3)

	# Scenario 24: Concurrent pile mutation (ABA physical state + ABA reservation release/complement)
	var plan24a: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_24a", &"lot_24a")
	assert_true(bool(plan24a["ok"]))
	pile_w.apply_state(9, 0.0, 0.0)
	pile_w.apply_state(10, 0.0, 0.0)
	assert_eq(String(coord.commit_prepared_withdrawal(site_a, u1, plan24a)["reason"]), "stale_revision")

	var plan24b: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_24b", &"lot_24b")
	assert_true(bool(plan24b["ok"]))
	assert_true(inventory.release_batch(site_a.reservation_id, {&"wood": 1}))
	assert_true(inventory.complement_reservation(site_a.reservation_id, {&"wood": 1}))
	assert_eq(String(coord.commit_prepared_withdrawal(site_a, u1, plan24b)["reason"]), "stale_revision")

	# Scenario 25: Concurrent carry_load mutation (ABA capacity toggle & FREE_GATHERED addition)
	var plan25: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_25", &"lot_25")
	assert_true(bool(plan25["ok"]))
	load1.set_base_capacity(30)
	load1.set_base_capacity(40)
	assert_eq(String(coord.commit_prepared_withdrawal(site_a, u1, plan25)["reason"]), "stale_revision")

	var plan25b: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_25b", &"lot_25b")
	assert_true(bool(plan25b["ok"]))
	var wood_src := ResourceSource.new()
	host.add_child(wood_src)
	wood_src.configure(&"src_25b", WOOD_BASE.duplicate(), 5, 5, 2)
	assert_true(bool(wood_src.transfer_to_carry_load_with_provenance(load1, &"op_fg25", &"lot_fg25", 1)["ok"]))
	assert_eq(String(coord.commit_prepared_withdrawal(site_a, u1, plan25b)["reason"]), "stale_revision")

	# Scenario 26a: Concurrent site mutation (pending claim release & re-claim ABA)
	var plan26a: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_26a", &"lot_26a")
	assert_true(bool(plan26a["ok"]))
	site_a.release_pickup_claim(u1)
	assert_eq(site_a.claim_pickup(u1, pile_w.pile_id, &"wood", 3), 3)
	assert_eq(String(coord.commit_prepared_withdrawal(site_a, u1, plan26a)["reason"]), "stale_revision")

	# Scenario 26b: Concurrent peer site mutation when unit already carries SITE_RESERVED for site_b
	var u_peer_w: Unit = _spawn_unit(host, "PeerDummy", &"peer_dummy", 20)
	_assign_transporter_and_claim(site_b, u1, pile_s, &"stone", 2)
	assert_true(bool(coord.execute_reserved_withdrawal(site_b, u1, pile_s.pile_id, &"stone", 2, &"op_seed_b", &"lot_seed_b")["ok"]))
	u1.global_position = pile_w.global_position + Vector3(0.4, 0.0, 0.0)
	u1._current_order = site_a._assigned_workers[u1.get_instance_id()]["order"]
	var plan26b: Dictionary = site_a.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 3, &"op_26b", &"lot_26b")
	assert_true(bool(plan26b["ok"]))
	assert_true((plan26b["peer_claim_revisions"] as Dictionary).has(site_b.site_id))
	# Mutate peer site_b (e.g. claim & release pickup on peer_w) -> invalidates peer_claim_revisions!
	assert_eq(site_b.claim_pickup(u_peer_w, pile_s.pile_id, &"stone", 1), 1)
	site_b.release_pickup_claim(u_peer_w)
	assert_eq(String(coord.commit_prepared_withdrawal(site_a, u1, plan26b)["reason"]), "stale_peer_site_revision")


func test_27_reentrancy_in_all_signals_and_consistent_observer_view() -> void:
	# Scenario 27
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 8, slots[0])

	var site: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_reent_site", {&"wood": 8}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "ReentU1", &"reent_u1", 40)
	var load1: UnitCarryLoad = u1.get_carry_load()
	_assign_transporter_and_claim(site, u1, pile_w, &"wood", 5)

	var observed_views: Dictionary = {}
	var reentry_results: Dictionary = {}

	var probe_cb := func(sig_name: String) -> void:
		observed_views[sig_name] = {
			"pile_amt": pile_w.amount,
			"pile_res": manager.get_pile_reservations(pile_w.pile_id),
			"inv_phys": inventory.get_physical_amount(&"wood"),
			"inv_res": inventory.get_reservation_amount(site.reservation_id, &"wood"),
			"carry_amt": load1.get_amount(&"wood"),
			"carry_weight": load1.get_current_weight(),
			"prov_valid": load1.validate_provenance(),
			"site_reserved": site.get_reserved_in_piles_amount(&"wood"),
			"site_transit": site.get_in_transit_amount(&"wood"),
			"site_claim": site.get_transit_claim_for_unit(u1),
			"invariant": site.verify_accounting_invariant(),
			"receipt_exists": coord.has_receipt(&"op_reent_main"),
		}
		reentry_results[sig_name] = {
			"coord_new": String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_reent_nested", &"lot_reent_nested")["reason"]),
			"coord_replay": String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 5, &"op_reent_main", &"lot_reent_main")["reason"]),
			"site_prep": String(site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_p", &"lot_p")["reason"]),
			"mgr_withdraw": manager.withdraw_reserved_from_pile(pile_w.pile_id, site.reservation_id, &"wood", 1),
			"mgr_release": manager.release_batch(site.reservation_id, {&"wood": 1}),
			"inv_withdraw": inventory.withdraw_reserved_from_pile_to_carry_load(pile_w.pile_id, site.reservation_id, WOOD_BASE.duplicate(), 1, load1),
			"carry_add": bool(load1.add_with_provenance(&"op_c", &"lot_c", &"wood", WOOD_BASE.unit_weight, 1, CarryProvenanceLedger.FREE_GATHERED)["ok"]),
			"site_claim_amt": site.claim_pickup(u1, pile_w.pile_id, &"wood", 1),
		}
		site.record_withdrawn_for_site(u1, &"wood", 1)

	var probe_conns: Array[Dictionary] = []
	var attach_probe := func(sig: Signal, sig_name: String) -> void:
		var cb := func() -> void: probe_cb.call(sig_name)
		sig.connect(cb)
		probe_conns.append({"sig": sig, "cb": cb})
	var cb_site := func(_s: ConstructionSite) -> void: probe_cb.call("site_state_changed")
	site.state_changed.connect(cb_site)
	probe_conns.append({"sig": site.state_changed, "cb": cb_site})

	attach_probe.call(manager.reservations_changed, "mgr_reservations_changed")
	attach_probe.call(inventory.reservations_changed, "inv_reservations_changed")
	attach_probe.call(manager.storage_changed, "mgr_storage_changed")
	attach_probe.call(inventory.inventory_changed, "inv_inventory_changed")
	attach_probe.call(load1.load_changed, "carry_load_changed")

	var main_res: Dictionary = coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 5, &"op_reent_main", &"lot_reent_main")
	for item: Dictionary in probe_conns:
		var sig: Signal = item["sig"] as Signal
		var cb: Callable = item["cb"] as Callable
		if sig.is_connected(cb):
			sig.disconnect(cb)
	probe_conns.clear()

	assert_true(bool(main_res["ok"]))
	assert_eq(observed_views.size(), 6)

	var expected_view: Dictionary = {
		"pile_amt": 3,
		"pile_res": {site.reservation_id: 3},
		"inv_phys": 3,
		"inv_res": 3,
		"carry_amt": 5,
		"carry_weight": 5 * WOOD_BASE.unit_weight,
		"prov_valid": true,
		"site_reserved": 3,
		"site_transit": 5,
		"site_claim": {&"wood": 5},
		"invariant": true,
		"receipt_exists": true,
	}
	for sig_key: Variant in observed_views.keys():
		assert_eq(observed_views[sig_key], expected_view, "Divergent observer state on signal " + String(sig_key))
		var r: Dictionary = reentry_results[sig_key] as Dictionary
		assert_eq(String(r["coord_new"]), "busy")
		assert_eq(String(r["coord_replay"]), "busy")
		assert_eq(String(r["site_prep"]), "busy")
		assert_false(bool(r["mgr_withdraw"]))
		assert_false(bool(r["mgr_release"]))
		assert_eq(int(r["inv_withdraw"]), 0)
		assert_false(bool(r["carry_add"]))
		assert_eq(int(r["site_claim_amt"]), 0)


func test_28_world_region_generation_worker_eligibility_and_tamper() -> void:
	# Scenario 28
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 10, slots[0])
	var site: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_iso_site", {&"wood": 6}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	# Separate SubViewport with own_world_3d -> incompatible World3D
	var vp := SubViewport.new()
	vp.own_world_3d = true
	add_test_child(vp)
	var remote := _make_fixture(0, vp)
	var remote_u: Unit = _spawn_unit(remote["host"] as Node, "RemoteU", &"remote_u", 20, pile_w.global_position)
	assert_eq(String(coord.execute_reserved_withdrawal(site, remote_u, pile_w.pile_id, &"wood", 1, &"op_w1", &"lot_w1")["reason"]), "unit_world_mismatch")

	# Local unit checks:
	var u1: Unit = _spawn_unit(host, "LocalU", &"local_u", 20, pile_w.global_position)
	# Unregistered worker -> worker_not_registered
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_unreg", &"lot_unreg")["reason"]), "worker_not_registered")

	# Registered BUILDER role -> claim_not_eligible
	var order := ConstructOrder.new(site, null, false)
	order.mark_running()
	u1._current_order = order
	site._assigned_workers[u1.get_instance_id()] = {
		"unit": u1, "order": order, "role": ConstructionSite.WorkerRole.BUILDER,
		"force_transporter": false, "solo_promoted_builder": false,
	}
	site._worker_order_ids.append(u1.get_instance_id())
	site.claim_pickup(u1, pile_w.pile_id, &"wood", 2)
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_bld", &"lot_bld")["reason"]), "claim_not_eligible")

	# Registered TRANSPORTER, missing pending pickup -> claim_not_eligible
	site._assigned_workers[u1.get_instance_id()]["role"] = ConstructionSite.WorkerRole.TRANSPORTER
	site.release_pickup_claim(u1)
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_nocl", &"lot_nocl")["reason"]), "claim_not_eligible")

	# Pending pickup smaller than requested -> claim_not_eligible
	site.claim_pickup(u1, pile_w.pile_id, &"wood", 1)
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 2, &"op_smcl", &"lot_smcl")["reason"]), "claim_not_eligible")

	# Incompatible generation option / incompatible provenance lot generation
	site.claim_pickup(u1, pile_w.pile_id, &"wood", 2)
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_gen", &"lot_gen", {"generation": site.get_generation() + 1})["reason"]), "invalid_generation")
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_waive", &"lot_waive", {"require_assigned_worker": false})["reason"]), "physical_authorization_required")

	# Foreign region / unknown reserved lot in load -> unknown_reserved_site
	var plan_before: Dictionary = site.prepare_reserved_withdrawal(u1, pile_w.pile_id, &"wood", 1, &"op_tamper", &"lot_tamper")
	assert_true(bool(plan_before["ok"]))
	var tampered: Dictionary = plan_before.duplicate(true)
	(tampered["pile_plan"]["after"] as Dictionary)["pile_amount"] = 999
	assert_eq(String(coord.commit_prepared_withdrawal(site, u1, tampered)["reason"]), "tampered_or_stale_plan")

	assert_true(bool(u1.get_carry_load().add_with_provenance(&"op_badgen", &"lot_badgen", &"wood", WOOD_BASE.unit_weight, 1, CarryProvenanceLedger.SITE_RESERVED, site.site_id, site.get_generation() + 5)["ok"]))
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_bg", &"lot_bg")["reason"]), "generation_mismatch")

	var u_reg: Unit = _spawn_unit(host, "RegU", &"reg_u", 20, pile_w.global_position)
	_assign_transporter_and_claim(site, u_reg, pile_w, &"wood", 1, true)
	assert_true(bool(u_reg.get_carry_load().add_with_provenance(&"op_for", &"lot_for", &"wood", WOOD_BASE.unit_weight, 1, CarryProvenanceLedger.SITE_RESERVED, &"foreign_site", 1)["ok"]))
	assert_eq(String(coord.execute_reserved_withdrawal(site, u_reg, pile_w.pile_id, &"wood", 1, &"op_for2", &"lot_for2")["reason"]), "unknown_reserved_site")

	# Non-ACTIVE site state & wrong-thread affinity guard:
	var prev_state: ConstructionSite.SiteState = site._site_state
	site._site_state = ConstructionSite.SiteState.COMPLETING
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_state", &"lot_state")["reason"]), "site_not_active")
	site._site_state = prev_state

	var saved_tid: int = coord._owner_thread_id
	coord._owner_thread_id = saved_tid + 1
	assert_eq(String(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 1, &"op_thr", &"lot_thr")["reason"]), "wrong_thread")
	coord._owner_thread_id = saved_tid


func test_29_legacy_bypass_methods_blocked_when_provenance_enabled() -> void:
	# Scenario 29
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var coord := ReservedWithdrawalCoordinator.new()

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 8, slots[0])
	var site: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_byp_site", {&"wood": 6}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	var u1: Unit = _spawn_unit(host, "BypU", &"byp_u", 20)
	var load1: UnitCarryLoad = u1.get_carry_load()
	_assign_transporter_and_claim(site, u1, pile_w, &"wood", 2, true)
	assert_true(bool(coord.execute_reserved_withdrawal(site, u1, pile_w.pile_id, &"wood", 2, &"op_byp_ok", &"lot_byp_ok")["ok"]))

	var spy := SignalSpy.new()
	spy.watch_all(manager, inventory, [site], [load1])
	var snap: Dictionary = _snapshot_all(manager, inventory, [site], [load1])

	var wood_def: ResourceDefinition = WOOD_BASE.duplicate() as ResourceDefinition
	assert_false(load1.add_units(wood_def, 1))
	assert_false(load1.add_resource(&"wood", wood_def.unit_weight, 1))
	assert_eq(load1.remove_units(&"wood", 1), 0)
	assert_eq(load1.take_all(), {})
	load1.restore_load_snapshot({}, {})
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(pile_w.pile_id, site.reservation_id, wood_def, 1, load1), 0)
	assert_eq(inventory.deliver_from_carry_load(load1), {})
	site.record_withdrawn_for_site(u1, &"wood", 1)
	assert_eq(site.accept_delivery_from_carry_load(u1, load1), {})

	assert_eq(spy.events, [])
	assert_eq(_snapshot_all(manager, inventory, [site], [load1]), snap)
	spy.cleanup()


func test_30_legacy_flow_without_provenance_remains_intact() -> void:
	# Scenario 30: Unit WITHOUT provenance uses full legacy logistics pipeline without regression
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w: GroundResourcePile = manager.try_create_pile_at(&"wood", 4, slots[0])
	var site: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"c2_leg_site", {&"wood": 4}),
		Vector3(8.0, 0.0, 8.0)
	)["site"] as ConstructionSite

	var legacy_u: Unit = _spawn_unit(host, "LegacyU", &"", 20, pile_w.global_position)
	var legacy_load: UnitCarryLoad = legacy_u.get_carry_load()
	assert_false(legacy_load.is_provenance_enabled())

	var order := ConstructOrder.new(site, zone, false)
	order.mark_running()
	legacy_u._current_order = order
	assert_eq(site.register_worker(legacy_u, order, false), ConstructionSite.WorkerRole.SOLO_SUPPLIER)

	var wood_def: ResourceDefinition = WOOD_BASE.duplicate() as ResourceDefinition
	assert_eq(site.claim_pickup(legacy_u, pile_w.pile_id, &"wood", 4), 4)
	var taken: int = inventory.withdraw_reserved_from_pile_to_carry_load(
		pile_w.pile_id,
		site.reservation_id,
		wood_def,
		4,
		legacy_load
	)
	assert_eq(taken, 4)
	site.record_withdrawn_for_site(legacy_u, &"wood", 4)
	assert_eq(site.get_transit_claim_for_unit(legacy_u), {&"wood": 4})
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(site.get_in_transit_amount(&"wood"), 4)

	var dropped: Dictionary = site.accept_delivery_from_carry_load(legacy_u, legacy_load)
	assert_eq(dropped, {&"wood": 4})
	assert_true(legacy_load.is_empty())
	assert_true(site.is_fully_supplied())
	assert_true(site.verify_accounting_invariant())

func _make_r1_withdrawal(fx: Dictionary, suffix: String, position: Vector3, slot_index: int) -> Dictionary:
	var manager: GroundPileManager = fx.manager
	var zone: CampStorageZone = fx.zone
	var cm: ConstructionManager = fx.cm
	var pile := manager.try_create_pile_at(&"wood", 4, zone.get_candidate_slots()[slot_index])
	var site: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(StringName("r1_" + suffix), {&"wood": 4}), position).site
	var unit := _spawn_unit(fx.host, suffix, StringName(suffix), 20)
	_assign_transporter_and_claim(site, unit, pile, &"wood", 2)
	return {"site": site, "pile": pile, "unit": unit, "load": unit.get_carry_load(), "pile_id": pile.pile_id}


func _r1_execute(coord: ReservedWithdrawalCoordinator, request: Dictionary, op: StringName, lot: StringName) -> Dictionary:
	return coord.execute_reserved_withdrawal(request.site, request.unit, request.pile_id, &"wood", 2, op, lot)


func test_r1_capacity_during_application_and_after_rollback() -> void:
	var fx := _make_fixture()
	var request := _make_r1_withdrawal(fx, "Apply", Vector3(8, 0, 8), 0)
	var load: UnitCarryLoad = request.load
	load.set_capacity_modifier(&"existing", 3)
	var capacity_calls: Array = []
	var attempts: Array = []
	var on_capacity := func() -> void: capacity_calls.append(true)
	load.capacity_changed.connect(on_capacity)
	var snapshot := _snapshot_all(fx.manager, fx.inventory, [request.site], [load])
	var rev := load.get_transaction_revision()
	var coord := ReservedWithdrawalCoordinator.new()
	coord.fault_injection_hook = func(stage: String, _ctx: Dictionary) -> bool:
		if stage != "after_pile_deduction":
			return true
		attempts.append(load.set_base_capacity(9))
		attempts.append(load.set_capacity_modifier(&"existing", 8))
		attempts.append(load.remove_capacity_modifier(&"existing"))
		return false
	var failed := _r1_execute(coord, request, &"r1_apply", &"r1_apply_lot")
	assert_eq(failed.reason, "aborted_after_pile_deduction")
	assert_eq(attempts, [false, false, false])
	assert_eq(load.get_base_capacity(), 20)
	assert_eq(load.get_effective_capacity(), 23)
	assert_eq(load.get_transaction_revision(), rev)
	assert_eq(capacity_calls, [])
	assert_false(coord.has_receipt(&"r1_apply"))
	# Rollback advances storage revisions, so compare the physical and ledger views separately.
	assert_eq(fx.manager.get_physical_amount(&"wood"), 4)
	assert_eq(fx.inventory.get_reservation_amount(request.site.reservation_id, &"wood"), 4)
	assert_eq(fx.manager._ledger.snapshot_state(), snapshot.ledger)
	assert_true(load.is_empty())
	assert_eq(request.site.get_transit_claim_for_unit(request.unit), {})
	assert_true(load.set_base_capacity(24))
	assert_eq(capacity_calls.size(), 1)
	load.capacity_changed.disconnect(on_capacity)
	coord.fault_injection_hook = Callable()


func test_r1_capacity_and_second_coordinator_during_commit_signals() -> void:
	var fx := _make_fixture()
	var request := _make_r1_withdrawal(fx, "Signals", Vector3(8, 0, 8), 0)
	var load: UnitCarryLoad = request.load
	var site: ConstructionSite = request.site
	load.set_capacity_modifier(&"existing", 3)
	var owner := ReservedWithdrawalCoordinator.new()
	var second := ReservedWithdrawalCoordinator.new()
	var views: Dictionary = {}
	var capacity_calls: Array = []
	var on_capacity := func() -> void: capacity_calls.append(true)
	load.capacity_changed.connect(on_capacity)
	var probe := func(label: String, mutate: Callable) -> void:
		var rev := load.get_transaction_revision()
		var outcome: Variant = mutate.call()
		var nested := _r1_execute(second, request, &"r1_nested", &"r1_nested_lot")
		views[label] = {
			"outcome": outcome, "revision_delta": load.get_transaction_revision() - rev,
			"revisions": [load.get_transaction_revision(), fx.manager.get_transaction_revision(),
				fx.inventory.get_transaction_revision(), site.get_transaction_revision()],
			"modifiers": load._capacity_modifiers.duplicate(),
			"capacity": load.get_effective_capacity(), "nested": nested.reason,
			"nested_dependency": nested.dependency, "physical": fx.manager.get_physical_amount(&"wood"),
			"reservation": fx.inventory.get_reservation_amount(site.reservation_id, &"wood"),
			"load": load.provenance_snapshot(), "weight": load.get_current_weight(),
			"claim": site.get_transit_claim_for_unit(request.unit),
			"receipt": owner.has_receipt(&"r1_signals"),
		}
	var reservation_cb := func() -> void: probe.call("reservations", func() -> bool: return load.set_base_capacity(30))
	var storage_cb := func() -> void: probe.call("storage", func() -> bool: return load.set_capacity_modifier(&"added", 5))
	var inventory_cb := func() -> void: probe.call("inventory", func() -> bool: return load.set_base_capacity(load.get_base_capacity()))
	var load_cb := func() -> void: probe.call("load", func() -> bool: return load.remove_capacity_modifier(&"existing"))
	var site_cb := func(_site: ConstructionSite) -> void: probe.call("site", func() -> bool: return load.set_capacity_modifier(&"added", 7))
	fx.manager.reservations_changed.connect(reservation_cb)
	fx.manager.storage_changed.connect(storage_cb)
	fx.inventory.inventory_changed.connect(inventory_cb)
	load.load_changed.connect(load_cb)
	site.state_changed.connect(site_cb)
	var result := _r1_execute(owner, request, &"r1_signals", &"r1_signals_lot")
	fx.manager.reservations_changed.disconnect(reservation_cb)
	fx.manager.storage_changed.disconnect(storage_cb)
	fx.inventory.inventory_changed.disconnect(inventory_cb)
	load.load_changed.disconnect(load_cb)
	site.state_changed.disconnect(site_cb)
	assert_true(result.ok)
	assert_eq(views.size(), 5)
	for label: String in views:
		var view: Dictionary = views[label]
		assert_false(view.outcome, label)
		assert_eq(view.revision_delta, 0, label)
		assert_eq(view.capacity, 23, label)
		assert_eq(view.modifiers, {&"existing": 3}, label)
		assert_eq(view.revisions, [load.get_transaction_revision(), fx.manager.get_transaction_revision(),
			fx.inventory.get_transaction_revision(), site.get_transaction_revision()], label)
		assert_eq(view.nested, "busy", label)
		assert_eq(view.nested_dependency, "coordinator", label)
		assert_eq(view.physical + int(view.load.amounts[&"wood"]), 4, label)
		assert_eq(view.reservation, 2, label)
		assert_eq(view.load, load.provenance_snapshot(), label)
		assert_eq(view.weight, 2 * WOOD_BASE.unit_weight, label)
		assert_eq(view.claim, {&"wood": 2}, label)
		assert_true(view.receipt, label)
	assert_eq(capacity_calls, [])
	assert_true(load.set_base_capacity(26))
	assert_eq(capacity_calls.size(), 1)
	load.capacity_changed.disconnect(on_capacity)


func test_r1_regional_replay_and_identifier_conflicts_across_handles() -> void:
	var fx := _make_fixture()
	var a := _make_r1_withdrawal(fx, "First", Vector3(8, 0, 8), 0)
	var b := _make_r1_withdrawal(fx, "Second", Vector3(14, 0, 8), 1)
	var owner := ReservedWithdrawalCoordinator.new()
	var second := ReservedWithdrawalCoordinator.new()
	var committed := _r1_execute(owner, a, &"r1_op", &"r1_lot")
	assert_true(committed.ok)
	var before := _snapshot_all(fx.manager, fx.inventory, [a.site, b.site], [a.load, b.load])
	var replay := _r1_execute(second, a, &"r1_op", &"r1_lot")
	assert_true(replay.get("ok", false))
	assert_true(replay.get("replayed", false))
	assert_eq(replay.get("withdrawn"), 0)
	assert_eq(replay.get("committed_amount"), 2)
	assert_eq(replay.get("receipt"), committed.get("receipt"))
	owner = null
	second = null
	var replacement := ReservedWithdrawalCoordinator.new()
	assert_true(_r1_execute(replacement, a, &"r1_op", &"r1_lot").get("replayed", false))
	assert_eq(_r1_execute(replacement, b, &"r1_op", &"r1_other_lot").reason, "operation_conflict")
	assert_eq(_r1_execute(replacement, b, &"r1_other_op", &"r1_lot").reason, "duplicate_lot")
	assert_eq(_snapshot_all(fx.manager, fx.inventory, [a.site, b.site], [a.load, b.load]), before)


func test_r1_regions_worlds_and_domain_lifetime() -> void:
	var fx := _make_fixture()
	var request := _make_r1_withdrawal(fx, "Local", Vector3(8, 0, 8), 0)
	var viewport: SubViewport = fx.host.get_viewport()
	var coord := ReservedWithdrawalCoordinator.new()
	var remote_view := SubViewport.new()
	remote_view.own_world_3d = true
	add_test_child(remote_view)
	var remote := _make_fixture(0, remote_view)
	var remote_request := _make_r1_withdrawal(remote, "Local", Vector3(8, 0, 8), 0)
	var region := _make_fixture(0, viewport, &"other_c2_region")
	region.host.position = Vector3(40, 0, 0)
	var region_request := _make_r1_withdrawal(region, "Local", Vector3(48, 0, 8), 0)

	var site: ConstructionSite = request.site
	var region_site: ConstructionSite = region_request.site
	var local_before := _snapshot_all(fx.manager, fx.inventory, [site], [request.load])
	var home := site.region_id
	site.region_id = &" "
	assert_eq(_r1_execute(coord, request, &"shared_id", &"shared_lot").reason, "invalid_domain")
	site.region_id = home
	var region_home := region_site.region_id
	region_site.region_id = home
	assert_eq(_r1_execute(coord, request, &"shared_id", &"shared_lot").reason, "ambiguous_domain")
	region_site.region_id = region_home
	assert_eq(_snapshot_all(fx.manager, fx.inventory, [site], [request.load]), local_before)

	for candidate: Dictionary in [request, remote_request, region_request]:
		var result := _r1_execute(coord, candidate, &"shared_id", &"shared_lot")
		assert_true(result.ok)
		assert_false(result.replayed)
		assert_eq(result.withdrawn, 2)
		assert_eq(candidate.load.get_amount(&"wood") + candidate.pile.amount, 4)

	# Even after the original site's relabeling, the same physical storage cannot be rebound.
	site.region_id = &"fake_region"
	assert_eq(_r1_execute(coord, request, &"fresh_id", &"fresh_lot").reason, "ambiguous_domain")
	site.region_id = home
	assert_true(_r1_execute(coord, request, &"shared_id", &"shared_lot").replayed)
	var world_ref: WeakRef = weakref(site.get_world_3d())
	var authority_ref: WeakRef = weakref(coord._last_authority())
	viewport.free()
	assert_null(world_ref.get_ref())
	assert_null(authority_ref.get_ref())
	assert_false(coord.has_receipt(&"shared_id"))
	assert_true(_r1_execute(coord, remote_request, &"shared_id", &"shared_lot").replayed)


func test_r1_scene_callbacks_run_after_receipt_and_mutators_are_excluded() -> void:
	var fx := _make_fixture()
	var request := _make_r1_withdrawal(fx, "Exhaust", Vector3(8, 0, 8), 0)
	var site: ConstructionSite = request.site
	var unit: Unit = request.unit
	var load: UnitCarryLoad = request.load
	var pile: GroundResourcePile = request.pile
	var manager: GroundPileManager = fx.manager
	var inventory: SettlementInventory = fx.inventory
	assert_eq(site.claim_pickup(unit, pile.pile_id, &"wood", 4), 4)
	var original_order := unit.get_current_order()
	var own_region := site.region_id
	var coord := ReservedWithdrawalCoordinator.new()
	var observations: Array = []
	var on_exit := func() -> void:
		observations.append(coord.has_receipt(&"exhaust"))
		observations.append(manager.get_physical_amount(&"wood"))
		observations.append(load.get_amount(&"wood"))
		observations.append(site.get_transit_claim_for_unit(unit))
		manager.begin_batch()
		load.begin_batch()
		manager.cleanup()
		inventory.set_storage_source(InMemoryStorageSource.new())
		site.region_id = &"redirected"
		unit.cancel_current_order()
		site.record_completion_failure("observer")
	pile.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	var result := coord.execute_reserved_withdrawal(site, unit, pile.pile_id, &"wood", 4, &"exhaust", &"exhaust_lot")
	assert_true(result.ok)
	assert_eq(observations, [true, 0, 4, {&"wood": 4}])
	assert_eq(inventory.get_storage_source(), manager)
	assert_eq(site.region_id, own_region)
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.ACTIVE)
	assert_eq(unit.get_current_order(), original_order)
	assert_false(load.is_transaction_busy())
	assert_false(manager.is_batch_active())


func test_r1_visual_sync_never_reports_a_provisional_pile() -> void:
	var fx := _make_fixture()
	var manager: GroundPileManager = fx.manager
	var zone: CampStorageZone = fx.zone
	var cm: ConstructionManager = fx.cm
	var pile := manager.try_create_pile_at(&"wood", 6, zone.get_candidate_slots()[0])
	var peer_pile := manager.try_create_pile_at(&"wood", 3, zone.get_candidate_slots()[1])
	var site: ConstructionSite = cm.try_create_site_from_placement(
		_make_building_def(&"r1_visual", {&"wood": 6}), Vector3(8, 0, 8)).site
	var unit := _spawn_unit(fx.host, "Visual", &"visual")
	_assign_transporter_and_claim(site, unit, pile, &"wood", 2)
	var load := unit.get_carry_load()
	var coord := ReservedWithdrawalCoordinator.new()
	var observations: Array = []
	var cb := func() -> void:
		peer_pile.apply_state(99, 0.0, 0.0)
		pile.amount = 111
		observations.append([pile.amount, peer_pile.amount, load.get_amount(&"wood"),
			site.get_transit_claim_for_unit(unit), coord.has_receipt(&"vis")])
	var mesh: MeshInstance3D = pile._mesh_instances[1]
	assert_true(mesh.visible)
	mesh.visibility_changed.connect(cb)
	coord.fault_injection_hook = func(stage: String, _ctx: Dictionary) -> bool:
		return stage != "after_pile_deduction"
	assert_false(coord.execute_reserved_withdrawal(site, unit, pile.pile_id, &"wood", 2, &"vis", &"vis_lot").ok)
	assert_eq(observations, [])
	assert_true(mesh.visible)
	assert_false(coord.is_busy())
	coord.fault_injection_hook = Callable()
	assert_true(coord.execute_reserved_withdrawal(site, unit, pile.pile_id, &"wood", 2, &"vis", &"vis_lot").ok)
	mesh.visibility_changed.disconnect(cb)
	assert_eq(observations, [[4, 3, 2, {&"wood": 2}, true]])
	assert_false(mesh.visible)
