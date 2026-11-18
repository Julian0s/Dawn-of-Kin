class_name UnitCarryLoad
extends RefCounted
## Physical individual carry inventory for a unit.
## Uses integer arithmetic internally for quantities, unit weights, and capacity.

signal load_changed()
signal capacity_changed()

var _provenance: CarryProvenanceLedger = null
var _provenance_unit: StringName = &""
var _transaction_revision: int = 0
var _provenance_busy: bool = false
var _provenance_applying: bool = false

var _base_capacity: int = 0
var _capacity_modifiers: Dictionary = {}
var _amounts: Dictionary = {}
var _unit_weights: Dictionary = {}
var _batch_depth: int = 0
var _dirty_load: bool = false
var _dirty_capacity: bool = false


func _init(initial_base_capacity: int = 20) -> void:
	_base_capacity = maxi(0, initial_base_capacity)


func begin_batch() -> void:
	_batch_depth += 1


func end_batch(discard_load_dirty: bool = false) -> void:
	if _batch_depth <= 0:
		return
	_batch_depth -= 1
	if _batch_depth == 0:
		if _dirty_capacity:
			_dirty_capacity = false
			capacity_changed.emit()
		if discard_load_dirty:
			_dirty_load = false
		elif _dirty_load:
			_dirty_load = false
			load_changed.emit()


func _emit_load_changed() -> void:
	_transaction_revision += 1
	if _batch_depth > 0:
		_dirty_load = true
		return
	load_changed.emit()


func _emit_capacity_changed() -> void:
	_transaction_revision += 1
	if _batch_depth > 0:
		_dirty_capacity = true
		return
	capacity_changed.emit()


func get_base_capacity() -> int:
	return _base_capacity


func set_base_capacity(new_capacity: int) -> bool:
	if new_capacity < 0:
		return false
	if _base_capacity == new_capacity:
		return true
	_base_capacity = new_capacity
	_emit_capacity_changed()
	return true


func set_capacity_modifier(modifier_id: StringName, delta: int) -> bool:
	if modifier_id.is_empty():
		return false
	if delta == 0:
		return remove_capacity_modifier(modifier_id)
	if _capacity_modifiers.has(modifier_id) and int(_capacity_modifiers[modifier_id]) == delta:
		return true
	_capacity_modifiers[modifier_id] = delta
	_emit_capacity_changed()
	return true


func remove_capacity_modifier(modifier_id: StringName) -> bool:
	if modifier_id.is_empty() or not _capacity_modifiers.has(modifier_id):
		return false
	_capacity_modifiers.erase(modifier_id)
	_emit_capacity_changed()
	return true


func get_capacity_modifier_total() -> int:
	var total: int = 0
	for key: Variant in _capacity_modifiers.keys():
		total += int(_capacity_modifiers[key])
	return total


func get_effective_capacity() -> int:
	return maxi(0, _base_capacity + get_capacity_modifier_total())


func get_current_weight() -> int:
	var total: int = 0
	for key: Variant in _amounts.keys():
		var resource_id: StringName = key as StringName
		total += int(_amounts[resource_id]) * int(_unit_weights[resource_id])
	return total


func get_remaining_capacity() -> int:
	return maxi(0, get_effective_capacity() - get_current_weight())


func get_fill_percentage() -> float:
	var current: int = get_current_weight()
	if current <= 0:
		return 0.0
	var effective: int = get_effective_capacity()
	if effective <= 0:
		return 100.0
	return clampf((float(current) * 100.0) / float(effective), 0.0, 100.0)


func is_empty() -> bool:
	return _amounts.is_empty()


func is_full() -> bool:
	return get_remaining_capacity() <= 0


func is_overloaded() -> bool:
	return get_current_weight() > get_effective_capacity()


