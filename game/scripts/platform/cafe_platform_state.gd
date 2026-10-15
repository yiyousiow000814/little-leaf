extends RefCounted
## Gameplay begins only when the cafe can accept actual play input.
static func playable(paused:bool,editing:bool,recovery:bool,intro:bool,too_small:bool,modal:bool)->bool:
	return not (paused or editing or recovery or intro or too_small or modal)
