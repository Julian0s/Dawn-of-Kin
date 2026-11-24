class_name PlacementValidator
extends RefCounted
## Spatial and navigation validator for T3.2 gridless building placement.
## Performs lightweight conservative checks during cursor hover and isolated candidate
## NavMesh connectivity checks on confirmation, without modifying active navigation or economy.

## Provisional spatial parameters calibrated for Godot 4.7.2 + TestMap (T3.2).
const MAX_TERRAIN_SLOPE_DEG: float = 10.0
const MAX_TERRAIN_HEIGHT_DELTA_M: float = 0.35
const TERRAIN_RAY_HALF_SPAN_Y: float = 8.0
const CENTER_NAV_SNAP_MAX_XZ_M: float = 0.75
const CENTER_NAV_SNAP_MAX_Y_M: float = 0.65
const PERIMETER_ACCESS_OFFSET_M: float = 0.85
const CORRIDOR_PROBE_OFFSET_M: float = 1.35
const PILE_FOOTPRINT_RADIUS_M: float = 0.55
const MIN_ACCESSIBLE_PERIMETER_POINTS: int = 2
const OBSTACLE_SHAPE_MIN_Y_OFFSET_M: float = 0.15
const FOOTPRINT_EDGE_TOLERANCE_M: float = 0.001
const TERRAIN_SAMPLE_INSET_RATIO: float = 0.96
const MAX_SHAPE_QUERY_RESULTS: int = 32

const REASON_INVALID_INPUT: StringName = &"invalid_input"
const REASON_NAV_NOT_READY: StringName = &"navigation_not_ready"
const REASON_OUT_OF_BOUNDS: StringName = &"out_of_region_bounds"
const REASON_INVALID_TERRAIN: StringName = &"invalid_terrain"
const REASON_CAMP_RESERVED: StringName = &"camp_reserved_zone"
const REASON_OBSTACLE_OVERLAP: StringName = &"obstacle_overlap"
const REASON_RESOURCE_OVERLAP: StringName = &"resource_overlap"
const REASON_PILE_OVERLAP: StringName = &"pile_overlap"
const REASON_UNIT_OVERLAP: StringName = &"unit_overlap"
const REASON_PERIMETER_UNREACHABLE: StringName = &"perimeter_unreachable"
const REASON_CORRIDOR_BLOCKED: StringName = &"corridor_blocked"
const REASON_NAVIGATION_STALE: StringName = &"navigation_stale"

var _body_box: BoxShape3D = BoxShape3D.new()
var _clearance_sphere: SphereShape3D = SphereShape3D.new()
var _shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


