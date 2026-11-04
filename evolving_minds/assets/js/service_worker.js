/* The controller injects only server-owned versioned public resource URLs. */
const CACHE=__OFFLINE_CACHE__
const RESOURCES=__OFFLINE_RESOURCES__
const PREFIX='evolving-minds-offline-'
const resources=new Map(RESOURCES.map(item=>[new URL(item.url,self.location.origin).href,item]))
const publicPages=new Set(['/','/tree','/lab','/offline'])
let preparing=null

async function validatedResponse(item){
  const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),15_000)
  try{
    const response=await fetch(new Request(item.url,{credentials:'omit',cache:'no-store',redirect:'error',signal:controller.signal}))
    if(!response.ok||response.type==='opaque')throw Error('Offline resource unavailable')
    const type=(response.headers.get('content-type')||'').toLowerCase()
    if(item.kind==='shell'){
      if(!type.startsWith('text/html')||response.headers.get('x-offline-shell')!=='1'||response.headers.get('x-offline-version')!==CACHE)throw Error('Offline shell version mismatch')
    }else{
      const valid=item.kind==='style'?type.startsWith('text/css'):item.kind==='script'?/^(?:text|application)\/javascript/.test(type):item.kind==='manifest'?type.startsWith('application/manifest+json'):type.startsWith('image/')
      if(!valid)throw Error('Unexpected offline resource type')
    }
    const reader=response.clone().body.getReader(),decoder=new TextDecoder();let size=0,text=''
    while(true){
      const chunk=await reader.read();if(chunk.done)break
      size+=chunk.value.byteLength
      if(size>1_000_000)throw Error('Offline resource exceeds its size limit')
      if(item.kind==='shell')text+=decoder.decode(chunk.value,{stream:true})
    }
    if(item.kind==='shell'&&/data-phx-session|data-phx-static|csrf-token/i.test(text+decoder.decode()))throw Error('Session-bearing HTML cannot be cached')
    return response
  }catch(error){controller.abort();throw error}
  finally{clearTimeout(timeout)}
}
function prepare(){
  if(preparing)return preparing
  preparing=(async()=>{
    const cache=await caches.open(CACHE)
    for(const item of RESOURCES){await cache.put(item.url,await validatedResponse(item))}
  })().finally(()=>{preparing=null})
  return preparing
}
async function available(){
  const cache=await caches.open(CACHE)
  for(const item of RESOURCES)if(!await cache.match(item.url))return false
  return true
}
self.addEventListener('install',event=>event.waitUntil(prepare().catch(async error=>{await caches.delete(CACHE);throw error})))
self.addEventListener('activate',event=>event.waitUntil((async()=>{
  const keys=await caches.keys()
  await Promise.all(keys.filter(key=>key.startsWith(PREFIX)&&key!==CACHE).map(key=>caches.delete(key)))
  await self.clients.claim()
})()))
self.addEventListener('message',event=>{
  if(event.data==='ACTIVATE_OFFLINE_UPDATE'){event.waitUntil(self.skipWaiting());return}
  if(!['OFFLINE_STATUS','PREPARE_OFFLINE'].includes(event.data)||!event.ports[0])return
  event.waitUntil((async()=>{
    try{if(event.data==='PREPARE_OFFLINE')await prepare();event.ports[0].postMessage({ready:await available(),version:CACHE})}
    catch(_){event.ports[0].postMessage({ready:false,version:CACHE})}
  })())
})
self.addEventListener('fetch',event=>{
  const request=event.request,url=new URL(request.url)
  // Gate before any response/caching work. Private routes, APIs, other origins and
  // non-GET requests always retain the browser's normal networking behavior.
  if(request.method!=='GET'||url.origin!==self.location.origin)return
  if(request.mode==='navigate'&&publicPages.has(url.pathname)){
    event.respondWith((async()=>{
      const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),8000)
      try{const response=await fetch(request,{signal:controller.signal});if(response.status<500)return response}
      catch(_){}finally{clearTimeout(timeout)}
      return await (await caches.open(CACHE)).match('/offline')||new Response('Connect to the internet to prepare your offline lab.',{status:503,headers:{'Content-Type':'text/plain'}})
    })());return
  }
  const item=resources.get(url.href)
  if(!item)return
  event.respondWith((async()=>{
    const cache=await caches.open(CACHE),cached=await cache.match(item.url)
    if(cached)return cached
    const response=await validatedResponse(item);await cache.put(item.url,response.clone());return response
  })())
})
