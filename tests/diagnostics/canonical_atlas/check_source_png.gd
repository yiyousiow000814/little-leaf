extends SceneTree
# Decode original source PNGs directly; emitted import PNG checks remain separate.
func _initialize():
 var output=OS.get_environment("LL_ATLAS_OUTPUT")
 var receipt=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("atlas-parity.json")))
 var names=["furniture","moving","heads"]
 var sizes=[Vector2i(1280,3244),Vector2i(1024,1908),Vector2i(1600,1728)]
 var rows=[];var failures=[]
 for i in range(3):
  var path="res://assets/cache/"+names[i]+"-atlas.png"
  var img=Image.load_from_file(path)
  if img==null:failures.append(path+" missing");continue
  img.convert(Image.FORMAT_RGBA8)
  var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(img.get_data())
  var digest=h.finish().hex_encode()
  var request=receipt.runtime_requests[i]
  var passed=img.get_size()==sizes[i] and digest==receipt.baseline_sha256[i] and digest==receipt.candidate_sha256[i] and digest==request.rgba_sha256 and request.prebaked and request.state=="ready"
  rows.append({"name":names[i],"source_rgba":digest,"size":[img.get_width(),img.get_height()],"passed":passed})
  if not passed:failures.append(names[i]+" original source PNG mismatch")
 FileAccess.open(output.path_join("source-png-check.json"),FileAccess.WRITE).store_string(JSON.stringify({"source_commit":receipt.source_commit,"rows":rows,"failures":failures},"  "))
 quit(0 if failures.is_empty() and rows.size()==3 else 1)
