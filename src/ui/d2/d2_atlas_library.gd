class_name D2AtlasLibrary
extends RefCounted
## Runtime loader and cache for the approved D2.2 pre-baked atlas and manifest.
## Loads exclusively via res://assets/ui/d2/ without relying on external filesystem paths.

const ASSETS_DIR: String = "res://assets/ui/d2/"
const ATLAS_PATH: String = ASSETS_DIR + "d2_2_faithful_atlas.png"
const MENU_MONOLITH_PATH: String = ASSETS_DIR + "d2_2_menu_monolith.png"
const MANIFEST_PATH: String = ASSETS_DIR + "atlas_manifest.json"
const PORTRAIT_ALDEN_PATH: String = ASSETS_DIR + "portrait_alden.jpg"
const PORTRAIT_BRENA_PATH: String = ASSETS_DIR + "portrait_brena.jpg"
const EMBLEM_PATH: String = ASSETS_DIR + "emblem_dawn_of_kin.png"
const SHELTER_MINI_PATH: String = ASSETS_DIR + "d1_shelter_mini.png"
const DEPOT_MINI_PATH: String = ASSETS_DIR + "d1_depot_mini.png"
const KINTSUGI_BASALT_PATH: String = ASSETS_DIR + "d2_kintsugi_basalt.png"

const REQUIRED_ASSET_PATHS: Array[String] = [
	ATLAS_PATH,
	MENU_MONOLITH_PATH,
	MANIFEST_PATH,
	PORTRAIT_ALDEN_PATH,
	PORTRAIT_BRENA_PATH,
	EMBLEM_PATH,
	SHELTER_MINI_PATH,
	DEPOT_MINI_PATH,
	KINTSUGI_BASALT_PATH,
]

const REQUIRED_REGIONS: Array[String] = [
	"maquette_depot_sel",
	"build_site_monolith",
	"maquette_shelter",
	"lineage_blade",
	"founder_stele_raised",
	"founder_stele",
	"top_plaque",
	"slab_maquetes_alab",
	"slab_cmd_basalt",
	"menu_primary_alab",
	"resource_rock",
	"build_valid_bar",
	"ico_wood",
	"ico_stone",
	"ico_food",
	"ico_tasks",
	"ico_lineage",
]

var _atlas_texture: Texture2D = null
var _manifest: Dictionary = {}
var _regions_cache: Dictionary = {}
var _loaded: bool = false


func load_all() -> bool:
	if _loaded:
		return is_valid()
	_loaded = true
	_regions_cache.clear()
	_manifest = _load_manifest_dict(MANIFEST_PATH)
	_atlas_texture = _load_texture(ATLAS_PATH)
	return is_valid()


func is_valid() -> bool:
	if _atlas_texture == null or _manifest.is_empty():
		return false
	var regions_val: Variant = _manifest.get("regions", null)
	if not (regions_val is Dictionary):
		return false
	var regions: Dictionary = regions_val as Dictionary
	for key: String in REQUIRED_REGIONS:
		if not regions.has(key):
			return false
	return true


func get_atlas_texture() -> Texture2D:
	if not _loaded:
		load_all()
	return _atlas_texture


func get_manifest() -> Dictionary:
	if not _loaded:
		load_all()
	return _manifest


func get_region_keys() -> Array[String]:
	if not _loaded:
		load_all()
	var result: Array[String] = []
	var regions_val: Variant = _manifest.get("regions", null)
	if regions_val is Dictionary:
		for key_val: Variant in (regions_val as Dictionary).keys():
			result.append(String(key_val))
	return result


func get_region_metadata(region_key: String) -> Dictionary:
	if not _loaded:
		load_all()
	var regions_val: Variant = _manifest.get("regions", null)
	if not (regions_val is Dictionary):
		return {}
	var regions: Dictionary = regions_val as Dictionary
	var entry_val: Variant = regions.get(region_key, null)
	return (entry_val as Dictionary) if entry_val is Dictionary else {}


func get_region_texture(region_key: String) -> AtlasTexture:
	if not _loaded:
		load_all()
	if _regions_cache.has(region_key):
		return _regions_cache[region_key] as AtlasTexture
	if _atlas_texture == null:
		return null
	var meta: Dictionary = get_region_metadata(region_key)
	if meta.is_empty():
		return null
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = _atlas_texture
	atlas_tex.region = Rect2(
		float(meta.get("x", 0.0)),
		float(meta.get("y", 0.0)),
		float(meta.get("w", 0.0)),
		float(meta.get("h", 0.0))
	)
	_regions_cache[region_key] = atlas_tex
	return atlas_tex


func validate_manifest_bounds() -> bool:
	if not is_valid():
		return false
	var atlas_w: float = float(_manifest.get("width", 0))
	var atlas_h: float = float(_manifest.get("height", 0))
	if atlas_w <= 0.0 or atlas_h <= 0.0:
		return false
	var regions: Dictionary = _manifest["regions"] as Dictionary
	for key: String in REQUIRED_REGIONS:
		var r: Dictionary = regions[key] as Dictionary
		var rx: float = float(r.get("x", -1.0))
		var ry: float = float(r.get("y", -1.0))
		var rw: float = float(r.get("w", 0.0))
		var rh: float = float(r.get("h", 0.0))
		if rx < 0.0 or ry < 0.0 or rw <= 0.0 or rh <= 0.0:
			return false
		if rx + rw > atlas_w or ry + rh > atlas_h:
			return false
	return true


static func _load_manifest_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return (parsed as Dictionary) if parsed is Dictionary else {}


static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var loaded: Resource = ResourceLoader.load(path)
		if loaded is Texture2D:
			return loaded as Texture2D
	# Fallback for unimported headless execution using res:// virtual filesystem
	if FileAccess.file_exists(path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			var img := Image.new()
			var err: Error = ERR_FILE_UNRECOGNIZED
			if path.ends_with(".png"):
				err = img.load_png_from_buffer(bytes)
			elif path.ends_with(".jpg") or path.ends_with(".jpeg"):
				err = img.load_jpg_from_buffer(bytes)
			if err == OK:
				return ImageTexture.create_from_image(img)
	return null
