extends RefCounted
## Cache preparation, not rasterization. Replay at the original shell position
## through the original helpers, retaining their opacity/AA/transform semantics.
const OpeningArt=preload("res://scripts/illustrated_openings.gd")
var entries={}
var rebuilds=0
var hits=0
class Painter extends RefCounted:
	var source
	var game
	var ui_scale
	var commands=[]
	func _init(view):source=view;game=view.game;ui_scale=view.ui_scale
	func iso(x,z,h=0.0):return source.iso(x,z,h)
	func poly(points,color):commands.append(["poly",points,color])
	func line(a,b,color,width=1.0):commands.append(["line",a,b,color,width])
	func draw_polygon(points,colors,uvs=PackedVector2Array(),texture=null):commands.append(["polygon",points,colors,uvs,texture])
func draw(view,host:Dictionary,attachments:Array,base_color,panel_color):
	var slot=str(host.get("host_id",""))
	# Only the fixed two shell hosts have retained slots. Unknown callers use
	# the original path, keeping storage bounded even during editing.
	if slot not in ["shell:back","shell:west"]:
		OpeningArt.draw_shell(view,host,attachments,base_color,panel_color);return
	# solid_panels -> cuts resolves walls only inside the attachments loop.
	# The supplied host still captures wall-induced shell length/run changes.
	var opening_walls=[] if attachments.is_empty() else view.game.model.built_walls
	var key=[host,attachments,opening_walls,view.origin,view.tile,view.ui_scale,view.zoom,view.game.wall_detail,base_color,panel_color]
	if not entries.has(slot) or entries[slot].key!=key:
		var painter=Painter.new(view)
		OpeningArt.draw_shell(painter,host,attachments,base_color,panel_color)
		entries[slot]={"key":key.duplicate(true),"commands":painter.commands};rebuilds+=1
	else:hits+=1
	for command in entries[slot].commands:
		match command[0]:
			"poly":view.poly(command[1],command[2])
			"line":view.line(command[1],command[2],command[3],command[4])
			"polygon":view.draw_polygon(command[1],command[2],command[3],command[4])
