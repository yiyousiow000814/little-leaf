import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {createFixtureStore} from './fullflow_fixtures.mjs';
const environment=await initializeTestEnvironment({projectId:'demo-little-leaf',firestore:{rules:readFileSync('firestore.rules','utf8')}});
try{
  assert.equal(await environment.withSecurityRulesDisabled(async()=>({mustNotBeReturned:true})),undefined,'SDK callback result is deliberately discarded');
  const fixtures=createFixtureStore(environment),value={schema:1,synthetic:'fixture-read-regression'};
  await fixtures.seed('fullflow-helper',value);
  assert.deepEqual(await fixtures.read('fullflow-helper'),value);
  assert.equal(await fixtures.read('fullflow-helper-missing'),null);
  await assert.rejects(fixtures.read('not-a-fixture'));
  await assert.rejects(fixtures.read('fullflow-helper','arbitrary-path'));
  assert.throws(()=>createFixtureStore({projectId:'production'}));
  console.log('Real emulator fixture helpers: callback-return regression, exact observation, missing document and synthetic-only scope passed.');
}finally{await environment.cleanup();}
