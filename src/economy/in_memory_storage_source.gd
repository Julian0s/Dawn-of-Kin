class_name InMemoryStorageSource
extends SettlementStorageSource
## Minimal T2.0 storage source for unit tests and pre-T2.1 inventory verification.
## Starts empty (zero free starting resources) and supports intentional decay recording.

var _amounts: Dictionary = {}
var _decayed: Dictionary = {}
var _reservations: Dictionary = {}
var _reservation_order: Dictionary = {}
var _next_reservation_seq: int = 1


func get_physical_amount(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return int(_amounts.get(resource_id, 0))


func get_all_physical_amounts() -> Dictionary:
	return _amounts.duplicate()


func get_reserved_amount(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	var total: int = 0
	for res_key: Variant in _reservations.keys():
		var bucket: Dictionary = _reservations[res_key] as Dictionary
		total += int(bucket.get(resource_id, 0))
	return total


func get_all_reserved_amounts() -> Dictionary:
	var totals: Dictionary = {}
	for res_key: Variant in _reservations.keys():
		var bucket: Dictionary = _reservations[res_key] as Dictionary
		for item_key: Variant in bucket.keys():
			var item_id: StringName = item_key as StringName
			var amt: int = int(bucket[item_id])
			if amt > 0:
				totals[item_id] = int(totals.get(item_id, 0)) + amt
	return totals


func has_reservation(reservation_id: StringName) -> bool:
	if reservation_id.is_empty() or not _reservations.has(reservation_id):
		return false
	return not (_reservations[reservation_id] as Dictionary).is_empty()


func get_reservation_amount(reservation_id: StringName, resource_id: StringName) -> int:
	if reservation_id.is_empty() or resource_id.is_empty() or not _reservations.has(reservation_id):
		return 0
	var bucket: Dictionary = _reservations[reservation_id] as Dictionary
	return int(bucket.get(resource_id, 0))


func get_reservation_amounts(reservation_id: StringName) -> Dictionary:
	if reservation_id.is_empty() or not _reservations.has(reservation_id):
		return {}
	return (_reservations[reservation_id] as Dictionary).duplicate()


func get_all_reservation_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for res_key: Variant in _reservations.keys():
		var res_id: StringName = res_key as StringName
		if has_reservation(res_id):
			ids.append(res_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var sa: int = int(_reservation_order.get(a, 0))
		var sb: int = int(_reservation_order.get(b, 0))
		if sa != sb:
			return sa < sb
		return String(a) < String(b)
	)
	return ids


func deposit(resource_id: StringName, amount: int) -> bool:
	if resource_id.is_empty() or amount <= 0:
		return false
	_amounts[resource_id] = get_physical_amount(resource_id) + amount
	_emit_storage_changed()
	return true


func withdraw(resource_id: StringName, amount: int) -> bool:
	if resource_id.is_empty() or amount <= 0:
		return false
	if get_available_amount(resource_id) < amount:
		return false
	var current: int = get_physical_amount(resource_id)
	var next_amount: int = current - amount
	if next_amount <= 0:
		_amounts.erase(resource_id)
	else:
		_amounts[resource_id] = next_amount
	_emit_storage_changed()
	return true


func reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if not can_reserve_batch(reservation_id, amounts):
		return false
	var parsed: Dictionary = parse_positive_batch(amounts)
	var items: Dictionary = parsed["items"] as Dictionary
	_reservations[reservation_id] = items.duplicate()
	_reservation_order[reservation_id] = _next_reservation_seq
	_next_reservation_seq += 1
	_emit_reservations_changed()
	_emit_storage_changed()
	return true


func release_batch(reservation_id: StringName, amounts: Dictionary = {}) -> bool:
	if not has_reservation(reservation_id):
		return false
	var bucket: Dictionary = _reservations[reservation_id] as Dictionary
	if amounts.is_empty():
		_reservations.erase(reservation_id)
		_reservation_order.erase(reservation_id)
		_emit_reservations_changed()
		_emit_storage_changed()
		return true

	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return false
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]
	for res_id: StringName in sorted_keys:
		if int(bucket.get(res_id, 0)) < int(items[res_id]):
			return false
	for res_id: StringName in sorted_keys:
		var left: int = int(bucket[res_id]) - int(items[res_id])
		if left <= 0:
			bucket.erase(res_id)
		else:
			bucket[res_id] = left
	if bucket.is_empty():
		_reservations.erase(reservation_id)
		_reservation_order.erase(reservation_id)
	_emit_reservations_changed()
	_emit_storage_changed()
	return true


func withdraw_reserved(reservation_id: StringName, resource_id: StringName, amount: int) -> bool:
	if reservation_id.is_empty() or resource_id.is_empty() or amount <= 0:
		return false
	if not has_reservation(reservation_id):
		return false
	var bucket: Dictionary = _reservations[reservation_id] as Dictionary
	if int(bucket.get(resource_id, 0)) < amount:
		return false
	var current_phys: int = get_physical_amount(resource_id)
	if current_phys < amount:
		return false

	var next_res: int = int(bucket[resource_id]) - amount
	if next_res <= 0:
		bucket.erase(resource_id)
	else:
		bucket[resource_id] = next_res
	if bucket.is_empty():
		_reservations.erase(reservation_id)
		_reservation_order.erase(reservation_id)

	var next_phys: int = current_phys - amount
	if next_phys <= 0:
		_amounts.erase(resource_id)
	else:
		_amounts[resource_id] = next_phys

	_emit_reservations_changed()
	_emit_storage_changed()
	return true


func record_intentional_decay(resource_id: StringName, amount: int) -> int:
	if resource_id.is_empty() or amount <= 0:
		return 0
	var current: int = get_physical_amount(resource_id)
	if current <= 0:
		return 0
	var decayed: int = mini(current, amount)
	var next_amount: int = current - decayed
	if next_amount <= 0:
		_amounts.erase(resource_id)
	else:
		_amounts[resource_id] = next_amount
	_decayed[resource_id] = int(_decayed.get(resource_id, 0)) + decayed

	var res_losses: Array[Dictionary] = _reconcile_reservations_after_decay(resource_id, next_amount)
	if not res_losses.is_empty():
		_emit_reservations_changed()
	_emit_storage_changed()
	for loss: Dictionary in res_losses:
		reservation_lost_to_decay.emit(
			loss["reservation_id"] as StringName,
			resource_id,
			loss["lost_amount"] as int
		)
	return decayed


func _reconcile_reservations_after_decay(resource_id: StringName, new_phys: int) -> Array[Dictionary]:
	var lost_records: Array[Dictionary] = []
	var total_res: int = get_reserved_amount(resource_id)
	var excess: int = total_res - maxi(0, new_phys)
	if excess <= 0:
		return lost_records

	var ids: Array[StringName] = []
	for key: Variant in _reservations.keys():
		var rid: StringName = key as StringName
		var bucket: Dictionary = _reservations[rid] as Dictionary
		if int(bucket.get(resource_id, 0)) > 0:
			ids.append(rid)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var sa: int = int(_reservation_order.get(a, 0))
		var sb: int = int(_reservation_order.get(b, 0))
		if sa != sb:
			return sa > sb
		return String(a) > String(b)
	)

	for rid: StringName in ids:
		if excess <= 0:
			break
		var bucket: Dictionary = _reservations[rid] as Dictionary
		var cur: int = int(bucket.get(resource_id, 0))
		var cut: int = mini(excess, cur)
		if cut <= 0:
			continue
		var left: int = cur - cut
		if left <= 0:
			bucket.erase(resource_id)
		else:
			bucket[resource_id] = left
		if bucket.is_empty():
			_reservations.erase(rid)
			_reservation_order.erase(rid)
		excess -= cut
		lost_records.append({
			"reservation_id": rid,
			"lost_amount": cut,
		})
	return lost_records


func get_total_decayed(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return int(_decayed.get(resource_id, 0))


func get_all_decayed() -> Dictionary:
	return _decayed.duplicate()
