extends RefCounted
## Review candidate clothing only. Reviewed bear head/fur/pose are untouched.
const Wardrobe = preload("res://scripts/customer_wardrobe.gd")
const TONES = {
	"sage":"a9b78a", "warm_brown":"aa9277", "cream":"efe5c7", "muted_rose":"c98e83", "espresso":"69634f",
	"muted_teal":"9cbbbd", "cocoa":"97856e", "oat":"e5d9b8", "dusty_mauve":"b99aab",
	"mauve":"b99aab", "dark_sage":"839476", "ivory":"f3e7ca", "soft_rose":"d3a39a"
}
static func options(appearance: Dictionary) -> Dictionary:
	var checked: Dictionary = Wardrobe.validate(appearance.get("wardrobe"))
	if not checked.ok or checked.record.species != "bear": return {}
	var record: Dictionary = checked.record
	var palette: Dictionary = Wardrobe.Catalog.PALETTES[record.palette]
	return {"shirt":TONES[palette.primary], "trousers":TONES[palette.neutral], "shoe_color":TONES[palette.dark], "legwear_color":TONES[palette.light], "accent":TONES[palette.accent], "outfit_items":record.items.duplicate(true)}
