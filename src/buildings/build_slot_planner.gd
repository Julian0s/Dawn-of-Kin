class_name BuildSlotPlanner
extends RefCounted
## Pure spatial helper for T3.3 construction logistics:
## resolves pile approach slots, site perimeter drop-off/builder standby slots,
## exact reach checks, and World3D-isolated occupied position collection.

const PILE_ANGLE_SAMPLES: int = 8
const HEIGHT_TOLERANCE: float = 2.5
const REACH_PROBE_HEIGHT: float = 0.55


static func has_clear_physical_access(
	from_pos: Vector3,
	to_pos: Vector3,
	world_3d: World3D,
	collision_mask: int = CollisionLayers.MASK_WORLD_SOLID
) -> bool:
	if not from_pos.is_finite() or not to_pos.is_finite():
		return false
	if world_3d == null or world_3d.direct_space_state == null:
		return true
	var delta_xz := Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z)
	if delta_xz.length_squared() <= 0.0004:
		return true
	var p0 := Vector3(from_pos.x, from_pos.y + REACH_PROBE_HEIGHT, from_pos.z)
	var p1 := Vector3(to_pos.x, to_pos.y + REACH_PROBE_HEIGHT, to_pos.z)
	var ray := PhysicsRayQueryParameters3D.create(p0, p1, collision_mask)
	ray.hit_from_inside = true
	return world_3d.direct_space_state.intersect_ray(ray).is_empty()


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
	var self_world: World3D = self_unit.get_world_3d()

	for node: Node in tree.get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
		if not (node is Unit):
			continue
		var other: Unit = node as Unit
		if other == self_unit or not is_instance_valid(other) or not other.is_inside_tree():
			continue
		if self_world != null and other.get_world_3d() != self_world:
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


static func is_unit_in_pile_reach(
	unit_pos: Vector3,
	pile_pos: Vector3,
	reach_radius: float = ConstructionSite.DEFAULT_PILE_PICKUP_REACH,
	world_3d: World3D = null
) -> bool:
	if not unit_pos.is_finite() or not pile_pos.is_finite():
		return false
	if absf(unit_pos.y - pile_pos.y) > HEIGHT_TOLERANCE:
		return false
	var dist: float = Vector2(unit_pos.x - pile_pos.x, unit_pos.z - pile_pos.z).length()
	if dist > reach_radius + 0.05:
		return false
	return has_clear_physical_access(unit_pos, pile_pos, world_3d)


static func is_unit_in_site_dropoff_range(
	unit_pos: Vector3,
	site: ConstructionSite,
	reach_tolerance: float = ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
	world_3d: World3D = null
) -> bool:
	if not unit_pos.is_finite() or site == null or not is_instance_valid(site):
		return false
	var site_pos: Vector3 = site.global_position if site.is_inside_tree() else site.position
	if not site_pos.is_finite() or absf(unit_pos.y - site_pos.y) > HEIGHT_TOLERANCE:
		return false
	var rect: Rect2 = site.get_footprint_rect()
	var closest_x: float = clampf(unit_pos.x, rect.position.x, rect.end.x)
	var closest_z: float = clampf(unit_pos.z, rect.position.y, rect.end.y)
	var dx: float = unit_pos.x - closest_x
	var dz: float = unit_pos.z - closest_z
	if sqrt(dx * dx + dz * dz) > reach_tolerance:
		return false
	var resolved_world: World3D = world_3d
	if resolved_world == null and site.is_inside_tree():
		resolved_world = site.get_world_3d()
	if resolved_world == null:
		return true
	var edge_target := Vector3(closest_x, site_pos.y, closest_z)
	return has_clear_physical_access(unit_pos, edge_target, resolved_world)


