class_name TestT362C49R2ScopeFinalization
extends TestCase
## Adversarial & regression suite for T3.6.2-C4.9-R2:
## Reproduces and verifies protection against premature publication and unauthorized/mismatched
## checkpoint restoration when an external callback (such as site_creator_override or
## child_entered_tree) obtains a genuine active SiteCreationScope or ManualComplementScope
## before commit confirmation.

const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")

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


func _create_gpm_env(region_id: StringName = &"c49_r2_gpm") -> Dictionary:
	var host := Node3D.new()
	host.name = "C49R2GpmHost_%s" % String(region_id)
	add_test_child(host)
	_extra_nodes.append(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"c49_r2_camp_%s" % String(region_id)
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


func _create_mem_env(region_id: StringName = &"c49_r2_mem") -> Dictionary:
	var host := Node3D.new()
	host.name = "C49R2MemHost_%s" % String(region_id)
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


func test_01_premature_publish_in_site_creator_override_then_null_rollback_ground_pile_and_in_memory() -> void:
	# Part A: GroundPileManager
	var fx_g: Dictionary = _create_gpm_env(&"c49_r2_gpm_pub")
	var mgr: GroundPileManager = fx_g["manager"] as GroundPileManager
	var inv_g: SettlementInventory = fx_g["inventory"] as SettlementInventory
	var cm_g: ConstructionManager = fx_g["cm"] as ConstructionManager

	var def_4w: BuildingDefinition = _make_def(&"r2_def_4w", {&"wood": 4})
	assert_true(inv_g.deposit(&"wood", 8))
	var res_1: Dictionary = cm_g.try_create_site_from_placement(def_4w, Vector3(4.0, 0.0, 4.0))
	assert_true(bool(res_1["ok"]))
	var site_1: ConstructionSite = res_1["site"] as ConstructionSite
	assert_eq(mgr.get_reserved_amount(&"wood"), 4)
	assert_eq(mgr.get_available_amount(&"wood"), 4)

	var sig_g := {"res": 0, "stor": 0, "inv_res": 0, "inv": 0, "created": 0, "rejected": 0}
	_connect_tracked(mgr.reservations_changed, func() -> void: sig_g["res"] = int(sig_g["res"]) + 1)
	_connect_tracked(mgr.storage_changed, func() -> void: sig_g["stor"] = int(sig_g["stor"]) + 1)
	_connect_tracked(inv_g.reservations_changed, func() -> void: sig_g["inv_res"] = int(sig_g["inv_res"]) + 1)
	_connect_tracked(inv_g.inventory_changed, func() -> void: sig_g["inv"] = int(sig_g["inv"]) + 1)
	_connect_tracked(cm_g.site_created, func(_s: ConstructionSite) -> void: sig_g["created"] = int(sig_g["created"]) + 1)
	_connect_tracked(cm_g.site_creation_rejected, func(_r: String, _m: String, _d: BuildingDefinition, _p: Vector3) -> void:
		sig_g["rejected"] = int(sig_g["rejected"]) + 1
	)

	var rev_mgr_0: int = mgr.get_transaction_revision()
	var rev_inv_0: int = inv_g.get_transaction_revision()
	var rev_site1_0: int = site_1.get_transaction_revision()
	var seq_g_0: int = cm_g._next_site_seq
	var probe_g := {"captured": false}

	cm_g.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not ReservedWithdrawalCoordinator._active_site_creation_scopes.is_empty():
			probe_g["captured"] = true
			var active_sc: ReservedWithdrawalCoordinator.SiteCreationScope = ReservedWithdrawalCoordinator._active_site_creation_scopes[0]
			mgr._publish_site_reservation_committed(active_sc)
			mgr._publish_silent_reservation_events(active_sc, false)
		return null

	var res_2: Dictionary = cm_g.try_create_site_from_placement(def_4w, Vector3(12.0, 0.0, 4.0))
	cm_g.site_creator_override = Callable()

	assert_true(bool(probe_g["captured"]))
	assert_false(bool(res_2["ok"]))
	assert_eq(String(res_2["reason"]), "site_instantiation_failed")
	assert_eq(mgr.get_all_reservation_ids(), [site_1.reservation_id], "Must not leave orphan reservation on GroundPileManager after premature publish attempt")
	assert_eq(mgr.get_reservation_amount(site_1.reservation_id, &"wood"), 4)
	assert_eq(mgr.get_physical_amount(&"wood"), 8)
	assert_eq(mgr.get_reserved_amount(&"wood"), 4)
	assert_eq(mgr.get_available_amount(&"wood"), 4)
	assert_eq(mgr.get_transaction_revision(), rev_mgr_0)
	assert_eq(inv_g.get_transaction_revision(), rev_inv_0)
	assert_eq(site_1.get_transaction_revision(), rev_site1_0)
	assert_eq(cm_g._next_site_seq, seq_g_0)
	assert_eq(int(sig_g["res"]), 0, "Premature publish during site_creator_override must emit zero reservations_changed signals")
	assert_eq(int(sig_g["stor"]), 0, "Premature publish during site_creator_override must emit zero storage_changed signals")
	assert_eq(int(sig_g["inv_res"]), 0)
	assert_eq(int(sig_g["inv"]), 0)
	assert_eq(int(sig_g["created"]), 0)
	assert_eq(int(sig_g["rejected"]), 1)
	assert_false(mgr.is_locked())
	assert_false(inv_g.is_transaction_busy())
	assert_false(site_1.is_transaction_busy())
	assert_true(ReservedWithdrawalCoordinator._active_site_creation_scopes.is_empty())

	# Part B: InMemoryStorageSource
	var fx_m: Dictionary = _create_mem_env(&"c49_r2_mem_pub")
	var src: InMemoryStorageSource = fx_m["source"] as InMemoryStorageSource
	var inv_m: SettlementInventory = fx_m["inventory"] as SettlementInventory
	var cm_m: ConstructionManager = fx_m["cm"] as ConstructionManager

	assert_true(inv_m.deposit(&"wood", 8))
	var m_res_1: Dictionary = cm_m.try_create_site_from_placement(def_4w, Vector3(4.0, 0.0, 4.0))
	assert_true(bool(m_res_1["ok"]))
	var m_site_1: ConstructionSite = m_res_1["site"] as ConstructionSite

	var sig_m := {"res": 0, "stor": 0, "inv_res": 0, "inv": 0, "created": 0, "rejected": 0}
	_connect_tracked(src.reservations_changed, func() -> void: sig_m["res"] = int(sig_m["res"]) + 1)
	_connect_tracked(src.storage_changed, func() -> void: sig_m["stor"] = int(sig_m["stor"]) + 1)
	_connect_tracked(inv_m.reservations_changed, func() -> void: sig_m["inv_res"] = int(sig_m["inv_res"]) + 1)
	_connect_tracked(inv_m.inventory_changed, func() -> void: sig_m["inv"] = int(sig_m["inv"]) + 1)
	_connect_tracked(cm_m.site_created, func(_s: ConstructionSite) -> void: sig_m["created"] = int(sig_m["created"]) + 1)
	_connect_tracked(cm_m.site_creation_rejected, func(_r: String, _m: String, _d: BuildingDefinition, _p: Vector3) -> void:
		sig_m["rejected"] = int(sig_m["rejected"]) + 1
	)

	var rev_src_0: int = src.get_transaction_revision()
	var rev_invm_0: int = inv_m.get_transaction_revision()
	var rev_msite1_0: int = m_site_1.get_transaction_revision()
	var seq_m_0: int = cm_m._next_site_seq
	var probe_m := {"captured": false}

	cm_m.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not ReservedWithdrawalCoordinator._active_site_creation_scopes.is_empty():
			probe_m["captured"] = true
			var active_sc: ReservedWithdrawalCoordinator.SiteCreationScope = ReservedWithdrawalCoordinator._active_site_creation_scopes[0]
			src._publish_site_reservation_committed(active_sc)
		return null

	var m_res_2: Dictionary = cm_m.try_create_site_from_placement(def_4w, Vector3(12.0, 0.0, 4.0))
	cm_m.site_creator_override = Callable()

	assert_true(bool(probe_m["captured"]))
	assert_false(bool(m_res_2["ok"]))
	assert_eq(String(m_res_2["reason"]), "site_instantiation_failed")
	assert_eq(src.get_all_reservation_ids(), [m_site_1.reservation_id], "Must not leave orphan reservation on InMemoryStorageSource after premature publish attempt")
	assert_eq(src.get_reservation_amount(m_site_1.reservation_id, &"wood"), 4)
	assert_eq(src.get_physical_amount(&"wood"), 8)
	assert_eq(src.get_reserved_amount(&"wood"), 4)
	assert_eq(src.get_available_amount(&"wood"), 4)
	assert_eq(src.get_transaction_revision(), rev_src_0)
	assert_eq(inv_m.get_transaction_revision(), rev_invm_0)
	assert_eq(m_site_1.get_transaction_revision(), rev_msite1_0)
	assert_eq(cm_m._next_site_seq, seq_m_0)
	assert_eq(int(sig_m["res"]), 0, "Premature publish on InMemoryStorageSource must emit zero reservations_changed signals")
	assert_eq(int(sig_m["stor"]), 0, "Premature publish on InMemoryStorageSource must emit zero storage_changed signals")
	assert_eq(int(sig_m["inv_res"]), 0)
	assert_eq(int(sig_m["inv"]), 0)
	assert_eq(int(sig_m["created"]), 0)
	assert_eq(int(sig_m["rejected"]), 1)
	assert_false(src.is_locked())
	assert_false(inv_m.is_transaction_busy())
	assert_false(m_site_1.is_transaction_busy())
	assert_true(ReservedWithdrawalCoordinator._active_site_creation_scopes.is_empty())


func test_02_premature_publish_in_child_entered_tree_then_overlap_failure_rolls_back_cleanly() -> void:
	var fx: Dictionary = _create_gpm_env(&"c49_r2_tree_pub")
	var sites_root: Node3D = fx["sites_root"] as Node3D
	var mgr: GroundPileManager = fx["manager"] as GroundPileManager
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var def_4w: BuildingDefinition = _make_def(&"r2_tree_4w", {&"wood": 4})
	assert_true(inv.deposit(&"wood", 8))
	var res_1: Dictionary = cm.try_create_site_from_placement(def_4w, Vector3(4.0, 0.0, 4.0))
	assert_true(bool(res_1["ok"]))
	var site_1: ConstructionSite = res_1["site"] as ConstructionSite

	var sig := {"res": 0, "stor": 0}
	_connect_tracked(mgr.reservations_changed, func() -> void: sig["res"] = int(sig["res"]) + 1)
	_connect_tracked(mgr.storage_changed, func() -> void: sig["stor"] = int(sig["stor"]) + 1)

	var rev_mgr_0: int = mgr.get_transaction_revision()
	var rev_inv_0: int = inv.get_transaction_revision()
	var seq_0: int = cm._next_site_seq
	var tree_probe := {"entered": false}

	_connect_tracked(sites_root.child_entered_tree, func(child: Node) -> void:
		if bool(tree_probe["entered"]):
			return
		tree_probe["entered"] = true
		if not ReservedWithdrawalCoordinator._active_site_creation_scopes.is_empty():
			var active_sc: ReservedWithdrawalCoordinator.SiteCreationScope = ReservedWithdrawalCoordinator._active_site_creation_scopes[0]
			mgr._publish_site_reservation_committed(active_sc)
			mgr._publish_silent_reservation_events(active_sc, false)
		# Move child onto site_1's footprint so post-tree-entry overlap validation fails!
		if child is Node3D:
			(child as Node3D).position = site_1.position
	)

	var res_2: Dictionary = cm.try_create_site_from_placement(def_4w, Vector3(12.0, 0.0, 4.0))
	assert_true(bool(tree_probe["entered"]))
	assert_false(bool(res_2["ok"]))
	assert_eq(String(res_2["reason"]), "site_instantiation_failed")
	assert_eq(mgr.get_all_reservation_ids(), [site_1.reservation_id], "Premature publish during child_entered_tree must not prevent rollback")
	assert_eq(mgr.get_reserved_amount(&"wood"), 4)
	assert_eq(mgr.get_available_amount(&"wood"), 4)
	assert_eq(mgr.get_transaction_revision(), rev_mgr_0)
	assert_eq(inv.get_transaction_revision(), rev_inv_0)
	assert_eq(cm._next_site_seq, seq_0)
	assert_eq(int(sig["res"]), 0)
	assert_eq(int(sig["stor"]), 0)


func test_03_mismatched_or_fabricated_checkpoint_with_real_active_scope_rejected_on_both_backends() -> void:
	# Part A: GroundPileManager — stale checkpoint from before site_1 + real active SiteCreationScope
	var fx_g: Dictionary = _create_gpm_env(&"c49_r2_gpm_ckpt")
	var mgr: GroundPileManager = fx_g["manager"] as GroundPileManager
	var inv_g: SettlementInventory = fx_g["inventory"] as SettlementInventory
	var cm_g: ConstructionManager = fx_g["cm"] as ConstructionManager

	var def_4w: BuildingDefinition = _make_def(&"r2_ckpt_4w", {&"wood": 4})
	assert_true(inv_g.deposit(&"wood", 8))

	# Snapshot empty ledger before site_1 exists.
	var stale_empty_gpm_ckpt: Dictionary = {
		"ledger_snapshot": mgr._ledger.snapshot_state(),
		"ledger_revision": mgr._ledger._transaction_revision,
		"storage_revision": mgr.get_transaction_revision(),
	}

	var res_1: Dictionary = cm_g.try_create_site_from_placement(def_4w, Vector3(4.0, 0.0, 4.0))
	assert_true(bool(res_1["ok"]))
	var site_1: ConstructionSite = res_1["site"] as ConstructionSite
	assert_eq(mgr.get_reservation_amount(site_1.reservation_id, &"wood"), 4)

	var rev_mgr_0: int = mgr.get_transaction_revision()
	var probe_g := {"called": false, "site1_during_override": 0}

	cm_g.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		probe_g["called"] = true
		var active_sc: ReservedWithdrawalCoordinator.SiteCreationScope = ReservedWithdrawalCoordinator._active_site_creation_scopes[0]
		# Try restoring stale pre-site_1 checkpoint and a fabricated checkpoint using the real active scope.
		mgr._restore_site_reservation_checkpoint_silent(stale_empty_gpm_ckpt, active_sc)
		mgr._restore_silent_checkpoint_internal(stale_empty_gpm_ckpt, active_sc, false)
		mgr._restore_site_reservation_checkpoint_silent({"ledger_snapshot": {}, "ledger_revision": 0, "storage_revision": 0}, active_sc)
		probe_g["site1_during_override"] = mgr.get_reservation_amount(site_1.reservation_id, &"wood")
		return null

	var res_2: Dictionary = cm_g.try_create_site_from_placement(def_4w, Vector3(12.0, 0.0, 4.0))
	cm_g.site_creator_override = Callable()

	assert_true(bool(probe_g["called"]))
	assert_false(bool(res_2["ok"]))
	assert_eq(int(probe_g["site1_during_override"]), 4, "Stale checkpoint with real active scope must not erase site_1 reservation during override")
	assert_eq(mgr.get_all_reservation_ids(), [site_1.reservation_id], "Legitimate rollback of site_2 must still succeed and preserve site_1")
	assert_eq(mgr.get_reservation_amount(site_1.reservation_id, &"wood"), 4)
	assert_eq(mgr.get_available_amount(&"wood"), 4)
	assert_eq(mgr.get_transaction_revision(), rev_mgr_0)

	# Part B: InMemoryStorageSource — stale checkpoint from before m_site_1 + real active SiteCreationScope
	var fx_m: Dictionary = _create_mem_env(&"c49_r2_mem_ckpt")
	var src: InMemoryStorageSource = fx_m["source"] as InMemoryStorageSource
	var inv_m: SettlementInventory = fx_m["inventory"] as SettlementInventory
	var cm_m: ConstructionManager = fx_m["cm"] as ConstructionManager

	assert_true(inv_m.deposit(&"wood", 8))
	var stale_empty_mem_ckpt: Dictionary = {
		"snap": src._create_rollback_snapshot(),
		"storage_revision": src.get_transaction_revision(),
	}

	var m_res_1: Dictionary = cm_m.try_create_site_from_placement(def_4w, Vector3(4.0, 0.0, 4.0))
	assert_true(bool(m_res_1["ok"]))
	var m_site_1: ConstructionSite = m_res_1["site"] as ConstructionSite
	assert_eq(src.get_reservation_amount(m_site_1.reservation_id, &"wood"), 4)

	var rev_src_0: int = src.get_transaction_revision()
	var probe_m := {"called": false, "site1_during_override": 0}

	cm_m.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		probe_m["called"] = true
		var active_sc: ReservedWithdrawalCoordinator.SiteCreationScope = ReservedWithdrawalCoordinator._active_site_creation_scopes[0]
		src._restore_site_reservation_checkpoint_silent(stale_empty_mem_ckpt, active_sc)
		src._restore_site_reservation_checkpoint_silent({"snap": {}, "storage_revision": 0}, active_sc)
		probe_m["site1_during_override"] = src.get_reservation_amount(m_site_1.reservation_id, &"wood")
		return null

	var m_res_2: Dictionary = cm_m.try_create_site_from_placement(def_4w, Vector3(12.0, 0.0, 4.0))
	cm_m.site_creator_override = Callable()

	assert_true(bool(probe_m["called"]))
	assert_false(bool(m_res_2["ok"]))
	assert_eq(int(probe_m["site1_during_override"]), 4, "Stale checkpoint with real active scope must not erase m_site_1 reservation on InMemoryStorageSource")
	assert_eq(src.get_all_reservation_ids(), [m_site_1.reservation_id])
	assert_eq(src.get_reservation_amount(m_site_1.reservation_id, &"wood"), 4)
	assert_eq(src.get_available_amount(&"wood"), 4)
	assert_eq(src.get_transaction_revision(), rev_src_0)


func test_04_repeated_publish_restore_and_manual_complement_active_scope_callbacks_remain_protected() -> void:
	var fx: Dictionary = _create_gpm_env(&"c49_r2_mc")
	var mgr: GroundPileManager = fx["manager"] as GroundPileManager
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var def_4w: BuildingDefinition = _make_def(&"r2_mc_4w", {&"wood": 4})
	assert_true(inv.deposit(&"wood", 8))

	var stale_ckpt: Dictionary = {
		"ledger_snapshot": mgr._ledger.snapshot_state(),
		"ledger_revision": mgr._ledger._transaction_revision,
		"storage_revision": mgr.get_transaction_revision(),
	}

	var sig := {"res": 0, "stor": 0}
	_connect_tracked(mgr.reservations_changed, func() -> void: sig["res"] = int(sig["res"]) + 1)
	_connect_tracked(mgr.storage_changed, func() -> void: sig["stor"] = int(sig["stor"]) + 1)

	# During site_created (post-publish, while SiteCreationScope is still active):
	var sc_post_probe := {"called": false}
	_connect_tracked(cm.site_created, func(_s: ConstructionSite) -> void:
		if bool(sc_post_probe["called"]):
			return
		sc_post_probe["called"] = true
		if not ReservedWithdrawalCoordinator._active_site_creation_scopes.is_empty():
			var active_sc: ReservedWithdrawalCoordinator.SiteCreationScope = ReservedWithdrawalCoordinator._active_site_creation_scopes[0]
			mgr._publish_site_reservation_committed(active_sc)
			mgr._restore_site_reservation_checkpoint_silent(stale_ckpt, active_sc)
	)

	var res_1: Dictionary = cm.try_create_site_from_placement(def_4w, Vector3(4.0, 0.0, 4.0))
	assert_true(bool(res_1["ok"]))
	assert_true(bool(sc_post_probe["called"]))
	var site_1: ConstructionSite = res_1["site"] as ConstructionSite
	assert_eq(int(sig["res"]), 1, "Repeated publish in site_created must not emit extra reservations_changed")
	assert_eq(int(sig["stor"]), 1, "Repeated publish in site_created must not emit extra storage_changed")
	assert_eq(site_1.get_reserved_in_piles_amount(&"wood"), 4)

	# Lose 2 wood on site_1 and test ManualComplementScope with its real active scope during commit signals.
	assert_true(inv.release_batch(site_1.reservation_id, {&"wood": 2}))
	assert_true(inv.withdraw(&"wood", 2))
	assert_eq(site_1.get_missing_amount(&"wood"), 2)

	var mc_probe := {"res_called": false}
	_connect_tracked(mgr.reservations_changed, func() -> void:
		if bool(mc_probe["res_called"]):
			return
		mc_probe["res_called"] = true
		if not ReservedWithdrawalCoordinator._active_manual_complement_scopes.is_empty():
			var active_mc: ReservedWithdrawalCoordinator.ManualComplementScope = ReservedWithdrawalCoordinator._active_manual_complement_scopes[0]
			mgr._publish_manual_complement_committed(active_mc)
			mgr._publish_silent_reservation_events(active_mc, true)
			mgr._restore_manual_complement_checkpoint_silent(stale_ckpt, active_mc)
			mgr._restore_silent_checkpoint_internal(stale_ckpt, active_mc, true)
	)

	var res_before_mc: int = int(sig["res"])
	var stor_before_mc: int = int(sig["stor"])
	var intent := ManualComplementIntent.create_for_test(self, site_1)
	var mc_out: Dictionary = site_1.authorize_manual_complement(intent, {}, false)
	assert_true(bool(mc_out["ok"]))
	assert_true(bool(mc_probe["res_called"]))
	assert_eq(int(sig["res"]) - res_before_mc, 1, "Repeated publish with active ManualComplementScope must not emit extra reservations_changed")
	assert_eq(int(sig["stor"]) - stor_before_mc, 1, "Repeated publish with active ManualComplementScope must not emit extra storage_changed")
	assert_eq(site_1.get_reserved_in_piles_amount(&"wood"), 4, "Checkpoint restore with active ManualComplementScope during commit callbacks must be rejected")
	assert_eq(site_1.get_missing_amount(&"wood"), 0)
	assert_true(site_1.verify_accounting_invariant())


func test_r3_ground_override() -> void:
	_audit(_create_gpm_env(&"audit_ground_override"), false, true)

func test_r3_memory_override() -> void:
	_audit(_create_mem_env(&"audit_memory_override"), false, true)

func test_r3_ground_child() -> void:
	_audit(_create_gpm_env(&"audit_ground_child"), true, true)

func test_r3_memory_child() -> void:
	_audit(_create_mem_env(&"audit_memory_child"), true, true)

func test_r3_ground_authorize_only() -> void:
	_audit(_create_gpm_env(&"audit_ground_auth_only"), false, false)

func test_r3_memory_authorize_only() -> void:
	_audit(_create_mem_env(&"audit_memory_auth_only"), false, false)

func _audit(fx: Dictionary, at_tree_entry: bool, should_publish: bool) -> void:
	var cm: ConstructionManager = fx.cm
	var root: Node3D = fx.sites_root
	var inv: SettlementInventory = fx.inventory
	var storage: SettlementStorageSource = inv.get_storage_source()
	var def := _make_def(&"audit_wood", {&"wood": 4})
	assert_true(inv.deposit(&"wood", 8))
	var first := cm.try_create_site_from_placement(def, Vector3(4, 0, 4))
	if not assert_true(first.ok, str(first)):
		return
	var valid_site: ConstructionSite = first.site
	var revisions := func() -> Array:
		return [storage.get_transaction_revision(), inv.get_transaction_revision(),
			valid_site.get_transaction_revision(),
			(storage as GroundPileManager).get_pile_ledger_revision() if storage is GroundPileManager else -1]
	var before: Array = revisions.call()
	var seq := cm._next_site_seq
	var observations := {}
	var events: Array = []
	var rejected: Array = []
	var created: Array = []
	for label: String in ["storage_changed", "reservations_changed", "inventory_changed", "inventory_reservations_changed"]:
		var source: Object = storage if label in ["storage_changed", "reservations_changed"] else inv
		var signal_name := "reservations_changed" if label == "inventory_reservations_changed" else label
		_connect_tracked(Signal(source, signal_name), func() -> void:
			events.append([label, cm._sites.size(), storage.get_reserved_amount(&"wood")]))
	_connect_tracked(cm.site_created, func(s: ConstructionSite) -> void: created.append(s))
	_connect_tracked(cm.site_creation_rejected, func(r: String, _m: String, _d: BuildingDefinition, _p: Vector3) -> void:
		rejected.append(r))
	var probe := func(rid: StringName) -> void:
		for sc: ReservedWithdrawalCoordinator.SiteCreationScope in ReservedWithdrawalCoordinator._active_site_creation_scopes:
			if sc.manager != cm or sc.storage_source != storage:
				continue
			observations["rid"] = rid
			observations["pre"] = [sc._reservation_applied, sc._bound_checkpoint.is_empty(), cm._sites.size(),
				sc.new_site != null, storage.get_reservation_amount(rid, &"wood")]
			observations["authorized"] = ReservedWithdrawalCoordinator._authorize_site_creation_commit(sc)
			observations["checkpoint_cleared"] = sc._bound_checkpoint.is_empty()
			if observations["authorized"] and should_publish:
				storage.call("_publish_site_reservation_committed", sc)
			observations["published"] = sc._published
			return
	if at_tree_entry:
		_connect_tracked(root.child_entered_tree, func(child: Node) -> void:
			var site := child as ConstructionSite
			probe.call(site.reservation_id)
			site.position = valid_site.position)
	else:
		cm.site_creator_override = func(_sid: StringName, rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
			probe.call(rid)
			return null
	var second := cm.try_create_site_from_placement(def, Vector3(12, 0, 4))
	cm.site_creator_override = Callable()
	var after: Array = revisions.call()
	var rid: StringName = observations.get("rid", &"")
	var orphan := storage.get_reservation_amount(rid, &"wood")
	print("[C49 AUDIT] backend=%s tree=%s publish_attempt=%s probe=%s result=%s orphan=%d physical=%d reserved=%d free=%d revisions=%s -> %s seq=%d -> %d events=%s rejected=%s" % [
		"ground" if storage is GroundPileManager else "memory", at_tree_entry, should_publish, observations,
		second.get("reason"), orphan, storage.get_physical_amount(&"wood"), storage.get_reserved_amount(&"wood"),
		storage.get_available_amount(&"wood"), before, after, seq, cm._next_site_seq, events, rejected])
	assert_eq(observations.get("pre"), [true, false, 1, at_tree_entry, 4], "fixture and real active scope")
	assert_eq(second.get("reason"), "site_instantiation_failed")
	assert_eq(cm.get_sites(), [valid_site])
	assert_eq(root.get_child_count(), 1)
	assert_eq(created.size(), 0)
	assert_eq(rejected, ["site_instantiation_failed"])
	assert_eq(storage.get_physical_amount(&"wood"), 8)
	assert_eq(storage.get_reservation_amount(valid_site.reservation_id, &"wood"), 4)
	assert_eq(cm._next_site_seq, seq)
	assert_false(cm._creation_in_progress)
	assert_false(inv.is_transaction_busy())
	assert_false(storage.is_locked())
	assert_false(valid_site.is_transaction_busy())
	assert_false(ReservedWithdrawalCoordinator._active_site_creation_scopes.any(
		func(sc: ReservedWithdrawalCoordinator.SiteCreationScope) -> bool: return sc.manager == cm))
	assert_eq(observations.get("authorized"), false, "Premature authorization must fail")
	assert_eq(observations.get("checkpoint_cleared"), false)
	assert_eq(orphan, 0, "A failed site must have no reservation")
	assert_eq(storage.get_available_amount(&"wood"), 4)
	assert_eq(after, before, "All revisions must roll back")
	assert_eq(events, [], "A failed site must emit no economic signals")


func test_r3_internal_refusal_rolls_back_and_legitimate_creation_reuses_id() -> void:
	_check_internal_refusal(_create_gpm_env(&"r3_ground_internal"))
	_check_internal_refusal(_create_mem_env(&"r3_memory_internal"))


func _check_internal_refusal(fx: Dictionary) -> void:
	var cm: ConstructionManager = fx.cm
	var root: Node3D = fx.sites_root
	var inv: SettlementInventory = fx.inventory
	var storage: SettlementStorageSource = inv.get_storage_source()
	var def := _make_def(&"r3_internal", {&"wood": 4})
	assert_true(inv.deposit(&"wood", 8))
	var first := cm.try_create_site_from_placement(def, Vector3(4, 0, 4))
	if not assert_true(first.ok, str(first)):
		return
	var peer: ConstructionSite = first.site
	var before := [storage.get_transaction_revision(), inv.get_transaction_revision(), peer.get_transaction_revision()]
	var seq := cm._next_site_seq
	var probe := {}
	var events: Array = []
	var created: Array = []
	var queue_candidate := func(child: Node) -> void:
		var site := child as ConstructionSite
		probe["site_id"] = site.site_id
		probe["reservation_id"] = site.reservation_id
		probe["node_id"] = site.get_instance_id()
		# Keep the site valid and non-overlapping, but make it ineligible for commit.
		site.queue_free()
	_connect_tracked(root.child_entered_tree, queue_candidate)
	var inspect_cleanup := func(child: Node) -> void:
		if child.get_instance_id() == probe.get("node_id"):
			var site := child as ConstructionSite
			probe["cleaned"] = not cm._sites.has(site) and not site.state_changed.is_connected(cm._on_site_state_changed)
	_connect_tracked(root.child_exiting_tree, inspect_cleanup)
	_connect_tracked(storage.reservations_changed, func() -> void: events.append(&"reservation"))
	_connect_tracked(storage.storage_changed, func() -> void: events.append(&"storage"))
	_connect_tracked(inv.inventory_changed, func() -> void: events.append(&"inventory"))
	_connect_tracked(cm.site_created, func(site: ConstructionSite) -> void:
		created.append([cm._sites.has(site), storage.get_reservation_amount(site.reservation_id, &"wood")]))

	var denied := cm.try_create_site_from_placement(def, Vector3(12, 0, 4))
	root.child_entered_tree.disconnect(queue_candidate)
	assert_eq(denied.get("reason"), "site_commit_not_authorized")
	assert_eq(probe.get("cleaned"), true)
	assert_false(is_instance_id_valid(int(probe.get("node_id", 0))))
	assert_eq(root.get_child_count(), 1)
	assert_eq(cm.get_sites(), [peer])
	assert_eq(cm._next_site_seq, seq)
	assert_eq(storage.get_all_reservation_ids(), [peer.reservation_id])
	assert_eq(storage.get_available_amount(&"wood"), 4)
	assert_eq([storage.get_transaction_revision(), inv.get_transaction_revision(), peer.get_transaction_revision()], before)
	assert_eq(events, [])
	assert_eq(created, [])
	assert_false(cm._creation_in_progress)
	assert_false(inv.is_transaction_busy())
	assert_false(storage.is_locked())
	assert_false(peer.is_transaction_busy())

	var legitimate := cm.try_create_site_from_placement(def, Vector3(12, 0, 4))
	if not assert_true(legitimate.ok, str(legitimate)):
		return
	var site: ConstructionSite = legitimate.site
	assert_eq(site.site_id, probe.get("site_id"))
	assert_eq(site.reservation_id, probe.get("reservation_id"))
	assert_eq(cm.get_sites(), [peer, site])
	assert_true(site.state_changed.is_connected(cm._on_site_state_changed))
	assert_eq(storage.get_physical_amount(&"wood"), 8)
	assert_eq(storage.get_reserved_amount(&"wood"), 8)
	assert_eq(created, [[true, 4]])
