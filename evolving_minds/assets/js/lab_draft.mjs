import {restoreWorld} from './lab_engine.mjs'
import {MISSIONS} from './lab_experiments.mjs'
export const DRAFT_KEY='evolving-minds:lab-draft:v1'
const MAX_BYTES=600_000
const failure=code=>Object.assign(Error(code==='storage'?'Reload recovery is unavailable in this tab. Save in the library or export your experiment.':'Previous reload recovery could not be read. Download its original data before resetting it.'),{code})
function raw(storage){try{return storage.getItem(DRAFT_KEY)}catch(_){throw failure('storage')}}
function parse(text){
  try{
    if(typeof text!=='string'||text.length>MAX_BYTES||new TextEncoder().encode(text).length>MAX_BYTES)throw Error()
    const data=JSON.parse(text)
    if(!data||data.version!==1||typeof data.savedAt!=='string'||data.savedAt.length>40||!Number.isFinite(Date.parse(data.savedAt))||typeof data.name!=='string'||data.name.length>60||!Number.isInteger(data.speed)||data.speed<1||data.speed>10||(data.mission!==null&&!MISSIONS.some(mission=>mission.id===data.mission)))throw Error()
    return {version:1,savedAt:data.savedAt,name:data.name,speed:data.speed,mission:data.mission,world:restoreWorld(data.world)}
  }catch(_){throw failure('invalid')}
}
export function readDraft(storage){const text=raw(storage);return text===null?null:parse(text)}
export function writeDraft(storage,{world,name='',speed=2,mission=null}){
  // Never replace unreadable recovery data without an explicit reset.
  readDraft(storage)
  const value=parse(JSON.stringify({version:1,savedAt:new Date().toISOString(),name:String(name).slice(0,60),speed,mission,world}))
  try{storage.setItem(DRAFT_KEY,JSON.stringify(value))}catch(_){throw failure('storage')}
  return value
}
export const rawDraftBackup=storage=>raw(storage)??''
export function resetUnreadableDraft(storage){
  let unreadable=false
  try{readDraft(storage)}catch(error){if(error.code!=='invalid')throw error;unreadable=true}
  if(!unreadable)throw Error('Reload recovery is readable again. Refresh before resetting it.')
  try{storage.removeItem(DRAFT_KEY)}catch(_){throw failure('storage')}
}
