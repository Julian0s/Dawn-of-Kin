extends TestCase
## Integration tests for UI-1.1B under real production provenance economy (use_provenance_economy = true):
## 1. Polygonal surface hitboxes with real mouse events:
##    - LMB & RMB on solid rock/plaque block RTS selection & orders
##    - Transparent shadow pad, chamfer corners, and gaps between rocks pass through to 3D world
##    - Wheel scroll blocked on solid HUD, active on free map
##    - Edge Pan blocked on solid HUD near edge, active on free edge (no stale _last_mouse_pos)
##    - WASD stays responsive over HUD during normal unlocked gameplay
##    - Dynamic resize 720p -> 1080p -> 720p preserves exact hitboxes
## 2. Real pause/resume via || and 1x buttons:
##    - Repeated pause/resume cycles with real mouse clicks (including clicking 1x while paused!)
##    - Camera 100% locked during pause (WASD, Edge Pan, Wheel Zoom, MMB Drag -> 0 displacement)
##    - EconomyClockController stops advancing during pause
##    - Zero RTS command or zoom leakage when right-clicking/scrolling on || or 1x
## 3. Pause during physical gathering, transport, and construction assembly under provenance economy:
##    - Complete freeze during pause, exact continuation and material conservation after resume
## 4. External pause preservation, scene exit, and clean re-entry
## 5. D2UiEscapeRouter pass-through (Esc clears selection/drag/catalog/placement once, no fake menu)
##    and full legacy mode (use_d2_2_hud = false) preservation.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SANDBOX_SCENE: PackedScene = preload("res://tests/visual/ui_1_d2_2_sandbox.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const MAX_WAIT_FRAMES: int = 120
const MAX_CYCLE_FRAMES: int = 2400
const SITE_POS: Vector3 = Vector3(-6.0, 0.0, 1.5)


func after_each() -> void:
	_release_all_actions()
	var tree: SceneTree = get_tree()
	if tree != null:
		if tree.has_meta(D2SimulationPauseController.TREE_META_PAUSE_AUTHORITIES):
			tree.remove_meta(D2SimulationPauseController.TREE_META_PAUSE_AUTHORITIES)
		tree.paused = false
	Engine.time_scale = 1.0


func _wait_nav_ready(main_root: MainScene) -> void:
	var test_map: TestMap = main_root.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var frames: int = 0
	while nav != null and not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	await wait_process_frames(2)
	await wait_physics_frames(2)


