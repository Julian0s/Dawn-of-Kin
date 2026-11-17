extends TestCase
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const COSTS: Dictionary = {&"wood": 12, &"stone": 6}
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")

class BackendOrder extends ConstructOrder:
	func start(body: CharacterBody3D, _move: UnitMovement, _nav: WorldNavigation) -> void:
		_unit = body as Unit
		mark_running()
		site.register_worker(_unit, self)
	func physics_update(_move: UnitMovement, _delta: float) -> void:
		pass

class InvalidBuilding extends BuildingInstance:
	func is_valid() -> bool:
		# Pass detached configure(), fail only after entering the scene tree.
		return not is_inside_tree() and super.is_valid()

class HeldNavigation extends WorldNavigation:
	# Real async bake; only callback delivery is held to reproduce an adversarial schedule.
	var held_session: CandidateSession = null
	var held_callback: Callable = Callable()
	func create_candidate_session_async(boxes: Array[Dictionary], callback: Callable) -> AsyncBakeToken:
		held_callback = callback
		return super.create_candidate_session_async(boxes, func(session: CandidateSession) -> void: held_session = session)
	func release_callback() -> void:
		held_callback.call(held_session)
		held_session = null
		held_callback = Callable()

func _fixture(region_id: StringName = &"default", held_navigation: bool = false) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	add_test_child(vp)
	var root := Node3D.new()
	root.set_meta(&"region_id", region_id)
	vp.add_child(root)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = CollisionLayers.MASK_TERRAIN
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	var nav: WorldNavigation = HeldNavigation.new() if held_navigation else WorldNavigation.new()
	nav.map_bounds = Rect2(-19, -19, 38, 38)
	root.add_child(nav)
	var sites := Node3D.new()
	root.add_child(sites)
	var inventory := SettlementInventory.new(InMemoryStorageSource.new())
	assert_true(inventory.deposit(&"wood", 24))
	assert_true(inventory.deposit(&"stone", 12))
	var cm := ConstructionManager.new()
	root.add_child(cm)
	cm.configure(sites, inventory, {}, null, nav, region_id)
	var result: Dictionary = cm.try_create_site_from_placement(SHELTER, Vector3.ZERO)
	assert_true(result["ok"])
	var site: ConstructionSite = result["site"]
	var units: Array[Unit] = []
	for i: int in range(2):
		var unit: Unit = UNIT_SCENE.instantiate() as Unit
		unit.definition = preload("res://data/characters/leader_a.tres").duplicate()
		unit.position = Vector3(float(i), 0, 2.85)
		root.add_child(unit)
		unit.set_physics_process(false)
		unit.issue_order(BackendOrder.new(site))
		units.append(unit)
	assert_true(site.assign_builder_slot_position(units[1], 0, units[1].position))
	_supply(site, inventory, units[0])
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < 120:
		await wait_physics_frames(1)
		frames += 1
	assert_true(nav.is_navigation_ready())
	return {"vp": vp, "root": root, "nav": nav, "cm": cm, "site": site, "units": units, "inventory": inventory}

func _supply(site: ConstructionSite, inventory: SettlementInventory, unit: Unit) -> void:
	for key: Variant in COSTS:
		var left: int = int(COSTS[key])
		var resource: ResourceDefinition = load("res://data/resources/%s.tres" % String(key)) as ResourceDefinition
		while left > 0:
			var take: int = mini(left, unit.get_carry_load().get_max_additional_units(resource))
			assert_true(inventory.withdraw_reserved(site.reservation_id, key, take))
			assert_true(unit.get_carry_load().add_units(resource, take))
			site.record_withdrawn_for_site(unit, key, take)
			assert_eq(int(site.accept_delivery_from_carry_load(unit, unit.get_carry_load()).get(key, 0)), take)
			left -= take


func _assemble(fx: Dictionary) -> void:
	var site: ConstructionSite = fx["site"]
	var worker: Unit = fx["units"][1]
	for i: int in range(120):
		await wait_physics_frames(1)
		assert_true(site.contribute_work(worker, 0.25)["ok"])
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	assert_true(site.is_inside_tree(), "Final contribution cannot remove the node on its own stack")

func _wait_for_building(cm: ConstructionManager) -> BuildingInstance:
	var frames: int = 0
	while cm.get_completed_buildings().is_empty() and frames < 240:
		await wait_process_frames(1)
		frames += 1
	assert_eq(cm.get_completed_buildings().size(), 1)
	return cm.get_completed_buildings()[0] if cm.get_completed_buildings().size() == 1 else null

