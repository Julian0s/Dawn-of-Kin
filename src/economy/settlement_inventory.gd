class_name SettlementInventory
extends RefCounted
## Single-authority economic query and transaction facade for the settlement.
## Delegates all balances and mutations directly to a SettlementStorageSource so
## it never holds a second independent balance that could diverge from camp piles.

signal inventory_changed()
signal reservations_changed()
signal reservation_lost_to_decay(reservation_id: StringName, resource_id: StringName, lost_amount: int)

var _storage_source: SettlementStorageSource = null
var _is_delivering: bool = false
var _transaction_revision: int = 0


func _init(storage_source: SettlementStorageSource = null) -> void:
	if storage_source != null:
		set_storage_source(storage_source)


func get_transaction_revision() -> int:
	return _transaction_revision


func is_transaction_busy() -> bool:
	if _is_delivering:
		return true
	if _storage_source != null:
		if _storage_source.is_batch_active():
			return true
		if _storage_source is GroundPileManager and (_storage_source as GroundPileManager).is_locked():
			return true
	return false


func set_storage_source(storage_source: SettlementStorageSource) -> void:
	if _storage_source == storage_source:
		return
	if _storage_source != null:
		if _storage_source.storage_changed.is_connected(_on_source_storage_changed):
			_storage_source.storage_changed.disconnect(_on_source_storage_changed)
		if _storage_source.reservations_changed.is_connected(_on_source_reservations_changed):
			_storage_source.reservations_changed.disconnect(_on_source_reservations_changed)
		if _storage_source.reservation_lost_to_decay.is_connected(_on_source_reservation_lost_to_decay):
			_storage_source.reservation_lost_to_decay.disconnect(_on_source_reservation_lost_to_decay)
	_storage_source = storage_source
	if _storage_source != null:
		if not _storage_source.storage_changed.is_connected(_on_source_storage_changed):
			_storage_source.storage_changed.connect(_on_source_storage_changed)
		if not _storage_source.reservations_changed.is_connected(_on_source_reservations_changed):
			_storage_source.reservations_changed.connect(_on_source_reservations_changed)
		if not _storage_source.reservation_lost_to_decay.is_connected(_on_source_reservation_lost_to_decay):
			_storage_source.reservation_lost_to_decay.connect(_on_source_reservation_lost_to_decay)
	_transaction_revision += 1
	inventory_changed.emit()
	reservations_changed.emit()


func get_storage_source() -> SettlementStorageSource:
	return _storage_source


func get_physical_amount(resource_id: StringName) -> int:
	if _storage_source == null or resource_id.is_empty():
		return 0
	return maxi(0, _storage_source.get_physical_amount(resource_id))


func get_all_physical_amounts() -> Dictionary:
	if _storage_source == null:
		return {}
	return _storage_source.get_all_physical_amounts()


func get_reserved_amount(resource_id: StringName) -> int:
	if _storage_source == null or resource_id.is_empty():
		return 0
	return maxi(0, _storage_source.get_reserved_amount(resource_id))


func get_all_reserved_amounts() -> Dictionary:
	if _storage_source == null:
		return {}
	return _storage_source.get_all_reserved_amounts()


func get_available_amount(resource_id: StringName) -> int:
	if _storage_source == null or resource_id.is_empty():
		return 0
	return maxi(0, _storage_source.get_available_amount(resource_id))


func get_all_available_amounts() -> Dictionary:
	if _storage_source == null:
		return {}
	return _storage_source.get_all_available_amounts()


func get_amount(resource_id: StringName) -> int:
	return get_available_amount(resource_id)


func get_all_amounts() -> Dictionary:
	return get_all_available_amounts()


func has_amount(resource_id: StringName, required_amount: int) -> bool:
	if required_amount < 0:
		return false
	if required_amount == 0:
		return true
	return get_available_amount(resource_id) >= required_amount


func has_amounts(amounts: Dictionary) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.can_withdraw_batch(amounts)


func has_reservation(reservation_id: StringName) -> bool:
	if _storage_source == null or reservation_id.is_empty():
		return false
	return _storage_source.has_reservation(reservation_id)


func get_reservation_amount(reservation_id: StringName, resource_id: StringName) -> int:
	if _storage_source == null or reservation_id.is_empty() or resource_id.is_empty():
		return 0
	return maxi(0, _storage_source.get_reservation_amount(reservation_id, resource_id))


func get_reservation_amounts(reservation_id: StringName) -> Dictionary:
	if _storage_source == null or reservation_id.is_empty():
		return {}
	return _storage_source.get_reservation_amounts(reservation_id)


func get_all_reservation_ids() -> Array[StringName]:
	if _storage_source == null:
		return []
	return _storage_source.get_all_reservation_ids()


func get_reserved_pile_entries(
	reservation_id: StringName,
	resource_id: StringName = &"",
	reference_pos: Vector3 = Vector3(INF, INF, INF)
) -> Array[Dictionary]:
	if _storage_source is GroundPileManager:
		return (_storage_source as GroundPileManager).get_reserved_pile_entries(
			reservation_id,
			resource_id,
			reference_pos
		)
	var result: Array[Dictionary] = []
	if _storage_source == null or not _storage_source.has_method("get_reserved_pile_entries"):
		return result
	var raw: Variant = _storage_source.call("get_reserved_pile_entries", reservation_id, resource_id, reference_pos)
	if raw is Array:
		for item: Variant in raw as Array:
			if item is Dictionary:
				result.append(item as Dictionary)
	return result


