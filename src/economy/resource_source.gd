class_name ResourceSource
extends Node3D
## Gatherable natural resource node (tree, rock, bush) with finite stock,
## deterministic depletion state, and worker slot reservation hooks for T2.3+.
## Contains no per-frame _process/_physics_process logic and no resource regeneration.

const GROUP_RESOURCE_SOURCES: StringName = &"resource_sources"

signal amount_changed(source: ResourceSource, remaining_amount: int, delta: int)
signal depleted(source: ResourceSource)

@export var source_id: StringName = &""
@export var definition: ResourceDefinition = null
@export var initial_amount: int = 20:
	set(value):
		initial_amount = maxi(0, value)
		if not _has_extracted:
			_remaining_amount = initial_amount
			_sync_visuals()
@export var max_extract_per_operation: int = 1
@export var max_simultaneous_workers: int = 2
@export var interaction_radius: float = 1.6

var _remaining_amount: int = 20
var _has_extracted: bool = false
var _is_transferring: bool = false
var _reserved_worker_ids: Array[int] = []


func _init() -> void:
	_remaining_amount = initial_amount


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	add_to_group(GROUP_RESOURCE_SOURCES)

	var solid_body: StaticBody3D = get_node_or_null("SolidBody") as StaticBody3D
	if solid_body != null:
		solid_body.collision_layer = CollisionLayers.MASK_OBSTACLES
		solid_body.collision_mask = 0

	var interaction_area: Area3D = get_node_or_null("InteractionArea") as Area3D
	if interaction_area != null:
		interaction_area.collision_layer = CollisionLayers.MASK_RESOURCES
		interaction_area.collision_mask = 0
		interaction_area.monitoring = false
		interaction_area.monitorable = true

	_sync_visuals()


func configure(
	p_source_id: StringName,
	p_definition: ResourceDefinition,
	p_initial_amount: int,
	p_max_extract_per_operation: int = 1,
	p_max_simultaneous_workers: int = 2
) -> void:
	source_id = p_source_id
	definition = p_definition
	max_extract_per_operation = p_max_extract_per_operation
	max_simultaneous_workers = p_max_simultaneous_workers
	_has_extracted = false
	_is_transferring = false
	initial_amount = p_initial_amount
	_remaining_amount = maxi(0, p_initial_amount)
	_reserved_worker_ids.clear()
	_sync_visuals()


func is_valid() -> bool:
	return (
		not source_id.is_empty()
		and definition != null
		and definition.is_valid()
		and initial_amount > 0
		and max_extract_per_operation > 0
		and max_simultaneous_workers > 0
		and _remaining_amount >= 0
		and _remaining_amount <= initial_amount
	)


func get_source_id() -> StringName:
	return source_id


func get_resource_id() -> StringName:
	if definition == null:
		return &""
	return definition.resource_id


func get_definition() -> ResourceDefinition:
	return definition


func get_category() -> int:
	if definition == null:
		return -1
	return int(definition.category)


func get_initial_amount() -> int:
	return initial_amount


func get_remaining_amount() -> int:
	return _remaining_amount


func is_depleted() -> bool:
	return _remaining_amount <= 0


func is_available() -> bool:
	return is_valid() and _remaining_amount > 0


func can_extract(requested_amount: int = 1) -> bool:
	return requested_amount > 0 and is_available()


func extract(requested_amount: int) -> int:
	if _is_transferring or requested_amount <= 0 or not is_available():
		return 0

	var capped_request: int = mini(requested_amount, max_extract_per_operation)
	var extracted: int = mini(capped_request, _remaining_amount)
	if extracted <= 0:
		return 0

	_has_extracted = true
	_remaining_amount = maxi(0, _remaining_amount - extracted)
	var became_depleted: bool = (_remaining_amount == 0)
	_sync_visuals()

	# Emit signals strictly after final state is committed.
	_is_transferring = true
	amount_changed.emit(self, _remaining_amount, -extracted)
	if became_depleted:
		depleted.emit(self)
	_is_transferring = false

	return extracted


