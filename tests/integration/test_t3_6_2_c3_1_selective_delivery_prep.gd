extends TestCase

const Planner = preload("res://src/economy/selective_site_delivery_planner.gd")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER: CharacterDefinition = preload("res://data/characters/leader_a.tres")

var _managers: Array[GroundPileManager] = []
var _signals: Array[Array] = []


func after_each() -> void:
	for connection: Array in _signals:
		var signal_ref: Signal = connection[0]
		var callback: Callable = connection[1]
		if signal_ref.is_connected(callback):
			signal_ref.disconnect(callback)
	_signals.clear()
	for manager: GroundPileManager in _managers:
		manager.cleanup()
	_managers.clear()


func _fixture() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_test_child(viewport)
	var host := Node3D.new()
	viewport.add_child(host)
	var zone := CampStorageZone.new()
	zone.position = Vector3(-8, 0, -8)
	zone.zone_bounds_half_extents = Vector2(8, 8)
	host.add_child(zone)
	var pile_root := Node3D.new()
	var site_root := Node3D.new()
	host.add_child(pile_root)
	host.add_child(site_root)
	var definitions := {&"wood": WOOD.duplicate(), &"stone": STONE.duplicate(), &"food": FOOD.duplicate()}
	var manager := GroundPileManager.new(definitions, zone, pile_root, SimulatedWorldTimeProvider.new(0))
	_managers.append(manager)
	var inventory := SettlementInventory.new(manager)
	var construction := ConstructionManager.new()
	host.add_child(construction)
	construction.configure(site_root, inventory, definitions, zone, null, &"c3_region")
	var slots := zone.get_candidate_slots()
	var wood := manager.try_create_pile_at(&"wood", 20, slots[0])
	var stone := manager.try_create_pile_at(&"stone", 8, slots[1])
	assert_not_null(wood)
	assert_not_null(stone)
	return {"host": host, "viewport": viewport, "manager": manager, "inventory": inventory,
		"cm": construction, "wood": wood, "stone": stone, "coordinator": ReservedWithdrawalCoordinator.new()}


func _create_site(fx: Dictionary, id: StringName, costs: Dictionary, x: float = 8.0) -> ConstructionSite:
	var definition := BuildingDefinition.new()
	definition.definition_id = id
	definition.display_name = String(id)
	definition.costs = costs
	definition.footprint_size = Vector2(3, 3)
	definition.build_work_required_sec = 10.0
	definition.max_builders = 2
	definition.visual_height = 2.0
	var result: Dictionary = fx.cm.try_create_site_from_placement(definition, Vector3(x, 0, 8))
	assert_true(result.get("ok", false))
	return result.get("site") as ConstructionSite


func _unit(fx: Dictionary, id: StringName, use_provenance: bool = true) -> Unit:
	var unit := UNIT_SCENE.instantiate() as Unit
	unit.definition = LEADER.duplicate() as CharacterDefinition
	unit.definition.base_carry_capacity = 80
	fx.host.add_child(unit)
	if use_provenance:
		assert_true(unit.get_carry_load().enable_provenance(id))
	return unit


func _withdraw(fx: Dictionary, site: ConstructionSite, unit: Unit, pile: GroundResourcePile, quantity: int, lot: StringName) -> void:
	var order := unit.get_current_order() as ConstructOrder
	if order == null or order.site != site:
		unit.cancel_current_order()
		order = ConstructOrder.new(site, null, true)
		order._unit = unit
		order.mark_running()
		unit._current_order = order
		assert_eq(site.register_worker(unit, order, true), ConstructionSite.WorkerRole.TRANSPORTER)
	unit.global_position = pile.global_position + Vector3(0.4, 0, 0)
	assert_eq(site.claim_pickup(unit, pile.pile_id, pile.resource_id, quantity), quantity)
	var result: Dictionary = fx.coordinator.execute_reserved_withdrawal(
		site, unit, pile.pile_id, pile.resource_id, quantity, StringName("pickup_" + String(lot)), lot)
	assert_eq(result.get("withdrawn"), quantity, str(result))


