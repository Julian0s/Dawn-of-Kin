class_name ConstructionTransferSession
extends RefCounted
## Economic intents for one opt-in construction order. Coordinators own all mutations.

enum Kind { NONE, WITHDRAWAL, DELIVERY }

const RETRY_INTERVAL_SEC := 0.25
const MAX_BUSY_RETRIES := 4

var is_executing: bool = false
var retry_kind: Kind = Kind.NONE

var _withdrawal := ReservedWithdrawalCoordinator.new()
var _delivery := SelectiveSiteDeliveryCoordinator.new()
var _identity: Dictionary = {}
var _world: WeakRef
var _order_id: int
var _kind: Kind = Kind.NONE
var _operation_id: StringName
var _lot_id: StringName
var _pile_id: int
var _resource_id: StringName
var _amount: int
var _busy_retries: int
var _retry_remaining: float
var _closed: bool
var _outcome_uncertain: bool


func withdraw(site: ConstructionSite, unit: Unit, order_id: int, pile_id: int, resource_id: StringName, amount: int) -> Dictionary:
	return _execute(site, unit, order_id, Kind.WITHDRAWAL, pile_id, resource_id, amount)


func deliver(site: ConstructionSite, unit: Unit, order_id: int) -> Dictionary:
	return _execute(site, unit, order_id, Kind.DELIVERY)


func retry_is_due(delta: float) -> bool:
	if _closed or retry_kind == Kind.NONE or is_executing:
		return false
	_retry_remaining -= delta
	return _retry_remaining <= 0.0


func retry(site: ConstructionSite, unit: Unit, order_id: int) -> Dictionary:
	return _execute(site, unit, order_id, retry_kind, _pile_id, _resource_id, _amount, true)


func _execute(
	site: ConstructionSite, unit: Unit, order_id: int, kind: Kind,
	pile_id: int = 0, resource_id: StringName = &"", amount: int = 0, scheduled: bool = false
) -> Dictionary:
	if _closed:
		return {"ok": false, "reason": "order_cancelled"}
	if is_executing:
		return {"ok": false, "reason": "busy"}
	if kind == Kind.NONE:
		return {"ok": false, "reason": "no_pending_transfer"}
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return {"ok": false, "reason": "wrong_thread"}
	var identity := _read_identity(site, unit)
	if identity.is_empty():
		return {"ok": false, "reason": "invalid_domain"}
	if not _identity.is_empty():
		if _identity != identity or _order_id != order_id or _kind != kind \
			or _pile_id != pile_id or _resource_id != resource_id or _amount != amount:
			return {"ok": false, "reason": "transaction_identity_changed"}
	var order := unit.get_current_order()
	if order == null or not order.is_active() or order.get_instance_id() != order_id:
		return {"ok": false, "reason": "worker_order_not_eligible"}
	if retry_kind != Kind.NONE and (not scheduled or _retry_remaining > 0.0):
		return {"ok": false, "reason": "busy"}
	if _identity.is_empty():
		_identity = identity
		_world = weakref(site.get_world_3d())
		_order_id = order_id
		_kind = kind
		_pile_id = pile_id
		_resource_id = resource_id
		_amount = amount

	is_executing = true
	var result := _reconcile() if _outcome_uncertain else _execute_intent(site, unit)
	is_executing = false
	if result.get("reason") == "busy":
		if _busy_retries >= MAX_BUSY_RETRIES:
			cancel_intent()
			return {"ok": false, "reason": "busy_retry_exhausted"}
		_busy_retries += 1
		_retry_remaining = RETRY_INTERVAL_SEC
		retry_kind = kind
		return result
	if _outcome_uncertain and not result.get("ok", false):
		retry_kind = Kind.NONE
		return result
	_reset_intent()
	return result