class ValidationContext extends RefCounted:
	var world_3d: World3D = null
	var space_state: PhysicsDirectSpaceState3D = null
	var world_navigation: WorldNavigation = null
	var region_bounds: Rect2 = Rect2()
	var camp_storage_zone: CampStorageZone = null
	var ground_pile_manager: GroundPileManager = null
	var extra_piles: Array[GroundResourcePile] = []
	var construction_sites: Array[ConstructionSite] = []
	var completed_buildings: Array[BuildingInstance] = []
	var region_id: StringName = &"default"
	var units: Array[Unit] = []
	var resource_sources: Array[ResourceSource] = []
	var connectivity_checkpoints: Array[Vector3] = []
	var region_root_id: int = 0
	var units_root_id: int = 0
	var region_root: Node = null
	var units_root: Node = null
	var piles_root: Node = null
	var has_region_scope: bool = false
	var has_explicit_units: bool = false
	var has_explicit_sources: bool = false

	static func from_region(
		p_region_root: Node,
		p_world_navigation: WorldNavigation = null,
		p_camp_zone: CampStorageZone = null,
		p_pile_manager: GroundPileManager = null,
		p_units: Array[Unit] = [],
		p_sources: Array[ResourceSource] = [],
		p_checkpoints: Array[Vector3] = [],
		p_units_root: Node = null,
		p_piles_root: Node = null
	) -> ValidationContext:
		var ctx := ValidationContext.new()
		ctx.world_navigation = p_world_navigation
		if is_instance_valid(p_region_root):
			ctx.region_id = StringName(p_region_root.get_meta(&"region_id", &"default"))
		ctx.camp_storage_zone = p_camp_zone
		ctx.ground_pile_manager = p_pile_manager
		ctx.connectivity_checkpoints = p_checkpoints.duplicate()
		ctx.has_region_scope = (p_region_root != null and is_instance_valid(p_region_root))
		if ctx.has_region_scope:
			ctx.region_root = p_region_root
			ctx.region_root_id = p_region_root.get_instance_id()
		if p_units_root != null and is_instance_valid(p_units_root):
			ctx.units_root = p_units_root
			ctx.units_root_id = p_units_root.get_instance_id()
		if p_piles_root != null and is_instance_valid(p_piles_root):
			ctx.piles_root = p_piles_root
		ctx.has_explicit_units = not p_units.is_empty()
		ctx.has_explicit_sources = not p_sources.is_empty()

		if p_region_root is Node3D and (p_region_root as Node3D).is_inside_tree():
			ctx.world_3d = (p_region_root as Node3D).get_world_3d()
		elif p_world_navigation != null and p_world_navigation.is_inside_tree():
			ctx.world_3d = p_world_navigation.get_world_3d()

		if ctx.world_3d != null:
			ctx.space_state = ctx.world_3d.direct_space_state

		if p_region_root != null and p_region_root.has_method("get_map_bounds"):
			var bounds_var: Variant = p_region_root.call("get_map_bounds")
			if bounds_var is Rect2:
				ctx.region_bounds = bounds_var as Rect2
		elif p_world_navigation != null and is_instance_valid(p_world_navigation):
			ctx.region_bounds = p_world_navigation.get_map_bounds()

		var seen_units: Dictionary = {}
		if not p_units.is_empty():
			for u: Unit in p_units:
				_append_scoped_unit(ctx.units, seen_units, u, ctx.world_3d)
		elif p_units_root != null and is_instance_valid(p_units_root):
			_collect_scoped_units_recursive(p_units_root, ctx.units, seen_units, ctx.world_3d)
			if ctx.has_region_scope:
				_collect_scoped_units_recursive(p_region_root, ctx.units, seen_units, ctx.world_3d)
		elif ctx.has_region_scope:
			if p_region_root.has_method("get_units"):
				var region_units_var: Variant = p_region_root.call("get_units")
				if region_units_var is Array:
					for item: Variant in region_units_var as Array:
						if item is Unit:
							_append_scoped_unit(ctx.units, seen_units, item as Unit, ctx.world_3d)
			_collect_scoped_units_recursive(p_region_root, ctx.units, seen_units, ctx.world_3d)
			var parent_node: Node = p_region_root.get_parent()
			if parent_node is MainScene and ctx.units.is_empty():
				for main_u: Unit in (parent_node as MainScene).get_units():
					_append_scoped_unit(ctx.units, seen_units, main_u, ctx.world_3d)

		var seen_sources: Dictionary = {}
		if not p_sources.is_empty():
			for s: ResourceSource in p_sources:
				_append_scoped_source(ctx.resource_sources, seen_sources, s, ctx.world_3d, ctx.region_id)
		elif ctx.has_region_scope:
			if p_region_root.has_method("get_all_region_resource_sources"):
				var all_sources_var: Variant = p_region_root.call("get_all_region_resource_sources")
				if all_sources_var is Array:
					for item: Variant in all_sources_var as Array:
						if item is ResourceSource:
							_append_scoped_source(ctx.resource_sources, seen_sources, item as ResourceSource, ctx.world_3d, ctx.region_id)
			elif p_region_root.has_method("get_resource_sources"):
				var region_sources_var: Variant = p_region_root.call("get_resource_sources")
				if region_sources_var is Array:
					for item: Variant in region_sources_var as Array:
						if item is ResourceSource:
							_append_scoped_source(ctx.resource_sources, seen_sources, item as ResourceSource, ctx.world_3d, ctx.region_id)
			_collect_scoped_sources_recursive(p_region_root, ctx.resource_sources, seen_sources, ctx.world_3d, ctx.region_id)

		var seen_piles: Dictionary = {}
		if p_piles_root != null and is_instance_valid(p_piles_root):
			_collect_scoped_piles_recursive(p_piles_root, ctx.extra_piles, seen_piles, ctx.world_3d)
		if ctx.has_region_scope:
			if p_region_root.has_method("get_ground_piles"):
				var region_piles_var: Variant = p_region_root.call("get_ground_piles")
				if region_piles_var is Array:
					for item: Variant in region_piles_var as Array:
						if item is GroundResourcePile:
							_append_scoped_pile(ctx.extra_piles, seen_piles, item as GroundResourcePile, ctx.world_3d)
			_collect_scoped_piles_recursive(p_region_root, ctx.extra_piles, seen_piles, ctx.world_3d)

		var seen_sites: Dictionary = {}
		var tree: SceneTree = p_region_root.get_tree() if p_region_root != null and is_instance_valid(p_region_root) else null
		if tree == null and p_world_navigation != null and is_instance_valid(p_world_navigation):
			tree = p_world_navigation.get_tree()
		if tree != null:
			for site_node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
				if site_node is ConstructionSite:
					_append_scoped_site(ctx.construction_sites, seen_sites, site_node as ConstructionSite, ctx.world_3d)
		if ctx.has_region_scope:
			_collect_scoped_sites_recursive(p_region_root, ctx.construction_sites, seen_sites, ctx.world_3d)

		if tree != null:
			for node: Node in tree.get_nodes_in_group(BuildingInstance.GROUP_COMPLETED_BUILDINGS):
				if node is BuildingInstance and _matches_world(node, ctx.world_3d):
					var building: BuildingInstance = node as BuildingInstance
					if building.is_inside_tree() and building.region_id == ctx.region_id:
						ctx.completed_buildings.append(building)
		ctx.construction_sites = ctx.construction_sites.filter(func(site: ConstructionSite) -> bool: return site.region_id == ctx.region_id)
		return ctx

	func refresh_dynamic_state() -> ValidationContext:
		if has_region_scope:
			if region_root == null or not is_instance_valid(region_root) or not region_root.is_inside_tree():
				return null
			var valid_units_root: Node = units_root if (units_root != null and is_instance_valid(units_root)) else null
			var valid_piles_root: Node = piles_root if (piles_root != null and is_instance_valid(piles_root)) else null
			var explicit_units: Array[Unit] = []
			if has_explicit_units:
				explicit_units = units
			var explicit_sources: Array[ResourceSource] = []
			if has_explicit_sources:
				explicit_sources = resource_sources
			return ValidationContext.from_region(
				region_root,
				world_navigation,
				camp_storage_zone,
				ground_pile_manager,
				explicit_units,
				explicit_sources,
				connectivity_checkpoints,
				valid_units_root,
				valid_piles_root
			)
		if world_3d != null:
			space_state = world_3d.direct_space_state
		if is_instance_valid(world_navigation) and world_navigation.is_inside_tree():
			completed_buildings.clear()
			for node: Node in world_navigation.get_tree().get_nodes_in_group(BuildingInstance.GROUP_COMPLETED_BUILDINGS):
				if node is BuildingInstance and _matches_world(node, world_3d) and (node as BuildingInstance).region_id == region_id:
					completed_buildings.append(node as BuildingInstance)
		return self

	static func _matches_world(node: Node, expected_world: World3D) -> bool:
		if node == null or not is_instance_valid(node):
			return false
		if expected_world != null and node is Node3D and (node as Node3D).is_inside_tree():
			return (node as Node3D).get_world_3d() == expected_world
		return true

	static func _append_scoped_unit(out: Array[Unit], seen: Dictionary, unit_node: Unit, expected_world: World3D) -> void:
		if not _matches_world(unit_node, expected_world):
			return
		var uid: int = unit_node.get_instance_id()
		if not seen.has(uid):
			seen[uid] = true
			out.append(unit_node)

	static func _collect_scoped_units_recursive(root_node: Node, out: Array[Unit], seen: Dictionary, expected_world: World3D) -> void:
		if root_node == null or not is_instance_valid(root_node):
			return
		if root_node is Unit:
			_append_scoped_unit(out, seen, root_node as Unit, expected_world)
		for child: Node in root_node.get_children():
			_collect_scoped_units_recursive(child, out, seen, expected_world)

	static func _matches_region_meta(node: Node, expected_region_id: StringName) -> bool:
		if expected_region_id.is_empty():
			return true
		var cursor: Node = node
		while cursor != null:
			if cursor.has_meta(&"region_id"):
				return StringName(cursor.get_meta(&"region_id")) == expected_region_id
			cursor = cursor.get_parent()
		return true

	static func _append_scoped_source(out: Array[ResourceSource], seen: Dictionary, source_node: ResourceSource, expected_world: World3D, expected_region_id: StringName = &"") -> void:
		if not _matches_world(source_node, expected_world):
			return
		if source_node.is_queued_for_deletion():
			return
		if not _matches_region_meta(source_node, expected_region_id):
			return
		var sid: int = source_node.get_instance_id()
		if not seen.has(sid):
			seen[sid] = true
			out.append(source_node)

	static func _collect_scoped_sources_recursive(root_node: Node, out: Array[ResourceSource], seen: Dictionary, expected_world: World3D, expected_region_id: StringName = &"") -> void:
		if root_node == null or not is_instance_valid(root_node) or root_node.is_queued_for_deletion():
			return
		if root_node is ResourceSource:
			_append_scoped_source(out, seen, root_node as ResourceSource, expected_world, expected_region_id)
		for child: Node in root_node.get_children():
			_collect_scoped_sources_recursive(child, out, seen, expected_world, expected_region_id)

	static func _append_scoped_pile(out: Array[GroundResourcePile], seen: Dictionary, pile_node: GroundResourcePile, expected_world: World3D) -> void:
		if not _matches_world(pile_node, expected_world):
			return
		var pid: int = pile_node.get_instance_id()
		if not seen.has(pid):
			seen[pid] = true
			out.append(pile_node)

	static func _collect_scoped_piles_recursive(root_node: Node, out: Array[GroundResourcePile], seen: Dictionary, expected_world: World3D) -> void:
		if root_node == null or not is_instance_valid(root_node):
			return
		if root_node is GroundResourcePile:
			_append_scoped_pile(out, seen, root_node as GroundResourcePile, expected_world)
		for child: Node in root_node.get_children():
			_collect_scoped_piles_recursive(child, out, seen, expected_world)

	static func _append_scoped_site(out: Array[ConstructionSite], seen: Dictionary, site_node: ConstructionSite, expected_world: World3D) -> void:
		if not _matches_world(site_node, expected_world):
			return
		var sid: int = site_node.get_instance_id()
		if not seen.has(sid):
			seen[sid] = true
			out.append(site_node)

	static func _collect_scoped_sites_recursive(root_node: Node, out: Array[ConstructionSite], seen: Dictionary, expected_world: World3D) -> void:
		if root_node == null or not is_instance_valid(root_node):
			return
		if root_node is ConstructionSite:
			_append_scoped_site(out, seen, root_node as ConstructionSite, expected_world)
		for child: Node in root_node.get_children():
			_collect_scoped_sites_recursive(child, out, seen, expected_world)


