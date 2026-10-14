extends RefCounted

# Reuse successful-transaction hooks, the existing voice, bus and preferences.
const CASH = preload("res://assets/audio/sfx/SfxCash.mp3")
const PLACE = preload("res://assets/audio/sfx/placement_volume_v02.wav")

static func install(settings):
	settings.effects["coin"] = CASH
	settings.effects["place"] = PLACE
