class_name CampDeliveryTransferSession
extends RefCounted
## Transactional intent session for one opt-in selective camp delivery order.
## Preserves frozen participant identity, normalized lot selection, regional operation_id,
## bounded busy retries, uncertain-outcome receipt reconciliation, and cancellation locks.
## Coordinators own all economic mutations.

const Planner = preload("res://src/economy/selective_camp_delivery_planner.gd")
const TxHelpers = preload("res://src/economy/selective_camp_delivery_tx_helpers.gd")

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

var _coordinator := SelectiveCampDeliveryCoordinator.new()
var _domain_allocator := ReservedWithdrawalCoordinator.new()
var _identity: Array = []
var _operation_id: StringName = &""
var _requested_lots: Array[Dictionary] = []
var _busy_retries: int = 0
var _retry_remaining: float = 0.0
var _final_result: Dictionary = {}
var _cancelled: bool = false


func get_operation_id() -> StringName:
	return _operation_id


func get_requested_lots() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for item: Dictionary in _requested_lots:
		copy.append(item.duplicate(true))
	return copy


func get_busy_retries() -> int:
	return _busy_retries


func get_final_result() -> Dictionary:
	return _final_result.duplicate(true)


func is_retry_scheduled() -> bool:
	return state == State.RETRY_SCHEDULED


func is_closed() -> bool:
	return _cancelled or state == State.SUCCEEDED or state == State.FAILED or state == State.CANCELLED


func retry_is_due(delta: float) -> bool:
	if state != State.RETRY_SCHEDULED:
		return false
	_retry_remaining -= maxf(delta, 0.0)
	return _retry_remaining <= 0.0


## Freezes the normalized lot selection and participant identity at order admission.
## Never mutates economic state, never creates a RegionalAuthority, and never allocates a serial.
func initialize_intent(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	order_id: int,
	requested_lots: Variant
) -> Dictionary:
	if is_closed() or state != State.IDLE:
		return _failure("intent_already_initialized", "session")
	if not CarryProvenanceLedger._id(region_id):
		return _failure("invalid_region", "session")
	var parsed: Dictionary = Planner._parse_lot_request(requested_lots, &"c3.4.3_intent_parse")
	if not bool(parsed.get("ok", false)):
		return _failure(String(parsed.get("reason", "invalid_request")), "preparation")
	var id_res: Dictionary = _build_live_identity(inventory, camp_zone, unit, StringName(region_id), order_id)
	if not bool(id_res.get("ok", false)):
		return id_res

	_identity = id_res["identity"] as Array
	_requested_lots.clear()
	for entry: Dictionary in (parsed["requests"] as Array[Dictionary]):
		_requested_lots.append(entry.duplicate(true))
	state = State.READY
	return {"ok": true, "reason": "", "dependency": ""}


## Pure read-only preflight via SelectiveCampDeliveryPlanner plus callback checks.
## Uses a non-colliding synthetic probe ID and never creates a RegionalAuthority or allocates a serial.
static func probe_preflight(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	requested_lots: Variant
) -> Dictionary:
	if inventory == null:
		return _failure("invalid_inventory", "preparation")
	var storage := inventory.get_storage_source() as GroundPileManager
	if storage == null:
		return _failure("unsupported_storage_source", "storage")
	if storage.pile_creator_override.is_valid() or not storage.pile_creator_override.is_null():
		return _failure("unsafe_pile_creator_override", "storage")
	var probe_op: StringName = _build_non_colliding_probe_op(unit, region_id)
	return Planner.prepare_selective_camp_delivery(inventory, camp_zone, unit, region_id, probe_op, requested_lots)


