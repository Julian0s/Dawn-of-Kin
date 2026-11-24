class_name UnitMovement
extends Node
## Handles NavigationAgent3D path following on the XZ plane, gravity, move_and_slide(),
## smooth facing rotation, arrival detection, and bounded stuck recovery.
## Does not decide orders or read player input.

enum MoveState {
	IDLE,
	MOVING,
	ARRIVED,
	FAILED_STUCK,
	FAILED_INVALID,
}

enum SpeedContext {
	NORMAL,
	WORK,
}

const ARRIVAL_TOLERANCE_XZ: float = 0.25
const ARRIVAL_TOLERANCE_Y: float = 1.0
const WAYPOINT_ARRIVAL_XZ: float = 0.20
const WAYPOINT_VERTICAL_TOLERANCE_Y: float = 0.65
const AGENT_PATH_DESIRED_DISTANCE: float = 0.45
const AGENT_TARGET_DESIRED_DISTANCE: float = 0.25
const AGENT_PATH_MAX_DISTANCE: float = 2.0
const FLOOR_SNAP_LENGTH_METERS: float = 0.3
const MAX_TERRAIN_STEP_UP_HEIGHT: float = 0.42
const STEP_UP_FORWARD_PROBE: float = 0.14
const STUCK_WINDOW_SEC: float = 1.5
const STUCK_MIN_PROGRESS_XZ: float = 0.25
const STUCK_SPEED_REFERENCE: float = 2.5
const STUCK_WINDOW_MAX_SCALE: float = 2.5
const STUCK_MIN_EFFECTIVE_SPEED: float = 0.4
const DEFAULT_WORK_APPROACH_SPEED: float = 2.5
const DEFAULT_MAX_LOAD_SPEED_MULTIPLIER: float = 0.60
const SPEED_TRANSITION_RATE: float = 8.0
const MAX_REPATH_ATTEMPTS: int = 1
const AVOIDANCE_RADIUS: float = 0.5
const AVOIDANCE_NEIGHBOR_DISTANCE: float = 3.5
const AVOIDANCE_MAX_NEIGHBORS: int = 8
const AVOIDANCE_TIME_HORIZON_AGENTS: float = 0.8
const AVOIDANCE_PRIORITY_IDLE: float = 1.0
const AVOIDANCE_PRIORITY_MOVING: float = 0.5
const AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_XZ: float = 0.45
const AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_Y: float = 0.75
const AVOIDANCE_MIN_ROTATION_SPEED: float = 0.2

@export var navigation_agent_path: NodePath = ^"../NavigationAgent3D"

var _body: CharacterBody3D = null
var _agent: NavigationAgent3D = null
var _world_navigation: WorldNavigation = null
var _carry_load: UnitCarryLoad = null

var _move_speed: float = 4.8
var _work_approach_speed: float = DEFAULT_WORK_APPROACH_SPEED
var _max_load_speed_multiplier: float = DEFAULT_MAX_LOAD_SPEED_MULTIPLIER
var _speed_context: SpeedContext = SpeedContext.NORMAL
var _target_move_speed: float = 4.8
var _effective_move_speed: float = 4.8
var _turn_rate: float = 10.0
var _gravity: float = 9.8

var _move_state: MoveState = MoveState.IDLE
var _target_position: Vector3 = Vector3.ZERO
var _active_path: PackedVector3Array = PackedVector3Array()
var _active_path_index: int = 0
var _progress_anchor_xz: Vector2 = Vector2.ZERO
var _no_progress_timer: float = 0.0
var _repath_attempts: int = 0
var _safe_velocity: Vector3 = Vector3.ZERO
var _has_safe_velocity: bool = false
var _awaiting_pending_nav_sync: bool = false
var _navigation_failure_reason: String = ""
var _repath_partial_unreachable: bool = false
var _repath_navigation_reason: String = ""


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_resolve_nodes()
	_configure_body_and_agent()
	_recompute_target_speed(true)


func _exit_tree() -> void:
	_disconnect_navigation_signals()
	_disconnect_agent_signals()
	_disconnect_carry_load_signals()


