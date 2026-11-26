class_name GatherTransferSession
extends RefCounted
## Transactional intent session for one opt-in gather extraction cycle.
## Freezes participant identity, requested amount, regional operation_id, and FREE_GATHERED lot_id;
## handles bounded busy retries, uncertain-outcome receipt reconciliation against ResourceSource,
## and permanent cancellation locks without creating a parallel economic authority.

enum State {
	IDLE,
	READY,
	EXECUTING,
	RETRY_SCHEDULED,
	SUCCEEDED,
	FAILED,
	CANCELLED,
}

const RETRY_INTERVAL_SEC: float = ConstructionTransferSession.RETRY_INTERVAL_SEC
const MAX_BUSY_RETRIES: int = ConstructionTransferSession.MAX_BUSY_RETRIES

var state: State = State.IDLE
var is_executing: bool = false

var _domain_allocator := ReservedWithdrawalCoordinator.new()
var _identity: Array = []
var _operation_id: StringName = &""
var _lot_id: StringName = &""
var _requested_amount: int = 0
var _cycle_index: int = 0
var _busy_retries: int = 0
var _retry_remaining: float = 0.0
var _final_result: Dictionary = {}
var _cancelled: bool = false
var _outcome_uncertain: bool = false


func get_operation_id() -> StringName:
	return _operation_id


func get_lot_id() -> StringName:
	return _lot_id


func get_requested_amount() -> int:
	return _requested_amount


func get_cycle_index() -> int:
	return _cycle_index


func get_busy_retries() -> int:
	return _busy_retries


func get_final_result() -> Dictionary:
	return _final_result.duplicate(true)


func is_retry_scheduled() -> bool:
	return state == State.RETRY_SCHEDULED


func is_outcome_uncertain() -> bool:
	return _outcome_uncertain


func is_closed() -> bool:
	return _cancelled or state == State.SUCCEEDED or state == State.FAILED or state == State.CANCELLED


func retry_is_due(delta: float) -> bool:
	if state != State.RETRY_SCHEDULED:
		return false
	_retry_remaining -= maxf(delta, 0.0)
	return _retry_remaining <= 0.0


## Freezes the cycle intent and participant identity without mutating economic state,
## creating a RegionalAuthority, or consuming a regional serial.
func initialize_cycle(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	source: ResourceSource,
	unit: Unit,
	region_id: Variant,
	order_id: int,
	cycle_index: int,
	requested_amount: int
) -> Dictionary:
	if is_closed() or state != State.IDLE:
		return _failure("intent_already_initialized", "session")
	if not CarryProvenanceLedger._id(region_id):
		return _failure("invalid_region", "session")
	if cycle_index <= 0:
		return _failure("invalid_cycle", "session")
	if requested_amount <= 0:
		return _failure("invalid_input", "session")

	var id_res: Dictionary = _build_live_identity(
		inventory, camp_zone, source, unit, StringName(region_id), order_id, cycle_index
	)
	if not bool(id_res.get("ok", false)):
		return id_res
	if _wood_is_before_fall(source):
		return _failure("tree_not_felled", "source")

	_identity = id_res["identity"] as Array
	_cycle_index = cycle_index
	_requested_amount = requested_amount
	state = State.READY
	return {"ok": true, "reason": "", "dependency": ""}


