class_name ManualComplementIntent
extends RefCounted
## Explicit single-use traceability intent required by ConstructionSite.authorize_manual_complement().
## Acts as an architectural origin-tracking and anti-accidental-trigger guard (DEC-11B),
## not as cryptographic proof of human interaction.

enum OriginKind {
	PLAYER_UI,
	TEST_HARNESS,
}

var origin_kind: OriginKind = OriginKind.TEST_HARNESS
var target_site: ConstructionSite = null
var issuer_ref: WeakRef = null
var consumed: bool = false
var _factory_authorized: bool = false


static func create_from_player_ui(
	ui_control: Control,
	site: ConstructionSite
) -> ManualComplementIntent:
	if ui_control == null or not is_instance_valid(ui_control):
		return null
	if site == null or not is_instance_valid(site):
		return null
	if not is_valid_issuer(ui_control, OriginKind.PLAYER_UI):
		return null
	return _make_intent(OriginKind.PLAYER_UI, ui_control, site)


static func create_for_test(
	test_owner: Object,
	site: ConstructionSite
) -> ManualComplementIntent:
	if test_owner == null or not is_instance_valid(test_owner):
		return null
	if site == null or not is_instance_valid(site):
		return null
	if not is_valid_issuer(test_owner, OriginKind.TEST_HARNESS):
		return null
	return _make_intent(OriginKind.TEST_HARNESS, test_owner, site)


static func _make_intent(
	p_origin: OriginKind,
	p_issuer: Object,
	p_site: ConstructionSite
) -> ManualComplementIntent:
	var intent := ManualComplementIntent.new()
	intent.origin_kind = p_origin
	intent.target_site = p_site
	intent.issuer_ref = weakref(p_issuer)
	intent.consumed = false
	intent._factory_authorized = true
	return intent


static func is_valid_issuer(issuer: Variant, expected_origin: OriginKind) -> bool:
	if issuer == null or not (issuer is Object):
		return false
	var obj: Object = issuer as Object
	if not is_instance_valid(obj):
		return false
	if (
		obj is SettlementStorageSource
		or obj is SettlementInventory
		or obj is EconomyClockController
		or obj is UnitOrder
		or obj is ConstructionSite
		or obj is ConstructionManager
	):
		return false
	if expected_origin == OriginKind.PLAYER_UI:
		return obj is Control and (obj as Control).is_inside_tree()
	return true


func is_structurally_valid_for(site: ConstructionSite) -> bool:
	if consumed or not _factory_authorized:
		return false
	if site == null or not is_instance_valid(site) or target_site != site:
		return false
	if issuer_ref == null:
		return false
	var issuer: Variant = issuer_ref.get_ref()
	return is_valid_issuer(issuer, origin_kind)
