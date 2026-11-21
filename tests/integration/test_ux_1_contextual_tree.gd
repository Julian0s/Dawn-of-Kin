extends TestCase

const SCENE := preload("res://tests/visual/ux_1_tree.tscn")


func _click(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, false)
	await wait_process_frames(1)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		viewport.push_input(event, false)
		await wait_process_frames(1)


func _fixture() -> SubViewport:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)
	var main := SCENE.instantiate() as MainScene
	view.add_child(main)
	for i in range(120):
		if main.get_test_map().get_navigation().is_navigation_ready(): break
		await wait_physics_frames(1)
	await wait_process_frames(3)
	return view


func _exercise(person_first: bool) -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var camera := view.get_camera_3d()
	var menu := main.get_node("UiLayer/TreeWorkMenu") as TreeWorkMenu
	var tree := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var wood := tree.get_remaining_amount()
	var stock := main.get_settlement_inventory().get_physical_amount(&"wood")
	var point := camera.unproject_position(tree.global_position + Vector3.UP)
	var team := main.get_units()
	var worker: Unit
	var other: Unit
	if person_first:
		worker = team[0]
		await _click(view, camera.unproject_position(worker.global_position + Vector3.UP))
		assert_true(menu.visible, "Menu do habitante")
		await _click(view, menu.action.get_global_rect().get_center())
		assert_true(menu.choosing_target, "Escolha do alvo")
	else:
		await _click(view, point)
		assert_eq(menu.tree_source, tree)
		assert_true(menu.visible, "Menu da árvore")
		assert_eq(menu.options.get_child_count(), 2)
		if menu.workers.is_empty():
			assert_true(false, "Sem sugestão para a árvore disponível")
			return
		menu.close_menu()
		await _click(view, point)
		worker = team[1]
		for child in menu.options.get_children():
			var box := child as CheckBox
			if box.button_pressed != (box.text == worker.get_definition().display_name):
				await _click(view, box.get_global_rect().get_center())
		assert_eq(menu.workers, [worker])
	other = team[1] if worker == team[0] else team[0]
	assert_null(worker.get_current_order())
	assert_null(other.get_current_order())
	assert_eq(tree.get_remaining_amount(), wood)
	assert_eq(main.get_settlement_inventory().get_physical_amount(&"wood"), stock)
	await _click(view, point if person_first else menu.action.get_global_rect().get_center())
	var order := worker.get_current_order() as GatherResourceOrder
	assert_not_null(order, "Despacho pela interface")
	if order == null: return
	assert_eq(order.source, tree)
	assert_null(other.get_current_order())
	assert_false(menu.visible)
	Engine.time_scale = 3.0
	var carried := false
	for i in range(3600):
		if main.get_settlement_inventory().get_physical_amount(&"wood") > stock: break
		await wait_physics_frames(1)
		carried = carried or worker.get_carry_load().get_amount(&"wood") > 0
	Engine.time_scale = 1.0
	var delivered := main.get_settlement_inventory().get_physical_amount(&"wood") - stock
	assert_true(carried, "Madeira passou pela mochila")
	assert_true(delivered > 0, "Descarga física no acampamento")
	assert_eq(wood - tree.get_remaining_amount(), delivered + worker.get_carry_load().get_amount(&"wood"))
	view.queue_free()
	await wait_process_frames(2)


func test_tree_to_worker_to_deposit() -> void:
	await _exercise(false)


func test_worker_to_tree_to_deposit() -> void:
	await _exercise(true)

func test_two_workers_fill_tree_and_menu_preserves_orders() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var menu := main.get_node("UiLayer/TreeWorkMenu") as TreeWorkMenu
	var tree := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var point := view.get_camera_3d().unproject_position(tree.global_position + Vector3.UP)
	await _click(view, point)
	for child in menu.options.get_children():
		var box := child as CheckBox
		if not box.button_pressed:
			await _click(view, box.get_global_rect().get_center())
	assert_eq(menu.workers.size(), 2)
	await _click(view, menu.action.get_global_rect().get_center())
	assert_eq(tree.get_active_worker_count(), 2)
	var units := main.get_units()
	var first := units[0].get_current_order()
	var second := units[1].get_current_order()
	await _click(view, point)
	assert_true(menu.visible)
	assert_true(menu.action.disabled)
	assert_string_contains(menu.message.text, "vagas")
	assert_eq(units[0].get_current_order(), first)
	assert_eq(units[1].get_current_order(), second)
	view.queue_free()
	await wait_process_frames(2)