## Pure provenance-based cargo inspection for opt-in ConstructOrder.
## Never uses aggregate resource totals as authorization to select lots.
## Separates usable lots for `site`, eligible camp-returnable lots, and non-returnable residual lots.
static func inspect_cargo_for_construction_site(
	site: ConstructionSite,
	camp_zone: CampStorageZone,
	unit: Unit,
	carry_load: UnitCarryLoad,
	allow_other_active_site_reserved: bool = false
) -> Dictionary:
	var empty_result: Dictionary = {
		"has_usable_for_site": false,
		"other_site_return_required": false,
		"returnable_requests": [] as Array[Dictionary],
		"has_non_returnable": false,
		"blocking_reason": "",
		"preflight_fatal_reason": "",
	}
	if carry_load == null or carry_load.is_empty():
		return empty_result
	if site == null or not is_instance_valid(site) or unit == null or not is_instance_valid(unit):
		empty_result["has_non_returnable"] = true
		empty_result["blocking_reason"] = "invalid_site"
		return empty_result
	if not carry_load.is_provenance_enabled() or not carry_load.validate_provenance():
		empty_result["has_non_returnable"] = true
		empty_result["blocking_reason"] = "unreconciled_cargo"
		return empty_result

	var snap: Dictionary = carry_load.provenance_snapshot()
	var ledger_dict: Dictionary = snap.get("ledger", {}) as Dictionary
	var lots: Dictionary = ledger_dict.get("lots", {}) as Dictionary
	var site_claim: Dictionary = site._read_transit_claim_for_unit_pure(unit.get_instance_id())

	var has_usable_for_site: bool = false
	var has_non_returnable: bool = false
	var blocking_reason: String = ""
	var preflight_fatal_reason: String = ""
	var other_site_return_required := false
	var free_candidates: Array[Dictionary] = []
	var other_site_candidates: Array[Dictionary] = []

	for lot_id: StringName in Planner._sorted_string_names(lots.keys()):
		var lot: Dictionary = lots[lot_id] as Dictionary
		var origin: StringName = StringName(lot.get("origin", &""))
		var res_id: StringName = StringName(lot.get("resource_id", &""))
		var qty: int = int(lot.get("quantity", 0))
		if qty <= 0:
			continue
		if origin == CarryProvenanceLedger.SITE_RESERVED:
			var lot_site_id: StringName = StringName(lot.get("site_id", &""))
			if lot_site_id == site.site_id:
				if int(site_claim.get(res_id, 0)) > 0 and site.get_remaining_need_for_dropoff(res_id) > 0:
					has_usable_for_site = true
				else:
					has_non_returnable = true
					if blocking_reason.is_empty():
						if int(lot.get("generation", 0)) != site.get_generation():
							blocking_reason = "generation_mismatch"
						else:
							blocking_reason = "unreconciled_site_claim"
			else:
				other_site_candidates.append({"lot_id": lot_id, "amount": qty})
		elif origin == CarryProvenanceLedger.FREE_GATHERED:
			free_candidates.append({"lot_id": lot_id, "amount": qty})
		else:
			has_non_returnable = true
			if blocking_reason.is_empty():
				blocking_reason = "invalid_ledger"

	var inventory: SettlementInventory = site.get_inventory()
	var region: StringName = site.region_id
	var has_valid_camp: bool = (
		camp_zone != null
		and is_instance_valid(camp_zone)
		and camp_zone.is_valid()
		and inventory != null
	)
	var selected_requests: Array[Dictionary] = []

	for entry: Dictionary in other_site_candidates:
		if not allow_other_active_site_reserved:
			has_non_returnable = true
			if blocking_reason.is_empty():
				if has_valid_camp:
					var probe_cons: Dictionary = probe_preflight(inventory, camp_zone, unit, region, [entry])
					if bool(probe_cons.get("ok", false)) or String(probe_cons.get("reason", "")) == "busy":
						blocking_reason = "selective_camp_delivery_required"
					else:
						blocking_reason = String(probe_cons.get("reason", "selective_camp_delivery_required"))
				else:
					blocking_reason = "selective_camp_delivery_required"
			continue

		if not has_valid_camp:
			has_non_returnable = true
			if blocking_reason.is_empty():
				blocking_reason = "unneeded_cargo_rejected"
			continue
		var probe_other: Dictionary = probe_preflight(inventory, camp_zone, unit, region, [entry])
		var other_reason: String = String(probe_other.get("reason", ""))
		if bool(probe_other.get("ok", false)) or other_reason == "busy":
			other_site_return_required = true
			selected_requests.append(entry)
		else:
			has_non_returnable = true
			if blocking_reason.is_empty():
				blocking_reason = other_reason if not other_reason.is_empty() else "unneeded_cargo_rejected"
			if preflight_fatal_reason.is_empty() and _is_fatal_camp_preflight_reason(other_reason):
				preflight_fatal_reason = other_reason
				other_site_return_required = true

	for free_entry: Dictionary in free_candidates:
		selected_requests.append(free_entry)

	selected_requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["lot_id"]) < String(b["lot_id"]))

	var returnable_requests: Array[Dictionary] = []
	if not selected_requests.is_empty():
		if not has_valid_camp:
			has_non_returnable = true
			preflight_fatal_reason = "unneeded_cargo_rejected"
			if blocking_reason.is_empty():
				blocking_reason = "unneeded_cargo_rejected"
		else:
			var combined: Dictionary = probe_preflight(inventory, camp_zone, unit, region, selected_requests)
			var combined_reason: String = String(combined.get("reason", ""))
			if bool(combined.get("ok", false)) or combined_reason == "busy":
				returnable_requests = selected_requests
			else:
				has_non_returnable = true
				preflight_fatal_reason = combined_reason if not combined_reason.is_empty() else "unneeded_cargo_rejected"
				if blocking_reason.is_empty():
					blocking_reason = preflight_fatal_reason

	return {
		"has_usable_for_site": has_usable_for_site,
		"other_site_return_required": other_site_return_required,
		"returnable_requests": returnable_requests,
		"has_non_returnable": has_non_returnable,
		"blocking_reason": blocking_reason,
		"preflight_fatal_reason": preflight_fatal_reason,
	}


