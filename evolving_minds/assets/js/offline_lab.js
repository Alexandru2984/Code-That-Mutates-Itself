import {EvolutionLab} from './lab_hook'
import {initPwa,refreshPwaPanel} from './pwa_client'
initPwa()
const root=document.getElementById('evolution-lab')
if(root){
  const lab={el:root}
  Object.assign(lab,EvolutionLab)
  let started=false
  try{lab.mounted();started=true}catch(_){const status=document.querySelector('[data-lab-startup]');if(status)status.textContent='The simulator could not start in this browser. Reload the page or open the live observatory.'}
  if(started)window.addEventListener('pagehide',event=>{if(!event.persisted)lab.destroyed()})
  if(started)window.addEventListener('pageshow',event=>{if(event.persisted){lab.last=performance.now();lab.running=false;lab.render();refreshPwaPanel()}})
}
