class_name TestT362C48R1StorageBoundary
extends TestCase
## Corrective adversarial & regression suite for T3.6.2-C4.8-R1:
## - Problem A: Direct public mutators on InMemoryStorageSource (and inherited batch mutators)
##   must be blocked while a SiteCreationScope is active, without breaking legitimate internal
##   silent reservation/rollback/publish or post-transaction normal usage.
## - Problem B: Unknown/arbitrary SettlementStorageSource implementations without transactional
##   silent/rollback guarantees must fail-closed with "unsupported_storage_source" before any mutation.
## - Full regression check across GroundPileManager, InMemoryStorageSource, multi-region, and P6-A.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const DOMAIN_META := ReservedWithdrawalCoordinator.DOMAIN_META

const FRAME_LIMIT := 2400

var _active_mains: Array[MainScene] = []
var _extra_nodes: Array[Node] = []
var _extra_managers: Array[GroundPileManager] = []
var _extra_releases: Array[Dictionary] = []
var _connections: Array[Array] = []
var _prior_scale: float = 1.0
var _prior_ticks: int = 60


class FailingConfigureSite extends ConstructionSite:
	func configure(
		_p_site_id: StringName,
		_p_reservation_id: StringName,
		_p_definition: BuildingDefinition,
		_p_inventory: SettlementInventory,
		_p_resource_defs: Dictionary = {},
		_p_region_id: StringName = &"default"
	) -> bool:
		return false


class BackendBuildOrder extends ConstructOrder:
	func start(body: CharacterBody3D, _move: UnitMovement, _nav: WorldNavigation) -> void:
		_unit = body as Unit
		mark_running()
		site.register_worker(_unit, self)

	func physics_update(_move: UnitMovement, _delta: float) -> void:
		pass


class CustomUnsupportedStorageSource extends SettlementStorageSource:
	var _amounts: Dictionary = {}
	var _reservations: Dictionary = {}
	var begin_batch_calls: int = 0
	var end_batch_calls: int = 0
	var reserve_batch_calls: int = 0
	var release_batch_calls: int = 0

	func begin_batch() -> void:
		begin_batch_calls += 1
		super.begin_batch()

	func end_batch(discard_dirty: bool = false) -> void:
		end_batch_calls += 1
		super.end_batch(discard_dirty)

	func get_physical_amount(resource_id: StringName) -> int:
		return int(_amounts.get(resource_id, 0))

	func get_all_physical_amounts() -> Dictionary:
		return _amounts.duplicate()

	func get_reserved_amount(resource_id: StringName) -> int:
		var total: int = 0
		for bucket_var: Variant in _reservations.values():
			total += int((bucket_var as Dictionary).get(resource_id, 0))
		return total

	func get_all_reserved_amounts() -> Dictionary:
		var totals: Dictionary = {}
		for bucket_var: Variant in _reservations.values():
			var bucket: Dictionary = bucket_var as Dictionary
			for k: Variant in bucket.keys():
				var rid: StringName = k as StringName
				totals[rid] = int(totals.get(rid, 0)) + int(bucket[rid])
		return totals

	func has_reservation(reservation_id: StringName) -> bool:
		return _reservations.has(reservation_id) and not (_reservations[reservation_id] as Dictionary).is_empty()

	func get_reservation_amount(reservation_id: StringName, resource_id: StringName) -> int:
		if not _reservations.has(reservation_id):
			return 0
		return int((_reservations[reservation_id] as Dictionary).get(resource_id, 0))

	func get_reservation_amounts(reservation_id: StringName) -> Dictionary:
		if not _reservations.has(reservation_id):
			return {}
		return (_reservations[reservation_id] as Dictionary).duplicate()

	func deposit(resource_id: StringName, amount: int) -> bool:
		if resource_id.is_empty() or amount <= 0:
			return false
		_amounts[resource_id] = get_physical_amount(resource_id) + amount
		_emit_storage_changed()
		return true

	func reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
		reserve_batch_calls += 1
		if not can_reserve_batch(reservation_id, amounts):
			return false
		_reservations[reservation_id] = amounts.duplicate()
		_emit_reservations_changed()
		_emit_storage_changed()
		return true

	func release_batch(reservation_id: StringName, _amounts: Dictionary = {}) -> bool:
		release_batch_calls += 1
		if not has_reservation(reservation_id):
			return false
		_reservations.erase(reservation_id)
		_emit_reservations_changed()
		_emit_storage_changed()
		return true


