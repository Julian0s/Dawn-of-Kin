class_name D2SimulationPauseController
extends Node
## Safe, ownership-aware simulation pause authority for the D2.2 HUD.
##
## Design & Safety Guarantees (UI-1.1B):
## - Maintains an idempotent set of UI-owned pause reasons (e.g. &"hud_pause").
## - Never calls EconomyClockController.set_paused() and never alters Engine.time_scale.
##   EconomyClockController (PROCESS_MODE_PAUSABLE) automatically respects SceneTree.paused.
## - Never performs a destructive unpause on a pause it does not own:
##   1) Detects pre-existing unmanaged external SceneTree.paused == true and refuses to clear it.
##   2) Establishes an explicit cooperative lease contract on SceneTree metadata
##      (&"dok_pause_authorities") so multiple pause authorities can coexist safely.
## - Uses a zero-polling pausable child observer (NOTIFICATION_PAUSED / NOTIFICATION_UNPAUSED)
##   to stay synchronized immediately with external SceneTree.paused transitions.
## - Locks/unlocks RtsCameraRig cleanly without leaving stuck drag or pan velocity.

signal pause_state_changed(is_any_paused: bool, is_hud_paused: bool, is_externally_paused: bool)

const REASON_HUD_PAUSE: StringName = &"hud_pause"
const TREE_META_PAUSE_AUTHORITIES: StringName = &"dok_pause_authorities"


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

var _owns_tree_pause: bool = false
var _observed_unmanaged_external_pause: bool = false
var _owns_camera_lock: bool = false
var _is_applying_tree_pause: bool = false

var _last_emitted_any_paused: bool = false
var _last_emitted_hud_paused: bool = false
var _last_emitted_external_paused: bool = false
var _has_emitted_state: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_owner_id = StringName("d2_hud_pause_%d" % get_instance_id())


func _enter_tree() -> void:
	_cached_tree = get_tree()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_cached_tree = get_tree()
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
	release_all_owned_pauses()
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
	if was_empty and tree != null:
		var other_leases: bool = has_other_pause_leases(tree, _owner_id)
		if tree.paused:
			if not other_leases and not _owns_tree_pause:
				# Unmanaged external authority already paused SceneTree directly.
				_observed_unmanaged_external_pause = true
				_owns_tree_pause = false
			else:
				# Tree is paused solely by cooperative lease(s); join cooperative ownership.
				_owns_tree_pause = not _observed_unmanaged_external_pause
		else:
			_observed_unmanaged_external_pause = false
			_owns_tree_pause = true

		_reasons[reason] = true
		_add_lease_entry(tree, _owner_id)
		if not tree.paused:
			_set_tree_paused_guarded(tree, true)
	else:
		_reasons[reason] = true

	_apply_camera_lock_state()
	_emit_state_if_changed()
	return true


func release_pause(reason: StringName) -> bool:
	if reason.is_empty() or not _reasons.has(reason):
		return false
	_reasons.erase(reason)
	if _reasons.is_empty():
		_release_owned_tree_pause_if_safe()
	_apply_camera_lock_state()
	_emit_state_if_changed()
	return true


func release_all_owned_pauses() -> void:
	if _reasons.is_empty():
		var tree: SceneTree = _get_scene_tree()
		if tree != null:
			_remove_lease_entry(tree, _owner_id)
		_owns_tree_pause = false
		_apply_camera_lock_state()
		_emit_state_if_changed()
		return
	_reasons.clear()
	_release_owned_tree_pause_if_safe()
	_apply_camera_lock_state()
	_emit_state_if_changed()


func sync_external_state() -> void:
	var tree: SceneTree = _get_scene_tree()
	if tree != null:
		var other_leases: bool = has_other_pause_leases(tree, _owner_id)
		if tree.paused:
			if not _owns_tree_pause and not other_leases and _reasons.is_empty():
				_observed_unmanaged_external_pause = true
		else:
			# Tree is currently running: clear stale unmanaged external flag.
			_observed_unmanaged_external_pause = false
			if _reasons.is_empty():
				_owns_tree_pause = false
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
		if tree.paused and (_observed_unmanaged_external_pause or not _owns_tree_pause):
			return true
	return is_economy_clock_externally_paused()


func is_economy_clock_externally_paused() -> bool:
	if _economy_clock == null or not is_instance_valid(_economy_clock):
		return false
	var tp: SimulatedWorldTimeProvider = _economy_clock.get_time_provider()
	return tp != null and tp.is_paused()


func can_hud_resume_simulation() -> bool:
	if _reasons.is_empty():
		return false
	if _reasons.size() > 1 or not _reasons.has(REASON_HUD_PAUSE):
		return false
	if _observed_unmanaged_external_pause or not _owns_tree_pause:
		return false
	var tree: SceneTree = _get_scene_tree()
	if tree != null and has_other_pause_leases(tree, _owner_id):
		return false
	return true


