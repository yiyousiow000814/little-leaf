extends RefCounted

# Reuse successful-transaction hooks, the existing voice, bus and preferences.
const CASH = preload("res://assets/audio/sfx/SfxCash.mp3")
const PLACE = preload("res://assets/audio/sfx/placement_volume_v02.wav")
const COIN_DROP = preload("res://assets/audio/sfx/SfxCoinDrop.mp3")
const COIN_PICKUP = preload("res://assets/audio/sfx/SfxCoinPickUp.mp3")

static func install(settings):
	settings.effects["coin"] = CASH
	settings.effects["place"] = PLACE
	settings.effects["coin_drop"] = COIN_DROP
	settings.effects["coin_pickup"] = COIN_PICKUP
