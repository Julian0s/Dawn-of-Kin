class_name TestT362C49ManualComplementAuthority
extends TestCase

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
## Adversarial & regression suite for T3.6.2-C4.9 / P6-B2:
## Regional transactional authority, peer/domain isolation, signal-reentrancy protection,
## direct storage boundary enforcement, fail-closed checks, and DEC-11B preservation
## for ConstructionSite.authorize_manual_complement().

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const DOMAIN_META := ReservedWithdrawalCoordinator.DOMAIN_META

var _extra_nodes: Array[Node] = []
var _extra_managers: Array[GroundPileManager] = []
var _extra_releases: Array[Dictionary] = []
var _connections: Array[Array] = []


class CustomUnsupportedStorageSource extends SettlementStorageSource:
	var _amounts: Dictionary = {}
	var _reservations: Dictionary = {}
	var can_complement_calls: int = 0
	var complement_calls: int = 0

	func deposit(resource_id: StringName, amount: int) -> bool:
		if resource_id.is_empty() or amount <= 0:
			return false
		_amounts[resource_id] = int(_amounts.get(resource_id, 0)) + amount
		return true

	func get_physical_amount(resource_id: StringName) -> int:
		return int(_amounts.get(resource_id, 0))

	func get_reserved_amount(resource_id: StringName) -> int:
		var total: int = 0
		for rid: Variant in _reservations.keys():
			var bucket: Dictionary = _reservations[rid] as Dictionary
			total += int(bucket.get(resource_id, 0))
		return total

	func has_reservation(reservation_id: StringName) -> bool:
		return _reservations.has(reservation_id) and not (_reservations[reservation_id] as Dictionary).is_empty()

	func get_reservation_amount(reservation_id: StringName, resource_id: StringName) -> int:
		if not _reservations.has(reservation_id):
			return 0
		return int((_reservations[reservation_id] as Dictionary).get(resource_id, 0))

	func reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
		if reservation_id.is_empty() or has_reservation(reservation_id):
			return false
		for k: Variant in amounts.keys():
			var res_id := k as StringName
			if get_available_amount(res_id) < int(amounts[k]):
				return false
		_reservations[reservation_id] = amounts.duplicate()
		return true

	func can_complement_reservation(reservation_id: StringName, extra_amounts: Dictionary) -> bool:
		can_complement_calls += 1
		for k: Variant in extra_amounts.keys():
			var res_id := k as StringName
			if get_available_amount(res_id) < int(extra_amounts[k]):
				return false
		return not reservation_id.is_empty() and not extra_amounts.is_empty()

	func complement_reservation(reservation_id: StringName, extra_amounts: Dictionary) -> bool:
		complement_calls += 1
		if not can_complement_reservation(reservation_id, extra_amounts):
			return false
		if not _reservations.has(reservation_id):
			_reservations[reservation_id] = {}
		var bucket: Dictionary = _reservations[reservation_id] as Dictionary
		for k: Variant in extra_amounts.keys():
			var res_id := k as StringName
			bucket[res_id] = int(bucket.get(res_id, 0)) + int(extra_amounts[k])
		_emit_reservations_changed()
		_emit_storage_changed()
		return true


class DummyDomainOwner extends RefCounted:
	pass


class TestBuildOrder extends ConstructOrder:
	func start(body: CharacterBody3D, _move: UnitMovement, _nav: WorldNavigation) -> void:
		_unit = body as Unit
		mark_running()
		site.register_worker(_unit, self)

	func physics_update(_move: UnitMovement, _delta: float) -> void:
		pass


func after_test() -> void:
	for conn: Array in _connections:
		if conn.size() == 3:
			var sig: Signal = conn[0] as Signal
			var cb: Callable = conn[1] as Callable
			if cb.is_valid() and sig.is_connected(cb):
				sig.disconnect(cb)
	_connections.clear()
	for node: Node in _extra_nodes:
		if is_instance_valid(node) and node.is_inside_tree() and node.get_parent() != null:
			node.get_parent().remove_child(node)
	for rel: Dictionary in _extra_releases:
		var w: World3D = rel.get("world") as World3D
		var mgr: GroundPileManager = rel.get("manager") as GroundPileManager
		var tok: RefCounted = rel.get("token") as RefCounted
		var inv: SettlementInventory = rel.get("inventory") as SettlementInventory
		var reg: StringName = rel.get("region", &"default") as StringName
		if w != null and is_instance_valid(w) and mgr != null and tok != null:
			ReservedWithdrawalCoordinator.release_regional_domain(w, reg, mgr, tok, get_tree(), inv)
	_extra_releases.clear()
	for mgr: GroundPileManager in _extra_managers:
		if mgr != null and not mgr.is_shut_down():
			mgr.cleanup()
	_extra_managers.clear()
	for node: Node in _extra_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_extra_nodes.clear()


func _connect_tracked(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb, null])


func _make_custom_def(def_id: StringName, costs: Dictionary, work_sec: float = 4.0) -> BuildingDefinition:
	var def := BuildingDefinition.new()
	def.definition_id = def_id
	def.display_name = String(def_id)
	def.footprint_size = Vector2(3.0, 3.0)
	def.costs = costs.duplicate()
	def.build_work_required_sec = work_sec
	def.max_builders = 2
	def.visual_height = 2.0
	return def