static func compute_pile_approach_slot(
	unit_pos: Vector3,
	pile_pos: Vector3,
	world_nav: WorldNavigation,
	occupied_positions: Array[Vector3] = [],
	agent_radius: float = WorldNavigation.DEFAULT_AGENT_RADIUS,
	reach_radius: float = ConstructionSite.DEFAULT_PILE_PICKUP_REACH
) -> Dictionary:
	if not unit_pos.is_finite() or not pile_pos.is_finite():
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_position"}
	if world_nav == null or not world_nav.is_navigation_ready():
		return {"valid": false, "position": Vector3.ZERO, "reason": "navigation_not_ready"}

	var nav_world_3d: World3D = world_nav.get_world_3d() if world_nav.is_inside_tree() else null
	var min_worker_spacing: float = agent_radius * 2.0 + 0.08
	var candidate_offsets: Array[Vector3] = []

	var to_unit := Vector2(unit_pos.x - pile_pos.x, unit_pos.z - pile_pos.z)
	var base_angle: float = atan2(to_unit.y, to_unit.x) if to_unit.length_squared() > 0.0001 else 0.0
	var radii: Array[float] = [
		minf(0.45, maxf(0.25, reach_radius * 0.45)),
		minf(0.88, maxf(0.45, reach_radius * 0.72)),
		0.0,
	]
	for r: float in radii:
		if r <= 0.05:
			candidate_offsets.append(pile_pos)
			continue
		for step: int in range(PILE_ANGLE_SAMPLES):
			var half_step: int = int(floor(float(step + 1) * 0.5))
			var offset_idx: int = half_step * (1 if (step % 2) == 1 else -1) if step > 0 else 0
			var angle: float = base_angle + float(offset_idx) * (TAU / float(PILE_ANGLE_SAMPLES))
			candidate_offsets.append(Vector3(
				pile_pos.x + cos(angle) * r,
				pile_pos.y,
				pile_pos.z + sin(angle) * r
			))

	var best_separated := Vector3(INF, INF, INF)
	var best_separated_dist: float = INF
	var best_fallback := Vector3(INF, INF, INF)
	var best_fallback_dist: float = INF

	for candidate: Vector3 in candidate_offsets:
		var snapped: Vector3 = world_nav.snap_to_navmesh(candidate)
		if not snapped.is_finite() or absf(snapped.y - pile_pos.y) > HEIGHT_TOLERANCE:
			continue
		var snap_pile_dist: float = Vector2(snapped.x - pile_pos.x, snapped.z - pile_pos.z).length()
		if snap_pile_dist > reach_radius:
			continue
		var path_res: WorldNavigation.PathResult = world_nav.find_path(unit_pos, snapped)
		if not _is_unit_connected_to_path(unit_pos, path_res, world_nav):
			continue
		var resolved: Vector3 = path_res.resolved_target
		var resolved_dist: float = Vector2(resolved.x - pile_pos.x, resolved.z - pile_pos.z).length()
		if resolved_dist > reach_radius:
			continue
		if not has_clear_physical_access(resolved, pile_pos, nav_world_3d):
			continue

		var travel_dist: float = _path_length(path_res.path)
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
	return {"valid": false, "position": Vector3.ZERO, "reason": "pile_unreachable"}


