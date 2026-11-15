class_name WorldNavigation
extends NavigationRegion3D
## Runtime 3D navigation manager for a region/level.
## Bakes a NavigationMesh from static world colliders, tracks real NavigationServer3D
## synchronization readiness, and provides connectivity-aware path queries.

signal navigation_ready
signal navigation_failed(reason: String)

enum QueryStatus {
	OK,
	PARTIAL_UNREACHABLE,
	NOT_READY,
	INVALID_QUERY,
}

const DEFAULT_CELL_SIZE: float = 0.25
const DEFAULT_CELL_HEIGHT: float = 0.25
const DEFAULT_AGENT_RADIUS: float = 0.5
const DEFAULT_AGENT_HEIGHT: float = 1.75
const DEFAULT_AGENT_MAX_CLIMB: float = 0.25
const DEFAULT_AGENT_MAX_SLOPE: float = 45.0
const DEFAULT_REGION_MIN_SIZE: float = 10.0
const REACHABLE_TOLERANCE_XZ: float = 0.75
const REACHABLE_TOLERANCE_Y: float = 0.75
const SYNC_TIMEOUT_SEC: float = 5.0
const BAKE_MIN_Y: float = -4.0
const BAKE_HEIGHT_Y: float = 20.0


class PathResult extends RefCounted:
	var status: int = QueryStatus.NOT_READY
	var reachable: bool = false
	var path: PackedVector3Array = PackedVector3Array()
	var resolved_target: Vector3 = Vector3.ZERO
	var reason: String = ""

	func is_ok() -> bool:
		return status == QueryStatus.OK


class CandidateSession extends RefCounted:
	var valid: bool = false
	var reason: String = ""
	var map_rid: RID = RID()
	var region_rid: RID = RID()
	var navigation_mesh: NavigationMesh = null
	var prepare_ms: float = 0.0
	var bake_ms: float = 0.0
	var server_sync_ms: float = 0.0
	var polygon_count: int = 0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			if region_rid.is_valid():
				NavigationServer3D.free_rid(region_rid)
				region_rid = RID()
			if map_rid.is_valid():
				NavigationServer3D.free_rid(map_rid)
				map_rid = RID()
			navigation_mesh = null
			valid = false

	func is_valid() -> bool:
		return valid and map_rid.is_valid() and region_rid.is_valid()

	func snap_to_navmesh(world_pos: Vector3) -> Vector3:
		if not is_valid() or not world_pos.is_finite():
			return world_pos
		return NavigationServer3D.map_get_closest_point(map_rid, world_pos)

	func find_path(from_pos: Vector3, to_pos: Vector3, optimize: bool = true) -> PathResult:
		if not is_valid():
			var err_res := PathResult.new()
			err_res.status = QueryStatus.NOT_READY
			err_res.reachable = false
			err_res.resolved_target = from_pos
			err_res.reason = reason if not reason.is_empty() else "candidate_session_invalid"
			return err_res
		return WorldNavigation.query_path_on_map(map_rid, from_pos, to_pos, optimize)

	func is_position_reachable(from_pos: Vector3, to_pos: Vector3) -> bool:
		return find_path(from_pos, to_pos).reachable

	func get_bake_metrics() -> Dictionary:
		return {
			"prepare_ms": prepare_ms,
			"bake_ms": bake_ms,
			"server_sync_ms": server_sync_ms,
			"polygon_count": polygon_count,
		}

	func dispose() -> void:
		if region_rid.is_valid():
			NavigationServer3D.free_rid(region_rid)
			region_rid = RID()
		if map_rid.is_valid():
			NavigationServer3D.free_rid(map_rid)
			map_rid = RID()
		navigation_mesh = null
		valid = false


class AsyncBakeToken extends RefCounted:
	var cancelled: bool = false

	func cancel() -> void:
		cancelled = true


@export var source_root_path: NodePath = ^".."
@export var auto_bake_on_ready: bool = true
@export var map_bounds: Rect2 = Rect2(-32.0, -32.0, 64.0, 64.0)

