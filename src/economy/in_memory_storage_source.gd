class_name InMemoryStorageSource
extends SettlementStorageSource
## Minimal T2.0 storage source for unit tests and pre-T2.1 inventory verification.
## Starts empty (zero free starting resources) and supports intentional decay recording.

var _amounts: Dictionary = {}
var _decayed: Dictionary = {}


func get_amount(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return int(_amounts.get(resource_id, 0))


func get_all_amounts() -> Dictionary:
	return _amounts.duplicate()


func deposit(resource_id: StringName, amount: int) -> bool:
	if resource_id.is_empty() or amount <= 0:
		return false
	_amounts[resource_id] = get_amount(resource_id) + amount
	_emit_storage_changed()
	return true


func withdraw(resource_id: StringName, amount: int) -> bool:
	if resource_id.is_empty() or amount <= 0:
		return false
	var current: int = get_amount(resource_id)
	if current < amount:
		return false
	var next_amount: int = current - amount
	if next_amount <= 0:
		_amounts.erase(resource_id)
	else:
		_amounts[resource_id] = next_amount
	_emit_storage_changed()
	return true


func record_intentional_decay(resource_id: StringName, amount: int) -> int:
	if resource_id.is_empty() or amount <= 0:
		return 0
	var current: int = get_amount(resource_id)
	if current <= 0:
		return 0
	var decayed: int = mini(current, amount)
	var next_amount: int = current - decayed
	if next_amount <= 0:
		_amounts.erase(resource_id)
	else:
		_amounts[resource_id] = next_amount
	_decayed[resource_id] = int(_decayed.get(resource_id, 0)) + decayed
	_emit_storage_changed()
	return decayed


func get_total_decayed(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return int(_decayed.get(resource_id, 0))


func get_all_decayed() -> Dictionary:
	return _decayed.duplicate()
