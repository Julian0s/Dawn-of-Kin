class_name UnitCarryLoad
extends RefCounted
## Physical individual carry inventory for a unit.
## Uses integer arithmetic internally for quantities, unit weights, and capacity.

signal load_changed()
signal capacity_changed()

var _base_capacity: int = 0
var _capacity_modifiers: Dictionary = {}
var _amounts: Dictionary = {}
var _unit_weights: Dictionary = {}


func _init(initial_base_capacity: int = 20) -> void:
	_base_capacity = maxi(0, initial_base_capacity)


func get_base_capacity() -> int:
	return _base_capacity


func set_base_capacity(new_capacity: int) -> bool:
	if new_capacity < 0:
		return false
	if _base_capacity == new_capacity:
		return true
	_base_capacity = new_capacity
	capacity_changed.emit()
	return true


func set_capacity_modifier(modifier_id: StringName, delta: int) -> bool:
	if modifier_id.is_empty():
		return false
	if delta == 0:
		return remove_capacity_modifier(modifier_id)
	if _capacity_modifiers.has(modifier_id) and int(_capacity_modifiers[modifier_id]) == delta:
		return true
	_capacity_modifiers[modifier_id] = delta
	capacity_changed.emit()
	return true


func remove_capacity_modifier(modifier_id: StringName) -> bool:
	if modifier_id.is_empty() or not _capacity_modifiers.has(modifier_id):
		return false
	_capacity_modifiers.erase(modifier_id)
	capacity_changed.emit()
	return true


func get_capacity_modifier_total() -> int:
	var total: int = 0
	for key: Variant in _capacity_modifiers.keys():
		total += int(_capacity_modifiers[key])
	return total


func get_effective_capacity() -> int:
	return maxi(0, _base_capacity + get_capacity_modifier_total())


func get_current_weight() -> int:
	var total: int = 0
	for key: Variant in _amounts.keys():
		var resource_id: StringName = key as StringName
		total += int(_amounts[resource_id]) * int(_unit_weights[resource_id])
	return total


func get_remaining_capacity() -> int:
	return maxi(0, get_effective_capacity() - get_current_weight())


func get_fill_percentage() -> float:
	var current: int = get_current_weight()
	if current <= 0:
		return 0.0
	var effective: int = get_effective_capacity()
	if effective <= 0:
		return 100.0
	return clampf((float(current) * 100.0) / float(effective), 0.0, 100.0)


func is_empty() -> bool:
	return _amounts.is_empty()


func is_full() -> bool:
	return get_remaining_capacity() <= 0


func get_amount(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return int(_amounts.get(resource_id, 0))


func get_all_amounts() -> Dictionary:
	return _amounts.duplicate()


func get_registered_unit_weight(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return int(_unit_weights.get(resource_id, 0))


func can_fit_one(definition: ResourceDefinition) -> bool:
	return get_max_additional_units(definition) >= 1


func get_max_additional_units(definition: ResourceDefinition) -> int:
	if definition == null or not definition.is_valid():
		return 0
	return get_max_additional_for(definition.resource_id, definition.unit_weight)


func get_max_additional_for(resource_id: StringName, unit_weight: int) -> int:
	if not _is_valid_resource_input(resource_id, unit_weight):
		return 0
	if not _is_weight_consistent(resource_id, unit_weight):
		return 0
	var remaining: int = get_remaining_capacity()
	if remaining < unit_weight:
		return 0
	@warning_ignore("integer_division")
	var max_units: int = remaining / unit_weight
	return max_units


func add_units(definition: ResourceDefinition, amount: int) -> bool:
	if definition == null or not definition.is_valid():
		return false
	return add_resource(definition.resource_id, definition.unit_weight, amount)


func add_resource(resource_id: StringName, unit_weight: int, amount: int) -> bool:
	if amount <= 0:
		return false
	if not _is_valid_resource_input(resource_id, unit_weight):
		return false
	if not _is_weight_consistent(resource_id, unit_weight):
		return false

	var added_weight: int = amount * unit_weight
	if added_weight > get_remaining_capacity():
		return false

	_unit_weights[resource_id] = unit_weight
	_amounts[resource_id] = get_amount(resource_id) + amount
	load_changed.emit()
	return true


func remove_units(resource_id: StringName, amount: int) -> int:
	if resource_id.is_empty() or amount <= 0:
		return 0
	var current: int = get_amount(resource_id)
	if current <= 0:
		return 0

	var removed: int = mini(current, amount)
	var next_amount: int = current - removed
	if next_amount <= 0:
		_amounts.erase(resource_id)
		_unit_weights.erase(resource_id)
	else:
		_amounts[resource_id] = next_amount

	load_changed.emit()
	return removed


func take_all() -> Dictionary:
	if _amounts.is_empty():
		return {}
	var taken: Dictionary = _amounts.duplicate()
	_amounts.clear()
	_unit_weights.clear()
	load_changed.emit()
	return taken


func _is_valid_resource_input(resource_id: StringName, unit_weight: int) -> bool:
	return not resource_id.is_empty() and unit_weight > 0


func _is_weight_consistent(resource_id: StringName, unit_weight: int) -> bool:
	if not _unit_weights.has(resource_id):
		return true
	return int(_unit_weights[resource_id]) == unit_weight
