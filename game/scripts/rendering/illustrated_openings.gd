extends RefCounted
## Actual holes: wall faces are partitioned around each hosted aperture.
## Casing, reveals and glass never paint a solid wall behind an opening.
const Geometry=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const WallArt=preload("res://scripts/rendering/illustrated_walls.gd")
static func front(host:Dictionary)->Vector2:
	if host.has("visual_front"):return host.visual_front
	return Vector2.ZERO if host.shell else host.normal*.5
static func back(host:Dictionary)->Vector2:
	if host.has("visual_back"):return host.visual_back
	return host.normal if host.shell else WallArt.back_offset(host.normal)
static func world(host:Dictionary,t:float)->Vector2:return host.a+(host.b-host.a).normalized()*t
static func p(view,host:Dictionary,t:float,h:float,offset:Vector2)->Vector2:
	var point=world(host,t)+offset;return view.iso(point.x,point.y,h)
static func quad(view,points:Array,color,uvs:Array=[],texture:Texture2D=null):
	var tint=Color(color);preload("res://scripts/rendering/cafe_canvas_draw.gd").draw_polygon(view,PackedVector2Array(points),PackedColorArray([tint,tint,tint,tint]),PackedVector2Array(uvs),texture)
static func tinted(value,alpha:float,tint:Color)->Color:return Color(value)*Color(tint.r,tint.g,tint.b,alpha*tint.a)
static func face(view,host:Dictionary,a:float,b:float,low:float,high:float,original_base="cfdbc2",original_panel="819874",alpha=1.0,tint=Color.WHITE):
	if b<=a+.00001 or high<=low+.00001:return
	var offset=front(host);var height=128.0 if host.height=="full" else 58.0
	if host.material=="original":
		original_base="e0e7d0" if host.axis=="x" else "cfdbc2"
		original_panel="91a27d" if host.axis=="x" else "819874"
		quad(view,[p(view,host,a,low,offset),p(view,host,b,low,offset),p(view,host,b,high,offset),p(view,host,a,high,offset)],tinted(original_base,alpha,tint))
		if low<36:
			quad(view,[p(view,host,a,low,offset),p(view,host,b,low,offset),p(view,host,b,minf(high,36),offset),p(view,host,a,minf(high,36),offset)],tinted(original_panel,alpha,tint))
		# A filled rail shares exact endpoints with adjacent wall slices. An
		# antialiased line per slice leaves tiny cap notches at every boundary.
		if low<=36 and high>=36:quad(view,[p(view,host,a,35,offset),p(view,host,b,35,offset),p(view,host,b,37,offset),p(view,host,a,37,offset)],tinted("a9b797",alpha,tint))
		return
	var texture=WallArt.texture_for(str(host.material),str(host.height))
	for tile in range(floori(a),ceili(b)):
		var start=maxf(a,tile);var finish=minf(b,tile+1)
		quad(view,[p(view,host,start,low,offset),p(view,host,finish,low,offset),p(view,host,finish,high,offset),p(view,host,start,high,offset)],tinted(Color.WHITE,alpha,tint),[Vector2(start-tile,1-low/height),Vector2(finish-tile,1-low/height),Vector2(finish-tile,1-high/height),Vector2(start-tile,1-high/height)],texture)
static func cap(view,host:Dictionary,a:float,b:float,alpha=1.0,tint=Color.WHITE,back_a:float=NAN,back_b:float=NAN):
	var h=128.0 if host.height=="full" else 58.0
	var color="fff1d0" if host.material=="original" else WallArt.PALETTES[host.material].cap
	quad(view,[p(view,host,a,h,front(host)),p(view,host,b,h,front(host)),p(view,host,b if is_nan(back_b) else back_b,h,back(host)),p(view,host,a if is_nan(back_a) else back_a,h,back(host))],tinted(color,alpha,tint))
