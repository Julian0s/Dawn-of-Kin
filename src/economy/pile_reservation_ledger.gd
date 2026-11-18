class_name PileReservationLedger
extends RefCounted
## Deterministic per-pile reservation ledger used by physical storage managers.
## Guarantees reserved units never exceed physical pile balances and implements
## Alternative B (direct reservation reduction) when pile amounts drop via decay.

var _by_pile: Dictionary = {}
var _reservation_order: Dictionary = {}
var _next_seq: int = 1
var _transaction_revision: int = 0


func get_transaction_revision() -> int:
	return _transaction_revision


func clear() -> void:
	_by_pile.clear()
	_reservation_order.clear()
	_next_seq = 1
	_transaction_revision += 1


func has_reservation(reservation_id: StringName) -> bool:
	if reservation_id.is_empty():
		return false
	for pile_key: Variant in _by_pile.keys():
		var entry: Dictionary = _by_pile[pile_key] as Dictionary
		var allocs: Dictionary = entry["allocations"] as Dictionary
		if int(allocs.get(reservation_id, 0)) > 0:
			return true
	return false


func get_all_reservation_ids() -> Array[StringName]:
	var active: Dictionary = {}
	for pile_key: Variant in _by_pile.keys():
		var entry: Dictionary = _by_pile[pile_key] as Dictionary
		var allocs: Dictionary = entry["allocations"] as Dictionary
		for res_key: Variant in allocs.keys():
			var res_id: StringName = res_key as StringName
			if int(allocs[res_id]) > 0:
				active[res_id] = true
	var ids: Array[StringName] = []
	for key: Variant in active.keys():
		ids.append(key as StringName)
	ids.sort_custom(_sort_reservation_ids_asc)
	return ids


func get_pile_reserved_amount(pile_id: int) -> int:
	if not _by_pile.has(pile_id):
		return 0
	var entry: Dictionary = _by_pile[pile_id] as Dictionary
	var allocs: Dictionary = entry["allocations"] as Dictionary
	var total: int = 0
	for key: Variant in allocs.keys():
		total += int(allocs[key])
	return total


func get_pile_reservations(pile_id: int) -> Dictionary:
	if not _by_pile.has(pile_id):
		return {}
	var entry: Dictionary = _by_pile[pile_id] as Dictionary
	var allocs: Dictionary = entry["allocations"] as Dictionary
	return allocs.duplicate()