func before_each() -> void:
	_prior_scale = Engine.time_scale
	_prior_ticks = Engine.physics_ticks_per_second
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180


func after_each() -> void:
	for conn: Array in _connections:
		var sig: Signal = conn[0]
		if is_instance_id_valid(sig.get_object_id()) and sig.is_connected(conn[1]):
			sig.disconnect(conn[1])
	_connections.clear()

	for node: Node in _extra_nodes:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_extra_nodes.clear()

	for mgr: GroundPileManager in _extra_managers:
		if mgr != null:
			mgr.cleanup()
	_extra_managers.clear()

	for rel: Dictionary in _extra_releases:
		var w: World3D = rel["world"] as World3D
		var r: StringName = rel["region"] as StringName
		var s: GroundPileManager = rel["storage"] as GroundPileManager
		var tok: RefCounted = rel["token"] as RefCounted
		if w != null and is_instance_valid(w) and s != null and tok != null:
			ReservedWithdrawalCoordinator.release_regional_domain(w, r, s, tok, get_tree())
	_extra_releases.clear()

	var mains_copy: Array[MainScene] = _active_mains.duplicate()
	_active_mains.clear()
	for main: MainScene in mains_copy:
		if is_instance_valid(main):
			if main.get_parent() != null:
				main.get_parent().remove_child(main)
			main.free()

	Engine.time_scale = _prior_scale
	Engine.physics_ticks_per_second = _prior_ticks
	await get_tree().process_frame


func _watch(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb])


func _until(cond: Callable, limit: int = FRAME_LIMIT) -> bool:
	for _i: int in range(limit):
		if cond.call():
			return true
		await wait_physics_frames(1)
	return cond.call()


func _def(wood_cost: int = 3, stone_cost: int = 2, work_sec: float = 0.25) -> BuildingDefinition:
	var d := SHELTER.duplicate() as BuildingDefinition
	d.costs = {&"wood": wood_cost, &"stone": stone_cost}
	d.build_work_required_sec = work_sec
	return d


func _spawn_mem_env(region_id: StringName = &"mem_r1") -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(640, 480)
	add_test_child(vp)
	_extra_nodes.append(vp)

	var host := Node3D.new()
	host.name = "MemHost_%s" % String(region_id)
	vp.add_child(host)

	var sites_root := Node3D.new()
	sites_root.name = "SitesRoot"
	host.add_child(sites_root)

	var defs: Dictionary = {
		&"wood": WOOD.duplicate(),
		&"stone": STONE.duplicate(),
	}
	var mem_source := InMemoryStorageSource.new()
	var inv := SettlementInventory.new(mem_source)
	var cm := ConstructionManager.new()
	cm.name = "CM_Mem"
	host.add_child(cm)
	cm.configure(sites_root, inv, defs, null, null, region_id)

	return {
		"vp": vp,
		"world": host.get_world_3d(),
		"host": host,
		"sites_root": sites_root,
		"defs": defs,
		"source": mem_source,
		"inventory": inv,
		"cm": cm,
		"region": region_id,
	}


func _spawn_main() -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	add_test_child(vp)

	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp.add_child(main)
	_active_mains.append(main)

	var nav: WorldNavigation = main.get_test_map().get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 180))
	await wait_physics_frames(2)

	return {
		"vp": vp,
		"main": main,
		"world": main.get_test_map().get_world_3d(),
		"nav": nav,
		"cm": main.get_construction_manager(),
		"sites_root": main.get_construction_sites_root(),
		"inventory": main.get_settlement_inventory(),
		"storage": main.get_ground_pile_manager(),
		"camp": main.get_camp_storage_zone(),
		"units": main.get_units(),
	}


