extends RefCounted
## Explicit script dispatch for typed Node2D callers; native methods are nonvirtual.
static func draw_set_transform_matrix(artist,value:Transform2D):
 if artist.has_method("art_draw_set_transform_matrix"):
  artist.art_draw_set_transform_matrix(value)
 else:artist.draw_set_transform_matrix(value)

static func draw_mesh(artist,mesh:Mesh,texture:Texture2D=null,xf:Transform2D=Transform2D.IDENTITY,tint:Color=Color.WHITE):
 if artist.has_method("art_draw_mesh"):
  artist.art_draw_mesh(mesh,texture,xf,tint)
 else:artist.draw_mesh(mesh,texture,xf,tint)

static func draw_polygon(artist,points:PackedVector2Array,colors:PackedColorArray,uvs:PackedVector2Array=PackedVector2Array(),texture:Texture2D=null):
 if artist.has_method("art_draw_polygon"):
  artist.art_draw_polygon(points,colors,uvs,texture)
 else:artist.draw_polygon(points,colors,uvs,texture)

static func draw_colored_polygon(artist,points:PackedVector2Array,tint:Color,uvs:PackedVector2Array=PackedVector2Array(),texture:Texture2D=null):
 if artist.has_method("art_draw_colored_polygon"):
  artist.art_draw_colored_polygon(points,tint,uvs,texture)
 else:artist.draw_colored_polygon(points,tint,uvs,texture)

static func draw_polyline(artist,points:PackedVector2Array,tint:Color,width:float=-1.0,antialiased:bool=false):
 if artist.has_method("art_draw_polyline"):
  artist.art_draw_polyline(points,tint,width,antialiased)
 else:artist.draw_polyline(points,tint,width,antialiased)

static func draw_multiline(artist,points:PackedVector2Array,tint:Color,width:float=-1.0,antialiased:bool=false):
 if artist.has_method("art_draw_multiline"):
  artist.art_draw_multiline(points,tint,width,antialiased)
 else:artist.draw_multiline(points,tint,width,antialiased)

static func draw_line(artist,start:Vector2,finish:Vector2,tint:Color,width:float=-1.0,antialiased:bool=false):
 if artist.has_method("art_draw_line"):
  artist.art_draw_line(start,finish,tint,width,antialiased)
 else:artist.draw_line(start,finish,tint,width,antialiased)

static func draw_rect(artist,rect:Rect2,tint:Color,filled:bool=true,width:float=-1.0,antialiased:bool=false):
 if artist.has_method("art_draw_rect"):
  artist.art_draw_rect(rect,tint,filled,width,antialiased)
 else:artist.draw_rect(rect,tint,filled,width,antialiased)

static func draw_texture_rect_region(artist,texture:Texture2D,rect:Rect2,source:Rect2,tint:Color=Color.WHITE,transpose:bool=false,clip_uv:bool=true):
 if artist.has_method("art_draw_texture_rect_region"):
  artist.art_draw_texture_rect_region(texture,rect,source,tint,transpose,clip_uv)
 else:artist.draw_texture_rect_region(texture,rect,source,tint,transpose,clip_uv)

static func draw_circle(artist,pos:Vector2,radius:float,tint:Color,filled:bool=true,width:float=-1.0,antialiased:bool=false):
 if artist.has_method("art_draw_circle"):
  artist.art_draw_circle(pos,radius,tint,filled,width,antialiased)
 else:artist.draw_circle(pos,radius,tint,filled,width,antialiased)

static func draw_string(artist,font:Font,pos:Vector2,text:String,alignment:HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT,width:float=-1,font_size:int=16,tint:Color=Color.WHITE,justification_flags:int=3,direction:TextServer.Direction=TextServer.DIRECTION_AUTO,orientation:TextServer.Orientation=TextServer.ORIENTATION_HORIZONTAL,oversampling:float=0.0):
 if artist.has_method("art_draw_string"):
  artist.art_draw_string(font,pos,text,alignment,width,font_size,tint,justification_flags,direction,orientation,oversampling)
 else:artist.draw_string(font,pos,text,alignment,width,font_size,tint,justification_flags,direction,orientation,oversampling)

