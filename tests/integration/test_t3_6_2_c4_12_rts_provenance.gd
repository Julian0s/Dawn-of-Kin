extends TestCase

const MAIN := preload("res://src/main/main.tscn")
const SHELTER := preload("res://data/buildings/shelter_basic.tres")


func _scene() -> MainScene:
	var main := MAIN.instantiate() as MainScene
	add_test_child(main)
	return main


func _until(condition: Callable, frames: int = 1800) -> bool:
	for frame: int in range(frames):
		if condition.call():
			return true
		await wait_physics_frames(1)
	return false


func before_each() -> void:
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0


func after_each() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func test_default_scene_admits_leaders_and_temporary_workers() -> void:
	var main := _scene()
	var nav := main.get_test_map().get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 180))
	var workers := main.get_placement_test_overlay().get_temporary_workers_controller()
	assert_true(workers.spawn_temporary_workers().ok)
	var ids: Array[StringName] = []
	for unit: Unit in main.get_units():
		var load := unit.get_carry_load()
		assert_true(load.validate_provenance())
		assert_true(load.is_empty())
		assert_eq(load.get_provenance_unit_id(), unit.get_character_id())
		assert_eq(unit.get_meta(&"region_id"), main._economy_region_id)
		ids.append(load.get_provenance_unit_id())
	assert_eq(ids, [&"leader_a", &"leader_b", &"test_worker_3", &"test_worker_4"])
	assert_true(workers.remove_temporary_workers_safely().ok)


func test_initial_admission_failure_preserves_both_loads() -> void:
	for reason: String in ["duplicate", "loaded", "domain"]:
		var main := MAIN.instantiate() as MainScene
		var leader_a := main.get_node("Units/LeaderA") as Unit
		var leader_b := main.get_node("Units/LeaderB") as Unit
		var a := leader_a.get_carry_load()
		var b := leader_b.get_carry_load()
		if reason == "duplicate":
			leader_b.definition = leader_a.definition
		elif reason == "loaded":
			assert_true(b.add_resource(&"wood", 1, 1))
		else:
			main._economy_region_id = &""
		var before := b.get_all_amounts()
		var revision_a := a.get_transaction_revision()
		var revision_b := b.get_transaction_revision()
		var events: Array[bool] = []
		a.load_changed.connect(func() -> void: events.append(true))
		b.load_changed.connect(func() -> void: events.append(true))
		add_test_child(main)
		assert_false(main._economy_admission_reason.is_empty(), reason)
		assert_false(a.is_provenance_enabled(), reason)
		assert_false(b.is_provenance_enabled(), reason)
		assert_eq(b.get_all_amounts(), before, reason)
		assert_eq(a.get_transaction_revision(), revision_a, reason)
		assert_eq(b.get_transaction_revision(), revision_b, reason)
		assert_eq(events.size(), 0, reason)
		assert_null(main.get_placement_test_overlay().get_temporary_workers_controller())
		main.get_parent().remove_child(main)
		main.queue_free()


func test_economic_dispatch_rejects_ambiguous_identity_before_replacing_order() -> void:
	var main := _scene()
	var map := main.get_test_map()
	assert_true(await _until(func() -> bool: return map.get_navigation().is_navigation_ready(), 180))
	var leaders := main.get_units()
	var unit := leaders[0]
	var load := unit.get_carry_load()
	var source := map.get_resource_sources()[0]
	var command := main.get_command_controller()
	main.get_selection_manager().select_single(unit)
	unit.issue_order(MoveOrder.new(unit.global_position + Vector3(1.0, 0.0, 0.0)))
	var previous := unit.get_current_order()
	assert_not_null(previous)
	leaders[1].get_carry_load()._provenance_unit = load.get_provenance_unit_id()
	var before := load.provenance_snapshot()
	var revision := load.get_transaction_revision()
	var remaining := source.get_remaining_amount()
	var rejects: Array[String] = []
	command.command_rejected.connect(func(_pick: PickResult, reason: String) -> void: rejects.append(reason))
	assert_false(command.command_at(PickResult.from_resource_source(source, source.global_position, Vector3.UP)))
	assert_eq(rejects, ["ambiguous_unit_identity"])
	assert_eq(unit.get_current_order(), previous)
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(load.get_transaction_revision(), revision)
	assert_eq(source.get_remaining_amount(), remaining)