static func compute_site_perimeter_slot(
	unit_pos: Vector3,
	site: ConstructionSite,
	world_nav: WorldNavigation,
	occupied_positions: Array[Vector3] = [],
	agent_radius: float = WorldNavigation.DEFAULT_AGENT_RADIUS,
	outward_margin: float = ConstructionSite.DEFAULT_DROPOFF_OUTWARD_MARGIN,
	preferred_slot_index: int = -1,
	reach_tolerance: float = ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE
) -> Dictionary:
	if not unit_pos.is_finite():
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_unit_position"}
	if site == null or not is_instance_valid(site) or not site.is_valid() or site.definition == null:
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_site"}
	if world_nav == null or not world_nav.is_navigation_ready():
		return {"valid": false, "position": Vector3.ZERO, "reason": "navigation_not_ready"}

	var site_pos: Vector3 = site.global_position if site.is_inside_tree() else site.position
	if not site_pos.is_finite():
		return {"valid": false, "position": Vector3.ZERO, "reason": "invalid_site"}

	var nav_world_3d: World3D = world_nav.get_world_3d() if world_nav.is_inside_tree() else null
	var min_worker_spacing: float = agent_radius * 2.0 + 0.1
	var margins: Array[float] = [outward_margin, minf(reach_tolerance * 0.9, outward_margin + 0.35)]
	var rect: Rect2 = site.get_footprint_rect()

	var best_separated := Vector3(INF, INF, INF)
	var best_separated_dist: float = INF
	var best_fallback := Vector3(INF, INF, INF)
	var best_fallback_dist: float = INF

	for margin: float in margins:
		var offsets: Array[Vector2] = site.definition.get_perimeter_offsets(margin)
		if offsets.is_empty():
			continue
		var count: int = offsets.size()
		var start_idx: int = posmod(preferred_slot_index, count) if preferred_slot_index >= 0 else 0
		for i: int in range(count):
			var idx: int = (start_idx + i) % count
			var off: Vector2 = offsets[idx]
			var raw_pt := Vector3(site_pos.x + off.x, site_pos.y, site_pos.z + off.y)
			var snapped: Vector3 = world_nav.snap_to_navmesh(raw_pt)
			if not snapped.is_finite() or absf(snapped.y - site_pos.y) > HEIGHT_TOLERANCE:
				continue
			if _distance_to_rect(snapped, rect) > reach_tolerance:
				continue

			var path_res: WorldNavigation.PathResult = world_nav.find_path(unit_pos, snapped)
			if not _is_unit_connected_to_path(unit_pos, path_res, world_nav):
				continue
			var resolved: Vector3 = path_res.resolved_target
			if not is_unit_in_site_dropoff_range(resolved, site, reach_tolerance, nav_world_3d):
				continue

			var travel_dist: float = _path_length(path_res.path)
			# When a specific builder slot index is requested, give modest preference
			# to earlier unblocked slots so multiple builders fan out around the perimeter.
			var score: float = travel_dist + (float(i) * 0.35 if preferred_slot_index >= 0 else 0.0)
			if _is_separated_from_all(resolved, occupied_positions, min_worker_spacing):
				if score < best_separated_dist:
					best_separated_dist = score
					best_separated = resolved
			elif score < best_fallback_dist:
				best_fallback_dist = score
				best_fallback = resolved

		if best_separated.is_finite():
			break

	if best_separated.is_finite():
		return {"valid": true, "position": best_separated, "reason": ""}
	if best_fallback.is_finite():
		return {"valid": true, "position": best_fallback, "reason": ""}
	return {"valid": false, "position": Vector3.ZERO, "reason": "site_unreachable"}