func _create_gpm_region(region_id: StringName = &"c49_region", bind_owner: bool = true) -> Dictionary:
	var host := Node3D.new()
	host.name = "C49Host_%s" % String(region_id)
	add_test_child(host)
	_extra_nodes.append(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"c49_camp_%s" % String(region_id)
	zone.position = Vector3(-10.0, 0.0, -10.0)
	zone.zone_bounds_half_extents = Vector2(6.0, 6.0)
	zone.slot_spacing = 1.5
	zone.min_pile_clearance = 1.0
	zone.max_pile_amount = 50
	zone.decay_multiplier = 1.0
	host.add_child(zone)

	var piles_root := Node3D.new()
	piles_root.name = "PilesRoot"
	host.add_child(piles_root)

	var sites_root := Node3D.new()
	sites_root.name = "SitesRoot"
	host.add_child(sites_root)

	var defs: Dictionary = {
		&"wood": WOOD.duplicate(),
		&"stone": STONE.duplicate(),
	}
	var time_provider := SimulatedWorldTimeProvider.new(0.0)
	var manager := GroundPileManager.new(defs, zone, piles_root, time_provider)
	_extra_managers.append(manager)
	var inventory := SettlementInventory.new(manager)

	var cm := ConstructionManager.new()
	host.add_child(cm)
	cm.configure(sites_root, inventory, defs, zone, null, region_id)

	var owner_token: DummyDomainOwner = null
	if bind_owner:
		owner_token = DummyDomainOwner.new()
		assert_true(manager.bind_domain_owner(owner_token))
		_extra_releases.append({
			"world": host.get_world_3d(),
			"region": region_id,
			"manager": manager,
			"token": owner_token,
			"inventory": inventory,
		})

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
		"owner_token": owner_token,
	}


func _create_in_memory_region(region_id: StringName = &"c49_mem_region") -> Dictionary:
	var host := Node3D.new()
	host.name = "C49MemHost_%s" % String(region_id)
	add_test_child(host)
	_extra_nodes.append(host)

	var sites_root := Node3D.new()
	sites_root.name = "SitesRoot"
	host.add_child(sites_root)

	var defs: Dictionary = {
		&"wood": WOOD.duplicate(),
		&"stone": STONE.duplicate(),
	}
	var mem_src := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(mem_src)
	var cm := ConstructionManager.new()
	host.add_child(cm)
	cm.configure(sites_root, inventory, defs, null, null, region_id)

	return {
		"host": host,
		"sites_root": sites_root,
		"defs": defs,
		"source": mem_src,
		"inventory": inventory,
		"cm": cm,
	}


func _spawn_worker(parent: Node, unit_name: String, pos: Vector3) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.name = unit_name
	unit.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	unit.position = pos
	parent.add_child(unit)
	return unit


