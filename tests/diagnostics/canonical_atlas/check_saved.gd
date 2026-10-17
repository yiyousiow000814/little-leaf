extends SceneTree
func digest(bytes:PackedByteArray)->String:
 var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func _initialize():
 var output=OS.get_environment("LL_ATLAS_OUTPUT")
 var receipt=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("atlas-parity.json")));var rows=[];var failures=[]
 for i in range(3):
  var name=["furniture","moving","heads"][i]
  var a=Image.load_from_file(output.path_join(name+"-regenerated.png"));var b=Image.load_from_file(output.path_join(name+"-atlas.png"))
  if a==null or b==null:failures.append(name+" PNG missing");continue
  a.convert(Image.FORMAT_RGBA8);b.convert(Image.FORMAT_RGBA8)
  var ah=digest(a.get_data());var bh=digest(b.get_data())
  var passed=a.get_size()==b.get_size() and ah==receipt.baseline_sha256[i] and bh==receipt.candidate_sha256[i] and ah==bh
  if not passed:failures.append(name+" saved RGBA mismatch")
  rows.append({"name":name,"size":[a.get_width(),a.get_height()],"regenerated_rgba":ah,"imported_rgba":bh,"passed":passed})
 FileAccess.open(output.path_join("saved-png-check.json"),FileAccess.WRITE).store_string(JSON.stringify({"source_commit":receipt.source_commit,"rows":rows,"failures":failures},"  "))
 quit(0 if failures.is_empty() and rows.size()==3 else 1)
