extends TestCase
## Unit and component-integration tests for T3.4.1:
## Separate accounting (_consumed_materials & §3.2 getters), transactional DEC-11B
## manual reservation complementation, ManualComplementIntent guards, and SiteState/AssemblySubstate.

const WOOD_BASE: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_BASE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_BASE: ResourceDefinition = preload("res://data/resources/food.tres")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")

var _managers_to_cleanup: Array[GroundPileManager] = []


func after_each() -> void:
	for manager: GroundPileManager in _managers_to_cleanup:
		if manager != null:
			manager.cleanup()
	_managers_to_cleanup.clear()


func _make_fixture(
	max_pile_amount: int = 0,
	defs_override: Dictionary = {}
) -> Dictionary:
	var host := Node3D.new()
	add_test_child(host)

	var zone := CampStorageZone.new()
	zone.zone_id = &"t341_test_camp"
	zone.position = Vector3(-8.0, 0.0, -8.0)
	zone.zone_bounds_half_extents = Vector2(6.0, 6.0)
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
	cm.configure(sites_root, inventory, defs, zone, null, &"t341_region")

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


func _make_test_building_def(def_id: StringName, costs: Dictionary) -> BuildingDefinition:
	# Exclusive unit-test fixture definition; never alters GDD official costs on SHELTER_DEF.
	var def := BuildingDefinition.new()
	def.definition_id = def_id
	def.display_name = String(def_id)
	def.footprint_size = Vector2(3.0, 3.0)
	def.costs = costs.duplicate()
	def.build_work_required_sec = 10.0
	def.max_builders = 2
	def.visual_height = 2.0
	return def


func _spawn_dummy_unit(parent: Node, unit_name: String, pos: Vector3 = Vector3.ZERO) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = unit_name
	u.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	u.position = pos
	parent.add_child(u)
	return u


class FailingSecondReserveManager:
	extends GroundPileManager

	var fail_commit: bool = false

	func _commit_reserve_entries(entries: Array[Dictionary], reservation_id: StringName) -> bool:
		if fail_commit:
			var snapshot: Dictionary = _ledger.snapshot_state()
			_is_mutating = true
			if not entries.is_empty():
				var first: Dictionary = entries[0]
				_ledger.allocate_on_pile(
					(first["pile"] as GroundResourcePile).pile_id,
					first["resource_id"] as StringName,
					reservation_id,
					1
				)
			# Simulate mid-transaction failure and verify snapshot rollback.
			_ledger.restore_state(snapshot)
			_is_mutating = false
			return false
		return super._commit_reserve_entries(entries, reservation_id)


