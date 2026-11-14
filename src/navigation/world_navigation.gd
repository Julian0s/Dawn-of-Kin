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


@export var source_root_path: NodePath = ^".."
@export var auto_bake_on_ready: bool = true
@export var map_bounds: Rect2 = Rect2(-32.0, -32.0, 64.0, 64.0)

var _is_ready: bool = false
var _is_syncing: bool = false
var _sync_started_usec: int = 0
var _sync_min_map_iteration: int = 1
var _sync_min_region_iteration: int = 1
var _last_bake_ms: float = 0.0
var _last_sync_ms: float = 0.0


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
		set_physics_process(false)
		push_error("WorldNavigation: Timed out waiting for NavigationServer3D map synchronization.")
		navigation_failed.emit("sync_timeout")
		return

	if _check_navigation_server_ready():
		_is_syncing = false
		_is_ready = true
		_last_sync_ms = float(Time.get_ticks_usec() - _sync_started_usec) / 1000.0
		set_physics_process(false)
		navigation_ready.emit()


func is_navigation_ready() -> bool:
	return _is_ready


func set_map_bounds(bounds: Rect2) -> void:
	map_bounds = bounds


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
	var result: PathResult = PathResult.new()
	if not _is_ready:
		result.status = QueryStatus.NOT_READY
		result.reachable = false
		result.resolved_target = from_pos
		result.reason = "navigation_not_ready"
		return result

	if not from_pos.is_finite() or not to_pos.is_finite():
		result.status = QueryStatus.INVALID_QUERY
		result.reachable = false
		result.resolved_target = Vector3.ZERO
		result.reason = "non_finite_coordinates"
		return result

	var map_rid: RID = get_navigation_map()
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
	nav_mesh.geometry_collision_mask = CollisionLayers.MASK_WORLD_SOLID
	nav_mesh.filter_baking_aabb = AABB(
		Vector3(map_bounds.position.x, BAKE_MIN_Y, map_bounds.position.y),
		Vector3(map_bounds.size.x, BAKE_HEIGHT_Y, map_bounds.size.y)
	)
	return nav_mesh


static func _distance_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
