extends TestCase

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")


func test_catalog_uses_definitions_and_controls_placement() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(viewport)
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	viewport.add_child(main)
	await wait_process_frames(3)
	var hud: ConstructionHud = main.get_node("UiLayer/ConstructionHud") as ConstructionHud
	var build: Button = hud.get_node("BuildButton") as Button
	var catalog: Control = hud.get_node("Catalog") as Control
	var shelter: Button = catalog.find_child("shelter_basic", true, false) as Button
	var depot: Button = catalog.find_child("storage_depot", true, false) as Button
	assert_false(catalog.visible)
	build.pressed.emit()
	assert_true(catalog.visible)
	assert_true(shelter.text.contains("12") and shelter.text.contains("6"))
	assert_true(depot.text.contains("18") and depot.text.contains("10"))
	build.pressed.emit()
	assert_false(catalog.visible)
	build.pressed.emit()
	shelter.pressed.emit()
	assert_false(catalog.visible)
	assert_eq(main.get_placement_controller().get_active_definition().definition_id, &"shelter_basic")
	main.get_placement_controller().cancel_placement()
	build.pressed.emit()
	depot.pressed.emit()
	assert_eq(main.get_placement_controller().get_active_definition().definition_id, &"storage_depot")
	main.get_placement_controller().cancel_placement()
	main.get_selection_manager().select_single(main.get_units()[0])
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		viewport.size = size
		await wait_process_frames(2)
		await _click(viewport, build.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
		await wait_process_frames(1)
		assert_true(catalog.visible)
		assert_true(Rect2(Vector2.ZERO, Vector2(size)).encloses(catalog.get_global_rect()))
		assert_false(catalog.get_global_rect().intersects(main.get_resource_hud().get_stockpile_panel().get_global_rect()))
		assert_false(catalog.get_global_rect().intersects(main.get_resource_hud().get_selected_unit_panel().get_global_rect()))
		await _click(viewport, build.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
		assert_false(catalog.visible)
	viewport.queue_free()
	await wait_process_frames(2)


func test_mouse_clicks_on_hud_do_not_change_selection_or_confirm() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(viewport)
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	viewport.add_child(main)
	await wait_process_frames(5)
	var leader: Unit = main.get_units()[0]
	main.get_selection_manager().select_single(leader)
	var hud: ConstructionHud = main.get_node("UiLayer/ConstructionHud") as ConstructionHud
	var build: Button = hud.get_node("BuildButton") as Button
	var catalog: Control = hud.get_node("Catalog") as Control
	await _click(viewport, build.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	assert_true(catalog.visible)
	assert_true(main.get_selection_manager().is_selected(leader))
	var shelter: Button = catalog.find_child("shelter_basic", true, false) as Button
	await _click(viewport, shelter.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	assert_true(main.get_placement_controller().is_placement_active())
	assert_true(main.get_selection_manager().is_selected(leader))
	await _click(viewport, build.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	assert_true(main.get_placement_controller().is_placement_active())
	assert_true(catalog.visible)
	assert_true(main.get_selection_manager().is_selected(leader))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape, false)
	await wait_process_frames(1)
	assert_false(catalog.visible)
	assert_true(main.get_placement_controller().is_placement_active())
	viewport.push_input(escape, false)
	await wait_process_frames(1)
	assert_false(main.get_placement_controller().is_placement_active())
	assert_true(main.get_selection_manager().is_selected(leader))
	build.pressed.emit()
	shelter.pressed.emit()
	await _click(viewport, Vector2(640, 360), MOUSE_BUTTON_RIGHT)
	assert_false(main.get_placement_controller().is_placement_active())
	assert_true(main.get_selection_manager().is_selected(leader))
	viewport.queue_free()
	await wait_process_frames(2)


func test_catalog_placement_rejects_camp_and_confirms_free_terrain() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(viewport)
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	viewport.add_child(main)
	var nav: WorldNavigation = main.get_test_map().get_navigation()
	for i: int in range(120):
		if nav.is_navigation_ready():
			break
		await wait_physics_frames(1)
	await wait_process_frames(3)
	var hud: ConstructionHud = main.get_node("UiLayer/ConstructionHud") as ConstructionHud
	var catalog: Control = hud.get_node("Catalog") as Control
	(hud.get_node("BuildButton") as Button).pressed.emit()
	(catalog.find_child("shelter_basic", true, false) as Button).pressed.emit()
	var placement: PlacementController = main.get_placement_controller()
	var counts := {"confirmed": 0, "rejected": 0}
	placement.placement_confirmed.connect(func(_def: BuildingDefinition, _pos: Vector3, _result: PlacementValidator.ValidationResult) -> void: counts.confirmed += 1)
	placement.placement_rejected.connect(func(_def: BuildingDefinition, _pos: Vector3, _result: PlacementValidator.ValidationResult) -> void: counts.rejected += 1)
	var camera: Camera3D = (main.get_node("RtsCameraRig") as RtsCameraRig).get_camera()
	await _click(viewport, camera.unproject_position(main.get_camp_storage_zone().get_anchor_position()), MOUSE_BUTTON_LEFT)
	assert_eq(counts.rejected, 1)
	assert_true(placement.is_placement_active())
	await _click(viewport, camera.unproject_position(Vector3(-6, 0, 1.5)), MOUSE_BUTTON_LEFT)
	for i: int in range(120):
		if not placement.is_placement_active():
			break
		await wait_physics_frames(1)
	assert_eq(counts.confirmed, 1)
	assert_false(placement.is_placement_active())
	viewport.queue_free()
	await wait_process_frames(2)


func _click(viewport: SubViewport, position: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, false)
	await wait_process_frames(1)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = position
		event.global_position = position
		viewport.push_input(event, false)
		await wait_process_frames(1)