func test_01_t34_aut_05a_single_failure_partial_cleanup_cooldown_and_retry() -> void:
	var fx: Dictionary = await _fixture()
	var cm: ConstructionManager = fx["cm"]
	var site: ConstructionSite = fx["site"]
	var attempts: Array[int] = [0]
	var partials: Array[int] = []
	cm.building_creator_override = func(_site: ConstructionSite) -> BuildingInstance:
		attempts[0] += 1
		if attempts[0] == 1:
			var partial := InvalidBuilding.new()
			partials.append(partial.get_instance_id())
			return partial
		return BuildingInstance.new()
	await _assemble(fx)
	await wait_process_frames(2)
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE)
	assert_eq(site.get_work_progress_sec(), 30.0)
	assert_eq(site.get_consumed_amounts(), COSTS)
	assert_true(site.verify_accounting_invariant())
	assert_true(site.is_inside_tree())
	assert_true(cm.has_footprint_overlapping_rect(site.get_footprint_rect()))
	assert_false(is_instance_id_valid(partials[0]))
	assert_eq(cm._buildings_root.get_child_count(), 0)
	assert_eq(site.contribute_work(fx["units"][1], 0.1)["reason"], "completion_pending_retry")
	assert_false(cm.retry_failed_site_completion(site), "Explicit call cannot bypass automatic cooldown")
	await get_tree().create_timer(0.5).timeout
	assert_eq(attempts[0], 1)
	var building: BuildingInstance = await _wait_for_building(cm)
	assert_true(building.is_valid())
	assert_eq(attempts[0], 2)
	assert_eq(building.incorporated_materials, COSTS)
	await wait_process_frames(2)
	assert_false(is_instance_valid(site))
	assert_eq(cm.get_sites().size(), 0)

func test_02_t34_aut_05b_three_failures_block_and_explicit_recovery() -> void:
	var fx: Dictionary = await _fixture()
	var cm: ConstructionManager = fx["cm"]
	var site: ConstructionSite = fx["site"]
	var attempts: Array[int] = [0]
	var failures: Array[String] = []
	site.site_completion_failed.connect(func(_s: ConstructionSite, reason: String) -> void: failures.append(reason))
	cm.building_creator_override = func(_site: ConstructionSite) -> Variant:
		attempts[0] += 1
		return null
	await _assemble(fx)
	await get_tree().create_timer(2.3).timeout
	assert_eq(attempts[0], 3)
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR)
	assert_eq(site.get_completion_diagnostic()["attempts_failed"], 3)
	assert_eq(failures.size(), 1)
	await get_tree().create_timer(1.1).timeout
	assert_eq(attempts[0], 3)
	assert_eq(site.get_consumed_amounts(), COSTS)
	assert_true(site.verify_accounting_invariant())
	cm.building_creator_override = Callable()
	assert_true(cm.retry_failed_site_completion(site))
	assert_false(cm.retry_failed_site_completion(site))
	var building: BuildingInstance = await _wait_for_building(cm)
	assert_eq(building.incorporated_materials, COSTS)

func test_03_t34_aut_05c_reentrancy_dedup_and_no_occupancy_gap() -> void:
	var fx: Dictionary = await _fixture()
	var cm: ConstructionManager = fx["cm"]
	var site: ConstructionSite = fx["site"]
	var emitted: Array[int] = [0]
	var nested: Array[bool] = []
	cm.building_creator_override = func(s: ConstructionSite) -> BuildingInstance:
		nested.append(cm.complete_site_transaction(s))
		cm._on_site_state_changed(s)
		return BuildingInstance.new()
	site.site_completed.connect(func(s: ConstructionSite, b: BuildingInstance) -> void:
		emitted[0] += 1
		assert_true(cm.get_sites().has(s))
		assert_true(cm.get_completed_buildings().has(b))
		assert_true(cm.has_footprint_overlapping_rect(s.get_footprint_rect()))
		assert_true(b.is_valid())
		assert_eq(cm.try_create_site_from_placement(SHELTER, s.global_position)["reason"], "building_overlap")
		nested.append(cm.complete_site_transaction(s))
	)
	await _assemble(fx)
	var building: BuildingInstance = await _wait_for_building(cm)
	await wait_process_frames(2)
	assert_eq(emitted[0], 1)
	assert_eq(nested, [false, false])
	assert_eq(cm.get_completed_buildings().size(), 1)
	assert_eq(building.incorporated_materials, COSTS)
	for unit: Unit in fx["units"]:
		assert_true(unit.get_current_order().is_succeeded())

