extends SceneTree
const Furniture=preload("res://scripts/furniture_static_atlas.gd")
func _initialize():
 var output=OS.get_environment("LL_ATLAS_OUTPUT")
 var old=Image.new();var fresh=Image.new()
 assert(old.load(output.path_join("furniture-atlas.png"))==OK)
 assert(fresh.load(output.path_join("furniture-regenerated.png"))==OK)
 old.convert(Image.FORMAT_RGBA8);fresh.convert(Image.FORMAT_RGBA8)
 assert(old.get_size()==fresh.get_size(),"Chair-only art must retain atlas dimensions")
 var atlas=Furniture.new();var regions=[]
 for r in range(4):regions.append(atlas.regions[atlas.key("chair_seat",r)])
 var before=old.get_data();var after=fresh.get_data();var changed=0;var outside=0
 for y in old.get_height():
  for x in old.get_width():
   var index=(y*old.get_width()+x)*4
   if before[index]==after[index] and before[index+1]==after[index+1] and before[index+2]==after[index+2] and before[index+3]==after[index+3]:continue
   changed+=1
   var allowed=false
   for rect in regions:
    if rect.has_point(Vector2(x,y)):allowed=true;break
   if not allowed:outside+=1
 var result={"changed_pixels":changed,"outside_chair_seat_pixels":outside,"regions":regions.map(func(rect):return {"position":[rect.position.x,rect.position.y],"size":[rect.size.x,rect.size.y]}),"dimensions":[old.get_width(),old.get_height()],"passed":changed>0 and outside==0,"player_data_used":false}
 FileAccess.open(output.path_join("chair-delta.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 quit(0 if result.passed else 1)
