extends TestCase
## Integration tests for T3.4.3: Reactive ConstructOrder assembly, zero polling in
## WAITING_FOR_MATERIALS, starvation/DEC-11B resume, and D9/DEC-18 promotions.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_DEF: ResourceDefinition = preload("res://data/resources/food.tres")

const MAX_NAV_FRAMES: int = 120
const MAX_SIM_FRAMES: int = 3600
const SITE_POS_A := Vector3(-6.0, 0.0, 1.5)
const SITE_POS_B := Vector3(0.37, 0.0, -13.19)


class SpyConstructionSite:
	extends ConstructionSite

	var contribute_calls: int = 0
	var contribute_calls_in_waiting: int = 0
	var watched_order: ConstructOrder = null
	var last_result: Dictionary = {}

	func contribute_work(unit: Unit, delta_sec: float) -> Dictionary:
		contribute_calls += 1
		if watched_order != null and watched_order.get_phase() == ConstructOrder.Phase.WAITING_FOR_MATERIALS:
			contribute_calls_in_waiting += 1
		last_result = super.contribute_work(unit, delta_sec)
		return last_result


func before_each() -> void:
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0


func after_each() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func _spawn_main_in_viewport(use_spy_site: bool = false) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp.add_child(main_root)

	var test_map: TestMap = main_root.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var frames: int = 0
	while nav != null and not nav.is_navigation_ready() and frames < MAX_NAV_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	await wait_process_frames(2)
	await wait_physics_frames(2)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var cm: ConstructionManager = main_root.get_construction_manager()
	var completed_records: Dictionary = {}
	cm.site_created.connect(func(s: ConstructionSite) -> void:
		s.site_completed.connect(func(done: ConstructionSite, _building: BuildingInstance) -> void:
			var record: Dictionary = done.get_status_snapshot()
			record["work_sec"] = done.get_work_progress_sec()
			record["ratio"] = done.get_progress_ratio()
			record["invariant"] = done.verify_accounting_invariant()
			completed_records[done.site_id] = record
		)
	)
	if use_spy_site and cm != null:
		cm.site_creator_override = func(_sid: StringName, _rid: StringName, _def: BuildingDefinition, _pos: Vector3) -> ConstructionSite:
			return SpyConstructionSite.new()

	return {
		"vp": vp,
		"main": main_root,
		"test_map": test_map,
		"nav": nav,
		"command": main_root.get_command_controller(),
		"inventory": main_root.get_settlement_inventory(),
		"pile_manager": main_root.get_ground_pile_manager(),
		"camp": main_root.get_camp_storage_zone(),
		"cm": cm,
		"completed_records": completed_records,
		"time": main_root.get_time_provider(),
		"units": main_root.get_units(),
	}


func _spawn_extra_worker(main_root: MainScene, nav: WorldNavigation, worker_name: String, pos: Vector3) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = worker_name
	u.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	var units_root: Node = main_root.get_node("Units")
	units_root.add_child(u)
	u.global_position = pos
	u.set_world_navigation(nav)
	return u


func _deliver_from_reserved(
	site: ConstructionSite,
	inventory: SettlementInventory,
	unit: Unit,
	res_id: StringName,
	amount: int
) -> void:
	var def: ResourceDefinition = WOOD_DEF.duplicate() as ResourceDefinition if res_id == &"wood" else STONE_DEF.duplicate() as ResourceDefinition
	var remaining: int = amount
	var carry_load: UnitCarryLoad = unit.get_carry_load()
	var entries: Array[Dictionary] = inventory.get_reserved_pile_entries(site.reservation_id, res_id)
	for entry: Dictionary in entries:
		if remaining <= 0:
			break
		var pile_id: int = int(entry["pile_id"])
		var avail_reserved: int = int(entry["reserved_amount"])
		while remaining > 0 and avail_reserved > 0:
			var room: int = carry_load.get_max_additional_units(def)
			if room <= 0:
				break
			var take: int = mini(remaining, mini(avail_reserved, room))
			var taken: int = inventory.withdraw_reserved_from_pile_to_carry_load(
				pile_id,
				site.reservation_id,
				def,
				take,
				carry_load
			)
			assert_eq(taken, take)
			site.record_withdrawn_for_site(unit, res_id, taken)
			var dropped: Dictionary = site.accept_delivery_from_carry_load(unit, carry_load)
			assert_eq(int(dropped.get(res_id, 0)), taken)
			remaining -= taken
			avail_reserved -= taken
	assert_eq(remaining, 0, "Expected exact reserved delivery of %d %s" % [amount, String(res_id)])


