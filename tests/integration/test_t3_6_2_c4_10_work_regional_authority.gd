extends TestCase

# Reuse the two storage backends and manager fixtures without inheriting their tests.
const Fixtures = preload("res://tests/integration/test_t3_6_2_c4_9_r2_scope_finalization.gd")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")

var _fixtures: Fixtures


class BackendOrder extends ConstructOrder:
	func start(body: CharacterBody3D, _move: UnitMovement, _nav: WorldNavigation) -> void:
		_unit = body as Unit
		mark_running()
		site.register_worker(_unit, self)

	func physics_update(_move: UnitMovement, _delta: float) -> void:
		pass


func before_each() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_test_child(viewport)
	_fixtures = Fixtures.new()
	viewport.add_child(_fixtures)


func after_each() -> void:
	_fixtures.after_each()
	_fixtures.cleanup_tracked_nodes()


func _region(id: StringName, physical: bool) -> Dictionary:
	return _fixtures._create_gpm_env(id) if physical else _fixtures._create_mem_env(id)


func _site(fx: Dictionary, pos: Vector3, supply: int = 4) -> Dictionary:
	var inv: SettlementInventory = fx.inventory
	var cm: ConstructionManager = fx.cm
	var def := _fixtures._make_def(&"c410_work", {&"wood": 4})
	def.build_work_required_sec = 1.0
	assert_true(inv.deposit(&"wood", 4))
	var result := cm.try_create_site_from_placement(def, pos)
	assert_true(result.get("ok", false), str(result))
	var site: ConstructionSite = result.site
	var units: Array[Unit] = []
	for offset: float in [0.0, -0.8, 0.8]:
		var unit := UNIT_SCENE.instantiate() as Unit
		unit.definition = LEADER.duplicate() as CharacterDefinition
		fx.host.add_child(unit)
		unit.global_position = pos + Vector3(offset, 0, 1.7)
		unit.set_physics_process(false)
		unit.issue_order(BackendOrder.new(site))
		units.append(unit)
	assert_eq(site.get_worker_role(units[0]), ConstructionSite.WorkerRole.TRANSPORTER)
	if supply > 0:
		_supply(inv, site, units[0], supply)
	for i: int in range(1, 3):
		assert_eq(site.get_worker_role(units[i]), ConstructionSite.WorkerRole.BUILDER)
		assert_true(site.assign_builder_slot_position(units[i], i - 1, units[i].global_position))
	return {"site": site, "units": units}


func _supply(inv: SettlementInventory, site: ConstructionSite, worker: Unit, units: int) -> void:
	assert_true(inv.withdraw_reserved(site.reservation_id, &"wood", units), "%s withdraw %d" % [site.region_id, units])
	assert_true(worker.get_carry_load().add_units(WOOD, units), "%s cargo %d" % [site.region_id, units])
	site.record_withdrawn_for_site(worker, &"wood", units)
	assert_eq(site.accept_delivery_from_carry_load(worker, worker.get_carry_load()).get(&"wood"), units)


func _snapshot(site: ConstructionSite) -> Array:
	return [site._work_progress_usec, site.get_delivered_buffer_amounts(), site.get_consumed_amounts(),
		site.get_site_state(), site.get_assembly_substate(), site.get_transaction_revision(), site._work_cycle_serial]