func test_01_blocks_manual_complement_when_site_or_domain_busy_with_zero_drift() -> void:
	var fx: Dictionary = _create_gpm_region(&"c49_busy_reg")
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var world: World3D = host.get_world_3d()

	var def_a: BuildingDefinition = _make_custom_def(&"c49_def_a", {&"wood": 4})
	var def_b: BuildingDefinition = _make_custom_def(&"c49_def_b", {&"wood": 2})

	assert_true(inventory.deposit(&"wood", 10))
	var res_a: Dictionary = cm.try_create_site_from_placement(def_a, Vector3(6.0, 0.0, 6.0))
	var res_b: Dictionary = cm.try_create_site_from_placement(def_b, Vector3(14.0, 0.0, 6.0))
	assert_true(bool(res_a["ok"]))
	assert_true(bool(res_b["ok"]))
	var site_a: ConstructionSite = res_a["site"] as ConstructionSite
	var site_b: ConstructionSite = res_b["site"] as ConstructionSite

	# Create missing wood deficit on site_a and deposit fresh free wood for complement.
	assert_true(inventory.release_batch(site_a.reservation_id, {&"wood": 2}))
	assert_true(inventory.withdraw(&"wood", 2))
	assert_eq(site_a.get_missing_amount(&"wood"), 2)
	assert_eq(inventory.get_available_amount(&"wood"), 4)

	# 1. Self _work_transaction_in_progress must block authorize_manual_complement cleanly.
	var rev_a0: int = site_a.get_transaction_revision()
	var rev_inv0: int = inventory.get_transaction_revision()
	var rev_mgr0: int = manager.get_transaction_revision()
	site_a._work_transaction_in_progress = true
	var intent_work := ManualComplementIntent.create_for_test(self, site_a)
	var out_work: Dictionary = site_a.authorize_manual_complement(intent_work, {}, false)
	site_a._work_transaction_in_progress = false
	assert_false(bool(out_work["ok"]), "Must block complement while own _work_transaction_in_progress is active")
	assert_true(intent_work.consumed, "Single-use intent must be consumed on blocked call")
	assert_eq(site_a.get_missing_amount(&"wood"), 2)
	assert_eq(site_a.get_transaction_revision(), rev_a0, "Blocked call must not drift site_a revision")
	assert_eq(inventory.get_transaction_revision(), rev_inv0)
	assert_eq(manager.get_transaction_revision(), rev_mgr0)

	# 2. Peer site _work_transaction_in_progress in the same region must block site_a.
	site_b._work_transaction_in_progress = true
	var intent_peer_work := ManualComplementIntent.create_for_test(self, site_a)
	var out_peer_work: Dictionary = site_a.authorize_manual_complement(intent_peer_work, {}, false)
	site_b._work_transaction_in_progress = false
	assert_false(bool(out_peer_work["ok"]), "Peer site active work lock in same domain must block complement")
	assert_eq(String(out_peer_work["reason"]), "busy")
	assert_true(intent_peer_work.consumed)
	assert_eq(site_a.get_missing_amount(&"wood"), 2)
	assert_eq(site_a.get_transaction_revision(), rev_a0)
	assert_eq(inventory.get_transaction_revision(), rev_inv0)
	assert_eq(manager.get_transaction_revision(), rev_mgr0)

	# 3. CampStorageZone transaction lock must block site_a.
	zone._coordinator_transaction_locked = true
	var intent_zone := ManualComplementIntent.create_for_test(self, site_a)
	var out_zone: Dictionary = site_a.authorize_manual_complement(intent_zone, {}, false)
	zone._coordinator_transaction_locked = false
	assert_false(bool(out_zone["ok"]), "CampStorageZone lock in same domain must block complement")
	assert_eq(String(out_zone["reason"]), "busy")
	assert_true(intent_zone.consumed)
	assert_eq(site_a.get_missing_amount(&"wood"), 2)
	assert_eq(site_a.get_transaction_revision(), rev_a0)

	# 4. Storage batch open (begin_batch) must block site_a without partial or queued mutation.
	manager.begin_batch()
	var intent_batch := ManualComplementIntent.create_for_test(self, site_a)
	var out_batch: Dictionary = site_a.authorize_manual_complement(intent_batch, {}, false)
	manager.end_batch(false)
	assert_false(bool(out_batch["ok"]), "Open storage batch must block complement")
	assert_eq(String(out_batch["reason"]), "busy")
	assert_true(intent_batch.consumed)
	assert_eq(site_a.get_missing_amount(&"wood"), 2)
	assert_eq(site_a.get_transaction_revision(), rev_a0)

	# 5. Live RegionalAuthority active_delivery / executing in (world, region) must block site_a.
	var domains: Dictionary = world.get_meta(DOMAIN_META, {}).duplicate() if world.has_meta(DOMAIN_META) else {}
	var auth := ReservedWithdrawalCoordinator.RegionalAuthority.new()
	auth.storage = weakref(manager)
	auth.is_executing = true
	domains[&"c49_busy_reg"] = auth
	world.set_meta(DOMAIN_META, domains)
	manager._withdrawal_world = weakref(world)
	manager._withdrawal_region = &"c49_busy_reg"

	var intent_auth := ManualComplementIntent.create_for_test(self, site_a)
	var out_auth: Dictionary = site_a.authorize_manual_complement(intent_auth, {}, false)
	auth.is_executing = false
	domains.erase(&"c49_busy_reg")
	if domains.is_empty():
		if world.has_meta(DOMAIN_META):
			world.remove_meta(DOMAIN_META)
	else:
		world.set_meta(DOMAIN_META, domains)
	manager._withdrawal_world = null
	manager._withdrawal_region = &""
	assert_false(bool(out_auth["ok"]), "Active RegionalAuthority execution must block complement")
	assert_eq(String(out_auth["reason"]), "busy")
	assert_true(intent_auth.consumed)
	assert_eq(site_a.get_missing_amount(&"wood"), 2)
	assert_eq(site_a.get_transaction_revision(), rev_a0)

	# Reusing intent_auth after RegionalAuthority unlocks must still be rejected as consumed.
	var out_reuse: Dictionary = site_a.authorize_manual_complement(intent_auth, {}, false)
	assert_false(bool(out_reuse["ok"]))
	assert_eq(String(out_reuse["reason"]), "unauthorized_or_missing_intent")

	# 6. Fresh intent succeeds cleanly once all locks clear.
	var intent_fresh := ManualComplementIntent.create_for_test(self, site_a)
	var out_ok: Dictionary = site_a.authorize_manual_complement(intent_fresh, {}, false)
	assert_true(bool(out_ok["ok"]))
	assert_true(intent_fresh.consumed)
	assert_eq(site_a.get_missing_amount(&"wood"), 0)
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 4)
	assert_true(site_a.verify_accounting_invariant())


