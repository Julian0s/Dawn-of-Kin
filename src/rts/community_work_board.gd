class_name CommunityWorkBoard
extends Node
## Regional registry for community single-source and logically grouped gather tasks (wood, stone, food).
## Event-driven, zero per-frame polling, and idempotent per ResourceSource.

signal task_registered(task: WorkTask)
signal task_updated(task: WorkTask)
signal task_closed(task: WorkTask)

const SUPPORTED_RESOURCE_IDS: Array[StringName] = [&"wood", &"stone", &"food"]

var _region_id: StringName = &"default"
var _expected_world_ref: WeakRef = null
var _next_task_id: int = 1
var _next_group_id: int = 1
var _tasks: Array[WorkTask] = []
var _active_by_source_id: Dictionary = {}
var _source_callbacks: Dictionary = {}


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func _exit_tree() -> void:
	teardown()


func teardown() -> void:
	for source_id_key: Variant in _source_callbacks.keys():
		var sid: int = int(source_id_key)
		var entry: Dictionary = _source_callbacks[sid] as Dictionary
		var src_ref: WeakRef = entry.get("source_ref") as WeakRef
		var src: ResourceSource = (src_ref.get_ref() as ResourceSource) if src_ref != null else null
		_disconnect_source_entry(src, entry)
	_source_callbacks.clear()
	_active_by_source_id.clear()
	_tasks.clear()
	_expected_world_ref = null


func configure(p_region_id: StringName, p_world_3d: World3D = null) -> void:
	_region_id = p_region_id if not p_region_id.is_empty() else &"default"
	_expected_world_ref = weakref(p_world_3d) if p_world_3d != null else null


func is_source_in_region_domain(source: ResourceSource) -> bool:
	if source == null or not is_instance_valid(source) or not source.is_inside_tree():
		return false
	if _expected_world_ref != null:
		var expected_world: World3D = _expected_world_ref.get_ref() as World3D
		if expected_world != null and source.get_world_3d() != expected_world:
			return false
	var source_region: StringName = _resolve_source_region(source)
	if not source_region.is_empty() and source_region != _region_id:
		return false
	return true


static func _resolve_source_region(source: Node) -> StringName:
	var cursor: Node = source
	while cursor != null:
		if cursor.has_meta(&"region_id"):
			return StringName(cursor.get_meta(&"region_id"))
		cursor = cursor.get_parent()
	return &""


func get_region_id() -> StringName:
	return _region_id


func allocate_group_id() -> int:
	var gid: int = _next_group_id
	_next_group_id += 1
	return gid


func register_gather_group(sources: Array[ResourceSource], p_group_id: int = 0) -> Dictionary:
	var created_tasks: Array[WorkTask] = []
	var existing_tasks: Array[WorkTask] = []
	var rejected_count: int = 0
	var seen_ids: Dictionary = {}
	var expected_resource_id: StringName = &""
	var resolved_group_id: int = p_group_id

	if resolved_group_id > 0:
		expected_resource_id = get_group_resource_id(resolved_group_id)

	var valid_candidates: Array[ResourceSource] = []
	for source: ResourceSource in sources:
		if source == null or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
			rejected_count += 1
			continue
		var sid: int = source.get_instance_id()
		if seen_ids.has(sid):
			continue
		seen_ids[sid] = true

		var def: ResourceDefinition = source.get_definition()
		var res_id: StringName = source.get_resource_id()
		if def == null or not def.is_valid() or not SUPPORTED_RESOURCE_IDS.has(res_id):
			rejected_count += 1
			continue
		if source.is_depleted() or not source.is_available():
			rejected_count += 1
			continue
		if not is_source_in_region_domain(source):
			rejected_count += 1
			continue
		if expected_resource_id.is_empty():
			expected_resource_id = res_id
		elif res_id != expected_resource_id:
			rejected_count += 1
			continue
		valid_candidates.append(source)

	if valid_candidates.is_empty():
		return {
			"ok": false,
			"group_id": 0,
			"resource_id": expected_resource_id,
			"created_tasks": created_tasks,
			"existing_tasks": existing_tasks,
			"rejected_count": rejected_count,
			"reason": "no_valid_sources",
		}

	if resolved_group_id <= 0:
		resolved_group_id = allocate_group_id()

	for source: ResourceSource in valid_candidates:
		var reg: Dictionary = register_gather_task(source, resolved_group_id)
		if bool(reg.get("ok", false)):
			var task: WorkTask = reg.get("task") as WorkTask
			if task != null:
				if bool(reg.get("created", false)):
					created_tasks.append(task)
				else:
					existing_tasks.append(task)
		else:
			rejected_count += 1

	var ok: bool = not created_tasks.is_empty() or not existing_tasks.is_empty()
	return {
		"ok": ok,
		"group_id": resolved_group_id if ok else 0,
		"resource_id": expected_resource_id,
		"created_tasks": created_tasks,
		"existing_tasks": existing_tasks,
		"rejected_count": rejected_count,
		"reason": "" if ok else "no_valid_sources",
	}


