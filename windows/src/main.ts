import {invoke} from '@tauri-apps/api/core';
import {getCurrentWindow} from '@tauri-apps/api/window';
import {listen} from '@tauri-apps/api/event';
import {demoSnapshot,isChinese,present,text,displayChoices,modelChoices,modelLabel,periodLabel,type Snapshot} from './presentation';
import './style.css';
const native=!!(window as unknown as {__TAURI_INTERNALS__?:unknown}).__TAURI_INTERNALS__;
const hover=native?getCurrentWindow().label==='hover':location.hash==='#hover';
let snapshot=demoSnapshot();let settings=native&&!hover;let pending=false;let localError='';let preferencesEditing=settings;
const root=document.querySelector<HTMLDivElement>('#app')!;
function element<K extends keyof HTMLElementTagNameMap>(tag:K,value?:string,cls?:string):HTMLElementTagNameMap[K] {
 const node=document.createElement(tag);if(value!==undefined)node.textContent=value;if(cls)node.className=cls;return node;
}
function label(key:string){return text(snapshot,key);}
function button(key:string,action:()=>Promise<void>|void,cls=''):HTMLButtonElement {
 const b=element('button',label(key),cls);b.type='button';b.onclick=()=>void run(action);return b;
}
async function run(action:()=>Promise<void>|void){if(pending)return;pending=true;localError='';try{await action();}catch(e){localError=typeof e==='object'&&e&&'code'in e?String(e.code):'http_error';}finally{pending=false;render();}}
async function command<T>(name:string,args?:Record<string,unknown>):Promise<T>{return invoke<T>(name,args);}
async function sync(){if(native && !pending && !preferencesEditing){const next=await command<Snapshot>('snapshot');if(JSON.stringify(next)!==JSON.stringify(snapshot)){snapshot=next;render();}}}
async function selectSource(source:string){
 if(native){snapshot=await command<Snapshot>('select_source',{source});}
 else {const prefs={...snapshot.preferences,source};snapshot=demoSnapshot(source);snapshot.preferences=prefs;}
}
function languageSelect(){
 const select=element('select');select.id='language';select.setAttribute('aria-label',label('language'));
 for(const [value,title] of [['system',label('system')],['en','English'],['zh','中文']]){const option=element('option',title);option.value=value;select.append(option);}
 select.value=snapshot.preferences.language;return select;
}
function sourcePicker(shell:HTMLElement){
 const sourceLabel=element('label',label('source'));sourceLabel.htmlFor='source';const select=element('select');select.id='source';
 for(const key of ['codex','claude']){const option=element('option',label(key));option.value=key;select.append(option);}
 for(const c of snapshot.connections){const option=element('option',`${c.name||'DeepSeek'} · ${c.harness==='claude'?'Claude Code':'Codex'}${c.supported?'':` · ${label('unsupported')}`}`);option.value=`api:${c.id}`;option.disabled=!c.supported;select.append(option);}
 if(!Array.from(select.options).some(o=>o.value===snapshot.preferences.source)){const option=element('option',label('source_missing'));option.value=snapshot.preferences.source;select.append(option);}
 select.value=snapshot.preferences.source;select.onchange=()=>void run(()=>selectSource(select.value));shell.append(sourceLabel,select);
}
function renderHover(){
 const view=present(snapshot);const shell=element('main',undefined,'hover-shell');const head=element('header');
 const title=element('span',view.model?`${view.name} · ${modelLabel(snapshot,view.model)}`:view.name,'hover-name');title.title=title.textContent||view.name;
 const selected=element('div',undefined,'hover-selected');
 if(view.selected&&/^\d+$/.test(view.selected))selected.append(element('span',periodLabel(Number(view.selected)),'period-badge'));
 selected.append(element('strong',view.amount,'hover-amount'));head.append(title,selected);shell.append(head);
 const data=snapshot.reading.data;
 if(data?.kind==='quota')for(const w of data.value.windows){
  const row=element('section',undefined,'hover-row');const line=element('div',undefined,'hover-line');
  const name=w.label&&w.label!=='claude'&&w.label!=='codex'?(['sonnet','opus'].includes(w.label)?label(w.label):modelLabel(snapshot,w.label)):w.minutes?periodLabel(w.minutes):label('window');
  line.append(element('span',name));
  const progress=element('progress');progress.max=100;progress.value=w.remaining??0;progress.setAttribute('aria-label',name);
  if(w.remaining==null){progress.className='unknown';progress.setAttribute('aria-hidden','true');}line.append(progress,element('strong',w.remaining==null?'—':`${w.remaining.toFixed(0)}%`));row.append(line);
  row.title=w.resetsAt?`${name} · ${label('reset')} ${new Date(w.resetsAt*1000).toLocaleString(document.documentElement.lang)}`:name;
  shell.append(row);
 }
 if(data?.kind==='balance')for(const w of data.value){const row=element('section',undefined,'hover-row');row.append(element('div',`${w.currency} ${w.total}`,'hover-wallet'),element('p',`${label('paid')} ${w.toppedUp} · ${label('granted')} ${w.granted}`,'muted'));shell.append(row);}
 if(view.stale)shell.append(element('p',label('stale'),'error'));
 if(snapshot.reading.error)shell.append(element('p',label(snapshot.reading.error.code),'error'));
 const selectedWindow=view.quotaWindow;
 const clock=(seconds:number)=>new Date(seconds*1000).toLocaleTimeString(document.documentElement.lang,{hour:'2-digit',minute:'2-digit',hour12:false});
 const updated=snapshot.reading.updated?`${label('updated')} ${clock(snapshot.reading.updated)}`:label('never');
 shell.append(element('footer',`${selectedWindow?.resetsAt?`${label('reset')} ${clock(selectedWindow.resetsAt)} · `:''}${updated}`,'muted'));
 root.append(shell);
}
function render(){
 const focused=(document.activeElement as HTMLElement|null)?.id;
 root.replaceChildren();document.documentElement.lang=isChinese(snapshot)?'zh-Hans':'en';document.body.classList.toggle('hover-mode',hover);
 document.documentElement.style.setProperty('--accent',snapshot.preferences.source==='codex'?'#338f74':snapshot.preferences.source==='claude'?'#cc785c':'#4d6bfe');
 if(hover){renderHover();return;}
 const shell=element('main',undefined,'shell');const header=element('header');const brand=element('div');
 brand.append(element('span','QUOTANEST','eyebrow'),element('h1',label('title')));const close=button('close',async()=>{if(native)await command('hide_controls');});close.id='close';header.append(brand,close);shell.append(header);
 if(!native)shell.append(element('p',label('demo'),'demo'));
 if(settings){
  const back=button('back',()=>{settings=false;preferencesEditing=false;});back.id='back';shell.append(back,element('h2',label('settings')));sourcePicker(shell);
  const form=element('form');const language=languageSelect();const languageLabel=element('label',label('language'));languageLabel.htmlFor='language';form.append(languageLabel,language);
  const path=element('input');path.id='directory';path.value=snapshot.preferences.directory;const pathLabel=element('label',label('directory'));pathLabel.htmlFor='directory';form.append(pathLabel,path);
  const autostart=element('input');autostart.type='checkbox';autostart.id='autostart';autostart.checked=snapshot.preferences.autostart;
  const autoLabel=element('label',label('autostart'),'check');autoLabel.prepend(autostart);form.append(autoLabel);
  const save=button('save',async()=>{const preferences={...snapshot.preferences,language:language.value,directory:path.value,autostart:autostart.checked};snapshot=native?await command<Snapshot>('save_preferences',{preferences}):{...snapshot,preferences};});save.id='save';
  const scan=button('scan',async()=>{snapshot=native?await command<Snapshot>('discover',{directory:path.value}):snapshot;});scan.id='scan';form.append(save,scan,element('p',label('privacy'),'muted'));
  if(snapshot.discoveryError)form.append(element('p',label(snapshot.discoveryError.code),'error'));
  const update=element('section',undefined,'settings-section');update.append(element('h2',label('checkUpdate')),element('p',label(snapshot.updateStatus),'muted'));
  const check=button('checkUpdate',async()=>{if(native){await command('check_update');await syncAfter();}else{snapshot.updateStatus='current';}});check.id='check-update';update.append(check);
  if(snapshot.update){update.append(element('p',snapshot.update.version));const install=button('install',async()=>{if(native)await command('install_update');});install.id='install-update';install.disabled=snapshot.updateStatus==='downloading';update.append(install);}
  const quit=button('quit',async()=>{if(native)await command('quit');});quit.id='quit';shell.append(form,update,element('p',label('scope'),'muted'),quit);
 }else{
  sourcePicker(shell);
  if(snapshot.preferences.source.startsWith('api:'))shell.append(element('p',label('configuration'),'muted'));
  const view=present(snapshot);const card=element('section',undefined,view.stale?'card stale':'card');card.setAttribute('aria-live','polite');
  card.append(element('span',snapshot.preferences.source==='codex'?label('codex'):snapshot.preferences.source==='claude'?label('claude'):`DeepSeek · ${label('api')}`,'eyebrow'),element('h2',view.name),element('div',view.amount,'amount'));
  if(view.quotaWindow){
   const selected=element('p',`${view.quotaWindow.label?modelLabel(snapshot,view.quotaWindow.label):view.name} · ${view.selected?periodLabel(Number(view.selected)):label('window')}`,'muted selected-reading');
   if(view.quotaWindow.resetsAt)selected.append(element('span',` · ${label('reset')} ${new Date(view.quotaWindow.resetsAt*1000).toLocaleString(document.documentElement.lang)}`));
   card.append(selected);
  }
  const models=modelChoices(snapshot);
  if(models.length>1){
   const group=element('fieldset',undefined,'model-picker');group.append(element('legend',label('model')));
   for(const choice of models){
    const option=element('label',undefined,'model-option');const radio=element('input');radio.type='radio';radio.name='model';radio.value=choice.value;radio.id=`model-${choice.value||'auto'}`;radio.checked=choice.value===view.model;
    radio.onchange=()=>void run(async()=>{if(native){snapshot=await command<Snapshot>('select_model',{value:choice.value});}else{snapshot.preferences.model={...snapshot.preferences.model,[snapshot.preferences.source]:choice.value};}});
    option.append(radio,element('span',choice.label));group.append(option);
   }
   card.append(group);
  }
  const choices=displayChoices(snapshot);
  if(choices.length>1){
   const displayLabel=element('label',label('trayDisplay'));displayLabel.htmlFor='display';const display=element('select');display.id='display';
   for(const choice of choices){const option=element('option',choice.label);option.value=choice.value;display.append(option);}
   display.value=view.selected||choices[0].value;
   display.onchange=()=>void run(async()=>{if(native){snapshot=await command<Snapshot>('select_display',{value:display.value});}else{snapshot.preferences.display={...snapshot.preferences.display,[snapshot.preferences.source]:display.value};}});
   card.append(displayLabel,display);
  }
  if(snapshot.reading.data?.kind==='quota'&&snapshot.reading.data.value.plan)card.append(element('p',`${label('plan')}: ${snapshot.reading.data.value.plan}`,'muted'));
  if(snapshot.reading.data?.kind==='balance')for(const wallet of snapshot.reading.data.value){
   const group=element('dl');const items=[[label('available'),`${wallet.currency} ${wallet.total}`],[label('paid'),`${wallet.currency} ${wallet.toppedUp}`],[label('granted'),`${wallet.currency} ${wallet.granted}`]];for(const [k,v]of items)group.append(element('dt',k),element('dd',v));card.append(group);
  }
  if(snapshot.reading.data?.kind==='quota')for(const quota of snapshot.reading.data.value.windows){
   const window=element('div',undefined,'quota-window');const period=quota.minutes?periodLabel(quota.minutes):label('window');
   if(quota.label)window.append(element('h3',['sonnet','opus'].includes(quota.label)?label(quota.label):modelLabel(snapshot,quota.label)));
   window.append(element('p',`${period} · ${quota.remaining==null?'—':`${quota.remaining.toFixed(1)}% ${label('remaining')}`}`));
   if(quota.remaining!=null){const meter=element('progress');meter.max=100;meter.value=quota.remaining;meter.setAttribute('aria-label',period);window.append(meter);}
   if(quota.resetsAt)window.append(element('p',`${label('reset')}: ${new Date(quota.resetsAt*1000).toLocaleString(document.documentElement.lang)}`,'muted'));card.append(window);
  }
  if(view.stale)card.append(element('p',label('stale'),'error'));
  if(snapshot.reading.error)card.append(element('p',label(snapshot.reading.error.code),'error'));
  const updated=snapshot.reading.updated?`${label('updated')}: ${new Date(snapshot.reading.updated*1000).toLocaleTimeString(document.documentElement.lang)}`:label('never');
  card.append(element('p',updated,'muted'));const refresh=button(snapshot.reading.refreshing?'refreshing':'refresh',async()=>{if(native){await command('refresh');snapshot=await command<Snapshot>('snapshot');}} ,'primary');refresh.id='refresh';refresh.disabled=snapshot.reading.refreshing;card.append(refresh);shell.append(card);
  const footer=element('footer');const set=button('settings',()=>{settings=true;preferencesEditing=true;});set.id='settings';footer.append(element('span',label('everyTwoMinutes'),'muted'),set);shell.append(footer);
  if(!snapshot.connections.length){shell.append(element('p',label('empty'),'muted'),button('connect',async()=>{snapshot=native?await command<Snapshot>('discover',{directory:snapshot.preferences.directory}):snapshot;}));}
  if(snapshot.discoveryError)shell.append(element('p',label(snapshot.discoveryError.code),'error'));
 }
 if(localError)shell.append(element('p',label(localError),'error'));
 root.append(shell);if(focused)document.getElementById(focused)?.focus({preventScroll:true});
}
async function syncAfter(){snapshot=await command<Snapshot>('snapshot');}
async function start(){if(native){try{snapshot=await command<Snapshot>('snapshot');}catch{localError='http_error';}}render();setInterval(()=>void sync().catch(()=>{}),1000);}
if(native){
 if(!hover)void listen('open-settings',()=>void run(async()=>{snapshot=await command<Snapshot>('snapshot');settings=true;preferencesEditing=true;}).then(()=>{root.scrollTop=0;document.getElementById('close')?.focus({preventScroll:true});}));
 void listen('snapshot-changed',()=>{if(hover)void sync().catch(()=>{});});
}
void start();
