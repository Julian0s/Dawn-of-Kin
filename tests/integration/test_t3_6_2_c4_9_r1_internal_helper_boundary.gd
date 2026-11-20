class_name TestT362C49R1InternalHelperBoundary
extends TestCase
## Adversarial & regression suite for T3.6.2-C4.9-R1:
## Verifies that internal reservation, checkpoint-restore, and event-publication helpers on
## InMemoryStorageSource and GroundPileManager cannot be invoked directly as bypasses outside
## transactions, during SiteCreationScope/ManualComplementScope callbacks, or with missing,
## forged, expired, or cross-domain scopes, while preserving DEC-11B and legacy behavior.

const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const DOMAIN_META := ReservedWithdrawalCoordinator.DOMAIN_META

var _extra_nodes: Array[Node] = []
var _extra_managers: Array[GroundPileManager] = []
var _connections: Array[Array] = []


func after_each() -> void:
	for conn: Array in _connections:
		if conn.size() == 2:
			var sig: Signal = conn[0] as Signal
			var cb: Callable = conn[1] as Callable
			if cb.is_valid() and sig.is_connected(cb):
				sig.disconnect(cb)
	_connections.clear()
	for node: Node in _extra_nodes:
		if is_instance_valid(node) and node.is_inside_tree() and node.get_parent() != null:
			node.get_parent().remove_child(node)
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
	_connections.append([sig, cb])


func _make_def(def_id: StringName, costs: Dictionary) -> BuildingDefinition:
	var def := BuildingDefinition.new()
	def.definition_id = def_id
	def.display_name = String(def_id)
	def.footprint_size = Vector2(3.0, 3.0)
	def.costs = costs.duplicate()
	def.build_work_required_sec = 4.0
	def.max_builders = 2
	def.visual_height = 2.0
	return def


func _create_mem_env(region_id: StringName = &"c49_r1_mem") -> Dictionary:
	var host := Node3D.new()
	host.name = "C49R1MemHost_%s" % String(region_id)
	add_test_child(host)
	_extra_nodes.append(host)

	var sites_root := Node3D.new()
	sites_root.name = "SitesRoot"
	host.add_child(sites_root)

	var defs: Dictionary = {&"wood": WOOD.duplicate(), &"stone": STONE.duplicate()}
	var src := InMemoryStorageSource.new()
	var inv := SettlementInventory.new(src)
	var cm := ConstructionManager.new()
	host.add_child(cm)
	cm.configure(sites_root, inv, defs, null, null, region_id)
	return {
		"host": host,
		"sites_root": sites_root,
		"defs": defs,
		"source": src,
		"inventory": inv,
		"cm": cm,
	}


