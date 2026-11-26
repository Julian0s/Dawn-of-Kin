extends TestCase
## Integration tests A01-01 to A01-12 for D4-A01:
## Event-driven top-center avoidance between AutonomousGatherFeedback and
## PlacementTestOverlay's PlacementStatusBanner on the real MainScene.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")


func _fixture(resolution: Vector2i = Vector2i(1280, 720)) -> SubViewport:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = resolution
	add_test_child(view)
	var main := MAIN_SCENE.instantiate() as MainScene
	view.add_child(main)
	for _i: int in range(120):
		if main.get_test_map().get_navigation().is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(main.get_test_map().get_navigation().is_navigation_ready(), "Fixture: WorldNavigation ready")
	var rig := main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false
	# Warm up placement preview so shader compile does not stall later assertions
	var ov := main.get_placement_test_overlay()
	ov.get_shelter_button().pressed.emit()
	await wait_process_frames(2)
	ov.get_cancel_button().pressed.emit()
	await wait_process_frames(1)
	var banner := ov.get_status_banner_control()
	if banner != null:
		banner.visible = false
	ov.set_process(false)
	await wait_process_frames(2)
	return view


func _teardown_fixture(view: SubViewport) -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(view):
		view.queue_free()
	await wait_process_frames(2)


func _assert_no_overlap(a: Control, b: Control, min_vertical_gap: float, label: String) -> void:
	assert_not_null(a, "%s: control A missing" % label)
	assert_not_null(b, "%s: control B missing" % label)
	assert_true(a.is_visible_in_tree(), "%s: control A must be visible" % label)
	assert_true(b.is_visible_in_tree(), "%s: control B must be visible" % label)
	var ra: Rect2 = a.get_global_rect()
	var rb: Rect2 = b.get_global_rect()
	var inter: Rect2 = ra.intersection(rb)
	var overlaps: bool = inter.size.x > 0.0 and inter.size.y > 0.0
	assert_false(overlaps, "%s: rects overlap! A=%s B=%s inter=%s" % [label, str(ra), str(rb), str(inter)])
	if min_vertical_gap > 0.0 and ra.end.x > rb.position.x and ra.position.x < rb.end.x:
		var below_gap: float = ra.position.y - rb.end.y
		var above_gap: float = rb.position.y - ra.end.y
		assert_true(
			below_gap >= min_vertical_gap - 0.5 or above_gap >= min_vertical_gap - 0.5,
			"%s: insufficient vertical separation! A=%s B=%s" % [label, str(ra), str(rb)]
		)


func _assert_gather_no_polling(fb: AutonomousGatherFeedback, label: String) -> void:
	assert_false(fb.is_processing(), "%s: AutonomousGatherFeedback must have zero _process polling" % label)
	assert_false(fb.is_physics_processing(), "%s: AutonomousGatherFeedback must have zero _physics_process polling" % label)


func test_a01_01_gather_then_placement_1280x720() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	fb.show_message("Corte de madeira concluído.")
	ov.get_shelter_button().pressed.emit()
	await wait_process_frames(2)

	_assert_no_overlap(fb, banner, 8.0, "A01-01 720p gather->placement")
	_assert_gather_no_polling(fb, "A01-01")
	ov.get_cancel_button().pressed.emit()
	await _teardown_fixture(view)


func test_a01_02_gather_then_placement_1920x1080() -> void:
	var view := await _fixture(Vector2i(1920, 1080))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	fb.show_message("Corte de madeira concluído.")
	ov.get_shelter_button().pressed.emit()
	await wait_process_frames(2)

	_assert_no_overlap(fb, banner, 8.0, "A01-02 1080p gather->placement")
	_assert_gather_no_polling(fb, "A01-02")
	ov.get_cancel_button().pressed.emit()
	await _teardown_fixture(view)


func test_a01_03_placement_active_then_gather_1280x720() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	ov.get_shelter_button().pressed.emit()
	ov._on_hover_state_changed(false, "Posição inválida: área intercepta recurso natural.", Vector3.ZERO)
	await wait_process_frames(1)
	fb.show_message("Aguardando trabalhador disponível.")
	await wait_process_frames(2)

	_assert_no_overlap(fb, banner, 8.0, "A01-03 720p placement->gather")
	_assert_gather_no_polling(fb, "A01-03")
	ov.get_cancel_button().pressed.emit()
	await _teardown_fixture(view)