func test_02_signal_reentrancy_and_direct_mutators_blocked_on_ground_pile_and_in_memory() -> void:
	# Part A: GroundPileManager — probe during reservations_changed, storage_changed, and peer state_changed.
	var fx: Dictionary = _create_gpm_region(&"c49_reent_gpm", false)
	var host: Node3D = fx["host"] as Node3D
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var world: World3D = host.get_world_3d()

	var def_a: BuildingDefinition = _make_custom_def(&"c49_rg_a", {&"wood": 4})
	var def_b: BuildingDefinition = _make_custom_def(&"c49_rg_b", {&"wood": 2})
	var def_ready: BuildingDefinition = _make_custom_def(&"c49_rg_ready", {&"stone": 2}, 1.0)

	assert_true(inventory.deposit(&"wood", 10))
	assert_true(inventory.deposit(&"stone", 2))
	var site_a: ConstructionSite = (cm.try_create_site_from_placement(def_a, Vector3(4.0, 0.0, 4.0)))["site"] as ConstructionSite
	var site_b: ConstructionSite = (cm.try_create_site_from_placement(def_b, Vector3(12.0, 0.0, 4.0)))["site"] as ConstructionSite
	var site_ready: ConstructionSite = (cm.try_create_site_from_placement(def_ready, Vector3(20.0, 0.0, 4.0)))["site"] as ConstructionSite

	# Make site_ready completion-ready (without dispatching completion yet).
	var carrier: Unit = _spawn_worker(host, "GpmCarrier", Vector3(20.0, 0.0, 6.2))
	carrier.set_physics_process(false)
	var worker: Unit = _spawn_worker(host, "GpmBuilder", Vector3(20.0, 0.0, 6.85))
	worker.set_physics_process(false)
	var carrier_order := TestBuildOrder.new(site_ready)
	var work_order := TestBuildOrder.new(site_ready)
	carrier.issue_order(carrier_order)
	worker.issue_order(work_order)
	var stone_pile: GroundResourcePile = manager.get_piles_for_resource(&"stone")[0]
	var taken_stone: int = inventory.withdraw_reserved_from_pile_to_carry_load(stone_pile.pile_id, site_ready.reservation_id, STONE, 2, carrier.get_carry_load())
	assert_eq(taken_stone, 2)
	site_ready.record_withdrawn_for_site(carrier, &"stone", 2)
	var delivered: Dictionary = site_ready.accept_delivery_from_carry_load(carrier, carrier.get_carry_load())
	assert_eq(int(delivered.get(&"stone", 0)), 2)
	site_ready._rebalance_worker_roles(false)
	var b_idx: int = site_ready.get_builder_slot_index(worker)
	assert_true(site_ready.assign_builder_slot_position(worker, b_idx, worker.global_position))
	for _step: int in range(4):
		await wait_physics_frames(1)
		if site_ready.get_site_state() == ConstructionSite.SiteState.COMPLETING:
			break
		var work_res: Dictionary = site_ready.contribute_work(worker, 0.25)
		assert_true(bool(work_res.get("ok", false)), str(work_res))
	assert_eq(site_ready.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	assert_true(site_ready.is_completion_ready())

	# Lose 2 wood on site_a and 1 wood on site_b, leave plenty of free wood.
	assert_true(inventory.release_batch(site_a.reservation_id, {&"wood": 2}))
	assert_true(inventory.release_batch(site_b.reservation_id, {&"wood": 1}))
	assert_true(inventory.withdraw(&"wood", 3))
	assert_true(inventory.deposit(&"wood", 6))

	var probe: Dictionary = {
		"res_done": false,
		"state_b_done": false,
		"region_active_during_res": false,
		"peer_busy_during_res": false,
		"peer_comp_ok": true,
		"peer_comp_reason": "",
		"create_ok": true,
		"create_reason": "",
		"complete_ok": true,
		"deposit_ok": true,
	}

	_connect_tracked(inventory.reservations_changed, func() -> void:
		if bool(probe["res_done"]):
			return
		probe["res_done"] = true
		probe["region_active_during_res"] = ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, &"c49_reent_gpm")
		probe["peer_busy_during_res"] = site_b.is_transaction_busy()
		var ib := ManualComplementIntent.create_for_test(self, site_b)
		var rb: Dictionary = site_b.authorize_manual_complement(ib, {}, false)
		probe["peer_comp_ok"] = bool(rb["ok"])
		probe["peer_comp_reason"] = String(rb["reason"])
		var cr: Dictionary = cm.try_create_site_from_placement(def_b, Vector3(28.0, 0.0, 4.0))
		probe["create_ok"] = bool(cr["ok"])
		probe["create_reason"] = String(cr["reason"])
		probe["complete_ok"] = cm.complete_site_transaction(site_ready)
		probe["deposit_ok"] = manager.deposit(&"wood", 5)
	)
	_connect_tracked(site_b.state_changed, func(_s: ConstructionSite) -> void:
		if bool(probe["state_b_done"]):
			return
		probe["state_b_done"] = true
		# Verify work on peer is also blocked during in-flight complement notification.
		probe["peer_work_progress"] = site_b.contribute_work(worker, 1.0)
	)

	var ia := ManualComplementIntent.create_for_test(self, site_a)
	var out_a: Dictionary = site_a.authorize_manual_complement(ia, {}, false)
	assert_true(bool(out_a["ok"]))
	assert_true(bool(probe["res_done"]))
	assert_true(bool(probe["region_active_during_res"]), "Regional transaction must be active during complement signals")
	assert_true(bool(probe["peer_busy_during_res"]), "Peer sites in region must be busy during complement signals")
	assert_false(bool(probe["peer_comp_ok"]), "Peer complement must be blocked during in-flight complement")
	assert_false(bool(probe["create_ok"]), "Site creation must be blocked during in-flight complement")
	assert_eq(String(probe["create_reason"]), "busy")
	assert_false(bool(probe["complete_ok"]), "Site completion must be blocked during in-flight complement")
	assert_false(bool(probe["deposit_ok"]), "Direct GroundPileManager deposit must be blocked during complement signals")
	assert_eq(site_b.get_missing_amount(&"wood"), 1, "Peer deficit must stay untouched")
	assert_eq(site_ready.get_site_state(), ConstructionSite.SiteState.COMPLETING, "Ready peer must not complete inside complement callback")

	# Part B: InMemoryStorageSource — all direct mutators + peer operations blocked during signals.
	var mfx: Dictionary = _create_in_memory_region(&"c49_reent_mem")
	var m_src: InMemoryStorageSource = mfx["source"] as InMemoryStorageSource
	var m_inv: SettlementInventory = mfx["inventory"] as SettlementInventory
	var m_cm: ConstructionManager = mfx["cm"] as ConstructionManager

	assert_true(m_inv.deposit(&"wood", 10))
	var m_site_a: ConstructionSite = (m_cm.try_create_site_from_placement(def_a, Vector3(4.0, 0.0, 12.0)))["site"] as ConstructionSite
	var m_site_b: ConstructionSite = (m_cm.try_create_site_from_placement(def_b, Vector3(12.0, 0.0, 12.0)))["site"] as ConstructionSite
	assert_true(m_inv.release_batch(m_site_a.reservation_id, {&"wood": 2}))
	assert_true(m_inv.release_batch(m_site_b.reservation_id, {&"wood": 1}))
	assert_true(m_inv.withdraw(&"wood", 3))
	assert_true(m_inv.deposit(&"wood", 4))

	var m_probe: Dictionary = {
		"inv_done": false,
		"src_locked": false,
		"src_deposit": true,
		"src_withdraw": true,
		"src_complement": true,
		"src_release": true,
		"src_decay": -1,
		"inv_withdraw": true,
		"peer_comp": true,
		"create_ok": true,
	}

	_connect_tracked(m_inv.inventory_changed, func() -> void:
		if bool(m_probe["inv_done"]):
			return
		m_probe["inv_done"] = true
		m_probe["src_locked"] = m_src.is_locked()
		m_probe["src_deposit"] = m_src.deposit(&"wood", 25)
		m_probe["src_withdraw"] = m_src.withdraw(&"wood", 1)
		m_probe["src_complement"] = m_src.complement_reservation(m_site_b.reservation_id, {&"wood": 1})
		m_probe["src_release"] = m_src.release_batch(m_site_a.reservation_id, {&"wood": 1})
		m_probe["src_decay"] = m_src.record_intentional_decay(&"wood", 2)
		m_probe["inv_withdraw"] = m_inv.withdraw(&"wood", 1)
		var mib := ManualComplementIntent.create_for_test(self, m_site_b)
		var mrb: Dictionary = m_site_b.authorize_manual_complement(mib, {}, false)
		m_probe["peer_comp"] = bool(mrb["ok"])
		var mcr: Dictionary = m_cm.try_create_site_from_placement(def_b, Vector3(20.0, 0.0, 12.0))
		m_probe["create_ok"] = bool(mcr["ok"])
	)

	var mia := ManualComplementIntent.create_for_test(self, m_site_a)
	var m_out: Dictionary = m_site_a.authorize_manual_complement(mia, {}, false)
	assert_true(bool(m_out["ok"]))
	assert_true(bool(m_probe["inv_done"]))
	assert_true(bool(m_probe["src_locked"]), "InMemoryStorageSource.is_locked() must be true during manual complement notifications")
	assert_false(bool(m_probe["src_deposit"]))
	assert_false(bool(m_probe["src_withdraw"]))
	assert_false(bool(m_probe["src_complement"]))
	assert_false(bool(m_probe["src_release"]))
	assert_eq(int(m_probe["src_decay"]), 0)
	assert_false(bool(m_probe["inv_withdraw"]))
	assert_false(bool(m_probe["peer_comp"]))
	assert_false(bool(m_probe["create_ok"]))
	assert_eq(m_src.get_physical_amount(&"wood"), 11)
	assert_eq(m_src.get_available_amount(&"wood"), 6)
	assert_eq(m_site_a.get_reserved_in_piles_amount(&"wood"), 4)
	assert_eq(m_site_b.get_reserved_in_piles_amount(&"wood"), 1)
	assert_false(m_src.is_locked(), "InMemoryStorageSource must unlock cleanly after complement returns")