func _gather(fx: Dictionary, unit: Unit, amount: int) -> void:
	var source := ResourceSource.new()
	fx.host.add_child(source)
	source.configure(&"tree", WOOD.duplicate(), 10, 5, 2)
	assert_eq(source.transfer_to_carry_load_with_provenance(unit.get_carry_load(), &"gather", &"free_wood", amount).extracted, amount)


func _watch(signal_ref: Signal, callback: Callable) -> void:
	signal_ref.connect(callback)
	_signals.append([signal_ref, callback])


func _observe(fx: Dictionary, sites: Array[ConstructionSite], unit: Unit) -> Array:
	var events: Array = []
	for signal_ref: Signal in [fx.manager.reservations_changed, fx.manager.storage_changed,
		fx.inventory.reservations_changed, fx.inventory.inventory_changed, unit.get_carry_load().load_changed,
		unit.get_carry_load().capacity_changed]:
		_watch(signal_ref, func() -> void: events.append("changed"))
	for site: ConstructionSite in sites:
		for signal_ref: Signal in [site.state_changed, site.buffer_changed, site.workers_changed, site.supply_completed]:
			_watch(signal_ref, func(_site: ConstructionSite) -> void: events.append("site_changed"))
	return events


func _snapshot(fx: Dictionary, sites: Array[ConstructionSite], unit: Unit) -> Dictionary:
	var entries: Array = []
	for site: ConstructionSite in sites:
		entries.append({"state": site.get_site_state(), "substate": site.get_assembly_substate(),
			"revision": site.get_transaction_revision(), "generation": site.get_generation(),
			"progress": site.get_work_progress_sec(), "buffer": site.get_delivered_buffer_amounts(),
			"consumed": site.get_consumed_amounts(), "claims": site._transit_claims.duplicate(true),
			"pending": site._pending_pickups.duplicate(true), "workers": site._assigned_workers.duplicate(true)})
	var piles: Array = []
	for pile: GroundResourcePile in fx.manager.get_piles():
		piles.append([pile.get_instance_id(), pile.amount, pile.elapsed_exposure_sec,
			pile.decay_accumulator_sec, pile.get_transaction_revision()])
	var world := unit.get_world_3d()
	var authority: Variant = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var receipts: Dictionary = {}
	for region: Variant in authority:
		receipts[region] = authority[region].receipts.duplicate(true)
	var load := unit.get_carry_load()
	return {"sites": entries, "piles": piles, "physical": fx.inventory.get_all_physical_amounts(),
		"reservations": fx.manager._ledger.snapshot_state(), "storage_revision": fx.manager.get_transaction_revision(),
		"inventory_revision": fx.inventory.get_transaction_revision(), "pile_ledger_revision": fx.manager.get_pile_ledger_revision(),
		"cargo": load.provenance_snapshot(), "load_revision": load.get_transaction_revision(), "capacity": load.get_effective_capacity(),
		"order": unit.get_current_order(), "position": unit.global_position, "receipts": receipts,
		"authority_present": world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META),
		"nodes": fx.host.find_children("*", "", true, false).size()}


func _prepare(site: ConstructionSite, unit: Unit, amounts: Variant = {}, op: Variant = &"drop") -> Dictionary:
	return Planner.prepare_selective_site_delivery(site, unit, op, amounts)


func _validate(site: ConstructionSite, unit: Unit, plan: Variant) -> Dictionary:
	return Planner.validate_selective_site_delivery_plan(site, unit, plan)


