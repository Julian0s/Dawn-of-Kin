class_name GroundPileManager
extends SettlementStorageSource
## Single transactional storage authority backing SettlementInventory with physical camp piles.
## Enforces atomic staged deposits with exact snapshot rollback, centralized time-driven decay,
## and reentrancy safety during both commits and signal notifications.

enum MergeExposurePolicy {
	WEIGHTED_AVERAGE,
	KEEP_OLDEST,
}

var merge_exposure_policy: MergeExposurePolicy = MergeExposurePolicy.WEIGHTED_AVERAGE
var pile_creator_override: Callable = Callable()

var _definitions: Dictionary = {}
var _camp_zone: CampStorageZone = null
var _piles_root: Node3D = null
var _time_provider: WorldTimeProvider = null
var _piles: Array[GroundResourcePile] = []
var _decayed: Dictionary = {}
var _next_pile_id: int = 1
var _last_decay_time_sec: float = 0.0
var _is_mutating: bool = false
var _is_notifying: bool = false
var _is_preparing_withdrawal: bool = false
var _visual_cache: Dictionary = {"meshes": {}, "materials": {}}
var _ledger: PileReservationLedger = PileReservationLedger.new()
var _pending_decay_reservation_losses: Array[Dictionary] = []


func _init(
	p_definitions: Dictionary = {},
	p_camp_zone: CampStorageZone = null,
	p_piles_root: Node3D = null,
	p_time_provider: WorldTimeProvider = null
) -> void:
	configure(p_definitions, p_camp_zone, p_piles_root, p_time_provider)


func configure(
	p_definitions: Dictionary,
	p_camp_zone: CampStorageZone,
	p_piles_root: Node3D,
	p_time_provider: WorldTimeProvider = null
) -> void:
	set_definitions(p_definitions)
	_camp_zone = p_camp_zone
	_piles_root = p_piles_root
	set_time_provider(p_time_provider)
	_transaction_revision += 1


func set_definitions(p_definitions: Dictionary) -> void:
	_definitions.clear()
	for raw_key: Variant in p_definitions.keys():
		var def_var: Variant = p_definitions[raw_key]
		if def_var is ResourceDefinition:
			var def: ResourceDefinition = def_var as ResourceDefinition
			if def.is_valid():
				_definitions[def.resource_id] = def
	_transaction_revision += 1


func set_camp_zone(p_camp_zone: CampStorageZone) -> void:
	_camp_zone = p_camp_zone
	_transaction_revision += 1


func get_camp_zone() -> CampStorageZone:
	return _camp_zone


func set_piles_root(p_piles_root: Node3D) -> void:
	_piles_root = p_piles_root
	_transaction_revision += 1


func set_time_provider(p_time_provider: WorldTimeProvider) -> void:
	_time_provider = p_time_provider
	if _time_provider != null:
		var now: float = _time_provider.get_world_time_sec()
		_last_decay_time_sec = now if is_finite(now) else 0.0
	else:
		_last_decay_time_sec = 0.0
	_transaction_revision += 1


func get_time_provider() -> WorldTimeProvider:
	return _time_provider


func is_locked() -> bool:
	return _is_mutating or _is_notifying or _is_preparing_withdrawal


func get_pile_ledger_revision() -> int:
	return _ledger.get_transaction_revision()


func get_resource_definition_pure(resource_id: StringName) -> ResourceDefinition:
	if resource_id.is_empty() or not _definitions.has(resource_id):
		return null
	var def_var: Variant = _definitions[resource_id]
	if def_var is ResourceDefinition and (def_var as ResourceDefinition).is_valid():
		return def_var as ResourceDefinition
	return null


func cleanup() -> void:
	for pile: GroundResourcePile in _piles:
		if is_instance_valid(pile):
			if pile.get_parent() != null:
				pile.get_parent().remove_child(pile)
			pile.free()
	_piles.clear()
	_decayed.clear()
	_ledger.clear()
	_pending_decay_reservation_losses.clear()
	_visual_cache = {"meshes": {}, "materials": {}}
	pile_creator_override = Callable()
	_transaction_revision += 1


func _dispatch_storage_changed() -> void:
	_is_notifying = true
	storage_changed.emit()
	_is_notifying = false


func _dispatch_reservations_changed() -> void:
	_is_notifying = true
	reservations_changed.emit()
	if not _pending_decay_reservation_losses.is_empty():
		var pending: Array[Dictionary] = _pending_decay_reservation_losses.duplicate()
		_pending_decay_reservation_losses.clear()
		for item: Dictionary in pending:
			reservation_lost_to_decay.emit(
				item["reservation_id"] as StringName,
				item["resource_id"] as StringName,
				item["lost_amount"] as int
			)
	_is_notifying = false


func get_physical_amount(resource_id: StringName) -> int:
	if resource_id == &"":
		return 0
	var total: int = 0
	for pile: GroundResourcePile in _piles:
		if is_instance_valid(pile) and pile.resource_id == resource_id:
			total += pile.amount
	return total


func get_all_physical_amounts() -> Dictionary:
	var totals: Dictionary = {}
	for pile: GroundResourcePile in _piles:
		if not is_instance_valid(pile) or pile.amount <= 0:
			continue
		totals[pile.resource_id] = (totals.get(pile.resource_id, 0) as int) + pile.amount
	return totals


func get_reserved_amount(resource_id: StringName) -> int:
	return _ledger.get_reserved_amount_by_resource(resource_id)


func get_all_reserved_amounts() -> Dictionary:
	return _ledger.get_all_reserved_amounts()


func has_reservation(reservation_id: StringName) -> bool:
	return _ledger.has_reservation(reservation_id)


func get_reservation_amount(reservation_id: StringName, resource_id: StringName) -> int:
	return _ledger.get_reservation_amount(reservation_id, resource_id)


func get_reservation_amounts(reservation_id: StringName) -> Dictionary:
	return _ledger.get_reservation_amounts(reservation_id)


func get_all_reservation_ids() -> Array[StringName]:
	return _ledger.get_all_reservation_ids()


