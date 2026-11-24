class_name SourceSelectionModel
extends RefCounted
## Pure visual selection model for natural ResourceSource nodes (R-03A D1).
## Holds selection intent completely decoupled from CommunityWorkBoard tasks,
## worker orders, carry loads, reservations, or economic state.
## Uses WeakRef + tree_exited/depleted signals so it never leaks sources or polls per frame.

signal selection_changed()

var _selected_order: Array[int] = []
var _selected_refs: Dictionary = {}
var _source_callbacks: Dictionary = {}
var _region_checker: Callable = Callable()
var _supported_resource_ids: PackedStringArray = PackedStringArray(["wood", "stone", "food"])


func configure(
	p_region_checker: Callable = Callable(),
	p_supported_resource_ids: PackedStringArray = PackedStringArray(["wood", "stone", "food"])
) -> void:
	_region_checker = p_region_checker
	_supported_resource_ids = p_supported_resource_ids.duplicate()
	if _prune_invalid_sources():
		selection_changed.emit()


func teardown() -> void:
	var had_items: bool = not _selected_order.is_empty()
	_disconnect_all_sources()
	_selected_order.clear()
	_selected_refs.clear()
	_region_checker = Callable()
	if had_items:
		selection_changed.emit()


func is_source_eligible(source: ResourceSource) -> bool:
	if source == null or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
		return false
	if source.is_depleted() or not source.is_available():
		return false
	var def: ResourceDefinition = source.get_definition()
	if def == null or not def.is_valid():
		return false
	var res_id: StringName = source.get_resource_id()
	if not _supported_resource_ids.has(String(res_id)):
		return false
	if _region_checker.is_valid() and not bool(_region_checker.call(source)):
		return false
	return true


func is_selected(source: ResourceSource) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var sid: int = source.get_instance_id()
	if not _selected_refs.has(sid):
		return false
	var resolved: ResourceSource = _resolve_ref(sid)
	return resolved == source and is_source_eligible(resolved)


func select_single(source: ResourceSource) -> bool:
	if not is_source_eligible(source):
		return false
	var sid: int = source.get_instance_id()
	if _selected_order.size() == 1 and _selected_order[0] == sid and is_selected(source):
		return false
	_disconnect_all_sources()
	_selected_order.clear()
	_selected_refs.clear()
	_insert_source(source)
	selection_changed.emit()
	return true


func deselect_source(source: ResourceSource) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var sid: int = source.get_instance_id()
	if not _selected_refs.has(sid):
		return false
	_remove_source_id(sid, source)
	selection_changed.emit()
	return true


func toggle_source(source: ResourceSource) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var sid: int = source.get_instance_id()
	if _selected_refs.has(sid):
		_remove_source_id(sid, source)
		selection_changed.emit()
		return false
	if not is_source_eligible(source):
		return false
	_insert_source(source)
	selection_changed.emit()
	return true


func add_sources(sources: Array[ResourceSource]) -> int:
	var changed: bool = _prune_invalid_sources()
	var added_count: int = 0
	for source: ResourceSource in sources:
		if not is_source_eligible(source):
			continue
		var sid: int = source.get_instance_id()
		if _selected_refs.has(sid):
			continue
		_insert_source(source)
		added_count += 1
		changed = true
	if changed:
		selection_changed.emit()
	return added_count


func clear() -> void:
	if _selected_order.is_empty() and _selected_refs.is_empty():
		return
	_disconnect_all_sources()
	_selected_order.clear()
	_selected_refs.clear()
	selection_changed.emit()


func get_selected_sources() -> Array[ResourceSource]:
	if _prune_invalid_sources():
		selection_changed.emit()
	var result: Array[ResourceSource] = []
	for sid: int in _selected_order:
		var src: ResourceSource = _resolve_ref(sid)
		if src != null:
			result.append(src)
	return result


func get_selected_by_resource(resource_id: StringName) -> Array[ResourceSource]:
	var result: Array[ResourceSource] = []
	for src: ResourceSource in get_selected_sources():
		if src.get_resource_id() == resource_id:
			result.append(src)
	return result


func get_count_for_resource(resource_id: StringName) -> int:
	return get_selected_by_resource(resource_id).size()


func get_counts_by_resource() -> Dictionary:
	var counts: Dictionary = {}
	for src: ResourceSource in get_selected_sources():
		var res_id: StringName = src.get_resource_id()
		counts[res_id] = int(counts.get(res_id, 0)) + 1
	return counts


func get_selected_count() -> int:
	return get_selected_sources().size()


func is_empty() -> bool:
	return get_selected_count() == 0


func _insert_source(source: ResourceSource) -> void:
	var sid: int = source.get_instance_id()
	_selected_order.append(sid)
	_selected_refs[sid] = weakref(source)
	_bind_source_signals(source, sid)


func _remove_source_id(sid: int, known_source: ResourceSource = null) -> void:
	_selected_order.erase(sid)
	_selected_refs.erase(sid)
	_unbind_source_signals(sid, known_source)


func _resolve_ref(sid: int) -> ResourceSource:
	if not _selected_refs.has(sid):
		return null
	var ref: WeakRef = _selected_refs[sid] as WeakRef
	var obj: Object = ref.get_ref() if ref != null else null
	if obj != null and is_instance_valid(obj) and obj is ResourceSource:
		return obj as ResourceSource
	return null


func _prune_invalid_sources() -> bool:
	var removed_any: bool = false
	var to_remove: Array[int] = []
	for sid: int in _selected_order:
		var src: ResourceSource = _resolve_ref(sid)
		if src == null or not is_source_eligible(src):
			to_remove.append(sid)
	for sid: int in to_remove:
		_remove_source_id(sid, null)
		removed_any = true
	return removed_any


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


func _unbind_source_signals(sid: int, known_source: ResourceSource = null) -> void:
	if not _source_callbacks.has(sid):
		return
	var entry: Dictionary = _source_callbacks[sid] as Dictionary
	_source_callbacks.erase(sid)
	var src: ResourceSource = known_source
	if src == null or not is_instance_valid(src):
		var ref: WeakRef = entry.get("source_ref") as WeakRef
		var obj: Object = ref.get_ref() if ref != null else null
		if obj != null and is_instance_valid(obj) and obj is ResourceSource:
			src = obj as ResourceSource
	if src == null or not is_instance_valid(src):
		return
	var on_exit: Callable = entry.get("on_exit", Callable()) as Callable
	var on_depleted: Callable = entry.get("on_depleted", Callable()) as Callable
	if on_exit.is_valid() and src.tree_exited.is_connected(on_exit):
		src.tree_exited.disconnect(on_exit)
	if on_depleted.is_valid() and src.depleted.is_connected(on_depleted):
		src.depleted.disconnect(on_depleted)


func _disconnect_all_sources() -> void:
	var sids: Array = _source_callbacks.keys().duplicate()
	for sid_val: Variant in sids:
		_unbind_source_signals(int(sid_val), null)
	_source_callbacks.clear()


func _on_source_tree_exited(sid: int) -> void:
	if not _selected_refs.has(sid):
		_unbind_source_signals(sid, null)
		return
	_remove_source_id(sid, null)
	selection_changed.emit()


func _on_source_depleted(_source: ResourceSource, sid: int) -> void:
	if not _selected_refs.has(sid):
		_unbind_source_signals(sid, null)
		return
	_remove_source_id(sid, null)
	selection_changed.emit()
