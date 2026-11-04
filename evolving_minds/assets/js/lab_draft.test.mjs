import test from 'node:test'
import assert from 'node:assert/strict'
import {createWorld,stepWorld} from './lab_engine.mjs'
import {DRAFT_KEY,readDraft,writeDraft,rawDraftBackup,resetUnreadableDraft} from './lab_draft.mjs'
const storage=()=>{const values=new Map();return {getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)}}

test('reload recovery preserves the random stream, name, speed and active mission',()=>{
  const local=storage(),world=createWorld({seed:'reload'});stepWorld(world)
  writeDraft(local,{world,name:'Recovered world',speed:4,mission:'famine'});const restored=readDraft(local)
  assert.equal(restored.name,'Recovered world');assert.equal(restored.speed,4);assert.equal(restored.mission,'famine')
  stepWorld(world);stepWorld(restored.world);assert.deepEqual(restored.world,world)
})
test('corrupt, oversized and unknown recovery formats remain untouched',()=>{
  const local=storage()
  for(const raw of ['broken','null','x'.repeat(600_001),JSON.stringify({version:99})]){
    local.setItem(DRAFT_KEY,raw);assert.throws(()=>readDraft(local),/could not be read/)
    assert.throws(()=>writeDraft(local,{world:createWorld()}));assert.equal(rawDraftBackup(local),raw)
  }
})
test('quota or permission failures preserve previous recovery and do not mutate the running world',()=>{
  const local=storage(),world=createWorld();writeDraft(local,{world});const previous=local.getItem(DRAFT_KEY);stepWorld(world)
  const denied={getItem:local.getItem,setItem(){throw Error('quota')}}
  assert.throws(()=>writeDraft(denied,{world}),/unavailable/);assert.equal(local.getItem(DRAFT_KEY),previous);assert.equal(world.tick,1)
  assert.throws(()=>readDraft({getItem(){throw Error('blocked')}}),/unavailable/)
})
test('an explicit reset affects only unreadable recovery, not other tab data',()=>{
  const local=storage();local.setItem('other','keep');local.setItem(DRAFT_KEY,'broken');resetUnreadableDraft(local)
  assert.equal(readDraft(local),null);assert.equal(local.getItem('other'),'keep');assert.throws(()=>resetUnreadableDraft(local),/readable again/)
})
