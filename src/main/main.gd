class_name MainScene
extends Node3D
## Root composition script connecting level data, world navigation, economy runtime,
## units, selection, and camera rig without relying on hidden singletons or autoloads.

const FOOD_DEFINITION: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_DEFINITION: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEFINITION: ResourceDefinition = preload("res://data/resources/stone.tres")

@onready var _test_map: TestMap = $TestMap
@onready var _camera_rig: RtsCameraRig = $RtsCameraRig
@onready var _units_root: Node3D = $Units
@onready var _selection_manager: SelectionManager = $SelectionManager
@onready var _command_controller: CommandController = $CommandController
@onready var _input_controller: RtsInputController = $RtsInputController
@onready var _destination_marker: DestinationMarker = $DestinationMarker
@onready var _economy_clock: EconomyClockController = get_node_or_null("EconomyClockController") as EconomyClockController
@onready var _selection_box_overlay: SelectionBoxOverlay = $UiLayer/SelectionBoxOverlay

var _time_provider: SimulatedWorldTimeProvider = null
var _camp_storage_zone: CampStorageZone = null
var _ground_pile_manager: GroundPileManager = null
var _settlement_inventory: SettlementInventory = null


func _ready() -> void:
	if _test_map != null and _camera_rig != null:
		_camera_rig.set_map_bounds(_test_map.get_map_bounds())

	var world_nav: WorldNavigation = _test_map.get_navigation() if _test_map != null else null
	if world_nav != null and _units_root != null:
		for child: Node in _units_root.get_children():
			if child is Unit:
				(child as Unit).set_world_navigation(world_nav)

	_setup_economy(world_nav)

	if _command_controller != null:
		_command_controller.configure(_selection_manager, world_nav, _destination_marker)
		if _settlement_inventory != null and _camp_storage_zone != null:
			_command_controller.configure_economy(_settlement_inventory, _camp_storage_zone)

	if _input_controller != null:
		_input_controller.configure(_selection_manager, _camera_rig, _selection_box_overlay, _command_controller)


func _exit_tree() -> void:
	if _ground_pile_manager != null:
		_ground_pile_manager.cleanup()
		_ground_pile_manager = null
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
