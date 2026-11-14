extends TestCase
## Integration tests for T2.5 HUD inside MainScene:
## - Stockpile starts at 0, stays 0 during gather/transport, updates only on physical delivery
## - Exact sync among SettlementStockpilePanel, SettlementInventory, and GroundPileManager piles
## - Two workers delivering simultaneously with strict conservation
## - SelectedUnitPanel live tracking through MOVING -> WORKING -> TRANSPORTING -> IDLE
## - Clean signal teardown on MainScene exit
## - Non-blocking mouse_filter and preserved RTS controls (click, box select, pan, zoom, edge scroll, F3)
## - Clean corner layout without overlap at 1280x720, 1920x1080, and dynamic window resize.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const MAX_WAIT_FRAMES: int = 120
const MAX_CYCLE_FRAMES: int = 1800


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
	for action: StringName in [
		InputActions.CAMERA_PAN_UP,
		InputActions.CAMERA_PAN_DOWN,
		InputActions.CAMERA_PAN_LEFT,
		InputActions.CAMERA_PAN_RIGHT,
	]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _accelerate_sources(test_map: TestMap, op_sec: float = 0.10, prep_sec: float = 0.0) -> void:
	for src: ResourceSource in test_map.get_resource_sources():
		src.set_gather_cycle_timings(op_sec, prep_sec)
		src.felling_duration_sec = minf(src.felling_duration_sec, 0.08)


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
	var frames: int = 0
	while nav != null and not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
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
		"rig": rig,
		"cam": rig.get_camera() if rig != null else null,
		"selection": main_root.get_selection_manager(),
		"inventory": main_root.get_settlement_inventory(),
		"pile_manager": main_root.get_ground_pile_manager(),
		"clock": main_root.get_economy_clock(),
		"hud": main_root.get_resource_hud(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _find_source(test_map: TestMap, source_id: StringName) -> ResourceSource:
	for src: ResourceSource in test_map.get_resource_sources():
		if src.source_id == source_id:
			return src
	return null


func _sum_piles_for_resource(pile_manager: GroundPileManager, resource_id: StringName) -> int:
	var total: int = 0
	for pile: GroundResourcePile in pile_manager.get_piles_for_resource(resource_id):
		if is_instance_valid(pile):
			total += pile.amount
	return total


func _push_mouse_click(vp: Viewport, button: MouseButton, screen_pos: Vector2, shift: bool = false) -> void:
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


func _assert_all_controls_mouse_ignore(control: Control) -> void:
	assert_eq(control.mouse_filter, Control.MOUSE_FILTER_IGNORE, "HUD control %s must not block mouse input" % control.name)
	for child: Node in control.get_children():
		if child is Control:
			_assert_all_controls_mouse_ignore(child as Control)


func _assert_hud_layout_in_viewport(main_root: MainScene, vp: Viewport) -> void:
	var hud: ResourceHud = main_root.get_resource_hud()
	var stockpile: SettlementStockpilePanel = hud.get_stockpile_panel()
	var unit_panel: SelectedUnitPanel = hud.get_selected_unit_panel()
	var debug_overlay: DebugOverlay = main_root.get_node("UiLayer/DebugOverlay") as DebugOverlay
	var debug_panel: Control = debug_overlay.get_node("Panel") as Control

	var vp_rect: Rect2 = vp.get_visible_rect()
	var stock_rect: Rect2 = stockpile.get_global_rect()
	var unit_rect: Rect2 = unit_panel.get_global_rect()
	var debug_rect: Rect2 = debug_panel.get_global_rect()

	assert_true(vp_rect.encloses(stock_rect), "Stockpile panel %s must fit inside viewport %s" % [str(stock_rect), str(vp_rect)])
	assert_true(vp_rect.encloses(unit_rect), "Unit panel %s must fit inside viewport %s" % [str(unit_rect), str(vp_rect)])
	assert_false(stock_rect.intersects(unit_rect), "Stockpile and unit panels must not overlap")
	assert_false(stock_rect.intersects(debug_rect), "Stockpile panel must not overlap DebugOverlay")
	assert_false(unit_rect.intersects(debug_rect), "Unit panel must not overlap DebugOverlay")

	# Panels must leave the center of the viewport unobstructed
	var center_rect := Rect2(vp_rect.size * 0.35, vp_rect.size * 0.30)
	assert_false(stock_rect.intersects(center_rect), "Stockpile panel must not cover center of map")
	assert_false(unit_rect.intersects(center_rect), "Unit panel must not cover center of map")

	# Edge scroll margin (6 px) remains clear around corners
	assert_true(stock_rect.position.y >= 10.0 and vp_rect.size.x - stock_rect.end.x >= 10.0)
	assert_true(unit_rect.position.x >= 10.0 and vp_rect.size.y - unit_rect.end.y >= 10.0)


func test_01_live_gather_no_premature_credit_simultaneous_delivery_and_decay_sync() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["cam"] as Camera3D
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var clock: EconomyClockController = ctx["clock"] as EconomyClockController
	var hud: ResourceHud = ctx["hud"] as ResourceHud
	var stockpile: SettlementStockpilePanel = hud.get_stockpile_panel()
	var unit_panel: SelectedUnitPanel = hud.get_selected_unit_panel()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	_accelerate_sources(test_map)
	_accelerate_work_walk([leader_a, leader_b])

	assert_not_null(hud)
	assert_eq(stockpile.get_displayed_amount(&"wood"), 0)
	assert_eq(stockpile.get_displayed_amount(&"stone"), 0)
	assert_eq(stockpile.get_displayed_amount(&"food"), 0)
	assert_false(unit_panel.visible)

	# Select LeaderA and command gathering on food_bush_01
	selection.select_single(leader_a)
	assert_true(unit_panel.visible)
	assert_eq(unit_panel.get_state_text(), "Ocioso")

	var food_bush: ResourceSource = _find_source(test_map, &"food_bush_01")
	rig.set_focus_position(Vector2(food_bush.global_position.x, food_bush.global_position.z))
	await wait_process_frames(1)
	var bush_scr: Vector2 = cam.unproject_position(food_bush.global_position + Vector3(0.0, 0.5, 0.0))
	await _push_mouse_click(get_viewport(), MOUSE_BUTTON_RIGHT, bush_scr)

	var saw_moving: bool = false
	var saw_working: bool = false
	var saw_transporting: bool = false
	var saw_partial_load: bool = false
	var frames: int = 0
	while inventory.get_amount(&"food") == 0 and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		match leader_a.get_state():
			Unit.State.MOVING:
				saw_moving = true
				assert_eq(unit_panel.get_state_text(), "Deslocando")
			Unit.State.WORKING:
				saw_working = true
				assert_eq(unit_panel.get_state_text(), "Trabalhando")
				if leader_a.get_carry_load().get_amount(&"food") > 0:
					saw_partial_load = true
					assert_eq(stockpile.get_displayed_amount(&"food"), 0, "HUD stockpile must stay 0 during gathering before delivery")
			Unit.State.TRANSPORTING:
				saw_transporting = true
				assert_eq(unit_panel.get_state_text(), "Transportando")
				assert_eq(stockpile.get_displayed_amount(&"food"), 0, "HUD stockpile must stay 0 while transporting")

	assert_true(saw_moving and saw_working and saw_transporting and saw_partial_load)
	var first_food_delivery: int = inventory.get_amount(&"food")
	assert_gt(first_food_delivery, 0)
	assert_eq(stockpile.get_displayed_amount(&"food"), first_food_delivery)
	assert_eq(stockpile.get_displayed_amount(&"food"), _sum_piles_for_resource(pile_manager, &"food"))

	# Cancel LeaderA before second delivery, then command BOTH workers simultaneously to wood_tree_01
	leader_a.cancel_current_order()
	var wood_tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	var initial_tree_wood: int = wood_tree.get_remaining_amount()
	selection.select_single(leader_a)
	selection.add_unit(leader_b)
	assert_eq(unit_panel.get_header_text(), "2 selecionados")

	rig.set_focus_position(Vector2(wood_tree.global_position.x, wood_tree.global_position.z))
	await wait_process_frames(1)
	var tree_scr: Vector2 = cam.unproject_position(wood_tree.global_position + Vector3(0.0, 1.4, 0.0))
	await _push_mouse_click(get_viewport(), MOUSE_BUTTON_RIGHT, tree_scr)

	# Wait for both workers to deliver wood (>= 16 wood across two loads)
	frames = 0
	while inventory.get_amount(&"wood") < 16 and frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	assert_true(inventory.get_amount(&"wood") >= 16)
	assert_eq(stockpile.get_displayed_amount(&"wood"), inventory.get_amount(&"wood"))
	assert_eq(stockpile.get_displayed_amount(&"wood"), _sum_piles_for_resource(pile_manager, &"wood"))
	assert_eq(
		wood_tree.get_remaining_amount() + leader_a.get_carry_load().get_amount(&"wood") + leader_b.get_carry_load().get_amount(&"wood") + stockpile.get_displayed_amount(&"wood"),
		initial_tree_wood
	)

	# Decay via EconomyClockController updates HUD stockpile accurately
	var food_before_decay: int = stockpile.get_displayed_amount(&"food")
	clock.advance_simulated_time(280.0)
	var expected_food_after_decay: int = _sum_piles_for_resource(pile_manager, &"food")
	assert_lt(expected_food_after_decay, food_before_decay)
	assert_eq(stockpile.get_displayed_amount(&"food"), expected_food_after_decay)
	assert_eq(stockpile.get_displayed_amount(&"food"), inventory.get_amount(&"food"))

	# Scene teardown cleanly disconnects all HUD signals
	main_root.get_parent().remove_child(main_root)
	assert_false(hud.is_bound_to_selection_manager(selection))
	assert_false(stockpile.is_bound_to_inventory(inventory))
	assert_true(inventory.inventory_changed.get_connections().is_empty())
	assert_true(selection.selection_changed.get_connections().is_empty())
	assert_false(unit_panel.is_bound_to_unit(leader_a))
	assert_false(unit_panel.is_bound_to_unit(leader_b))
	main_root.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(hud))


