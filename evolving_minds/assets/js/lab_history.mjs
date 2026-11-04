export const HISTORY_METRICS={
  population:{label:'Population',max:60,unit:'minds',color:'#b9efd2',value:point=>point.population},
  energy:{label:'Mean energy',max:100,unit:'%',color:'#e5bb72',value:point=>point.energy},
  aggression:{label:'Mean aggression',max:100,unit:'%',color:'#f3a66b',value:point=>point.aggression*100},
  curiosity:{label:'Mean curiosity',max:100,unit:'%',color:'#75d9c5',value:point=>point.curiosity*100},
  solari:{label:'Solari population',max:60,unit:'minds',color:'#e5bb72',value:point=>point.solari},
  umbra:{label:'Umbra population',max:60,unit:'minds',color:'#c5a3ed',value:point=>point.umbra}
}
export function historyView(history,{metric='population',tick=null,follow=true}={}){
  if(!history.length)return null
  const key=Object.keys(HISTORY_METRICS).includes(metric)?metric:'population',definition=HISTORY_METRICS[key]
  const index=follow?history.length-1:Math.max(0,history.findIndex(point=>point.tick===tick))
  const first=history[0].tick,last=history.at(-1).tick,span=Math.max(1,last-first),x=point=>(point.tick-first)*100/span
  return {key,definition,index,point:history[index],first,last,marker:x(history[index]),
    points:history.map(point=>`${x(point)},${95-definition.value(point)/definition.max*85}`).join(' ')}
}