func test_c2_cargo_mixed_origins_and_deterministic_partial_multiresource_plan() -> void:
	var fx := _fixture()
	var a := _create_site(fx, &"a", {&"wood": 8, &"stone": 3})
	var b := _create_site(fx, &"b", {&"wood": 5}, 14)
	var unit := _unit(fx, &"mixed")
	_gather(fx, unit, 2)
	_withdraw(fx, a, unit, fx.wood, 3, &"z_wood")
	_withdraw(fx, a, unit, fx.wood, 2, &"a_wood")
	_withdraw(fx, a, unit, fx.stone, 2, &"a_stone")
	_withdraw(fx, b, unit, fx.wood, 4, &"b_wood")
	var peer := _unit(fx, &"peer_worker")
	_withdraw(fx, a, peer, fx.wood, 1, &"peer_wood")
	unit.cancel_current_order()
	unit.global_position = Vector3(40, 0, 40)
	assert_false(BuildSlotPlanner.is_unit_in_site_dropoff_range(unit.global_position, a,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, unit.get_world_3d()))
	var events := _observe(fx, [a, b], unit)
	var before := _snapshot(fx, [a, b], unit)
	var plan := _prepare(a, unit, {&"wood": 3, &"stone": 2})
	assert_true(plan.get("ok", false), str(plan))
	assert_eq(plan.get("deliverable"), {&"wood": 3, &"stone": 2})
	assert_true(plan.get("dry_run_only", false))
	assert_false(plan.get("commit_supported", true))
	assert_false(plan.get("physical_delivery_authorized", true))
	if plan.ok:
		assert_eq(plan.lot_debits.map(func(debit: Dictionary) -> Variant: return debit.lot_id),
			[&"a_stone", &"a_wood", &"z_wood"])
		assert_eq(plan.lot_debits[2].before, 3)
		assert_eq(plan.lot_debits[2].delivered, 1)
		assert_eq(plan.lot_debits[2].after, 2)
		assert_eq(plan.after.cargo.amounts, {&"wood": 8})
		assert_eq(plan.after.claim, {&"wood": 2})
		assert_eq(plan.after.cargo.ledger.lots[&"free_wood"], plan.before.cargo.ledger.lots[&"free_wood"])
		assert_eq(plan.after.cargo.ledger.lots[&"b_wood"], plan.before.cargo.ledger.lots[&"b_wood"])
		assert_eq(plan.before.accounting[&"wood"].transit, 6)
		assert_eq(plan.after.accounting[&"wood"], {"required": 8, "reserved": 2, "transit": 3, "buffer": 3, "consumed": 0, "missing": 0})
		assert_eq(_prepare(a, unit, {&"stone": 2, &"wood": 3}), plan)
		assert_true(_validate(a, unit, plan).ok)
	var maximum := _prepare(a, unit)
	assert_eq(maximum.get("deliverable"), {&"wood": 5, &"stone": 2})
	assert_eq(_prepare(a, unit, {&"wood": 6}).get("reason"), "requested_amount_exceeds_eligible")
	assert_eq(_prepare(b, unit).get("deliverable"), {&"wood": 4})
	assert_eq(_snapshot(fx, [a, b], unit), before)
	assert_eq(events, [])


func test_bad_requests_id_conflicts_and_legacy_delivery() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 8})
	var unit := _unit(fx, &"carrier")
	assert_false(unit.get_world_3d().has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))
	var fresh := _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit).reason, "no_eligible_delivery")
	assert_eq(_snapshot(fx, [site], unit), fresh)
	_withdraw(fx, site, unit, fx.wood, 2, &"reserved")
	var events := _observe(fx, [site], unit)
	var before := _snapshot(fx, [site], unit)
	for amounts: Variant in [[], null, {&"wood": -1}, {&"wood": 0}, {&"wood": 1.0}, {&"wood": true}, {123: 1}, {" ": 1}]:
		assert_eq(_prepare(site, unit, amounts).reason, "invalid_request")
	assert_eq(_prepare(site, unit, {&"stone": 1}).reason, "resource_not_required")
	assert_eq(_prepare(site, unit, {}, &" ").reason, "invalid_operation")
	assert_eq(_prepare(site, unit, {}, &"pickup_reserved").reason, "operation_conflict")
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_eq(events, [])
	var duplicate := _unit(fx, &"carrier")
	assert_eq(site.claim_pickup(duplicate, fx.wood.pile_id, &"wood", 1), 1)
	before = _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit).reason, "ambiguous_unit_identity")
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_eq(events, [])
	site.release_pickup_claim(duplicate)
	var legacy := _unit(fx, &"legacy", false)
	var inventory: SettlementInventory = fx.inventory
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(fx.wood.pile_id, site.reservation_id,
		WOOD, 2, legacy.get_carry_load()), 2)
	site.record_withdrawn_for_site(legacy, &"wood", 2)
	assert_eq(_prepare(site, legacy).reason, "provenance_disabled")
	assert_eq(site.accept_delivery_from_carry_load(legacy, legacy.get_carry_load()), {&"wood": 2})
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 2)
	assert_false(legacy.get_carry_load().is_provenance_enabled())


