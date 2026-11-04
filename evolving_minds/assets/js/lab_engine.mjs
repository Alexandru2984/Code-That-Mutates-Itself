export const SCENARIOS = {
  balanced: {population:24, aggression:0.5, curiosity:0.5, mutation:0.12, epoch:'normal'},
  cooperation: {population:28, aggression:0.15, curiosity:0.85, mutation:0.08, epoch:'abundance'},
  conflict: {population:28, aggression:0.9, curiosity:0.2, mutation:0.15, epoch:'normal'},
  survival: {population:20, aggression:0.5, curiosity:0.5, mutation:0.2, epoch:'famine'}
}
const clamp = (n, min=0, max=1) => Math.max(min,Math.min(max,Number.isFinite(n)?n:min))
const random = world => {
  let x=world.rng; x^=x<<13; x^=x>>>17; x^=x<<5; world.rng=x>>>0;
  return world.rng/4294967296
}
const jitter = (world,n,amount) => clamp(n+(random(world)*2-1)*amount)
const note = (world,text) => { world.events.unshift({tick:world.tick,text}); world.events.length=Math.min(world.events.length,10) }
const spawn = (world,parent=null) => {
  const id=world.nextId++;
  const e={id,name:`Mind ${String(id).padStart(3,'0')}`,tribe:parent?.tribe || (random(world)<0.5?'solari':'umbra'),
    aggression:jitter(world,parent?.aggression ?? world.config.aggression,parent?world.config.mutation:0.15),
    curiosity:jitter(world,parent?.curiosity ?? world.config.curiosity,parent?world.config.mutation:0.15),
    energy:parent?75:100,generation:parent?parent.generation+1:1,parentId:parent?.id ?? null,born:world.tick};
  world.entities.push(e);world.births++;return e
}
export function createWorld(config={}) {
  const normalized={seed:String(config.seed || 'first-light').slice(0,80),population:Math.round(clamp(Number(config.population??24),2,60)),
    aggression:clamp(Number(config.aggression??0.5)),curiosity:clamp(Number(config.curiosity??0.5)),mutation:clamp(Number(config.mutation??0.12),0,0.3),
    epoch:['normal','abundance','famine'].includes(config.epoch)?config.epoch:'normal'};
  let seed=2166136261;for(const char of normalized.seed){seed^=char.charCodeAt(0);seed=Math.imul(seed,16777619)}
  const world={version:1,config:normalized,rng:(seed>>>0)||1,tick:0,nextId:1,entities:[],births:0,deaths:0,attacks:0,cooperations:0,mutations:0,events:[],history:[]};
  for(let i=0;i<normalized.population;i++)spawn(world);
  note(world,`${normalized.population} minds begin their story.`);world.history.push(summarize(world));return world
}
export function summarize(world) {
  const living=world.entities,n=living.length;
  return {tick:world.tick,population:n,energy:n?Math.round(living.reduce((s,e)=>s+e.energy,0)/n):0,
    aggression:n?living.reduce((s,e)=>s+e.aggression,0)/n:0,curiosity:n?living.reduce((s,e)=>s+e.curiosity,0)/n:0,
    generation:Math.max(0,...living.map(e=>e.generation)),solari:living.filter(e=>e.tribe==='solari').length,
    umbra:living.filter(e=>e.tribe==='umbra').length}
}
export function stepWorld(world) {
  if(!world.entities.length)return world;
  world.tick++;
  const cost={abundance:3,normal:5,famine:8}[world.config.epoch];
  for(const actor of [...world.entities]) {
    if(actor.energy<=0)continue;
    const candidates=world.entities.filter(e=>e.id!==actor.id&&e.energy>0);
    if(candidates.length) {
      const target=candidates[Math.floor(random(world)*candidates.length)];
      if(actor.tribe!==target.tribe&&random(world)<actor.aggression) {
        world.attacks++;
        if(target.aggression>0.5){actor.energy-=10;target.energy-=10}
        else {actor.energy+=8;target.energy-=6}
      } else {
        world.cooperations++;
        const bonus=2+Math.round((actor.curiosity+target.curiosity)*2);
        actor.energy+=bonus;target.energy+=bonus;
      }
    }
    actor.energy-=cost;
    if(random(world)<0.08) {
      actor.aggression=jitter(world,actor.aggression,world.config.mutation);
      actor.curiosity=jitter(world,actor.curiosity,world.config.mutation);world.mutations++;
    }
    actor.energy=clamp(actor.energy,0,100);
  }
  for(const e of world.entities)e.energy=clamp(e.energy,0,100);
  const dead=world.entities.filter(e=>e.energy<=0);world.deaths+=dead.length;
  if(dead.length)note(world,`${dead.length} ${dead.length===1?'mind reaches':'minds reach'} the end of life.`);
  world.entities=world.entities.filter(e=>e.energy>0);
  if(world.entities.length&&world.entities.length<60&&world.tick%2===0) {
    const candidates=world.entities.filter(e=>e.energy>=45);
    if(candidates.length) {
      let pick=random(world)*candidates.reduce((sum,e)=>sum+e.energy,0);
      const parent=candidates.find(e=>(pick-=e.energy)<=0)||candidates[candidates.length-1];
      const child=spawn(world,parent);parent.energy-=8;note(world,`${child.name} inherits generation ${child.generation} from ${parent.name}.`);
    }
  }
  if(!world.entities.length)note(world,'Extinction. Change the conditions and try a new experiment.');
  world.history.push(summarize(world));if(world.history.length>120)world.history.shift();return world
}

