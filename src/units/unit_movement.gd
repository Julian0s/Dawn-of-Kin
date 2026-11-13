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

const ARRIVAL_TOLERANCE_XZ: float = 0.25
const ARRIVAL_TOLERANCE_Y: float = 1.0
const WAYPOINT_ARRIVAL_XZ: float = 0.20
const AGENT_PATH_DESIRED_DISTANCE: float = 0.85
const AGENT_TARGET_DESIRED_DISTANCE: float = 0.85
const AGENT_PATH_MAX_DISTANCE: float = 2.0
const FLOOR_SNAP_LENGTH_METERS: float = 0.3
const MAX_TERRAIN_STEP_UP_HEIGHT: float = 0.42
const STEP_UP_FORWARD_PROBE: float = 0.14
const STUCK_WINDOW_SEC: float = 1.5
const STUCK_MIN_PROGRESS_XZ: float = 0.25
const MAX_REPATH_ATTEMPTS: int = 1

@export var navigation_agent_path: NodePath = ^"../NavigationAgent3D"

var _body: CharacterBody3D = null
var _agent: NavigationAgent3D = null
var _world_navigation: WorldNavigation = null

var _move_speed: float = 4.8
var _turn_rate: float = 10.0
var _gravity: float = 9.8

var _move_state: MoveState = MoveState.IDLE
var _target_position: Vector3 = Vector3.ZERO
var _active_path: PackedVector3Array = PackedVector3Array()
var _active_path_index: int = 0
var _progress_anchor_xz: Vector2 = Vector2.ZERO
var _no_progress_timer: float = 0.0
var _repath_attempts: int = 0


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_resolve_nodes()
	_configure_body_and_agent()


func configure(body: CharacterBody3D, agent: NavigationAgent3D = null) -> void:
	_body = body
	if agent != null:
		_agent = agent
	elif _agent == null:
		_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D
	_configure_body_and_agent()


func set_world_navigation(world_nav: WorldNavigation) -> void:
	_world_navigation = world_nav
	_bind_agent_map()


func get_world_navigation() -> WorldNavigation:
	return _world_navigation


func set_motion_profile(move_speed: float, turn_rate: float) -> void:
	_move_speed = maxf(move_speed, 0.1)
	_turn_rate = maxf(turn_rate, 0.1)


func get_move_state() -> MoveState:
	return _move_state


func get_target_position() -> Vector3:
	return _target_position


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
	_target_position = target
	_repath_attempts = 0
	_no_progress_timer = 0.0
	_progress_anchor_xz = Vector2(_body.global_position.x, _body.global_position.z)

	if is_at_target(_target_position):
		_move_state = MoveState.ARRIVED
		return true

	_agent.target_position = _target_position
	_agent.get_next_path_position()
	_refresh_active_path()
	_move_state = MoveState.MOVING
	return true


func stop_movement() -> void:
	_move_state = MoveState.IDLE
	_no_progress_timer = 0.0
	_repath_attempts = 0
	_active_path = PackedVector3Array()
	_active_path_index = 0
	if _body != null:
		_body.velocity.x = 0.0
		_body.velocity.z = 0.0
	if _agent != null and _body != null:
		_agent.target_position = _body.global_position


func step_movement(delta: float) -> void:
	_resolve_nodes()
	if _body == null:
		return

	var vel: Vector3 = _body.velocity
	if not _body.is_on_floor():
		vel.y -= _gravity * delta
	elif vel.y < 0.0:
		vel.y = 0.0

	if _move_state != MoveState.MOVING:
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

	var steer_point: Vector3 = _resolve_steer_point()
	var body_pos: Vector3 = _body.global_position
	var delta_xz: Vector2 = Vector2(steer_point.x - body_pos.x, steer_point.z - body_pos.z)
	var dist_xz: float = delta_xz.length()

	if dist_xz > 0.001:
		var dir_xz: Vector2 = delta_xz / dist_xz
		var step_speed: float = _move_speed
		var on_final_segment: bool = _active_path.is_empty() or _active_path_index >= _active_path.size() - 1
		if on_final_segment and delta > 0.0:
			var dist_to_final_xz: float = _distance_xz(body_pos, _target_position)
			step_speed = minf(_move_speed, dist_to_final_xz / delta)
		vel.x = dir_xz.x * step_speed
		vel.z = dir_xz.y * step_speed

		var target_yaw: float = atan2(-dir_xz.x, -dir_xz.y)
		var rot_alpha: float = 1.0 - exp(-_turn_rate * delta)
		_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, rot_alpha)
	else:
		vel.x = 0.0
		vel.z = 0.0

	var pre_move_xz: Vector2 = Vector2(_body.global_position.x, _body.global_position.z)
	_body.velocity = vel
	_body.move_and_slide()

	if dist_xz > 0.001:
		var post_move_xz: Vector2 = Vector2(_body.global_position.x, _body.global_position.z)
		var expected_xz: float = Vector2(vel.x, vel.z).length() * delta
		if expected_xz > 0.01 and post_move_xz.distance_to(pre_move_xz) < expected_xz * 0.35:
			_try_terrain_step_up(Vector2(vel.x, vel.z).normalized(), expected_xz)

	if is_at_target(_target_position):
		_finish_arrival(_body.velocity)
		return

	_update_stuck_detection(delta)


func _finish_arrival(current_vel: Vector3) -> void:
	_move_state = MoveState.ARRIVED
	_no_progress_timer = 0.0
	_body.velocity = Vector3(0.0, current_vel.y, 0.0)


func _resolve_steer_point() -> Vector3:
	if _active_path.is_empty():
		_agent.get_next_path_position()
		_refresh_active_path()

	var body_pos: Vector3 = _body.global_position
	while _active_path_index < _active_path.size() - 1:
		var wp: Vector3 = _active_path[_active_path_index]
		var same_vertical_band: bool = absf(body_pos.y - wp.y) <= ARRIVAL_TOLERANCE_Y
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
			if absf(body_pos.y - wp.y) <= ARRIVAL_TOLERANCE_Y and _distance_xz(body_pos, wp) <= WAYPOINT_ARRIVAL_XZ:
				_active_path_index += 1
			else:
				break


func _update_stuck_detection(delta: float) -> void:
	var current_xz: Vector2 = Vector2(_body.global_position.x, _body.global_position.z)
	if current_xz.distance_to(_progress_anchor_xz) >= STUCK_MIN_PROGRESS_XZ:
		_progress_anchor_xz = current_xz
		_no_progress_timer = 0.0
		return

	_no_progress_timer += delta
	if _no_progress_timer < STUCK_WINDOW_SEC:
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
		if repath_result.status == WorldNavigation.QueryStatus.OK or (
			repath_result.status == WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE
			and not repath_result.path.is_empty()
		):
			_target_position = repath_result.resolved_target

	_agent.target_position = _target_position
	_agent.get_next_path_position()
	_refresh_active_path()


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
		_world_navigation = _find_world_navigation()


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
		_agent.radius = WorldNavigation.DEFAULT_AGENT_RADIUS
		_agent.height = WorldNavigation.DEFAULT_AGENT_HEIGHT
		_agent.avoidance_enabled = false
		_bind_agent_map()


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