func configure(body: CharacterBody3D, agent: NavigationAgent3D = null) -> void:
	_body = body
	if agent != null and agent != _agent:
		_disconnect_agent_signals()
		_agent = agent
	elif _agent == null:
		_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D
	_configure_body_and_agent()


func set_world_navigation(world_nav: WorldNavigation) -> void:
	_disconnect_navigation_signals()
	_world_navigation = world_nav
	_connect_navigation_signals()
	_bind_agent_map()


func get_world_navigation() -> WorldNavigation:
	return _world_navigation


func set_carry_load(carry_load: UnitCarryLoad) -> void:
	if _carry_load == carry_load:
		_recompute_target_speed(_move_state != MoveState.MOVING)
		return
	_disconnect_carry_load_signals()
	_carry_load = carry_load
	_connect_carry_load_signals()
	_recompute_target_speed(_move_state != MoveState.MOVING)


func set_motion_profile(
	move_speed: float,
	turn_rate: float,
	work_approach_speed: float = -1.0,
	max_load_speed_multiplier: float = -1.0
) -> void:
	_move_speed = maxf(move_speed, 0.1)
	_turn_rate = maxf(turn_rate, 0.1)
	if work_approach_speed > 0.0 and is_finite(work_approach_speed):
		_work_approach_speed = maxf(work_approach_speed, 0.1)
	if max_load_speed_multiplier > 0.0 and is_finite(max_load_speed_multiplier):
		_max_load_speed_multiplier = clampf(max_load_speed_multiplier, 0.1, 1.0)
	_recompute_target_speed(_move_state != MoveState.MOVING)


func set_speed_context(context: SpeedContext) -> void:
	if _speed_context == context:
		return
	_speed_context = context
	_recompute_target_speed(_move_state != MoveState.MOVING)


func get_speed_context() -> SpeedContext:
	return _speed_context


func get_target_move_speed() -> float:
	return _target_move_speed


func get_effective_move_speed() -> float:
	return _effective_move_speed


func get_current_load_multiplier() -> float:
	return compute_load_speed_multiplier(_get_load_fill_ratio(), _max_load_speed_multiplier)


static func compute_load_speed_multiplier(
	fill_ratio: float,
	max_load_multiplier: float = DEFAULT_MAX_LOAD_SPEED_MULTIPLIER
) -> float:
	if not is_finite(fill_ratio) or fill_ratio <= 0.0:
		return 1.0
	var clamped_ratio: float = clampf(fill_ratio, 0.0, 1.0)
	var min_mult: float = clampf(max_load_multiplier, 0.1, 1.0) if is_finite(max_load_multiplier) else DEFAULT_MAX_LOAD_SPEED_MULTIPLIER
	return lerpf(1.0, min_mult, clamped_ratio)


static func compute_stuck_window_sec(effective_speed: float) -> float:
	var safe_speed: float = effective_speed if is_finite(effective_speed) else STUCK_MIN_EFFECTIVE_SPEED
	var ref_speed: float = clampf(safe_speed, STUCK_MIN_EFFECTIVE_SPEED, STUCK_SPEED_REFERENCE)
	var scale: float = clampf(STUCK_SPEED_REFERENCE / ref_speed, 1.0, STUCK_WINDOW_MAX_SCALE)
	return STUCK_WINDOW_SEC * scale


func get_move_state() -> MoveState:
	return _move_state


func get_target_position() -> Vector3:
	return _target_position


func is_repath_partial_unreachable() -> bool:
	return _repath_partial_unreachable


func get_repath_navigation_reason() -> String:
	return _repath_navigation_reason


func get_repath_attempts() -> int:
	return _repath_attempts


func get_no_progress_timer() -> float:
	return _no_progress_timer


func is_at_target(target: Vector3) -> bool:
	if _body == null or not target.is_finite():
		return false
	var pos: Vector3 = _body.global_position
	var dist_xz: float = _distance_xz(pos, target)
	var dy: float = absf(pos.y - target.y)
	return dist_xz <= ARRIVAL_TOLERANCE_XZ and dy <= ARRIVAL_TOLERANCE_Y