func register_gather_task(source: ResourceSource, p_group_id: int = 0) -> Dictionary:
	if source == null or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
		return {"ok": false, "created": false, "task": null, "reason": "invalid_source"}
	var def: ResourceDefinition = source.get_definition()
	var res_id: StringName = source.get_resource_id()
	if def == null or not def.is_valid() or not SUPPORTED_RESOURCE_IDS.has(res_id):
		return {"ok": false, "created": false, "task": null, "reason": "unsupported_resource"}
	if source.is_depleted():
		return {"ok": false, "created": false, "task": null, "reason": "source_depleted"}
	if not source.is_available():
		return {"ok": false, "created": false, "task": null, "reason": "invalid_source"}
	if not is_source_in_region_domain(source):
		return {"ok": false, "created": false, "task": null, "reason": "region_mismatch"}

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
	task.group_id = p_group_id if p_group_id > 0 else allocate_group_id()
	task.kind = WorkTask.kind_from_resource_id(res_id)
	task.resource_id = res_id
	task.resource_definition = def
	task.region_id = _region_id
	task.source = source
	task.source_id = source.get_source_id()
	task.state = WorkTask.State.PENDING_WORKERS

	_tasks.append(task)
	_active_by_source_id[sid] = task
	_bind_source_signals(source, sid)
	task_registered.emit(task)
	return {"ok": true, "created": true, "task": task, "reason": ""}


func register_wood_gather_task(source: ResourceSource) -> Dictionary:
	if source == null or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
		return {"ok": false, "created": false, "task": null, "reason": "invalid_source"}
	if source.get_resource_id() != &"wood":
		return {"ok": false, "created": false, "task": null, "reason": "unsupported_resource"}
	return register_gather_task(source)


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


func get_tasks_in_group(group_id: int) -> Array[WorkTask]:
	var result: Array[WorkTask] = []
	if group_id <= 0:
		return result
	for task: WorkTask in _tasks:
		if task != null and task.is_active() and task.group_id == group_id:
			result.append(task)
	return result


func has_active_tasks_in_group(group_id: int) -> bool:
	if group_id <= 0:
		return false
	for task: WorkTask in _tasks:
		if task != null and task.is_active() and task.group_id == group_id:
			return true
	return false


func get_group_resource_id(group_id: int) -> StringName:
	if group_id <= 0:
		return &""
	for task: WorkTask in _tasks:
		if task != null and task.is_active() and task.group_id == group_id:
			return task.resource_id
	return &""


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


func get_blocked_tasks() -> Array[WorkTask]:
	var blocked: Array[WorkTask] = []
	for task: WorkTask in _tasks:
		if task != null and task.state == WorkTask.State.BLOCKED_REAUTHORIZATION:
			blocked.append(task)
	return blocked


func get_all_tasks() -> Array[WorkTask]:
	return _tasks.duplicate()


func get_cancellable_tasks_for_sources(
	sources: Array[ResourceSource],
	resource_id: StringName
) -> Array[WorkTask]:
	## Returns active tasks strictly matching (selected sources ∩ resource_id ∩ valid regional domain).
	## Includes PENDING_WORKERS, IN_PROGRESS, and BLOCKED_REAUTHORIZATION; never expands by group_id.
	var result: Array[WorkTask] = []
	if not SUPPORTED_RESOURCE_IDS.has(resource_id):
		return result
	var seen_source_ids: Dictionary = {}
	for src: ResourceSource in sources:
		if src == null or not is_instance_valid(src):
			continue
		var sid: int = src.get_instance_id()
		if seen_source_ids.has(sid):
			continue
		seen_source_ids[sid] = true
		if not is_source_in_region_domain(src):
			continue
		var task: WorkTask = get_active_task_for_source(src)
		if task == null or not task.is_active():
			continue
		if task.resource_id != resource_id:
			continue
		if task.region_id != _region_id:
			continue
		result.append(task)
	return result


