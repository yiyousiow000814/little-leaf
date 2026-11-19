import json,sys
from pathlib import Path
from guard import need
from receipt import OUT
from counter_verify import report
d=json.loads(OUT.read_text())
need(d['stage']=='canvas_counter' and d['native_pixels_verified'] is True and d['qualified_stills']==8 and d['web_qualified'] is False)
s=report(json.loads(Path(sys.argv[1]).read_text()))
d.update(status='native_stills_and_isolated_commands_verified',stage='complete',isolated_wall_canvas=s)
OUT.write_text(json.dumps(d,indent=2)+'\n')
