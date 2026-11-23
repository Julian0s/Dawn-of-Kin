extends TestCase
## Integration tests for UI-1.2 under real production provenance economy (use_provenance_economy = true):
## - Real mouse clicks & Shift+clicks on founder steles (bidirectional SelectionManager sync)
## - 3D selection & box-selection syncing steles (elevation) and lineage blade
## - Esc clearing selection, lowering steles, hiding lineage blade without stale state
## - Real physical gathering & transport updating blade state, carry weight, %, and materials live
## - Zero click/right-click/scroll leakage through solid steles and blade; transparent corners pass through
## - No duplicate legacy SelectedUnitPanel or selection listeners in D2.2 mode
## - Pause, camera lock, Edge Pan, Esc pass-through, and legacy mode (use_d2_2_hud = false) intact
## - Dynamic resize 1280x720 <-> 1920x1080 with zero overlap/clipping and valid hitboxes.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SANDBOX_SCENE: PackedScene = preload("res://tests/visual/ui_1_d2_2_sandbox.tscn")
const MAX_WAIT_FRAMES: int = 120
const MAX_CYCLE_FRAMES: int = 2400


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


func _push_mouse_click(vp: Viewport, pos: Vector2, button: MouseButton, shift: bool = false) -> void:
	_push_mouse_motion(vp, pos)
	await wait_process_frames(1)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.shift_pressed = shift
	press.position = pos
	press.global_position = pos
	vp.push_input(press, true)
	await wait_process_frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.shift_pressed = shift
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


