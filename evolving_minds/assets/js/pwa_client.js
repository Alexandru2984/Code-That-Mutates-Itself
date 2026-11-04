let initialized=false,registration=null,installPrompt=null,busy=false,ready=false,reloading=false,updateRequested=false
let message='Enable offline access while connected. Saved experiments stay in this browser; export a library to transfer them to another device.'
const supported=()=>window.isSecureContext&&'serviceWorker'in navigator
const owns=reg=>[reg?.active,reg?.waiting,reg?.installing].some(worker=>worker&&new URL(worker.scriptURL).pathname==='/service-worker.js')
const status=(worker,action='OFFLINE_STATUS')=>new Promise(resolve=>{
  if(!worker){resolve(false);return}
  const channel=new MessageChannel(),timeout=setTimeout(()=>{channel.port1.close();resolve(false)},action==='PREPARE_OFFLINE'?30_000:2000)
  channel.port1.onmessage=event=>{clearTimeout(timeout);channel.port1.close();resolve(event.data?.ready===true)}
  worker.postMessage(action,[channel.port2])
})
const activeWorker=reg=>new Promise((resolve,reject)=>{
  if(reg.active){resolve(reg.active);return}
  const worker=reg.installing||reg.waiting
  if(!worker){reject(Error('Offline install is not active'));return}
  const timeout=setTimeout(()=>{worker.removeEventListener('statechange',check);reject(Error('Offline install timed out'))},30_000)
  function check(){
    if(worker.state==='activated'){clearTimeout(timeout);worker.removeEventListener('statechange',check);resolve(worker)}
    else if(worker.state==='redundant'){clearTimeout(timeout);worker.removeEventListener('statechange',check);reject(Error('Offline install failed'))}
  }
  worker.addEventListener('statechange',check);check()
})
export function refreshPwaPanel(){
  for(const el of document.querySelectorAll('[data-pwa-status]'))el.textContent=!supported()?'Offline access is unavailable in this browser. Export your library to keep a portable copy.':message
  for(const el of document.querySelectorAll('[data-enable-offline]')){el.disabled=busy||!supported();el.textContent=busy?'Preparing offline lab…':ready?'Refresh offline files':'Enable offline lab'}
  for(const el of document.querySelectorAll('[data-pwa-mode]'))el.textContent=ready?'Offline ready':'Browser edition'
  for(const el of document.querySelectorAll('[data-install-app]'))el.hidden=!installPrompt
  for(const el of document.querySelectorAll('[data-remove-offline]')){el.hidden=!registration;el.disabled=busy}
  const waiting=!!registration?.waiting
  for(const selector of ['[data-apply-update]','[data-pwa-update-note]'])for(const el of document.querySelectorAll(selector))el.hidden=!waiting
  for(const el of document.querySelectorAll('[data-offline-state]'))el.textContent=navigator.onLine?'You are online. Open the live observatory when you want to see the shared world. This lab also works without a connection.':'You are offline. Your private experiments and saved library work here. Live observations need a connection.'
}
function observe(reg){
  registration=reg
  reg.addEventListener('updatefound',()=>{reg.installing?.addEventListener('statechange',()=>{refreshPwaPanel()})})
}
export function initPwa(){
  if(initialized||location.pathname.startsWith('/admin'))return
  initialized=true
  if(supported()){
    navigator.serviceWorker.getRegistration('/').then(async reg=>{
      if(!owns(reg))return
      observe(reg);ready=await status(reg.active);message=ready?'Your lab is ready offline on this device. Export your library periodically to keep a portable backup.':'Connect and enable offline access to refresh this device.';refreshPwaPanel()
    }).catch(()=>{})
    navigator.serviceWorker.addEventListener('controllerchange',()=>{if(updateRequested&&!reloading){reloading=true;location.reload()}})
  }
  window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();installPrompt=event;refreshPwaPanel()})
  window.addEventListener('appinstalled',()=>{installPrompt=null;refreshPwaPanel()})
  window.addEventListener('online',refreshPwaPanel);window.addEventListener('offline',refreshPwaPanel)
  document.addEventListener('click',async event=>{
    if(event.target.closest('[data-enable-offline]')){
      if(busy||!supported())return
      if(!navigator.onLine){message='Connect to the internet once to download the offline lab.';refreshPwaPanel();return}
      busy=true;message='Downloading the private lab for this device…';refreshPwaPanel()
      try{
        const reg=await navigator.serviceWorker.register('/service-worker.js',{scope:'/',updateViaCache:'none'});observe(reg)
        if(reg.active)await reg.update()
        if(reg.waiting){message='A new version is ready. Save your experiment, then reload to update.'}
        else{
          const active=await activeWorker(reg)
          ready=await status(active,'PREPARE_OFFLINE')
          message=ready?'Your lab is ready offline on this device. You can reload without a connection.':'Offline files could not be prepared. Stay connected and try again.'
        }
      }catch(_){message='Offline access could not be prepared. Keep this tab open or export your experiment and try again later.'}
      finally{busy=false;refreshPwaPanel()}
    }
    if(event.target.closest('[data-remove-offline]')&&registration&&!busy){
      busy=true;refreshPwaPanel()
      try{
        if(!owns(registration))throw Error('Unknown offline registration')
        await registration.unregister()
        for(const key of await caches.keys())if(key.startsWith('evolving-minds-offline-'))await caches.delete(key)
        registration=null;ready=false;message='Offline files removed. Your saved experiment library is still on this device.'
      }catch(_){message='Offline files could not be removed. Try again after closing other app tabs.'}
      finally{busy=false;refreshPwaPanel()}
    }
    if(event.target.closest('[data-install-app]')&&installPrompt){
      const prompt=installPrompt;installPrompt=null;refreshPwaPanel()
      try{await prompt.prompt()}catch(_){}
    }
    if(event.target.closest('[data-apply-update]')&&registration?.waiting){
      window.dispatchEvent(new Event('evolving-minds:before-update'));updateRequested=true;registration.waiting.postMessage('ACTIVATE_OFFLINE_UPDATE')
    }
  })
  refreshPwaPanel()
}
