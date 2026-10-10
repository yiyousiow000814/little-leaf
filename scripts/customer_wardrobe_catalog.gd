extends RefCounted
## Candidate contracts, not approved artwork. No resources or runtime side effects.
const REVISION = "customer-draft-1"
const SPECIES = ["bear", "rabbit", "fox", "cat", "dog", "red_panda"]
const SLOTS = ["top", "lower", "shoes", "legwear", "glasses", "headwear", "ribbon", "back_bow"]
const OPTIONAL = ["legwear", "glasses", "headwear", "ribbon", "back_bow"]
const PALETTES = {
	"sage_cream": {"primary": "sage", "neutral": "warm_brown", "light": "cream", "accent": "muted_rose", "dark": "espresso"},
	"teal_oat": {"primary": "muted_teal", "neutral": "cocoa", "light": "oat", "accent": "dusty_mauve", "dark": "espresso"},
	"mauve_ivory": {"primary": "mauve", "neutral": "dark_sage", "light": "ivory", "accent": "soft_rose", "dark": "warm_brown"}
}
const COLOR_ROLES = {"top": "primary", "lower": "neutral", "shoes": "dark", "legwear": "light", "glasses": "dark", "headwear": "light", "ribbon": "accent", "back_bow": "accent"}
# Fur IDs describe natural markings, never clothing recolors. Final art is pending.
const FUR = {
	"bear": [{"id": "brown_muzzle", "coat": "brown", "markings": "cream_muzzle"}, {"id": "dark_brown_muzzle", "coat": "dark_brown", "markings": "tan_muzzle"}],
	"rabbit": [{"id": "cream_pink_ears", "coat": "cream", "markings": "pink_inner_ears"}, {"id": "brown_white_muzzle", "coat": "brown", "markings": "white_muzzle_pink_inner_ears"}],
	"fox": [{"id": "russet_white_black", "coat": "russet", "markings": "white_muzzle_chest_tail_tip_black_legs"}, {"id": "red_white_black", "coat": "red_brown", "markings": "white_muzzle_chest_tail_tip_black_legs"}],
	"cat": [{"id": "brown_tabby", "coat": "brown", "markings": "dark_tabby_stripes"}, {"id": "black_white", "coat": "black", "markings": "white_muzzle_chest_paws"}],
	"dog": [{"id": "tan_white", "coat": "tan", "markings": "white_muzzle_chest"}, {"id": "brown_white", "coat": "brown", "markings": "white_muzzle_chest_paws"}],
	"red_panda": [{"id": "russet_mask_rings", "coat": "russet", "markings": "white_face_mask_dark_legs_ringed_tail"}, {"id": "auburn_mask_rings", "coat": "auburn", "markings": "white_face_mask_dark_legs_ringed_tail"}]
}
const FIT = {
	"bear": {"ears": "round", "tail": "short", "face": "broad_muzzle"},
	"rabbit": {"ears": "long_asymmetric_droop_pink_inner", "tail": "short", "face": "short_muzzle"},
	"fox": {"ears": "pointed", "tail": "bushy", "face": "long_muzzle"},
	"cat": {"ears": "pointed", "tail": "long", "face": "short_muzzle"},
	"dog": {"ears": "soft_floppy", "tail": "long", "face": "long_muzzle"},
	"red_panda": {"ears": "round", "tail": "bushy_ringed", "face": "masked_muzzle"}
}
const ITEMS = {
	"top_shirt": {"slot": "top", "anchor": "torso", "fit": "connected_sleeves"},
	"top_cardigan": {"slot": "top", "anchor": "torso", "fit": "connected_sleeves"},
	"lower_trousers": {"slot": "lower", "anchor": "hips", "fit": "tail_clear_cuff"},
	"lower_skirt": {"slot": "lower", "anchor": "hips", "fit": "tail_clear_seated_hem"},
	"shoes_loafers": {"slot": "shoes", "anchor": "feet", "fit": "paw_ankle_join"},
	"shoes_boots": {"slot": "shoes", "anchor": "feet", "fit": "paw_ankle_join", "excludes": ["legwear_socks"]},
	"legwear_socks": {"slot": "legwear", "anchor": "legs", "fit": "cuff_join"},
	"legwear_tights": {"slot": "legwear", "anchor": "legs", "fit": "waist_ankle_join", "requires": {"lower": "lower_skirt"}},
	"glasses_round": {"slot": "glasses", "anchor": "face", "fit": "species_muzzle_bridge"},
	"glasses_oval": {"slot": "glasses", "anchor": "face", "fit": "species_muzzle_bridge"},
	"headwear_open_cap": {"slot": "headwear", "anchor": "head", "fit": "ear_openings", "excludes": ["ribbon_head"]},
	"headwear_closed_cap": {"slot": "headwear", "anchor": "head", "fit": "short_ear_clearance", "species": ["bear", "red_panda"], "excludes": ["ribbon_head"]},
	"ribbon_head": {"slot": "ribbon", "anchor": "head", "fit": "flat_clip_ear_clear", "excludes": ["headwear_open_cap", "headwear_closed_cap"]},
	"bow_upper_back": {"slot": "back_bow", "anchor": "upper_back", "fit": "tail_clear_body_facing"},
	"bow_low_back": {"slot": "back_bow", "anchor": "lower_back", "fit": "short_tail_body_facing", "species": ["bear", "rabbit"]}
}

static func compatible(item_id: String, species: String, selected: Dictionary) -> bool:
	if item_id == "none": return species in SPECIES
	if not ITEMS.has(item_id) or not species in SPECIES: return false
	var item: Dictionary = ITEMS[item_id]
	if not species in item.get("species", SPECIES): return false
	for slot in item.get("requires", {}):
		if selected.get(slot) != item.requires[slot]: return false
	for other_id in selected.values():
		if other_id == "none": continue
		if not ITEMS.has(other_id): return false
		if other_id in item.get("excludes", []) or item_id in ITEMS[other_id].get("excludes", []): return false
	return true

static func candidates(slot: String, species: String, selected: Dictionary) -> Array:
	var result: Array = []
	if not slot in SLOTS or not species in SPECIES: return result
	if slot in OPTIONAL: result.append("none")
	var ids: Array = ITEMS.keys()
	ids.sort()
	for item_id in ids:
		if ITEMS[item_id].slot == slot and compatible(item_id, species, selected): result.append(item_id)
	return result

static func asset_contract(item_id: String, species: String) -> Dictionary:
	if not ITEMS.has(item_id) or not species in SPECIES: return {}
	if not species in ITEMS[item_id].get("species", SPECIES): return {}
	return {"id": "customer/%s/%s@%s" % [species, item_id, REVISION], "status": "pending_art_review", "anchor": ITEMS[item_id].anchor, "fit": ITEMS[item_id].fit, "species_fit": FIT[species].duplicate(true), "body_facing": true, "directions": 8, "poses": ["idle", "walk", "seated", "task"]}
