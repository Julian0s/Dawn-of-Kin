class_name InMemoryStorageSource
extends SettlementStorageSource
## Minimal T2.0 storage source for unit tests and pre-T2.1 inventory verification.
## Starts empty (zero free starting resources) and supports intentional decay recording.

var _amounts: Dictionary = {}
var _decayed: Dictionary = {}
var _reservations: Dictionary = {}
var _reservation_order: Dictionary = {}
var _next_reservation_seq: int = 1
var _is_preparing_withdrawal: bool = false


func is_locked() -> bool:
	return (
		_is_preparing_withdrawal
		or ReservedWithdrawalCoordinator._has_active_site_creation_for_storage(null, self)
		or ReservedWithdrawalCoordinator._has_active_manual_complement_for_storage(null, self)
		or ReservedWithdrawalCoordinator._has_active_cancellation_for_storage(null, self)
	)


func begin_batch() -> void:
	if is_locked():
		return
	super.begin_batch()


func end_batch(discard_dirty: bool = false) -> void:
	if is_locked():
		return
	super.end_batch(discard_dirty)


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
	if is_locked() or resource_id.is_empty() or amount <= 0:
		return false
	_amounts[resource_id] = get_physical_amount(resource_id) + amount
	_emit_storage_changed()
	return true


func deposit_batch(amounts: Dictionary) -> bool:
	if is_locked():
		return false
	return super.deposit_batch(amounts)


func withdraw(resource_id: StringName, amount: int) -> bool:
	if is_locked() or resource_id.is_empty() or amount <= 0:
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


func withdraw_batch(amounts: Dictionary) -> bool:
	if is_locked():
		return false
	return super.withdraw_batch(amounts)


func can_reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if is_locked():
		return false
	return super.can_reserve_batch(reservation_id, amounts)


func reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if is_locked() or not super.can_reserve_batch(reservation_id, amounts):
		return false
	var parsed: Dictionary = parse_positive_batch(amounts)
	var items: Dictionary = parsed["items"] as Dictionary
	_reservations[reservation_id] = items.duplicate()
	_reservation_order[reservation_id] = _next_reservation_seq
	_next_reservation_seq += 1
	_emit_reservations_changed()
	_emit_storage_changed()
	return true


func _can_complement_reservation_unlocked(
	reservation_id: StringName,
	extra_amounts: Dictionary,
	scope: Variant = null
) -> bool:
	if scope != null:
		if not (scope is ReservedWithdrawalCoordinator.ManualComplementScope):
			return false
		var mc_scope := scope as ReservedWithdrawalCoordinator.ManualComplementScope
		if not ReservedWithdrawalCoordinator._owns_manual_complement_scope(mc_scope) or mc_scope.storage_source != self:
			return false
	elif is_locked():
		return false
	if reservation_id.is_empty():
		return false
	var parsed: Dictionary = parse_positive_batch(extra_amounts)
	if not (parsed["ok"] as bool):
		return false
	var items: Dictionary = parsed["items"] as Dictionary
	for key: Variant in items.keys():
		var res_id: StringName = key as StringName
		if get_available_amount(res_id) < int(items[res_id]):
			return false
	return true


func can_complement_reservation(reservation_id: StringName, extra_amounts: Dictionary) -> bool:
	if is_locked():
		return false
	return _can_complement_reservation_unlocked(reservation_id, extra_amounts, null)


func _apply_complement_reservation_internal(
	reservation_id: StringName,
	extra_amounts: Dictionary,
	scope: Variant = null
) -> Dictionary:
	if not (scope is ReservedWithdrawalCoordinator.ManualComplementScope):
		return {"ok": false, "checkpoint": {}}
	var mc_scope := scope as ReservedWithdrawalCoordinator.ManualComplementScope
	if not ReservedWithdrawalCoordinator._owns_manual_complement_scope(mc_scope) or mc_scope.storage_source != self:
		return {"ok": false, "checkpoint": {}}
	if (
		mc_scope._complement_applied
		or mc_scope._published
		or mc_scope._rolled_back
		or mc_scope._commit_authorized
		or mc_scope._rollback_authorized
		or is_batch_active()
		or not _is_preparing_withdrawal
	):
		return {"ok": false, "checkpoint": {}}
	if not _can_complement_reservation_unlocked(reservation_id, extra_amounts, mc_scope):
		return {"ok": false, "checkpoint": {}}
	var parsed: Dictionary = parse_positive_batch(extra_amounts)
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]
	var checkpoint: Dictionary = {
		"snap": _create_rollback_snapshot(),
		"storage_revision": _transaction_revision,
	}

	if not _reservations.has(reservation_id):
		_reservations[reservation_id] = {}
	var bucket: Dictionary = _reservations[reservation_id] as Dictionary
	for res_id: StringName in sorted_keys:
		var add_amt: int = int(items[res_id])
		if get_available_amount(res_id) < add_amt:
			_restore_rollback_snapshot(checkpoint["snap"])
			_transaction_revision = int(checkpoint["storage_revision"])
			return {"ok": false, "checkpoint": {}}
		bucket[res_id] = int(bucket.get(res_id, 0)) + add_amt
	if not _reservation_order.has(reservation_id):
		_reservation_order[reservation_id] = _next_reservation_seq
		_next_reservation_seq += 1
	mc_scope._bound_checkpoint = checkpoint.duplicate(true)
	return {"ok": true, "checkpoint": checkpoint}