class ValidationResult extends RefCounted:
	var valid: bool = false
	var reason_code: StringName = &""
	var reason_text: String = ""
	var resolved_position: Vector3 = Vector3.ZERO
	var used_candidate_navmesh: bool = false
	var accessible_perimeter_points: Array[Vector3] = []
	var evaluation_usec: int = 0
	var main_thread_usec: int = 0
	var candidate_prepare_ms: float = 0.0
	var candidate_bake_ms: float = 0.0
	var candidate_sync_ms: float = 0.0
	var connectivity_query_ms: float = 0.0


func validate_hover(
	definition: BuildingDefinition,
	raw_position: Vector3,
	context: ValidationContext
) -> ValidationResult:
	var started_usec: int = Time.get_ticks_usec()
	var result: ValidationResult = _validate_spatial_base(definition, raw_position, context)
	if not result.valid:
		result.evaluation_usec = Time.get_ticks_usec() - started_usec
		return result

	var space_state: PhysicsDirectSpaceState3D = _resolve_space_state(context)
	var bounds: Rect2 = _resolve_region_bounds(context)
	var world_nav: WorldNavigation = context.world_navigation
	var hub_origin: Vector3 = _resolve_connectivity_hub(
		definition,
		result.resolved_position,
		context,
		space_state,
		bounds
	)
	if not hub_origin.is_finite():
		_fail_result(result, REASON_PERIMETER_UNREACHABLE, "Posição inválida: sem acesso válido ao perímetro de montagem.")
		result.evaluation_usec = Time.get_ticks_usec() - started_usec
		return result

	var perimeter: Array[Vector3] = _collect_accessible_perimeter_on_nav(
		definition,
		result.resolved_position,
		hub_origin,
		world_nav,
		space_state,
		bounds,
		MIN_ACCESSIBLE_PERIMETER_POINTS
	)
	result.accessible_perimeter_points = perimeter
	if perimeter.size() < MIN_ACCESSIBLE_PERIMETER_POINTS:
		_fail_result(result, REASON_PERIMETER_UNREACHABLE, "Posição inválida: sem acesso válido ao perímetro de montagem.")
		result.evaluation_usec = Time.get_ticks_usec() - started_usec
		return result

	result.evaluation_usec = Time.get_ticks_usec() - started_usec
	return result


func validate_confirm(
	definition: BuildingDefinition,
	raw_position: Vector3,
	context: ValidationContext
) -> ValidationResult:
	var started_usec: int = Time.get_ticks_usec()
	var job: Dictionary = _prepare_confirm_job(definition, raw_position, context, started_usec)
	if not (job["proceed"] as bool):
		return job["result"] as ValidationResult

	var world_nav: WorldNavigation = context.world_navigation
	var candidate_boxes: Array[Dictionary] = job["candidate_boxes"] as Array[Dictionary]
	var session: WorldNavigation.CandidateSession = world_nav.create_candidate_session(candidate_boxes)
	var finalize_res: ValidationResult = _complete_confirm_with_session(
		definition,
		job,
		session,
		started_usec,
		0,
		false
	)
	return finalize_res


## Non-blocking confirmation check: performs spatial pre-checks and anchor collection
## synchronously, runs Recast candidate NavMesh baking on a worker thread, then revalidates
## live world state and navigation revision alongside candidate connectivity on completion.
func validate_confirm_async(
	definition: BuildingDefinition,
	raw_position: Vector3,
	context: ValidationContext,
	on_complete: Callable
) -> WorldNavigation.AsyncBakeToken:
	var started_usec: int = Time.get_ticks_usec()
	var job: Dictionary = _prepare_confirm_job(definition, raw_position, context, started_usec)
	if not (job["proceed"] as bool):
		var sync_fail: ValidationResult = job["result"] as ValidationResult
		sync_fail.main_thread_usec = sync_fail.evaluation_usec
		if on_complete.is_valid():
			on_complete.call(sync_fail)
		return null

	var world_nav: WorldNavigation = context.world_navigation
	var candidate_boxes: Array[Dictionary] = job["candidate_boxes"] as Array[Dictionary]
	var pre_main_usec: int = Time.get_ticks_usec() - started_usec

	return world_nav.create_candidate_session_async(
		candidate_boxes,
		func(session: WorldNavigation.CandidateSession) -> void:
			var final_res: ValidationResult = _complete_confirm_with_session(
				definition,
				job,
				session,
				started_usec,
				pre_main_usec,
				true
			)
			if on_complete.is_valid():
				on_complete.call(final_res)
	)