func get_pile_reserved_amount(pile_id: int) -> int:
	return _ledger.get_pile_reserved_amount(pile_id)


func get_pile_available_amount(pile_id: int) -> int:
	var pile: GroundResourcePile = get_pile_by_id(pile_id)
	if pile == null or not is_instance_valid(pile):
		return 0
	return maxi(0, pile.amount - _ledger.get_pile_reserved_amount(pile_id))


func get_pile_reservations(pile_id: int) -> Dictionary:
	return _ledger.get_pile_reservations(pile_id)


func get_piles() -> Array[GroundResourcePile]:
	var result: Array[GroundResourcePile] = []
	for pile: GroundResourcePile in _piles:
		if is_instance_valid(pile):
			result.append(pile)
	return result


func get_piles_for_resource(resource_id: StringName) -> Array[GroundResourcePile]:
	var result: Array[GroundResourcePile] = []
	for pile: GroundResourcePile in _piles:
		if is_instance_valid(pile) and pile.resource_id == resource_id:
			result.append(pile)
	return result


func get_pile_world_position(pile: GroundResourcePile) -> Vector3:
	if pile == null or not is_instance_valid(pile):
		return Vector3.ZERO
	if pile.is_inside_tree():
		return pile.global_position
	return _piles_local_to_world(pile.position)


