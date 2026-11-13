extends TestCase
## Integration tests for T2.4.3 natural resource states:
## - Trees stand upright until valid extraction, fell once smoothly before transport,
##   remain fallen across multiple worker trips, preserve wood conservation, and keep
##   SolidBody / InteractionArea / WorldNavigation / WorldPicker contracts intact.
## - Multiple workers sharing a tree never trigger duplicate felling animations.
## - Cancellations before vs after first extraction behave coherently.
## - Bushes progressively hide fruits and preserve green foliage when depleted.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const MAX_WAIT_FRAMES: int = 120
const MAX_CYCLE_FRAMES: int = 900


func after_each() -> void:
	for btn: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(btn):
			var ev := InputEventMouseButton.new()
			ev.button_index = btn
			ev.pressed = false
			get_viewport().push_input(ev, true)


func _accelerate_work_walk(units: Array) -> void:
	for u: Variant in units:
		if u is Unit:
			var unit_node: Unit = u as Unit
			var fast_def: CharacterDefinition = unit_node.get_definition().duplicate() as CharacterDefinition
			fast_def.move_speed = 7.5
			fast_def.work_approach_speed = 7.5
			fast_def.max_load_speed_multiplier = 1.0
			unit_node.apply_definition(fast_def)


func _spawn_main_scene() -> Dictionary:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	add_test_child(main_root)

	var test_map: TestMap = main_root.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	if nav != null:
		var frames: int = 0
		while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
			await wait_physics_frames(1)
			frames += 1

	await wait_process_frames(3)
	await wait_physics_frames(3)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var leader_a: Unit = null
	var leader_b: Unit = null
	for u: Unit in main_root.get_units():
		if u.get_character_id() == &"leader_a":
			leader_a = u
		elif u.get_character_id() == &"leader_b":
			leader_b = u

	return {
		"main": main_root,
		"test_map": test_map,
		"nav": nav,
		"rig": rig,
		"camera": rig.get_camera() if rig != null else null,
		"selection": main_root.get_selection_manager(),
		"cmd": main_root.get_command_controller(),
		"inventory": main_root.get_settlement_inventory(),
		"camp_zone": test_map.get_camp_storage_zone() if test_map != null else null,
		"pile_manager": main_root.get_ground_pile_manager(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _find_source(test_map: TestMap, source_id: StringName) -> ResourceSource:
	for src: ResourceSource in test_map.get_resource_sources():
		if src.get_source_id() == source_id:
			return src
	return null


func test_01_felling_completes_before_transport_keeps_colliders_and_picking_valid() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	_accelerate_work_walk([leader_a])

	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	assert_not_null(wood_tree)
	assert_true(wood_tree.is_standing())
	wood_tree.set_gather_cycle_timings(0.06, 0.0)
	wood_tree.felling_duration_sec = 0.15
	wood_tree.max_extract_per_operation = 10 # Fill carry capacity on 1st chop to stress wait-for-felling

	var solid: StaticBody3D = wood_tree.get_node("SolidBody") as StaticBody3D
	var solid_col: CollisionShape3D = solid.get_node("CollisionShape3D") as CollisionShape3D
	var area: Area3D = wood_tree.get_node("InteractionArea") as Area3D
	var tree_root_tf: Transform3D = wood_tree.global_transform
	var solid_tf_before: Transform3D = solid.global_transform
	var area_tf_before: Transform3D = area.global_transform
	var solid_radius_before: float = wood_tree.get_solid_radius()

	# Picking standing tree succeeds
	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state
	var picker := WorldPicker.new()
	rig.set_focus_position(Vector2(wood_tree.global_position.x, wood_tree.global_position.z))
	await wait_process_frames(1)
	var standing_screen: Vector2 = cam.unproject_position(wood_tree.global_position + Vector3(0.0, 1.4, 0.0))
	var standing_pick: PickResult = picker.pick_along_ray(space_state, cam.project_ray_origin(standing_screen), cam.project_ray_normal(standing_screen))
	assert_true(standing_pick.is_available_resource_source())
	assert_eq(standing_pick.resource_source, wood_tree)

	leader_a.global_position = Vector3(7.8, 0.0, -1.5)
	await wait_physics_frames(2)
	leader_a.issue_order(GatherResourceOrder.new(wood_tree, camp_zone, inventory))

	var saw_felling: bool = false
	var entered_transport_while_felling: bool = false
	var saw_fallen_then_transport: bool = false
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES and not saw_fallen_then_transport:
		await wait_physics_frames(1)
		frames += 1
		if wood_tree.is_felling():
			saw_felling = true
			assert_true(solid.global_transform.is_equal_approx(solid_tf_before), "SolidBody must not shift during felling")
			if leader_a.get_state() == Unit.State.TRANSPORTING:
				entered_transport_while_felling = true
		if wood_tree.is_fallen() and leader_a.get_state() == Unit.State.TRANSPORTING:
			saw_fallen_then_transport = true

	assert_true(saw_felling, "First valid wood extraction must play smooth felling state")
	assert_false(entered_transport_while_felling, "Worker must wait for felling animation before entering TRANSPORTING")
	assert_true(saw_fallen_then_transport)
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), 10, "Waiting for felling must not duplicate wood extraction")
	assert_eq(wood_tree.get_remaining_amount(), 14)

	# Colliders, root transform, navigation, and picking remain completely valid on fallen tree
	assert_true(wood_tree.global_transform.is_equal_approx(tree_root_tf))
	assert_true(solid.global_transform.is_equal_approx(solid_tf_before))
	assert_true(area.global_transform.is_equal_approx(area_tf_before))
	assert_eq(solid.collision_layer, CollisionLayers.MASK_OBSTACLES)
	assert_eq(area.collision_layer, CollisionLayers.MASK_RESOURCES)
	assert_near((solid_col.shape as CylinderShape3D).radius, 0.35, 0.001)
	assert_near(wood_tree.get_solid_radius(), solid_radius_before, 0.001)

	var fallen_screen: Vector2 = cam.unproject_position(wood_tree.global_position + Vector3(0.35, 0.35, 0.0))
	var fallen_pick: PickResult = picker.pick_along_ray(space_state, cam.project_ray_origin(fallen_screen), cam.project_ray_normal(fallen_screen))
	assert_true(fallen_pick.is_available_resource_source(), "Fallen tree with wood left must stay pickable")
	assert_eq(fallen_pick.resource_source, wood_tree)

	var corridor_path: WorldNavigation.PathResult = nav.find_path(Vector3(-8.0, 0.0, -10.0), Vector3(0.0, 0.0, 0.0))
	assert_eq(corridor_path.status, WorldNavigation.QueryStatus.OK, "Fallen tree must not affect T1 wall-gap corridor navigation")


