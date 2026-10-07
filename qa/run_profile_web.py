"""Run an exported disposable performance fixture in an owned Chrome profile."""
from pathlib import Path
import argparse,http.server,threading,subprocess,time,json
p=argparse.ArgumentParser();p.add_argument('--web',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
r=a.web.resolve();q=a.output.resolve();q.mkdir(parents=True,exist_ok=False)
class Handler(http.server.SimpleHTTPRequestHandler):
 def __init__(self,*args,**kw):super().__init__(*args,directory=str(r),**kw)
 def log_message(self,*args):pass
s=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=s.serve_forever,daemon=True).start()
flags=['--headless=new','--mute-audio','--window-size=1360,880','--disable-background-networking','--disable-component-update','--disable-default-apps','--no-first-run','--no-default-browser-check','--user-data-dir='+str(q/'chrome-profile'),'--remote-debugging-port=0','about:blank']
b=subprocess.Popen([r'C:\Program Files\Google\Chrome\Application\chrome.exe',*flags],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW)
try:
 for i in range(100):
  port=q/'chrome-profile/DevToolsActivePort'
  if port.exists():break
  if b.poll() is not None:raise RuntimeError('Chrome exited')
  time.sleep(.1)
 d=subprocess.run(['node',str(Path(__file__).with_name('profile_web.js')),port.read_text().splitlines()[0],'http://127.0.0.1:'+str(s.server_port)+'/index.html',str(q)],capture_output=True,text=True,timeout=170)
 (q/'run.log').write_text(d.stdout+d.stderr);print(d.stdout+d.stderr);assert d.returncode==0
finally:
 if b.poll() is None:b.terminate();b.wait(timeout=10)
 s.shutdown();s.server_close()
