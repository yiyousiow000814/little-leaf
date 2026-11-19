extends RefCounted
## Pure counters only. Four bins in image storage order; no coordinates or pixels exit.
static func summarize(a:PackedByteArray,b:PackedByteArray,size:Vector2i,sentinel=false)->Dictionary:
	if size.x<1 or size.y<1 or a.size()!=size.x*size.y*4 or b.size()!=a.size():return {}
	var q:=[0,0,0,0]
	var changed:=0
	var alpha_only:=0
	var alpha_changed:=0
	var rgb_changed:=0
	var one_lsb:=0
	var max_delta:=0
	var outside:=0
	var outside_flip:=0
	if a!=b:
		for y in range(size.y):
			for x in range(size.x):
				var i:=(y*size.x+x)*4
				if a[i]==b[i] and a[i+1]==b[i+1] and a[i+2]==b[i+2] and a[i+3]==b[i+3]:continue
				var rgb:=maxi(maxi(absi(a[i]-b[i]),absi(a[i+1]-b[i+1])),absi(a[i+2]-b[i+2]))
				var ad:=absi(a[i+3]-b[i+3])
				var magnitude:=maxi(rgb,ad)
				changed+=1
				if rgb==0:alpha_only+=1
				else:rgb_changed+=1
				if ad!=0:alpha_changed+=1
				if magnitude==1:one_lsb+=1
				max_delta=maxi(magnitude,max_delta)
				q[int(x>=size.x*0.5)+2*int(y>=size.y*0.5)]+=1
				if sentinel:
					var r:=Rect2i(14,14,43,39)
					if not r.has_point(Vector2i(x,y)):outside+=1
					if not r.has_point(Vector2i(x,size.y-1-y)):outside_flip+=1
	return {"changed":changed,"quadrants":q,"rgb_changed":rgb_changed,"alpha_changed":alpha_changed,"alpha_only":alpha_only,
		"one_lsb":one_lsb,"max_byte_delta":max_delta,"outside_sentinel":outside,"outside_sentinel_flipped":outside_flip}

