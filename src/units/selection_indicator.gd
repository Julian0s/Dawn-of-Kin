class_name SelectionIndicator
extends Node3D
## Provisional ground-ring feedback for unit selection and hover states.
## Renders distinct matte indicators without physics colliders or click blocking.

const GROUND_CLEARANCE_Y: float = 0.04
const SELECTED_INNER_RADIUS: float = 0.56
const SELECTED_OUTER_RADIUS: float = 0.74
const SELECTED_SEGMENTS: int = 36

const HOVER_INNER_RADIUS: float = 0.78
const HOVER_OUTER_RADIUS: float = 0.90
const HOVER_ARC_COUNT: int = 4
const HOVER_ARC_SPAN_RATIO: float = 0.56
const HOVER_ARC_SUBSEGMENTS: int = 7

const SELECTED_COLOR: Color = Color(0.90, 0.76, 0.30, 0.90)
const HOVER_COLOR: Color = Color(0.92, 0.96, 1.0, 0.72)

@onready var _selected_mesh: MeshInstance3D = $SelectedRing
@onready var _hover_mesh: MeshInstance3D = $HoverRing

var _is_selected: bool = false
var _is_hovered: bool = false
var _parent_body: CharacterBody3D = null


func _ready() -> void:
	_parent_body = get_parent() as CharacterBody3D
	position = Vector3(0.0, GROUND_CLEARANCE_Y, 0.0)
	_build_visuals()
	_refresh_visibility()


func _process(_delta: float) -> void:
	_align_to_floor()


func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	_refresh_visibility()


func is_selected() -> bool:
	return _is_selected


func set_hovered(hovered: bool) -> void:
	if _is_hovered == hovered:
		return
	_is_hovered = hovered
	_refresh_visibility()


func is_hovered() -> bool:
	return _is_hovered


func _refresh_visibility() -> void:
	if _selected_mesh != null:
		_selected_mesh.visible = _is_selected
	if _hover_mesh != null:
		_hover_mesh.visible = _is_hovered

	var any_visible: bool = _is_selected or _is_hovered
	visible = any_visible
	set_process(any_visible)
	if any_visible:
		_align_to_floor()


func _align_to_floor() -> void:
	if _parent_body == null or not _parent_body.is_inside_tree() or not _parent_body.is_on_floor():
		quaternion = Quaternion.IDENTITY
		position = Vector3(0.0, GROUND_CLEARANCE_Y, 0.0)
		return

	var world_normal: Vector3 = _parent_body.get_floor_normal()
	if world_normal.length_squared() < 0.001:
		quaternion = Quaternion.IDENTITY
		position = Vector3(0.0, GROUND_CLEARANCE_Y, 0.0)
		return

	var local_normal: Vector3 = (_parent_body.global_basis.inverse() * world_normal).normalized()
	quaternion = Quaternion(Vector3.UP, local_normal)
	position = local_normal * GROUND_CLEARANCE_Y


func _build_visuals() -> void:
	if _selected_mesh != null:
		_selected_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_selected_mesh.mesh = _create_segmented_ring_mesh(
			SELECTED_INNER_RADIUS,
			SELECTED_OUTER_RADIUS,
			1,
			1.0,
			SELECTED_SEGMENTS
		)
		_selected_mesh.material_override = _create_ring_material(SELECTED_COLOR)

	if _hover_mesh != null:
		_hover_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hover_mesh.mesh = _create_segmented_ring_mesh(
			HOVER_INNER_RADIUS,
			HOVER_OUTER_RADIUS,
			HOVER_ARC_COUNT,
			HOVER_ARC_SPAN_RATIO,
			HOVER_ARC_SUBSEGMENTS
		)
		_hover_mesh.material_override = _create_ring_material(HOVER_COLOR)


static func _create_ring_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat


static func _create_segmented_ring_mesh(
	inner_r: float,
	outer_r: float,
	arc_count: int,
	arc_span_ratio: float,
	sub_segments: int
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var sector_angle: float = TAU / float(maxi(arc_count, 1))
	var arc_angle: float = sector_angle * clampf(arc_span_ratio, 0.05, 1.0)
	var half_arc: float = arc_angle * 0.5
	var base_offset: float = 0.0 if arc_count == 1 else sector_angle * 0.5

	for arc_idx: int in range(maxi(arc_count, 1)):
		var center_angle: float = float(arc_idx) * sector_angle + base_offset
		var start_angle: float = center_angle - half_arc
		var base_vert: int = vertices.size()

		for step: int in range(sub_segments + 1):
			var t: float = float(step) / float(sub_segments)
			var angle: float = start_angle + arc_angle * t
			var cos_a: float = cos(angle)
			var sin_a: float = sin(angle)
			vertices.append(Vector3(cos_a * inner_r, 0.0, sin_a * inner_r))
			vertices.append(Vector3(cos_a * outer_r, 0.0, sin_a * outer_r))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)

		for step: int in range(sub_segments):
			var i0: int = base_vert + step * 2
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
