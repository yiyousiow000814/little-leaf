extends RefCounted
## Input hygiene only. The service, never this parser, resolves or counts players.
const MAX_RECIPIENTS=100
const MAX_INPUT_UNITS=8192

static func valid_uid(value:String)->bool:
 if value.length()!=12:return false
 for index in value.length():
  var point=value.unicode_at(index)
  if point<48 or point>57 or (index==0 and point==48):return false
 return true

static func parse(value:String)->Dictionary:
 var result={"uids":[],"invalid":[],"duplicates":0,"too_many":false}
 # Reject oversized paste before tokenization; never silently truncate recipients.
 if value.length()>MAX_INPUT_UNITS:
  result.invalid.append("Input too long");return result
 var separators=RegEx.new();separators.compile("[\\s,;，；、]+")
 var tokens=separators.sub(value.strip_edges()," ",true).split(" ",false)
 var seen={}
 for token in tokens:
  if not valid_uid(token):
   if not result.invalid.has(token):result.invalid.append(token)
  elif seen.has(token):result.duplicates+=1
  else:seen[token]=true;result.uids.append(token)
 result.uids.sort()
 result.too_many=result.uids.size()>MAX_RECIPIENTS
 return result