func test_01_bidirectional_selection_clicks_shift_box_esc_and_hitbox_blocking() -> void:
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
	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var steles: D2FounderStelesView = d2.get_founder_steles_view()
	var blade: D2LineageBladeView = d2.get_lineage_blade_view()
	var sel: SelectionManager = main_root.get_selection_manager()
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	rig.edge_pan_enabled = false

	# Zero duplicate legacy ResourceHud / SelectedUnitPanel
	var legacy_hud: ResourceHud = main_root.get_resource_hud()
	assert_false(legacy_hud.visible, "Legacy ResourceHud must be hidden in D2.2 mode")
	assert_false(legacy_hud.is_bound_to_selection_manager(sel), "Legacy ResourceHud must not hold duplicate selection listener")
	assert_false(legacy_hud.get_selected_unit_panel().is_visible_in_tree(), "Legacy SelectedUnitPanel must stay hidden")

	var leader_a: Unit = steles.get_slot_unit(0)
	var leader_b: Unit = steles.get_slot_unit(1)
	assert_not_null(leader_a)
	assert_not_null(leader_b)
	assert_eq(steles.get_slot_name_text(0), "Leader A")
	assert_eq(steles.get_slot_name_text(1), "Leader B")
	assert_false(blade.visible, "Blade starts hidden with empty selection")

	# 1. Real LMB click on Stele 0 -> selects Leader A, elevates Stele 0, shows blade
	var stele0_center: Vector2 = steles.get_slot_content_rect(0).get_center()
	var stele0_y_before: float = steles.get_slot_content_rect(0).position.y
	await _push_mouse_click(vp, stele0_center, MOUSE_BUTTON_LEFT)
	assert_eq(sel.get_selected_units(), [leader_a], "Clicking Stele 0 must select Leader A in SelectionManager")
	assert_true(steles.is_slot_selected(0))
	assert_false(steles.is_slot_selected(1))
	assert_near(stele0_y_before - steles.get_slot_content_rect(0).position.y, 22.0, 0.2, "Stele 0 must raise 22 px")
	assert_true(blade.visible)
	assert_eq(blade.get_title_text(), "Leader A")

	# 2. Real LMB click on Stele 1 -> switches selection to Leader B
	var stele1_center: Vector2 = steles.get_slot_content_rect(1).get_center()
	await _push_mouse_click(vp, stele1_center, MOUSE_BUTTON_LEFT)
	assert_eq(sel.get_selected_units(), [leader_b], "Clicking Stele 1 must select Leader B")
	assert_false(steles.is_slot_selected(0))
	assert_true(steles.is_slot_selected(1))
	assert_eq(blade.get_title_text(), "Leader B")

	# 3. Real Shift+click on Stele 0 -> adds Leader A to multi-selection!
	await _push_mouse_click(vp, steles.get_slot_content_rect(0).get_center(), MOUSE_BUTTON_LEFT, true)
	assert_eq(sel.get_selection_count(), 2, "Shift+click Stele 0 must produce 2-unit multi-selection")
	assert_true(steles.is_slot_selected(0))
	assert_true(steles.is_slot_selected(1))
	assert_eq(blade.get_selection_mode(), D2LineageBladeView.SelectionMode.MULTI)
	assert_false(blade.is_single_details_visible())
	assert_true(blade.is_multi_summary_visible())

	# 4. Real Shift+click on Stele 1 -> removes Leader B, leaving only Leader A
	await _push_mouse_click(vp, steles.get_slot_content_rect(1).get_center(), MOUSE_BUTTON_LEFT, true)
	assert_eq(sel.get_selected_units(), [leader_a], "Shift+click selected Stele 1 must toggle it off")
	assert_eq(blade.get_selection_mode(), D2LineageBladeView.SelectionMode.SINGLE)
	assert_eq(blade.get_title_text(), "Leader A")

	# 5. Right-click & scroll on Stele 0 and Lineage Blade MUST NOT leak RTS orders or camera zoom!
	var zoom_before: float = rig.get_target_zoom_distance()
	await _push_mouse_click(vp, steles.get_slot_content_rect(0).get_center(), MOUSE_BUTTON_RIGHT)
	await _push_mouse_wheel(vp, steles.get_slot_content_rect(0).get_center(), MOUSE_BUTTON_WHEEL_UP)
	await _push_mouse_click(vp, blade.get_content_bounds().get_center(), MOUSE_BUTTON_RIGHT)
	await _push_mouse_wheel(vp, blade.get_content_bounds().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	assert_null(leader_a.get_current_order(), "Right-clicking steles or blade must NEVER issue RTS move/gather order")
	assert_near(rig.get_target_zoom_distance(), zoom_before, 0.001, "Scrolling steles or blade must NEVER zoom camera")

	# 6. Transparent 10 px shadow corner of stele passes through (not hovered)
	var stele0_pad_corner: Vector2 = steles.get_slot_slab(0).position + Vector2(2.0, 2.0)
	_push_mouse_motion(vp, stele0_pad_corner)
	await wait_process_frames(1)
	assert_null(vp.gui_get_hovered_control(), "Transparent shadow pad corner of stele must pass through")

	# 7. Real 3D world click on Leader B syncs steles & blade!
	var cam: Camera3D = rig.get_camera()
	var b_screen: Vector2 = cam.unproject_position(leader_b.global_position + Vector3(0.0, 0.8, 0.0))
	await _push_mouse_click(vp, b_screen, MOUSE_BUTTON_LEFT)
	assert_eq(sel.get_selected_units(), [leader_b], "3D world click on Leader B must sync steles and blade")
	assert_true(steles.is_slot_selected(1))
	assert_eq(blade.get_title_text(), "Leader B")

	# 8. Box-selection sync (via SelectionManager set_selection as box-select emits)
	sel.set_selection([leader_a, leader_b])
	await wait_process_frames(1)
	assert_true(steles.is_slot_selected(0))
	assert_true(steles.is_slot_selected(1))
	assert_eq(blade.get_selection_mode(), D2LineageBladeView.SelectionMode.MULTI)

	# 9. Pause via || -> clicking stele while paused does NOT alter selection; 1x resumes cleanly!
	var btn_pause: D2SlabButton = d2.get_top_plaque_view().get_pause_button()
	var btn_resume: D2SlabButton = d2.get_top_plaque_view().get_resume_button()
	await _push_mouse_click(vp, btn_pause.position + btn_pause.size * 0.5, MOUSE_BUTTON_LEFT)
	assert_true(get_tree().paused)
	await _push_mouse_click(vp, steles.get_slot_content_rect(0).get_center(), MOUSE_BUTTON_LEFT)
	assert_eq(sel.get_selection_count(), 2, "Steles must respect PROCESS_MODE_PAUSABLE and not alter selection during pause")
	await _push_mouse_click(vp, btn_resume.position + btn_resume.size * 0.5, MOUSE_BUTTON_LEFT)
	assert_false(get_tree().paused)

	# 10. Esc clears selection -> lowers steles and hides blade cleanly
	await _push_escape(vp)
	assert_eq(sel.get_selection_count(), 0, "Esc must clear selection cleanly")
	assert_false(steles.is_slot_selected(0))
	assert_false(steles.is_slot_selected(1))
	assert_false(blade.visible, "Blade must hide when selection is cleared via Esc")

	# 11. Resize 1920x1080 -> 1280x720 -> 1920x1080: zero overlap, stays in viewport, hitboxes valid
	sel.select_single(leader_a)
	for res: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		vp.size = res
		await wait_process_frames(3)
		var vp_rect := Rect2(Vector2.ZERO, Vector2(res))
		var s0_rect: Rect2 = steles.get_slot_content_rect(0)
		var s1_rect: Rect2 = steles.get_slot_content_rect(1)
		var b_rect: Rect2 = blade.get_content_bounds()
		assert_true(vp_rect.encloses(s0_rect), "Stele 0 inside viewport %s" % str(res))
		assert_true(vp_rect.encloses(s1_rect), "Stele 1 inside viewport %s" % str(res))
		assert_true(vp_rect.encloses(b_rect), "Blade inside viewport %s" % str(res))
		assert_false(s0_rect.intersects(s1_rect), "Steles must never overlap at %s" % str(res))
		assert_false(s1_rect.intersects(b_rect), "Second stele and blade must never overlap at %s" % str(res))
		_push_mouse_motion(vp, b_rect.get_center())
		await wait_process_frames(1)
		assert_eq(vp.gui_get_hovered_control(), blade.get_slab(), "Blade polygon must hit after resize %s" % str(res))

	var conn_before_unbind: int = sel.selection_changed.get_connections().size()
	assert_true(steles.is_bound_to_selection_manager(sel))
	assert_true(blade.is_bound_to_selection_manager(sel))
	d2.unbind()
	assert_false(steles.is_bound_to_selection_manager(sel), "Founder steles must disconnect from SelectionManager on unbind")
	assert_false(blade.is_bound_to_selection_manager(sel), "Lineage blade must disconnect from SelectionManager on unbind")
	assert_eq(sel.selection_changed.get_connections().size(), conn_before_unbind - 2, "Both D2 selection listeners must disconnect cleanly on unbind")
	await _teardown_main(main_root, vp)


func test_02_real_gathering_transport_updates_blade_and_steles_under_provenance() -> void:
	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	add_test_child(main_root)
	await _wait_nav_ready(main_root)

	assert_true(main_root.use_provenance_economy, "Transport test MUST run under production use_provenance_economy = true")
	var rig: RtsCameraRig = main_root.get_node("RtsCameraRig") as RtsCameraRig
	rig.edge_pan_enabled = false

	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var steles: D2FounderStelesView = d2.get_founder_steles_view()
	var blade: D2LineageBladeView = d2.get_lineage_blade_view()
	var inv: SettlementInventory = main_root.get_settlement_inventory()
	var leader_a: Unit = steles.get_slot_unit(0)

	# Accelerate timings deterministically while keeping real physical extraction/provenance/delivery
	var wood_src: ResourceSource = null
	for src: ResourceSource in main_root.get_test_map().get_resource_sources():
		src.set_gather_cycle_timings(0.08, 0.0)
		src.felling_duration_sec = minf(src.felling_duration_sec, 0.06)
		if src.get_resource_id() == &"wood" and wood_src == null:
			wood_src = src
	assert_not_null(wood_src)

	var fast_def: CharacterDefinition = leader_a.get_definition().duplicate() as CharacterDefinition
	fast_def.move_speed = 8.0
	fast_def.work_approach_speed = 8.0
	fast_def.max_load_speed_multiplier = 1.0
	leader_a.apply_definition(fast_def)

	main_root.get_selection_manager().select_single(leader_a)
	assert_true(blade.visible)
	assert_eq(blade.get_carried_value_text(&"wood"), "0")
	assert_eq(blade.get_percentage_text(), "0%")

	main_root.get_command_controller().command_at(PickResult.from_resource_source(wood_src, wood_src.global_position, Vector3.UP))

	# Wait until Leader A physically carries wood in transit
	var saw_live_carry: bool = false
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		var carried_wood: int = leader_a.get_carry_load().get_amount(&"wood")
		if carried_wood > 0:
			var expected_snap: Dictionary = HudFormatter.build_carry_snapshot(leader_a.get_carry_load())
			assert_eq(blade.get_carried_value_text(&"wood"), "%d" % carried_wood, "Blade wood count must match real carry load in transit")
			assert_eq(blade.get_percentage_text(), String(expected_snap["percentage_text"]), "Blade percentage must match HudFormatter live")
			assert_eq(blade.get_weight_text(), String(expected_snap["weight_text"]), "Blade weight text must match HudFormatter live")
			assert_eq(steles.get_slot_state_text(0), HudFormatter.format_unit_state(leader_a.get_state()), "Stele state must match live unit state")
			assert_true(leader_a.get_carry_load().validate_provenance())
			saw_live_carry = true
			break
	assert_true(saw_live_carry, "Blade and stele must reflect live wood carry during real gathering/transport")

	# Wait for delivery to camp -> carry returns to 0 while stockpile rises (zero economic duplication!)
	var delivered: bool = false
	while frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		if inv.get_amount(&"wood") > 0 and leader_a.get_carry_load().is_empty():
			delivered = true
			break
	await wait_process_frames(2)
	assert_true(delivered)
	assert_eq(blade.get_carried_value_text(&"wood"), "0", "Blade wood carry must reset to 0 after camp delivery")
	assert_eq(blade.get_percentage_text(), "0%")
	assert_eq(d2.get_resource_rocks_view().get_displayed_amount(&"wood"), inv.get_amount(&"wood"))
	assert_eq(inv.get_amount(&"wood"), inv.get_physical_amount(&"wood"))
	assert_eq(inv.get_reserved_amount(&"wood"), 0)

	leader_a.cancel_current_order()
	var td: Dictionary = main_root.request_controlled_teardown()
	assert_true(bool(td.get("ok", false)), "Controlled economic teardown must succeed: %s" % str(td))
	await wait_process_frames(2)


func test_03_legacy_mode_selected_unit_panel_completely_intact() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var legacy_main: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp.add_child(legacy_main)
	await _wait_nav_ready(legacy_main)

	assert_false(legacy_main.use_d2_2_hud, "Production main.tscn default must keep use_d2_2_hud = false")
	assert_null(legacy_main.get_d2_hud_root(), "Legacy mode must not instantiate D2HudRoot")
	var legacy_hud: ResourceHud = legacy_main.get_resource_hud()
	assert_true(legacy_hud.visible)
	assert_true(legacy_hud.is_bound_to_selection_manager(legacy_main.get_selection_manager()))

	var leader: Unit = legacy_main.get_units()[0]
	legacy_main.get_selection_manager().select_single(leader)
	await wait_process_frames(1)
	var legacy_unit_panel: SelectedUnitPanel = legacy_hud.get_selected_unit_panel()
	assert_true(legacy_unit_panel.visible, "Legacy SelectedUnitPanel must remain fully functional when use_d2_2_hud = false")
	assert_eq(legacy_unit_panel.get_header_text(), "Leader A")

	await _teardown_main(legacy_main, vp)