func test_02_multi_trip_tree_stays_fallen_conserves_wood_and_depletes_to_stump() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var cmd: CommandController = ctx["cmd"] as CommandController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	_accelerate_work_walk([leader_a])

	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	wood_tree.configure(&"wood_tree_01", wood_tree.get_definition(), 14, 5, 2)
	wood_tree.set_gather_cycle_timings(0.04, 0.0)
	wood_tree.felling_duration_sec = 0.12
	camp_zone.position = Vector3(6.4, 0.0, -1.5)

	leader_a.global_position = Vector3(7.8, 0.0, -1.5)
	await wait_physics_frames(2)
	var order := GatherResourceOrder.new(wood_tree, camp_zone, inventory)
	leader_a.issue_order(order)

	var ever_felled: bool = false
	var stood_back_up: bool = false
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES and leader_a.get_state() != Unit.State.IDLE:
		await wait_physics_frames(1)
		frames += 1
		if wood_tree.is_felling() or wood_tree.is_fallen():
			ever_felled = true
		if ever_felled and wood_tree.is_standing():
			stood_back_up = true
		var accounted: int = wood_tree.get_remaining_amount() + leader_a.get_carry_load().get_amount(&"wood") + inventory.get_amount(&"wood")
		assert_eq(accounted, 14, "Wood must remain strictly conserved across felling, transport, and return trips")

	assert_true(ever_felled)
	assert_false(stood_back_up, "Once felled, tree must NEVER return to standing upright across trips")
	assert_true(order.is_succeeded())
	assert_eq(order.get_delivered_trips(), 2)
	assert_eq(inventory.get_amount(&"wood"), 14)
	assert_true(wood_tree.is_depleted())
	assert_false((wood_tree.get_node("AvailableVisual") as Node3D).visible)
	assert_true((wood_tree.get_node("DepletedVisual") as Node3D).visible, "Depleted tree must keep stump remnant visible")
	assert_false((wood_tree.get_node("DiscoverabilityBadge") as Node3D).visible)

	# Subsequent right-click on depleted stump rejects cleanly
	selection.select_single(leader_a)
	var stump_pick := PickResult.from_resource_source(wood_tree, wood_tree.global_position, Vector3.UP)
	assert_false(cmd.command_at(stump_pick))
	assert_eq(cmd.get_last_command_reason(), "resource_source_depleted")