func test_01_t34_aut_09b_reactive_order_cycles_starvation_zero_polling_and_wakeup() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport(true)
	var vp: SubViewport = ctx["vp"] as SubViewport
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var w0: Unit = units[0]
	var u1: Unit = units[1]

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res["ok"]))
	var spy: SpyConstructionSite = res["site"] as SpyConstructionSite
	assert_not_null(spy)

	# Seed initial buffer {wood: 2, stone: 0} physically through w0.
	_deliver_from_reserved(spy, inventory, w0, &"wood", 2)
	assert_eq(spy.get_delivered_buffer_amount(&"wood"), 2)
	assert_eq(spy.get_delivered_buffer_amount(&"stone"), 0)

	# Position u1 cleanly on builder slot 0 (South perimeter) and keep step timing exact (0.25s/cycle).
	u1.global_position = SITE_POS_A + Vector3(0.0, 0.0, 2.85)
	await wait_physics_frames(2)

	w0.set_physics_process(false)
	u1.set_physics_process(false)
	var o0 := ConstructOrder.new(spy, camp)
	var o1 := ConstructOrder.new(spy, camp)
	spy.watched_order = o1
	w0.issue_order(o0)
	u1.issue_order(o1)

	assert_eq(spy.get_worker_role(w0), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(spy.get_worker_role(u1), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(spy.get_builder_slot_index(u1), 0)
	assert_eq(o1.get_phase(), ConstructOrder.Phase.BUILDER_ASSEMBLING, "Builder on slot 0 with buffer enters BUILDER_ASSEMBLING")

	# Direct Guard 2 check: dt = 6.0s must be rejected cleanly with zero mutation.
	var invalid_dt: Dictionary = spy.contribute_work(u1, 6.0)
	assert_false(bool(invalid_dt["ok"]))
	assert_eq(invalid_dt["reason"], "invalid_delta")
	assert_false(bool(invalid_dt["starved"]))
	assert_eq(spy.get_work_progress_sec(), 0.0)
	spy.contribute_calls = 0

	var buf_signals: Array[int] = [0]
	var state_signals: Array[int] = [0]
	spy.buffer_changed.connect(func(_s: ConstructionSite) -> void: buf_signals[0] += 1)
	spy.state_changed.connect(func(_s: ConstructionSite) -> void: state_signals[0] += 1)

	# Run exact 0.25s integration cycles 1..20 through ConstructOrder.physics_update.
	for cycle: int in range(1, 21):
		await wait_physics_frames(1)
		o1.physics_update(u1.get_movement(), 0.25)
		assert_eq(spy.contribute_calls, cycle, "Exactly 1 contribute_work call per active assembling cycle")
		assert_true(spy.verify_accounting_invariant())
		if cycle < 10:
			assert_eq(spy.get_consumed_amount(&"wood"), 0)
			assert_false(bool(spy.last_result.get("starved", false)))
			assert_eq(o1.get_phase(), ConstructOrder.Phase.BUILDER_ASSEMBLING)
		elif cycle == 10:
			assert_eq(spy.get_work_progress_sec(), 2.5, "Cycle 10 hits exact 1/12 milestone")
			assert_eq(spy.get_consumed_amount(&"wood"), 1, "Cycle 10 consumes 1st wood")
			assert_eq(spy.get_delivered_buffer_amount(&"wood"), 1)
			assert_false(bool(spy.last_result.get("starved", false)))
			assert_eq(o1.get_phase(), ConstructOrder.Phase.BUILDER_ASSEMBLING)
		elif cycle < 20:
			assert_eq(spy.get_consumed_amount(&"wood"), 1)
			assert_false(bool(spy.last_result.get("starved", false)))
			assert_eq(o1.get_phase(), ConstructOrder.Phase.BUILDER_ASSEMBLING)
		else:
			assert_eq(spy.get_work_progress_sec(), 4.999999, "Cycle 20 clamps at 4_999_999 usec")
			assert_eq(spy.get_consumed_amount(&"wood"), 1)
			assert_eq(spy.get_delivered_buffer_amount(&"wood"), 1)
			assert_true(bool(spy.last_result.get("starved", false)))
			assert_eq(spy.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
			assert_eq(o1.get_phase(), ConstructOrder.Phase.WAITING_FOR_MATERIALS, "Cycle 20 transitions order immediately to WAITING_FOR_MATERIALS")

	var buf_before_wait: int = buf_signals[0]
	var state_before_wait: int = state_signals[0]

	# Cycles 21..24: ConstructOrder must perform ZERO polling calls to contribute_work().
	for _idle_cycle: int in range(21, 25):
		await wait_physics_frames(1)
		o1.physics_update(u1.get_movement(), 0.25)
		assert_eq(o1.get_phase(), ConstructOrder.Phase.WAITING_FOR_MATERIALS)

	assert_eq(spy.contribute_calls, 20, "Cycles 21..24 must issue 0 calls to contribute_work()")
	assert_eq(spy.contribute_calls_in_waiting, 0)
	assert_eq(buf_signals[0], buf_before_wait, "Zero redundant buffer_changed signals while WAITING_FOR_MATERIALS")
	assert_eq(state_signals[0], state_before_wait, "Zero redundant state_changed signals while WAITING_FOR_MATERIALS")

	# Direct unit call in PAUSED_STARVED stays non-advancing and must NOT debit 2nd wood.
	await wait_physics_frames(1)
	var paused_direct: Dictionary = spy.contribute_work(u1, 0.25)
	assert_true(bool(paused_direct["ok"]))
	assert_eq(paused_direct["advanced_sec"], 0.0)
	assert_true(bool(paused_direct["starved"]))
	assert_eq(spy.get_work_progress_sec(), 4.999999)
	assert_eq(spy.get_consumed_amounts(), {&"wood": 1, &"stone": 0})
	assert_eq(spy.get_delivered_buffer_amounts(), {&"wood": 1, &"stone": 0})

	# Physical delivery of 1 stone emits buffer_changed -> signals wake ConstructOrder without polling!
	_deliver_from_reserved(spy, inventory, w0, &"stone", 1)
	assert_eq(o1.get_phase(), ConstructOrder.Phase.BUILDER_ASSEMBLING, "Signal wakeup moves order from WAITING_FOR_MATERIALS to BUILDER_ASSEMBLING")

	await wait_physics_frames(1)
	o1.physics_update(u1.get_movement(), 0.000001)
	assert_eq(spy.get_work_progress_sec(), 5.0, "Crosses 1/6 milestone atomically after stone delivery")
	assert_eq(spy.get_consumed_amounts(), {&"wood": 2, &"stone": 1})
	assert_eq(spy.get_delivered_buffer_amounts(), {&"wood": 0, &"stone": 0})
	assert_eq(spy.get_assembly_substate(), ConstructionSite.AssemblySubstate.ASSEMBLING)
	assert_eq(o1.get_phase(), ConstructOrder.Phase.BUILDER_ASSEMBLING)

	# Advance remaining slack up to next bottleneck (w_max(wood) = 7_499_999 usec) -> pauses again!
	for _k: int in range(10):
		await wait_physics_frames(1)
		o1.physics_update(u1.get_movement(), 0.25)
	assert_eq(spy.get_work_progress_sec(), 7.499999)
	assert_eq(spy.get_consumed_amounts(), {&"wood": 2, &"stone": 1})
	assert_eq(spy.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
	assert_eq(o1.get_phase(), ConstructOrder.Phase.WAITING_FOR_MATERIALS)
	assert_true(spy.verify_accounting_invariant())

	w0.set_physics_process(true)
	u1.set_physics_process(true)
	vp.queue_free()
	await wait_process_frames(2)


func test_02_t34_aut_10_parallel_logistics_starvation_wakeup_and_full_completion() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport(true)
	var vp: SubViewport = ctx["vp"] as SubViewport
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var w1: Unit = units[0]
	var w2: Unit = units[1]

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res["ok"]))
	var spy: SpyConstructionSite = res["site"] as SpyConstructionSite
	var completed_id_spy: StringName = spy.site_id
	assert_not_null(spy)

	# Initially deliver only {wood: 2, stone: 0}; keep remaining {wood: 10, stone: 6} reserved in camp piles.
	_deliver_from_reserved(spy, inventory, w1, &"wood", 2)
	w1.global_position = camp.global_position + Vector3(0.0, 0.0, 2.0)
	w2.global_position = SITE_POS_A + Vector3(0.0, 0.0, 2.85)
	await wait_physics_frames(2)

	# Hold transporter w1 briefly until builder w2 exhausts initial buffer and pauses at 4_999_999 usec.
	w1.set_physics_process(false)
	var o1 := ConstructOrder.new(spy, camp)
	var o2 := ConstructOrder.new(spy, camp)
	spy.watched_order = o2
	w1.issue_order(o1)
	w2.issue_order(o2)

	var starv_frames: int = 0
	while spy.get_assembly_substate() != ConstructionSite.AssemblySubstate.PAUSED_STARVED and starv_frames < 1200:
		await wait_physics_frames(1)
		starv_frames += 1

	assert_eq(spy.get_site_state(), ConstructionSite.SiteState.ACTIVE)
	assert_eq(spy.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
	assert_eq(o2.get_phase(), ConstructOrder.Phase.WAITING_FOR_MATERIALS)
	assert_eq(spy.get_work_progress_sec(), 4.999999)
	assert_eq(spy.get_consumed_amounts(), {&"wood": 1, &"stone": 0})
	assert_eq(spy.get_delivered_buffer_amounts(), {&"wood": 1, &"stone": 0})

	var calls_at_starve: int = spy.contribute_calls
	await wait_physics_frames(12)
	assert_eq(spy.contribute_calls, calls_at_starve, "Builder must perform 0 contribute_work polling calls while waiting")

	# Resume physical transporter logistics until stone wakeup, full supply, and 100% completion.
	w1.set_physics_process(true)
	var saw_wakeup_crossing: bool = false
	var saw_post_supply_dual_builder: bool = false
	var sim_frames: int = 0
	while is_instance_valid(spy) and not spy.is_completed_or_completing() and sim_frames < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		if not is_instance_valid(spy):
			break
		sim_frames += 1
		if not saw_wakeup_crossing and spy.get_work_progress_sec() >= 5.0 and spy.get_consumed_amount(&"stone") >= 1:
			saw_wakeup_crossing = true
		if spy.is_fully_supplied() and spy.get_worker_role(w1) == ConstructionSite.WorkerRole.BUILDER and spy.get_worker_role(w2) == ConstructionSite.WorkerRole.BUILDER:
			saw_post_supply_dual_builder = true

	await wait_physics_frames(4)
	assert_true(saw_wakeup_crossing, "Delivering stone must wake builder via buffer_changed and cross 5_000_000 usec")
	assert_true(saw_post_supply_dual_builder, "Transporter must promote to 2nd BUILDER slot on supply completion")
	var final_spy: Dictionary = await _assert_completed(ctx, completed_id_spy)
	assert_eq(final_spy["site_state"], ConstructionSite.SiteState.COMPLETED)
	assert_eq(final_spy["work_sec"], 30.0)
	assert_eq(final_spy["ratio"], 1.0)
	assert_eq(final_spy["consumed"], {&"wood": 12, &"stone": 6})
	assert_eq(final_spy["delivered_buffer"], {&"wood": 0, &"stone": 0})
	assert_eq(final_spy["total_received"][&"wood"], 12)
	assert_eq(final_spy["total_received"][&"stone"], 6)
	assert_eq(final_spy["reserved_in_piles"][&"wood"], 0)
	assert_eq(final_spy["reserved_in_piles"][&"stone"], 0)
	assert_eq(final_spy["missing"][&"wood"], 0)
	assert_eq(final_spy["missing"][&"stone"], 0)
	assert_true(final_spy["invariant"])
	assert_eq(o1.status, UnitOrder.Status.SUCCEEDED)
	assert_eq(o2.status, UnitOrder.Status.SUCCEEDED)
	assert_eq(w1.get_state(), Unit.State.IDLE)
	assert_eq(w2.get_state(), Unit.State.IDLE)
	assert_false(is_instance_valid(spy), "Site removed after permanent building registration")

	vp.queue_free()
	await wait_process_frames(2)


func test_03_t34_aut_10b_wood_decay_starvation_no_auto_realloc_and_manual_complement() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport(true)
	var vp: SubViewport = ctx["vp"] as SubViewport
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var pile_mgr: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var time_p: SimulatedWorldTimeProvider = ctx["time"] as SimulatedWorldTimeProvider
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var w_seed: Unit = units[0]
	var worker: Unit = units[1]

	var slots: Array[Vector3] = camp.get_candidate_slots()
	assert_true(slots.size() >= 3)
	var pos_1: Vector3 = slots[0]
	var pos_stone: Vector3 = slots[1]
	var pos_3: Vector3 = slots[2]

	var pile_w1: GroundResourcePile = pile_mgr.try_create_pile_at(&"wood", 12, pos_1)
	var pile_s1: GroundResourcePile = pile_mgr.try_create_pile_at(&"stone", 6, pos_stone)
	assert_not_null(pile_w1)
	assert_not_null(pile_s1)

	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res["ok"]))
	var spy: SpyConstructionSite = res["site"] as SpyConstructionSite
	var completed_id_spy: StringName = spy.site_id
	assert_not_null(spy)

	# Initial buffer {wood: 2, stone: 6} (stone can_decay=false per DEC-11A); Pile 1 holds 10 reserved wood at 420s grace end.
	_deliver_from_reserved(spy, inventory, w_seed, &"wood", 2)
	_deliver_from_reserved(spy, inventory, w_seed, &"stone", 6)
	assert_eq(pile_w1.amount, 10)
	pile_w1.apply_state(10, 420.0, 0.0)

	# 1. Advance clock +1200.0s -> Pile 1 decays 10 wood (10 -> 0, removed); stone buffer stays intact (DEC-11A).
	time_p.advance(1200.0)
	var losses: Dictionary = pile_mgr.step_decay()
	assert_eq(int(losses.get(&"wood", 0)), 10)
	assert_eq(int(losses.get(&"stone", 0)), 0)
	assert_false(pile_mgr.has_reservation(spy.reservation_id))
	assert_eq(spy.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(spy.get_missing_amount(&"wood"), 10)
	assert_eq(spy.get_delivered_buffer_amounts(), {&"wood": 2, &"stone": 6})
	assert_true(spy.verify_accounting_invariant())

	# 2. Create independent Pile 3 (10 free wood, 0 reserved) post-decay: NO silent auto-reallocation.
	var pile_3: GroundResourcePile = pile_mgr.try_create_pile_at(&"wood", 10, pos_3)
	assert_not_null(pile_3)
	assert_eq(pile_3.amount, 10)
	assert_eq(pile_mgr.get_pile_available_amount(pile_3.pile_id), 10)
	assert_eq(spy.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(spy.get_missing_amount(&"wood"), 10)

	# 3. Assign sole worker -> builds from buffer until starving at exact 7_499_999 usec ({w:2, s:1} consumed, {w:0, s:5} buffer).
	worker.global_position = SITE_POS_A + Vector3(0.0, 0.0, 2.85)
	await wait_physics_frames(2)
	var order := ConstructOrder.new(spy, camp)
	spy.watched_order = order
	worker.issue_order(order)
	assert_eq(spy.get_worker_role(worker), ConstructionSite.WorkerRole.BUILDER, "Sole worker with 0 reserved piles & consumable buffer promotes via try_promote_solo_to_builder")

	var starv_f: int = 0
	while spy.get_assembly_substate() != ConstructionSite.AssemblySubstate.PAUSED_STARVED and starv_f < 1500:
		await wait_physics_frames(1)
		starv_f += 1

	assert_eq(spy.get_site_state(), ConstructionSite.SiteState.ACTIVE)
	assert_eq(spy.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
	assert_eq(order.get_phase(), ConstructOrder.Phase.WAITING_FOR_MATERIALS)
	assert_eq(spy.get_work_progress_sec(), 7.499999, "Must stall strictly at 7_499_999 usec")
	assert_eq(spy.get_consumed_amounts(), {&"wood": 2, &"stone": 1})
	assert_eq(spy.get_delivered_buffer_amounts(), {&"wood": 0, &"stone": 5})

	var calls_at_starve: int = spy.contribute_calls
	await wait_physics_frames(15)
	assert_eq(spy.contribute_calls, calls_at_starve, "0 contribute_work calls while awaiting DEC-11B complement")
	assert_eq(spy.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(pile_mgr.get_pile_available_amount(pile_3.pile_id), 10)

	# 4. Authorize DEC-11B manual complement -> reserves 10 wood in Pile 3 -> physical delivery -> completes 30s (100%).
	var intent := ManualComplementIntent.create_for_test(self, spy)
	assert_not_null(intent)
	var comp_out: Dictionary = spy.authorize_manual_complement(intent, {}, false)
	assert_true(bool(comp_out["ok"]))
	assert_eq(int((comp_out["complemented"] as Dictionary).get(&"wood", 0)), 10)
	assert_eq(spy.get_missing_amount(&"wood"), 0)
	assert_eq(spy.get_reserved_in_piles_amount(&"wood"), 10)
	assert_eq(pile_mgr.get_pile_available_amount(pile_3.pile_id), 0)
	assert_eq(spy.get_work_progress_sec(), 7.499999, "Manual complement preserves exact prior progress")
	assert_eq(spy.get_consumed_amounts(), {&"wood": 2, &"stone": 1})

	var comp_f: int = 0
	while is_instance_valid(spy) and not spy.is_completed_or_completing() and comp_f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		if not is_instance_valid(spy):
			break
		comp_f += 1
	await wait_physics_frames(4)

	var final_spy: Dictionary = await _assert_completed(ctx, completed_id_spy)
	assert_eq(final_spy["site_state"], ConstructionSite.SiteState.COMPLETED)
	assert_eq(final_spy["work_sec"], 30.0)
	assert_eq(final_spy["ratio"], 1.0)
	assert_eq(final_spy["consumed"], {&"wood": 12, &"stone": 6})
	assert_eq(final_spy["delivered_buffer"], {&"wood": 0, &"stone": 0})
	assert_eq(final_spy["reserved_in_piles"][&"wood"], 0)
	assert_eq(final_spy["missing"][&"wood"], 0)
	assert_true(final_spy["invariant"])
	assert_eq(order.status, UnitOrder.Status.SUCCEEDED)
	assert_eq(worker.get_state(), Unit.State.IDLE)

	vp.queue_free()
	await wait_process_frames(2)


func test_04_t34_aut_11_d9_one_two_three_fourth_worker_and_interruption_resume() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport(true)
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var command: CommandController = ctx["command"] as CommandController
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var base_units: Array[Unit] = ctx["units"] as Array[Unit]
	var w1: Unit = base_units[0]
	var w2: Unit = base_units[1]
	var w3: Unit = _spawn_extra_worker(main_root, nav, "D9_W3", SITE_POS_B + Vector3(-2.5, 0.0, 2.0))
	var w4: Unit = _spawn_extra_worker(main_root, nav, "D9_W4", SITE_POS_B + Vector3(-3.5, 0.0, -2.0))

	# Subcase 1 (1 worker DEC-18): supplies all accessible materials with 0 progress during transport, then promotes & assembles at 1.0 s/s.
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var site1: SpyConstructionSite = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)["site"] as SpyConstructionSite
	var completed_id_site1: StringName = site1.site_id
	assert_not_null(site1)

	w1.global_position = camp.global_position + Vector3(-1.0, 0.0, 2.0)
	await wait_physics_frames(2)
	assert_true(command.command_units_to_site(site1, [w1]))
	assert_eq(site1.get_worker_role(w1), ConstructionSite.WorkerRole.SOLO_SUPPLIER)

	var zero_progress_while_supplying: bool = true
	var f1: int = 0
	while not site1.is_fully_supplied() and f1 < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		f1 += 1
		if site1.get_work_progress_sec() > 0.0:
			zero_progress_while_supplying = false
	assert_true(site1.is_fully_supplied())
	assert_true(zero_progress_while_supplying, "DEC-18 solo supplier must transport all materials before starting assembly")

	while is_instance_valid(site1) and not site1.is_completed_or_completing() and f1 < MAX_SIM_FRAMES * 2:
		await wait_physics_frames(1)
		if not is_instance_valid(site1):
			break
		f1 += 1
	await wait_physics_frames(4)
	var final_site1: Dictionary = await _assert_completed(ctx, completed_id_site1)
	assert_eq(final_site1["site_state"], ConstructionSite.SiteState.COMPLETED)
	assert_eq(final_site1["consumed"], {&"wood": 12, &"stone": 6})
	assert_eq(w1.get_state(), Unit.State.IDLE)

	# Subcase 2 (2 workers D9): 1 TRANSPORTER + 1 BUILDER assemble in parallel, then dual BUILDERs at 2.0 s/s.
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var site2: SpyConstructionSite = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, -5.0))["site"] as SpyConstructionSite
	var completed_id_site2: StringName = site2.site_id
	assert_not_null(site2)
	w1.global_position = camp.global_position + Vector3(-1.0, 0.0, 2.0)
	w2.global_position = Vector3(-6.0, 0.0, -5.0 + 2.85)
	await wait_physics_frames(2)

	assert_true(command.command_units_to_site(site2, [w1, w2]))
	assert_eq(site2.get_worker_role(w1), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site2.get_worker_role(w2), ConstructionSite.WorkerRole.BUILDER)

	var saw_parallel_progress_before_full_supply: bool = false
	var saw_dual_builders_after_supply: bool = false
	var f2: int = 0
	while is_instance_valid(site2) and not site2.is_completed_or_completing() and f2 < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		if not is_instance_valid(site2):
			break
		f2 += 1
		if not site2.is_fully_supplied() and site2.get_work_progress_sec() > 0.0:
			saw_parallel_progress_before_full_supply = true
		if site2.is_fully_supplied() and site2.get_worker_role(w1) == ConstructionSite.WorkerRole.BUILDER and site2.get_worker_role(w2) == ConstructionSite.WorkerRole.BUILDER:
			saw_dual_builders_after_supply = true
	await wait_physics_frames(4)
	assert_true(saw_parallel_progress_before_full_supply, "2-worker team must assemble in parallel before full supply")
	assert_true(saw_dual_builders_after_supply, "2-worker transporter must promote to 2nd BUILDER slot on supply completion")
	var final_site2: Dictionary = await _assert_completed(ctx, completed_id_site2)
	assert_eq(final_site2["site_state"], ConstructionSite.SiteState.COMPLETED)
	assert_eq(final_site2["consumed"], {&"wood": 12, &"stone": 6})
	assert_eq(w1.get_state(), Unit.State.IDLE)
	assert_eq(w2.get_state(), Unit.State.IDLE)

	# Subcase 3 & 4 (3 workers + 4th rejected + MoveOrder interruption/resume):
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var site3: SpyConstructionSite = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(0.0, 0.0, -5.0))["site"] as SpyConstructionSite
	var completed_id_site3: StringName = site3.site_id
	assert_not_null(site3)
	w1.global_position = camp.global_position + Vector3(-1.0, 0.0, 2.0)
	w2.global_position = Vector3(0.0, 0.0, -5.0 + 2.85)
	w3.global_position = Vector3(-1.1, 0.0, -5.0 + 2.85)
	await wait_physics_frames(2)

	assert_true(command.command_units_to_site(site3, [w1, w2, w3]))
	assert_eq(site3.get_worker_role(w1), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site3.get_worker_role(w2), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(site3.get_worker_role(w3), ConstructionSite.WorkerRole.BUILDER)
	assert_false(command.command_units_to_site(site3, [w4]), "4th worker must be rejected (no_worker_slot)")
	assert_eq(command.get_last_command_reason(), ConstructOrder.REASON_NO_WORKER_SLOT)

	# Wait until supply completes -> 3rd-team transporter exits to IDLE while 2 builders assemble.
	var f3: int = 0
	while not site3.is_fully_supplied() and f3 < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		f3 += 1
	await wait_physics_frames(4)
	assert_eq(w1.get_state(), Unit.State.IDLE, "3-worker transporter must exit to IDLE once site is supplied and 2 builders exist")
	assert_eq(site3.get_worker_role(w2), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(site3.get_worker_role(w3), ConstructionSite.WorkerRole.BUILDER)

	# Let 2 builders advance past 10s, then interrupt both with MoveOrder (PAUSED_NO_WORKERS), verify preservation, then resume!
	while site3.get_work_progress_sec() < 12.0 and f3 < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		f3 += 1
	assert_true(site3.get_work_progress_sec() >= 12.0 and site3.get_work_progress_sec() < 28.0)

	w2.issue_order(MoveOrder.new(Vector3(-3.0, 0.0, -8.0)))
	w3.issue_order(MoveOrder.new(Vector3(3.0, 0.0, -8.0)))
	await wait_physics_frames(3)
	assert_eq(site3.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_NO_WORKERS)
	var saved_progress: float = site3.get_work_progress_sec()
	var saved_consumed: Dictionary = site3.get_consumed_amounts()
	var saved_buffer: Dictionary = site3.get_delivered_buffer_amounts()
	assert_true(site3.verify_accounting_invariant())

	# Resume with both workers -> reaches exact COMPLETING without duplicate material consumption.
	assert_true(command.command_units_to_site(site3, [w2, w3]))
	while is_instance_valid(site3) and not site3.is_completed_or_completing() and f3 < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		if not is_instance_valid(site3):
			break
		f3 += 1
	await wait_physics_frames(4)
	assert_true(saved_progress >= 12.0)
	assert_eq(int(saved_consumed.get(&"wood", 0)) + int(saved_buffer.get(&"wood", 0)), 12)
	assert_eq(int(saved_consumed.get(&"stone", 0)) + int(saved_buffer.get(&"stone", 0)), 6)
	var final_site3: Dictionary = await _assert_completed(ctx, completed_id_site3)
	assert_eq(final_site3["site_state"], ConstructionSite.SiteState.COMPLETED)
	assert_eq(final_site3["work_sec"], 30.0)
	assert_eq(final_site3["consumed"], {&"wood": 12, &"stone": 6})
	assert_eq(final_site3["delivered_buffer"], {&"wood": 0, &"stone": 0})
	assert_eq(w2.get_state(), Unit.State.IDLE)
	assert_eq(w3.get_state(), Unit.State.IDLE)

	vp.queue_free()
	await wait_process_frames(2)


func test_05_t34_builder_with_unneeded_cargo_returns_to_camp_then_assembles() -> void:
	# Caso A: BUILDER carrying excess external resources from prior work returns them via
	# DeliverToCampOrder before moving to its assigned anchor and assembling, or fails cleanly
	# without deleting backpack cargo when return is impossible.
	var ctx: Dictionary = await _spawn_main_in_viewport(true)
	var vp: SubViewport = ctx["vp"] as SubViewport
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var w_trans: Unit = units[0]
	var w_builder: Unit = units[1]

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res["ok"]))
	var spy: SpyConstructionSite = res["site"] as SpyConstructionSite
	var completed_id_spy: StringName = spy.site_id
	assert_not_null(spy)

	# Seed initial partial materials {wood: 4, stone: 2} so BUILDER has valid work once pack is cleared.
	_deliver_from_reserved(spy, inventory, w_trans, &"wood", 4)
	_deliver_from_reserved(spy, inventory, w_trans, &"stone", 2)

	# Give future BUILDER unneeded prior cargo (3 food + 2 unattributed wood = 7 kg <= 20 kg), standing near slot 0.
	assert_true(w_builder.get_carry_load().add_units(FOOD_DEF.duplicate() as ResourceDefinition, 3))
	assert_true(w_builder.get_carry_load().add_units(WOOD_DEF.duplicate() as ResourceDefinition, 2))
	w_trans.global_position = camp.global_position + Vector3(-1.0, 0.0, 2.5)
	w_builder.global_position = SITE_POS_A + Vector3(0.0, 0.0, 2.85)
	await wait_physics_frames(2)

	var o_trans := ConstructOrder.new(spy, camp)
	var o_builder := ConstructOrder.new(spy, camp)
	w_trans.issue_order(o_trans)
	w_builder.issue_order(o_builder)

	assert_eq(spy.get_worker_role(w_trans), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(spy.get_worker_role(w_builder), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(o_builder.get_phase(), ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO, "BUILDER with excess cargo must return it to camp instead of idling in BUILDER_STANDBY")
	assert_eq(w_builder.get_carry_load().get_amount(&"food"), 3)
	assert_eq(w_builder.get_carry_load().get_amount(&"wood"), 2)

	var saw_camp_returned: bool = false
	var saw_builder_assembling: bool = false
	var f: int = 0
	while is_instance_valid(spy) and not spy.is_completed_or_completing() and f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		if not is_instance_valid(spy):
			break
		f += 1
		if not saw_camp_returned and w_builder.get_carry_load().is_empty():
			if inventory.get_available_amount(&"food") == 3 and inventory.get_available_amount(&"wood") == 2:
				saw_camp_returned = true
		if o_builder.is_active() and o_builder.get_phase() == ConstructOrder.Phase.BUILDER_ASSEMBLING and spy.get_work_progress_sec() > 0.0:
			saw_builder_assembling = true

	await wait_physics_frames(4)
	assert_true(saw_camp_returned, "BUILDER must physically return unneeded food and wood to camp stock")
	assert_true(saw_builder_assembling, "BUILDER must move to slot and assemble after returning excess cargo")
	var final_spy: Dictionary = await _assert_completed(ctx, completed_id_spy)
	assert_eq(final_spy["site_state"], ConstructionSite.SiteState.COMPLETED)
	assert_eq(final_spy["consumed"], {&"wood": 12, &"stone": 6})
	assert_eq(final_spy["delivered_buffer"], {&"wood": 0, &"stone": 0})
	assert_eq(inventory.get_available_amount(&"food"), 3, "Returned excess food must remain conserved at camp")
	assert_eq(inventory.get_available_amount(&"wood"), 2, "Returned excess wood must never leak into site buffer or disappear")
	assert_true(w_builder.get_carry_load().is_empty())
	assert_eq(o_builder.status, UnitOrder.Status.SUCCEEDED)
	assert_eq(w_builder.get_state(), Unit.State.IDLE)
	assert_true(final_spy["invariant"])

	# Subcheck (Contract #5 & #6): impossible camp return fails explicitly without deleting pack cargo or stalling silently.
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var site_fail: SpyConstructionSite = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_B)["site"] as SpyConstructionSite
	assert_not_null(site_fail)
	assert_true(w_builder.get_carry_load().add_units(FOOD_DEF.duplicate() as ResourceDefinition, 2))
	w_trans.issue_order(ConstructOrder.new(site_fail, camp))
	var o_fail := ConstructOrder.new(site_fail, null)
	w_builder.issue_order(o_fail)
	await wait_physics_frames(2)
	assert_eq(o_fail.status, UnitOrder.Status.FAILED, "Missing camp zone for unneeded return must fail explicitly")
	assert_eq(o_fail.failure_reason, ConstructOrder.REASON_UNNEEDED_CARGO_REJECTED)
	assert_eq(w_builder.get_carry_load().get_amount(&"food"), 2, "Failed return must preserve unit backpack cargo intact")
	assert_eq(w_builder.get_state(), Unit.State.IDLE)

	vp.queue_free()
	await wait_process_frames(2)


func test_06_t34_builder_with_usable_and_unneeded_cargo_delivers_then_returns_then_assembles() -> void:
	# Caso B: BUILDER holds both site-attributed claimed cargo (3 wood) AND excess unneeded
	# cargo (2 unattributed wood + 2 food) within weight capacity (12/20 kg).
	# Must prioritize site drop-off of the 3 claimed wood first, then return (2 wood + 2 food) to camp,
	# then occupy its builder slot and assemble without loss, duplication, or leakage.
	var ctx: Dictionary = await _spawn_main_in_viewport(true)
	var vp: SubViewport = ctx["vp"] as SubViewport
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var w_trans: Unit = units[0]
	var w_builder: Unit = units[1]

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res["ok"]))
	var spy: SpyConstructionSite = res["site"] as SpyConstructionSite
	var completed_id_spy: StringName = spy.site_id
	assert_not_null(spy)

	# Withdraw 3 attributed wood into w_builder and claim transit ownership, then add 2 external wood + 2 food.
	var wood_entries: Array[Dictionary] = inventory.get_reserved_pile_entries(spy.reservation_id, &"wood")
	assert_false(wood_entries.is_empty())
	var withdrawn: int = inventory.withdraw_reserved_from_pile_to_carry_load(
		int(wood_entries[0]["pile_id"]),
		spy.reservation_id,
		WOOD_DEF.duplicate() as ResourceDefinition,
		3,
		w_builder.get_carry_load()
	)
	assert_eq(withdrawn, 3)
	spy.record_withdrawn_for_site(w_builder, &"wood", 3)
	assert_true(w_builder.get_carry_load().add_units(WOOD_DEF.duplicate() as ResourceDefinition, 2))
	assert_true(w_builder.get_carry_load().add_units(FOOD_DEF.duplicate() as ResourceDefinition, 2))
	assert_eq(w_builder.get_carry_load().get_amount(&"wood"), 5)
	assert_eq(w_builder.get_carry_load().get_amount(&"food"), 2)

	w_trans.global_position = camp.global_position + Vector3(-2.0, 0.0, 2.5)
	w_builder.global_position = Vector3(-9.0, 0.0, 4.5)
	await wait_physics_frames(2)

	var o_trans := ConstructOrder.new(spy, camp)
	var o_builder := ConstructOrder.new(spy, camp)
	w_trans.issue_order(o_trans)
	w_builder.issue_order(o_builder)

	assert_eq(spy.get_worker_role(w_trans), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(spy.get_worker_role(w_builder), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(o_builder.get_phase(), ConstructOrder.Phase.MOVING_TO_SITE_DROPOFF, "BUILDER must deliver usable claimed site cargo before returning unneeded items")
	assert_eq(spy.get_work_progress_sec(), 0.0)
	assert_eq(spy.get_in_transit_amount(&"wood"), 3)

	var saw_usable_delivered_only: bool = false
	var saw_returning_unneeded: bool = false
	var saw_builder_assembling_empty_pack: bool = false
	var sim_f: int = 0
	while is_instance_valid(spy) and not spy.is_completed_or_completing() and sim_f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		if not is_instance_valid(spy):
			break
		sim_f += 1
		if not saw_usable_delivered_only and spy.get_in_transit_amount(&"wood") == 0 and spy.get_total_received_amount(&"wood") >= 3:
			if w_builder.get_carry_load().get_amount(&"wood") >= 2 and w_builder.get_carry_load().get_amount(&"food") == 2:
				saw_usable_delivered_only = true
		if o_builder.is_active() and o_builder.get_phase() == ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO:
			saw_returning_unneeded = true
		if o_builder.is_active() and o_builder.get_phase() == ConstructOrder.Phase.BUILDER_ASSEMBLING:
			if w_builder.get_carry_load().is_empty():
				saw_builder_assembling_empty_pack = true

	await wait_physics_frames(4)
	assert_true(saw_usable_delivered_only, "Site drop-off must take only the 3 attributed wood and leave excess pack intact")
	assert_true(saw_returning_unneeded, "Remaining excess cargo must transition BUILDER to RETURNING_UNNEEDED_CARGO")
	assert_true(saw_builder_assembling_empty_pack, "After returning excess cargo, BUILDER must occupy slot and assemble")
	var final_spy: Dictionary = await _assert_completed(ctx, completed_id_spy)
	assert_eq(final_spy["site_state"], ConstructionSite.SiteState.COMPLETED)
	assert_eq(final_spy["work_sec"], 30.0)
	assert_eq(final_spy["consumed"], {&"wood": 12, &"stone": 6})
	assert_eq(final_spy["delivered_buffer"], {&"wood": 0, &"stone": 0})
	assert_eq(inventory.get_available_amount(&"wood"), 2, "Excess unattributed 2 wood must be conserved in camp")
	assert_eq(inventory.get_available_amount(&"food"), 2, "Excess 2 food must be conserved in camp")
	assert_eq(w_builder.get_state(), Unit.State.IDLE)
	assert_true(final_spy["invariant"])

	vp.queue_free()
	await wait_process_frames(2)


func test_07_t34_reactive_wait_zero_polling_after_cargo_return_and_duplicate_guard() -> void:
	# Caso C: After a BUILDER clears unneeded cargo and pauses in WAITING_FOR_MATERIALS at 4_999_999 usec,
	# verify ZERO calls to contribute_work(), preservation of duplicate-frame guard, exact in-transit
	# accounting conservation, and clean signal wakeup when stone arrives.
	var ctx: Dictionary = await _spawn_main_in_viewport(true)
	var vp: SubViewport = ctx["vp"] as SubViewport
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var w0: Unit = units[0]
	var u1: Unit = units[1]

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res["ok"]))
	var spy: SpyConstructionSite = res["site"] as SpyConstructionSite
	assert_not_null(spy)

	# Pre-deliver {wood: 2, stone: 0} via w0 and hold w0 paused during u1's return + assembly starvation test.
	_deliver_from_reserved(spy, inventory, w0, &"wood", 2)
	assert_true(u1.get_carry_load().add_units(FOOD_DEF.duplicate() as ResourceDefinition, 2))
	w0.global_position = camp.global_position + Vector3(-2.0, 0.0, 2.0)
	u1.global_position = camp.global_position + Vector3(0.0, 0.0, 1.5)
	await wait_physics_frames(2)

	w0.set_physics_process(false)
	var o0 := ConstructOrder.new(spy, camp)
	var o1 := ConstructOrder.new(spy, camp)
	spy.watched_order = o1
	w0.issue_order(o0)
	u1.issue_order(o1)

	assert_eq(spy.get_worker_role(u1), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(o1.get_phase(), ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO)

	var starv_f: int = 0
	while spy.get_assembly_substate() != ConstructionSite.AssemblySubstate.PAUSED_STARVED and starv_f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		starv_f += 1

	assert_true(u1.get_carry_load().is_empty())
	assert_eq(inventory.get_available_amount(&"food"), 2)
	assert_eq(spy.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
	assert_eq(o1.get_phase(), ConstructOrder.Phase.WAITING_FOR_MATERIALS)
	assert_eq(spy.get_work_progress_sec(), 4.999999)
	assert_eq(spy.get_consumed_amounts(), {&"wood": 1, &"stone": 0})
	assert_eq(spy.get_delivered_buffer_amounts(), {&"wood": 1, &"stone": 0})

	var buf_signals: Array[int] = [0]
	var state_signals: Array[int] = [0]
	spy.buffer_changed.connect(func(_s: ConstructionSite) -> void: buf_signals[0] += 1)
	spy.state_changed.connect(func(_s: ConstructionSite) -> void: state_signals[0] += 1)
	var calls_at_starve: int = spy.contribute_calls
	var waiting_calls_before: int = spy.contribute_calls_in_waiting

	await wait_physics_frames(20)
	assert_eq(spy.contribute_calls, calls_at_starve, "0 calls to contribute_work() across 20 frames in WAITING_FOR_MATERIALS")
	assert_eq(spy.contribute_calls_in_waiting, waiting_calls_before)
	assert_eq(buf_signals[0], 0, "0 buffer_changed signals emitted while waiting in starvation")
	assert_eq(state_signals[0], 0, "0 redundant state_changed signals emitted while waiting in starvation")

	# Verify per-frame duplicate guard stays intact alongside conservation.
	await wait_physics_frames(1)
	var first_direct: Dictionary = spy.contribute_work(u1, 0.25)
	var dup_direct: Dictionary = spy.contribute_work(u1, 0.25)
	assert_true(bool(first_direct["ok"]))
	assert_eq(first_direct["advanced_sec"], 0.0)
	assert_false(bool(dup_direct["ok"]))
	assert_eq(dup_direct["reason"], "duplicate_cycle_contribution")
	assert_eq(spy.get_work_progress_sec(), 4.999999)
	assert_eq(spy.get_consumed_amounts(), {&"wood": 1, &"stone": 0})

	# Withdraw 2 stone into w0 transit claim and verify exact conservation across reserved/in_transit/buffer/consumed.
	var stone_entries: Array[Dictionary] = inventory.get_reserved_pile_entries(spy.reservation_id, &"stone")
	assert_false(stone_entries.is_empty())
	var withdrawn_stone: int = inventory.withdraw_reserved_from_pile_to_carry_load(
		int(stone_entries[0]["pile_id"]),
		spy.reservation_id,
		STONE_DEF.duplicate() as ResourceDefinition,
		2,
		w0.get_carry_load()
	)
	assert_eq(withdrawn_stone, 2)
	spy.record_withdrawn_for_site(w0, &"stone", 2)
	assert_eq(spy.get_in_transit_amount(&"stone"), 2)
	assert_eq(spy.get_reserved_in_piles_amount(&"stone"), 4)
	assert_eq(spy.get_missing_amount(&"stone"), 0)
	assert_true(spy.verify_accounting_invariant())

	# Delivering stone via w0 wakes u1 via signal and advances cleanly past 5_000_000 usec.
	var delivered: Dictionary = spy.accept_delivery_from_carry_load(w0, w0.get_carry_load())
	assert_eq(int(delivered.get(&"stone", 0)), 2)
	assert_eq(o1.get_phase(), ConstructOrder.Phase.BUILDER_ASSEMBLING)

	var wake_f: int = 0
	while spy.get_work_progress_sec() < 5.0 and wake_f < 60:
		await wait_physics_frames(1)
		wake_f += 1
	assert_true(spy.get_work_progress_sec() >= 5.0)
	assert_eq(spy.get_consumed_amount(&"wood"), 2)
	assert_eq(spy.get_consumed_amount(&"stone"), 1)
	assert_eq(inventory.get_available_amount(&"food"), 2)
	assert_true(spy.verify_accounting_invariant())

	w0.set_physics_process(true)
	vp.queue_free()
	await wait_process_frames(2)


func _assert_completed(ctx: Dictionary, id: StringName) -> Dictionary:
	var cm: ConstructionManager = ctx["cm"]
	var records: Dictionary = ctx["completed_records"]
	var frames: int = 0
	while not records.has(id) and frames < 120:
		await wait_process_frames(1)
		frames += 1
	assert_true(records.has(id), "Completion signal must preserve accounting evidence before node removal")
	var found: BuildingInstance = null
	for b: BuildingInstance in cm.get_completed_buildings():
		if b.building_id == id:
			found = b
	assert_not_null(found)
	if found != null:
		assert_true(found.is_valid())
		assert_eq(found.incorporated_materials, {&"wood": 12, &"stone": 6})
		assert_true(cm.has_building_overlapping_rect(found.get_footprint_rect()))
	assert_null(cm.get_site_by_id(id))
	return records.get(id, {})
