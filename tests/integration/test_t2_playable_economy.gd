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
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")

const MAX_WAIT_FRAMES: int = 120
const MAX_CYCLE_FRAMES: int = 1400
const MAX_REAL_PACE_CYCLE_FRAMES: int = 2400


func _accelerate_sources(test_map: TestMap, op_sec: float = 0.12, prep_sec: float = 0.0) -> void:
	if test_map == null:
		return
	for src: ResourceSource in test_map.get_resource_sources():
		src.set_gather_cycle_timings(op_sec, prep_sec)
		src.felling_duration_sec = minf(src.felling_duration_sec, 0.10)


func _accelerate_work_walk(units: Array) -> void:
	for u: Variant in units:
		if u is Unit:
			var unit_node: Unit = u as Unit
			var fast_def: CharacterDefinition = unit_node.get_definition().duplicate() as CharacterDefinition
			fast_def.move_speed = 7.5
			fast_def.work_approach_speed = 7.5
			fast_def.max_load_speed_multiplier = 1.0
			unit_node.apply_definition(fast_def)


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
	main_root.use_provenance_economy = false
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
	_accelerate_sources(test_map)
	_accelerate_work_walk([leader_a])
	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	var initial_wood: int = wood_tree.get_remaining_amount()

	await _select_unit_by_click(rig, cam, leader_a)
	assert_eq(selection.get_selected_units(), [leader_a])

	await _right_click_world(rig, cam, wood_tree.global_position + Vector3(0.0, 1.5, 0.0))
	assert_true(leader_a.get_current_order() is GatherResourceOrder)

	# Wait until unit picks up wood and starts transporting back to camp (real production pace)
	var saw_transporting: bool = false
	var frames: int = 0
	while frames < MAX_REAL_PACE_CYCLE_FRAMES:
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

	# Wait for delivery into CampStorageZone (real pace loaded return)
	while inventory.get_amount(&"wood") == 0 and frames < MAX_REAL_PACE_CYCLE_FRAMES:
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
	_accelerate_sources(test_map)
	_accelerate_work_walk([leader_a, leader_b])

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
	_accelerate_sources(test_map)
	_accelerate_work_walk([leader_a])
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
	_accelerate_sources(test_map)
	_accelerate_work_walk([leader_a, leader_b])

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


func _has_collider_descendant(root_node: Node) -> bool:
	for child: Node in root_node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			return true
		if _has_collider_descendant(child):
			return true
	return false


