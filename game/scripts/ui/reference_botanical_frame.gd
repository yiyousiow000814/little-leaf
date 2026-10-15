extends Control
## Four editable painted quadrants form one continuous botanical composition.
## Actual controls remain native siblings; opaque list/transport surfaces cover
## ornament behind them. No generated text, controls or screenshot backgrounds.
const BORDER=preload("res://assets/ui/music_botanical/continuous_gold_botanical.png")
const COMPACT_STEM=preload("res://assets/ui/music_botanical/gold_flowering_stem.png")
const CORNER_FAN=preload("res://assets/ui/music_botanical/corner-leaf-fan-r25.png")
const CORNER_CURL=preload("res://assets/ui/music_botanical/sculpted-curl-r24.png")
const LOCAL_BLEND=preload("res://assets/ui/music_botanical/local_botanical_blend.gdshader")
const LOCAL_FADES=[Vector4(12,7,4,8),Vector4(6,7,4,10),Vector4(10,4,14,4),Vector4.ZERO,Vector4.ZERO]
const QUIET_MASK=preload("res://assets/ui/music_botanical/reference_botanical_mask.gdshader")
var pieces:Array[TextureRect]=[]
# Corner islands are anchored to the functional folio and tray, not to the
# stretched board perimeter. Untouched source paint remains independently editable.
var local_pieces:Array[TextureRect]=[]
var local_regions:Array[Rect2]=[Rect2(1220,0,316,225),Rect2(1260,630,276,394),Rect2(140,850,420,174),Rect2(0,0,1254,1254),Rect2(0,0,1254,1254)]
var local_targets:Array[Rect2]=[]
var finials:Array[TextureRect]=[]
var _fan_ink:Array=[]
var _curl_ink:Array=[]
var emboss:Array[TextureRect]=[]
var _local_enabled:=false
var _library:=Rect2()
var _tray:=Rect2()
var _ink:Array=[]
var _scale:=1.0
var _origin:=Vector2.ZERO
var _large:=false
var _compact_rect:=Rect2()
var occluders:Array[Rect2]=[]
var quiet_rects:Array[Rect2]=[]
var _last_size:=Vector2(-1,-1)
func _init():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 _ink=JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/music_botanical/continuous_gold_ink.json"))
 _fan_ink=JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/music_botanical/corner-leaf-fan-r25-ink.json"))
 _curl_ink=JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/music_botanical/sculpted-curl-r24-ink.json"))
 for index in 5:
  var part=TextureRect.new();part.name=["UpperLeftBotanical","UpperRightBotanical","LowerLeftBotanical","LowerRightBotanical","CompactHeaderBotanical"][index]
  var atlas=AtlasTexture.new();atlas.atlas=BORDER
  atlas.region=Rect2((index%2)*768,(index/2)*512,768,512) if index<4 else Rect2(24,178,2120,380)
  if index==4:atlas.atlas=COMPACT_STEM
  part.texture=atlas;part.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;part.stretch_mode=TextureRect.STRETCH_SCALE
  part.mouse_filter=Control.MOUSE_FILTER_IGNORE;part.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
  var mask=ShaderMaterial.new();mask.shader=QUIET_MASK;part.material=mask
  add_child(part);pieces.append(part)
 for index in local_regions.size():
  var part=TextureRect.new();part.name=["FolioUpperRightBranch","FolioLowerRightFlowers","FolioLowerLeftCurl","TrayOuterLeftFlowers","TrayOuterRightFlowers"][index]
  var atlas=AtlasTexture.new();atlas.atlas=CORNER_FAN if index>=3 else BORDER;atlas.region=local_regions[index];part.texture=atlas
  part.flip_h=index==4
  part.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;part.stretch_mode=TextureRect.STRETCH_SCALE
  part.mouse_filter=Control.MOUSE_FILTER_IGNORE;part.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
  var blend=ShaderMaterial.new();blend.shader=LOCAL_BLEND;part.material=blend
  part.z_index=30;add_child(part);local_pieces.append(part);part.hide()
 for index in 2:
  var leaf=TextureRect.new();leaf.name="TrayEmboss%d"%index;leaf.texture=preload("res://assets/ui/music_pearlwood/selected_song_leaves_r25.svg")
  leaf.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;leaf.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
  leaf.mouse_filter=Control.MOUSE_FILTER_IGNORE;leaf.modulate=Color(.94,1.0,.84,.40);leaf.z_index=29
  add_child(leaf);emboss.append(leaf);leaf.hide()
 for index in 2:
  var curl=TextureRect.new();curl.name="SculptedUpperCorner%d"%index;curl.texture=CORNER_CURL
  curl.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;curl.stretch_mode=TextureRect.STRETCH_SCALE;curl.flip_h=index==1
  curl.mouse_filter=Control.MOUSE_FILTER_IGNORE;curl.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;curl.z_index=31
  add_child(curl);finials.append(curl);curl.hide()
 resized.connect(_arrange);hide()
