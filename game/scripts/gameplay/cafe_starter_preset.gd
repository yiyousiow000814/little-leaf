extends RefCounted
## Fresh-game layout data only. Loading an existing save must never apply a
## preset or fill a deliberately empty cell. Lifecycle and economy stay in Model.
const Footprint=preload("res://scripts/gameplay/cafe_footprint.gd")
const Openings=preload("res://scripts/gameplay/cafe_wall_openings.gd")
const Segments=preload("res://scripts/gameplay/cafe_shell_segments.gd")
const FLOOR_STYLE="warm_oak"
const WALL_MATERIAL="original"
# Order preserves the original furniture IDs and next-ID sequence.
const FURNITURE=[
	["stove",8,1,0],["beverage",9,1,0],["sink",10,1,0],
	["counter",8,2,0],["counter",9,2,0],
	["table",3,3,0],["chair",3,4,0],
	["table",6,5,0],["chair",6,6,0],
	["plant",1,1,0],["plant",10,6,0],
	["bookshelf",5,0,0],["lamp",1,7,0],
]
const PUBLIC_ITEM_IDS=[1,2,3,4,6,7]

static func furniture(public_layout:bool=false)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for index in FURNITURE.size():
		var id=index+1
		var spec=FURNITURE[index]
		var item={"id":id,"kind":spec[0],"x":spec[1],"z":spec[2],"rot":spec[3]}
		result.append(item)
	return select_public_furniture(result) if public_layout else result

static func select_public_furniture(items:Array)->Array[Dictionary]:
	# Keep the same retained item records as the historical startup transition.
	var result:Array[Dictionary]=[]
	for item in items:
		if int(item.id) not in PUBLIC_ITEM_IDS:continue
		if int(item.id)==4:item.x=6;item.z=2
		result.append(item)
	return result

static func floors()->Dictionary:
	var result={}
	for z in range(Footprint.DEPTH):
		for x in range(Footprint.WIDTH):
			result["%d,%d"%[x,z]]={"style":FLOOR_STYLE,"paid_cost":0}
	return result

static func structure()->Dictionary:
	# Compatibility representation until the reviewed unified-building migration.
	# This is initialization, never an absent-wall/render fallback.
	var products=Openings.initial_shell_products(WALL_MATERIAL)
	return {"products":products,"segments":Segments.migrate(products,[]).segments,
		"attachments":Openings.initial_attachments(),"floors":floors()}