var _is_ready: bool = false
var _is_syncing: bool = false
var _sync_started_usec: int = 0
var _sync_min_map_iteration: int = 1
var _sync_min_region_iteration: int = 1
var _navigation_revision: int = 0
var _last_bake_ms: float = 0.0
var _last_sync_ms: float = 0.0
var _cached_static_vertices: PackedFloat32Array = PackedFloat32Array()
var _cached_static_indices: PackedInt32Array = PackedInt32Array()
var _cached_static_source_id: int = 0
var _cached_static_bounds: Rect2 = Rect2()
var _has_static_geometry_cache: bool = false
var _active_async_tokens: Array[AsyncBakeToken] = []


func _exit_tree() -> void:
	for tok: AsyncBakeToken in _active_async_tokens:
		if tok != null:
			tok.cancel()
	_active_async_tokens.clear()


func _ready() -> void:
	set_physics_process(false)
	var source_root: Node = get_node_or_null(source_root_path)
	if source_root is TestMap:
		map_bounds = (source_root as TestMap).get_map_bounds()

	if auto_bake_on_ready:
		call_deferred("request_rebake")


func _physics_process(_delta: float) -> void:
	if not _is_syncing:
		set_physics_process(false)
		return

	var elapsed_sec: float = float(Time.get_ticks_usec() - _sync_started_usec) / 1_000_000.0
	if elapsed_sec > SYNC_TIMEOUT_SEC:
		_is_syncing = false
		_is_ready = false
		_navigation_revision += 1
		set_physics_process(false)
		push_error("WorldNavigation: Timed out waiting for NavigationServer3D map synchronization.")
		navigation_failed.emit("sync_timeout")
		return

	if _check_navigation_server_ready():
		_is_syncing = false
		_is_ready = true
		_navigation_revision += 1
		_last_sync_ms = float(Time.get_ticks_usec() - _sync_started_usec) / 1000.0
		set_physics_process(false)
		navigation_ready.emit()


func is_navigation_ready() -> bool:
	return _is_ready


func get_navigation_revision() -> int:
	return _navigation_revision


func set_map_bounds(bounds: Rect2) -> void:
	if not map_bounds.is_equal_approx(bounds):
		invalidate_static_geometry_cache()
	map_bounds = bounds


func invalidate_static_geometry_cache() -> void:
	var had_cache: bool = _has_static_geometry_cache
	_has_static_geometry_cache = false
	_cached_static_vertices = PackedFloat32Array()
	_cached_static_indices = PackedInt32Array()
	_cached_static_source_id = 0
	_cached_static_bounds = Rect2()
	if had_cache:
		_navigation_revision += 1


func has_static_geometry_cache() -> bool:
	return _has_static_geometry_cache


func get_map_bounds() -> Rect2:
	return map_bounds


func get_last_bake_metrics() -> Dictionary:
	var vert_count: int = 0
	var poly_count: int = 0
	if navigation_mesh != null:
		vert_count = navigation_mesh.get_vertices().size()
		poly_count = navigation_mesh.get_polygon_count()
	return {
		"bake_ms": _last_bake_ms,
		"sync_ms": _last_sync_ms,
		"total_ms": _last_bake_ms + _last_sync_ms,
		"vertex_count": vert_count,
		"polygon_count": poly_count,
	}


## Bakes the NavigationMesh from static colliders under source_root_path and
## starts asynchronous readiness verification against NavigationServer3D.
func request_rebake() -> void:
	_is_ready = false
	_is_syncing = false
	_navigation_revision += 1

	var source_root: Node = get_node_or_null(source_root_path)
	if source_root == null:
		source_root = get_parent()
	if source_root == null:
		push_error("WorldNavigation: No valid source root found for navmesh baking.")
		navigation_failed.emit("missing_source_root")
		return

	var bake_start_usec: int = Time.get_ticks_usec()
	var nav_mesh: NavigationMesh = _create_configured_navmesh()
	var source_data: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, source_root)
	_append_sloped_terrain_side_curbs(source_root, source_data)
	_store_static_geometry_cache(source_root, source_data)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	_last_bake_ms = float(Time.get_ticks_usec() - bake_start_usec) / 1000.0

	if nav_mesh.get_polygon_count() == 0:
		push_error("WorldNavigation: Baked NavigationMesh contains 0 polygons.")
		navigation_failed.emit("empty_navmesh")
		return

	var map_rid: RID = get_navigation_map()
	var region_rid: RID = get_region_rid()
	_sync_min_map_iteration = (NavigationServer3D.map_get_iteration_id(map_rid) + 1) if map_rid.is_valid() else 1
	_sync_min_region_iteration = (NavigationServer3D.region_get_iteration_id(region_rid) + 1) if region_rid.is_valid() else 1
	navigation_mesh = nav_mesh
	_sync_started_usec = Time.get_ticks_usec()
	_is_syncing = true
	set_physics_process(true)