func complement_reservation(reservation_id: StringName, extra_amounts: Dictionary) -> bool:
	if is_locked() or not _can_complement_reservation_unlocked(reservation_id, extra_amounts, null):
		return false
	var parsed: Dictionary = parse_positive_batch(extra_amounts)
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]
	var snapshot: Variant = _create_rollback_snapshot()

	if not _reservations.has(reservation_id):
		_reservations[reservation_id] = {}
	var bucket: Dictionary = _reservations[reservation_id] as Dictionary
	for res_id: StringName in sorted_keys:
		var add_amt: int = int(items[res_id])
		if get_available_amount(res_id) < add_amt:
			_restore_rollback_snapshot(snapshot)
			return false
		bucket[res_id] = int(bucket.get(res_id, 0)) + add_amt
	if not _reservation_order.has(reservation_id):
		_reservation_order[reservation_id] = _next_reservation_seq
		_next_reservation_seq += 1

	begin_batch()
	_emit_reservations_changed()
	_emit_storage_changed()
	end_batch(false)
	return true


func release_batch(reservation_id: StringName, amounts: Dictionary = {}) -> bool:
	if is_locked() or not has_reservation(reservation_id):
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
	if is_locked() or reservation_id.is_empty() or resource_id.is_empty() or amount <= 0:
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


func withdraw_reserved_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if is_locked():
		return false
	return super.withdraw_reserved_batch(reservation_id, amounts)


func _create_rollback_snapshot() -> Variant:
	var res_copy: Dictionary = {}
	for key: Variant in _reservations.keys():
		res_copy[key] = (_reservations[key] as Dictionary).duplicate()
	return {
		"amounts": _amounts.duplicate(),
		"reservations": res_copy,
		"reservation_order": _reservation_order.duplicate(),
		"next_reservation_seq": _next_reservation_seq,
	}


func _restore_rollback_snapshot(snapshot: Variant) -> void:
	if not (snapshot is Dictionary):
		return
	var snap: Dictionary = snapshot as Dictionary
	_amounts = (snap.get("amounts", {}) as Dictionary).duplicate()
	_reservations.clear()
	var res_src: Dictionary = snap.get("reservations", {}) as Dictionary
	for key: Variant in res_src.keys():
		_reservations[key] = (res_src[key] as Dictionary).duplicate()
	_reservation_order = (snap.get("reservation_order", {}) as Dictionary).duplicate()
	_next_reservation_seq = int(snap.get("next_reservation_seq", 1))


func record_intentional_decay(resource_id: StringName, amount: int) -> int:
	if is_locked() or resource_id.is_empty() or amount <= 0:
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


func _apply_site_reservation_silent(
	reservation_id: StringName,
	amounts: Dictionary,
	scope: ReservedWithdrawalCoordinator.SiteCreationScope
) -> Dictionary:
	if not ReservedWithdrawalCoordinator._owns_site_creation_scope(scope) or scope.storage_source != self:
		return {"ok": false, "reason": "unauthorized_scope", "checkpoint": {}}
	if (
		scope._reservation_applied
		or scope._published
		or scope._rolled_back
		or scope._commit_authorized
		or scope._rollback_authorized
		or is_batch_active()
		or not _is_preparing_withdrawal
	):
		return {"ok": false, "reason": "busy", "checkpoint": {}}
	if not super.can_reserve_batch(reservation_id, amounts):
		return {"ok": false, "reason": "insufficient_resources", "checkpoint": {}}
	var parsed: Dictionary = parse_positive_batch(amounts)
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "reason": "insufficient_resources", "checkpoint": {}}
	var checkpoint: Dictionary = {
		"snap": _create_rollback_snapshot(),
		"storage_revision": _transaction_revision,
	}
	var items: Dictionary = parsed["items"] as Dictionary
	_reservations[reservation_id] = items.duplicate()
	_reservation_order[reservation_id] = _next_reservation_seq
	_next_reservation_seq += 1
	_transaction_revision += 1
	scope._reservation_applied = true
	scope._bound_checkpoint = checkpoint.duplicate(true)
	return {"ok": true, "reason": "", "checkpoint": checkpoint}