static func _is_fatal_camp_preflight_reason(reason: String) -> bool:
	return reason in [
		"unsafe_custom_position_validator",
		"unsafe_pile_creator_override",
		"no_valid_camp_slot",
		"navigation_not_ready",
		"region_mismatch",
		"world_mismatch",
		"invalid_camp_zone",
		"invalid_piles_root",
		"unsupported_storage_source",
		"invalid_physical_pile_collection",
	]


func execute_or_retry(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	order_id: int
) -> Dictionary:
	if _cancelled or state == State.CANCELLED:
		return _failure("order_cancelled", "session")
	if state == State.SUCCEEDED or state == State.FAILED:
		return _failure("intent_already_closed", "session")
	if is_executing:
		return _failure("busy", "session")

	is_executing = true
	state = State.EXECUTING
	var result: Dictionary = _execute_locked(inventory, camp_zone, unit, region_id, order_id)
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
			_final_result = _failure("busy_retry_exhausted", "coordinator")
			return _final_result.duplicate(true)
		_busy_retries += 1
		_retry_remaining = RETRY_INTERVAL_SEC
		state = State.RETRY_SCHEDULED
		return result

	state = State.FAILED
	_final_result = result.duplicate(true)
	return result


## Permanently cancels an uncommitted intent. If the frozen operation_id was already committed
## (e.g., externally during a busy window), returns and preserves the committed receipt without
## issuing any new commit.
func cancel_intent(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant
) -> Dictionary:
	if state == State.SUCCEEDED:
		return (_final_result.get("receipt", {}) as Dictionary).duplicate(true)
	_cancelled = true
	state = State.CANCELLED
	_retry_remaining = 0.0
	if _operation_id.is_empty():
		return {}
	var receipt: Dictionary = _lookup_committed_receipt(unit, region_id)
	if receipt.is_empty():
		return {}
	if not _receipt_matches_cancel_participants(receipt, inventory, camp_zone, unit, region_id):
		return {}
	_final_result = {
		"ok": true,
		"reason": "",
		"dependency": "",
		"replayed": true,
		"delivered_now": 0,
		"delivered_amounts": (receipt.get("delivered_amounts", {}) as Dictionary).duplicate(true),
		"created_pile_ids": (receipt.get("created_pile_ids", []) as Array).duplicate(),
		"receipt": receipt.duplicate(true),
	}
	return receipt


