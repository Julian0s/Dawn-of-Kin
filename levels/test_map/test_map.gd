class_name TestMap
extends Node3D
## Greybox test level for T1 RTS validation.
## Provides a 64x64 m terrain with obstacles, a wall with gap, a closed enclosure,
## a ramp leading to an elevated plateau, directional lighting, and map bounds.

@export var map_bounds: Rect2 = Rect2(-32.0, -32.0, 64.0, 64.0)

@onready var _world_navigation: WorldNavigation = get_node_or_null("WorldNavigation") as WorldNavigation
@onready var _camp_storage_zone: CampStorageZone = get_node_or_null("CampStorageZone") as CampStorageZone
@onready var _camp_piles_root: Node3D = get_node_or_null("CampPiles") as Node3D
@onready var _resource_sources_root: Node3D = get_node_or_null("ResourceSources") as Node3D


func get_map_bounds() -> Rect2:
	return map_bounds


func get_navigation() -> WorldNavigation:
	return _world_navigation


func get_camp_storage_zone() -> CampStorageZone:
	return _camp_storage_zone


func get_camp_piles_root() -> Node3D:
	return _camp_piles_root


func get_resource_sources_root() -> Node3D:
	return _resource_sources_root


func get_resource_sources() -> Array[ResourceSource]:
	var sources: Array[ResourceSource] = []
	if _resource_sources_root == null:
		return sources
	for child: Node in _resource_sources_root.get_children():
		if child is ResourceSource:
			sources.append(child as ResourceSource)
	return sources
