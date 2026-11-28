extends TestCase
## Unit tests for R-03B B3:
## - UnitControlState 4th ControlMode (PERSONAL_POST_MOVE_WAIT) & helpers
## - Unit.personal_post_move_wait_sec experimental provisional default (8.0 s), options [3, 8, 15], bounds
## - Lazy timer absence at spawn and for COMMUNITY units
## - HudFormatter discrete labels (B0-Q07 A / B0-A05) with strictly ZERO countdown/timer digits.

const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")


func _make_def(
	cid: StringName,
	display: String,
	aff: CharacterDefinition.HouseAffiliation,
	orig: CharacterDefinition.FoundingHouseOrigin,
	age: CharacterDefinition.AgeStage
) -> CharacterDefinition:
	var def := CharacterDefinition.new()
	def.character_id = cid
	def.display_name = display
	def.house_affiliation = aff
	def.founding_house_origin = orig
	def.age_stage = age
	return def


func _spawn_unit(def: CharacterDefinition, node_name: String) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = node_name
	u.definition = def
	add_test_child(u)
	return u


func test_unit_control_state_personal_post_move_wait_enum_and_helpers() -> void:
	var cs := UnitControlState.new()
	assert_eq(UnitControlState.ControlMode.size(), 4)
	assert_eq(int(UnitControlState.ControlMode.COMMUNITY_FREE), 0)
	assert_eq(int(UnitControlState.ControlMode.COMMUNITY_WORKING), 1)
	assert_eq(int(UnitControlState.ControlMode.PERSONAL_ACTIVE), 2)
	assert_eq(int(UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT), 3)

	assert_true(cs.is_community_free())
	assert_false(cs.is_personal_active())
	assert_false(cs.is_personal_post_move_wait())
	assert_false(cs.is_personal_controlled())

	cs._apply_internal(UnitControlState.ControlMode.PERSONAL_ACTIVE, UnitOrder.OrderOrigin.PERSONAL)
	assert_true(cs.is_personal_active())
	assert_false(cs.is_personal_post_move_wait())
	assert_true(cs.is_personal_controlled())
	assert_eq(cs.get_mode_name(), "PERSONAL_ACTIVE")

	cs._apply_internal(UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, UnitOrder.OrderOrigin.NONE)
	assert_false(cs.is_community_free())
	assert_false(cs.is_personal_active())
	assert_true(cs.is_personal_post_move_wait())
	assert_true(cs.is_personal_controlled())
	assert_eq(cs.get_mode_name(), "PERSONAL_POST_MOVE_WAIT")
	assert_eq(cs.get_active_origin(), UnitOrder.OrderOrigin.NONE)

	var delta: Dictionary = cs._commit_published_mode()
	assert_true(bool(delta["changed"]))
	assert_eq(delta["previous_mode"], UnitControlState.ControlMode.COMMUNITY_FREE)
	assert_eq(delta["new_mode"], UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	assert_false(bool(cs._commit_published_mode()["changed"]))


func test_unit_experimental_wait_defaults_bounds_and_lazy_timer_invariant() -> void:
	assert_eq(Unit.EXPERIMENTAL_POST_MOVE_WAIT_OPTIONS_SEC, [3.0, 8.0, 15.0])
	assert_true(is_equal_approx(Unit.DEFAULT_EXPERIMENTAL_POST_MOVE_WAIT_SEC, 8.0))

	var founder := _spawn_unit(LEADER_A_DEF, "FounderWaitUnit")
	var community := _spawn_unit(
		_make_def(&"comm_wait_u", "Comm Wait", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.ADULT),
		"CommWaitUnit"
	)
	await wait_process_frames(1)

	assert_true(is_equal_approx(founder.personal_post_move_wait_sec, 8.0), "Experimental provisional default must be 8.0 s")
	assert_false(founder.has_personal_wait_timer(), "Wait timer must be lazy — absent at spawn")
	assert_false(founder.is_personal_wait_timer_active())
	assert_true(is_equal_approx(founder.get_personal_wait_time_left(), 0.0))
	assert_false(community.has_personal_wait_timer(), "COMMUNITY unit must NOT instantiate wait timer")

	# Setter clamping for invalid/negative/non-finite values
	founder.personal_post_move_wait_sec = -5.0
	assert_true(is_equal_approx(founder.personal_post_move_wait_sec, 0.0))
	founder.personal_post_move_wait_sec = NAN
	assert_true(is_equal_approx(founder.personal_post_move_wait_sec, 0.0))
	founder.personal_post_move_wait_sec = INF
	assert_true(is_equal_approx(founder.personal_post_move_wait_sec, 0.0))
	for opt: float in Unit.EXPERIMENTAL_POST_MOVE_WAIT_OPTIONS_SEC:
		founder.personal_post_move_wait_sec = opt
		assert_true(is_equal_approx(founder.personal_post_move_wait_sec, opt))

	# Rejected personal order on COMMUNITY unit never instantiates wait timer
	assert_false(community.issue_personal_order(MoveOrder.new(Vector3.ZERO)))
	assert_false(community.has_personal_wait_timer(), "COMMUNITY unit must never instantiate wait timer even after refused personal order")


func test_hud_formatter_discrete_labels_have_zero_countdown_or_digits() -> void:
	var founder := _spawn_unit(LEADER_A_DEF, "FounderHudUnit")
	var community := _spawn_unit(
		_make_def(&"comm_hud_u", "Comm Hud", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.ADULT),
		"CommHudUnit"
	)
	await wait_process_frames(1)

	var digit_re := RegEx.new()
	digit_re.compile("[0-9]")

	# Founding House COMMUNITY_FREE
	var lbl_free: String = HudFormatter.format_unit_inspection_meta(founder, null)
	assert_eq(lbl_free, "Trabalho comunitário")
	assert_null(digit_re.search(lbl_free), "Discrete label must contain zero digits/countdown")

	# Founding House PERSONAL_ACTIVE
	founder._control_state._apply_internal(UnitControlState.ControlMode.PERSONAL_ACTIVE, UnitOrder.OrderOrigin.PERSONAL)
	var lbl_personal: String = HudFormatter.format_unit_inspection_meta(founder, null)
	assert_eq(lbl_personal, "Ordem pessoal")
	assert_null(digit_re.search(lbl_personal))

	# Founding House PERSONAL_POST_MOVE_WAIT
	founder._control_state._apply_internal(UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, UnitOrder.OrderOrigin.NONE)
	var lbl_wait: String = HudFormatter.format_unit_inspection_meta(founder, null)
	assert_eq(lbl_wait, "Aguardando retorno")
	assert_null(digit_re.search(lbl_wait), "PERSONAL_POST_MOVE_WAIT label must NEVER display countdown or remaining seconds")
	assert_false(lbl_wait.to_lower().contains("seg"), "Wait label must not mention seconds")

	# Founding House COMMUNITY_WORKING
	founder._control_state._apply_internal(UnitControlState.ControlMode.COMMUNITY_WORKING, UnitOrder.OrderOrigin.COMMUNITY)
	var lbl_work: String = HudFormatter.format_unit_inspection_meta(founder, null)
	assert_eq(lbl_work, "Trabalho comunitário")
	assert_null(digit_re.search(lbl_work))

	# COMMUNITY read-only resident
	var lbl_comm: String = HudFormatter.format_unit_inspection_meta(community, null)
	assert_eq(lbl_comm, "Morador — somente leitura")
	assert_null(digit_re.search(lbl_comm))

	# Null unit returns empty
	assert_eq(HudFormatter.format_unit_inspection_meta(null, null), "")