func test_region_serializes_callbacks_with_real_peer_contribution() -> void:
	for physical: bool in [true, false]:
		var fx := _region(&"c410_ab_ground" if physical else &"c410_ab_memory", physical)
		var other := _region(&"c410_other_ground" if physical else &"c410_other_memory", physical)
		var a := _site(fx, Vector3(5, 0, 5))
		var b := _site(fx, Vector3(12, 0, 5))
		var c := _site(other, Vector3(25, 0, 5))
		var site_a: ConstructionSite = a.site
		var site_b: ConstructionSite = b.site
		var site_c: ConstructionSite = c.site
		var world := site_a.get_world_3d()
		assert_eq(world, site_c.get_world_3d())
		var inv: SettlementInventory = fx.inventory
		var peer_before := _snapshot(site_b)
		var events := {}
		var on_buffer := func(_site: ConstructionSite) -> void:
			events["busy"] = ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, site_a.region_id)
			events["other_busy"] = ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, site_c.region_id)
			events["same_site"] = site_a.contribute_work(a.units[2], 0.25)
			events["peer"] = site_b.contribute_work(b.units[1], 0.25)
			events["deposit"] = inv.deposit(&"wood", 1)
			var cm: ConstructionManager = fx.cm
			events["placement"] = cm.try_create_site_from_placement(site_a.definition, Vector3(19, 0, 5))
			events["other"] = site_c.contribute_work(c.units[1], 0.25)
		var on_state := func(_site: ConstructionSite) -> void:
			events["state_busy"] = ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, site_a.region_id)
		site_a.buffer_changed.connect(on_buffer, CONNECT_ONE_SHOT)
		site_a.state_changed.connect(on_state, CONNECT_ONE_SHOT)
		assert_true(site_a.contribute_work(a.units[1], 0.25).ok)
		var peer_after := _snapshot(site_b)
		print("[C410] physical=%s callbacks=%s peer=%s=>%s" % [physical, events, peer_before, peer_after])
		assert_eq(events.get("busy"), true, "Regional occupancy is visible during consumption")
		assert_eq(events.get("state_busy"), true, "Regional occupancy is visible during progress notification")
		assert_eq(events.get("other_busy"), false)
		assert_eq(events.same_site.reason, "duplicate_cycle_contribution")
		assert_eq(events.peer.get("reason"), "busy")
		assert_eq(peer_after, peer_before)
		assert_false(events.deposit)
		assert_eq(events.placement.reason, "busy")
		assert_true(events.other.ok, str(events.other))
		assert_eq(site_c.get_consumed_amounts(), {&"wood": 1})
		assert_eq(inv.get_physical_amount(&"wood"), 0)
		assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, site_a.region_id))
		assert_false(inv.is_transaction_busy())
		assert_false(site_a.is_transaction_busy())
		assert_eq(site_a.contribute_work(a.units[1], 0.25).reason, "duplicate_cycle_contribution")
		assert_true(site_a.contribute_work(a.units[2], 0.25).ok)
		assert_eq(site_a._work_progress_usec, 500_000)
		assert_eq(site_a.get_consumed_amounts(), {&"wood": 2})


func test_starved_work_resumes_and_completes_automatically() -> void:
	for physical: bool in [true, false]:
		var fx := _region(&"c410_resume_ground" if physical else &"c410_resume_memory", physical)
		var a := _site(fx, Vector3(5 if physical else 28, 0, 5), 1)
		var site: ConstructionSite = a.site
		var cm: ConstructionManager = fx.cm
		var inv: SettlementInventory = fx.inventory
		var world := site.get_world_3d()
		var previous := {}
		var first := site.contribute_work(a.units[1], 0.25)
		assert_true(first.ok, "%s first %s" % [site.region_id, first])
		var starved := site.contribute_work(a.units[2], 0.25)
		assert_true(starved.starved, "%s starved %s" % [site.region_id, starved])
		assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
		assert_true(site.verify_accounting_invariant())
		assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, site.region_id))
		_supply(inv, site, a.units[0], 3)
		for _i: int in range(3):
			await wait_physics_frames(2)
			previous = site.contribute_work(a.units[1], 0.25)
			assert_true(previous.ok, "%s resumed %s" % [site.region_id, previous])
			if previous.completed:
				break
		assert_true(previous.get("completed", false))
		assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, site.region_id))
		await wait_process_frames(2)
		var buildings := cm.get_completed_buildings()
		assert_eq(buildings.size(), 1)
		if buildings.size() == 1:
			assert_eq(buildings[0].incorporated_materials, {&"wood": 4})
		assert_eq(cm.get_sites().size(), 0)
		assert_false(inv.is_transaction_busy())


func test_worker_order_change_cannot_contribute_twice_in_one_frame() -> void:
	var fx := _region(&"c410_worker_frame", false)
	var a := _site(fx, Vector3(5, 0, 5))
	var b := _site(fx, Vector3(12, 0, 5))
	var site_a: ConstructionSite = a.site
	var site_b: ConstructionSite = b.site
	var worker: Unit = a.units[1]
	assert_true(site_a.contribute_work(worker, 0.25).ok)
	var outgoing: Unit = b.units[2]
	outgoing.cancel_current_order()
	worker.global_position = outgoing.global_position
	worker.issue_order(BackendOrder.new(site_b))
	var slot := site_b.get_builder_slot_index(worker)
	assert_true(site_b.assign_builder_slot_position(worker, slot, worker.global_position))
	var before := _snapshot(site_b)
	var repeated := site_b.contribute_work(worker, 0.25)
	assert_eq(repeated.reason, "duplicate_cycle_contribution")
	assert_eq(_snapshot(site_b), before)
	await wait_physics_frames(2)
	assert_true(site_b.contribute_work(worker, 0.25).ok)
