class_name PickResult
extends RefCounted
## Typed result of a 3D world picking raycast from screen space.
## Reusable across selection (T1.6) and contextual commands (T1.8).

enum Kind {
	NONE,
	UNIT,
	GROUND,
	OBSTACLE,
	RESOURCE_SOURCE,
	CONSTRUCTION_SITE,
}

var kind: Kind = Kind.NONE
var unit: Unit = null
var resource_source: ResourceSource = null
var construction_site: ConstructionSite = null
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var collider: Object = null


static func none() -> PickResult:
	return PickResult.new()


static func from_unit(
	p_unit: Unit,
	p_position: Vector3,
	p_normal: Vector3,
	p_collider: Object = null
) -> PickResult:
	var res := PickResult.new()
	res.kind = Kind.UNIT
	res.unit = p_unit
	res.position = p_position
	res.normal = p_normal
	res.collider = p_collider
	return res


static func from_ground(
	p_position: Vector3,
	p_normal: Vector3,
	p_collider: Object = null
) -> PickResult:
	var res := PickResult.new()
	res.kind = Kind.GROUND
	res.position = p_position
	res.normal = p_normal
	res.collider = p_collider
	return res


static func from_obstacle(
	p_position: Vector3,
	p_normal: Vector3,
	p_collider: Object = null
) -> PickResult:
	var res := PickResult.new()
	res.kind = Kind.OBSTACLE
	res.position = p_position
	res.normal = p_normal
	res.collider = p_collider
	return res


static func from_resource_source(
	p_resource_source: ResourceSource,
	p_position: Vector3,
	p_normal: Vector3,
	p_collider: Object = null
) -> PickResult:
	var res := PickResult.new()
	res.kind = Kind.RESOURCE_SOURCE
	res.resource_source = p_resource_source
	res.position = p_position
	res.normal = p_normal
	res.collider = p_collider
	return res


static func from_construction_site(
	p_site: ConstructionSite,
	p_position: Vector3,
	p_normal: Vector3,
	p_collider: Object = null
) -> PickResult:
	var res := PickResult.new()
	res.kind = Kind.CONSTRUCTION_SITE
	res.construction_site = p_site
	res.position = p_position
	res.normal = p_normal
	res.collider = p_collider
	return res


func is_none() -> bool:
	return kind == Kind.NONE


func is_unit() -> bool:
	return kind == Kind.UNIT and unit != null and is_instance_valid(unit)


func is_ground() -> bool:
	return kind == Kind.GROUND


func is_obstacle() -> bool:
	return kind == Kind.OBSTACLE


func is_resource_source() -> bool:
	return kind == Kind.RESOURCE_SOURCE and resource_source != null and is_instance_valid(resource_source)


func is_available_resource_source() -> bool:
	return is_resource_source() and resource_source.is_available()


func is_construction_site() -> bool:
	return kind == Kind.CONSTRUCTION_SITE and construction_site != null and is_instance_valid(construction_site)
