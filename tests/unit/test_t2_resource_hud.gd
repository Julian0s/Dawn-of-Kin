extends TestCase
## Unit tests for T2.5 HUD formatting, panels, signal binding/unbinding,
## redundancy guards, overload clamping, exposure indicator, and selection modes.

const RESOURCE_HUD_SCENE: PackedScene = preload("res://src/ui/resource_hud.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const LEADER_B_DEF: CharacterDefinition = preload("res://data/characters/leader_b.tres")
const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")


func _create_unit(def: CharacterDefinition, unit_name: String) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.name = unit_name
	unit.definition = def
	add_test_child(unit)
	return unit


func _create_hud_stack() -> Dictionary:
	var piles_root := Node3D.new()
	piles_root.name = "TestCampPiles"
	add_test_child(piles_root)

	var camp_zone := CampStorageZone.new()
	camp_zone.name = "TestCampZone"
	add_test_child(camp_zone)

	var time_provider := SimulatedWorldTimeProvider.new(0.0)
	var definitions: Dictionary = {
		&"food": FOOD_RES,
		&"wood": WOOD_RES,
		&"stone": STONE_RES,
	}
	var pile_manager := GroundPileManager.new(definitions, camp_zone, piles_root, time_provider)
	var inventory := SettlementInventory.new(pile_manager)
	var selection := SelectionManager.new()
	selection.name = "TestSelectionManager"
	add_test_child(selection)

	var hud: ResourceHud = RESOURCE_HUD_SCENE.instantiate() as ResourceHud
	add_test_child(hud)
	hud.configure(inventory, selection, camp_zone, pile_manager)

	return {
		"piles_root": piles_root,
		"camp_zone": camp_zone,
		"time_provider": time_provider,
		"pile_manager": pile_manager,
		"inventory": inventory,
		"selection": selection,
		"hud": hud,
		"stockpile": hud.get_stockpile_panel(),
		"unit_panel": hud.get_selected_unit_panel(),
	}


func test_01_stockpile_starts_zero_and_syncs_deposit_withdraw_and_decay() -> void:
	var ctx: Dictionary = _create_hud_stack()
	var stockpile: SettlementStockpilePanel = ctx["stockpile"] as SettlementStockpilePanel
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var time_provider: SimulatedWorldTimeProvider = ctx["time_provider"] as SimulatedWorldTimeProvider
	await wait_process_frames(1)

	assert_eq(stockpile.get_displayed_amount(&"wood"), 0)
	assert_eq(stockpile.get_displayed_amount(&"stone"), 0)
	assert_eq(stockpile.get_displayed_amount(&"food"), 0)
	assert_eq(stockpile.get_wood_value_text(), "0")
	assert_eq(stockpile.get_stone_value_text(), "0")
	assert_eq(stockpile.get_food_value_text(), "0")
	assert_eq(stockpile.get_exposure_text(), "Armazenamento: exposto")

	assert_true(pile_manager.deposit_batch({&"wood": 7, &"stone": 4, &"food": 5}))
	assert_eq(stockpile.get_displayed_amount(&"wood"), 7)
	assert_eq(stockpile.get_displayed_amount(&"stone"), 4)
	assert_eq(stockpile.get_displayed_amount(&"food"), 5)
	assert_eq(stockpile.get_wood_value_text(), "7")
	assert_eq(stockpile.get_stone_value_text(), "4")
	assert_eq(stockpile.get_food_value_text(), "5")

	# Consumption updates HUD immediately
	assert_true(inventory.withdraw(&"wood", 3))
	assert_eq(stockpile.get_displayed_amount(&"wood"), 4)
	assert_eq(stockpile.get_wood_value_text(), "4")

	# Decay updates HUD immediately (food grace 180s + 2 * 45s = 270s -> 280s loses 2 food)
	time_provider.advance(280.0)
	var losses: Dictionary = pile_manager.step_decay()
	assert_eq(int(losses.get(&"food", 0)), 2)
	assert_eq(stockpile.get_displayed_amount(&"food"), 3)
	assert_eq(stockpile.get_food_value_text(), "3")

	# Protected zone check (T3 preparation) without countdown invention
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	camp_zone.decay_multiplier = 0.0
	stockpile.refresh()
	assert_eq(stockpile.get_exposure_text(), "Armazenamento: protegido")
	assert_false(stockpile.get_exposure_text().contains("s"))
	pile_manager.cleanup()


func test_02_carry_load_percentage_partial_full_and_overload() -> void:
	var ctx: Dictionary = _create_hud_stack()
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var unit_panel: SelectedUnitPanel = ctx["unit_panel"] as SelectedUnitPanel
	var unit: Unit = _create_unit(LEADER_A_DEF, "LeaderA")
	await wait_process_frames(1)

	selection.select_single(unit)
	assert_true(unit_panel.visible)
	assert_eq(unit_panel.get_selection_mode(), SelectedUnitPanel.SelectionMode.SINGLE)
	assert_eq(unit_panel.get_header_text(), "Leader A")
	assert_eq(unit_panel.get_state_text(), "Ocioso")
	assert_eq(unit_panel.get_percentage_text(), "0%")
	assert_near(unit_panel.get_bar_value(), 0.0, 0.01)
	assert_eq(unit_panel.get_weight_text(), "Carga: 0 / 20")

	# 6 stones = 18 / 20 = 90%, even though 7th stone (+3) cannot fit
	var load: UnitCarryLoad = unit.get_carry_load()
	assert_true(load.add_units(STONE_RES, 6))
	assert_false(load.can_fit_one(STONE_RES))
	assert_eq(unit_panel.get_percentage_text(), "90%")
	assert_near(unit_panel.get_bar_value(), 90.0, 0.01)
	assert_eq(unit_panel.get_weight_text(), "Carga: 18 / 20")
	assert_eq(unit_panel.get_carried_text(&"stone"), "Pedra: 6")

	# Fill to 100% with 2 food (weight 20 / 20)
	assert_true(load.add_units(FOOD_RES, 2))
	assert_eq(unit_panel.get_percentage_text(), "100%")
	assert_near(unit_panel.get_bar_value(), 100.0, 0.01)
	assert_eq(unit_panel.get_weight_text(), "Carga: 20 / 20")
	assert_eq(unit_panel.get_carried_text(&"food"), "Alimentos: 2")

	# Overload via capacity modifier removal: 26 / 20 -> bar stays <= 100, real weight visible
	assert_true(load.set_capacity_modifier(&"pack", 10))
	assert_true(load.add_units(WOOD_RES, 3)) # +6 -> 26 / 30
	assert_true(load.remove_capacity_modifier(&"pack")) # 26 / 20 overloaded
	assert_true(load.is_overloaded())
	assert_eq(unit_panel.get_percentage_text(), "100%")
	assert_true(unit_panel.get_bar_value() <= 100.0, "Overload progress bar must never exceed 100")
	assert_near(unit_panel.get_bar_value(), 100.0, 0.01)
	assert_eq(unit_panel.get_weight_text(), "Carga: 26 / 20 (sobrecarga)")
	assert_eq(unit_panel.get_carried_text(&"wood"), "Madeira: 3")
	(ctx["pile_manager"] as GroundPileManager).cleanup()


func test_03_unit_states_and_selection_modes_empty_single_multi() -> void:
	var ctx: Dictionary = _create_hud_stack()
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var stockpile: SettlementStockpilePanel = ctx["stockpile"] as SettlementStockpilePanel
	var unit_panel: SelectedUnitPanel = ctx["unit_panel"] as SelectedUnitPanel
	var unit_a: Unit = _create_unit(LEADER_A_DEF, "LeaderA")
	var unit_b: Unit = _create_unit(LEADER_B_DEF, "LeaderB")
	await wait_process_frames(1)

	# Empty selection: stockpile visible, unit panel hidden
	assert_true(stockpile.visible)
	assert_false(unit_panel.visible)
	assert_eq(unit_panel.get_selection_mode(), SelectedUnitPanel.SelectionMode.EMPTY)

	# Single selection: verify all Unit.State translations via real state transitions
	selection.select_single(unit_a)
	assert_eq(unit_panel.get_state_text(), "Ocioso")
	unit_a._set_state(Unit.State.MOVING)
	assert_eq(unit_panel.get_state_text(), "Deslocando")
	unit_a._set_state(Unit.State.WORKING)
	assert_eq(unit_panel.get_state_text(), "Trabalhando")
	unit_a._set_state(Unit.State.TRANSPORTING)
	assert_eq(unit_panel.get_state_text(), "Transportando")
	unit_a._set_state(Unit.State.IDLE)
	assert_eq(unit_panel.get_state_text(), "Ocioso")

	# Multi selection: shows count, hides single load details and never averages loads
	assert_true(unit_a.get_carry_load().add_units(WOOD_RES, 4))
	selection.add_unit(unit_b)
	assert_true(unit_panel.visible)
	assert_eq(unit_panel.get_selection_mode(), SelectedUnitPanel.SelectionMode.MULTI)
	assert_eq(unit_panel.get_selected_count(), 2)
	assert_eq(unit_panel.get_header_text(), "2 selecionados")
	assert_false(unit_panel.is_single_details_visible())
	assert_true(unit_panel.is_multi_summary_visible())
	assert_false(unit_panel.is_bound_to_unit(unit_a))
	assert_false(unit_panel.is_bound_to_unit(unit_b))

	# Clear selection: returns to hidden without touching stockpile
	selection.clear_selection()
	assert_false(unit_panel.visible)
	assert_true(stockpile.visible)
	(ctx["pile_manager"] as GroundPileManager).cleanup()


func test_04_rapid_switch_unit_removal_no_redundant_updates_and_clean_unbind() -> void:
	var ctx: Dictionary = _create_hud_stack()
	var hud: ResourceHud = ctx["hud"] as ResourceHud
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var pile_manager: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var stockpile: SettlementStockpilePanel = ctx["stockpile"] as SettlementStockpilePanel
	var unit_panel: SelectedUnitPanel = ctx["unit_panel"] as SelectedUnitPanel

	var unit_a: Unit = _create_unit(LEADER_A_DEF, "LeaderA")
	var unit_b: Unit = _create_unit(LEADER_B_DEF, "LeaderB")
	assert_true(unit_a.get_carry_load().add_units(FOOD_RES, 3))
	assert_true(unit_b.get_carry_load().add_units(STONE_RES, 2))
	await wait_process_frames(2)

	# Zero per-frame polling on HUD nodes
	assert_false(hud.is_processing())
	assert_false(hud.is_physics_processing())
	assert_false(stockpile.is_processing())
	assert_false(unit_panel.is_processing())

	# Rapid selection switches disconnect old unit signals cleanly
	selection.select_single(unit_a)
	assert_eq(unit_panel.get_header_text(), "Leader A")
	assert_eq(unit_panel.get_carried_text(&"food"), "Alimentos: 3")
	assert_true(unit_panel.is_bound_to_unit(unit_a))

	selection.select_single(unit_b)
	assert_eq(unit_panel.get_header_text(), "Leader B")
	assert_eq(unit_panel.get_carried_text(&"stone"), "Pedra: 2")
	assert_false(unit_panel.is_bound_to_unit(unit_a))
	assert_true(unit_panel.is_bound_to_unit(unit_b))

	# Mutating unit_a while unit_b is selected must NOT update unit_panel
	var applies_before: int = unit_panel.get_apply_count()
	var stock_applies_before: int = stockpile.get_apply_count()
	assert_true(unit_a.get_carry_load().add_units(FOOD_RES, 2))
	unit_a._set_state(Unit.State.WORKING)
	await wait_process_frames(3)
	assert_eq(unit_panel.get_apply_count(), applies_before, "Idle frames and unselected unit mutations must not trigger UI updates")
	assert_eq(stockpile.get_apply_count(), stock_applies_before)

	# Redundant same-selection / same-value refresh must NOT trigger UI re-apply
	selection.select_single(unit_b)
	unit_panel.refresh()
	stockpile.refresh()
	assert_eq(unit_panel.get_apply_count(), applies_before)
	assert_eq(stockpile.get_apply_count(), stock_applies_before)

	# Inventory change updates stockpile only, not selected unit panel
	assert_true(pile_manager.deposit_batch({&"wood": 5}))
	assert_eq(stockpile.get_apply_count(), stock_applies_before + 1)
	assert_eq(unit_panel.get_apply_count(), applies_before)

	# Removing selected unit from SceneTree cleans up HUD without errors
	unit_b.queue_free()
	await wait_process_frames(2)
	assert_false(unit_panel.visible)
	assert_eq(unit_panel.get_selection_mode(), SelectedUnitPanel.SelectionMode.EMPTY)
	assert_null(unit_panel.get_tracked_unit())

	# Explicit unbind disconnects SelectionManager and SettlementInventory signals
	hud.unbind()
	assert_false(hud.is_bound_to_selection_manager(selection))
	assert_false(stockpile.is_bound_to_inventory(inventory))
	pile_manager.cleanup()