func test_01_t34_aut_01_authorized_complement_after_decay_cond_1() -> void:
	# Uses real decay_wood_provisional.tres (420s grace, 120s interval) & stone (can_decay=false).
	var fx: Dictionary = _make_fixture()
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_p: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var slots: Array[Vector3] = zone.get_candidate_slots()
	assert_true(slots.size() >= 3)
	var pos_wood_1: Vector3 = slots[0]
	var pos_stone: Vector3 = slots[1]
	var pos_wood_2: Vector3 = slots[2]

	# Binding Condition 1: reserve all 6 stone for Shelter (12 wood, 6 stone) upfront
	# so stone deficit never interferes when calling authorize_manual_complement with {}.
	var pile_w1: GroundResourcePile = manager.try_create_pile_at(&"wood", 18, pos_wood_1)
	var pile_s1: GroundResourcePile = manager.try_create_pile_at(&"stone", 6, pos_stone)
	assert_not_null(pile_w1)
	assert_not_null(pile_s1)
	pile_w1.apply_state(18, 420.0, 0.0)

	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(8.0, 0.0, 8.0))
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 6)
	assert_eq(manager.get_pile_available_amount(pile_w1.pile_id), 6)
	assert_true(site.verify_accounting_invariant())

	# Advance clock +1200.0s: 1200 / 120 = 10 wood lost on Pile 1 (6 free + 4 reserved).
	# DEC-11A: Stone has can_decay == false and remains completely untouched.
	time_p.advance(1200.0)
	var losses: Dictionary = manager.step_decay()
	assert_eq(int(losses.get(&"wood", 0)), 10)
	assert_eq(int(losses.get(&"stone", 0)), 0)
	assert_eq(pile_w1.amount, 8)
	assert_eq(pile_s1.amount, 6)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)
	assert_eq(site.get_missing_amount(&"wood"), 4)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 6)
	assert_eq(site.get_missing_amount(&"stone"), 0)

	# Post-decay independent Pile 2 (no deposit_batch merge): must NOT auto-reserve!
	var pile_w2: GroundResourcePile = manager.try_create_pile_at(&"wood", 6, pos_wood_2)
	assert_not_null(pile_w2)
	assert_eq(pile_w2.amount, 6)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)
	assert_eq(site.get_missing_amount(&"wood"), 4)
	assert_eq(inventory.get_physical_amount(&"wood"), 14)
	assert_eq(inventory.get_available_amount(&"wood"), 6)

	# Authorize manual complement with {} (allowed because Condition 1 stone=6/6 is covered).
	var intent := ManualComplementIntent.create_for_test(self, site)
	assert_not_null(intent)
	var out: Dictionary = site.authorize_manual_complement(intent, {}, false)
	assert_true(bool(out["ok"]))
	assert_eq(int((out["complemented"] as Dictionary).get(&"wood", 0)), 4)
	assert_true((out["remaining_missing"] as Dictionary).is_empty())
	assert_true(intent.consumed)
	assert_eq(site.get_missing_amount(&"wood"), 0)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)
	assert_eq(manager.get_pile_available_amount(pile_w2.pile_id), 2)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(site.get_consumed_amount(&"wood"), 0)
	assert_true(site.verify_accounting_invariant())

	# Also verify Binding Condition 1 alternative (explicitly requesting only {&"wood": 4} on another site with missing stone).
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res2: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(14.0, 0.0, 8.0))
	assert_true(bool(res2["ok"]))
	var site2: ConstructionSite = res2["site"] as ConstructionSite
	assert_true(inventory.release_batch(site2.reservation_id, {&"wood": 4, &"stone": 2}))
	assert_eq(site2.get_missing_amount(&"wood"), 4)
	assert_eq(site2.get_missing_amount(&"stone"), 2)
	assert_true(inventory.withdraw(&"stone", 2)) # 0 free stone left; 4+2=6 wood free (2 from pile_w2 + 4 released)
	var explicit_intent := ManualComplementIntent.create_for_test(self, site2)
	var out_explicit: Dictionary = site2.authorize_manual_complement(explicit_intent, {&"wood": 4}, false)
	assert_true(bool(out_explicit["ok"]))
	assert_eq(site2.get_missing_amount(&"wood"), 0)
	assert_eq(site2.get_missing_amount(&"stone"), 2)
	assert_true(site2.verify_accounting_invariant())