func test_03_concurrent_workers_single_felling_and_cancel_before_vs_after_extract() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	_accelerate_work_walk([leader_a, leader_b])

	var tree_1: ResourceSource = _find_source(test_map, &"wood_tree_01")
	tree_1.set_gather_cycle_timings(0.06, 0.04)
	tree_1.max_extract_per_operation = 5
	tree_1.felling_duration_sec = 0.16
	camp_zone.position = Vector3(6.4, 0.0, -1.5)
	var initial_1: int = tree_1.get_remaining_amount()

	# A. Cancel BEFORE first extraction does NOT fell tree
	leader_a.global_position = Vector3(5.0, 0.0, -1.5)
	leader_a.issue_order(GatherResourceOrder.new(tree_1, camp_zone, inventory))
	await wait_physics_frames(5)
	leader_a.cancel_current_order()
	await wait_physics_frames(4)
	assert_true(tree_1.is_standing(), "Cancelling before first extraction must leave tree standing")
	assert_eq(tree_1.get_remaining_amount(), initial_1)

	# B. Two concurrent workers sharing tree_1 trigger felling ONCE without reversing pivot
	var pivot: Node3D = tree_1.get_node("AvailableVisual/FellingPivot") as Node3D
	leader_a.global_position = Vector3(7.9, 0.0, -2.0)
	leader_b.global_position = Vector3(7.9, 0.0, -1.0)
	await wait_physics_frames(2)
	leader_a.issue_order(GatherResourceOrder.new(tree_1, camp_zone, inventory))
	leader_b.issue_order(GatherResourceOrder.new(tree_1, camp_zone, inventory))

	var felling_transitions: int = 0
	var was_felling: bool = false
	var saw_pivot_reversed: bool = false
	var min_rot_z: float = 0.0
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES and (inventory.get_amount(&"wood") < 12 or leader_a.get_state() == Unit.State.TRANSPORTING):
		await wait_physics_frames(1)
		frames += 1
		if tree_1.is_felling() and not was_felling:
			felling_transitions += 1
		was_felling = tree_1.is_felling()
		if pivot.rotation.z < min_rot_z:
			min_rot_z = pivot.rotation.z
		elif tree_1.is_felling() and pivot.rotation.z > min_rot_z + 0.05:
			saw_pivot_reversed = true
		var total_w: int = tree_1.get_remaining_amount() + leader_a.get_carry_load().get_amount(&"wood") + leader_b.get_carry_load().get_amount(&"wood") + inventory.get_amount(&"wood")
		assert_eq(total_w, initial_1)

	leader_a.cancel_current_order()
	leader_b.cancel_current_order()
	assert_eq(felling_transitions, 1, "Two workers chopping same tree must trigger felling transition exactly once")
	assert_false(saw_pivot_reversed, "Felling animation must not restart upright on second worker chop")
	assert_true(tree_1.is_fallen())

	# C. Cancel AFTER first extraction keeps tree falling/fallen and preserves carried wood
	var tree_2: ResourceSource = _find_source(test_map, &"wood_tree_02")
	tree_2.set_gather_cycle_timings(0.08, 0.0)
	tree_2.felling_duration_sec = 0.16
	leader_a.get_carry_load().take_all()
	leader_a.global_position = Vector3(7.8, 0.0, 5.5)
	await wait_physics_frames(2)
	leader_a.issue_order(GatherResourceOrder.new(tree_2, camp_zone, inventory))
	frames = 0
	while frames < 180 and leader_a.get_carry_load().get_amount(&"wood") == 0:
		await wait_physics_frames(1)
		frames += 1
	assert_gt(leader_a.get_carry_load().get_amount(&"wood"), 0)
	var carried: int = leader_a.get_carry_load().get_amount(&"wood")
	leader_a.issue_order(MoveOrder.new(Vector3(6.0, 0.0, 5.5)))

	frames = 0
	while tree_2.is_felling() and frames < 60:
		await wait_physics_frames(1)
		frames += 1
	assert_true(tree_2.is_fallen(), "Tree must complete fall into FALLEN even if worker cancels mid-fall")
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), carried)


func test_04_bush_gather_reduces_fruits_keeps_green_bush_and_delivers_camp_piles() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var cmd: CommandController = ctx["cmd"] as CommandController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var leader_b: Unit = ctx["leader_b"] as Unit
	_accelerate_work_walk([leader_b])

	var bush: ResourceSource = _find_source(test_map, &"food_bush_02")
	assert_not_null(bush)
	bush.configure(&"food_bush_02", bush.get_definition(), 8, 2, 2)
	bush.set_gather_cycle_timings(0.04, 0.0)
	camp_zone.position = Vector3(2.5, 0.0, 5.8)
	assert_eq(bush.get_visible_fruit_count(), 6)

	leader_b.global_position = Vector3(2.0, 0.0, 6.2)
	await wait_physics_frames(2)
	leader_b.issue_order(GatherResourceOrder.new(bush, camp_zone, inventory))

	var min_seen_while_available: int = 6
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES and leader_b.get_state() != Unit.State.IDLE:
		await wait_physics_frames(1)
		frames += 1
		if bush.get_remaining_amount() > 0:
			min_seen_while_available = mini(min_seen_while_available, bush.get_visible_fruit_count())

	assert_lt(min_seen_while_available, 6, "Fruits on bush must visibly decrease during active gather")
	assert_true(bush.is_depleted())
	assert_eq(bush.get_visible_fruit_count(), 0)
	assert_false((bush.get_node("AvailableVisual") as Node3D).visible)
	assert_true((bush.get_node("DepletedVisual") as Node3D).visible, "Green bush vegetation must stay visible after harvest")
	assert_false((bush.get_node("DiscoverabilityBadge") as Node3D).visible)
	assert_eq(inventory.get_amount(&"food"), 8)
	assert_gt(pile_manager.get_piles().size(), 0)

	selection.select_single(leader_b)
	var empty_pick := PickResult.from_resource_source(bush, bush.global_position, Vector3.UP)
	assert_false(cmd.command_at(empty_pick), "Depleted bush must reject new gather orders")
	assert_eq(cmd.get_last_command_reason(), "resource_source_depleted")