func _push_mouse_motion(vp: Viewport, pos: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.relative = relative
	vp.push_input(motion, true)


func _push_mouse_click(vp: Viewport, pos: Vector2, button: MouseButton) -> void:
	_push_mouse_motion(vp, pos)
	await wait_process_frames(1)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = pos
	press.global_position = pos
	vp.push_input(press, true)
	await wait_process_frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = pos
	release.global_position = pos
	vp.push_input(release, true)
	await wait_process_frames(1)


func _push_mouse_wheel(vp: Viewport, pos: Vector2, button: MouseButton) -> void:
	_push_mouse_motion(vp, pos)
	await wait_process_frames(1)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = button
	wheel.pressed = true
	wheel.position = pos
	wheel.global_position = pos
	vp.push_input(wheel, true)
	var wheel_rel := InputEventMouseButton.new()
	wheel_rel.button_index = button
	wheel_rel.pressed = false
	wheel_rel.position = pos
	wheel_rel.global_position = pos
	vp.push_input(wheel_rel, true)
	await wait_process_frames(1)


func _push_escape(vp: Viewport) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	ev.echo = false
	vp.push_input(ev, true)
	await wait_process_frames(1)


func _set_action_pressed(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _release_all_actions() -> void:
	for action: StringName in [
		InputActions.CAMERA_PAN_UP,
		InputActions.CAMERA_PAN_DOWN,
		InputActions.CAMERA_PAN_LEFT,
		InputActions.CAMERA_PAN_RIGHT,
		InputActions.CAMERA_DRAG,
	]:
		if Input.is_action_pressed(action):
			_set_action_pressed(action, false)


func _teardown_main(main_root: MainScene, vp: SubViewport = null) -> void:
	if main_root != null and is_instance_valid(main_root):
		for u: Unit in main_root.get_units():
			u.cancel_current_order()
		var td: Dictionary = main_root.request_controlled_teardown()
		if not bool(td.get("ok", false)) and main_root.is_inside_tree():
			main_root.queue_free()
	if vp != null and is_instance_valid(vp):
		vp.queue_free()
	await wait_process_frames(2)


func test_01_surface_hitboxes_clicks_scroll_edge_pan_and_resize() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	assert_true(main_root.use_provenance_economy, "Test must run under production use_provenance_economy = true")
	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var rocks: D2ResourceRocksView = d2.get_resource_rocks_view()
	var plaque: D2TopPlaqueView = d2.get_top_plaque_view()
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	rig.edge_pan_enabled = false

	var leader: Unit = main_root.get_units()[0]
	var sel: SelectionManager = main_root.get_selection_manager()
	sel.select_single(leader)
	assert_eq(sel.get_selected_units().size(), 1)
	assert_null(leader.get_current_order())

	var wood_slab: D2PolygonalSlab = rocks.get_slab(0)
	var stone_slab: D2PolygonalSlab = rocks.get_slab(1)
	var plaque_slab: D2PolygonalSlab = plaque.get_slab()

	var wood_center: Vector2 = wood_slab.position + wood_slab.size * 0.5
	var stone_center: Vector2 = stone_slab.position + stone_slab.size * 0.5
	var plaque_solid_top: Vector2 = plaque_slab.position + Vector2(plaque_slab.size.x * 0.5, plaque_slab.size.y * 0.25)

	# 1. Left-click on solid wood rock -> consumed by HUD, selection preserved
	await _push_mouse_click(vp, wood_center, MOUSE_BUTTON_LEFT)
	assert_eq(vp.gui_get_hovered_control(), wood_slab, "Solid rock center must be hovered")
	assert_eq(sel.get_selected_units().size(), 1, "Left-click on solid rock must NOT clear unit selection")

	# 2. Right-click on solid stone rock -> consumed by HUD, zero move/gather order leaked
	await _push_mouse_click(vp, stone_center, MOUSE_BUTTON_RIGHT)
	assert_eq(vp.gui_get_hovered_control(), stone_slab, "Solid stone rock center must be hovered")
	assert_null(leader.get_current_order(), "Right-click on solid rock must NOT issue any RTS order")

	# 3. Transparent shadow pad corner of wood rock -> passes through to 3D world
	var wood_shadow_corner: Vector2 = wood_slab.position + Vector2(2.0, 2.0)
	_push_mouse_motion(vp, wood_shadow_corner)
	await wait_process_frames(1)
	assert_null(vp.gui_get_hovered_control(), "Transparent shadow corner must NOT be hovered")
	assert_false(wood_slab.contains_global_point(wood_shadow_corner))

	# 4. Transparent chamfer cut corner -> passes through to 3D world
	var s: float = d2.get_current_scale()
	var wood_chamfer_outside: Vector2 = wood_slab.position + Vector2(10.5 * s, 10.5 * s)
	_push_mouse_motion(vp, wood_chamfer_outside)
	await wait_process_frames(1)
	assert_null(vp.gui_get_hovered_control(), "Transparent chamfer corner must pass through")

	# 5. Gap between wood and stone rocks -> passes through to 3D world & allows real RTS command
	var gap_pt := Vector2(
		(D2Tokens.ROCK_ORIGIN.x + D2Tokens.ROCK_CONTENT_SIZE.x + D2Tokens.ROCK_GAP_X * 0.5) * s,
		(D2Tokens.ROCK_ORIGIN.y + 22.0) * s
	)
	_push_mouse_motion(vp, gap_pt)
	await wait_process_frames(1)
	assert_null(vp.gui_get_hovered_control(), "Gap between rocks must pass through")
	await _push_mouse_click(vp, gap_pt, MOUSE_BUTTON_LEFT)
	assert_eq(sel.get_selected_units().size(), 0, "Left-click in gap between rocks must pass through to clear selection on terrain")
	sel.select_single(leader)

	# 6. Scroll wheel on solid rock and solid top plaque -> zoom unchanged
	var zoom_before: float = rig.get_target_zoom_distance()
	await _push_mouse_wheel(vp, wood_center, MOUSE_BUTTON_WHEEL_UP)
	assert_near(rig.get_target_zoom_distance(), zoom_before, 0.001, "Scroll over solid rock must NOT zoom camera")
	await _push_mouse_wheel(vp, plaque_solid_top, MOUSE_BUTTON_WHEEL_DOWN)
	assert_near(rig.get_target_zoom_distance(), zoom_before, 0.001, "Scroll over solid top plaque must NOT zoom camera")

	# 7. Scroll wheel on free map center -> zoom changes cleanly
	var free_center: Vector2 = Vector2(vp.size) * 0.5
	await _push_mouse_wheel(vp, free_center, MOUSE_BUTTON_WHEEL_UP)
	assert_lt(rig.get_target_zoom_distance(), zoom_before - 0.5, "Scroll over free map must zoom camera in")

	# 8. Edge Pan over solid HUD near edge vs free edge (and verify no stale _last_mouse_pos)
	rig.edge_pan_enabled = true
	rig._window_has_focus = true
	rig._mouse_inside_window = true
	rig.set_focus_position(Vector2.ZERO)

	# First pan at free left edge -> moves focus left
	_push_mouse_motion(vp, Vector2(2.0, 360.0))
	await wait_process_frames(1)
	assert_null(vp.gui_get_hovered_control(), "Free left edge must not be hovered by GUI")
	for _i: int in range(8):
		rig.step_camera(1.0 / 60.0)
	assert_lt(rig.get_focus_position().x, -0.05, "Free left edge must trigger Edge Pan")

	# Now widen edge_pan_margin_base_px so solid wood rock sits strictly inside edge zone;
	# moving from free edge directly onto solid rock must update _last_mouse_pos AND block Edge Pan!
	rig.edge_pan_margin_base_px = 60.0
	rig.set_focus_position(Vector2.ZERO)
	_push_mouse_motion(vp, wood_center)
	await wait_process_frames(1)
	assert_eq(vp.gui_get_hovered_control(), wood_slab, "Pointer moved onto rock must be hovered")
	for _i: int in range(10):
		rig.step_camera(1.0 / 60.0)
	assert_vec2_near(rig.get_focus_position(), Vector2.ZERO, 0.001, "Edge Pan MUST be blocked when pointer is over solid HUD rock")

	# WASD during normal unlocked gameplay still works even while hovering solid rock
	Input.action_press(InputActions.CAMERA_PAN_RIGHT)
	for _i: int in range(8):
		rig.step_camera(1.0 / 60.0)
	Input.action_release(InputActions.CAMERA_PAN_RIGHT)
	assert_gt(rig.get_focus_position().length(), 0.2, "WASD must stay responsive over HUD during normal unlocked gameplay")

	# 9. Dynamic resize 720p -> 1080p -> 720p preserves accurate hitboxes
	rig.edge_pan_enabled = false
	for res: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		vp.size = res
		await wait_process_frames(3)
		var c_rock: Vector2 = wood_slab.position + wood_slab.size * 0.5
		var c_pad: Vector2 = wood_slab.position + Vector2(2.0, 2.0)
		_push_mouse_motion(vp, c_rock)
		await wait_process_frames(1)
		assert_eq(vp.gui_get_hovered_control(), wood_slab, "Solid rock must hit after resize to %s" % str(res))
		_push_mouse_motion(vp, c_pad)
		await wait_process_frames(1)
		assert_null(vp.gui_get_hovered_control(), "Shadow pad must pass through after resize to %s" % str(res))

	await _teardown_main(main_root, vp)


func test_02_real_pause_buttons_camera_lock_and_economy_clock() -> void:
	var vp := SubViewport.new()
	vp.process_mode = Node.PROCESS_MODE_ALWAYS
	vp.own_world_3d = true
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	assert_true(main_root.use_provenance_economy)
	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var plaque: D2TopPlaqueView = d2.get_top_plaque_view()
	var pause_ctrl: D2SimulationPauseController = d2.get_pause_controller()
	var clock: EconomyClockController = main_root.get_economy_clock()
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	var leader: Unit = main_root.get_units()[0]
	main_root.get_selection_manager().select_single(leader)

	var btn_pause: D2SlabButton = plaque.get_pause_button()
	var btn_resume: D2SlabButton = plaque.get_resume_button()
	var pause_pos: Vector2 = btn_pause.position + btn_pause.size * 0.5
	var resume_pos: Vector2 = btn_resume.position + btn_resume.size * 0.5

	# Right-click & scroll on || and 1x leak zero RTS commands and zero zoom
	var zoom_init: float = rig.get_target_zoom_distance()
	await _push_mouse_click(vp, pause_pos, MOUSE_BUTTON_RIGHT)
	await _push_mouse_wheel(vp, pause_pos, MOUSE_BUTTON_WHEEL_UP)
	await _push_mouse_click(vp, resume_pos, MOUSE_BUTTON_RIGHT)
	await _push_mouse_wheel(vp, resume_pos, MOUSE_BUTTON_WHEEL_DOWN)
	assert_null(leader.get_current_order(), "Right-clicking || or 1x must not issue RTS orders")
	assert_near(rig.get_target_zoom_distance(), zoom_init, 0.001, "Scrolling || or 1x must not zoom camera")
	assert_false(get_tree().paused)

	# Repeated pause/resume cycle 1 & 2 via REAL mouse clicks
	for cycle: int in range(2):
		# Start camera moving so we also verify residual pan velocity is cleared on pause!
		rig.edge_pan_enabled = true
		rig._window_has_focus = true
		rig._mouse_inside_window = true
		rig.set_focus_position(Vector2.ZERO)
		_set_action_pressed(InputActions.CAMERA_PAN_RIGHT, true)
		for _i: int in range(5):
			rig.step_camera(1.0 / 60.0)
		_set_action_pressed(InputActions.CAMERA_PAN_RIGHT, false)

		await _push_mouse_click(vp, pause_pos, MOUSE_BUTTON_LEFT)
		assert_true(get_tree().paused, "Cycle %d: clicking || must pause SceneTree" % cycle)
		assert_true(pause_ctrl.is_paused())
		assert_true(clock.is_paused(), "Cycle %d: EconomyClockController must report paused" % cycle)
		assert_true(rig.is_input_locked(), "Cycle %d: RtsCameraRig must lock input on pause" % cycle)
		assert_true(btn_pause.is_active_state())
		assert_false(btn_resume.is_active_state())

		# Verify camera is 100% immobile under WASD, Edge Pan, Wheel Zoom, and MMB Drag while paused
		var locked_focus: Vector2 = rig.get_focus_position()
		var locked_zoom: float = rig.get_current_zoom_distance()
		var locked_world_time: float = clock.get_world_time_sec()

		_set_action_pressed(InputActions.CAMERA_PAN_UP, true)
		_push_mouse_motion(vp, Vector2(2.0, 540.0))
		await _push_mouse_wheel(vp, Vector2(960.0, 540.0), MOUSE_BUTTON_WHEEL_UP)
		var drag_press := InputEventAction.new()
		drag_press.action = InputActions.CAMERA_DRAG
		drag_press.pressed = true
		vp.push_input(drag_press, true)
		_push_mouse_motion(vp, Vector2(1060.0, 540.0), Vector2(100.0, 0.0))
		var drag_rel := InputEventAction.new()
		drag_rel.action = InputActions.CAMERA_DRAG
		drag_rel.pressed = false
		vp.push_input(drag_rel, true)

		for _i: int in range(10):
			rig.step_camera(1.0 / 60.0)
		await wait_process_frames(5)
		_set_action_pressed(InputActions.CAMERA_PAN_UP, false)

		assert_vec2_near(rig.get_focus_position(), locked_focus, 0.0001, "Camera focus must stay completely frozen during pause")
		assert_near(rig.get_current_zoom_distance(), locked_zoom, 0.0001, "Camera zoom must stay completely frozen during pause")
		assert_near(rig.get_target_zoom_distance(), locked_zoom, 0.0001, "Camera target zoom must stay frozen during pause")
		assert_near(clock.get_world_time_sec(), locked_world_time, 0.0001, "Economy clock must not advance during pause")

		# Click 1x WITH REAL MOUSE CLICK while SceneTree.paused == true!
		await _push_mouse_click(vp, resume_pos, MOUSE_BUTTON_LEFT)
		assert_false(get_tree().paused, "Cycle %d: clicking 1x while paused must resume SceneTree" % cycle)
		assert_false(pause_ctrl.is_paused())
		assert_false(clock.is_paused())
		assert_false(rig.is_input_locked())
		assert_false(btn_pause.is_active_state())
		assert_true(btn_resume.is_active_state())

		# Verify zero sudden camera jump immediately after resume
		rig.edge_pan_enabled = false
		rig.step_camera(1.0 / 60.0)
		assert_vec2_near(rig.get_focus_position(), locked_focus, 0.001, "Resuming from pause must not cause camera jump")

	await _teardown_main(main_root, vp)


func test_03_pause_during_gathering_transport_and_construction_with_provenance() -> void:
	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	add_test_child(main_root)
	await _wait_nav_ready(main_root)

	assert_true(main_root.use_provenance_economy, "Conservation test MUST run under use_provenance_economy = true")
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	rig.edge_pan_enabled = false

	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var pause_ctrl: D2SimulationPauseController = d2.get_pause_controller()
	var rocks: D2ResourceRocksView = d2.get_resource_rocks_view()
	var inv: SettlementInventory = main_root.get_settlement_inventory()
	var cm: ConstructionManager = main_root.get_construction_manager()
	var units: Array[Unit] = main_root.get_units()
	var leader_a: Unit = units[0]
	var leader_b: Unit = units[1]

	# Accelerate timings for deterministic integration speed while keeping real physics/navigation/provenance
	for src: ResourceSource in main_root.get_test_map().get_resource_sources():
		src.set_gather_cycle_timings(0.08, 0.0)
		src.felling_duration_sec = minf(src.felling_duration_sec, 0.06)

	for u: Unit in units:
		var fast_def: CharacterDefinition = u.get_definition().duplicate() as CharacterDefinition
		fast_def.move_speed = 8.0
		fast_def.work_approach_speed = 8.0
		fast_def.max_load_speed_multiplier = 1.0
		u.apply_definition(fast_def)

	# --- PHASE 1: Pause during active physical gathering & transport ---
	var wood_src: ResourceSource = null
	for src: ResourceSource in main_root.get_test_map().get_resource_sources():
		if src.get_resource_id() == &"wood":
			wood_src = src
			break
	assert_not_null(wood_src)

	main_root.get_selection_manager().select_single(leader_a)
	main_root.get_command_controller().command_at(PickResult.from_resource_source(wood_src, wood_src.global_position, Vector3.UP))

	var carrying_found: bool = false
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		if leader_a.get_carry_load().get_amount(&"wood") > 0 and inv.get_amount(&"wood") == 0:
			carrying_found = true
			break
	assert_true(carrying_found, "LeaderA must carry gathered wood before delivery")

	# Pause mid-transport via || button
	d2.get_top_plaque_view().get_pause_button().pressed.emit()
	assert_true(get_tree().paused)
	var pos_paused: Vector3 = leader_a.global_position
	var carry_paused: int = leader_a.get_carry_load().get_amount(&"wood")
	var inv_paused: int = inv.get_amount(&"wood")
	assert_true(leader_a.get_carry_load().validate_provenance(), "Provenance must be valid when paused")

	await wait_process_frames(15)
	assert_vec3_near(leader_a.global_position, pos_paused, 0.0001, "Worker must not move during pause")
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), carry_paused, "Carry load must not mutate during pause")
	assert_eq(inv.get_amount(&"wood"), inv_paused, "Inventory must not mutate during pause")

	# Resume via 1x button and wait for physical delivery
	d2.get_top_plaque_view().get_resume_button().pressed.emit()
	assert_false(get_tree().paused)

	var delivered: bool = false
	while frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		if inv.get_amount(&"wood") > 0 and leader_a.get_carry_load().is_empty():
			delivered = true
			break
	assert_true(delivered, "Worker must complete physical wood delivery after resuming from pause")
	leader_a.cancel_current_order()
	await wait_process_frames(2)

	var wood_after_gather: int = inv.get_amount(&"wood")
	assert_gt(wood_after_gather, 0)
	assert_eq(inv.get_physical_amount(&"wood"), wood_after_gather)
	assert_eq(inv.get_reserved_amount(&"wood"), 0)
	assert_eq(rocks.get_displayed_amount(&"wood"), wood_after_gather)

	# --- PHASE 2: Pause during construction material transport & assembly ---
	var build_def: BuildingDefinition = SHELTER_DEF.duplicate() as BuildingDefinition
	build_def.definition_id = &"ui_1_1b_pause_shelter"
	build_def.costs = {&"wood": 4, &"stone": 2}
	build_def.build_work_required_sec = 0.8

	assert_true(inv.deposit(&"wood", 6))
	assert_true(inv.deposit(&"stone", 4))
	var start_wood: int = inv.get_physical_amount(&"wood")
	var start_stone: int = inv.get_physical_amount(&"stone")

	var created: Dictionary = cm.try_create_site_from_placement(build_def, SITE_POS)
	assert_true(bool(created.get("ok", false)), "Construction site creation must succeed: %s" % str(created))
	var site: ConstructionSite = created["site"] as ConstructionSite
	assert_not_null(site)

	main_root.get_selection_manager().set_selection([leader_a, leader_b])
	main_root.get_command_controller().command_at(PickResult.from_construction_site(site, site.global_position, Vector3.UP))

	# Wait until active assembly begins (or materials delivered & assembly > 0 before completion)
	var saw_active_assembly: bool = false
	var c_frames: int = 0
	while c_frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		c_frames += 1
		if site.get_work_progress_sec() > 0.05 and not site.is_completed_or_completing():
			saw_active_assembly = true
			break
	assert_true(saw_active_assembly, "Construction site must reach active assembly before pausing")

	# Pause mid-assembly!
	d2.get_top_plaque_view().get_pause_button().pressed.emit()
	assert_true(get_tree().paused)
	assert_true(pause_ctrl.is_paused())
	var work_paused: float = site.get_work_progress_sec()
	var pos_a_paused: Vector3 = leader_a.global_position
	var pos_b_paused: Vector3 = leader_b.global_position

	await wait_process_frames(15)
	assert_near(site.get_work_progress_sec(), work_paused, 0.0001, "Construction assembly must NOT advance during pause")
	assert_vec3_near(leader_a.global_position, pos_a_paused, 0.0001, "Builder A must stay frozen during pause")
	assert_vec3_near(leader_b.global_position, pos_b_paused, 0.0001, "Builder B must stay frozen during pause")

	# Resume and verify completion + exact material conservation
	d2.get_top_plaque_view().get_resume_button().pressed.emit()
	assert_false(get_tree().paused)

	var completed: bool = false
	while c_frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		c_frames += 1
		if cm.get_completed_buildings().size() >= 1:
			completed = true
			break
	await wait_process_frames(3)
	assert_true(completed, "Construction must complete cleanly after resuming from pause")

	# Exact material conservation check under provenance economy
	assert_eq(inv.get_physical_amount(&"wood"), start_wood - 4, "Exact wood conservation after construction pause/resume")
	assert_eq(inv.get_physical_amount(&"stone"), start_stone - 2, "Exact stone conservation after construction pause/resume")
	assert_eq(inv.get_reserved_amount(&"wood"), 0, "Zero leftover wood reservations")
	assert_eq(inv.get_reserved_amount(&"stone"), 0, "Zero leftover stone reservations")
	assert_true(leader_a.get_carry_load().is_empty())
	assert_true(leader_b.get_carry_load().is_empty())
	assert_true(leader_a.get_carry_load().validate_provenance())
	assert_true(leader_b.get_carry_load().validate_provenance())
	assert_eq(rocks.get_displayed_amount(&"wood"), inv.get_amount(&"wood"))
	assert_eq(rocks.get_displayed_amount(&"stone"), inv.get_amount(&"stone"))

	leader_a.cancel_current_order()
	leader_b.cancel_current_order()
	var preflight: Dictionary = main_root.preflight_economic_teardown()
	assert_true(bool(preflight.get("ok", false)), "Preflight teardown must pass: %s" % str(preflight))
	var teardown: Dictionary = main_root.request_controlled_teardown()
	assert_true(bool(teardown.get("ok", false)), "Controlled teardown must succeed: %s" % str(teardown))
	await wait_process_frames(2)


