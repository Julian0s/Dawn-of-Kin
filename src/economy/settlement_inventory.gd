class_name SettlementInventory
extends RefCounted
## Single-authority economic query and transaction facade for the settlement.
## Delegates all balances and mutations directly to a SettlementStorageSource so
## it never holds a second independent balance that could diverge from camp piles.

signal inventory_changed()

var _storage_source: SettlementStorageSource = null
var _is_delivering: bool = false


func _init(storage_source: SettlementStorageSource = null) -> void:
	if storage_source != null:
		set_storage_source(storage_source)


func set_storage_source(storage_source: SettlementStorageSource) -> void:
	if _storage_source == storage_source:
		return
	if _storage_source != null and _storage_source.storage_changed.is_connected(_on_source_storage_changed):
		_storage_source.storage_changed.disconnect(_on_source_storage_changed)
	_storage_source = storage_source
	if _storage_source != null and not _storage_source.storage_changed.is_connected(_on_source_storage_changed):
		_storage_source.storage_changed.connect(_on_source_storage_changed)
	inventory_changed.emit()


func get_storage_source() -> SettlementStorageSource:
	return _storage_source


func get_amount(resource_id: StringName) -> int:
	if _storage_source == null or resource_id.is_empty():
		return 0
	return maxi(0, _storage_source.get_amount(resource_id))


func get_all_amounts() -> Dictionary:
	if _storage_source == null:
		return {}
	return _storage_source.get_all_amounts()


func has_amount(resource_id: StringName, required_amount: int) -> bool:
	if required_amount < 0:
		return false
	if required_amount == 0:
		return true
	return get_amount(resource_id) >= required_amount


func deposit(resource_id: StringName, amount: int) -> bool:
	if _storage_source == null or resource_id.is_empty() or amount <= 0:
		return false
	return _storage_source.deposit(resource_id, amount)


func withdraw(resource_id: StringName, amount: int) -> bool:
	if _storage_source == null or resource_id.is_empty() or amount <= 0:
		return false
	return _storage_source.withdraw(resource_id, amount)


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
	inventory_changed.emit()