func _prepare_confirm_job(
	definition: BuildingDefinition,
	raw_position: Vector3,
	context: ValidationContext,
	started_usec: int
) -> Dictionary:
	if context != null:
		context = context.refresh_dynamic_state()
	var result: ValidationResult = _validate_spatial_base(definition, raw_position, context)
	if not result.valid:
		result.evaluation_usec = Time.get_ticks_usec() - started_usec
		result.main_thread_usec = result.evaluation_usec
		return {"proceed": false, "result": result}

	var space_state: PhysicsDirectSpaceState3D = _resolve_space_state(context)
	var bounds: Rect2 = _resolve_region_bounds(context)
	var world_nav: WorldNavigation = context.world_navigation
	var center_pos: Vector3 = result.resolved_position

	var hub_origin: Vector3 = _resolve_connectivity_hub(
		definition,
		center_pos,
		context,
		space_state,
		bounds
	)
	if not hub_origin.is_finite():
		_fail_result(result, REASON_PERIMETER_UNREACHABLE, "Posição inválida: sem acesso válido ao perímetro de montagem.")
		result.evaluation_usec = Time.get_ticks_usec() - started_usec
		result.main_thread_usec = result.evaluation_usec
		return {"proceed": false, "result": result}

	# Collect pre-placement reachable anchors BEFORE candidate baking so we only preserve
	# connectivity that already existed on the current navigable region.
	var pre_camp_target: Vector3 = Vector3(INF, INF, INF)
	if context.camp_storage_zone != null and is_instance_valid(context.camp_storage_zone) and context.camp_storage_zone.is_valid():
		var camp_anchor: Vector3 = context.camp_storage_zone.get_anchor_position()
		if world_nav.find_path(hub_origin, camp_anchor).is_ok():
			pre_camp_target = camp_anchor

	var exclusion_rect: Rect2 = definition.get_footprint_rect_at(Vector2(center_pos.x, center_pos.z)).grow(WorldNavigation.DEFAULT_AGENT_RADIUS + 0.05)

	var pre_unit_targets: Array[Vector3] = []
	for u: Unit in context.units:
		if u == null or not is_instance_valid(u) or not u.is_inside_tree():
			continue
		var u_pos: Vector3 = u.global_position
		if not u_pos.is_finite():
			continue
		if exclusion_rect.has_point(Vector2(u_pos.x, u_pos.z)):
			continue
		if world_nav.find_path(hub_origin, u_pos).is_ok():
			pre_unit_targets.append(u_pos)

	var pre_source_groups: Array[Array] = []
	for src: ResourceSource in context.resource_sources:
		if src == null or not is_instance_valid(src) or not src.is_inside_tree() or not src.is_available():
			continue
		var source_approaches: Array[Vector3] = _collect_reachable_source_approaches(
			src,
			hub_origin,
			exclusion_rect,
			world_nav,
			space_state,
			bounds
		)
		if not source_approaches.is_empty():
			pre_source_groups.append(source_approaches)

	var pre_checkpoints: Array[Vector3] = []
	for cp: Vector3 in context.connectivity_checkpoints:
		if not cp.is_finite():
			continue
		if exclusion_rect.has_point(Vector2(cp.x, cp.z)):
			continue
		if world_nav.find_path(hub_origin, cp).is_ok():
			pre_checkpoints.append(cp)

	var pre_corridor_probes: Array[Vector3] = _collect_reachable_corridor_probes(
		definition,
		center_pos,
		hub_origin,
		world_nav,
		space_state,
		bounds
	)

	var candidate_boxes: Array[Dictionary] = [
		{
			"position": center_pos,
			"size": Vector3(definition.footprint_size.x, definition.visual_height, definition.footprint_size.y),
		}
	]
	for existing_site: ConstructionSite in context.construction_sites:
		if existing_site == null or not is_instance_valid(existing_site) or existing_site.definition == null or not existing_site.occupies_construction_footprint():
			continue
		candidate_boxes.append({
			"position": existing_site.global_position,
			"size": Vector3(
				existing_site.definition.footprint_size.x,
				existing_site.definition.visual_height,
				existing_site.definition.footprint_size.y
			),
		})

	for building: BuildingInstance in context.completed_buildings:
		if is_instance_valid(building) and building.is_inside_tree():
			candidate_boxes.append({"position": building.global_position, "size": building.get_footprint_aabb().size})

	return {
		"proceed": true,
		"result": result,
		"raw_position": raw_position,
		"context": context,
		"space_state": space_state,
		"bounds": bounds,
		"center_pos": center_pos,
		"hub_origin": hub_origin,
		"pre_camp_target": pre_camp_target,
		"pre_unit_targets": pre_unit_targets,
		"pre_source_groups": pre_source_groups,
		"pre_checkpoints": pre_checkpoints,
		"pre_corridor_probes": pre_corridor_probes,
		"candidate_boxes": candidate_boxes,
		"start_nav_revision": world_nav.get_navigation_revision(),
		"start_nav_mesh": world_nav.navigation_mesh,
		"start_had_cache": world_nav.has_static_geometry_cache(),
	}


func _revalidate_confirm_preconditions(
	definition: BuildingDefinition,
	job: Dictionary,
	base_result: ValidationResult
) -> Dictionary:
	var orig_ctx: ValidationContext = job.get("context") as ValidationContext
	if orig_ctx == null:
		_fail_result(base_result, REASON_INVALID_INPUT, "Posição inválida: contexto da região ausente.")
		return {"ok": false, "result": base_result}

	var world_nav: WorldNavigation = orig_ctx.world_navigation
	if world_nav == null or not is_instance_valid(world_nav) or not world_nav.is_inside_tree():
		_fail_result(base_result, REASON_NAV_NOT_READY, "Posição inválida: navegação da região indisponível.")
		return {"ok": false, "result": base_result}

	if not world_nav.is_navigation_ready():
		_fail_result(base_result, REASON_NAV_NOT_READY, "Posição inválida: navegação da região foi alterada ou não está pronta.")
		return {"ok": false, "result": base_result}

	var start_nav_revision: int = int(job.get("start_nav_revision", -1))
	var start_nav_mesh: Variant = job.get("start_nav_mesh")
	var start_had_cache: bool = bool(job.get("start_had_cache", false))
	if (
		world_nav.get_navigation_revision() != start_nav_revision
		or world_nav.navigation_mesh != start_nav_mesh
		or (start_had_cache and not world_nav.has_static_geometry_cache())
	):
		_fail_result(base_result, REASON_NAVIGATION_STALE, "Posição inválida: a navegação da região foi modificada durante a validação.")
		return {"ok": false, "result": base_result}

	var current_ctx: ValidationContext = orig_ctx.refresh_dynamic_state()
	if current_ctx == null:
		_fail_result(base_result, REASON_INVALID_INPUT, "Posição inválida: contexto da região tornou-se inválido.")
		return {"ok": false, "result": base_result}

	var bounds_at_start: Rect2 = job["bounds"] as Rect2
	var current_bounds: Rect2 = _resolve_region_bounds(current_ctx)
	if not current_bounds.is_equal_approx(bounds_at_start):
		_fail_result(base_result, REASON_NAVIGATION_STALE, "Posição inválida: os limites da região alteraram durante a validação.")
		return {"ok": false, "result": base_result}

	var raw_position: Vector3 = job["raw_position"] as Vector3
	var current_spatial: ValidationResult = _validate_spatial_base(definition, raw_position, current_ctx)
	if not current_spatial.valid:
		current_spatial.used_candidate_navmesh = base_result.used_candidate_navmesh
		current_spatial.candidate_prepare_ms = base_result.candidate_prepare_ms
		current_spatial.candidate_bake_ms = base_result.candidate_bake_ms
		current_spatial.candidate_sync_ms = base_result.candidate_sync_ms
		return {"ok": false, "result": current_spatial}

	var start_center: Vector3 = job["center_pos"] as Vector3
	if current_spatial.resolved_position.distance_squared_to(start_center) > 0.0004:
		_fail_result(base_result, REASON_NAVIGATION_STALE, "Posição inválida: o terreno sob a construção alterou durante a validação.")
		return {"ok": false, "result": base_result}

	var current_space_state: PhysicsDirectSpaceState3D = _resolve_space_state(current_ctx)
	if current_space_state == null:
		_fail_result(base_result, REASON_INVALID_INPUT, "Posição inválida: espaço físico da região indisponível.")
		return {"ok": false, "result": base_result}

	return {
		"ok": true,
		"space_state": current_space_state,
		"bounds": current_bounds,
	}


