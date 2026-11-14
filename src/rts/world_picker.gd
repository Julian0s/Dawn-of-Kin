class_name WorldPicker
extends RefCounted
## Converts viewport screen coordinates into 3D PickResult values via real physics raycasts.
## Prioritizes unit selection Area3D targets while respecting solid geometry occlusion.

const DEFAULT_MAX_RAY_DISTANCE: float = 250.0
const OCCLUSION_EPSILON: float = 0.05


func pick_at_screen_pos(
	camera: Camera3D,
	screen_pos: Vector2,
	max_distance: float = DEFAULT_MAX_RAY_DISTANCE
) -> PickResult:
	if camera == null or not camera.is_inside_tree() or not screen_pos.is_finite():
		return PickResult.none()

	var world_3d: World3D = camera.get_world_3d()
	if world_3d == null:
		return PickResult.none()

	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if space_state == null:
		return PickResult.none()

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	return pick_along_ray(space_state, ray_origin, ray_dir, max_distance)


func pick_along_ray(
	space_state: PhysicsDirectSpaceState3D,
	ray_origin: Vector3,
	ray_dir: Vector3,
	max_distance: float = DEFAULT_MAX_RAY_DISTANCE
) -> PickResult:
	if space_state == null or not ray_origin.is_finite() or not ray_dir.is_finite():
		return PickResult.none()
	if ray_dir.length_squared() < 0.000001 or max_distance <= 0.0:
		return PickResult.none()

	var norm_dir: Vector3 = ray_dir.normalized()
	var ray_end: Vector3 = ray_origin + norm_dir * max_distance

	var selection_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		CollisionLayers.MASK_SELECTION
	)
	selection_query.collide_with_areas = true
	selection_query.collide_with_bodies = false
	var sel_hit: Dictionary = space_state.intersect_ray(selection_query)

	var resource_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		CollisionLayers.MASK_RESOURCES
	)
	resource_query.collide_with_areas = true
	resource_query.collide_with_bodies = true
	var res_hit: Dictionary = space_state.intersect_ray(resource_query)

	var solid_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		CollisionLayers.MASK_WORLD_SOLID
	)
	solid_query.collide_with_areas = false
	solid_query.collide_with_bodies = true
	var solid_hit: Dictionary = space_state.intersect_ray(solid_query)

	var has_sel: bool = not sel_hit.is_empty()
	var has_res: bool = not res_hit.is_empty()
	var has_solid: bool = not solid_hit.is_empty()

	var picked_unit: Unit = _resolve_unit_from_collider(sel_hit.get("collider")) if has_sel else null
	var unit_pos: Vector3 = Vector3.ZERO
	var unit_dist: float = INF
	var unit_visible: bool = false
	if picked_unit != null:
		unit_pos = sel_hit["position"] as Vector3
		unit_dist = ray_origin.distance_to(unit_pos)
		unit_visible = not _is_distance_occluded_by_hit(ray_origin, solid_hit, unit_dist)

	var picked_source: ResourceSource = _resolve_resource_source_from_collider(res_hit.get("collider")) if has_res else null
	var source_pos: Vector3 = Vector3.ZERO
	var source_dist: float = INF
	var source_visible: bool = false
	if picked_source != null:
		source_pos = res_hit["position"] as Vector3
		source_dist = ray_origin.distance_to(source_pos)
		source_visible = not _is_source_occluded(
			space_state,
			ray_origin,
			ray_end,
			solid_hit,
			picked_source,
			source_dist
		)

	if unit_visible and source_visible:
		if source_dist + OCCLUSION_EPSILON < unit_dist:
			return _build_resource_pick(picked_source, res_hit, source_pos)
		return PickResult.from_unit(
			picked_unit,
			unit_pos,
			_safe_hit_normal(sel_hit),
			sel_hit.get("collider")
		)

	if unit_visible:
		return PickResult.from_unit(
			picked_unit,
			unit_pos,
			_safe_hit_normal(sel_hit),
			sel_hit.get("collider")
		)

	if source_visible:
		return _build_resource_pick(picked_source, res_hit, source_pos)

	if has_solid:
		var solid_collider: Object = solid_hit.get("collider")
		var solid_pos: Vector3 = solid_hit["position"] as Vector3
		var solid_normal: Vector3 = _safe_hit_normal(solid_hit)
		var col_obj: CollisionObject3D = solid_collider as CollisionObject3D
		if col_obj != null:
			if (col_obj.collision_layer & CollisionLayers.MASK_OBSTACLES) != 0:
				return PickResult.from_obstacle(solid_pos, solid_normal, solid_collider)
			if (col_obj.collision_layer & CollisionLayers.MASK_TERRAIN) != 0:
				return PickResult.from_ground(solid_pos, solid_normal, solid_collider)

	return PickResult.none()


