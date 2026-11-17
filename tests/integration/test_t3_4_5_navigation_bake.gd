extends TestCase
## T34-AUT-06 / 12 / 12B: real async bakes with controlled callback delivery.
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const COSTS: Dictionary = {&"wood": 12, &"stone": 6}
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const MAP_SCENE: PackedScene = preload("res://levels/test_map/test_map.tscn")

class BackendOrder extends ConstructOrder:
	func start(body: CharacterBody3D, _move: UnitMovement, _nav: WorldNavigation) -> void:
		_unit = body as Unit
		mark_running()
		site.register_worker(_unit, self)
	func physics_update(_move: UnitMovement, _delta: float) -> void:
		pass

class ControlledNavigation extends WorldNavigation:
	var held: Array[Dictionary] = []
	var hold_callbacks: bool = true
	var fail_bakes: bool = false
	var force_planner_fallback: bool = false
	func is_position_reachable(from_pos: Vector3, to_pos: Vector3) -> bool:
		return false if force_planner_fallback else super.is_position_reachable(from_pos, to_pos)
	var diagnostics: Array[String] = []
	func _on_active_rebake_async_complete(token: AsyncBakeToken, mesh: NavigationMesh, started: int) -> void:
		if hold_callbacks:
			held.append({"token": token, "mesh": mesh, "started": started})
		elif fail_bakes:
			_fail_active_rebake("injected_bake_failure")
		else:
			super._on_active_rebake_async_complete(token, mesh, started)
	func release(index: int = 0) -> void:
		var entry: Dictionary = held.pop_at(index)
		super._on_active_rebake_async_complete(entry["token"], entry["mesh"], entry["started"])
	func _report_degraded_error(reason: String) -> void:
		# Capture the expected production diagnostic instead of poisoning strict stderr.
		diagnostics.append(reason)

func _fixture(region_id: StringName = &"default", held_navigation: bool = true) -> Dictionary:
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
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.add_child(floor_body)
	var nav: WorldNavigation = ControlledNavigation.new() if held_navigation else WorldNavigation.new()
	nav.source_root_path = ^"../Terrain"
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


func _wait_held(nav: ControlledNavigation, count: int = 1) -> void:
	for _frame: int in range(180):
		if nav.held.size() >= count:
			break
		await wait_process_frames(1)
	assert_eq(nav.held.size(), count)


func _wait_applied(nav: WorldNavigation) -> void:
	for _frame: int in range(240):
		if nav._pending_building_blockers.is_empty() and nav._active_rebake_token == null:
			break
		await wait_physics_frames(1)
	assert_true(nav._pending_building_blockers.is_empty())
	assert_null(nav._active_rebake_token)
	assert_true(nav.is_navigation_ready())


func _traveller(fx: Dictionary, at: Vector3 = Vector3(-8, 0, 0)) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.definition = preload("res://data/characters/leader_a.tres").duplicate()
	unit.position = at
	(fx["root"] as Node).add_child(unit)
	unit.set_world_navigation(fx["nav"])
	return unit


func test_09_repath_to_partial_target_fails_after_real_rebake() -> void:
	var fx: Dictionary = await _fixture()
	var nav: ControlledNavigation = fx["nav"]
	var unit: Unit = _traveller(fx)
	await _assemble(fx)
	var original := Vector3.ZERO
	assert_true(nav.find_path(unit.global_position, original).is_ok())
	var order := MoveOrder.new(original)
	unit.issue_order(order)
	assert_true(order.is_active())
	assert_false(order.is_partial_unreachable)
	assert_true((fx["cm"] as ConstructionManager).complete_site_transaction(fx["site"]))
	assert_true(unit.get_movement()._awaiting_pending_nav_sync)
	assert_eq(nav.find_path(unit.global_position, original).reason, "pending_building_blocker")
	await _wait_held(nav)
	nav.release()
	await _wait_applied(nav)
	var result: WorldNavigation.PathResult = nav.find_path(unit.global_position, original)
	assert_eq(result.status, WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE)
	assert_false(result.path.is_empty())
	assert_true(unit.get_movement().is_repath_partial_unreachable())
	assert_ne(unit.get_movement().get_target_position(), original)
	for _frame: int in range(300):
		await wait_physics_frames(1)
		assert_false(Rect2(-2, -2, 4, 4).has_point(Vector2(unit.global_position.x, unit.global_position.z)))
		if order.is_finished():
			break
	assert_eq(order.status, UnitOrder.Status.FAILED)
	assert_eq(order.failure_reason, UnitOrder.REASON_UNREACHABLE)
	assert_true(order.is_partial_unreachable)
	assert_eq(order.requested_target, original)
	assert_eq((fx["cm"] as ConstructionManager).get_completed_buildings()[0].incorporated_materials, COSTS)


