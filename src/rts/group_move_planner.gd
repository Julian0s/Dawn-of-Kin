class_name GroupMovePlanner
extends RefCounted
## Pure RTS group movement target planner.
## Computes deterministic, obstacle-aware, non-overlapping concentric target slots
## around a destination and assigns them cleanly to units without crossing paths.

const DEFAULT_AGENT_RADIUS: float = 0.5
const DEFAULT_CLEARANCE: float = 0.8
const RING_BASE_SAMPLES: int = 6
const MAX_RING_COUNT: int = 8
const PAIR_HALF_SPREAD_RATIO: float = 0.55
const COST_IMPROVEMENT_EPSILON: float = 0.0005


class PlanResult extends RefCounted:
	var valid: bool = false
	var anchor_position: Vector3 = Vector3.ZERO
	var targets: Array[Vector3] = []
	var all_slots_reachable: bool = false
	var requested_target_reachable: bool = true


static func plan_targets(
	unit_positions: Array[Vector3],
	requested_target: Vector3,
	agent_radius: float = DEFAULT_AGENT_RADIUS,
	clearance: float = DEFAULT_CLEARANCE,
	snap_callable: Callable = Callable(),
	reachability_callable: Callable = Callable(),
	allow_snapped_anchor_on_unreachable: bool = true
) -> PlanResult:
	var result := PlanResult.new()
	var unit_count: int = unit_positions.size()
	if unit_count == 0 or not requested_target.is_finite():
		return result

	for unit_pos: Vector3 in unit_positions:
		if not unit_pos.is_finite():
			return result

	var effective_radius: float = maxf(agent_radius, 0.1)
	var effective_clearance: float = maxf(clearance, 0.0)
	var min_spacing: float = maxf(effective_radius * 2.0 + effective_clearance, 0.25)

	var has_reachability: bool = reachability_callable.is_valid()
	var req_reachable: bool = true
	if has_reachability:
		req_reachable = _any_unit_can_reach(unit_positions, requested_target, reachability_callable)
	result.requested_target_reachable = req_reachable

	if not allow_snapped_anchor_on_unreachable and has_reachability and not req_reachable:
		return _build_unreachable_fallback_plan(unit_positions, requested_target, min_spacing)

	var anchor: Vector3 = _snap_position(requested_target, snap_callable)
	if not anchor.is_finite():
		anchor = requested_target

	if has_reachability and not _any_unit_can_reach(unit_positions, anchor, reachability_callable):
		var recovered: Vector3 = _find_nearby_reachable_anchor(
			unit_positions,
			requested_target,
			min_spacing,
			snap_callable,
			reachability_callable
		)
		if recovered.is_finite():
			anchor = recovered
		elif not req_reachable:
			return _build_unreachable_fallback_plan(unit_positions, requested_target, min_spacing)

	result.anchor_position = anchor

	if unit_count == 1:
		var single_reachable: bool = true
		if has_reachability:
			single_reachable = _is_reachable(unit_positions[0], anchor, reachability_callable)
		if not single_reachable and not allow_snapped_anchor_on_unreachable:
			return _build_unreachable_fallback_plan(unit_positions, requested_target, min_spacing)
		result.targets.append(anchor)
		result.all_slots_reachable = single_reachable
		result.valid = true
		return result

	var group_centroid: Vector3 = _compute_centroid(unit_positions)
	var right_axis: Vector3 = _compute_right_axis_xz(group_centroid, anchor)
	var raw_candidates: Array[Vector3] = _generate_raw_candidates(unit_count, anchor, right_axis, min_spacing)

	var accepted_slots: Array[Vector3] = []
	for raw_pos: Vector3 in raw_candidates:
		if accepted_slots.size() >= unit_count:
			break
		var candidate: Vector3 = _snap_position(raw_pos, snap_callable)
		if not candidate.is_finite():
			continue
		if has_reachability and not _any_unit_can_reach(unit_positions, candidate, reachability_callable):
			continue
		if not _is_separated_from_all(candidate, accepted_slots, min_spacing):
			continue
		accepted_slots.append(candidate)

	if accepted_slots.size() < unit_count:
		# Fill any remaining slots with deterministic geometric offsets around anchor without breaking count.
		var fallback_candidates: Array[Vector3] = _generate_raw_candidates(unit_count, requested_target, right_axis, min_spacing)
		for raw_pos: Vector3 in fallback_candidates:
			if accepted_slots.size() >= unit_count:
				break
			var snapped_fallback: Vector3 = _snap_position(raw_pos, snap_callable) if not has_reachability else raw_pos
			if not snapped_fallback.is_finite():
				snapped_fallback = raw_pos
			if not _is_separated_from_all(snapped_fallback, accepted_slots, min_spacing * 0.95):
				continue
			accepted_slots.append(snapped_fallback)

		while accepted_slots.size() < unit_count:
			var angle: float = TAU * float(accepted_slots.size()) / float(unit_count)
			accepted_slots.append(requested_target + Vector3(cos(angle) * min_spacing, 0.0, sin(angle) * min_spacing))

		result.all_slots_reachable = false
	else:
		result.all_slots_reachable = true

	result.targets = assign_slots_minimum_distance(unit_positions, accepted_slots)
	result.valid = result.targets.size() == unit_count
	return result