## Geometrically projects a world position onto the nearest navmesh surface.
## Returns world_pos unchanged if navigation is not ready.
func snap_to_navmesh(world_pos: Vector3) -> Vector3:
	if not _is_ready:
		return world_pos
	var map_rid: RID = get_navigation_map()
	if not map_rid.is_valid():
		return world_pos
	return NavigationServer3D.map_get_closest_point(map_rid, world_pos)


## Queries a path from from_pos to to_pos and distinguishes geometric projection
## from actual reachability across connected navigable regions.
func find_path(from_pos: Vector3, to_pos: Vector3, optimize: bool = true) -> PathResult:
	if not _is_ready:
		var not_ready := PathResult.new()
		not_ready.status = QueryStatus.NOT_READY
		not_ready.reachable = false
		not_ready.resolved_target = from_pos
		not_ready.reason = "navigation_not_ready"
		return not_ready
	return query_path_on_map(get_navigation_map(), from_pos, to_pos, optimize)


static func query_path_on_map(
	map_rid: RID,
	from_pos: Vector3,
	to_pos: Vector3,
	optimize: bool = true
) -> PathResult:
	var result: PathResult = PathResult.new()
	if not from_pos.is_finite() or not to_pos.is_finite():
		result.status = QueryStatus.INVALID_QUERY
		result.reachable = false
		result.resolved_target = Vector3.ZERO
		result.reason = "non_finite_coordinates"
		return result

	if not map_rid.is_valid():
		result.status = QueryStatus.NOT_READY
		result.reachable = false
		result.resolved_target = from_pos
		result.reason = "invalid_navigation_map"
		return result

	var snapped_from: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, from_pos)
	var snapped_to: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, to_pos)
	var raw_path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, snapped_from, snapped_to, optimize)

	result.path = raw_path
	if raw_path.is_empty():
		result.status = QueryStatus.PARTIAL_UNREACHABLE
		result.reachable = false
		result.resolved_target = snapped_from
		result.reason = "empty_path"
		return result

	var path_end: Vector3 = raw_path[raw_path.size() - 1]
	result.resolved_target = path_end

	var end_to_snapped_xz: float = _distance_xz(path_end, snapped_to)
	var end_to_snapped_y: float = absf(path_end.y - snapped_to.y)
	var end_to_target_xz: float = _distance_xz(path_end, to_pos)
	if end_to_snapped_xz > REACHABLE_TOLERANCE_XZ or end_to_snapped_y > REACHABLE_TOLERANCE_Y:
		result.status = QueryStatus.PARTIAL_UNREACHABLE
		result.reachable = false
		result.reason = "disconnected_region"
		return result

	if end_to_target_xz > REACHABLE_TOLERANCE_XZ:
		result.status = QueryStatus.PARTIAL_UNREACHABLE
		result.reachable = false
		result.reason = "target_outside_navmesh"
		return result

	result.status = QueryStatus.OK
	result.reachable = true
	result.reason = ""
	return result