func get_reserved_amount_by_resource(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	var total: int = 0
	for pile_key: Variant in _by_pile.keys():
		var entry: Dictionary = _by_pile[pile_key] as Dictionary
		if (entry["resource_id"] as StringName) != resource_id:
			continue
		var allocs: Dictionary = entry["allocations"] as Dictionary
		for key: Variant in allocs.keys():
			total += int(allocs[key])
	return total


func get_all_reserved_amounts() -> Dictionary:
	var totals: Dictionary = {}
	for pile_key: Variant in _by_pile.keys():
		var entry: Dictionary = _by_pile[pile_key] as Dictionary
		var res_id: StringName = entry["resource_id"] as StringName
		var allocs: Dictionary = entry["allocations"] as Dictionary
		var pile_sum: int = 0
		for key: Variant in allocs.keys():
			pile_sum += int(allocs[key])
		if pile_sum > 0:
			totals[res_id] = int(totals.get(res_id, 0)) + pile_sum
	return totals


func get_reservation_amount(reservation_id: StringName, resource_id: StringName) -> int:
	if reservation_id.is_empty() or resource_id.is_empty():
		return 0
	var total: int = 0
	for pile_key: Variant in _by_pile.keys():
		var entry: Dictionary = _by_pile[pile_key] as Dictionary
		if (entry["resource_id"] as StringName) != resource_id:
			continue
		var allocs: Dictionary = entry["allocations"] as Dictionary
		total += int(allocs.get(reservation_id, 0))
	return total


func get_reservation_amounts(reservation_id: StringName) -> Dictionary:
	if reservation_id.is_empty():
		return {}
	var totals: Dictionary = {}
	for pile_key: Variant in _by_pile.keys():
		var entry: Dictionary = _by_pile[pile_key] as Dictionary
		var allocs: Dictionary = entry["allocations"] as Dictionary
		var amt: int = int(allocs.get(reservation_id, 0))
		if amt > 0:
			var res_id: StringName = entry["resource_id"] as StringName
			totals[res_id] = int(totals.get(res_id, 0)) + amt
	return totals


func get_pile_reservation_amount(pile_id: int, reservation_id: StringName) -> int:
	if not _by_pile.has(pile_id) or reservation_id.is_empty():
		return 0
	var entry: Dictionary = _by_pile[pile_id] as Dictionary
	var allocs: Dictionary = entry["allocations"] as Dictionary
	return int(allocs.get(reservation_id, 0))


func allocate_on_pile(
	pile_id: int,
	resource_id: StringName,
	reservation_id: StringName,
	amount: int
) -> void:
	if pile_id <= 0 or resource_id.is_empty() or reservation_id.is_empty() or amount <= 0:
		return
	if not _reservation_order.has(reservation_id):
		_reservation_order[reservation_id] = _next_seq
		_next_seq += 1
	if not _by_pile.has(pile_id):
		_by_pile[pile_id] = {
			"resource_id": resource_id,
			"allocations": {},
		}
	var entry: Dictionary = _by_pile[pile_id] as Dictionary
	var allocs: Dictionary = entry["allocations"] as Dictionary
	allocs[reservation_id] = int(allocs.get(reservation_id, 0)) + amount
	_transaction_revision += 1


func deduct_from_pile(
	pile_id: int,
	reservation_id: StringName,
	amount: int
) -> int:
	if amount <= 0 or not _by_pile.has(pile_id) or reservation_id.is_empty():
		return 0
	var entry: Dictionary = _by_pile[pile_id] as Dictionary
	var allocs: Dictionary = entry["allocations"] as Dictionary
	var current: int = int(allocs.get(reservation_id, 0))
	if current <= 0:
		return 0
	var deducted: int = mini(current, amount)
	var left: int = current - deducted
	if left <= 0:
		allocs.erase(reservation_id)
	else:
		allocs[reservation_id] = left
	if allocs.is_empty():
		_by_pile.erase(pile_id)
	if left <= 0 and not has_reservation(reservation_id):
		_reservation_order.erase(reservation_id)
	if deducted > 0:
		_transaction_revision += 1
	return deducted


func reconcile_pile_after_decay(pile_id: int, new_pile_amount: int) -> Array[Dictionary]:
	## Enforces Alternative B (direct reservation loss without automatic re-anchoring):
	## if new_pile_amount < total_reserved on pile_id, excess reservations are trimmed
	## deterministically in reverse reservation creation order.
	var lost_records: Array[Dictionary] = []
	if not _by_pile.has(pile_id):
		return lost_records

	var clamped_amount: int = maxi(0, new_pile_amount)
	var total_reserved: int = get_pile_reserved_amount(pile_id)
	var excess: int = total_reserved - clamped_amount
	if excess <= 0:
		return lost_records

	var entry: Dictionary = _by_pile[pile_id] as Dictionary
	var resource_id: StringName = entry["resource_id"] as StringName
	var allocs: Dictionary = entry["allocations"] as Dictionary

	var res_ids: Array[StringName] = []
	for key: Variant in allocs.keys():
		res_ids.append(key as StringName)
	res_ids.sort_custom(_sort_reservation_ids_desc)

	for res_id: StringName in res_ids:
		if excess <= 0:
			break
		var current: int = int(allocs.get(res_id, 0))
		if current <= 0:
			continue
		var cut: int = mini(excess, current)
		var deducted: int = deduct_from_pile(pile_id, res_id, cut)
		if deducted > 0:
			excess -= deducted
			lost_records.append({
				"reservation_id": res_id,
				"resource_id": resource_id,
				"lost_amount": deducted,
			})

	return lost_records


func erase_pile(pile_id: int) -> void:
	if not _by_pile.has(pile_id):
		return
	var entry: Dictionary = _by_pile[pile_id] as Dictionary
	var allocs: Dictionary = entry["allocations"] as Dictionary
	var affected_ids: Array[StringName] = []
	for key: Variant in allocs.keys():
		affected_ids.append(key as StringName)
	_by_pile.erase(pile_id)
	for res_id: StringName in affected_ids:
		if not has_reservation(res_id):
			_reservation_order.erase(res_id)
	_transaction_revision += 1


func snapshot_state() -> Dictionary:
	var piles_copy: Dictionary = {}
	for pile_key: Variant in _by_pile.keys():
		var entry: Dictionary = _by_pile[pile_key] as Dictionary
		piles_copy[pile_key] = {
			"resource_id": entry["resource_id"],
			"allocations": (entry["allocations"] as Dictionary).duplicate(),
		}
	return {
		"by_pile": piles_copy,
		"reservation_order": _reservation_order.duplicate(),
		"next_seq": _next_seq,
	}


func restore_state(snap: Dictionary) -> void:
	_by_pile.clear()
	var piles_src: Dictionary = snap.get("by_pile", {}) as Dictionary
	for pile_key: Variant in piles_src.keys():
		var entry: Dictionary = piles_src[pile_key] as Dictionary
		_by_pile[pile_key] = {
			"resource_id": entry["resource_id"],
			"allocations": (entry["allocations"] as Dictionary).duplicate(),
		}
	_reservation_order = (snap.get("reservation_order", {}) as Dictionary).duplicate()
	_next_seq = int(snap.get("next_seq", 1))
	_transaction_revision += 1


func _sort_reservation_ids_asc(a: StringName, b: StringName) -> bool:
	var seq_a: int = int(_reservation_order.get(a, 0))
	var seq_b: int = int(_reservation_order.get(b, 0))
	if seq_a != seq_b:
		return seq_a < seq_b
	return String(a) < String(b)


func _sort_reservation_ids_desc(a: StringName, b: StringName) -> bool:
	var seq_a: int = int(_reservation_order.get(a, 0))
	var seq_b: int = int(_reservation_order.get(b, 0))
	if seq_a != seq_b:
		return seq_a > seq_b
	return String(a) > String(b)