static func assign_slots_minimum_distance(
	unit_positions: Array[Vector3],
	slots: Array[Vector3]
) -> Array[Vector3]:
	var count: int = unit_positions.size()
	var assigned: Array[Vector3] = []
	if count == 0 or slots.size() < count:
		return assigned

	var slot_indices: Array[int] = []
	slot_indices.resize(count)
	var used_slots: Array[bool] = []
	used_slots.resize(slots.size())
	used_slots.fill(false)

	var assigned_units: Array[bool] = []
	assigned_units.resize(count)
	assigned_units.fill(false)

	# Greedy globally-shortest pair initialization (deterministic tie-break).
	for _step: int in range(count):
		var best_u: int = -1
		var best_s: int = -1
		var best_dist_sq: float = INF
		for u_idx: int in range(count):
			if assigned_units[u_idx]:
				continue
			for s_idx: int in range(slots.size()):
				if used_slots[s_idx]:
					continue
				var dist_sq: float = _distance_xz_sq(unit_positions[u_idx], slots[s_idx])
				if dist_sq < best_dist_sq:
					best_dist_sq = dist_sq
					best_u = u_idx
					best_s = s_idx
		if best_u >= 0 and best_s >= 0:
			assigned_units[best_u] = true
			used_slots[best_s] = true
			slot_indices[best_u] = best_s

	# Bounded 2-opt refinement eliminates intersecting paths and lowers total distance.
	if count >= 2:
		var max_passes: int = count * count
		for _pass: int in range(max_passes):
			var improved: bool = false
			for i: int in range(count - 1):
				for j: int in range(i + 1, count):
					var s_i: int = slot_indices[i]
					var s_j: int = slot_indices[j]
					var current_cost: float = _distance_xz(unit_positions[i], slots[s_i]) + _distance_xz(unit_positions[j], slots[s_j])
					var swapped_cost: float = _distance_xz(unit_positions[i], slots[s_j]) + _distance_xz(unit_positions[j], slots[s_i])
					if swapped_cost + COST_IMPROVEMENT_EPSILON < current_cost:
						slot_indices[i] = s_j
						slot_indices[j] = s_i
						improved = true
			if not improved:
				break

	for u_idx: int in range(count):
		assigned.append(slots[slot_indices[u_idx]])
	return assigned


