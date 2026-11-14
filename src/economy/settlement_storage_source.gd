class_name SettlementStorageSource
extends RefCounted
## Replaceable storage backend interface for SettlementInventory.
## In T2.1+, GroundPileManager implements or adapts this contract so camp piles
## and SettlementInventory share a single transactional authority without duplicate balances.

signal storage_changed()

var _batch_depth: int = 0
var _batch_dirty: bool = false


func begin_batch() -> void:
	_batch_depth += 1


func end_batch(discard_dirty: bool = false) -> void:
	if _batch_depth <= 0:
		return
	_batch_depth -= 1
	if _batch_depth == 0:
		if discard_dirty:
			_batch_dirty = false
			return
		if _batch_dirty:
			_batch_dirty = false
			_dispatch_storage_changed()


func is_batch_active() -> bool:
	return _batch_depth > 0


func _emit_storage_changed() -> void:
	if _batch_depth > 0:
		_batch_dirty = true
		return
	_dispatch_storage_changed()


func _dispatch_storage_changed() -> void:
	storage_changed.emit()


func get_amount(_resource_id: StringName) -> int:
	return 0


func get_all_amounts() -> Dictionary:
	return {}


func deposit(_resource_id: StringName, _amount: int) -> bool:
	return false


func can_deposit_batch(amounts: Dictionary) -> bool:
	if amounts.is_empty():
		return false
	for key: Variant in amounts.keys():
		if not (key is StringName):
			return false
		var resource_id: StringName = key as StringName
		var amount: int = int(amounts[resource_id])
		if resource_id.is_empty() or amount <= 0:
			return false
	return true


func deposit_batch(amounts: Dictionary) -> bool:
	if not can_deposit_batch(amounts):
		return false
	var prev_dirty: bool = _batch_dirty
	begin_batch()
	var deposited: Dictionary = {}
	for key: Variant in amounts.keys():
		var resource_id: StringName = key as StringName
		var amount: int = int(amounts[resource_id])
		if not deposit(resource_id, amount):
			for rb_key: Variant in deposited.keys():
				var rb_id: StringName = rb_key as StringName
				withdraw(rb_id, int(deposited[rb_id]))
			_batch_dirty = prev_dirty
			end_batch(false)
			return false
		deposited[resource_id] = amount
	end_batch(false)
	return true


func withdraw(_resource_id: StringName, _amount: int) -> bool:
	return false


func get_total_decayed(_resource_id: StringName) -> int:
	return 0


func get_all_decayed() -> Dictionary:
	return {}