func test_04_t34_aut_07_same_frame_hover_confirm_async_physics_and_stock() -> void:
	var fx: Dictionary = await _fixture()
	var cm: ConstructionManager = fx["cm"]
	var site: ConstructionSite = fx["site"]
	var validator := PlacementValidator.new()
	var context := PlacementValidator.ValidationContext.from_region(fx["root"], fx["nav"])
	var seen: Array[int] = [0]
	site.site_completed.connect(func(_s: ConstructionSite, b: BuildingInstance) -> void:
		seen[0] += 1
		assert_eq(validator.validate_hover(SHELTER, b.global_position, context).reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP)
		assert_eq(validator.validate_confirm(SHELTER, b.global_position, context).reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP)
		var results: Array[PlacementValidator.ValidationResult] = []
		validator.validate_confirm_async(SHELTER, b.global_position, context, func(r: PlacementValidator.ValidationResult) -> void: results.append(r))
		assert_eq(results.size(), 1)
		assert_false(results[0].valid)
	)
	var inventory: SettlementInventory = fx["inventory"]
	var free_before: int = inventory.get_available_amount(&"wood")
	await _assemble(fx)
	var prepared := BuildingInstance.new()
	assert_true(prepared.configure(site.site_id, site.definition, site.region_id, site.get_consumed_amounts()))
	assert_true(cm.complete_site_transaction(site, prepared), "R2-03 also accepts a preconfigured instance")
	var b: BuildingInstance = await _wait_for_building(cm)
	assert_eq(seen[0], 1)
	assert_eq(b.building_id, site.site_id if is_instance_valid(site) else &"site_default_0001")
	assert_eq(b.definition, SHELTER)
	assert_eq(BuildingInstance.resolve_from_collider(b._body), b)
	assert_eq((b._shape.shape as BoxShape3D).size, Vector3(4, 3, 4))
	assert_eq(cm.try_create_site_from_placement(SHELTER, b.global_position)["reason"], "building_overlap")
	assert_eq(inventory.get_available_amount(&"wood"), free_before)
	await wait_physics_frames(2)
	assert_eq(validator.validate_hover(SHELTER, b.global_position, context).reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP)
	assert_true(b._body.is_inside_tree())
	var ray := PhysicsRayQueryParameters3D.create(b.global_position + Vector3(0, 5, 0), b.global_position + Vector3(0, 0.1, 0), CollisionLayers.MASK_BUILDINGS)
	var hit: Dictionary = b.get_world_3d().direct_space_state.intersect_ray(ray)
	assert_false(hit.is_empty(), "Permanent collider remains in the physics server after synchronization")
	assert_eq(BuildingInstance.resolve_from_collider(hit.get("collider")), b)

func test_05_t34_aut_07_adversarial_pending_async_and_revision_without_cache() -> void:
	var fx: Dictionary = await _fixture(&"default", true)
	var nav: HeldNavigation = fx["nav"] as HeldNavigation
	var cm: ConstructionManager = fx["cm"]
	var target := Vector3(8, 0, 0)
	var context := PlacementValidator.ValidationContext.from_region(fx["root"], nav)
	var validator := PlacementValidator.new()
	var results: Array[PlacementValidator.ValidationResult] = []
	var token: WorldNavigation.AsyncBakeToken = validator.validate_confirm_async(SHELTER, target, context,
		func(r: PlacementValidator.ValidationResult) -> void: results.append(r))
	assert_not_null(token)
	# Another placement creates and fully assembles an actual site at that location
	# while the earlier candidate's completion callback is pending.
	var created: Dictionary = cm.try_create_site_from_placement(SHELTER, target)
	assert_true(created["ok"])
	var site: ConstructionSite = created["site"]
	var units: Array[Unit] = fx["units"]
	for i: int in range(2):
		units[i].position = target + Vector3(float(i), 0, 2.85)
		units[i].issue_order(BackendOrder.new(site))
	assert_true(site.assign_builder_slot_position(units[1], 0, units[1].position))
	_supply(site, fx["inventory"], units[0])
	fx["site"] = site
	await _assemble(fx)
	await _wait_for_building(cm)
	var frames: int = 0
	while nav.held_session == null and frames < 180:
		await wait_process_frames(1)
		frames += 1
	assert_not_null(nav.held_session)
	assert_true(results.is_empty())
	nav.release_callback()
	assert_eq(results.size(), 1)
	assert_false(results[0].valid)
	assert_eq(results[0].reason_code, PlacementValidator.REASON_NAVIGATION_STALE)
	var revision: int = nav.get_navigation_revision()
	nav.invalidate_static_geometry_cache()
	nav.notify_building_geometry_changed()
	assert_gt(float(nav.get_navigation_revision()), float(revision))
	assert_true(nav.is_navigation_ready(), "No active rebake in T3.4.4")


func test_06_t34_aut_07_world_and_region_isolation() -> void:
	var first: Dictionary = await _fixture(&"region_a")
	var second: Dictionary = await _fixture(&"region_b")
	await _assemble(first)
	await _wait_for_building(first["cm"])
	var context_a := PlacementValidator.ValidationContext.from_region(first["root"], first["nav"])
	var context_b := PlacementValidator.ValidationContext.from_region(second["root"], second["nav"])
	assert_eq(context_a.completed_buildings.size(), 1)
	assert_eq(context_b.completed_buildings.size(), 0)
	assert_ne(first["root"].get_world_3d(), second["root"].get_world_3d())
	# Same world, different logical region must also filter group-discovered buildings.
	var other_region := Node3D.new()
	other_region.set_meta(&"region_id", &"region_b")
	first["root"].add_child(other_region)
	var other_context := PlacementValidator.ValidationContext.from_region(other_region, first["nav"])
	assert_eq(other_context.completed_buildings.size(), 0)


