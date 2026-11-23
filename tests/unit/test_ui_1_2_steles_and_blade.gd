extends TestCase
## Unit tests for UI-1.2 (D2FounderStelesView & D2LineageBladeView):
## - Founder identification & DT-04 dynamic naming via HudFormatter.format_unit_name()
## - Portrait mapping by character_id (&"leader_a" -> Alden, &"leader_b" -> Brena) + safe fallback
## - Canonical 1080p & 720p geometry, +6 px second-stele stagger, and -22 px raised selection lift
## - Polygonal hitboxes on steles and lineage blade (solid hit vs 10 px transparent shadow pad)
## - Bidirectional SelectionManager sync, multi-selection without invented group sums, empty hide
## - Carry transitions 0% -> partial -> 100% -> overload via real UnitCarryLoad signals
## - Zero polling, idempotent configure/unbind, and unit removal cleanup.

const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const LEADER_B_DEF: CharacterDefinition = preload("res://data/characters/leader_b.tres")
const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_DEF: ResourceDefinition = preload("res://data/resources/food.tres")


func _spawn_unit(def: CharacterDefinition, node_name: String) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = node_name
	u.definition = def
	add_test_child(u)
	return u


func test_01_founder_identification_portraits_fallback_and_geometry() -> void:
	var lib := D2AtlasLibrary.new()
	lib.load_all()
	var tf := D2ThemeFactory.new()
	var sel := SelectionManager.new()
	add_test_child(sel)

	var leader_a: Unit = _spawn_unit(LEADER_A_DEF, "LeaderA")
	var leader_b: Unit = _spawn_unit(LEADER_B_DEF, "LeaderB")
	await wait_process_frames(1)

	var steles := D2FounderStelesView.new()
	add_test_child(steles)
	steles.setup_visuals(lib, tf, Vector2(1920.0, 1080.0), 1.0)
	# Pass in reversed order to verify canonical leader_a -> slot 0, leader_b -> slot 1 ordering
	steles.configure(sel, [leader_b, leader_a])
	steles.configure(sel, [leader_b, leader_a]) # idempotent

	assert_false(steles.is_processing(), "D2FounderStelesView must not poll _process")
	assert_false(steles.is_physics_processing(), "D2FounderStelesView must not poll _physics_process")
	assert_eq(steles.process_mode, Node.PROCESS_MODE_PAUSABLE, "Founder steles must respect pause restrictions")
	assert_true(steles.is_bound_to_selection_manager(sel))
	assert_true(steles.is_bound_to_unit(leader_a))
	assert_true(steles.is_bound_to_unit(leader_b))

	# DT-04 names & portrait textures
	assert_eq(steles.get_slot_unit(0), leader_a)
	assert_eq(steles.get_slot_unit(1), leader_b)
	assert_eq(steles.get_slot_name_text(0), "Leader A", "DT-04: must use HudFormatter.format_unit_name(leader_a)")
	assert_eq(steles.get_slot_name_text(1), "Leader B", "DT-04: must use HudFormatter.format_unit_name(leader_b)")
	assert_eq(steles.get_slot_state_text(0), "Ocioso")
	assert_eq(steles.get_slot_state_text(1), "Ocioso")

	var tex_a: Texture2D = steles.get_slot_portrait_texture(0)
	var tex_b: Texture2D = steles.get_slot_portrait_texture(1)
	assert_not_null(tex_a, "leader_a must load approved portrait_alden.jpg")
	assert_not_null(tex_b, "leader_b must load approved portrait_brena.jpg")
	assert_ne(tex_a, tex_b, "Founder portraits must be distinct")

	# Canonical 1080p geometry: x0=20, x1=142, second stele +6 px lower, normal size 108x136
	var r0: Rect2 = steles.get_slot_content_rect(0)
	var r1: Rect2 = steles.get_slot_content_rect(1)
	assert_near(r0.position.x, 20.0, 0.1, "First stele X must be 20 px at 1080p")
	assert_near(r1.position.x, 142.0, 0.1, "Second stele X must be 142 px at 1080p")
	assert_near(r1.position.y - r0.position.y, 6.0, 0.1, "Second stele must sit 6 px lower in normal composition")
	assert_near(r0.size.x, 108.0, 0.1)
	assert_near(r0.size.y, 136.0, 0.1)
	assert_false(r0.intersects(r1), "Independent steles must not overlap")

	# Selection raises stele 0 by 22 px and switches content height to 154 px
	sel.select_single(leader_a)
	assert_true(steles.is_slot_selected(0))
	assert_false(steles.is_slot_selected(1))
	var r0_raised: Rect2 = steles.get_slot_content_rect(0)
	assert_near(r0.position.y - r0_raised.position.y, 22.0, 0.1, "Selected stele must elevate by 22 px")
	assert_near(r0_raised.size.y, 154.0, 0.1, "Raised stele active content height must be 154 px")

	# Polygonal hitbox checks: center hits, 10 px transparent shadow pad misses
	var btn0: D2SlabButton = steles.get_slot_button(0)
	assert_eq(btn0.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(btn0.mouse_force_pass_scroll_events)
	assert_eq(btn0.focus_mode, Control.FOCUS_NONE)
	assert_true(btn0.contains_local_point(btn0.size * 0.5), "Stele center must hit polygon")
	assert_false(btn0.contains_local_point(Vector2(2.0, 2.0)), "Stele 10 px shadow pad corner must pass through")

	# Multi-selection elevates BOTH steles independently
	sel.add_unit(leader_b)
	assert_true(steles.is_slot_selected(0))
	assert_true(steles.is_slot_selected(1))
	assert_near(steles.get_slot_content_rect(1).size.y, 154.0, 0.1)

	# Clear selection lowers both back to 136 px
	sel.clear_selection()
	assert_false(steles.is_slot_selected(0))
	assert_false(steles.is_slot_selected(1))
	assert_near(steles.get_slot_content_rect(0).size.y, 136.0, 0.1)
	assert_near(steles.get_slot_content_rect(1).size.y, 136.0, 0.1)

	# Future inhabitant safe portrait fallback (no dedicated portrait)
	var custom_def := CharacterDefinition.new()
	custom_def.character_id = &"settler_future"
	custom_def.display_name = "Kael"
	custom_def.base_carry_capacity = 20
	var future_unit: Unit = _spawn_unit(custom_def, "FutureSettler")
	await wait_process_frames(1)
	steles.configure(sel, [future_unit])
	assert_eq(steles.get_slot_name_text(0), "Kael")
	assert_null(steles.get_slot_portrait_texture(0), "Unknown character_id must use safe fallback instead of mismatched portrait")
	assert_true(steles.is_slot_visible(0))
	assert_false(steles.is_slot_visible(1))

	steles.unbind()
	assert_false(steles.is_bound_to_selection_manager(sel))
	assert_false(steles.is_bound_to_unit(future_unit))


func test_02_lineage_blade_carry_0_to_100_overload_multi_empty_and_cleanup() -> void:
	var lib := D2AtlasLibrary.new()
	lib.load_all()
	var tf := D2ThemeFactory.new()
	var sel := SelectionManager.new()
	add_test_child(sel)

	var leader_a: Unit = _spawn_unit(LEADER_A_DEF, "LeaderA")
	var leader_b: Unit = _spawn_unit(LEADER_B_DEF, "LeaderB")
	await wait_process_frames(1)

	var blade := D2LineageBladeView.new()
	add_test_child(blade)
	blade.setup_visuals(lib, tf, Vector2(1920.0, 1080.0), 1.0)
	blade.configure(sel)
	blade.configure(sel) # idempotent

	assert_false(blade.is_processing(), "D2LineageBladeView must not poll _process")
	assert_false(blade.is_physics_processing(), "D2LineageBladeView must not poll _physics_process")
	assert_eq(blade.process_mode, Node.PROCESS_MODE_PAUSABLE)

	# Empty selection -> hidden, zero stale text
	assert_false(blade.visible, "Blade must be hidden on empty selection")
	assert_eq(blade.get_selection_mode(), D2LineageBladeView.SelectionMode.EMPTY)
	assert_eq(blade.get_title_text(), "")

	# Single selection: 0% carry
	sel.select_single(leader_a)
	assert_true(blade.visible)
	assert_eq(blade.get_selection_mode(), D2LineageBladeView.SelectionMode.SINGLE)
	assert_true(blade.is_single_details_visible())
	assert_false(blade.is_multi_summary_visible())
	assert_true(blade.is_bound_to_unit(leader_a))
	assert_eq(blade.get_title_text(), "Leader A")
	assert_eq(blade.get_badge_text(), "OCIOSO")
	assert_eq(blade.get_percentage_text(), "0%")
	assert_eq(blade.get_weight_text(), "Peso transportado: 0 / 20")
	assert_eq(blade.get_carried_value_text(&"wood"), "0")
	assert_eq(blade.get_carried_value_text(&"stone"), "0")
	assert_eq(blade.get_carried_value_text(&"food"), "0")
	assert_false(blade.is_overload_indicated())

	# Redundant refresh must not re-apply
	var applies_before: int = blade.get_apply_count()
	blade.refresh()
	assert_eq(blade.get_apply_count(), applies_before, "Identical refresh must be deduplicated")

	# Partial carry -> signal-driven immediate update (wood=3 weight 6, stone=2 weight 6, food=2 weight 2 => 14/20 = 70%)
	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	assert_true(load_a.add_resource(&"wood", WOOD_DEF.unit_weight, 3))
	assert_true(load_a.add_resource(&"stone", STONE_DEF.unit_weight, 2))
	assert_true(load_a.add_resource(&"food", FOOD_DEF.unit_weight, 2))
	assert_eq(blade.get_carried_value_text(&"wood"), "3")
	assert_eq(blade.get_carried_value_text(&"stone"), "2")
	assert_eq(blade.get_carried_value_text(&"food"), "2")
	assert_eq(blade.get_weight_text(), "Peso transportado: 14 / 20")
	assert_eq(blade.get_percentage_text(), "70%")
	assert_false(blade.is_overload_indicated())

	# 100% carry (add 3 wood -> +6 weight => 20/20 = 100%)
	assert_true(load_a.add_resource(&"wood", WOOD_DEF.unit_weight, 3))
	assert_eq(blade.get_weight_text(), "Peso transportado: 20 / 20")
	assert_eq(blade.get_percentage_text(), "100%")
	assert_false(blade.is_overload_indicated())

	# Overload via capacity_changed signal (capacity drops below 20 -> overloaded!)
	assert_true(load_a.set_capacity_modifier(&"test_overload", -8))
	assert_true(load_a.is_overloaded())
	assert_true(blade.is_overload_indicated(), "Blade must react immediately to capacity_changed overload")
	assert_true(blade.get_weight_text().contains("sobrecarga"), "Weight text must reflect HudFormatter overload label")
	assert_true(load_a.remove_capacity_modifier(&"test_overload"))
	assert_false(blade.is_overload_indicated())

	# Polygonal hitbox on blade slab
	var blade_slab: D2PolygonalSlab = blade.get_slab()
	assert_eq(blade_slab.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(blade_slab.mouse_force_pass_scroll_events)
	assert_true(blade_slab.contains_local_point(blade_slab.size * 0.5))
	assert_false(blade_slab.contains_local_point(Vector2(2.0, 2.0)), "Blade 10 px shadow pad must pass through")

	# Multi-selection: NO individual carry details or invented group totals!
	sel.set_selection([leader_a, leader_b])
	assert_true(blade.visible)
	assert_eq(blade.get_selection_mode(), D2LineageBladeView.SelectionMode.MULTI)
	assert_eq(blade.get_selected_count(), 2)
	assert_false(blade.is_single_details_visible(), "Multi-selection must hide individual carry breakdown")
	assert_true(blade.is_multi_summary_visible())
	assert_true(blade.get_title_text().contains("2"))
	assert_eq(blade.get_badge_text(), "GRUPO")
	assert_true(blade.get_multi_summary_text().contains("Leader A"))
	assert_true(blade.get_multi_summary_text().contains("Leader B"))
	assert_false(blade.get_multi_summary_text().contains("20 / 20"), "Multi-selection must NOT show individual weight as group data")

	# Unit removed from tree while selected -> cleans up safely
	sel.select_single(leader_b)
	assert_eq(blade.get_title_text(), "Leader B")
	leader_b.queue_free()
	await wait_process_frames(2)
	assert_false(blade.visible, "Removing sole selected unit must hide blade cleanly")
	assert_eq(blade.get_selection_mode(), D2LineageBladeView.SelectionMode.EMPTY)
	assert_null(blade.get_tracked_unit())

	# Unbind disconnects all signals cleanly
	blade.unbind()
	assert_false(blade.is_bound_to_selection_manager(sel))
	assert_eq(sel.selection_changed.get_connections().size(), 0)
