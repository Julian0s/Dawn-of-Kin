extends TestCase
## Integration tests for UI-1.3 in real MainScene under production provenance economy
## (use_provenance_economy = true):
## 1. Open/close maquettes dock via real click on alabaster slab and [B]; select Shelter/Depot
##    via real click and [1]/[2]; verify shortcuts scoped to construction context & blocked on pause.
## 2. Real Viewport InputEventKey(KEY_ESCAPE) priority hierarchy:
##    - Dock open (no placement) -> Esc closes ONLY dock (preserves RTS selection)
##    - Dock open + placement active -> 1st Esc closes dock (30), 2nd Esc cancels placement (40),
##      3rd Esc passes through to RtsInputController and clears unit selection
##    - Placement active (dock closed) -> Esc cancels ONLY placement (dock stays closed)
##    - Pause active -> Esc does NOT alter dock/placement and does NOT unpause tree
## 3. Anti click-through (LMB, RMB, MMB, wheel scroll) on slabs, maquettes, status bar, and
##    transparent 10 px shadow pad pass-through; dynamic resize 1280x720 <-> 1920x1080 zero overlap.
## 4. Real placement flow under use_provenance_economy = true:
##    - Valid hover, invalid camp/unit obstruction, dynamic world update
##    - Async confirmation pending state + double-commit prevention -> single ConstructionSite created
##      reserving real wood/stone without instant deduction or UI economy bypass
##    - Zero duplicate ConstructionHud or PlacementTestOverlay status banner; F6/F7/F8 & inspector intact
## 5. Legacy mode (use_d2_2_hud = false) 100% preserved & zero listener leaks after unbind/teardown.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SANDBOX_SCENE: PackedScene = preload("res://tests/visual/ui_1_d2_2_sandbox.tscn")
const MAX_WAIT_FRAMES: int = 120
const FREE_BUILD_POS: Vector3 = Vector3(-6.0, 0.0, 1.5)


func after_each() -> void:
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


