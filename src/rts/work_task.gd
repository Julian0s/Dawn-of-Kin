class_name WorkTask
extends RefCounted
## Community work task targeting a single ResourceSource (wood, stone, or food).

enum Kind {
	GATHER_WOOD,
	GATHER_STONE,
	GATHER_FOOD,
}

enum State {
	PENDING_WORKERS,
	IN_PROGRESS,
	BLOCKED_REAUTHORIZATION,
	COMPLETED,
	FAILED,
	CANCELLED,
}

const REASON_ALL_WORKERS_EXCLUDED: String = "all_workers_manually_excluded"
const REASON_PLAYER_CANCELLED: String = "player_cancelled_community_work"

var task_id: int = 0
var group_id: int = 0
var kind: Kind = Kind.GATHER_WOOD
var resource_id: StringName = &"wood"
var resource_definition: ResourceDefinition = null
var region_id: StringName = &"default"
var created_seq: int = 0
var source: ResourceSource = null
var source_id: StringName = &""
var state: State = State.PENDING_WORKERS
var assigned_unit: Unit = null
var assigned_order: GatherResourceOrder = null
var assigned_order_revision: int = -1
var last_reason: String = ""
var excluded_unit_ids: Dictionary = {}


static func kind_from_resource_id(p_resource_id: StringName) -> Kind:
	match p_resource_id:
		&"stone":
			return Kind.GATHER_STONE
		&"food":
			return Kind.GATHER_FOOD
		_:
			return Kind.GATHER_WOOD


func is_active() -> bool:
	return (
		state == State.PENDING_WORKERS
		or state == State.IN_PROGRESS
		or state == State.BLOCKED_REAUTHORIZATION
	)


func is_blocked_reauthorization() -> bool:
	return state == State.BLOCKED_REAUTHORIZATION


func is_source_valid() -> bool:
	return (
		source != null
		and is_instance_valid(source)
		and source.is_inside_tree()
		and not source.is_queued_for_deletion()
	)


func is_source_usable() -> bool:
	return is_source_valid() and source.is_available() and not source.is_depleted()


func has_assigned_worker() -> bool:
	return (
		assigned_unit != null
		and is_instance_valid(assigned_unit)
		and assigned_order != null
		and assigned_order.is_active()
	)


func clear_assignment() -> void:
	assigned_unit = null
	assigned_order = null
	assigned_order_revision = -1
