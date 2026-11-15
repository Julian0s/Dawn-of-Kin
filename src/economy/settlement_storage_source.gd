class_name SettlementStorageSource
extends RefCounted
## Replaceable storage backend interface for SettlementInventory.
## In T2.1+, GroundPileManager implements or adapts this contract so camp piles
## and SettlementInventory share a single transactional authority without duplicate balances.

signal storage_changed()
signal reservations_changed()
signal reservation_lost_to_decay(reservation_id: StringName, resource_id: StringName, lost_amount: int)

var _batch_depth: int = 0
var _batch_dirty: bool = false
var _reservation_batch_dirty: bool = false


func begin_batch() -> void:
	_batch_depth += 1


func end_batch(discard_dirty: bool = false) -> void:
	if _batch_depth <= 0:
		return
	_batch_depth -= 1
	if _batch_depth == 0:
		if discard_dirty:
			_batch_dirty = false
			_reservation_batch_dirty = false
			return
		var fire_storage: bool = _batch_dirty
		var fire_res: bool = _reservation_batch_dirty
		_batch_dirty = false
		_reservation_batch_dirty = false
		if fire_storage:
			_dispatch_storage_changed()
		if fire_res:
			_dispatch_reservations_changed()


func is_batch_active() -> bool:
	return _batch_depth > 0


func _emit_storage_changed() -> void:
	if _batch_depth > 0:
		_batch_dirty = true
		return
	_dispatch_storage_changed()


func _emit_reservations_changed() -> void:
	if _batch_depth > 0:
		_reservation_batch_dirty = true
		return
	_dispatch_reservations_changed()


func _dispatch_storage_changed() -> void:
	storage_changed.emit()


func _dispatch_reservations_changed() -> void:
	reservations_changed.emit()


func get_physical_amount(_resource_id: StringName) -> int:
	return 0


func get_all_physical_amounts() -> Dictionary:
	return {}


func get_reserved_amount(_resource_id: StringName) -> int:
	return 0


func get_all_reserved_amounts() -> Dictionary:
	return {}


func get_available_amount(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return maxi(0, get_physical_amount(resource_id) - get_reserved_amount(resource_id))


func get_all_available_amounts() -> Dictionary:
	var physical: Dictionary = get_all_physical_amounts()
	var reserved: Dictionary = get_all_reserved_amounts()
	var available: Dictionary = {}
	for key: Variant in physical.keys():
		var res_id: StringName = key as StringName
		var free_amt: int = maxi(0, int(physical[res_id]) - int(reserved.get(res_id, 0)))
		if free_amt > 0:
			available[res_id] = free_amt
	return available


func get_amount(resource_id: StringName) -> int:
	## Returns usable unreserved stock (equals physical balance when no reservations exist).
	return get_available_amount(resource_id)


func get_all_amounts() -> Dictionary:
	## Returns usable unreserved balances by resource_id.
	return get_all_available_amounts()


func has_reservation(_reservation_id: StringName) -> bool:
	return false


func get_reservation_amount(_reservation_id: StringName, _resource_id: StringName) -> int:
	return 0


func get_reservation_amounts(_reservation_id: StringName) -> Dictionary:
	return {}


func get_all_reservation_ids() -> Array[StringName]:
	return []


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


func can_withdraw_batch(amounts: Dictionary) -> bool:
	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return false
	var items: Dictionary = parsed["items"] as Dictionary
	for key: Variant in items.keys():
		var res_id: StringName = key as StringName
		if get_available_amount(res_id) < int(items[res_id]):
			return false
	return true


func withdraw_batch(amounts: Dictionary) -> bool:
	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return false
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]
	for res_id: StringName in sorted_keys:
		if get_available_amount(res_id) < int(items[res_id]):
			return false

	var prev_dirty: bool = _batch_dirty
	var prev_res_dirty: bool = _reservation_batch_dirty
	begin_batch()
	var withdrawn: Dictionary = {}
	for res_id: StringName in sorted_keys:
		var req: int = int(items[res_id])
		if not withdraw(res_id, req):
			for rb_key: Variant in withdrawn.keys():
				var rb_id: StringName = rb_key as StringName
				deposit(rb_id, int(withdrawn[rb_id]))
			_batch_dirty = prev_dirty
			_reservation_batch_dirty = prev_res_dirty
			end_batch(true)
			return false
		withdrawn[res_id] = req
	end_batch(false)
	return true


func can_reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if reservation_id.is_empty() or has_reservation(reservation_id):
		return false
	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return false
	var items: Dictionary = parsed["items"] as Dictionary
	for key: Variant in items.keys():
		var res_id: StringName = key as StringName
		if get_available_amount(res_id) < int(items[res_id]):
			return false
	return true


func reserve_batch(_reservation_id: StringName, _amounts: Dictionary) -> bool:
	return false


func release_batch(_reservation_id: StringName, _amounts: Dictionary = {}) -> bool:
	return false


func withdraw_reserved(_reservation_id: StringName, _resource_id: StringName, _amount: int) -> bool:
	return false


func withdraw_reserved_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if reservation_id.is_empty() or not has_reservation(reservation_id):
		return false
	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return false
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]
	for res_id: StringName in sorted_keys:
		if get_reservation_amount(reservation_id, res_id) < int(items[res_id]):
			return false
	var prev_dirty: bool = _batch_dirty
	var prev_res_dirty: bool = _reservation_batch_dirty
	begin_batch()
	for res_id: StringName in sorted_keys:
		if not withdraw_reserved(reservation_id, res_id, int(items[res_id])):
			_batch_dirty = prev_dirty
			_reservation_batch_dirty = prev_res_dirty
			end_batch(true)
			return false
	end_batch(false)
	return true


static func parse_positive_batch(amounts: Dictionary) -> Dictionary:
	if amounts.is_empty():
		return {"ok": false, "items": {}, "keys": []}
	var items: Dictionary = {}
	var sorted_keys: Array[StringName] = []
	for raw_key: Variant in amounts.keys():
		if not (raw_key is StringName or raw_key is String):
			return {"ok": false, "items": {}, "keys": []}
		var res_id: StringName = StringName(raw_key)
		if res_id.is_empty() or items.has(res_id):
			return {"ok": false, "items": {}, "keys": []}
		var raw_val: Variant = amounts[raw_key]
		if not (raw_val is int) or (raw_val as int) <= 0:
			return {"ok": false, "items": {}, "keys": []}
		items[res_id] = raw_val as int
		sorted_keys.append(res_id)
	sorted_keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return {"ok": true, "items": items, "keys": sorted_keys}


func get_total_decayed(_resource_id: StringName) -> int:
	return 0


func get_all_decayed() -> Dictionary:
	return {}