func _create_gpm_env(region_id: StringName = &"c49_r1_gpm") -> Dictionary:
	var host := Node3D.new()
	host.name = "C49R1GpmHost_%s" % String(region_id)
	add_test_child(host)
	_extra_nodes.append(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"c49_r1_camp_%s" % String(region_id)
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

	var defs: Dictionary = {&"wood": WOOD.duplicate(), &"stone": STONE.duplicate()}
	var time_p := SimulatedWorldTimeProvider.new(0.0)
	var mgr := GroundPileManager.new(defs, zone, piles_root, time_p)
	_extra_managers.append(mgr)
	var inv := SettlementInventory.new(mgr)
	var cm := ConstructionManager.new()
	host.add_child(cm)
	cm.configure(sites_root, inv, defs, zone, null, region_id)
	return {
		"host": host,
		"zone": zone,
		"piles_root": piles_root,
		"sites_root": sites_root,
		"defs": defs,
		"time": time_p,
		"manager": mgr,
		"inventory": inv,
		"cm": cm,
	}


func _build_forged_mc_scope(site: ConstructionSite, inv: SettlementInventory, src: SettlementStorageSource, gpm: GroundPileManager) -> ReservedWithdrawalCoordinator.ManualComplementScope:
	var fake := ReservedWithdrawalCoordinator.ManualComplementScope.new()
	fake.world = site.get_world_3d()
	fake.region_id = site.region_id
	fake.site = site
	fake.inventory = inv
	fake.storage_source = src
	fake.storage = gpm
	fake.sites = [site]
	return fake


func _build_forged_sc_scope(cm: ConstructionManager, inv: SettlementInventory, src: SettlementStorageSource, gpm: GroundPileManager) -> ReservedWithdrawalCoordinator.SiteCreationScope:
	var fake := ReservedWithdrawalCoordinator.SiteCreationScope.new()
	fake.world = cm._sites_root.get_world_3d() if cm != null and is_instance_valid(cm._sites_root) else null
	fake.region_id = cm.get_region_id()
	fake.manager = cm
	fake.inventory = inv
	fake.storage_source = src
	fake.storage = gpm
	return fake


func test_01_in_memory_internal_helpers_blocked_outside_and_inside_transactions() -> void:
	var fx: Dictionary = _create_mem_env(&"c49_r1_mem_a")
	var src: InMemoryStorageSource = fx["source"] as InMemoryStorageSource
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var def_a: BuildingDefinition = _make_def(&"r1_mem_a", {&"wood": 4})
	var def_b: BuildingDefinition = _make_def(&"r1_mem_b", {&"wood": 4})
	var def_c: BuildingDefinition = _make_def(&"r1_mem_c", {&"wood": 2})

	assert_true(inv.deposit(&"wood", 14))
	var site_a: ConstructionSite = (cm.try_create_site_from_placement(def_a, Vector3(4.0, 0.0, 4.0)))["site"] as ConstructionSite
	var site_b: ConstructionSite = (cm.try_create_site_from_placement(def_b, Vector3(12.0, 0.0, 4.0)))["site"] as ConstructionSite

	# Create deficits: 2 wood missing on site_a, 2 wood missing on site_b, plus plenty of free wood.
	assert_true(inv.release_batch(site_a.reservation_id, {&"wood": 2}))
	assert_true(inv.release_batch(site_b.reservation_id, {&"wood": 2}))
	assert_true(inv.withdraw(&"wood", 4))
	assert_true(inv.deposit(&"wood", 8))
	assert_eq(src.get_physical_amount(&"wood"), 18)
	assert_eq(src.get_available_amount(&"wood"), 14)

	# 1. Outside any transaction: direct call to _apply_complement_reservation_internal must fail cleanly.
	var sig_counts := {"res": 0, "stor": 0}
	_connect_tracked(src.reservations_changed, func() -> void:
		sig_counts["res"] = int(sig_counts["res"]) + 1
	)
	_connect_tracked(src.storage_changed, func() -> void:
		sig_counts["stor"] = int(sig_counts["stor"]) + 1
	)

	var rev_src_0: int = src.get_transaction_revision()
	var outside_apply: Dictionary = src._apply_complement_reservation_internal(site_b.reservation_id, {&"wood": 2})
	assert_false(bool(outside_apply.get("ok", false)), "Direct _apply_complement_reservation_internal outside transaction must be rejected")
	assert_eq(src.get_reservation_amount(site_b.reservation_id, &"wood"), 2)
	assert_eq(src.get_available_amount(&"wood"), 14)
	assert_eq(src.get_transaction_revision(), rev_src_0)
	assert_eq(int(sig_counts["res"]), 0)
	assert_eq(int(sig_counts["stor"]), 0)

	# Legacy public complement_reservation() outside transaction remains preserved!
	assert_true(src.reserve_batch(&"legacy_mem_res", {&"wood": 1}))
	assert_true(src.complement_reservation(&"legacy_mem_res", {&"wood": 1}))
	assert_eq(src.get_reservation_amount(&"legacy_mem_res", &"wood"), 2)
	assert_true(src.release_batch(&"legacy_mem_res"))
	assert_eq(src.get_available_amount(&"wood"), 14)

	# 2. During SiteCreationScope (site_creator_override): _apply_complement_reservation_internal & _can_complement_reservation_unlocked must fail.
	var sc_probe := {
		"called": false,
		"direct_ok": true,
		"forged_ok": true,
		"unlocked_can": true,
		"public_comp": true,
	}
	cm.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not bool(sc_probe["called"]):
			sc_probe["called"] = true
			var r_direct: Dictionary = src._apply_complement_reservation_internal(site_b.reservation_id, {&"wood": 2})
			sc_probe["direct_ok"] = bool(r_direct.get("ok", false))
			var forged_mc := _build_forged_mc_scope(site_b, inv, src, null)
			var r_forged: Dictionary = src._apply_manual_complement_silent(site_b.reservation_id, {&"wood": 2}, forged_mc)
			sc_probe["forged_ok"] = bool(r_forged.get("ok", false))
			sc_probe["unlocked_can"] = src._can_complement_reservation_unlocked(site_b.reservation_id, {&"wood": 1})
			sc_probe["public_comp"] = src.complement_reservation(site_b.reservation_id, {&"wood": 1})
		return ConstructionSite.new()

	var sc_res: Dictionary = cm.try_create_site_from_placement(def_c, Vector3(20.0, 0.0, 4.0))
	cm.site_creator_override = Callable()
	assert_true(bool(sc_res["ok"]))
	assert_true(bool(sc_probe["called"]))
	assert_false(bool(sc_probe["direct_ok"]), "During SiteCreationScope, _apply_complement_reservation_internal must refuse")
	assert_false(bool(sc_probe["forged_ok"]), "Forged ManualComplementScope must fail")
	assert_false(bool(sc_probe["unlocked_can"]), "_can_complement_reservation_unlocked must refuse while storage is locked without authorized scope")
	assert_false(bool(sc_probe["public_comp"]))
	assert_eq(src.get_reservation_amount(site_b.reservation_id, &"wood"), 2)

	# 3. During ManualComplementScope callbacks (reservations_changed, storage_changed, inventory_changed):
	var mc_probe := {
		"res_done": false,
		"stor_done": false,
		"inv_done": false,
		"res_apply_ok": true,
		"res_unlocked_can": true,
		"stor_apply_ok": true,
		"inv_apply_ok": true,
		"inv_forged_ok": true,
	}
	_connect_tracked(src.reservations_changed, func() -> void:
		if bool(mc_probe["res_done"]):
			return
		mc_probe["res_done"] = true
		mc_probe["res_apply_ok"] = bool(src._apply_complement_reservation_internal(site_b.reservation_id, {&"wood": 2}).get("ok", false))
		mc_probe["res_unlocked_can"] = src._can_complement_reservation_unlocked(site_b.reservation_id, {&"wood": 1})
	)
	_connect_tracked(src.storage_changed, func() -> void:
		if bool(mc_probe["stor_done"]):
			return
		mc_probe["stor_done"] = true
		mc_probe["stor_apply_ok"] = bool(src._apply_complement_reservation_internal(site_b.reservation_id, {&"wood": 2}).get("ok", false))
	)
	_connect_tracked(inv.inventory_changed, func() -> void:
		if bool(mc_probe["inv_done"]):
			return
		mc_probe["inv_done"] = true
		mc_probe["inv_apply_ok"] = bool(src._apply_complement_reservation_internal(site_b.reservation_id, {&"wood": 2}).get("ok", false))
		var forged := _build_forged_mc_scope(site_b, inv, src, null)
		mc_probe["inv_forged_ok"] = bool(src._apply_manual_complement_silent(site_b.reservation_id, {&"wood": 2}, forged).get("ok", false))
		if not ReservedWithdrawalCoordinator._active_manual_complement_scopes.is_empty():
			mc_probe["captured_scope"] = ReservedWithdrawalCoordinator._active_manual_complement_scopes[0]
	)

	var intent_a := ManualComplementIntent.create_for_test(self, site_a)
	var out_a: Dictionary = site_a.authorize_manual_complement(intent_a, {}, false)
	assert_true(bool(out_a["ok"]))
	assert_true(bool(mc_probe["res_done"]))
	assert_true(bool(mc_probe["stor_done"]))
	assert_true(bool(mc_probe["inv_done"]))
	assert_false(bool(mc_probe["res_apply_ok"]), "Direct _apply_complement_reservation_internal in reservations_changed must fail")
	assert_false(bool(mc_probe["res_unlocked_can"]), "_can_complement_reservation_unlocked in reservations_changed without scope must return false")
	assert_false(bool(mc_probe["stor_apply_ok"]), "Direct _apply_complement_reservation_internal in storage_changed must fail")
	assert_false(bool(mc_probe["inv_apply_ok"]), "Direct _apply_complement_reservation_internal in inventory_changed must fail")
	assert_false(bool(mc_probe["inv_forged_ok"]), "Forged scope in inventory_changed must fail")

	# Expired real scope captured from previous transaction must also fail!
	var expired_mem_scope: ReservedWithdrawalCoordinator.ManualComplementScope = mc_probe.get("captured_scope") as ReservedWithdrawalCoordinator.ManualComplementScope
	assert_not_null(expired_mem_scope)
	var exp_apply: Dictionary = src._apply_manual_complement_silent(site_b.reservation_id, {&"wood": 2}, expired_mem_scope)
	assert_false(bool(exp_apply.get("ok", false)), "Expired ManualComplementScope must be rejected on InMemoryStorageSource")
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 4)
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 2, "Unauthorized complement on site_b must not take effect")
	assert_eq(site_b.get_missing_amount(&"wood"), 2)
	assert_false(src.is_locked())


