extends RefCounted
## Volatile diagnostics only. Never reads or writes a save or preferences file.
const LIMIT=240
const EVENTS=["boot_requested","read_result","read_accepted","read_failure","save_requested","save_queued","save_skipped","save_validated","save_submitted","save_confirmed","save_accepted","save_failure","retry_requested"]
const SOURCES=["authority","legacy-v13","fresh","native-primary","native-import","review"]
const CODES=["VALIDATION_FAILED","STAGING_FAILED","INVALID_ACK","INVALID_REVISION_ACK","INVALID_CREDIT_ACK","CREDIT_SYNC_REQUIRED","WRITES_SUPPRESSED","RECOVERY_BLOCKED","NATIVE_SAVE_FAILED","BRIDGE_MISSING","NOT_READY","REVISION_CONFLICT","CORRUPT_AUTHORITY","STORAGE_BLOCKED","STORAGE_ABORT","STORAGE_UNAVAILABLE","INVALID_SAVE","SAVE_BUSY","REVISION_LIMIT","QuotaExceededError","SecurityError","AbortError","UnknownError"]
static var entries:Array[String]=[]
static var dropped=0
static var sequence=0

static func record(event:String,fields:Dictionary={}):
 if event not in EVENTS:return
 var safe={}
 if fields.get("layer","") in ["vault","controller","native"]:safe.layer=fields.layer
 if fields.get("source","") in SOURCES:safe.source=fields.source
 var profile=fields.get("profileId","")
 if profile is String and profile!="" and profile.length()<=128:safe.profileId=profile
 var revision=fields.get("revision",-1)
 if revision is int and revision>=0:safe.revision=revision
 var code=fields.get("code","")
 if code is String and code!="":safe.code=code if code in CODES else "STORAGE_ERROR"
 if OS.has_feature("web"):
  # The complete bridge call is guarded in JS. Observer failures never escape
  # into the controller, suppress its callbacks, or change save return values.
  JavaScriptBridge.eval("(()=>{try{const log=globalThis.LittleLeafSaveLog;if(log){log.setVersion(%s);log.record(%s,%s)}}catch(_){}})()"%[JSON.stringify(_version()),JSON.stringify(event),JSON.stringify(safe)])
  return
 sequence+=1
 var line=Time.get_datetime_string_from_system(true)+"Z #"+str(sequence)+" "+event
 for key in ["layer","source","profileId","revision","code"]:
  if safe.has(key):line+=" "+("profile" if key=="profileId" else key)+"="+(_fingerprint(safe[key]) if key=="profileId" else str(safe[key]))
 entries.append(line)
 if entries.size()>LIMIT:entries.pop_front();dropped+=1

static func _version()->String:
 return str(ProjectSettings.get_setting("application/config/version","unknown"))

static func _fingerprint(value:String)->String:
 var hash_value=2166136261
 for byte in value.to_utf8_buffer():hash_value=((hash_value^byte)*16777619)&0xffffffff
 return "%08x"%hash_value

static func text()->String:
 if OS.has_feature("web"):
  var result=JavaScriptBridge.eval("(()=>{try{return globalThis.LittleLeafSaveLog.text()}catch(_){return 'Save log unavailable in this package'}})()")
  return str(result)
 return "Little Leaf save log | app "+_version()+"\nSession only. Copy before refreshing or closing.\nNative accepted means the save codec returned success. Browser durability is only observed in a Web build.\nEvents retained=%d/%d | older events dropped=%d\n"%[entries.size(),LIMIT,dropped]+"\n".join(entries)

static func copy()->String:
 if OS.has_feature("web"):
  return str(JavaScriptBridge.eval("(()=>{try{return globalThis.LittleLeafSaveLog.copy()}catch(_){return 'unavailable'}})()"))
 if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):return "unavailable"
 var value=text()
 DisplayServer.clipboard_set(value)
 return "copied" if DisplayServer.clipboard_get()==value else "unavailable"

static func copy_status()->String:
 if not OS.has_feature("web"):return ""
 return str(JavaScriptBridge.eval("(()=>{try{return globalThis.LittleLeafSaveLog.copyStatus}catch(_){return 'unavailable'}})()"))