func execute_or_retry(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	source: ResourceSource,
	unit: Unit,
	region_id: Variant,
	order_id: int,
	in_working_range: bool
) -> Dictionary:
	if _cancelled or state == State.CANCELLED:
		return _failure("order_cancelled", "session")
	if state == State.SUCCEEDED or state == State.FAILED:
		return _failure("intent_already_closed", "session")
	if is_executing:
		return _failure("busy", "session")

	is_executing = true
	state = State.EXECUTING
	var result: Dictionary = _execute_locked(
		inventory, camp_zone, source, unit, region_id, order_id, in_working_range
	)
	is_executing = false

	if _cancelled:
		state = State.CANCELLED
		return result

	if bool(result.get("ok", false)):
		state = State.SUCCEEDED
		_final_result = result.duplicate(true)
		return result

	if String(result.get("reason", "")) == "busy":
		if _busy_retries >= MAX_BUSY_RETRIES:
			state = State.FAILED
			_final_result = _failure("busy_retry_exhausted", "source")
			return _final_result.duplicate(true)
		_busy_retries += 1
		_retry_remaining = RETRY_INTERVAL_SEC
		state = State.RETRY_SCHEDULED
		return result

	state = State.FAILED
	_final_result = result.duplicate(true)
	return result


## Permanently cancels an uncommitted cycle. If the frozen operation_id was already
## committed on ResourceSource, recognizes and returns its receipt without mutating stock.
func cancel_intent(source: ResourceSource, unit: Unit) -> Dictionary:
	if state == State.SUCCEEDED:
		return (_final_result.get("receipt", {}) as Dictionary).duplicate(true)
	_cancelled = true
	state = State.CANCELLED
	_retry_remaining = 0.0
	if _operation_id.is_empty():
		return {}
	if source == null or not is_instance_valid(source) or unit == null or not is_instance_valid(unit):
		return {}
	var load: UnitCarryLoad = unit.get_carry_load()
	if load == null:
		return {}
	var rec: Dictionary = source.get_provenance_receipt(_operation_id)
	if not _receipt_matches_session(rec, source, load):
		return {}
	_final_result = {
		"ok": true,
		"reason": "",
		"dependency": "",
		"replayed": true,
		"extracted": 0,
		"committed_amount": int(rec.get("committed_amount", 0)),
		"operation_id": _operation_id,
		"lot_id": _lot_id,
		"receipt": rec.duplicate(true),
	}
	return rec