static func find_best_pickup_candidate(
	unit: Unit,
	unit_pos: Vector3,
	site: ConstructionSite,
	world_nav: WorldNavigation,
	occupied_positions: Array[Vector3],
	agent_radius: float = WorldNavigation.DEFAULT_AGENT_RADIUS
) -> Dictionary:
	if unit == null or not is_instance_valid(unit) or site == null or not site.is_valid():
		return {"found": false, "reason": "invalid_context"}
	var inventory: SettlementInventory = site.get_inventory()
	var carry_load: UnitCarryLoad = unit.get_carry_load()
	if inventory == null or carry_load == null:
		return {"found": false, "reason": "invalid_inventory"}
	if world_nav == null or not world_nav.is_navigation_ready():
		return {"found": false, "reason": "navigation_not_ready"}

	var best_candidate: Dictionary = {}
	var best_dist_sq: float = INF
	var saw_any_reserved: bool = false
	var saw_any_room: bool = false
	var last_fail_reason: String = "no_reserved_piles"

	var required: Dictionary = site.get_required_amounts()
	var keys: Array[StringName] = []
	for k: Variant in required.keys():
		keys.append(k as StringName)
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))

	for res_id: StringName in keys:
		var claimable_for_site: int = site.get_remaining_supply_to_claim(res_id, unit)
		if claimable_for_site <= 0:
			continue
		var res_def: ResourceDefinition = site.get_resource_definition(res_id)
		if res_def == null or not res_def.is_valid():
			continue
		var carry_room: int = carry_load.get_max_additional_units(res_def)
		if carry_room <= 0:
			continue
		saw_any_room = true

		var entries: Array[Dictionary] = inventory.get_reserved_pile_entries(
			site.reservation_id,
			res_id,
			unit_pos
		)
		for entry: Dictionary in entries:
			var pile_id: int = int(entry["pile_id"])
			var pile: GroundResourcePile = entry["pile"] as GroundResourcePile
			var reserved_on_pile: int = int(entry["reserved_amount"])
			var other_pending: int = site.get_pending_pickup_amount(pile_id, res_id, unit)
			var available_to_claim: int = mini(
				mini(claimable_for_site, carry_room),
				maxi(0, reserved_on_pile - other_pending)
			)
			if available_to_claim <= 0:
				continue
			saw_any_reserved = true

			var pile_pos: Vector3 = entry["world_pos"] as Vector3
			var slot_res: Dictionary = compute_pile_approach_slot(
				unit_pos,
				pile_pos,
				world_nav,
				occupied_positions,
				agent_radius
			)
			if not (slot_res.get("valid", false) as bool):
				last_fail_reason = str(slot_res.get("reason", "pile_unreachable"))
				continue

			var slot_pos: Vector3 = slot_res["position"] as Vector3
			var dist_sq: float = Vector2(slot_pos.x - unit_pos.x, slot_pos.z - unit_pos.z).length_squared()
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_candidate = {
					"found": true,
					"pile_id": pile_id,
					"pile": pile,
					"resource_id": res_id,
					"resource_def": res_def,
					"pile_pos": pile_pos,
					"slot_pos": slot_pos,
					"reserved_on_pile": reserved_on_pile,
					"available_claim": available_to_claim,
					"reason": "",
				}

	if not best_candidate.is_empty():
		return best_candidate
	if not saw_any_room and not carry_load.is_empty():
		return {"found": false, "reason": "carry_load_full"}
	if not saw_any_reserved:
		return {"found": false, "reason": "no_reserved_piles"}
	return {"found": false, "reason": last_fail_reason}


static func _distance_to_rect(pos: Vector3, rect: Rect2) -> float:
	var dx: float = maxf(maxf(rect.position.x - pos.x, 0.0), pos.x - rect.end.x)
	var dz: float = maxf(maxf(rect.position.y - pos.z, 0.0), pos.z - rect.end.y)
	return sqrt(dx * dx + dz * dz)


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


static func _is_unit_connected_to_path(
	unit_pos: Vector3,
	path_res: WorldNavigation.PathResult,
	world_nav: WorldNavigation
) -> bool:
	if path_res == null or path_res.status != WorldNavigation.QueryStatus.OK or path_res.path.is_empty():
		return false
	var start_pt: Vector3 = path_res.path[0]
	var start_dist_xz: float = Vector2(start_pt.x - unit_pos.x, start_pt.z - unit_pos.z).length()
	var start_dist_y: float = absf(start_pt.y - unit_pos.y)
	if start_dist_xz > WorldNavigation.REACHABLE_TOLERANCE_XZ + 0.5 or start_dist_y > WorldNavigation.REACHABLE_TOLERANCE_Y:
		return false
	if start_dist_xz > 0.25 and world_nav != null and world_nav.is_inside_tree():
		if not has_clear_physical_access(unit_pos, start_pt, world_nav.get_world_3d()):
			return false
	return true


static func _path_length(path: PackedVector3Array) -> float:
	if path.size() < 2:
		return 0.0
	var total: float = 0.0
	for i: int in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total
