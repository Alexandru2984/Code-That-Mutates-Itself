import test from 'node:test'
import assert from 'node:assert/strict'
import {createWorld,stepWorld} from './lab_engine.mjs'
import {LIBRARY_KEY,LIBRARY_LIMIT,readLibrary,saveExperiment,renameExperiment,removeExperiment,undoRemoval,compareExperiments,historyCsv,comparisonCsv} from './lab_library.mjs'
const storage=()=>{const values=new Map();return {getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,String(value)),values}}

test('legacy saves remain recoverable and are not overwritten by the new library',()=>{
  const local=storage(),world=createWorld({seed:'legacy'}),legacy=JSON.stringify(world);local.setItem('evolving-minds:lab:v1',legacy);
  const recovered=readLibrary(local);assert.equal(recovered.length,1);assert.deepEqual(recovered[0].world,world);
  saveExperiment(local,createWorld({seed:'new'}),'New world');assert.equal(readLibrary(local).length,2);assert.equal(local.getItem('evolving-minds:lab:v1'),legacy);
});
test('saved worlds are detached snapshots and capacity never silently removes data',()=>{
  const local=storage(),world=createWorld();const saved=saveExperiment(local,world,'Baseline');stepWorld(world);
  assert.equal(readLibrary(local)[0].world.tick,0);renameExperiment(local,saved.id,'Renamed');assert.equal(readLibrary(local)[0].name,'Renamed');
  for(let i=1;i<LIBRARY_LIMIT;i++)saveExperiment(local,world,`Variant ${i}`);
  const before=local.getItem(LIBRARY_KEY);assert.throws(()=>saveExperiment(local,world,'Overflow'),/holds 6/);assert.equal(local.getItem(LIBRARY_KEY),before);
});
test('remove and undo preserve saved identity and world data',()=>{
  const local=storage();const first=saveExperiment(local,createWorld({seed:'first'}),'First');saveExperiment(local,createWorld({seed:'second'}),'Second');
  const removed=removeExperiment(local,first.id);assert.equal(readLibrary(local).length,1);undoRemoval(local,removed);
  assert.deepEqual(readLibrary(local)[1],first);assert.throws(()=>undoRemoval(local,removed),/already/);
});
test('corrupt and duplicate-identity libraries are rejected without modifying their source',()=>{
  const local=storage();saveExperiment(local,createWorld(),'Good');const good=JSON.parse(local.getItem(LIBRARY_KEY));
  for(const raw of ['broken',JSON.stringify({...good,version:99}),JSON.stringify({version:2,entries:[good.entries[0],good.entries[0]]})]){
    local.setItem(LIBRARY_KEY,raw);assert.throws(()=>readLibrary(local));assert.throws(()=>saveExperiment(local,createWorld(),'Do not replace'));assert.equal(local.getItem(LIBRARY_KEY),raw);
  }
});
test('CSV exports escape spreadsheet formulas and preserve quoted labels',()=>{
  const world=createWorld({seed:'  @SUM(1,2)'});const csv=historyCsv(world,'=HYPERLINK("x")');
  assert.ok(csv.includes('"\'=HYPERLINK(""x"")"'));assert.ok(csv.includes('"\'  @SUM(1,2)"'));
  assert.ok(historyCsv(world,'A "quoted" name').includes('"A ""quoted"" name"'));
  const local=storage();const ids=Array.from({length:4},(_,i)=>saveExperiment(local,world,`World ${i}`).id);
  assert.equal(compareExperiments(readLibrary(local),ids).length,3);
  assert.equal(comparisonCsv(readLibrary(local),ids).split('\r\n').filter(Boolean).length,4);
});
