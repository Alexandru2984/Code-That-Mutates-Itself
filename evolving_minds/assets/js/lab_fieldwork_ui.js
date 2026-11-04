import {createWorld} from './lab_engine.mjs'
import {MISSIONS,MISSION_KEY,experimentLink,readExperimentLink,missionProgress,readCompleted,completeMission} from './lab_experiments.mjs'
const node=(tag,text,cls)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el}

export function mountFieldwork(hook){
  const root=hook.el;let active=null,completed={},awarded=new Set(),storageWarning=false
  try{completed=readCompleted(localStorage)}catch(error){hook.notice(error.message)}
  const cards=root.querySelector('[data-mission-list]');cards.replaceChildren()
  for(const [index,mission]of MISSIONS.entries()){
    const card=node('article',undefined,'mission-card'),heading=node('h3',`${String(index+1).padStart(2,'0')} · ${mission.title}`)
    const description=node('p',mission.description,'muted'),badge=node('span',completed[mission.id]?'✓ Completed locally':'Ready to explore','mission-badge');badge.dataset.missionBadge=mission.id
    const start=node('button','Start mission','button button-quiet');start.type='button';start.dataset.missionStart=mission.id
    card.append(heading,description,badge,start);cards.append(card)
  }
  const update=()=>{
    for(const item of MISSIONS){const badge=root.querySelector(`[data-mission-badge="${item.id}"]`);badge.textContent=completed[item.id]||awarded.has(item.id)?'✓ Completed locally':active===item.id?'Exploring now':'Ready to explore'}
    const panel=root.querySelector('[data-active-mission]');panel.hidden=!active;if(!active)return
    const mission=MISSIONS.find(item=>item.id===active),progress=missionProgress(hook.world,active)
    root.querySelector('[data-mission-title]').textContent=mission.title
    const targets=root.querySelector('[data-mission-targets]');targets.replaceChildren()
    for(const target of progress.targets){
      const item=node('div'),label=node('label',`${target.label}: ${target.value} / ${target.target}`),bar=node('progress');bar.max=100;bar.value=target.percent
      label.append(bar);item.append(label);targets.append(item)
    }
    const hint=root.querySelector('[data-mission-hint]');hint.textContent=progress.environmentMatches?'All targets must be met together. Adjust the conditions and rebuild to test another strategy.':`This mission needs the ${mission.epoch} environment. Choose it in the settings and rebuild.`
    if(progress.complete&&!awarded.has(active)){
      awarded.add(active)
      try{completed=completeMission(localStorage,active)}catch(error){if(!storageWarning){storageWarning=true;hook.notice(`Mission complete in this session. ${error.message||'Browser storage is unavailable.'}`)}}
      root.querySelector(`[data-mission-badge="${active}"]`).textContent='✓ Completed locally'
      if(!storageWarning)hook.notice(`Mission complete: ${mission.title}. Save this experiment to compare its strategy.`)
    }
    root.querySelector('[data-mission-result]').textContent=progress.complete?'✓ All targets met in this experiment':completed[active]||awarded.has(active)?'Completed before · keep exploring another strategy':'Mission in progress'
  }
  const start=id=>{
    const mission=MISSIONS.find(item=>item.id===id);if(!mission)return
    active=id;hook.loadSnapshot(createWorld({...mission.config,seed:mission.seed}));root.querySelector('[data-save-name]').value=mission.title
    update();hook.notice(`${mission.title} started and paused. Run the experiment, inspect the targets, then try changing a condition.`)
    root.querySelector('[data-missions]').open=true
  }
  const onClick=async event=>{
    const startId=event.target.closest('[data-mission-start]')?.dataset.missionStart
    if(startId){start(startId);return}
    if(event.target.closest('[data-mission-stop]')){active=null;update();hook.notice('Mission closed. Your experiment is still here.');return}
    if(event.target.closest('[data-share-conditions]')){
      try{
        const url=experimentLink(location.href,hook.world.config,active),field=root.querySelector('[data-share-link]');field.value=url;root.querySelector('[data-share-result]').hidden=false
        try{await navigator.clipboard.writeText(url);hook.notice('Starting conditions link copied. It begins at step zero; use JSON to share the current snapshot.')}
        catch(_){field.focus();field.select();hook.notice('Starting conditions link ready. Copy it from the field; it begins at step zero.')}
      }catch(error){hook.notice(error.message)}
    }
  }
  root.addEventListener('click',onClick)
  const onStorage=event=>{if(event.key===MISSION_KEY||event.key===null){try{completed=readCompleted(localStorage);update()}catch(error){hook.notice(error.message)}}};window.addEventListener('storage',onStorage)
  try{
    const shared=readExperimentLink(location.search)
    if(shared){active=shared.mission;hook.loadSnapshot(createWorld(shared.config));if(active)root.querySelector('[data-missions]').open=true;hook.notice('Shared starting conditions loaded at step zero. Run your own reproducible experiment.')}
  }catch(error){hook.notice(error.message)}
  update()
  return {update,destroy(){root.removeEventListener('click',onClick);window.removeEventListener('storage',onStorage)}}
}
