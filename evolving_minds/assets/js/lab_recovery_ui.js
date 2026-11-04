import {readDraft,writeDraft,rawDraftBackup,resetUnreadableDraft} from './lab_draft.mjs'
import {downloadText} from './downloads'
const sharedKeys=['experiment','seed','population','aggression','curiosity','mutation','epoch','mission']
export function mountRecovery(hook){
  const root=hook.el,status=root.querySelector('[data-session-status]'),time=root.querySelector('[data-session-time]'),problem=root.querySelector('[data-session-problem]')
  let storage,dirty=false,blocked=false,timer=null,savedOnce=false,shared=new URLSearchParams(location.search).has('experiment')
  const fail=error=>{blocked=true;status.textContent=error.code==='invalid'?error.message:'Reload recovery is unavailable in this tab. Save in the library or export your experiment.';problem.hidden=error.code!=='invalid'}
  const stamp=draft=>{time.textContent=`Last checkpoint ${new Date(draft.savedAt).toLocaleTimeString()}`;time.dateTime=draft.savedAt}
  const flush=()=>{
    if(timer!==null){clearTimeout(timer);timer=null}
    if(!dirty||blocked||!storage)return
    try{
      const draft=writeDraft(storage,{world:hook.world,name:root.querySelector('[data-save-name]').value,speed:hook.speed,mission:hook.fieldwork.currentMission()})
      dirty=false;stamp(draft)
      if(!savedOnce){status.textContent='Your current experiment can be recovered after a reload in this tab. Save in the library for a lasting copy.';savedOnce=true}
      if(shared){const url=new URL(location.href);for(const key of sharedKeys)url.searchParams.delete(key);history.replaceState(history.state,'',url);shared=false}
    }catch(error){fail(error)}
  }
  const touch=()=>{if(blocked||!storage)return;dirty=true;if(shared){queueMicrotask(flush)}else if(timer===null)timer=setTimeout(flush,1500)}
  try{
    storage=sessionStorage
    const draft=readDraft(storage)
    if(draft&&!shared){
      hook.loadSnapshot(draft.world);root.querySelector('[data-save-name]').value=draft.name;hook.speed=draft.speed
      const speed=root.querySelector('input[name=speed]');speed.value=draft.speed;speed.closest('label').querySelector('output').textContent=`${draft.speed}×`
      hook.fieldwork.restoreMission(draft.mission);stamp(draft);savedOnce=true;status.textContent='Previous experiment recovered in this tab. It is paused and ready to continue.'
      hook.notice(`Recovered your previous session at step ${draft.world.tick}, paused. Named library saves stay unchanged.`)
    }else{status.textContent=shared?'Shared starting conditions are ready. Reload recovery begins when you change this experiment.':'Reload recovery is available in this tab. Save or export an experiment to keep a lasting copy.'}
  }catch(error){fail(error)}
  const onClick=event=>{
    const action=event.target.closest('[data-session-action]')?.dataset.sessionAction
    try{
      if(action==='backup')downloadText(rawDraftBackup(storage),'evolving-minds-session-recovery.json','application/octet-stream')
      if(action==='reset'&&window.confirm('Reset unreadable reload recovery? Download its original data first if needed. The experiment currently open stays unchanged.')){resetUnreadableDraft(storage);blocked=false;problem.hidden=true;touch();flush()}
    }catch(error){status.textContent=error.message||'Recovery data could not be updated.'}
  }
  const onVisibility=()=>{if(document.hidden)flush()}
  root.addEventListener('click',onClick);window.addEventListener('pagehide',flush);window.addEventListener('evolving-minds:before-update',flush);document.addEventListener('visibilitychange',onVisibility)
  return {touch,flush,destroy(){flush();root.removeEventListener('click',onClick);window.removeEventListener('pagehide',flush);window.removeEventListener('evolving-minds:before-update',flush);document.removeEventListener('visibilitychange',onVisibility)}}
}