func _restore_site_reservation_checkpoint_silent(
	checkpoint: Dictionary,
	scope: ReservedWithdrawalCoordinator.SiteCreationScope
) -> void:
	if not ReservedWithdrawalCoordinator._owns_site_creation_scope(scope) or scope.storage_source != self:
		return
	if (
		not scope._reservation_applied
		or scope._published
		or scope._rolled_back
		or not scope._rollback_authorized
		or scope._commit_authorized
		or checkpoint.is_empty()
		or scope._bound_checkpoint.is_empty()
		or checkpoint != scope._bound_checkpoint
	):
		return
	_restore_rollback_snapshot(scope._bound_checkpoint.get("snap"))
	_transaction_revision = int(scope._bound_checkpoint.get("storage_revision", _transaction_revision))
	scope._reservation_applied = false
	scope._rollback_authorized = false
	scope._rolled_back = true
	scope._bound_checkpoint = {}


func _publish_site_reservation_committed(
	scope: ReservedWithdrawalCoordinator.SiteCreationScope
) -> void:
	if not ReservedWithdrawalCoordinator._owns_site_creation_scope(scope) or scope.storage_source != self:
		return
	if (
		not scope._reservation_applied
		or scope._published
		or scope._rolled_back
		or not scope._commit_authorized
		or scope._rollback_authorized
	):
		return
	scope._published = true
	scope._commit_authorized = false
	scope._bound_checkpoint = {}
	if is_batch_active():
		_reservation_batch_dirty = true
		_batch_dirty = true
		return
	_dispatch_reservations_changed()
	_dispatch_storage_changed()


## ---------------------------------------------------------------------------
## T3.6.3-B1.1 — Scoped Silent Reservation Release Primitives (D3)
## Revision Rollback Contract (Audit Adjustment 1):
## Rollback restores exact reservation amounts, reservation_order, and next_seq
## while advancing _transaction_revision monotonically so stale plans stay invalid.
## ---------------------------------------------------------------------------

func _prepare_cancel_release_under_guard(
	reservation_id: StringName,
	expected_amounts: Dictionary,
	scope: Variant = null
) -> Dictionary:
	if not (scope is ReservedWithdrawalCoordinator.CancellationScope):
		return {"ok": false, "reason": "unauthorized_scope"}
	var cc := scope as ReservedWithdrawalCoordinator.CancellationScope
	if not ReservedWithdrawalCoordinator._owns_cancellation_scope(cc) or cc.storage_source != self or cc._rolled_back or cc._published:
		return {"ok": false, "reason": "unauthorized_scope"}
	if cc._release_applied or cc._commit_authorized or cc._rollback_authorized or is_batch_active() or not _is_preparing_withdrawal:
		return {"ok": false, "reason": "busy"}
	if not CarryProvenanceLedger._id(reservation_id) or reservation_id != cc.reservation_id:
		return {"ok": false, "reason": "reservation_identity_mismatch"}

	var normalized_expected: Dictionary = {}
	var positive_expected: Dictionary = {}
	var total_expected: int = 0
	for k: Variant in expected_amounts.keys():
		if not CarryProvenanceLedger._id(k):
			return {"ok": false, "reason": "invalid_expected_amounts"}
		var v: Variant = expected_amounts[k]
		if typeof(v) != TYPE_INT or int(v) < 0:
			return {"ok": false, "reason": "invalid_expected_amounts"}
		var amt: int = int(v)
		if total_expected > CarryProvenanceLedger.MAX_INT - amt:
			return {"ok": false, "reason": "overflow"}
		var res_key := StringName(k)
		normalized_expected[res_key] = amt
		total_expected += amt
		if amt > 0:
			positive_expected[res_key] = amt
	if normalized_expected != cc._expected_release_amounts:
		return {"ok": false, "reason": "expected_amounts_mismatch"}
	if cc._release_noop != (total_expected == 0):
		return {"ok": false, "reason": "noop_expectation_mismatch"}

	var actual_reserved: Dictionary = get_reservation_amounts(reservation_id)
	if total_expected == 0:
		if has_reservation(reservation_id) or not actual_reserved.is_empty():
			return {"ok": false, "reason": "reservation_amount_mismatch"}
		return {
			"ok": true,
			"reason": "",
			"noop": true,
			"reservation_id": reservation_id,
			"released_amounts": {},
			"revisions": {"storage_revision": _transaction_revision},
		}

	if not has_reservation(reservation_id):
		return {"ok": false, "reason": "missing_reservation"}
	if actual_reserved != positive_expected:
		return {"ok": false, "reason": "reservation_amount_mismatch"}

	return {
		"ok": true,
		"reason": "",
		"noop": false,
		"reservation_id": reservation_id,
		"released_amounts": positive_expected.duplicate(),
		"revisions": {"storage_revision": _transaction_revision},
	}