static func end_face(view,host:Dictionary,t:float,low:float,high:float,alpha=1.0,tint=Color.WHITE):
	if high<=low+.00001:return
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
		# The fixed isometric camera sees only +axis end faces. Gap starts
		# and half-to-full rises face away; Canvas2D does not cull them for us.
		if b>=length-.00001 or index+1==runs.size() or float(runs[index+1].from)>b+.00001:
			for panel in panels:
				if float(panel.to)>=b-.00001 and float(panel.from)<b-.00001:end_face(view,host,b,panel.bottom,panel.top)
		elif index+1<runs.size():
			var next:Dictionary=runs[index+1]
			if run.height=="full" and next.height=="half":end_face(view,host,b,58,128)
static func corner_cut(host:Dictionary,walls:Array,at_end:bool)->Vector2:
	# Miter only an unambiguous equal-height L joint. The saved grid edge and
	# collision profile never move; the two cap polygons meet without a notch.
	var length=host.a.distance_to(host.b);var t=length if at_end else 0.0
	var point:Vector2=host.b if at_end else host.a
	var joint={};var other_starts=false
	for wall in walls:
		if Geometry.Walls.identity(wall)==host.host_id:continue
		var other_a=Vector2(float(wall.x),float(wall.z))
		var other_b=other_a+(Vector2.RIGHT if wall.axis=="x" else Vector2.DOWN)
		if not other_a.is_equal_approx(point) and not other_b.is_equal_approx(point):continue
		if wall.axis==host.axis:return Vector2(t,t)
		if not joint.is_empty() or wall.height!=host.height:return Vector2(t,t)
		# Only the actual neighbor needs a host dictionary, not every edge.
		joint=Geometry.wall_host(wall);other_starts=other_a.is_equal_approx(point)
	if joint.is_empty():return Vector2(t,t)
	var inward=(not at_end)==other_starts
	var front_t=Geometry.axis_value(front(joint) if inward else back(joint),host.axis)
	var back_t=Geometry.axis_value(back(joint) if inward else front(joint),host.axis)
	return Vector2(t+front_t,t+back_t)

static func draw_built_piece(view,piece:Dictionary,attachments:Array,alpha=1.0,tint=Color.WHITE):
	var wall:Dictionary=piece.entry
	var host=Geometry.wall_host(wall)
	var a=float(piece.wall_t0);var b=float(piece.wall_t1)
	var cut_a=corner_cut(host,view.game.model.built_walls,false) if is_zero_approx(a) else Vector2(a,a)
	var cut_b=corner_cut(host,view.game.model.built_walls,true) if piece.wall_end else Vector2(b,b)
	var panels=Geometry.solid_panels(host,view.game.model.built_walls,attachments)
	for panel in panels:
		var start=maxf(a,float(panel.from));var finish=minf(b,float(panel.to))
		if is_zero_approx(start):start=cut_a.x
		if is_equal_approx(finish,1.0):finish=cut_b.x
		if finish>start+.00001:face(view,host,start,finish,panel.bottom,panel.top,"cfdbc2","819874",alpha,tint)
	cap(view,host,cut_a.x,cut_b.x,alpha,tint,cut_a.y,cut_b.y)
	if piece.wall_end and is_equal_approx(cut_b.x,cut_b.y):
		for panel in panels:
			if float(panel.to)>=1.0-.00001:end_face(view,host,1,maxf(float(panel.bottom),visible_end_bottom(host,view.game.model.built_walls)),panel.top,alpha,tint)
static func visible_end_bottom(host:Dictionary,walls:Array)->float:
	for wall in walls:
		var next=Geometry.wall_host(wall)
		if next.a.is_equal_approx(host.b) and next.axis==host.axis and front(next).is_equal_approx(front(host)) and back(next).is_equal_approx(back(host)):
			return Geometry.WALL_HEIGHT if next.height=="full" else 58.0
	return 0.0

static func frame_half_width(opening:Dictionary)->float:
	return .085 if opening.kind=="door" and float(opening.width)>1.0 else .045
static func frame_slice_depth(host:Dictionary,position:float)->float:
	var perpendicular=host.a.x+host.a.y-Geometry.axis_value(host.a,host.axis)
	return perpendicular+(floorf(position*WallArt.SLICES)+.5)/WallArt.SLICES+front(host).x+front(host).y+.066
