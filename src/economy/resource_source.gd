class_name ResourceSource
extends Node3D
## Gatherable natural resource node (tree, rock, bush) with finite stock,
## deterministic depletion state, and worker slot reservation hooks for T2.3+.
## Contains no per-frame _process/_physics_process logic and no resource regeneration.

const GROUP_RESOURCE_SOURCES: StringName = &"resource_sources"

enum TreeVisualState {
	STANDING,
	FELLING,
	FALLEN,
}

signal amount_changed(source: ResourceSource, remaining_amount: int, delta: int)
signal depleted(source: ResourceSource)

@export var source_id: StringName = &"":
	set(value):
		if source_id != value:
			_transaction_revision += 1
		source_id = value
@export var definition: ResourceDefinition = null:
	set(value):
		if definition != value:
			_transaction_revision += 1
		definition = value
@export var initial_amount: int = 20:
	set(value):
		if initial_amount != maxi(0, value):
			_transaction_revision += 1
		initial_amount = maxi(0, value)
		if not _has_extracted:
			_remaining_amount = initial_amount
			_sync_visuals()
@export var max_extract_per_operation: int = 1:
	set(value):
		if max_extract_per_operation != value:
			_transaction_revision += 1
		max_extract_per_operation = value
@export var max_simultaneous_workers: int = 2
@export var interaction_radius: float = 1.6
@export var gather_operation_duration_sec: float = 2.5
@export var gather_prepare_duration_sec: float = 0.35
@export var felling_duration_sec: float = 0.50
@export var show_discoverability_badge: bool = true:
	set(value):
		show_discoverability_badge = value
		_sync_visuals()
@export var discoverability_label_text: String = "":
	set(value):
		discoverability_label_text = value
		_sync_visuals()

var _transaction_revision: int = 0
var _provenance_receipts: Dictionary = {}
var _remaining_amount: int = 20
var _has_extracted: bool = false
var _is_transferring: bool = false
var _reserved_worker_ids: Array[int] = []
var _available_base_transform: Transform3D = Transform3D.IDENTITY
var _has_available_base_transform: bool = false
var _feedback_tween: Tween = null
var _tree_visual_state: TreeVisualState = TreeVisualState.STANDING
var _felling_tween: Tween = null
var _has_felling_rest_pose: bool = false
var _felling_pivot_rest: Transform3D = Transform3D.IDENTITY
var _canopy_rest_transforms: Dictionary = {}
var _badge_label_rest_pos: Vector3 = Vector3.ZERO
var _has_badge_label_rest_pos: bool = false


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

	_cache_available_base_transform()
	_cache_felling_rest_pose()
	_sync_visuals()


func _exit_tree() -> void:
	_kill_feedback_tween()
	_reset_feedback_visuals()
	_kill_felling_tween()
	_reset_felling_visuals()


func configure(
	p_source_id: StringName,
	p_definition: ResourceDefinition,
	p_initial_amount: int,
	p_max_extract_per_operation: int = 1,
	p_max_simultaneous_workers: int = 2
) -> void:
	if _is_transferring:
		return
	_transaction_revision += 1
	source_id = p_source_id
	definition = p_definition
	max_extract_per_operation = p_max_extract_per_operation
	max_simultaneous_workers = p_max_simultaneous_workers
	_has_extracted = false
	_is_transferring = false
	initial_amount = p_initial_amount
	_remaining_amount = maxi(0, p_initial_amount)
	_reserved_worker_ids.clear()
	_reset_feedback_visuals()
	_reset_felling_visuals()
	_sync_visuals()