export function restoreWorld(data) {
  const invalid=()=>{throw new Error('This is not a valid version 1 experiment snapshot.')};
  const int=(n,min=0,max=1_000_000_000)=>Number.isSafeInteger(n)&&n>=min&&n<=max;
  const number=(n,min=0,max=1)=>Number.isFinite(n)&&n>=min&&n<=max;
  const text=(s,max)=>typeof s==='string'&&s.length>0&&s.length<=max;
  if(!data||data.version!==1||!data.config||!int(data.tick)||!int(data.rng,1,4294967295)||!int(data.nextId,1))invalid();
  const c=data.config;
  if(!text(c.seed,80)||!int(c.population,2,60)||!number(c.aggression)||!number(c.curiosity)||!number(c.mutation,0,.3)||!['normal','abundance','famine'].includes(c.epoch))invalid();
  if(!Array.isArray(data.entities)||data.entities.length>60||!Array.isArray(data.history)||data.history.length<1||data.history.length>120||!Array.isArray(data.events)||data.events.length>10)invalid();
  for(const key of ['births','deaths','attacks','cooperations','mutations'])if(!int(data[key]))invalid();
  if(data.births-data.deaths!==data.entities.length)invalid();
  const entities=data.entities.map(e=>{
    if(!e||!int(e.id,1)||e.id>=data.nextId||!text(e.name,32)||!['solari','umbra'].includes(e.tribe)||!number(e.aggression)||!number(e.curiosity)||!number(e.energy,Number.MIN_VALUE,100)||!int(e.generation,1)||!int(e.born,0,data.tick)||(e.parentId!==null&&(!int(e.parentId,1)||e.parentId>=e.id)))invalid();
    return {id:e.id,name:e.name,tribe:e.tribe,aggression:e.aggression,curiosity:e.curiosity,energy:e.energy,generation:e.generation,parentId:e.parentId,born:e.born}
  });
  if(new Set(entities.map(e=>e.id)).size!==entities.length)invalid();
  let previous=-1;
  const history=data.history.map(p=>{
    if(!p||!int(p.tick,0,data.tick)||p.tick<previous||!int(p.population,0,60)||!int(p.energy,0,100)||!number(p.aggression)||!number(p.curiosity)||!int(p.generation)||!int(p.solari,0,60)||!int(p.umbra,0,60)||p.solari+p.umbra!==p.population)invalid();
    previous=p.tick;return {tick:p.tick,population:p.population,energy:p.energy,aggression:p.aggression,curiosity:p.curiosity,generation:p.generation,solari:p.solari,umbra:p.umbra}
  });
  const events=data.events.map(e=>{if(!e||!int(e.tick,0,data.tick)||!text(e.text,240))invalid();return {tick:e.tick,text:e.text}});
  return {version:1,config:{seed:c.seed,population:c.population,aggression:c.aggression,curiosity:c.curiosity,mutation:c.mutation,epoch:c.epoch},rng:data.rng,tick:data.tick,nextId:data.nextId,entities,births:data.births,deaths:data.deaths,attacks:data.attacks,cooperations:data.cooperations,mutations:data.mutations,events,history}
}
