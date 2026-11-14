extends TestCase
## Integration tests for T2.1: CampStorageZone + GroundPileManager validated against
## real WorldNavigation and TestMap terrain/obstacles without modifying shared scenes.

const TEST_MAP_SCENE: PackedScene = preload("res://levels/test_map/test_map.tscn")
const WOOD_BASE: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_BASE: ResourceDefinition = preload("res://data/resources/stone.tres")
const MAX_WAIT_FRAMES: int = 120

var _managers_to_cleanup: Array[GroundPileManager] = []


func after_each() -> void:
	for manager: GroundPileManager in _managers_to_cleanup:
		if manager != null:
			manager.cleanup()
	_managers_to_cleanup.clear()


func _wait_for_navigation_ready(nav: WorldNavigation) -> bool:
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	return nav.is_navigation_ready()


func test_01_camp_piles_reject_off_navmesh_and_unreachable_enclosure_positions() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_not_null(nav, "TestMap must expose WorldNavigation")
	if nav == null:
		return

	var ready_ok: bool = await _wait_for_navigation_ready(nav)
	assert_true(ready_ok, "WorldNavigation must become ready before camp validation")

	# Anchor camp zone on flat walkable ground in TestMap (0, 0, 2) with wide bounds
	# reaching into the closed enclosure at (-16, 0, 12) so reachability is genuinely tested.
	var zone := CampStorageZone.new()
	zone.zone_id = &"camp_nav_test"
	zone.position = Vector3(-4.0, 0.0, 4.0)
	zone.zone_bounds_half_extents = Vector2(20.0, 20.0)
	zone.slot_spacing = 1.5
	zone.max_nav_snap_distance = 0.65
	zone.set_world_navigation(nav)
	test_map.add_child(zone)

	var piles_root := Node3D.new()
	piles_root.name = "TestPilesRoot"
	test_map.add_child(piles_root)

	var time_provider := SimulatedWorldTimeProvider.new(0.0)
	var defs: Dictionary = {
		&"wood": WOOD_BASE.duplicate(),
		&"stone": STONE_BASE.duplicate(),
	}
	var manager := GroundPileManager.new(defs, zone, piles_root, time_provider)
	_managers_to_cleanup.append(manager)

	# 1. Valid walkable spot inside bounds near anchor
	var valid_pile: GroundResourcePile = manager.try_create_pile_at(
		&"wood", 4, Vector3(-2.0, 0.0, 4.0)
	)
	assert_not_null(valid_pile, "Walkable spot reachable from anchor must accept pile")

	# 2. Closed enclosure interior at (-16, 0, 12) is on terrain but unreachable from (-4, 0, 4)
	var blocked_enclosure: GroundResourcePile = manager.try_create_pile_at(
		&"stone", 3, Vector3(-16.0, 0.0, 12.0)
	)
	assert_null(blocked_enclosure, "Unreachable closed enclosure must reject pile placement")

	# 3. Position well outside the 64x64 navigable terrain (beyond map edge)
	zone.zone_bounds_half_extents = Vector2(50.0, 50.0)
	var off_navmesh: GroundResourcePile = manager.try_create_pile_at(
		&"stone", 3, Vector3(42.0, 0.0, 42.0)
	)
	assert_null(off_navmesh, "Off-navmesh position outside terrain must be rejected")

	# 4. Automatic deterministic batch placement snaps safely onto navmesh
	assert_true(manager.deposit(&"stone", 5), "Batch deposit must find valid walkable camp slots")
	assert_eq(manager.get_amount(&"wood"), 4)
	assert_eq(manager.get_amount(&"stone"), 5)
	assert_eq(manager.get_piles().size(), 2)