func _execute_locked(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	order_id: int
) -> Dictionary:
	if not CarryProvenanceLedger._id(region_id):
		return _failure("invalid_region", "session")
	var region := StringName(region_id)
	var id_res: Dictionary = _build_live_identity(inventory, camp_zone, unit, region, order_id)
	if not bool(id_res.get("ok", false)):
		return id_res
	var live_identity: Array = id_res["identity"] as Array
	if _identity.is_empty():
		_identity = live_identity
	elif _identity != live_identity:
		return _failure("transaction_identity_changed", "session")

	var storage: GroundPileManager = inventory.get_storage_source() as GroundPileManager
	var world: World3D = unit.get_world_3d()
	var load: UnitCarryLoad = unit.get_carry_load()

	# If our frozen operation_id was already committed, let the coordinator verify & replay it directly.
	var already_committed: bool = not _operation_id.is_empty() and not _lookup_committed_receipt(unit, region).is_empty()
	if not already_committed:
		var phys_check: Dictionary = TxHelpers.check_physical_authorization_participants(
			unit, load, camp_zone, storage, world
		)
		if not bool(phys_check.get("ok", false)):
			return _failure(
				String(phys_check.get("reason", "out_of_camp_dropoff_range")),
				String(phys_check.get("dependency", "authorization"))
			)

	if _operation_id.is_empty():
		var alloc: Dictionary = _domain_allocator._allocate_camp_delivery_operation_id(
			inventory, camp_zone, unit, region, order_id
		)
		if not bool(alloc.get("ok", false)):
			return _failure(String(alloc.get("reason", "invalid_domain")), String(alloc.get("dependency", "coordinator")))
		_operation_id = alloc["operation_id"] as StringName

	var result: Variant = _invoke_coordinator(inventory, camp_zone, unit, region)
	if result is Dictionary and typeof((result as Dictionary).get("ok")) == TYPE_BOOL:
		return result as Dictionary

	# Uncertain outcome: consult receipt for the original operation_id and replay idempotently if present.
	# Never allocate a second operation_id for a potentially committed transfer.
	var receipt: Dictionary = _lookup_committed_receipt(unit, region)
	if not receipt.is_empty():
		var replay: Variant = _invoke_coordinator(inventory, camp_zone, unit, region)
		if replay is Dictionary:
			var replay_dict: Dictionary = replay as Dictionary
			if bool(replay_dict.get("ok", false)) and bool(replay_dict.get("replayed", false)):
				return replay_dict
	return _failure("unknown_transaction_outcome", "coordinator")


## Virtual indirection so adversarial tests can simulate an uncertain coordinator response
## via a test subclass without exposing mutable test callbacks in production.
func _invoke_coordinator(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region: StringName
) -> Dictionary:
	return _coordinator.execute_selective_camp_delivery(
		inventory, camp_zone, unit, region, _operation_id, _requested_lots
	)


func _lookup_committed_receipt(unit: Unit, region_id: Variant) -> Dictionary:
	if _operation_id.is_empty():
		return {}
	var direct: Dictionary = _coordinator.get_receipt(_operation_id)
	if not direct.is_empty():
		return direct
	if is_instance_valid(unit) and unit.is_inside_tree():
		var world: World3D = unit.get_world_3d()
		if world != null:
			return _coordinator.get_receipt_in_domain(world, region_id, _operation_id)
	return {}


