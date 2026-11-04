import test from 'node:test'
import assert from 'node:assert/strict'
import {historyView,HISTORY_METRICS} from './lab_history.mjs'
import {createWorld,stepWorld} from './lab_engine.mjs'

test('history inspection selects real measurements without mutating the experiment',()=>{
  const world=createWorld();for(let i=0;i<10;i++)stepWorld(world);const before=JSON.stringify(world)
  const selected=historyView(world.history,{tick:3,follow:false,metric:'energy'})
  assert.equal(selected.point.tick,3);assert.equal(selected.definition.value(selected.point),world.history[3].energy);assert.equal(JSON.stringify(world),before)
  assert.equal(historyView(world.history).point.tick,10)
})
test('chart coordinates use actual step spacing and bounded metric scales',()=>{
  const world=createWorld(),point=world.history[0],history=[point,{...point,tick:10},{...point,tick:30}]
  const view=historyView(history);assert.equal(view.points.split(' ')[1].split(',')[0],String(100/3));assert.equal(view.marker,100)
  for(const metric of Object.keys(HISTORY_METRICS)){const selected=historyView(history,{metric});assert.ok(selected.definition.value(selected.point)<=selected.definition.max)}
  assert.equal(historyView(history,{metric:'__proto__'}).key,'population')
})
test('a pruned selection advances to the oldest retained measurement',()=>{
  const world=createWorld();for(let i=0;i<150;i++)stepWorld(world)
  assert.equal(historyView(world.history,{tick:0,follow:false}).point.tick,world.history[0].tick)
  assert.equal(historyView(world.history,{tick:0,follow:false}).index,0)
  assert.equal(historyView([]),null)
})
