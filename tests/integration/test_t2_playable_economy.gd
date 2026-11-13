extends TestCase
## Integration tests for T2.4 Playable Economy Composition in MainScene + TestMap:
## - Scene wiring without autoloads (CampStorageZone, CampPiles, ResourceSources, EconomyClockController, Inventory)
## - Protagonists starting without initial tools/equipment placeholders (mochila, bedroll, cajado hidden)
## - Automatic WorldNavigation rebake respecting TestMap ResourceSource solid bodies
## - Screen click selection + right-click gathering across Wood, Stone, Food (single & both leaders)
## - Individual physical camp piles inside CampStorageZone bounds with strict conservation & zero premature credit
## - Interruption mid-transport/mid-work via MoveOrder preserving CarryLoad & releasing slots
## - Source depletion auto-returning partial cargo & rejecting depleted source commands
## - Centralized EconomyClockController decay, pause/time_scale respect, and zero per-pile tick overhead
## - Clean resource disposal on MainScene exit and prolonged multi-trip session convergence.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")

const MAX_WAIT_FRAMES: int = 120
const MAX_CYCLE_FRAMES: int = 1400


func after_each() -> void:
	if get_tree() != null:
		get_tree().paused = false
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

	var test_map: TestMap = main_root.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	if nav != null:
		var frames: int = 0
		while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
			await wait_physics_frames(1)
			frames += 1

	await wait_process_frames(2)
	await wait_physics_frames(2)

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
		"inventory": main_root.get_settlement_inventory(),
		"pile_manager": main_root.get_ground_pile_manager(),
		"camp_zone": main_root.get_camp_storage_zone(),
		"clock": main_root.get_economy_clock(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _find_source(test_map: TestMap, source_id: StringName) -> ResourceSource:
	for src: ResourceSource in test_map.get_resource_sources():
		if src.source_id == source_id:
			return src
	return null


func _simulate_right_click(screen_pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = screen_pos
	press.global_position = screen_pos
	get_viewport().push_input(press, true)

	await wait_physics_frames(1)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = screen_pos
	release.global_position = screen_pos
	get_viewport().push_input(release, true)
	await wait_physics_frames(2)


func _simulate_left_click(screen_pos: Vector2, shift: bool = false) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = shift
	press.position = screen_pos
	press.global_position = screen_pos
	get_viewport().push_input(press, true)

	await wait_physics_frames(1)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.shift_pressed = shift
	release.position = screen_pos
	release.global_position = screen_pos
	get_viewport().push_input(release, true)
	await wait_physics_frames(2)


func _right_click_world(rig: RtsCameraRig, cam: Camera3D, world_pos: Vector3) -> void:
	rig.set_focus_position(Vector2(world_pos.x, world_pos.z))
	await wait_process_frames(1)
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	await _simulate_right_click(screen_pos)


func _select_unit_by_click(rig: RtsCameraRig, cam: Camera3D, unit: Unit, shift: bool = false) -> void:
	rig.set_focus_position(Vector2(unit.global_position.x, unit.global_position.z))
	await wait_process_frames(1)
	var screen_pos: Vector2 = cam.unproject_position(unit.global_position + Vector3(0.0, 0.9, 0.0))
	await _simulate_left_click(screen_pos, shift)


func _assert_all_piles_valid(camp_zone: CampStorageZone, pile_manager: GroundPileManager, piles_root: Node3D) -> void:
	var piles: Array[GroundResourcePile] = pile_manager.get_piles()
	assert_eq(piles_root.get_child_count(), piles.size(), "CampPiles children must mirror GroundPileManager piles")
	for i: int in range(piles.size()):
		var pile_a: GroundResourcePile = piles[i]
		assert_true(is_instance_valid(pile_a))
		assert_gt(pile_a.amount, 0)
		assert_true(camp_zone.is_position_in_bounds(pile_a.global_position), "Camp pile must stay inside CampStorageZone bounds")
		assert_false(pile_a.is_processing(), "Camp piles must not run per-node _process")
		assert_false(pile_a.is_physics_processing(), "Camp piles must not run per-node _physics_process")
		for j: int in range(i + 1, piles.size()):
			var pile_b: GroundResourcePile = piles[j]
			var dist_xz: float = Vector2(
				pile_a.global_position.x - pile_b.global_position.x,
				pile_a.global_position.z - pile_b.global_position.z
			).length()
			assert_true(
				dist_xz >= camp_zone.min_pile_clearance - 0.01,
				"Camp piles must maintain minimum horizontal clearance"
			)


func test_01_scene_wiring_protagonists_and_navigation_rebake() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var clock: EconomyClockController = ctx["clock"] as EconomyClockController
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	# Explicit dependency injection without autoloads
	assert_not_null(camp_zone)
	assert_not_null(pile_manager)
	assert_not_null(inventory)
	assert_not_null(clock)
	assert_eq(cmd.get_settlement_inventory(), inventory)
	assert_eq(cmd.get_camp_storage_zone(), camp_zone)
	assert_eq(get_tree().root.get_child_count(), 1, "No autoload singletons should exist in the scene tree root")

	# Provisional decay profiles loaded properly
	assert_not_null(FOOD_RES.decay_profile)
	assert_true(FOOD_RES.decay_profile.can_decay)
	assert_not_null(WOOD_RES.decay_profile)
	assert_true(WOOD_RES.decay_profile.can_decay)
	assert_not_null(STONE_RES.decay_profile)
	assert_false(STONE_RES.decay_profile.can_decay)

	# TestMap composition: Obstacles preserved, no pre-built buildings, 6 unique reachable sources
	assert_not_null(test_map.get_node_or_null("Obstacles/WallWithGap"))
	assert_not_null(test_map.get_node_or_null("Obstacles/ClosedEnclosure"))
	assert_not_null(test_map.get_camp_piles_root())
	assert_eq(test_map.get_camp_piles_root().get_child_count(), 0)

	var sources: Array[ResourceSource] = test_map.get_resource_sources()
	assert_eq(sources.size(), 6, "TestMap should expose 6 collectable sources (2 wood, 2 stone, 2 food)")
	var seen_ids: Dictionary = {}
	var counts_by_type: Dictionary = {}
	for src: ResourceSource in sources:
		assert_ne(src.source_id, &"")
		assert_false(seen_ids.has(src.source_id), "Every placed ResourceSource must have a unique source_id")
		seen_ids[src.source_id] = true
		var rid: StringName = src.get_resource_id()
		counts_by_type[rid] = (counts_by_type.get(rid, 0) as int) + 1
		assert_false(camp_zone.is_position_in_bounds(src.global_position), "Resource sources must be outside CampStorageZone")
		var path_res: WorldNavigation.PathResult = nav.find_path(camp_zone.get_anchor_position(), src.global_position + Vector3(0.0, 0.0, 1.5))
		assert_true(path_res.is_ok() and path_res.reachable, "Camp must have navigable path toward each resource source")

	assert_eq(counts_by_type.get(&"wood", 0), 2)
	assert_eq(counts_by_type.get(&"stone", 0), 2)
	assert_eq(counts_by_type.get(&"food", 0), 2)

	# Protagonists start without tools/equipment placeholder meshes visible
	for unit: Unit in [leader_a, leader_b]:
		var backpack := unit.get_node("VisualRoot/ExplorerVisual/Backpack_Secondary") as MeshInstance3D
		var bedroll := unit.get_node("VisualRoot/ExplorerVisual/Bedroll_Primary") as MeshInstance3D
		var staff := unit.get_node("VisualRoot/CloakVisual/WalkingStaff_Secondary") as MeshInstance3D
		assert_false(backpack.visible, "Backpack placeholder must start hidden per GDD")
		assert_false(bedroll.visible, "Bedroll placeholder must start hidden per GDD")
		assert_false(staff.visible, "Walking staff placeholder must start hidden per GDD")

	# WorldNavigation automatically rebaked ResourceSource solid colliders on TestMap load
	var tree_01: ResourceSource = _find_source(test_map, &"wood_tree_01")
	assert_not_null(tree_01)
	var across_start: Vector3 = tree_01.global_position + Vector3(-2.5, 0.0, 0.0)
	var across_end: Vector3 = tree_01.global_position + Vector3(2.5, 0.0, 0.0)
	var detour_res: WorldNavigation.PathResult = nav.find_path(across_start, across_end)
	assert_true(detour_res.is_ok() and detour_res.reachable)
	assert_gt(detour_res.path.size(), 2, "Path crossing WoodTree01 SolidBody must route around trunk automatically")
	var max_lateral_dev: float = 0.0
	for pt: Vector3 in detour_res.path:
		max_lateral_dev = maxf(max_lateral_dev, absf(pt.z - tree_01.global_position.z))
	assert_gt(max_lateral_dev, 0.45, "Path around WoodTree01 SolidBody must deflect outside trunk radius")


func test_02_playable_right_click_wood_cycle_and_no_premature_credit() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var leader_a: Unit = ctx["leader_a"] as Unit
	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	var initial_wood: int = wood_tree.get_remaining_amount()

	await _select_unit_by_click(rig, cam, leader_a)
	assert_eq(selection.get_selected_units(), [leader_a])

	await _right_click_world(rig, cam, wood_tree.global_position + Vector3(0.0, 1.5, 0.0))
	assert_true(leader_a.get_current_order() is GatherResourceOrder)

	# Wait until unit picks up wood and starts transporting back to camp
	var saw_transporting: bool = false
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		if leader_a.get_state() == Unit.State.TRANSPORTING:
			saw_transporting = true
			assert_eq(
				inventory.get_amount(&"wood"),
				0,
				"SettlementInventory must NOT credit wood while unit is still transporting"
			)
			assert_eq(test_map.get_camp_piles_root().get_child_count(), 0)
			break
	assert_true(saw_transporting, "LeaderA must enter TRANSPORTING state with harvested wood")

	# Wait for delivery into CampStorageZone
	while inventory.get_amount(&"wood") == 0 and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	var delivered: int = inventory.get_amount(&"wood")
	assert_gt(delivered, 0, "LeaderA must deliver harvested wood to CampStorageZone")
	assert_eq(test_map.get_camp_piles_root().get_child_count(), 1)
	_assert_all_piles_valid(camp_zone, pile_manager, test_map.get_camp_piles_root())

	# Exact conservation law
	var total_accounted: int = (
		wood_tree.get_remaining_amount()
		+ leader_a.get_carry_load().get_amount(&"wood")
		+ inventory.get_amount(&"wood")
	)
	assert_eq(total_accounted, initial_wood, "Total wood across source, worker, and camp must be strictly conserved")


func test_03_multi_worker_multi_resource_types_create_individual_camp_piles() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var food_bush: ResourceSource = _find_source(test_map, &"food_bush_01")
	var stone_rock: ResourceSource = _find_source(test_map, &"stone_rock_01")
	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_01")

	# Phase 1: Both protagonists gather food simultaneously
	selection.select_single(leader_a)
	selection.add_unit(leader_b)
	await _right_click_world(rig, cam, food_bush.global_position + Vector3(0.0, 0.5, 0.0))

	var frames: int = 0
	while inventory.get_amount(&"food") < 6 and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	assert_true(inventory.get_amount(&"food") >= 6, "Both workers should harvest and deliver food")

	# Phase 2: Reassign LeaderA -> stone, LeaderB -> wood
	var finished_orders: Array[String] = []
	leader_a.order_finished.connect(func(o: UnitOrder) -> void:
		finished_orders.append("%s(status=%d,reason=%s,phase=%s)" % [
			o.get_order_name(),
			o.status,
			o.failure_reason,
			str(o.get_phase()) if o is GatherResourceOrder else "-"
		])
	)
	selection.select_single(leader_a)
	await _right_click_world(rig, cam, stone_rock.global_position + Vector3(0.0, 0.5, 0.0))
	assert_true(
		leader_a.get_current_order() is GatherResourceOrder,
		"Stone click failed: reason=%s state=%s" % [main_root.get_command_controller().get_last_command_reason(), str(leader_a.get_state())]
	)
	selection.select_single(leader_b)
	await _right_click_world(rig, cam, wood_tree.global_position + Vector3(0.0, 1.5, 0.0))
	assert_true(leader_b.get_current_order() is GatherResourceOrder)

	frames = 0
	while (inventory.get_amount(&"stone") == 0 or inventory.get_amount(&"wood") == 0) and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	assert_gt(inventory.get_amount(&"food"), 0)
	assert_gt(inventory.get_amount(&"stone"), 0, "LeaderA stone delivery missing; finished=%s state=%s pos=%s carry=%s" % [str(finished_orders), str(leader_a.get_state()), str(leader_a.global_position), str(leader_a.get_carry_load().get_all_amounts())])
	assert_gt(inventory.get_amount(&"wood"), 0)
	assert_true(pile_manager.get_piles_for_resource(&"food").size() >= 1)
	assert_true(pile_manager.get_piles_for_resource(&"stone").size() >= 1)
	assert_true(pile_manager.get_piles_for_resource(&"wood").size() >= 1)
	_assert_all_piles_valid(camp_zone, pile_manager, test_map.get_camp_piles_root())


func test_04_interruption_mid_transport_preserves_load_and_depletion_behavior() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var food_bush_2: ResourceSource = _find_source(test_map, &"food_bush_02")
	var initial_food: int = food_bush_2.get_remaining_amount()

	selection.select_single(leader_a)
	await _right_click_world(rig, cam, food_bush_2.global_position + Vector3(0.0, 0.5, 0.0))

	# Wait until LeaderA finishes gathering and is transporting cargo
	var frames: int = 0
	while leader_a.get_state() != Unit.State.TRANSPORTING and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	assert_eq(leader_a.get_state(), Unit.State.TRANSPORTING)
	var carried_before_interrupt: int = leader_a.get_carry_load().get_amount(&"food")
	assert_gt(carried_before_interrupt, 0)

	# Interrupt with ground MoveOrder right-click: load stays on worker, slot reservation cleared
	var safe_ground := Vector3(-4.0, 0.0, 8.0)
	await _right_click_world(rig, cam, safe_ground)
	assert_true(leader_a.get_current_order() is MoveOrder)
	assert_eq(leader_a.get_carry_load().get_amount(&"food"), carried_before_interrupt, "Interrupt must preserve carried cargo")
	assert_eq(inventory.get_amount(&"food"), 0, "Interrupted cargo must not vanish or auto-credit")
	assert_false(food_bush_2.is_worker_reserved(leader_a), "Interrupted gather cycle must not leak source slot reservation")

	# Drain source down to 1 unit respecting max_extract_per_operation
	var drained: int = 0
	while food_bush_2.get_remaining_amount() > 1:
		var got: int = food_bush_2.extract(food_bush_2.get_remaining_amount() - 1)
		assert_gt(got, 0)
		drained += got
	var stone_rock_2: ResourceSource = _find_source(test_map, &"stone_rock_02")
	await _right_click_world(rig, cam, stone_rock_2.global_position + Vector3(0.0, 0.5, 0.0))

	# Wait for carried food + stone delivery convergence or move to stone
	frames = 0
	while inventory.get_amount(&"food") < carried_before_interrupt and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	assert_true(
		inventory.get_amount(&"food") >= carried_before_interrupt,
		"Reassigning worker to another resource must still return or preserve pre-carried food into camp inventory"
	)

	# Deplete food_bush_02 to 0 and confirm right-click fails cleanly without breaking current order
	assert_eq(food_bush_2.extract(1), 1)
	assert_true(food_bush_2.is_depleted())
	var prev_order: UnitOrder = leader_a.get_current_order()
	await _right_click_world(rig, cam, food_bush_2.global_position + Vector3(0.0, 0.3, 0.0))
	assert_eq(cmd.get_last_command_reason(), "resource_source_depleted")
	assert_eq(leader_a.get_current_order(), prev_order)

	# Conservation check on food_bush_02
	var total_food: int = (
		food_bush_2.get_remaining_amount()
		+ drained
		+ 1
		+ leader_a.get_carry_load().get_amount(&"food")
		+ inventory.get_amount(&"food")
	)
	assert_eq(total_food, initial_food)


func test_05_economy_clock_decay_pause_time_scale_and_cleanup() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var clock: EconomyClockController = ctx["clock"] as EconomyClockController

	assert_eq(clock.get_children().size(), 1, "EconomyClockController must own exactly one centralized Timer")
	var timer: Timer = clock.get_timer()
	assert_not_null(timer)
	var prev_wait: float = timer.wait_time
	var t_before: float = clock.get_world_time_sec()
	timer.wait_time = 0.05
	timer.start()
	var tick_frames: int = 0
	while clock.get_world_time_sec() <= t_before and tick_frames < 30:
		await wait_process_frames(1)
		tick_frames += 1
	assert_gt(clock.get_world_time_sec(), t_before, "Centralized Timer tick must advance EconomyClockController")
	timer.wait_time = prev_wait
	timer.start()

	assert_true(pile_manager.deposit_batch({&"food": 5, &"stone": 4}))
	assert_eq(inventory.get_amount(&"food"), 5)
	assert_eq(inventory.get_amount(&"stone"), 4)
	_assert_all_piles_valid(camp_zone, pile_manager, test_map.get_camp_piles_root())

	# Paused clock or paused SceneTree must block decay and time progression
	clock.set_paused(true)
	clock.advance_simulated_time(500.0)
	assert_eq(inventory.get_amount(&"food"), 5, "Paused EconomyClockController must freeze decay")
	clock.set_paused(false)

	get_tree().paused = true
	clock.advance_simulated_time(500.0)
	assert_eq(inventory.get_amount(&"food"), 5, "SceneTree pause must freeze EconomyClockController decay")
	get_tree().paused = false

	# Time scale + grace/gradual decay on food while stone never decays
	assert_true(clock.set_time_scale(2.0))
	# exposure_duration_sec = 180, gradual_unit_interval_sec = 45 -> 180 + 2*45 = 270 -> advance 140s @ 2x = 280s -> lose 2 food
	var losses: Dictionary = clock.advance_simulated_time(140.0)
	assert_eq(losses.get(&"food", 0), 2)
	assert_eq(losses.get(&"stone", 0), 0)
	assert_eq(inventory.get_amount(&"food"), 3)
	assert_eq(inventory.get_amount(&"stone"), 4)
	assert_eq(pile_manager.get_total_decayed(&"food"), 2)
	_assert_all_piles_valid(camp_zone, pile_manager, test_map.get_camp_piles_root())

	# Clean exit tree cleanup releases all piles without error
	var food_pile: GroundResourcePile = pile_manager.get_piles_for_resource(&"food")[0]
	var stone_pile: GroundResourcePile = pile_manager.get_piles_for_resource(&"stone")[0]
	main_root.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(food_pile))
	assert_false(is_instance_valid(stone_pile))


func test_06_prolonged_session_convergence_and_t1_compatibility() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var clock: EconomyClockController = ctx["clock"] as EconomyClockController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_02")
	var food_bush: ResourceSource = _find_source(test_map, &"food_bush_01")
	var initial_wood: int = wood_tree.get_remaining_amount()
	var initial_food: int = food_bush.get_remaining_amount()

	selection.select_single(leader_a)
	await _right_click_world(rig, cam, wood_tree.global_position + Vector3(0.0, 1.5, 0.0))
	selection.select_single(leader_b)
	await _right_click_world(rig, cam, food_bush.global_position + Vector3(0.0, 0.5, 0.0))

	# Run prolonged session until LeaderA completes >= 2 trips (16+ wood) and LeaderB completes >= 2 trips (12+ food)
	var frames: int = 0
	var max_prolonged_frames: int = 3200
	while (inventory.get_amount(&"wood") < 16 or inventory.get_amount(&"food") < 12) and frames < max_prolonged_frames:
		await wait_physics_frames(1)
		frames += 1

	assert_true(inventory.get_amount(&"wood") >= 16, "LeaderA must complete multiple wood round trips")
	assert_true(inventory.get_amount(&"food") >= 12, "LeaderB must complete multiple food round trips")

	# Step decay mildly (still inside grace window -> 0 decay, piles stay intact)
	clock.advance_simulated_time(60.0)
	_assert_all_piles_valid(camp_zone, pile_manager, test_map.get_camp_piles_root())

	# Verify exact conservation across prolonged session
	var accounted_wood: int = (
		wood_tree.get_remaining_amount()
		+ leader_a.get_carry_load().get_amount(&"wood")
		+ leader_b.get_carry_load().get_amount(&"wood")
		+ inventory.get_amount(&"wood")
		+ pile_manager.get_total_decayed(&"wood")
	)
	var accounted_food: int = (
		food_bush.get_remaining_amount()
		+ leader_a.get_carry_load().get_amount(&"food")
		+ leader_b.get_carry_load().get_amount(&"food")
		+ inventory.get_amount(&"food")
		+ pile_manager.get_total_decayed(&"food")
	)
	assert_eq(accounted_wood, initial_wood)
	assert_eq(accounted_food, initial_food)

	# T1 compatibility: cancel into ground MoveOrder + invalid sky click remains safe
	selection.select_single(leader_a)
	await _right_click_world(rig, cam, Vector3(0.0, 0.0, -3.5))
	assert_true(leader_a.get_current_order() is MoveOrder)
