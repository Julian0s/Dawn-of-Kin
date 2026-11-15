class_name PlacementPreview
extends Node3D
## Gridless 3D visual preview for T3.2 building placement and temporary confirmation pulse.
## Uses shadowless, collision-free primitive meshes sized to the active BuildingDefinition.

const VOLUME_OPACITY: float = 0.34
const BORDER_THICKNESS_M: float = 0.08
const BORDER_HEIGHT_M: float = 0.06
const GROUND_OFFSET_Y: float = 0.02
const CONFIRM_PULSE_DURATION_SEC: float = 0.75

const VALID_VOLUME_COLOR: Color = Color(0.26, 0.58, 0.32, 0.34)
const VALID_BORDER_COLOR: Color = Color(0.32, 0.70, 0.38, 0.85)
const INVALID_VOLUME_COLOR: Color = Color(0.74, 0.26, 0.22, 0.36)
const INVALID_BORDER_COLOR: Color = Color(0.84, 0.30, 0.25, 0.88)
const CONFIRM_VOLUME_COLOR: Color = Color(0.34, 0.68, 0.40, 0.42)
const CONFIRM_BORDER_COLOR: Color = Color(0.42, 0.82, 0.48, 0.92)

var _built: bool = false
var _volume_material: StandardMaterial3D = null
var _border_material: StandardMaterial3D = null

var _base_pad: MeshInstance3D = null
var _body_mesh: MeshInstance3D = null
var _roof_mesh: MeshInstance3D = null
var _edge_north: MeshInstance3D = null
var _edge_south: MeshInstance3D = null
var _edge_east: MeshInstance3D = null
var _edge_west: MeshInstance3D = null

var _active_definition_id: StringName = &""
var _active_size: Vector2 = Vector2.ZERO
var _active_height: float = 0.0
var _is_valid_state: bool = false
var _is_pulsing_confirm: bool = false
var _pulse_elapsed_sec: float = 0.0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_ensure_visuals_built()
	visible = false


func _process(delta: float) -> void:
	if not _is_pulsing_confirm:
		set_process(false)
		return
	_pulse_elapsed_sec += maxf(delta, 0.0)
	var t: float = clampf(_pulse_elapsed_sec / CONFIRM_PULSE_DURATION_SEC, 0.0, 1.0)
	if t >= 1.0:
		hide_preview()
		return
	var fade: float = 1.0 - t
	if _volume_material != null:
		_volume_material.albedo_color = Color(
			CONFIRM_VOLUME_COLOR.r,
			CONFIRM_VOLUME_COLOR.g,
			CONFIRM_VOLUME_COLOR.b,
			CONFIRM_VOLUME_COLOR.a * fade
		)
	if _border_material != null:
		_border_material.albedo_color = Color(
			CONFIRM_BORDER_COLOR.r,
			CONFIRM_BORDER_COLOR.g,
			CONFIRM_BORDER_COLOR.b,
			CONFIRM_BORDER_COLOR.a * fade
		)


func show_preview(
	definition: BuildingDefinition,
	world_pos: Vector3,
	is_valid: bool
) -> void:
	if definition == null or not definition.is_valid() or not world_pos.is_finite():
		hide_preview()
		return

	_ensure_visuals_built()
	_is_pulsing_confirm = false
	_pulse_elapsed_sec = 0.0
	set_process(false)

	_apply_definition_geometry(definition)
	global_position = world_pos
	_apply_state_colors(is_valid)
	visible = true


func show_confirmation_pulse(
	definition: BuildingDefinition,
	world_pos: Vector3
) -> void:
	if definition == null or not definition.is_valid() or not world_pos.is_finite():
		hide_preview()
		return

	_ensure_visuals_built()
	_apply_definition_geometry(definition)
	global_position = world_pos
	_is_pulsing_confirm = true
	_pulse_elapsed_sec = 0.0
	_volume_material.albedo_color = CONFIRM_VOLUME_COLOR
	_border_material.albedo_color = CONFIRM_BORDER_COLOR
	visible = true
	set_process(true)


func hide_preview() -> void:
	_is_pulsing_confirm = false
	_pulse_elapsed_sec = 0.0
	set_process(false)
	visible = false


func is_valid_state() -> bool:
	return _is_valid_state


func is_confirmation_pulse_active() -> bool:
	return _is_pulsing_confirm


func get_displayed_footprint_size() -> Vector2:
	return _active_size


