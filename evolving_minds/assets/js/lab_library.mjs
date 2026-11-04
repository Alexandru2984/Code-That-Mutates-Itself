import {restoreWorld,summarize} from './lab_engine.mjs'

export const LIBRARY_KEY='evolving-minds:lab-library:v2'
export const LIBRARY_LIMIT=6
const MAX_BYTES=1_500_000
const invalid=()=>{throw Error('The saved experiment library could not be read. Existing data has not been changed.')}
const label=(name,world)=>String(name||'').trim().slice(0,60)||`${world.config.seed} · Step ${world.tick}`.slice(0,60)
const entryCopy=entry=>{
  if(!entry||typeof entry.id!=='string'||!/^[-a-zA-Z0-9]{1,64}$/.test(entry.id)||typeof entry.name!=='string'||!entry.name.trim()||entry.name.length>60||
    !(entry.savedAt===null||(typeof entry.savedAt==='string'&&entry.savedAt.length<=40&&Number.isFinite(Date.parse(entry.savedAt)))))invalid()
  return {id:entry.id,name:entry.name,savedAt:entry.savedAt,world:restoreWorld(entry.world)}
}
export function readLibrary(storage){
  const raw=storage.getItem(LIBRARY_KEY)
  if(raw===null){
    const legacy=storage.getItem('evolving-minds:lab:v1');if(legacy===null)return []
    if(legacy.length>512000)invalid()
    try{return [{id:'legacy-save',name:'Recovered experiment',savedAt:null,world:restoreWorld(JSON.parse(legacy))}]}catch(_){invalid()}
  }
  if(raw.length>MAX_BYTES)invalid()
  try{
    const data=JSON.parse(raw)
    if(data.version!==2||!Array.isArray(data.entries)||data.entries.length>LIBRARY_LIMIT)invalid()
    const entries=data.entries.map(entryCopy)
    if(new Set(entries.map(e=>e.id)).size!==entries.length)invalid()
    return entries
  }catch(_){invalid()}
}
function write(storage,entries){
  const raw=JSON.stringify({version:2,entries:entries.map(entryCopy)})
  if(new TextEncoder().encode(raw).length>MAX_BYTES)throw Error('This experiment library is too large. Export or remove an experiment first.')
  storage.setItem(LIBRARY_KEY,raw)
  return entries
}
export function saveExperiment(storage,world,name){
  const entries=readLibrary(storage)
  if(entries.length>=LIBRARY_LIMIT)throw Error(`Your library holds ${LIBRARY_LIMIT} experiments. Export or remove one before saving another.`)
  const snapshot=restoreWorld(world)
  const entry={id:globalThis.crypto.randomUUID(),name:label(name,snapshot),savedAt:new Date().toISOString(),world:snapshot}
  write(storage,[entry,...entries]);return entry
}
export function renameExperiment(storage,id,name){
  const entries=readLibrary(storage),entry=entries.find(e=>e.id===id)
  if(!entry)throw Error('That saved experiment is no longer available.')
  if(!String(name||'').trim())throw Error('Enter a name before renaming the experiment.')
  entry.name=label(name,entry.world);return write(storage,entries)
}
export function removeExperiment(storage,id){
  const entries=readLibrary(storage),index=entries.findIndex(e=>e.id===id)
  if(index<0)throw Error('That saved experiment is no longer available.')
  const [entry]=entries.splice(index,1);write(storage,entries);return {entry,index}
}
export function undoRemoval(storage,removed){
  const entries=readLibrary(storage)
  if(entries.length>=LIBRARY_LIMIT)throw Error('Make room in the library before restoring this experiment.')
  if(entries.some(e=>e.id===removed.entry.id))throw Error('This experiment is already in the library.')
  entries.splice(Math.min(removed.index,entries.length),0,entryCopy(removed.entry));return write(storage,entries)
}
export function compareExperiments(entries,ids){
  return ids.slice(0,3).flatMap(id=>{const entry=entries.find(e=>e.id===id);return entry?[{...entry,summary:summarize(entry.world)}]:[]})
}
function cell(value){
  let text=String(value??'')
  // Quotes alone do not stop spreadsheet formulas, including whitespace-prefixed ones.
  if(/^[\s]*[=+\-@]/.test(text)||/^[\t\r]/.test(text))text="'"+text
  return '"'+text.replace(/"/g,'""')+'"'
}
const columns=['experiment','seed','epoch','step','population','mean_energy','mean_aggression','mean_curiosity','generation','solari','umbra']
const row=(entry,point)=>[entry.name,entry.world.config.seed,entry.world.config.epoch,point.tick,point.population,point.energy,point.aggression,point.curiosity,point.generation,point.solari,point.umbra]
const csv=rows=>'\ufeff'+[columns,...rows].map(values=>values.map(cell).join(',')).join('\r\n')+'\r\n'
export function historyCsv(world,name){const snapshot=restoreWorld(world);const entry={name:label(name,snapshot),world:snapshot};return csv(snapshot.history.map(point=>row(entry,point)))}
export function comparisonCsv(entries,ids){return csv(compareExperiments(entries,ids).map(entry=>row(entry,entry.summary)))}
