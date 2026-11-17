class_name BuildingInstance
extends Node3D
## Completed structure with permanent occupancy and physical collision.
## Provisional exterior geometry; no depot storage or gameplay services (T3.7).
const GROUP_COMPLETED_BUILDINGS: StringName = &"completed_buildings"
var building_id: StringName = &""
var definition: BuildingDefinition = null
var region_id: StringName = &""
var footprint_size: Vector2 = Vector2.ZERO
var incorporated_materials: Dictionary = {}
var _body: StaticBody3D = null
var _shape: CollisionShape3D = null


func configure(p_id: StringName, p_definition: BuildingDefinition, p_region: StringName, materials: Dictionary = {}) -> bool:
	if not building_id.is_empty() or p_id.is_empty() or p_region.is_empty() or p_definition == null or not p_definition.is_valid():
		return false
	building_id = p_id
	definition = p_definition
	region_id = p_region
	footprint_size = definition.footprint_size
	incorporated_materials = materials.duplicate()
	name = String(building_id)
	set_meta(&"region_id", region_id)
	_body = StaticBody3D.new()
	_body.name = "BuildingBody"
	_body.collision_layer = CollisionLayers.MASK_BUILDINGS | CollisionLayers.MASK_OBSTACLES
	_body.collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(footprint_size.x, definition.visual_height, footprint_size.y)
	_shape.shape = box
	_shape.position.y = definition.visual_height * 0.5
	_body.add_child(_shape)
	add_child(_body)
	add_to_group(GROUP_COMPLETED_BUILDINGS)
	_build_exterior()
	return is_valid()


func is_valid() -> bool:
	if building_id.is_empty() or region_id.is_empty() or definition == null or not definition.is_valid():
		return false
	if footprint_size != definition.footprint_size or not is_instance_valid(_body) or not is_instance_valid(_shape):
		return false
	if _body.get_parent() != self or _shape.get_parent() != _body or _shape.disabled or not (_shape.shape is BoxShape3D):
		return false
	if _body.transform != Transform3D.IDENTITY or _shape.transform.basis != Basis.IDENTITY or _shape.position != Vector3(0.0, definition.visual_height * 0.5, 0.0):
		return false
	var size: Vector3 = (_shape.shape as BoxShape3D).size
	return _body.collision_layer == (CollisionLayers.MASK_BUILDINGS | CollisionLayers.MASK_OBSTACLES) and size == Vector3(footprint_size.x, definition.visual_height, footprint_size.y)


func get_footprint_rect() -> Rect2:
	var origin: Vector3 = global_position if is_inside_tree() else position
	return Rect2(Vector2(origin.x, origin.z) - footprint_size * 0.5, footprint_size)


func get_footprint_aabb() -> AABB:
	var origin: Vector3 = global_position if is_inside_tree() else position
	return AABB(Vector3(origin.x - footprint_size.x * 0.5, origin.y, origin.z - footprint_size.y * 0.5), Vector3(footprint_size.x, definition.visual_height, footprint_size.y))


static func resolve_from_collider(collider: Object) -> BuildingInstance:
	if not is_instance_valid(collider) or not (collider is Node):
		return null
	var node: Node = collider as Node
	while node != null:
		if node is BuildingInstance:
			return node as BuildingInstance
		node = node.get_parent()
	return null


func _build_exterior() -> void:
	var walls := MeshInstance3D.new()
	walls.name = "Walls"
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(footprint_size.x * 0.94, definition.visual_height * 0.65, footprint_size.y * 0.94)
	walls.mesh = wall_mesh
	walls.position.y = wall_mesh.size.y * 0.5
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.62, 0.43, 0.25)
	walls.material_override = wall_material
	add_child(walls)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(footprint_size.x, definition.visual_height * 0.35, footprint_size.y)
	roof.mesh = roof_mesh
	roof.position.y = definition.visual_height * 0.825
	var roof_material := StandardMaterial3D.new()
	roof_material.albedo_color = Color(0.31, 0.23, 0.15)
	roof.material_override = roof_material
	add_child(roof)