func set_premium(value:bool):visible=value
func set_surfaces(folio:Rect2,tray:Rect2,enabled:bool):
 if _library==folio and _tray==tray and _local_enabled==enabled:return
 _library=folio;_tray=tray;_local_enabled=enabled;_arrange_local()
func _arrange_local():
 if not _large:
  _arrange_phone_ornament()
  return
 var show_local=_local_enabled and _large and size.x>=1000 and size.y>=680
 for part in local_pieces:part.visible=show_local
 for part in emboss:part.visible=show_local
 for part in finials:part.visible=show_local
 local_targets.clear()
 if not show_local:return
 var s=minf(size.x/1427.152,size.y/932.274)
 local_targets.assign([
  Rect2(Vector2(_library.end.x-139*s,_library.position.y-4*s),Vector2(164,100)*s),
  Rect2(Vector2(_library.end.x-93*s,_library.end.y-109*s),Vector2(118,150)*s),
  Rect2(Vector2(_library.position.x-12*s,_library.end.y-57*s),Vector2(176,73)*s),
  Rect2(Vector2(3*s,size.y-73*s),Vector2(70,70)*s),
  Rect2(Vector2(size.x-73*s,size.y-73*s),Vector2(70,70)*s)])
 for index in local_pieces.size():
  var area=local_targets[index];area.position=area.position.clamp(Vector2.ONE*3*s,size-area.size-Vector2.ONE*3*s)
  local_targets[index]=area;local_pieces[index].position=area.position;local_pieces[index].size=area.size
  local_pieces[index].material.set_shader_parameter("surface_size",area.size)
  local_pieces[index].material.set_shader_parameter("edge_fade",LOCAL_FADES[index]*s)
 for index in 2:
  emboss[index].position=Vector2(_tray.position.x+25*s if index==0 else _tray.end.x-52*s,_tray.position.y+49*s)
  emboss[index].size=Vector2(39,56)*s
  finials[index].position=Vector2(11*s if index==0 else size.x-141*s,1*s)
  finials[index].size=Vector2(130,32)*s
func _arrange_phone_ornament():
 # Reuse retained pieces in independent control-free phone edge slots.
 for part in local_pieces:part.hide()
 for part in emboss:part.hide()
 for part in finials:part.show()
 var sprig_width=clampf(size.x-310,32,60)
 local_targets.assign([Rect2(Vector2((size.x-sprig_width)*.5,3),Vector2(sprig_width,sprig_width*.7)),Rect2(),Rect2(),Rect2(Vector2(1,size.y-21),Vector2(20,20)),Rect2(Vector2(size.x-21,size.y-21),Vector2(20,20))])
 for index in [0,3,4]:
  var part=local_pieces[index];var area=local_targets[index]
  part.position=area.position;part.size=area.size;part.show()
  part.material.set_shader_parameter("surface_size",area.size);part.material.set_shader_parameter("edge_fade",Vector4.ZERO)
 for index in 2:
  finials[index].position=Vector2(3 if index==0 else size.x-48,1)
  finials[index].size=Vector2(45,15)
