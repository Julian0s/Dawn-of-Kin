class_name UnitControlPermissions
extends RefCounted
## Single source of truth for R-03B B1 character control, inspection, community work,
## and economic recovery permissions derived strictly from validated CharacterDefinition metadata.

enum PersonalCommandKind {
	MOVE,
	GATHER_WOOD,
	GATHER_STONE,
	GATHER_FOOD,
	CONSTRUCT_SITE,
	DELIVER_TO_CAMP,
}

const REASON_INVALID_DEFINITION: String = "invalid_character_definition"
const REASON_PERSONAL_CONTROL_DENIED: String = "personal_control_denied"
const REASON_AGE_RESTRICTED_TASK: String = "age_restricted_task"
const REASON_RECOVERY_REQUIRES_AUTHORITY: String = "recovery_order_requires_system_authority"
const REASON_INVALID_ORDER: String = "invalid_order"
const REASON_UNSUPPORTED_PERSONAL_ORDER: String = "unsupported_personal_order"


static func _get_valid_definition(unit: Unit) -> CharacterDefinition:
	if unit == null or not is_instance_valid(unit):
		return null
	var def: CharacterDefinition = unit.get_definition()
	if def == null or not def.is_valid():
		return null
	return def


static func can_be_selected_visually(unit: Unit) -> bool:
	var def: CharacterDefinition = _get_valid_definition(unit)
	return def != null and def.age_stage != CharacterDefinition.AgeStage.BABY


static func can_be_inspected(unit: Unit) -> bool:
	return can_be_selected_visually(unit)


static func is_read_only_community_unit(unit: Unit) -> bool:
	var def: CharacterDefinition = _get_valid_definition(unit)
	return (
		def != null
		and def.house_affiliation == CharacterDefinition.HouseAffiliation.COMMUNITY
		and def.age_stage != CharacterDefinition.AgeStage.BABY
	)


static func get_personal_order_rejection_reason(unit: Unit, command_kind: PersonalCommandKind) -> String:
	var def: CharacterDefinition = _get_valid_definition(unit)
	if def == null:
		return REASON_INVALID_DEFINITION
	if def.age_stage == CharacterDefinition.AgeStage.BABY:
		return REASON_AGE_RESTRICTED_TASK
	if def.house_affiliation != CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE:
		return REASON_PERSONAL_CONTROL_DENIED
	if def.age_stage == CharacterDefinition.AgeStage.CHILD:
		match command_kind:
			PersonalCommandKind.MOVE, PersonalCommandKind.GATHER_FOOD, PersonalCommandKind.DELIVER_TO_CAMP:
				return ""
			_:
				return REASON_AGE_RESTRICTED_TASK
	return ""


static func can_receive_personal_order(unit: Unit, command_kind: PersonalCommandKind) -> bool:
	return get_personal_order_rejection_reason(unit, command_kind).is_empty()


static func personal_command_kind_for_resource_source(source: ResourceSource) -> PersonalCommandKind:
	if source != null and is_instance_valid(source):
		match source.get_category():
			ResourceDefinition.Category.FOOD:
				return PersonalCommandKind.GATHER_FOOD
			ResourceDefinition.Category.STONE:
				return PersonalCommandKind.GATHER_STONE
			ResourceDefinition.Category.WOOD:
				return PersonalCommandKind.GATHER_WOOD
	return PersonalCommandKind.GATHER_WOOD


static func get_personal_order_rejection_reason_for_order(unit: Unit, order: UnitOrder) -> String:
	if order == null:
		return REASON_INVALID_ORDER
	if order is RecoveryOrder:
		return REASON_RECOVERY_REQUIRES_AUTHORITY
	if order is MoveOrder:
		return get_personal_order_rejection_reason(unit, PersonalCommandKind.MOVE)
	if order is DeliverToCampOrder:
		return get_personal_order_rejection_reason(unit, PersonalCommandKind.DELIVER_TO_CAMP)
	if order is ConstructOrder:
		return get_personal_order_rejection_reason(unit, PersonalCommandKind.CONSTRUCT_SITE)
	if order is GatherResourceOrder:
		var gather_order: GatherResourceOrder = order as GatherResourceOrder
		var cat: int = gather_order.get_source_category()
		match cat:
			ResourceDefinition.Category.FOOD:
				return get_personal_order_rejection_reason(unit, PersonalCommandKind.GATHER_FOOD)
			ResourceDefinition.Category.STONE:
				return get_personal_order_rejection_reason(unit, PersonalCommandKind.GATHER_STONE)
			ResourceDefinition.Category.WOOD:
				return get_personal_order_rejection_reason(unit, PersonalCommandKind.GATHER_WOOD)
			_:
				return get_personal_order_rejection_reason(unit, PersonalCommandKind.GATHER_WOOD)
	return REASON_UNSUPPORTED_PERSONAL_ORDER


static func can_receive_personal_order_for_order(unit: Unit, order: UnitOrder) -> bool:
	return get_personal_order_rejection_reason_for_order(unit, order).is_empty()


static func can_be_community_worker_base(unit: Unit) -> bool:
	var def: CharacterDefinition = _get_valid_definition(unit)
	return def != null and def.age_stage != CharacterDefinition.AgeStage.BABY


static func can_participate_in_community_work(unit: Unit, task_kind: WorkTask.Kind) -> bool:
	var def: CharacterDefinition = _get_valid_definition(unit)
	if def == null or def.age_stage == CharacterDefinition.AgeStage.BABY:
		return false
	if def.age_stage == CharacterDefinition.AgeStage.CHILD:
		return task_kind == WorkTask.Kind.GATHER_FOOD
	return true


static func can_participate_in_community_work_for_order(unit: Unit, order: UnitOrder) -> bool:
	if not (order is GatherResourceOrder):
		return false
	var gather_order: GatherResourceOrder = order as GatherResourceOrder
	match gather_order.get_source_category():
		ResourceDefinition.Category.WOOD:
			return can_participate_in_community_work(unit, WorkTask.Kind.GATHER_WOOD)
		ResourceDefinition.Category.STONE:
			return can_participate_in_community_work(unit, WorkTask.Kind.GATHER_STONE)
		ResourceDefinition.Category.FOOD:
			return can_participate_in_community_work(unit, WorkTask.Kind.GATHER_FOOD)
		_:
			return false


static func can_perform_recovery_order(unit: Unit) -> bool:
	var def: CharacterDefinition = _get_valid_definition(unit)
	return (
		def != null
		and (
			def.age_stage == CharacterDefinition.AgeStage.YOUTH
			or def.age_stage == CharacterDefinition.AgeStage.ADULT
		)
	)


static func can_join_manual_team_future(unit: Unit, task_kind: WorkTask.Kind) -> bool:
	var def: CharacterDefinition = _get_valid_definition(unit)
	if def == null or def.house_affiliation != CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE:
		return false
	return can_participate_in_community_work(unit, task_kind)