## Creates an isolated temporary NavigationServer3D map/region baked with the current
## region geometry plus candidate building blocker boxes, without altering the active navmesh.
## Caller should call session.dispose() when done (also auto-freed on reference drop).
func create_candidate_session(candidate_boxes: Array[Dictionary]) -> CandidateSession:
	var session := CandidateSession.new()
	var prep: Dictionary = _prepare_candidate_build_inputs(candidate_boxes)
	if not (prep.get("ok", false) as bool):
		session.reason = String(prep.get("reason", "candidate_prep_failed"))
		return session

	var cand_nav: NavigationMesh = prep["nav_mesh"] as NavigationMesh
	var source_data: NavigationMeshSourceGeometryData3D = prep["source_data"] as NavigationMeshSourceGeometryData3D
	var prepare_ms: float = float(prep.get("prepare_ms", 0.0))

	var bake_start_usec: int = Time.get_ticks_usec()
	NavigationServer3D.bake_from_source_geometry_data(cand_nav, source_data)
	var bake_ms: float = float(Time.get_ticks_usec() - bake_start_usec) / 1000.0
	return _finalize_candidate_session(cand_nav, prepare_ms, bake_ms)


## Runs the isolated candidate NavMesh bake on a background worker thread and invokes
## on_complete(session) on the main thread once ready, preventing main-thread bake stalls.
func create_candidate_session_async(
	candidate_boxes: Array[Dictionary],
	on_complete: Callable
) -> AsyncBakeToken:
	var token := AsyncBakeToken.new()
	var prep: Dictionary = _prepare_candidate_build_inputs(candidate_boxes)
	if not (prep.get("ok", false) as bool):
		var err_session := CandidateSession.new()
		err_session.reason = String(prep.get("reason", "candidate_prep_failed"))
		if on_complete.is_valid():
			on_complete.call(err_session)
		return token

	var cand_nav: NavigationMesh = prep["nav_mesh"] as NavigationMesh
	var source_data: NavigationMeshSourceGeometryData3D = prep["source_data"] as NavigationMeshSourceGeometryData3D
	var prepare_ms: float = float(prep.get("prepare_ms", 0.0))
	var bake_start_usec: int = Time.get_ticks_usec()
	_prune_finished_async_tokens()
	_active_async_tokens.append(token)

	var finish_cb: Callable = WorldNavigation._on_candidate_bake_async_complete.bind(
		weakref(self),
		token,
		cand_nav,
		bake_start_usec,
		prepare_ms,
		on_complete
	)
	NavigationServer3D.bake_from_source_geometry_data_async(cand_nav, source_data, finish_cb)
	return token


func _prune_finished_async_tokens() -> void:
	for i: int in range(_active_async_tokens.size() - 1, -1, -1):
		var tok: AsyncBakeToken = _active_async_tokens[i]
		if tok == null or tok.cancelled:
			_active_async_tokens.remove_at(i)


static func _on_candidate_bake_async_complete(
	nav_ref: WeakRef,
	token: AsyncBakeToken,
	cand_nav: NavigationMesh,
	bake_start_usec: int,
	prepare_ms: float,
	on_complete: Callable
) -> void:
	if token != null and token.cancelled:
		return
	var world_nav: WorldNavigation = nav_ref.get_ref() as WorldNavigation
	if world_nav == null or not is_instance_valid(world_nav) or not world_nav.is_inside_tree():
		return
	world_nav._active_async_tokens.erase(token)
	var elapsed_bake_ms: float = float(Time.get_ticks_usec() - bake_start_usec) / 1000.0
	var session: CandidateSession = world_nav._finalize_candidate_session(cand_nav, prepare_ms, elapsed_bake_ms)
	if on_complete.is_valid():
		on_complete.call(session)
	else:
		session.dispose()


func _store_static_geometry_cache(source_root: Node, source_data: NavigationMeshSourceGeometryData3D) -> void:
	if source_root == null or not is_instance_valid(source_root) or source_data == null:
		invalidate_static_geometry_cache()
		return
	var verts: PackedFloat32Array = source_data.get_vertices()
	var indices: PackedInt32Array = source_data.get_indices()
	if verts.is_empty():
		invalidate_static_geometry_cache()
		return
	_cached_static_vertices = verts
	_cached_static_indices = indices
	_cached_static_source_id = source_root.get_instance_id()
	_cached_static_bounds = map_bounds
	_has_static_geometry_cache = true