func begin_move_to(target: Vector3) -> bool:
	_resolve_nodes()
	if _body == null or _agent == null or not target.is_finite():
		_move_state = MoveState.FAILED_INVALID
		return false

	_bind_agent_map()
	_recompute_target_speed(_move_state != MoveState.MOVING)
	_target_position = target
	_repath_partial_unreachable = false
	_repath_navigation_reason = ""
	_navigation_failure_reason = ""
	_awaiting_pending_nav_sync = false
	_repath_attempts = 0
	_no_progress_timer = 0.0
	_progress_anchor_xz = Vector2(_body.global_position.x, _body.global_position.z)
	_safe_velocity = Vector3.ZERO
	_has_safe_velocity = false
	if _world_navigation != null:
		var query: WorldNavigation.PathResult = _world_navigation.find_path(_body.global_position, target)
		if query.reason == "pending_building_nav_sync":
			_move_state = MoveState.MOVING
			_wait_for_pending_navigation()
			return true
		if query.reason in ["pending_building_blocker", "navigation_rebake_degraded"]:
			_fail_pending_navigation(query.reason)
			return false

	if is_at_target(_target_position):
		_move_state = MoveState.ARRIVED
		_agent.avoidance_priority = AVOIDANCE_PRIORITY_IDLE
		_agent.set_velocity(Vector3.ZERO)
		return true

	_agent.max_speed = _effective_move_speed
	_agent.avoidance_priority = AVOIDANCE_PRIORITY_MOVING
	_agent.target_position = _target_position
	_agent.get_next_path_position()
	_refresh_active_path()
	_move_state = MoveState.MOVING
	_check_pending_path()
	return true


func stop_movement() -> void:
	_awaiting_pending_nav_sync = false
	_move_state = MoveState.IDLE
	_no_progress_timer = 0.0
	_repath_attempts = 0
	_active_path = PackedVector3Array()
	_active_path_index = 0
	_safe_velocity = Vector3.ZERO
	_has_safe_velocity = false
	if _body != null:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
	if _agent != null:
		_agent.avoidance_priority = AVOIDANCE_PRIORITY_IDLE
		_agent.set_velocity(Vector3.ZERO)
		if _body != null and _body.is_inside_tree():
			_agent.target_position = _body.global_position


func face_towards(world_point: Vector3, delta: float) -> void:
	_resolve_nodes()
	if _body == null or not world_point.is_finite():
		return
	var dir_xz := Vector2(world_point.x - _body.global_position.x, world_point.z - _body.global_position.z)
	if dir_xz.length_squared() <= 0.0001:
		return
	var move_dir: Vector2 = dir_xz.normalized()
	var target_yaw: float = atan2(-move_dir.x, -move_dir.y)
	var rot_alpha: float = 1.0 - exp(-_turn_rate * maxf(delta, 0.0))
	_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, rot_alpha)


