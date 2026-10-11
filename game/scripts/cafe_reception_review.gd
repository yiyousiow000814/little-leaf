extends RefCounted
## Private native review custody. No production profile discovery or imports.
const SaveContract=preload("res://scripts/cafe_save_contract.gd")
const PROTECTED=["little_leaf_cafe_layout_motion_v15.json","little_leaf_cafe_navigation_v16.json","little_leaf_cafe_footprint_placement_v17.json","little_leaf_cafe_routing_reception_review_v19.json","little_leaf_illustrated_r9.json","little_leaf_illustrated_r7.json","little_leaf_illustrated_r6.json","little_leaf_illustrated_r5.json","little_leaf_illustrated_r4.json"]

static func canonical(path:String)->String:
	var resolved=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().trim_suffix("/")
	return resolved.to_lower() if OS.get_name()=="Windows" else resolved

static func inside(path:String,parent:String)->bool:
	return path!=parent and path.begins_with(parent+"/")

static func link_free(path:String,allow_new_file:bool=false)->bool:
	# Check every ancestor, including those outside the disposable root.
	# Godot4.6.3 Windows is_link checks FILE_ATTRIBUTE_REPARSE_POINT.
	var at=path
	var first=true
	# The checker needs an accessible existing parent, not permission to list
	# every ancestor. Absolute attribute queries still check each ancestor.
	var checker=DirAccess.open(path.get_base_dir())
	if checker==null:return false
	while at!="":
		var parent=at.get_base_dir()
		if parent==at or parent=="":return DirAccess.dir_exists_absolute(at)
		if checker.is_link(at):return false
		var exists=checker.file_exists(at) or checker.dir_exists(at)
		if not exists and not (first and allow_new_file):return false
		if not first and not checker.dir_exists(at):return false
		at=parent;first=false
	return false

static func scope_allowed(routing:bool=false)->bool:
	if OS.has_feature("web") or OS.get_name() not in ["Windows","Linux","macOS"]:return false
	var args=OS.get_cmdline_user_args()
	if "--fresh-review" not in args or "--reception-candidate" not in args:return false
	if routing:
		for flag in ["--navigation-candidate","--guest-navigation-candidate","--routing-reception-persistence-candidate"]:
			if flag not in args:return false
	elif "--navigation-candidate" in args or "--guest-navigation-candidate" in args or "--routing-reception-persistence-candidate" in args:return false
	for flag in ["--navigation-persistence-candidate","--footprint-placement"]:
		if flag in args:return false
	if routing and "--reception-persistence-candidate" in args:return false
	var raw=OS.get_environment("LL_RECEPTION_REVIEW_ROOT").replace("\\","/")
	if not raw.is_absolute_path() or raw.begins_with("user://") or raw.begins_with("res://"):return false
	var scope=canonical(raw);var data=canonical(OS.get_user_data_dir())
	if not inside(data,scope) or not link_free(scope) or not link_free(data):return false
	# A dedicated application directory is required, even in a disposable root.
	for profile in SaveContract.PROFILES:
		for component in (data+"/"+scope).split("/"):
			if component.to_lower()==str(profile.app).to_lower():return false
	return true

static func persistence_allowed(routing:bool=false)->bool:
	return scope_allowed(routing) and (routing or "--reception-persistence-candidate" in OS.get_cmdline_user_args())

static func path_allowed(path:String,temporary:bool=false,routing:bool=false)->bool:
	if not persistence_allowed(routing):return false
	var target=canonical(path);var data=canonical(OS.get_user_data_dir())
	if not target.is_absolute_path() or not inside(target,data):return false
	if DirAccess.dir_exists_absolute(target):return false
	var base=target.get_file()
	# Reject Windows alternate streams, reserved device aliases and ambiguous names.
	if base.is_empty() or base.begins_with(".") or base.ends_with(".") or base.ends_with(" "):return false
	for character in base:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":return false
	var stem=base.get_basename().to_lower()
	if stem in ["con","prn","aux","nul","com1","com2","com3","com4","com5","com6","com7","com8","com9","lpt1","lpt2","lpt3","lpt4","lpt5","lpt6","lpt7","lpt8","lpt9"]:return false
	if temporary:
		if not base.ends_with(".json.tmp"):return false
		base=base.trim_suffix(".tmp")
	elif not base.ends_with(".json"):return false
	if base.to_lower() in PROTECTED and not (routing and routing_filename(base)):return false
	if routing and base.to_lower()==SaveContract.RECEPTION_REVIEW_FILE.get_file().to_lower():return false
	for profile in SaveContract.PROFILES:
		if base.to_lower()==str(profile.file).to_lower():return false
	return link_free(target,true)

static func reception_filename(path:String)->bool:
	return canonical(path).get_file().to_lower()==SaveContract.RECEPTION_REVIEW_FILE.get_file().to_lower()

static func routing_filename(path:String)->bool:
	return canonical(path).get_file().to_lower().trim_suffix(".tmp")==SaveContract.ROUTING_RECEPTION_REVIEW_FILE.get_file().to_lower()

static func commit(temp_path:String,path:String,routing:bool=false)->bool:
	if not path_allowed(path,false,routing) or not path_allowed(temp_path,true,routing):return false
	if OS.get_name()!="Windows":return DirAccess.rename_absolute(temp_path,path)==OK
	# Godot's Windows rename deletes an existing target first. File.Replace keeps
	# that target intact on failure; File.Move refuses an unexpected new target.
	var temp=canonical(temp_path).replace("'","''");var target=canonical(path).replace("'","''")
	var script="$ErrorActionPreference='Stop';try{if([IO.File]::Exists('%s')){[IO.File]::Replace('%s','%s',[NullString]::Value)}else{[IO.File]::Move('%s','%s')};exit 0}catch{exit 1}"%[target,temp,target,temp,target]
	var encoded=Marshalls.raw_to_base64(script.to_utf16_buffer())
	var output=[]
	return OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-WindowStyle","Hidden","-EncodedCommand",encoded],output,false)==0