func test_a01_04_placement_active_then_gather_1920x1080() -> void:
	var view := await _fixture(Vector2i(1920, 1080))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	ov.get_shelter_button().pressed.emit()
	ov._on_hover_state_changed(false, "Posição inválida: área intercepta recurso natural.", Vector3.ZERO)
	await wait_process_frames(1)
	fb.show_message("Aguardando trabalhador disponível.")
	await wait_process_frames(2)

	_assert_no_overlap(fb, banner, 8.0, "A01-04 1080p placement->gather")
	_assert_gather_no_polling(fb, "A01-04")
	ov.get_cancel_button().pressed.emit()
	await _teardown_fixture(view)


func test_a01_05_placement_cancelled_restores_gather_top_offset() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	ov.get_shelter_button().pressed.emit()
	await wait_process_frames(1)
	fb.show_message("Corte autorizado em lote.")
	await wait_process_frames(2)
	assert_gt(fb.get_top_offset(), AutonomousGatherFeedback.BASE_TOP_OFFSET + 20.0, "A01-05: feedback must shift down while banner visible")

	ov.get_cancel_button().pressed.emit()
	await wait_process_frames(2)
	assert_false(banner.is_visible_in_tree(), "A01-05: placement banner must hide after cancel")
	assert_near(fb.get_top_offset(), AutonomousGatherFeedback.BASE_TOP_OFFSET, 0.5, "A01-05: feedback must restore BASE_TOP_OFFSET after banner hides")
	_assert_gather_no_polling(fb, "A01-05")
	await _teardown_fixture(view)


func test_a01_06_placement_suppressed_restores_gather_top_offset() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	ov.get_shelter_button().pressed.emit()
	await wait_process_frames(1)
	fb.show_message("Coleta comunitária iniciada.")
	await wait_process_frames(2)
	_assert_no_overlap(fb, banner, 8.0, "A01-06 before suppress")

	ov.set_placement_status_banner_suppressed(true)
	await wait_process_frames(2)
	assert_false(banner.is_visible_in_tree(), "A01-06: suppressed banner hidden")
	assert_near(fb.get_top_offset(), AutonomousGatherFeedback.BASE_TOP_OFFSET, 0.5, "A01-06: suppression restores BASE_TOP_OFFSET")
	ov.get_cancel_button().pressed.emit()
	await _teardown_fixture(view)


func test_a01_07_toast_rejection_and_gather_no_overlap() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	ov._on_site_creation_rejected("blocked", "Espaço insuficiente para canteiro.", MainScene.SHELTER_BASIC_DEFINITION, Vector3.ZERO)
	await wait_process_frames(1)
	fb.show_message("Nenhuma árvore autorizada.")
	await wait_process_frames(2)
	_assert_no_overlap(fb, banner, 8.0, "A01-07 toast + gather")

	# Simulate toast expiration cleanly
	ov._toast_remaining_sec = 0.01
	await wait_physics_frames(2)
	await wait_process_frames(3)
	if not banner.is_visible_in_tree():
		assert_near(fb.get_top_offset(), AutonomousGatherFeedback.BASE_TOP_OFFSET, 0.5, "A01-07: toast expiry restores BASE_TOP_OFFSET")
	await _teardown_fixture(view)


func test_a01_08_viewport_resize_720p_to_1080p_preserves_clearance() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	ov.get_shelter_button().pressed.emit()
	fb.show_message("Coleta de pedra autorizada.")
	await wait_process_frames(2)
	_assert_no_overlap(fb, banner, 8.0, "A01-08 initial 720p")

	view.size = Vector2i(1920, 1080)
	await wait_process_frames(3)
	_assert_no_overlap(fb, banner, 8.0, "A01-08 resized 1080p")
	var fb_center_x: float = fb.get_global_rect().position.x + fb.get_global_rect().size.x * 0.5
	assert_near(fb_center_x, 960.0, 2.0, "A01-08: centered horizontally in 1920px viewport")

	ov.get_cancel_button().pressed.emit()
	await _teardown_fixture(view)


