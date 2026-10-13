extends RefCounted
## Submission cadence only; SDK acceptance never confirms remote cloud persistence.
static func due(crazygames:bool,dirty:bool,seconds:float,pending:bool,blocked:bool,dragging:bool)->bool:
	if not crazygames:return seconds>15.0 and not dragging
	return dirty and seconds>=5.0 and not pending and not blocked and not dragging