func step_movement(delta: float) -> void:
	_resolve_nodes()
	if _body == null:
		return

	var vel: Vector3 = _body.velocity
	if not _body.is_on_floor():
		vel.y -= _gravity * delta
	elif vel.y < 0.0:
		vel.y = 0.0
	if _move_state == MoveState.MOVING:
		_check_pending_path()
	if _awaiting_pending_nav_sync:
		_body.velocity = Vector3(0.0, vel.y, 0.0)
		_body.move_and_slide()
		return

	if _move_state != MoveState.MOVING:
		if _agent != null and _agent.avoidance_enabled:
			_agent.avoidance_priority = AVOIDANCE_PRIORITY_IDLE
			_agent.set_velocity(Vector3.ZERO)
		vel.x = 0.0
		vel.z = 0.0
		_body.velocity = vel
		_body.move_and_slide()
		return

	if is_at_target(_target_position):
		_finish_arrival(vel)
		return

	if _agent == null:
		_move_state = MoveState.FAILED_INVALID
		vel.x = 0.0
		vel.z = 0.0
		_body.velocity = vel
		_body.move_and_slide()
		return

	_advance_effective_speed(delta)

	var steer_point: Vector3 = _resolve_steer_point()
	if _awaiting_pending_nav_sync or _move_state == MoveState.FAILED_INVALID:
		_body.velocity = Vector3(0, vel.y, 0)
		_body.move_and_slide()
		return
	var body_pos: Vector3 = _body.global_position
	var delta_xz: Vector2 = Vector2(steer_point.x - body_pos.x, steer_point.z - body_pos.z)
	var dist_xz: float = delta_xz.length()

	var desired_xz: Vector2 = Vector2.ZERO
	if dist_xz > 0.001:
		var dir_xz: Vector2 = delta_xz / dist_xz
		var step_speed: float = _effective_move_speed
		var on_final_segment: bool = _active_path.is_empty() or _active_path_index >= _active_path.size() - 1
		if on_final_segment and delta > 0.0:
			var dist_to_final_xz: float = _distance_xz(body_pos, _target_position)
			step_speed = minf(_effective_move_speed, dist_to_final_xz / delta)
		desired_xz = dir_xz * step_speed

	if _agent.avoidance_enabled:
		_agent.max_speed = _effective_move_speed
		_agent.avoidance_priority = AVOIDANCE_PRIORITY_MOVING
		_agent.set_velocity(Vector3(desired_xz.x, 0.0, desired_xz.y))

	var applied_xz: Vector2 = desired_xz
	if _agent.avoidance_enabled and _has_safe_velocity:
		var safe_xz := Vector2(_safe_velocity.x, _safe_velocity.z)
		if safe_xz.length() > _effective_move_speed:
			safe_xz = safe_xz.normalized() * _effective_move_speed
		applied_xz = _clamp_avoidance_to_navmesh(body_pos, safe_xz, desired_xz, delta)

	vel.x = applied_xz.x
	vel.z = applied_xz.y
	if _world_navigation != null and _world_navigation.is_route_blocked_by_pending_building(body_pos, body_pos + Vector3(applied_xz.x, 0, applied_xz.y) * delta):
		_check_pending_path()
		_wait_for_pending_navigation()
		_body.velocity = Vector3(0, vel.y, 0)
		_body.move_and_slide()
		return

	if applied_xz.length() > AVOIDANCE_MIN_ROTATION_SPEED:
		var move_dir: Vector2 = applied_xz.normalized()
		var target_yaw: float = atan2(-move_dir.x, -move_dir.y)
		var rot_alpha: float = 1.0 - exp(-_turn_rate * delta)
		_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, rot_alpha)

	var pre_move_xz: Vector2 = Vector2(_body.global_position.x, _body.global_position.z)
	_body.velocity = vel
	_body.move_and_slide()

	if applied_xz.length() > 0.001:
		var post_move_xz: Vector2 = Vector2(_body.global_position.x, _body.global_position.z)
		var expected_xz: float = applied_xz.length() * delta
		if expected_xz > 0.01 and post_move_xz.distance_to(pre_move_xz) < expected_xz * 0.35:
			_try_terrain_step_up(applied_xz.normalized(), expected_xz)

	if is_at_target(_target_position):
		_finish_arrival(_body.velocity)
		return

	_update_stuck_detection(delta)


func _finish_arrival(current_vel: Vector3) -> void:
	_move_state = MoveState.ARRIVED
	_no_progress_timer = 0.0
	_safe_velocity = Vector3.ZERO
	_has_safe_velocity = false
	_body.velocity = Vector3(0.0, current_vel.y, 0.0)
	if _agent != null:
		_agent.avoidance_priority = AVOIDANCE_PRIORITY_IDLE
		_agent.set_velocity(Vector3.ZERO)


func _resolve_steer_point() -> Vector3:
	if _active_path.is_empty():
		_agent.get_next_path_position()
		_refresh_active_path()

	var body_pos: Vector3 = _body.global_position
	while _active_path_index < _active_path.size() - 1:
		var wp: Vector3 = _active_path[_active_path_index]
		var same_vertical_band: bool = absf(body_pos.y - wp.y) <= WAYPOINT_VERTICAL_TOLERANCE_Y
		if same_vertical_band and _distance_xz(body_pos, wp) <= WAYPOINT_ARRIVAL_XZ:
			_active_path_index += 1
		else:
			break

	if _active_path_index < _active_path.size() - 1:
		return _active_path[_active_path_index]

	return _target_position