static func depth_entries(opening:Dictionary)->Array[Dictionary]:
	# Frame pieces follow the same quarter-cell order as their supporting wall.
	# One whole lintel at midpoint depth is covered again by the nearer slices.
	var host:Dictionary=opening.host;var half=frame_half_width(opening)
	var a=Geometry.axis_value(opening.a,host.axis);var b=Geometry.axis_value(opening.b,host.axis)
	var result:Array[Dictionary]=[
		{"type":"opening_frame","depth":frame_slice_depth(host,a-half)-.001,"entry":opening,"part":"reveal"},
		{"type":"opening_frame","depth":frame_slice_depth(host,a+half),"entry":opening,"part":"start"},
		{"type":"opening_frame","depth":frame_slice_depth(host,b+half),"entry":opening,"part":"end"}]
	for index in range(floori((a-half)*WallArt.SLICES),ceili((b+half)*WallArt.SLICES)):
		var left=maxf(a-half,float(index)/WallArt.SLICES);var right=minf(b+half,float(index+1)/WallArt.SLICES)
		var piece=opening.duplicate();piece.frame_from=left-a;piece.frame_to=right-a
		result.append({"type":"opening_frame","depth":frame_slice_depth(host,(left+right)*.5),"entry":piece,"part":"middle"})
	return result
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
static func casing_front(host:Dictionary)->Vector2:
	# The unified painter already orders casing after its supporting slice.
	# A second normal nudge misaligns the projected slice edge and gets bitten
	# by the next wall slice at some zoom/pan phases. Keep the same front plane.
	if host.has("visual_front"):return front(host)
	return front(host)+(host.normal.normalized()*.008 if not host.shell else -host.normal.normalized()*.01)
static func casing(view,opening:Dictionary,part:String,alpha=1.0,tint=Color.WHITE):
	var host:Dictionary=opening.host;var axis:Vector2=(host.b-host.a).normalized()
	var near=casing_front(host)
	var far=back(host);var a:Vector2=opening.a;var b:Vector2=opening.b
	var low=float(opening.bottom);var high=float(opening.top)
	var half=frame_half_width(opening)
	var color=Color("597d60")*Color(tint.r,tint.g,tint.b,alpha*tint.a)
	var reveal=Color("dce2c9")*Color(tint.r,tint.g,tint.b,alpha*tint.a)
	# Reveal is inside the aperture but overlaps the frame's one-pixel lower
	# lip. Draw it before all casing slices, never from a later jamb entry.
	if part=="reveal":
		for visible_face in visible_jamb_reveal(view,opening):preload("res://scripts/rendering/cafe_canvas_draw.gd").draw_colored_polygon(view,visible_face,reveal)
		return
	if part in ["start","end"]:
		var endpoint=a if part=="start" else b
		var left=endpoint-axis*half+near;var right=endpoint+axis*half+near
		quad(view,[view.iso(left.x,left.y,low),view.iso(right.x,right.y,low),view.iso(right.x,right.y,high+4),view.iso(left.x,left.y,high+4)],color)
	else:
		var start=float(opening.get("frame_from",-half));var finish=float(opening.get("frame_to",a.distance_to(b)+half))
		var left=a+axis*start+near;var right=a+axis*finish+near
		quad(view,[view.iso(left.x,left.y,high+4),view.iso(right.x,right.y,high+4),view.iso(right.x,right.y,high-1),view.iso(left.x,left.y,high-1)],color)
		if opening.kind=="window":
			var glass_a=a+axis*clampf(start,0,a.distance_to(b));var glass_b=a+axis*clampf(finish,0,a.distance_to(b))
			var af=glass_a+front(host);var bf=glass_b+front(host);var ab=glass_a+far;var bb=glass_b+far
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

static func selection_outline(view,opening:Dictionary):
	# Selection is a presentation overlay; preserve the exact hosted aperture.
	var near=front(opening.host);var a:Vector2=opening.a+near;var b:Vector2=opening.b+near
	var points=[view.iso(a.x,a.y,opening.bottom),view.iso(b.x,b.y,opening.bottom),view.iso(b.x,b.y,opening.top+4),view.iso(a.x,a.y,opening.top+4)]
	for index in 4:
		view.line(points[index],points[(index+1)%4],"fff3d8",4.5)
		view.line(points[index],points[(index+1)%4],"477050",2.0)
