import {readLibrary,saveExperiment,renameExperiment,removeExperiment,undoRemoval,compareExperiments,comparisonCsv,historyCsv,LIBRARY_KEY,exportLibrary,importLibrary,rawLibraryBackup,resetUnreadableLibrary,MAX_ARCHIVE_BYTES} from './lab_library.mjs'

const node=(tag,text,cls)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el}
const button=(text,action,id)=>{const el=node('button',text,'button button-quiet');el.type='button';el.dataset.entryAction=action;if(id)el.dataset.entryId=id;return el}
const percent=n=>`${Math.round(n*100)}%`
export function mountLibrary(hook){
  const library={entries:[],selected:[],removed:null}
  const root=hook.el,notice=hook.notice
  const download=(content,name,type)=>{const url=URL.createObjectURL(new Blob([content],{type}));const link=document.createElement('a');link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}
  const render=()=>{
    const active=document.activeElement;
    const focus=active&&root.contains(active)?{action:active.dataset.entryAction,id:active.dataset.entryId,name:active.dataset.savedName}:null;
    library.entries=readLibrary(localStorage)
    root.querySelector('[data-library-problem]').hidden=true
    root.querySelector('[data-entry-action=export_library]').disabled=false
    library.selected=library.selected.filter(id=>library.entries.some(e=>e.id===id))
    const list=root.querySelector('[data-library-list]');list.replaceChildren()
    for(const entry of library.entries){
      const article=node('article',undefined,'saved-experiment');article.dataset.savedId=entry.id
      const heading=node('h3',entry.name);article.append(heading)
      const summary=entry.world,detail=node('p',`Seed ${summary.config.seed} · Step ${summary.tick} · ${summary.entities.length} minds · ${summary.config.epoch}`,'muted');article.append(detail)
      const date=node('small',entry.savedAt?`Saved ${new Date(entry.savedAt).toLocaleString()}`:'Recovered from the earlier browser save');article.append(date)
      const renameRow=node('div',undefined,'saved-rename'),name=node('input');name.type='text';name.value=entry.name;name.maxLength=60;name.dataset.savedName=entry.id;name.setAttribute('aria-label',`Rename ${entry.name}`);renameRow.append(name,button('Rename','rename',entry.id));article.append(renameRow)
      const actions=node('div',undefined,'saved-actions'),compare=button(library.selected.includes(entry.id)?'✓ Comparing':'+ Compare','compare',entry.id);compare.setAttribute('aria-pressed',String(library.selected.includes(entry.id)));actions.append(button('Load experiment','load',entry.id),compare,button('Remove','remove',entry.id));article.append(actions);list.append(article)
    }
    root.querySelector('[data-library-empty]').hidden=library.entries.length>0
    root.querySelector('[data-library-count]').textContent=`${library.entries.length}/6`
    root.querySelector('[data-library-undo]').hidden=!library.removed
    const selected=compareExperiments(library.entries,library.selected),panel=root.querySelector('[data-saved-comparison]');panel.hidden=selected.length===0
    const cards=root.querySelector('[data-comparison-cards]');cards.replaceChildren()
    const colors=['#b9efd2','#e5bb72','#c5a3ed'],dashes=['','5 2','1 2'];
    const chart=root.querySelector('[data-comparison-chart]');chart.replaceChildren()
    const histories=selected.flatMap(e=>e.world.history),min=Math.min(...histories.map(p=>p.tick)),max=Math.max(...histories.map(p=>p.tick))
    const hasTrace=selected.some(entry=>entry.world.history.length>1);chart.style.display=hasTrace?'':'none'
    root.querySelector('[data-comparison-axis]').textContent=!selected.length?'':hasTrace?`Step ${min} → ${max} · Population 0–60. Single-point snapshots have no trace.`:'Run and save an experiment after at least one step to draw its population history. Starting values appear in the cards above.'
    for(const [index,entry]of selected.entries()){
      const card=node('article',undefined,'saved-comparison-card'),title=node('h4',entry.name);title.style.color=colors[index];card.append(title)
      for(const [label,value]of [['Population',entry.summary.population],['Mean energy',`${entry.summary.energy}%`],['Generation',entry.summary.generation],['Aggression',percent(entry.summary.aggression)],['Curiosity',percent(entry.summary.curiosity)],['Births / deaths',`${entry.world.births} / ${entry.world.deaths}`]]){const line=node('p');line.append(node('span',label),node('strong',value));card.append(line)}
      card.append(button('Load this experiment','load',entry.id));cards.append(card)
      const line=document.createElementNS('http://www.w3.org/2000/svg','polyline');line.setAttribute('points',entry.world.history.map(p=>`${(p.tick-min)*100/Math.max(max-min,1)},${95-p.population/60*85}`).join(' '));line.setAttribute('stroke',colors[index]);line.setAttribute('stroke-dasharray',dashes[index]);line.setAttribute('stroke-width','2');line.setAttribute('fill','none');line.setAttribute('vector-effect','non-scaling-stroke');chart.append(line)
    }
    if(focus){
      let target=focus.name?root.querySelector(`[data-saved-name="${focus.name}"]`):null;
      if(focus.action)target=root.querySelector(`[data-entry-action="${focus.action}"]${focus.id?`[data-entry-id="${focus.id}"]`:''}`);
      if((!target||!target.getClientRects().length)&&focus.action==='remove')target=root.querySelector('[data-library-undo]');
      if(target?.getClientRects().length)target.focus({preventScroll:true});
    }
  }
  const refresh=()=>{try{render()}catch(error){
    root.querySelector('[data-library-problem]').hidden=false;root.querySelector('[data-library-list]').replaceChildren();root.querySelector('[data-saved-comparison]').hidden=true;root.querySelector('[data-library-empty]').hidden=true;root.querySelector('[data-library-count]').textContent='Unavailable';root.querySelector('[data-library-undo]').hidden=true;root.querySelector('[data-entry-action=export_library]').disabled=true
    notice(error.message||'Browser storage is unavailable. Export your experiment to keep it.')
  }}
  const onClick=event=>{
    const target=event.target.closest('[data-entry-action]');if(!target)return
    const {entryAction:action,entryId:id}=target.dataset
    try{
      if(action==='export_library'){download(exportLibrary(localStorage),'evolving-minds-library.json','application/json');notice('Library exported. Import this file on another device to merge your saved experiments.');return}
      if(action==='backup_raw'){download(rawLibraryBackup(localStorage),'evolving-minds-library-recovery.json','application/octet-stream');notice('Original library data downloaded. Keep it before resetting the unreadable library.');return}
      if(action==='reset_library'){
        if(!window.confirm('Reset the unreadable experiment library? Download its original data first if you want to recover it. Your current experiment stays open.'))return
        resetUnreadableLibrary(localStorage);library.selected=[];library.removed=null;refresh();notice('Library reset. Your current experiment and other browser preferences are unchanged.');return
      }
      if(action==='load'){const entry=readLibrary(localStorage).find(e=>e.id===id);if(!entry)throw Error('That experiment is no longer available.');hook.loadSnapshot(entry.world);root.querySelector('[data-save-name]').value=entry.name;notice(`Loaded ${entry.name}. The saved snapshot stays unchanged.`)}
      if(action==='compare'){if(library.selected.includes(id))library.selected=library.selected.filter(item=>item!==id);else if(library.selected.length<3)library.selected.push(id);else throw Error('Compare up to three saved experiments at a time.')}
      if(action==='rename'){renameExperiment(localStorage,id,root.querySelector(`[data-saved-name="${id}"]`).value);notice('Saved experiment renamed.')}
      if(action==='remove'){library.removed=removeExperiment(localStorage,id);notice('Saved experiment removed. You can undo this removal until you leave the page.')}
      if(action==='undo'){undoRemoval(localStorage,library.removed);library.removed=null;notice('Saved experiment restored.')}
      if(action==='clear_compare')library.selected=[]
      if(action==='export_compare')download(comparisonCsv(library.entries,library.selected),'evolving-minds-comparison.csv','text/csv;charset=utf-8')
      refresh()
    }catch(error){notice(error.message||'The library could not be updated.')}
  }
  root.addEventListener('click',onClick)
  const archiveInput=root.querySelector('[data-import-library]')
  const onArchive=async event=>{
    const file=event.target.files?.[0];if(!file)return
    try{
      if(file.size>MAX_ARCHIVE_BYTES)throw Error('Library archives must be smaller than 2 MB.')
      const result=importLibrary(localStorage,await file.text());refresh();notice(`Imported ${result.added} experiment${result.added===1?'':'s'}; skipped ${result.skipped} identical save${result.skipped===1?'':'s'}. Existing saves were preserved.`)
    }catch(error){notice(error.message||'This library could not be imported. Existing saves have not been changed.')}
    event.target.value=''
  }
  archiveInput.addEventListener('change',onArchive)
  const onStorage=event=>{if(event.key===LIBRARY_KEY||event.key===null)refresh()};window.addEventListener('storage',onStorage)
  refresh()
  return {
    save(){saveExperiment(localStorage,hook.world,root.querySelector('[data-save-name]').value);refresh();notice('Experiment saved in this browser. Select saved snapshots below to compare them.')},
    load(){const entry=readLibrary(localStorage)[0];if(!entry){notice('No saved experiment in this browser yet.');return}hook.loadSnapshot(entry.world);root.querySelector('[data-save-name]').value=entry.name;notice('Saved experiment loaded and paused.')},
    exportCsv(){download(historyCsv(hook.world,root.querySelector('[data-save-name]').value),'evolving-minds-history.csv','text/csv;charset=utf-8')},
    destroy(){root.removeEventListener('click',onClick);archiveInput.removeEventListener('change',onArchive);window.removeEventListener('storage',onStorage)}
  }
}