func test_a01_09_no_secondary_overlap_with_debug_overlay_and_resource_hud() -> void:
	for res: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var view := await _fixture(res)
		var main := view.get_child(0) as MainScene
		var fb := main.get_autonomous_gather_feedback()
		var ov := main.get_placement_test_overlay()
		var banner := ov.get_status_banner_control()
		var debug_panel := main.get_node_or_null("UiLayer/DebugOverlay/Panel") as Control
		var resource_panel: Control = main.get_resource_hud().get_stockpile_panel() if main.get_resource_hud() != null else null

		if debug_panel != null:
			debug_panel.visible = true
		ov.get_shelter_button().pressed.emit()
		fb.show_message("Aguardando trabalhador disponível.")
		await wait_process_frames(2)

		var tag := "A01-09 (%dx%d)" % [res.x, res.y]
		_assert_no_overlap(fb, banner, 8.0, tag + " vs banner")
		if debug_panel != null and debug_panel.is_visible_in_tree():
			_assert_no_overlap(fb, debug_panel, 0.0, tag + " vs DebugOverlay")
		if resource_panel != null and resource_panel.is_visible_in_tree() and resource_panel.get_global_rect().size.x > 0.0:
			_assert_no_overlap(fb, resource_panel, 0.0, tag + " vs ResourceHud")

		ov.get_cancel_button().pressed.emit()
		await _teardown_fixture(view)


func test_a01_10_placement_status_text_growth_keeps_clearance() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	ov.get_shelter_button().pressed.emit()
	fb.show_message("Corte autorizado.")
	await wait_process_frames(2)
	_assert_no_overlap(fb, banner, 8.0, "A01-10 before growth")

	ov._on_hover_state_changed(
		false,
		"Posição inválida: área intercepta recurso natural próximo ao acampamento.\nAjuste para terreno livre.",
		Vector3.ZERO
	)
	await wait_process_frames(3)
	_assert_no_overlap(fb, banner, 8.0, "A01-10 after multi-line growth")
	ov.get_cancel_button().pressed.emit()
	await _teardown_fixture(view)


func test_a01_11_auto_hide_timer_hides_feedback_without_polling() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	_assert_gather_no_polling(fb, "A01-11 initial")

	fb.show_message("Coleta concluída.")
	await wait_process_frames(1)
	assert_true(fb.visible, "A01-11: visible right after show_message")
	assert_near(fb._hide_timer.wait_time, AutonomousGatherFeedback.AUTO_HIDE_SEC, 0.001, "A01-11: default timer 3.0s")
	assert_false(fb._hide_timer.is_stopped(), "A01-11: one-shot timer started")
	_assert_gather_no_polling(fb, "A01-11 visible")

	fb._hide_timer.start(0.05)
	await get_tree().create_timer(0.12).timeout
	await wait_process_frames(1)
	assert_false(fb.visible, "A01-11: hidden after one-shot timer expiry")
	_assert_gather_no_polling(fb, "A01-11 after hide")
	await _teardown_fixture(view)


func test_a01_12_freed_avoidance_target_unbinds_cleanly() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var fb := main.get_autonomous_gather_feedback()
	var ov := main.get_placement_test_overlay()
	var banner := ov.get_status_banner_control()

	ov.get_shelter_button().pressed.emit()
	fb.show_message("Madeira em coleta.")
	await wait_process_frames(2)
	assert_gt(fb.get_top_offset(), AutonomousGatherFeedback.BASE_TOP_OFFSET + 20.0, "A01-12: shifted while banner active")

	ov.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(banner), "A01-12: target freed cleanly")
	assert_near(fb.get_top_offset(), AutonomousGatherFeedback.BASE_TOP_OFFSET, 0.5, "A01-12: freeing target restores BASE_TOP_OFFSET")
	_assert_gather_no_polling(fb, "A01-12")
	await _teardown_fixture(view)
