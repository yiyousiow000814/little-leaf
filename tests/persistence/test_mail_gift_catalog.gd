extends SceneTree
const Catalog=preload("res://scripts/ui/cafe_mail_gift_catalog.gd")
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():
 var catalog=Catalog.new();var rows:Array=[]
 for i in 125:rows.append({"id":"item_%03d"%i,"name":"Test item %03d"%i,"category":"Kitchen" if i%2==0 else "Decor"})
 catalog.configure(rows)
 check(catalog.entries.size()==125,"catalogue retains display metadata, not controls")
 check(catalog.categories()==["All","Kitchen","Decor"],"categories come only from supplied real taxonomy")
 check(catalog.matching("Kitchen","").size()==63,"category filters the full catalogue before paging")
 check(catalog.matching("All","  ITEM 124  ")[0].id=="item_124","case-insensitive token search reaches last item")
 check(catalog.matching("Decor","124").is_empty(),"search and category intersect")
 check(catalog.matching("All","ingredient").is_empty(),"unimplemented ingredients are not fabricated")
 var page=Catalog.page(catalog.entries,999,4)
 check(page.page==31 and page.pages==32 and page.rows.size()==1 and page.rows[0].id=="item_124","last result page clamps and remains bounded")
 page=Catalog.page(catalog.entries,-4,4)
 check(page.page==0 and page.rows.size()==4,"first result page clamps negative input")
 page=Catalog.page([],99,4)
 check(page.page==0 and page.pages==1 and page.rows.is_empty(),"empty results have no stale rows")
 catalog.configure([{"id":"stove","name":"Stove","category":"Kitchen"},{"id":"stove","name":"Duplicate","category":"Other"}])
 check(catalog.entries.size()==1 and catalog.categories()==["All","Kitchen"],"duplicate IDs never create two display selections")
 rows[0].name="Mutated caller data"
 check(catalog.entries[0].name=="Stove","display catalogue owns copied metadata")
 print("MAIL_GIFT_CATALOG_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"synthetic_only":true}))
 quit(0 if failures.is_empty() else 1)
