extends TestCase
## Unit and spatial validation tests for T3.2 building placement:
## - BuildingDefinition metadata & invalid resource guards
## - Gridless free terrain valid hover/confirm (with and without CampStorageZone)
## - Dynamic D6 CampStorageZone footprint rejection (full, partial, resized)
## - Out-of-bounds, off-terrain void, slope, cliff height-delta rejections
## - Obstacles, natural resources (tree/rock/bush), ground piles (camp & standalone), units
## - Work perimeter unreachable rejection
## - Isolated CandidateSession NavMesh corridor blocking rejection + active nav preservation
## - Zero inventory/pile/reservation side effects & safe NaN/unready navigation handling.

const TEST_MAP_SCENE: PackedScene = preload("res://levels/test_map/test_map.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DEPOT_DEF: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")
const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")
const MAX_WAIT_FRAMES: int = 120


func _wait_for_navigation_ready(nav: WorldNavigation) -> bool:
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	return nav.is_navigation_ready()


func _add_static_box(
	parent: Node3D,
	node_name: String,
	pos: Vector3,
	size: Vector3,
	layer: int
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = pos

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	parent.add_child(body)
	return body


func _build_custom_corridor_region() -> Dictionary:
	var region := Node3D.new()
	region.name = "CustomCorridorRegion"
	add_test_child(region)

	# Continuous terrain slab 36x24 m (x in [-18, 18], z in [-12, 12], top at y=0).
	_add_static_box(
		region,
		"TerrainFloor",
		Vector3(0.0, -0.5, 0.0),
		Vector3(36.0, 1.0, 24.0),
		CollisionLayers.MASK_TERRAIN
	)

	# Perimeter walls enclosing the 36x24 terrain so agents cannot bypass outside.
	_add_static_box(region, "BorderNorth", Vector3(0.0, 1.5, -11.5), Vector3(36.0, 3.0, 1.0), CollisionLayers.MASK_OBSTACLES)
	_add_static_box(region, "BorderSouth", Vector3(0.0, 1.5, 11.5), Vector3(36.0, 3.0, 1.0), CollisionLayers.MASK_OBSTACLES)
	_add_static_box(region, "BorderWest", Vector3(-17.5, 1.5, 0.0), Vector3(1.0, 3.0, 22.0), CollisionLayers.MASK_OBSTACLES)
	_add_static_box(region, "BorderEast", Vector3(17.5, 1.5, 0.0), Vector3(1.0, 3.0, 22.0), CollisionLayers.MASK_OBSTACLES)

	# Internal divider at x=0 leaving a single 4.6 m corridor in z in [-2.3, 2.3].
	# North divider: z in [-11.0, -2.3] => center -6.65, size 8.7
	_add_static_box(region, "DividerNorth", Vector3(0.0, 1.5, -6.65), Vector3(2.0, 3.0, 8.7), CollisionLayers.MASK_OBSTACLES)
	# South divider: z in [2.3, 11.0] => center 6.65, size 8.7
	_add_static_box(region, "DividerSouth", Vector3(0.0, 1.5, 6.65), Vector3(2.0, 3.0, 8.7), CollisionLayers.MASK_OBSTACLES)

	var nav := WorldNavigation.new()
	nav.name = "WorldNavigation"
	nav.set_map_bounds(Rect2(-17.0, -11.0, 34.0, 22.0))
	region.add_child(nav)

	return {
		"region": region,
		"nav": nav,
		"checkpoint_west": Vector3(-10.0, 0.0, 0.0),
		"checkpoint_east": Vector3(10.0, 0.0, 0.0),
	}


func test_01_building_definitions_and_invalid_definition_guards() -> void:
	assert_not_null(SHELTER_DEF, "shelter_basic.tres must load")
	assert_not_null(DEPOT_DEF, "storage_depot.tres must load")
	assert_true(SHELTER_DEF.is_valid(), "shelter_basic.tres must be valid")
	assert_true(DEPOT_DEF.is_valid(), "storage_depot.tres must be valid")

	assert_eq(SHELTER_DEF.definition_id, &"shelter_basic")
	assert_vec2_near(SHELTER_DEF.footprint_size, Vector2(4.0, 4.0), 0.001)
	assert_eq(int(SHELTER_DEF.costs.get("wood", -1)), 12)
	assert_eq(int(SHELTER_DEF.costs.get("stone", -1)), 6)
	assert_near(SHELTER_DEF.build_work_required_sec, 30.0, 0.001)
	assert_eq(SHELTER_DEF.max_builders, 2)
	assert_true(SHELTER_DEF.storage_capacities.is_empty())

	assert_eq(DEPOT_DEF.definition_id, &"storage_depot")
	assert_vec2_near(DEPOT_DEF.footprint_size, Vector2(5.0, 4.0), 0.001)
	assert_eq(int(DEPOT_DEF.costs.get("wood", -1)), 18)
	assert_eq(int(DEPOT_DEF.costs.get("stone", -1)), 10)
	assert_near(DEPOT_DEF.build_work_required_sec, 45.0, 0.001)
	assert_eq(DEPOT_DEF.max_builders, 2)
	assert_eq(int(DEPOT_DEF.storage_capacities.get("wood", -1)), 50)
	assert_eq(int(DEPOT_DEF.storage_capacities.get("stone", -1)), 50)
	assert_eq(int(DEPOT_DEF.storage_capacities.get("food", -1)), 30)

	var bad_empty := BuildingDefinition.new()
	assert_false(bad_empty.is_valid(), "Empty definition_id must fail validation")

	var bad_size := SHELTER_DEF.duplicate() as BuildingDefinition
	bad_size.footprint_size = Vector2(0.0, 4.0)
	assert_false(bad_size.is_valid(), "Zero footprint dimension must fail validation")

	var bad_nan := SHELTER_DEF.duplicate() as BuildingDefinition
	bad_nan.footprint_size = Vector2(NAN, 4.0)
	assert_false(bad_nan.is_valid(), "NaN footprint dimension must fail validation")

	var bad_cost := SHELTER_DEF.duplicate() as BuildingDefinition
	bad_cost.costs = {"wood": -3}
	assert_false(bad_cost.is_valid(), "Negative cost must fail validation")


func test_02_test_map_gridless_valid_placement_and_dynamic_camp_zone_d6() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav), "WorldNavigation must become ready")
	await wait_physics_frames(2)

	var camp_zone: CampStorageZone = test_map.get_camp_storage_zone()
	assert_not_null(camp_zone, "TestMap must expose CampStorageZone")

	var validator := PlacementValidator.new()
	var ctx := PlacementValidator.ValidationContext.from_region(
		test_map,
		nav,
		camp_zone
	)

	# 1. Gridless arbitrary fractional position on flat open terrain succeeds.
	var free_pos := Vector3(0.37, 0.0, -13.19)
	var hover_free := validator.validate_hover(SHELTER_DEF, free_pos, ctx)
	assert_true(hover_free.valid, "Free gridless flat ground must pass hover: %s" % hover_free.reason_text)
	assert_false(hover_free.used_candidate_navmesh, "Hover check must not run candidate bake")
	assert_vec3_near(hover_free.resolved_position, free_pos, 0.02)

	var poly_before: int = nav.navigation_mesh.get_polygon_count()
	var confirm_free := validator.validate_confirm(DEPOT_DEF, free_pos, ctx)
	assert_true(confirm_free.valid, "Free gridless flat ground must pass depot confirm: %s" % confirm_free.reason_text)
	assert_true(confirm_free.used_candidate_navmesh, "Confirm check must run isolated candidate NavMesh")
	assert_eq(nav.navigation_mesh.get_polygon_count(), poly_before, "Active WorldNavigation polygon count must remain untouched")

	# 2. Works equally without any CampStorageZone configured.
	var no_camp_ctx := PlacementValidator.ValidationContext.from_region(
		test_map,
		nav,
		null
	)
	var confirm_no_camp := validator.validate_confirm(SHELTER_DEF, free_pos, no_camp_ctx)
	assert_true(confirm_no_camp.valid, "Placement must not require a CampStorageZone to exist")

	# 3. CampStorageZone centered at (0, 0, 0.5) with half_extents (2.8, 2.2) -> rejects full & partial overlap.
	var camp_anchor: Vector3 = camp_zone.get_anchor_position()
	var camp_full := validator.validate_hover(SHELTER_DEF, camp_anchor, ctx)
	assert_false(camp_full.valid, "Center of CampStorageZone must be rejected")
	assert_eq(camp_full.reason_code, PlacementValidator.REASON_CAMP_RESERVED)
	assert_string_contains(camp_full.reason_text.to_lower(), "área reservada")

	# Partial corner overlap: 4x4 (half 2.0) placed at x = 2.8 + 1.5 = 4.3 overlaps camp x <= 2.8.
	var camp_partial := validator.validate_hover(SHELTER_DEF, Vector3(camp_anchor.x + 4.3, 0.0, camp_anchor.z), ctx)
	assert_false(camp_partial.valid, "Partial overlap with CampStorageZone must be rejected")
	assert_eq(camp_partial.reason_code, PlacementValidator.REASON_CAMP_RESERVED)

	# Placing cleanly outside CampStorageZone succeeds (x = 2.8 + 2.0 + 0.5 = 5.3, away from trees/rocks).
	var camp_outside := validator.validate_hover(SHELTER_DEF, Vector3(camp_anchor.x, 0.0, camp_anchor.z + 5.2), ctx)
	assert_true(camp_outside.valid, "Position outside CampStorageZone bounds must succeed: %s" % camp_outside.reason_text)

	# 4. Dynamic CampStorageZone change: enlarging zone_bounds_half_extents expands rejected footprint immediately.
	camp_zone.zone_bounds_half_extents = Vector2(5.0, 5.5)
	var camp_resized := validator.validate_hover(SHELTER_DEF, Vector3(camp_anchor.x, 0.0, camp_anchor.z + 5.2), ctx)
	assert_false(camp_resized.valid, "Resized CampStorageZone must dynamically reject newly covered area")
	assert_eq(camp_resized.reason_code, PlacementValidator.REASON_CAMP_RESERVED)


