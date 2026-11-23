class_name MainScene
extends Node3D
## Root composition script connecting level data, world navigation, economy runtime,
## units, selection, and camera rig without relying on hidden singletons or autoloads.

const FOOD_DEFINITION: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_DEFINITION: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEFINITION: ResourceDefinition = preload("res://data/resources/stone.tres")
const SHELTER_BASIC_DEFINITION: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const STORAGE_DEPOT_DEFINITION: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")

@export var use_provenance_economy: bool = false
@export var automatic_cancellation_recovery: bool = true
@export var use_d2_2_hud: bool = false

@onready var _test_map: TestMap = $TestMap
@onready var _camera_rig: RtsCameraRig = $RtsCameraRig
@onready var _units_root: Node3D = $Units
@onready var _selection_manager: SelectionManager = $SelectionManager
@onready var _command_controller: CommandController = $CommandController
@onready var _input_controller: RtsInputController = $RtsInputController
@onready var _destination_marker: DestinationMarker = $DestinationMarker
@onready var _economy_clock: EconomyClockController = get_node_or_null("EconomyClockController") as EconomyClockController
@onready var _placement_controller: PlacementController = get_node_or_null("PlacementController") as PlacementController
@onready var _selection_box_overlay: SelectionBoxOverlay = $UiLayer/SelectionBoxOverlay
@onready var _resource_hud: ResourceHud = get_node_or_null("UiLayer/ResourceHud") as ResourceHud
@onready var _placement_test_overlay: PlacementTestOverlay = get_node_or_null("UiLayer/PlacementTestOverlay") as PlacementTestOverlay

var _time_provider: SimulatedWorldTimeProvider = null
var _camp_storage_zone: CampStorageZone = null
var _ground_pile_manager: GroundPileManager = null
var _settlement_inventory: SettlementInventory = null
var _construction_sites_root: Node3D = null
var _construction_manager: ConstructionManager = null
var _test_workers_controller: TemporaryTestWorkersController = null
var _economy_domain_owner_token: RefCounted = null
var _economy_world_ref: WeakRef = null
var _economy_region_id: StringName = &"default"
var _last_domain_release_result: Dictionary = {}
var _economy_admission_reason: String = ""
var _d2_hud_root: D2HudRoot = null


func _ready() -> void:
	if _test_map != null and _camera_rig != null:
		_camera_rig.set_map_bounds(_test_map.get_map_bounds())

	var world_nav: WorldNavigation = _test_map.get_navigation() if _test_map != null else null
	if world_nav != null and _units_root != null:
		for child: Node in _units_root.get_children():
			if child is Unit:
				(child as Unit).set_world_navigation(world_nav)

	_setup_economy(world_nav)
	_setup_construction(world_nav)
	if use_provenance_economy:
		var admission := ReservedWithdrawalCoordinator.admit_empty_provenance_units(
			get_units(), _units_root, _camp_storage_zone, _settlement_inventory, _economy_region_id
		)
		_economy_admission_reason = String(admission.get("reason", "invalid_domain")) if not admission.ok else ""
		if not _economy_admission_reason.is_empty():
			print("Economia RTS bloqueada: ", _economy_admission_reason)

	if _command_controller != null:
		_command_controller.configure(_selection_manager, world_nav, _destination_marker)
		_command_controller.configure_economy(
			_settlement_inventory, _camp_storage_zone, _economy_region_id,
			use_provenance_economy, _economy_admission_reason
		)

	if _economy_admission_reason.is_empty():
		_setup_placement(world_nav)

	if _input_controller != null:
		_input_controller.configure(
			_selection_manager,
			_camera_rig,
			_selection_box_overlay,
			_command_controller,
			_placement_controller if _economy_admission_reason.is_empty() else null
		)

	if use_d2_2_hud:
		if _resource_hud != null:
			_resource_hud.unbind()
			_resource_hud.visible = false
			var legacy_stockpile: SettlementStockpilePanel = _resource_hud.get_stockpile_panel()
			if legacy_stockpile != null:
				legacy_stockpile.visible = false
			var legacy_unit_panel: SelectedUnitPanel = _resource_hud.get_selected_unit_panel()
			if legacy_unit_panel != null:
				legacy_unit_panel.visible = false
		_setup_d2_hud()
	elif _resource_hud != null:
		_resource_hud.configure(_settlement_inventory, _selection_manager, _camp_storage_zone, _ground_pile_manager)


