class_name CameraMath
extends RefCounted
## Pure mathematical helpers for isometric RTS camera positioning,
## zoom clamping, bounds clamping, exponential smoothing, and drag/edge panning.

const DEFAULT_DPI: float = 96.0
const MIN_PITCH_SIN: float = 0.25


static func get_dpi_scale(dpi: int) -> float:
	if dpi <= 0:
		return 1.0
	return maxf(float(dpi) / DEFAULT_DPI, 1.0)


static func clamp_zoom_distance(distance: float, min_distance: float, max_distance: float) -> float:
	var low: float = minf(min_distance, max_distance)
	var high: float = maxf(min_distance, max_distance)
	return clampf(distance, low, high)


static func compute_zoom_proportional_speed(
	base_speed: float,
	current_distance: float,
	reference_distance: float
) -> float:
	var safe_ref: float = maxf(reference_distance, 0.001)
	var safe_dist: float = maxf(current_distance, 0.0)
	return maxf(base_speed, 0.0) * (safe_dist / safe_ref)


static func clamp_focus_to_bounds(focus_xz: Vector2, bounds: Rect2) -> Vector2:
	var min_x: float = bounds.position.x
	var max_x: float = bounds.position.x + maxf(bounds.size.x, 0.0)
	var min_z: float = bounds.position.y
	var max_z: float = bounds.position.y + maxf(bounds.size.y, 0.0)
	return Vector2(clampf(focus_xz.x, min_x, max_x), clampf(focus_xz.y, min_z, max_z))


## Converts a screen-aligned pan direction (+x = right, +y = up on screen)
## into a world XZ plane direction vector for a Y-axis yaw rotation in radians.
static func screen_pan_to_world_xz(screen_pan: Vector2, yaw_radians: float) -> Vector2:
	var cos_y: float = cos(yaw_radians)
	var sin_y: float = sin(yaw_radians)
	var world_right: Vector2 = Vector2(cos_y, -sin_y)
	var world_forward: Vector2 = Vector2(-sin_y, -cos_y)
	return world_right * screen_pan.x + world_forward * screen_pan.y


static func compute_exp_smoothing_factor(rate: float, delta: float) -> float:
	if rate <= 0.0 or delta <= 0.0:
		return 0.0
	return 1.0 - exp(-rate * delta)


## Converts screen-space drag motion (+x = right, +y = down) into ground-grab
## screen-pan displacement (+x = pan right, +y = pan up/forward on screen).
static func compute_drag_screen_pan(
	screen_delta: Vector2,
	distance: float,
	fov_degrees: float,
	pitch_degrees: float,
	viewport_height: float
) -> Vector2:
	var safe_height: float = maxf(viewport_height, 1.0)
	var half_fov_rad: float = deg_to_rad(clampf(fov_degrees, 1.0, 175.0)) * 0.5
	var visible_world_height: float = 2.0 * maxf(distance, 0.0) * tan(half_fov_rad)
	var world_per_pixel_x: float = visible_world_height / safe_height
	var pitch_sin: float = maxf(absf(sin(deg_to_rad(pitch_degrees))), MIN_PITCH_SIN)
	var world_per_pixel_y: float = world_per_pixel_x / pitch_sin
	return Vector2(
		-screen_delta.x * world_per_pixel_x,
		screen_delta.y * world_per_pixel_y
	)


static func compute_edge_pan_direction(
	mouse_pos: Vector2,
	viewport_size: Vector2,
	margin_px: float
) -> Vector2:
	if margin_px <= 0.0 or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ZERO
	if mouse_pos.x < 0.0 or mouse_pos.y < 0.0 or mouse_pos.x > viewport_size.x or mouse_pos.y > viewport_size.y:
		return Vector2.ZERO

	var dir: Vector2 = Vector2.ZERO
	if mouse_pos.x <= margin_px:
		dir.x -= 1.0
	elif mouse_pos.x >= viewport_size.x - margin_px:
		dir.x += 1.0

	if mouse_pos.y <= margin_px:
		dir.y += 1.0
	elif mouse_pos.y >= viewport_size.y - margin_px:
		dir.y -= 1.0

	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	return dir


## Computes the expected camera position offset relative to the ground focus point
## for a YawPivot (Y = yaw) -> PitchPivot (X = -pitch) -> Camera (Z = +distance) rig.
static func compute_camera_local_offset(
	distance: float,
	yaw_radians: float,
	pitch_radians: float
) -> Vector3:
	var horiz: float = distance * cos(pitch_radians)
	var height: float = distance * sin(pitch_radians)
	return Vector3(
		horiz * sin(yaw_radians),
		height,
		horiz * cos(yaw_radians)
	)
