class_name CommunityWorkBoard
extends Node
## Minimal RUX-1 regional registry for community wood-gather tasks.

signal task_registered(task: WorkTask)
signal task_updated(task: WorkTask)
signal task_closed(task: WorkTask)


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func configure(_p_region_id: StringName) -> void:
	pass


func register_wood_gather_task(_source: ResourceSource) -> Dictionary:
	return {"ok": false, "created": false, "task": null, "reason": "not_implemented"}


func get_active_task_for_source(_source: ResourceSource) -> WorkTask:
	return null


func get_active_tasks() -> Array[WorkTask]:
	return []


func get_pending_tasks() -> Array[WorkTask]:
	return []


func get_all_tasks() -> Array[WorkTask]:
	return []


func close_task(_task: WorkTask, _final_state: WorkTask.State, _reason: String = "") -> void:
	pass
