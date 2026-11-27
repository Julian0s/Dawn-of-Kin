class_name CharacterDefinition
extends Resource
## Persistent identity and movement/visual configuration for a unit character.
## Keeps stable ID and provisional T1 representation decoupled from scene nodes.

enum SilhouetteKind {
	EXPLORER_PACK,
	CLOAK_SCOUT,
}

enum HouseAffiliation {
	COMMUNITY,
	FOUNDING_HOUSE,
}

enum FoundingHouseOrigin {
	NONE,
	ORIGINAL_FOUNDER,
	DIRECT_DESCENDANT,
	EXTERNAL_SPOUSE,
}

enum AgeStage {
	BABY,
	CHILD,
	YOUTH,
	ADULT,
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
@export var house_affiliation: HouseAffiliation = HouseAffiliation.COMMUNITY
@export var founding_house_origin: FoundingHouseOrigin = FoundingHouseOrigin.NONE
@export var age_stage: AgeStage = AgeStage.ADULT


func is_valid() -> bool:
	if (
		character_id.is_empty()
		or move_speed <= 0.0
		or not is_finite(move_speed)
		or work_approach_speed <= 0.0
		or not is_finite(work_approach_speed)
		or max_load_speed_multiplier <= 0.0
		or max_load_speed_multiplier > 1.0
		or not is_finite(max_load_speed_multiplier)
		or turn_rate <= 0.0
		or not is_finite(turn_rate)
		or base_carry_capacity <= 0
	):
		return false
	if house_affiliation != HouseAffiliation.COMMUNITY and house_affiliation != HouseAffiliation.FOUNDING_HOUSE:
		return false
	if (
		founding_house_origin != FoundingHouseOrigin.NONE
		and founding_house_origin != FoundingHouseOrigin.ORIGINAL_FOUNDER
		and founding_house_origin != FoundingHouseOrigin.DIRECT_DESCENDANT
		and founding_house_origin != FoundingHouseOrigin.EXTERNAL_SPOUSE
	):
		return false
	if (
		age_stage != AgeStage.BABY
		and age_stage != AgeStage.CHILD
		and age_stage != AgeStage.YOUTH
		and age_stage != AgeStage.ADULT
	):
		return false
	if house_affiliation == HouseAffiliation.COMMUNITY and founding_house_origin != FoundingHouseOrigin.NONE:
		return false
	if house_affiliation == HouseAffiliation.FOUNDING_HOUSE and founding_house_origin == FoundingHouseOrigin.NONE:
		return false
	if (
		(founding_house_origin == FoundingHouseOrigin.ORIGINAL_FOUNDER or founding_house_origin == FoundingHouseOrigin.EXTERNAL_SPOUSE)
		and age_stage != AgeStage.ADULT
	):
		return false
	return true


func is_founding_house_member() -> bool:
	return is_valid() and house_affiliation == HouseAffiliation.FOUNDING_HOUSE


func is_original_founder() -> bool:
	return is_founding_house_member() and founding_house_origin == FoundingHouseOrigin.ORIGINAL_FOUNDER