func set_quiet_rects(rects:Array[Rect2]):
 if quiet_rects==rects:return
 quiet_rects.assign(rects);_update_masks()
func _update_masks():
 for part in pieces:
  var regions=PackedVector4Array()
  for area in quiet_rects:
   var relative=area.position-part.position
   regions.append(Vector4(relative.x,relative.y,relative.x+area.size.x,relative.y+area.size.y))
  while regions.size()<8:regions.append(Vector4.ZERO)
  part.material.set_shader_parameter("quiet_rects",regions)
  part.material.set_shader_parameter("quiet_count",mini(quiet_rects.size(),8))
func _arrange():
 if size==_last_size:return
 _last_size=size
 for part in pieces:part.hide()

 _large=size.y>=550 and size.x>=850
 if _large:
  _scale=minf((size.x-24)/1536.0,(size.y-16)/1024.0)
  _origin=(size-Vector2(1536,1024)*_scale)*.5
  for index in 4:
   pieces[index].position=_origin+Vector2((index%2)*768,(index/2)*512)*_scale
   pieces[index].size=Vector2(768,512)*_scale;pieces[index].show()
 else:
  var width=minf(maxf(size.x-270,48),100)
  _compact_rect=Rect2(Vector2((size.x-width)*.5,1),Vector2(width,width*380.0/2120.0))
  pieces[4].position=_compact_rect.position;pieces[4].size=_compact_rect.size;pieces[4].hide()
 _update_masks();_arrange_local()
func _without_cover(rect:Rect2,cover:Rect2)->Array[Rect2]:
 var overlap=rect.intersection(cover)
 if not overlap.has_area():return [rect]
 var result:Array[Rect2]=[]
 for candidate in [Rect2(rect.position,Vector2(rect.size.x,overlap.position.y-rect.position.y)),Rect2(Vector2(rect.position.x,overlap.end.y),Vector2(rect.size.x,rect.end.y-overlap.end.y)),Rect2(Vector2(rect.position.x,overlap.position.y),Vector2(overlap.position.x-rect.position.x,overlap.size.y)),Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(rect.end.x-overlap.end.x,overlap.size.y))]:
  if candidate.has_area():result.append(candidate)
 return result
func ink_rects()->Array[Rect2]:
 var result:Array[Rect2]=[]
 if not is_visible_in_tree():return result
 if not _large and pieces[4].is_visible_in_tree():result.append(get_global_transform()*_compact_rect)
 for cell in (_ink if _large else []):
  var local=Rect2(Vector2(cell[0],cell[1])*_scale+_origin,Vector2(cell[2],cell[3])*_scale)
  var surviving:Array[Rect2]=[local]
  for cover in occluders+quiet_rects:
   var next:Array[Rect2]=[]
   for item in surviving:next.append_array(_without_cover(item,cover))
   surviving=next
  for item in surviving:result.append(get_global_transform()*item)
 for index in local_targets.size():
  if not local_pieces[index].is_visible_in_tree():continue
  var source=local_regions[index];var target=local_targets[index];var ratio=target.size/source.size
  for cell in (_fan_ink if index>=3 else _ink):
   var clipped=Rect2(cell[0],cell[1],cell[2],cell[3]).intersection(source)
   if clipped.has_area():
    var offset=clipped.position-source.position
    if local_pieces[index].flip_h:offset.x=source.size.x-offset.x-clipped.size.x
    result.append(get_global_transform()*Rect2(target.position+offset*ratio,clipped.size*ratio))
 for part in finials:
  if not part.is_visible_in_tree():continue
  var ratio=part.size/Vector2(2172,724)
  for cell in _curl_ink:
   var position=Vector2(cell[0],cell[1])
   if part.flip_h:position.x=2172-position.x-cell[2]
   result.append(get_global_transform()*Rect2(part.position+position*ratio,Vector2(cell[2],cell[3])*ratio))
 for part in emboss:
  if part.is_visible_in_tree():result.append(part.get_global_rect())
 return result
