extends RefCounted
## A new profile may begin its first real visit on the existing near street,
## but only entirely outside the current rendered view. Later visits still
## start at the fixed world endpoints. Never move the camera or an actor.
const MIN_Z=10.8
const MAX_Z=26.0 # Existing short-route bounds also allow a closed guest's return.
const STEP=.25

static func character_bounds(art,position:Vector2)->Rect2:
 var scale=maxf(.1,art.ui_scale*art.zoom*(1.55 if art.game.wall_detail else 1.0))
 var feet:Vector2=art.iso(position.x,position.y)
 # Conservative full-body / carried-prop bounds plus a walking-frame margin.
 return Rect2(feet-Vector2(48,92)*scale,Vector2(96,112)*scale).grow(12.0)

static func offscreen_start(game)->Vector2:
 if not is_instance_valid(game.illustration) or game.compact_ui.viewport_too_small:return Vector2.INF
 var art=game.illustration
 var viewport:Rect2=art.get_viewport_rect()
 # Projection is updated by normal camera/resize handling and the renderer.
 # Do not use the intro's temporary downward drawing offset as a spawn edge.
 for index in range(int(ceil((MAX_Z-MIN_Z)/STEP))+1):
  var position=Vector2(game.model.ARRIVAL_LANE_X,minf(MAX_Z,MIN_Z+index*STEP))
  if not character_bounds(art,position).intersects(viewport):return position
 return Vector2.INF