func test_03_terrain_bounds_obstacles_resources_piles_and_units_rejections() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav), "WorldNavigation must become ready")
	await wait_physics_frames(2)

	var camp_zone: CampStorageZone = test_map.get_camp_storage_zone()
	var piles_root: Node3D = test_map.get_camp_piles_root()
	var time_provider := SimulatedWorldTimeProvider.new(0.0)
	var pile_defs: Dictionary = {
		&"wood": WOOD_DEF.duplicate(),
		&"stone": STONE_DEF.duplicate(),
	}
	var pile_manager := GroundPileManager.new(pile_defs, camp_zone, piles_root, time_provider)
	var validator := PlacementValidator.new()

	var ctx := PlacementValidator.ValidationContext.from_region(
		test_map,
		nav,
		camp_zone,
		pile_manager
	)

	# 1. Out of region bounds & off terrain void.
	var out_bounds := validator.validate_hover(SHELTER_DEF, Vector3(60.0, 0.0, 0.0), ctx)
	assert_false(out_bounds.valid)
	assert_eq(out_bounds.reason_code, PlacementValidator.REASON_OUT_OF_BOUNDS)

	# 2. Steep ramp around (9.05, 0.81, -14.0) on TestMap.
	var steep_ramp := validator.validate_hover(SHELTER_DEF, Vector3(9.05, 0.81, -14.0), ctx)
	assert_false(steep_ramp.valid, "Steep ramp must fail slope/height terrain validation")
	assert_eq(steep_ramp.reason_code, PlacementValidator.REASON_INVALID_TERRAIN)

	# 3. Plateau drop-off edge near (13.0, 2.0, -14.0) straddles y=2 and y=0.
	var cliff_edge := validator.validate_hover(SHELTER_DEF, Vector3(13.0, 2.0, -14.0), ctx)
	assert_false(cliff_edge.valid, "Plateau edge with elevation step must be rejected")
	assert_eq(cliff_edge.reason_code, PlacementValidator.REASON_INVALID_TERRAIN)

	# 4. Obstacle overlap (WallWest at (-8, 1.25, -6)).
	var wall_overlap := validator.validate_hover(SHELTER_DEF, Vector3(-8.0, 0.0, -6.0), ctx)
	assert_false(wall_overlap.valid, "Overlap with WallWest must be rejected")
	assert_eq(wall_overlap.reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP)

	# 5. Natural resource overlap (Tree, Rock, Bush) from TestMap.
	var checked_sources: int = 0
	for src: ResourceSource in test_map.get_resource_sources():
		if src == null or not is_instance_valid(src):
			continue
		var res_hit := validator.validate_hover(SHELTER_DEF, src.global_position, ctx)
		assert_false(res_hit.valid, "Overlap with resource source %s must be rejected" % src.name)
		assert_eq(res_hit.reason_code, PlacementValidator.REASON_RESOURCE_OVERLAP)
		checked_sources += 1
	assert_gt(float(checked_sources), 2.0, "TestMap must provide multiple resource sources to test")

	# 6. Physical GroundResourcePile overlap:
	#    Create a standalone GroundResourcePile outside CampStorageZone inside region test_map.
	var free_spot := Vector3(0.37, 0.0, -13.19)
	var standalone_pile := GroundResourcePile.new()
	test_map.add_child(standalone_pile)
	standalone_pile.configure_initial(901, WOOD_DEF, 5, free_spot)
	await wait_process_frames(1)

	var ctx_with_pile := PlacementValidator.ValidationContext.from_region(
		test_map,
		nav,
		camp_zone,
		pile_manager
	)
	var pile_hit := validator.validate_hover(SHELTER_DEF, free_spot, ctx_with_pile)
	assert_false(pile_hit.valid, "Standalone ground pile inside footprint must be rejected")
	assert_eq(pile_hit.reason_code, PlacementValidator.REASON_PILE_OVERLAP)
	standalone_pile.queue_free()
	await wait_process_frames(1)

	# Also test a GroundPileManager camp pile overlap (even when zone check disabled in ctx).
	var camp_pile: GroundResourcePile = pile_manager.try_create_pile_at(&"stone", 6, camp_zone.get_anchor_position() + Vector3(0.0, 0.0, 0.0))
	assert_not_null(camp_pile)
	var ctx_no_zone := PlacementValidator.ValidationContext.from_region(test_map, nav, null, pile_manager)
	var managed_pile_hit := validator.validate_hover(SHELTER_DEF, camp_pile.global_position, ctx_no_zone)
	assert_false(managed_pile_hit.valid, "Managed pile must still block placement even without CampStorageZone")
	assert_eq(managed_pile_hit.reason_code, PlacementValidator.REASON_PILE_OVERLAP)

	# 7. Unit overlap (instantiate real unit scene inside region test_map at free_spot).
	var dummy_unit: Unit = UNIT_SCENE.instantiate() as Unit
	dummy_unit.position = free_spot
	test_map.add_child(dummy_unit)
	await wait_physics_frames(1)
	var ctx_with_unit := PlacementValidator.ValidationContext.from_region(
		test_map,
		nav,
		camp_zone,
		pile_manager
	)
	var unit_hit := validator.validate_hover(SHELTER_DEF, free_spot, ctx_with_unit)
	assert_false(unit_hit.valid, "Unit inside footprint must reject placement")
	assert_eq(unit_hit.reason_code, PlacementValidator.REASON_UNIT_OVERLAP)

	# 8. Unreachable / enclosed interior without accessible work perimeter (TestMap ClosedEnclosure at (-16, 0, 12)).
	var enclosed := validator.validate_hover(SHELTER_DEF, Vector3(-16.0, 0.0, 12.0), ctx)
	assert_false(enclosed.valid, "Closed enclosure interior must reject placement")
	assert_true(
		enclosed.reason_code == PlacementValidator.REASON_PERIMETER_UNREACHABLE
		or enclosed.reason_code == PlacementValidator.REASON_OBSTACLE_OVERLAP,
		"Closed enclosure must fail perimeter or obstacle check"
	)

	pile_manager.cleanup()


