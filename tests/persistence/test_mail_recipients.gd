extends SceneTree
const Recipients=preload("res://scripts/ui/cafe_mail_recipients.gd")
var checks=0
var failures=[]
func check(ok:bool,description:String):
 checks+=1
 if not ok:failures.append(description);printerr("FAIL ",description)
func _initialize():
 check(Recipients.valid_uid("123456789012"),"12 digit UID")
 for invalid in ["023456789012","12345678901","1234567890123","１２３４５６７８９０１２","12345678901a","1.23456789012e11","authUid12345"]:
  check(not Recipients.valid_uid(invalid),"reject "+invalid)
 var parsed=Recipients.parse("234567890123,123456789012\n234567890123；345678901234 123456789012")
 check(parsed.uids==["123456789012","234567890123","345678901234"] and parsed.duplicates==2,"stable sorted dedupe")
 check(Recipients.parse("123456789012\t234567890123\r\n345678901234").uids.size()==3,"spreadsheet paste")
 check(Recipients.parse("123456789012,bad").invalid==["bad"],"invalid entry retained rather than ignored")
 check(Recipients.parse("").uids.is_empty(),"empty input")
 check(Recipients.parse(" ").invalid.is_empty(),"blank input")
 check(not Recipients.parse("1".repeat(8193)).invalid.is_empty(),"oversized paste rejected, not truncated")
 var ids=[]
 for i in 100:ids.append(str(123456789000+i))
 check(not Recipients.parse(",".join(ids)).too_many,"100 UIDs allowed by draft input cap")
 ids.append("234567890123")
 check(Recipients.parse(",".join(ids)).too_many,"101 UIDs rejected")
 print("MAIL_RECIPIENTS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
