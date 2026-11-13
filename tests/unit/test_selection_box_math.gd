extends TestCase
## Unit tests for pure screen-space SelectionBoxMath geometry and camera projection helpers.

const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")


func test_01_normalize_rect_handles_all_four_drag_directions() -> void:
	var expected := Rect2(100.0, 200.0, 300.0, 150.0)

	# Top-left -> Bottom-right
	assert_eq(SelectionBoxMath.normalize_rect(Vector2(100.0, 200.0), Vector2(400.0, 350.0)), expected)
	# Bottom-right -> Top-left
	assert_eq(SelectionBoxMath.normalize_rect(Vector2(400.0, 350.0), Vector2(100.0, 200.0)), expected)
	# Top-right -> Bottom-left
	assert_eq(SelectionBoxMath.normalize_rect(Vector2(400.0, 200.0), Vector2(100.0, 350.0)), expected)
	# Bottom-left -> Top-right
	assert_eq(SelectionBoxMath.normalize_rect(Vector2(100.0, 350.0), Vector2(400.0, 200.0)), expected)

	var degenerate: Rect2 = SelectionBoxMath.normalize_rect(Vector2(50.0, 60.0), Vector2(50.0, 60.0))
	assert_vec2_near(degenerate.position, Vector2(50.0, 60.0), 0.0001)
	assert_vec2_near(degenerate.size, Vector2.ZERO, 0.0001)


func test_02_point_in_box_viewport_and_radius_rules() -> void:
	var box := Rect2(100.0, 100.0, 200.0, 150.0)
	var viewport_rect := Rect2(0.0, 0.0, 1280.0, 720.0)

	assert_true(SelectionBoxMath.is_point_in_box(Vector2(150.0, 150.0), box, viewport_rect))
	assert_false(SelectionBoxMath.is_point_in_box(Vector2(90.0, 150.0), box, viewport_rect))
	assert_true(SelectionBoxMath.is_point_in_box(Vector2(90.0, 150.0), box, viewport_rect, 12.0))
	assert_false(SelectionBoxMath.is_point_in_box(Vector2(-10.0, 150.0), Rect2(-50.0, 100.0, 200.0, 100.0), viewport_rect), "Points outside viewport must be rejected")
	assert_false(SelectionBoxMath.is_point_in_box(Vector2(INF, 100.0), box, viewport_rect))


func test_03_projection_inclusion_behind_camera_and_zoom_levels() -> void:
	var container := Node3D.new()
	add_test_child(container)

	var camera := Camera3D.new()
	camera.fov = 35.0
	camera.position = Vector3(0.0, 20.0, 20.0)
	container.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.make_current()

	var unit_front: Unit = UNIT_SCENE.instantiate() as Unit
	unit_front.position = Vector3(0.0, 0.0, 0.0)
	container.add_child(unit_front)

	var unit_side: Unit = UNIT_SCENE.instantiate() as Unit
	unit_side.position = Vector3(12.0, 0.0, 0.0)
	container.add_child(unit_side)

	var unit_behind: Unit = UNIT_SCENE.instantiate() as Unit
	unit_behind.position = Vector3(0.0, 25.0, 35.0)
	container.add_child(unit_behind)

	await wait_process_frames(2)

	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var front_screen: Vector2 = camera.unproject_position(SelectionBoxMath.get_unit_world_anchor(unit_front))
	var tight_box := Rect2(front_screen - Vector2(30.0, 30.0), Vector2(60.0, 60.0))

	var collected: Array[Unit] = SelectionBoxMath.collect_units_in_box(
		camera,
		[unit_front, unit_side, unit_behind, unit_front, null],
		tight_box,
		viewport_rect
	)
	assert_eq(collected.size(), 1)
	assert_true(collected.has(unit_front))
	assert_false(collected.has(unit_side))
	assert_false(collected.has(unit_behind), "Unit behind camera must never be selected")

	# Even a giant full-viewport box must still exclude units behind the camera.
	var full_screen_collected: Array[Unit] = SelectionBoxMath.collect_units_in_box(
		camera,
		[unit_front, unit_behind],
		viewport_rect,
		viewport_rect
	)
	assert_eq(full_screen_collected.size(), 1)
	assert_true(full_screen_collected.has(unit_front))

	# Pull camera back (far zoom) and verify unit_front remains selectable via updated projection.
	camera.position = Vector3(0.0, 40.0, 40.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	await wait_process_frames(1)

	var far_screen: Vector2 = camera.unproject_position(SelectionBoxMath.get_unit_world_anchor(unit_front))
	var far_box: Rect2 = SelectionBoxMath.normalize_rect(far_screen + Vector2(20.0, 20.0), far_screen - Vector2(20.0, 20.0))
	assert_true(SelectionBoxMath.is_unit_in_box(camera, unit_front, far_box, viewport_rect))
