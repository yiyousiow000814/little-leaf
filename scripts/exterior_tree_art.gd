extends RefCounted
## Original vector tree illustration. Coordinates are authored around the existing
## ground contact; placement, land-clearance rules and atlas bounds stay unchanged.
## Curves are sampled once when this shared artist is constructed. Normal gameplay
## still draws the existing 4× cached atlas, not these individual polygons.
var layers: Array = []

func _init():
	# root contact
	layers.append(_shape("9fae7b",Vector2(-13,1),[
		[-7,-2,4,-2,14,1],
		[10,5,-10,5,-13,1],
	]))
	# trunk silhouette
	layers.append(_shape("8d8059",Vector2(-8,2),[
		[-4,-8,-5,-22,-6,-36],
		[-7,-46,-10,-54,-16,-61],
		[-21,-66,-23,-71,-23,-76],
		[-18,-73,-13,-67,-9,-63],
		[-7,-61,-5,-57,-4,-55],
		[-3,-67,-1,-75,3,-82],
		[6,-77,5,-65,4,-57],
		[9,-62,14,-70,22,-74],
		[22,-69,14,-58,8,-51],
		[2,-41,2,-32,3,-21],
		[4,-10,4,-3,9,2],
		[3,4,-3,4,-8,2],
	]))
	# trunk warm face
	layers.append(_shape("ae9a6c",Vector2(-5,1),[
		[-2,-12,-4,-27,-4,-38],
		[-4,-47,-7,-57,-13,-63],
		[-14,-66,-17,-69,-17,-71],
		[-10,-65,-6,-59,-4,-53],
		[-1,-49,0,-49,1,-54],
		[4,-63,9,-66,14,-69],
		[10,-63,6,-57,3,-51],
		[-1,-41,0,-30,1,-19],
		[2,-10,1,-4,5,2],
		[1,3,-3,3,-5,1],
	]))
	# trunk soft light
	layers.append(_shape("c2b082",Vector2(-4,-32),[
		[-4,-21,-2,-12,-4,-3],
		[-2,-2,-1,-2,0,-2],
		[-2,-14,-1,-25,-2,-34],
		[-2,-41,-3,-46,-5,-48],
		[-4,-42,-4,-36,-4,-32],
	]))
	# canopy silhouette
	layers.append(_shape("829b63",Vector2(-43,-81),[
		[-50,-91,-47,-104,-36,-109],
		[-38,-122,-27,-129,-15,-127],
		[-9,-137,7,-137,15,-130],
		[25,-132,37,-124,36,-113],
		[49,-109,51,-95,45,-86],
		[54,-75,46,-60,34,-59],
		[28,-49,16,-47,6,-54],
		[-3,-45,-17,-48,-23,-54],
		[-36,-51,-50,-62,-47,-74],
		[-47,-77,-45,-79,-43,-81],
	]))
	# right canopy
	layers.append(_shape("87a363",Vector2(15,-127),[
		[25,-129,35,-121,34,-110],
		[44,-108,47,-100,44,-90],
		[41,-85,38,-82,34,-82],
		[43,-79,49,-71,41,-63],
		[36,-58,30,-60,29,-57],
		[23,-51,13,-51,7,-58],
		[0,-66,4,-79,9,-86],
		[16,-100,22,-107,15,-127],
	]))
	# left lower canopy
	layers.append(_shape("95af6e",Vector2(-35,-106),[
		[-46,-102,-47,-92,-40,-84],
		[-42,-82,-45,-78,-45,-73],
		[-46,-62,-36,-55,-26,-57],
		[-20,-53,-13,-51,-7,-54],
		[3,-58,5,-68,-1,-76],
		[-5,-83,-13,-84,-18,-83],
		[-25,-89,-27,-100,-35,-106],
	]))
	# middle canopy
	layers.append(_shape("9cb577",Vector2(-32,-110),[
		[-33,-121,-23,-127,-12,-124],
		[-6,-133,7,-133,14,-126],
		[20,-127,29,-123,30,-116],
		[34,-110,31,-102,25,-98],
		[30,-93,29,-86,25,-81],
		[20,-76,15,-77,11,-78],
		[8,-70,-1,-67,-9,-71],
		[-16,-69,-25,-74,-26,-82],
		[-34,-84,-39,-92,-35,-99],
		[-36,-104,-34,-108,-32,-110],
	]))
	# upper canopy
	layers.append(_shape("aec585",Vector2(-30,-112),[
		[-31,-119,-22,-124,-13,-121],
		[-8,-131,4,-132,12,-124],
		[20,-126,28,-120,28,-113],
		[31,-107,26,-99,19,-98],
		[16,-91,9,-88,2,-91],
		[-5,-86,-14,-88,-18,-95],
		[-26,-94,-33,-103,-30,-112],
	]))
	# top light plane
	layers.append(_shape("bbce93",Vector2(-25,-115),[
		[-22,-120,-16,-120,-11,-118],
		[-7,-125,1,-128,7,-124],
		[3,-124,-2,-121,-4,-117],
		[-5,-114,-9,-112,-13,-114],
		[-17,-116,-21,-116,-25,-115],
	]))
	# left light plane
	layers.append(_shape("a3bb7b",Vector2(-39,-76),[
		[-37,-81,-31,-83,-25,-80],
		[-20,-82,-15,-79,-13,-76],
		[-18,-77,-21,-75,-24,-73],
		[-28,-76,-34,-77,-39,-73],
		[-39,-74,-39,-75,-39,-76],
	]))
	# right sage plane
	layers.append(_shape("95ad71",Vector2(24,-97),[
		[30,-101,37,-99,39,-94],
		[39,-90,36,-87,32,-88],
		[34,-91,29,-95,24,-93],
		[24,-94,24,-96,24,-97],
	]))
	# Quiet interior foliage planes. They sit within the accepted crown;
	# outer contour, trunk/root contact and the atlas envelope stay unchanged.
	layers.append(_shape("91aa6d",Vector2(-17,-76),[
		[-12,-73,-6,-73,-1,-76],
		[4,-77,9,-76,12,-73],
		[9,-68,3,-66,-3,-68],
		[-9,-65,-15,-68,-17,-76],
	]))
	layers.append(_shape("a4bb7c",Vector2(-38,-70),[
		[-35,-74,-29,-75,-25,-72],
		[-21,-73,-17,-71,-16,-68],
		[-22,-69,-24,-65,-28,-65],
		[-33,-64,-37,-66,-38,-70],
	]))
	layers.append(_shape("92aa6e",Vector2(18,-60),[
		[23,-64,28,-64,32,-61],
		[28,-56,22,-54,17,-56],
		[12,-55,9,-57,9,-60],
		[12,-58,15,-58,18,-60],
	]))
	# leaf pair left a
	layers.append(_shape("b5c989",Vector2(-22,-100),[
		[-26,-101,-28,-104,-27,-107],
		[-22,-107,-20,-104,-22,-100],
	]))
	# leaf pair left b
	layers.append(_shape("8faa6b",Vector2(-22,-100),[
		[-21,-105,-16,-106,-14,-104],
		[-15,-100,-18,-99,-22,-100],
	]))
	# leaf pair lower a
	layers.append(_shape("abc17f",Vector2(-21,-65),[
		[-25,-65,-28,-68,-27,-71],
		[-23,-72,-20,-69,-21,-65],
	]))
	# leaf pair lower b
	layers.append(_shape("829e61",Vector2(-21,-65),[
		[-19,-69,-15,-69,-13,-67],
		[-15,-64,-18,-64,-21,-65],
	]))
	# leaf pair right a
	layers.append(_shape("a7bd7c",Vector2(27,-70),[
		[22,-70,20,-73,21,-76],
		[25,-76,28,-74,27,-70],
	]))
	# leaf pair right b
	layers.append(_shape("77935a",Vector2(27,-70),[
		[28,-74,32,-75,35,-73],
		[33,-70,30,-68,27,-70],
	]))
	# ground tuft left
	layers.append(_shape("9caf7b",Vector2(-11,3),[
		[-12,0,-15,-2,-17,-2],
		[-16,-3,-12,-2,-10,0],
		[-10,-4,-8,-6,-7,-6],
		[-8,-1,-7,2,-6,3],
	]))
	# ground tuft right
	layers.append(_shape("adbd88",Vector2(5,3),[
		[7,0,7,-3,9,-4],
		[10,-1,9,1,9,2],
		[12,-1,15,-1,16,0],
		[13,1,13,2,12,3],
	]))

func _shape(color: String, start: Vector2, curves: Array) -> Array:
	var points := PackedVector2Array([start])
	var previous := start
	for curve in curves:
		var first := Vector2(curve[0],curve[1])
		var second := Vector2(curve[2],curve[3])
		var finish := Vector2(curve[4],curve[5])
		var length := previous.distance_to(first)+first.distance_to(second)+second.distance_to(finish)
		var steps := maxi(4,ceili(length/3.0))
		for step in range(1,steps+1):
			var t := float(step)/steps
			points.append(previous.bezier_interpolate(first,second,finish,t))
		previous = finish
	if points[-1].is_equal_approx(start): points.remove_at(points.size()-1)
	return [color,points]

func draw_tree(artist: Node2D, ground: Vector2, scale: float, horizontal_scale: float = 1.0) -> void:
	var transform := Transform2D(Vector2(scale*horizontal_scale,0),Vector2(0,scale),ground)
	for layer in layers:
		artist.poly(Array(transform * layer[1]),layer[0])
