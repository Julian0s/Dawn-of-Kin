extends TestCase
## Integration tests for T3.2 building placement flow inside MainScene + TestMap:
## - Activating Shelter (4x4) and Depot (5x4) previews via PlacementTestOverlay buttons and F6/F7
## - Gridless mouse-hover tracking & valid/invalid preview feedback (including CampStorageZone)
## - Valid LMB confirmation (exits placement, shows pulse/toast, creates NO ConstructionSite/obstacles/economy changes)
## - Invalid LMB confirmation (stays active, emits rejection + reason text)
## - Esc and RMB cancellation without issuing Move/Gather orders or altering unit selection
## - Non-interference with RTS selection, box selection, right-click orders, camera WASD/arrows/MMB/zoom/edge scroll
## - UI non-overlap & mouse passthrough at 1280x720 and 1920x1080 + clean MainScene teardown.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
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
	for action: StringName in [
		InputActions.CAMERA_PAN_UP,
		InputActions.CAMERA_PAN_DOWN,
		InputActions.CAMERA_PAN_LEFT,
		InputActions.CAMERA_PAN_RIGHT,
	]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _spawn_main_in_viewport(vp_size: Vector2i = Vector2i(1280, 720)) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = vp_size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp.add_child(main_root)

	var test_map: TestMap = main_root.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var frames: int = 0
	while nav != null and not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	await wait_process_frames(3)
	await wait_physics_frames(2)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	return {
		"vp": vp,
		"main": main_root,
		"test_map": test_map,
		"nav": nav,
		"rig": rig,
		"camera": rig.get_camera() if rig != null else null,
		"placement": main_root.get_placement_controller(),
		"overlay": main_root.get_placement_test_overlay(),
		"selection": main_root.get_selection_manager(),
		"inventory": main_root.get_settlement_inventory(),
		"units": main_root.get_units(),
	}


