extends RefCounted
## One fixed cadence for dirty game progress; manual/lifecycle flushes are separate.
## SDK acceptance still never confirms remote cloud persistence.
const INTERVAL_SECONDS=5.0
static func due(_crazygames:bool,dirty:bool,seconds:float,pending:bool,blocked:bool,dragging:bool)->bool:
	return dirty and seconds>=INTERVAL_SECONDS and not pending and not blocked and not dragging
