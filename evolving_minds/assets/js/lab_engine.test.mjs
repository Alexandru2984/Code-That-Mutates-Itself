import test from 'node:test'
import assert from 'node:assert/strict'
import {createWorld,stepWorld,summarize,SCENARIOS,restoreWorld} from './lab_engine.mjs'

test('the same seed and controls reproduce the same experiment',()=>{
  const a=createWorld({seed:'reproducible',...SCENARIOS.cooperation}),b=createWorld({seed:'reproducible',...SCENARIOS.cooperation});
  for(let i=0;i<150;i++){stepWorld(a);stepWorld(b)}assert.deepEqual(a,b);
  assert.notDeepEqual(createWorld({seed:'other'}).entities,createWorld({seed:'reproducible'}).entities);
});
test('all scenarios preserve bounds, bookkeeping and bounded history over long runs',()=>{
  for(const scenario of Object.values(SCENARIOS)){
    const world=createWorld({...scenario,seed:'invariants'});
    for(let i=0;i<500;i++){
      stepWorld(world);assert.ok(world.entities.length<=60);assert.ok(world.history.length<=120);assert.ok(world.events.length<=10);
      assert.equal(world.births-world.deaths,world.entities.length);
      assert.equal(new Set(world.entities.map(e=>e.id)).size,world.entities.length);
      for(const e of world.entities){assert.ok(e.energy>0&&e.energy<=100);assert.ok(e.aggression>=0&&e.aggression<=1);assert.ok(e.curiosity>=0&&e.curiosity<=1);assert.ok(e.generation>=1)}
    }
  }
});
test('malformed numeric input is bounded and an extinct world remains inspectable',()=>{
  const world=createWorld({population:Infinity,aggression:-100,curiosity:100,mutation:900,epoch:'unknown'});
  assert.equal(world.config.population,2);assert.equal(world.config.aggression,0);assert.equal(world.config.curiosity,1);assert.equal(world.config.mutation,.3);assert.equal(world.config.epoch,'normal');
  world.entities=[];const tick=world.tick;stepWorld(world);assert.equal(world.tick,tick);assert.equal(summarize(world).population,0);
});

test('exported snapshots resume the same random stream without sharing mutable state',async()=>{
  const {restoreWorld}=await import('./lab_engine.mjs');
  const original=createWorld({...SCENARIOS.balanced,seed:'resume'});for(let i=0;i<30;i++)stepWorld(original);
  const resumed=restoreWorld(JSON.parse(JSON.stringify(original)));assert.deepEqual(resumed,original);
  for(let i=0;i<80;i++){stepWorld(original);stepWorld(resumed)}assert.deepEqual(resumed,original);
  resumed.config.seed='different';assert.notEqual(original.config.seed,resumed.config.seed);
});
test('malformed, oversized and duplicate-identity snapshots are rejected without coercion',async()=>{
  const {restoreWorld}=await import('./lab_engine.mjs');const source=createWorld();
  for(const edit of [w=>{w.entities[0].energy=Infinity},w=>{w.entities[1].id=w.entities[0].id},w=>{w.config.aggression='0.5'},w=>{w.rng=0},w=>{w.version=2},w=>{w.history=Array(121).fill(w.history[0])},w=>{w.births=1}]){
    const broken=structuredClone(source);edit(broken);assert.throws(()=>restoreWorld(broken),/valid version 1/);
  }
  const data=JSON.parse(JSON.stringify(source));data.__proto__={polluted:true};const loaded=restoreWorld(data);assert.equal(loaded.polluted,undefined);assert.equal({}.polluted,undefined);
});

test('duplicate historical steps are rejected rather than shown as ambiguous measurements',()=>{
  const world=createWorld();world.history.push({...world.history[0]})
  assert.throws(()=>restoreWorld(world),/not a valid/)
})