func _refresh_active_path() -> void:
	_active_path = _agent.get_current_navigation_path()
	if _active_path.is_empty() and _world_navigation != null and _world_navigation.is_navigation_ready():
		var fallback_query: WorldNavigation.PathResult = _world_navigation.find_path(_body.global_position, _target_position)
		_active_path = fallback_query.path
	_active_path_index = 0
	if _active_path.size() > 1:
		var body_pos: Vector3 = _body.global_position
		while _active_path_index < _active_path.size() - 1:
			var wp: Vector3 = _active_path[_active_path_index]
			if absf(body_pos.y - wp.y) <= WAYPOINT_VERTICAL_TOLERANCE_Y and _distance_xz(body_pos, wp) <= WAYPOINT_ARRIVAL_XZ:
				_active_path_index += 1
			else:
				break
	_check_pending_path()


func _update_stuck_detection(delta: float) -> void:
	var current_xz: Vector2 = Vector2(_body.global_position.x, _body.global_position.z)
	if current_xz.distance_to(_progress_anchor_xz) >= STUCK_MIN_PROGRESS_XZ:
		_progress_anchor_xz = current_xz
		_no_progress_timer = 0.0
		return

	_no_progress_timer += delta
	var stuck_window: float = compute_stuck_window_sec(_effective_move_speed)
	if _no_progress_timer < stuck_window:
		return

	if _repath_attempts < MAX_REPATH_ATTEMPTS:
		_repath_attempts += 1
		_no_progress_timer = 0.0
		_progress_anchor_xz = current_xz
		_perform_controlled_repath()
	else:
		_move_state = MoveState.FAILED_STUCK
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0


func _perform_controlled_repath() -> void:
	if _world_navigation != null and _world_navigation.is_navigation_ready():
		var repath_result: WorldNavigation.PathResult = _world_navigation.find_path(_body.global_position, _target_position)
		if repath_result.reason == "pending_building_nav_sync":
			_wait_for_pending_navigation()
			return
		if repath_result.reason in ["navigation_rebake_degraded", "pending_building_blocker"]:
			_fail_pending_navigation(repath_result.reason)
			return
		if repath_result.path.is_empty() and not repath_result.is_ok():
			_fail_pending_navigation(repath_result.reason)
			return
		if repath_result.status == WorldNavigation.QueryStatus.OK or (
			repath_result.status == WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE
			and not repath_result.path.is_empty()
		):
			if repath_result.status == WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE:
				_repath_partial_unreachable = true
				_repath_navigation_reason = repath_result.reason
			_target_position = repath_result.resolved_target

	_agent.target_position = _target_position
	_agent.get_next_path_position()
	_refresh_active_path()
	_check_pending_path()


func _connect_navigation_signals() -> void:
	if not is_instance_valid(_world_navigation):
		return
	if not _world_navigation.building_blocker_added.is_connected(_on_building_blocker_added):
		_world_navigation.building_blocker_added.connect(_on_building_blocker_added)
		_world_navigation.navigation_ready.connect(_on_navigation_ready)
		_world_navigation.navigation_rebake_degraded.connect(_on_navigation_degraded)


func _disconnect_navigation_signals() -> void:
	if is_instance_valid(_world_navigation) and _world_navigation.building_blocker_added.is_connected(_on_building_blocker_added):
		_world_navigation.building_blocker_added.disconnect(_on_building_blocker_added)
		_world_navigation.navigation_ready.disconnect(_on_navigation_ready)
		_world_navigation.navigation_rebake_degraded.disconnect(_on_navigation_degraded)


func _on_building_blocker_added(_rect: Rect2) -> void:
	_check_pending_path()