func _probe_all_direct_mutators(
	src: InMemoryStorageSource,
	target_rid: StringName,
	peer_rid: StringName,
	tag: String
) -> Dictionary:
	var forged := ReservedWithdrawalCoordinator.SiteCreationScope.new()
	forged.storage_source = src
	var forged_apply: Dictionary = src._apply_site_reservation_silent(
		StringName("forged_res_%s" % tag), {&"wood": 1}, forged
	)
	var pre_depth: int = src._batch_depth
	src.begin_batch()
	var batch_changed: bool = src._batch_depth != pre_depth
	if batch_changed:
		src.end_batch(false)

	return {
		"deposit": src.deposit(&"wood", 5),
		"withdraw": src.withdraw(&"wood", 1),
		"reserve": src.reserve_batch(StringName("rogue_%s" % tag), {&"wood": 1}),
		"complement_peer": src.complement_reservation(peer_rid, {&"wood": 1}),
		"wd_res_new": src.withdraw_reserved(target_rid, &"wood", 1),
		"wd_res_peer": src.withdraw_reserved(peer_rid, &"wood", 1),
		"wd_res_batch_peer": src.withdraw_reserved_batch(peer_rid, {&"wood": 1}),
		"release_new": src.release_batch(target_rid),
		"release_peer": src.release_batch(peer_rid),
		"decay": src.record_intentional_decay(&"wood", 1),
		"deposit_batch": src.deposit_batch({&"wood": 1}),
		"withdraw_batch": src.withdraw_batch({&"wood": 1}),
		"forged_scope_ok": bool(forged_apply.get("ok", false)),
		"batch_changed": batch_changed,
	}


func _assert_all_mutators_blocked(probe: Dictionary, label: String) -> void:
	for k: String in [
		"deposit", "withdraw", "reserve", "complement_peer", "release_new",
		"release_peer", "wd_res_new", "wd_res_peer", "deposit_batch",
		"withdraw_batch", "wd_res_batch_peer", "forged_scope_ok", "batch_changed",
	]:
		assert_false(bool(probe.get(k, true)), "%s: direct %s must be blocked" % [label, k])
	assert_eq(int(probe.get("decay", -1)), 0, "%s: direct decay must be blocked" % label)