func owns_tree_pause() -> bool:
	return _owns_tree_pause


func get_owner_id() -> StringName:
	return _owner_id


## Cooperative Pause Authority Contract:
## External subsystems that need to pause SceneTree cooperatively alongside the HUD
## should acquire and release named leases via these static methods.
static func acquire_tree_pause_lease(tree: SceneTree, owner_id: StringName) -> bool:
	if tree == null or owner_id.is_empty():
		return false
	var leases: Dictionary = _get_or_create_leases_dict(tree)
	var already_had: bool = leases.has(owner_id)
	leases[owner_id] = true
	if not tree.paused:
		tree.paused = true
	return not already_had


static func release_tree_pause_lease(tree: SceneTree, owner_id: StringName) -> bool:
	if tree == null or owner_id.is_empty():
		return false
	if not tree.has_meta(TREE_META_PAUSE_AUTHORITIES):
		return false
	var leases_val: Variant = tree.get_meta(TREE_META_PAUSE_AUTHORITIES)
	if not (leases_val is Dictionary):
		return false
	var leases: Dictionary = leases_val as Dictionary
	if not leases.has(owner_id):
		return false
	leases.erase(owner_id)
	if leases.is_empty() and tree.paused:
		tree.paused = false
	return true


static func has_other_pause_leases(tree: SceneTree, exclude_owner_id: StringName) -> bool:
	if tree == null or not tree.has_meta(TREE_META_PAUSE_AUTHORITIES):
		return false
	var leases_val: Variant = tree.get_meta(TREE_META_PAUSE_AUTHORITIES)
	if not (leases_val is Dictionary):
		return false
	var leases: Dictionary = leases_val as Dictionary
	for key: Variant in leases.keys():
		if (key as StringName) != exclude_owner_id:
			return true
	return false


static func get_active_pause_leases(tree: SceneTree) -> Array[StringName]:
	var result: Array[StringName] = []
	if tree == null or not tree.has_meta(TREE_META_PAUSE_AUTHORITIES):
		return result
	var leases_val: Variant = tree.get_meta(TREE_META_PAUSE_AUTHORITIES)
	if not (leases_val is Dictionary):
		return result
	for key: Variant in (leases_val as Dictionary).keys():
		result.append(key as StringName)
	return result


static func _get_or_create_leases_dict(tree: SceneTree) -> Dictionary:
	if tree.has_meta(TREE_META_PAUSE_AUTHORITIES):
		var existing: Variant = tree.get_meta(TREE_META_PAUSE_AUTHORITIES)
		if existing is Dictionary:
			return existing as Dictionary
	var created: Dictionary = {}
	tree.set_meta(TREE_META_PAUSE_AUTHORITIES, created)
	return created


static func _add_lease_entry(tree: SceneTree, owner_id: StringName) -> void:
	var leases: Dictionary = _get_or_create_leases_dict(tree)
	leases[owner_id] = true


static func _remove_lease_entry(tree: SceneTree, owner_id: StringName) -> void:
	if not tree.has_meta(TREE_META_PAUSE_AUTHORITIES):
		return
	var leases_val: Variant = tree.get_meta(TREE_META_PAUSE_AUTHORITIES)
	if leases_val is Dictionary:
		(leases_val as Dictionary).erase(owner_id)


func _release_owned_tree_pause_if_safe() -> void:
	var tree: SceneTree = _get_scene_tree()
	if tree == null:
		_owns_tree_pause = false
		return
	_remove_lease_entry(tree, _owner_id)
	var other_leases: bool = has_other_pause_leases(tree, _owner_id)
	var can_unpause: bool = (
		_owns_tree_pause
		and not _observed_unmanaged_external_pause
		and not other_leases
	)
	_owns_tree_pause = false
	if can_unpause and tree.paused:
		_set_tree_paused_guarded(tree, false)


func _set_tree_paused_guarded(tree: SceneTree, paused: bool) -> void:
	_is_applying_tree_pause = true
	tree.paused = paused
	_is_applying_tree_pause = false


func _on_tree_pause_notification(tree_is_now_paused: bool) -> void:
	if _is_applying_tree_pause:
		return
	var tree: SceneTree = _get_scene_tree()
	if tree_is_now_paused:
		var other_leases: bool = tree != null and has_other_pause_leases(tree, _owner_id)
		if not _owns_tree_pause and not other_leases:
			_observed_unmanaged_external_pause = true
	else:
		_observed_unmanaged_external_pause = false
		if _reasons.is_empty():
			_owns_tree_pause = false
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
	if _has_emitted_state \
		and any_p == _last_emitted_any_paused \
		and hud_p == _last_emitted_hud_paused \
		and ext_p == _last_emitted_external_paused:
		return
	_has_emitted_state = true
	_last_emitted_any_paused = any_p
	_last_emitted_hud_paused = hud_p
	_last_emitted_external_paused = ext_p
	pause_state_changed.emit(any_p, hud_p, ext_p)
