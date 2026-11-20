class_name CancellationLifecycleGuard
extends RefCounted
## Read-only preflight for cooperative destruction. Cannot veto external free/exit_tree.


static func inspect_storage(storage: GroundPileManager) -> Dictionary:
	if storage == null or storage.is_locked() or storage.is_batch_active():
		return {"ok": false, "reason": "transaction_in_progress"}
	var world := storage.get_bound_withdrawal_world()
	var region := storage.get_bound_withdrawal_region()
	if world == null:
		return {"ok": true, "reason": ""}
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var authority := domains.get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
	if authority == null:
		return {"ok": false, "reason": "ambiguous_economic_domain"}
	if authority.storage == null or authority.storage.get_ref() != storage or authority.has_active_operation():
		return {"ok": false, "reason": "transaction_in_progress"}
	for record: ReservedWithdrawalCoordinator.CancellationCustodyRecord in authority.cancellation_custodies.values():
		if record == null or record.region_id != region or record.world_instance_id != world.get_instance_id() or not ReservedWithdrawalCoordinator.validate_custody_accounting_pure(record).ok:
			return {"ok": false, "reason": "invalid_cancellation_custody"}
		if record.get_obligation_status() != &"settled":
			return {"ok": false, "reason": "pending_cancellation_custody"}
	return {"ok": true, "reason": ""}


static func inspect_worker(unit: Unit, region: StringName) -> Dictionary:
	if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
		return {"ok": false, "reason": "invalid_worker_state"}
	if unit.get_current_order() is RecoveryOrder and unit.get_current_order().is_active():
		return {"ok": false, "reason": "recovery_order_active"}
	var world := unit.get_world_3d()
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var authority := domains.get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
	if authority == null:
		return {"ok": true, "reason": ""}
	if authority.has_active_operation():
		return {"ok": false, "reason": "transaction_in_progress"}
	var uid := unit.get_carry_load().get_provenance_unit_id()
	for record: ReservedWithdrawalCoordinator.CancellationCustodyRecord in authority.cancellation_custodies.values():
		if record == null or not ReservedWithdrawalCoordinator.validate_custody_accounting_pure(record).ok:
			return {"ok": false, "reason": "invalid_cancellation_custody"}
		if record.get_obligation_status() != &"settled" and (record.assigned_unit_ids.has(uid) or record.recovery_unit_ids.has(uid) or record.transit_lots_by_unit.has(uid)):
			return {"ok": false, "reason": "pending_cancellation_custody"}
	return {"ok": true, "reason": ""}