func test_04_isolated_candidate_navmesh_blocks_corridor_and_preserves_active_nav() -> void:
	var setup: Dictionary = _build_custom_corridor_region()
	var region: Node3D = setup["region"] as Node3D
	var nav: WorldNavigation = setup["nav"] as WorldNavigation
	var cp_west: Vector3 = setup["checkpoint_west"] as Vector3
	var cp_east: Vector3 = setup["checkpoint_east"] as Vector3

	assert_true(await _wait_for_navigation_ready(nav), "Custom corridor navigation must become ready")
	await wait_physics_frames(2)

	var pre_path: WorldNavigation.PathResult = nav.find_path(cp_west, cp_east)
	assert_true(pre_path.is_ok() and pre_path.reachable, "West-to-East corridor must initially be traversable")

	var validator := PlacementValidator.new()
	var ctx := PlacementValidator.ValidationContext.from_region(
		region,
		nav,
		null,
		null,
		[],
		[],
		[cp_west, cp_east]
	)

	# Place 4x4 shelter centered at x=0, z=0 inside the 4.6m corridor -> leaves 0.3m per side < 0.5m agent radius!
	# Terrain and obstacles at (0,0,0) only hit the corridor floor unless the 2m divider at x=0 overlaps!
	#Wait: DividerNorth starts at z=-2.3 and DividerSouth starts at z=+2.3, both x in [-1, 1];
	# So shift candidate to (2.5, 0.0, 0.0) or widen corridor mouth? Wait: at (0,0,0), 4x4 spans z in [-2, 2], x in [-2, 2]!
	# Wait: x in [-2, 2] overlaps DividerNorth (z=-2.3, still 0.3m gap!) -> zero obstacle overlap at z in [-2, 2]!
	var plug_pos := Vector3(0.0, 0.0, 0.0)
	var reject_res := validator.validate_confirm(SHELTER_DEF, plug_pos, ctx)
	assert_false(reject_res.valid, "Placing 4x4 shelter in 4.6m corridor must be rejected on candidate NavMesh")
	assert_true(reject_res.used_candidate_navmesh, "Confirmation check must use isolated candidate NavMesh")
	assert_eq(reject_res.reason_code, PlacementValidator.REASON_CORRIDOR_BLOCKED)

	# Active WorldNavigation must remain completely untouched and still connect cp_west -> cp_east.
	var post_reject_path: WorldNavigation.PathResult = nav.find_path(cp_west, cp_east)
	assert_true(post_reject_path.is_ok() and post_reject_path.reachable, "Rejected candidate must not modify active WorldNavigation")

	# Valid open position in West room keeps corridor open and confirms cleanly.
	var open_west_pos := Vector3(-10.0, 0.0, 5.5)
	var accept_res := validator.validate_confirm(DEPOT_DEF, open_west_pos, ctx)
	assert_true(accept_res.valid, "Open position in West room must pass candidate NavMesh check: %s" % accept_res.reason_text)
	assert_true(accept_res.used_candidate_navmesh)

	# Verify repeated candidate sessions don't break active navigation.
	var post_accept_path: WorldNavigation.PathResult = nav.find_path(cp_west, cp_east)
	assert_true(post_accept_path.is_ok() and post_accept_path.reachable, "Active WorldNavigation must remain intact after valid confirm")


