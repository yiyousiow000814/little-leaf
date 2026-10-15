extends RefCounted
const StarterPreset=preload("res://scripts/gameplay/cafe_starter_preset.gd")
# Public fresh profile is intentionally sparse. Historical fixture reset_new()
# stays available for regression tests; saved restaurants are never replaced.
static func apply(model):
	model.reset_new()
	model.first_guest_pending=true
	# Direct cleanup needs no starter bin. Optional shop purchases use the
	# catalog price; historical entitlements are retained by the save reader.
	model.included_bin_pending=false
	model.items.assign(StarterPreset.select_public_furniture(model.items))
	model.rebuild_dining_sets()
	model.ensure_basic_register()
	model.last_event="Your small cafe is ready · Decorate to make it yours"
	model.changed.emit()