func deposit(resource_id: StringName, amount: int) -> bool:
	if _storage_source == null or resource_id.is_empty() or amount <= 0:
		return false
	return _storage_source.deposit(resource_id, amount)


func withdraw(resource_id: StringName, amount: int) -> bool:
	if _storage_source == null or resource_id.is_empty() or amount <= 0:
		return false
	return _storage_source.withdraw(resource_id, amount)


func can_withdraw_batch(amounts: Dictionary) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.can_withdraw_batch(amounts)


func withdraw_batch(amounts: Dictionary) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.withdraw_batch(amounts)


func can_reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.can_reserve_batch(reservation_id, amounts)


func reserve_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.reserve_batch(reservation_id, amounts)


func can_complement_reservation(reservation_id: StringName, extra_amounts: Dictionary) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.can_complement_reservation(reservation_id, extra_amounts)


func complement_reservation(reservation_id: StringName, extra_amounts: Dictionary) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.complement_reservation(reservation_id, extra_amounts)


func release_batch(reservation_id: StringName, amounts: Dictionary = {}) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.release_batch(reservation_id, amounts)


func withdraw_reserved(reservation_id: StringName, resource_id: StringName, amount: int) -> bool:
	if _storage_source == null or reservation_id.is_empty() or resource_id.is_empty() or amount <= 0:
		return false
	return _storage_source.withdraw_reserved(reservation_id, resource_id, amount)


func withdraw_reserved_batch(reservation_id: StringName, amounts: Dictionary) -> bool:
	if _storage_source == null:
		return false
	return _storage_source.withdraw_reserved_batch(reservation_id, amounts)


func withdraw_reserved_from_pile_to_carry_load(
	pile_id: int,
	reservation_id: StringName,
	resource_def: ResourceDefinition,
	requested_amount: int,
	carry_load: UnitCarryLoad
) -> int:
	if _is_delivering or _storage_source == null or carry_load == null:
		return 0
	if reservation_id.is_empty() or resource_def == null or not resource_def.is_valid() or requested_amount <= 0:
		return 0

	var capacity_room: int = carry_load.get_max_additional_units(resource_def)
	var actual: int = mini(requested_amount, capacity_room)
	if actual <= 0:
		return 0

	var uses_targeted_pile: bool = _storage_source.has_method("withdraw_reserved_from_pile")
	if uses_targeted_pile and pile_id <= 0:
		return 0

	var snapshot: Dictionary = carry_load.get_all_amounts()
	var weights_backup: Dictionary = carry_load.get_all_unit_weights()

	_is_delivering = true
	carry_load.begin_batch()
	var added_ok: bool = carry_load.add_units(resource_def, actual)
	if not added_ok:
		carry_load.restore_load_snapshot(snapshot, weights_backup)
		carry_load.end_batch(true)
		_is_delivering = false
		return 0

	_storage_source.begin_batch()
	var withdrawn: bool = false
	if uses_targeted_pile:
		withdrawn = bool(_storage_source.call(
			"withdraw_reserved_from_pile",
			pile_id,
			reservation_id,
			resource_def.resource_id,
			actual
		))
	else:
		withdrawn = _storage_source.withdraw_reserved(reservation_id, resource_def.resource_id, actual)

	if not withdrawn:
		carry_load.restore_load_snapshot(snapshot, weights_backup)
		_storage_source.end_batch(true)
		carry_load.end_batch(true)
		_is_delivering = false
		return 0

	_storage_source.end_batch(false)
	carry_load.end_batch(false)
	_is_delivering = false
	return actual


func deliver_from_carry_load(carry_load: UnitCarryLoad) -> Dictionary:
	if _is_delivering or _storage_source == null or carry_load == null or carry_load.is_empty():
		return {}

	var snapshot: Dictionary = carry_load.get_all_amounts()
	var weights_backup: Dictionary = carry_load.get_all_unit_weights()
	var pending: Dictionary = {}
	for key: Variant in snapshot.keys():
		if not (key is StringName):
			return {}
		var resource_id: StringName = key as StringName
		var amount: int = int(snapshot[resource_id])
		if resource_id.is_empty() or amount <= 0 or int(weights_backup.get(resource_id, 0)) <= 0:
			return {}
		pending[resource_id] = amount

	if pending.is_empty() or not _storage_source.can_deposit_batch(pending):
		return {}

	_is_delivering = true
	carry_load.begin_batch()
	_storage_source.begin_batch()

	var taken: Dictionary = carry_load.take_all()
	if taken.is_empty() or not _storage_source.deposit_batch(taken):
		carry_load.restore_load_snapshot(snapshot, weights_backup)
		_storage_source.end_batch(true)
		carry_load.end_batch(true)
		_is_delivering = false
		return {}

	# Both states are now final and conserved before any observer callback runs.
	_storage_source.end_batch(false)
	carry_load.end_batch(false)
	_is_delivering = false
	return taken.duplicate()


func get_total_decayed(resource_id: StringName) -> int:
	if _storage_source == null or resource_id.is_empty():
		return 0
	return maxi(0, _storage_source.get_total_decayed(resource_id))


func get_all_decayed() -> Dictionary:
	if _storage_source == null:
		return {}
	return _storage_source.get_all_decayed()


func _on_source_storage_changed() -> void:
	_transaction_revision += 1
	inventory_changed.emit()


func _on_source_reservations_changed() -> void:
	_transaction_revision += 1
	reservations_changed.emit()


func _on_source_reservation_lost_to_decay(
	reservation_id: StringName,
	resource_id: StringName,
	lost_amount: int
) -> void:
	_transaction_revision += 1
	reservation_lost_to_decay.emit(reservation_id, resource_id, lost_amount)