func test_03_in_flight_complement_blocks_withdrawal_delivery_and_removal_while_other_region_stays_free() -> void:
	var fx_a: Dictionary = _create_gpm_region(&"c49_reg_alpha", true)
	var fx_b: Dictionary = _create_gpm_region(&"c49_reg_beta", false)
	var host_a: Node3D = fx_a["host"] as Node3D
	var zone_a: CampStorageZone = fx_a["zone"] as CampStorageZone
	var mgr_a: GroundPileManager = fx_a["manager"] as GroundPileManager
	var inv_a: SettlementInventory = fx_a["inventory"] as SettlementInventory
	var cm_a: ConstructionManager = fx_a["cm"] as ConstructionManager
	var world_a: World3D = host_a.get_world_3d()

	var mgr_b: GroundPileManager = fx_b["manager"] as GroundPileManager
	var inv_b: SettlementInventory = fx_b["inventory"] as SettlementInventory
	var cm_b: ConstructionManager = fx_b["cm"] as ConstructionManager

	var def_site: BuildingDefinition = _make_custom_def(&"c49_reg_iso", {&"wood": 4})
	assert_true(inv_a.deposit(&"wood", 8))
	assert_true(inv_b.deposit(&"wood", 6))
	var site_a1: ConstructionSite = (cm_a.try_create_site_from_placement(def_site, Vector3(4.0, 0.0, 4.0)))["site"] as ConstructionSite
	var site_a2: ConstructionSite = (cm_a.try_create_site_from_placement(def_site, Vector3(12.0, 0.0, 4.0)))["site"] as ConstructionSite
	var site_b1: ConstructionSite = (cm_b.try_create_site_from_placement(def_site, Vector3(4.0, 0.0, 20.0)))["site"] as ConstructionSite

	assert_true(inv_a.release_batch(site_a1.reservation_id, {&"wood": 2}))
	assert_true(inv_a.withdraw(&"wood", 2))
	assert_true(inv_a.deposit(&"wood", 2))

	assert_true(inv_b.release_batch(site_b1.reservation_id, {&"wood": 1}))
	assert_true(inv_b.withdraw(&"wood", 1))
	assert_true(inv_b.deposit(&"wood", 1))

	var unit_a: Unit = _spawn_worker(host_a, "WorkerAlpha", Vector3(10.0, 0.0, 10.0))
	assert_true(unit_a.get_carry_load().enable_provenance(&"worker_alpha"))
	var unit_d: Unit = _spawn_worker(host_a, "WorkerDeliv", Vector3(11.0, 0.0, 10.0))
	assert_true(unit_d.get_carry_load().enable_provenance(&"worker_deliv"))
	var seed_add: Dictionary = CarryFixture.add_lot(unit_d.get_carry_load(),
		&"op_seed",
		&"lot_seed_free",
		&"wood",
		WOOD.unit_weight,
		1,
		CarryProvenanceLedger.FREE_GATHERED
	)
	assert_true(bool(seed_add.get("ok", false)))
	var coord := ReservedWithdrawalCoordinator.new()
	var s_deliv := SelectiveSiteDeliveryCoordinator.new()
	var c_deliv := SelectiveCampDeliveryCoordinator.new()

	var slots_a: Array[Vector3] = zone_a.get_candidate_slots()
	var pile_a: GroundResourcePile = mgr_a.get_piles_for_resource(&"wood")[0]

	var probe: Dictionary = {
		"done": false,
		"withdraw_ok": true,
		"withdraw_reason": "",
		"s_deliv_ok": true,
		"c_deliv_ok": true,
		"c_deliv_reason": "",
		"removal_ok": true,
		"removal_reason": "",
		"release_ok": true,
		"release_reason": "",
		"other_region_active": true,
		"other_region_comp_ok": false,
	}

	_connect_tracked(inv_a.reservations_changed, func() -> void:
		if bool(probe["done"]):
			return
		probe["done"] = true
		var w_res: Dictionary = coord.execute_reserved_withdrawal(
			site_a2,
			unit_a,
			pile_a.pile_id,
			&"wood",
			1,
			&"op_c49_withdraw",
			&"lot_c49_withdraw"
		)
		probe["withdraw_ok"] = bool(w_res.get("ok", false))
		probe["withdraw_reason"] = String(w_res.get("reason", ""))

		var sd_res: Dictionary = s_deliv.execute_selective_site_delivery(site_a2, unit_d, &"op_c49_sd", {&"wood": 1})
		probe["s_deliv_ok"] = bool(sd_res.get("ok", false))

		var cd_res: Dictionary = c_deliv.execute_selective_camp_delivery(inv_a, zone_a, unit_d, &"c49_reg_alpha", &"op_c49_cd")
		probe["c_deliv_ok"] = bool(cd_res.get("ok", false))
		probe["c_deliv_reason"] = String(cd_res.get("reason", ""))

		var rem: Dictionary = ReservedWithdrawalCoordinator.inspect_domain_for_worker_removal_readonly(
			world_a,
			&"c49_reg_alpha",
			mgr_a,
			zone_a
		)
		probe["removal_ok"] = bool(rem.get("ok", false))
		probe["removal_reason"] = String(rem.get("reason", ""))

		var rel: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(
			world_a,
			&"c49_reg_alpha",
			mgr_a,
			fx_a["owner_token"] as RefCounted,
			get_tree(),
			inv_a
		)
		probe["release_ok"] = bool(rel.get("ok", false))
		probe["release_reason"] = String(rel.get("reason", ""))

		# Independent sibling region must remain completely unblocked.
		probe["other_region_active"] = ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(
			(fx_b["host"] as Node3D).get_world_3d(),
			&"c49_reg_beta"
		)
		var ib := ManualComplementIntent.create_for_test(self, site_b1)
		var ob: Dictionary = site_b1.authorize_manual_complement(ib, {}, false)
		probe["other_region_comp_ok"] = bool(ob["ok"])
	)
	assert_false(slots_a.is_empty())

	var ia := ManualComplementIntent.create_for_test(self, site_a1)
	var out_a: Dictionary = site_a1.authorize_manual_complement(ia, {}, false)
	assert_true(bool(out_a["ok"]))
	assert_true(bool(probe["done"]))
	assert_false(bool(probe["withdraw_ok"]), "ReservedWithdrawalCoordinator must refuse during in-flight complement")
	assert_eq(String(probe["withdraw_reason"]), "busy")
	assert_false(bool(probe["s_deliv_ok"]), "SelectiveSiteDeliveryCoordinator must refuse during in-flight complement")
	assert_false(bool(probe["c_deliv_ok"]), "SelectiveCampDeliveryCoordinator must refuse during in-flight complement")
	assert_false(bool(probe["removal_ok"]), "Worker removal inspection must report active regional transaction")
	assert_eq(String(probe["removal_reason"]), "regional_transaction_active")
	assert_false(bool(probe["release_ok"]), "release_regional_domain must refuse while complement holds domain")
	assert_eq(String(probe["release_reason"]), "busy")
	assert_false(bool(probe["other_region_active"]), "Unrelated region_b must not report active transaction")
	assert_true(bool(probe["other_region_comp_ok"]), "Unrelated region_b must still permit manual complement")
	assert_true(unit_a.get_carry_load().get_all_amounts().is_empty())