func _complete_confirm_with_session(
	definition: BuildingDefinition,
	job: Dictionary,
	session: WorldNavigation.CandidateSession,
	started_usec: int,
	pre_main_usec: int,
	revalidate_state: bool
) -> ValidationResult:
	var post_start_usec: int = Time.get_ticks_usec()
	var result: ValidationResult = job["result"] as ValidationResult
	var space_state: PhysicsDirectSpaceState3D = job["space_state"] as PhysicsDirectSpaceState3D
	var bounds: Rect2 = job["bounds"] as Rect2
	var center_pos: Vector3 = job["center_pos"] as Vector3
	var hub_origin: Vector3 = job["hub_origin"] as Vector3
	var pre_camp_target: Vector3 = job["pre_camp_target"] as Vector3
	var pre_unit_targets: Array[Vector3] = job["pre_unit_targets"] as Array[Vector3]
	var pre_source_groups: Array[Array] = job["pre_source_groups"] as Array[Array]
	var pre_checkpoints: Array[Vector3] = job["pre_checkpoints"] as Array[Vector3]
	var pre_corridor_probes: Array[Vector3] = job["pre_corridor_probes"] as Array[Vector3]

	result.used_candidate_navmesh = true
	if session != null:
		result.candidate_prepare_ms = session.prepare_ms
		result.candidate_bake_ms = session.bake_ms
		result.candidate_sync_ms = session.server_sync_ms

	if session == null or not session.is_valid():
		if session != null:
			session.dispose()
		_fail_result(result, REASON_CORRIDOR_BLOCKED, "Posição inválida: falha ao validar malha de navegação candidata.")
		result.evaluation_usec = Time.get_ticks_usec() - started_usec
		result.main_thread_usec = pre_main_usec + (Time.get_ticks_usec() - post_start_usec) if pre_main_usec > 0 else result.evaluation_usec
		return result

	if revalidate_state:
		var recheck: Dictionary = _revalidate_confirm_preconditions(definition, job, result)
		if not (recheck.get("ok", false) as bool):
			session.dispose()
			var stale_res: ValidationResult = recheck["result"] as ValidationResult
			stale_res.evaluation_usec = Time.get_ticks_usec() - started_usec
			stale_res.main_thread_usec = pre_main_usec + (Time.get_ticks_usec() - post_start_usec) if pre_main_usec > 0 else stale_res.evaluation_usec
			return stale_res
		space_state = recheck["space_state"] as PhysicsDirectSpaceState3D
		bounds = recheck["bounds"] as Rect2

	var query_start_usec: int = Time.get_ticks_usec()
	var candidate_perimeter: Array[Vector3] = _collect_accessible_perimeter_on_candidate(
		definition,
		center_pos,
		hub_origin,
		session,
		space_state,
		bounds
	)
	result.accessible_perimeter_points = candidate_perimeter
	if candidate_perimeter.size() < MIN_ACCESSIBLE_PERIMETER_POINTS:
		result.connectivity_query_ms = float(Time.get_ticks_usec() - query_start_usec) / 1000.0
		session.dispose()
		_fail_result(result, REASON_PERIMETER_UNREACHABLE, "Posição inválida: perímetro de trabalho inacessível após ocupação.")
		result.evaluation_usec = Time.get_ticks_usec() - started_usec
		result.main_thread_usec = pre_main_usec + (Time.get_ticks_usec() - post_start_usec) if pre_main_usec > 0 else result.evaluation_usec
		return result

	var connectivity_ok: bool = _verify_candidate_connectivity(
		session,
		hub_origin,
		pre_camp_target,
		pre_unit_targets,
		pre_source_groups,
		pre_checkpoints,
		pre_corridor_probes
	)
	result.connectivity_query_ms = float(Time.get_ticks_usec() - query_start_usec) / 1000.0
	session.dispose()

	if not connectivity_ok:
		_fail_result(result, REASON_CORRIDOR_BLOCKED, "Posição inválida: bloquearia corredor ou acesso de navegação.")
		result.evaluation_usec = Time.get_ticks_usec() - started_usec
		result.main_thread_usec = pre_main_usec + (Time.get_ticks_usec() - post_start_usec) if pre_main_usec > 0 else result.evaluation_usec
		return result

	result.valid = true
	result.reason_code = &""
	result.reason_text = ""
	result.evaluation_usec = Time.get_ticks_usec() - started_usec
	result.main_thread_usec = pre_main_usec + (Time.get_ticks_usec() - post_start_usec) if pre_main_usec > 0 else result.evaluation_usec
	return result


func _validate_spatial_base(
	definition: BuildingDefinition,
	raw_position: Vector3,
	context: ValidationContext
) -> ValidationResult:
	var result := ValidationResult.new()
	if definition == null or not definition.is_valid() or not raw_position.is_finite():
		_fail_result(result, REASON_INVALID_INPUT, "Posição inválida: dados de construção ou coordenada inválidos.")
		return result

	if context == null:
		_fail_result(result, REASON_INVALID_INPUT, "Posição inválida: contexto da região ausente.")
		return result

	context = context.refresh_dynamic_state()
	if context == null:
		_fail_result(result, REASON_INVALID_INPUT, "Region context expired.")
		return result
	var space_state: PhysicsDirectSpaceState3D = _resolve_space_state(context)
	if space_state == null:
		_fail_result(result, REASON_INVALID_INPUT, "Posição inválida: espaço físico da região indisponível.")
		return result

	var world_nav: WorldNavigation = context.world_navigation
	if world_nav == null or not is_instance_valid(world_nav) or not world_nav.is_navigation_ready():
		_fail_result(result, REASON_NAV_NOT_READY, "Posição inválida: navegação da região ainda não está pronta.")
		return result

	var bounds: Rect2 = _resolve_region_bounds(context)
	if not _is_footprint_inside_bounds(definition, Vector2(raw_position.x, raw_position.z), bounds):
		_fail_result(result, REASON_OUT_OF_BOUNDS, "Posição inválida: fora dos limites válidos da região.")
		return result

	var terrain_eval: Dictionary = _evaluate_footprint_terrain(space_state, definition, raw_position)
	if not (terrain_eval["ok"] as bool):
		_fail_result(result, REASON_INVALID_TERRAIN, "Posição inválida: terreno ausente ou irregular para construção.")
		return result

	var resolved_pos: Vector3 = terrain_eval["center_pos"] as Vector3
	result.resolved_position = resolved_pos

	if _overlaps_camp_storage_zone(definition, resolved_pos, context.camp_storage_zone):
		_fail_result(result, REASON_CAMP_RESERVED, "Posição inválida: área reservada para pilhas do acampamento.")
		return result

	var body_height: float = maxf(definition.visual_height - OBSTACLE_SHAPE_MIN_Y_OFFSET_M, 0.5)
	_body_box.size = Vector3(definition.footprint_size.x, body_height, definition.footprint_size.y)
	var shape_origin := Vector3(
		resolved_pos.x,
		resolved_pos.y + OBSTACLE_SHAPE_MIN_Y_OFFSET_M + body_height * 0.5,
		resolved_pos.z
	)
	var shape_xform := Transform3D(Basis.IDENTITY, shape_origin)

	var res_hits: Array[Dictionary] = _intersect_box(
		space_state,
		_body_box,
		shape_xform,
		CollisionLayers.MASK_RESOURCES,
		true,
		true
	)
	if not res_hits.is_empty():
		_fail_result(result, REASON_RESOURCE_OVERLAP, "Posição inválida: área intercepta recurso natural.")
		return result

	var obstacle_hits: Array[Dictionary] = _intersect_box(
		space_state,
		_body_box,
		shape_xform,
		CollisionLayers.MASK_OBSTACLES | CollisionLayers.MASK_BUILDINGS,
		false,
		true
	)
	var scoped_obstacles: Array[Dictionary] = []
	for hit: Dictionary in obstacle_hits:
		var collider: Object = hit.get("collider")
		if is_instance_valid(collider) and collider.has_meta(&"_cancellation_region") and collider.get_meta(&"_cancellation_region") != context.region_id:
			continue
		var site := ConstructionSite.resolve_from_collider(hit.get("collider"))
		if site != null and not site.occupies_construction_footprint():
			continue
		var building: BuildingInstance = BuildingInstance.resolve_from_collider(hit.get("collider"))
		if building == null or building.region_id == context.region_id:
			scoped_obstacles.append(hit)
	if not scoped_obstacles.is_empty():
		for hit: Dictionary in scoped_obstacles:
			if _resolve_resource_source_from_collider(hit.get("collider")) != null:
				_fail_result(result, REASON_RESOURCE_OVERLAP, "Posição inválida: área intercepta recurso natural.")
				return result
		_fail_result(result, REASON_OBSTACLE_OVERLAP, "Posição inválida: há obstáculos ou construções na área.")
		return result

	var candidate_rect: Rect2 = definition.get_footprint_rect_at(Vector2(resolved_pos.x, resolved_pos.z))
	var tol: float = FOOTPRINT_EDGE_TOLERANCE_M
	var shrunk_candidate := Rect2(
		candidate_rect.position + Vector2(tol, tol),
		Vector2(maxf(0.0, candidate_rect.size.x - tol * 2.0), maxf(0.0, candidate_rect.size.y - tol * 2.0))
	)
	for building: BuildingInstance in context.completed_buildings:
		if is_instance_valid(building) and building.is_inside_tree() and building.region_id == context.region_id and ValidationContext._matches_world(building, context.world_3d) and building.get_footprint_rect().intersects(shrunk_candidate, true):
			_fail_result(result, REASON_OBSTACLE_OVERLAP, "Completed building occupies this area.")
			return result
	if CancellationRecoveryTransaction.overlaps(context.world_3d, context.region_id, shrunk_candidate):
		# Custody survives removal of the visual site node.
		_fail_result(result, REASON_OBSTACLE_OVERLAP, "Cancellation materials occupy this area.")
		return result
	for existing_site: ConstructionSite in context.construction_sites:
		if existing_site == null or not is_instance_valid(existing_site) or not existing_site.is_valid() or not existing_site.occupies_construction_footprint():
			continue
		if existing_site.get_footprint_rect().intersects(shrunk_candidate, true):
			_fail_result(result, REASON_OBSTACLE_OVERLAP, "Posição inválida: já existe um canteiro de obra nessa área.")
			return result

	if _overlaps_physical_piles(definition, resolved_pos, context):
		_fail_result(result, REASON_PILE_OVERLAP, "Posição inválida: há pilhas de materiais neste local.")
		return result

	if _overlaps_units(space_state, _body_box, shape_xform, definition, resolved_pos, context):
		_fail_result(result, REASON_UNIT_OVERLAP, "Posição inválida: há trabalhadores na área da construção.")
		return result

	var snapped_center: Vector3 = world_nav.snap_to_navmesh(resolved_pos)
	if not snapped_center.is_finite():
		_fail_result(result, REASON_INVALID_TERRAIN, "Posição inválida: terreno fora da área navegável.")
		return result
	var snap_xz: float = Vector2(snapped_center.x - resolved_pos.x, snapped_center.z - resolved_pos.z).length()
	if snap_xz > CENTER_NAV_SNAP_MAX_XZ_M or absf(snapped_center.y - resolved_pos.y) > CENTER_NAV_SNAP_MAX_Y_M:
		_fail_result(result, REASON_INVALID_TERRAIN, "Posição inválida: terreno incompatível com a malha navegável.")
		return result

	result.valid = true
	return result