func _prepare_candidate_build_inputs(candidate_boxes: Array[Dictionary]) -> Dictionary:
	var source_root: Node = get_node_or_null(source_root_path)
	if source_root == null:
		source_root = get_parent()
	if source_root == null or not is_instance_valid(source_root):
		return {"ok": false, "reason": "missing_source_root"}

	var prep_start_usec: int = Time.get_ticks_usec()
	var cand_nav: NavigationMesh = _create_configured_navmesh()
	var source_data := NavigationMeshSourceGeometryData3D.new()

	var cache_valid: bool = (
		_has_static_geometry_cache
		and _cached_static_source_id == source_root.get_instance_id()
		and _cached_static_bounds.is_equal_approx(map_bounds)
		and not _cached_static_vertices.is_empty()
	)
	if cache_valid:
		source_data.append_arrays(_cached_static_vertices, _cached_static_indices)
	else:
		NavigationServer3D.parse_source_geometry_data(cand_nav, source_data, source_root)
		_append_sloped_terrain_side_curbs(source_root, source_data)
		_store_static_geometry_cache(source_root, source_data)

	for box_entry: Dictionary in candidate_boxes:
		var box_pos: Variant = box_entry.get("position")
		var box_size: Variant = box_entry.get("size")
		if not (box_pos is Vector3) or not (box_size is Vector3):
			continue
		var p: Vector3 = box_pos as Vector3
		var s: Vector3 = box_size as Vector3
		if not p.is_finite() or not s.is_finite() or s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
			continue
		# Extend slightly below floor surface (0.3 m) so Recast has zero bottom gap against slopes/ground.
		var total_height: float = s.y + 0.3
		var box_center := Vector3(p.x, p.y - 0.3 + total_height * 0.5, p.z)
		var faces: PackedVector3Array = _build_box_faces(Vector3(s.x, total_height, s.z))
		source_data.add_faces(faces, Transform3D(Basis.IDENTITY, box_center))

	var prepare_ms: float = float(Time.get_ticks_usec() - prep_start_usec) / 1000.0
	return {
		"ok": true,
		"nav_mesh": cand_nav,
		"source_data": source_data,
		"prepare_ms": prepare_ms,
	}


func _finalize_candidate_session(
	cand_nav: NavigationMesh,
	prepare_ms: float,
	bake_ms: float
) -> CandidateSession:
	var session := CandidateSession.new()
	session.prepare_ms = prepare_ms
	session.bake_ms = bake_ms
	session.polygon_count = cand_nav.get_polygon_count() if cand_nav != null else 0
	if cand_nav == null or session.polygon_count == 0:
		session.reason = "empty_candidate_navmesh"
		return session

	var sync_start_usec: int = Time.get_ticks_usec()
	var cand_map_rid: RID = NavigationServer3D.map_create()
	var cand_reg_rid: RID = NavigationServer3D.region_create()
	if not cand_map_rid.is_valid() or not cand_reg_rid.is_valid():
		if cand_reg_rid.is_valid():
			NavigationServer3D.free_rid(cand_reg_rid)
		if cand_map_rid.is_valid():
			NavigationServer3D.free_rid(cand_map_rid)
		session.reason = "failed_to_allocate_candidate_rids"
		return session

	NavigationServer3D.map_set_use_async_iterations(cand_map_rid, false)
	NavigationServer3D.map_set_up(cand_map_rid, Vector3.UP)
	NavigationServer3D.map_set_cell_size(cand_map_rid, cand_nav.cell_size)
	NavigationServer3D.map_set_cell_height(cand_map_rid, cand_nav.cell_height)
	NavigationServer3D.map_set_active(cand_map_rid, true)

	NavigationServer3D.region_set_use_async_iterations(cand_reg_rid, false)
	NavigationServer3D.region_set_map(cand_reg_rid, cand_map_rid)
	NavigationServer3D.region_set_navigation_mesh(cand_reg_rid, cand_nav)

	NavigationServer3D.map_force_update(cand_map_rid)
	if NavigationServer3D.map_get_iteration_id(cand_map_rid) == 0:
		NavigationServer3D.map_force_update(cand_map_rid)

	var attached_regions: Array[RID] = NavigationServer3D.map_get_regions(cand_map_rid)
	if attached_regions.is_empty() or not attached_regions.has(cand_reg_rid):
		NavigationServer3D.free_rid(cand_reg_rid)
		NavigationServer3D.free_rid(cand_map_rid)
		session.reason = "candidate_region_attach_failed"
		return session

	session.server_sync_ms = float(Time.get_ticks_usec() - sync_start_usec) / 1000.0
	session.map_rid = cand_map_rid
	session.region_rid = cand_reg_rid
	session.navigation_mesh = cand_nav
	session.valid = true
	return session