func transfer_to_carry_load(carry_load: UnitCarryLoad, requested_amount: int = -1) -> int:
	## Atomically transfers up to min(requested_amount, max_extract_per_operation, carry capacity)
	## directly from this source to carry_load without double-drain or reentrant loss.
	if _is_transferring or carry_load == null or not is_available():
		return 0
	if requested_amount == 0:
		return 0

	var max_fit: int = carry_load.get_max_additional_units(definition)
	if max_fit <= 0:
		return 0

	var op_cap: int = max_extract_per_operation
	if requested_amount > 0:
		op_cap = mini(requested_amount, max_extract_per_operation)
	var extracted: int = mini(_remaining_amount, mini(op_cap, max_fit))
	if extracted <= 0:
		return 0

	carry_load.begin_batch()
	var added: bool = carry_load.add_units(definition, extracted)
	if not added:
		carry_load.end_batch(true)
		return 0

	_has_extracted = true
	_remaining_amount = maxi(0, _remaining_amount - extracted)
	var became_depleted: bool = (_remaining_amount == 0)
	_sync_visuals()

	# Both source and carry_load now reflect final conserved quantities before observers fire.
	_is_transferring = true
	carry_load.end_batch(false)
	amount_changed.emit(self, _remaining_amount, -extracted)
	if became_depleted:
		depleted.emit(self)
	_is_transferring = false

	return extracted


func reserve_worker(worker: Node) -> bool:
	_prune_invalid_workers()
	if worker == null or not is_instance_valid(worker) or not is_available():
		return false
	var wid: int = worker.get_instance_id()
	if _reserved_worker_ids.has(wid):
		return true
	if _reserved_worker_ids.size() >= max_simultaneous_workers:
		return false
	_reserved_worker_ids.append(wid)
	return true


func release_worker(worker: Node) -> void:
	_prune_invalid_workers()
	if worker == null:
		return
	var wid: int = worker.get_instance_id()
	_reserved_worker_ids.erase(wid)


func clear_worker_reservations() -> void:
	_reserved_worker_ids.clear()


func is_worker_reserved(worker: Node) -> bool:
	_prune_invalid_workers()
	if worker == null or not is_instance_valid(worker):
		return false
	return _reserved_worker_ids.has(worker.get_instance_id())


func has_worker_slot(worker: Node = null) -> bool:
	_prune_invalid_workers()
	if not is_available():
		return false
	if worker != null and is_instance_valid(worker) and _reserved_worker_ids.has(worker.get_instance_id()):
		return true
	return _reserved_worker_ids.size() < max_simultaneous_workers


func get_active_worker_count() -> int:
	_prune_invalid_workers()
	return _reserved_worker_ids.size()


func get_interaction_radius() -> float:
	return interaction_radius


func get_solid_radius() -> float:
	var solid_body: StaticBody3D = get_node_or_null("SolidBody") as StaticBody3D
	if solid_body == null:
		return 0.0

	var shape_node: CollisionShape3D = solid_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return 0.0

	var scale_xz: float = 1.0
	if shape_node.is_inside_tree():
		var s: Vector3 = shape_node.global_transform.basis.get_scale()
		scale_xz = maxf(absf(s.x), absf(s.z))

	var col_shape: Shape3D = shape_node.shape
	if col_shape is SphereShape3D:
		return (col_shape as SphereShape3D).radius * scale_xz
	if col_shape is CylinderShape3D:
		return (col_shape as CylinderShape3D).radius * scale_xz
	if col_shape is CapsuleShape3D:
		return (col_shape as CapsuleShape3D).radius * scale_xz
	if col_shape is BoxShape3D:
		var box_size: Vector3 = (col_shape as BoxShape3D).size
		return Vector2(box_size.x, box_size.z).length() * 0.5 * scale_xz
	return 0.0


func _prune_invalid_workers() -> void:
	var kept: Array[int] = []
	for wid: int in _reserved_worker_ids:
		if is_instance_id_valid(wid):
			var obj: Object = instance_from_id(wid)
			if obj is Node and is_instance_valid(obj):
				kept.append(wid)
	_reserved_worker_ids = kept


func _sync_visuals() -> void:
	var available_node: Node3D = get_node_or_null("AvailableVisual") as Node3D
	var depleted_node: Node3D = get_node_or_null("DepletedVisual") as Node3D
	var show_available: bool = _remaining_amount > 0
	if available_node != null:
		available_node.visible = show_available
	if depleted_node != null:
		depleted_node.visible = not show_available