func test_02_ground_pile_apply_and_prepare_helpers_blocked_without_authorized_scope() -> void:
	var fx: Dictionary = _create_gpm_env(&"c49_r1_gpm_apply")
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var mgr: GroundPileManager = fx["manager"] as GroundPileManager
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var def_a: BuildingDefinition = _make_def(&"r1_gpm_a", {&"wood": 4})
	var def_b: BuildingDefinition = _make_def(&"r1_gpm_b", {&"wood": 4})
	var def_c: BuildingDefinition = _make_def(&"r1_gpm_c", {&"wood": 2})

	assert_true(inv.deposit(&"wood", 10))
	var site_a: ConstructionSite = (cm.try_create_site_from_placement(def_a, Vector3(4.0, 0.0, 4.0)))["site"] as ConstructionSite
	var site_b: ConstructionSite = (cm.try_create_site_from_placement(def_b, Vector3(12.0, 0.0, 4.0)))["site"] as ConstructionSite

	assert_true(inv.release_batch(site_a.reservation_id, {&"wood": 2}))
	assert_true(inv.release_batch(site_b.reservation_id, {&"wood": 2}))
	assert_true(inv.withdraw(&"wood", 4))

	# Create an independent free wood pile on another camp slot.
	var slots: Array[Vector3] = zone.get_candidate_slots()
	assert_true(slots.size() >= 3)
	var free_pile: GroundResourcePile = mgr.try_create_pile_at(&"wood", 8, slots[2])
	assert_not_null(free_pile)
	var fake_entries: Array[Dictionary] = [{"pile": free_pile, "resource_id": &"wood", "amount": 2}]

	# 1. Outside transaction: _prepare_reserve_plan_under_guard_internal & _apply_prepared_entries_silent_internal must fail.
	var mgr_rev_0: int = mgr.get_transaction_revision()
	var out_prep_0: Dictionary = mgr._prepare_reserve_plan_under_guard_internal(site_b.reservation_id, {&"wood": 2}, true)
	var out_apply_0: Dictionary = mgr._apply_prepared_entries_silent_internal(site_b.reservation_id, fake_entries)
	assert_false(bool(out_prep_0.get("ok", false)))
	assert_false(bool(out_apply_0.get("ok", false)))
	assert_eq(mgr.get_pile_reserved_amount(free_pile.pile_id), 0)
	assert_eq(mgr.get_transaction_revision(), mgr_rev_0)

	# 2. During SiteCreationScope (inside site_creator_override where _is_preparing_withdrawal=true, _is_mutating=false, _is_notifying=false):
	var sc_probe := {
		"called": false,
		"prep_ok": true,
		"apply_no_scope_ok": true,
		"apply_forged_sc_ok": true,
	}
	cm.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not bool(sc_probe["called"]):
			sc_probe["called"] = true
			sc_probe["prep_ok"] = bool(mgr._prepare_reserve_plan_under_guard_internal(site_b.reservation_id, {&"wood": 2}, true).get("ok", false))
			sc_probe["apply_no_scope_ok"] = bool(mgr._apply_prepared_entries_silent_internal(&"rogue_site_res", fake_entries).get("ok", false))
			var forged_sc := _build_forged_sc_scope(cm, inv, mgr, mgr)
			sc_probe["apply_forged_sc_ok"] = bool(mgr._apply_prepared_site_reservation_silent(&"rogue_site_res_2", fake_entries, forged_sc).get("ok", false))
		return ConstructionSite.new()

	var sc_out: Dictionary = cm.try_create_site_from_placement(def_c, Vector3(20.0, 0.0, 4.0))
	cm.site_creator_override = Callable()
	assert_true(bool(sc_out["ok"]))
	assert_true(bool(sc_probe["called"]))
	assert_false(bool(sc_probe["prep_ok"]), "Unauthorized _prepare_reserve_plan_under_guard_internal during SiteCreationScope must fail")
	assert_false(bool(sc_probe["apply_no_scope_ok"]), "Unauthorized _apply_prepared_entries_silent_internal during site_creator_override must fail")
	assert_false(bool(sc_probe["apply_forged_sc_ok"]), "Forged SiteCreationScope must fail")
	assert_false(mgr.has_reservation(&"rogue_site_res"))
	assert_false(mgr.has_reservation(&"rogue_site_res_2"))

	# 3. During ManualComplementScope signals AND direct state_changed fallback (unbound inventory signals -> _is_notifying=false):
	var mc_probe := {
		"res_done": false,
		"stor_done": false,
		"inv_done": false,
		"state_done": false,
		"res_apply_ok": true,
		"stor_apply_ok": true,
		"inv_apply_ok": true,
		"state_apply_ok": true,
		"state_forged_ok": true,
	}
	_connect_tracked(mgr.reservations_changed, func() -> void:
		if bool(mc_probe["res_done"]):
			return
		mc_probe["res_done"] = true
		mc_probe["res_apply_ok"] = bool(mgr._apply_prepared_entries_silent_internal(site_b.reservation_id, fake_entries).get("ok", false))
	)
	_connect_tracked(mgr.storage_changed, func() -> void:
		if bool(mc_probe["stor_done"]):
			return
		mc_probe["stor_done"] = true
		mc_probe["stor_apply_ok"] = bool(mgr._apply_prepared_entries_silent_internal(site_b.reservation_id, fake_entries).get("ok", false))
	)
	_connect_tracked(inv.inventory_changed, func() -> void:
		if bool(mc_probe["inv_done"]):
			return
		mc_probe["inv_done"] = true
		mc_probe["inv_apply_ok"] = bool(mgr._apply_prepared_entries_silent_internal(site_b.reservation_id, fake_entries).get("ok", false))
	)
	_connect_tracked(site_a.state_changed, func(_s: ConstructionSite) -> void:
		if bool(mc_probe["state_done"]):
			return
		mc_probe["state_done"] = true
		mc_probe["state_apply_ok"] = bool(mgr._apply_prepared_entries_silent_internal(site_b.reservation_id, fake_entries).get("ok", false))
		var forged_mc := _build_forged_mc_scope(site_b, inv, mgr, mgr)
		mc_probe["state_forged_ok"] = bool(mgr._apply_prepared_manual_complement_silent(site_b.reservation_id, fake_entries, forged_mc).get("ok", false))
	)

	# Unbind inventory echo on site_a specifically to also exercise direct state_changed while _is_preparing_withdrawal=true & _is_notifying=false.
	site_a._unbind_inventory()
	var intent_a := ManualComplementIntent.create_for_test(self, site_a)
	var out_a: Dictionary = site_a.authorize_manual_complement(intent_a, {}, false)
	site_a._bind_inventory()
	assert_true(bool(out_a["ok"]))
	assert_true(bool(mc_probe["res_done"]))
	assert_true(bool(mc_probe["stor_done"]))
	assert_true(bool(mc_probe["inv_done"]))
	assert_true(bool(mc_probe["state_done"]))
	assert_false(bool(mc_probe["res_apply_ok"]))
	assert_false(bool(mc_probe["stor_apply_ok"]))
	assert_false(bool(mc_probe["inv_apply_ok"]))
	assert_false(bool(mc_probe["state_apply_ok"]), "Unauthorized _apply_prepared_entries_silent_internal during state_changed (_is_notifying=false) must fail")
	assert_false(bool(mc_probe["state_forged_ok"]), "Forged ManualComplementScope during state_changed must fail")
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 2)
	assert_eq(site_b.get_missing_amount(&"wood"), 2)
	assert_false(mgr.is_locked())


