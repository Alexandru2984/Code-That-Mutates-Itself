import {createWorld,stepWorld,summarize,restoreWorld,SCENARIOS} from './lab_engine.mjs'

export const EvolutionLab = {
  mounted() {
    this.world=createWorld();this.running=false;this.speed=2;this.selected=null;this.elapsed=0;this.last=performance.now();this.destroyedFlag=false;
    this.canvas=this.el.querySelector('canvas');this.ctx=this.canvas.getContext('2d');
    this.form=this.el.querySelector('form');this.el.querySelector('fieldset').disabled=false;
    this.readConfig=()=>Object.fromEntries(new FormData(this.form));
    this.onSubmit=e=>{e.preventDefault();this.world=createWorld(this.readConfig());this.selected=null;this.running=false;this.elapsed=0;this.render()};
    this.form.addEventListener('submit',this.onSubmit);
    this.notice=text=>{this.el.querySelector('[data-lab-notice]').textContent=text};
    this.loadSnapshot=data=>{this.world=restoreWorld(data);this.running=false;this.elapsed=0;this.selected=null;for(const [key,value] of Object.entries(this.world.config)){if(this.form.elements[key])this.form.elements[key].value=value}this.render()};
    this.onFile=async e=>{
      const file=e.target.files?.[0];if(!file)return;
      try{if(file.size>512000)throw Error('Snapshot files must be smaller than 500 KB.');this.loadSnapshot(JSON.parse(await file.text()));this.notice('Experiment imported and paused. Continue whenever you are ready.')}catch(error){this.notice(error instanceof SyntaxError?'This file is not valid JSON.':error.message)}
      e.target.value='';
    };
    this.fileInput=this.el.querySelector('[data-import]');this.fileInput.addEventListener('change',this.onFile);
    this.onClick=e=>{
      const action=e.target.closest('[data-action]')?.dataset.action;
      if(action==='play'){if(this.world.entities.length)this.running=!this.running;this.render()}
      if(action==='step'){this.running=false;stepWorld(this.world);this.render()}
      if(action==='save'){
        try{localStorage.setItem('evolving-minds:lab:v1',JSON.stringify(this.world));this.notice('Experiment saved in this browser. You can leave and load it later.')}catch(_){this.notice('Browser storage is unavailable. Export the experiment to keep it.')}
      }
      if(action==='load'){
        try{const raw=localStorage.getItem('evolving-minds:lab:v1');if(!raw){this.notice('No saved experiment in this browser yet.');return}this.loadSnapshot(JSON.parse(raw));this.notice('Saved experiment loaded and paused.')}catch(_){this.notice('The saved experiment could not be read. Import a valid JSON snapshot instead.')}
      }
      if(action==='export'){
        const url=URL.createObjectURL(new Blob([JSON.stringify(this.world,null,2)],{type:'application/json'}));
        const link=document.createElement('a');link.href=url;link.download='evolving-minds-lab.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000)
      }
      const scenario=e.target.closest('[data-scenario]')?.dataset.scenario;
      if(SCENARIOS[scenario]){for(const [key,value]of Object.entries(SCENARIOS[scenario]))this.form.elements[key].value=value;this.world=createWorld({...this.readConfig(),...SCENARIOS[scenario]});this.selected=null;this.running=false;this.elapsed=0;this.render()}
    };
    this.el.addEventListener('click',this.onClick);
    this.onInput=e=>{
      if(e.target.name==='speed')this.speed=Number(e.target.value);
      const output=e.target.closest('label')?.querySelector('output');
      if(output)output.textContent=e.target.name==='population'?e.target.value:e.target.name==='speed'?`${e.target.value}×`:`${Math.round(Number(e.target.value)*100)}%`;
    };
    this.el.addEventListener('input',this.onInput);
    this.inspect=this.el.querySelector('[data-inspect]');this.onInspect=()=>{this.selected=Number(this.inspect.value)||null;this.render()};this.inspect.addEventListener('change',this.onInspect);
    this.onCanvas=e=>{const r=this.canvas.getBoundingClientRect();const x=e.clientX-r.left,y=e.clientY-r.top;let best=null,distance=25;for(const mind of this.world.entities){const dx=20+mind.aggression*(r.width-40)-x,dy=r.height-20-mind.curiosity*(r.height-40)-y;const d=Math.hypot(dx,dy);if(d<distance){best=mind;distance=d}}this.selected=best?.id??null;this.render()};
    this.canvas.addEventListener('click',this.onCanvas);
    this.resize=new ResizeObserver(()=>this.render());this.resize.observe(this.canvas.parentElement);
    this.animate=time=>{if(this.destroyedFlag)return;const delta=Math.min(time-this.last,250);this.last=time;if(this.running&&!document.hidden){this.elapsed+=delta;let changed=false;while(this.elapsed>=1000/this.speed){this.elapsed-=1000/this.speed;stepWorld(this.world);changed=true}if(changed)this.render()}else this.elapsed=0;this.frame=requestAnimationFrame(this.animate)};
    this.frame=requestAnimationFrame(this.animate);this.render();
  },
  render() {
    if(!this.world.entities.length)this.running=false;
    const stats=summarize(this.world);
    for(const el of this.el.querySelectorAll('[data-stat]'))el.textContent=stats[el.dataset.stat]??this.world[el.dataset.stat]??0;
    const play=this.el.querySelector('[data-action=play]');play.disabled=this.world.entities.length===0;this.el.querySelector('[data-action=step]').disabled=this.world.entities.length===0;play.textContent=this.running?'Ⅱ Pause experiment':'▶ Run experiment';play.setAttribute('aria-pressed',String(this.running));
    for(const input of this.form.querySelectorAll('input[type=range]')){const output=input.closest('label')?.querySelector('output');if(output)output.textContent=input.name==='population'?input.value:`${Math.round(Number(input.value)*100)}%`}
    const ids=this.world.entities.map(e=>e.id).join(',');
    if(this.inspect.dataset.ids!==ids){this.inspect.replaceChildren(new Option('Choose a mind to inspect',''));for(const e of this.world.entities)this.inspect.add(new Option(`${e.name} · ${e.tribe} · Gen ${e.generation}`,e.id));this.inspect.dataset.ids=ids}
    this.inspect.value=this.selected||'';
    const selected=this.world.entities.find(e=>e.id===this.selected);
    this.el.querySelector('[data-mind-detail]').textContent=selected?`${selected.name} · ${selected.tribe} · Generation ${selected.generation} · Energy ${Math.round(selected.energy)}% · Aggression ${Math.round(selected.aggression*100)}% · Curiosity ${Math.round(selected.curiosity*100)}%`:'Select a dot or choose a mind above to inspect its traits.';
    this.el.querySelector('[data-lab-events]').replaceChildren(...this.world.events.map(event=>{const li=document.createElement('li');li.textContent=`Step ${event.tick} · ${event.text}`;return li}));
    const points=this.world.history.map((p,i)=>`${i*100/Math.max(this.world.history.length-1,1)},${95-p.population/60*85}`).join(' ');this.el.querySelector('[data-lab-chart]').setAttribute('points',points);
    const canvas=this.canvas,context=this.ctx,rect=canvas.parentElement.getBoundingClientRect(),w=Math.max(rect.width,100),h=360,dpr=Math.min(window.devicePixelRatio||1,2);
    canvas.width=w*dpr;canvas.height=h*dpr;canvas.style.width=`${w}px`;canvas.style.height=`${h}px`;context.setTransform(dpr,0,0,dpr,0,0);context.clearRect(0,0,w,h);
    context.strokeStyle='#ffffff12';context.lineWidth=1;context.beginPath();context.moveTo(w/2,0);context.lineTo(w/2,h);context.moveTo(0,h/2);context.lineTo(w,h/2);context.stroke();
    for(const e of this.world.entities){const x=20+e.aggression*(w-40),y=h-20-e.curiosity*(h-40);context.beginPath();context.arc(x,y,4+e.energy/100*6,0,Math.PI*2);context.fillStyle=e.tribe==='solari'?'#e5bb72':'#c5a3ed';context.globalAlpha=.45+e.energy/180;context.fill();if(e.id===this.selected){context.globalAlpha=1;context.strokeStyle='#eef2ed';context.lineWidth=2;context.stroke()}}
    context.globalAlpha=1;
    canvas.setAttribute('aria-label',`${stats.population} minds on the trait map. Aggression increases rightward, curiosity upward. Use the inspect menu for keyboard access.`);
    this.el.querySelector('[data-extinct]').hidden=this.world.entities.length>0;
  },
  destroyed() {
    this.destroyedFlag=true;cancelAnimationFrame(this.frame);this.resize.disconnect();this.el.removeEventListener('click',this.onClick);this.el.removeEventListener('input',this.onInput);this.form.removeEventListener('submit',this.onSubmit);this.canvas.removeEventListener('click',this.onCanvas);this.inspect.removeEventListener('change',this.onInspect);this.fileInput.removeEventListener('change',this.onFile);
  }
}
