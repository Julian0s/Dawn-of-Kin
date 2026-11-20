extends TestCase

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const SITE_A := Vector3(-6.0, 0.0, 1.5)
const SITE_B := Vector3(0.37, 0.0, -13.19)


func _fixture(use_provenance: bool = true) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(viewport)
	var main := MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = use_provenance
	viewport.add_child(main)
	var nav := main.get_test_map().get_navigation()
	for i: int in range(120):
		if nav.is_navigation_ready(): break
		await wait_physics_frames(1)
	await wait_process_frames(2)
	return {"vp": viewport, "main": main, "ui": main.get_node("UiLayer/BuildingInspectorPanel") as BuildingInspectorPanel}


func test_site_selection_refresh_and_layout() -> void:
	var ctx: Dictionary = await _fixture()
	var main: MainScene = ctx.main
	var ui: BuildingInspectorPanel = ctx.ui
	var inventory := main.get_settlement_inventory()
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var result := main.get_construction_manager().try_create_site_from_placement(SHELTER, SITE_A)
	assert_true(result.ok)
	var site: ConstructionSite = result.site
	await wait_process_frames(2)
	assert_false(ui._panel.visible)
	var camera: Camera3D = (main.get_node("RtsCameraRig") as RtsCameraRig).get_camera()
	await _click(ctx.vp, camera.unproject_position(site.global_position + Vector3(0, 0.35, 0)))
	assert_true(ui._panel.visible)
	assert_false(main.get_placement_test_overlay().is_site_panel_visible())
	var legacy := PlacementTestOverlay.new()
	(ctx.vp as SubViewport).add_child(legacy)
	legacy.configure(main.get_placement_controller(), SHELTER, SHELTER)
	legacy.set_inspected_site(site)
	assert_true(legacy.is_site_panel_visible())
	legacy.queue_free()
	assert_eq(ui._progress.value, 0.0)
	assert_string_contains(ui._materials.text, "12")
	assert_false(ui._complement.visible)
	assert_string_contains(ui._workers.text, "Nenhum")
	main.get_selection_manager().select_single(main.get_units()[0])
	assert_false(ui._panel.visible)
	main.get_input_controller().construction_site_picked.emit(site)
	assert_true(ui._panel.visible)
	var unit: Unit = main.get_units()[0]
	await _click(ctx.vp, ui._panel.get_global_rect().position + Vector2(5, 5))
	assert_true(main.get_selection_manager().is_selected(unit))
	assert_null(unit.get_current_order())
	assert_eq(ui._site, site)
	var f8 := InputEventKey.new()
	f8.keycode = KEY_F8
	f8.physical_keycode = KEY_F8
	f8.pressed = true
	(ctx.vp as SubViewport).push_input(f8, false)
	await wait_process_frames(1)
	var overlay := main.get_placement_test_overlay()
	assert_true((overlay.get_node("TemporaryPlacementBar") as Control).visible)
	assert_false(overlay.get_shelter_button().visible)
	assert_false(overlay.get_depot_button().visible)
	(ctx.vp as SubViewport).push_input(f8, false)
	await wait_process_frames(1)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		(ctx.vp as SubViewport).size = size
		await wait_process_frames(2)
		assert_true(Rect2(Vector2.ZERO, Vector2(size)).encloses(ui._panel.get_global_rect()))
		assert_false(ui._panel.get_global_rect().intersects(main.get_resource_hud().get_stockpile_panel().get_global_rect()))
	main.get_input_controller().construction_site_picked.emit(null)
	assert_false(ui._panel.visible)
	(ctx.vp as SubViewport).queue_free()
	await wait_process_frames(2)


