class_name CharacterDefinition
extends Resource
## Persistent identity and movement/visual configuration for a unit character.
## Keeps stable ID and provisional T1 representation decoupled from scene nodes.

enum SilhouetteKind {
	EXPLORER_PACK,
	CLOAK_SCOUT,
}

@export var character_id: StringName = &""
@export var display_name: String = "Unit"
@export var move_speed: float = 4.8
@export var work_approach_speed: float = 2.5
@export var max_load_speed_multiplier: float = 0.60
@export var turn_rate: float = 10.0
@export var silhouette_kind: SilhouetteKind = SilhouetteKind.EXPLORER_PACK
@export var primary_color: Color = Color(0.86, 0.34, 0.18, 1.0)
@export var secondary_color: Color = Color(0.22, 0.17, 0.14, 1.0)
@export var base_carry_capacity: int = 20


func is_valid() -> bool:
	return (
		not character_id.is_empty()
		and move_speed > 0.0
		and is_finite(move_speed)
		and work_approach_speed > 0.0
		and is_finite(work_approach_speed)
		and max_load_speed_multiplier > 0.0
		and max_load_speed_multiplier <= 1.0
		and is_finite(max_load_speed_multiplier)
		and turn_rate > 0.0
		and is_finite(turn_rate)
		and base_carry_capacity > 0
	)
