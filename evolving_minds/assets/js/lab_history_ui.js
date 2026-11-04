import {historyView} from './lab_history.mjs'
export function mountHistory(hook){
  const root=hook.el,metric=root.querySelector('[data-history-metric]'),slider=root.querySelector('[data-history-step]'),followButton=root.querySelector('[data-history-follow]'),chart=root.querySelector('[data-history-chart]')
  let follow=true,tick=null,world=null
  const update=()=>{
    if(world!==hook.world){world=hook.world;follow=true;tick=null}
    const view=historyView(hook.world.history,{metric:metric.value,tick,follow});if(!view)return
    tick=view.point.tick;slider.max=hook.world.history.length-1;slider.value=view.index;slider.disabled=hook.world.history.length<2
    const label=`Step ${tick}, ${view.definition.label.toLowerCase()} ${Math.round(view.definition.value(view.point))} ${view.definition.unit}`
    slider.setAttribute('aria-valuetext',label);root.querySelector('[data-history-caption]').textContent=`Step ${tick} · ${view.definition.label}`
    root.querySelector('[data-history-value]').textContent=`${Math.round(view.definition.value(view.point))} ${view.definition.unit}`
    root.querySelector('[data-history-axis]').textContent=`Step ${view.first} → ${view.last} · Scale 0–${view.definition.max} ${view.definition.unit}`
    const hasTrace=hook.world.history.length>1;chart.style.display=hasTrace?'':'none';root.querySelector('[data-history-empty]').hidden=hasTrace
    const line=root.querySelector('[data-lab-chart]');line.setAttribute('points',view.points);line.setAttribute('stroke',view.definition.color)
    const marker=root.querySelector('[data-history-marker]');marker.setAttribute('x1',view.marker);marker.setAttribute('x2',view.marker)
    chart.setAttribute('aria-label',`${view.definition.label} history from step ${view.first} to ${view.last}. ${label}. Use the recorded-step slider to inspect measurements.`)
    for(const [key,value]of Object.entries(view.point)){const target=root.querySelector(`[data-history-stat="${key}"]`);if(target)target.textContent=key==='aggression'||key==='curiosity'?`${Math.round(value*100)}%`:key==='energy'?`${value}%`:value}
    followButton.setAttribute('aria-pressed',String(follow));followButton.textContent=follow?'✓ Following latest':'Follow latest →'
  }
  const onMetric=()=>update(),onStep=()=>{follow=false;tick=hook.world.history[Number(slider.value)]?.tick??null;update()},onFollow=()=>{follow=true;update()}
  const onChart=event=>{const rect=chart.getBoundingClientRect(),ratio=Math.max(0,Math.min(1,(event.clientX-rect.left)/rect.width)),history=hook.world.history,target=history[0].tick+ratio*(history.at(-1).tick-history[0].tick);follow=false;tick=history.reduce((best,point)=>Math.abs(point.tick-target)<Math.abs(best.tick-target)?point:best).tick;update()}
  metric.addEventListener('change',onMetric);slider.addEventListener('input',onStep);followButton.addEventListener('click',onFollow);chart.addEventListener('click',onChart);update()
  return {update,destroy(){metric.removeEventListener('change',onMetric);slider.removeEventListener('input',onStep);followButton.removeEventListener('click',onFollow);chart.removeEventListener('click',onChart)}}
}
