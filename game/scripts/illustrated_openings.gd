extends RefCounted
## Actual holes: wall faces are partitioned around each hosted aperture.
## Casing, reveals and glass never paint a solid wall behind an opening.
const Geometry=preload("res://scripts/cafe_wall_openings.gd")
const WallArt=preload("res://scripts/illustrated_walls.gd")
static func front(host:Dictionary)->Vector2:return Vector2.ZERO if host.shell else host.normal*.5
static func back(host:Dictionary)->Vector2:return host.normal if host.shell else -host.normal*.5
static func world(host:Dictionary,t:float)->Vector2:return host.a+(host.b-host.a).normalized()*t
static func p(view,host:Dictionary,t:float,h:float,offset:Vector2)->Vector2:
	var point=world(host,t)+offset;return view.iso(point.x,point.y,h)
static func quad(view,points:Array,color,uvs:Array=[],texture:Texture2D=null):
	var tint=Color(color);preload("res://scripts/cafe_canvas_draw.gd").draw_polygon(view,PackedVector2Array(points),PackedColorArray([tint,tint,tint,tint]),PackedVector2Array(uvs),texture)
static func tinted(value,alpha:float,tint:Color)->Color:return Color(value)*Color(tint.r,tint.g,tint.b,alpha*tint.a)
static func face(view,host:Dictionary,a:float,b:float,low:float,high:float,original_base="cfdbc2",original_panel="819874",alpha=1.0,tint=Color.WHITE):
	if b<=a+.00001 or high<=low+.00001:return
	var offset=front(host);var height=128.0 if host.height=="full" else 58.0
	if host.material=="original":
		view.poly([p(view,host,a,low,offset),p(view,host,b,low,offset),p(view,host,b,high,offset),p(view,host,a,high,offset)],tinted(original_base,alpha,tint))
		if low<36:
			view.poly([p(view,host,a,low,offset),p(view,host,b,low,offset),p(view,host,b,minf(high,36),offset),p(view,host,a,minf(high,36),offset)],tinted(original_panel,alpha,tint))
		if low<=36 and high>=36:view.line(p(view,host,a,36,offset),p(view,host,b,36,offset),tinted("a9b797",alpha,tint),2*view.ui_scale)
		return
	var texture=WallArt.texture_for(str(host.material),str(host.height))
	for tile in range(floori(a),ceili(b)):
		var start=maxf(a,tile);var finish=minf(b,tile+1)
		quad(view,[p(view,host,start,low,offset),p(view,host,finish,low,offset),p(view,host,finish,high,offset),p(view,host,start,high,offset)],tinted(Color.WHITE,alpha,tint),[Vector2(start-tile,1-low/height),Vector2(finish-tile,1-low/height),Vector2(finish-tile,1-high/height),Vector2(start-tile,1-high/height)],texture)
static func cap(view,host:Dictionary,a:float,b:float,alpha=1.0,tint=Color.WHITE):
	var h=128.0 if host.height=="full" else 58.0
	var color="fff1d0" if host.material=="original" else WallArt.PALETTES[host.material].cap
	quad(view,[p(view,host,a,h,front(host)),p(view,host,b,h,front(host)),p(view,host,b,h,back(host)),p(view,host,a,h,back(host))],tinted(color,alpha,tint))
static func end_face(view,host:Dictionary,t:float,low:float,high:float,alpha=1.0,tint=Color.WHITE):
	var color="b8c7a8" if host.material=="original" else WallArt.PALETTES[host.material].end
	quad(view,[p(view,host,t,low,front(host)),p(view,host,t,low,back(host)),p(view,host,t,high,back(host)),p(view,host,t,high,front(host))],tinted(color,alpha,tint))
static func segment_selection_geometry(view,host:Dictionary)->Dictionary:
	# Outline the visible faces of the complete wall product, using its actual
	# thickness. These are selection edges, not new gaps or interior wall faces.
	var length=host.a.distance_to(host.b);var height=128.0 if host.height=="full" else 58.0
	var a=p(view,host,0,0,front(host));var b=p(view,host,length,0,front(host))
	var ah=p(view,host,0,height,front(host));var bh=p(view,host,length,height,front(host))
	var ab=p(view,host,0,height,back(host));var bb=p(view,host,length,height,back(host))
	var bottom_back=p(view,host,length,0,back(host))
	return {"front":PackedVector2Array([a,b,bh,ah]),"cap":PackedVector2Array([ah,bh,bb,ab]),"near_end":PackedVector2Array([b,bottom_back,bb,bh]),
		"edges":PackedVector2Array([a,b,b,bh,bh,ah,ah,a,ah,ab,ab,bb,bb,bh,b,bottom_back,bottom_back,bb])}
