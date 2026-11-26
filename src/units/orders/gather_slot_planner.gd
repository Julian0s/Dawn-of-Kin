class_name GatherSlotPlanner
extends RefCounted
## Pure spatial helper resolving navigable approach slots around ResourceSource nodes
## and drop-off slots inside CampStorageZone without penetrating solid source geometry.

const SOURCE_ANGLE_SAMPLES: int = 16


static func collect_other_unit_positions(
	self_unit: Unit,
	include_reserved_targets: bool = true
) -> Array[Vector3]:
	var occupied: Array[Vector3] = []
	if self_unit == null or not is_instance_valid(self_unit) or not self_unit.is_inside_tree():
		return occupied

	var tree: SceneTree = self_unit.get_tree()
	if tree == null:
		return occupied

	for node: Node in tree.get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
		if not (node is Unit):
			continue
		var other: Unit = node as Unit
		if other == self_unit or not is_instance_valid(other) or not other.is_inside_tree():
			continue

		if include_reserved_targets:
			var other_order: UnitOrder = other.get_current_order()
			if other_order is MoveOrder:
				var move_target: Vector3 = (other_order as MoveOrder).resolved_target
				if move_target.is_finite():
					occupied.append(move_target)
					continue
			elif other_order != null and other_order.has_method("get_reserved_target"):
				var reserved: Variant = other_order.call("get_reserved_target")
				if reserved is Vector3 and (reserved as Vector3).is_finite():
					occupied.append(reserved as Vector3)
					continue

		occupied.append(other.global_position)

	return occupied


static func compute_source_approach_slot(
	unit_pos: Vector3,
	source: ResourceSource,
	world_nav: WorldNavigation,
	occupied_positions: Array[Vector3] = [],
	agent_radius: float = WorldNavigation.DEFAULT_AGENT_RADIUS
) -> Dictionary:
	if not unit_pos.is_finite():
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_unit_position"}
	if source == null or not is_instance_valid(source) or not source.is_inside_tree():
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_source"}
	if world_nav == null or not world_nav.is_navigation_ready():
		return {"valid": false, "position": Vector3.ZERO, "reason": "navigation_not_ready"}

	var source_pos: Vector3 = source.global_position
	if not source_pos.is_finite():
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_source"}

	var solid_radius: float = maxf(source.get_solid_radius(), 0.0)
	var inter_radius: float = maxf(source.get_interaction_radius(), 0.1)
	var min_safe_radius: float = (solid_radius + agent_radius) if solid_radius > 0.0 else maxf(agent_radius * 0.6, 0.45)

	if inter_radius < min_safe_radius:
		return {"valid": false, "position": Vector3.ZERO, "reason": "source_geometry_unreachable"}

	var preferred_radius: float = clampf(min_safe_radius + 0.02, min_safe_radius, maxf(min_safe_radius, inter_radius - 0.28))
	var candidate_radii: Array[float] = [
		preferred_radius,
		clampf(min_safe_radius + 0.08, min_safe_radius, maxf(min_safe_radius, inter_radius - 0.16)),
		minf(min_safe_radius + 0.02, inter_radius),
	]

	var to_unit_xz := Vector2(unit_pos.x - source_pos.x, unit_pos.z - source_pos.z)
	var base_angle: float = atan2(to_unit_xz.y, to_unit_xz.x) if to_unit_xz.length_squared() > 0.0001 else 0.0
	var min_worker_spacing: float = agent_radius * 2.0 + 0.1

	var best_separated := Vector3(INF, INF, INF)
	var best_separated_dist: float = INF
	var best_fallback := Vector3(INF, INF, INF)
	var best_fallback_dist: float = INF

	for ring_radius: float in candidate_radii:
		var separated_hit_step: int = -1
		for step: int in range(SOURCE_ANGLE_SAMPLES):
			var half_step: int = int(floor(float(step + 1) * 0.5))
			var offset_idx: int = half_step * (1 if (step % 2) == 1 else -1) if step > 0 else 0
			var angle: float = base_angle + float(offset_idx) * (TAU / float(SOURCE_ANGLE_SAMPLES))
			var candidate := Vector3(
				source_pos.x + cos(angle) * ring_radius,
				source_pos.y,
				source_pos.z + sin(angle) * ring_radius
			)
			var snapped: Vector3 = world_nav.snap_to_navmesh(candidate)
			if not snapped.is_finite():
				continue
			if absf(snapped.y - source_pos.y) > 2.5:
				continue

			var dist_from_source: float = Vector2(snapped.x - source_pos.x, snapped.z - source_pos.z).length()
			if dist_from_source < min_safe_radius or dist_from_source > inter_radius:
				continue

			var path_res: WorldNavigation.PathResult = world_nav.find_path(unit_pos, snapped)
			if path_res.status != WorldNavigation.QueryStatus.OK or path_res.path.is_empty():
				continue

			var resolved: Vector3 = path_res.resolved_target
			var resolved_source_dist: float = Vector2(resolved.x - source_pos.x, resolved.z - source_pos.z).length()
			if resolved_source_dist < min_safe_radius or resolved_source_dist > inter_radius:
				continue

			var travel_dist: float = Vector2(resolved.x - unit_pos.x, resolved.z - unit_pos.z).length()
			if _is_separated_from_all(resolved, occupied_positions, min_worker_spacing):
				if travel_dist < best_separated_dist:
					best_separated_dist = travel_dist
					best_separated = resolved
				if separated_hit_step < 0:
					separated_hit_step = step
			elif travel_dist < best_fallback_dist:
				best_fallback_dist = travel_dist
				best_fallback = resolved

			# Once a valid separated slot is found nearest the unit approach angle, compare only
			# its immediate symmetric neighbors on the same ring instead of scanning all 48 slots.
			if separated_hit_step >= 0 and (step - separated_hit_step) >= 2:
				break
		if best_separated.is_finite():
			break

	if best_separated.is_finite():
		return {"valid": true, "position": best_separated, "reason": ""}
	if best_fallback.is_finite():
		return {"valid": true, "position": best_fallback, "reason": ""}
	return {"valid": false, "position": Vector3.ZERO, "reason": "source_unreachable"}