func test_01_t34_aut_06_coalescence_stale_callback_and_two_buildings() -> void:
	var fx: Dictionary = await _fixture()
	var nav: ControlledNavigation = fx["nav"]
	var cm: ConstructionManager = fx["cm"]
	var second_site: ConstructionSite = cm.try_create_site_from_placement(SHELTER, Vector3(8, 0, 0))["site"]
	# Assemble two real sites simultaneously, with distinct registered builders.
	var other: Unit = _traveller(fx, Vector3(8, 0, 2.85))
	other.set_physics_process(false)
	other.issue_order(BackendOrder.new(second_site))
	var builder: Unit = _traveller(fx, Vector3(9, 0, 2.85))
	builder.set_physics_process(false)
	builder.issue_order(BackendOrder.new(second_site))
	assert_true(second_site.assign_builder_slot_position(builder, 0, builder.position), "T06 assertion 12")
	_supply(second_site, fx["inventory"], other)
	for _step: int in range(119):
		await wait_physics_frames(1)
		assert_true((fx["site"] as ConstructionSite).contribute_work(fx["units"][1], 0.25)["ok"])
		assert_true(second_site.contribute_work(builder, 0.25)["ok"])
	await wait_physics_frames(1)
	assert_true((fx["site"] as ConstructionSite).contribute_work(fx["units"][1], 0.25)["ok"])
	assert_true(cm.complete_site_transaction(fx["site"]))
	var first_token: WorldNavigation.AsyncBakeToken = nav._active_rebake_token
	var old_mesh: NavigationMesh = nav.navigation_mesh
	var first_frame: int = Engine.get_physics_frames()
	assert_eq(nav.navigation_mesh, old_mesh)
	assert_true(nav.has_static_geometry_cache(), "T06 assertion 25")
	await wait_physics_frames(1)
	assert_true(second_site.contribute_work(builder, 0.25)["ok"])
	assert_true(cm.complete_site_transaction(second_site), "T06 assertion 28")
	assert_eq(Engine.get_physics_frames() - first_frame, 1, "The second completion is exactly one physics frame later")
	assert_true(first_token.cancelled, "T06 assertion 30")
	for _frame: int in range(180):
		if not nav.held.is_empty() and nav.held.back()["token"] == nav._active_rebake_token:
			break
		await wait_process_frames(1)
	assert_false(nav.held.is_empty())
	var latest_revision: int = nav._active_rebake_token.revision
	assert_eq(cm.get_completed_buildings().size(), 2)
	assert_eq(nav._pending_building_blockers.size(), 2)
	# Simulate a newer blocker while a previous revision is being cleared.
	nav._pending_building_blockers.append({"revision": latest_revision + 1, "rect": Rect2(15, 15, 1, 1), "permanent_degraded": false})
	nav._clear_applied_building_blockers(latest_revision)
	assert_eq(nav._pending_building_blockers.size(), 1)
	assert_eq(nav._pending_building_blockers[0]["revision"], latest_revision + 1)
	# Restore the two real blockers before applying the actual latest bake.
	nav._pending_building_blockers.clear()
	for b: BuildingInstance in cm.get_completed_buildings():
		nav._pending_building_blockers.append({"revision": latest_revision, "rect": b.get_footprint_rect().grow(0.5), "permanent_degraded": false})
	# The first worker can finish before cancellation (held) or after (discarded by
	# dispatch). In either schedule, explicitly replay the obsolete callback too.
	nav.release(nav.held.size() - 1)
	await _wait_applied(nav)
	var final_mesh: NavigationMesh = nav.navigation_mesh
	while not nav.held.is_empty():
		nav.release(0)
	nav.hold_callbacks = false
	nav._on_active_rebake_async_complete(first_token, old_mesh, Time.get_ticks_usec())
	assert_eq(nav.navigation_mesh, final_mesh, "Late cancelled callback cannot replace the mesh")
	assert_eq(nav._applied_building_revision, latest_revision)
	assert_true(nav.held.is_empty(), "T06 assertion 58")
	assert_true(nav._active_async_tokens.is_empty(), "T06 assertion 59")
	var token_ref: WeakRef = weakref(first_token)
	first_token = null
	await wait_process_frames(2)
	assert_null(token_ref.get_ref(), "Cancelled token is released after callback cleanup")
	for center: Vector3 in [Vector3.ZERO, Vector3(8, 0, 0)]:
		var path: WorldNavigation.PathResult = nav.find_path(center + Vector3(0, 0, -6), center + Vector3(0, 0, 6))
		assert_true(path.is_ok())
		for i: int in range(path.path.size() - 1):
			assert_false(WorldNavigation._segment_intersects_rect(path.path[i], path.path[i + 1], Rect2(Vector2(center.x - 2, -2), Vector2(4, 4))))
	assert_eq((fx["inventory"] as SettlementInventory).get_physical_amount(&"wood"), 0)
	assert_eq(cm.get_completed_buildings()[0].incorporated_materials, COSTS)
	assert_eq(cm.get_completed_buildings()[1].incorporated_materials, COSTS)