static func draw_shell(view,host:Dictionary,attachments:Array,base_color,panel_color):
	if host.has("segment_runs"):
		draw_shell_runs(view,host,attachments,base_color,panel_color);return
	var panels=Geometry.solid_panels(host,view.game.model.built_walls,attachments)
	for panel in panels:face(view,host,panel.from,panel.to,panel.bottom,panel.top,base_color,panel_color)
	var length=host.a.distance_to(host.b);cap(view,host,0,length)
	for panel in panels:
		if float(panel.to)>=length-.00001:end_face(view,host,length,panel.bottom,panel.top)
static func draw_shell_runs(view,root:Dictionary,attachments:Array,base_color,panel_color):
	# Runs keep the original root origin, so texture UVs and aperture offsets
	# never restart at a style boundary. No end face is added at equal heights.
	var runs:Array=root.segment_runs;var length=root.a.distance_to(root.b)
	for index in runs.size():
		var run:Dictionary=runs[index];var host=root.duplicate(true)
		host.height=run.height;host.material=run.material
		var a=float(run.from);var b=float(run.to)
		var panels=Geometry.solid_panels(host,view.game.model.built_walls,attachments)
		for panel in panels:
			face(view,host,maxf(a,float(panel.from)),minf(b,float(panel.to)),panel.bottom,panel.top,base_color,panel_color)
		cap(view,host,a,b)
		if b>=length-.00001:
			for panel in panels:
				if float(panel.to)>=length-.00001:end_face(view,host,length,panel.bottom,panel.top)
		elif index+1<runs.size():
			var next:Dictionary=runs[index+1]
			if run.height=="full" and next.height=="half":end_face(view,host,b,58,128)
			elif run.height=="half" and next.height=="full":
				var tall=root.duplicate(true);tall.height=next.height;tall.material=next.material;end_face(view,tall,b,58,128)
static func draw_built_piece(view,piece:Dictionary,attachments:Array,alpha=1.0,tint=Color.WHITE):
	var wall:Dictionary=piece.entry
	var host=Geometry.wall_host(wall)
	if bool(wall.get("preview",false)) or int(wall.get("id",-1))<0 or Geometry.cuts(host,view.game.model.built_walls,attachments).is_empty():WallArt.draw_piece(view,piece,alpha,tint);return
	var a=float(piece.wall_t0);var b=float(piece.wall_t1)
	var panels=Geometry.solid_panels(host,view.game.model.built_walls,attachments)
	for panel in panels:
		var start=maxf(a,float(panel.from));var finish=minf(b,float(panel.to))
		if finish>start+.00001:face(view,host,start,finish,panel.bottom,panel.top,"cfdbc2","819874",alpha,tint)
	cap(view,host,a,b,alpha,tint)
	if piece.wall_end:
		for panel in panels:
			if float(panel.to)>=1.0-.00001:end_face(view,host,1,panel.bottom,panel.top,alpha,tint)
static func depth_entries(opening:Dictionary)->Array[Dictionary]:
	var a:Vector2=opening.a;var b:Vector2=opening.b;var middle=(a+b)*.5
	return [{"type":"opening_frame","depth":a.x+a.y+.015,"entry":opening,"part":"start"},
		{"type":"opening_frame","depth":middle.x+middle.y+.02,"entry":opening,"part":"middle"},
		{"type":"opening_frame","depth":b.x+b.y+.05,"entry":opening,"part":"end"}]
static func visible_jamb_reveal(view,opening:Dictionary)->Array[PackedVector2Array]:
	var host:Dictionary=opening.host;var a:Vector2=opening.a;var b:Vector2=opening.b
	var low=float(opening.bottom);var high=float(opening.top)
	var af=a+front(host);var bf=b+front(host);var ab=a+back(host)
	var aperture=PackedVector2Array([view.iso(af.x,af.y,low),view.iso(bf.x,bf.y,low),view.iso(bf.x,bf.y,high),view.iso(af.x,af.y,high)])
	var reveal=PackedVector2Array([view.iso(af.x,af.y,low),view.iso(ab.x,ab.y,low),view.iso(ab.x,ab.y,high),view.iso(af.x,af.y,high)])
	# The back of the jamb projects above the front aperture. The solid lintel
	# has already been drawn, so this later reveal must not repaint through it.
	# Clip the visible face only; the wall/opening dimensions remain untouched.
	return Geometry2D.intersect_polygons(reveal,aperture)
