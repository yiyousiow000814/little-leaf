import json,unittest
from pathlib import Path
from unittest.mock import patch
from github_latest import key,select,qualify,reconcile,latest
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parents[2]
def release(tag,**extra):return dict(tag_name=tag,draft=False,prerelease=False,**extra)
class LatestTests(unittest.TestCase):
 def test_letter_order(self):self.assertEqual(sorted(['v0.1.11','v0.1.10b','v0.1.10','v0.1.10a'],key=key),['v0.1.10','v0.1.10a','v0.1.10b','v0.1.11'])
 def test_all_pages_and_backfill(self):
  pages=[[release('v0.1.10')],[release('v0.1.11')]]
  self.assertEqual(select(pages,release('v0.1.10a'))['tag_name'],'v0.1.11')
  self.assertIsNone(select(pages,release('v0.1.12')))
 def test_unknown_api_data_fail_closed(self):
  for pages,current in [({},None),[[{}],None],([[]],release('unknown'))]:
   with self.assertRaises((ValueError,TypeError)):select(pages,current)
 def test_draft_and_prerelease_ignored(self):
  a=release('v1.0.0');a['draft']=True;b=release('v2.0.0');b['prerelease']=True
  self.assertEqual(select([[a,b,release('v0.1.10a')]],None)['tag_name'],'v0.1.10a')
 def test_both_completion_orders_preserve_all_and_monotonic_latest(self):
  for order in [('v0.1.10a','v0.1.11'),('v0.1.11','v0.1.10a')]:
   published=[release('v0.1.10')];current=published[0]
   for tag in order:
    published.append(release(tag));chosen=select([published],current)
    if chosen:current=chosen
   self.assertEqual(len(published),3);self.assertEqual(current['tag_name'],'v0.1.11')
  self.assertEqual(select([[release('v0.1.10a'),release('v0.1.11')]],release('v0.1.10'))['tag_name'],'v0.1.11')
 def test_workflow_only_serializes_promotion(self):
  s=(ROOT/'.github/workflows/github-release.yml').read_text();self.assertIn('group: github-release-${{ inputs.tag || github.ref_name }}',s);self.assertIn('group: github-release-latest',s);self.assertIn('queue: max',s);self.assertIn('--latest=false',s);self.assertIn('needs: release',s)
 def test_exact_metadata_and_main_ancestry(self):
  calls=[]
  def git(*args):
   calls.append(args)
   if args[1]=='rev-parse':return 'a'*40
   if args[1]=='merge-base':return ''
   if args[-1].endswith(':project.godot'):return 'config/version="0.1.10a"'
   return json.dumps({'schema_version':1,'version':'0.1.10a','status':'released','date':'2026-01-01'})
  self.assertEqual(qualify('v0.1.10a',git),'a'*40);self.assertTrue(any('origin/main' in c for c in calls))
  with self.assertRaises(ValueError):qualify('v0.1.10b',git)
 def test_reconcile_late_older_job_promotes_highest_and_confirms(self):
  calls=[]
  def api(*args):
   calls.append(args)
   if '--paginate' in args:return json.dumps([[release('v0.1.10a')],[release('v0.1.11')]])
   return 'a'*40 if '--jq' in args else ''
  with patch('github_latest.run',side_effect=api),patch('github_latest.qualify',return_value='a'*40),patch('github_latest.latest',side_effect=[release('v0.1.10'),release('v0.1.10a'),release('v0.1.11')]):
   self.assertEqual(reconcile('owner/repo'),'Latest confirmed: v0.1.11')
  self.assertEqual([c for c in calls if 'edit' in c],[('gh','release','edit','v0.1.11','--repo','owner/repo','--latest')])
 def test_newer_latest_during_validation_prevents_mutation(self):
  with patch('github_latest.run',side_effect=[json.dumps([[release('v0.1.11')]]),'a'*40]) as api,patch('github_latest.qualify',return_value='a'*40),patch('github_latest.latest',side_effect=[release('v0.1.10'),release('v0.1.12')]):
   self.assertIn('advanced',reconcile('owner/repo'));self.assertEqual(api.call_count,2)
 def test_uncertain_promotion_is_not_retried(self):
  calls=[]
  def api(*args):
   calls.append(args)
   if '--paginate' in args:return json.dumps([[release('v0.1.11')]])
   if 'edit' in args:raise RuntimeError('lost acknowledgment')
   return 'a'*40
  with patch('github_latest.run',side_effect=api),patch('github_latest.qualify',return_value='a'*40),patch('github_latest.latest',return_value=release('v0.1.10')):
   with self.assertRaises(RuntimeError):reconcile('owner/repo')
  self.assertEqual(len([c for c in calls if 'edit' in c]),1)
 def test_latest_api_requires_explicit_status_and_valid_json(self):
  for code,text in [(1,'HTTP/2.0 403 Forbidden'),(1,''),(0,'not http'),(0,'HTTP/2.0 200 OK\n\ninvalid')]:
   with patch('github_latest.subprocess.run',return_value=SimpleNamespace(returncode=code,stdout=text)):
    with self.assertRaises((ValueError,IndexError)):latest('owner/repo')
  with patch('github_latest.subprocess.run',return_value=SimpleNamespace(returncode=1,stdout='HTTP/2.0 404 Not Found')):self.assertIsNone(latest('owner/repo'))
 def test_api_failure_never_mutates(self):
  with patch('github_latest.run',side_effect=RuntimeError('offline')) as run:
   with self.assertRaises(RuntimeError):reconcile('owner/repo')
   self.assertEqual(run.call_count,1)
if __name__=='__main__':unittest.main()