func test_04_fail_closed_on_unsupported_storage_and_ambiguous_domain() -> void:
	# Subcase A: Unknown custom SettlementStorageSource must fail-closed before mutating storage or bumping revisions.
	var host := Node3D.new()
	host.name = "C49CustomStorageHost"
	add_test_child(host)
	_extra_nodes.append(host)

	var custom := CustomUnsupportedStorageSource.new()
	assert_true(custom.deposit(&"wood", 6))
	assert_true(custom.reserve_batch(&"res_custom", {&"wood": 2}))
	var inv := SettlementInventory.new(custom)

	var site := ConstructionSite.new()
	host.add_child(site)
	var defs: Dictionary = {&"wood": WOOD.duplicate()}
	var custom_def: BuildingDefinition = _make_custom_def(&"c49_custom_def", {&"wood": 4})
	assert_true(site.configure(&"site_custom", &"res_custom", custom_def, inv, defs, &"c49_custom_reg"))
	assert_eq(site.get_missing_amount(&"wood"), 2)

	var rev_site_0: int = site.get_transaction_revision()
	var rev_inv_0: int = inv.get_transaction_revision()
	var can_res: Dictionary = site.can_authorize_manual_complement({}, false)
	assert_false(bool(can_res["ok"]))
	assert_eq(String(can_res["reason"]), "unsupported_storage_source")
	assert_eq(custom.can_complement_calls, 0, "Unsupported storage source must fail-closed before calling can_complement_reservation")

	var intent_custom := ManualComplementIntent.create_for_test(self, site)
	var auth_res: Dictionary = site.authorize_manual_complement(intent_custom, {}, false)
	assert_false(bool(auth_res["ok"]))
	assert_eq(String(auth_res["reason"]), "unsupported_storage_source")
	assert_true(intent_custom.consumed)
	assert_eq(custom.complement_calls, 0, "Unsupported storage source must fail-closed before calling complement_reservation")
	assert_eq(custom.get_reservation_amount(&"res_custom", &"wood"), 2)
	assert_eq(site.get_transaction_revision(), rev_site_0)
	assert_eq(inv.get_transaction_revision(), rev_inv_0)

	# Subcase B: Ambiguous domain (mismatched storage binding / cross-region shared backing) fails closed.
	var fx: Dictionary = _create_gpm_region(&"c49_ambig_reg", false)
	var mgr: GroundPileManager = fx["manager"] as GroundPileManager
	var inv_gpm: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm_gpm: ConstructionManager = fx["cm"] as ConstructionManager

	assert_true(inv_gpm.deposit(&"wood", 6))
	var s_gpm: ConstructionSite = (cm_gpm.try_create_site_from_placement(custom_def, Vector3(6.0, 0.0, 6.0)))["site"] as ConstructionSite
	assert_true(inv_gpm.release_batch(s_gpm.reservation_id, {&"wood": 2}))
	assert_true(inv_gpm.withdraw(&"wood", 2))
	assert_true(inv_gpm.deposit(&"wood", 2))

	mgr._withdrawal_world = weakref((fx["host"] as Node3D).get_world_3d())
	mgr._withdrawal_region = &"other_region"
	var rev_gpm_site_0: int = s_gpm.get_transaction_revision()
	var rev_gpm_inv_0: int = inv_gpm.get_transaction_revision()
	var rev_gpm_mgr_0: int = mgr.get_transaction_revision()

	var intent_ambig := ManualComplementIntent.create_for_test(self, s_gpm)
	var out_ambig: Dictionary = s_gpm.authorize_manual_complement(intent_ambig, {}, false)
	mgr._withdrawal_world = null
	mgr._withdrawal_region = &""
	assert_false(bool(out_ambig["ok"]))
	assert_eq(String(out_ambig["reason"]), "ambiguous_domain")
	assert_true(intent_ambig.consumed)
	assert_eq(s_gpm.get_missing_amount(&"wood"), 2)
	assert_eq(s_gpm.get_transaction_revision(), rev_gpm_site_0)
	assert_eq(inv_gpm.get_transaction_revision(), rev_gpm_inv_0)
	assert_eq(mgr.get_transaction_revision(), rev_gpm_mgr_0)


