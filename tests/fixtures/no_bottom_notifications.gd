extends RefCounted
## Structural regression guard. Absence must be real, never hidden/no-op compatibility.
static func has_property(object:Object,key:String)->bool:
 for property in object.get_property_list():
  if str(property.name)==key:return true
 return false
static func unexpected_nodes(node:Node,allowed_show:Node,allowed_tutorial_next:Node=null)->Array:
 var result=[]
 var script=node.get_script()
 if script!=null and "cafe_status_notice" in str(script.resource_path):result.append(str(node.get_path()))
 if node is Button and node!=allowed_show and node!=allowed_tutorial_next and node.text in ["Show","Next"]:result.append(str(node.get_path())+": "+node.text)
 for child in node.get_children():result.append_array(unexpected_nodes(child,allowed_show,allowed_tutorial_next))
 return result
static func verify(game,assertion:Callable,label:String):
 for key in ["status_text","toast_lifetime"]:
  assertion.call(not has_property(game,key),label+": no bottom state "+key)
 for method in ["_notify","_service_warning","_dismiss_edit_feedback"]:
  assertion.call(not game.has_method(method),label+": no bottom producer "+method)
 assertion.call(not has_property(game.compact_ui,"status_notice"),label+": no bottom component")
 assertion.call(not game.compact_ui.has_method("refresh_status"),label+": no bottom refresh")
 for method in ["show_access_issue","current_access_issue","access_message","_fit_access_camera","draw_access_focus"]:
  assertion.call(not game.workface_guidance.has_method(method),label+": no bottom navigation "+method)
 assertion.call(not FileAccess.file_exists("res://scripts/cafe_status_notice.gd"),label+": component source deleted")
 # The guide now has a deliberate Next action; it is not the retired bottom
 # notice navigator. Exempt only that exact button in its actual guide panel.
 var guide=game.get("tutorial")
 var tutorial_next=guide.next_button if guide!=null and guide.panel.is_ancestor_of(guide.next_button) else null
 assertion.call(unexpected_nodes(game.ui,game.compact_ui.blockage_button,tutorial_next).is_empty(),label+": no bottom notice or legacy navigation nodes")
 assertion.call(game.compact_ui.wallet_notice!=null,label+": wallet notifications remain")
 assertion.call(is_instance_valid(game.compact_ui.hint) and is_instance_valid(game.compact_ui.hint_text),label+": pointer hint remains")
 assertion.call(game.workface_guidance.has_method("describe") and game.workface_guidance.has_method("draw_ground"),label+": ground guidance remains")