func test_claim_generation_world_and_balance_rejections_are_pure() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 8})
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 2, &"reserved")
	var remote := _fixture()
	var remote_unit := _unit(remote, &"remote")
	var load := unit.get_carry_load()
	var events := _observe(fx, [site], unit)
	assert_eq(_prepare(site, remote_unit).reason, "unit_world_mismatch")
	var entry: Dictionary = site._transit_claims[unit.get_instance_id()]
	for amount: int in [1, 3]:
		entry.amounts[&"wood"] = amount
		var before := _snapshot(fx, [site], unit)
		assert_eq(_prepare(site, unit).reason, "unreconciled_site_claim")
		assert_eq(_snapshot(fx, [site], unit), before)
	entry.amounts[&"wood"] = 2
	entry.carry_load = remote_unit.get_carry_load()
	assert_eq(_prepare(site, unit).reason, "carry_load_mismatch")
	entry.carry_load = load
	load._amounts[&"wood"] = 3
	assert_eq(_prepare(site, unit).reason, "unreconciled_cargo")
	load._amounts[&"wood"] = 2
	load._unit_weights[&"wood"] = 1
	assert_eq(_prepare(site, unit).reason, "resource_or_weight_mismatch")
	load._unit_weights[&"wood"] = WOOD.unit_weight
	site._generation += 1
	assert_eq(_prepare(site, unit).reason, "generation_mismatch")
	site._generation -= 1
	var region := site.region_id
	site.region_id = &"another_region"
	assert_eq(_prepare(site, unit).reason, "ambiguous_domain")
	site.region_id = region
	site._site_state = ConstructionSite.SiteState.COMPLETING
	assert_eq(_prepare(site, unit).reason, "site_not_active")
	site._site_state = ConstructionSite.SiteState.ACTIVE
	assert_true(_prepare(site, unit).ok)
	assert_eq(events, [])
	assert_true(load.add_with_provenance(&"unknown", &"unknown_lot", &"wood", WOOD.unit_weight, 1,
		CarryProvenanceLedger.SITE_RESERVED, &"unknown_site", 1).ok)
	events.clear()
	var snapshot := _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit).reason, "unknown_reserved_site")
	assert_eq(_snapshot(fx, [site], unit), snapshot)
	assert_eq(events, [])