func test_02_t34_aut_01b_intent_guards_forged_reused_consumed_on_failure_and_reentrancy() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_p: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_w1: GroundResourcePile = manager.try_create_pile_at(&"wood", 12, slots[0])
	var pile_s1: GroundResourcePile = manager.try_create_pile_at(&"stone", 6, slots[1])
	assert_not_null(pile_w1)
	assert_not_null(pile_s1)
	pile_w1.apply_state(12, 420.0, 0.0)

	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(8.0, 0.0, 8.0))
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite

	# Decay 4 wood so missing = 4 wood, 0 free stock currently.
	time_p.advance(480.0)
	manager.step_decay()
	assert_eq(site.get_missing_amount(&"wood"), 4)

	# 1. null intent rejected with 0 mutations.
	var r_null: Dictionary = site.authorize_manual_complement(null)
	assert_false(bool(r_null["ok"]))
	assert_eq(r_null["reason"], "unauthorized_or_missing_intent")
	assert_eq(site.get_missing_amount(&"wood"), 4)

	# 3. Automated / simulation issuers rejected at factory AND execution.
	var clock := EconomyClockController.new()
	host.add_child(clock)
	var construct_order := ConstructOrder.new(site)
	var deliver_order := DeliverToCampOrder.new(zone)
	assert_null(ManualComplementIntent.create_for_test(inventory, site))
	assert_null(ManualComplementIntent.create_for_test(manager, site))
	assert_null(ManualComplementIntent.create_for_test(clock, site))
	assert_null(ManualComplementIntent.create_for_test(construct_order, site))
	assert_null(ManualComplementIntent.create_for_test(deliver_order, site))
	assert_null(ManualComplementIntent.create_for_test(site, site))
	assert_null(ManualComplementIntent.create_for_test(cm, site))

	# Detached UI Control (outside tree) also rejected.
	var detached_ctrl := Control.new()
	assert_null(ManualComplementIntent.create_from_player_ui(detached_ctrl, site))
	detached_ctrl.free()

	# Bypassing factory manually must still fail validation.
	var manual_bypass := ManualComplementIntent.new()
	manual_bypass.target_site = site
	manual_bypass.issuer_ref = weakref(self)
	var r_bypass: Dictionary = site.authorize_manual_complement(manual_bypass)
	assert_false(bool(r_bypass["ok"]))
	assert_eq(r_bypass["reason"], "unauthorized_or_missing_intent")

	# 5. Immediate consumption EVEN WHEN operation fails (insufficient_free_stock).
	var intent_fail := ManualComplementIntent.create_for_test(self, site)
	assert_not_null(intent_fail)
	assert_false(intent_fail.consumed)
	var r_insufficient: Dictionary = site.authorize_manual_complement(intent_fail, {}, false)
	assert_false(bool(r_insufficient["ok"]))
	assert_eq(r_insufficient["reason"], "insufficient_free_stock")
	assert_true(intent_fail.consumed, "Intent MUST be consumed immediately even when transaction fails")

	# 4. Adding free wood & advancing decay/time never auto-complements missing reservation.
	assert_true(inventory.deposit(&"wood", 4))
	time_p.advance(10.0)
	manager.step_decay()
	assert_eq(site.get_missing_amount(&"wood"), 4)

	# 2 + 5. Reusing intent_fail after stock arrives is rejected; fresh ticket is required.
	var r_reuse_failed: Dictionary = site.authorize_manual_complement(intent_fail, {}, false)
	assert_false(bool(r_reuse_failed["ok"]))
	assert_eq(r_reuse_failed["reason"], "unauthorized_or_missing_intent")
	assert_eq(site.get_missing_amount(&"wood"), 4)

	# 6. Signal reentrancy guard (_is_complementing): recursive call during state/reservations_changed fails cleanly.
	var reentrant_intent := ManualComplementIntent.create_for_test(self, site)
	var reentrant_results: Array[Dictionary] = []
	var triggered: Array[bool] = [false]
	site.state_changed.connect(func(_s: ConstructionSite) -> void:
		if not triggered[0]:
			triggered[0] = true
			reentrant_results.append(site.authorize_manual_complement(reentrant_intent, {}, false))
	)
	var intent_ok := ManualComplementIntent.create_for_test(self, site)
	var r_ok: Dictionary = site.authorize_manual_complement(intent_ok, {}, false)
	assert_true(bool(r_ok["ok"]))
	assert_true(intent_ok.consumed)
	assert_true(triggered[0])
	assert_eq(reentrant_results.size(), 1)
	assert_false(bool(reentrant_results[0]["ok"]))
	assert_eq(reentrant_results[0]["reason"], "reentrant_complement_blocked")
	assert_true(reentrant_intent.consumed)

	# Reusing intent_ok is rejected.
	var r_reuse_ok: Dictionary = site.authorize_manual_complement(intent_ok, {}, false)
	assert_false(bool(r_reuse_ok["ok"]))
	assert_eq(r_reuse_ok["reason"], "unauthorized_or_missing_intent")

	# Wrong target site does not authorize.
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res_other: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(14.0, 0.0, 8.0))
	var other_site: ConstructionSite = res_other["site"] as ConstructionSite
	var wrong_site_intent := ManualComplementIntent.create_for_test(self, other_site)
	var r_wrong: Dictionary = site.authorize_manual_complement(wrong_site_intent)
	assert_false(bool(r_wrong["ok"]))
	assert_eq(r_wrong["reason"], "unauthorized_or_missing_intent")
	assert_false(wrong_site_intent.consumed)

	# Live Control in tree is accepted by create_from_player_ui.
	var live_ctrl := Control.new()
	host.add_child(live_ctrl)
	var ui_intent := ManualComplementIntent.create_from_player_ui(live_ctrl, site)
	assert_not_null(ui_intent)
	assert_eq(ui_intent.origin_kind, ManualComplementIntent.OriginKind.PLAYER_UI)