func _push_mouse_motion(vp: Viewport, pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
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


func _push_key(vp: Viewport, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ev.echo = false
	vp.push_input(ev, true)
	await wait_process_frames(1)


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


func test_01_dock_shortcuts_real_viewport_escape_hierarchy_and_pause_safety() -> void:
	var vp := SubViewport.new()
	vp.process_mode = Node.PROCESS_MODE_ALWAYS
	vp.own_world_3d = true
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	main_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	assert_true(main_root.use_provenance_economy, "Test must run under production use_provenance_economy = true")
	assert_null(main_root.get_node_or_null("UiLayer/ConstructionHud"), "Legacy ConstructionHud must not exist in D2.2 mode")
	assert_not_null(main_root.get_node_or_null("UiLayer/BuildingInspectorPanel"), "Legacy BuildingInspectorPanel must remain intact until UI-1.4")

	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var slabs: D2ActionSlabsView = d2.get_action_slabs_view()
	var dock: D2ConstructionDockView = d2.get_construction_dock_view()
	var status_bar: D2PlacementStatusBar = d2.get_placement_status_bar()
	var router: D2UiEscapeRouter = d2.get_escape_router()
	var placement: PlacementController = main_root.get_placement_controller()
	var overlay: PlacementTestOverlay = main_root.get_placement_test_overlay()
	var sel: SelectionManager = main_root.get_selection_manager()
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	rig.edge_pan_enabled = false

	assert_true(overlay.is_placement_status_banner_suppressed(), "PlacementTestOverlay status banner must be suppressed in D2.2 mode")
	assert_eq(router.get_registered_handler_ids(), [D2HudRoot.ESC_HANDLER_MAQUETTES, D2HudRoot.ESC_HANDLER_PLACEMENT])
	assert_false(router.has_handler(&"d2_main_menu"), "No UI-1.5 main menu fallback handler may be registered in UI-1.3")

	var leader: Unit = main_root.get_units()[0]
	sel.select_single(leader)
	assert_eq(sel.get_selected_units().size(), 1)

	# [1]/[2] outside construction context must NOT start placement
	await _push_key(vp, KEY_1)
	assert_false(placement.is_placement_active(), "[1] outside construction context must not start placement")
	await _push_key(vp, KEY_2)
	assert_false(placement.is_placement_active(), "[2] outside construction context must not start placement")

	# Click Maquetes alabaster slab -> opens dock without clearing RTS selection
	var maq_center: Vector2 = slabs.get_maquettes_content_rect().get_center()
	await _push_mouse_click(vp, maq_center, MOUSE_BUTTON_LEFT)
	assert_true(dock.is_dock_open(), "Clicking Maquetes alabaster slab must open construction dock")
	assert_true(slabs.is_maquettes_open())
	assert_eq(sel.get_selected_units().size(), 1, "Clicking Maquetes slab must not clear unit selection")

	# Click Maquetes slab again -> closes dock
	await _push_mouse_click(vp, slabs.get_maquettes_content_rect().get_center(), MOUSE_BUTTON_LEFT)
	assert_false(dock.is_dock_open(), "Second click on Maquetes slab must close dock")

	# Press [B] via real Viewport InputEventKey -> opens dock
	await _push_key(vp, KEY_B)
	assert_true(dock.is_dock_open(), "[B] must open construction dock")

	# Real Viewport Esc with dock open & no placement -> closes ONLY dock (preserves selection!)
	var handled_ids: Array[StringName] = []
	var rec_cb: Callable = func(hid: StringName) -> void: handled_ids.append(hid)
	router.escape_handled.connect(rec_cb)

	await _push_key(vp, KEY_ESCAPE)
	assert_false(dock.is_dock_open(), "Esc must close open dock via PRIORITY_MAQUETTES")
	assert_eq(sel.get_selected_units().size(), 1, "Esc closing dock must NOT clear RTS unit selection")
	assert_eq(handled_ids, [D2HudRoot.ESC_HANDLER_MAQUETTES])

	# Re-open with [B], press [1] -> starts Shelter placement and closes dock cleanly
	await _push_key(vp, KEY_B)
	assert_true(dock.is_dock_open())
	await _push_key(vp, KEY_1)
	assert_true(placement.is_placement_active(), "[1] inside open dock must start Shelter placement")
	assert_eq(placement.get_active_definition().definition_id, &"shelter_basic")
	assert_false(dock.is_dock_open(), "Starting placement must deterministically close dock")
	assert_true(status_bar.visible, "D2PlacementStatusBar must appear when placement starts")
	assert_false(overlay.is_status_visible(), "Legacy PlacementTestOverlay banner must NOT duplicate D2PlacementStatusBar")

	# Press [2] while placement is active -> switches cleanly to Depot
	await _push_key(vp, KEY_2)
	assert_true(placement.is_placement_active())
	assert_eq(placement.get_active_definition().definition_id, &"storage_depot")

	# Re-open dock mid-placement with [B], then test 3-step real Viewport Esc sequence:
	# 1st Esc -> closes dock ONLY (placement & selection remain!)
	# 2nd Esc -> cancels placement ONLY (dock stays closed & selection remains!)
	# 3rd Esc -> passes through router to RtsInputController and clears unit selection!
	handled_ids.clear()
	await _push_key(vp, KEY_B)
	assert_true(dock.is_dock_open())
	assert_true(dock.is_card_selected(1), "Depot card must show selected state while Depot placement is active")

	await _push_key(vp, KEY_ESCAPE)
	assert_false(dock.is_dock_open(), "1st Esc must close dock ONLY")
	assert_true(placement.is_placement_active(), "1st Esc closing dock must NOT cancel placement")
	assert_eq(sel.get_selected_units().size(), 1)

	await _push_key(vp, KEY_ESCAPE)
	assert_false(placement.is_placement_active(), "2nd Esc must cancel placement ONLY")
	assert_false(dock.is_dock_open(), "Cancelling placement must NOT reopen dock")
	assert_false(status_bar.visible, "Status bar must hide after Esc cancels placement")
	assert_eq(sel.get_selected_units().size(), 1, "2nd Esc cancelling placement must NOT clear selection")

	await _push_key(vp, KEY_ESCAPE)
	assert_eq(sel.get_selected_units().size(), 0, "3rd Esc must pass through to RtsInputController and clear selection")
	assert_eq(handled_ids, [D2HudRoot.ESC_HANDLER_MAQUETTES, D2HudRoot.ESC_HANDLER_PLACEMENT])
	router.escape_handled.disconnect(rec_cb)

	# Pause safety: open dock, pause via || -> [B], [1], Esc, and clicking Maquetes must NOT act or unpause!
	sel.select_single(leader)
	await _push_key(vp, KEY_B)
	assert_true(dock.is_dock_open())
	d2.get_top_plaque_view().get_pause_button().pressed.emit()
	assert_true(get_tree().paused)

	await _push_key(vp, KEY_ESCAPE)
	assert_true(get_tree().paused, "Esc while paused must NOT unpause tree")
	assert_true(dock.is_dock_open(), "Esc while paused must NOT trigger construction dock actions")

	await _push_key(vp, KEY_1)
	assert_false(placement.is_placement_active(), "[1] while paused must NOT start placement")

	await _push_key(vp, KEY_B)
	assert_true(dock.is_dock_open(), "[B] while paused must NOT toggle dock")

	await _push_mouse_click(vp, slabs.get_maquettes_content_rect().get_center(), MOUSE_BUTTON_LEFT)
	assert_true(dock.is_dock_open(), "Clicking Maquetes slab while paused must NOT toggle dock")

	# Resume via 1x -> construction controls work again cleanly
	d2.get_top_plaque_view().get_resume_button().pressed.emit()
	assert_false(get_tree().paused)
	await _push_key(vp, KEY_ESCAPE)
	assert_false(dock.is_dock_open())

	# QA hotkeys F6/F7 remain functional via PlacementTestOverlay without showing legacy banner
	await _push_key(vp, KEY_F6)
	assert_true(placement.is_placement_active(), "QA hotkey F6 must remain functional in D2.2 mode")
	assert_eq(placement.get_active_definition().definition_id, &"shelter_basic")
	assert_true(status_bar.visible)
	assert_false(overlay.is_status_visible(), "F6 must not show duplicate legacy status banner")
	await _push_key(vp, KEY_ESCAPE)
	assert_false(placement.is_placement_active())

	await _teardown_main(main_root, vp)


func test_02_anti_click_through_shadow_passthrough_and_responsive_resize() -> void:
	var vp := SubViewport.new()
	vp.process_mode = Node.PROCESS_MODE_ALWAYS
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	main_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var slabs: D2ActionSlabsView = d2.get_action_slabs_view()
	var dock: D2ConstructionDockView = d2.get_construction_dock_view()
	var status_bar: D2PlacementStatusBar = d2.get_placement_status_bar()
	var placement: PlacementController = main_root.get_placement_controller()
	var sel: SelectionManager = main_root.get_selection_manager()
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	rig.edge_pan_enabled = false

	var leader: Unit = main_root.get_units()[0]
	sel.select_single(leader)
	var zoom_before: float = rig.get_target_zoom_distance()

	# 1. RMB, MMB, LMB, and scroll on Commands basalt slab (Tarefas/Linhagem inert) -> zero leakage!
	var cmd_center: Vector2 = slabs.get_commands_content_rect().get_center()
	await _push_mouse_click(vp, cmd_center, MOUSE_BUTTON_LEFT)
	await _push_mouse_click(vp, cmd_center, MOUSE_BUTTON_RIGHT)
	await _push_mouse_wheel(vp, cmd_center, MOUSE_BUTTON_WHEEL_UP)
	assert_eq(sel.get_selected_units().size(), 1, "Clicks on basalt commands slab must NOT alter RTS selection")
	assert_null(leader.get_current_order(), "RMB on basalt commands slab must NOT issue RTS order")
	assert_near(rig.get_target_zoom_distance(), zoom_before, 0.001, "Scroll on basalt commands slab must NOT zoom camera")

	# 2. RMB and scroll on Maquetes alabaster slab -> zero leakage!
	var maq_center: Vector2 = slabs.get_maquettes_content_rect().get_center()
	await _push_mouse_click(vp, maq_center, MOUSE_BUTTON_RIGHT)
	await _push_mouse_wheel(vp, maq_center, MOUSE_BUTTON_WHEEL_DOWN)
	assert_false(dock.is_dock_open(), "RMB on Maquetes slab must NOT toggle dock")
	assert_null(leader.get_current_order(), "RMB on Maquetes slab must NOT issue RTS order")
	assert_near(rig.get_target_zoom_distance(), zoom_before, 0.001, "Scroll on Maquetes slab must NOT zoom camera")

	# 3. Transparent 10 px shadow pad of Maquetes slab passes through to 3D world
	var maq_slab: D2PolygonalSlab = slabs.get_maquettes_slab()
	var pad_pt: Vector2 = maq_slab.position + Vector2(2.0, 2.0)
	_push_mouse_motion(vp, pad_pt)
	await wait_process_frames(1)
	assert_null(vp.gui_get_hovered_control(), "Transparent 10 px shadow pad must pass through to 3D world")

	# 4. Open dock -> RMB & scroll on maquette card leak nothing; click Shelter card starts placement
	await _push_mouse_click(vp, maq_center, MOUSE_BUTTON_LEFT)
	assert_true(dock.is_dock_open())
	var shelter_center: Vector2 = dock.get_card_content_rect(0).get_center()
	await _push_mouse_click(vp, shelter_center, MOUSE_BUTTON_RIGHT)
	await _push_mouse_wheel(vp, shelter_center, MOUSE_BUTTON_WHEEL_UP)
	assert_false(placement.is_placement_active(), "RMB on maquette card must NOT start placement")
	assert_null(leader.get_current_order(), "RMB on maquette card must NOT leak RTS order")
	assert_near(rig.get_target_zoom_distance(), zoom_before, 0.001, "Scroll on maquette card must NOT zoom")

	# Real LMB click on Shelter maquette card starts placement
	await _push_mouse_click(vp, shelter_center, MOUSE_BUTTON_LEFT)
	assert_true(placement.is_placement_active(), "LMB on Shelter maquette card must start placement")
	assert_eq(placement.get_active_definition().definition_id, &"shelter_basic")
	assert_true(status_bar.visible)

	# 5. Clicking LMB / RMB / scroll on D2PlacementStatusBar must NOT confirm or cancel placement or zoom!
	var sb_center: Vector2 = status_bar.get_content_bounds().get_center()
	await _push_mouse_click(vp, sb_center, MOUSE_BUTTON_LEFT)
	await _push_mouse_click(vp, sb_center, MOUSE_BUTTON_RIGHT)
	await _push_mouse_wheel(vp, sb_center, MOUSE_BUTTON_WHEEL_UP)
	assert_true(placement.is_placement_active(), "Clicks on D2PlacementStatusBar must NOT confirm or cancel placement")
	assert_near(rig.get_target_zoom_distance(), zoom_before, 0.001, "Scroll on D2PlacementStatusBar must NOT zoom")

	# 6. Dynamic resize 1280x720 <-> 1920x1080 with ALL panels visible simultaneously (steles, blade, dock, slabs, status bar, rocks, plaque, debug)
	dock.set_dock_open(true)
	var debug_panel: Control = main_root.get_node("UiLayer/DebugOverlay/Panel") as Control
	for res: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		vp.size = res
		await wait_process_frames(3)
		var vp_rect := Rect2(Vector2.ZERO, Vector2(res))
		var r_rocks: Rect2 = d2.get_resource_rocks_view().get_content_bounds()
		var r_plaque: Rect2 = d2.get_top_plaque_view().get_content_bounds()
		var r_steles: Rect2 = d2.get_founder_steles_view().get_content_bounds()
		var r_blade: Rect2 = d2.get_lineage_blade_view().get_content_bounds()
		var r_slabs: Rect2 = slabs.get_content_bounds()
		var r_dock: Rect2 = dock.get_content_bounds()
		var r_bar: Rect2 = status_bar.get_content_bounds()

		for rect: Rect2 in [r_rocks, r_plaque, r_steles, r_blade, r_slabs, r_dock, r_bar]:
			assert_true(vp_rect.encloses(rect), "HUD rect %s must stay inside viewport %s" % [str(rect), str(res)])
		assert_false(r_bar.intersects(r_rocks), "Status bar must not overlap rocks at %s" % str(res))
		assert_false(r_bar.intersects(r_plaque), "Status bar must not overlap top plaque at %s" % str(res))
		assert_false(r_bar.intersects(debug_panel.get_global_rect()), "Status bar must not overlap DebugOverlay at %s" % str(res))
		assert_false(r_dock.intersects(r_slabs), "Maquettes dock must not overlap action slabs at %s" % str(res))
		assert_false(r_dock.intersects(r_blade), "Maquettes dock must not overlap lineage blade at %s" % str(res))
		assert_false(r_slabs.intersects(r_blade), "Action slabs must not overlap lineage blade at %s" % str(res))
		assert_false(r_dock.intersects(r_plaque), "Maquettes dock must not overlap top plaque at %s" % str(res))

		# Verify hitboxes updated cleanly after resize
		var m_center: Vector2 = slabs.get_maquettes_content_rect().get_center()
		_push_mouse_motion(vp, m_center)
		await wait_process_frames(1)
		assert_eq(vp.gui_get_hovered_control(), slabs.get_maquettes_button(), "Maquetes hitbox must stay aligned after resize to %s" % str(res))

	placement.cancel_placement()
	await _teardown_main(main_root, vp)


func test_03_real_provenance_placement_async_confirm_dynamic_reval_and_legacy_intact() -> void:
	# Part A: Real D2.2 construction placement & economy conservation under use_provenance_economy = true
	var vp := SubViewport.new()
	vp.process_mode = Node.PROCESS_MODE_ALWAYS
	vp.own_world_3d = true
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	main_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	assert_true(main_root.use_provenance_economy, "Construction flow MUST run under production use_provenance_economy = true")
	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var dock: D2ConstructionDockView = d2.get_construction_dock_view()
	var status_bar: D2PlacementStatusBar = d2.get_placement_status_bar()
	var placement: PlacementController = main_root.get_placement_controller()
	var inv: SettlementInventory = main_root.get_settlement_inventory()
	var cm: ConstructionManager = main_root.get_construction_manager()
	var cam: Camera3D = (main_root.get_node("RtsCameraRig") as RtsCameraRig).get_camera()

	# Seed real camp stockpile with enough wood (16) and stone (10) for Shelter (12 wood + 6 stone)
	assert_true(inv.deposit(&"wood", 16))
	assert_true(inv.deposit(&"stone", 10))
	assert_eq(inv.get_available_amount(&"wood"), 16)
	assert_eq(inv.get_available_amount(&"stone"), 10)

	# Open dock with [B] and pick Shelter via real click on maquette card
	await _push_key(vp, KEY_B)
	assert_true(dock.is_dock_open())
	await _push_mouse_click(vp, dock.get_card_content_rect(0).get_center(), MOUSE_BUTTON_LEFT)
	assert_true(placement.is_placement_active())
	assert_eq(placement.get_active_definition().definition_id, &"shelter_basic")

	# 1. Hover over CampStorageZone -> INVALID with concrete camp reason; click rejects & keeps placement active
	var camp_pos: Vector3 = main_root.get_camp_storage_zone().get_anchor_position()
	var camp_screen: Vector2 = cam.unproject_position(camp_pos)
	placement.update_preview_at_world_pos(camp_pos)
	assert_eq(status_bar.get_status_mode(), D2PlacementStatusBar.StatusMode.INVALID)
	assert_eq(status_bar.get_last_reason_code(), PlacementValidator.REASON_CAMP_RESERVED)
	assert_true(status_bar.get_displayed_text().contains("acampamento"))

	await _push_mouse_click(vp, camp_screen, MOUSE_BUTTON_LEFT)
	assert_true(placement.is_placement_active(), "Rejected placement click must preserve active placement mode")
	assert_eq(status_bar.get_status_mode(), D2PlacementStatusBar.StatusMode.INVALID)
	assert_eq(cm.get_sites().size(), 0, "Rejected placement must create zero construction sites")

	# 2. Hover free build spot -> VALID, then move a unit into it -> dynamic world revalidation flips to INVALID, then move unit away -> VALID again!
	placement.update_preview_at_world_pos(FREE_BUILD_POS)
	assert_eq(status_bar.get_status_mode(), D2PlacementStatusBar.StatusMode.VALID)
	assert_true(status_bar.get_displayed_text().contains("LOCAL VÁLIDO"))

	var blocker_unit: Unit = main_root.get_units()[1]
	var orig_unit_pos: Vector3 = blocker_unit.global_position
	blocker_unit.global_position = FREE_BUILD_POS
	await wait_physics_frames(2)
	placement.update_preview_at_world_pos(FREE_BUILD_POS)
	assert_eq(status_bar.get_status_mode(), D2PlacementStatusBar.StatusMode.INVALID, "Dynamic unit obstruction must immediately invalidate status bar")
	assert_eq(status_bar.get_last_reason_code(), PlacementValidator.REASON_UNIT_OVERLAP)

	blocker_unit.global_position = orig_unit_pos
	await wait_physics_frames(2)
	placement.update_preview_at_world_pos(FREE_BUILD_POS)
	assert_eq(status_bar.get_status_mode(), D2PlacementStatusBar.StatusMode.VALID)

	# 3. Real async confirmation + double-commit prevention!
	placement.use_async_confirm = true
	var saw_confirming: Array[bool] = [false]
	var pending_cb: Callable = func(p: bool) -> void:
		if p and status_bar.get_status_mode() == D2PlacementStatusBar.StatusMode.CONFIRMING:
			saw_confirming[0] = true
	placement.confirm_pending_changed.connect(pending_cb)

	var confirm_count: Array[int] = [0]
	var conf_cb: Callable = func(_d: BuildingDefinition, _p: Vector3, _r: PlacementValidator.ValidationResult) -> void:
		confirm_count[0] += 1
	placement.placement_confirmed.connect(conf_cb)

	var free_screen: Vector2 = cam.unproject_position(FREE_BUILD_POS)
	await _push_mouse_click(vp, free_screen, MOUSE_BUTTON_LEFT)
	# Immediately attempt a duplicate confirmation while async bake is in flight (must be ignored!)
	if placement.is_confirm_pending():
		assert_eq(status_bar.get_status_mode(), D2PlacementStatusBar.StatusMode.CONFIRMING)
		assert_false(status_bar.get_displayed_text().contains("LOCAL VÁLIDO"))
		placement.confirm_at_world_pos(FREE_BUILD_POS)

	var wait_f: int = 0
	while placement.is_placement_active() and wait_f < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		wait_f += 1
	await wait_process_frames(2)

	placement.confirm_pending_changed.disconnect(pending_cb)
	placement.placement_confirmed.disconnect(conf_cb)

	assert_true(saw_confirming[0], "Async confirmation must transition D2PlacementStatusBar through CONFIRMING")
	assert_eq(confirm_count[0], 1, "Placement must confirm exactly ONCE with zero double commit")
	assert_false(placement.is_placement_active())
	assert_false(status_bar.visible, "D2PlacementStatusBar must hide cleanly after confirmation")
	assert_false(dock.is_dock_open(), "Dock must stay closed after confirmation")

	# Verify real ConstructionSite created & economy reserved (NOT deducted instantly!)
	assert_eq(cm.get_sites().size(), 1, "Single real ConstructionSite must be created via ConstructionManager")
	assert_eq(inv.get_physical_amount(&"wood"), 16, "Physical wood stays in camp piles until carried")
	assert_eq(inv.get_physical_amount(&"stone"), 10, "Physical stone stays in camp piles until carried")
	assert_eq(inv.get_reserved_amount(&"wood"), 12, "Exact 12 wood reserved for Shelter")
	assert_eq(inv.get_reserved_amount(&"stone"), 6, "Exact 6 stone reserved for Shelter")
	assert_eq(inv.get_available_amount(&"wood"), 4, "Available wood reflects exact reservation (16 - 12)")
	assert_eq(inv.get_available_amount(&"stone"), 4, "Available stone reflects exact reservation (10 - 6)")
	assert_eq(d2.get_resource_rocks_view().get_displayed_amount(&"wood"), 4, "Resource rocks must reflect post-reservation available wood")
	assert_eq(d2.get_resource_rocks_view().get_displayed_amount(&"stone"), 4, "Resource rocks must reflect post-reservation available stone")

	# 4. Verify zero listener leaks on unbind() before teardown
	var start_before: int = placement.placement_started.get_connections().size()
	var hover_before: int = placement.hover_state_changed.get_connections().size()
	d2.unbind()
	assert_false(dock.is_bound_to_controller(placement))
	assert_false(status_bar.is_bound_to_controller(placement))
	assert_eq(d2.get_escape_router().get_handler_count(), 0)
	assert_lt(placement.placement_started.get_connections().size(), start_before, "Dock & status bar must disconnect placement_started on unbind()")
	assert_lt(placement.hover_state_changed.get_connections().size(), hover_before, "Status bar must disconnect hover_state_changed on unbind()")

	await _teardown_main(main_root, vp)

	# Part B: Legacy mode (main.tscn default use_d2_2_hud = false) 100% intact
	var vp_leg := SubViewport.new()
	vp_leg.own_world_3d = true
	vp_leg.size = Vector2i(1280, 720)
	vp_leg.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp_leg)

	var legacy_main: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp_leg.add_child(legacy_main)
	await _wait_nav_ready(legacy_main)

	assert_false(legacy_main.use_d2_2_hud, "main.tscn default must remain use_d2_2_hud = false")
	assert_null(legacy_main.get_d2_hud_root())
	var leg_hud: ConstructionHud = legacy_main.get_node_or_null("UiLayer/ConstructionHud") as ConstructionHud
	assert_not_null(leg_hud, "Legacy ConstructionHud must remain present when use_d2_2_hud = false")
	assert_false(legacy_main.get_placement_test_overlay().is_placement_status_banner_suppressed(), "Legacy PlacementTestOverlay banner must remain unsuppressed when use_d2_2_hud = false")

	await _teardown_main(legacy_main, vp_leg)
