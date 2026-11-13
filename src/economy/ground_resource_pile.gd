class_name GroundResourcePile
extends Node3D
## Physical ground resource pile inside CampStorageZone.
## Has zero per-frame _process/_physics_process logic; decay and stock are managed centrally
## by GroundPileManager. Visuals use lightweight shadowless primitive meshes.

var pile_id: int = 0
var resource_id: StringName = &""
var definition: ResourceDefinition = null
var amount: int = 0
var elapsed_exposure_sec: float = 0.0
var decay_accumulator_sec: float = 0.0

var _visual_root: Node3D = null
var _mesh_instances: Array[MeshInstance3D] = []


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func configure_initial(
	p_pile_id: int,
	p_definition: ResourceDefinition,
	p_amount: int,
	p_position: Vector3,
	p_elapsed_exposure_sec: float = 0.0,
	p_decay_accumulator_sec: float = 0.0,
	p_visual_cache: Dictionary = {}
) -> void:
	pile_id = p_pile_id
	definition = p_definition
	resource_id = p_definition.resource_id if p_definition != null else &""
	amount = p_amount
	elapsed_exposure_sec = p_elapsed_exposure_sec
	decay_accumulator_sec = p_decay_accumulator_sec
	position = p_position
	name = "Pile_%d_%s" % [pile_id, String(resource_id)]
	_rebuild_visuals(p_visual_cache)
	sync_visual()


func apply_state(
	p_amount: int,
	p_elapsed_exposure_sec: float,
	p_decay_accumulator_sec: float
) -> void:
	amount = p_amount
	elapsed_exposure_sec = p_elapsed_exposure_sec
	decay_accumulator_sec = p_decay_accumulator_sec
	sync_visual()


func is_valid() -> bool:
	return (
		pile_id > 0
		and definition != null
		and definition.is_valid()
		and resource_id == definition.resource_id
		and amount > 0
		and is_finite(elapsed_exposure_sec)
		and elapsed_exposure_sec >= 0.0
		and is_finite(decay_accumulator_sec)
		and decay_accumulator_sec >= 0.0
	)


func get_exposure_ratio() -> float:
	if definition == null or definition.decay_profile == null:
		return 0.0
	var profile: DecayProfile = definition.decay_profile
	if not profile.can_decay or profile.exposure_duration_sec <= 0.0:
		return 0.0
	return clampf(elapsed_exposure_sec / profile.exposure_duration_sec, 0.0, 1.0)


func get_visual_tier() -> int:
	if amount <= 0:
		return 0
	if amount <= 5:
		return 1
	if amount <= 15:
		return 2
	return 3


func get_visible_mesh_count() -> int:
	var visible_count: int = 0
	for mi: MeshInstance3D in _mesh_instances:
		if is_instance_valid(mi) and mi.visible:
			visible_count += 1
	return visible_count


func sync_visual() -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	var tier: int = get_visual_tier()
	var total: int = _mesh_instances.size()
	for i: int in range(total):
		var mi: MeshInstance3D = _mesh_instances[i]
		if not is_instance_valid(mi):
			continue
		if tier == 0:
			mi.visible = false
		elif tier == 1:
			mi.visible = i == 0
		elif tier == 2:
			mi.visible = i < mini(3, total)
		else:
			mi.visible = true

	var scale_factor: float = 0.75 + 0.12 * float(tier)
	_visual_root.scale = Vector3(scale_factor, scale_factor, scale_factor)