func _evaluate_footprint_terrain(
	space_state: PhysicsDirectSpaceState3D,
	definition: BuildingDefinition,
	raw_position: Vector3
) -> Dictionary:
	var half: Vector2 = definition.get_half_extents() * TERRAIN_SAMPLE_INSET_RATIO
	var sample_factors: Array[float] = [-1.0, 0.0, 1.0]
	var min_y: float = INF
	var max_y: float = -INF
	var center_y: float = raw_position.y
	var has_center_hit: bool = false

	_ray_query.collision_mask = CollisionLayers.MASK_TERRAIN
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true

	for fx: float in sample_factors:
		for fz: float in sample_factors:
			var sx: float = raw_position.x + fx * half.x
			var sz: float = raw_position.z + fz * half.y
			_ray_query.from = Vector3(sx, raw_position.y + TERRAIN_RAY_HALF_SPAN_Y, sz)
			_ray_query.to = Vector3(sx, raw_position.y - TERRAIN_RAY_HALF_SPAN_Y, sz)
			var hit: Dictionary = space_state.intersect_ray(_ray_query)
			if hit.is_empty():
				return {"ok": false}

			var hit_pos: Vector3 = hit["position"] as Vector3
			var hit_normal: Vector3 = hit.get("normal", Vector3.UP) as Vector3
			if not hit_pos.is_finite() or not hit_normal.is_finite() or hit_normal.length_squared() < 0.0001:
				return {"ok": false}

			var norm: Vector3 = hit_normal.normalized()
			var slope_deg: float = rad_to_deg(acos(clampf(norm.y, -1.0, 1.0)))
			if slope_deg > MAX_TERRAIN_SLOPE_DEG:
				return {"ok": false}

			min_y = minf(min_y, hit_pos.y)
			max_y = maxf(max_y, hit_pos.y)
			if fx == 0.0 and fz == 0.0:
				center_y = hit_pos.y
				has_center_hit = true

	if not has_center_hit or (max_y - min_y) > MAX_TERRAIN_HEIGHT_DELTA_M:
		return {"ok": false}

	return {
		"ok": true,
		"center_pos": Vector3(raw_position.x, center_y, raw_position.z),
	}


func _overlaps_camp_storage_zone(
	definition: BuildingDefinition,
	center_pos: Vector3,
	camp_zone: CampStorageZone
) -> bool:
	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid():
		return false
	var zone_anchor: Vector3 = camp_zone.get_anchor_position()
	var zone_half: Vector2 = camp_zone.zone_bounds_half_extents
	var b_half: Vector2 = definition.get_half_extents()
	var dx: float = absf(center_pos.x - zone_anchor.x)
	var dz: float = absf(center_pos.z - zone_anchor.z)
	return (
		dx < (b_half.x + zone_half.x - FOOTPRINT_EDGE_TOLERANCE_M)
		and dz < (b_half.y + zone_half.y - FOOTPRINT_EDGE_TOLERANCE_M)
	)


func _overlaps_physical_piles(
	definition: BuildingDefinition,
	center_pos: Vector3,
	context: ValidationContext
) -> bool:
	var expanded_half: Vector2 = definition.get_half_extents() + Vector2(PILE_FOOTPRINT_RADIUS_M, PILE_FOOTPRINT_RADIUS_M)
	var piles: Array[GroundResourcePile] = _collect_region_piles(context)
	for pile: GroundResourcePile in piles:
		if pile == null or not is_instance_valid(pile) or pile.amount <= 0:
			continue
		var p_pos: Vector3 = pile.global_position if pile.is_inside_tree() else pile.position
		if not p_pos.is_finite():
			continue
		if absf(p_pos.x - center_pos.x) < expanded_half.x and absf(p_pos.z - center_pos.z) < expanded_half.y:
			return true
	return false