func test_05_safe_invalid_inputs_unready_nav_and_zero_economy_side_effects() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav), "WorldNavigation must become ready")
	await wait_physics_frames(2)

	var camp_zone: CampStorageZone = test_map.get_camp_storage_zone()
	var piles_root: Node3D = test_map.get_camp_piles_root()
	var time_provider := SimulatedWorldTimeProvider.new(0.0)
	var defs: Dictionary = {
		&"food": ResourceDefinition.new(),
		&"wood": WOOD_DEF.duplicate(),
		&"stone": STONE_DEF.duplicate(),
	}
	defs[&"food"].resource_id = &"food"
	defs[&"food"].display_name = "Alimentos"
	defs[&"food"].unit_weight = 1
	var pile_manager := GroundPileManager.new(defs, camp_zone, piles_root, time_provider)
	var inventory := SettlementInventory.new(pile_manager)

	var pile: GroundResourcePile = pile_manager.try_create_pile_at(&"wood", 15, camp_zone.get_anchor_position())
	assert_not_null(pile)
	var reserved_ok: bool = inventory.reserve_batch(&"existing_order", {&"wood": 5})
	assert_true(reserved_ok)

	var validator := PlacementValidator.new()
	var ctx := PlacementValidator.ValidationContext.from_region(test_map, nav, camp_zone, pile_manager)

	# NaN / INF / null checks.
	var r_null := validator.validate_hover(null, Vector3(-11.0, 0.0, 4.0), ctx)
	assert_false(r_null.valid)
	assert_eq(r_null.reason_code, PlacementValidator.REASON_INVALID_INPUT)

	var r_nan := validator.validate_confirm(SHELTER_DEF, Vector3(NAN, 0.0, 4.0), ctx)
	assert_false(r_nan.valid)
	assert_eq(r_nan.reason_code, PlacementValidator.REASON_INVALID_INPUT)

	var r_inf := validator.validate_hover(SHELTER_DEF, Vector3(-11.0, INF, 4.0), ctx)
	assert_false(r_inf.valid)
	assert_eq(r_inf.reason_code, PlacementValidator.REASON_INVALID_INPUT)

	# Unready navigation fails cleanly.
	var unready_ctx := PlacementValidator.ValidationContext.from_region(test_map, null, camp_zone, pile_manager)
	var r_unready := validator.validate_hover(SHELTER_DEF, Vector3(-11.0, 0.0, 4.0), unready_ctx)
	assert_false(r_unready.valid)
	assert_eq(r_unready.reason_code, PlacementValidator.REASON_NAV_NOT_READY)

	# Confirm placement with DEPOT_DEF (costs 18 wood, 10 stone): must NOT deduct or reserve inventory!
	var confirm_ok := validator.validate_confirm(DEPOT_DEF, Vector3(0.37, 0.0, -13.19), ctx)
	assert_true(confirm_ok.valid, "Valid depot confirm must succeed: %s" % confirm_ok.reason_text)
	assert_eq(inventory.get_physical_amount(&"wood"), 15, "T3.2 confirm must not touch physical stock")
	assert_eq(inventory.get_available_amount(&"wood"), 10, "T3.2 confirm must not create or alter reservations")
	assert_eq(inventory.get_reserved_amount(&"wood"), 5, "T3.2 confirm must keep existing reservations untouched")
	assert_eq(pile_manager.get_piles().size(), 1, "T3.2 confirm must not create or remove piles")

	pile_manager.cleanup()


