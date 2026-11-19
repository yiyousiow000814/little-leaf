extends SceneTree
# Separate pinned-engine PNG decode. This empty headless project loads no game,
# waits for no frames and reads/writes only the runner's private staging.
const LABELS=["full-with-door","half-first","door-mutated-first","half-with-window-first","occluded-first","over-wall-first","door-removed-first","themed-alt-camera-first"]
const SAMPLE="89504e470d0a1a0a0000000d494844520000000200000002080600000072b60d240000001a49444154789c6360646266616563e760e0e4e2e6e1e5e3170000036600896df92a510000000049454e44ae426082"
func _initialize():
 var args=OS.get_cmdline_user_args()
 var ok=false
 if args.size()==1 and args[0]=="--self-test":
  var im=Image.new();ok=im.load_png_from_buffer(SAMPLE.hex_decode())==OK and im.get_size()==Vector2i(2,2)
  if ok:
   im.convert(Image.FORMAT_RGBA8);ok=im.get_data().hex_encode()=="0102030405060708090a0b0c0d0e0f10"
 elif args.size()==2 and args[0]=="--decode":ok=decode(args[1])
 if ok:print("WALL_PNG_DECODER_OK")
 quit(0 if ok else 23)
func decode(folder:String)->bool:
 for i in LABELS.size():
  var stem=folder.path_join("%02d-%s"%[i,LABELS[i]])
  var f=FileAccess.open(stem+".png",FileAccess.READ)
  if f==null or f.get_length()<33 or f.get_length()>16*1024*1024:return false
  # PNG signature, 13-byte IHDR, declared 1360 x 880 checked before allocation.
  if f.get_buffer(24).hex_encode()!="89504e470d0a1a0a0000000d494844520000055000000370":return false
  f.seek(0);var encoded=f.get_buffer(f.get_length());f.close()
  var im=Image.new()
  if im.load_png_from_buffer(encoded)!=OK or im.get_size()!=Vector2i(1360,880):return false
  im.convert(Image.FORMAT_RGBA8);var raw=im.get_data()
  if raw.size()!=1360*880*4:return false
  var out=FileAccess.open(stem+".rgba",FileAccess.WRITE)
  if out==null:return false
  out.store_buffer(raw);out.close()
 return true