static func _build_unreachable_fallback_plan(
	unit_positions: Array[Vector3],
	requested_target: Vector3,
	min_spacing: float
) -> PlanResult:
	var result := PlanResult.new()
	result.anchor_position = requested_target
	result.all_slots_reachable = false
	result.requested_target_reachable = false

	var count: int = unit_positions.size()
	if count == 1:
		result.targets.append(requested_target)
		result.valid = true
		return result

	var centroid: Vector3 = _compute_centroid(unit_positions)
	var right_axis: Vector3 = _compute_right_axis_xz(centroid, requested_target)
	var raw_candidates: Array[Vector3] = _generate_raw_candidates(count, requested_target, right_axis, min_spacing)
	var slots: Array[Vector3] = []
	for i: int in range(count):
		slots.append(raw_candidates[i])

	result.targets = assign_slots_minimum_distance(unit_positions, slots)
	result.valid = result.targets.size() == count
	return result


static func _find_nearby_reachable_anchor(
	unit_positions: Array[Vector3],
	center: Vector3,
	min_spacing: float,
	snap_callable: Callable,
	reachability_callable: Callable
) -> Vector3:
	var candidates: Array[Vector3] = _generate_raw_candidates(6, center, Vector3.RIGHT, min_spacing)
	for raw_pos: Vector3 in candidates:
		var snapped: Vector3 = _snap_position(raw_pos, snap_callable)
		if snapped.is_finite() and _any_unit_can_reach(unit_positions, snapped, reachability_callable):
			return snapped
	return Vector3(NAN, NAN, NAN)


static func _generate_raw_candidates(
	unit_count: int,
	anchor: Vector3,
	right_axis: Vector3,
	min_spacing: float
) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	var base_angle: float = atan2(right_axis.z, right_axis.x)

	if unit_count == 2:
		var half_spread: float = min_spacing * PAIR_HALF_SPREAD_RATIO
		candidates.append(anchor - right_axis * half_spread)
		candidates.append(anchor + right_axis * half_spread)
		candidates.append(anchor)
	else:
		candidates.append(anchor)

	for ring_idx: int in range(1, MAX_RING_COUNT + 1):
		var radius: float = min_spacing * float(ring_idx)
		var ring_samples: int = maxi(RING_BASE_SAMPLES * ring_idx, ceili(TAU * radius / min_spacing))
		for sample_idx: int in range(ring_samples):
			var angle: float = base_angle + TAU * (float(sample_idx) / float(ring_samples))
			candidates.append(anchor + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))

	return candidates


static func _snap_position(pos: Vector3, snap_callable: Callable) -> Vector3:
	if not snap_callable.is_valid():
		return pos
	var snapped_var: Variant = snap_callable.call(pos)
	if snapped_var is Vector3:
		return snapped_var as Vector3
	return pos


static func _is_reachable(from_pos: Vector3, to_pos: Vector3, reachability_callable: Callable) -> bool:
	if not reachability_callable.is_valid():
		return true
	var reachable_var: Variant = reachability_callable.call(from_pos, to_pos)
	return bool(reachable_var)


static func _any_unit_can_reach(
	unit_positions: Array[Vector3],
	target_pos: Vector3,
	reachability_callable: Callable
) -> bool:
	for unit_pos: Vector3 in unit_positions:
		if _is_reachable(unit_pos, target_pos, reachability_callable):
			return true
	return false


static func _is_separated_from_all(candidate: Vector3, existing: Array[Vector3], min_spacing: float) -> bool:
	var min_sq: float = maxf(min_spacing - 0.001, 0.0)
	min_sq *= min_sq
	for pos: Vector3 in existing:
		if _distance_xz_sq(candidate, pos) < min_sq:
			return false
	return true


static func _compute_centroid(positions: Array[Vector3]) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	for pos: Vector3 in positions:
		sum += pos
	return sum / float(maxi(positions.size(), 1))


static func _compute_right_axis_xz(from_pos: Vector3, to_pos: Vector3) -> Vector3:
	var forward_xz := Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z)
	if forward_xz.length_squared() < 0.0001:
		return Vector3.RIGHT
	var fwd_norm: Vector2 = forward_xz.normalized()
	return Vector3(-fwd_norm.y, 0.0, fwd_norm.x)


static func _distance_xz(a: Vector3, b: Vector3) -> float:
	return sqrt(_distance_xz_sq(a, b))


static func _distance_xz_sq(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return dx * dx + dz * dz