func _push_mouse_motion(vp: SubViewport, screen_pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen_pos
	ev.global_position = screen_pos
	vp.push_input(ev, false)


func _push_mouse_click(vp: SubViewport, button: MouseButton, screen_pos: Vector2) -> void:
	_push_mouse_motion(vp, screen_pos)
	await wait_process_frames(1)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = screen_pos
	press.global_position = screen_pos
	vp.push_input(press, false)
	await wait_process_frames(1)

	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = screen_pos
	release.global_position = screen_pos
	vp.push_input(release, false)
	await wait_process_frames(2)


func _push_key_press(vp: SubViewport, keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.pressed = true
	vp.push_input(down, false)
	await wait_process_frames(1)

	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.pressed = false
	vp.push_input(up, false)
	await wait_process_frames(1)


func _collect_non_button_controls_blocking_mouse(node: Control) -> Array[String]:
	var bad: Array[String] = []
	if not (node is BaseButton) and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		bad.append(node.name)
	for child: Node in node.get_children():
		if child is Control:
			bad.append_array(_collect_non_button_controls_blocking_mouse(child as Control))
	return bad


func _wait_for_confirm_settled(placement: PlacementController, max_frames: int = 90) -> void:
	var frames: int = 0
	while placement.is_confirm_pending() and frames < max_frames:
		await wait_process_frames(1)
		frames += 1


func test_01_overlay_triggers_preview_sizes_hover_feedback_confirm_and_zero_side_effects() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var camera: Camera3D = ctx["camera"] as Camera3D
	var placement: PlacementController = ctx["placement"] as PlacementController
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var test_map: TestMap = ctx["test_map"] as TestMap

	assert_not_null(placement)
	assert_not_null(overlay)
	assert_false(placement.is_placement_active())

	var confirmed_events: Array[Dictionary] = []
	var rejected_events: Array[Dictionary] = []
	placement.placement_confirmed.connect(func(def: BuildingDefinition, pos: Vector3, res: PlacementValidator.ValidationResult) -> void:
		confirmed_events.append({"def": def, "pos": pos, "res": res})
	)
	placement.placement_rejected.connect(func(def: BuildingDefinition, pos: Vector3, res: PlacementValidator.ValidationResult) -> void:
		rejected_events.append({"def": def, "pos": pos, "res": res})
	)

	# 1. Start Shelter (4x4) via F6 hotkey.
	await _push_key_press(vp, KEY_F6)
	assert_true(placement.is_placement_active(), "F6 must activate placement mode")
	assert_eq(placement.get_active_definition().definition_id, &"shelter_basic")

	# Hover over valid free spot (-6.0, 0.0, 1.5).
	var free_world := Vector3(-6.0, 0.0, 1.5)
	var free_screen: Vector2 = camera.unproject_position(free_world)
	_push_mouse_motion(vp, free_screen)
	await wait_process_frames(2)

	var preview: PlacementPreview = placement.get_preview()
	assert_not_null(preview)
	assert_true(preview.visible, "Preview must be visible while hovering terrain")
	assert_true(preview.is_valid_state(), "Free terrain hover must set valid green state")
	assert_vec2_near(preview.get_displayed_footprint_size(), Vector2(4.0, 4.0), 0.001)

	# 2. Switch to Depot (5x4) via overlay button press.
	overlay.get_depot_button().pressed.emit()
	await wait_process_frames(2)
	assert_true(placement.is_placement_active())
	assert_eq(placement.get_active_definition().definition_id, &"storage_depot")
	_push_mouse_motion(vp, free_screen + Vector2(3.0, 0.0))
	await wait_process_frames(2)
	assert_vec2_near(preview.get_displayed_footprint_size(), Vector2(5.0, 4.0), 0.001)

	# 3. Hover over CampStorageZone anchor -> invalid red + D6 reason text + LMB click rejected (remains active).
	var camp_world: Vector3 = test_map.get_camp_storage_zone().get_anchor_position()
	var camp_screen: Vector2 = camera.unproject_position(camp_world)
	_push_mouse_motion(vp, camp_screen)
	await wait_process_frames(2)
	assert_false(preview.is_valid_state(), "CampStorageZone hover must show invalid red visual")
	assert_string_contains(overlay.get_status_detail_text().to_lower(), "área reservada")

	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, camp_screen)
	assert_true(placement.is_placement_active(), "Invalid LMB click must keep placement active")
	assert_eq(rejected_events.size(), 1, "Invalid LMB click must emit placement_rejected")
	assert_eq(confirmed_events.size(), 0)

	# 4. Valid LMB click over free ground confirms cleanly without instantiating ConstructionSite or changing stock.
	var child_count_before: int = test_map.get_child_count()
	var poly_before: int = nav.navigation_mesh.get_polygon_count()
	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, free_screen)
	await _wait_for_confirm_settled(placement)

	assert_false(placement.is_placement_active(), "Valid LMB confirm must exit placement mode")
	assert_eq(confirmed_events.size(), 1, "Valid LMB click must emit placement_confirmed")
	assert_true(preview.visible, "Temporary confirmation pulse should briefly stay visible")
	assert_true(overlay.is_status_visible(), "Confirmation toast should display temporarily")
	assert_eq(test_map.get_child_count(), child_count_before, "T3.2 must not instantiate ConstructionSite or Building nodes")
	assert_eq(nav.navigation_mesh.get_polygon_count(), poly_before, "T3.2 confirm must not alter active WorldNavigation")
	assert_eq(inventory.get_physical_amount(&"wood"), 0, "T3.2 confirm must not modify settlement inventory")

	# Verify pulse fades out automatically after duration.
	preview._process(PlacementPreview.CONFIRM_PULSE_DURATION_SEC + 0.1)
	assert_false(preview.visible, "Confirmation pulse must hide cleanly after fade")

	vp.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(main_root), "MainScene must free cleanly with zero errors")