func is_valid() -> bool:
	return (
		not source_id.is_empty()
		and definition != null
		and definition.is_valid()
		and initial_amount > 0
		and max_extract_per_operation > 0
		and max_simultaneous_workers > 0
		and gather_operation_duration_sec > 0.0
		and is_finite(gather_operation_duration_sec)
		and gather_prepare_duration_sec >= 0.0
		and is_finite(gather_prepare_duration_sec)
		and felling_duration_sec > 0.0
		and is_finite(felling_duration_sec)
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
	_transaction_revision += 1
	var became_depleted: bool = (_remaining_amount == 0)
	_trigger_tree_felling_if_needed(became_depleted)
	_sync_visuals()
	if not became_depleted:
		_trigger_gather_feedback()

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
	_transaction_revision += 1
	var became_depleted: bool = (_remaining_amount == 0)
	_trigger_tree_felling_if_needed(became_depleted)
	_sync_visuals()
	if not became_depleted:
		_trigger_gather_feedback()

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


func get_tree_visual_state() -> TreeVisualState:
	return _tree_visual_state


func is_standing() -> bool:
	return get_category() == ResourceDefinition.Category.WOOD and _tree_visual_state == TreeVisualState.STANDING and _remaining_amount > 0


func is_felling() -> bool:
	return get_category() == ResourceDefinition.Category.WOOD and _tree_visual_state == TreeVisualState.FELLING and _remaining_amount > 0


func is_fallen() -> bool:
	return get_category() == ResourceDefinition.Category.WOOD and _tree_visual_state == TreeVisualState.FALLEN


func get_total_fruit_count() -> int:
	var fruits_node: Node = get_node_or_null("AvailableVisual/Fruits")
	if fruits_node == null:
		return 0
	return fruits_node.get_child_count()


func get_visible_fruit_count() -> int:
	var available_node: Node3D = get_node_or_null("AvailableVisual") as Node3D
	if available_node == null or not available_node.visible or _remaining_amount <= 0:
		return 0
	var fruits_node: Node = available_node.get_node_or_null("Fruits")
	if fruits_node == null:
		return 0
	var count: int = 0
	for child: Node in fruits_node.get_children():
		if child is Node3D and (child as Node3D).visible:
			count += 1
	return count


func get_interaction_radius() -> float:
	return interaction_radius


func get_gather_operation_duration_sec() -> float:
	return gather_operation_duration_sec


func get_gather_prepare_duration_sec() -> float:
	return gather_prepare_duration_sec


func set_gather_cycle_timings(p_operation_duration_sec: float, p_prepare_duration_sec: float = -1.0) -> void:
	gather_operation_duration_sec = maxf(p_operation_duration_sec, 0.01)
	if p_prepare_duration_sec >= 0.0:
		gather_prepare_duration_sec = p_prepare_duration_sec


func set_discoverability_badge_visible(enabled: bool) -> void:
	show_discoverability_badge = enabled


func is_discoverability_badge_visible() -> bool:
	return show_discoverability_badge


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


func _cache_available_base_transform() -> void:
	var available_node: Node3D = get_node_or_null("AvailableVisual") as Node3D
	if available_node != null and not _has_available_base_transform:
		_available_base_transform = available_node.transform
		_has_available_base_transform = true


func _kill_feedback_tween() -> void:
	if _feedback_tween != null and is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	_feedback_tween = null


func _reset_feedback_visuals() -> void:
	_kill_feedback_tween()
	var available_node: Node3D = get_node_or_null("AvailableVisual") as Node3D
	if available_node != null and _has_available_base_transform:
		available_node.transform = _available_base_transform


func _trigger_gather_feedback() -> void:
	if not is_inside_tree() or _remaining_amount <= 0:
		return
	var available_node: Node3D = get_node_or_null("AvailableVisual") as Node3D
	if available_node == null:
		return
	_cache_available_base_transform()
	_kill_feedback_tween()
	available_node.transform = _available_base_transform

	var pulse_transform: Transform3D = _available_base_transform
	var out_sec: float = 0.08
	var return_sec: float = 0.14
	match get_category():
		ResourceDefinition.Category.WOOD:
			var sway_basis: Basis = Basis(Vector3(0.0, 0.0, 1.0), 0.055).scaled(Vector3(1.02, 0.97, 1.02))
			pulse_transform = Transform3D(_available_base_transform.basis * sway_basis, _available_base_transform.origin)
		ResourceDefinition.Category.STONE:
			var jolt_basis: Basis = _available_base_transform.basis.scaled(Vector3(1.03, 0.94, 1.03))
			pulse_transform = Transform3D(jolt_basis, _available_base_transform.origin + Vector3(0.0, -0.025, 0.0))
			out_sec = 0.06
			return_sec = 0.12
		ResourceDefinition.Category.FOOD:
			var rustle_basis: Basis = Basis(Vector3(1.0, 0.0, 0.0), 0.045).scaled(Vector3(1.04, 0.95, 1.04))
			pulse_transform = Transform3D(_available_base_transform.basis * rustle_basis, _available_base_transform.origin)
			out_sec = 0.07
			return_sec = 0.13
		_:
			var default_basis: Basis = _available_base_transform.basis.scaled(Vector3(1.02, 0.97, 1.02))
			pulse_transform = Transform3D(default_basis, _available_base_transform.origin)

	var tween: Tween = create_tween()
	if tween == null:
		return
	_feedback_tween = tween
	tween.tween_property(available_node, "transform", pulse_transform, out_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(available_node, "transform", _available_base_transform, return_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _cache_felling_rest_pose() -> void:
	if _has_felling_rest_pose:
		return
	var pivot: Node3D = get_node_or_null("AvailableVisual/FellingPivot") as Node3D
	if pivot != null:
		_felling_pivot_rest = pivot.transform
		_has_felling_rest_pose = true
		for mesh_name: String in ["CanopyMesh", "CanopyUpperMesh"]:
			var canopy_node: Node3D = pivot.get_node_or_null(mesh_name) as Node3D
			if canopy_node != null:
				_canopy_rest_transforms[mesh_name] = canopy_node.transform

	var label_node: Label3D = get_node_or_null("DiscoverabilityBadge/BadgeLabel") as Label3D
	if label_node != null and not _has_badge_label_rest_pos:
		_badge_label_rest_pos = label_node.position
		_has_badge_label_rest_pos = true


func _kill_felling_tween() -> void:
	if _felling_tween != null and is_instance_valid(_felling_tween):
		_felling_tween.kill()
	_felling_tween = null


func _reset_felling_visuals() -> void:
	_kill_felling_tween()
	_tree_visual_state = TreeVisualState.STANDING
	if _has_felling_rest_pose:
		var pivot: Node3D = get_node_or_null("AvailableVisual/FellingPivot") as Node3D
		if pivot != null:
			pivot.transform = _felling_pivot_rest
			for mesh_name: Variant in _canopy_rest_transforms.keys():
				var canopy_node: Node3D = pivot.get_node_or_null(String(mesh_name)) as Node3D
				if canopy_node != null:
					canopy_node.transform = _canopy_rest_transforms[mesh_name] as Transform3D
	if _has_badge_label_rest_pos:
		var label_node: Label3D = get_node_or_null("DiscoverabilityBadge/BadgeLabel") as Label3D
		if label_node != null:
			label_node.position = _badge_label_rest_pos


func _on_felling_tween_finished() -> void:
	_felling_tween = null
	_tree_visual_state = TreeVisualState.FALLEN


func _trigger_tree_felling_if_needed(became_depleted: bool) -> void:
	if get_category() != ResourceDefinition.Category.WOOD:
		return
	if _tree_visual_state != TreeVisualState.STANDING:
		return
	if became_depleted:
		_kill_felling_tween()
		_tree_visual_state = TreeVisualState.FALLEN
		return

	var pivot: Node3D = get_node_or_null("AvailableVisual/FellingPivot") as Node3D
	if pivot == null or not is_inside_tree():
		_tree_visual_state = TreeVisualState.FALLEN
		return

	_cache_felling_rest_pose()
	_kill_felling_tween()
	_tree_visual_state = TreeVisualState.FELLING

	var total_sec: float = maxf(felling_duration_sec, 0.05)
	var drop_sec: float = total_sec * 0.74
	var settle_sec: float = total_sec * 0.26

	var mid_tf := Transform3D(Basis.from_euler(Vector3(0.0, 0.0, -1.46)), Vector3(-0.38, 0.27, 0.0))
	var fallen_tf := Transform3D(Basis.from_euler(Vector3(0.0, 0.0, -1.525)), Vector3(-0.55, 0.23, 0.0))

	var tween: Tween = create_tween()
	if tween == null:
		pivot.transform = fallen_tf
		_tree_visual_state = TreeVisualState.FALLEN
		return

	_felling_tween = tween
	tween.set_parallel(true)
	tween.tween_property(pivot, "transform", mid_tf, drop_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var canopy_main: Node3D = pivot.get_node_or_null("CanopyMesh") as Node3D
	if canopy_main != null:
		var canopy_fallen := Transform3D(
			Basis.IDENTITY.scaled(Vector3(0.32, 0.70, 0.76)),
			Vector3(-0.30, 1.45, 0.0)
		)
		tween.tween_property(canopy_main, "transform", canopy_fallen, drop_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var canopy_upper: Node3D = pivot.get_node_or_null("CanopyUpperMesh") as Node3D
	if canopy_upper != null:
		var upper_fallen := Transform3D(
			Basis.IDENTITY.scaled(Vector3(0.32, 0.70, 0.74)),
			Vector3(-0.22, 1.66, -0.14)
		)
		tween.tween_property(canopy_upper, "transform", upper_fallen, drop_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var label_node: Label3D = get_node_or_null("DiscoverabilityBadge/BadgeLabel") as Label3D
	if label_node != null and _has_badge_label_rest_pos:
		var fallen_label_pos := Vector3(_badge_label_rest_pos.x + 0.35, 1.85, _badge_label_rest_pos.z)
		tween.tween_property(label_node, "position", fallen_label_pos, drop_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.chain().tween_property(pivot, "transform", fallen_tf, settle_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(Callable(self, "_on_felling_tween_finished"))


func _sync_bush_fruits(show_available: bool) -> void:
	var fruits_node: Node = get_node_or_null("AvailableVisual/Fruits")
	if fruits_node == null:
		return
	var fruit_nodes: Array[Node3D] = []
	for child: Node in fruits_node.get_children():
		if child is Node3D:
			fruit_nodes.append(child as Node3D)
	var total: int = fruit_nodes.size()
	if total <= 0:
		return
	var visible_count: int = 0
	if show_available and _remaining_amount > 0 and initial_amount > 0:
		var ratio: float = clampf(float(_remaining_amount) / float(initial_amount), 0.0, 1.0)
		visible_count = clampi(ceili(ratio * float(total)), 1, total)
	for i: int in range(total):
		fruit_nodes[i].visible = (i < visible_count)


func _sync_visuals() -> void:
	var available_node: Node3D = get_node_or_null("AvailableVisual") as Node3D
	var depleted_node: Node3D = get_node_or_null("DepletedVisual") as Node3D
	var badge_node: Node3D = get_node_or_null("DiscoverabilityBadge") as Node3D
	var show_available: bool = _remaining_amount > 0
	if not show_available:
		_reset_feedback_visuals()
		_kill_felling_tween()
	if available_node != null:
		available_node.visible = show_available
	if get_category() == ResourceDefinition.Category.FOOD:
		_sync_bush_fruits(show_available)
	if depleted_node != null:
		depleted_node.visible = not show_available
	if badge_node != null:
		badge_node.visible = show_discoverability_badge and show_available
		var label_node: Label3D = badge_node.get_node_or_null("BadgeLabel") as Label3D
		if label_node != null:
			label_node.text = _resolve_discoverability_text()


func _resolve_discoverability_text() -> String:
	if not discoverability_label_text.strip_edges().is_empty():
		return discoverability_label_text
	match get_category():
		ResourceDefinition.Category.WOOD:
			return "Madeira"
		ResourceDefinition.Category.STONE:
			return "Pedra"
		ResourceDefinition.Category.FOOD:
			return "Alimento"
		_:
			return ""

## Testable pre-commit boundary; default has no effects. Guards are held.
func _before_provenance_transfer_commit() -> bool:
	return true

## Opt-in only. `extracted` is zero on replay; `committed_amount` is historical.
func transfer_to_carry_load_with_provenance(carry_load: UnitCarryLoad, operation_id: Variant, lot_id: Variant, requested_amount: int) -> Dictionary:
	if _is_transferring or carry_load == null or carry_load._provenance_busy:
		return {"ok": false, "reason": "busy", "extracted": 0}
	if not CarryProvenanceLedger._id(operation_id) or not CarryProvenanceLedger._id(lot_id) or requested_amount <= 0:
		return {"ok": false, "reason": "invalid_input", "extracted": 0}
	var op := StringName(operation_id)
	if _provenance_receipts.has(op):
		var old: Dictionary = _provenance_receipts[op]
		if old.load.get_ref() != carry_load or old.lot != StringName(lot_id) or old.requested != requested_amount or old.source != source_id or definition == null or old.resource != definition.resource_id or old.weight != definition.unit_weight:
			return {"ok": false, "reason": "operation_conflict", "extracted": 0}
		return {"ok": true, "reason": "", "replayed": true, "extracted": 0, "committed_amount": old.amount}
	_is_transferring = true
	carry_load._provenance_busy = true
	if not is_available() or carry_load._provenance == null or not carry_load.validate_provenance():
		carry_load._provenance_busy = false
		_is_transferring = false
		return {"ok": false, "reason": "unavailable", "extracted": 0}
	var amount: int = mini(_remaining_amount, mini(requested_amount, mini(max_extract_per_operation, carry_load.get_max_additional_units(definition))))
	if amount <= 0:
		carry_load._provenance_busy = false
		_is_transferring = false
		return {"ok": false, "reason": "capacity", "extracted": 0}
	var source_revision: int = _transaction_revision
	var source_definition: ResourceDefinition = definition
	var source_resource: StringName = definition.resource_id
	var source_weight: int = definition.unit_weight
	var remaining_before: int = _remaining_amount
	var plan: Dictionary = carry_load._prepare_provenance_add(op, lot_id, definition.resource_id, definition.unit_weight, amount, CarryProvenanceLedger.FREE_GATHERED)
	if not plan.get("ok", false) or plan.get("replayed", false):
		carry_load._provenance_busy = false
		_is_transferring = false
		return {"ok": false, "reason": "invalid_plan", "extracted": 0}
	if not _before_provenance_transfer_commit() or _transaction_revision != source_revision or _remaining_amount != remaining_before or definition != source_definition or definition.resource_id != source_resource or definition.unit_weight != source_weight or not is_available():
		carry_load._provenance_busy = false
		_is_transferring = false
		return {"ok": false, "reason": "stale_or_aborted", "extracted": 0}
	carry_load._provenance_applying = true
	var applied: bool = carry_load._apply_prepared_provenance_add(plan)
	carry_load._provenance_applying = false
	if not applied:
		carry_load._provenance_busy = false
		_is_transferring = false
		return {"ok": false, "reason": "stale_plan", "extracted": 0}
	# The remaining operations are non-failing integer assignments, with no callbacks.
	_remaining_amount = remaining_before - amount
	_has_extracted = true
	_transaction_revision += 1
	_provenance_receipts[op] = {"load": weakref(carry_load), "source": source_id, "resource": definition.resource_id, "weight": definition.unit_weight, "lot": StringName(lot_id), "requested": requested_amount, "amount": amount}
	var became_depleted: bool = _remaining_amount == 0
	_trigger_tree_felling_if_needed(became_depleted)
	_sync_visuals()
	if not became_depleted:
		_trigger_gather_feedback()
	carry_load._emit_load_changed()
	amount_changed.emit(self, _remaining_amount, -amount)
	if became_depleted:
		depleted.emit(self)
	carry_load._provenance_busy = false
	_is_transferring = false
	return {"ok": true, "reason": "", "replayed": false, "extracted": amount, "committed_amount": amount}
