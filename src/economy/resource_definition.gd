class_name ResourceDefinition
extends Resource
## Parametrized economic definition for a gatherable/storable material.
## Uses integer internal unit weights to avoid floating-point drift.

enum Category {
	FOOD,
	WOOD,
	STONE,
}

@export var resource_id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.FOOD
@export var unit_weight: int = 1
@export var decay_profile: DecayProfile = null


func is_valid() -> bool:
	if resource_id.is_empty():
		return false
	if unit_weight <= 0:
		return false
	if decay_profile != null and not decay_profile.is_valid():
		return false
	return true
