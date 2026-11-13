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

	var solid_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		CollisionLayers.MASK_WORLD_SOLID
	)
	solid_query.collide_with_areas = false
	solid_query.collide_with_bodies = true
	var solid_hit: Dictionary = space_state.intersect_ray(solid_query)

	var has_sel: bool = not sel_hit.is_empty()
	var has_solid: bool = not solid_hit.is_empty()

	if has_sel:
		var picked_unit: Unit = _resolve_unit_from_collider(sel_hit.get("collider"))
		if picked_unit != null:
			var sel_pos: Vector3 = sel_hit["position"] as Vector3
			var sel_dist: float = ray_origin.distance_to(sel_pos)
			var occluded: bool = false
			if has_solid:
				var solid_pos: Vector3 = solid_hit["position"] as Vector3
				var solid_dist: float = ray_origin.distance_to(solid_pos)
				if solid_dist + OCCLUSION_EPSILON < sel_dist:
					occluded = true
			if not occluded:
				var sel_normal: Vector3 = sel_hit["normal"] as Vector3
				return PickResult.from_unit(picked_unit, sel_pos, sel_normal, sel_hit.get("collider"))

	if has_solid:
		var solid_collider: Object = solid_hit.get("collider")
		var solid_pos: Vector3 = solid_hit["position"] as Vector3
		var solid_normal: Vector3 = solid_hit["normal"] as Vector3
		var col_obj: CollisionObject3D = solid_collider as CollisionObject3D
		if col_obj != null:
			if (col_obj.collision_layer & CollisionLayers.MASK_OBSTACLES) != 0:
				return PickResult.from_obstacle(solid_pos, solid_normal, solid_collider)
			if (col_obj.collision_layer & CollisionLayers.MASK_TERRAIN) != 0:
				return PickResult.from_ground(solid_pos, solid_normal, solid_collider)

	return PickResult.none()


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
