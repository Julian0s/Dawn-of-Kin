extends TestCase

const InspectorFixture := preload("res://tests/integration/test_t3_5_2_building_inspector.gd")
const RecoveryFixture := preload("res://tests/integration/test_t3_6_3_b1_2_cancellation_commit_transaction.gd")
const COORD := preload("res://src/economy/reserved_withdrawal_coordinator.gd")


func _scene(provenance: bool = true) -> Dictionary:
	var fixture := InspectorFixture.new()
	add_test_child(fixture)
	var ctx := await fixture._fixture(provenance)
	var main: MainScene = ctx.main
	main.get_economy_clock().set_process(false)
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 24))
	assert_true(inv.deposit(&"stone", 12))
	ctx.site = main.get_construction_manager().try_create_site_from_placement(InspectorFixture.SHELTER, InspectorFixture.SITE_A).get("site")
	assert_not_null(ctx.site)
	ctx.fixture = fixture
	return ctx


func test_d3_entry_exists_in_playable_inspector() -> void:
	var ctx := await _scene()
	var ui: BuildingInspectorPanel = ctx.ui
	var site: ConstructionSite = ctx.site
	ui.set_site(site)
	assert_true(ui._d3_begin.visible, "The playable inspector must provide a D3 preview")
	site._site_state = ConstructionSite.SiteState.COMPLETING
	ui._refresh()
	assert_false(ui._d3_begin.visible)
	site._site_state = ConstructionSite.SiteState.ACTIVE
	(ctx.main as MainScene).get_construction_manager()._completion_in_progress = true
	ui._refresh()
	assert_false(ui._d3_begin.visible, "Completion transaction must exclude cancellation")
	(ctx.main as MainScene).get_construction_manager()._completion_in_progress = false
	var incompatible := await _scene(false)
	ui = incompatible.ui
	ui.set_site(incompatible.site)
	assert_false(ui._d3_begin.visible)
	ui._begin_d3()
	assert_true(ui._d3_plan.is_empty())
	assert_true((incompatible.site as ConstructionSite).is_active())


func test_preview_mouse_readonly_and_repeat_confirmation() -> void:
	var ctx := await _scene()
	var main: MainScene = ctx.main
	var ui: BuildingInspectorPanel = ctx.ui
	var site: ConstructionSite = ctx.site
	var inv := main.get_settlement_inventory()
	var reserved := inv.get_reservation_amounts(site.reservation_id)
	var stock := inv.get_all_physical_amounts()
	var revision := site.get_transaction_revision()
	var worker := main.get_units()[0]
	main.get_selection_manager().select_single(worker)
	ui.set_site(site)
	await wait_process_frames(2)
	await ctx.fixture._click(ctx.vp, ui._d3_begin.get_global_rect().get_center())
	assert_false(ui._d3_plan.is_empty())
	assert_eq(inv.get_all_physical_amounts(), stock)
	assert_eq(inv.get_reservation_amounts(site.reservation_id), reserved)
	assert_eq(site.get_transaction_revision(), revision)
	assert_null(worker.get_current_order())
	assert_true(main.get_selection_manager().is_selected(worker))
	assert_string_contains(ui._plan.text, "S 12  T 0  B 0  K 0  D 0  M 0")
	var plan := ui._d3_plan
	if plan.is_empty():
		return
	var during_commit: Array = []
	var cb := func() -> void:
		ui._confirm_d3()
		during_commit.append(ui._d3_plan.is_empty())
	inv.reservations_changed.connect(cb)
	await wait_process_frames(2)
	await ctx.fixture._click(ctx.vp, ui._d3_confirm.get_global_rect().get_center())
	inv.reservations_changed.disconnect(cb)
	ui._confirm_d3()
	assert_eq(during_commit, [true])
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.CANCELLED)
	assert_eq(inv.get_all_physical_amounts(), stock)
	assert_false(inv.has_reservation(site.reservation_id))
	assert_true(COORD.execute_site_cancellation(site, plan.operation, plan).replayed)
	assert_string_contains(ui._state.text, "concluída")
	site.queue_free()
	await wait_process_frames(2)
	ui.set_site(null)
	assert_true(ui._recovery_open.visible)
	ui._open_recovery()
	assert_string_contains(ui._state.text, "concluída")


func test_selection_removal_and_decay_reject_old_confirmation() -> void:
	var ctx := await _scene()
	var main: MainScene = ctx.main
	var ui: BuildingInspectorPanel = ctx.ui
	var site: ConstructionSite = ctx.site
	var other: ConstructionSite = main.get_construction_manager().try_create_site_from_placement(InspectorFixture.SHELTER, InspectorFixture.SITE_B).site
	ui.set_site(site)
	ui._begin_d3()
	ui.set_site(other)
	ui._confirm_d3()
	assert_true(site.is_active() and other.is_active())
	ui._begin_d3()
	other.queue_free()
	ui._confirm_d3()
	assert_true(other.is_active())
	await wait_process_frames(2)
	ui.set_site(site)
	ui._begin_d3()
	assert_false(ui._d3_plan.is_empty())
	var piles := main.get_ground_pile_manager()
	for pile: GroundResourcePile in piles.get_piles():
		if pile.resource_id == &"wood":
			pile.apply_state(pile.amount, 420.0, 0.0)
	main.get_time_provider().advance(3600.0)
	main.get_ground_pile_manager().step_decay()
	var remaining := main.get_settlement_inventory().get_reservation_amounts(site.reservation_id)
	assert_true(int(remaining.get(&"wood", 0)) < 12, "Decay must actually change the site reservation")
	ui._confirm_d3()
	assert_true(site.is_active())
	assert_true(ui._d3_plan.is_empty())
	assert_eq(main.get_settlement_inventory().get_reservation_amounts(site.reservation_id), remaining)
	assert_string_contains(ui._message.text, "nova prévia")
	assert_true(ui._complement.visible, str(site.get_complementable_missing_amounts()))
	ui._begin_d3()
	assert_false(ui._d3_plan.is_empty(), ui._message.text)
	assert_string_contains(ui._plan.text, "M %d" % (12 - int(remaining.get(&"wood", 0))))
	site._site_state = ConstructionSite.SiteState.COMPLETING
	ui._confirm_d3()
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	site._site_state = ConstructionSite.SiteState.ACTIVE