func test_02_esc_and_rmb_cancel_preserve_selection_without_rts_orders() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var camera: Camera3D = ctx["camera"] as Camera3D
	var placement: PlacementController = ctx["placement"] as PlacementController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var leader_a: Unit = units[0]

	# Select LeaderA before entering placement.
	var leader_screen: Vector2 = camera.unproject_position(leader_a.global_position + Vector3(0.0, 0.9, 0.0))
	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, leader_screen)
	assert_eq(selection.get_selected_units(), [leader_a])
	assert_null(leader_a.get_current_order())

	var cancelled_defs: Array[BuildingDefinition] = []
	placement.placement_cancelled.connect(func(def: BuildingDefinition) -> void:
		cancelled_defs.append(def)
	)

	# 1. Start placement via F6 and cancel with RMB over walkable ground -> must NOT issue MoveOrder or deselect!
	await _push_key_press(vp, KEY_F6)
	assert_true(placement.is_placement_active())
	var move_target_screen: Vector2 = camera.unproject_position(Vector3(-6.0, 0.0, 4.0))
	await _push_mouse_click(vp, MOUSE_BUTTON_RIGHT, move_target_screen)

	assert_false(placement.is_placement_active(), "RMB must cancel active placement")
	assert_eq(cancelled_defs.size(), 1)
	assert_false(placement.get_preview().visible, "Preview must hide immediately on RMB cancel")
	assert_null(leader_a.get_current_order(), "RMB cancelling placement must NOT issue MoveOrder")
	assert_eq(selection.get_selected_units(), [leader_a], "Selection must remain intact on RMB cancel")

	# 2. Start placement via F7 and cancel with Esc -> must NOT clear unit selection!
	await _push_key_press(vp, KEY_F7)
	assert_true(placement.is_placement_active())
	await _push_key_press(vp, KEY_ESCAPE)

	assert_false(placement.is_placement_active(), "Esc must cancel active placement")
	assert_eq(cancelled_defs.size(), 2)
	assert_eq(selection.get_selected_units(), [leader_a], "Esc cancelling placement must preserve unit selection")

	# 3. After cancellation, normal RMB move order and LMB selection work again.
	await _push_mouse_click(vp, MOUSE_BUTTON_RIGHT, move_target_screen)
	assert_true(leader_a.get_current_order() is MoveOrder, "Normal RMB MoveOrder must work after placement cancellation")

	var empty_ground_screen: Vector2 = camera.unproject_position(Vector3(-12.0, 0.0, 8.0))
	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, empty_ground_screen)
	assert_true(selection.is_empty(), "Normal LMB empty click must clear selection after placement ends")

	vp.queue_free()
	await wait_process_frames(2)


func test_03_camera_controls_during_placement_and_layout_two_resolutions() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport(Vector2i(1280, 720))
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var placement: PlacementController = ctx["placement"] as PlacementController
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay

	# Verify overlay containers do not block mouse input and buttons use FOCUS_NONE.
	var blocking_nodes: Array[String] = _collect_non_button_controls_blocking_mouse(overlay)
	assert_eq(blocking_nodes, [], "Non-button controls in PlacementTestOverlay must use MOUSE_FILTER_IGNORE")
	assert_eq(overlay.get_shelter_button().focus_mode, Control.FOCUS_NONE)
	assert_eq(overlay.get_depot_button().focus_mode, Control.FOCUS_NONE)
	assert_eq(overlay.get_cancel_button().focus_mode, Control.FOCUS_NONE)

	await _push_key_press(vp, KEY_F6)
	assert_true(placement.is_placement_active())

	# 1. Keyboard WASD pan works during active placement.
	var focus_before_wasd: Vector2 = rig.get_focus_position()
	Input.action_press(InputActions.CAMERA_PAN_RIGHT)
	for _i: int in range(6):
		rig.step_camera(1.0 / 60.0)
	Input.action_release(InputActions.CAMERA_PAN_RIGHT)
	assert_gt(rig.get_focus_position().x, focus_before_wasd.x, "WASD/Arrow pan must keep working during placement")

	# 2. MMB drag pan works during active placement.
	var focus_before_mmb: Vector2 = rig.get_focus_position()
	var mmb_down := InputEventMouseButton.new()
	mmb_down.button_index = MOUSE_BUTTON_MIDDLE
	mmb_down.pressed = true
	mmb_down.position = Vector2(640.0, 360.0)
	vp.push_input(mmb_down, false)
	var mmb_drag := InputEventMouseMotion.new()
	mmb_drag.position = Vector2(540.0, 360.0)
	mmb_drag.relative = Vector2(-100.0, 0.0)
	vp.push_input(mmb_drag, false)
	var mmb_up := InputEventMouseButton.new()
	mmb_up.button_index = MOUSE_BUTTON_MIDDLE
	mmb_up.pressed = false
	mmb_up.position = Vector2(540.0, 360.0)
	vp.push_input(mmb_up, false)
	await wait_process_frames(1)
	assert_ne(rig.get_focus_position(), focus_before_mmb, "MMB drag pan must keep working during placement")

	# 3. Mouse wheel zoom works during active placement.
	var zoom_before: float = rig.get_target_zoom_distance()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(640.0, 360.0)
	vp.push_input(wheel, false)
	await wait_process_frames(2)
	assert_lt(rig.get_target_zoom_distance(), zoom_before, "Scroll zoom must keep working during placement")

	# 4. Layout non-overlap check at 1280x720 and 1920x1080 with SelectedUnitPanel + Overlay active.
	placement.cancel_placement()
	var leader_a: Unit = (ctx["units"] as Array[Unit])[0]
	main_root.get_selection_manager().select_single(leader_a)
	await _push_key_press(vp, KEY_F7)
	_push_mouse_motion(vp, Vector2(480.0, 360.0))
	await wait_process_frames(3)

	for test_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		vp.size = test_size
		await wait_process_frames(3)
		var vp_rect := Rect2(Vector2.ZERO, Vector2(test_size))
		var bar_panel: Control = overlay.get_node("TemporaryPlacementBar") as Control
		var status_panel: Control = overlay.get_node("PlacementStatusBanner") as Control
		var stockpile_panel: Control = main_root.get_resource_hud().get_stockpile_panel()
		var unit_panel: Control = main_root.get_resource_hud().get_selected_unit_panel()

		var bar_rect: Rect2 = bar_panel.get_global_rect()
		var status_rect: Rect2 = status_panel.get_global_rect()
		var stock_rect: Rect2 = stockpile_panel.get_global_rect()
		var unit_rect: Rect2 = unit_panel.get_global_rect()

		assert_true(vp_rect.encloses(bar_rect), "Placement bar must stay inside viewport %s" % str(test_size))
		assert_true(vp_rect.encloses(status_rect), "Placement status banner must stay inside viewport %s" % str(test_size))
		assert_false(bar_rect.intersects(stock_rect), "Placement bar must not overlap stockpile HUD at %s" % str(test_size))
		assert_false(bar_rect.intersects(unit_rect), "Placement bar must not overlap selected unit HUD at %s" % str(test_size))
		assert_false(status_rect.intersects(stock_rect), "Placement status banner must not overlap stockpile HUD at %s" % str(test_size))

	vp.queue_free()
	await wait_process_frames(2)


