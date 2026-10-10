extends RefCounted
## Original sage/cream artwork, rasterized once from editable SVG strings.
## Four small independently sorted slices give local wall/actor occlusion.
## Each slice costs one textured face and one solid cap; only the last slice
## adds an end face. No per-frame decorative primitive or texture generation.
const Geometry=preload("res://scripts/cafe_walls.gd")
const SLICES:=4
const PALETTES:={
	"sage_panels":{"base":"dce4cb","panel":"8fa57d","ink":"a5b48d","cap":"fff0d1","end":"aebd98"},
	"cream_stripe":{"base":"f4ead1","panel":"c4ba99","ink":"ded2ac","cap":"fff4dd","end":"cfc4a4"},
	"leaf_print":{"base":"e7ecd8","panel":"a6b28b","ink":"98ac83","cap":"fff0d1","end":"bec9a6"},
}
static var _textures:Dictionary={}

static func depth_entries(wall:Dictionary) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for index in range(SLICES):
		var t0:=float(index)/SLICES
		var t1:=float(index+1)/SLICES
		result.append({"depth":float(wall.x+wall.z)+(t0+t1)*.5+Geometry.THICKNESS*.5,"type":"built_wall","entry":wall,"wall_t0":t0,"wall_t1":t1,"wall_end":index==SLICES-1})
	return result

static func face_svg(material:String,height:String) -> String:
	var palette:Dictionary=PALETTES.get(material,PALETTES.sage_panels)
	var panel_y:=184 if height=="full" else 168
	var content:="<rect width='96' height='256' fill='#%s'/>"%palette.base
	if material=="cream_stripe":
		for x in [12,36,60,84]:content+="<path d='M%d 0V%d' stroke='#%s' stroke-width='6'/>"%[x,panel_y,palette.ink]
	elif material=="leaf_print":
		for point in [Vector2i(24,40),Vector2i(72,94),Vector2i(24,143)]:
			content+="<g transform='translate(%d %d)'><path d='M0 11V-10' stroke='#%s' stroke-width='2'/><path d='M0 0C-15 0 -14 -16 -2 -11C3 -8 3 -4 0 0M0 6C15 7 15 -9 3 -5C-1 -3 -2 2 0 6' fill='#%s'/></g>"%[point.x,point.y,palette.ink,palette.ink]
	else:
		for x in [24,72]:content+="<path d='M%d 0V%d' stroke='#%s' stroke-width='1.5' opacity='.55'/>"%[x,panel_y,palette.ink]
	content+="<rect y='%d' width='96' height='%d' fill='#%s'/><path d='M0 %dH96' stroke='#%s' stroke-width='7'/><path d='M0 %dH96M0 249H96' stroke='#%s' stroke-width='3'/>"%[panel_y,256-panel_y,palette.panel,panel_y,palette.cap,panel_y+7,palette.ink]
	for x in [4,48,92]:content+="<path d='M%d %dV249' stroke='#%s' stroke-width='2'/>"%[x,panel_y+9,palette.ink]
	return "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='256' viewBox='0 0 96 256'>"+content+"</svg>"

static func texture_for(material:String,height:String) -> Texture2D:
	var key:=material+":"+height
	if not _textures.has(key):
		var image:=Image.new()
		if image.load_svg_from_string(face_svg(material,height))!=OK:return null
		_textures[key]=ImageTexture.create_from_image(image)
	return _textures[key]

static func _polygon(view:Node2D,points:Array,color:Color,uvs:Array=[],texture:Texture2D=null):
	var colors:=PackedColorArray([color,color,color,color])
	view.draw_polygon(PackedVector2Array(points),colors,PackedVector2Array(uvs),texture)

static func draw_piece(view:Node2D,piece:Dictionary,alpha:float=1.0,tint:Color=Color.WHITE):
	var wall:Dictionary=piece.entry
	var ends:=Geometry.endpoints(wall)
	var start:Vector2=ends[0].lerp(ends[1],float(piece.get("wall_t0",0.0)))
	var finish:Vector2=ends[0].lerp(ends[1],float(piece.get("wall_t1",1.0)))
	var normal:Vector2=(Vector2.DOWN if wall.axis=="x" else Vector2.RIGHT)*Geometry.THICKNESS*.5
	var height:=float(Geometry.HEIGHT_PIXELS.get(str(wall.height),128.0))
	var p0:Vector2=view.iso(start.x+normal.x,start.y+normal.y)
	var p1:Vector2=view.iso(finish.x+normal.x,finish.y+normal.y)
	var p2:Vector2=view.iso(finish.x+normal.x,finish.y+normal.y,height)
	var p3:Vector2=view.iso(start.x+normal.x,start.y+normal.y,height)
	var back_end:Vector2=view.iso(finish.x-normal.x,finish.y-normal.y,height)
	var back_start:Vector2=view.iso(start.x-normal.x,start.y-normal.y,height)
	var color:=Color(tint.r,tint.g,tint.b,alpha*tint.a)
	var palette:Dictionary=PALETTES.get(str(wall.material),PALETTES.sage_panels)
	_polygon(view,[p0,p1,p2,p3],color,[Vector2(piece.wall_t0,1),Vector2(piece.wall_t1,1),Vector2(piece.wall_t1,0),Vector2(piece.wall_t0,0)],texture_for(str(wall.material),str(wall.height)))
	_polygon(view,[p3,p2,back_end,back_start],Color(palette.cap)*color)
	if bool(piece.get("wall_end",true)):
		_polygon(view,[p1,view.iso(finish.x-normal.x,finish.y-normal.y),back_end,p2],Color(palette.end)*color)

static func draw_wall(view:Node2D,wall:Dictionary,alpha:float=1.0,tint:Color=Color.WHITE):
	for piece in depth_entries(wall):draw_piece(view,piece,alpha,tint)
