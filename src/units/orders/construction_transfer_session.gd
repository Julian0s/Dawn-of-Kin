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
var _identity: Array = []
var _operation_id: StringName
var _lot_id: StringName
var _pile_id: int
var _resource_id: StringName
var _amount: int
var _busy_retries: int
var _retry_remaining: float


func withdraw(site: ConstructionSite, unit: Unit, order_id: int, pile_id: int, resource_id: StringName, amount: int) -> Dictionary:
	_pile_id = pile_id
	_resource_id = resource_id
	_amount = amount
	return _execute(site, unit, order_id, Kind.WITHDRAWAL)


func deliver(site: ConstructionSite, unit: Unit, order_id: int) -> Dictionary:
	return _execute(site, unit, order_id, Kind.DELIVERY)


func retry_is_due(delta: float) -> bool:
	_retry_remaining -= delta
	return _retry_remaining <= 0.0


func retry(site: ConstructionSite, unit: Unit, order_id: int) -> Dictionary:
	return _execute(site, unit, order_id, retry_kind)


func _execute(site: ConstructionSite, unit: Unit, order_id: int, kind: Kind) -> Dictionary:
	if is_executing:
		return {"ok": false, "reason": "busy"}
	is_executing = true
	var result := _execute_intent(site, unit, order_id, kind)
	is_executing = false
	if result.get("reason") == "busy":
		if _busy_retries >= MAX_BUSY_RETRIES:
			return {"ok": false, "reason": "busy_retry_exhausted"}
		_busy_retries += 1
		_retry_remaining = RETRY_INTERVAL_SEC
		retry_kind = kind
		return result
	clear()
	return result


func _execute_intent(site: ConstructionSite, unit: Unit, order_id: int, kind: Kind) -> Dictionary:
	var world := site.get_world_3d()
	var load := unit.get_carry_load()
	if world == null or unit.get_world_3d() != world or load == null:
		return {"ok": false, "reason": "invalid_domain"}
	var identity := [world.get_instance_id(), site.region_id, site.get_instance_id(), site.site_id,
		site.get_generation(), site.reservation_id, unit.get_instance_id(), load.get_instance_id(),
		load.get_provenance_unit_id(), order_id, kind]
	if _identity.is_empty():
		_identity = identity
	elif _identity != identity:
		return {"ok": false, "reason": "transaction_identity_changed"}
	if _operation_id.is_empty():
		var stage := "withdrawal" if kind == Kind.WITHDRAWAL else "delivery"
		var ids := _withdrawal._allocate_construction_transfer_ids(site, unit, order_id, stage, _pile_id, _resource_id)
		if not ids.ok:
			return ids
		_operation_id = ids.operation_id
		_lot_id = ids.lot_id

	var result := _invoke_coordinator(site, unit, kind)
	if typeof(result.get("ok")) == TYPE_BOOL:
		return result
	# A missing outcome requires reconciliation of the original intent. The
	# same coordinator validates the receipt identity and returns a replay.
	var receipt := _withdrawal.get_receipt(_operation_id) if kind == Kind.WITHDRAWAL else _delivery.get_receipt(_operation_id)
	if not receipt.is_empty():
		var replay := _invoke_coordinator(site, unit, kind)
		if replay.get("ok", false) and replay.get("replayed", false):
			return replay
	return {"ok": false, "reason": "unknown_transaction_outcome"}


func _invoke_coordinator(site: ConstructionSite, unit: Unit, kind: Kind) -> Dictionary:
	if kind == Kind.WITHDRAWAL:
		return _withdrawal.execute_reserved_withdrawal(
			site, unit, _pile_id, _resource_id, _amount, _operation_id, _lot_id)
	return _delivery.execute_selective_site_delivery(site, unit, _operation_id)


func clear() -> void:
	retry_kind = Kind.NONE
	_identity.clear()
	_operation_id = &""
	_lot_id = &""
	_pile_id = 0
	_resource_id = &""
	_amount = 0
	_busy_retries = 0
	_retry_remaining = 0.0
