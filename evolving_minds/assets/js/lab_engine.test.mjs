import test from 'node:test'
import assert from 'node:assert/strict'
import {createWorld,stepWorld,summarize,SCENARIOS} from './lab_engine.mjs'

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
