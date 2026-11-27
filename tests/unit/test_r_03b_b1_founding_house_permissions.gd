extends TestCase
## Unit tests for R-03B B1:
## - A01: Original founders (leader_a.tres, leader_b.tres)
## - A02: Direct descendants and external spouses (Founding House without DEC-07 original founder status)
## - A05 (unit layer): OrderOrigin defaults and invalid metadata denying privileges
## - B01-B03: AgeStage matrix (BABY, CHILD, YOUTH, ADULT) across personal, community, and recovery permissions

const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const LEADER_B_DEF: CharacterDefinition = preload("res://data/characters/leader_b.tres")


func _make_def(
	id: StringName,
	display_name_text: String,
	affiliation: CharacterDefinition.HouseAffiliation,
	origin: CharacterDefinition.FoundingHouseOrigin,
	age: CharacterDefinition.AgeStage
) -> CharacterDefinition:
	var def := CharacterDefinition.new()
	def.character_id = id
	def.display_name = display_name_text
	def.house_affiliation = affiliation
	def.founding_house_origin = origin
	def.age_stage = age
	return def


func _spawn_unit(def: CharacterDefinition, node_name: String) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = node_name
	u.definition = def
	add_test_child(u)
	return u


func test_a01_original_founders_metadata_and_permissions() -> void:
	for def: CharacterDefinition in [LEADER_A_DEF, LEADER_B_DEF]:
		assert_not_null(def, "Founder resource must load")
		assert_true(def.is_valid(), "Founder definition must be valid")
		assert_eq(def.house_affiliation, CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE)
		assert_eq(def.founding_house_origin, CharacterDefinition.FoundingHouseOrigin.ORIGINAL_FOUNDER)
		assert_eq(def.age_stage, CharacterDefinition.AgeStage.ADULT)
		assert_true(def.is_founding_house_member(), "Founder must belong to Founding House")
		assert_true(def.is_original_founder(), "Founder must be original founder (DEC-07)")

	var u_a: Unit = _spawn_unit(LEADER_A_DEF, "FounderAUnit")
	await wait_process_frames(1)

	assert_true(UnitControlPermissions.can_be_selected_visually(u_a))
	assert_true(UnitControlPermissions.can_be_inspected(u_a))
	assert_false(UnitControlPermissions.is_read_only_community_unit(u_a))
	for kind: int in [
		UnitControlPermissions.PersonalCommandKind.MOVE,
		UnitControlPermissions.PersonalCommandKind.GATHER_WOOD,
		UnitControlPermissions.PersonalCommandKind.GATHER_STONE,
		UnitControlPermissions.PersonalCommandKind.GATHER_FOOD,
		UnitControlPermissions.PersonalCommandKind.CONSTRUCT_SITE,
		UnitControlPermissions.PersonalCommandKind.DELIVER_TO_CAMP,
	]:
		assert_true(UnitControlPermissions.can_receive_personal_order(u_a, kind), "Founder must accept personal command %d" % kind)
	for task_kind: int in [WorkTask.Kind.GATHER_WOOD, WorkTask.Kind.GATHER_STONE, WorkTask.Kind.GATHER_FOOD]:
		assert_true(UnitControlPermissions.can_participate_in_community_work(u_a, task_kind))
	assert_true(UnitControlPermissions.can_perform_recovery_order(u_a))

	# Membership must NEVER depend on display_name or node name.
	var renamed_founder := _make_def(
		&"renamed_founder",
		"Aldeao Qualquer",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.ORIGINAL_FOUNDER,
		CharacterDefinition.AgeStage.ADULT
	)
	var u_renamed: Unit = _spawn_unit(renamed_founder, "Worker99")
	await wait_process_frames(1)
	assert_true(UnitControlPermissions.can_receive_personal_order(u_renamed, UnitControlPermissions.PersonalCommandKind.MOVE))


func test_a02_direct_descendant_and_external_spouse_without_original_founder_flag() -> void:
	var descendant_def := _make_def(
		&"descendant_adult",
		"Filha",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT,
		CharacterDefinition.AgeStage.ADULT
	)
	var spouse_def := _make_def(
		&"external_spouse",
		"Conjuge",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.EXTERNAL_SPOUSE,
		CharacterDefinition.AgeStage.ADULT
	)
	assert_true(descendant_def.is_valid())
	assert_true(spouse_def.is_valid())
	assert_true(descendant_def.is_founding_house_member())
	assert_false(descendant_def.is_original_founder(), "Direct descendant must NOT have DEC-07 original founder flag")
	assert_true(spouse_def.is_founding_house_member())
	assert_false(spouse_def.is_original_founder(), "External spouse must NOT have DEC-07 original founder flag")

	var u_desc: Unit = _spawn_unit(descendant_def, "DescendantUnit")
	var u_spouse: Unit = _spawn_unit(spouse_def, "SpouseUnit")
	await wait_process_frames(1)

	for u: Unit in [u_desc, u_spouse]:
		assert_true(UnitControlPermissions.can_receive_personal_order(u, UnitControlPermissions.PersonalCommandKind.MOVE))
		assert_true(UnitControlPermissions.can_receive_personal_order(u, UnitControlPermissions.PersonalCommandKind.CONSTRUCT_SITE))
		assert_true(UnitControlPermissions.can_participate_in_community_work(u, WorkTask.Kind.GATHER_WOOD))
		assert_true(UnitControlPermissions.can_join_manual_team_future(u, WorkTask.Kind.GATHER_WOOD))


