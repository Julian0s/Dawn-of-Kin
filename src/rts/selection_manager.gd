class_name SelectionManager
extends Node
## Maintains the active set of selected Unit instances without handling input or raycasting.
## Prevents duplicates/invalid references and prunes units that exit the SceneTree.

signal selection_changed(selected_units: Array[Unit])

var _selected_units: Array[Unit] = []


func _exit_tree() -> void:
	for unit: Unit in _selected_units:
		if is_instance_valid(unit):
			_disconnect_unit_signal(unit)
	_selected_units.clear()


func get_selected_units() -> Array[Unit]:
	_prune_invalid_units(false)
	return _selected_units.duplicate()


func get_selection_count() -> int:
	_prune_invalid_units(false)
	return _selected_units.size()


func is_empty() -> bool:
	return get_selection_count() == 0


func is_selected(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	return _selected_units.has(unit)


func select_single(unit: Unit) -> void:
	_prune_invalid_units(false)
	if not _is_selectable_unit(unit):
		clear_selection()
		return

	if _selected_units.size() == 1 and _selected_units[0] == unit:
		unit.set_selected(true)
		return

	for existing: Unit in _selected_units:
		if is_instance_valid(existing) and existing != unit:
			_disconnect_unit_signal(existing)
			existing.set_selected(false)

	_selected_units.clear()
	_selected_units.append(unit)
	_connect_unit_signal(unit)
	unit.set_selected(true)
	_emit_selection_changed()


func add_unit(unit: Unit) -> void:
	_prune_invalid_units(false)
	if not _is_selectable_unit(unit) or _selected_units.has(unit):
		return

	_selected_units.append(unit)
	_connect_unit_signal(unit)
	unit.set_selected(true)
	_emit_selection_changed()


func add_units(units: Array[Unit]) -> void:
	var changed: bool = _prune_invalid_units(false)
	for candidate: Unit in units:
		if not _is_selectable_unit(candidate) or _selected_units.has(candidate):
			continue
		_selected_units.append(candidate)
		_connect_unit_signal(candidate)
		candidate.set_selected(true)
		changed = true

	if changed:
		_emit_selection_changed()


func remove_unit(unit: Unit) -> void:
	var removed: bool = _prune_invalid_units(false)
	if unit != null and _selected_units.has(unit):
		_selected_units.erase(unit)
		if is_instance_valid(unit):
			_disconnect_unit_signal(unit)
			unit.set_selected(false)
		removed = true

	if removed:
		_emit_selection_changed()


func toggle_unit(unit: Unit) -> void:
	if not _is_selectable_unit(unit):
		return
	if is_selected(unit):
		remove_unit(unit)
	else:
		add_unit(unit)


func set_selection(units: Array[Unit]) -> void:
	_prune_invalid_units(false)

	var desired: Array[Unit] = []
	for candidate: Unit in units:
		if _is_selectable_unit(candidate) and not desired.has(candidate):
			desired.append(candidate)

	if _arrays_match(_selected_units, desired):
		return

	for existing: Unit in _selected_units:
		if is_instance_valid(existing) and not desired.has(existing):
			_disconnect_unit_signal(existing)
			existing.set_selected(false)

	_selected_units.clear()
	for unit: Unit in desired:
		_selected_units.append(unit)
		_connect_unit_signal(unit)
		unit.set_selected(true)

	_emit_selection_changed()


func clear_selection() -> void:
	var pruned: bool = _prune_invalid_units(false)
	if _selected_units.is_empty():
		if pruned:
			_emit_selection_changed()
		return

	for existing: Unit in _selected_units:
		if is_instance_valid(existing):
			_disconnect_unit_signal(existing)
			existing.set_selected(false)

	_selected_units.clear()
	_emit_selection_changed()


func _on_unit_tree_exited(unit: Unit) -> void:
	if _selected_units.has(unit):
		_selected_units.erase(unit)
		if is_instance_valid(unit):
			_disconnect_unit_signal(unit)
			unit.set_selected(false)
		_emit_selection_changed()


func _connect_unit_signal(unit: Unit) -> void:
	var cb: Callable = Callable(self, "_on_unit_tree_exited").bind(unit)
	if not unit.tree_exited.is_connected(cb):
		unit.tree_exited.connect(cb)


func _disconnect_unit_signal(unit: Unit) -> void:
	var cb: Callable = Callable(self, "_on_unit_tree_exited").bind(unit)
	if unit.tree_exited.is_connected(cb):
		unit.tree_exited.disconnect(cb)


func _prune_invalid_units(emit_if_changed: bool) -> bool:
	var changed: bool = false
	for i: int in range(_selected_units.size() - 1, -1, -1):
		var unit: Unit = _selected_units[i]
		if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
			if unit != null and is_instance_valid(unit):
				_disconnect_unit_signal(unit)
				unit.set_selected(false)
			_selected_units.remove_at(i)
			changed = true

	if changed and emit_if_changed:
		_emit_selection_changed()
	return changed


func _emit_selection_changed() -> void:
	selection_changed.emit(_selected_units.duplicate())


static func _is_selectable_unit(unit: Unit) -> bool:
	return (
		unit != null
		and is_instance_valid(unit)
		and unit.is_inside_tree()
		and UnitControlPermissions.can_be_selected_visually(unit)
	)


static func _arrays_match(a: Array[Unit], b: Array[Unit]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in range(a.size()):
		if a[i] != b[i]:
			return false
	return true
