class_name D2SimulationPauseController
extends Node
## Safe, ownership-aware simulation pause authority for the D2.2 HUD.
##
## Design & Safety Guarantees (UI-1.1B + UI-1.1B R1):
## - Maintains an idempotent set of UI-owned pause reasons (e.g. &"hud_pause").
## - Never calls EconomyClockController.set_paused() and never alters Engine.time_scale.
##   EconomyClockController (PROCESS_MODE_PAUSABLE) automatically respects SceneTree.paused.
## - Single tree-scoped cooperative pause authority record on SceneTree metadata
##   (&"dok_pause_authorities") tracking:
##   1) active cooperative leases,
##   2) whether the cooperative registry actually owns the false -> true transition,
##   3) whether an unmanaged external pause was observed before cooperative acquisition,
##   4) event-driven WeakRef listeners (zero polling) so HUD controls update synchronously
##      even when SceneTree.paused stays true across lease transitions.
## - Conservative safety rule: NEVER executes tree.paused = false unless ALL cooperative
##   leases are released AND the cooperative registry owns the pause AND no unmanaged
##   external pause was observed.
## - Locks/unlocks RtsCameraRig cleanly without leaving stuck drag or pan velocity.

signal pause_state_changed(is_any_paused: bool, is_hud_paused: bool, is_externally_paused: bool)

const REASON_HUD_PAUSE: StringName = &"hud_pause"
const TREE_META_PAUSE_AUTHORITIES: StringName = &"dok_pause_authorities"

const _KEY_LEASES: StringName = &"leases"
const _KEY_COOP_OWNS_PAUSE: StringName = &"cooperative_owns_pause"
const _KEY_UNMANAGED_EXTERNAL: StringName = &"unmanaged_external_observed"
const _KEY_LISTENERS: StringName = &"listeners"


class _TreePauseObserver:
	extends Node
	var _owner_controller: WeakRef = null

	func _init(owner_controller: D2SimulationPauseController) -> void:
		name = "TreePauseObserver"
		process_mode = Node.PROCESS_MODE_PAUSABLE
		set_process(false)
		set_physics_process(false)
		_owner_controller = weakref(owner_controller)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
			var ctrl: D2SimulationPauseController = _owner_controller.get_ref() as D2SimulationPauseController
			if ctrl != null and is_instance_valid(ctrl):
				ctrl._on_tree_pause_notification(what == NOTIFICATION_PAUSED)


var _owner_id: StringName = &""
var _reasons: Dictionary = {}
var _camera_rig: RtsCameraRig = null
var _economy_clock: EconomyClockController = null
var _observer: _TreePauseObserver = null
var _cached_tree: SceneTree = null

var _owns_camera_lock: bool = false

var _last_emitted_any_paused: bool = false
var _last_emitted_hud_paused: bool = false
var _last_emitted_external_paused: bool = false
var _last_emitted_can_resume: bool = false
var _has_emitted_state: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_owner_id = StringName("d2_hud_pause_%d" % get_instance_id())


func _enter_tree() -> void:
	_cached_tree = get_tree()
	if _cached_tree != null:
		_register_listener(_cached_tree, self)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_cached_tree = get_tree()
	if _cached_tree != null:
		_register_listener(_cached_tree, self)
	if _observer == null:
		_observer = _TreePauseObserver.new(self)
		add_child(_observer)
	sync_external_state()


func _exit_tree() -> void:
	unbind()


func _get_scene_tree() -> SceneTree:
	if is_inside_tree():
		_cached_tree = get_tree()
		return _cached_tree
	return _cached_tree


func configure(
	camera_rig: RtsCameraRig = null,
	economy_clock: EconomyClockController = null
) -> void:
	if _camera_rig != null and _camera_rig != camera_rig and _owns_camera_lock:
		if is_instance_valid(_camera_rig):
			_camera_rig.set_input_locked(false)
		_owns_camera_lock = false
	_camera_rig = camera_rig
	_economy_clock = economy_clock
	sync_external_state()


