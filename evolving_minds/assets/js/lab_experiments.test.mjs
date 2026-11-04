import test from 'node:test'
import assert from 'node:assert/strict'
import {createWorld,stepWorld} from './lab_engine.mjs'
import {MISSIONS,MISSION_KEY,experimentLink,readExperimentLink,missionProgress,readCompleted,completeMission} from './lab_experiments.mjs'
const storage=()=>{const data=new Map();return {getItem:key=>data.get(key)??null,setItem:(key,value)=>data.set(key,value)}}

test('shared links recreate starting conditions, including Unicode and small trait values',()=>{
  const world=createWorld({seed:'Română & 🧠? + = #',aggression:1e-7});stepWorld(world)
  const url=new URL(experimentLink('https://example.test/lab?token=private#old',world.config,'diversity'))
  assert.equal(url.origin,'https://example.test');assert.equal(url.pathname,'/lab');assert.equal(url.hash,'');assert.equal(url.searchParams.has('token'),false)
  const shared=readExperimentLink(url.search);assert.deepEqual(shared.config,world.config);assert.equal(shared.mission,'diversity')
  assert.equal(createWorld(shared.config).tick,0)
})
test('ambiguous, malformed and oversized links never produce partial settings',()=>{
  const url=new URL(experimentLink('https://example.test',createWorld().config))
  for(const query of [url.search+'&seed=second',url.search.replace('population=24','population='),url.search.replace('aggression=0.5','aggression=Infinity'),url.search+'&mission=unknown',url.search+'&padding='+ 'x'.repeat(2048)])assert.throws(()=>readExperimentLink(query),/invalid starting conditions/)
  assert.equal(readExperimentLink('?utm_source=example'),null)
})
test('missions require all targets together and can be solved by running real worlds',()=>{
  for(const mission of MISSIONS){
    const world=createWorld({...mission.config,seed:mission.seed,...(mission.id==='diversity'?{aggression:.1,curiosity:.95,epoch:'abundance'}:{})})
    assert.equal(missionProgress(world,mission.id).complete,false)
    for(let i=0;i<120;i++)stepWorld(world)
    assert.equal(missionProgress(world,mission.id).complete,true,mission.id)
    if(mission.epoch){world.config.epoch='normal';assert.equal(missionProgress(world,mission.id).complete,false)}
  }
})
test('local milestones persist once and corrupt data is preserved',()=>{
  const local=storage();assert.deepEqual(readCompleted(local),{})
  const first=completeMission(local,'famine');assert.deepEqual(completeMission(local,'famine'),first)
  assert.throws(()=>completeMission(local,'unknown'))
  for(const raw of ['broken','null',JSON.stringify({version:1,completed:{unknown:new Date().toISOString()}})]){
    local.setItem(MISSION_KEY,raw);assert.throws(()=>completeMission(local,'famine'));assert.equal(local.getItem(MISSION_KEY),raw)
  }
})