func test_character_definition_defaults_and_cross_field_invariants() -> void:
	var raw_def := CharacterDefinition.new()
	assert_eq(raw_def.house_affiliation, CharacterDefinition.HouseAffiliation.COMMUNITY, "Safe default affiliation must be COMMUNITY")
	assert_eq(raw_def.founding_house_origin, CharacterDefinition.FoundingHouseOrigin.NONE, "Safe default origin must be NONE")
	assert_eq(raw_def.age_stage, CharacterDefinition.AgeStage.ADULT, "Safe default age must be ADULT")
	assert_false(raw_def.is_valid(), "Empty character_id must be invalid")

	raw_def.character_id = &"common_default"
	assert_true(raw_def.is_valid(), "COMMUNITY + NONE + ADULT with valid id must be valid")
	assert_false(raw_def.is_founding_house_member())
	assert_false(raw_def.is_original_founder())

	# Invalid combinations:
	var bad_community_origin := _make_def(
		&"bad_1", "Bad 1",
		CharacterDefinition.HouseAffiliation.COMMUNITY,
		CharacterDefinition.FoundingHouseOrigin.ORIGINAL_FOUNDER,
		CharacterDefinition.AgeStage.ADULT
	)
	assert_false(bad_community_origin.is_valid(), "COMMUNITY cannot carry ORIGINAL_FOUNDER origin")

	var bad_founder_none := _make_def(
		&"bad_2", "Bad 2",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.NONE,
		CharacterDefinition.AgeStage.ADULT
	)
	assert_false(bad_founder_none.is_valid(), "FOUNDING_HOUSE cannot carry NONE origin")

	var bad_founder_youth := _make_def(
		&"bad_3", "Bad 3",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.ORIGINAL_FOUNDER,
		CharacterDefinition.AgeStage.YOUTH
	)
	assert_false(bad_founder_youth.is_valid(), "ORIGINAL_FOUNDER must be ADULT")

	var bad_spouse_youth := _make_def(
		&"bad_4", "Bad 4",
		CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE,
		CharacterDefinition.FoundingHouseOrigin.EXTERNAL_SPOUSE,
		CharacterDefinition.AgeStage.YOUTH
	)
	assert_false(bad_spouse_youth.is_valid(), "EXTERNAL_SPOUSE must be ADULT")

	# Invalid metadata grants ZERO permissions.
	var u_bad: Unit = _spawn_unit(bad_community_origin, "BadMetaUnit")
	await wait_process_frames(1)
	assert_false(UnitControlPermissions.can_be_selected_visually(u_bad))
	assert_false(UnitControlPermissions.can_be_inspected(u_bad))
	assert_false(UnitControlPermissions.can_receive_personal_order(u_bad, UnitControlPermissions.PersonalCommandKind.MOVE))
	assert_false(UnitControlPermissions.can_participate_in_community_work(u_bad, WorkTask.Kind.GATHER_FOOD))
	assert_false(UnitControlPermissions.can_perform_recovery_order(u_bad))


