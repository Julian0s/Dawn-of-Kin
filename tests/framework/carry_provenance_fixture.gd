extends RefCounted


## Seeds synthetic lots through the real planner and commit checks for test scenarios.
## Gameplay must acquire material from a source or an authorized withdrawal.
static func add_lot(load: UnitCarryLoad, operation_id: Variant, lot_id: Variant, resource_id: StringName, unit_weight: int, amount: int, origin: Variant, site_id: Variant = &"", generation: int = 0) -> Dictionary:
	if load._provenance == null or load._provenance_busy:
		return {"ok": false, "reason": "unavailable"}
	load._provenance_busy = true
	var plan := load._prepare_provenance_add(operation_id, lot_id, resource_id, unit_weight, amount, origin, site_id, generation)
	if not plan.ok or plan.get("replayed", false):
		load._provenance_busy = false
		return plan
	load._provenance_applying = true
	var applied := load._apply_prepared_provenance_add(plan)
	load._provenance_applying = false
	if not applied:
		load._provenance_busy = false
		return {"ok": false, "reason": "stale_plan"}
	load._emit_load_changed()
	load._provenance_busy = false
	return {"ok": true, "replayed": false}