func _apply_prepared_cancel_release_silent(
	plan: Dictionary,
	scope: Variant = null
) -> Dictionary:
	if not (scope is ReservedWithdrawalCoordinator.CancellationScope):
		return {"ok": false, "reason": "unauthorized_scope", "checkpoint": {}}
	var cc := scope as ReservedWithdrawalCoordinator.CancellationScope
	if not ReservedWithdrawalCoordinator._owns_cancellation_scope(cc) or cc.storage_source != self or cc._rolled_back or cc._published:
		return {"ok": false, "reason": "unauthorized_scope", "checkpoint": {}}
	if cc._release_applied or cc._commit_authorized or cc._rollback_authorized or is_batch_active() or not _is_preparing_withdrawal:
		return {"ok": false, "reason": "busy", "checkpoint": {}}
	if not bool(plan.get("ok", false)) or StringName(plan.get("reservation_id", &"")) != cc.reservation_id:
		return {"ok": false, "reason": "invalid_plan", "checkpoint": {}}

	var plan_revs_var: Variant = plan.get("revisions")
	if not (plan_revs_var is Dictionary) or int((plan_revs_var as Dictionary).get("storage_revision", -1)) != _transaction_revision:
		return {"ok": false, "reason": "stale_revision", "checkpoint": {}}

	var recomputed: Dictionary = _prepare_cancel_release_under_guard(cc.reservation_id, cc._expected_release_amounts, cc)
	if not bool(recomputed.get("ok", false)) or recomputed != plan:
		return {"ok": false, "reason": String(recomputed.get("reason", "stale_plan")), "checkpoint": {}}

	var is_noop: bool = bool(plan.get("noop", false))
	var checkpoint: Dictionary = {
		"reservation_id": cc.reservation_id,
		"noop": is_noop,
		"mutated": not is_noop,
		"snap": _create_rollback_snapshot(),
		"pre_storage_revision": _transaction_revision,
	}
	if not is_noop:
		_reservations.erase(cc.reservation_id)
		_reservation_order.erase(cc.reservation_id)
	_transaction_revision += 1
	checkpoint["applied_storage_revision"] = _transaction_revision
	cc._release_applied = true
	cc._bound_checkpoint = checkpoint.duplicate(true)
	return {"ok": true, "reason": "", "noop": is_noop, "checkpoint": checkpoint}


func _restore_cancel_release_checkpoint_silent(
	checkpoint: Dictionary,
	scope: Variant = null
) -> bool:
	if not (scope is ReservedWithdrawalCoordinator.CancellationScope):
		return false
	var cc := scope as ReservedWithdrawalCoordinator.CancellationScope
	if not ReservedWithdrawalCoordinator._owns_cancellation_scope(cc) or cc.storage_source != self:
		return false
	if (
		not cc._release_applied
		or cc._published
		or cc._rolled_back
		or not cc._rollback_authorized
		or cc._commit_authorized
		or checkpoint.is_empty()
		or cc._bound_checkpoint.is_empty()
		or checkpoint != cc._bound_checkpoint
	):
		return false
	_restore_rollback_snapshot(cc._bound_checkpoint.get("snap"))
	_transaction_revision += 1
	cc._release_applied = false
	cc._rollback_authorized = false
	cc._rolled_back = true
	cc._bound_checkpoint = {}
	return true


