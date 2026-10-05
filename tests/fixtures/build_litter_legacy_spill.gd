extends RefCounted
## Deterministic synthetic fixture, independent of profiles or player saves.
## Replays seed 60's first geometry attempt from the frozen legacy implementation.
const LegacyGeometry=preload("res://tests/fixtures/litter_art_v2/cafe_floor_geometry.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")

static func build()->Dictionary:
	var cell=Vector2i(4,6)
	var seed=60 # Synthetic mess id 1 * 47 + synthetic guest id 1 * 13.
	var center=Vector2(cell)+Vector2(.5,.5)
	center+=Vector2(LegacyGeometry._fraction(seed,70)-.5,LegacyGeometry._fraction(seed,71)-.5)*.64
	var entry={"id":1,"token":1,"floor_cell":cell,"floor_target":center,
		"debris_target":center,"spill_target":center,"floor_debris":"none",
		"floor_spill":true,"spill_remaining":1.0,"spill_cleaned":false,
		"trash_owner":"none","trash_staff_index":-1,"trash_target_id":-1,
		"floor_dirty":true,"floor_cleaned":false,"source_guest_id":1,"spawn_path_step":3}
	entry.mess_shape=LegacyGeometry._build(entry,seed,1.0)
	var snapshot={"next_id":2,"completed":0,"messes":[entry],"walks":[{
		"guest_id":1,"cell":Vector2i(5,6),"pos":Vector2(5.5,6.5),"inside_steps":3,"dropped":true}]}
	return {"messes":Codec.new().encode(snapshot)}