static func _read_identity(site: ConstructionSite, unit: Unit) -> Dictionary:
	if not is_instance_valid(site) or not site.is_inside_tree() or site.is_queued_for_deletion() or not site.is_active():
		return {}
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return {}
	var world := site.get_world_3d()
	var load := unit.get_carry_load()
	var inventory := site.get_inventory()
	var storage := (inventory.get_storage_source() as GroundPileManager) if inventory != null else null
	if world == null or unit.get_world_3d() != world or load == null or storage == null:
		return {}
	# Same participant identity as a site delivery receipt. Order and withdrawal
	# payload are held separately and do not change between attempts.
	return {
		"world": world.get_instance_id(), "region_id": site.region_id,
		"site": site.get_instance_id(), "site_id": site.site_id,
		"generation": site.get_generation(), "reservation_id": site.reservation_id,
		"unit": unit.get_instance_id(), "load": load.get_instance_id(), "unit_id": load.get_provenance_unit_id(),
		"inventory": inventory.get_instance_id(), "storage": storage.get_instance_id(),
	}


func _execute_intent(site: ConstructionSite, unit: Unit) -> Dictionary:
	if _operation_id.is_empty():
		var stage := "withdrawal" if _kind == Kind.WITHDRAWAL else "delivery"
		var ids := _withdrawal._allocate_construction_transfer_ids(site, unit, _order_id, stage, _pile_id, _resource_id)
		if not ids.ok:
			return ids
		_operation_id = ids.operation_id
		_lot_id = ids.lot_id

	var result := _invoke_coordinator(site, unit, _kind)
	if typeof(result.get("ok")) == TYPE_BOOL:
		return result
	_outcome_uncertain = true
	return _reconcile()


func _reconcile() -> Dictionary:
	var receipt := _lookup_pending_receipt()
	if receipt.is_empty():
		return {"ok": false, "reason": "unknown_transaction_outcome"}
	# Confirmation of a prior commit is read-only, even if an observer has
	# invalidated the original participants since the coordinator published it.
	if _kind == Kind.WITHDRAWAL:
		return {"ok": true, "reason": "", "dependency": "", "replayed": true, "withdrawn": 0,
			"committed_amount": receipt.committed_amount, "receipt": receipt}
	return SelectiveSiteDeliveryCoordinator._success(receipt, true)


func _lookup_pending_receipt() -> Dictionary:
	if _world == null or _operation_id.is_empty():
		return {}
	var world := _world.get_ref() as World3D
	if world == null:
		return {}
	if _kind == Kind.DELIVERY:
		var delivery := _delivery.get_receipt_in_domain(world, _identity.region_id, _operation_id)
		if delivery.get("identity") == _identity and delivery.get("requested_amounts") == {}:
			return delivery
		return {}
	var withdrawal := _withdrawal.get_receipt_in_domain(world, _identity.region_id, _operation_id)
	if withdrawal.is_empty():
		return {}
	if withdrawal.site_instance_id != _identity.site or withdrawal.site_id != _identity.site_id \
		or withdrawal.generation != _identity.generation or withdrawal.reservation_id != _identity.reservation_id \
		or withdrawal.unit_instance_id != _identity.unit or withdrawal.carry_load_instance_id != _identity.load \
		or withdrawal.unit_id != _identity.unit_id or withdrawal.pile_id != _pile_id \
		or withdrawal.resource_id != _resource_id or withdrawal.requested_amount != _amount \
		or withdrawal.lot_id != _lot_id:
		return {}
	return withdrawal


func _invoke_coordinator(site: ConstructionSite, unit: Unit, kind: Kind) -> Dictionary:
	if kind == Kind.WITHDRAWAL:
		return _withdrawal.execute_reserved_withdrawal(
			site, unit, _pile_id, _resource_id, _amount, _operation_id, _lot_id)
	return _delivery.execute_selective_site_delivery(site, unit, _operation_id)


## Seal the order's session. A pending commit can still be inspected by ID,
## including after the original site or worker has left the scene.
func cancel_intent() -> Dictionary:
	if is_executing or OS.get_thread_caller_id() != OS.get_main_thread_id():
		return {}
	_closed = true
	retry_kind = Kind.NONE
	_retry_remaining = 0.0
	return _lookup_pending_receipt()


func _reset_intent() -> void:
	retry_kind = Kind.NONE
	_identity.clear()
	_world = null
	_order_id = 0
	_kind = Kind.NONE
	_outcome_uncertain = false
	_operation_id = &""
	_lot_id = &""
	_pile_id = 0
	_resource_id = &""
	_amount = 0
	_busy_retries = 0
	_retry_remaining = 0.0