func test_03_restore_checkpoint_and_publish_events_blocked_without_authorized_scope() -> void:
	var fx: Dictionary = _create_gpm_env(&"c49_r1_gpm_ckpt")
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var mgr: GroundPileManager = fx["manager"] as GroundPileManager
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var def_a: BuildingDefinition = _make_def(&"r1_ckpt_a", {&"wood": 4})
	var def_c: BuildingDefinition = _make_def(&"r1_ckpt_c", {&"wood": 2})

	assert_true(inv.deposit(&"wood", 10))
	var slots: Array[Vector3] = zone.get_candidate_slots()
	assert_false(slots.is_empty())

	# Capture stale pre-site checkpoint of ledger BEFORE creating site_a.
	var stale_ckpt: Dictionary = {
		"ledger_snapshot": mgr._ledger.snapshot_state(),
		"ledger_revision": mgr._ledger._transaction_revision,
		"storage_revision": mgr.get_transaction_revision(),
	}

	var site_a: ConstructionSite = (cm.try_create_site_from_placement(def_a, Vector3(4.0, 0.0, 4.0)))["site"] as ConstructionSite
	assert_true(mgr.has_reservation(site_a.reservation_id))
	assert_true(inv.release_batch(site_a.reservation_id, {&"wood": 2}))
	assert_true(inv.withdraw(&"wood", 2))
	assert_true(inv.deposit(&"wood", 4))

	var sig_counts := {"res": 0, "stor": 0, "inv_res": 0, "inv": 0}
	_connect_tracked(mgr.reservations_changed, func() -> void:
		sig_counts["res"] = int(sig_counts["res"]) + 1
	)
	_connect_tracked(mgr.storage_changed, func() -> void:
		sig_counts["stor"] = int(sig_counts["stor"]) + 1
	)
	_connect_tracked(inv.reservations_changed, func() -> void:
		sig_counts["inv_res"] = int(sig_counts["inv_res"]) + 1
	)
	_connect_tracked(inv.inventory_changed, func() -> void:
		sig_counts["inv"] = int(sig_counts["inv"]) + 1
	)

	# 1. Outside transaction: _restore_silent_checkpoint_internal & _publish_silent_reservation_events must do nothing.
	var rev_mgr_0: int = mgr.get_transaction_revision()
	var rev_inv_0: int = inv.get_transaction_revision()
	var rev_site_0: int = site_a.get_transaction_revision()
	mgr._restore_silent_checkpoint_internal(stale_ckpt)
	assert_true(mgr.has_reservation(site_a.reservation_id), "Unauthorized _restore_silent_checkpoint_internal outside tx must not erase ledger")
	assert_eq(mgr.get_reservation_amount(site_a.reservation_id, &"wood"), 2)
	assert_eq(mgr.get_transaction_revision(), rev_mgr_0)

	mgr._publish_silent_reservation_events()
	assert_eq(sig_counts, {"res": 0, "stor": 0, "inv_res": 0, "inv": 0}, "Unauthorized _publish_silent_reservation_events outside tx must emit zero signals")
	assert_eq(inv.get_transaction_revision(), rev_inv_0)
	assert_eq(site_a.get_transaction_revision(), rev_site_0)

	# 2. During SiteCreationScope (site_creator_override): neither _restore nor _publish may run!
	var sc_probe := {"called": false, "sig_snapshot": {}, "ledger_intact": false}
	cm.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not bool(sc_probe["called"]):
			sc_probe["called"] = true
			mgr._restore_silent_checkpoint_internal(stale_ckpt)
			var forged_sc := _build_forged_sc_scope(cm, inv, mgr, mgr)
			mgr._restore_site_reservation_checkpoint_silent(stale_ckpt, forged_sc)
			sc_probe["ledger_intact"] = mgr.has_reservation(site_a.reservation_id)
			var before_sigs: Dictionary = sig_counts.duplicate()
			mgr._publish_silent_reservation_events()
			mgr._publish_site_reservation_committed(forged_sc)
			sc_probe["sig_snapshot"] = {
				"d_res": int(sig_counts["res"]) - int(before_sigs["res"]),
				"d_stor": int(sig_counts["stor"]) - int(before_sigs["stor"]),
			}
		return ConstructionSite.new()

	var sc_res: Dictionary = cm.try_create_site_from_placement(def_c, Vector3(14.0, 0.0, 4.0))
	cm.site_creator_override = Callable()
	assert_true(bool(sc_res["ok"]))
	assert_true(bool(sc_probe["called"]))
	assert_true(bool(sc_probe["ledger_intact"]), "_restore_silent_checkpoint_internal during SiteCreationScope must not wipe reservations")
	assert_eq(sc_probe["sig_snapshot"], {"d_res": 0, "d_stor": 0}, "Unauthorized _publish during site_creator_override must emit zero signals")

	# 3. During ManualComplementScope callbacks: _restore must not wipe ledger; _publish must not cause extra reentrant emissions!
	var mc_probe := {
		"res_done": false,
		"stor_done": false,
		"inv_done": false,
		"res_before_extra": 0,
		"res_after_extra": 0,
		"stor_before_extra": 0,
		"stor_after_extra": 0,
	}
	_connect_tracked(mgr.reservations_changed, func() -> void:
		if bool(mc_probe["res_done"]):
			return
		mc_probe["res_done"] = true
		mgr._restore_silent_checkpoint_internal(stale_ckpt)
		var forged_mc := _build_forged_mc_scope(site_a, inv, mgr, mgr)
		mgr._restore_manual_complement_checkpoint_silent(stale_ckpt, forged_mc)
		mc_probe["res_before_extra"] = int(sig_counts["res"])
		mgr._publish_silent_reservation_events()
		mgr._publish_manual_complement_committed(forged_mc)
		mc_probe["res_after_extra"] = int(sig_counts["res"])
	)
	_connect_tracked(mgr.storage_changed, func() -> void:
		if bool(mc_probe["stor_done"]):
			return
		mc_probe["stor_done"] = true
		mgr._restore_silent_checkpoint_internal(stale_ckpt)
		mc_probe["stor_before_extra"] = int(sig_counts["stor"])
		mgr._publish_silent_reservation_events()
		mc_probe["stor_after_extra"] = int(sig_counts["stor"])
	)
	_connect_tracked(inv.inventory_changed, func() -> void:
		if bool(mc_probe["inv_done"]):
			return
		mc_probe["inv_done"] = true
		mgr._restore_silent_checkpoint_internal(stale_ckpt)
	)

	var sig_before_mc: Dictionary = sig_counts.duplicate()
	var intent_a := ManualComplementIntent.create_for_test(self, site_a)
	var out_a: Dictionary = site_a.authorize_manual_complement(intent_a, {}, false)
	assert_true(bool(out_a["ok"]))
	assert_true(bool(mc_probe["res_done"]))
	assert_true(bool(mc_probe["stor_done"]))
	assert_true(bool(mc_probe["inv_done"]))
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 4, "Unauthorized checkpoint restore during signals must not revert complement")
	assert_eq(int(mc_probe["res_after_extra"]) - int(mc_probe["res_before_extra"]), 0, "Unauthorized _publish inside reservations_changed must emit 0 extra signals")
	assert_eq(int(mc_probe["stor_after_extra"]) - int(mc_probe["stor_before_extra"]), 0, "Unauthorized _publish inside storage_changed must emit 0 extra signals")
	assert_eq(int(sig_counts["res"]) - int(sig_before_mc["res"]), 1, "Legitimate complement must emit exactly 1 reservations_changed")
	assert_eq(int(sig_counts["stor"]) - int(sig_before_mc["stor"]), 1, "Legitimate complement must emit exactly 1 storage_changed")