func test_04_external_pause_preservation_scene_exit_and_reentry() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var pause_ctrl: D2SimulationPauseController = d2.get_pause_controller()
	var btn_resume: D2SlabButton = d2.get_top_plaque_view().get_resume_button()

	# External pause active before HUD acts
	get_tree().paused = true
	await wait_process_frames(2)
	assert_true(pause_ctrl.is_externally_paused())
	assert_true(btn_resume.disabled, "1x must be disabled under external pause")

	# Clicking 1x via real mouse click does NOT clear external pause
	var resume_pos: Vector2 = btn_resume.position + btn_resume.size * 0.5
	await _push_mouse_click(vp, resume_pos, MOUSE_BUTTON_LEFT)
	assert_true(get_tree().paused, "Clicking disabled 1x must never unpause external pause")

	# HUD also requests pause, then scene exits -> external pause MUST remain intact!
	pause_ctrl.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE)
	await _teardown_main(main_root, vp)
	assert_true(get_tree().paused, "Scene teardown during external pause must preserve external SceneTree.paused == true")

	# Clear external pause and re-enter a fresh scene -> zero leaked state
	get_tree().paused = false
	await wait_process_frames(1)

	var vp2 := SubViewport.new()
	vp2.own_world_3d = true
	vp2.size = Vector2i(1280, 720)
	vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp2)

	var main_root2: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	vp2.add_child(main_root2)
	await _wait_nav_ready(main_root2)

	var d2_2: D2HudRoot = main_root2.get_d2_hud_root()
	var pause_ctrl2: D2SimulationPauseController = d2_2.get_pause_controller()
	assert_false(pause_ctrl2.is_paused(), "Fresh scene re-entry must start unpaused with zero leaked state")
	assert_false(pause_ctrl2.is_externally_paused())

	# Pause owned by HUD -> teardown restores tree.paused = false cleanly
	pause_ctrl2.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE)
	assert_true(get_tree().paused)
	await _teardown_main(main_root2, vp2)
	assert_false(get_tree().paused, "Scene teardown while HUD owns pause must restore SceneTree.paused = false")