func _rebuild_visuals(visual_cache: Dictionary = {}) -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		remove_child(_visual_root)
		_visual_root.free()
	_mesh_instances.clear()

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	if definition == null:
		return

	var mat: StandardMaterial3D = _get_cached_material(definition.category, visual_cache)
	match definition.category:
		ResourceDefinition.Category.WOOD:
			var log_mesh: Mesh = _get_cached_mesh(&"wood_log", visual_cache)
			var offsets: Array[Vector3] = [
				Vector3(-0.14, 0.09, 0.0),
				Vector3(0.14, 0.09, 0.0),
				Vector3(0.0, 0.24, 0.02),
				Vector3(-0.08, 0.36, -0.02),
			]
			var rots: Array[Vector3] = [
				Vector3(0.0, 0.08, PI * 0.5),
				Vector3(0.0, -0.06, PI * 0.5),
				Vector3(0.0, 0.35, PI * 0.5),
				Vector3(0.0, -0.25, PI * 0.5),
			]
			for i: int in range(offsets.size()):
				_add_piece(log_mesh, mat, offsets[i], rots[i], "Log_%d" % i)
		ResourceDefinition.Category.STONE:
			var stone_mesh: Mesh = _get_cached_mesh(&"stone_block", visual_cache)
			var offsets: Array[Vector3] = [
				Vector3(-0.15, 0.11, 0.08),
				Vector3(0.15, 0.11, -0.06),
				Vector3(0.0, 0.13, -0.14),
				Vector3(0.0, 0.27, 0.02),
			]
			var rots: Array[Vector3] = [
				Vector3(0.1, 0.4, 0.05),
				Vector3(-0.08, 1.1, 0.1),
				Vector3(0.05, 2.0, -0.08),
				Vector3(0.15, 0.7, -0.1),
			]
			for i: int in range(offsets.size()):
				_add_piece(stone_mesh, mat, offsets[i], rots[i], "Stone_%d" % i)
		ResourceDefinition.Category.FOOD:
			var food_mesh: Mesh = _get_cached_mesh(&"food_bundle", visual_cache)
			var offsets: Array[Vector3] = [
				Vector3(-0.12, 0.1, 0.1),
				Vector3(0.12, 0.1, 0.08),
				Vector3(0.0, 0.1, -0.12),
				Vector3(0.0, 0.23, 0.0),
			]
			for i: int in range(offsets.size()):
				_add_piece(food_mesh, mat, offsets[i], Vector3.ZERO, "Food_%d" % i)


func _add_piece(
	mesh: Mesh,
	material: StandardMaterial3D,
	local_pos: Vector3,
	local_rot: Vector3,
	piece_name: String
) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = piece_name
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = local_pos
	mi.rotation = local_rot
	_visual_root.add_child(mi)
	_mesh_instances.append(mi)


func _get_cached_mesh(key: StringName, visual_cache: Dictionary) -> Mesh:
	var meshes: Dictionary = {}
	if visual_cache.has("meshes") and visual_cache["meshes"] is Dictionary:
		meshes = visual_cache["meshes"] as Dictionary
	if meshes.has(key):
		return meshes[key] as Mesh
	var mesh: Mesh
	match key:
		&"wood_log":
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = 0.08
			cyl.bottom_radius = 0.09
			cyl.height = 0.48
			cyl.radial_segments = 8
			cyl.rings = 1
			mesh = cyl
		&"stone_block":
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(0.24, 0.18, 0.22)
			mesh = box
		_:
			var sph: SphereMesh = SphereMesh.new()
			sph.radius = 0.12
			sph.height = 0.20
			sph.radial_segments = 8
			sph.rings = 4
			mesh = sph
	if visual_cache.has("meshes") and visual_cache["meshes"] is Dictionary:
		meshes[key] = mesh
	return mesh


func _get_cached_material(category: ResourceDefinition.Category, visual_cache: Dictionary) -> StandardMaterial3D:
	var materials: Dictionary = {}
	if visual_cache.has("materials") and visual_cache["materials"] is Dictionary:
		materials = visual_cache["materials"] as Dictionary
	if materials.has(category):
		return materials[category] as StandardMaterial3D
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.roughness = 0.9
	match category:
		ResourceDefinition.Category.WOOD:
			mat.albedo_color = Color(0.48, 0.30, 0.16, 1.0)
		ResourceDefinition.Category.STONE:
			mat.albedo_color = Color(0.54, 0.56, 0.58, 1.0)
		ResourceDefinition.Category.FOOD:
			mat.albedo_color = Color(0.76, 0.48, 0.18, 1.0)
	if visual_cache.has("materials") and visual_cache["materials"] is Dictionary:
		materials[category] = mat
	return mat