func test_03_t34_aut_02_refusal_idempotency_partial_and_rollback() -> void:
	var fx: Dictionary = _make_fixture()
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(8.0, 0.0, 8.0))
	var site: ConstructionSite = res["site"] as ConstructionSite

	# Lose 4 wood reservation intentionally (0 free wood left).
	assert_true(inventory.release_batch(site.reservation_id, {&"wood": 4}))
	assert_true(inventory.withdraw(&"wood", 4))
	assert_eq(site.get_missing_amount(&"wood"), 4)
	assert_eq(inventory.get_available_amount(&"wood"), 0)

	# Scenario A: 0 free stock -> refused cleanly.
	var can_a: Dictionary = site.can_authorize_manual_complement({}, false)
	assert_false(bool(can_a["ok"]))
	assert_eq(can_a["reason"], "insufficient_free_stock")
	var out_a: Dictionary = site.authorize_manual_complement(ManualComplementIntent.create_for_test(self, site), {}, false)
	assert_false(bool(out_a["ok"]))
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)

	# Scenario C: only 2 free wood when 4 missing -> strict fails, allow_partial=true reserves 2.
	assert_true(inventory.deposit(&"wood", 2))
	var out_strict: Dictionary = site.authorize_manual_complement(ManualComplementIntent.create_for_test(self, site), {}, false)
	assert_false(bool(out_strict["ok"]))
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)

	var out_partial: Dictionary = site.authorize_manual_complement(ManualComplementIntent.create_for_test(self, site), {}, true)
	assert_true(bool(out_partial["ok"]))
	assert_eq(int((out_partial["complemented"] as Dictionary).get(&"wood", 0)), 2)
	assert_eq(int((out_partial["remaining_missing"] as Dictionary).get(&"wood", 0)), 2)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 10)
	assert_eq(inventory.get_available_amount(&"wood"), 0)

	# Complement remaining 2, then test Scenario B (idempotent nothing_missing with new ticket).
	assert_true(inventory.deposit(&"wood", 2))
	var out_finish: Dictionary = site.authorize_manual_complement(ManualComplementIntent.create_for_test(self, site), {}, false)
	assert_true(bool(out_finish["ok"]))
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)

	var out_b: Dictionary = site.authorize_manual_complement(ManualComplementIntent.create_for_test(self, site), {}, false)
	assert_true(bool(out_b["ok"]))
	assert_eq(out_b["reason"], "nothing_missing")
	assert_true((out_b["complemented"] as Dictionary).is_empty())
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)

	# reserve_batch must STILL block existing reservation_ids; only complement_reservation extends them.
	assert_true(inventory.deposit(&"wood", 3))
	assert_false(inventory.can_reserve_batch(site.reservation_id, {&"wood": 1}))
	assert_false(inventory.reserve_batch(site.reservation_id, {&"wood": 1}))
	assert_true(inventory.can_complement_reservation(site.reservation_id, {&"wood": 1}))

	# Rollback & 0->N complement parity on InMemoryStorageSource & FailingSecondReserveManager.
	var base_src := SettlementStorageSource.new()
	assert_false(base_src.can_complement_reservation(&"x", {&"wood": 1}))
	assert_false(base_src.complement_reservation(&"x", {&"wood": 1}))

	var mem := InMemoryStorageSource.new()
	mem.deposit(&"wood", 5)
	mem.reserve_batch(&"site_mem", {&"wood": 5})
	assert_false(mem.reserve_batch(&"site_mem", {&"wood": 1}))
	mem.record_intentional_decay(&"wood", 5) # Total loss -> 0 remaining!
	assert_false(mem.has_reservation(&"site_mem"))
	mem.deposit(&"wood", 5)
	assert_true(mem.can_complement_reservation(&"site_mem", {&"wood": 5}))
	assert_true(mem.complement_reservation(&"site_mem", {&"wood": 5}))
	assert_eq(mem.get_reservation_amount(&"site_mem", &"wood"), 5)

	var rb_host := Node3D.new()
	add_test_child(rb_host)
	var rb_zone := CampStorageZone.new()
	rb_zone.zone_bounds_half_extents = Vector2(4.0, 4.0)
	rb_host.add_child(rb_zone)
	var rb_piles := Node3D.new()
	rb_host.add_child(rb_piles)
	var rb_mgr := FailingSecondReserveManager.new(fx["defs"] as Dictionary, rb_zone, rb_piles, SimulatedWorldTimeProvider.new(0.0))
	_managers_to_cleanup.append(rb_mgr)
	rb_mgr.deposit(&"wood", 5)
	assert_true(rb_mgr.reserve_batch(&"rb_res", {&"wood": 2}))
	rb_mgr.fail_commit = true
	assert_false(rb_mgr.complement_reservation(&"rb_res", {&"wood": 3}))
	assert_eq(rb_mgr.get_reservation_amount(&"rb_res", &"wood"), 2, "Rollback on commit failure must preserve prior reservation exactly")


