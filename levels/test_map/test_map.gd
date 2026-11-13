class_name TestMap
extends Node3D
## Greybox test level for T1 RTS validation.
## Provides a 64x64 m terrain with obstacles, a wall with gap, a closed enclosure,
## a ramp leading to an elevated plateau, directional lighting, and map bounds.

@export var map_bounds: Rect2 = Rect2(-32.0, -32.0, 64.0, 64.0)

@onready var _world_navigation: WorldNavigation = get_node_or_null("WorldNavigation") as WorldNavigation


func get_map_bounds() -> Rect2:
	return map_bounds


func get_navigation() -> WorldNavigation:
	return _world_navigation