## 1. Problem A: All direct InMemoryStorageSource mutators (including inherited batch ops)
##    must be refused across ALL 5 callback points during active site creation, and resume
##    working normally once the transaction exits.
func test_01_direct_in_memory_mutators_blocked_across_all_5_creation_callbacks() -> void:
	var fx: Dictionary = _spawn_mem_env(&"c48_r1_mem_1")
	var src: InMemoryStorageSource = fx["source"] as InMemoryStorageSource
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var sites_root: Node3D = fx["sites_root"] as Node3D

	assert_true(src.deposit(&"wood", 12))
	assert_true(src.deposit(&"stone", 8))

	var peer_res: Dictionary = cm.try_create_site_from_placement(_def(2, 1), Vector3(-12.0, 0.0, 6.0))
	assert_true(bool(peer_res.get("ok", false)), str(peer_res))
	var peer_site: ConstructionSite = peer_res["site"] as ConstructionSite
	var peer_rid: StringName = peer_site.reservation_id

	var target_pos := Vector3(6.0, 0.0, 6.0)
	var target_def := _def(3, 2)
	var probe_state := {
		"active": true,
		"expected_sid": &"",
		"expected_rid": &"",
		"signals": [] as Array[String],
		"override_probe": {},
		"tree_probe": {},
		"tree_valid": false,
		"probed_res": false,
		"storage_res_probe": {},
		"storage_res_site_found": false,
		"probed_chg": false,
		"storage_chg_probe": {},
		"storage_chg_site_found": false,
		"probed_created": false,
		"created_probe": {},
		"created_double": {},
	}

	cm.site_creator_override = func(sid: StringName, rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not bool(probe_state["active"]):
			return ConstructionSite.new()
		probe_state["expected_sid"] = sid
		probe_state["expected_rid"] = rid
		probe_state["override_probe"] = _probe_all_direct_mutators(src, rid, peer_rid, "override")
		return ConstructionSite.new()

	_watch(sites_root.child_entered_tree, func(child: Node) -> void:
		if not bool(probe_state["active"]) or not (child is ConstructionSite) or not (probe_state["tree_probe"] as Dictionary).is_empty():
			return
		var s: ConstructionSite = child as ConstructionSite
		probe_state["tree_valid"] = s.is_valid()
		probe_state["tree_probe"] = _probe_all_direct_mutators(src, s.reservation_id, peer_rid, "tree")
	)

	_watch(src.reservations_changed, func() -> void:
		if not bool(probe_state["active"]):
			return
		(probe_state["signals"] as Array[String]).append("src_res")
		if bool(probe_state["probed_res"]):
			return
		probe_state["probed_res"] = true
		var sid: StringName = probe_state["expected_sid"] as StringName
		var rid: StringName = probe_state["expected_rid"] as StringName
		probe_state["storage_res_site_found"] = cm.get_site_by_id(sid) != null and cm.get_site_by_id(sid).is_valid()
		probe_state["storage_res_probe"] = _probe_all_direct_mutators(src, rid, peer_rid, "src_res")
	)

	_watch(src.storage_changed, func() -> void:
		if not bool(probe_state["active"]):
			return
		(probe_state["signals"] as Array[String]).append("src_chg")
		if bool(probe_state["probed_chg"]):
			return
		probe_state["probed_chg"] = true
		var sid: StringName = probe_state["expected_sid"] as StringName
		var rid: StringName = probe_state["expected_rid"] as StringName
		probe_state["storage_chg_site_found"] = cm.get_site_by_id(sid) != null and cm.get_site_by_id(sid).is_valid()
		probe_state["storage_chg_probe"] = _probe_all_direct_mutators(src, rid, peer_rid, "src_chg")
	)

	_watch(cm.site_created, func(s: ConstructionSite) -> void:
		if not bool(probe_state["active"]) or bool(probe_state["probed_created"]):
			return
		probe_state["probed_created"] = true
		(probe_state["signals"] as Array[String]).append("site_created")
		probe_state["created_probe"] = _probe_all_direct_mutators(src, s.reservation_id, peer_rid, "site_created")
		probe_state["created_double"] = cm.try_create_site_from_placement(target_def, Vector3(18.0, 0.0, 6.0))
	)

	var res: Dictionary = cm.try_create_site_from_placement(target_def, target_pos)
	probe_state["active"] = false
	cm.site_creator_override = Callable()

	assert_true(bool(res.get("ok", false)), str(res))
	var created: ConstructionSite = res["site"] as ConstructionSite
	assert_not_null(created)
	if is_instance_valid(created):
		assert_true(created.is_valid())
	assert_eq(cm.get_sites().size(), 2)
	assert_eq(probe_state["signals"], ["src_res", "src_chg", "site_created"])
	assert_true(bool(probe_state["tree_valid"]))
	assert_true(bool(probe_state["storage_res_site_found"]))
	assert_true(bool(probe_state["storage_chg_site_found"]))

	_assert_all_mutators_blocked(probe_state["override_probe"] as Dictionary, "override")
	if not (probe_state["tree_probe"] as Dictionary).is_empty():
		_assert_all_mutators_blocked(probe_state["tree_probe"] as Dictionary, "child_entered_tree")
	if not (probe_state["storage_res_probe"] as Dictionary).is_empty():
		_assert_all_mutators_blocked(probe_state["storage_res_probe"] as Dictionary, "reservations_changed")
	if not (probe_state["storage_chg_probe"] as Dictionary).is_empty():
		_assert_all_mutators_blocked(probe_state["storage_chg_probe"] as Dictionary, "storage_changed")
	if not (probe_state["created_probe"] as Dictionary).is_empty():
		_assert_all_mutators_blocked(probe_state["created_probe"] as Dictionary, "site_created")
	assert_false(bool((probe_state["created_double"] as Dictionary).get("ok", true)))
	assert_eq(String((probe_state["created_double"] as Dictionary).get("reason", "")), "busy")

	# Exact conservation & zero lock leak after return
	assert_eq(src.get_physical_amount(&"wood"), 12)
	assert_eq(src.get_physical_amount(&"stone"), 8)
	assert_eq(src.get_reserved_amount(&"wood"), 5)
	assert_eq(src.get_reserved_amount(&"stone"), 3)
	assert_eq(src.get_available_amount(&"wood"), 7)
	assert_eq(src.get_available_amount(&"stone"), 5)
	if is_instance_valid(created):
		assert_eq(src.get_reservation_amounts(created.reservation_id), {&"wood": 3, &"stone": 2})
		assert_eq(src.get_all_reservation_ids(), [peer_rid, created.reservation_id])
	assert_eq(src.get_reservation_amounts(peer_rid), {&"wood": 2, &"stone": 1})
	assert_eq(src.get_total_decayed(&"wood"), 0)
	assert_true(src.has_method("is_locked") and not bool(src.call("is_locked")))
	assert_false(inv.is_transaction_busy())

	# Direct storage access resumes cleanly outside active creation
	assert_true(src.deposit(&"wood", 2))
	assert_true(src.withdraw(&"wood", 2))
	assert_true(src.complement_reservation(peer_rid, {&"wood": 1}))
	assert_eq(src.get_reservation_amount(peer_rid, &"wood"), 3)
	assert_true(src.withdraw_reserved(peer_rid, &"wood", 1))
	assert_eq(src.get_reservation_amount(peer_rid, &"wood"), 2)
	assert_eq(src.get_physical_amount(&"wood"), 11)
	assert_eq(src.record_intentional_decay(&"stone", 1), 1)
	assert_eq(src.get_total_decayed(&"stone"), 1)


## 2. Rollback integrity on InMemoryStorageSource under direct mutator probes:
##    failed override/configure never corrupts stock/peer/revisions and emits zero intermediate signals.
func test_02_in_memory_failure_rollback_blocks_direct_tamper_and_emits_zero_signals() -> void:
	var fx: Dictionary = _spawn_mem_env(&"c48_r1_mem_2")
	var src: InMemoryStorageSource = fx["source"] as InMemoryStorageSource
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	assert_true(src.deposit(&"wood", 10))
	assert_true(src.deposit(&"stone", 6))
	var peer_res: Dictionary = cm.try_create_site_from_placement(_def(2, 1), Vector3(-12.0, 0.0, 6.0))
	assert_true(bool(peer_res.get("ok", false)))
	var peer_site: ConstructionSite = peer_res["site"] as ConstructionSite
	var peer_rid: StringName = peer_site.reservation_id

	var sigs: Array[String] = []
	var rejected: Array[String] = []
	_watch(src.reservations_changed, func() -> void: sigs.append("src_res"))
	_watch(src.storage_changed, func() -> void: sigs.append("src_chg"))
	_watch(inv.reservations_changed, func() -> void: sigs.append("inv_res"))
	_watch(inv.inventory_changed, func() -> void: sigs.append("inv_chg"))
	_watch(cm.site_created, func(_s: ConstructionSite) -> void: sigs.append("site_created"))
	_watch(cm.site_creation_rejected, func(r: String, _m: String, _d: BuildingDefinition, _p: Vector3) -> void:
		rejected.append(r)
	)

	var rev_src_0: int = src.get_transaction_revision()
	var rev_inv_0: int = inv.get_transaction_revision()
	var rev_peer_0: int = peer_site.get_transaction_revision()

	var probes := {"null": {}, "cfg": {}}
	cm.site_creator_override = func(_sid: StringName, rid: StringName, _d: BuildingDefinition, _p: Vector3) -> Variant:
		probes["null"] = _probe_all_direct_mutators(src, rid, peer_rid, "rb_null")
		return null
	var res_null: Dictionary = cm.try_create_site_from_placement(_def(3, 2), Vector3(6.0, 0.0, 6.0))
	assert_false(bool(res_null.get("ok", true)))
	assert_eq(res_null.get("reason"), "site_instantiation_failed")

	cm.site_creator_override = func(_sid: StringName, rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		probes["cfg"] = _probe_all_direct_mutators(src, rid, peer_rid, "rb_cfg")
		return FailingConfigureSite.new()
	var res_cfg: Dictionary = cm.try_create_site_from_placement(_def(3, 2), Vector3(6.0, 0.0, 6.0))
	assert_false(bool(res_cfg.get("ok", true)))
	assert_eq(res_cfg.get("reason"), "site_instantiation_failed")
	cm.site_creator_override = Callable()

	_assert_all_mutators_blocked(probes["null"] as Dictionary, "rollback_null")
	_assert_all_mutators_blocked(probes["cfg"] as Dictionary, "rollback_configure")
	assert_eq(sigs, [], "Failed InMemory creations must emit ZERO intermediate signals")
	assert_eq(rejected, ["site_instantiation_failed", "site_instantiation_failed"])
	assert_eq(src.get_transaction_revision(), rev_src_0)
	assert_eq(inv.get_transaction_revision(), rev_inv_0)
	assert_eq(peer_site.get_transaction_revision(), rev_peer_0)
	assert_eq(src.get_all_reservation_ids(), [peer_rid])
	assert_eq(src.get_reservation_amounts(peer_rid), {&"wood": 2, &"stone": 1})
	assert_eq(src.get_available_amount(&"wood"), 8)
	assert_eq(src.get_available_amount(&"stone"), 5)
	assert_true(src.has_method("is_locked") and not bool(src.call("is_locked")))
	assert_false(inv.is_transaction_busy())

	# Subsequent creation & direct storage operations succeed cleanly
	var ok_after: Dictionary = cm.try_create_site_from_placement(_def(3, 2), Vector3(6.0, 0.0, 6.0))
	assert_true(bool(ok_after.get("ok", false)), str(ok_after))
	assert_eq(cm.get_sites().size(), 2)
	assert_true(src.deposit(&"stone", 2))
	assert_eq(src.get_physical_amount(&"stone"), 8)


## 3. Problem B: Unknown SettlementStorageSource subclass must fail-closed BEFORE any mutation,
##    signal, ID increment, or node allocation.
func test_03_unknown_storage_source_fails_closed_before_any_mutation() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(640, 480)
	add_test_child(vp)
	_extra_nodes.append(vp)

	var host := Node3D.new()
	vp.add_child(host)
	var sites_root := Node3D.new()
	host.add_child(sites_root)

	var custom := CustomUnsupportedStorageSource.new()
	assert_true(custom.deposit(&"wood", 10))
	assert_true(custom.deposit(&"stone", 6))
	var inv := SettlementInventory.new(custom)
	var cm := ConstructionManager.new()
	host.add_child(cm)
	cm.configure(sites_root, inv, {&"wood": WOOD.duplicate(), &"stone": STONE.duplicate()}, null, null, &"custom_reg")

	var events: Array[String] = []
	var rejected: Array[String] = []
	_watch(custom.storage_changed, func() -> void: events.append("src_chg"))
	_watch(custom.reservations_changed, func() -> void: events.append("src_res"))
	_watch(inv.inventory_changed, func() -> void: events.append("inv_chg"))
	_watch(inv.reservations_changed, func() -> void: events.append("inv_res"))
	_watch(cm.site_created, func(_s: ConstructionSite) -> void: events.append("site_created"))
	_watch(cm.site_creation_rejected, func(r: String, _m: String, _d: BuildingDefinition, _p: Vector3) -> void:
		rejected.append(r)
	)

	var rev_custom_0: int = custom.get_transaction_revision()
	var rev_inv_0: int = inv.get_transaction_revision()
	var next_seq_0: int = cm._next_site_seq

	var res: Dictionary = cm.try_create_site_from_placement(_def(2, 1), Vector3(6.0, 0.0, 6.0))
	assert_false(bool(res.get("ok", true)), "Unknown storage backend must be rejected fail-closed")
	assert_eq(String(res.get("reason", "")), "unsupported_storage_source")
	assert_null(res.get("site"))
	assert_eq(rejected, ["unsupported_storage_source"])
	assert_eq(events, [], "Unsupported storage rejection must emit ZERO storage/inventory/created signals")
	assert_eq(custom.begin_batch_calls, 0, "Must never call begin_batch on unsupported storage")
	assert_eq(custom.end_batch_calls, 0, "Must never call end_batch on unsupported storage")
	assert_eq(custom.reserve_batch_calls, 0, "Must never call reserve_batch on unsupported storage")
	assert_eq(custom.release_batch_calls, 0, "Must never call release_batch on unsupported storage")
	assert_eq(custom.get_transaction_revision(), rev_custom_0)
	assert_eq(inv.get_transaction_revision(), rev_inv_0)
	assert_eq(cm._next_site_seq, next_seq_0)
	assert_eq(custom.get_physical_amount(&"wood"), 10)
	assert_eq(custom.get_reserved_amount(&"wood"), 0)
	assert_eq(cm.get_sites().size(), 0)
	assert_eq(sites_root.get_child_count(), 0)
	assert_false(inv.is_transaction_busy())
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(host.get_world_3d(), &"custom_reg"))


## 4. Regression: GroundPileManager creation, multi-region isolation in same World3D,
##    and P6-A completion continue working cleanly together.
func test_04_regression_ground_pile_multiregion_and_p6a_completion_intact() -> void:
	var fx: Dictionary = await _spawn_main()
	var main: MainScene = fx["main"] as MainScene
	var world: World3D = fx["world"] as World3D
	var cm_main: ConstructionManager = fx["cm"] as ConstructionManager
	var inv_main: SettlementInventory = fx["inventory"] as SettlementInventory
	var units: Array[Unit] = fx["units"] as Array[Unit]

	assert_true(inv_main.deposit(&"wood", 8))
	assert_true(inv_main.deposit(&"stone", 4))

	# Distinct InMemory region in the same World3D creates independently during active main GroundPileManager creation
	var reg_mem_host := Node3D.new()
	reg_mem_host.name = "MemSubRegionHost"
	main.add_child(reg_mem_host)
	_extra_nodes.append(reg_mem_host)
	var reg_mem_sites := Node3D.new()
	reg_mem_host.add_child(reg_mem_sites)
	var mem_src := InMemoryStorageSource.new()
	assert_true(mem_src.deposit(&"wood", 6))
	assert_true(mem_src.deposit(&"stone", 4))
	var mem_inv := SettlementInventory.new(mem_src)
	var cm_mem := ConstructionManager.new()
	reg_mem_host.add_child(cm_mem)
	cm_mem.configure(reg_mem_sites, mem_inv, {&"wood": WOOD.duplicate(), &"stone": STONE.duplicate()}, null, null, &"mem_distinct_r1")

	var probe := {"mem_create_during_main": {}, "ran": false}
	cm_main.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not bool(probe["ran"]):
			probe["ran"] = true
			probe["mem_create_during_main"] = cm_mem.try_create_site_from_placement(_def(2, 1), Vector3(14.0, 0.0, 14.0))
		return ConstructionSite.new()

	var main_res: Dictionary = cm_main.try_create_site_from_placement(_def(2, 1, 0.25), Vector3(-6.0, 0.0, 1.5))
	cm_main.site_creator_override = Callable()
	assert_true(bool(main_res.get("ok", false)), str(main_res))
	assert_true(bool((probe["mem_create_during_main"] as Dictionary).get("ok", false)))
	assert_false(world.has_meta(DOMAIN_META))

	# Complete main site under P6-A cleanly
	var site_main: ConstructionSite = main_res["site"] as ConstructionSite
	var builder: Unit = units[0]
	builder.set_physics_process(false)
	builder.global_position = site_main.global_position + Vector3(0.0, 0.0, 2.85)
	var load := builder.get_carry_load()
	var w_entry: Dictionary = inv_main.get_reserved_pile_entries(site_main.reservation_id, &"wood")[0]
	assert_eq(inv_main.withdraw_reserved_from_pile_to_carry_load(int(w_entry["pile_id"]), site_main.reservation_id, WOOD, 2, load), 2)
	site_main.record_withdrawn_for_site(builder, &"wood", 2)
	var s_entry: Dictionary = inv_main.get_reserved_pile_entries(site_main.reservation_id, &"stone")[0]
	assert_eq(inv_main.withdraw_reserved_from_pile_to_carry_load(int(s_entry["pile_id"]), site_main.reservation_id, STONE, 1, load), 1)
	site_main.record_withdrawn_for_site(builder, &"stone", 1)
	assert_false(site_main.accept_delivery_from_carry_load(builder, load).is_empty())
	builder.issue_order(BackendBuildOrder.new(site_main))
	assert_true(site_main.try_promote_solo_to_builder(builder))
	var b_idx: int = site_main.get_builder_slot_index(builder)
	assert_true(site_main.assign_builder_slot_position(builder, b_idx, builder.global_position))
	var steps: int = 0
	while site_main.get_site_state() == ConstructionSite.SiteState.ACTIVE and steps < 20:
		await wait_physics_frames(1)
		site_main.contribute_work(builder, 0.25)
		steps += 1
	assert_eq(site_main.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	assert_true(await _until(func() -> bool: return cm_main.get_completed_buildings().size() == 1, 240))
	assert_eq(cm_main.get_sites().size(), 0)
	assert_eq(cm_mem.get_sites().size(), 1)
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, cm_main.get_region_id()))
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, cm_mem.get_region_id()))
	assert_true(mem_src.has_method("is_locked") and not bool(mem_src.call("is_locked")))