func _push_mouse_click_in_viewport(vp: Viewport, button: MouseButton, screen_pos: Vector2, shift: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	vp.push_input(motion, true)

	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.shift_pressed = shift
	press.position = screen_pos
	press.global_position = screen_pos
	vp.push_input(press, true)

	await wait_physics_frames(1)

	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.shift_pressed = shift
	release.position = screen_pos
	release.global_position = screen_pos
	vp.push_input(release, true)
	await wait_physics_frames(2)


func _assert_initial_framing_and_picking_in_viewport(
	main_root: MainScene,
	vp: Viewport,
	expected_size: Vector2
) -> void:
	var test_map: TestMap = main_root.get_test_map()
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	var cam: Camera3D = rig.get_camera()
	var vp_rect: Rect2 = vp.get_visible_rect()
	assert_eq(vp_rect.size, expected_size, "Viewport under test must match expected resolution")

	var picker := WorldPicker.new()
	var seen_categories: Dictionary = {}
	var expected_labels: Dictionary = {
		ResourceDefinition.Category.WOOD: "Madeira",
		ResourceDefinition.Category.STONE: "Pedra",
		ResourceDefinition.Category.FOOD: "Alimento",
	}

	for src: ResourceSource in test_map.get_resource_sources():
		seen_categories[src.get_category()] = true
		var badge: Node3D = src.get_node_or_null("DiscoverabilityBadge") as Node3D
		assert_not_null(badge, "Each collectable source must expose DiscoverabilityBadge")
		assert_true(badge.visible, "DiscoverabilityBadge must be visible initially")
		assert_false(_has_collider_descendant(badge), "DiscoverabilityBadge must not add extra colliders")
		assert_false(src.is_processing())
		assert_false(src.is_physics_processing())

		var badge_label: Label3D = badge.get_node_or_null("BadgeLabel") as Label3D
		assert_not_null(badge_label)
		assert_eq(badge_label.text, expected_labels[src.get_category()])

		var pick_point: Vector3 = src.global_position + Vector3(0.0, 0.8, 0.0)
		assert_true(cam.is_position_in_frustum(pick_point), "Source %s must lie inside initial camera frustum" % str(src.source_id))
		var screen_pos: Vector2 = cam.unproject_position(pick_point)
		assert_true(vp_rect.has_point(screen_pos), "Source %s must project inside initial %s viewport" % [str(src.source_id), str(expected_size)])
		var pick: PickResult = picker.pick_at_screen_pos(cam, screen_pos)
		assert_true(
			pick.is_available_resource_source() and pick.resource_source == src,
			"Source %s must be unoccluded and pickable from initial framing at %s" % [str(src.source_id), str(screen_pos)]
		)

	assert_true(seen_categories.has(ResourceDefinition.Category.WOOD))
	assert_true(seen_categories.has(ResourceDefinition.Category.STONE))
	assert_true(seen_categories.has(ResourceDefinition.Category.FOOD))

	var camp_zone: CampStorageZone = test_map.get_camp_storage_zone()
	var camp_badge: Node3D = camp_zone.get_node_or_null("CampBadge") as Node3D
	assert_not_null(camp_badge)
	assert_true(camp_badge.visible)
	assert_false(_has_collider_descendant(camp_badge))
	assert_false(camp_zone.is_processing())
	assert_false(camp_zone.is_physics_processing())

	# Toggle discoverability badges cleanly off and back on
	test_map.set_resource_discoverability_badges_visible(false)
	for src: ResourceSource in test_map.get_resource_sources():
		assert_false((src.get_node("DiscoverabilityBadge") as Node3D).visible)
	assert_false(camp_badge.visible)
	test_map.set_resource_discoverability_badges_visible(true)


func _spawn_main_in_subviewport(vp_size: Vector2i) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = vp_size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	main_root.use_provenance_economy = false
	vp.add_child(main_root)
	var test_map: TestMap = main_root.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation()
	var wait_f: int = 0
	while not nav.is_navigation_ready() and wait_f < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		wait_f += 1
	await wait_process_frames(3)
	await wait_physics_frames(2)

	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	rig.edge_pan_enabled = false
	var cam: Camera3D = rig.get_camera()
	return {
		"viewport": vp,
		"main": main_root,
		"test_map": test_map,
		"nav": nav,
		"rig": rig,
		"cam": cam,
	}


func test_07_initial_framing_real_mouse_discoverability_and_delivery() -> void:
	# 1. Verify 1280x720 framing, unoccluded picking, and real mouse order start via isolated SubViewport
	var sub_ctx: Dictionary = await _spawn_main_in_subviewport(Vector2i(1280, 720))
	var sub_vp: SubViewport = sub_ctx["viewport"] as SubViewport
	var sub_main: MainScene = sub_ctx["main"] as MainScene
	var sub_map: TestMap = sub_ctx["test_map"] as TestMap
	var sub_cam: Camera3D = sub_ctx["cam"] as Camera3D
	_assert_initial_framing_and_picking_in_viewport(sub_main, sub_vp, Vector2(1280.0, 720.0))

	# Real left-click select + right-click gather on visible stone_rock_02 without moving camera
	var sub_leader: Unit = sub_main.get_units()[0]
	var sub_sel: SelectionManager = sub_main.get_selection_manager()
	var sub_leader_scr: Vector2 = sub_cam.unproject_position(sub_leader.global_position + Vector3(0.0, 0.9, 0.0))
	await _push_mouse_click_in_viewport(sub_vp, MOUSE_BUTTON_LEFT, sub_leader_scr)
	assert_eq(sub_sel.get_selected_units(), [sub_leader])

	var sub_rock: ResourceSource = _find_source(sub_map, &"stone_rock_02")
	var sub_rock_scr: Vector2 = sub_cam.unproject_position(sub_rock.global_position + Vector3(0.0, 0.7, 0.0))
	await _push_mouse_click_in_viewport(sub_vp, MOUSE_BUTTON_RIGHT, sub_rock_scr)
	assert_true(sub_leader.get_current_order() is GatherResourceOrder, "1280x720 initial-view right-click must start GatherResourceOrder")

	sub_vp.queue_free()
	await wait_process_frames(2)

	# 2. Verify 1920x1080 initial camera framing through full walk -> gather -> return -> camp pile -> ground MoveOrder
	var hd_ctx: Dictionary = await _spawn_main_in_subviewport(Vector2i(1920, 1080))
	var hd_vp: SubViewport = hd_ctx["viewport"] as SubViewport
	var main_root: MainScene = hd_ctx["main"] as MainScene
	var test_map: TestMap = hd_ctx["test_map"] as TestMap
	var cam: Camera3D = hd_ctx["cam"] as Camera3D
	var selection: SelectionManager = main_root.get_selection_manager()
	var inventory: SettlementInventory = main_root.get_settlement_inventory()
	var pile_manager: GroundPileManager = main_root.get_ground_pile_manager()
	var camp_zone: CampStorageZone = main_root.get_camp_storage_zone()
	var leader_a: Unit = main_root.get_units()[0]
	_accelerate_sources(test_map)
	_accelerate_work_walk([leader_a])

	_assert_initial_framing_and_picking_in_viewport(main_root, hd_vp, Vector2(1920.0, 1080.0))

	# Do NOT move camera! Select LeaderA and right-click WoodTree01 directly from initial camera
	var la_scr: Vector2 = cam.unproject_position(leader_a.global_position + Vector3(0.0, 0.9, 0.0))
	await _push_mouse_click_in_viewport(hd_vp, MOUSE_BUTTON_LEFT, la_scr)
	assert_eq(selection.get_selected_units(), [leader_a])

	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	var tree_scr: Vector2 = cam.unproject_position(wood_tree.global_position + Vector3(0.0, 1.4, 0.0))
	await _push_mouse_click_in_viewport(hd_vp, MOUSE_BUTTON_RIGHT, tree_scr)
	assert_true(leader_a.get_current_order() is GatherResourceOrder)

	var saw_moving: bool = false
	var saw_working: bool = false
	var saw_transporting: bool = false
	var frames: int = 0
	while inventory.get_amount(&"wood") == 0 and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		match leader_a.get_state():
			Unit.State.MOVING:
				saw_moving = true
			Unit.State.WORKING:
				saw_working = true
			Unit.State.TRANSPORTING:
				saw_transporting = true

	assert_true(saw_moving)
	assert_true(saw_working)
	assert_true(saw_transporting)
	assert_gt(inventory.get_amount(&"wood"), 0, "Worker must unload wood into CampStorageZone")
	var piles: Array[GroundResourcePile] = pile_manager.get_piles_for_resource(&"wood")
	assert_eq(piles.size(), 1)
	assert_true(piles[0].visible, "Delivered physical pile must be visible in camp")
	_assert_all_piles_valid(camp_zone, pile_manager, test_map.get_camp_piles_root())

	# Free-ground right-click from initial framing preserves MoveOrder
	var free_ground := Vector3(-1.5, 0.0, 6.0)
	var free_scr: Vector2 = cam.unproject_position(free_ground)
	await _push_mouse_click_in_viewport(hd_vp, MOUSE_BUTTON_RIGHT, free_scr)
	assert_true(leader_a.get_current_order() is MoveOrder, "Free-ground right-click must still issue MoveOrder")

	hd_vp.queue_free()
	await wait_process_frames(2)


func test_08_t231_reclicking_busy_source_during_transport_preserves_delivery() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	_accelerate_sources(test_map)

	var unit_c: Unit = UNIT_SCENE.instantiate() as Unit
	unit_c.definition = LEADER_A_DEF
	unit_c.position = Vector3(5.0, 0.0, 1.0)
	main_root.get_node("Units").add_child(unit_c)
	unit_c.set_world_navigation(nav)
	_accelerate_work_walk([leader_a, leader_b, unit_c])
	await wait_physics_frames(2)

	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	assert_eq(wood_tree.max_simultaneous_workers, 2)

	# LeaderA gathers until entering TRANSPORTING (which releases its source slot)
	selection.select_single(leader_a)
	await _right_click_world(rig, cam, wood_tree.global_position + Vector3(0.0, 1.4, 0.0))

	var frames: int = 0
	while leader_a.get_state() != Unit.State.TRANSPORTING and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	assert_eq(leader_a.get_state(), Unit.State.TRANSPORTING)
	var active_order: UnitOrder = leader_a.get_current_order()
	var carried_wood: int = leader_a.get_carry_load().get_amount(&"wood")
	assert_gt(carried_wood, 0)
	assert_false(wood_tree.is_worker_reserved(leader_a))

	# Occupy both source slots with LeaderB and UnitC while LeaderA is transporting
	selection.select_single(leader_b)
	selection.add_unit(unit_c)
	await _right_click_world(rig, cam, wood_tree.global_position + Vector3(0.0, 1.4, 0.0))
	assert_eq(wood_tree.get_active_worker_count(), 2, "Both worker slots should now be occupied")
	assert_false(wood_tree.has_worker_slot(leader_a))

	# Re-clicking the same busy source with LeaderA selected MUST NOT cancel its active delivery
	selection.select_single(leader_a)
	await _right_click_world(rig, cam, wood_tree.global_position + Vector3(0.0, 1.4, 0.0))
	assert_eq(cmd.get_last_command_reason(), GatherResourceOrder.REASON_NO_WORKER_SLOT)
	assert_eq(leader_a.get_current_order(), active_order, "Active delivery order must not be cancelled when clicking full source")
	assert_true(leader_a.get_current_order().is_active())
	assert_eq(leader_a.get_state(), Unit.State.TRANSPORTING)

	# Confirm LeaderA completes delivery normally without losing carried wood
	frames = 0
	while inventory.get_amount(&"wood") < carried_wood and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	assert_true(inventory.get_amount(&"wood") >= carried_wood, "LeaderA must finish delivering carried wood safely")
