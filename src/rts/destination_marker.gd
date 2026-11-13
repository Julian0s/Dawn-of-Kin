class_name DestinationMarker
extends Node3D
## Provisional discrete matte 3D destination pulse for right-click move orders.
## Reuses one scene node and material instances so rapid commands never allocate or accumulate nodes.

const DURATION_SEC: float = 0.65
const GROUND_OFFSET_Y: float = 0.05
const START_SCALE: float = 1.24
const END_SCALE: float = 0.78

const OUTER_INNER_RADIUS: float = 0.42
const OUTER_OUTER_RADIUS: float = 0.54
const INNER_INNER_RADIUS: float = 0.10
const INNER_OUTER_RADIUS: float = 0.20
const RING_SEGMENTS: int = 32

const REACHABLE_COLOR: Color = Color(0.92, 0.78, 0.36, 0.88)
const UNREACHABLE_COLOR: Color = Color(0.84, 0.44, 0.30, 0.82)

@onready var _outer_ring: MeshInstance3D = $OuterRing
@onready var _inner_ring: MeshInstance3D = $InnerRing

var _outer_material: StandardMaterial3D = null
var _inner_material: StandardMaterial3D = null
var _base_color: Color = REACHABLE_COLOR
var _elapsed: float = 0.0
var _active: bool = false
var _pulse_count: int = 0
var _last_world_position: Vector3 = Vector3.ZERO
var _last_reachable: bool = true


func _ready() -> void:
	_build_visuals()
	hide_marker()


func _process(delta: float) -> void:
	if not _active:
		set_process(false)
		return

	_elapsed += maxf(delta, 0.0)
	var progress: float = clampf(_elapsed / DURATION_SEC, 0.0, 1.0)
	if progress >= 1.0:
		hide_marker()
		return

	_apply_animation_frame(progress)


func show_at(
	world_pos: Vector3,
	surface_normal: Vector3 = Vector3.UP,
	is_reachable: bool = true
) -> void:
	if not world_pos.is_finite():
		return

	_ensure_visuals_built()

	var safe_normal: Vector3 = surface_normal.normalized() if surface_normal.is_finite() and surface_normal.length_squared() > 0.001 else Vector3.UP
	global_position = world_pos + safe_normal * GROUND_OFFSET_Y
	quaternion = Quaternion(Vector3.UP, safe_normal)

	_last_world_position = world_pos
	_last_reachable = is_reachable
	_base_color = REACHABLE_COLOR if is_reachable else UNREACHABLE_COLOR
	_elapsed = 0.0
	_active = true
	_pulse_count += 1
	visible = true
	set_process(true)
	_apply_animation_frame(0.0)


func hide_marker() -> void:
	_active = false
	_elapsed = 0.0
	visible = false
	set_process(false)


func is_marker_active() -> bool:
	return _active


func get_pulse_count() -> int:
	return _pulse_count


func get_last_world_position() -> Vector3:
	return _last_world_position


func was_last_reachable() -> bool:
	return _last_reachable


func _apply_animation_frame(progress: float) -> void:
	var eased: float = 1.0 - pow(1.0 - progress, 2.0)
	var scale_xz: float = lerpf(START_SCALE, END_SCALE, eased)
	scale = Vector3(scale_xz, 1.0, scale_xz)

	var alpha_factor: float = pow(1.0 - progress, 1.15)
	if _outer_material != null:
		var outer_col: Color = _base_color
		outer_col.a = _base_color.a * alpha_factor
		_outer_material.albedo_color = outer_col
	if _inner_material != null:
		var inner_col: Color = _base_color
		inner_col.a = clampf(_base_color.a * 1.05, 0.0, 1.0) * alpha_factor
		_inner_material.albedo_color = inner_col


func _ensure_visuals_built() -> void:
	if _outer_material == null or _inner_material == null:
		_build_visuals()


func _build_visuals() -> void:
	if _outer_ring != null:
		_outer_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_outer_ring.mesh = _create_ring_mesh(OUTER_INNER_RADIUS, OUTER_OUTER_RADIUS, RING_SEGMENTS)
		_outer_material = _create_matte_material(REACHABLE_COLOR)
		_outer_ring.material_override = _outer_material

	if _inner_ring != null:
		_inner_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_inner_ring.mesh = _create_ring_mesh(INNER_INNER_RADIUS, INNER_OUTER_RADIUS, RING_SEGMENTS)
		_inner_material = _create_matte_material(REACHABLE_COLOR)
		_inner_ring.material_override = _inner_material


static func _create_matte_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat


static func _create_ring_mesh(inner_r: float, outer_r: float, segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var seg_count: int = maxi(segments, 8)
	for step: int in range(seg_count + 1):
		var angle: float = TAU * (float(step) / float(seg_count))
		var cos_a: float = cos(angle)
		var sin_a: float = sin(angle)
		vertices.append(Vector3(cos_a * inner_r, 0.0, sin_a * inner_r))
		vertices.append(Vector3(cos_a * outer_r, 0.0, sin_a * outer_r))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

	for step: int in range(seg_count):
		var i0: int = step * 2
		var i1: int = i0 + 1
		var i2: int = i0 + 2
		var i3: int = i0 + 3
		indices.append_array([i0, i2, i1, i1, i2, i3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