static func casing(view,opening:Dictionary,part:String,alpha=1.0,tint=Color.WHITE):
	var host:Dictionary=opening.host;var axis:Vector2=(host.b-host.a).normalized();var normal:Vector2=host.normal
	var near=front(host)+(normal.normalized()*.008 if not host.shell else -normal.normalized()*.01)
	var far=back(host);var a:Vector2=opening.a;var b:Vector2=opening.b
	var low=float(opening.bottom);var high=float(opening.top)
	var half=.085 if opening.kind=="door" and float(opening.width)>1.0 else .045
	var color=Color("597d60")*Color(tint.r,tint.g,tint.b,alpha*tint.a)
	var reveal=Color("dce2c9")*Color(tint.r,tint.g,tint.b,alpha*tint.a)
	if part in ["start","end"]:
		var endpoint=a if part=="start" else b
		var left=endpoint-axis*half+near;var right=endpoint+axis*half+near
		# Only the far reveal faces the camera. Its front casing is drawn last.
		if part=="start":
			for visible_face in visible_jamb_reveal(view,opening):preload("res://scripts/cafe_canvas_draw.gd").draw_colored_polygon(view,visible_face,reveal)
		quad(view,[view.iso(left.x,left.y,low),view.iso(right.x,right.y,low),view.iso(right.x,right.y,high+4),view.iso(left.x,left.y,high+4)],color)
	else:
		var left=a-axis*half+near;var right=b+axis*half+near
		quad(view,[view.iso(left.x,left.y,high+4),view.iso(right.x,right.y,high+4),view.iso(right.x,right.y,high-1),view.iso(left.x,left.y,high-1)],color)
		if opening.kind=="window":
			var af=a+front(host);var bf=b+front(host);var ab=a+far;var bb=b+far
			quad(view,[view.iso(af.x,af.y,low),view.iso(bf.x,bf.y,low),view.iso(bf.x,bf.y,high),view.iso(af.x,af.y,high)],Color(.68,.84,.79,.18*alpha))
			quad(view,[view.iso(af.x,af.y,low),view.iso(bf.x,bf.y,low),view.iso(bb.x,bb.y,low),view.iso(ab.x,ab.y,low)],Color("edf0d8")*Color(1,1,1,alpha))
			quad(view,[view.iso(left.x,left.y,low+1),view.iso(right.x,right.y,low+1),view.iso(right.x,right.y,low-3),view.iso(left.x,left.y,low-3)],tinted(color,alpha,tint))
static func threshold(view,opening:Dictionary):
	if opening.kind!="door":return
	var host:Dictionary=opening.host;var a:Vector2=opening.a;var b:Vector2=opening.b
	var near=front(host);var far=back(host)
	quad(view,[view.iso(a.x+near.x,a.y+near.y),view.iso(b.x+near.x,b.y+near.y),view.iso(b.x+far.x,b.y+far.y),view.iso(a.x+far.x,a.y+far.y)],"e4dbb8")
static func hit_host(view,screen:Vector2,host:Dictionary)->bool:
	var height=128.0 if host.height=="full" else 58.0;var a:Vector2=host.a+front(host);var b:Vector2=host.b+front(host)
	return Geometry2D.is_point_in_polygon(screen,PackedVector2Array([view.iso(a.x,a.y),view.iso(b.x,b.y),view.iso(b.x,b.y,height),view.iso(a.x,a.y,height)]))
static func hit_opening(view,screen:Vector2,opening:Dictionary)->bool:
	var near=front(opening.host);var a:Vector2=opening.a+near;var b:Vector2=opening.b+near
	return Geometry2D.is_point_in_polygon(screen,PackedVector2Array([view.iso(a.x,a.y,opening.bottom),view.iso(b.x,b.y,opening.bottom),view.iso(b.x,b.y,opening.top+4),view.iso(a.x,a.y,opening.top+4)]))