func test_02_t34_aut_12b_a_b_c_d_commands_pause_and_resume() -> void:
	var fx: Dictionary = await _fixture()
	var nav: ControlledNavigation = fx["nav"]
	var unit: Unit = _traveller(fx)
	var distant: Unit = _traveller(fx, Vector3(-8, 0, 10))
	await _assemble(fx)
	var order := MoveOrder.new(Vector3(8, 0, 0))
	unit.issue_order(order)
	assert_true(order.is_active())
	(fx["site"] as ConstructionSite).site_completed.connect(func(_site: ConstructionSite, _building: BuildingInstance) -> void:
		assert_eq(nav._pending_building_blockers.size(), 1, "Blocker precedes external completion callbacks")
		assert_eq(nav.find_path(unit.global_position, Vector3(8, 0, 0)).reason, "pending_building_nav_sync")
	)
	assert_true((fx["cm"] as ConstructionManager).complete_site_transaction(fx["site"]))
	assert_true(unit.get_movement()._awaiting_pending_nav_sync, "Blocker signal stops the old agent path synchronously")
	var selection := SelectionManager.new()
	(fx["root"] as Node).add_child(selection)
	selection.select_single(unit)
	var command := CommandController.new()
	(fx["root"] as Node).add_child(command)
	command.configure(selection, nav)
	assert_false(command.command_at(PickResult.from_ground(Vector3(8, 0, 0), Vector3.UP)))
	assert_eq(unit.get_current_order(), order, "Rejected command did not replace the previous order")
	assert_eq(command.get_last_command_reason(), "pending_building_nav_sync")
	assert_false(command.command_at(PickResult.from_ground(Vector3.ZERO, Vector3.UP)))
	assert_eq(command.get_last_command_reason(), "pending_building_blocker")
	selection.select_single(distant)
	assert_true(command.command_at(PickResult.from_ground(Vector3(-4, 0, 10), Vector3.UP)))
	var stopped_position: Vector3 = unit.global_position
	await _wait_held(nav)
	await get_tree().create_timer(1.7).timeout
	assert_true(unit.get_movement()._awaiting_pending_nav_sync)
	assert_lt(Vector2(unit.global_position.x - stopped_position.x, unit.global_position.z - stopped_position.z).length(), 0.05)
	assert_eq(unit.get_movement().get_no_progress_timer(), 0.0)
	assert_true(order.is_active())
	assert_gt(distant.global_position.x, -6.0, "Unaffected command keeps moving while bake callback is held")
	nav.release()
	await _wait_applied(nav)
	assert_false(unit.get_movement()._awaiting_pending_nav_sync)
	var saw_detour: bool = false
	for _frame: int in range(360):
		await wait_physics_frames(1)
		saw_detour = saw_detour or absf(unit.global_position.z) > 2.0
		assert_false(Rect2(-2, -2, 4, 4).has_point(Vector2(unit.global_position.x, unit.global_position.z)))
		if order.is_finished():
			break
	assert_true(saw_detour)
	assert_true(order.is_succeeded())
	assert_near(unit.get_movement().get_effective_move_speed(), 4.8, 0.01)