func test_04_t34_aut_03_multi_site_shared_pile_decay_cond_2() -> void:
	# Binding Condition 2: exclusive unit-test fixture with 5-wood requirement per site,
	# preserving real step_decay() exposure behavior and GDD Shelter costs untouched.
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_p: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_1: GroundResourcePile = manager.try_create_pile_at(&"wood", 10, slots[0])
	var pile_2: GroundResourcePile = manager.try_create_pile_at(&"wood", 4, slots[1])
	assert_not_null(pile_1)
	assert_not_null(pile_2)
	pile_1.apply_state(10, 420.0, 0.0)
	pile_2.apply_state(4, 0.0, 0.0)

	var test_def_a: BuildingDefinition = _make_test_building_def(&"test_5wood_a", {&"wood": 5})
	var test_def_b: BuildingDefinition = _make_test_building_def(&"test_5wood_b", {&"wood": 5})

	# Reserve 5 wood on Pile 1 first for Site A (seq=1), then 5 wood on Pile 1 for Site B (seq=2).
	assert_true(inventory.reserve_batch(&"res_site_a", {&"wood": 5}))
	assert_true(inventory.reserve_batch(&"res_site_b", {&"wood": 5}))
	var site_a := ConstructionSite.new()
	var site_b := ConstructionSite.new()
	host.add_child(site_a)
	host.add_child(site_b)
	assert_true(site_a.configure(&"site_a", &"res_site_a", test_def_a, inventory, fx["defs"] as Dictionary))
	assert_true(site_b.configure(&"site_b", &"res_site_b", test_def_b, inventory, fx["defs"] as Dictionary))
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 5)
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 5)

	# Advance +480.0s simultaneously on both piles:
	# Pile 1 (420 -> 900s): loses 4 wood (10 -> 6w); Pile 2 (0 -> 480s, over=60s < 120s): loses 0 wood (4w free preserved).
	time_p.advance(480.0)
	var step_losses: Dictionary = manager.step_decay()
	assert_eq(int(step_losses.get(&"wood", 0)), 4)
	assert_eq(pile_1.amount, 6)
	assert_eq(pile_2.amount, 4)
	assert_true(is_equal_approx(pile_2.decay_accumulator_sec, 60.0))

	# Reverse reservation reduction on Pile 1 trims Site B (5 -> 1) while preserving Site A (5/5).
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 5)
	assert_eq(site_a.get_missing_amount(&"wood"), 0)
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 1)
	assert_eq(site_b.get_missing_amount(&"wood"), 4)

	# Complement Site B only: pulls 4 free wood from Pile 2 without touching Site A.
	var out_b: Dictionary = site_b.authorize_manual_complement(ManualComplementIntent.create_for_test(self, site_b), {}, false)
	assert_true(bool(out_b["ok"]))
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 5)
	assert_eq(site_b.get_missing_amount(&"wood"), 0)
	assert_eq(manager.get_pile_available_amount(pile_2.pile_id), 0)
	assert_eq(manager.get_pile_reserved_amount(pile_2.pile_id), 4)
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 5)
	assert_eq(site_a.get_missing_amount(&"wood"), 0)
	assert_true(site_a.verify_accounting_invariant())
	assert_true(site_b.verify_accounting_invariant())


func test_05_t34_aut_04_in_transit_conservation_on_interruption() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_p: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var defs: Dictionary = fx["defs"] as Dictionary
	var wood_def: ResourceDefinition = defs[&"wood"] as ResourceDefinition

	var slots: Array[Vector3] = zone.get_candidate_slots()
	var pile_1: GroundResourcePile = manager.try_create_pile_at(&"wood", 4, slots[0])
	var pile_2: GroundResourcePile = manager.try_create_pile_at(&"wood", 8, slots[1])
	var pile_s: GroundResourcePile = manager.try_create_pile_at(&"stone", 6, slots[2])
	assert_not_null(pile_1)
	assert_not_null(pile_2)
	assert_not_null(pile_s)
	pile_1.apply_state(4, 0.0, 0.0)
	pile_2.apply_state(8, 300.0, 0.0)

	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(8.0, 0.0, 8.0))
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite

	var w1: Unit = _spawn_dummy_unit(host, "W1_Transit", Vector3(2.0, 0.0, 2.0))
	var order1 := UnitOrder.new()
	order1.mark_running()
	assert_eq(site.register_worker(w1, order1, false), ConstructionSite.WorkerRole.SOLO_SUPPLIER)

	# Worker withdraws 4 wood from Pile 1 and then gets interrupted (cancelled + unregistered).
	var taken: int = inventory.withdraw_reserved_from_pile_to_carry_load(pile_1.pile_id, site.reservation_id, wood_def, 4, w1.get_carry_load())
	assert_eq(taken, 4)
	site.record_withdrawn_for_site(w1, &"wood", 4)
	order1.cancel(null)
	site.unregister_worker(w1, order1)
	assert_eq(site.get_in_transit_amount(&"wood"), 4)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)
	assert_eq(site.get_missing_amount(&"wood"), 0)

	# Advance +360.0s: Pile 2 (300 -> 660s, over=240s) loses 2 wood -> reserved drops 8 -> 6, missing = 2!
	time_p.advance(360.0)
	var losses: Dictionary = manager.step_decay()
	assert_eq(int(losses.get(&"wood", 0)), 2)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 6)
	assert_eq(site.get_in_transit_amount(&"wood"), 4)
	assert_eq(site.get_missing_amount(&"wood"), 2, "In-transit 4w must remain deducted from missing")

	# Deposit 2 free wood post-decay and manually complement ONLY the 2 missing units.
	var pile_3: GroundResourcePile = manager.try_create_pile_at(&"wood", 2, slots[3])
	assert_not_null(pile_3)
	var out: Dictionary = site.authorize_manual_complement(ManualComplementIntent.create_for_test(self, site), {}, false)
	assert_true(bool(out["ok"]))
	assert_eq(int((out["complemented"] as Dictionary).get(&"wood", 0)), 2)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)
	assert_eq(site.get_in_transit_amount(&"wood"), 4)
	assert_eq(site.get_missing_amount(&"wood"), 0)

	# Resuming delivery delivers the 4w carried load without loss or duplication.
	var delivered: Dictionary = site.accept_delivery_from_carry_load(w1, w1.get_carry_load())
	assert_eq(int(delivered.get(&"wood", 0)), 4)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 4)
	assert_eq(site.get_in_transit_amount(&"wood"), 0)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)
	assert_eq(site.get_missing_amount(&"wood"), 0)
	assert_true(site.verify_accounting_invariant())


