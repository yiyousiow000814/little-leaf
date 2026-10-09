extends SceneTree
## Source-bound exact raw-pixel and every-mipmap comparison; no frame-rate claim.
const Hud=preload("res://scripts/cafe_hud.gd")
const NAMES=["rail","wallet","mobile_purse","sign","decorate","decorate_done","staff","settings","cream_face","green_face","shop_frame"]
class Fixture extends RefCounted:
 var game=null
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func digest(bytes):
 var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func _initialize():run.call_deferred()
func run():
 var fixture=Fixture.new();var hud=Hud.new(fixture);var records=[]
 Hud.textures.clear()
 for name in NAMES:
  var path="res://assets/ui/fidelity_hud/"+name+".png"
  var original=Image.new();check(original.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK,name+" raw PNG decoded")
  original.generate_mipmaps();original.convert(Image.FORMAT_RGBA8)
  var texture=hud._texture(name)
  check(texture is CompressedTexture2D,name+" uses imported resource")
  check(hud._texture(name)==texture,name+" instance cache preserved")
  var actual=texture.get_image()
  check(actual!=null,name+" image available")
  if actual==null:continue
  if actual.is_compressed():check(actual.decompress()==OK,name+" lossless image decompresses")
  actual.convert(Image.FORMAT_RGBA8)
  check(actual.get_size()==original.get_size(),name+" dimensions exact")
  check(actual.has_mipmaps() and actual.get_mipmap_count()==original.get_mipmap_count(),name+" full mip chain retained")
  var expected=original.get_data();var observed=actual.get_data();var base_bytes=original.get_width()*original.get_height()*4
  check(observed.slice(0,base_bytes)==expected.slice(0,base_bytes),name+" level zero RGBA exact")
  check(observed==expected,name+" every mipmap RGBA exact")
  records.append({"name":name,"size":[actual.get_width(),actual.get_height()],"mipmap_count":actual.get_mipmap_count(),"rgba_bytes":observed.size(),"original_sha256":digest(expected),"imported_sha256":digest(observed),"exact":observed==expected})
 var coin=hud._texture("coin");check(coin is ImageTexture,"coin keeps runtime padded ImageTexture path")
 var coin_image=coin.get_image();check(coin_image!=null and coin_image.get_size()==Vector2i(72,72),"padded coin dimensions remain72x72")
 check(coin_image!=null and coin_image.has_mipmaps(),"coin mipmaps retained")
 var coin_source=Image.new();coin_source.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ui/fidelity_hud/coin.png"))
 var padded=Image.create(72,72,false,Image.FORMAT_RGBA8);padded.fill(Color.TRANSPARENT)
 padded.blit_rect(coin_source,Rect2i(Vector2i.ZERO,coin_source.get_size()),Vector2i(4,4));padded.generate_mipmaps()
 check(coin_image!=null and coin_image.get_data()==padded.get_data(),"padded coin and every mipmap remain exact")
 print("HUD_IMPORTED_TEXTURE_PARITY ",JSON.stringify({"checks":checks,"failures":failures,"images":records,"scope":"Exact native source PNG and all-mipmap RGBA; no visual/frame-time acceptance"}))
 quit(0 if failures.is_empty() else 1)