func test_03_t34_aut_12b_e_three_failures_degraded_no_rollback() -> void:
	var fx: Dictionary = await _fixture()
	var nav: ControlledNavigation = fx["nav"]
	var unit: Unit = _traveller(fx)
	await _assemble(fx)
	var order := MoveOrder.new(Vector3(8, 0, 0))
	unit.issue_order(order)
	nav.hold_callbacks = false
	nav.fail_bakes = true
	var signals: Array[int] = [0]
	nav.navigation_rebake_degraded.connect(func(_count: int, _reason: String) -> void: signals[0] += 1)
	assert_true((fx["cm"] as ConstructionManager).complete_site_transaction(fx["site"]))
	for _frame: int in range(300):
		await wait_physics_frames(1)
		if nav._rebake_degraded:
			break
	assert_true(nav._rebake_degraded)
	assert_eq(nav._active_rebake_attempts, 3)
	assert_eq(nav.diagnostics, ["injected_bake_failure"])
	assert_eq(signals[0], 1)
	assert_true(nav._pending_building_blockers[0]["permanent_degraded"])
	await wait_physics_frames(2)
	assert_eq(order.status, UnitOrder.Status.FAILED)
	assert_eq(order.failure_reason, UnitOrder.REASON_UNREACHABLE)
	assert_false(unit.get_movement()._awaiting_pending_nav_sync)
	assert_eq(nav.find_path(Vector3(-8, 0, 0), Vector3(8, 0, 0)).reason, "navigation_rebake_degraded")
	assert_true(nav.find_path(Vector3(-8, 0, 10), Vector3(8, 0, 10)).is_ok())
	assert_true(nav.is_navigation_ready())
	var building: BuildingInstance = (fx["cm"] as ConstructionManager).get_completed_buildings()[0]
	assert_true(building.is_valid())
	assert_eq(building.incorporated_materials, COSTS)
	assert_true((fx["cm"] as ConstructionManager).get_sites().is_empty())
	await get_tree().create_timer(1.2).timeout
	assert_eq(nav._active_rebake_attempts, 3)
	assert_null(nav._active_rebake_token)


func test_04_t34_aut_12b_no_blockers_and_region_world_isolation() -> void:
	var fx: Dictionary = await _fixture()
	var other: Dictionary = await _fixture(&"other")
	var nav: WorldNavigation = fx["nav"]
	var foreign: WorldNavigation = other["nav"]
	assert_false(nav.is_route_blocked_by_pending_building(Vector3(-8, 0, 0), Vector3(8, 0, 0)))
	assert_false(nav.does_path_intersect_pending_blockers(PackedVector3Array()))
	assert_true(nav.find_path(Vector3(-8, 0, 0), Vector3(8, 0, 0)).is_ok())
	var roots_before: int = nav._additional_source_roots.size()
	nav.register_additional_source_root((other["cm"] as ConstructionManager)._buildings_root)
	assert_eq(nav._additional_source_roots.size(), roots_before)
	var wrong_region := Node3D.new()
	wrong_region.set_meta(&"region_id", &"other")
	(fx["root"] as Node).add_child(wrong_region)
	nav.register_additional_source_root(wrong_region)
	assert_eq(nav._additional_source_roots.size(), roots_before)
	await _assemble(fx)
	assert_true((fx["cm"] as ConstructionManager).complete_site_transaction(fx["site"]))
	assert_true(nav.is_route_blocked_by_pending_building(Vector3(-8, 0, 0), Vector3(8, 0, 0)))
	assert_false(foreign.is_route_blocked_by_pending_building(Vector3(-8, 0, 0), Vector3(8, 0, 0)))
	assert_true(foreign.find_path(Vector3(-8, 0, 0), Vector3(8, 0, 0)).is_ok())
	await _wait_held(nav as ControlledNavigation)
	(nav as ControlledNavigation).release()
	await _wait_applied(nav)
	# Equal boxes from PlacementValidator must produce identical input, not duplicates.
	var building: BuildingInstance = (fx["cm"] as ConstructionManager).get_completed_buildings()[0]
	var a: Dictionary = nav._prepare_candidate_build_inputs([])
	var b: Dictionary = nav._prepare_candidate_build_inputs([{"position": building.global_position, "size": (building._shape.shape as BoxShape3D).size}])
	assert_eq((a["source_data"] as NavigationMeshSourceGeometryData3D).get_vertices().size(), (b["source_data"] as NavigationMeshSourceGeometryData3D).get_vertices().size())
	assert_eq((a["source_data"] as NavigationMeshSourceGeometryData3D).get_indices().size(), (b["source_data"] as NavigationMeshSourceGeometryData3D).get_indices().size())