func test_04_dynamic_world_hover_updates_with_stationary_cursor_and_midflight_cancel() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var camera: Camera3D = ctx["camera"] as Camera3D
	var placement: PlacementController = ctx["placement"] as PlacementController
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay
	var test_map: TestMap = ctx["test_map"] as TestMap
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var leader_a: Unit = units[0]

	var confirmed_defs: Array[BuildingDefinition] = []
	placement.placement_confirmed.connect(func(def: BuildingDefinition, _pos: Vector3, _res: PlacementValidator.ValidationResult) -> void:
		confirmed_defs.append(def)
	)

	await _push_key_press(vp, KEY_F6)
	assert_true(placement.is_placement_active())

	# Hover cursor once over open spot (-6.0, 0.0, 1.5) and keep mouse + camera completely stationary!
	var free_world := Vector3(-6.0, 0.0, 1.5)
	var free_screen: Vector2 = camera.unproject_position(free_world)
	_push_mouse_motion(vp, free_screen)
	await wait_process_frames(2)
	var preview: PlacementPreview = placement.get_preview()
	assert_true(preview.is_valid_state(), "Hover should start valid green over open terrain")

	# 1. Worker moves into stationary hovered footprint -> preview flips invalid automatically!
	var orig_pos: Vector3 = leader_a.global_position
	leader_a.global_position = free_world
	await wait_physics_frames(2)
	for _i: int in range(12):
		await get_tree().create_timer(0.02).timeout
	assert_false(preview.is_valid_state(), "Worker entering stationary footprint must flip preview invalid")
	assert_string_contains(overlay.get_status_detail_text().to_lower(), "trabalhadores")

	# Worker leaves stationary hovered footprint -> preview flips back valid automatically!
	leader_a.global_position = orig_pos
	await wait_physics_frames(2)
	for _i: int in range(12):
		await get_tree().create_timer(0.02).timeout
	assert_true(preview.is_valid_state(), "Worker leaving stationary footprint must flip preview back to valid")

	# 2. Physical pile appears then disappears inside stationary footprint -> preview flips red then green!
	var dyn_pile := GroundResourcePile.new()
	test_map.add_child(dyn_pile)
	dyn_pile.configure_initial(950, main_root.WOOD_DEFINITION, 6, free_world)
	for _i: int in range(12):
		await get_tree().create_timer(0.02).timeout
	assert_false(preview.is_valid_state(), "Pile appearing inside stationary footprint must flip preview invalid")
	assert_string_contains(overlay.get_status_detail_text().to_lower(), "pilhas")

	dyn_pile.queue_free()
	await wait_process_frames(2)
	for _i: int in range(12):
		await get_tree().create_timer(0.02).timeout
	assert_true(preview.is_valid_state(), "Pile disappearing inside stationary footprint must restore valid green")

	# 3. Natural resource stops blocking area while cursor stays stationary over FoodBush01.
	var bush: ResourceSource = null
	for src: ResourceSource in test_map.get_resource_sources():
		if src.source_id == &"food_bush_01":
			bush = src
			break
	assert_not_null(bush)
	var bush_world := Vector3(-11.5, 0.0, 4.5)
	var bush_screen: Vector2 = camera.unproject_position(bush_world)
	_push_mouse_motion(vp, bush_screen)
	await wait_process_frames(2)
	assert_false(preview.is_valid_state(), "Natural resource under stationary cursor must start invalid")

	bush.queue_free()
	await wait_physics_frames(2)
	for _i: int in range(12):
		await get_tree().create_timer(0.02).timeout
	assert_true(preview.is_valid_state(), "Removing blocking resource under stationary cursor must update preview to valid")

	# 4. Trigger valid async confirmation, then press Esc mid-flight -> must abort cleanly with 0 confirmed events!
	_push_mouse_motion(vp, free_screen)
	await wait_process_frames(2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = free_screen
	press.global_position = free_screen
	vp.push_input(press, false)
	await wait_process_frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = free_screen
	release.global_position = free_screen
	vp.push_input(release, false)
	await _push_key_press(vp, KEY_ESCAPE)
	await _wait_for_confirm_settled(placement)
	await wait_process_frames(6)
	assert_false(placement.is_placement_active())
	assert_eq(confirmed_defs.size(), 0, "Esc during async confirm must cancel cleanly without confirming")

	vp.queue_free()
	await wait_process_frames(2)


func test_05_async_confirm_race_conditions_scenarios_a_to_e() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var camera: Camera3D = ctx["camera"] as Camera3D
	var placement: PlacementController = ctx["placement"] as PlacementController
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var test_map: TestMap = ctx["test_map"] as TestMap
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var leader_a: Unit = units[0]

	var confirmed_events: Array[Dictionary] = []
	var rejected_events: Array[Dictionary] = []
	var cancelled_defs: Array[BuildingDefinition] = []
	placement.placement_confirmed.connect(func(def: BuildingDefinition, pos: Vector3, res: PlacementValidator.ValidationResult) -> void:
		confirmed_events.append({"def": def, "pos": pos, "result": res})
	)
	placement.placement_rejected.connect(func(def: BuildingDefinition, pos: Vector3, res: PlacementValidator.ValidationResult) -> void:
		rejected_events.append({"def": def, "pos": pos, "result": res})
	)
	placement.placement_cancelled.connect(func(def: BuildingDefinition) -> void:
		cancelled_defs.append(def)
	)

	await _push_key_press(vp, KEY_F6)
	assert_true(placement.is_placement_active())
	var shelter_def: BuildingDefinition = placement.get_active_definition()
	var free_world := Vector3(-6.0, 0.0, 1.5)
	var free_screen: Vector2 = camera.unproject_position(free_world)
	_push_mouse_motion(vp, free_screen)
	await wait_process_frames(2)
	var preview: PlacementPreview = placement.get_preview()
	assert_true(preview.is_valid_state())

	# Scenario A: worker enters footprint deterministically while confirm bake is in flight.
	var orig_leader_pos: Vector3 = leader_a.global_position
	placement.confirm_at_world_pos(free_world)
	assert_true(placement.is_confirm_pending(), "Async confirm must be pending right after dispatch")
	assert_null(placement.confirm_at_world_pos(free_world), "Duplicate confirm while pending must be ignored")
	leader_a.global_position = free_world
	await _wait_for_confirm_settled(placement)

	assert_eq(confirmed_events.size(), 0, "Scenario A must not emit placement_confirmed")
	assert_eq(rejected_events.size(), 1, "Scenario A must emit placement_rejected")
	assert_eq((rejected_events[0]["result"] as PlacementValidator.ValidationResult).reason_code, PlacementValidator.REASON_UNIT_OVERLAP)
	assert_true(placement.is_placement_active(), "Scenario A rejection must keep placement active")
	assert_false(preview.is_valid_state(), "Scenario A rejection must flip preview to invalid red")

	leader_a.global_position = orig_leader_pos
	await wait_physics_frames(2)

	# Scenario B: physical pile spawns in footprint before async callback completes.
	placement.confirm_at_world_pos(free_world)
	assert_true(placement.is_confirm_pending())
	var dyn_pile := GroundResourcePile.new()
	test_map.add_child(dyn_pile)
	dyn_pile.configure_initial(981, main_root.WOOD_DEFINITION, 5, free_world)
	await _wait_for_confirm_settled(placement)

	assert_eq(confirmed_events.size(), 0, "Scenario B must not emit placement_confirmed")
	assert_eq(rejected_events.size(), 2, "Scenario B must emit placement_rejected")
	assert_eq((rejected_events[1]["result"] as PlacementValidator.ValidationResult).reason_code, PlacementValidator.REASON_PILE_OVERLAP)
	assert_true(placement.is_placement_active(), "Scenario B rejection must keep placement active")
	assert_false(preview.is_valid_state(), "Scenario B rejection must show invalid red preview")

	dyn_pile.queue_free()
	await wait_process_frames(2)

	# Scenario E: navigation rebake triggered mid-flight must invalidate stale candidate mesh.
	placement.confirm_at_world_pos(free_world)
	assert_true(placement.is_confirm_pending())
	nav.request_rebake()
	await _wait_for_confirm_settled(placement)
	var nav_wait: int = 0
	while not nav.is_navigation_ready() and nav_wait < 120:
		await wait_process_frames(1)
		nav_wait += 1
	assert_true(nav.is_navigation_ready(), "Navigation rebake must settle")
	assert_eq(confirmed_events.size(), 0, "Scenario E must never emit placement_confirmed from stale bake")
	assert_eq(rejected_events.size(), 3, "Scenario E must emit placement_rejected")
	assert_true(placement.is_placement_active())

	# Scenario D1: RMB cancel during pending bake prevents confirmation and never reopens preview.
	placement.confirm_at_world_pos(free_world)
	assert_true(placement.is_confirm_pending())
	await _push_mouse_click(vp, MOUSE_BUTTON_RIGHT, free_screen)
	assert_false(placement.is_confirm_pending(), "RMB cancel must clear pending confirm immediately")
	assert_false(placement.is_placement_active(), "RMB cancel must deactivate placement")
	assert_false(preview.visible, "Preview must remain hidden after mid-flight cancel")
	assert_eq(cancelled_defs.size(), 1)
	await wait_process_frames(15)
	assert_eq(confirmed_events.size(), 0, "Delayed callback after RMB cancel must not confirm")
	assert_false(placement.is_placement_active(), "Delayed callback must not reopen placement")
	assert_false(preview.visible, "Delayed callback must not reopen preview")

	# Scenario D2: building switch during pending bake prevents confirmation for old building.
	await _push_key_press(vp, KEY_F6)
	assert_true(placement.is_placement_active())
	placement.confirm_at_world_pos(free_world)
	assert_true(placement.is_confirm_pending())
	await _push_key_press(vp, KEY_F7)
	var depot_def: BuildingDefinition = placement.get_active_definition()
	assert_ne(depot_def, shelter_def)
	await wait_process_frames(15)
	assert_eq(confirmed_events.size(), 0, "Switching building during pending bake must abort old confirm")
	assert_true(placement.is_placement_active())
	assert_eq(placement.get_active_definition(), depot_def)

	# Scenario C: stable state completes and confirms normally.
	placement.confirm_at_world_pos(free_world)
	assert_true(placement.is_confirm_pending())
	await _wait_for_confirm_settled(placement)
	assert_eq(confirmed_events.size(), 1, "Scenario C stable confirm must emit placement_confirmed once")
	assert_true((confirmed_events[0]["result"] as PlacementValidator.ValidationResult).valid)
	assert_false(placement.is_placement_active())

	# Scenario D3: destroying controller mid-flight cancels safely without confirming.
	await _push_key_press(vp, KEY_F6)
	placement.confirm_at_world_pos(free_world)
	assert_true(placement.is_confirm_pending())
	placement.queue_free()
	await get_tree().create_timer(0.18).timeout
	assert_eq(confirmed_events.size(), 1, "Freeing controller mid-flight must never emit additional confirmation")

	vp.queue_free()
	await wait_process_frames(2)
