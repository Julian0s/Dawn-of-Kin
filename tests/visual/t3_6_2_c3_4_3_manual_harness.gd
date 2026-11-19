extends SceneTree
## Removable standalone development harness for manual visual validation of T3.6.2-C3.4.3.
## Keeps production scenes and permanent HUD completely untouched.
## Launch:
##   Godot --path "C:\Projetos\Dawn_of_Kin_wt_t3_4_5" --script "res://tests/visual/t3_6_2_c3_4_3_manual_harness.gd"

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")


class HarnessController extends Node:
	var main: MainScene = null
	var nav: WorldNavigation = null
	var site_a: ConstructionSite = null
	var site_b: ConstructionSite = null
	var seq: int = 0
	var last_order: UnitOrder = null

	func _unhandled_key_input(event: InputEvent) -> void:
		if not (event is InputEventKey):
			return
		var key_ev: InputEventKey = event as InputEventKey
		if not key_ev.pressed or key_ev.echo or not key_ev.ctrl_pressed:
			return
		match key_ev.keycode:
			KEY_1:
				_enable_opt_in_on_selected()
			KEY_2:
				_add_free_test_cargo()
			KEY_3:
				_setup_mixed_cargo_scenario()
			KEY_4:
				_issue_conservative_selective_camp_return()
			KEY_5:
				_issue_explicit_site_b_reserved_return()
			KEY_6:
				_issue_opt_in_construct_order_site_a()
			KEY_7:
				_print_status("MANUAL_INSPECT")
			KEY_8:
				_issue_opt_in_gather_nearest(ResourceDefinition.Category.WOOD)
			KEY_9:
				_issue_opt_in_gather_nearest(ResourceDefinition.Category.FOOD)

	func _selected_unit() -> Unit:
		var sel := main.get_node("SelectionManager") as SelectionManager
		var units: Array[Unit] = sel.get_selected_units()
		if units.is_empty():
			print("[C3.4.3 HARNESS] Nenhuma unidade selecionada. Selecione um trabalhador com LMB.")
			return null
		return units[0]

	func _enable_opt_in_on_selected() -> void:
		var unit := _selected_unit()
		if unit == null:
			return
		var load: UnitCarryLoad = unit.get_carry_load()
		if load.is_provenance_enabled():
			print("[C3.4.3 HARNESS] Proveniencia ja habilitada em %s (unit_id=%s)." % [unit.name, String(load.get_provenance_unit_id())])
			return
		var ok: bool = load.enable_provenance(StringName("manual_" + String(unit.name).to_lower()))
		print("[C3.4.3 HARNESS] enable_provenance(%s) -> ok=%s (mochila vazia obrigatoria)." % [unit.name, str(ok)])
		_print_status("AFTER_OPT_IN")

	func _add_free_test_cargo() -> void:
		var unit := _selected_unit()
		if unit == null:
			return
		var load: UnitCarryLoad = unit.get_carry_load()
		if not load.is_provenance_enabled():
			print("[C3.4.3 HARNESS] Habilite proveniencia primeiro com Ctrl+1.")
			return
		seq += 1
		var res: Dictionary = load.add_with_provenance(
			StringName("manual_op_free_%d" % seq),
			StringName("manual_lot_free_%d" % seq),
			&"wood",
			WOOD.unit_weight,
			4,
			CarryProvenanceLedger.FREE_GATHERED
		)
		print("[C3.4.3 HARNESS] Carga livre adicionada (4 wood): %s" % str(res))
		_print_status("AFTER_ADD_FREE")

	func _ensure_sites() -> void:
		var cm: ConstructionManager = main.get_construction_manager()
		var inv: SettlementInventory = main.get_settlement_inventory()
		if site_a == null or not is_instance_valid(site_a) or not site_a.is_active():
			if inv.get_available_amount(&"stone") < 3:
				inv.deposit(&"stone", 3)
			var def_a := SHELTER.duplicate() as BuildingDefinition
			def_a.costs = {&"stone": 3}
			var ra: Dictionary = cm.try_create_site_from_placement(def_a, Vector3(-6.0, 0.0, 1.5))
			if bool(ra.get("ok", false)):
				site_a = ra["site"] as ConstructionSite
		if site_b == null or not is_instance_valid(site_b) or not site_b.is_active():
			if inv.get_available_amount(&"wood") < 4:
				inv.deposit(&"wood", 4)
			var def_b := SHELTER.duplicate() as BuildingDefinition
			def_b.costs = {&"wood": 4}
			var rb: Dictionary = cm.try_create_site_from_placement(def_b, Vector3(0.37, 0.0, -13.19))
			if bool(rb.get("ok", false)):
				site_b = rb["site"] as ConstructionSite

	func _setup_mixed_cargo_scenario() -> void:
		var unit := _selected_unit()
		if unit == null:
			return
		var load: UnitCarryLoad = unit.get_carry_load()
		if not load.is_provenance_enabled():
			print("[C3.4.3 HARNESS] Habilite proveniencia primeiro com Ctrl+1.")
			return
		_ensure_sites()
		if site_b == null or not is_instance_valid(site_b):
			print("[C3.4.3 HARNESS] Falha ao criar Obra B.")
			return
		var inv: SettlementInventory = main.get_settlement_inventory()
		var entries: Array[Dictionary] = inv.get_reserved_pile_entries(site_b.reservation_id, &"wood")
		if entries.is_empty():
			print("[C3.4.3 HARNESS] Sem pilha reservada para Obra B.")
			return
		seq += 1
		var entry: Dictionary = entries[0]
		var saved_pos: Vector3 = unit.global_position
		var tmp_order := ConstructOrder.new(site_b, main.get_camp_storage_zone(), true, true)
		tmp_order._unit = unit
		tmp_order.mark_running()
		unit._current_order = tmp_order
		site_b.register_worker(unit, tmp_order, true)
		site_b.claim_pickup(unit, int(entry["pile_id"]), &"wood", 2, int(entry["reserved_amount"]))
		unit.global_position = nav.snap_to_navmesh(entry["world_pos"] as Vector3)
		var coord := ReservedWithdrawalCoordinator.new()
		var w_res: Dictionary = coord.execute_reserved_withdrawal(
			site_b, unit, int(entry["pile_id"]), &"wood", 2,
			StringName("manual_op_res_%d" % seq), StringName("manual_lot_site_b_%d" % seq)
		)
		site_b.unregister_worker(unit, tmp_order)
		unit._current_order = null
		unit.global_position = saved_pos
		var f_res: Dictionary = load.add_with_provenance(
			StringName("manual_op_mix_free_%d" % seq),
			StringName("manual_lot_mix_free_%d" % seq),
			&"food",
			FOOD.unit_weight,
			3,
			CarryProvenanceLedger.FREE_GATHERED
		)
		print("[C3.4.3 HARNESS] Carga mista preparada: SiteB(2 wood)=%s | Free(3 food)=%s" % [str(w_res.get("ok")), str(f_res.get("ok"))])
		_print_status("AFTER_MIXED_CARGO")

	func _issue_conservative_selective_camp_return() -> void:
		var unit := _selected_unit()
		if unit == null:
			return
		var order := DeliverToCampOrder.new(
			main.get_camp_storage_zone(), main.get_settlement_inventory(), true, nav.get_region_id(), []
		)
		last_order = order
		unit.issue_order(order)
		print("[C3.4.3 HARNESS] DeliverToCampOrder seletivo conservador emitido: status=%d failure=%s" % [order.status, order.failure_reason])

	func _issue_explicit_site_b_reserved_return() -> void:
		var unit := _selected_unit()
		if unit == null:
			return
		var load: UnitCarryLoad = unit.get_carry_load()
		if not load.is_provenance_enabled():
			print("[C3.4.3 HARNESS] Proveniencia desabilitada.")
			return
		var req: Array[Dictionary] = []
		var lots: Dictionary = load.provenance_snapshot()["ledger"]["lots"] as Dictionary
		for lot_key: Variant in lots.keys():
			var lot: Dictionary = lots[lot_key] as Dictionary
			if StringName(lot["origin"]) == CarryProvenanceLedger.SITE_RESERVED and site_b != null and StringName(lot["site_id"]) == site_b.site_id:
				req.append({"lot_id": lot["lot_id"], "amount": int(lot["quantity"])})
		if req.is_empty():
			print("[C3.4.3 HARNESS] Nenhum lote SITE_RESERVED da Obra B na mochila.")
			return
		var order := DeliverToCampOrder.new(
			main.get_camp_storage_zone(), main.get_settlement_inventory(), true, nav.get_region_id(), req
		)
		last_order = order
		unit.issue_order(order)
		print("[C3.4.3 HARNESS] DeliverToCampOrder seletivo explicito (Obra B) emitido: req=%s status=%d failure=%s" % [str(req), order.status, order.failure_reason])

	func _issue_opt_in_construct_order_site_a() -> void:
		var unit := _selected_unit()
		if unit == null:
			return
		_ensure_sites()
		if site_a == null or not is_instance_valid(site_a):
			print("[C3.4.3 HARNESS] Obra A indisponivel.")
			return
		var order := ConstructOrder.new(site_a, main.get_camp_storage_zone(), true, true)
		last_order = order
		unit.issue_order(order)
		print("[C3.4.3 HARNESS] ConstructOrder opt-in (Obra A) emitido: status=%d phase=%d failure=%s" % [order.status, order.get_phase(), order.failure_reason])

	func _find_nearest_available_source(unit: Unit, category: int) -> ResourceSource:
		var best: ResourceSource = null
		var best_d2: float = INF
		for src: ResourceSource in main.get_test_map().get_resource_sources():
			if src == null or not is_instance_valid(src) or not src.is_available():
				continue
			if src.get_category() != category:
				continue
			var d2: float = unit.global_position.distance_squared_to(src.global_position)
			if d2 < best_d2:
				best_d2 = d2
				best = src
		return best

	func _issue_opt_in_gather_nearest(category: int) -> void:
		var unit := _selected_unit()
		if unit == null:
			return
		var src: ResourceSource = _find_nearest_available_source(unit, category)
		if src == null:
			print("[C3.5 HARNESS] Nenhuma fonte disponivel para categoria=%d." % category)
			return
		var order := GatherResourceOrder.new(
			src,
			main.get_camp_storage_zone(),
			main.get_settlement_inventory(),
			-1.0,
			-1.0,
			true,
			nav.get_region_id()
		)
		last_order = order
		unit.issue_order(order)
		print("[C3.5 HARNESS] GatherResourceOrder opt-in emitido: source=%s (%d rest.) status=%d phase=%d failure=%s" % [
			String(src.source_id), src.get_remaining_amount(), order.status, order.get_phase(), order.failure_reason
		])

	func _print_status(tag: String) -> void:
		var inv: SettlementInventory = main.get_settlement_inventory()
		var unit := _selected_unit()
		print("--- [C3.4.3 HARNESS :: %s] ---" % tag)
		print("  Estoque fisico=%s | livre(wood=%d,stone=%d,food=%d) | reservado=%s" % [
			str(inv.get_all_physical_amounts()),
			inv.get_available_amount(&"wood"), inv.get_available_amount(&"stone"), inv.get_available_amount(&"food"),
			str(inv.get_all_reserved_amounts()),
		])
		if site_a != null and is_instance_valid(site_a):
			print("  Obra A (%s): active=%s buf=%s res=%s" % [
				String(site_a.site_id), str(site_a.is_active()),
				str(site_a.get_delivered_buffer_amounts()), str(inv.get_reservation_amounts(site_a.reservation_id))
			])
		if site_b != null and is_instance_valid(site_b):
			print("  Obra B (%s): active=%s buf=%s res=%s" % [
				String(site_b.site_id), str(site_b.is_active()),
				str(site_b.get_delivered_buffer_amounts()), str(inv.get_reservation_amounts(site_b.reservation_id))
			])
		if unit != null:
			var load: UnitCarryLoad = unit.get_carry_load()
			print("  Unidade=%s state=%s pos=%s prov=%s peso=%d/%d amounts=%s" % [
				unit.name, unit.get_state_name(), str(unit.global_position),
				str(load.is_provenance_enabled()), load.get_current_weight(), load.get_effective_capacity(),
				str(load.get_all_amounts())
			])
			if load.is_provenance_enabled():
				print("  Lotes restantes=%s" % str(load.provenance_snapshot()["ledger"]["lots"]))
		if last_order != null:
			print("  Ultima ordem=%s status=%d failure=%s" % [last_order.get_order_name(), last_order.status, last_order.failure_reason])
			if last_order is GatherResourceOrder:
				var go: GatherResourceOrder = last_order as GatherResourceOrder
				print("  Gather opt-in=%s phase=%d extraidos=%d ciclos=%d viagens=%d src_rest=%d src_slots=%d" % [
					str(go.is_provenance_mode()), go.get_phase(), go.get_total_extracted_units(),
					go.get_extraction_cycles_completed(), go.get_delivered_trips(),
					go.source.get_remaining_amount() if is_instance_valid(go.source) else -1,
					go.source.get_active_worker_count() if is_instance_valid(go.source) else -1
				])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MAIN_SCENE.instantiate() as MainScene
	root.add_child(main)
	await process_frame
	await process_frame
	var nav: WorldNavigation = main.get_test_map().get_navigation()
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < 240:
		await physics_frame
		frames += 1
	if not nav.is_navigation_ready():
		push_error("C3.4.3 manual harness: navigation did not become ready")
		quit(1)
		return

	var inv: SettlementInventory = main.get_settlement_inventory()
	inv.deposit(&"wood", 12)
	inv.deposit(&"stone", 8)

	var ctrl := HarnessController.new()
	ctrl.name = "C343ManualHarnessController"
	ctrl.main = main
	ctrl.nav = nav
	main.add_child(ctrl)

	print("=================================================================")
	print("DAWN OF KIN — HARNESS MANUAL REMOVIVEL T3.6.2-C3.4.3")
	print("  Selecione uma unidade com LMB e use os atalhos:")
	print("  Ctrl+1: Habilitar proveniencia opt-in (mochila vazia)")
	print("  Ctrl+2: Adicionar carga de teste FREE_GATHERED (4 wood)")
	print("  Ctrl+3: Preparar carga mista (Obra B 2 wood + Free 3 food)")
	print("  Ctrl+4: Ordenar retorno seletivo conservador (apenas FREE)")
	print("  Ctrl+5: Ordenar retorno seletivo explicito do lote Obra B")
	print("  Ctrl+6: Ordenar ConstructOrder opt-in para Obra A")
	print("  Ctrl+7: Imprimir diagnostico completo de estoque e lotes")
	print("  Ctrl+8: [C3.5] Coleta opt-in na arvore de madeira mais proxima")
	print("  Ctrl+9: [C3.5] Coleta opt-in no arbusto de alimento mais proximo")
	print("  RMB no chao durante caminhada: testar interrupcao manual")
	print("=================================================================")