func test_05_t34_aut_12_real_testmap_ramp_and_physical_detour() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	add_test_child(vp)
	var map: TestMap = MAP_SCENE.instantiate() as TestMap
	vp.add_child(map)
	var nav: WorldNavigation = map.get_navigation()
	for _frame: int in range(120):
		if nav.is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(nav.is_navigation_ready())
	var cached: PackedFloat32Array = nav._cached_static_vertices.duplicate()
	var sites := Node3D.new()
	vp.add_child(sites)
	var inventory := SettlementInventory.new(InMemoryStorageSource.new())
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var cm := ConstructionManager.new()
	vp.add_child(cm)
	cm.configure(sites, inventory, {}, null, nav)
	var created: Dictionary = cm.try_create_site_from_placement(SHELTER, Vector3(17, 2, -14))
	assert_true(created["ok"])
	var site: ConstructionSite = created["site"]
	var builders: Array[Unit] = []
	for idx: int in range(2):
		var worker: Unit = UNIT_SCENE.instantiate() as Unit
		worker.definition = preload("res://data/characters/leader_a.tres").duplicate()
		worker.position = Vector3(17 + idx, 2, -11.15)
		vp.add_child(worker)
		worker.set_physics_process(false)
		worker.issue_order(BackendOrder.new(site))
		builders.append(worker)
	assert_true(site.assign_builder_slot_position(builders[1], 0, builders[1].position))
	_supply(site, inventory, builders[0])
	await _assemble({"site": site, "units": builders})
	assert_true(cm.complete_site_transaction(site))
	var building: BuildingInstance = cm.get_completed_buildings()[0]
	assert_eq(building.incorporated_materials, COSTS)
	assert_false(site.is_inside_tree())
	await _wait_applied(nav)
	assert_eq(nav._cached_static_vertices, cached, "Static terrain + ramp curbs are unchanged")
	var path: WorldNavigation.PathResult = nav.find_path(Vector3(0, 0, -14), Vector3(20, 2, -14))
	assert_true(path.is_ok())
	var traversed_ramp: bool = false
	for point: Vector3 in path.path:
		if point.x > 5 and point.x < 11:
			traversed_ramp = true
			assert_lt(absf(point.z + 14), 2.2)
	assert_true(traversed_ramp)
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.definition = preload("res://data/characters/leader_a.tres").duplicate()
	unit.position = Vector3(0, 0, -14)
	vp.add_child(unit)
	unit.set_world_navigation(nav)
	await wait_physics_frames(3)
	var order := MoveOrder.new(Vector3(20, 2, -14))
	unit.issue_order(order)
	var detour: bool = false
	for _frame: int in range(600):
		await wait_physics_frames(1)
		var p: Vector3 = unit.global_position
		assert_false(building.get_footprint_rect().has_point(Vector2(p.x, p.z)))
		if p.x > 5 and p.x < 11:
			assert_lt(absf(p.z + 14), 2.2, "Physical traversal remains between the ramp curbs")
		if p.x > 13:
			assert_gt(p.y, 1.6, "Unit cannot fall from plateau while detouring")
			detour = detour or absf(p.z + 14) > 2.0
		if order.is_finished():
			break
	assert_true(order.is_succeeded())
	assert_true(detour)


func test_06_t34_aut_12b_construct_order_waits_reactively_then_resumes() -> void:
	var fx: Dictionary = await _fixture()
	var nav: ControlledNavigation = fx["nav"]
	var cm: ConstructionManager = fx["cm"]
	var target: ConstructionSite = cm.try_create_site_from_placement(SHELTER, Vector3(8, 0, 0))["site"]
	var unit: Unit = _traveller(fx)
	await _assemble(fx)
	assert_true(cm.complete_site_transaction(fx["site"]))
	var order := ConstructOrder.new(target)
	unit.issue_order(order)
	# The in-memory fixture has no physical piles. Give the far site materials via
	# real claims/carry/delivery, then ask the registered solo worker to assemble.
	assert_true(order.is_active() or order.is_finished())
	# A dedicated builder exercises the production slot query against old NavMesh.
	var supplier: Unit = _traveller(fx, Vector3(8, 0, 2.85))
	supplier.set_physics_process(false)
	supplier.issue_order(BackendOrder.new(target))
	_supply(target, fx["inventory"], supplier)
	unit.issue_order(ConstructOrder.new(target))
	order = unit.get_current_order() as ConstructOrder
	assert_not_null(order)
	assert_true(order.is_active())
	assert_true(order._waiting_for_navigation)
	var progress: float = target.get_work_progress_sec()
	await _wait_held(nav)
	await wait_physics_frames(12)
	assert_true(order.is_active())
	assert_true(order._waiting_for_navigation)
	assert_eq(target.get_work_progress_sec(), progress)
	assert_eq(target.get_consumed_amounts(), {&"wood": 0, &"stone": 0})
	nav.release()
	await _wait_applied(nav)
	await wait_physics_frames(2)
	assert_false(order._waiting_for_navigation)
	assert_true(order.is_active())
	assert_ne(order.get_phase(), ConstructOrder.Phase.WAITING_FOR_MATERIALS)
	# Terminal degradation also wakes a reactive slot wait, without touching cargo.
	order._wait_for_navigation()
	nav.navigation_rebake_degraded.emit(1, "injected_terminal_failure")
	assert_eq(order.status, UnitOrder.Status.FAILED)
	assert_eq(order.failure_reason, UnitOrder.REASON_UNREACHABLE)
	assert_false(order._waiting_for_navigation)
	assert_eq(target.get_work_progress_sec(), progress)


