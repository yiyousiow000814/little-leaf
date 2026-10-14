extends RefCounted
## Synchronous namespaced localStorage preferences, independent of progress.
## Legacy CFG bytes arrive only through the shell's read-only IDB bootstrap.
var api
var last_error=""
var source=""
var usable=false
func load_into(config:ConfigFile)->bool:
	api=JavaScriptBridge.get_interface("__littleLeafPreferences")
	if api==null:
		last_error="Browser preference support is missing";return false
	var result=JSON.parse_string(str(api.bootJson))
	if not result is Dictionary or not bool(result.get("ok",false)):
		last_error=str(result.get("error","Preferences are unavailable")) if result is Dictionary else "Preference startup did not finish"
		return false
	source=str(result.get("source",""))
	if config.parse(str(result.get("text","")))!=OK:
		last_error="Saved preferences could not be parsed; original bytes are unchanged";return false
	usable=true
	if source=="legacy-readonly" and not bool(api.acceptLoaded()):last_error=str(api.lastError)
	return true
func save_from(config:ConfigFile)->bool:
	if api==null or not usable:
		if last_error=="":last_error="Browser preferences are unavailable"
		return false
	if not bool(api.writeText(config.encode_to_text())):
		last_error=str(api.lastError);return false
	last_error="";return true