func _check_pending_path() -> void:
	if _move_state != MoveState.MOVING or _world_navigation == null or _world_navigation._pending_building_blockers.is_empty():
		return
	var path: PackedVector3Array = PackedVector3Array([_body.global_position])
	for idx: int in range(_active_path_index, _active_path.size()):
		path.append(_active_path[idx])
	if path.size() == 1:
		path.append(_target_position)
	# Also protect paths cached directly in NavigationAgent3D on the old mesh.
	var agent_path: PackedVector3Array = _agent.get_current_navigation_path() if _agent != null else PackedVector3Array()
	var intersects_agent: bool = _world_navigation.does_path_intersect_pending_blockers(agent_path, _agent.get_current_navigation_path_index() if _agent != null else 0)
	if not _world_navigation.does_path_intersect_pending_blockers(path) and not intersects_agent:
		return
	for idx: int in range(path.size() - 1):
		if _world_navigation.get_pending_route_reason(path[idx], path[idx + 1]) == "navigation_rebake_degraded":
			_fail_pending_navigation("navigation_rebake_degraded")
			return
	_wait_for_pending_navigation()


func _wait_for_pending_navigation() -> void:
	_awaiting_pending_nav_sync = true
	_no_progress_timer = 0.0
	_safe_velocity = Vector3.ZERO
	_has_safe_velocity = false
	if _body != null:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
	if _agent != null:
		_agent.set_velocity(Vector3.ZERO)


func _fail_pending_navigation(reason: String) -> void:
	_wait_for_pending_navigation()
	_awaiting_pending_nav_sync = false
	_navigation_failure_reason = reason
	_move_state = MoveState.FAILED_INVALID


func _on_navigation_ready() -> void:
	if not _awaiting_pending_nav_sync or _move_state != MoveState.MOVING:
		return
	_awaiting_pending_nav_sync = false
	_no_progress_timer = 0.0
	_progress_anchor_xz = Vector2(_body.global_position.x, _body.global_position.z)
	_perform_controlled_repath()


func _on_navigation_degraded(_count: int, _reason: String) -> void:
	if _awaiting_pending_nav_sync:
		_fail_pending_navigation("navigation_rebake_degraded")


func _try_terrain_step_up(dir_xz: Vector2, desired_step: float) -> void:
	if not _body.is_on_floor():
		return

	var hit_steep_terrain: bool = false
	for i: int in range(_body.get_slide_collision_count()):
		var slide_col: KinematicCollision3D = _body.get_slide_collision(i)
		if slide_col == null:
			continue
		var collider: CollisionObject3D = slide_col.get_collider() as CollisionObject3D
		if collider == null:
			continue
		if (collider.collision_layer & CollisionLayers.MASK_TERRAIN) == 0:
			continue
		if slide_col.get_normal().y < 0.707:
			hit_steep_terrain = true
			break

	if not hit_steep_terrain:
		return

	var start_tf: Transform3D = _body.global_transform
	var up_motion: Vector3 = Vector3(0.0, MAX_TERRAIN_STEP_UP_HEIGHT, 0.0)
	if _body.test_move(start_tf, up_motion):
		return

	var raised_tf: Transform3D = start_tf.translated(up_motion)
	var fwd_dist: float = maxf(desired_step, STEP_UP_FORWARD_PROBE)
	var fwd_motion: Vector3 = Vector3(dir_xz.x * fwd_dist, 0.0, dir_xz.y * fwd_dist)
	if _body.test_move(raised_tf, fwd_motion):
		return

	var stepped_tf: Transform3D = raised_tf.translated(fwd_motion)
	var down_col: KinematicCollision3D = KinematicCollision3D.new()
	var down_motion: Vector3 = Vector3(0.0, -(MAX_TERRAIN_STEP_UP_HEIGHT + 0.05), 0.0)
	if not _body.test_move(stepped_tf, down_motion, down_col):
		return

	if down_col.get_normal().y < cos(_body.floor_max_angle):
		return

	var land_collider: CollisionObject3D = down_col.get_collider() as CollisionObject3D
	if land_collider == null or (land_collider.collision_layer & CollisionLayers.MASK_TERRAIN) == 0:
		return

	_body.global_position = stepped_tf.origin + down_col.get_travel()
	_body.apply_floor_snap()