func _setup_d2_hud() -> void:
	var ui_layer: Node = get_node_or_null("UiLayer")
	if ui_layer == null:
		return
	_d2_hud_root = D2HudRoot.new()
	_d2_hud_root.name = "D2HudRoot"
	ui_layer.add_child(_d2_hud_root)
	var build_defs: Array[BuildingDefinition] = [SHELTER_BASIC_DEFINITION, STORAGE_DEPOT_DEFINITION]
	var active_placement: PlacementController = _placement_controller if _economy_admission_reason.is_empty() else null
	_d2_hud_root.configure(
		_settlement_inventory,
		_camp_storage_zone,
		_ground_pile_manager,
		_camera_rig,
		_economy_clock,
		_selection_manager,
		get_units(),
		active_placement,
		build_defs
	)
	if not _d2_hud_root.layout_updated.is_connected(_on_d2_layout_updated):
		_d2_hud_root.layout_updated.connect(_on_d2_layout_updated)
	_on_d2_layout_updated(_d2_hud_root.get_current_scale())


func _on_d2_layout_updated(_scale_factor: float) -> void:
	if _d2_hud_root == null or not is_instance_valid(_d2_hud_root):
		return
	var debug_panel: Control = get_node_or_null("UiLayer/DebugOverlay/Panel") as Control
	if debug_panel != null:
		debug_panel.offset_top = _d2_hud_root.get_debug_overlay_top_offset()


func _setup_placement(world_nav: WorldNavigation) -> void:
	if _placement_controller != null:
		_placement_controller.configure(
			_camera_rig,
			_test_map,
			world_nav,
			_camp_storage_zone,
			_ground_pile_manager,
			self,
			_units_root
		)
		if not _placement_controller.placement_confirmed.is_connected(_on_placement_confirmed):
			_placement_controller.placement_confirmed.connect(_on_placement_confirmed)
	if _placement_test_overlay != null and _placement_controller != null:
		_placement_test_overlay.configure(
			_placement_controller,
			SHELTER_BASIC_DEFINITION,
			STORAGE_DEPOT_DEFINITION
		)
		_placement_test_overlay.configure_construction(
			_construction_manager,
			_command_controller,
			_selection_manager,
			_input_controller
		)
		if _test_workers_controller == null:
			_test_workers_controller = TemporaryTestWorkersController.new()
		_test_workers_controller.configure(
			_units_root,
			world_nav,
			_camp_storage_zone,
			_selection_manager,
			_construction_sites_root,
			_settlement_inventory,
			_economy_region_id,
			use_provenance_economy
		)
		_placement_test_overlay.configure_test_workers(_test_workers_controller)
		_placement_test_overlay.use_game_catalog()
		_placement_test_overlay.use_context_inspector()
		if use_d2_2_hud:
			_placement_test_overlay.set_placement_status_banner_suppressed(true)
	if _placement_controller != null and not use_d2_2_hud:
		var construction_hud := ConstructionHud.new()
		construction_hud.name = "ConstructionHud"
		$UiLayer.add_child(construction_hud)
		construction_hud.configure(_placement_controller, [SHELTER_BASIC_DEFINITION, STORAGE_DEPOT_DEFINITION])
	var inspector := BuildingInspectorPanel.new()
	inspector.name = "BuildingInspectorPanel"
	$UiLayer.add_child(inspector)
	var d3_manager := _construction_manager if use_provenance_economy and _economy_admission_reason.is_empty() else null
	inspector.configure(_input_controller, _selection_manager, d3_manager, get_node_or_null("UiLayer/DebugOverlay/Panel") as Control)


func _setup_construction(world_nav: WorldNavigation) -> void:
	_construction_sites_root = get_node_or_null("ConstructionSites") as Node3D
	if _construction_sites_root == null:
		_construction_sites_root = Node3D.new()
		_construction_sites_root.name = "ConstructionSites"
		add_child(_construction_sites_root)

	_construction_manager = get_node_or_null("ConstructionManager") as ConstructionManager
	if _construction_manager == null:
		_construction_manager = ConstructionManager.new()
		_construction_manager.name = "ConstructionManager"
		add_child(_construction_manager)

	var defs: Dictionary = {
		&"food": FOOD_DEFINITION,
		&"wood": WOOD_DEFINITION,
		&"stone": STONE_DEFINITION,
	}
	_construction_manager.configure(
		_construction_sites_root,
		_settlement_inventory,
		defs,
		_camp_storage_zone,
		world_nav,
		_economy_region_id
	)
	if use_provenance_economy and automatic_cancellation_recovery:
		_construction_manager.enable_cancellation_recovery()