func test_06_region_isolation_two_regions_and_async_confirm_parity() -> void:
	# Region A: TestMap with CampStorageZone inside SubViewport A (own_world_3d)
	var vp_a := SubViewport.new()
	vp_a.own_world_3d = true
	vp_a.size = Vector2i(256, 256)
	add_test_child(vp_a)
	var map_a: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	vp_a.add_child(map_a)
	var nav_a: WorldNavigation = map_a.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav_a), "Region A navigation must become ready")

	# Region B: flat region WITHOUT CampStorageZone inside SubViewport B (own_world_3d),
	# carrying its own Unit & GroundResourcePile sitting at (0.37, 0.0, -13.19) — the exact coordinate free in Region A!
	var vp_b := SubViewport.new()
	vp_b.own_world_3d = true
	vp_b.size = Vector2i(256, 256)
	add_test_child(vp_b)
	var region_b := Node3D.new()
	region_b.name = "RegionB"
	vp_b.add_child(region_b)
	_add_static_box(
		region_b,
		"FloorB",
		Vector3(0.0, -0.5, 0.0),
		Vector3(48.0, 1.0, 48.0),
		CollisionLayers.MASK_TERRAIN
	)
	var nav_b := WorldNavigation.new()
	nav_b.set_map_bounds(Rect2(-24.0, -24.0, 48.0, 48.0))
	region_b.add_child(nav_b)
	assert_true(await _wait_for_navigation_ready(nav_b), "Region B navigation must become ready")

	var foreign_unit: Unit = UNIT_SCENE.instantiate() as Unit
	foreign_unit.position = Vector3(0.37, 0.0, -13.19)
	region_b.add_child(foreign_unit)

	var foreign_pile := GroundResourcePile.new()
	region_b.add_child(foreign_pile)
	foreign_pile.configure_initial(999, WOOD_DEF, 8, Vector3(0.37, 0.0, -13.19))

	await wait_physics_frames(2)

	var validator := PlacementValidator.new()
	var ctx_a := PlacementValidator.ValidationContext.from_region(map_a, nav_a, map_a.get_camp_storage_zone())
	var ctx_b := PlacementValidator.ValidationContext.from_region(region_b, nav_b, null)

	# Region A context must NOT pick up Region B's unit/pile at (0.37, 0.0, -13.19).
	assert_false(ctx_a.units.has(foreign_unit), "Region A context must exclude units belonging to Region B")
	assert_false(ctx_a.extra_piles.has(foreign_pile), "Region A context must exclude piles belonging to Region B")
	var hover_a := validator.validate_hover(SHELTER_DEF, Vector3(0.37, 0.0, -13.19), ctx_a)
	assert_true(hover_a.valid, "Region A must stay valid despite objects at same coords in Region B: %s" % hover_a.reason_text)

	# Region B context MUST see its own objects (so (0.37, 0, -13.19) rejects in B), while (0.0, 0.0, 0.5) — which is CampStorageZone in A — is VALID in B!
	var blocked_b := validator.validate_hover(SHELTER_DEF, Vector3(0.37, 0.0, -13.19), ctx_b)
	assert_false(blocked_b.valid, "Region B must still detect its own pile/unit")
	var free_b := validator.validate_hover(SHELTER_DEF, Vector3(0.0, 0.0, 0.5), ctx_b)
	assert_true(free_b.valid, "Region B without CampStorageZone must stay valid at A's camp coordinate: %s" % free_b.reason_text)

	# Async confirmation parity on Region A using cached static geometry.
	var async_results: Array[PlacementValidator.ValidationResult] = []
	validator.validate_confirm_async(
		DEPOT_DEF,
		Vector3(0.37, 0.0, -13.19),
		ctx_a,
		func(res: PlacementValidator.ValidationResult) -> void:
			async_results.append(res)
	)
	var wait_f: int = 0
	while async_results.is_empty() and wait_f < 120:
		await wait_process_frames(1)
		wait_f += 1
	assert_eq(async_results.size(), 1, "Async confirm callback must fire once")
	if async_results.size() == 1:
		var ares: PlacementValidator.ValidationResult = async_results[0]
		assert_true(ares.valid, "Async confirm on valid spot must match sync validity: %s" % ares.reason_text)
		assert_true(ares.used_candidate_navmesh)