func test_07_regional_root_mismatch_preserves_site_then_recovers() -> void:
	var fx: Dictionary = await _fixture()
	var cm: ConstructionManager = fx["cm"]
	var site: ConstructionSite = fx["site"]
	await _assemble(fx)
	cm._buildings_root.set_meta(&"region_id", &"wrong_region")
	assert_false(cm.complete_site_transaction(site))
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE)
	assert_eq(site.get_completion_diagnostic()["reason"], "invalid_buildings_root")
	assert_eq(site.get_consumed_amounts(), COSTS)
	assert_true(site.is_inside_tree())
	cm._buildings_root.set_meta(&"region_id", &"default")
	var building: BuildingInstance = await _wait_for_building(cm)
	assert_eq(building.region_id, &"default")
	assert_eq(building.incorporated_materials, COSTS)


func test_08_invalid_factory_return_cannot_free_existing_scene_nodes() -> void:
	var fx: Dictionary = await _fixture()
	var cm: ConstructionManager = fx["cm"]
	var site: ConstructionSite = fx["site"]
	cm.building_creator_override = func(s: ConstructionSite) -> Variant: return s
	await _assemble(fx)
	await wait_process_frames(2)
	assert_true(is_instance_valid(site))
	assert_true(site.is_inside_tree())
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE)
	assert_eq(site.get_consumed_amounts(), COSTS)
	assert_true(cm.get_sites().has(site))
	cm.building_creator_override = Callable()
	var building: BuildingInstance = await _wait_for_building(cm)
	assert_eq(building.incorporated_materials, COSTS)


func test_09_t34_aut_07_stale_hover_context_after_site_removal_before_physics_sync() -> void:
	var fx: Dictionary = await _fixture()
	var site: ConstructionSite = fx["site"]
	var cm: ConstructionManager = fx["cm"]
	var context := PlacementValidator.ValidationContext.from_region(fx["root"], fx["nav"])
	var validator := PlacementValidator.new()
	var other_region := Node3D.new()
	other_region.set_meta(&"region_id", &"independent_region")
	fx["root"].add_child(other_region)
	var other_context := PlacementValidator.ValidationContext.from_region(other_region, fx["nav"])
	assert_true(context.construction_sites.has(site))
	assert_eq(context.completed_buildings.size(), 0)
	var site_id: StringName = site.site_id
	await _assemble(fx)
	assert_true(cm.complete_site_transaction(site))
	assert_null(cm.get_site_by_id(site_id))
	assert_false(site.is_inside_tree())
	assert_eq(cm.get_completed_buildings().size(), 1)
	var building: BuildingInstance = cm.get_completed_buildings()[0]
	assert_eq(building.building_id, site_id)
	assert_true(context.construction_sites.has(site), "Original snapshot still holds the removed site")
	assert_eq(context.completed_buildings.size(), 0, "Original snapshot predates the building")
	var refreshed: PlacementValidator.ValidationContext = context.refresh_dynamic_state()
	assert_false(refreshed.construction_sites.has(site))
	assert_true(refreshed.completed_buildings.has(building))
	assert_false(other_context.refresh_dynamic_state().completed_buildings.has(building), "Another region in the same world excludes this building")
	# Both old and new physical colliders are excluded: only logical occupancy can reject.
	# No physics frame is awaited between transaction and hover.
	var original_layer: int = building._body.collision_layer
	building._body.collision_layer = 0
	site._site_body.collision_layer = 0
	var same_frame: PlacementValidator.ValidationResult = validator.validate_hover(SHELTER, building.global_position, context)
	assert_false(same_frame.valid)
	assert_eq(same_frame.reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP)
	assert_eq(same_frame.reason_text, "Completed building occupies this area.")
	var other_hover: PlacementValidator.ValidationResult = validator.validate_hover(SHELTER, building.global_position, other_context)
	assert_ne(other_hover.reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP, "The other region does not inherit the completed footprint; the shared fixture navmesh may reject its terrain independently")
	building._body.collision_layer = original_layer
	await wait_physics_frames(2)
	var after_sync: PlacementValidator.ValidationResult = validator.validate_hover(SHELTER, building.global_position, context)
	assert_false(after_sync.valid)
	assert_eq(after_sync.reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP)
	assert_true(validator.validate_hover(SHELTER, Vector3(10, 0, 10), context).valid)