func preflight_economic_teardown() -> Dictionary:
	if _ground_pile_manager == null or _settlement_inventory == null:
		return {"ok": false, "reason": "missing_economy"}
	if _settlement_inventory.is_transaction_busy():
		return {"ok": false, "reason": "transaction_in_progress"}
	var custody := CancellationLifecycleGuard.inspect_storage(_ground_pile_manager)
	if not custody.ok:
		return custody
	for unit: Unit in get_units():
		var load := unit.get_carry_load()
		if unit._is_reserved_withdrawal_locked() or load.is_transaction_busy():
			return {"ok": false, "reason": "transaction_in_progress"}
		if not load.is_empty() or load.get_current_weight() > 0 or (load.is_provenance_enabled() and not load.validate_provenance()):
			return {"ok": false, "reason": "pending_material_obligation"}
	return {"ok": true, "reason": ""}


## Explicit internal entry; no UI/quit binding is introduced. _exit_tree cannot veto free().
func request_controlled_teardown() -> Dictionary:
	var check := preflight_economic_teardown()
	if not check.ok:
		return check
	if get_parent() == null or not is_inside_tree():
		return {"ok": false, "reason": "invalid_scene"}
	# Quiesce cooperative economic entry points before tree-exit observers run.
	# Keep local owners: _exit_tree clears MainScene's composition references.
	var storage := _ground_pile_manager
	var inventory := _settlement_inventory
	var camp := _camp_storage_zone
	var world := get_world_3d()
	var tree := get_tree()
	var domain_owner := _economy_domain_owner_token
	var region := storage.get_bound_withdrawal_region()
	if region.is_empty():
		region = _economy_region_id
	var authority := CancellationRecoveryTransaction._authority(world, region)
	if authority != null and (authority.storage == null or authority.storage.get_ref() != storage or authority.has_active_operation()):
		return {"ok": false, "reason": "ambiguous_or_busy_economic_domain"}
	var loads: Array[UnitCarryLoad] = []
	var orders: Array[Dictionary] = []
	if authority != null:
		authority.is_executing = true
	inventory._is_delivering = true
	storage._is_preparing_withdrawal = true
	if is_instance_valid(camp):
		camp._coordinator_transaction_locked = true
	for unit: Unit in get_units():
		var load := unit.get_carry_load()
		loads.append(load)
		load._coordinator_transaction_locked = true
		load._provenance_busy = true
		if unit.get_current_order() != null:
			orders.append({"order": unit.get_current_order(), "movement": unit.get_movement()})
	get_parent().remove_child(self)
	for load: UnitCarryLoad in loads:
		load._coordinator_transaction_locked = false
		load._provenance_busy = false
	if is_instance_valid(camp):
		camp._coordinator_transaction_locked = false
	storage._is_preparing_withdrawal = false
	inventory._is_delivering = false
	if authority != null:
		authority.is_executing = false
	# A transfer delegate may conservatively defer cancellation while locked.
	# The detached scene cannot accept new work; finish unbinding those delegates.
	for entry: Dictionary in orders:
		if entry.order.is_active():
			entry.order.cancel(entry.movement, UnitOrder.REASON_UNIT_EXITED)
	storage.cleanup()
	_last_domain_release_result = ReservedWithdrawalCoordinator.release_regional_domain(world, region, storage, domain_owner, tree, inventory)
	queue_free()
	return {"ok": true, "reason": ""}


func _on_placement_confirmed(
	definition: BuildingDefinition,
	world_position: Vector3,
	_result: PlacementValidator.ValidationResult
) -> void:
	if _construction_manager != null and is_instance_valid(_construction_manager):
		_construction_manager.try_create_site_from_placement(definition, world_position)


