class_name HudFormatter
extends RefCounted
## Pure formatting and snapshot helpers for T2.5 resource and unit HUD panels.
## Queries SettlementInventory and UnitCarryLoad directly without caching parallel balances.

enum ExposureTone {
	PROTECTED,
	EXPOSED_IDLE,
	EXPOSED_ACTIVE,
}


static func format_unit_state(state: Unit.State) -> String:
	match state:
		Unit.State.IDLE:
			return "Ocioso"
		Unit.State.MOVING:
			return "Deslocando"
		Unit.State.WORKING:
			return "Trabalhando"
		Unit.State.TRANSPORTING:
			return "Transportando"
		_:
			return "Ocioso"


static func format_unit_name(unit: Unit) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""
	var def: CharacterDefinition = unit.get_definition()
	if def != null and not def.display_name.strip_edges().is_empty():
		return def.display_name
	if not String(unit.name).is_empty():
		return String(unit.name)
	return "Personagem"


static func format_resource_label(resource_id: StringName) -> String:
	match resource_id:
		&"wood":
			return "Madeira"
		&"stone":
			return "Pedra"
		&"food":
			return "Alimentos"
		_:
			return String(resource_id)


static func format_unit_inspection_meta(unit: Unit, community_board: CommunityWorkBoard = null) -> String:
	if not UnitControlPermissions.is_read_only_community_unit(unit):
		return ""
	var base_text: String = "Morador — somente leitura"
	if community_board != null and is_instance_valid(community_board):
		var active_task: WorkTask = community_board.get_active_task_for_unit(unit)
		if active_task != null:
			return "%s · Coleta comunitária: %s" % [base_text, format_resource_label(active_task.resource_id)]
	var active_order: UnitOrder = unit.get_current_order()
	if active_order is RecoveryOrder:
		return "%s · Recuperação de materiais" % base_text
	if active_order is GatherResourceOrder and active_order.get_order_origin() == UnitOrder.OrderOrigin.COMMUNITY:
		var gather_order: GatherResourceOrder = active_order as GatherResourceOrder
		var src: ResourceSource = gather_order.source
		if src != null and is_instance_valid(src):
			return "%s · Coleta comunitária: %s" % [base_text, format_resource_label(src.get_resource_id())]
	return base_text


static func compute_display_percentage(current_weight: int, effective_capacity: int, raw_percentage: float) -> int:
	if current_weight <= 0:
		return 0
	if effective_capacity <= 0 or current_weight >= effective_capacity:
		return 100
	var clamped_raw: float = clampf(raw_percentage, 0.0, 100.0)
	return clampi(roundi(clamped_raw), 1, 99)


static func build_carry_snapshot(carry_load: UnitCarryLoad) -> Dictionary:
	if carry_load == null:
		return {
			"current_weight": 0,
			"effective_capacity": 0,
			"fill_percentage": 0.0,
			"display_percentage": 0,
			"is_overloaded": false,
			"wood": 0,
			"stone": 0,
			"food": 0,
			"percentage_text": "0%",
			"weight_text": "Peso transportado: 0 / 0",
		}

	var current_weight: int = carry_load.get_current_weight()
	var effective_capacity: int = carry_load.get_effective_capacity()
	var fill_percentage: float = clampf(carry_load.get_fill_percentage(), 0.0, 100.0)
	var display_percentage: int = compute_display_percentage(current_weight, effective_capacity, fill_percentage)
	var is_overloaded: bool = carry_load.is_overloaded()
	var wood: int = carry_load.get_amount(&"wood")
	var stone: int = carry_load.get_amount(&"stone")
	var food: int = carry_load.get_amount(&"food")

	var weight_text: String = "Peso transportado: %d / %d" % [current_weight, effective_capacity]
	if is_overloaded:
		weight_text = "%s (sobrecarga)" % weight_text

	return {
		"current_weight": current_weight,
		"effective_capacity": effective_capacity,
		"fill_percentage": fill_percentage,
		"display_percentage": display_percentage,
		"is_overloaded": is_overloaded,
		"wood": wood,
		"stone": stone,
		"food": food,
		"percentage_text": "%d%%" % display_percentage,
		"weight_text": weight_text,
	}


static func build_stockpile_snapshot(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone = null,
	pile_manager: GroundPileManager = null
) -> Dictionary:
	var wood: int = inventory.get_amount(&"wood") if inventory != null else 0
	var stone: int = inventory.get_amount(&"stone") if inventory != null else 0
	var food: int = inventory.get_amount(&"food") if inventory != null else 0

	var resolved_pile_manager: GroundPileManager = pile_manager
	if resolved_pile_manager == null and inventory != null:
		var source: SettlementStorageSource = inventory.get_storage_source()
		if source is GroundPileManager:
			resolved_pile_manager = source as GroundPileManager

	var resolved_camp_zone: CampStorageZone = camp_zone
	if resolved_camp_zone == null and resolved_pile_manager != null:
		resolved_camp_zone = resolved_pile_manager.get_camp_zone()

	var is_protected: bool = (
		resolved_camp_zone != null
		and is_instance_valid(resolved_camp_zone)
		and resolved_camp_zone.is_valid()
		and resolved_camp_zone.decay_multiplier <= 0.0
	)

	var has_decaying_piles: bool = false
	if not is_protected:
		if resolved_pile_manager != null:
			for pile: GroundResourcePile in resolved_pile_manager.get_piles():
				if not is_instance_valid(pile) or pile.amount <= 0:
					continue
				if pile.definition != null and pile.definition.decay_profile != null and pile.definition.decay_profile.can_decay:
					has_decaying_piles = true
					break
		elif inventory != null:
			has_decaying_piles = (wood > 0 or food > 0)

	var exposure_tone: int = ExposureTone.EXPOSED_IDLE
	var exposure_text: String = "Armazenamento: exposto"
	if is_protected:
		exposure_tone = ExposureTone.PROTECTED
		exposure_text = "Armazenamento: protegido"
	elif has_decaying_piles:
		exposure_tone = ExposureTone.EXPOSED_ACTIVE

	return {
		"wood": wood,
		"stone": stone,
		"food": food,
		"is_protected": is_protected,
		"has_decaying_piles": has_decaying_piles,
		"exposure_tone": exposure_tone,
		"exposure_text": exposure_text,
	}