func _publish_cancel_release_committed(
	scope: Variant = null
) -> bool:
	if not (scope is ReservedWithdrawalCoordinator.CancellationScope):
		return false
	var cc := scope as ReservedWithdrawalCoordinator.CancellationScope
	if not ReservedWithdrawalCoordinator._owns_cancellation_scope(cc) or cc.storage_source != self:
		return false
	if (
		not cc._release_applied
		or cc._published
		or cc._rolled_back
		or not cc._commit_authorized
		or cc._rollback_authorized
	):
		return false
	cc._published = true
	cc._commit_authorized = false
	cc._bound_checkpoint = {}
	if cc._release_noop:
		return true
	if is_batch_active():
		_reservation_batch_dirty = true
		_batch_dirty = true
		return true
	_dispatch_reservations_changed()
	_dispatch_storage_changed()
	return true


func _prepare_manual_complement_under_guard(
	reservation_id: StringName,
	extra_amounts: Dictionary,
	scope: ReservedWithdrawalCoordinator.ManualComplementScope
) -> Dictionary:
	if not ReservedWithdrawalCoordinator._owns_manual_complement_scope(scope) or scope.storage_source != self:
		return {"ok": false, "reason": "unauthorized_scope"}
	if (
		scope._complement_applied
		or scope._published
		or scope._rolled_back
		or scope._commit_authorized
		or scope._rollback_authorized
		or is_batch_active()
		or not _is_preparing_withdrawal
	):
		return {"ok": false, "reason": "busy"}
	if not _can_complement_reservation_unlocked(reservation_id, extra_amounts, scope):
		return {"ok": false, "reason": "insufficient_resources"}
	return {"ok": true, "reason": ""}


func _apply_manual_complement_silent(
	reservation_id: StringName,
	extra_amounts: Dictionary,
	scope: ReservedWithdrawalCoordinator.ManualComplementScope
) -> Dictionary:
	if not ReservedWithdrawalCoordinator._owns_manual_complement_scope(scope) or scope.storage_source != self:
		return {"ok": false, "reason": "unauthorized_scope", "checkpoint": {}}
	if (
		scope._complement_applied
		or scope._published
		or scope._rolled_back
		or scope._commit_authorized
		or scope._rollback_authorized
		or is_batch_active()
		or not _is_preparing_withdrawal
	):
		return {"ok": false, "reason": "busy", "checkpoint": {}}
	var res: Dictionary = _apply_complement_reservation_internal(reservation_id, extra_amounts, scope)
	if not bool(res.get("ok", false)):
		return {"ok": false, "reason": "insufficient_resources", "checkpoint": {}}
	_transaction_revision += 1
	scope._complement_applied = true
	return {"ok": true, "reason": "", "checkpoint": res["checkpoint"]}


func _restore_manual_complement_checkpoint_silent(
	checkpoint: Dictionary,
	scope: ReservedWithdrawalCoordinator.ManualComplementScope
) -> void:
	if not ReservedWithdrawalCoordinator._owns_manual_complement_scope(scope) or scope.storage_source != self:
		return
	if (
		not scope._complement_applied
		or scope._published
		or scope._rolled_back
		or not scope._rollback_authorized
		or scope._commit_authorized
		or checkpoint.is_empty()
		or scope._bound_checkpoint.is_empty()
		or checkpoint != scope._bound_checkpoint
	):
		return
	_restore_rollback_snapshot(scope._bound_checkpoint.get("snap"))
	_transaction_revision = int(scope._bound_checkpoint.get("storage_revision", _transaction_revision))
	scope._complement_applied = false
	scope._rollback_authorized = false
	scope._rolled_back = true
	scope._bound_checkpoint = {}


func _publish_manual_complement_committed(
	scope: ReservedWithdrawalCoordinator.ManualComplementScope
) -> void:
	if not ReservedWithdrawalCoordinator._owns_manual_complement_scope(scope) or scope.storage_source != self:
		return
	if (
		not scope._complement_applied
		or scope._published
		or scope._rolled_back
		or not scope._commit_authorized
		or scope._rollback_authorized
	):
		return
	scope._published = true
	scope._commit_authorized = false
	scope._bound_checkpoint = {}
	if is_batch_active():
		_reservation_batch_dirty = true
		_batch_dirty = true
		return
	_dispatch_reservations_changed()
	_dispatch_storage_changed()