func _exit_tree() -> void:
	if _placement_controller != null and is_instance_valid(_placement_controller):
		if _placement_controller.placement_confirmed.is_connected(_on_placement_confirmed):
			_placement_controller.placement_confirmed.disconnect(_on_placement_confirmed)
	if _resource_hud != null:
		_resource_hud.unbind()
	if _d2_hud_root != null and is_instance_valid(_d2_hud_root):
		if _d2_hud_root.layout_updated.is_connected(_on_d2_layout_updated):
			_d2_hud_root.layout_updated.disconnect(_on_d2_layout_updated)
		_d2_hud_root.unbind()
	_d2_hud_root = null
	if _ground_pile_manager != null:
		var world: World3D = get_world_3d()
		if world == null and _economy_world_ref != null:
			world = _economy_world_ref.get_ref() as World3D
		var release_region: StringName = _ground_pile_manager.get_bound_withdrawal_region()
		if release_region.is_empty():
			release_region = _economy_region_id
		var domain_busy: bool = (
			(world != null and ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, release_region))
			or _ground_pile_manager.is_locked()
			or _ground_pile_manager.is_batch_active()
			or (_settlement_inventory != null and _settlement_inventory.is_transaction_busy())
		)
		if domain_busy:
			if world != null and get_tree() != null and _economy_domain_owner_token != null:
				_last_domain_release_result = ReservedWithdrawalCoordinator.release_regional_domain(
					world,
					release_region,
					_ground_pile_manager,
					_economy_domain_owner_token,
					get_tree(),
					_settlement_inventory
				)
			else:
				_last_domain_release_result = {
					"ok": false,
					"released": false,
					"reason": "busy",
					"region_id": release_region,
				}
		else:
			_ground_pile_manager.cleanup()
			if world != null and get_tree() != null and _economy_domain_owner_token != null:
				_last_domain_release_result = ReservedWithdrawalCoordinator.release_regional_domain(
					world,
					release_region,
					_ground_pile_manager,
					_economy_domain_owner_token,
					get_tree(),
					_settlement_inventory
				)
			else:
				_last_domain_release_result = {
					"ok": false,
					"released": false,
					"reason": "missing_world_or_tree",
					"region_id": release_region,
				}
		_ground_pile_manager = null
	_economy_domain_owner_token = null
	_economy_world_ref = null
	_construction_manager = null
	_construction_sites_root = null
	_test_workers_controller = null
	_settlement_inventory = null
	_time_provider = null


func _setup_economy(world_nav: WorldNavigation) -> void:
	if _test_map == null:
		return
	_camp_storage_zone = _test_map.get_camp_storage_zone()
	var camp_piles_root: Node3D = _test_map.get_camp_piles_root()
	if _camp_storage_zone == null or camp_piles_root == null:
		return

	_camp_storage_zone.set_world_navigation(world_nav)
	_time_provider = SimulatedWorldTimeProvider.new(0.0)
	var definitions: Dictionary = {
		&"food": FOOD_DEFINITION,
		&"wood": WOOD_DEFINITION,
		&"stone": STONE_DEFINITION,
	}
	_ground_pile_manager = GroundPileManager.new(
		definitions,
		_camp_storage_zone,
		camp_piles_root,
		_time_provider
	)
	_economy_domain_owner_token = RefCounted.new()
	_ground_pile_manager.bind_domain_owner(_economy_domain_owner_token)
	var world: World3D = get_world_3d()
	_economy_world_ref = weakref(world) if world != null else null
	_last_domain_release_result = {}
	_settlement_inventory = SettlementInventory.new(_ground_pile_manager)

	if _economy_clock == null:
		_economy_clock = EconomyClockController.new()
		_economy_clock.name = "EconomyClockController"
		add_child(_economy_clock)
	_economy_clock.configure(_ground_pile_manager, _time_provider)


func get_units() -> Array[Unit]:
	var result: Array[Unit] = []
	if _units_root == null:
		return result
	for child: Node in _units_root.get_children():
		if child is Unit:
			result.append(child as Unit)
	return result


func get_test_map() -> TestMap:
	return _test_map


func get_selection_manager() -> SelectionManager:
	return _selection_manager


func get_input_controller() -> RtsInputController:
	return _input_controller


func get_selection_box_overlay() -> SelectionBoxOverlay:
	return _selection_box_overlay


func get_resource_hud() -> ResourceHud:
	return _resource_hud


func get_d2_hud_root() -> D2HudRoot:
	return _d2_hud_root


func get_command_controller() -> CommandController:
	return _command_controller


func get_destination_marker() -> DestinationMarker:
	return _destination_marker


func get_camp_storage_zone() -> CampStorageZone:
	return _camp_storage_zone


func get_ground_pile_manager() -> GroundPileManager:
	return _ground_pile_manager


func get_settlement_inventory() -> SettlementInventory:
	return _settlement_inventory


func get_economy_clock() -> EconomyClockController:
	return _economy_clock


func get_time_provider() -> SimulatedWorldTimeProvider:
	return _time_provider


func get_placement_controller() -> PlacementController:
	return _placement_controller


func get_placement_test_overlay() -> PlacementTestOverlay:
	return _placement_test_overlay


func get_construction_manager() -> ConstructionManager:
	return _construction_manager


func get_construction_sites_root() -> Node3D:
	return _construction_sites_root


func get_last_domain_release_result() -> Dictionary:
	return _last_domain_release_result.duplicate(true)
