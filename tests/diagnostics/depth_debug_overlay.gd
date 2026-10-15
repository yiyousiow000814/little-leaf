extends Node2D
## Read-only CanvasLayer child, loaded by the diagnostic script only.
## Existing probe values and authored contours; never a depth comparator.
var observations: Array = []
var completed_frame: int = -1
var dropped: int = 0
var font = ThemeDB.fallback_font

func observe(events: Array, frame_id: int, missed: int) -> void:
	observations = events.duplicate(true)
	completed_frame = frame_id
	dropped = missed
	queue_redraw()

func _draw() -> void:
	var groups = {}
	for row in observations:
		if not row.has("index_at_completed_frame"):continue
		var context = row.context
		var key = str(context.id) + "/" + str(context.part)
		if not groups.has(key):groups[key] = {"context":context,"indices":[],"cursors":[],"visible":[],"generation":row.generation}
		groups[key].indices.append(row.index_at_completed_frame)
		groups[key].cursors.append(row.cursor)
		groups[key].visible.append(row.visible_at_completed_frame)
	draw_rect(Rect2(850,20,490,450),Color(.04,.06,.08,.92))
	var y = 44.0
	draw_string(font,Vector2(864,y),"DEV DEPTH | completed %d | dropped %d"%[completed_frame,dropped],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
	y += 25
	draw_string(font,Vector2(864,y),"Order is observed, not computed by this overlay.",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	y += 25
	for key in groups:
		var group = groups[key];var c = group.context
		var anchor = Vector2(c.anchor[0],c.anchor[1])
		draw_line(anchor-Vector2(7,0),anchor+Vector2(7,0),Color.CYAN,2)
		draw_line(anchor-Vector2(0,7),anchor+Vector2(0,7),Color.CYAN,2)
		draw_string(font,anchor+Vector2(10,18),key,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.CYAN)
		for contour in c.get("occlusion_contours",[]):
			var points = PackedVector2Array()
			for p in contour:points.append(Vector2(p[0],p[1]))
			if points.size()>2:
				points.append(points[0]);draw_polyline(points,Color(1,.55,.15,.9),1.5)
		draw_string(font,Vector2(864,y),key,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.CYAN);y+=19
		draw_string(font,Vector2(864,y),"world (%.3f, %.3f) | anchor (%.1f, %.1f)"%[c.world[0],c.world[1],c.anchor[0],c.anchor[1]],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE);y+=19
		draw_string(font,Vector2(864,y),"depth %.6f | generation %s"%[c.depth,str(group.generation)],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE);y+=19
		draw_string(font,Vector2(864,y),"cursor %s | native %s"%[str(group.cursors),str(group.indices)],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE);y+=19
		draw_string(font,Vector2(864,y),"visible %s"%str(group.visible),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE);y+=26
	draw_string(font,Vector2(864,440),"Orange: authored trunk/crown, not collision or footprint.",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
