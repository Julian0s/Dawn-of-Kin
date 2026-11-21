class_name CommunityTaskDispatcher
extends Node
## Minimal RUX-1 event-driven community task dispatcher (stub for RED phase).

signal task_assigned(task: WorkTask, unit: Unit, order: GatherResourceOrder)
signal task_waiting(task: WorkTask, reason: String)
signal task_feedback(message: String)


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func configure(
	_p_board: CommunityWorkBoard,
	_p_command_controller: CommandController,
	_p_world_nav: WorldNavigation,
	_p_units_root: Node,
	_p_camp_zone: CampStorageZone,
	_p_inventory: SettlementInventory,
	_p_region_id: StringName = &"default",
	_p_use_provenance: bool = true
) -> void:
	pass


func request_dispatch() -> void:
	pass
