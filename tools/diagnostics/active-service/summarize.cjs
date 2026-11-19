'use strict';
const assert=require('node:assert/strict'), fs=require('node:fs'), path=require('node:path');
const dir=process.argv[2];
assert(dir);
const trials=['A1','B1','B2','A2'].map(label=>{
  const source=path.join(dir,label,'active-service-cadence.json');
  if(!fs.existsSync(source))return {label,status:'missing'};
  const r=JSON.parse(fs.readFileSync(source,'utf8'));
  const env=r.raw.environment, a=r.active;
  return {label,status:a.foreground_without_screenshot?.count>0 && !r.raw.lost?'sampled':'incomplete',
    source:r.source, artifact_sha256:r.artifact_sha256, fixture_sha256:r.scenario.fixture_sha256,
    renderer:env.renderer, userAgent:env.userAgent, dpr:env.dpr, size:env.size,
    foreground:a.foreground_without_screenshot, all:a.all, controller:a.near_controller_prepare,
    indexedDB:a.near_async_indexeddb, overlap_reliable:r.save_clock_reliable && !r.save_log_maybe_truncated,
    sample_duration_ms:r.marks.payment_paid-r.marks.service_begin, long_animation_frames:r.raw.longFrames.length,
    wall_count:r.scenario.wall_count, served_delta_coins:r.scenario.payment_delta};
});
const sample=trials[0];
const heldConstant=['fixture_sha256','renderer','userAgent','dpr','size','wall_count'];
const comparable=trials.every(t=>t.status==='sampled' && heldConstant.every(k=>JSON.stringify(t[k])===JSON.stringify(sample[k])))
  && !!sample.renderer && trials[0].source.exact===trials[3].source.exact && trials[1].source.exact===trials[2].source.exact
  && trials[0].source.exact!==trials[1].source.exact;
const report={scope:'Same-host browser callback cadence, not display presentations or 60 FPS + 15% CPU/GPU headroom',
  comparable, trials};
fs.writeFileSync(path.join(dir,'comparison-summary.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
if(!comparable)process.exitCode=1;
