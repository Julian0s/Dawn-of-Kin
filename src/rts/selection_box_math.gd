class_name SelectionBoxMath
extends RefCounted
## Pure screen-space geometry helpers for RTS box selection.
## Projects 3D unit anchors through Camera3D without per-pixel raycasts.

const DEFAULT_ANCHOR_OFFSET: Vector3 = Vector3(0.0, 0.95, 0.0)


static func normalize_rect(start_pos: Vector2, end_pos: Vector2) -> Rect2:
	var min_x: float = minf(start_pos.x, end_pos.x)
	var min_y: float = minf(start_pos.y, end_pos.y)
	var max_x: float = maxf(start_pos.x, end_pos.x)
	var max_y: float = maxf(start_pos.y, end_pos.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


static func get_unit_world_anchor(unit: Unit, anchor_offset: Vector3 = DEFAULT_ANCHOR_OFFSET) -> Vector3:
	return unit.global_position + anchor_offset


static func is_point_in_box(
	screen_pos: Vector2,
	box_rect: Rect2,
	viewport_rect: Rect2 = Rect2(),
	screen_radius_px: float = 0.0
) -> bool:
	if not screen_pos.is_finite():
		return false
	if viewport_rect.has_area() and not viewport_rect.has_point(screen_pos):
		return false
	if screen_radius_px <= 0.0:
		return box_rect.has_point(screen_pos)

	var closest: Vector2 = screen_pos.clamp(box_rect.position, box_rect.end)
	return screen_pos.distance_squared_to(closest) <= screen_radius_px * screen_radius_px


static func is_unit_in_box(
	camera: Camera3D,
	unit: Unit,
	raw_box_rect: Rect2,
	viewport_rect: Rect2 = Rect2(),
	anchor_offset: Vector3 = DEFAULT_ANCHOR_OFFSET,
	screen_radius_px: float = 0.0
) -> bool:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return false
	if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
		return false

	var world_anchor: Vector3 = get_unit_world_anchor(unit, anchor_offset)
	if camera.is_position_behind(world_anchor):
		return false

	var screen_pos: Vector2 = camera.unproject_position(world_anchor)
	var normalized_box: Rect2 = normalize_rect(raw_box_rect.position, raw_box_rect.end)
	return is_point_in_box(screen_pos, normalized_box, viewport_rect, screen_radius_px)


static func collect_units_in_box(
	camera: Camera3D,
	candidates: Array,
	raw_box_rect: Rect2,
	viewport_rect: Rect2 = Rect2(),
	anchor_offset: Vector3 = DEFAULT_ANCHOR_OFFSET,
	screen_radius_px: float = 0.0
) -> Array[Unit]:
	var result: Array[Unit] = []
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return result

	var normalized_box: Rect2 = normalize_rect(raw_box_rect.position, raw_box_rect.end)
	for candidate: Variant in candidates:
		if not (candidate is Unit):
			continue
		var unit: Unit = candidate as Unit
		if result.has(unit):
			continue
		if is_unit_in_box(camera, unit, normalized_box, viewport_rect, anchor_offset, screen_radius_px):
			result.append(unit)
	return result


static func get_source_world_anchor(source: ResourceSource) -> Vector3:
	var y_offset: float = 0.9 if source.get_resource_id() == &"wood" else 0.5
	return source.global_position + Vector3(0.0, y_offset, 0.0)


static func is_source_in_box(
	camera: Camera3D,
	source: ResourceSource,
	raw_box_rect: Rect2,
	viewport_rect: Rect2 = Rect2(),
	screen_radius_px: float = 0.0
) -> bool:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return false
	if source == null or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
		return false

	var world_anchor: Vector3 = get_source_world_anchor(source)
	if camera.is_position_behind(world_anchor):
		return false

	var screen_pos: Vector2 = camera.unproject_position(world_anchor)
	var normalized_box: Rect2 = normalize_rect(raw_box_rect.position, raw_box_rect.end)
	return is_point_in_box(screen_pos, normalized_box, viewport_rect, screen_radius_px)


static func collect_sources_in_box(
	camera: Camera3D,
	candidates: Array,
	raw_box_rect: Rect2,
	viewport_rect: Rect2 = Rect2(),
	required_resource_id: StringName = &"",
	available_only: bool = true,
	screen_radius_px: float = 0.0
) -> Array[ResourceSource]:
	var result: Array[ResourceSource] = []
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return result

	var normalized_box: Rect2 = normalize_rect(raw_box_rect.position, raw_box_rect.end)
	for candidate: Variant in candidates:
		if not (candidate is ResourceSource):
			continue
		var source: ResourceSource = candidate as ResourceSource
		if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
			continue
		if result.has(source):
			continue
		if not required_resource_id.is_empty() and source.get_resource_id() != required_resource_id:
			continue
		if available_only and (source.is_depleted() or not source.is_available()):
			continue
		if is_source_in_box(camera, source, normalized_box, viewport_rect, screen_radius_px):
			result.append(source)
	return result