func test_06_site_states_and_eight_getters_contract_verification() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var defs: Dictionary = fx["defs"] as Dictionary
	var wood_def: ResourceDefinition = defs[&"wood"] as ResourceDefinition
	var stone_def: ResourceDefinition = defs[&"stone"] as ResourceDefinition

	var site := ConstructionSite.new()
	host.add_child(site)
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.UNCONFIGURED)
	assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.NONE)
	assert_false(site.is_active())

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	assert_true(inventory.reserve_batch(&"res_getters", {&"wood": 12, &"stone": 6}))
	assert_true(site.configure(&"site_getters", &"res_getters", SHELTER_DEF, inventory, defs))

	assert_eq(site.get_site_state(), ConstructionSite.SiteState.ACTIVE)
	assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.WAITING_ASSEMBLY)
	assert_true(site.is_active())
	assert_eq(site.get_consumed_amount(&"wood"), 0)
	assert_eq(site.get_consumed_amount(&"stone"), 0)
	assert_eq(site.get_total_received_amount(&"wood"), 0)
	assert_eq(site.get_remaining_need_for_dropoff(&"wood"), 12)
	assert_eq(site.get_remaining_supply_to_claim(&"wood"), 12)
	assert_eq(site.get_missing_amount(&"wood"), 0)
	assert_false(site.is_fully_supplied())
	assert_true(site.verify_accounting_invariant())

	# Simulate full withdrawal & delivery (2 trips for wood since LeaderA capacity is 20 -> 10w max/trip) and check all getters with consumed=0.
	var u: Unit = _spawn_dummy_unit(host, "W_Full")
	var wood_piles: Array[Dictionary] = inventory.get_reserved_pile_entries(site.reservation_id, &"wood")
	var stone_piles: Array[Dictionary] = inventory.get_reserved_pile_entries(site.reservation_id, &"stone")
	var wood_pile_id: int = int(wood_piles[0]["pile_id"])
	var take_w1: int = inventory.withdraw_reserved_from_pile_to_carry_load(wood_pile_id, site.reservation_id, wood_def, 10, u.get_carry_load())
	assert_eq(take_w1, 10)
	site.record_withdrawn_for_site(u, &"wood", take_w1)
	assert_eq(site.get_remaining_supply_to_claim(&"wood"), 2)
	assert_eq(site.get_in_transit_amount(&"wood"), 10)
	assert_true(site.verify_accounting_invariant())

	site.accept_delivery_from_carry_load(u, u.get_carry_load())
	assert_eq(site.get_total_received_amount(&"wood"), 10)
	assert_eq(site.get_remaining_need_for_dropoff(&"wood"), 2)
	assert_false(site.is_fully_supplied())

	var take_w2: int = inventory.withdraw_reserved_from_pile_to_carry_load(wood_pile_id, site.reservation_id, wood_def, 2, u.get_carry_load())
	assert_eq(take_w2, 2)
	site.record_withdrawn_for_site(u, &"wood", take_w2)
	assert_eq(site.get_remaining_supply_to_claim(&"wood"), 0)
	site.accept_delivery_from_carry_load(u, u.get_carry_load())
	assert_eq(site.get_total_received_amount(&"wood"), 12)
	assert_eq(site.get_remaining_need_for_dropoff(&"wood"), 0)
	assert_false(site.is_fully_supplied())

	var take_s: int = inventory.withdraw_reserved_from_pile_to_carry_load(int(stone_piles[0]["pile_id"]), site.reservation_id, stone_def, 6, u.get_carry_load())
	site.record_withdrawn_for_site(u, &"stone", take_s)
	site.accept_delivery_from_carry_load(u, u.get_carry_load())
	assert_true(site.is_fully_supplied())
	assert_true(site.verify_accounting_invariant())
	var snap: Dictionary = site.get_status_snapshot()
	assert_eq(int(snap["site_state"]), ConstructionSite.SiteState.ACTIVE)
	assert_eq(int(snap["assembly_substate"]), ConstructionSite.AssemblySubstate.WAITING_ASSEMBLY)
	assert_eq(int((snap["consumed"] as Dictionary).get(&"wood", -1)), 0)
	assert_eq(int((snap["total_received"] as Dictionary).get(&"wood", -1)), 12)