func _resolve_nodes() -> void:
	if _body == null:
		_body = get_parent() as CharacterBody3D
	if _agent == null:
		_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D
	if _world_navigation == null:
		set_world_navigation(_find_world_navigation())


func _configure_body_and_agent() -> void:
	if _body != null:
		_body.floor_stop_on_slope = true
		_body.floor_constant_speed = true
		_body.floor_max_angle = deg_to_rad(WorldNavigation.DEFAULT_AGENT_MAX_SLOPE)
		_body.floor_snap_length = FLOOR_SNAP_LENGTH_METERS
	if _agent != null:
		_agent.path_desired_distance = AGENT_PATH_DESIRED_DISTANCE
		_agent.target_desired_distance = AGENT_TARGET_DESIRED_DISTANCE
		_agent.path_max_distance = AGENT_PATH_MAX_DISTANCE
		_agent.use_3d_avoidance = false
		_agent.radius = AVOIDANCE_RADIUS
		_agent.height = WorldNavigation.DEFAULT_AGENT_HEIGHT
		_agent.neighbor_distance = AVOIDANCE_NEIGHBOR_DISTANCE
		_agent.max_neighbors = AVOIDANCE_MAX_NEIGHBORS
		_agent.time_horizon_agents = AVOIDANCE_TIME_HORIZON_AGENTS
		_agent.time_horizon_obstacles = 0.0
		_agent.max_speed = _effective_move_speed
		_agent.avoidance_layers = 1
		_agent.avoidance_mask = 1
		_agent.avoidance_priority = AVOIDANCE_PRIORITY_IDLE
		_agent.avoidance_enabled = true
		_connect_agent_signals()
		_bind_agent_map()


func _recompute_target_speed(snap_effective: bool = false) -> void:
	var base_speed: float = _work_approach_speed if _speed_context == SpeedContext.WORK else _move_speed
	var load_mult: float = compute_load_speed_multiplier(_get_load_fill_ratio(), _max_load_speed_multiplier)
	_target_move_speed = maxf(base_speed * load_mult, 0.1)
	if snap_effective or _effective_move_speed <= 0.01:
		_effective_move_speed = _target_move_speed
	if _agent != null:
		_agent.max_speed = _effective_move_speed


func _advance_effective_speed(delta: float) -> void:
	_recompute_target_speed(false)
	if absf(_effective_move_speed - _target_move_speed) <= 0.005:
		_effective_move_speed = _target_move_speed
		return
	var alpha: float = clampf(1.0 - exp(-SPEED_TRANSITION_RATE * maxf(delta, 0.0)), 0.0, 1.0)
	_effective_move_speed = lerpf(_effective_move_speed, _target_move_speed, alpha)
	if _agent != null:
		_agent.max_speed = _effective_move_speed


func _get_load_fill_ratio() -> float:
	if _carry_load == null or _carry_load.is_empty():
		return 0.0
	var weight: int = _carry_load.get_current_weight()
	if weight <= 0:
		return 0.0
	var cap: int = _carry_load.get_effective_capacity()
	if cap <= 0 or _carry_load.is_overloaded():
		return 1.0
	return clampf(float(weight) / float(cap), 0.0, 1.0)


func _connect_carry_load_signals() -> void:
	if _carry_load == null:
		return
	if not _carry_load.load_changed.is_connected(_on_carry_load_changed):
		_carry_load.load_changed.connect(_on_carry_load_changed)
	if not _carry_load.capacity_changed.is_connected(_on_carry_load_changed):
		_carry_load.capacity_changed.connect(_on_carry_load_changed)


func _disconnect_carry_load_signals() -> void:
	if _carry_load == null:
		return
	if _carry_load.load_changed.is_connected(_on_carry_load_changed):
		_carry_load.load_changed.disconnect(_on_carry_load_changed)
	if _carry_load.capacity_changed.is_connected(_on_carry_load_changed):
		_carry_load.capacity_changed.disconnect(_on_carry_load_changed)