func _overlaps_units(
	space_state: PhysicsDirectSpaceState3D,
	shape: BoxShape3D,
	shape_xform: Transform3D,
	definition: BuildingDefinition,
	center_pos: Vector3,
	context: ValidationContext
) -> bool:
	var unit_hits: Array[Dictionary] = _intersect_box(
		space_state,
		shape,
		shape_xform,
		CollisionLayers.MASK_UNITS,
		false,
		true
	)
	for hit: Dictionary in unit_hits:
		var col: Variant = hit.get("collider")
		if col is Unit:
			var hit_unit: Unit = col as Unit
			if not context.has_region_scope or context.units.has(hit_unit) or _is_node_inside_region_scope(hit_unit, context):
				return true
		else:
			return true
	var half: Vector2 = definition.get_half_extents()
	for unit_node: Unit in context.units:
		if unit_node == null or not is_instance_valid(unit_node) or not unit_node.is_inside_tree():
			continue
		var u_pos: Vector3 = unit_node.global_position
		if not u_pos.is_finite():
			continue
		if absf(u_pos.x - center_pos.x) < (half.x + 0.35) and absf(u_pos.z - center_pos.z) < (half.y + 0.35):
			return true
	return false


static func _is_node_inside_region_scope(node: Node, context: ValidationContext) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var cursor: Node = node
	while cursor != null:
		var cid: int = cursor.get_instance_id()
		if cid == context.region_root_id or (context.units_root_id != 0 and cid == context.units_root_id):
			return true
		cursor = cursor.get_parent()
	return false


func _resolve_connectivity_hub(
	definition: BuildingDefinition,
	center_pos: Vector3,
	context: ValidationContext,
	space_state: PhysicsDirectSpaceState3D,
	bounds: Rect2
) -> Vector3:
	var world_nav: WorldNavigation = context.world_navigation
	var exclusion_rect: Rect2 = definition.get_footprint_rect_at(Vector2(center_pos.x, center_pos.z)).grow(WorldNavigation.DEFAULT_AGENT_RADIUS + 0.05)

	if context.camp_storage_zone != null and is_instance_valid(context.camp_storage_zone) and context.camp_storage_zone.is_valid():
		var anchor: Vector3 = context.camp_storage_zone.get_anchor_position()
		if _is_point_nav_clear(anchor, exclusion_rect, world_nav):
			return anchor
		for slot: Vector3 in context.camp_storage_zone.get_candidate_slots():
			if _is_point_nav_clear(slot, exclusion_rect, world_nav):
				return slot

	for u: Unit in context.units:
		if u != null and is_instance_valid(u) and u.is_inside_tree():
			var u_pos: Vector3 = u.global_position
			if _is_point_nav_clear(u_pos, exclusion_rect, world_nav):
				return u_pos

	for cp: Vector3 in context.connectivity_checkpoints:
		if _is_point_nav_clear(cp, exclusion_rect, world_nav):
			return cp

	for offset_xz: Vector2 in definition.get_perimeter_offsets(PERIMETER_ACCESS_OFFSET_M):
		var candidate := Vector3(center_pos.x + offset_xz.x, center_pos.y, center_pos.z + offset_xz.y)
		var ground_pt: Vector3 = _sample_clear_walkable_ground_point(candidate, center_pos.y, bounds, space_state)
		if ground_pt.is_finite() and _is_point_nav_clear(ground_pt, exclusion_rect, world_nav):
			return ground_pt

	return Vector3(INF, INF, INF)


