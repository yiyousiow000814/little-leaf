extends "res://scripts/illustrated_cafe.gd"
## A retained UI portrait using the exact in-cafe character painter. It owns
## no model, animation loop, viewport, texture bake or simulation state.
var staff_role="chef"
var member_id=0
var backdrop=Color("dce9d5")
func _ready():
 set_process(false);texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
func set_member(index:int):
 if member_id==index:return
 member_id=index;queue_redraw()
func _draw():
 draw_circle(Vector2(0,-37),33,backdrop)
 character(Vector2.ZERO,member_id,true,false,false,"idle",0.0,Vector2(18,-28),Vector2(1,0),"none","none",{},staff_role)
