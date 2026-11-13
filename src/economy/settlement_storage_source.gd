class_name SettlementStorageSource
extends RefCounted
## Replaceable storage backend interface for SettlementInventory.
## In T2.1+, GroundPileManager implements or adapts this contract so camp piles
## and SettlementInventory share a single transactional authority without duplicate balances.

@warning_ignore("unused_signal")
signal storage_changed()


func get_amount(_resource_id: StringName) -> int:
	return 0


func get_all_amounts() -> Dictionary:
	return {}


func deposit(_resource_id: StringName, _amount: int) -> bool:
	return false


func withdraw(_resource_id: StringName, _amount: int) -> bool:
	return false


func get_total_decayed(_resource_id: StringName) -> int:
	return 0


func get_all_decayed() -> Dictionary:
	return {}