func test_05_escape_router_passthrough_and_legacy_mode_intact() -> void:
	# Part A: D2.2 mode Esc pass-through
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var router: D2UiEscapeRouter = d2.get_escape_router()
	var sel: SelectionManager = main_root.get_selection_manager()
	var input_ctrl: RtsInputController = main_root.get_input_controller()
	var placement: PlacementController = main_root.get_placement_controller()
	var construction_hud: ConstructionHud = main_root.get_node("UiLayer/ConstructionHud") as ConstructionHud
	var leader: Unit = main_root.get_units()[0]

	assert_not_null(router)
	assert_true(router.is_pass_through_mode(), "UI-1.1B Escape router must operate strictly in pass-through mode")

	# 1. ConstructionHud catalog open -> Esc closes ONLY catalog (does NOT clear unit selection!)
	sel.select_single(leader)
	var catalog: Control = construction_hud.get_node("Catalog") as Control
	catalog.visible = true
	await _push_escape(vp)
	assert_false(catalog.visible, "Esc must close legacy ConstructionHud catalog via ConstructionHud._input()")
	assert_eq(sel.get_selected_units().size(), 1, "Esc closing catalog must NOT double-cancel unit selection")

	# 2. Placement active -> Esc cancels ONLY placement (does NOT clear unit selection!)
	placement.start_placement(SHELTER_DEF)
	assert_true(placement.is_placement_active())
	await _push_escape(vp)
	assert_false(placement.is_placement_active(), "Esc must cancel active placement cleanly")
	assert_eq(sel.get_selected_units().size(), 1, "Esc cancelling placement must NOT double-cancel unit selection")

	# 3. Active box drag -> Esc cancels ONLY drag (does NOT clear existing selection!)
	input_ctrl._left_pressed = true
	input_ctrl._is_drag_gesture = true
	await _push_escape(vp)
	assert_false(input_ctrl.is_drag_gesture_active(), "Esc must cancel active selection drag")
	assert_eq(sel.get_selected_units().size(), 1, "Esc cancelling drag must NOT clear selection on same press")

	# 4. Normal selection -> Esc clears selection
	await _push_escape(vp)
	assert_eq(sel.get_selected_units().size(), 0, "Esc with no modal/drag/placement must clear selection")

	# 5. Paused via || -> Esc opens NO fake menu and does NOT unpause; 1x still resumes
	d2.get_top_plaque_view().get_pause_button().pressed.emit()
	assert_true(get_tree().paused)
	await _push_escape(vp)
	assert_true(get_tree().paused, "Esc during HUD pause in UI-1.1B must not open fake menu or unpause")
	d2.get_top_plaque_view().get_resume_button().pressed.emit()
	assert_false(get_tree().paused, "1x must still resume simulation cleanly")

	await _teardown_main(main_root, vp)

	# Part B: Legacy mode (main.tscn, use_d2_2_hud = false) completely untouched
	var vp_leg := SubViewport.new()
	vp_leg.own_world_3d = true
	vp_leg.size = Vector2i(1280, 720)
	vp_leg.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp_leg)

	var legacy_main: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp_leg.add_child(legacy_main)
	await _wait_nav_ready(legacy_main)

	assert_false(legacy_main.use_d2_2_hud, "Production main.tscn must keep use_d2_2_hud = false")
	assert_true(legacy_main.use_provenance_economy)
	assert_null(legacy_main.get_d2_hud_root(), "Legacy mode must not instantiate D2HudRoot")
	assert_null(legacy_main.get_node_or_null("UiLayer/D2HudRoot"))
	var leg_rig: RtsCameraRig = legacy_main.get_node("RtsCameraRig") as RtsCameraRig
	assert_false(leg_rig.is_input_locked())

	var leg_sel: SelectionManager = legacy_main.get_selection_manager()
	leg_sel.select_single(legacy_main.get_units()[0])
	await _push_escape(vp_leg)
	assert_eq(leg_sel.get_selected_units().size(), 0, "Legacy mode Esc must continue clearing selection identically")

	await _teardown_main(legacy_main, vp_leg)
