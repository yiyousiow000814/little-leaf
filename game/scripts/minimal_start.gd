extends RefCounted
# Public fresh profile is intentionally sparse. Historical fixture reset_new()
# stays available for regression tests; saved restaurants are never replaced.
static func apply(model):
	model.reset_new()
	model.first_guest_pending=true
	var basics:Array[Dictionary]=[]
	for item in model.items:
		if int(item.id) in [1,2,3,4,6,7]:
			if int(item.id)==4:item.x=6;item.z=2
			basics.append(item)
	model.items.assign(basics)
	model.rebuild_dining_sets()
	model.ensure_basic_register()
	model.last_event="Your small cafe is ready · Decorate to make it yours"
	model.changed.emit()
