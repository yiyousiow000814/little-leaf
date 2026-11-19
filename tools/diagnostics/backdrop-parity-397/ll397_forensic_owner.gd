extends "res://ll397_active_backdrop.gd"
## QA only. Default replays v1's target policy. The one alternative matches root.
## This must not change the root format, art, opacity, filtering or thresholds.
var _match_root := false

func target_policy(match_root:bool,a)->bool:
	if not is_instance_valid(a) or _baking or _inside:return false
	var root:Window=a.get_tree().root
	if root.use_hdr_2d or root.msaa_2d!=Viewport.MSAA_DISABLED or root.transparent_bg:return false
	_restore()
	_baked=[]
	_match_root=match_root
	if is_instance_valid(_vp):
		_vp.transparent_bg=root.transparent_bg if _match_root else true
	return true

func _init_producer(a)->bool:
	if not super._init_producer(a):return false
	_vp.transparent_bg=a.get_tree().root.transparent_bg if _match_root else true
	return true

func target_class()->Dictionary:
	if not is_instance_valid(_vp):return {}
	return {"producer_transparent":_vp.transparent_bg,"root_transparent":_vp.get_tree().root.transparent_bg,
		"producer_hdr":_vp.use_hdr_2d,"root_hdr":_vp.get_tree().root.use_hdr_2d}