func notify_task_updated(task: WorkTask) -> void:
	if task == null or not _tasks.has(task):
		return
	task_updated.emit(task)


func reauthorize_gather_task(task: WorkTask) -> Dictionary:
	## Explicit player reauthorization (R-03A D1-C / D0-A01) for a task in BLOCKED_REAUTHORIZATION.
	## Preserves task identity/group, clears only this task's manual worker exclusions,
	## and notifies CommunityTaskDispatcher through normal event-driven eligibility & guards.
	if task == null or not _tasks.has(task) or not task.is_active():
		return {"ok": false, "reauthorized": false, "task": null, "reason": "task_not_active"}
	if not task.is_blocked_reauthorization():
		return {"ok": false, "reauthorized": false, "task": task, "reason": "task_not_blocked"}
	if not task.is_source_usable():
		var unusable_reason: String = "source_depleted" if (task.is_source_valid() and task.source.is_depleted()) else "invalid_source"
		close_task(task, WorkTask.State.FAILED, unusable_reason)
		return {"ok": false, "reauthorized": false, "task": null, "reason": unusable_reason}
	if not is_source_in_region_domain(task.source):
		return {"ok": false, "reauthorized": false, "task": task, "reason": "region_mismatch"}

	task.excluded_unit_ids.clear()
	task.state = WorkTask.State.PENDING_WORKERS
	task.last_reason = ""
	notify_task_updated(task)
	return {"ok": true, "reauthorized": true, "task": task, "reason": ""}


func close_task(task: WorkTask, final_state: WorkTask.State, reason: String = "") -> void:
	if task == null or not task.is_active():
		return
	if final_state != WorkTask.State.COMPLETED and final_state != WorkTask.State.FAILED and final_state != WorkTask.State.CANCELLED:
		return

	var sid: int = _find_source_id_for_task(task)
	if sid != 0:
		_active_by_source_id.erase(sid)
		var safe_source: ResourceSource = task.source if is_instance_valid(task.source) else null
		_unbind_source_signals(sid, safe_source)

	task.state = final_state
	task.last_reason = reason
	task.clear_assignment()
	task_closed.emit(task)


func _bind_source_signals(source: ResourceSource, sid: int) -> void:
	if _source_callbacks.has(sid):
		return
	var on_exit: Callable = Callable(self, "_on_source_tree_exited").bind(sid)
	var on_depleted: Callable = Callable(self, "_on_source_depleted").bind(sid)
	var on_slot_released: Callable = Callable(self, "_on_source_worker_slot_released").bind(sid)
	if not source.tree_exited.is_connected(on_exit):
		source.tree_exited.connect(on_exit)
	if not source.depleted.is_connected(on_depleted):
		source.depleted.connect(on_depleted)
	if not source.worker_slot_released.is_connected(on_slot_released):
		source.worker_slot_released.connect(on_slot_released)
	_source_callbacks[sid] = {
		"source_ref": weakref(source),
		"on_exit": on_exit,
		"on_depleted": on_depleted,
		"on_slot_released": on_slot_released,
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
	var on_slot_released: Callable = entry.get("on_slot_released", Callable()) as Callable
	if on_exit.is_valid() and source.tree_exited.is_connected(on_exit):
		source.tree_exited.disconnect(on_exit)
	if on_depleted.is_valid() and source.depleted.is_connected(on_depleted):
		source.depleted.disconnect(on_depleted)
	if on_slot_released.is_valid() and source.worker_slot_released.is_connected(on_slot_released):
		source.worker_slot_released.disconnect(on_slot_released)


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
		task_updated.emit(task)


func _on_source_worker_slot_released(_source: ResourceSource, sid: int) -> void:
	if not _active_by_source_id.has(sid):
		return
	var task: WorkTask = _active_by_source_id[sid] as WorkTask
	if task == null or task.state != WorkTask.State.PENDING_WORKERS:
		return
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
