extends RefCounted
## Presentation-only catalogue. It never grants, stores or authorizes an item.
## Callers supply real catalogue names/categories and their supported IDs.
var entries:Array=[]

# The gameplay catalogue is an Array, not a Dictionary indexed by kind.
static func item_name(model,kind:String)->String:
 return model.name_of(kind) if not kind.strip_edges().is_empty() else "Unknown item"

func configure(rows:Array):
 entries=[]
 var seen={}
 for row in rows:
  var id=str(row.get("id",""))
  if id=="" or seen.has(id):continue
  seen[id]=true
  entries.append({"id":id,"name":str(row.get("name",id)),"category":str(row.get("category","Other"))})

func categories()->Array:
 var result:Array=["All"]
 for row in entries:
  if not row.category in result:result.append(row.category)
 return result

func matching(category:String,query:String)->Array:
 var tokens=query.strip_edges().to_lower().split(" ",false)
 return entries.filter(func(row):
  if category!="All" and row.category!=category:return false
  var words=(row.name+" "+row.id+" "+row.category).to_lower()
  for token in tokens:
   if not str(token) in words:return false
  return true
 )

static func page(rows:Array,index:int,limit:int)->Dictionary:
 var size=maxi(1,limit)
 var pages=maxi(1,ceili(float(rows.size())/size))
 var selected=clampi(index,0,pages-1)
 return {"rows":rows.slice(selected*size,(selected+1)*size),"page":selected,"pages":pages,"total":rows.size()}