func unbind() -> void:
	var tree: SceneTree = _get_scene_tree()
	release_all_owned_pauses()
	if tree != null:
		_unregister_listener(tree, self)
	if _owns_camera_lock:
		if _camera_rig != null and is_instance_valid(_camera_rig):
			_camera_rig.set_input_locked(false)
		_owns_camera_lock = false
	_camera_rig = null
	_economy_clock = null
	if not is_inside_tree():
		_cached_tree = null


func request_pause(reason: StringName) -> bool:
	if reason.is_empty():
		return false
	if _reasons.has(reason):
		_apply_camera_lock_state()
		_emit_state_if_changed()
		return false

	var tree: SceneTree = _get_scene_tree()
	var was_empty: bool = _reasons.is_empty()
	_reasons[reason] = true
	if was_empty and tree != null:
		acquire_tree_pause_lease(tree, _owner_id)

	_apply_camera_lock_state()
	_emit_state_if_changed()
	return true


func release_pause(reason: StringName) -> bool:
	if reason.is_empty() or not _reasons.has(reason):
		return false
	_reasons.erase(reason)
	if _reasons.is_empty():
		var tree: SceneTree = _get_scene_tree()
		if tree != null:
			release_tree_pause_lease(tree, _owner_id)
	_apply_camera_lock_state()
	_emit_state_if_changed()
	return true


func release_all_owned_pauses() -> void:
	_reasons.clear()
	var tree: SceneTree = _get_scene_tree()
	if tree != null:
		release_tree_pause_lease(tree, _owner_id)
	_apply_camera_lock_state()
	_emit_state_if_changed()


func sync_external_state() -> void:
	var tree: SceneTree = _get_scene_tree()
	if tree != null:
		var state: Dictionary = _get_or_create_tree_state(tree)
		var leases: Dictionary = state[_KEY_LEASES] as Dictionary
		if tree.paused:
			if leases.is_empty() and not bool(state[_KEY_COOP_OWNS_PAUSE]):
				state[_KEY_UNMANAGED_EXTERNAL] = true
		else:
			state[_KEY_UNMANAGED_EXTERNAL] = false
			if leases.is_empty():
				state[_KEY_COOP_OWNS_PAUSE] = false
	_apply_camera_lock_state()
	_emit_state_if_changed()


func is_paused() -> bool:
	var tree: SceneTree = _get_scene_tree()
	if tree != null and tree.paused:
		return true
	return not _reasons.is_empty()


func is_hud_paused() -> bool:
	return not _reasons.is_empty()


func has_reason(reason: StringName) -> bool:
	return _reasons.has(reason)


func get_active_reasons() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _reasons.keys():
		out.append(key as StringName)
	return out


func is_externally_paused() -> bool:
	var tree: SceneTree = _get_scene_tree()
	if tree != null:
		if has_other_pause_leases(tree, _owner_id):
			return true
		if tree.paused:
			var state: Dictionary = _get_existing_tree_state(tree)
			if state.is_empty():
				return true
			if bool(state[_KEY_UNMANAGED_EXTERNAL]) or not bool(state[_KEY_COOP_OWNS_PAUSE]):
				return true
	return is_economy_clock_externally_paused()


func is_economy_clock_externally_paused() -> bool:
	if _economy_clock == null or not is_instance_valid(_economy_clock):
		return false
	var tp: SimulatedWorldTimeProvider = _economy_clock.get_time_provider()
	return tp != null and tp.is_paused()


func can_hud_resume_simulation() -> bool:
	if _reasons.size() != 1 or not _reasons.has(REASON_HUD_PAUSE):
		return false
	if not owns_tree_pause():
		return false
	if is_externally_paused():
		return false
	return true


func owns_tree_pause() -> bool:
	if _reasons.is_empty():
		return false
	var tree: SceneTree = _get_scene_tree()
	if tree == null:
		return false
	var state: Dictionary = _get_existing_tree_state(tree)
	if state.is_empty():
		return false
	var leases: Dictionary = state[_KEY_LEASES] as Dictionary
	return (
		leases.has(_owner_id)
		and bool(state[_KEY_COOP_OWNS_PAUSE])
		and not bool(state[_KEY_UNMANAGED_EXTERNAL])
	)