func test_07_async_confirm_revalidation_scenarios_a_b_c_e() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav), "WorldNavigation must become ready")
	await wait_physics_frames(2)

	var camp_zone: CampStorageZone = test_map.get_camp_storage_zone()
	var worker: Unit = UNIT_SCENE.instantiate() as Unit
	worker.position = Vector3(-14.0, 0.0, 4.0)
	test_map.add_child(worker)
	await wait_physics_frames(2)

	var validator := PlacementValidator.new()
	var ctx := PlacementValidator.ValidationContext.from_region(test_map, nav, camp_zone)
	var valid_pos := Vector3(0.37, 0.0, -13.19)

	# Scenario C: stable world state confirms cleanly via async validator contract.
	var res_c: Array[PlacementValidator.ValidationResult] = []
	var tok_c: WorldNavigation.AsyncBakeToken = validator.validate_confirm_async(
		DEPOT_DEF,
		valid_pos,
		ctx,
		func(r: PlacementValidator.ValidationResult) -> void:
			res_c.append(r)
	)
	assert_not_null(tok_c)
	var wait_f: int = 0
	while res_c.is_empty() and wait_f < 120:
		await wait_process_frames(1)
		wait_f += 1
	assert_eq(res_c.size(), 1, "Scenario C callback must fire once")
	assert_true(res_c[0].valid, "Scenario C stable async confirm must succeed: %s" % res_c[0].reason_text)
	assert_true(res_c[0].used_candidate_navmesh)

	# Scenario A: worker enters footprint deterministically while async bake is in flight.
	var res_a: Array[PlacementValidator.ValidationResult] = []
	var tok_a: WorldNavigation.AsyncBakeToken = validator.validate_confirm_async(
		SHELTER_DEF,
		valid_pos,
		ctx,
		func(r: PlacementValidator.ValidationResult) -> void:
			res_a.append(r)
	)
	assert_not_null(tok_a)
	assert_true(res_a.is_empty(), "Async callback must not complete synchronously before next-line mutation")
	worker.global_position = valid_pos

	wait_f = 0
	while res_a.is_empty() and wait_f < 120:
		await wait_process_frames(1)
		wait_f += 1
	assert_eq(res_a.size(), 1, "Scenario A callback must fire once")
	assert_false(res_a[0].valid, "Scenario A must reject when worker entered footprint mid-bake")
	assert_eq(res_a[0].reason_code, PlacementValidator.REASON_UNIT_OVERLAP)
	worker.global_position = Vector3(-14.0, 0.0, 4.0)
	await wait_physics_frames(2)

	# Scenario B: new physical pile spawns inside footprint while async bake is in flight.
	var res_b: Array[PlacementValidator.ValidationResult] = []
	var tok_b: WorldNavigation.AsyncBakeToken = validator.validate_confirm_async(
		SHELTER_DEF,
		valid_pos,
		ctx,
		func(r: PlacementValidator.ValidationResult) -> void:
			res_b.append(r)
	)
	assert_not_null(tok_b)
	assert_true(res_b.is_empty(), "Async callback must still be pending before pile spawn")
	var spawned_pile := GroundResourcePile.new()
	test_map.add_child(spawned_pile)
	spawned_pile.configure_initial(980, WOOD_DEF, 6, valid_pos)

	wait_f = 0
	while res_b.is_empty() and wait_f < 120:
		await wait_process_frames(1)
		wait_f += 1
	assert_eq(res_b.size(), 1, "Scenario B callback must fire once")
	assert_false(res_b[0].valid, "Scenario B must reject when pile appeared in footprint mid-bake")
	assert_eq(res_b[0].reason_code, PlacementValidator.REASON_PILE_OVERLAP)
	spawned_pile.queue_free()
	await wait_process_frames(2)

	# Scenario E1: static geometry cache invalidated mid-flight while nav reports ready.
	var res_e1: Array[PlacementValidator.ValidationResult] = []
	var tok_e1: WorldNavigation.AsyncBakeToken = validator.validate_confirm_async(
		SHELTER_DEF,
		valid_pos,
		ctx,
		func(r: PlacementValidator.ValidationResult) -> void:
			res_e1.append(r)
	)
	assert_not_null(tok_e1)
	assert_true(res_e1.is_empty())
	nav.invalidate_static_geometry_cache()

	wait_f = 0
	while res_e1.is_empty() and wait_f < 120:
		await wait_process_frames(1)
		wait_f += 1
	assert_eq(res_e1.size(), 1, "Scenario E1 callback must fire once")
	assert_false(res_e1[0].valid, "Scenario E1 must reject stale candidate session when static cache invalidated")
	assert_eq(res_e1[0].reason_code, PlacementValidator.REASON_NAVIGATION_STALE)

	nav.request_rebake()
	assert_true(await _wait_for_navigation_ready(nav), "Navigation must recover after rebake")

	# Scenario E2: full rebake initiated mid-flight; reject even if rebake finishes quickly.
	var res_e2: Array[PlacementValidator.ValidationResult] = []
	var tok_e2: WorldNavigation.AsyncBakeToken = validator.validate_confirm_async(
		SHELTER_DEF,
		valid_pos,
		ctx,
		func(r: PlacementValidator.ValidationResult) -> void:
			res_e2.append(r)
	)
	assert_not_null(tok_e2)
	assert_true(res_e2.is_empty())
	nav.request_rebake()

	wait_f = 0
	while res_e2.is_empty() and wait_f < 120:
		await wait_process_frames(1)
		wait_f += 1
	assert_true(await _wait_for_navigation_ready(nav), "Navigation rebake must finish cleanly")
	assert_eq(res_e2.size(), 1, "Scenario E2 callback must fire once")
	assert_false(res_e2[0].valid, "Scenario E2 must reject candidate session from previous nav revision")
	assert_true(
		res_e2[0].reason_code == PlacementValidator.REASON_NAVIGATION_STALE
		or res_e2[0].reason_code == PlacementValidator.REASON_NAV_NOT_READY,
		"Scenario E2 must fail with navigation stale/not ready, got %s" % String(res_e2[0].reason_code)
	)