func test_07_t34_aut_12b_watchdog_rollback_and_bounded_retry() -> void:
	var fx: Dictionary = await _fixture()
	var nav: ControlledNavigation = fx["nav"]
	await _assemble(fx)
	var valid_mesh: NavigationMesh = nav.navigation_mesh
	assert_true((fx["cm"] as ConstructionManager).complete_site_transaction(fx["site"]))
	await _wait_held(nav)
	var stale_token: WorldNavigation.AsyncBakeToken = nav._active_rebake_token
	# Exercise the real watchdog branch with a deterministic expired timestamp.
	nav._active_rebake_started_usec = Time.get_ticks_usec() - 6_000_000
	nav._physics_process(0.016)
	assert_true(stale_token.cancelled)
	assert_eq(nav.navigation_mesh, valid_mesh)
	assert_eq(nav._active_rebake_attempts, 1)
	assert_eq(nav._pending_building_blockers.size(), 1)
	await wait_physics_frames(12)
	assert_eq(nav._active_rebake_attempts, 1, "No per-frame retry during the cooldown")
	nav.release()
	assert_eq(nav.navigation_mesh, valid_mesh)
	await get_tree().create_timer(1.1).timeout
	await _wait_held(nav)
	assert_eq(nav._active_rebake_attempts, 2)
	nav.release()
	assert_true(nav._is_syncing)
	nav._sync_started_usec = Time.get_ticks_usec() - 6_000_000
	nav._physics_process(0.016)
	assert_eq(nav.navigation_mesh, valid_mesh, "Sync timeout restores last valid NavigationMesh")
	assert_eq(nav._pending_building_blockers.size(), 1)
	await get_tree().create_timer(1.1).timeout
	await _wait_held(nav)
	assert_eq(nav._active_rebake_attempts, 3)
	nav.release()
	await _wait_applied(nav)
	assert_false(nav._rebake_degraded)
	assert_eq(nav._active_rebake_attempts, 0)


func test_08_t34_aut_12b_formation_target_cannot_bypass_blocker() -> void:
	var fx: Dictionary = await _fixture()
	var nav: ControlledNavigation = fx["nav"]
	var first: Unit = _traveller(fx, Vector3(-8, 0, 3))
	var second: Unit = _traveller(fx, Vector3(-8, 0, 5))
	await _assemble(fx)
	assert_true((fx["cm"] as ConstructionManager).complete_site_transaction(fx["site"]))
	var selection := SelectionManager.new()
	(fx["root"] as Node).add_child(selection)
	selection.add_units([first, second])
	var command := CommandController.new()
	(fx["root"] as Node).add_child(command)
	command.configure(selection, nav)
	var target := Vector3(0, 0, 2.6)
	nav.force_planner_fallback = true
	assert_false(nav.is_route_blocked_by_pending_building(first.global_position, target))
	assert_false(nav.is_route_blocked_by_pending_building(second.global_position, target))
	assert_false(command.command_at(PickResult.from_ground(target, Vector3.UP)))
	assert_not_null(command.get_last_plan(), "Requested target is clear: rejection comes after formation planning")
	assert_null(first.get_current_order())
	assert_null(second.get_current_order())
	assert_eq(command.get_last_command_reason(), "pending_building_blocker")
	await _wait_held(nav)
	nav.release()
	await _wait_applied(nav)