func is_position_reachable(from_pos: Vector3, to_pos: Vector3) -> bool:
	return find_path(from_pos, to_pos).reachable


func resolve_reachable_target(from_pos: Vector3, to_pos: Vector3) -> Vector3:
	return find_path(from_pos, to_pos).resolved_target


func _check_navigation_server_ready() -> bool:
	var map_rid: RID = get_navigation_map()
	var region_rid: RID = get_region_rid()
	if not map_rid.is_valid() or not region_rid.is_valid():
		return false
	if NavigationServer3D.map_get_iteration_id(map_rid) < _sync_min_map_iteration:
		return false
	if NavigationServer3D.region_get_iteration_id(region_rid) < _sync_min_region_iteration:
		return false
	var regions: Array[RID] = NavigationServer3D.map_get_regions(map_rid)
	if regions.is_empty() or not regions.has(region_rid):
		return false

	var center_xz: Vector2 = map_bounds.get_center()
	var probe: Vector3 = Vector3(center_xz.x, 0.0, center_xz.y)
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, probe)
	if not closest.is_finite():
		return false
	var probe_path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, closest, closest, true)
	return not probe_path.is_empty()


func _create_configured_navmesh() -> NavigationMesh:
	var nav_mesh: NavigationMesh = NavigationMesh.new()
	nav_mesh.cell_size = DEFAULT_CELL_SIZE
	nav_mesh.cell_height = DEFAULT_CELL_HEIGHT
	nav_mesh.agent_radius = DEFAULT_AGENT_RADIUS
	nav_mesh.agent_height = DEFAULT_AGENT_HEIGHT
	nav_mesh.agent_max_climb = DEFAULT_AGENT_MAX_CLIMB
	nav_mesh.agent_max_slope = DEFAULT_AGENT_MAX_SLOPE
	nav_mesh.region_min_size = DEFAULT_REGION_MIN_SIZE
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = CollisionLayers.MASK_NAV_STATIC
	nav_mesh.filter_baking_aabb = AABB(
		Vector3(map_bounds.position.x, BAKE_MIN_Y, map_bounds.position.y),
		Vector3(map_bounds.size.x, BAKE_HEIGHT_Y, map_bounds.size.y)
	)
	return nav_mesh


