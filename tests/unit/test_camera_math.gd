extends TestCase
## Unit tests for pure RTS camera math helpers in CameraMath.


func test_01_zoom_distance_clamping() -> void:
	assert_near(CameraMath.clamp_zoom_distance(36.0, 22.0, 58.0), 36.0, 0.0001)
	assert_near(CameraMath.clamp_zoom_distance(5.0, 22.0, 58.0), 22.0, 0.0001)
	assert_near(CameraMath.clamp_zoom_distance(120.0, 22.0, 58.0), 58.0, 0.0001)
	assert_near(CameraMath.clamp_zoom_distance(10.0, 58.0, 22.0), 22.0, 0.0001, "Swapped min/max must still clamp safely")


func test_02_zoom_proportional_speed() -> void:
	var speed_ref: float = CameraMath.compute_zoom_proportional_speed(24.0, 36.0, 36.0)
	var speed_near: float = CameraMath.compute_zoom_proportional_speed(24.0, 18.0, 36.0)
	var speed_far: float = CameraMath.compute_zoom_proportional_speed(24.0, 54.0, 36.0)

	assert_near(speed_ref, 24.0, 0.0001)
	assert_near(speed_near, 12.0, 0.0001)
	assert_near(speed_far, 36.0, 0.0001)
	assert_near(CameraMath.compute_zoom_proportional_speed(-5.0, 36.0, 36.0), 0.0, 0.0001)


func test_03_focus_bounds_clamping() -> void:
	var bounds: Rect2 = Rect2(-32.0, -32.0, 64.0, 64.0)
	assert_vec2_near(CameraMath.clamp_focus_to_bounds(Vector2(5.0, -10.0), bounds), Vector2(5.0, -10.0), 0.0001)
	assert_vec2_near(CameraMath.clamp_focus_to_bounds(Vector2(-80.0, 90.0), bounds), Vector2(-32.0, 32.0), 0.0001)
	assert_vec2_near(CameraMath.clamp_focus_to_bounds(Vector2(50.0, -50.0), bounds), Vector2(32.0, -32.0), 0.0001)

	var degenerate: Rect2 = Rect2(10.0, 20.0, -5.0, 0.0)
	assert_vec2_near(CameraMath.clamp_focus_to_bounds(Vector2(100.0, -100.0), degenerate), Vector2(10.0, 20.0), 0.0001)


func test_04_screen_pan_to_world_xz_at_isometric_yaw() -> void:
	var right_zero: Vector2 = CameraMath.screen_pan_to_world_xz(Vector2(1.0, 0.0), 0.0)
	var up_zero: Vector2 = CameraMath.screen_pan_to_world_xz(Vector2(0.0, 1.0), 0.0)
	assert_vec2_near(right_zero, Vector2(1.0, 0.0), 0.0001)
	assert_vec2_near(up_zero, Vector2(0.0, -1.0), 0.0001)

	var yaw_45: float = deg_to_rad(45.0)
	var right_iso: Vector2 = CameraMath.screen_pan_to_world_xz(Vector2(1.0, 0.0), yaw_45)
	var up_iso: Vector2 = CameraMath.screen_pan_to_world_xz(Vector2(0.0, 1.0), yaw_45)
	var inv_sqrt2: float = 1.0 / sqrt(2.0)

	assert_vec2_near(right_iso, Vector2(inv_sqrt2, -inv_sqrt2), 0.0001)
	assert_vec2_near(up_iso, Vector2(-inv_sqrt2, -inv_sqrt2), 0.0001)
	assert_near(right_iso.dot(up_iso), 0.0, 0.0001, "Screen right and screen up must map orthogonally on XZ")


func test_05_exponential_smoothing_stability() -> void:
	assert_near(CameraMath.compute_exp_smoothing_factor(12.0, 0.0), 0.0, 0.0001)
	assert_near(CameraMath.compute_exp_smoothing_factor(0.0, 0.016), 0.0, 0.0001)

	var f_small: float = CameraMath.compute_exp_smoothing_factor(12.0, 0.016)
	var f_large: float = CameraMath.compute_exp_smoothing_factor(12.0, 0.05)
	assert_gt(f_small, 0.0)
	assert_lt(f_small, f_large)
	assert_lt(f_large, 1.0)


func test_06_drag_screen_pan_and_edge_pan() -> void:
	var pan_near: Vector2 = CameraMath.compute_drag_screen_pan(Vector2(100.0, 50.0), 22.0, 35.0, 55.0, 1080.0)
	var pan_far: Vector2 = CameraMath.compute_drag_screen_pan(Vector2(100.0, 50.0), 44.0, 35.0, 55.0, 1080.0)
	assert_lt(pan_near.x, 0.0, "Dragging cursor right must pan focus left (grab-pan)")
	assert_gt(pan_near.y, 0.0, "Dragging cursor down must pan focus up/forward")
	assert_vec2_near(pan_far, pan_near * 2.0, 0.0001, "Drag pan must scale linearly with zoom distance")

	var viewport: Vector2 = Vector2(1920.0, 1080.0)
	assert_vec2_near(CameraMath.compute_edge_pan_direction(Vector2(960.0, 540.0), viewport, 6.0), Vector2.ZERO, 0.0001)
	assert_vec2_near(CameraMath.compute_edge_pan_direction(Vector2(-5.0, 540.0), viewport, 6.0), Vector2.ZERO, 0.0001)
	assert_vec2_near(CameraMath.compute_edge_pan_direction(Vector2(40.0, 540.0), viewport, 6.0), Vector2.ZERO, 0.0001, "30-50px from edge must not trigger pan")
	assert_vec2_near(CameraMath.compute_edge_pan_direction(Vector2(4.0, 540.0), viewport, 6.0), Vector2(-1.0, 0.0), 0.0001)
	assert_vec2_near(CameraMath.compute_edge_pan_direction(Vector2(1916.0, 4.0), viewport, 6.0), Vector2(1.0, 1.0).normalized(), 0.0001)


func test_07_camera_local_offset_and_dpi_scale() -> void:
	var offset: Vector3 = CameraMath.compute_camera_local_offset(36.0, deg_to_rad(45.0), deg_to_rad(55.0))
	assert_near(offset.length(), 36.0, 0.001)
	assert_near(offset.y, 36.0 * sin(deg_to_rad(55.0)), 0.001)
	assert_near(offset.x, offset.z, 0.001, "45 deg yaw must place camera symmetrically on +X/+Z diagonal")

	assert_near(CameraMath.get_dpi_scale(96), 1.0, 0.0001)
	assert_near(CameraMath.get_dpi_scale(192), 2.0, 0.0001)
	assert_near(CameraMath.get_dpi_scale(0), 1.0, 0.0001)
