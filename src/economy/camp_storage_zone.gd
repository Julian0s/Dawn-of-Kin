class_name CampStorageZone
extends Node3D
## Logical camp storage area validating slot coordinates and navigation reachability.
## Contains no StaticBody3D colliders or pre-existing buildings, keeping T2.1 pure ground storage.

@export var zone_id: StringName = &"camp_storage_main"
@export var zone_bounds_half_extents: Vector2 = Vector2(4.0, 4.0)
@export var slot_spacing: float = 1.2
@export var min_pile_clearance: float = 0.85
@export var max_pile_amount: int = 0
@export var decay_multiplier: float = 1.0
@export var max_nav_snap_distance: float = 0.65

var _world_navigation: WorldNavigation = null
var _custom_position_validator: Callable = Callable()


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func set_world_navigation(navigation: WorldNavigation) -> void:
	_world_navigation = navigation


func get_world_navigation() -> WorldNavigation:
	return _world_navigation


func set_custom_position_validator(validator: Callable) -> void:
	_custom_position_validator = validator


func get_anchor_position() -> Vector3:
	if is_inside_tree():
		return global_position
	return position


func is_valid() -> bool:
	return (
		zone_id != &""
		and is_finite(zone_bounds_half_extents.x)
		and is_finite(zone_bounds_half_extents.y)
		and zone_bounds_half_extents.x > 0.0
		and zone_bounds_half_extents.y > 0.0
		and is_finite(slot_spacing)
		and slot_spacing > 0.0
		and is_finite(min_pile_clearance)
		and min_pile_clearance >= 0.0
		and is_finite(decay_multiplier)
		and decay_multiplier >= 0.0
		and is_finite(max_nav_snap_distance)
		and max_nav_snap_distance > 0.0
	)


func is_position_finite(world_pos: Vector3) -> bool:
	return is_finite(world_pos.x) and is_finite(world_pos.y) and is_finite(world_pos.z)


func is_position_in_bounds(world_pos: Vector3) -> bool:
	if not is_valid() or not is_position_finite(world_pos):
		return false
	var anchor: Vector3 = get_anchor_position()
	var dx: float = absf(world_pos.x - anchor.x)
	var dz: float = absf(world_pos.z - anchor.z)
	return dx <= zone_bounds_half_extents.x + 0.0001 and dz <= zone_bounds_half_extents.y + 0.0001


func get_candidate_slots() -> Array[Vector3]:
	var slots: Array[Vector3] = []
	if not is_valid():
		return slots
	var anchor: Vector3 = get_anchor_position()
	var step: float = slot_spacing
	var cols_half: int = int(floor(zone_bounds_half_extents.x / step))
	var rows_half: int = int(floor(zone_bounds_half_extents.y / step))
	var entries: Array[Dictionary] = []
	for gz: int in range(-rows_half, rows_half + 1):
		for gx: int in range(-cols_half, cols_half + 1):
			var lx: float = float(gx) * step
			var lz: float = float(gz) * step
			var world_pos: Vector3 = Vector3(anchor.x + lx, anchor.y, anchor.z + lz)
			entries.append({
				"pos": world_pos,
				"dist_sq": lx * lx + lz * lz,
				"lz": lz,
				"lx": lx,
			})
	entries.sort_custom(_sort_slot_entries)
	for entry: Dictionary in entries:
		slots.append(entry["pos"] as Vector3)
	return slots


func validate_pile_position(world_pos: Vector3, occupied_positions: Array[Vector3]) -> Dictionary:
	if not is_valid():
		return {"valid": false, "position": world_pos, "reason": "invalid_zone"}
	if not is_position_in_bounds(world_pos):
		return {"valid": false, "position": world_pos, "reason": "out_of_bounds"}

	var resolved_pos: Vector3 = world_pos
	if _world_navigation != null:
		if not _world_navigation.is_navigation_ready():
			return {"valid": false, "position": world_pos, "reason": "navigation_not_ready"}
		var snapped: Vector3 = _world_navigation.snap_to_navmesh(world_pos)
		var horiz_offset: float = Vector2(snapped.x - world_pos.x, snapped.z - world_pos.z).length()
		if horiz_offset > max_nav_snap_distance or absf(snapped.y - world_pos.y) > 2.5:
			return {"valid": false, "position": world_pos, "reason": "off_navmesh"}
		var anchor: Vector3 = get_anchor_position()
		if not _world_navigation.is_position_reachable(anchor, snapped):
			return {"valid": false, "position": world_pos, "reason": "unreachable_from_anchor"}
		resolved_pos = snapped
		if not is_position_in_bounds(resolved_pos):
			return {"valid": false, "position": resolved_pos, "reason": "snapped_out_of_bounds"}

	if _custom_position_validator.is_valid():
		var custom_ok: Variant = _custom_position_validator.call(resolved_pos)
		if custom_ok is bool and not (custom_ok as bool):
			return {"valid": false, "position": resolved_pos, "reason": "custom_rejected"}

	for occupied: Vector3 in occupied_positions:
		var flat_dist: float = Vector2(resolved_pos.x - occupied.x, resolved_pos.z - occupied.z).length()
		if flat_dist < min_pile_clearance:
			return {"valid": false, "position": resolved_pos, "reason": "occupied_or_too_close"}

	return {"valid": true, "position": resolved_pos, "reason": ""}


func _sort_slot_entries(a: Dictionary, b: Dictionary) -> bool:
	var da: float = a["dist_sq"] as float
	var db: float = b["dist_sq"] as float
	if not is_equal_approx(da, db):
		return da < db
	var za: float = a["lz"] as float
	var zb: float = b["lz"] as float
	if not is_equal_approx(za, zb):
		return za < zb
	return (a["lx"] as float) < (b["lx"] as float)