func _on_carry_load_changed() -> void:
	_recompute_target_speed(_move_state != MoveState.MOVING)


func _connect_agent_signals() -> void:
	if _agent != null and not _agent.velocity_computed.is_connected(_on_velocity_computed):
		_agent.velocity_computed.connect(_on_velocity_computed)


func _disconnect_agent_signals() -> void:
	if _agent != null and is_instance_valid(_agent) and _agent.velocity_computed.is_connected(_on_velocity_computed):
		_agent.velocity_computed.disconnect(_on_velocity_computed)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if _move_state != MoveState.MOVING:
		_safe_velocity = Vector3.ZERO
		_has_safe_velocity = false
		return
	if safe_velocity.is_finite():
		_safe_velocity = safe_velocity
		_has_safe_velocity = true


func _clamp_avoidance_to_navmesh(
	body_pos: Vector3,
	safe_xz: Vector2,
	desired_xz: Vector2,
	delta: float
) -> Vector2:
	if safe_xz.length_squared() < 0.001:
		return safe_xz
	if _world_navigation == null or not _world_navigation.is_navigation_ready():
		return safe_xz
	if safe_xz.distance_to(desired_xz) <= 0.15:
		return safe_xz

	var lookahead: float = maxf(delta * 8.0, 0.35)
	var probe_dir: Vector2 = safe_xz.normalized()
	var probe_pos := Vector3(body_pos.x + probe_dir.x * lookahead, body_pos.y, body_pos.z + probe_dir.y * lookahead)
	var snapped: Vector3 = _world_navigation.snap_to_navmesh(probe_pos)
	if not snapped.is_finite():
		return desired_xz

	if _distance_xz(probe_pos, snapped) <= AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_XZ and absf(snapped.y - body_pos.y) <= AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_Y:
		return safe_xz

	var inward_xz := Vector2(snapped.x - probe_pos.x, snapped.z - probe_pos.z)
	if inward_xz.length_squared() < 0.0001:
		return desired_xz

	var outward_dir: Vector2 = -inward_xz.normalized()
	var outward_proj: float = safe_xz.dot(outward_dir)
	if outward_proj > 0.0:
		var clamped_xz: Vector2 = safe_xz - outward_dir * outward_proj
		if clamped_xz.length_squared() > 0.001:
			var check_dir: Vector2 = clamped_xz.normalized()
			var check_pos := Vector3(body_pos.x + check_dir.x * lookahead, body_pos.y, body_pos.z + check_dir.y * lookahead)
			var check_snap: Vector3 = _world_navigation.snap_to_navmesh(check_pos)
			if check_snap.is_finite() and _distance_xz(check_pos, check_snap) <= AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_XZ and absf(check_snap.y - body_pos.y) <= AVOIDANCE_NAVMESH_CLAMP_TOLERANCE_Y:
				return clamped_xz

	if desired_xz.length_squared() > 0.001:
		return desired_xz.normalized() * minf(desired_xz.length(), safe_xz.length())
	return Vector2.ZERO


func _bind_agent_map() -> void:
	if _agent == null or _world_navigation == null:
		return
	var map_rid: RID = _world_navigation.get_navigation_map()
	if map_rid.is_valid():
		_agent.set_navigation_map(map_rid)


func _find_world_navigation() -> WorldNavigation:
	if not is_inside_tree():
		return null
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var found: WorldNavigation = _search_world_navigation(scene_root)
		if found != null:
			return found
	var cursor: Node = get_parent()
	while cursor != null:
		var found: WorldNavigation = _search_world_navigation(cursor)
		if found != null:
			return found
		cursor = cursor.get_parent()
	return null


func _search_world_navigation(root_node: Node) -> WorldNavigation:
	if root_node is WorldNavigation:
		return root_node as WorldNavigation
	for child: Node in root_node.get_children():
		if child is WorldNavigation:
			return child as WorldNavigation
		if child is TestMap:
			var nav: WorldNavigation = (child as TestMap).get_navigation()
			if nav != null:
				return nav
	return null


static func _distance_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