func test_decay_explicit_confirmation_and_conservation() -> void:
	var ctx: Dictionary = await _fixture(false)
	var main: MainScene = ctx.main
	var ui: BuildingInspectorPanel = ctx.ui
	var manager := main.get_ground_pile_manager()
	var inventory := main.get_settlement_inventory()
	var slots := main.get_camp_storage_zone().get_candidate_slots()
	var wood: GroundResourcePile = manager.try_create_pile_at(&"wood", 12, slots[0])
	assert_not_null(wood)
	assert_not_null(manager.try_create_pile_at(&"stone", 12, slots[1]))
	var first := main.get_construction_manager().try_create_site_from_placement(SHELTER, SITE_A)
	assert_true(first.ok)
	var site: ConstructionSite = first.site
	wood.apply_state(12, 420.0, 0.0)
	main.get_time_provider().advance(1200.0)
	var losses := manager.step_decay()
	assert_eq(int(losses.get(&"wood", 0)), 10)
	assert_eq(int(losses.get(&"stone", 0)), 0)
	assert_eq(site.get_missing_amount(&"wood"), 10)
	ui.set_site(site)
	await wait_process_frames(2)
	assert_true(ui._complement.visible)
	await _click(ctx.vp, ui._complement.get_global_rect().get_center())
	assert_true(ui._confirm.disabled)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 2)
	ui._cancel.pressed.emit()
	assert_not_null(manager.try_create_pile_at(&"wood", 24, slots[2]))
	var second := main.get_construction_manager().try_create_site_from_placement(SHELTER, SITE_B)
	assert_true(second.ok)
	var other: ConstructionSite = second.site
	assert_eq(other.get_reserved_in_piles_amount(&"wood"), 12)
	ui.set_site(site)
	await wait_process_frames(2)
	await _click(ctx.vp, ui._complement.get_global_rect().get_center())
	assert_false(ui._confirm.disabled)
	assert_string_contains(ui._plan.text, "faltam 10")
	assert_string_contains(ui._plan.text, "livres 12")
	ui.set_site(other)
	ui._confirm.pressed.emit()
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 2)
	ui.set_site(site)
	await wait_process_frames(2)
	await _click(ctx.vp, ui._complement.get_global_rect().get_center())
	var buffer_before := site.get_delivered_buffer_amounts()
	var consumed_before := site.get_consumed_amounts()
	var progress_before := site.get_progress_ratio()
	await _click(ctx.vp, ui._confirm.get_global_rect().get_center())
	ui._confirm.pressed.emit()
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)
	assert_eq(other.get_reserved_in_piles_amount(&"wood"), 12)
	assert_eq(site.get_delivered_buffer_amounts(), buffer_before)
	assert_eq(site.get_consumed_amounts(), consumed_before)
	assert_eq(site.get_progress_ratio(), progress_before)
	assert_true(site.verify_accounting_invariant())
	assert_true(other.verify_accounting_invariant())
	var completed: Array[Dictionary] = []
	site.site_completed.connect(func(done: ConstructionSite, _building: BuildingInstance) -> void:
		completed.append({"consumed": done.get_consumed_amounts(), "buffer": done.get_delivered_buffer_amounts(), "valid": done.verify_accounting_invariant()})
	)
	var worker: Unit = main.get_units()[0]
	var order := ConstructOrder.new(site, main.get_camp_storage_zone())
	worker.issue_order(order)
	Engine.time_scale = 3.0
	var saw_buffer := false
	var saw_progress := false
	var saw_worker := false
	for i: int in range(3600):
		if not completed.is_empty(): break
		await wait_physics_frames(1)
		if is_instance_valid(site):
			saw_buffer = saw_buffer or site.get_delivered_buffer_amount(&"wood") > 0
			saw_progress = saw_progress or ui._progress.value > 0.0
			saw_worker = saw_worker or ui._workers.text.contains("Construtor") or ui._workers.text.contains("Supridor")
	Engine.time_scale = 1.0
	assert_eq(completed.size(), 1)
	assert_true(saw_buffer)
	assert_true(saw_progress)
	assert_true(saw_worker)
	if not completed.is_empty():
		assert_eq(completed[0].consumed, {&"wood": 12, &"stone": 6})
		assert_eq(completed[0].buffer, {&"wood": 0, &"stone": 0})
		assert_true(completed[0].valid)
	assert_eq(other.get_reserved_in_piles_amount(&"wood"), 12)
	await wait_process_frames(2)
	assert_false(ui._panel.visible)
	(ctx.vp as SubViewport).queue_free()
	await wait_process_frames(2)


func test_removed_site_cannot_confirm_pending_reservation() -> void:
	var ctx: Dictionary = await _fixture()
	var main: MainScene = ctx.main
	var ui: BuildingInspectorPanel = ctx.ui
	var piles := main.get_ground_pile_manager()
	var inventory := main.get_settlement_inventory()
	var slots := main.get_camp_storage_zone().get_candidate_slots()
	var wood: GroundResourcePile = piles.try_create_pile_at(&"wood", 12, slots[0])
	assert_not_null(wood)
	assert_not_null(piles.try_create_pile_at(&"stone", 6, slots[1]))
	var result := main.get_construction_manager().try_create_site_from_placement(SHELTER, SITE_A)
	assert_true(result.ok)
	var site: ConstructionSite = result.site
	wood.apply_state(12, 420.0, 0.0)
	main.get_time_provider().advance(1200.0)
	piles.step_decay()
	assert_not_null(piles.try_create_pile_at(&"wood", 10, slots[2]))
	ui.set_site(site)
	await wait_process_frames(2)
	ui._complement.pressed.emit()
	assert_false(ui._confirm.disabled)
	var available_before := inventory.get_available_amount(&"wood")
	site.queue_free()
	ui._confirm.pressed.emit()
	assert_eq(inventory.get_available_amount(&"wood"), available_before)
	await wait_process_frames(2)
	assert_false(ui._panel.visible)
	ui._confirm.pressed.emit()
	assert_eq(inventory.get_available_amount(&"wood"), available_before)
	(ctx.vp as SubViewport).queue_free()
	await wait_process_frames(2)


func _click(viewport: SubViewport, position: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = position
	move.global_position = position
	viewport.push_input(move, false)
	await wait_process_frames(1)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		viewport.push_input(event, false)
		await wait_process_frames(1)