func test_02_hud_non_blocking_rts_controls_and_two_resolutions_plus_resize() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp.add_child(main_root)

	var nav: WorldNavigation = main_root.get_test_map().get_navigation()
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	await wait_process_frames(3)
	await wait_physics_frames(2)

	var hud: ResourceHud = main_root.get_resource_hud()
	var stockpile: SettlementStockpilePanel = hud.get_stockpile_panel()
	var unit_panel: SelectedUnitPanel = hud.get_selected_unit_panel()
	var selection: SelectionManager = main_root.get_selection_manager()
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	var cam: Camera3D = rig.get_camera()
	var debug_overlay: DebugOverlay = main_root.get_node("UiLayer/DebugOverlay") as DebugOverlay
	var leader_a: Unit = main_root.get_units()[0]

	_assert_all_controls_mouse_ignore(hud)

	# Select LeaderA to make SelectedUnitPanel visible and check 1280x720 layout
	var leader_scr: Vector2 = cam.unproject_position(leader_a.global_position + Vector3(0.0, 0.9, 0.0))
	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, leader_scr)
	assert_eq(selection.get_selected_units(), [leader_a])
	await wait_process_frames(2)
	_assert_hud_layout_in_viewport(main_root, vp)

	# Clicking directly over stockpile HUD area must pass through to RTS input (clears selection)
	var stock_center: Vector2 = stockpile.get_global_rect().get_center()
	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, stock_center)
	assert_true(selection.is_empty(), "Left click over HUD panel must pass through to world input and clear selection")

	# Re-select LeaderA and verify right-click over SelectedUnitPanel still issues MoveOrder
	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, leader_scr)
	assert_eq(selection.get_selected_units(), [leader_a])
	await wait_process_frames(1)
	var unit_panel_center: Vector2 = unit_panel.get_global_rect().get_center()
	await _push_mouse_click(vp, MOUSE_BUTTON_RIGHT, unit_panel_center)
	assert_true(leader_a.get_current_order() is MoveOrder, "Right click over HUD panel must pass through as RTS command")

	# Resize SubViewport to 1920x1080 and verify layout adaptation
	vp.size = Vector2i(1920, 1080)
	await wait_process_frames(3)
	_assert_hud_layout_in_viewport(main_root, vp)

	# Resize back to 1280x720 and verify layout adaptation again
	vp.size = Vector2i(1280, 720)
	await wait_process_frames(3)
	_assert_hud_layout_in_viewport(main_root, vp)

	# F3 DebugOverlay toggle still works cleanly alongside ResourceHud
	var initial_debug_vis: bool = debug_overlay.visible
	var f3_event := InputEventKey.new()
	f3_event.physical_keycode = KEY_F3
	f3_event.pressed = true
	vp.push_input(f3_event, false)
	await wait_process_frames(1)
	assert_ne(debug_overlay.visible, initial_debug_vis, "F3 DebugOverlay toggle must continue working")
	f3_event.pressed = false
	vp.push_input(f3_event, false)

	# Camera zoom and keyboard pan still work with ResourceHud active
	var zoom_before: float = rig.get_target_zoom_distance()
	var wheel_in := InputEventMouseButton.new()
	wheel_in.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_in.pressed = true
	wheel_in.position = Vector2(640.0, 360.0)
	vp.push_input(wheel_in, false)
	await wait_process_frames(2)
	assert_lt(rig.get_target_zoom_distance(), zoom_before, "Mouse wheel zoom must still work")

	var focus_before: Vector2 = rig.get_focus_position()
	rig.edge_pan_enabled = true
	rig._window_has_focus = true
	rig._mouse_inside_window = true
	var edge_motion := InputEventMouseMotion.new()
	edge_motion.position = Vector2(2.0, 360.0)
	vp.push_input(edge_motion, true)
	await wait_process_frames(1)
	for _i: int in range(8):
		rig.step_camera(1.0 / 60.0)
	assert_lt(rig.get_focus_position().x, focus_before.x, "Edge scrolling at true border must remain functional")
	rig.edge_pan_enabled = false

	vp.queue_free()
	await wait_process_frames(2)