func test_04_cross_region_scope_rejected_and_rollback_and_legacy_preserved() -> void:
	# Cross-region scope checks between Region A and Region B (both GroundPileManager & InMemoryStorageSource).
	var fx_a: Dictionary = _create_gpm_env(&"c49_r1_cross_a")
	var fx_b: Dictionary = _create_gpm_env(&"c49_r1_cross_b")
	var mgr_a: GroundPileManager = fx_a["manager"] as GroundPileManager
	var inv_a: SettlementInventory = fx_a["inventory"] as SettlementInventory
	var cm_a: ConstructionManager = fx_a["cm"] as ConstructionManager

	var zone_b: CampStorageZone = fx_b["zone"] as CampStorageZone
	var mgr_b: GroundPileManager = fx_b["manager"] as GroundPileManager
	var inv_b: SettlementInventory = fx_b["inventory"] as SettlementInventory
	var cm_b: ConstructionManager = fx_b["cm"] as ConstructionManager

	var def_x: BuildingDefinition = _make_def(&"r1_cross_def", {&"wood": 4})
	assert_true(inv_a.deposit(&"wood", 6))
	assert_true(inv_b.deposit(&"wood", 8))
	var site_a: ConstructionSite = (cm_a.try_create_site_from_placement(def_x, Vector3(4.0, 0.0, 4.0)))["site"] as ConstructionSite
	var site_b: ConstructionSite = (cm_b.try_create_site_from_placement(def_x, Vector3(4.0, 0.0, 20.0)))["site"] as ConstructionSite
	assert_true(inv_a.release_batch(site_a.reservation_id, {&"wood": 2}))
	assert_true(inv_a.withdraw(&"wood", 2))
	assert_true(inv_a.deposit(&"wood", 2))
	assert_true(inv_b.release_batch(site_b.reservation_id, {&"wood": 2}))
	assert_true(inv_b.withdraw(&"wood", 2))
	assert_true(inv_b.deposit(&"wood", 2))

	var pile_b: GroundResourcePile = mgr_b.get_piles_for_resource(&"wood")[0]
	var entries_b: Array[Dictionary] = [{"pile": pile_b, "resource_id": &"wood", "amount": 2}]

	# Active ManualComplementScope in Region A must NOT authorize mutating Region B via internal helpers!
	var active_probe := {
		"done": false,
		"cross_apply_ok": true,
		"cross_pub_res": 0,
		"valid_cross_complement_ok": false,
	}
	_connect_tracked(mgr_b.reservations_changed, func() -> void:
		active_probe["cross_pub_res"] = int(active_probe["cross_pub_res"]) + 1
	)
	_connect_tracked(mgr_a.reservations_changed, func() -> void:
		if bool(active_probe["done"]):
			return
		active_probe["done"] = true
		var real_a_scopes: Array = ReservedWithdrawalCoordinator._active_manual_complement_scopes
		if not real_a_scopes.is_empty():
			var real_a_scope: ReservedWithdrawalCoordinator.ManualComplementScope = real_a_scopes[0] as ReservedWithdrawalCoordinator.ManualComplementScope
			active_probe["captured_a_scope"] = real_a_scope
			active_probe["cross_apply_ok"] = bool(mgr_b._apply_prepared_manual_complement_silent(site_b.reservation_id, entries_b, real_a_scope).get("ok", false))
			mgr_b._publish_manual_complement_committed(real_a_scope)
	)

	var intent_a := ManualComplementIntent.create_for_test(self, site_a)
	var out_a: Dictionary = site_a.authorize_manual_complement(intent_a, {}, false)
	assert_true(bool(out_a["ok"]))
	assert_true(bool(active_probe["done"]))
	assert_false(bool(active_probe["cross_apply_ok"]), "Active Region A scope must be rejected by Region B storage")
	assert_eq(int(active_probe["cross_pub_res"]), 0, "Region A scope must not publish events on Region B storage")
	assert_eq(site_b.get_missing_amount(&"wood"), 2)

	# Expired real scope captured from Region A must also fail on Region A after completion!
	var expired_a_scope: ReservedWithdrawalCoordinator.ManualComplementScope = active_probe.get("captured_a_scope") as ReservedWithdrawalCoordinator.ManualComplementScope
	assert_not_null(expired_a_scope)
	var pile_a: GroundResourcePile = mgr_a.get_piles_for_resource(&"wood")[0]
	var exp_entries_a: Array[Dictionary] = [{"pile": pile_a, "resource_id": &"wood", "amount": 1}]
	var exp_gpm_apply: Dictionary = mgr_a._apply_prepared_manual_complement_silent(site_a.reservation_id, exp_entries_a, expired_a_scope)
	assert_false(bool(exp_gpm_apply.get("ok", false)), "Expired ManualComplementScope must be rejected on GroundPileManager")

	# After Region A finishes, Region B can complement legitimately with DEC-11B & zero spurious RegionalAuthority.
	var intent_b := ManualComplementIntent.create_for_test(self, site_b)
	var out_b: Dictionary = site_b.authorize_manual_complement(intent_b, {}, false)
	assert_true(bool(out_b["ok"]))
	assert_eq(site_b.get_missing_amount(&"wood"), 0)
	assert_eq(site_b.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(site_b.get_consumed_amount(&"wood"), 0)
	assert_false((zone_b.get_world_3d().get_meta(DOMAIN_META, {}) as Dictionary).has(&"c49_r1_cross_b"))
	assert_true(site_a.verify_accounting_invariant())
	assert_true(site_b.verify_accounting_invariant())
