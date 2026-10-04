extends RefCounted
## Isolated native experiment: startup only discovers its own new profile.
## Legacy fixtures can be loaded by an explicitly supplied copied path.
const SaveContract=preload("res://scripts/cafe_save_contract.gd")
const PROFILES=SaveContract.PROFILES
static func primary_for_app()->String:
 return SaveContract.PRIMARY_FILE
static func progress_candidates(primary:String,current_directory:String="")->Array[String]:
 var current=OS.get_user_data_dir() if current_directory=="" else current_directory
 # Do not let an obsolete caller re-enable legacy profile discovery.
 return [current.path_join(SaveContract.PRIMARY_FILE.get_file()).simplify_path()]
static func settings_candidates(primary:String,current_directory:String="")->Array[String]:
 var current=OS.get_user_data_dir() if current_directory=="" else current_directory
 return [current.path_join("little_leaf_settings.cfg").simplify_path()]
static func first_existing(candidates:Array)->String:
 for candidate in candidates:
  if FileAccess.file_exists(candidate):return candidate
 return ""
