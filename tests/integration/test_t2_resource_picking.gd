extends TestCase
## Integration tests for T2.2: ResourceSource picking for wood/stone/food,
## wall/obstacle occlusion, zero self-occlusion by source SolidBody, unit priority
## in front of resources, depleted/invalid picks, T1 command preservation,
## and WorldNavigation obstacle baking compatibility.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const MAX_WAIT_FRAMES: int = 120


func after_each() -> void:
	_release_all_inputs()


func _release_all_inputs() -> void:
	for btn: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(btn):
			var ev := InputEventMouseButton.new()
			ev.button_index = btn
			ev.pressed = false
			get_viewport().push_input(ev, true)


func _spawn_main_scene() -> Dictionary:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	add_test_child(main_root)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
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
		"command_controller": main_root.get_command_controller(),
		"controller": main_root.get_input_controller(),
		"marker": main_root.get_destination_marker(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _simulate_right_click(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	get_viewport().push_input(motion, true)
	await wait_process_frames(1)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.position = screen_pos
	press.global_position = screen_pos
	press.pressed = true
	get_viewport().push_input(press, true)
	await wait_process_frames(1)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.position = screen_pos
	release.global_position = screen_pos
	release.pressed = false
	get_viewport().push_input(release, true)
	await wait_process_frames(2)


func test_01_pick_visible_sources_across_all_three_categories() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var controller: RtsInputController = ctx["controller"] as RtsInputController

	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	tree.position = Vector3(6.0, 0.0, 4.0)
	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	rock.position = Vector3(10.0, 0.0, 4.0)
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.position = Vector3(14.0, 0.0, 4.0)

	main_root.add_child(tree)
	main_root.add_child(rock)
	main_root.add_child(bush)
	await wait_physics_frames(3)

	var pairs: Array[Dictionary] = [
		{"src": tree, "offset": Vector3(0.0, 1.5, 0.0), "id": &"wood"},
		{"src": rock, "offset": Vector3(0.0, 0.5, 0.0), "id": &"stone"},
		{"src": bush, "offset": Vector3(0.0, 0.45, 0.0), "id": &"food"},
	]
	for entry: Dictionary in pairs:
		var src: ResourceSource = entry["src"] as ResourceSource
		var world_pt: Vector3 = src.global_position + (entry["offset"] as Vector3)
		rig.set_focus_position(Vector2(world_pt.x, world_pt.z))
		await wait_process_frames(1)
		var pick: PickResult = controller.pick_at_screen_pos(cam.unproject_position(world_pt))
		assert_true(pick.is_resource_source(), "Visible source %s must pick as RESOURCE_SOURCE" % String(src.source_id))
		assert_true(pick.is_available_resource_source())
		assert_eq(pick.resource_source, src)
		assert_eq(pick.resource_source.get_resource_id(), entry["id"] as StringName)
		assert_true(pick.position.is_finite())
		assert_true(pick.normal.is_finite() and pick.normal.length_squared() > 0.5)


func test_02_wall_occlusion_and_zero_self_occlusion_by_own_solid_body() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var cam: Camera3D = ctx["camera"] as Camera3D
	var space_state: PhysicsDirectSpaceState3D = main_root.get_world_3d().direct_space_state
	var picker := WorldPicker.new()

	# 1. Source whose own SolidBody protrudes CLOSER to ray_origin than its InteractionArea:
	# own SolidBody MUST NOT occlude its own InteractionArea.
	var custom_src := ResourceSource.new()
	custom_src.configure(&"protruding_tree", WOOD_RES, 10, 1)
	custom_src.position = Vector3(4.0, 0.0, 8.0)

	var solid := StaticBody3D.new()
	solid.name = "SolidBody"
	solid.collision_layer = CollisionLayers.MASK_OBSTACLES
	solid.collision_mask = 0
	var solid_shape := CollisionShape3D.new()
	var box_s := BoxShape3D.new()
	box_s.size = Vector3(1.2, 2.0, 1.2)
	solid_shape.shape = box_s
	solid.position = Vector3(0.0, 1.0, 0.6) # sticks 0.6m toward +Z ray origin
	solid.add_child(solid_shape)
	custom_src.add_child(solid)

	var area := Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = CollisionLayers.MASK_RESOURCES
	area.collision_mask = 0
	area.monitoring = false
	var area_shape := CollisionShape3D.new()
	var box_a := BoxShape3D.new()
	box_a.size = Vector3(1.0, 2.0, 0.6)
	area_shape.shape = box_a
	area.position = Vector3(0.0, 1.0, -0.5) # strictly behind own SolidBody along Z
	area.add_child(area_shape)
	custom_src.add_child(area)
	main_root.add_child(custom_src)

	# 2. Place another source directly behind WallWest along camera line of sight
	var cam_to_wall_xz: Vector3 = Vector3(-8.0, 0.0, -6.0) - Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	cam_to_wall_xz = cam_to_wall_xz.normalized()
	var blocked_tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	blocked_tree.position = Vector3(-8.0, 0.0, -6.0) + cam_to_wall_xz * 1.15
	main_root.add_child(blocked_tree)
	await wait_physics_frames(3)

	# Test self-occlusion ray hitting protruding SolidBody first then InteractionArea behind it
	var origin: Vector3 = Vector3(4.0, 1.0, 13.0)
	var self_pick: PickResult = picker.pick_along_ray(space_state, origin, Vector3(0.0, 0.0, -1.0))
	assert_true(self_pick.is_resource_source(), "Own SolidBody must never self-occlude InteractionArea")
	assert_eq(self_pick.resource_source, custom_src)

	# Test external wall occlusion using camera ray through WallWest onto blocked_tree
	var blocked_screen: Vector2 = cam.unproject_position(blocked_tree.global_position + Vector3(0.0, 0.8, 0.0))
	var ray_o: Vector3 = cam.project_ray_origin(blocked_screen)
	var ray_d: Vector3 = cam.project_ray_normal(blocked_screen)
	var wall_pick: PickResult = picker.pick_along_ray(space_state, ray_o, ray_d)
	assert_true(wall_pick.is_obstacle(), "External solid wall must occlude ResourceSource behind it")


func test_03_unit_priority_and_occlusion_relative_to_resource() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var cam: Camera3D = ctx["camera"] as Camera3D
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var space_state: PhysicsDirectSpaceState3D = main_root.get_world_3d().direct_space_state
	var picker := WorldPicker.new()

	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.position = Vector3(5.0, 0.0, 5.0)
	main_root.add_child(bush)

	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	rock.position = Vector3(-4.0, 0.0, 6.0)
	main_root.add_child(rock)
	await wait_physics_frames(3)

	# 1. Unit directly in front of bush along ray -> Unit wins
	var cam_dir: Vector3 = ((bush.global_position + Vector3(0.0, 0.6, 0.0)) - cam.global_position).normalized()
	var front_unit_pos: Vector3 = bush.global_position - Vector3(cam_dir.x, 0.0, cam_dir.z).normalized() * 1.4
	leader_a.global_position = front_unit_pos
	await wait_physics_frames(3)

	var unit_screen: Vector2 = cam.unproject_position(leader_a.global_position + Vector3(0.0, 0.9, 0.0))
	var front_pick: PickResult = controller.pick_at_screen_pos(unit_screen)
	assert_true(front_pick.is_unit(), "Visible unit in front of resource must keep picking priority")
	assert_eq(front_pick.unit, leader_a)
	assert_eq(selection.get_selection_count(), 0)

	# 2. Unit directly behind rock SolidBody along controlled horizontal ray -> Rock wins
	var rock_ray_origin: Vector3 = rock.global_position + Vector3(0.0, 0.5, 6.0)
	leader_a.global_position = rock.global_position + Vector3(0.0, 0.0, -1.6)
	await wait_physics_frames(3)
	var behind_pick: PickResult = picker.pick_along_ray(space_state, rock_ray_origin, Vector3(0.0, 0.0, -1.0))
	assert_true(behind_pick.is_resource_source(), "Solid resource in front must occlude unit behind it")
	assert_eq(behind_pick.resource_source, rock)


func test_04_depleted_and_available_source_command_safety_and_t1_preservation() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var marker: DestinationMarker = ctx["marker"] as DestinationMarker
	var leader_a: Unit = ctx["leader_a"] as Unit

	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	tree.position = Vector3(6.5, 0.0, 6.5)
	main_root.add_child(tree)
	await wait_physics_frames(3)

	selection.select_single(leader_a)
	marker.visible = false

	# 1. Invalid / sky rays return NONE and command_at returns false
	var picker := WorldPicker.new()
	var sky: PickResult = picker.pick_along_ray(main_root.get_world_3d().direct_space_state, cam.global_position, Vector3.UP)
	assert_true(sky.is_none())
	assert_false(cmd.command_at(sky))
	assert_false(picker.pick_along_ray(main_root.get_world_3d().direct_space_state, Vector3(NAN, 0, 0), Vector3.DOWN).is_resource_source())

	# 2. Start an active MoveOrder on LeaderA, then right-click available ResourceSource:
	# must NOT convert click to MoveOrder or alter the active MoveOrder.
	var move_goal := Vector3(-1.5, 0.0, 8.0)
	rig.set_focus_position(Vector2(move_goal.x, move_goal.z))
	await wait_process_frames(1)
	await _simulate_right_click(cam.unproject_position(move_goal))
	assert_eq(leader_a.get_state(), Unit.State.MOVING)
	var active_order: UnitOrder = leader_a.get_current_order()
	assert_true(active_order is MoveOrder)

	rig.set_focus_position(Vector2(tree.global_position.x, tree.global_position.z))
	await wait_process_frames(1)
	var tree_screen: Vector2 = cam.unproject_position(tree.global_position + Vector3(0.0, 1.5, 0.0))
	var res_pick: PickResult = controller.pick_at_screen_pos(tree_screen)
	assert_true(res_pick.is_available_resource_source())

	await _simulate_right_click(tree_screen)
	assert_eq(cmd.get_last_command_reason(), "gather_order_not_integrated")
	assert_eq(leader_a.get_current_order(), active_order, "Right-clicking resource before T2.3 must preserve active order")
	assert_eq(leader_a.get_state(), Unit.State.MOVING)

	# 3. Deplete tree, verify deterministic depleted picking & safe contextual command rejection
	tree.max_extract_per_operation = 50
	assert_eq(tree.extract(20), 20)
	var depleted_pick: PickResult = controller.pick_at_screen_pos(tree_screen)
	assert_true(depleted_pick.is_resource_source())
	assert_false(depleted_pick.is_available_resource_source())
	assert_false(cmd.command_at(depleted_pick))
	assert_eq(cmd.get_last_command_reason(), "resource_source_depleted")
	assert_eq(leader_a.get_current_order(), active_order)

	# 4. Normal ground right-click still issues MoveOrder properly
	var ground_goal := Vector3(1.0, 0.0, 5.0)
	rig.set_focus_position(Vector2(ground_goal.x, ground_goal.z))
	await wait_process_frames(1)
	await _simulate_right_click(cam.unproject_position(ground_goal))
	assert_eq(leader_a.get_state(), Unit.State.MOVING)
	assert_ne(leader_a.get_current_order(), active_order, "Ground click must still replace with MoveOrder")


func test_05_world_navigation_respects_resource_solid_bodies_when_rebaked() -> void:
	var root := Node3D.new()
	add_test_child(root)

	var ground := StaticBody3D.new()
	ground.collision_layer = CollisionLayers.MASK_TERRAIN
	ground.collision_mask = 0
	var g_shape := CollisionShape3D.new()
	var g_box := BoxShape3D.new()
	g_box.size = Vector3(24.0, 1.0, 24.0)
	g_shape.shape = g_box
	ground.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(g_shape)
	root.add_child(ground)

	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	rock.position = Vector3(0.0, 0.0, 0.0)
	root.add_child(rock)

	var nav := WorldNavigation.new()
	nav.source_root_path = ^".."
	nav.map_bounds = Rect2(-12.0, -12.0, 24.0, 24.0)
	nav.auto_bake_on_ready = true
	root.add_child(nav)

	var frames: int = 0
	while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	assert_true(nav.is_navigation_ready())

	# Rock SolidBody (MASK_OBSTACLES) has radius = 0.9 at (0, 0.5, 0).
	# NavigationMesh uses DEFAULT_AGENT_RADIUS = 0.5 and DEFAULT_CELL_SIZE = 0.25.
	# Theoretical exclusion zone radius is rock_radius (0.9) + agent_radius (0.5) = 1.4 m.
	# Any segment intersecting the horizontal circle around (0, 0) of radius rock_radius (0.9)
	# would mean the route physically cuts through the solid body of the rock.
	var route: WorldNavigation.PathResult = nav.find_path(Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0))
	assert_true(route.is_ok(), "Path query must succeed")
	assert_true(route.reachable, "Path between opposite sides of rock must be reachable")
	assert_gt(float(route.path.size()), 2.0, "Path around obstacle must have intermediate waypoints")

	var rock_center_2d := Vector2(rock.position.x, rock.position.z)
	var solid_radius: float = 0.9 # from SphereShape3D_solid in rock_source.tscn

	var min_route_dist: float = _compute_min_horizontal_distance_to_point(route.path, rock_center_2d)
	# The actual routed path must stay completely clear of the solid obstacle (>= 0.9m).
	assert_gt(min_route_dist, solid_radius, "Actual route must never penetrate rock solid radius (0.9m)")

	# Negative control: a straight line synthetic path passing through the center (-4,0,0) -> (4,0,0)
	# MUST fail the exact same geometric clearance check.
	var straight_synthetic_path := PackedVector3Array([Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)])
	var synthetic_min_dist: float = _compute_min_horizontal_distance_to_point(straight_synthetic_path, rock_center_2d)
	assert_near(synthetic_min_dist, 0.0, 0.001, "Straight synthetic path through rock center must have ~0 distance")
	assert_false(synthetic_min_dist > solid_radius, "Negative control: straight path must fail clearance check")


static func _compute_min_horizontal_distance_to_point(path: PackedVector3Array, target_2d: Vector2) -> float:
	if path.is_empty():
		return INF
	if path.size() == 1:
		return Vector2(path[0].x, path[0].z).distance_to(target_2d)

	var min_dist: float = INF
	for i: int in range(path.size() - 1):
		var a := Vector2(path[i].x, path[i].z)
		var b := Vector2(path[i + 1].x, path[i + 1].z)
		var seg_dist: float = _distance_point_to_segment_2d(target_2d, a, b)
		if seg_dist < min_dist:
			min_dist = seg_dist
	return min_dist


static func _distance_point_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	var proj: Vector2 = a + ab * t
	return p.distance_to(proj)