func test_05_legacy_complement_avoids_spurious_authority_and_preserves_dec11b_partial_and_zeroed_recovery() -> void:
	var fx: Dictionary = _create_gpm_region(&"c49_leg_reg", false)
	var host: Node3D = fx["host"] as Node3D
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_p: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var world: World3D = host.get_world_3d()

	assert_false((world.get_meta(DOMAIN_META, {}) as Dictionary).has(&"c49_leg_reg"), "Pure legacy setup starts with no RegionalAuthority")

	var def: BuildingDefinition = _make_custom_def(&"c49_leg_def", {&"wood": 6})
	assert_true(inventory.deposit(&"wood", 6))
	var site_main: ConstructionSite = (cm.try_create_site_from_placement(def, Vector3(4.0, 0.0, 4.0)))["site"] as ConstructionSite
	assert_true(inventory.deposit(&"wood", 4))
	var def_peer: BuildingDefinition = _make_custom_def(&"c49_leg_peer", {&"wood": 4})
	var site_peer: ConstructionSite = (cm.try_create_site_from_placement(def_peer, Vector3(12.0, 0.0, 4.0)))["site"] as ConstructionSite

	# Decay everything on piles so main drops 6 -> 0 (total erasure in ledger) and peer drops too.
	time_p.advance(1860.0)
	var losses: Dictionary = manager.step_decay()
	assert_gt(int(losses.get(&"wood", 0)), 0)
	assert_eq(site_main.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(site_main.get_missing_amount(&"wood"), 6)
	var peer_res_after_decay: int = site_peer.get_reserved_in_piles_amount(&"wood")

	# Free stock arrives: still ZERO automatic reallocation (DEC-11B).
	assert_true(inventory.deposit(&"wood", 4))
	assert_eq(site_main.get_missing_amount(&"wood"), 6)

	# Strict failed complement must preserve missing=6, available=4, consume intent, and NOT drift revisions or materialize authority.
	var rev_site_0: int = site_main.get_transaction_revision()
	var rev_peer_0: int = site_peer.get_transaction_revision()
	var rev_inv_0: int = inventory.get_transaction_revision()
	var rev_mgr_0: int = manager.get_transaction_revision()
	var intent_strict_fail := ManualComplementIntent.create_for_test(self, site_main)
	var out_fail: Dictionary = site_main.authorize_manual_complement(intent_strict_fail, {}, false)
	assert_false(bool(out_fail["ok"]))
	assert_eq(String(out_fail["reason"]), "insufficient_free_stock")
	assert_true(intent_strict_fail.consumed)
	assert_eq(site_main.get_transaction_revision(), rev_site_0, "Failed insufficient complement must not drift site revision")
	assert_eq(site_peer.get_transaction_revision(), rev_peer_0)
	assert_eq(inventory.get_transaction_revision(), rev_inv_0)
	assert_eq(manager.get_transaction_revision(), rev_mgr_0)
	assert_false((world.get_meta(DOMAIN_META, {}) as Dictionary).has(&"c49_leg_reg"))

	# Partial complement (allow_partial=true) succeeds cleanly, reserves 4, delivers 0 (physical transport still needed).
	var intent_partial := ManualComplementIntent.create_for_test(self, site_main)
	var out_partial: Dictionary = site_main.authorize_manual_complement(intent_partial, {}, true)
	assert_true(bool(out_partial["ok"]))
	assert_eq(int((out_partial["complemented"] as Dictionary).get(&"wood", 0)), 4)
	assert_eq(site_main.get_reserved_in_piles_amount(&"wood"), 4)
	assert_eq(site_main.get_missing_amount(&"wood"), 2)
	assert_eq(site_main.get_delivered_buffer_amount(&"wood"), 0, "DEC-11B requires physical transport")
	assert_eq(site_main.get_consumed_amount(&"wood"), 0)
	assert_eq(site_peer.get_reserved_in_piles_amount(&"wood"), peer_res_after_decay)
	assert_false((world.get_meta(DOMAIN_META, {}) as Dictionary).has(&"c49_leg_reg"), "Legacy complement must never materialize RegionalAuthority")

	# Deposit remaining 2, finish complement, then check idempotent nothing_missing keeps locks & invariants clean.
	assert_true(inventory.deposit(&"wood", 2))
	var intent_finish := ManualComplementIntent.create_for_test(self, site_main)
	var out_finish: Dictionary = site_main.authorize_manual_complement(intent_finish, {}, false)
	assert_true(bool(out_finish["ok"]))
	assert_eq(site_main.get_missing_amount(&"wood"), 0)
	assert_eq(site_main.get_reserved_in_piles_amount(&"wood"), 6)

	var rev_before_noop: int = site_main.get_transaction_revision()
	var intent_noop := ManualComplementIntent.create_for_test(self, site_main)
	var out_noop: Dictionary = site_main.authorize_manual_complement(intent_noop, {}, false)
	assert_true(bool(out_noop["ok"]))
	assert_eq(String(out_noop["reason"]), "nothing_missing")
	assert_eq(site_main.get_transaction_revision(), rev_before_noop, "No-op nothing_missing must not drift revision")
	assert_false(site_main.is_transaction_busy())
	assert_false(inventory.is_transaction_busy())
	assert_false(manager.is_locked())
	assert_false((world.get_meta(DOMAIN_META, {}) as Dictionary).has(&"c49_leg_reg"))
	assert_true(site_main.verify_accounting_invariant())
	assert_true(site_peer.verify_accounting_invariant())
