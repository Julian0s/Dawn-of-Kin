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


func _fixture(region: StringName = &"c3_region", viewport: SubViewport = null) -> Dictionary:
	if viewport == null:
		viewport = SubViewport.new()
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
	construction.configure(site_root, inventory, definitions, zone, null, region)
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
		_arm_order(site, unit)
	unit.global_position = pile.global_position + Vector3(0.4, 0, 0)
	assert_eq(site.claim_pickup(unit, pile.pile_id, pile.resource_id, quantity), quantity)
	var result: Dictionary = fx.coordinator.execute_reserved_withdrawal(
		site, unit, pile.pile_id, pile.resource_id, quantity, StringName("pickup_" + String(lot)), lot)
	assert_eq(result.get("withdrawn"), quantity, str(result))


func _gather(fx: Dictionary, unit: Unit, amount: int) -> void:
	var source := ResourceSource.new()
	fx.host.add_child(source)
	source.configure(&"tree", WOOD.duplicate(), 10, 5, 2)
	source.set(&"_tree_harvest_stage", ResourceSource.TreeHarvestStage.FALLEN)
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


func _arm_order(site: ConstructionSite, unit: Unit, force_transporter: bool = true) -> ConstructOrder:
	unit.cancel_current_order()
	# Simulate an already-running construction assignment without advancing AI.
	# The transaction checks this real order and the actual physics world.
	var order := ConstructOrder.new(site, null, force_transporter)
	order._unit = unit
	order.mark_running()
	unit._current_order = order
	var expected := ConstructionSite.WorkerRole.TRANSPORTER if force_transporter else ConstructionSite.WorkerRole.SOLO_SUPPLIER
	assert_eq(site.register_worker(unit, order, force_transporter), expected)
	return order