func test_b01_b02_b03_age_stage_permission_matrix() -> void:
	var baby_founder := _spawn_unit(_make_def(&"baby_f", "Bebe F", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.BABY), "BabyF")
	var baby_common := _spawn_unit(_make_def(&"baby_c", "Bebe C", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.BABY), "BabyC")
	var child_founder := _spawn_unit(_make_def(&"child_f", "Crianca F", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.CHILD), "ChildF")
	var child_common := _spawn_unit(_make_def(&"child_c", "Crianca C", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.CHILD), "ChildC")
	var youth_founder := _spawn_unit(_make_def(&"youth_f", "Jovem F", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.YOUTH), "YouthF")
	var youth_common := _spawn_unit(_make_def(&"youth_c", "Jovem C", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.YOUTH), "YouthC")
	var adult_common := _spawn_unit(_make_def(&"adult_c", "Adulto C", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.ADULT), "AdultC")
	await wait_process_frames(1)

	# B01: BABY totally blocked in map selection, inspection, personal, community, recovery.
	for baby: Unit in [baby_founder, baby_common]:
		assert_false(UnitControlPermissions.can_be_selected_visually(baby), "BABY cannot be selected on map")
		assert_false(UnitControlPermissions.can_be_inspected(baby), "BABY cannot be inspected on map")
		assert_false(UnitControlPermissions.can_receive_personal_order(baby, UnitControlPermissions.PersonalCommandKind.MOVE))
		assert_false(UnitControlPermissions.can_receive_personal_order(baby, UnitControlPermissions.PersonalCommandKind.GATHER_FOOD))
		assert_false(UnitControlPermissions.can_participate_in_community_work(baby, WorkTask.Kind.GATHER_FOOD))
		assert_false(UnitControlPermissions.can_perform_recovery_order(baby))

	# B02: CHILD (Founding House) -> light/safe personal & community ALLOWED; heavy FORBIDDEN.
	assert_true(UnitControlPermissions.can_be_selected_visually(child_founder))
	assert_true(UnitControlPermissions.can_receive_personal_order(child_founder, UnitControlPermissions.PersonalCommandKind.MOVE))
	assert_true(UnitControlPermissions.can_receive_personal_order(child_founder, UnitControlPermissions.PersonalCommandKind.GATHER_FOOD))
	assert_true(UnitControlPermissions.can_receive_personal_order(child_founder, UnitControlPermissions.PersonalCommandKind.DELIVER_TO_CAMP))
	assert_false(UnitControlPermissions.can_receive_personal_order(child_founder, UnitControlPermissions.PersonalCommandKind.GATHER_WOOD))
	assert_false(UnitControlPermissions.can_receive_personal_order(child_founder, UnitControlPermissions.PersonalCommandKind.GATHER_STONE))
	assert_false(UnitControlPermissions.can_receive_personal_order(child_founder, UnitControlPermissions.PersonalCommandKind.CONSTRUCT_SITE))
	assert_eq(UnitControlPermissions.get_personal_order_rejection_reason(child_founder, UnitControlPermissions.PersonalCommandKind.GATHER_WOOD), "age_restricted_task")
	assert_true(UnitControlPermissions.can_participate_in_community_work(child_founder, WorkTask.Kind.GATHER_FOOD))
	assert_false(UnitControlPermissions.can_participate_in_community_work(child_founder, WorkTask.Kind.GATHER_WOOD))
	assert_false(UnitControlPermissions.can_participate_in_community_work(child_founder, WorkTask.Kind.GATHER_STONE))
	assert_false(UnitControlPermissions.can_perform_recovery_order(child_founder), "CHILD must not receive heavy construction recovery")

	# B02: CHILD (COMMUNITY) -> read-only inspection + light community work ONLY; ZERO personal commands.
	assert_true(UnitControlPermissions.can_be_selected_visually(child_common))
	assert_true(UnitControlPermissions.is_read_only_community_unit(child_common))
	assert_false(UnitControlPermissions.can_receive_personal_order(child_common, UnitControlPermissions.PersonalCommandKind.MOVE))
	assert_false(UnitControlPermissions.can_receive_personal_order(child_common, UnitControlPermissions.PersonalCommandKind.GATHER_FOOD))
	assert_eq(UnitControlPermissions.get_personal_order_rejection_reason(child_common, UnitControlPermissions.PersonalCommandKind.MOVE), "personal_control_denied")
	assert_true(UnitControlPermissions.can_participate_in_community_work(child_common, WorkTask.Kind.GATHER_FOOD))
	assert_false(UnitControlPermissions.can_participate_in_community_work(child_common, WorkTask.Kind.GATHER_WOOD))
	assert_false(UnitControlPermissions.can_participate_in_community_work(child_common, WorkTask.Kind.GATHER_STONE))
	assert_false(UnitControlPermissions.can_perform_recovery_order(child_common))

	# B03: YOUTH & ADULT
	assert_true(UnitControlPermissions.can_receive_personal_order(youth_founder, UnitControlPermissions.PersonalCommandKind.GATHER_WOOD))
	assert_true(UnitControlPermissions.can_receive_personal_order(youth_founder, UnitControlPermissions.PersonalCommandKind.CONSTRUCT_SITE))
	assert_true(UnitControlPermissions.can_participate_in_community_work(youth_founder, WorkTask.Kind.GATHER_STONE))
	assert_true(UnitControlPermissions.can_perform_recovery_order(youth_founder))

	assert_false(UnitControlPermissions.can_receive_personal_order(youth_common, UnitControlPermissions.PersonalCommandKind.MOVE))
	assert_true(UnitControlPermissions.can_participate_in_community_work(youth_common, WorkTask.Kind.GATHER_WOOD))
	assert_true(UnitControlPermissions.can_perform_recovery_order(youth_common))

	assert_true(UnitControlPermissions.can_be_selected_visually(adult_common))
	assert_true(UnitControlPermissions.is_read_only_community_unit(adult_common))
	assert_false(UnitControlPermissions.can_receive_personal_order(adult_common, UnitControlPermissions.PersonalCommandKind.MOVE))
	assert_true(UnitControlPermissions.can_participate_in_community_work(adult_common, WorkTask.Kind.GATHER_WOOD))
	assert_true(UnitControlPermissions.can_perform_recovery_order(adult_common))
	assert_false(UnitControlPermissions.can_join_manual_team_future(adult_common, WorkTask.Kind.GATHER_WOOD))


func test_order_origin_defaults() -> void:
	var move := MoveOrder.new(Vector3.ZERO)
	assert_eq(move.get_order_origin(), UnitOrder.OrderOrigin.NONE, "Unadmitted order must have OrderOrigin.NONE")