func get_reserved_pile_entries(
	reservation_id: StringName,
	resource_id: StringName = &"",
	reference_pos: Vector3 = Vector3(INF, INF, INF)
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if reservation_id.is_empty() or not _ledger.has_reservation(reservation_id):
		return entries

	var use_ref_pos: bool = is_finite(reference_pos.x) and is_finite(reference_pos.z)
	for pile: GroundResourcePile in _piles:
		if not is_instance_valid(pile) or pile.amount <= 0:
			continue
		if not resource_id.is_empty() and pile.resource_id != resource_id:
			continue
		var reserved_on_pile: int = mini(
			pile.amount,
			_ledger.get_pile_reservation_amount(pile.pile_id, reservation_id)
		)
		if reserved_on_pile <= 0:
			continue
		var world_pos: Vector3 = get_pile_world_position(pile)
		var dist_sq: float = 0.0
		if use_ref_pos:
			var delta: Vector2 = Vector2(world_pos.x - reference_pos.x, world_pos.z - reference_pos.z)
			dist_sq = delta.length_squared()
		entries.append({
			"pile_id": pile.pile_id,
			"pile": pile,
			"resource_id": pile.resource_id,
			"reserved_amount": reserved_on_pile,
			"pile_amount": pile.amount,
			"elapsed_exposure_sec": pile.elapsed_exposure_sec,
			"world_pos": world_pos,
			"distance_sq": dist_sq,
		})

	if use_ref_pos:
		entries.sort_custom(_sort_reserved_entries_by_distance)
	else:
		entries.sort_custom(_sort_reserved_entries_by_exposure)
	return entries


func get_pile_by_id(pile_id: int) -> GroundResourcePile:
	for pile: GroundResourcePile in _piles:
		if is_instance_valid(pile) and pile.pile_id == pile_id:
			return pile
	return null


func get_total_decayed(resource_id: StringName) -> int:
	if resource_id == &"":
		return 0
	return _decayed.get(resource_id, 0) as int


func get_all_decayed() -> Dictionary:
	return _decayed.duplicate()


func deposit(resource_id: StringName, amount: int) -> bool:
	if amount <= 0:
		return false
	return deposit_batch({resource_id: amount})


func can_deposit_batch(amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_deposit_plan(amounts)
	return plan["ok"] as bool


func deposit_batch(amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_deposit_plan(amounts)
	if not (plan["ok"] as bool):
		return false
	return _commit_deposit_plan(plan)


func try_create_pile_at(resource_id: StringName, amount: int, world_pos: Vector3) -> GroundResourcePile:
	if is_locked() or amount <= 0:
		return null
	if _camp_zone == null or not _camp_zone.is_valid():
		return null
	if _piles_root == null or not is_instance_valid(_piles_root):
		return null
	if not _definitions.has(resource_id):
		return null
	var def: ResourceDefinition = _definitions[resource_id] as ResourceDefinition
	if def == null or not def.is_valid():
		return null
	if _camp_zone.max_pile_amount > 0 and amount > _camp_zone.max_pile_amount:
		return null

	var occupied: Array[Vector3] = _collect_occupied_world_positions()
	var validation: Dictionary = _camp_zone.validate_pile_position(world_pos, occupied)
	if not (validation["valid"] as bool):
		return null

	var resolved_world: Vector3 = validation["position"] as Vector3
	var local_pos: Vector3 = _world_to_piles_local(resolved_world)
	var plan: Dictionary = {
		"ok": true,
		"merges": [],
		"creates": [
			{
				"definition": def,
				"amount": amount,
				"world_pos": resolved_world,
				"local_pos": local_pos,
			}
		],
	}
	if not _commit_deposit_plan(plan):
		return null
	return _piles[_piles.size() - 1]


func withdraw(resource_id: StringName, amount: int) -> bool:
	if is_locked() or resource_id == &"" or amount <= 0:
		return false
	return withdraw_batch({resource_id: amount})


func can_withdraw_batch(amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_withdraw_plan(amounts)
	return plan["ok"] as bool


func withdraw_batch(amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_withdraw_plan(amounts)
	if not (plan["ok"] as bool):
		return false
	return _commit_withdraw_plan(plan["entries"] as Array[Dictionary], &"")


func can_reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_reserve_plan_internal(reservation_id, amounts, false)
	return plan["ok"] as bool


func reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_reserve_plan_internal(reservation_id, amounts, false)
	if not (plan["ok"] as bool):
		return false
	return _commit_reserve_entries(plan["entries"] as Array[Dictionary], reservation_id)


func can_complement_reservation(reservation_id: StringName, extra_amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_reserve_plan_internal(reservation_id, extra_amounts, true)
	return plan["ok"] as bool


func complement_reservation(reservation_id: StringName, extra_amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_reserve_plan_internal(reservation_id, extra_amounts, true)
	if not (plan["ok"] as bool):
		return false
	return _commit_reserve_entries(plan["entries"] as Array[Dictionary], reservation_id)


func _commit_reserve_entries(entries: Array[Dictionary], reservation_id: StringName) -> bool:
	if entries.is_empty():
		return false
	var snapshot: Dictionary = _ledger.snapshot_state()
	_is_mutating = true
	for entry: Dictionary in entries:
		var pile: GroundResourcePile = entry["pile"] as GroundResourcePile
		var res_id: StringName = entry["resource_id"] as StringName
		var allocate_amt: int = entry["amount"] as int
		if pile == null or not is_instance_valid(pile) or allocate_amt <= 0:
			_ledger.restore_state(snapshot)
			_transaction_revision += 1
			_is_mutating = false
			return false
		var pile_free: int = maxi(0, pile.amount - _ledger.get_pile_reserved_amount(pile.pile_id))
		if pile_free < allocate_amt:
			_ledger.restore_state(snapshot)
			_transaction_revision += 1
			_is_mutating = false
			return false
		_ledger.allocate_on_pile(pile.pile_id, res_id, reservation_id, allocate_amt)
	_is_mutating = false

	_emit_reservations_changed()
	_emit_storage_changed()
	return true


func release_batch(reservation_id: StringName, amounts: Dictionary = {}) -> bool:
	if is_locked() or reservation_id.is_empty() or not _ledger.has_reservation(reservation_id):
		return false

	var plan: Dictionary = _build_release_plan(reservation_id, amounts)
	if not (plan["ok"] as bool):
		return false

	_is_mutating = true
	var entries: Array[Dictionary] = plan["entries"] as Array[Dictionary]
	for entry: Dictionary in entries:
		var pile_id: int = entry["pile_id"] as int
		var amt: int = entry["amount"] as int
		_ledger.deduct_from_pile(pile_id, reservation_id, amt)
	_is_mutating = false

	_emit_reservations_changed()
	_emit_storage_changed()
	return true


func withdraw_reserved(reservation_id: StringName, resource_id: StringName, amount: int) -> bool:
	if is_locked() or reservation_id.is_empty() or resource_id.is_empty() or amount <= 0:
		return false
	return withdraw_reserved_batch(reservation_id, {resource_id: amount})


func withdraw_reserved_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if is_locked():
		return false
	var plan: Dictionary = _build_withdraw_reserved_plan(reservation_id, amounts)
	if not (plan["ok"] as bool):
		return false
	return _commit_withdraw_plan(plan["entries"] as Array[Dictionary], reservation_id)


func withdraw_reserved_from_pile(
	pile_id: int,
	reservation_id: StringName,
	resource_id: StringName,
	amount: int
) -> bool:
	if is_locked() or pile_id <= 0 or reservation_id.is_empty() or resource_id.is_empty() or amount <= 0:
		return false
	var pile: GroundResourcePile = get_pile_by_id(pile_id)
	if pile == null or not is_instance_valid(pile):
		return false
	if pile.resource_id != resource_id or pile.amount < amount:
		return false
	var held: int = _ledger.get_pile_reservation_amount(pile_id, reservation_id)
	if held < amount:
		return false
	var entries: Array[Dictionary] = [{
		"pile": pile,
		"resource_id": resource_id,
		"amount": amount,
	}]
	return _commit_withdraw_plan(entries, reservation_id)


func step_decay() -> Dictionary:
	var losses: Dictionary = {}
	if is_locked() or _time_provider == null:
		return losses

	var now: float = _time_provider.get_world_time_sec()
	if not is_finite(now):
		return losses

	if _time_provider.is_paused():
		_last_decay_time_sec = now
		return losses

	var delta_sec: float = maxf(0.0, now - _last_decay_time_sec)
	_last_decay_time_sec = now
	if delta_sec <= 0.0:
		return losses
	if _camp_zone == null or not _camp_zone.is_valid():
		return losses

	var zone_mult: float = _camp_zone.decay_multiplier
	if zone_mult <= 0.0:
		return losses

	var eff_delta: float = delta_sec * zone_mult
	if eff_delta <= 0.0:
		return losses

	_is_mutating = true
	var changed: bool = false
	var pile_updated: bool = false
	var res_losses: Array[Dictionary] = []
	var snapshot: Array[GroundResourcePile] = _piles.duplicate()
	for pile: GroundResourcePile in snapshot:
		if not is_instance_valid(pile) or pile.definition == null:
			continue
		var profile: DecayProfile = pile.definition.decay_profile
		if profile == null or not profile.can_decay or not profile.is_valid():
			continue

		if profile.decay_mode == DecayProfile.DecayMode.EXPIRE_ALL:
			if profile.exposure_duration_sec <= 0.0:
				continue
			var new_elapsed: float = pile.elapsed_exposure_sec + eff_delta
			if new_elapsed >= profile.exposure_duration_sec - 0.000001:
				var expired_amount: int = pile.amount
				_record_decay(pile.resource_id, expired_amount, losses)
				res_losses.append_array(_ledger.reconcile_pile_after_decay(pile.pile_id, 0))
				_remove_and_free_pile(pile)
				changed = true
				pile_updated = true
			else:
				pile.apply_state(pile.amount, new_elapsed, pile.decay_accumulator_sec)
				pile_updated = true
		else:
			var interval: float = profile.gradual_unit_interval_sec
			var grace: float = profile.exposure_duration_sec
			if interval <= 0.0:
				interval = profile.exposure_duration_sec
				grace = 0.0
			if interval <= 0.0:
				continue
			var old_elapsed: float = pile.elapsed_exposure_sec
			var new_elapsed_grad: float = old_elapsed + eff_delta
			var old_over: float = maxf(0.0, old_elapsed - grace)
			var new_over: float = maxf(0.0, new_elapsed_grad - grace)
			var accum: float = pile.decay_accumulator_sec + (new_over - old_over)
			var units_to_lose: int = mini(pile.amount, int(floor(accum / interval + 0.000001)))
			accum = maxf(0.0, accum - float(units_to_lose) * interval)
			var remaining_units: int = pile.amount - units_to_lose
			if units_to_lose > 0:
				_record_decay(pile.resource_id, units_to_lose, losses)
				res_losses.append_array(_ledger.reconcile_pile_after_decay(pile.pile_id, remaining_units))
				changed = true
			if remaining_units <= 0:
				_remove_and_free_pile(pile)
			else:
				pile.apply_state(remaining_units, new_elapsed_grad, accum)
			pile_updated = true

	if pile_updated:
		_transaction_revision += 1
	_is_mutating = false
	if not res_losses.is_empty():
		_pending_decay_reservation_losses.append_array(res_losses)
		_emit_reservations_changed()
	if changed:
		_emit_storage_changed()
	if not _pending_decay_reservation_losses.is_empty() and not is_batch_active():
		_is_notifying = true
		var direct: Array[Dictionary] = _pending_decay_reservation_losses.duplicate()
		_pending_decay_reservation_losses.clear()
		for item: Dictionary in direct:
			reservation_lost_to_decay.emit(
				item["reservation_id"] as StringName,
				item["resource_id"] as StringName,
				item["lost_amount"] as int
			)
		_is_notifying = false
	return losses


func _build_deposit_plan(amounts: Dictionary) -> Dictionary:
	if amounts.is_empty():
		return {"ok": false, "reason": "empty_batch", "merges": [], "creates": []}
	if _camp_zone == null or not _camp_zone.is_valid():
		return {"ok": false, "reason": "invalid_camp_zone", "merges": [], "creates": []}
	if _piles_root == null or not is_instance_valid(_piles_root):
		return {"ok": false, "reason": "invalid_piles_root", "merges": [], "creates": []}

	var sorted_keys: Array[StringName] = []
	for raw_key: Variant in amounts.keys():
		if not (raw_key is StringName or raw_key is String):
			return {"ok": false, "reason": "invalid_resource_key", "merges": [], "creates": []}
		var res_id: StringName = StringName(raw_key)
		if res_id == &"":
			return {"ok": false, "reason": "empty_resource_id", "merges": [], "creates": []}
		var raw_val: Variant = amounts[raw_key]
		if not (raw_val is int) or (raw_val as int) <= 0:
			return {"ok": false, "reason": "invalid_amount", "merges": [], "creates": []}
		if not _definitions.has(res_id):
			return {"ok": false, "reason": "unknown_resource_id", "merges": [], "creates": []}
		var def: ResourceDefinition = _definitions[res_id] as ResourceDefinition
		if def == null or not def.is_valid():
			return {"ok": false, "reason": "invalid_definition", "merges": [], "creates": []}
		if sorted_keys.has(res_id):
			return {"ok": false, "reason": "duplicate_resource_id", "merges": [], "creates": []}
		sorted_keys.append(res_id)

	sorted_keys.sort_custom(_sort_resource_ids)

	var merges: Array[Dictionary] = []
	var creates: Array[Dictionary] = []
	var virtual_amounts: Dictionary = {}
	var occupied: Array[Vector3] = []
	for pile: GroundResourcePile in _piles:
		if not is_instance_valid(pile):
			continue
		virtual_amounts[pile.pile_id] = pile.amount
		occupied.append(_piles_local_to_world(pile.position))

	var candidate_slots: Array[Vector3] = _camp_zone.get_candidate_slots()
	var max_per_pile: int = _camp_zone.max_pile_amount

	var ordered_piles: Array[GroundResourcePile] = get_piles()
	ordered_piles.sort_custom(_sort_piles_by_id)

	for res_id: StringName in sorted_keys:
		var def: ResourceDefinition = _definitions[res_id] as ResourceDefinition
		var remaining: int = amounts[res_id] as int

		for pile: GroundResourcePile in ordered_piles:
			if remaining <= 0:
				break
			if pile.resource_id != res_id:
				continue
			var v_amt: int = virtual_amounts[pile.pile_id] as int
			var add_here: int = remaining
			if max_per_pile > 0:
				var cap_left: int = maxi(0, max_per_pile - v_amt)
				add_here = mini(remaining, cap_left)
			if add_here <= 0:
				continue
			merges.append({
				"pile": pile,
				"add_amount": add_here,
			})
			virtual_amounts[pile.pile_id] = v_amt + add_here
			remaining -= add_here

		while remaining > 0:
			var placed: bool = false
			for slot_world: Vector3 in candidate_slots:
				var validation: Dictionary = _camp_zone.validate_pile_position(slot_world, occupied)
				if not (validation["valid"] as bool):
					continue
				var resolved_world: Vector3 = validation["position"] as Vector3
				var take: int = mini(remaining, max_per_pile) if max_per_pile > 0 else remaining
				creates.append({
					"definition": def,
					"amount": take,
					"world_pos": resolved_world,
					"local_pos": _world_to_piles_local(resolved_world),
				})
				occupied.append(resolved_world)
				remaining -= take
				placed = true
				break
			if not placed:
				return {"ok": false, "reason": "no_valid_camp_slot", "merges": [], "creates": []}

	return {"ok": true, "reason": "", "merges": merges, "creates": creates}


func _commit_deposit_plan(plan: Dictionary) -> bool:
	_is_mutating = true

	var merge_snapshots: Array[Dictionary] = []
	for m: Dictionary in (plan["merges"] as Array):
		var pile: GroundResourcePile = m["pile"] as GroundResourcePile
		merge_snapshots.append({
			"pile": pile,
			"amount": pile.amount,
			"elapsed": pile.elapsed_exposure_sec,
			"accum": pile.decay_accumulator_sec,
		})

	for m: Dictionary in (plan["merges"] as Array):
		var pile: GroundResourcePile = m["pile"] as GroundResourcePile
		var add_amount: int = m["add_amount"] as int
		var next_state: Dictionary = _compute_merged_state(pile, add_amount)
		pile.apply_state(
			next_state["amount"] as int,
			next_state["elapsed"] as float,
			next_state["accum"] as float
		)

	var created_piles: Array[GroundResourcePile] = []
	var staged_next_id: int = _next_pile_id
	var commit_ok: bool = true

	for c: Dictionary in (plan["creates"] as Array):
		var def: ResourceDefinition = c["definition"] as ResourceDefinition
		var amt: int = c["amount"] as int
		var local_pos: Vector3 = c["local_pos"] as Vector3
		var new_pile: GroundResourcePile = _instantiate_pile(staged_next_id, def, amt, local_pos)
		if new_pile == null or not new_pile.is_valid():
			if new_pile != null and is_instance_valid(new_pile):
				if new_pile.get_parent() != null:
					new_pile.get_parent().remove_child(new_pile)
				new_pile.free()
			commit_ok = false
			break
		staged_next_id += 1
		created_piles.append(new_pile)

	if not commit_ok:
		for snap: Dictionary in merge_snapshots:
			var pile: GroundResourcePile = snap["pile"] as GroundResourcePile
			if is_instance_valid(pile):
				pile.apply_state(
					snap["amount"] as int,
					snap["elapsed"] as float,
					snap["accum"] as float
				)
		for cp: GroundResourcePile in created_piles:
			if is_instance_valid(cp):
				if cp.get_parent() != null:
					cp.get_parent().remove_child(cp)
				cp.free()
		_transaction_revision += 1
		_is_mutating = false
		return false

	_next_pile_id = staged_next_id
	for cp: GroundResourcePile in created_piles:
		_piles.append(cp)

	_is_mutating = false
	_emit_storage_changed()
	return true


func _instantiate_pile(
	p_pile_id: int,
	p_definition: ResourceDefinition,
	p_amount: int,
	p_local_pos: Vector3
) -> GroundResourcePile:
	if pile_creator_override.is_valid():
		var custom_result: Variant = pile_creator_override.call(
			p_pile_id,
			p_definition,
			p_amount,
			p_local_pos
		)
		if not (custom_result is GroundResourcePile):
			return null
		var override_pile: GroundResourcePile = custom_result as GroundResourcePile
		if override_pile.get_parent() == null:
			_piles_root.add_child(override_pile)
		return override_pile

	var pile: GroundResourcePile = GroundResourcePile.new()
	_piles_root.add_child(pile)
	pile.configure_initial(
		p_pile_id,
		p_definition,
		p_amount,
		p_local_pos,
		0.0,
		0.0,
		_visual_cache
	)
	return pile


func _compute_merged_state(pile: GroundResourcePile, add_amount: int) -> Dictionary:
	var old_amount: int = pile.amount
	var new_amount: int = old_amount + add_amount
	if merge_exposure_policy == MergeExposurePolicy.KEEP_OLDEST or new_amount <= 0:
		return {
			"amount": new_amount,
			"elapsed": pile.elapsed_exposure_sec,
			"accum": pile.decay_accumulator_sec,
		}
	var ratio: float = float(old_amount) / float(new_amount)
	return {
		"amount": new_amount,
		"elapsed": pile.elapsed_exposure_sec * ratio,
		"accum": pile.decay_accumulator_sec * ratio,
	}


func _remove_and_free_pile(pile: GroundResourcePile) -> void:
	if is_instance_valid(pile):
		_ledger.erase_pile(pile.pile_id)
	_piles.erase(pile)
	if is_instance_valid(pile):
		if pile.get_parent() != null:
			pile.get_parent().remove_child(pile)
		pile.free()
	_transaction_revision += 1


func _build_withdraw_plan(amounts: Dictionary) -> Dictionary:
	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return {"ok": false, "entries": []}
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]

	var entries: Array[Dictionary] = []
	for res_id: StringName in sorted_keys:
		var req: int = int(items[res_id])
		var matching: Array[GroundResourcePile] = _collect_sorted_piles_for_resource(res_id)
		var remaining: int = req
		for pile: GroundResourcePile in matching:
			if remaining <= 0:
				break
			var pile_free: int = maxi(0, pile.amount - _ledger.get_pile_reserved_amount(pile.pile_id))
			if pile_free <= 0:
				continue
			var take: int = mini(remaining, pile_free)
			entries.append({
				"pile": pile,
				"resource_id": res_id,
				"amount": take,
			})
			remaining -= take
		if remaining > 0:
			return {"ok": false, "entries": []}
	return {"ok": true, "entries": entries}


func _build_reserve_plan(reservation_id: StringName, amounts: Dictionary) -> Dictionary:
	return _build_reserve_plan_internal(reservation_id, amounts, false)


func _build_reserve_plan_internal(
	reservation_id: StringName,
	amounts: Dictionary,
	allow_existing: bool
) -> Dictionary:
	if reservation_id.is_empty():
		return {"ok": false, "entries": []}
	if not allow_existing and _ledger.has_reservation(reservation_id):
		return {"ok": false, "entries": []}
	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return {"ok": false, "entries": []}
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]

	var entries: Array[Dictionary] = []
	for res_id: StringName in sorted_keys:
		if not _definitions.has(res_id):
			return {"ok": false, "entries": []}
		var req: int = int(items[res_id])
		var matching: Array[GroundResourcePile] = _collect_sorted_piles_for_resource(res_id)
		var remaining: int = req
		for pile: GroundResourcePile in matching:
			if remaining <= 0:
				break
			var pile_free: int = maxi(0, pile.amount - _ledger.get_pile_reserved_amount(pile.pile_id))
			if pile_free <= 0:
				continue
			var allocate_amt: int = mini(remaining, pile_free)
			entries.append({
				"pile": pile,
				"resource_id": res_id,
				"amount": allocate_amt,
			})
			remaining -= allocate_amt
		if remaining > 0:
			return {"ok": false, "entries": []}
	return {"ok": true, "entries": entries}


func _build_release_plan(reservation_id: StringName, amounts: Dictionary) -> Dictionary:
	var entries: Array[Dictionary] = []
	var matching_piles: Array[GroundResourcePile] = []
	for pile: GroundResourcePile in _piles:
		if is_instance_valid(pile) and _ledger.get_pile_reservation_amount(pile.pile_id, reservation_id) > 0:
			matching_piles.append(pile)
	matching_piles.sort_custom(_sort_withdraw_piles)

	if amounts.is_empty():
		for pile: GroundResourcePile in matching_piles:
			var amt: int = _ledger.get_pile_reservation_amount(pile.pile_id, reservation_id)
			if amt > 0:
				entries.append({"pile_id": pile.pile_id, "amount": amt})
		return {"ok": not entries.is_empty(), "entries": entries}

	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return {"ok": false, "entries": []}
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]

	for res_id: StringName in sorted_keys:
		var req: int = int(items[res_id])
		var remaining: int = req
		for pile: GroundResourcePile in matching_piles:
			if pile.resource_id != res_id or remaining <= 0:
				continue
			var held: int = _ledger.get_pile_reservation_amount(pile.pile_id, reservation_id)
			var release_amt: int = mini(remaining, held)
			if release_amt > 0:
				entries.append({"pile_id": pile.pile_id, "amount": release_amt})
				remaining -= release_amt
		if remaining > 0:
			return {"ok": false, "entries": []}
	return {"ok": true, "entries": entries}


func _build_withdraw_reserved_plan(reservation_id: StringName, amounts: Dictionary) -> Dictionary:
	if reservation_id.is_empty() or not _ledger.has_reservation(reservation_id):
		return {"ok": false, "entries": []}
	var parsed: Dictionary = parse_positive_batch(amounts)
	if not (parsed["ok"] as bool):
		return {"ok": false, "entries": []}
	var items: Dictionary = parsed["items"] as Dictionary
	var sorted_keys: Array[StringName] = parsed["keys"] as Array[StringName]

	var entries: Array[Dictionary] = []
	for res_id: StringName in sorted_keys:
		var req: int = int(items[res_id])
		var matching: Array[GroundResourcePile] = _collect_sorted_piles_for_resource(res_id)
		var remaining: int = req
		for pile: GroundResourcePile in matching:
			if remaining <= 0:
				break
			var held: int = mini(pile.amount, _ledger.get_pile_reservation_amount(pile.pile_id, reservation_id))
			if held <= 0:
				continue
			var take: int = mini(remaining, held)
			entries.append({
				"pile": pile,
				"resource_id": res_id,
				"amount": take,
			})
			remaining -= take
		if remaining > 0:
			return {"ok": false, "entries": []}
	return {"ok": true, "entries": entries}


func _commit_withdraw_plan(
	entries: Array[Dictionary],
	deduct_reservation_id: StringName
) -> bool:
	_is_mutating = true
	var ledger_snap: Dictionary = _ledger.snapshot_state()
	var pile_snapshots: Dictionary = {}
	var touched_piles: Array[GroundResourcePile] = []

	for entry: Dictionary in entries:
		var pile: GroundResourcePile = entry["pile"] as GroundResourcePile
		if not is_instance_valid(pile):
			continue
		if not pile_snapshots.has(pile.pile_id):
			pile_snapshots[pile.pile_id] = {
				"pile": pile,
				"amount": pile.amount,
				"elapsed": pile.elapsed_exposure_sec,
				"accum": pile.decay_accumulator_sec,
			}
			touched_piles.append(pile)

	var commit_ok: bool = true
	for entry: Dictionary in entries:
		if not _commit_withdraw_entry(entry, deduct_reservation_id):
			commit_ok = false
			break

	if not commit_ok:
		_ledger.restore_state(ledger_snap)
		for pile_id_key: Variant in pile_snapshots.keys():
			var snap: Dictionary = pile_snapshots[pile_id_key] as Dictionary
			var pile: GroundResourcePile = snap["pile"] as GroundResourcePile
			if is_instance_valid(pile):
				pile.apply_state(
					snap["amount"] as int,
					snap["elapsed"] as float,
					snap["accum"] as float
				)
		_transaction_revision += 1
		_is_mutating = false
		return false

	for pile: GroundResourcePile in touched_piles:
		if is_instance_valid(pile) and pile.amount <= 0:
			_remove_and_free_pile(pile)

	_is_mutating = false
	if not deduct_reservation_id.is_empty():
		_emit_reservations_changed()
	_emit_storage_changed()
	return true


func _commit_withdraw_entry(
	entry: Dictionary,
	deduct_reservation_id: StringName
) -> bool:
	var pile: GroundResourcePile = entry["pile"] as GroundResourcePile
	var take: int = entry["amount"] as int
	if not is_instance_valid(pile) or take <= 0 or pile.amount < take:
		return false
	if not deduct_reservation_id.is_empty():
		var deducted: int = _ledger.deduct_from_pile(pile.pile_id, deduct_reservation_id, take)
		if deducted != take:
			return false
	else:
		var free_now: int = maxi(0, pile.amount - _ledger.get_pile_reserved_amount(pile.pile_id))
		if free_now < take:
			return false
	var next_amount: int = pile.amount - take
	pile.apply_state(next_amount, pile.elapsed_exposure_sec, pile.decay_accumulator_sec)
	return true


func _collect_sorted_piles_for_resource(resource_id: StringName) -> Array[GroundResourcePile]:
	var matching: Array[GroundResourcePile] = []
	for pile: GroundResourcePile in _piles:
		if is_instance_valid(pile) and pile.resource_id == resource_id and pile.amount > 0:
			matching.append(pile)
	matching.sort_custom(_sort_withdraw_piles)
	return matching


func _record_decay(resource_id: StringName, lost_amount: int, step_losses: Dictionary) -> void:
	if lost_amount <= 0:
		return
	_decayed[resource_id] = (_decayed.get(resource_id, 0) as int) + lost_amount
	step_losses[resource_id] = (step_losses.get(resource_id, 0) as int) + lost_amount


func _collect_occupied_world_positions() -> Array[Vector3]:
	var occupied: Array[Vector3] = []
	for pile: GroundResourcePile in _piles:
		if is_instance_valid(pile):
			occupied.append(_piles_local_to_world(pile.position))
	return occupied


func _world_to_piles_local(world_pos: Vector3) -> Vector3:
	if _piles_root != null and is_instance_valid(_piles_root) and _piles_root.is_inside_tree():
		return _piles_root.to_local(world_pos)
	if _piles_root != null and is_instance_valid(_piles_root):
		return world_pos - _piles_root.position
	return world_pos


func _piles_local_to_world(local_pos: Vector3) -> Vector3:
	if _piles_root != null and is_instance_valid(_piles_root) and _piles_root.is_inside_tree():
		return _piles_root.to_global(local_pos)
	if _piles_root != null and is_instance_valid(_piles_root):
		return _piles_root.position + local_pos
	return local_pos


func _sort_resource_ids(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)


func _sort_piles_by_id(a: GroundResourcePile, b: GroundResourcePile) -> bool:
	return a.pile_id < b.pile_id


func _sort_withdraw_piles(a: GroundResourcePile, b: GroundResourcePile) -> bool:
	if not is_equal_approx(a.elapsed_exposure_sec, b.elapsed_exposure_sec):
		return a.elapsed_exposure_sec > b.elapsed_exposure_sec
	return a.pile_id < b.pile_id


func _sort_reserved_entries_by_distance(a: Dictionary, b: Dictionary) -> bool:
	var dist_a: float = float(a.get("distance_sq", 0.0))
	var dist_b: float = float(b.get("distance_sq", 0.0))
	if absf(dist_a - dist_b) > 0.0001:
		return dist_a < dist_b
	return _sort_reserved_entries_by_exposure(a, b)


func _sort_reserved_entries_by_exposure(a: Dictionary, b: Dictionary) -> bool:
	var exp_a: float = float(a.get("elapsed_exposure_sec", 0.0))
	var exp_b: float = float(b.get("elapsed_exposure_sec", 0.0))
	if not is_equal_approx(exp_a, exp_b):
		return exp_a > exp_b
	return int(a.get("pile_id", 0)) < int(b.get("pile_id", 0))


## Pure side-effect-free preparation for withdrawing a site-reserved quantity from a pile.
## Does not modify piles, reservations, ledger, revisions, or emit any signals.
func _prepare_reserved_pile_withdrawal(
	pile_id: int,
	reservation_id: StringName,
	resource_id: StringName,
	amount: int
) -> Dictionary:
	if _is_mutating or _is_notifying or is_batch_active():
		return {"ok": false, "reason": "busy"}
	if pile_id <= 0 or reservation_id.is_empty() or resource_id.is_empty() or amount <= 0:
		return {"ok": false, "reason": "invalid_input"}

	var pile: GroundResourcePile = get_pile_by_id(pile_id)
	if pile == null or not is_instance_valid(pile) or not pile.is_valid() or pile.amount <= 0:
		return {"ok": false, "reason": "invalid_or_missing_pile"}
	if pile.resource_id != resource_id or pile.definition == null or not pile.definition.is_valid() or pile.definition.resource_id != resource_id:
		return {"ok": false, "reason": "pile_resource_mismatch"}
	if _definitions.has(resource_id):
		var registered_def: Variant = _definitions[resource_id]
		if not (registered_def is ResourceDefinition) or not (registered_def as ResourceDefinition).is_valid():
			return {"ok": false, "reason": "resource_or_weight_mismatch"}
		var reg_rd: ResourceDefinition = registered_def as ResourceDefinition
		if reg_rd.resource_id != resource_id or reg_rd.unit_weight != pile.definition.unit_weight:
			return {"ok": false, "reason": "resource_or_weight_mismatch"}

	var total_reserved_on_pile: int = _ledger.get_pile_reserved_amount(pile_id)
	if total_reserved_on_pile < 0 or total_reserved_on_pile > pile.amount:
		return {"ok": false, "reason": "unreconciled_pile_reservations"}

	var reserved_for_site_on_pile: int = _ledger.get_pile_reservation_amount(pile_id, reservation_id)
	if reserved_for_site_on_pile <= 0:
		if total_reserved_on_pile > 0:
			return {"ok": false, "reason": "reservation_belongs_to_other_site"}
		return {"ok": false, "reason": "no_site_reservation_on_pile"}

	if amount > reserved_for_site_on_pile:
		return {"ok": false, "reason": "insufficient_pile_reservation"}
	if amount > pile.amount:
		return {"ok": false, "reason": "insufficient_pile_physical"}

	var before_ledger_state: Dictionary = _ledger.snapshot_state()
	var candidate_ledger := PileReservationLedger.new()
	candidate_ledger.restore_state(before_ledger_state)
	var deducted: int = candidate_ledger.deduct_from_pile(pile_id, reservation_id, amount)
	if deducted != amount:
		return {"ok": false, "reason": "ledger_deduction_mismatch"}

	var next_pile_amount: int = pile.amount - amount
	var next_pile_total_reserved: int = candidate_ledger.get_pile_reserved_amount(pile_id)
	var free_before: int = pile.amount - total_reserved_on_pile
	var free_after: int = next_pile_amount - next_pile_total_reserved
	if next_pile_amount < 0 or next_pile_total_reserved != total_reserved_on_pile - amount or free_after != free_before:
		return {"ok": false, "reason": "unreconciled_pile_reservations"}

	var pile_res_before: Dictionary = _ledger.get_pile_reservations(pile_id)
	var pile_res_after: Dictionary = candidate_ledger.get_pile_reservations(pile_id)
	for res_key: Variant in pile_res_before.keys():
		var rid: StringName = res_key as StringName
		if rid != reservation_id and int(pile_res_after.get(rid, 0)) != int(pile_res_before[rid]):
			return {"ok": false, "reason": "unreconciled_pile_reservations"}
	if candidate_ledger.get_reservation_amount(reservation_id, resource_id) != _ledger.get_reservation_amount(reservation_id, resource_id) - amount:
		return {"ok": false, "reason": "ledger_deduction_mismatch"}

	return {
		"ok": true,
		"reason": "",
		"pile_id": pile_id,
		"pile_instance_id": pile.get_instance_id(),
		"reservation_id": reservation_id,
		"resource_id": resource_id,
		"unit_weight": pile.definition.unit_weight,
		"amount": amount,
		"revisions": {
			"storage_revision": get_transaction_revision(),
			"pile_ledger_revision": _ledger.get_transaction_revision(),
			"pile_revision": pile.get_transaction_revision(),
		},
		"before": {
			"pile_amount": pile.amount,
			"pile_will_remove": false,
			"pile_elapsed_exposure_sec": pile.elapsed_exposure_sec,
			"pile_decay_accumulator_sec": pile.decay_accumulator_sec,
			"pile_reserved_for_site": reserved_for_site_on_pile,
			"pile_total_reserved": total_reserved_on_pile,
			"pile_free_amount": free_before,
			"pile_reservations": pile_res_before,
			"site_total_reserved_resource": _ledger.get_reservation_amount(reservation_id, resource_id),
			"ledger_state": before_ledger_state,
		},
		"after": {
			"pile_amount": next_pile_amount,
			"pile_will_remove": next_pile_amount == 0,
			"pile_reserved_for_site": candidate_ledger.get_pile_reservation_amount(pile_id, reservation_id),
			"pile_total_reserved": next_pile_total_reserved,
			"pile_free_amount": free_after,
			"pile_reservations": pile_res_after,
			"site_total_reserved_resource": candidate_ledger.get_reservation_amount(reservation_id, resource_id),
			"ledger_state": candidate_ledger.snapshot_state(),
		},
	}


## Captures an isolated pre-mutation checkpoint for a single pile withdrawal transaction.
func _capture_pile_withdrawal_checkpoint(pile_id: int) -> Dictionary:
	var pile: GroundResourcePile = get_pile_by_id(pile_id)
	return {
		"pile": pile,
		"pile_id": pile_id,
		"amount": pile.amount if pile != null and is_instance_valid(pile) else 0,
		"elapsed": pile.elapsed_exposure_sec if pile != null and is_instance_valid(pile) else 0.0,
		"accum": pile.decay_accumulator_sec if pile != null and is_instance_valid(pile) else 0.0,
		"ledger_state": _ledger.snapshot_state(),
		"storage_revision": _transaction_revision,
		"ledger_revision": _ledger.get_transaction_revision(),
		"mutated": false,
	}


## Applies a previously prepared pile withdrawal silently while coordinator holds _is_preparing_withdrawal.
## Does not emit signals and defers exhausted pile node removal until commit boundary.
func _apply_prepared_pile_withdrawal_silent(pile_plan: Dictionary, checkpoint: Dictionary) -> Dictionary:
	if not _is_preparing_withdrawal or _is_mutating or _is_notifying or is_batch_active():
		return {"ok": false, "reason": "busy"}
	if not bool(pile_plan.get("ok", false)):
		return {"ok": false, "reason": "invalid_plan"}
	var pile_id: int = int(pile_plan.get("pile_id", 0))
	var reservation_id: StringName = StringName(pile_plan.get("reservation_id", &""))
	var resource_id: StringName = StringName(pile_plan.get("resource_id", &""))
	var amount: int = int(pile_plan.get("amount", 0))
	if pile_id <= 0 or reservation_id.is_empty() or resource_id.is_empty() or amount <= 0:
		return {"ok": false, "reason": "invalid_plan"}

	var pile: GroundResourcePile = get_pile_by_id(pile_id)
	if pile == null or not is_instance_valid(pile) or pile.get_instance_id() != int(pile_plan.get("pile_instance_id", -1)):
		return {"ok": false, "reason": "invalid_or_missing_pile"}

	var plan_revs: Dictionary = pile_plan.get("revisions", {}) as Dictionary
	if (
		int(plan_revs.get("storage_revision", -1)) != _transaction_revision
		or int(plan_revs.get("pile_ledger_revision", -1)) != _ledger.get_transaction_revision()
		or int(plan_revs.get("pile_revision", -1)) != pile.get_transaction_revision()
	):
		return {"ok": false, "reason": "stale_revision"}

	var recomputed: Dictionary = _prepare_reserved_pile_withdrawal(pile_id, reservation_id, resource_id, amount)
	if not bool(recomputed.get("ok", false)) or recomputed != pile_plan:
		return {"ok": false, "reason": String(recomputed.get("reason", "stale_plan"))}

	_is_mutating = true
	var deducted: int = _ledger.deduct_from_pile(pile_id, reservation_id, amount)
	if deducted != amount:
		_ledger.restore_state(checkpoint["ledger_state"] as Dictionary)
		_transaction_revision += 1
		_is_mutating = false
		return {"ok": false, "reason": "ledger_deduction_mismatch"}

	checkpoint["mutated"] = true
	var next_amount: int = int((pile_plan["after"] as Dictionary)["pile_amount"])
	pile.apply_state(
		next_amount,
		float((pile_plan["before"] as Dictionary)["pile_elapsed_exposure_sec"]),
		float((pile_plan["before"] as Dictionary)["pile_decay_accumulator_sec"])
	)
	_transaction_revision += 1
	_is_mutating = false
	return {"ok": true, "pile": pile, "exhausted": next_amount <= 0}


## Restores pile and reservation ledger state silently on transaction rollback, advancing revisions monotonically.
func _restore_pile_withdrawal_checkpoint_silent(checkpoint: Dictionary) -> void:
	if checkpoint.is_empty() or not bool(checkpoint.get("mutated", false)):
		return
	var ledger_state: Variant = checkpoint.get("ledger_state")
	if ledger_state is Dictionary:
		_ledger.restore_state(ledger_state as Dictionary)
	var pile: GroundResourcePile = checkpoint.get("pile") as GroundResourcePile
	if pile != null and is_instance_valid(pile):
		pile.apply_state(
			int(checkpoint.get("amount", 0)),
			float(checkpoint.get("elapsed", 0.0)),
			float(checkpoint.get("accum", 0.0))
		)
	checkpoint["mutated"] = false
	_transaction_revision += 1


## Removes and frees an exhausted pile node strictly at the irreversible commit boundary.
func _finalize_exhausted_pile_after_commit_silent(pile: GroundResourcePile) -> bool:
	if not _is_preparing_withdrawal or _is_mutating:
		return false
	if pile == null or not is_instance_valid(pile):
		return false
	if pile.amount > 0:
		return false
	_remove_and_free_pile(pile)
	return true