func get_owner_id() -> StringName:
	return _owner_id


## Cooperative Pause Authority Contract:
## External subsystems that need to pause SceneTree cooperatively alongside the HUD
## acquire and release named leases via these static methods.
## Conservative ownership rule: if SceneTree.paused was already true with no active
## cooperative owner prior to acquisition, the registry marks an unmanaged external
## pause and refuses to unpause SceneTree when all cooperative leases are released.
static func acquire_tree_pause_lease(tree: SceneTree, owner_id: StringName) -> bool:
	if tree == null or owner_id.is_empty():
		return false
	var state: Dictionary = _get_or_create_tree_state(tree)
	var leases: Dictionary = state[_KEY_LEASES] as Dictionary
	if leases.has(owner_id):
		return false

	if not tree.paused:
		state[_KEY_UNMANAGED_EXTERNAL] = false
		state[_KEY_COOP_OWNS_PAUSE] = true
	elif leases.is_empty() or not bool(state[_KEY_COOP_OWNS_PAUSE]):
		state[_KEY_UNMANAGED_EXTERNAL] = true
		state[_KEY_COOP_OWNS_PAUSE] = false

	leases[owner_id] = true
	if not tree.paused:
		tree.paused = true
	_notify_tree_listeners(tree)
	return true


static func release_tree_pause_lease(tree: SceneTree, owner_id: StringName) -> bool:
	if tree == null or owner_id.is_empty():
		return false
	var state: Dictionary = _get_existing_tree_state(tree)
	if state.is_empty():
		return false
	var leases: Dictionary = state[_KEY_LEASES] as Dictionary
	if not leases.has(owner_id):
		return false

	leases.erase(owner_id)
	if leases.is_empty():
		var can_unpause: bool = (
			bool(state[_KEY_COOP_OWNS_PAUSE])
			and not bool(state[_KEY_UNMANAGED_EXTERNAL])
		)
		state[_KEY_COOP_OWNS_PAUSE] = false
		if can_unpause and tree.paused:
			tree.paused = false
		elif not tree.paused:
			state[_KEY_UNMANAGED_EXTERNAL] = false
	_notify_tree_listeners(tree)
	return true


static func has_other_pause_leases(tree: SceneTree, exclude_owner_id: StringName) -> bool:
	var state: Dictionary = _get_existing_tree_state(tree)
	if state.is_empty():
		return false
	var leases: Dictionary = state[_KEY_LEASES] as Dictionary
	for key: Variant in leases.keys():
		if (key as StringName) != exclude_owner_id:
			return true
	return false


static func get_active_pause_leases(tree: SceneTree) -> Array[StringName]:
	var result: Array[StringName] = []
	var state: Dictionary = _get_existing_tree_state(tree)
	if state.is_empty():
		return result
	var leases: Dictionary = state[_KEY_LEASES] as Dictionary
	for key: Variant in leases.keys():
		result.append(key as StringName)
	return result


static func _get_existing_tree_state(tree: SceneTree) -> Dictionary:
	if tree == null or not tree.has_meta(TREE_META_PAUSE_AUTHORITIES):
		return {}
	var existing: Variant = tree.get_meta(TREE_META_PAUSE_AUTHORITIES)
	if existing is Dictionary:
		var d: Dictionary = existing as Dictionary
		if d.has(_KEY_LEASES) and d[_KEY_LEASES] is Dictionary:
			return d
	return {}


static func _get_or_create_tree_state(tree: SceneTree) -> Dictionary:
	var existing: Dictionary = _get_existing_tree_state(tree)
	if not existing.is_empty():
		return existing
	var created: Dictionary = {
		_KEY_LEASES: {},
		_KEY_COOP_OWNS_PAUSE: false,
		_KEY_UNMANAGED_EXTERNAL: false,
		_KEY_LISTENERS: [],
	}
	tree.set_meta(TREE_META_PAUSE_AUTHORITIES, created)
	return created