func test_physical_dispatch_tracking_manual_priority_and_settlement() -> void:
	var ctx := await _scene()
	var main: MainScene = ctx.main
	var ui: BuildingInspectorPanel = ctx.ui
	var site: ConstructionSite = ctx.site
	var worker := main.get_units()[0]
	var fixture := RecoveryFixture.new()
	add_test_child(fixture)
	fixture._withdraw(main, site, worker, &"ui_take", &"ui_lot")
	ui.set_site(site)
	ui._begin_d3()
	assert_eq(ui._d3_plan.economics[&"wood"].in_transit, 2)
	ui._confirm_d3()
	var id := ui._tracking_id
	assert_false(id.is_empty())
	if id.is_empty():
		return
	assert_string_contains(ui._materials.text, "0 | 2 | 0 | 0")
	await wait_physics_frames(2)
	assert_true(worker.get_current_order() is RecoveryOrder)
	var manual := MoveOrder.new(worker.global_position + Vector3(0.8, 0, 0.8))
	worker.issue_order(manual)
	ui._refresh()
	assert_string_contains(ui._state.text, "bloqueada")
	assert_string_contains(ui._message.text, "ordem manual")
	assert_true(await fixture._until(func() -> bool: return manual.is_finished(), 500))
	assert_false(worker.get_current_order() is RecoveryOrder)
	assert_eq(worker.get_carry_load().get_amount(&"wood"), 2)
	site.queue_free()
	await wait_process_frames(2)
	ui._refresh()
	assert_string_contains(ui._materials.text, "0 | 2 | 0 | 0")
	assert_true(main.get_construction_manager().assign_cancellation_recovery(id, [worker]).ok)
	assert_true(await fixture._until(func() -> bool:
		return COORD.get_cancellation_custody_readonly(main.get_world_3d(), &"default", id).snapshot.state == ConstructionCancellationMath.State.SETTLED
	, 1200))
	ui._refresh()
	assert_string_contains(ui._state.text, "concluída")
	assert_string_contains(ui._materials.text, "0 | 0 | 2 | 0")

func test_integrated_preview_of_incorporated_and_local_materials() -> void:
	var fixture := RecoveryFixture.new()
	add_test_child(fixture)
	fixture.before_each()
	var main := await fixture._fixture(true)
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site := fixture._site(main, InspectorFixture.SITE_A)
	assert_true(main.get_command_controller().command_units_to_site(site, main.get_units()))
	assert_true(await fixture._until(func() -> bool: return site._work_progress_usec >= 15_000_000, 6500))
	var ui := main.get_node("UiLayer/BuildingInspectorPanel") as BuildingInspectorPanel
	ui.set_site(site)
	ui._begin_d3()
	assert_string_contains(ui._plan.text, "Madeira  S 0  T 0  B 6  K 1  D 5  M 0")
	assert_string_contains(ui._plan.text, "Pedra  S 0  T 0  B 3  K 0  D 3  M 0")
	ui._confirm_d3()
	assert_string_contains(ui._materials.text, "Madeira: 7 | 0 | 0 | 5")
	assert_string_contains(ui._state.text, "pendente")
	var id := ui._tracking_id
	assert_false(id.is_empty())
	if not id.is_empty():
		assert_true(await fixture._until(func() -> bool:
			return COORD.get_cancellation_custody_readonly(main.get_world_3d(), &"default", id).snapshot.state == ConstructionCancellationMath.State.SETTLED
		, 6500))
		ui._refresh()
		assert_string_contains(ui._materials.text, "Madeira: 0 | 0 | 7 | 5")
		assert_string_contains(ui._state.text, "concluída")
	fixture.after_each()

func test_withdrawal_after_preview_makes_confirmation_stale() -> void:
	var ctx := await _scene()
	var main: MainScene = ctx.main
	var ui: BuildingInspectorPanel = ctx.ui
	var site: ConstructionSite = ctx.site
	var worker := main.get_units()[0]
	ui.set_site(site)
	ui._begin_d3()
	assert_false(ui._d3_plan.is_empty())
	var fixture := RecoveryFixture.new()
	add_test_child(fixture)
	fixture._withdraw(main, site, worker, &"ui_stale_take", &"ui_stale_lot")
	var snapshot := worker.get_carry_load().provenance_snapshot()
	assert_eq(worker.get_carry_load().get_amount(&"wood"), 2)
	ui._confirm_d3()
	assert_true(site.is_active())
	assert_eq(worker.get_carry_load().provenance_snapshot(), snapshot)
	assert_string_contains(ui._message.text, "nova prévia")
