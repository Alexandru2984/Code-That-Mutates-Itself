import {SCENARIOS,summarize} from './lab_engine.mjs'

export const MISSIONS=[
  {id:'common-ground',title:'Build common ground',description:'Keep a generous world thriving through cooperation.',seed:'common-ground-v1',config:SCENARIOS.cooperation,epoch:'abundance'},
  {id:'famine',title:'Outlast the famine',description:'Find a strategy that keeps scarce resources from ending the population.',seed:'outlast-famine-v1',config:SCENARIOS.survival,epoch:'famine'},
  {id:'diversity',title:'Let diversity endure',description:'Help both tribes survive while new traits emerge.',seed:'diversity-v1',config:SCENARIOS.balanced}
]
const keys=['seed','population','aggression','curiosity','mutation','epoch']
function validConfig(config){
  return typeof config.seed==='string'&&config.seed.length>0&&config.seed.length<=80&&!/[\u0000-\u001f\u007f]/.test(config.seed)&&
    Number.isInteger(config.population)&&config.population>=2&&config.population<=60&&
    ['aggression','curiosity','mutation'].every(key=>Number.isFinite(config[key])&&config[key]>=0&&config[key]<=(key==='mutation'?.3:1))&&
    ['normal','abundance','famine'].includes(config.epoch)
}
export function experimentLink(base,config,missionId){
  if(!validConfig(config))throw Error('These starting conditions cannot be shared. Build a new experiment first.')
  const url=new URL('/lab',base);url.searchParams.set('experiment','1')
  for(const key of keys)url.searchParams.set(key,config[key])
  if(MISSIONS.some(mission=>mission.id===missionId))url.searchParams.set('mission',missionId)
  return url.href
}
export function readExperimentLink(search){
  const params=new URLSearchParams(search)
  if(!params.has('experiment'))return null
  const invalid=()=>{throw Error('This experiment link has invalid starting conditions. Your current world has not been changed.')}
  if(search.length>2048||params.getAll('experiment').length!==1||params.get('experiment')!=='1')invalid()
  for(const key of keys)if(params.getAll(key).length!==1)invalid()
  for(const key of ['population','aggression','curiosity','mutation'])if(!/^(?:\d+)(?:\.\d+)?(?:e[+-]?\d{1,3})?$/i.test(params.get(key)))invalid()
  const config=Object.fromEntries(keys.map(key=>[key,['seed','epoch'].includes(key)?params.get(key):Number(params.get(key))]))
  if(!validConfig(config)||params.getAll('mission').length>1)invalid()
  const mission=params.get('mission')
  if(mission&&!MISSIONS.some(item=>item.id===mission))invalid()
  return {config,mission:mission||null}
}
export function missionProgress(world,id){
  const mission=MISSIONS.find(item=>item.id===id);if(!mission)return null
  const stats=summarize(world),cooperation=Math.round(world.cooperations/Math.max(world.cooperations+world.attacks,1)*100)
  const targets=id==='common-ground'?
    [['Steps observed',world.tick,60],['Living minds',stats.population,40],['Cooperative encounters (%)',cooperation,90]]:
    id==='famine'? [['Steps observed',world.tick,60],['Living minds',stats.population,20],['Mean energy (%)',stats.energy,50]]:
    [['Steps observed',world.tick,80],['Solari minds',stats.solari,10],['Umbra minds',stats.umbra,10],['Mutations recorded',world.mutations,50]]
  const environmentMatches=!mission.epoch||world.config.epoch===mission.epoch
  return {targets:targets.map(([label,value,target])=>({label,value,target,percent:Math.min(100,Math.floor(value/target*100))})),
    environmentMatches,complete:environmentMatches&&targets.every(([,value,target])=>value>=target)}
}
export const MISSION_KEY='evolving-minds:lab-missions:v1'
export function readCompleted(storage){
  const raw=storage.getItem(MISSION_KEY);if(raw===null)return {}
  try{
    if(raw.length>2048)throw Error()
    const data=JSON.parse(raw)
    if(data.version!==1||!data.completed||Array.isArray(data.completed)||typeof data.completed!=='object')throw Error()
    const completed={}
    for(const [id,date]of Object.entries(data.completed)){
      if(!MISSIONS.some(item=>item.id===id)||typeof date!=='string'||date.length>40||!Number.isFinite(Date.parse(date)))throw Error()
      completed[id]=date
    }
    return completed
  }catch(_){throw Error('Saved mission milestones could not be read. Existing data has not been changed.')}
}
export function completeMission(storage,id){
  if(!MISSIONS.some(item=>item.id===id))throw Error('Unknown mission.')
  const completed=readCompleted(storage)
  if(!completed[id]){completed[id]=new Date().toISOString();storage.setItem(MISSION_KEY,JSON.stringify({version:1,completed}))}
  return completed
}