func get_amount(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return int(_amounts.get(resource_id, 0))


func get_all_amounts() -> Dictionary:
	return _amounts.duplicate()


func get_all_unit_weights() -> Dictionary:
	return _unit_weights.duplicate()


func restore_load_snapshot(amounts: Dictionary, unit_weights: Dictionary) -> void:
	if _provenance != null:
		return
	_amounts = amounts.duplicate()
	_unit_weights = unit_weights.duplicate()
	_transaction_revision += 1


func get_registered_unit_weight(resource_id: StringName) -> int:
	if resource_id.is_empty():
		return 0
	return int(_unit_weights.get(resource_id, 0))


func can_fit_one(definition: ResourceDefinition) -> bool:
	return get_max_additional_units(definition) >= 1


func get_max_additional_units(definition: ResourceDefinition) -> int:
	if definition == null or not definition.is_valid():
		return 0
	return get_max_additional_for(definition.resource_id, definition.unit_weight)


func get_max_additional_for(resource_id: StringName, unit_weight: int) -> int:
	if not _is_valid_resource_input(resource_id, unit_weight):
		return 0
	if not _is_weight_consistent(resource_id, unit_weight):
		return 0
	var remaining: int = get_remaining_capacity()
	if remaining < unit_weight:
		return 0
	@warning_ignore("integer_division")
	var max_units: int = remaining / unit_weight
	return max_units


func add_units(definition: ResourceDefinition, amount: int) -> bool:
	if definition == null or not definition.is_valid():
		return false
	return add_resource(definition.resource_id, definition.unit_weight, amount)


func add_resource(resource_id: StringName, unit_weight: int, amount: int) -> bool:
	if _provenance != null:
		return false
	if amount <= 0:
		return false
	if not _is_valid_resource_input(resource_id, unit_weight):
		return false
	if not _is_weight_consistent(resource_id, unit_weight):
		return false

	var added_weight: int = amount * unit_weight
	if added_weight > get_remaining_capacity():
		return false

	_unit_weights[resource_id] = unit_weight
	_amounts[resource_id] = get_amount(resource_id) + amount
	_emit_load_changed()
	return true


func remove_units(resource_id: StringName, amount: int) -> int:
	if _provenance != null:
		return 0
	if resource_id.is_empty() or amount <= 0:
		return 0
	var current: int = get_amount(resource_id)
	if current <= 0:
		return 0

	var removed: int = mini(current, amount)
	var next_amount: int = current - removed
	if next_amount <= 0:
		_amounts.erase(resource_id)
		_unit_weights.erase(resource_id)
	else:
		_amounts[resource_id] = next_amount

	_emit_load_changed()
	return removed


func take_all() -> Dictionary:
	if _provenance != null:
		return {}
	if _amounts.is_empty():
		return {}
	var taken: Dictionary = _amounts.duplicate()
	_amounts.clear()
	_unit_weights.clear()
	_emit_load_changed()
	return taken


func _is_valid_resource_input(resource_id: StringName, unit_weight: int) -> bool:
	return not resource_id.is_empty() and unit_weight > 0


func _is_weight_consistent(resource_id: StringName, unit_weight: int) -> bool:
	if not _unit_weights.has(resource_id):
		return true
	return int(_unit_weights[resource_id]) == unit_weight


func get_transaction_revision() -> int:
	return _transaction_revision


func is_provenance_enabled() -> bool:
	return _provenance != null


func get_provenance_unit_id() -> StringName:
	return _provenance_unit


func is_transaction_busy() -> bool:
	return _provenance_busy or _provenance_applying or _batch_depth > 0


## An owned ledger is created here and never exposed: one ledger per load.
func enable_provenance(unit_id: StringName) -> bool:
	if _provenance != null or _provenance_busy or String(unit_id).strip_edges().is_empty() or not _amounts.is_empty() or not _unit_weights.is_empty():
		return false
	_provenance_unit = unit_id
	_provenance = CarryProvenanceLedger.new()
	_transaction_revision += 1
	return true

func provenance_snapshot() -> Dictionary:
	if _provenance == null:
		return {}
	return {"unit_id": _provenance_unit, "amounts": _amounts.duplicate(true), "weights": _unit_weights.duplicate(true), "ledger": _provenance.snapshot_transaction_state()}

func validate_provenance() -> bool:
	return _provenance != null and _provenance.validate_aggregate(_provenance_unit, _amounts).ok

## Only the owning transaction invokes these internal helpers while holding the guard.
## A plan is detached data: application replays validation and rejects stale or edited plans.
func _prepare_provenance_add(operation_id: Variant, lot_id: Variant, resource_id: StringName, unit_weight: int, amount: int, origin: Variant, site_id: Variant = &"", generation: int = 0) -> Dictionary:
	if _provenance == null:
		return {"ok": false, "reason": "unavailable"}
	if resource_id.is_empty() or unit_weight <= 0 or amount <= 0 or not _is_weight_consistent(resource_id, unit_weight):
		return {"ok": false, "reason": "invalid_resource"}
	if not validate_provenance():
		return {"ok": false, "reason": "unreconciled"}
	var candidate := CarryProvenanceLedger.new()
	if not candidate.restore_transaction_state(_provenance.snapshot_transaction_state()):
		return {"ok": false, "reason": "invalid_ledger"}
	var lot := {"lot_id": lot_id, "unit_id": _provenance_unit, "resource_id": resource_id, "quantity": amount, "origin": origin, "site_id": site_id, "generation": generation}
	var result: Dictionary = candidate.register_lot(operation_id, lot)
	if not result.ok or result.replayed:
		return result
	if amount > get_max_additional_for(resource_id, unit_weight):
		return {"ok": false, "reason": "capacity"}
	var next_amounts: Dictionary = _amounts.duplicate(true)
	var existing: int = get_amount(resource_id)
	if existing > CarryProvenanceLedger.MAX_INT - amount:
		return {"ok": false, "reason": "overflow"}
	next_amounts[resource_id] = existing + amount
	if not candidate.validate_aggregate(_provenance_unit, next_amounts).ok:
		return {"ok": false, "reason": "unreconciled"}
	return {"ok": true, "replayed": false, "base": provenance_snapshot(), "capacity": get_effective_capacity(), "revision": _transaction_revision,
		"operation": operation_id, "lot_id": lot_id, "resource": resource_id, "weight": unit_weight,
		"amount": amount, "origin": origin, "site": site_id, "generation": generation,
		"amounts": next_amounts, "ledger": candidate.snapshot_transaction_state()}

func _apply_prepared_provenance_add(plan: Dictionary) -> bool:
	# This is an internal operation; public callers use add_with_provenance().
	if not _provenance_applying or not _provenance_busy or _provenance == null or not plan.get("ok", false) or plan.get("replayed", true):
		return false
	for key: String in ["base", "capacity", "revision", "operation", "lot_id", "resource", "weight", "amount", "origin", "site", "generation", "amounts", "ledger"]:
		if not plan.has(key):
			return false
	if plan.base != provenance_snapshot() or plan.capacity != get_effective_capacity() or plan.revision != _transaction_revision:
		return false
	# Recompute rather than trust mutable caller-supplied amounts or ledger state.
	var checked := _prepare_provenance_add(plan.operation, plan.lot_id, plan.resource, plan.weight, plan.amount, plan.origin, plan.site, plan.generation)
	if not checked.get("ok", false) or checked.get("replayed", true) or checked != plan:
		return false
	var candidate := CarryProvenanceLedger.new()
	if not candidate.restore_transaction_state(plan.ledger):
		return false
	_amounts = plan.amounts.duplicate(true)
	_unit_weights[plan.resource] = plan.weight
	_provenance = candidate
	_transaction_revision += 1
	return true

func add_with_provenance(operation_id: Variant, lot_id: Variant, resource_id: StringName, unit_weight: int, amount: int, origin: Variant, site_id: Variant = &"", generation: int = 0) -> Dictionary:
	if _provenance == null or _provenance_busy:
		return {"ok": false, "reason": "unavailable"}
	_provenance_busy = true
	var plan := _prepare_provenance_add(operation_id, lot_id, resource_id, unit_weight, amount, origin, site_id, generation)
	if not plan.ok or plan.get("replayed", false):
		_provenance_busy = false
		return plan
	_provenance_applying = true
	var applied := _apply_prepared_provenance_add(plan)
	_provenance_applying = false
	if not applied:
		_provenance_busy = false
		return {"ok": false, "reason": "stale_plan"}
	_emit_load_changed()
	_provenance_busy = false
	return {"ok": true, "replayed": false}


func _capture_provenance_checkpoint() -> Dictionary:
	return {
		"snapshot": provenance_snapshot(),
		"revision": _transaction_revision,
	}


func _restore_provenance_checkpoint_silent(checkpoint: Dictionary) -> bool:
	if not _provenance_busy or _provenance == null or checkpoint.is_empty():
		return false
	var snap: Variant = checkpoint.get("snapshot")
	if not (snap is Dictionary):
		return false
	var snap_dict: Dictionary = snap as Dictionary
	if snap_dict.is_empty():
		return false
	var candidate := CarryProvenanceLedger.new()
	if not candidate.restore_transaction_state(snap_dict.get("ledger", {})):
		return false
	_amounts = (snap_dict.get("amounts", {}) as Dictionary).duplicate(true)
	_unit_weights = (snap_dict.get("weights", {}) as Dictionary).duplicate(true)
	_provenance = candidate
	_transaction_revision += 1
	return true