func test_real_rts_gathers_delivers_and_completes_shelter() -> void:
	var main := _scene()
	var map := main.get_test_map()
	var nav := map.get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 180))
	var leaders := main.get_units()
	var leader := leaders[0]
	var load := leader.get_carry_load()
	var inv := main.get_settlement_inventory()
	var command := main.get_command_controller()
	main.get_economy_clock().set_process(false)
	main.get_selection_manager().select_single(leader)
	for resource: StringName in [&"food", &"wood", &"stone"]:
		var source: ResourceSource = null
		for candidate: ResourceSource in map.get_resource_sources():
			if candidate.definition.resource_id == resource:
				source = candidate
				break
		assert_not_null(source, String(resource))
		if source == null:
			return
		var physical_start := inv.get_physical_amount(resource)
		var source_start := source.get_remaining_amount()
		var target := int(SHELTER.costs.get(resource, 1))
		var pick := PickResult.from_resource_source(source, source.global_position, Vector3.UP)
		assert_true(command.command_at(pick), command.get_last_command_reason())
		var order := leader.get_current_order() as GatherResourceOrder
		assert_not_null(order)
		if order == null:
			return
		assert_true(order.use_provenance_transactions)
		assert_true(await _until(func() -> bool: return load.get_amount(resource) > 0 or order.is_finished()))
		assert_true(load.get_current_weight() > 0, order.failure_reason)
		assert_true(load.validate_provenance())
		assert_true(await _until(func() -> bool: return inv.get_physical_amount(resource) >= target or order.is_finished(), 4200))
		assert_true(inv.get_physical_amount(resource) >= target, order.failure_reason)
		assert_eq(source_start - source.get_remaining_amount(), inv.get_physical_amount(resource) - physical_start + load.get_amount(resource))
		leader.cancel_current_order()
		assert_null(order.get_active_gather_session())
	var manager := main.get_construction_manager()
	var created := manager.try_create_site_from_placement(SHELTER, Vector3(-6.0, 0.0, 1.5))
	assert_true(created.ok, str(created))
	if not created.ok:
		return
	var site := created.site as ConstructionSite
	assert_true(command.command_units_to_site(site, leaders), command.get_last_command_reason())
	assert_true(await _until(func() -> bool: return manager.get_completed_buildings().size() == 1, 6500))
	var buildings := manager.get_completed_buildings()
	if buildings.size() == 1:
		assert_eq(buildings[0].incorporated_materials, SHELTER.costs)
	assert_eq(manager.get_sites().size(), 0)
	for worker: Unit in leaders:
		assert_true(worker.get_carry_load().validate_provenance())
	var world := main.get_world_3d()
	main.get_parent().remove_child(main)
	assert_true(main.get_last_domain_release_result().ok)
	main.queue_free()
	var next := _scene()
	assert_eq(next.get_world_3d(), world)
	assert_true(next._economy_admission_reason.is_empty())


func test_real_rts_redirect_returns_to_original_reservation() -> void:
	var main := _scene()
	var nav := main.get_test_map().get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 180))
	var worker := main.get_units()[0]
	var load := worker.get_carry_load()
	var inv := main.get_settlement_inventory()
	var command := main.get_command_controller()
	main.get_economy_clock().set_process(false)
	assert_true(inv.deposit(&"wood", 8))
	assert_true(inv.deposit(&"stone", 4))
	var manager := main.get_construction_manager()
	var def_a := SHELTER.duplicate() as BuildingDefinition
	def_a.costs = {&"stone": 2}
	var def_b := SHELTER.duplicate() as BuildingDefinition
	def_b.costs = {&"wood": 4}
	var a := manager.try_create_site_from_placement(def_a, Vector3(-6.0, 0.0, 1.5))
	var b := manager.try_create_site_from_placement(def_b, Vector3(0.37, 0.0, -13.19))
	assert_true(a.ok and b.ok, str([a, b]))
	if not a.ok or not b.ok:
		return
	var target := a.site as ConstructionSite
	var origin := b.site as ConstructionSite
	main.get_selection_manager().select_single(worker)
	assert_true(command.command_at(PickResult.from_construction_site(origin, origin.global_position, Vector3.UP)))
	assert_true(await _until(func() -> bool: return load.get_amount(&"wood") > 0))
	var amount := load.get_amount(&"wood")
	var reserved := origin.get_reserved_in_piles_amount(&"wood")
	var available := inv.get_available_amount(&"wood")
	var before := load.provenance_snapshot()
	var origin_claim := origin._read_transit_claim_for_unit_pure(worker.get_instance_id())
	assert_eq(origin_claim, {&"wood": amount})
	var pick := PickResult.from_construction_site(target, target.global_position, Vector3.UP)
	assert_true(command.command_at(pick), command.get_last_command_reason())
	var interrupted := worker.get_current_order() as ConstructOrder
	assert_eq(interrupted.get_phase(), ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO)
	worker.cancel_current_order()
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(origin.get_reserved_in_piles_amount(&"wood"), reserved)
	assert_eq(origin._read_transit_claim_for_unit_pure(worker.get_instance_id()), origin_claim)
	assert_true(command.command_at(pick), command.get_last_command_reason())
	var redirected := worker.get_current_order() as ConstructOrder
	assert_true(await _until(func() -> bool: return redirected.camp_return_trips_completed > 0 or redirected.is_finished()))
	assert_eq(redirected.camp_return_trips_completed, 1, redirected.failure_reason)
	assert_eq(load.get_amount(&"wood"), 0)
	assert_eq(origin.get_reserved_in_piles_amount(&"wood"), reserved + amount)
	assert_eq(inv.get_available_amount(&"wood"), available)
	assert_eq(origin._read_transit_claim_for_unit_pure(worker.get_instance_id()), {})
	assert_eq(target.get_delivered_buffer_amount(&"stone"), 0)
	assert_true(await _until(func() -> bool: return redirected.is_finished(), 4800))
	assert_true(redirected.is_succeeded(), redirected.failure_reason)
