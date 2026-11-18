extends RefCounted
class_name CarryProvenanceLedger
## Isolated ledger: no connection to physical cargo or gameplay.
const MAX_INT: int = 9223372036854775807
const FREE_GATHERED := &"FREE_GATHERED"
const SITE_RESERVED := &"SITE_RESERVED"
var _lots: Dictionary = {}
var _operations: Dictionary = {}
var _used_lots: Dictionary = {}

static func _id(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and not String(value).strip_edges().is_empty()

func snapshot() -> Dictionary:
	return _lots.duplicate(true)

func _prior(op: Variant, payload: Dictionary) -> Dictionary:
	if not _id(op):
		return {"ok": false, "reason": "invalid_operation"}
	if _operations.has(StringName(op)):
		if _operations[StringName(op)] == payload:
			return {"ok": true, "replayed": true}
		return {"ok": false, "reason": "operation_conflict"}
	return {"ok": true, "replayed": false}

func register_lot(op: Variant, lot: Variant) -> Dictionary:
	if typeof(lot) != TYPE_DICTIONARY or lot.size() != 7:
		return {"ok": false, "reason": "invalid_lot"}
	for field: String in ["lot_id", "unit_id", "resource_id", "quantity", "origin", "site_id", "generation"]:
		if not lot.has(field):
			return {"ok": false, "reason": "invalid_lot"}
	if not _id(lot.lot_id) or not _id(lot.unit_id) or not _id(lot.resource_id) or typeof(lot.quantity) != TYPE_INT or lot.quantity <= 0 or typeof(lot.generation) != TYPE_INT or lot.generation < 0:
		return {"ok": false, "reason": "invalid_lot"}
	if lot.origin == FREE_GATHERED:
		if not (typeof(lot.site_id) == TYPE_STRING or typeof(lot.site_id) == TYPE_STRING_NAME) or not String(lot.site_id).is_empty() or lot.generation != 0:
			return {"ok": false, "reason": "invalid_origin"}
	elif lot.origin == SITE_RESERVED:
		if not _id(lot.site_id):
			return {"ok": false, "reason": "invalid_origin"}
	else:
		return {"ok": false, "reason": "invalid_origin"}
	var canonical := {"lot_id": StringName(lot.lot_id), "unit_id": StringName(lot.unit_id), "resource_id": StringName(lot.resource_id), "quantity": lot.quantity, "origin": StringName(lot.origin), "site_id": StringName(lot.site_id), "generation": lot.generation}
	var payload := {"kind": "register", "lot": canonical}
	var previous := _prior(op, payload)
	if not previous.ok or previous.replayed:
		return previous
	if _used_lots.has(canonical.lot_id):
		return {"ok": false, "reason": "duplicate_lot"}
	var total := _sum(canonical.unit_id, canonical.resource_id)
	if not total.ok or canonical.quantity > MAX_INT - total.value:
		return {"ok": false, "reason": "overflow"}
	_lots[canonical.lot_id] = canonical.duplicate(true)
	_used_lots[canonical.lot_id] = true
	_operations[StringName(op)] = payload.duplicate(true)
	return {"ok": true, "replayed": false}

func _sum(unit: StringName, resource: StringName) -> Dictionary:
	var total: int = 0
	for lot: Dictionary in _lots.values():
		if lot.unit_id == unit and lot.resource_id == resource:
			if total > MAX_INT - lot.quantity:
				return {"ok": false, "reason": "overflow"}
			total += lot.quantity
	return {"ok": true, "value": total}

func query(unit: Variant, resource: Variant, origin: Variant, site: Variant = &"") -> Array:
	var result: Array = []
	for lot: Dictionary in _lots.values():
		if lot.unit_id == unit and lot.resource_id == resource and lot.origin == origin and (origin != SITE_RESERVED or lot.site_id == site):
			result.append(lot.duplicate(true))
	return result

func split_lot(op: Variant, lot_id: Variant, child_id: Variant, amount: Variant) -> Dictionary:
	if not _id(lot_id) or not _id(child_id) or typeof(amount) != TYPE_INT or amount <= 0:
		return {"ok": false, "reason": "invalid_input"}
	var payload := {"kind": "split", "lot_id": StringName(lot_id), "child_id": StringName(child_id), "amount": amount}
	var previous := _prior(op, payload)
	if not previous.ok or previous.replayed:
		return previous
	if not _lots.has(StringName(lot_id)) or _used_lots.has(StringName(child_id)) or amount >= _lots[StringName(lot_id)].quantity:
		return {"ok": false, "reason": "invalid_split"}
	var child: Dictionary = _lots[StringName(lot_id)].duplicate(true)
	child.lot_id = StringName(child_id)
	child.quantity = amount
	_lots[StringName(lot_id)].quantity -= amount
	_lots[StringName(child_id)] = child
	_used_lots[StringName(child_id)] = true
	_operations[StringName(op)] = payload
	return {"ok": true, "replayed": false}

func withdraw(op: Variant, lot_id: Variant, amount: Variant) -> Dictionary:
	if not _id(lot_id) or typeof(amount) != TYPE_INT or amount <= 0:
		return {"ok": false, "reason": "invalid_input"}
	var payload := {"kind": "withdraw", "lot_id": StringName(lot_id), "amount": amount}
	var previous := _prior(op, payload)
	if not previous.ok or previous.replayed:
		return previous
	if not _lots.has(StringName(lot_id)) or amount > _lots[StringName(lot_id)].quantity:
		return {"ok": false, "reason": "insufficient_lot"}
	_lots[StringName(lot_id)].quantity -= amount
	if _lots[StringName(lot_id)].quantity == 0:
		_lots.erase(StringName(lot_id))
	_operations[StringName(op)] = payload
	return {"ok": true, "replayed": false}

func validate_aggregate(unit: Variant, aggregate: Variant) -> Dictionary:
	if not _id(unit) or typeof(aggregate) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_aggregate"}
	var totals: Dictionary = {}
	for lot: Dictionary in _lots.values():
		if lot.unit_id == unit:
			var old: int = totals.get(lot.resource_id, 0)
			if old > MAX_INT - lot.quantity:
				return {"ok": false, "reason": "overflow"}
			totals[lot.resource_id] = old + lot.quantity
	for key: Variant in aggregate:
		if not _id(key) or typeof(aggregate[key]) != TYPE_INT or aggregate[key] < 0:
			return {"ok": false, "reason": "invalid_aggregate"}
		if aggregate[key] != totals.get(StringName(key), 0):
			return {"ok": false, "reason": "unreconciled_cargo"}
	for key: Variant in totals:
		if totals[key] != aggregate.get(key, 0):
			return {"ok": false, "reason": "unreconciled_cargo"}
	return {"ok": true}
