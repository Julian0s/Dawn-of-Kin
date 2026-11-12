class_name CollisionLayers
extends RefCounted
## Central registry of 3D physics layer indices and bitmasks.
## Must stay synchronized with [layer_names] in project.godot.

const LAYER_TERRAIN: int = 1
const LAYER_OBSTACLES: int = 2
const LAYER_UNITS: int = 3
const LAYER_SELECTION: int = 4
const LAYER_BUILDINGS: int = 5 # Reserved for T3 construction
const LAYER_RESOURCES: int = 6 # Reserved for T2 gatherable resources

const MASK_TERRAIN: int = 1 << (LAYER_TERRAIN - 1)
const MASK_OBSTACLES: int = 1 << (LAYER_OBSTACLES - 1)
const MASK_UNITS: int = 1 << (LAYER_UNITS - 1)
const MASK_SELECTION: int = 1 << (LAYER_SELECTION - 1)
const MASK_BUILDINGS: int = 1 << (LAYER_BUILDINGS - 1)
const MASK_RESOURCES: int = 1 << (LAYER_RESOURCES - 1)

## Ground and solid world geometry used by unit bodies and ground picking.
const MASK_WORLD_SOLID: int = MASK_TERRAIN | MASK_OBSTACLES