static func _build_resource_pick(
	source: ResourceSource,
	res_hit: Dictionary,
	source_pos: Vector3
) -> PickResult:
	return PickResult.from_resource_source(
		source,
		source_pos,
		_safe_hit_normal(res_hit),
		res_hit.get("collider")
	)


static func _safe_hit_normal(hit: Dictionary) -> Vector3:
	var n: Vector3 = hit.get("normal", Vector3.UP) as Vector3
	if not n.is_finite() or n.length_squared() < 0.0001:
		return Vector3.UP
	return n.normalized()


static func _is_distance_occluded_by_hit(
	ray_origin: Vector3,
	blocking_hit: Dictionary,
	target_dist: float
) -> bool:
	if blocking_hit.is_empty():
		return false
	var solid_pos: Vector3 = blocking_hit["position"] as Vector3
	var solid_dist: float = ray_origin.distance_to(solid_pos)
	return solid_dist + OCCLUSION_EPSILON < target_dist


static func _is_source_occluded(
	space_state: PhysicsDirectSpaceState3D,
	ray_origin: Vector3,
	ray_end: Vector3,
	initial_solid_hit: Dictionary,
	source: ResourceSource,
	source_dist: float
) -> bool:
	if initial_solid_hit.is_empty():
		return false
	var solid_collider: Object = initial_solid_hit.get("collider")
	if _resolve_resource_source_from_collider(solid_collider) == source:
		var self_rids: Array[RID] = _collect_source_collision_rids(source)
		var ext_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			ray_origin,
			ray_end,
			CollisionLayers.MASK_WORLD_SOLID,
			self_rids
		)
		ext_query.collide_with_areas = false
		ext_query.collide_with_bodies = true
		var ext_hit: Dictionary = space_state.intersect_ray(ext_query)
		return _is_distance_occluded_by_hit(ray_origin, ext_hit, source_dist)
	return _is_distance_occluded_by_hit(ray_origin, initial_solid_hit, source_dist)


static func _collect_source_collision_rids(source: ResourceSource) -> Array[RID]:
	var rids: Array[RID] = []
	if source == null or not is_instance_valid(source):
		return rids
	var stack: Array[Node] = [source]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is CollisionObject3D:
			var rid: RID = (current as CollisionObject3D).get_rid()
			if rid.is_valid() and not rids.has(rid):
				rids.append(rid)
		for child: Node in current.get_children():
			stack.append(child)
	var parent_node: Node = source.get_parent()
	if parent_node is CollisionObject3D:
		var parent_rid: RID = (parent_node as CollisionObject3D).get_rid()
		if parent_rid.is_valid() and not rids.has(parent_rid):
			rids.append(parent_rid)
	return rids


static func _resolve_unit_from_collider(collider: Object) -> Unit:
	if collider == null:
		return null
	if collider is Unit:
		return collider as Unit
	if collider is Node:
		var cursor: Node = (collider as Node).get_parent()
		while cursor != null:
			if cursor is Unit:
				return cursor as Unit
			cursor = cursor.get_parent()
	return null


static func _resolve_resource_source_from_collider(collider: Object) -> ResourceSource:
	if collider == null:
		return null
	if collider is ResourceSource:
		return collider as ResourceSource
	if collider is Node:
		var node: Node = collider as Node
		var cursor: Node = node.get_parent()
		while cursor != null:
			if cursor is ResourceSource:
				return cursor as ResourceSource
			cursor = cursor.get_parent()
		for child: Node in node.get_children():
			if child is ResourceSource:
				return child as ResourceSource
	return null