func _ensure_visuals_built() -> void:
	if _built:
		return
	_built = true

	_volume_material = StandardMaterial3D.new()
	_volume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_volume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_volume_material.cull_mode = BaseMaterial3D.CULL_BACK
	_volume_material.albedo_color = VALID_VOLUME_COLOR

	_border_material = StandardMaterial3D.new()
	_border_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_material.cull_mode = BaseMaterial3D.CULL_BACK
	_border_material.albedo_color = VALID_BORDER_COLOR

	_base_pad = _create_box_mesh_instance("BasePad", _volume_material)
	_body_mesh = _create_box_mesh_instance("BodyVolume", _volume_material)
	_roof_mesh = _create_mesh_instance("RoofVolume", _volume_material)
	_edge_north = _create_box_mesh_instance("EdgeNorth", _border_material)
	_edge_south = _create_box_mesh_instance("EdgeSouth", _border_material)
	_edge_east = _create_box_mesh_instance("EdgeEast", _border_material)
	_edge_west = _create_box_mesh_instance("EdgeWest", _border_material)


func _create_mesh_instance(node_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = material
	add_child(mi)
	return mi


func _create_box_mesh_instance(node_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var mi: MeshInstance3D = _create_mesh_instance(node_name, material)
	mi.mesh = BoxMesh.new()
	return mi


func _apply_definition_geometry(definition: BuildingDefinition) -> void:
	if (
		_active_definition_id == definition.definition_id
		and _active_size.is_equal_approx(definition.footprint_size)
		and is_equal_approx(_active_height, definition.visual_height)
	):
		return

	_active_definition_id = definition.definition_id
	_active_size = definition.footprint_size
	_active_height = definition.visual_height

	var w: float = _active_size.x
	var d: float = _active_size.y
	var h: float = _active_height

	var pad_box: BoxMesh = _base_pad.mesh as BoxMesh
	pad_box.size = Vector3(w, 0.04, d)
	_base_pad.position = Vector3(0.0, GROUND_OFFSET_Y, 0.0)

	var body_h: float = h * 0.62
	var roof_h: float = maxf(h - body_h, 0.4)
	var body_box: BoxMesh = _body_mesh.mesh as BoxMesh
	body_box.size = Vector3(maxf(w - 0.16, 0.5), body_h, maxf(d - 0.16, 0.5))
	_body_mesh.position = Vector3(0.0, GROUND_OFFSET_Y + 0.02 + body_h * 0.5, 0.0)

	if definition.definition_id == &"shelter_basic":
		var prism := PrismMesh.new()
		prism.left_to_right = 0.5
		prism.size = Vector3(w, roof_h, d)
		_roof_mesh.mesh = prism
	else:
		var flat_roof := BoxMesh.new()
		flat_roof.size = Vector3(w, roof_h * 0.55, d)
		_roof_mesh.mesh = flat_roof
	_roof_mesh.position = Vector3(0.0, GROUND_OFFSET_Y + 0.02 + body_h + roof_h * 0.45, 0.0)

	var half_w: float = w * 0.5
	var half_d: float = d * 0.5
	var border_y: float = GROUND_OFFSET_Y + BORDER_HEIGHT_M * 0.5

	(_edge_north.mesh as BoxMesh).size = Vector3(w, BORDER_HEIGHT_M, BORDER_THICKNESS_M)
	_edge_north.position = Vector3(0.0, border_y, -half_d + BORDER_THICKNESS_M * 0.5)

	(_edge_south.mesh as BoxMesh).size = Vector3(w, BORDER_HEIGHT_M, BORDER_THICKNESS_M)
	_edge_south.position = Vector3(0.0, border_y, half_d - BORDER_THICKNESS_M * 0.5)

	(_edge_west.mesh as BoxMesh).size = Vector3(BORDER_THICKNESS_M, BORDER_HEIGHT_M, maxf(d - BORDER_THICKNESS_M * 2.0, 0.1))
	_edge_west.position = Vector3(-half_w + BORDER_THICKNESS_M * 0.5, border_y, 0.0)

	(_edge_east.mesh as BoxMesh).size = Vector3(BORDER_THICKNESS_M, BORDER_HEIGHT_M, maxf(d - BORDER_THICKNESS_M * 2.0, 0.1))
	_edge_east.position = Vector3(half_w - BORDER_THICKNESS_M * 0.5, border_y, 0.0)


func _apply_state_colors(is_valid: bool) -> void:
	_is_valid_state = is_valid
	if is_valid:
		_volume_material.albedo_color = VALID_VOLUME_COLOR
		_border_material.albedo_color = VALID_BORDER_COLOR
	else:
		_volume_material.albedo_color = INVALID_VOLUME_COLOR
		_border_material.albedo_color = INVALID_BORDER_COLOR