static func _receipt_matches_cancel_participants(
	receipt: Dictionary,
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant
) -> bool:
	if receipt.is_empty() or not (receipt.get("identity") is Dictionary):
		return false
	if inventory == null or camp_zone == null or not is_instance_valid(camp_zone) or unit == null or not is_instance_valid(unit):
		return false
	var load := unit.get_carry_load()
	var storage := inventory.get_storage_source() as GroundPileManager
	if load == null or storage == null or not unit.is_inside_tree() or unit.get_world_3d() == null:
		return false
	var id: Dictionary = receipt["identity"] as Dictionary
	return (
		int(id.get("world", 0)) == unit.get_world_3d().get_instance_id()
		and StringName(id.get("region_id", &"")) == StringName(region_id)
		and int(id.get("inventory", 0)) == inventory.get_instance_id()
		and int(id.get("storage", 0)) == storage.get_instance_id()
		and int(id.get("camp_zone", 0)) == camp_zone.get_instance_id()
		and int(id.get("unit", 0)) == unit.get_instance_id()
		and int(id.get("load", 0)) == load.get_instance_id()
	)


static func _build_live_identity(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region: StringName,
	order_id: int
) -> Dictionary:
	if order_id == 0:
		return _failure("invalid_order", "session")
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _failure("invalid_unit", "authorization")
	var world: World3D = unit.get_world_3d()
	if world == null:
		return _failure("invalid_domain", "authorization")
	if inventory == null:
		return _failure("invalid_inventory", "authorization")
	var storage := inventory.get_storage_source() as GroundPileManager
	if storage == null:
		return _failure("unsupported_storage_source", "storage")
	if (
		camp_zone == null
		or not is_instance_valid(camp_zone)
		or not camp_zone.is_inside_tree()
		or camp_zone.is_queued_for_deletion()
		or not camp_zone.is_valid()
	):
		return _failure("invalid_camp_zone", "camp_zone")
	if camp_zone.get_world_3d() != world:
		return _failure("world_mismatch", "camp_zone")
	if storage.get_camp_zone() != camp_zone:
		return _failure("invalid_camp_zone", "camp_zone")
	var load := unit.get_carry_load()
	if load == null or not load.is_provenance_enabled() or not CarryProvenanceLedger._id(load.get_provenance_unit_id()):
		return _failure("provenance_disabled", "carry_load")
	return {
		"ok": true,
		"identity": [
			world.get_instance_id(),
			region,
			inventory.get_instance_id(),
			storage.get_instance_id(),
			camp_zone.get_instance_id(),
			camp_zone.zone_id,
			unit.get_instance_id(),
			load.get_instance_id(),
			load.get_provenance_unit_id(),
			order_id,
		],
	}


static func _build_non_colliding_probe_op(unit: Unit, region_id: Variant) -> StringName:
	var base := "c3.4.3:probe"
	var op := StringName(base)
	var load: UnitCarryLoad = unit.get_carry_load() if is_instance_valid(unit) else null
	var ledger: CarryProvenanceLedger = load._provenance if load != null else null
	var authority: ReservedWithdrawalCoordinator.RegionalAuthority = null
	if is_instance_valid(unit) and unit.is_inside_tree() and unit.get_world_3d() != null and CarryProvenanceLedger._id(region_id):
		var domains: Dictionary = unit.get_world_3d().get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
		authority = domains.get(StringName(region_id)) as ReservedWithdrawalCoordinator.RegionalAuthority
	var suffix: int = 0
	while (ledger != null and ledger._operations.has(op)) or (authority != null and authority.receipts.has(op)):
		suffix += 1
		op = StringName("%s:%d" % [base, suffix])
	return op


static func _failure(reason: String, dependency: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"dependency": dependency,
		"replayed": false,
		"delivered_now": 0,
		"delivered_amounts": {},
		"created_pile_ids": [],
		"receipt": {},
	}
