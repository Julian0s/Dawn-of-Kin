class_name CommunityWorkBoard
extends Node
## Minimal RUX-1 regional registry for community wood-gather tasks.
## Event-driven, zero per-frame polling, and idempotent per ResourceSource.

signal task_registered(task: WorkTask)
signal task_updated(task: WorkTask)
signal task_closed(task: WorkTask)

var _region_id: StringName = &"default"
var _next_task_id: int = 1
var _tasks: Array[WorkTask] = []
var _active_by_source_id: Dictionary = {}
var _source_callbacks: Dictionary = {}


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func _exit_tree() -> void:
	for source_id_key: Variant in _source_callbacks.keys():
		var sid: int = int(source_id_key)
		var entry: Dictionary = _source_callbacks[sid] as Dictionary
		var src_ref: WeakRef = entry.get("source_ref") as WeakRef
		var src: ResourceSource = (src_ref.get_ref() as ResourceSource) if src_ref != null else null
		_disconnect_source_entry(src, entry)
	_source_callbacks.clear()
	_active_by_source_id.clear()
	_tasks.clear()


func configure(p_region_id: StringName) -> void:
	_region_id = p_region_id if not p_region_id.is_empty() else &"default"


func get_region_id() -> StringName:
	return _region_id


func register_wood_gather_task(source: ResourceSource) -> Dictionary:
	if source == null or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
		return {"ok": false, "created": false, "task": null, "reason": "invalid_source"}
	if source.get_resource_id() != &"wood":
		return {"ok": false, "created": false, "task": null, "reason": "unsupported_resource"}
	if source.is_depleted():
		return {"ok": false, "created": false, "task": null, "reason": "source_depleted"}
	if not source.is_available():
		return {"ok": false, "created": false, "task": null, "reason": "invalid_source"}

	var sid: int = source.get_instance_id()
	if _active_by_source_id.has(sid):
		var existing: WorkTask = _active_by_source_id[sid] as WorkTask
		if existing != null and existing.is_active():
			return {"ok": true, "created": false, "task": existing, "reason": "already_registered"}
		_active_by_source_id.erase(sid)

	var task := WorkTask.new()
	task.task_id = _next_task_id
	task.created_seq = _next_task_id
	_next_task_id += 1
	task.kind = WorkTask.Kind.GATHER_WOOD
	task.region_id = _region_id
	task.source = source
	task.source_id = source.get_source_id()
	task.state = WorkTask.State.PENDING_WORKERS

	_tasks.append(task)
	_active_by_source_id[sid] = task
	_bind_source_signals(source, sid)
	task_registered.emit(task)
	return {"ok": true, "created": true, "task": task, "reason": ""}


func get_active_task_for_source(source: ResourceSource) -> WorkTask:
	if source == null or not is_instance_valid(source):
		return null
	var sid: int = source.get_instance_id()
	if not _active_by_source_id.has(sid):
		return null
	var task: WorkTask = _active_by_source_id[sid] as WorkTask
	if task == null or not task.is_active():
		_active_by_source_id.erase(sid)
		return null
	return task


func get_active_tasks() -> Array[WorkTask]:
	var active: Array[WorkTask] = []
	for task: WorkTask in _tasks:
		if task != null and task.is_active():
			active.append(task)
	return active


func get_pending_tasks() -> Array[WorkTask]:
	var pending: Array[WorkTask] = []
	for task: WorkTask in _tasks:
		if task != null and task.state == WorkTask.State.PENDING_WORKERS:
			pending.append(task)
	return pending


func get_all_tasks() -> Array[WorkTask]:
	return _tasks.duplicate()


func notify_task_updated(task: WorkTask) -> void:
	if task == null or not _tasks.has(task):
		return
	task_updated.emit(task)


func close_task(task: WorkTask, final_state: WorkTask.State, reason: String = "") -> void:
	if task == null or not task.is_active():
		return
	if final_state != WorkTask.State.COMPLETED and final_state != WorkTask.State.FAILED and final_state != WorkTask.State.CANCELLED:
		return

	var sid: int = _find_source_id_for_task(task)
	if sid != 0:
		_active_by_source_id.erase(sid)
		_unbind_source_signals(sid, task.source)

	task.state = final_state
	task.last_reason = reason
	task.clear_assignment()
	task_closed.emit(task)


func _bind_source_signals(source: ResourceSource, sid: int) -> void:
	if _source_callbacks.has(sid):
		return
	var on_exit: Callable = Callable(self, "_on_source_tree_exited").bind(sid)
	var on_depleted: Callable = Callable(self, "_on_source_depleted").bind(sid)
	if not source.tree_exited.is_connected(on_exit):
		source.tree_exited.connect(on_exit)
	if not source.depleted.is_connected(on_depleted):
		source.depleted.connect(on_depleted)
	_source_callbacks[sid] = {
		"source_ref": weakref(source),
		"on_exit": on_exit,
		"on_depleted": on_depleted,
	}


func _unbind_source_signals(sid: int, source: ResourceSource) -> void:
	if not _source_callbacks.has(sid):
		return
	var entry: Dictionary = _source_callbacks[sid] as Dictionary
	_source_callbacks.erase(sid)
	var resolved_source: ResourceSource = source
	if resolved_source == null or not is_instance_valid(resolved_source):
		var src_ref: WeakRef = entry.get("source_ref") as WeakRef
		resolved_source = (src_ref.get_ref() as ResourceSource) if src_ref != null else null
	_disconnect_source_entry(resolved_source, entry)


func _disconnect_source_entry(source: ResourceSource, entry: Dictionary) -> void:
	if source == null or not is_instance_valid(source):
		return
	var on_exit: Callable = entry.get("on_exit", Callable()) as Callable
	var on_depleted: Callable = entry.get("on_depleted", Callable()) as Callable
	if on_exit.is_valid() and source.tree_exited.is_connected(on_exit):
		source.tree_exited.disconnect(on_exit)
	if on_depleted.is_valid() and source.depleted.is_connected(on_depleted):
		source.depleted.disconnect(on_depleted)


func _on_source_tree_exited(sid: int) -> void:
	if not _active_by_source_id.has(sid):
		_unbind_source_signals(sid, null)
		return
	var task: WorkTask = _active_by_source_id[sid] as WorkTask
	if task == null or not task.is_active():
		_active_by_source_id.erase(sid)
		_unbind_source_signals(sid, null)
		return
	if not task.has_assigned_worker():
		close_task(task, WorkTask.State.FAILED, "invalid_source")
	else:
		# Let the active GatherResourceOrder deliver any carried wood or finish cleanly.
		task_updated.emit(task)


func _on_source_depleted(_source: ResourceSource, sid: int) -> void:
	if not _active_by_source_id.has(sid):
		return
	var task: WorkTask = _active_by_source_id[sid] as WorkTask
	if task == null or not task.is_active():
		_active_by_source_id.erase(sid)
		return
	if not task.has_assigned_worker():
		close_task(task, WorkTask.State.FAILED, "source_depleted")
	else:
		# Active worker finishes physical delivery before task reaches COMPLETED.
		task_updated.emit(task)


func _find_source_id_for_task(task: WorkTask) -> int:
	if task.source != null and is_instance_valid(task.source):
		var direct_sid: int = task.source.get_instance_id()
		if _active_by_source_id.get(direct_sid) == task:
			return direct_sid
	for key: Variant in _active_by_source_id.keys():
		var sid: int = int(key)
		if _active_by_source_id[sid] == task:
			return sid
	return 0