static func compute_camp_dropoff_slot(
	unit_pos: Vector3,
	camp_zone: CampStorageZone,
	world_nav: WorldNavigation,
	occupied_positions: Array[Vector3] = [],
	agent_radius: float = WorldNavigation.DEFAULT_AGENT_RADIUS
) -> Dictionary:
	if not unit_pos.is_finite():
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_unit_position"}
	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid():
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_camp_zone"}
	if world_nav == null or not world_nav.is_navigation_ready():
		return {"valid": false, "position": Vector3.ZERO, "reason": "navigation_not_ready"}

	var candidates: Array[Vector3] = camp_zone.get_candidate_slots()
	var anchor: Vector3 = camp_zone.get_anchor_position()
	if candidates.is_empty() and anchor.is_finite():
		candidates.append(anchor)

	var min_worker_spacing: float = agent_radius * 2.0 + 0.1
	var best_separated := Vector3(INF, INF, INF)
	var best_separated_dist: float = INF
	var best_fallback := Vector3(INF, INF, INF)
	var best_fallback_dist: float = INF

	for slot: Vector3 in candidates:
		if not slot.is_finite():
			continue
		var snapped: Vector3 = world_nav.snap_to_navmesh(slot)
		if not snapped.is_finite():
			continue
		var horiz_offset: float = Vector2(snapped.x - slot.x, snapped.z - slot.z).length()
		if horiz_offset > camp_zone.max_nav_snap_distance or absf(snapped.y - slot.y) > 2.5:
			continue
		if not camp_zone.is_position_in_bounds(snapped):
			continue

		var path_res: WorldNavigation.PathResult = world_nav.find_path(unit_pos, snapped)
		if path_res.status != WorldNavigation.QueryStatus.OK or path_res.path.is_empty():
			continue

		var resolved: Vector3 = path_res.resolved_target
		var travel_dist: float = Vector2(resolved.x - unit_pos.x, resolved.z - unit_pos.z).length()
		if _is_separated_from_all(resolved, occupied_positions, min_worker_spacing):
			if travel_dist < best_separated_dist:
				best_separated_dist = travel_dist
				best_separated = resolved
		elif travel_dist < best_fallback_dist:
			best_fallback_dist = travel_dist
			best_fallback = resolved

	if best_separated.is_finite():
		return {"valid": true, "position": best_separated, "reason": ""}
	if best_fallback.is_finite():
		return {"valid": true, "position": best_fallback, "reason": ""}
	return {"valid": false, "position": Vector3.ZERO, "reason": "camp_unreachable"}


static func _is_separated_from_all(
	pos: Vector3,
	occupied_positions: Array[Vector3],
	min_spacing: float
) -> bool:
	var min_sq: float = min_spacing * min_spacing
	for other_pos: Vector3 in occupied_positions:
		if not other_pos.is_finite():
			continue
		var dx: float = pos.x - other_pos.x
		var dz: float = pos.z - other_pos.z
		if dx * dx + dz * dz < min_sq:
			return false
	return true