func _execute_locked(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	source: ResourceSource,
	unit: Unit,
	region_id: Variant,
	order_id: int,
	in_working_range: bool
) -> Dictionary:
	if not CarryProvenanceLedger._id(region_id):
		return _failure("invalid_region", "session")
	if _outcome_uncertain:
		return _failure("unknown_transaction_outcome", "source")
	if _cycle_index <= 0 or _requested_amount <= 0:
		return _failure("invalid_input", "session")

	var region := StringName(region_id)
	var id_res: Dictionary = _build_live_identity(
		inventory, camp_zone, source, unit, region, order_id, _cycle_index
	)
	if not bool(id_res.get("ok", false)):
		return id_res

	var live_identity: Array = id_res["identity"] as Array
	if _identity.is_empty():
		_identity = live_identity
	elif _identity != live_identity:
		return _failure("transaction_identity_changed", "session")

	var load: UnitCarryLoad = unit.get_carry_load()
	var existing_receipt: Dictionary = {}
	if not _operation_id.is_empty():
		existing_receipt = source.get_provenance_receipt(_operation_id)

	if existing_receipt.is_empty():
		if not source.is_available():
			var unavail_reason: String = "source_depleted" if source.is_depleted() else "invalid_source"
			return _failure(unavail_reason, "source")
		if _wood_is_before_fall(source):
			return _failure("tree_not_felled", "source")
		if not in_working_range:
			return _failure("out_of_gather_range", "authorization")
		if _operation_id.is_empty():
			var alloc: Dictionary = _domain_allocator._allocate_gather_operation_ids(
				inventory, camp_zone, source, unit, region, order_id, _cycle_index
			)
			if not bool(alloc.get("ok", false)):
				return _failure(
					String(alloc.get("reason", "invalid_domain")),
					String(alloc.get("dependency", "coordinator"))
				)
			_operation_id = alloc["operation_id"] as StringName
			_lot_id = alloc["lot_id"] as StringName
		else:
			var world: World3D = unit.get_world_3d()
			if ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, region):
				return _failure("busy", "coordinator")
			var storage: GroundPileManager = inventory.get_storage_source() as GroundPileManager
			var domain_probe: Dictionary = ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(
				world, region, inventory, storage, _operation_id, unit.get_tree()
			)
			if not bool(domain_probe.get("ok", false)):
				return _failure(
					String(domain_probe.get("reason", "invalid_domain")),
					String(domain_probe.get("dependency", "coordinator"))
				)
	elif not _receipt_matches_session(existing_receipt, source, load):
		return _failure("operation_conflict", "receipt")

	var raw_result: Variant = _invoke_source_transfer(source, load)
	if raw_result is Dictionary:
		var res_dict: Dictionary = raw_result as Dictionary
		if typeof(res_dict.get("ok")) == TYPE_BOOL:
			if not bool(res_dict.get("ok", false)):
				return {
					"ok": false,
					"reason": String(res_dict.get("reason", "transfer_rejected")),
					"dependency": "source",
					"replayed": false,
					"extracted": 0,
					"committed_amount": 0,
					"operation_id": _operation_id,
					"lot_id": _lot_id,
					"receipt": {},
				}
			var replayed: bool = bool(res_dict.get("replayed", false))
			var extracted: int = int(res_dict.get("extracted", 0))
			var committed_amt: int = int(res_dict.get("committed_amount", extracted))
			var rec_now: Dictionary = source.get_provenance_receipt(_operation_id)
			if rec_now.is_empty() or not _receipt_matches_session(rec_now, source, load):
				_outcome_uncertain = true
				return _failure("unknown_transaction_outcome", "source")
			if replayed and extracted != 0:
				return _failure("operation_conflict", "receipt")
			return {
				"ok": true,
				"reason": "",
				"dependency": "",
				"replayed": replayed,
				"extracted": extracted,
				"committed_amount": committed_amt,
				"operation_id": _operation_id,
				"lot_id": _lot_id,
				"receipt": rec_now.duplicate(true),
			}

	# Uncertain outcome: consult ResourceSource receipt for the frozen operation_id and replay idempotently.
	# Never allocate a second operation_id or lot_id when commit outcome is ambiguous.
	_outcome_uncertain = true
	if source != null and is_instance_valid(source) and source.is_inside_tree() and load != null:
		var rec_after: Dictionary = source.get_provenance_receipt(_operation_id)
		if _receipt_matches_session(rec_after, source, load):
			var replay_raw: Variant = _invoke_source_transfer(source, load)
			if replay_raw is Dictionary:
				var replay_dict: Dictionary = replay_raw as Dictionary
				if bool(replay_dict.get("ok", false)) and bool(replay_dict.get("replayed", false)) and int(replay_dict.get("extracted", 0)) == 0:
					_outcome_uncertain = false
					return {
						"ok": true,
						"reason": "",
						"dependency": "",
						"replayed": true,
						"extracted": 0,
						"committed_amount": int(replay_dict.get("committed_amount", rec_after.get("committed_amount", 0))),
						"operation_id": _operation_id,
						"lot_id": _lot_id,
						"receipt": rec_after.duplicate(true),
					}
	return _failure("unknown_transaction_outcome", "source")


static func _wood_is_before_fall(source: ResourceSource) -> bool:
	return (
		source.get_category() == ResourceDefinition.Category.WOOD
		and source.get_tree_harvest_stage() < ResourceSource.TreeHarvestStage.FALLEN
	)


## Virtual indirection so adversarial tests can simulate an uncertain source response
## via a test subclass without exposing mutable test callbacks in production.
func _invoke_source_transfer(source: ResourceSource, carry_load: UnitCarryLoad) -> Dictionary:
	return source.transfer_to_carry_load_with_provenance(
		carry_load, _operation_id, _lot_id, _requested_amount
	)