func _collect_accessible_perimeter_on_nav(
	definition: BuildingDefinition,
	center_pos: Vector3,
	hub_origin: Vector3,
	world_nav: WorldNavigation,
	space_state: PhysicsDirectSpaceState3D,
	bounds: Rect2,
	max_points: int = -1
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for offset_xz: Vector2 in definition.get_perimeter_offsets(PERIMETER_ACCESS_OFFSET_M):
		var candidate := Vector3(center_pos.x + offset_xz.x, center_pos.y, center_pos.z + offset_xz.y)
		var ground_pt: Vector3 = _sample_clear_walkable_ground_point(candidate, center_pos.y, bounds, space_state)
		if not ground_pt.is_finite():
			continue
		var path_res: WorldNavigation.PathResult = world_nav.find_path(hub_origin, ground_pt)
		if path_res.is_ok():
			points.append(path_res.resolved_target)
			if max_points > 0 and points.size() >= max_points:
				break
	return points


func _collect_accessible_perimeter_on_candidate(
	definition: BuildingDefinition,
	center_pos: Vector3,
	hub_origin: Vector3,
	session: WorldNavigation.CandidateSession,
	space_state: PhysicsDirectSpaceState3D,
	bounds: Rect2
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for offset_xz: Vector2 in definition.get_perimeter_offsets(PERIMETER_ACCESS_OFFSET_M):
		var candidate := Vector3(center_pos.x + offset_xz.x, center_pos.y, center_pos.z + offset_xz.y)
		var ground_pt: Vector3 = _sample_clear_walkable_ground_point(candidate, center_pos.y, bounds, space_state)
		if not ground_pt.is_finite():
			continue
		var path_res: WorldNavigation.PathResult = session.find_path(hub_origin, ground_pt)
		if path_res.is_ok():
			points.append(path_res.resolved_target)
	return points


func _collect_reachable_corridor_probes(
	definition: BuildingDefinition,
	center_pos: Vector3,
	hub_origin: Vector3,
	world_nav: WorldNavigation,
	space_state: PhysicsDirectSpaceState3D,
	bounds: Rect2
) -> Array[Vector3]:
	var probes: Array[Vector3] = []
	var half: Vector2 = definition.get_half_extents()
	var offsets: Array[Vector2] = [
		Vector2(0.0, half.y + CORRIDOR_PROBE_OFFSET_M),
		Vector2(0.0, -(half.y + CORRIDOR_PROBE_OFFSET_M)),
		Vector2(half.x + CORRIDOR_PROBE_OFFSET_M, 0.0),
		Vector2(-(half.x + CORRIDOR_PROBE_OFFSET_M), 0.0),
		Vector2(half.x + CORRIDOR_PROBE_OFFSET_M, half.y + CORRIDOR_PROBE_OFFSET_M),
		Vector2(-(half.x + CORRIDOR_PROBE_OFFSET_M), half.y + CORRIDOR_PROBE_OFFSET_M),
		Vector2(half.x + CORRIDOR_PROBE_OFFSET_M, -(half.y + CORRIDOR_PROBE_OFFSET_M)),
		Vector2(-(half.x + CORRIDOR_PROBE_OFFSET_M), -(half.y + CORRIDOR_PROBE_OFFSET_M)),
	]
	for off: Vector2 in offsets:
		var candidate := Vector3(center_pos.x + off.x, center_pos.y, center_pos.z + off.y)
		var ground_pt: Vector3 = _sample_clear_walkable_ground_point(candidate, center_pos.y, bounds, space_state)
		if not ground_pt.is_finite():
			continue
		if world_nav.find_path(hub_origin, ground_pt).is_ok():
			probes.append(ground_pt)
	return probes


func _collect_reachable_source_approaches(
	source: ResourceSource,
	hub_origin: Vector3,
	exclusion_rect: Rect2,
	world_nav: WorldNavigation,
	space_state: PhysicsDirectSpaceState3D,
	bounds: Rect2
) -> Array[Vector3]:
	var approaches: Array[Vector3] = []
	var src_pos: Vector3 = source.global_position
	if not src_pos.is_finite():
		return approaches
	var solid_radius: float = maxf(source.get_solid_radius(), 0.0)
	var inter_radius: float = maxf(source.get_interaction_radius(), 0.5)
	var ring_radius: float = clampf(
		solid_radius + WorldNavigation.DEFAULT_AGENT_RADIUS + 0.15,
		WorldNavigation.DEFAULT_AGENT_RADIUS + 0.1,
		maxf(WorldNavigation.DEFAULT_AGENT_RADIUS + 0.1, inter_radius - 0.1)
	)
	var dirs: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]
	for d: Vector2 in dirs:
		var pt := Vector3(src_pos.x + d.x * ring_radius, src_pos.y, src_pos.z + d.y * ring_radius)
		if exclusion_rect.has_point(Vector2(pt.x, pt.z)):
			continue
		var ground_pt: Vector3 = _sample_clear_walkable_ground_point(pt, src_pos.y, bounds, space_state)
		if not ground_pt.is_finite():
			continue
		if world_nav.find_path(hub_origin, ground_pt).is_ok():
			approaches.append(ground_pt)
	return approaches


func _verify_candidate_connectivity(
	session: WorldNavigation.CandidateSession,
	hub_origin: Vector3,
	pre_camp_target: Vector3,
	pre_unit_targets: Array[Vector3],
	pre_source_groups: Array[Array],
	pre_checkpoints: Array[Vector3],
	pre_corridor_probes: Array[Vector3]
) -> bool:
	if pre_camp_target.is_finite():
		if not session.find_path(hub_origin, pre_camp_target).is_ok():
			return false

	for u_pos: Vector3 in pre_unit_targets:
		if not session.find_path(hub_origin, u_pos).is_ok():
			return false

	for src_group: Array in pre_source_groups:
		var any_reachable: bool = false
		for raw_pt: Variant in src_group:
			if raw_pt is Vector3 and session.find_path(hub_origin, raw_pt as Vector3).is_ok():
				any_reachable = true
				break
		if not any_reachable:
			return false

	for cp: Vector3 in pre_checkpoints:
		if not session.find_path(hub_origin, cp).is_ok():
			return false

	for probe: Vector3 in pre_corridor_probes:
		if not session.find_path(hub_origin, probe).is_ok():
			return false

	return true


func _sample_clear_walkable_ground_point(
	candidate_pos: Vector3,
	reference_y: float,
	bounds: Rect2,
	space_state: PhysicsDirectSpaceState3D
) -> Vector3:
	var inf_pt := Vector3(INF, INF, INF)
	if not candidate_pos.is_finite():
		return inf_pt
	var pt_xz := Vector2(candidate_pos.x, candidate_pos.z)
	if bounds.size.x > 0.0 and bounds.size.y > 0.0 and not bounds.has_point(pt_xz):
		return inf_pt

	_ray_query.from = Vector3(candidate_pos.x, reference_y + TERRAIN_RAY_HALF_SPAN_Y, candidate_pos.z)
	_ray_query.to = Vector3(candidate_pos.x, reference_y - TERRAIN_RAY_HALF_SPAN_Y, candidate_pos.z)
	_ray_query.collision_mask = CollisionLayers.MASK_TERRAIN
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	var hit: Dictionary = space_state.intersect_ray(_ray_query)
	if hit.is_empty():
		return inf_pt

	var ground_pos: Vector3 = hit["position"] as Vector3
	if not ground_pos.is_finite() or absf(ground_pos.y - reference_y) > 0.85:
		return inf_pt

	_clearance_sphere.radius = WorldNavigation.DEFAULT_AGENT_RADIUS * 0.9
	_shape_query.shape = _clearance_sphere
	_shape_query.transform = Transform3D(Basis.IDENTITY, ground_pos + Vector3(0.0, 0.9, 0.0))
	_shape_query.collision_mask = CollisionLayers.MASK_OBSTACLES | CollisionLayers.MASK_BUILDINGS
	_shape_query.collide_with_areas = false
	_shape_query.collide_with_bodies = true
	if not space_state.intersect_shape(_shape_query, 1).is_empty():
		return inf_pt

	return ground_pos


static func _is_point_nav_clear(
	world_pos: Vector3,
	exclusion_rect: Rect2,
	world_nav: WorldNavigation
) -> bool:
	if not world_pos.is_finite():
		return false
	if exclusion_rect.has_point(Vector2(world_pos.x, world_pos.z)):
		return false
	var snapped: Vector3 = world_nav.snap_to_navmesh(world_pos)
	if not snapped.is_finite():
		return false
	var dist_xz: float = Vector2(snapped.x - world_pos.x, snapped.z - world_pos.z).length()
	return dist_xz <= WorldNavigation.REACHABLE_TOLERANCE_XZ and absf(snapped.y - world_pos.y) <= WorldNavigation.REACHABLE_TOLERANCE_Y


func _intersect_box(
	space_state: PhysicsDirectSpaceState3D,
	shape: BoxShape3D,
	xform: Transform3D,
	collision_mask: int,
	collide_areas: bool,
	collide_bodies: bool
) -> Array[Dictionary]:
	_shape_query.shape = shape
	_shape_query.transform = xform
	_shape_query.collision_mask = collision_mask
	_shape_query.collide_with_areas = collide_areas
	_shape_query.collide_with_bodies = collide_bodies
	return space_state.intersect_shape(_shape_query, MAX_SHAPE_QUERY_RESULTS)


static func _collect_region_piles(context: ValidationContext) -> Array[GroundResourcePile]:
	var seen: Dictionary = {}
	var result: Array[GroundResourcePile] = []
	if context.ground_pile_manager != null:
		for pile: GroundResourcePile in context.ground_pile_manager.get_piles():
			if is_instance_valid(pile) and not seen.has(pile.get_instance_id()):
				seen[pile.get_instance_id()] = true
				result.append(pile)
	for extra_pile: GroundResourcePile in context.extra_piles:
		if is_instance_valid(extra_pile) and not seen.has(extra_pile.get_instance_id()):
			seen[extra_pile.get_instance_id()] = true
			result.append(extra_pile)
	return result


static func _resolve_space_state(context: ValidationContext) -> PhysicsDirectSpaceState3D:
	if context.space_state != null:
		return context.space_state
	if context.world_3d != null:
		return context.world_3d.direct_space_state
	return null


static func _resolve_region_bounds(context: ValidationContext) -> Rect2:
	if context.region_bounds.size.x > 0.0 and context.region_bounds.size.y > 0.0:
		return context.region_bounds
	if context.world_navigation != null and is_instance_valid(context.world_navigation):
		return context.world_navigation.get_map_bounds()
	return Rect2()


static func _is_footprint_inside_bounds(
	definition: BuildingDefinition,
	center_xz: Vector2,
	bounds: Rect2
) -> bool:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return false
	var rect: Rect2 = definition.get_footprint_rect_at(center_xz)
	return (
		rect.position.x >= bounds.position.x - FOOTPRINT_EDGE_TOLERANCE_M
		and rect.position.y >= bounds.position.y - FOOTPRINT_EDGE_TOLERANCE_M
		and rect.end.x <= bounds.end.x + FOOTPRINT_EDGE_TOLERANCE_M
		and rect.end.y <= bounds.end.y + FOOTPRINT_EDGE_TOLERANCE_M
	)


static func _resolve_resource_source_from_collider(collider: Object) -> ResourceSource:
	if collider == null:
		return null
	if collider is ResourceSource:
		return collider as ResourceSource
	if collider is Node:
		var cursor: Node = (collider as Node).get_parent()
		while cursor != null:
			if cursor is ResourceSource:
				return cursor as ResourceSource
			cursor = cursor.get_parent()
	return null


static func _fail_result(
	result: ValidationResult,
	code: StringName,
	message: String
) -> void:
	result.valid = false
	result.reason_code = code
	result.reason_text = message
