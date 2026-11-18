extends RefCounted
class_name ConstructionCancellationMath
## Pure planning only. This does not validate physical custody or cancel a site.

enum State { ACTIVE, REQUESTED, PREVALIDATING, FREEZING, RECOVERY_PENDING, RETURNING, RETURN_BLOCKED, SETTLED }
const MAX_INT: int = 9223372036854775807
const FIELDS := ["required", "reserved", "in_transit", "buffer", "incorporated", "missing"]

static func evaluate_refund(incorporated: Variant, progress: Variant, total_work: Variant) -> Dictionary:
	if typeof(incorporated) != TYPE_INT or typeof(progress) != TYPE_INT or typeof(total_work) != TYPE_INT:
		return {"ok": false, "reason": "invalid_type"}
	if incorporated < 0 or total_work <= 0 or progress < 0 or progress > total_work:
		return {"ok": false, "reason": "invalid_range"}
	var remaining: int = total_work - progress
	if remaining == 0 or incorporated == 0:
		return {"ok": true, "value": 0}
	@warning_ignore("integer_division")
	if incorporated > MAX_INT / remaining:
		return {"ok": false, "reason": "overflow"}
	@warning_ignore("integer_division")
	var fraction: int = (incorporated * remaining) / total_work
	@warning_ignore("integer_division")
	return {"ok": true, "value": fraction / 2}

static func evaluate_snapshot(snapshot: Variant) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY or snapshot.size() != 3 or not snapshot.has("progress") or not snapshot.has("total_work") or not snapshot.has("resources"):
		return {"ok": false, "reason": "invalid_snapshot"}
	var progress: Variant = snapshot["progress"]
	var work: Variant = snapshot["total_work"]
	var validity: Dictionary = evaluate_refund(0, progress, work)
	if not validity.ok:
		return validity
	var resources: Variant = snapshot["resources"]
	if typeof(resources) != TYPE_DICTIONARY or resources.is_empty():
		return {"ok": false, "reason": "invalid_resources"}
	var result: Dictionary = {}
	for resource: Variant in resources:
		if (typeof(resource) != TYPE_STRING and typeof(resource) != TYPE_STRING_NAME) or String(resource).is_empty():
			return {"ok": false, "reason": "invalid_resource"}
		var key := StringName(resource)
		if result.has(key):
			return {"ok": false, "reason": "duplicate_resource"}
		var data: Variant = resources[resource]
		if typeof(data) != TYPE_DICTIONARY or data.size() != FIELDS.size():
			return {"ok": false, "reason": "invalid_fields"}
		for field: String in FIELDS:
			if not data.has(field) or typeof(data[field]) != TYPE_INT or data[field] < 0:
				return {"ok": false, "reason": "invalid_quantity"}
		var sum: int = 0
		for field: String in ["reserved", "in_transit", "buffer", "incorporated", "missing"]:
			var amount: int = data[field]
			if sum > MAX_INT - amount:
				return {"ok": false, "reason": "overflow"}
			sum += amount
		if sum != data.required:
			return {"ok": false, "reason": "accounting_mismatch"}
		var refund: Dictionary = evaluate_refund(data.incorporated, progress, work)
		if not refund.ok:
			return refund
		var recovered: int = refund.value
		# All terms are nonnegative and bounded by the checked accounting sum.
		var physical_return: int = data.in_transit + data.buffer + recovered
		result[key] = {"reservation_release": data.reserved, "in_transit": data.in_transit,
			"buffer": data.buffer, "incorporated_recovered": recovered,
			"demolition_loss": data.incorporated - recovered, "missing": data.missing,
			"future_physical_return": physical_return, "total_predicted": data.reserved + physical_return}
	return {"ok": true, "resources": result, "physical_verified": false}

static func plan_transition(from: Variant, to: Variant) -> Dictionary:
	if typeof(from) != TYPE_INT or typeof(to) != TYPE_INT or from < State.ACTIVE or from > State.SETTLED or to < State.ACTIVE or to > State.SETTLED:
		return {"ok": false, "reason": "invalid_state"}
	var committed: bool = from >= State.RECOVERY_PENDING
	if from == to:
		return {"ok": true, "changed": false, "state": from, "committed": committed}
	var allowed: bool = false
	match from:
		State.ACTIVE: allowed = to == State.REQUESTED
		State.REQUESTED: allowed = to == State.PREVALIDATING or to == State.ACTIVE
		State.PREVALIDATING: allowed = to == State.FREEZING or to == State.ACTIVE
		State.FREEZING: allowed = to == State.RECOVERY_PENDING or to == State.ACTIVE
		State.RECOVERY_PENDING: allowed = to == State.RETURNING or to == State.RETURN_BLOCKED or to == State.SETTLED
		State.RETURNING: allowed = to == State.RETURN_BLOCKED or to == State.RECOVERY_PENDING or to == State.SETTLED
		State.RETURN_BLOCKED: allowed = to == State.RETURNING or to == State.RECOVERY_PENDING
	if not allowed:
		return {"ok": false, "reason": "invalid_transition"}
	return {"ok": true, "changed": true, "state": to, "committed": to >= State.RECOVERY_PENDING}