func _receipt_matches_session(rec: Dictionary, source: ResourceSource, load: UnitCarryLoad) -> bool:
	if rec.is_empty() or source == null or not is_instance_valid(source) or load == null:
		return false
	var def: ResourceDefinition = source.get_definition()
	if def == null or not def.is_valid():
		return false
	return (
		StringName(rec.get("operation_id", &"")) == _operation_id
		and StringName(rec.get("lot_id", &"")) == _lot_id
		and int(rec.get("requested_amount", 0)) == _requested_amount
		and StringName(rec.get("source_id", &"")) == source.source_id
		and StringName(rec.get("resource_id", &"")) == def.resource_id
		and int(rec.get("unit_weight", 0)) == def.unit_weight
		and int(rec.get("carry_load_instance_id", 0)) == load.get_instance_id()
	)


static func _build_live_identity(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	source: ResourceSource,
	unit: Unit,
	region: StringName,
	order_id: int,
	cycle_index: int
) -> Dictionary:
	if order_id == 0:
		return _static_failure("invalid_order", "session")
	if cycle_index <= 0:
		return _static_failure("invalid_cycle", "session")
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _static_failure("invalid_unit", "authorization")
	var world: World3D = unit.get_world_3d()
	if world == null:
		return _static_failure("invalid_domain", "authorization")
	if (
		source == null
		or not is_instance_valid(source)
		or not source.is_inside_tree()
		or source.is_queued_for_deletion()
	):
		return _static_failure("invalid_source", "source")
	if source.get_world_3d() != world:
		return _static_failure("world_mismatch", "source")
	var source_def: ResourceDefinition = source.get_definition()
	if source_def == null or not source_def.is_valid() or not CarryProvenanceLedger._id(source.source_id):
		return _static_failure("invalid_source", "source")
	if inventory == null:
		return _static_failure("invalid_inventory", "authorization")
	var storage := inventory.get_storage_source() as GroundPileManager
	if storage == null:
		return _static_failure("unsupported_storage_source", "storage")
	if (
		camp_zone == null
		or not is_instance_valid(camp_zone)
		or not camp_zone.is_inside_tree()
		or camp_zone.is_queued_for_deletion()
		or not camp_zone.is_valid()
	):
		return _static_failure("invalid_camp_zone", "camp_zone")
	if camp_zone.get_world_3d() != world:
		return _static_failure("world_mismatch", "camp_zone")
	if storage.get_camp_zone() != camp_zone:
		return _static_failure("invalid_camp_zone", "camp_zone")
	var load := unit.get_carry_load()
	if load == null or not load.is_provenance_enabled() or not CarryProvenanceLedger._id(load.get_provenance_unit_id()):
		return _static_failure("provenance_disabled", "carry_load")
	var id_check: Dictionary = ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(
		world, region, unit, load, unit.get_tree()
	)
	if not bool(id_check.get("ok", false)):
		return _static_failure(String(id_check.get("reason", "ambiguous_unit_identity")), String(id_check.get("dependency", "unit")))
	return {
		"ok": true,
		"identity": [
			world.get_instance_id(),
			region,
			inventory.get_instance_id(),
			storage.get_instance_id(),
			camp_zone.get_instance_id(),
			camp_zone.zone_id,
			source.get_instance_id(),
			source.source_id,
			source_def.resource_id,
			source_def.unit_weight,
			unit.get_instance_id(),
			load.get_instance_id(),
			load.get_provenance_unit_id(),
			order_id,
			cycle_index,
		],
	}


func _failure(reason: String, dependency: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"dependency": dependency,
		"replayed": false,
		"extracted": 0,
		"committed_amount": 0,
		"operation_id": _operation_id,
		"lot_id": _lot_id,
		"receipt": {},
	}


static func _static_failure(reason: String, dependency: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"dependency": dependency,
		"replayed": false,
		"extracted": 0,
		"committed_amount": 0,
		"operation_id": &"",
		"lot_id": &"",
		"receipt": {},
	}