func test_plan_revalidation_rejects_payload_changes_and_participant_aba() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 8})
	var peer := _create_site(fx, &"b", {&"wood": 4}, 14)
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 3, &"lot_a")
	_withdraw(fx, peer, unit, fx.wood, 2, &"lot_b")
	var load := unit.get_carry_load()
	var events := _observe(fx, [site, peer], unit)
	var before := _snapshot(fx, [site, peer], unit)
	var plan := _prepare(site, unit, {&"wood": 1})
	assert_true(plan.ok)
	assert_true(_validate(site, unit, plan).ok)
	var edited := plan.duplicate(true)
	edited.lot_debits[0].lot_id = &"lot_b"
	assert_eq(_validate(site, unit, edited).reason, "tampered_or_stale_plan")
	edited = plan.duplicate(true)
	edited.identity.world = 123
	assert_eq(_validate(site, unit, edited).reason, "identity_mismatch")
	edited = plan.duplicate(true)
	edited.after.accounting[&"wood"].buffer = 1.0
	assert_false(_validate(site, unit, edited).ok)
	edited = plan.duplicate(true)
	edited.erase("before")
	assert_eq(_validate(site, unit, edited).reason, "invalid_plan")
	assert_eq(_snapshot(fx, [site, peer], unit), before)
	assert_eq(events, [])

	load.set_base_capacity(79)
	load.set_base_capacity(80)
	assert_eq(_validate(site, unit, plan).reason, "stale_revision")
	plan = _prepare(site, unit)
	_gather(fx, unit, 1)
	assert_eq(_validate(site, unit, plan).reason, "stale_revision")
	plan = _prepare(site, unit)
	peer._transaction_revision += 1
	assert_eq(_validate(site, unit, plan).reason, "stale_revision")
	plan = _prepare(site, unit)
	site._transit_claims[unit.get_instance_id()].amounts[&"wood"] = 2
	assert_eq(_validate(site, unit, plan).reason, "unreconciled_site_claim")
	site._transit_claims[unit.get_instance_id()].amounts[&"wood"] = 3
	site._generation += 1
	assert_eq(_validate(site, unit, plan).reason, "generation_mismatch")
	site._generation -= 1

	# A different worker races with preparation through the real legacy buffer API.
	plan = _prepare(site, unit)
	var legacy := _unit(fx, &"legacy", false)
	var inventory: SettlementInventory = fx.inventory
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(fx.wood.pile_id, site.reservation_id,
		WOOD, 1, legacy.get_carry_load()), 1)
	site.record_withdrawn_for_site(legacy, &"wood", 1)
	assert_eq(site.accept_delivery_from_carry_load(legacy, legacy.get_carry_load()), {&"wood": 1})
	var after_external_change := _snapshot(fx, [site, peer], unit)
	events.clear()
	assert_eq(_validate(site, unit, plan).reason, "stale_revision")
	assert_eq(_snapshot(fx, [site, peer], unit), after_external_change)
	assert_eq(events, [])


func test_simulated_id_collision_and_buffer_overbooking_are_refused() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 5})
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 2, &"reserved")
	var load := unit.get_carry_load()
	assert_true(load.add_with_provenance(&"c3.1:4:drop:0", &"unrelated", &"wood",
		WOOD.unit_weight, 1, CarryProvenanceLedger.FREE_GATHERED).ok)
	var events := _observe(fx, [site], unit)
	var before := _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit).reason, "lot_debit_conflict")
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_eq(_prepare(site, unit, {}, &"distinct").get("deliverable"), {&"wood": 2})
	assert_eq(_snapshot(fx, [site], unit), before)
	# Inject inconsistent accounting while the ledger and current worker's claim still agree.
	site._delivered_buffer[&"wood"] = 1
	before = _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit, {}, &"distinct").reason, "accounting_invariant_violated")
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_eq(events, [])


func test_valid_plan_can_be_prepared_without_creating_an_authority() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 5})
	var unit := _unit(fx, &"carrier")
	var load := unit.get_carry_load()
	# Controlled bootstrap of an existing reconciled cargo without registering a C2 receipt.
	assert_true(fx.manager.withdraw_reserved_from_pile(fx.wood.pile_id, site.reservation_id, &"wood", 2))
	assert_true(load.add_with_provenance(&"historical", &"lot", &"wood", WOOD.unit_weight, 2,
		CarryProvenanceLedger.SITE_RESERVED, site.site_id, site.get_generation()).ok)
	site._ensure_transit_listener(unit, load)
	site._transit_claims[unit.get_instance_id()].amounts[&"wood"] = 2
	var events := _observe(fx, [site], unit)
	var before := _snapshot(fx, [site], unit)
	var plan := _prepare(site, unit)
	assert_eq(plan.get("deliverable"), {&"wood": 2})
	assert_true(_validate(site, unit, plan).ok)
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_false(unit.get_world_3d().has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))
	assert_eq(events, [])