static func _register_listener(tree: SceneTree, controller: D2SimulationPauseController) -> void:
	var state: Dictionary = _get_or_create_tree_state(tree)
	var listeners: Array = state[_KEY_LISTENERS] as Array
	for i: int in range(listeners.size() - 1, -1, -1):
		var wr: WeakRef = listeners[i] as WeakRef
		var obj: Object = wr.get_ref() if wr != null else null
		if obj == null or not is_instance_valid(obj):
			listeners.remove_at(i)
		elif obj == controller:
			return
	listeners.append(weakref(controller))


static func _unregister_listener(tree: SceneTree, controller: D2SimulationPauseController) -> void:
	var state: Dictionary = _get_existing_tree_state(tree)
	if state.is_empty():
		return
	var listeners: Array = state[_KEY_LISTENERS] as Array
	for i: int in range(listeners.size() - 1, -1, -1):
		var wr: WeakRef = listeners[i] as WeakRef
		var obj: Object = wr.get_ref() if wr != null else null
		if obj == null or not is_instance_valid(obj) or obj == controller:
			listeners.remove_at(i)


static func _notify_tree_listeners(tree: SceneTree) -> void:
	var state: Dictionary = _get_existing_tree_state(tree)
	if state.is_empty():
		return
	var listeners: Array = state[_KEY_LISTENERS] as Array
	var snapshot: Array = listeners.duplicate()
	var had_dead: bool = false
	for item: Variant in snapshot:
		var wr: WeakRef = item as WeakRef
		var ctrl: D2SimulationPauseController = (wr.get_ref() as D2SimulationPauseController) if wr != null else null
		if ctrl != null and is_instance_valid(ctrl):
			ctrl._on_cooperative_leases_changed()
		else:
			had_dead = true
	if had_dead:
		for i: int in range(listeners.size() - 1, -1, -1):
			var wr: WeakRef = listeners[i] as WeakRef
			var obj: Object = wr.get_ref() if wr != null else null
			if obj == null or not is_instance_valid(obj):
				listeners.remove_at(i)


func _on_cooperative_leases_changed() -> void:
	_apply_camera_lock_state()
	_emit_state_if_changed()


func _on_tree_pause_notification(tree_is_now_paused: bool) -> void:
	var tree: SceneTree = _get_scene_tree()
	if tree != null:
		var state: Dictionary = _get_or_create_tree_state(tree)
		var leases: Dictionary = state[_KEY_LEASES] as Dictionary
		if tree_is_now_paused:
			if leases.is_empty() and not bool(state[_KEY_COOP_OWNS_PAUSE]):
				state[_KEY_UNMANAGED_EXTERNAL] = true
		else:
			state[_KEY_UNMANAGED_EXTERNAL] = false
			if leases.is_empty():
				state[_KEY_COOP_OWNS_PAUSE] = false
	_apply_camera_lock_state()
	_emit_state_if_changed()


func _apply_camera_lock_state() -> void:
	if _camera_rig == null or not is_instance_valid(_camera_rig):
		_owns_camera_lock = false
		return
	var should_lock: bool = is_paused()
	if should_lock:
		_camera_rig.set_input_locked(true)
		_owns_camera_lock = true
	elif _owns_camera_lock:
		_camera_rig.set_input_locked(false)
		_owns_camera_lock = false


func _emit_state_if_changed() -> void:
	var any_p: bool = is_paused()
	var hud_p: bool = is_hud_paused()
	var ext_p: bool = is_externally_paused()
	var can_res: bool = can_hud_resume_simulation()
	if _has_emitted_state \
		and any_p == _last_emitted_any_paused \
		and hud_p == _last_emitted_hud_paused \
		and ext_p == _last_emitted_external_paused \
		and can_res == _last_emitted_can_resume:
		return
	_has_emitted_state = true
	_last_emitted_any_paused = any_p
	_last_emitted_hud_paused = hud_p
	_last_emitted_external_paused = ext_p
	_last_emitted_can_resume = can_res
	pause_state_changed.emit(any_p, hud_p, ext_p)