func test_07_zeroed_wood_reservation_in_ground_pile_manager_and_manual_recreation() -> void:
	# Real GroundPileManager test verifying full ledger removal when reservation decays to 0
	# and clean recreation under the exact same reservation_id via ManualComplementIntent.
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var zone: CampStorageZone = fx["zone"] as CampStorageZone
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var time_p: SimulatedWorldTimeProvider = fx["time"] as SimulatedWorldTimeProvider

	var slots: Array[Vector3] = zone.get_candidate_slots()
	assert_true(slots.size() >= 2)
	var pile_1: GroundResourcePile = manager.try_create_pile_at(&"wood", 12, slots[0])
	assert_not_null(pile_1)
	pile_1.apply_state(12, 420.0, 0.0)

	var wood_only_def: BuildingDefinition = _make_test_building_def(&"test_zeroed_wood_site", {&"wood": 12})
	var res_id := &"res_zeroed_wood_site"
	assert_true(inventory.reserve_batch(res_id, {&"wood": 12}))
	var site := ConstructionSite.new()
	host.add_child(site)
	assert_true(site.configure(&"site_zeroed_wood", res_id, wood_only_def, inventory, fx["defs"] as Dictionary))
	assert_true(manager.has_reservation(res_id))
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)
	assert_true(site.verify_accounting_invariant())

	# Advance +1440.0s (12 * 120s): decays all 12 wood in Pile 1 -> reservation drops completely from ledger.
	time_p.advance(1440.0)
	var losses: Dictionary = manager.step_decay()
	assert_eq(int(losses.get(&"wood", 0)), 12)
	assert_false(manager.has_reservation(res_id), "Zeroed reservation must disappear completely from PileReservationLedger")
	assert_false(manager.get_all_reservation_ids().has(res_id))
	assert_eq(manager.get_reserved_amount(&"wood"), 0)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(site.get_missing_amount(&"wood"), 12)
	assert_true(site.verify_accounting_invariant())

	# Create new physical pile with 15 free wood: zero automatic reallocation.
	var pile_2: GroundResourcePile = manager.try_create_pile_at(&"wood", 15, slots[1])
	assert_not_null(pile_2)
	assert_false(manager.has_reservation(res_id))
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(site.get_missing_amount(&"wood"), 12)
	assert_eq(manager.get_available_amount(&"wood"), 15)

	# Authorize manual complement with valid ManualComplementIntent: recreates reservation under same reservation_id.
	var intent := ManualComplementIntent.create_for_test(self, site)
	assert_not_null(intent)
	var out: Dictionary = site.authorize_manual_complement(intent, {}, false)
	assert_true(bool(out["ok"]))
	assert_true(intent.consumed)
	assert_eq(int((out["complemented"] as Dictionary).get(&"wood", 0)), 12)
	assert_true((out["remaining_missing"] as Dictionary).is_empty())

	assert_true(manager.has_reservation(res_id), "Complement must recreate reservation under same reservation_id")
	assert_true(manager.get_all_reservation_ids().has(res_id))
	assert_eq(manager.get_reservation_amount(res_id, &"wood"), 12)
	assert_eq(manager.get_pile_reserved_amount(pile_2.pile_id), 12)
	assert_eq(manager.get_pile_available_amount(pile_2.pile_id), 3)
	assert_eq(manager.get_available_amount(&"wood"), 3)
	assert_eq(manager.get_physical_amount(&"wood"), 15)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)
	assert_eq(site.get_missing_amount(&"wood"), 0)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(site.get_consumed_amount(&"wood"), 0)
	assert_true(site.verify_accounting_invariant())


