extends RefCounted
## Inner wood face, measured on the original 512 x 158 shop_frame.png.
## Its 64px nine-slice corners stay unscaled in both mail panels. Leaf tips and
## the outer bevel are not content space: left/right 32, top 26, bottom 24px.
const WOOD_FACE=Vector4(32,26,32,24)

static func apply(panel:PanelContainer,width:float):
 var breathing=6.0 if width<480 else 10.0
 var inset=WOOD_FACE+Vector4(breathing,breathing,breathing,breathing)
 var style=panel.get_theme_stylebox("panel")
 for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
  if style.get_content_margin(side)!=inset[side]:style.set_content_margin(side,inset[side])

static func inner_rect(panel:Control)->Rect2:
 return Rect2(panel.global_position+Vector2(WOOD_FACE.x,WOOD_FACE.y),panel.size-Vector2(WOOD_FACE.x+WOOD_FACE.z,WOOD_FACE.y+WOOD_FACE.w))

# Short landscape needs the available safe height rather than a tall-screen
# percentage; keep a 12px exterior gap on both edges, outside the wood itself.
static func height_budget(view:Vector2,insets:Vector4,preferred:float)->float:
 var safe_height=maxf(0,view.y-insets.y-insets.w)
 var available=maxf(0,safe_height-24)
 return available if safe_height<500 else minf(available,preferred)