static func _append_sloped_terrain_side_curbs(
	source_root: Node,
	source_data: NavigationMeshSourceGeometryData3D
) -> void:
	if source_root == null or source_data == null:
		return
	const CURB_WIDTH: float = 0.40
	const CURB_START_INSET: float = 0.05
	const CURB_TOP_INSET: float = 0.15
	const CURB_MIN_LEN: float = 0.50
	const CURB_BOTTOM_MARGIN: float = 0.50
	const CURB_TOP_MARGIN: float = 0.90
	const CURB_LATERAL_OVERLAP: float = 0.02

	var queue: Array[Node] = [source_root]
	var head: int = 0
	while head < queue.size():
		var node: Node = queue[head]
		head += 1
		for child: Node in node.get_children():
			queue.append(child)
		if not (node is StaticBody3D):
			continue
		var body: StaticBody3D = node as StaticBody3D
		if (body.collision_layer & CollisionLayers.MASK_TERRAIN) == 0:
			continue

		for child: Node in body.get_children():
			if not (child is CollisionShape3D):
				continue
			var col_shape: CollisionShape3D = child as CollisionShape3D
			if col_shape.disabled or not (col_shape.shape is BoxShape3D):
				continue
			var xf: Transform3D = col_shape.global_transform
			var b: Basis = xf.basis.orthonormalized()
			var up_axis: Vector3 = b.y if b.y.y >= 0.0 else -b.y
			# Process walkable sloped slabs (approx 5..45 degrees) whose sides drop onto lower terrain.
			if up_axis.y > 0.996 or up_axis.y < 0.707:
				continue

			var scale_vec: Vector3 = xf.basis.get_scale().abs()
			var box_size: Vector3 = (col_shape.shape as BoxShape3D).size * scale_vec
			var slope_axis: Vector3 = b.x
			var slope_half: float = box_size.x * 0.5
			var lat_half: float = box_size.z * 0.5
			if absf(b.z.y) > absf(b.x.y):
				slope_axis = b.z
				slope_half = box_size.z * 0.5
				lat_half = box_size.x * 0.5
			if slope_axis.y < 0.0:
				slope_axis = -slope_axis

			var horiz_up := Vector3(slope_axis.x, 0.0, slope_axis.z)
			if horiz_up.length_squared() <= 0.0001:
				continue
			horiz_up = horiz_up.normalized()
			var horiz_lat: Vector3 = horiz_up.cross(Vector3.UP).normalized()
			var curb_basis := Basis(horiz_up, Vector3.UP, horiz_lat)

			var top_center: Vector3 = col_shape.global_position + up_axis * (box_size.y * 0.5)
			var foot_pos: Vector3 = top_center - slope_axis * slope_half
			var crest_pos: Vector3 = top_center + slope_axis * slope_half
			var horiz_len: float = Vector2(crest_pos.x - foot_pos.x, crest_pos.z - foot_pos.z).length()
			if horiz_len <= CURB_START_INSET + CURB_MIN_LEN:
				continue

			var u_start: float = CURB_START_INSET
			var u_end: float = maxf(u_start + CURB_MIN_LEN, horiz_len - CURB_TOP_INSET)
			var curb_len: float = u_end - u_start
			var y_min: float = minf(foot_pos.y, crest_pos.y) - CURB_BOTTOM_MARGIN
			var y_max: float = maxf(foot_pos.y, crest_pos.y) + CURB_TOP_MARGIN
			var curb_height: float = y_max - y_min
			var center_y: float = (y_min + y_max) * 0.5
			var foot_xz := Vector3(foot_pos.x, 0.0, foot_pos.z)
			var mid_u: float = (u_start + u_end) * 0.5
			var curb_faces: PackedVector3Array = _build_box_faces(Vector3(curb_len, curb_height, CURB_WIDTH))

			for side: float in [-1.0, 1.0]:
				var lat_offset: float = (lat_half + CURB_WIDTH * 0.5 - CURB_LATERAL_OVERLAP) * side
				var curb_origin := foot_xz + horiz_up * mid_u + horiz_lat * lat_offset + Vector3(0.0, center_y, 0.0)
				source_data.add_faces(curb_faces, Transform3D(curb_basis, curb_origin))


static func _build_box_faces(size: Vector3) -> PackedVector3Array:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	var p000 := Vector3(-hx, -hy, -hz)
	var p100 := Vector3(hx, -hy, -hz)
	var p110 := Vector3(hx, hy, -hz)
	var p010 := Vector3(-hx, hy, -hz)
	var p001 := Vector3(-hx, -hy, hz)
	var p101 := Vector3(hx, -hy, hz)
	var p111 := Vector3(hx, hy, hz)
	var p011 := Vector3(-hx, hy, hz)
	return PackedVector3Array([
		p010, p110, p111, p010, p111, p011,
		p000, p101, p100, p000, p001, p101,
		p001, p011, p111, p001, p111, p101,
		p000, p100, p110, p000, p110, p010,
		p100, p101, p111, p100, p111, p110,
		p000, p010, p011, p000, p011, p001,
	])


static func _distance_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