func test_08_multi_resource_atomicity_wood_ok_stone_short_and_retry() -> void:
	var fx: Dictionary = _make_fixture()
	var host: Node3D = fx["host"] as Node3D
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var inventory: SettlementInventory = fx["inventory"] as SettlementInventory
	var cm: ConstructionManager = fx["cm"] as ConstructionManager

	# Other active site holding independent reservations that must never be touched.
	assert_true(inventory.deposit(&"wood", 3))
	assert_true(inventory.deposit(&"stone", 2))
	var other_def: BuildingDefinition = _make_test_building_def(&"test_other_site", {&"wood": 3, &"stone": 2})
	assert_true(inventory.reserve_batch(&"res_other_site", {&"wood": 3, &"stone": 2}))
	var site_other := ConstructionSite.new()
	host.add_child(site_other)
	assert_true(site_other.configure(&"site_other", &"res_other_site", other_def, inventory, fx["defs"] as Dictionary))

	# Target Shelter site (12 wood, 6 stone) with deficits on BOTH wood (4) and stone (3).
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(8.0, 0.0, 8.0))
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite

	assert_true(inventory.release_batch(site.reservation_id, {&"wood": 4, &"stone": 3}))
	assert_true(inventory.withdraw(&"wood", 4))
	assert_true(inventory.withdraw(&"stone", 3))
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 3)
	assert_eq(site.get_missing_amount(&"wood"), 4)
	assert_eq(site.get_missing_amount(&"stone"), 3)

	# Provide sufficient free wood (5 >= 4) but insufficient free stone (2 < 3).
	assert_true(inventory.deposit(&"wood", 5))
	assert_true(inventory.deposit(&"stone", 2))

	var intent_fail := ManualComplementIntent.create_for_test(self, site)
	assert_not_null(intent_fail)
	var fail_res: Dictionary = site.authorize_manual_complement(intent_fail, {}, false)
	assert_false(bool(fail_res["ok"]))
	assert_eq(fail_res["reason"], "insufficient_free_stock")

	# Strict atomicity checks: zero partial allocation, balances intact, other site intact, ticket consumed.
	assert_true(intent_fail.consumed, "Ticket must be consumed even when multi-resource transaction fails")
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 8)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 3)
	assert_eq(site.get_missing_amount(&"wood"), 4)
	assert_eq(site.get_missing_amount(&"stone"), 3)
	assert_eq(manager.get_physical_amount(&"wood"), 16)
	assert_eq(manager.get_physical_amount(&"stone"), 7)
	assert_eq(manager.get_available_amount(&"wood"), 5)
	assert_eq(manager.get_available_amount(&"stone"), 2)
	assert_eq(site_other.get_reserved_in_piles_amount(&"wood"), 3)
	assert_eq(site_other.get_reserved_in_piles_amount(&"stone"), 2)
	assert_true(site.verify_accounting_invariant())
	assert_true(site_other.verify_accounting_invariant())

	# Add the missing 1 stone (free stone becomes 3 == needed 3) and retry with a NEW ticket.
	assert_true(inventory.deposit(&"stone", 1))
	var reuse_res: Dictionary = site.authorize_manual_complement(intent_fail, {}, false)
	assert_false(bool(reuse_res["ok"]))
	assert_eq(reuse_res["reason"], "unauthorized_or_missing_intent")

	var intent_ok := ManualComplementIntent.create_for_test(self, site)
	assert_not_null(intent_ok)
	var ok_res: Dictionary = site.authorize_manual_complement(intent_ok, {}, false)
	assert_true(bool(ok_res["ok"]))
	assert_true(intent_ok.consumed)
	assert_eq(int((ok_res["complemented"] as Dictionary).get(&"wood", 0)), 4)
	assert_eq(int((ok_res["complemented"] as Dictionary).get(&"stone", 0)), 3)
	assert_true((ok_res["remaining_missing"] as Dictionary).is_empty())
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 6)
	assert_eq(site.get_missing_amount(&"wood"), 0)
	assert_eq(site.get_missing_amount(&"stone"), 0)
	assert_eq(manager.get_available_amount(&"wood"), 1)
	assert_eq(manager.get_available_amount(&"stone"), 0)
	assert_eq(site_other.get_reserved_in_piles_amount(&"wood"), 3)
	assert_eq(site_other.get_reserved_in_piles_amount(&"stone"), 2)
	assert_true(site.verify_accounting_invariant())
	assert_true(site_other.verify_accounting_invariant())
