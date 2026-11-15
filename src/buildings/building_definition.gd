class_name BuildingDefinition
extends Resource
## Spatial, visual, and future construction metadata definition for a building type.
## In T3.2, costs, build duration, max builders, and capacities act strictly as metadata.

@export var definition_id: StringName = &""
@export var display_name: String = ""
@export var footprint_size: Vector2 = Vector2(4.0, 4.0)
@export var visual_height: float = 3.0
@export var costs: Dictionary = {}
@export var build_work_required_sec: float = 30.0
@export var max_builders: int = 2
@export var storage_capacities: Dictionary = {}


func is_valid() -> bool:
	if definition_id.is_empty():
		return false
	if not is_finite(footprint_size.x) or not is_finite(footprint_size.y):
		return false
	if footprint_size.x <= 0.0 or footprint_size.y <= 0.0:
		return false
	if not is_finite(visual_height) or visual_height <= 0.0:
		return false
	if not is_finite(build_work_required_sec) or build_work_required_sec <= 0.0:
		return false
	if max_builders <= 0:
		return false

	for key: Variant in costs.keys():
		if not (key is StringName or key is String) or String(key).is_empty():
			return false
		var amount: Variant = costs[key]
		if not (amount is int) or (amount as int) < 0:
			return false

	for cap_key: Variant in storage_capacities.keys():
		if not (cap_key is StringName or cap_key is String) or String(cap_key).is_empty():
			return false
		var cap_amount: Variant = storage_capacities[cap_key]
		if not (cap_amount is int) or (cap_amount as int) < 0:
			return false

	return true


func get_half_extents() -> Vector2:
	return footprint_size * 0.5


func get_footprint_rect_at(center_xz: Vector2) -> Rect2:
	var half: Vector2 = get_half_extents()
	return Rect2(center_xz - half, footprint_size)


func get_footprint_aabb_at(center_pos: Vector3) -> AABB:
	var half: Vector2 = get_half_extents()
	return AABB(
		Vector3(center_pos.x - half.x, center_pos.y, center_pos.z - half.y),
		Vector3(footprint_size.x, visual_height, footprint_size.y)
	)


func get_perimeter_offsets(outward_margin: float) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	if not is_valid() or not is_finite(outward_margin) or outward_margin <= 0.0:
		return offsets
	var half: Vector2 = get_half_extents()
	var span_x: float = maxf(half.x * 0.55, 0.25)
	var span_z: float = maxf(half.y * 0.55, 0.25)
	var ext_x: float = half.x + outward_margin
	var ext_z: float = half.y + outward_margin

	# South (+Z), North (-Z), East (+X), West (-X): center sample first per side, then flanks.
	offsets.append(Vector2(0.0, ext_z))
	offsets.append(Vector2(-span_x, ext_z))
	offsets.append(Vector2(span_x, ext_z))

	offsets.append(Vector2(0.0, -ext_z))
	offsets.append(Vector2(-span_x, -ext_z))
	offsets.append(Vector2(span_x, -ext_z))

	offsets.append(Vector2(ext_x, 0.0))
	offsets.append(Vector2(ext_x, -span_z))
	offsets.append(Vector2(ext_x, span_z))

	offsets.append(Vector2(-ext_x, 0.0))
	offsets.append(Vector2(-ext_x, -span_z))
	offsets.append(Vector2(-ext_x, span_z))

	return offsets
