"""Offline read-only integrity/comparison wrapper; never starts Godot or runs an FPS sample."""
import argparse, hashlib, importlib.util, json, re, sys, zipfile, tempfile
from pathlib import Path
sys.dont_write_bytecode=True
BASE='8c415d94fdb86e68dd0ce90d3482f9e668e8805d'
TREE='e2f47c90931397e6d633bb3b7b6824fd4b4005cb'
ZIP='3e0c8a7bad9ebac47c8148fc4bfffef2356c86140e66afc086dad95c478b4e0d'
SEAL='3be62d00e9cb59f97d99d7625f136341e515b97f782460c9edfa9e5fe875b573'
HELPERS={'compare.py':'d56998f48bb5b18cb29fe6af41b53b3059c240f3604d3682677228d81d1c9768','run-native.sh':'76f2433fafef6459c48ddaa993b6e2b87e80dbe1f0e905c8156a812e523d25db','stage.py':'3536c465bbbe5b9694105580ba9945c9dd51f493699990a702c4d0375856b627','native_draw_probe.gd':'bb793f1a25a178189b792f7bb343449209000914b538d4bcc07c50254361dd3b','synthetic-starter-21walls.json':'ed6fcfc1e4a3396389eff71b09f60740d099de9c046eb0e37eabe900e8c1cf4f'}
RAW='diagnostic-native-draw.json'
def require(value,msg):
 if not value:raise ValueError(msg)
def sha(data):return hashlib.sha256(data).hexdigest()
def fingerprint(seal,arm,pre=False):
 keys=['engine','display_server','window','refresh_hz','video_adapter','video_vendor','video_api','processor','platform'] if pre else seal['fingerprint'].keys()
 bad={k:(seal['fingerprint'][k],arm.get(k,'MISSING')) for k in keys if k not in arm or seal['fingerprint'][k]!=arm[k]}
 require(not bad,'incompatible envelope: '+json.dumps(bad))
def archived(archive,helpers):
 require(not sys.flags.optimize,'Run without python -O: immutable comparator uses asserts')
 for n,d in HELPERS.items():require(sha((helpers/n).read_bytes())==d,'wrong #368 helper '+n)
 spec=importlib.util.spec_from_file_location('frozen368',helpers/'compare.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 require(sha(archive.read_bytes())==ZIP,'wrong frozen archive bytes')
 with zipfile.ZipFile(archive) as z,tempfile.TemporaryDirectory() as work:
  sealed=z.read('baseline-seal.json');require(sha(sealed)==SEAL,'wrong sealed bytes')
  seal=json.loads(sealed);require(seal['source']['commit']==BASE and seal['source']['tree']==TREE,'wrong original')
  root=Path(work)
  for n,d in seal['sha256'].items():
   data=z.read('before/'+n);require(sha(data)==d,'wrong frozen '+n);(root/n).write_bytes(data)
  baseline=module.summary(root);fingerprint(seal,baseline['envelope'])
  require(baseline['source']==seal['source'] and baseline['probe_sha256']==HELPERS['native_draw_probe.gd'],'wrong original sampler')
  require(baseline['count']==311 and baseline['frame_gap_ms']['p95']==41.114,'original report differs')
 return seal,baseline,module
def audio_display(log):
 return ('All audio drivers failed, falling back to the dummy driver.' in log and 'Could not set V-Sync mode' in log and 'OpenGL API 4.5 (Core Profile) Mesa 25.2.8-0ubuntu0.24.04.4 - Compatibility - Using Device: Mesa - llvmpipe (LLVM 20.1.2, 256 bits)' in log)
def bind(binding,summary,dirname):
 for k,size in [('commit',40),('tree',40),('archive_sha256',64)]:
  require(re.fullmatch('[0-9a-f]{'+str(size)+'}',binding.get(k,'')), 'unbound candidate '+k)
 require(binding['commit']!=BASE and summary['source']=={**{k:binding[k] for k in ('commit','tree','archive_sha256')},'allowed_project_paths':['game']},'candidate committed bytes mismatch')
 require(summary['probe_sha256']==HELPERS['native_draw_probe.gd'],'candidate used different sampler')
 raw=json.loads((dirname/RAW).read_text())
 require(raw['scope']=='Godot frame_post_draw, not physical presentations or busy time','different clock')
 require(audio_display((dirname/'native-game.log').read_text()),'audio/vsync/driver differed from historical logs')
def main():
 p=argparse.ArgumentParser();p.add_argument('--archive',required=True,type=Path);p.add_argument('--helpers',required=True,type=Path)
 p.add_argument('--host-envelope',type=Path);p.add_argument('--graphics',type=Path);p.add_argument('--candidate',type=Path);p.add_argument('--binding',type=Path)
 a=p.parse_args();seal,original,module=archived(a.archive,a.helpers)
 if a.host_envelope:require(a.host_envelope.read_text().strip()==seal['fingerprint']['runtime-envelope.txt'],'cloud runner image/CPU/kernel/cgroup/visibility differs; do not sample')
 if a.graphics:fingerprint(seal,json.loads(a.graphics.read_text()),pre=True)
 require(bool(a.candidate)==bool(a.binding),'need candidate and binding together')
 if a.candidate:
  now=module.summary(a.candidate);bind(json.loads(a.binding.read_text()),now,a.candidate);fingerprint(seal,now['envelope'])
  require(now['state']==original['state'],'end-state differed: isolate candidate; no comparison')
  print(json.dumps({'kind':'frozen archived original; one source-bound candidate; engine-completed native cadence only','baseline':original,'candidate':now,'p95_gap_delta_ms':now['frame_gap_ms']['p95']-original['frame_gap_ms']['p95'],'engine_completed_fps_delta':now['average_engine_completed_fps']-original['average_engine_completed_fps'],'p95_gap_within_60hz_period':now['frame_gap_ms']['p95']<=1000/60,'p95_gap_within_14p1667ms_reference_only':now['frame_gap_ms']['p95']<=.85*1000/60,'busy_work_headroom':'UNMEASURED by capped completed-draw intervals; separate pacing-excluded workload timer required','presentation':'unmeasured'},indent=2))
 else:print(json.dumps({'frozen_verified':True,'original_frames':original['count'],'p95_gap_ms':original['frame_gap_ms']['p95'],'sample_started':False}))
if __name__=='__main__':main()
