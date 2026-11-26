import test from 'node:test';
import assert from 'node:assert/strict';
import { text, present, demoSnapshot, modelChoices, displayChoices } from '../src/presentation.js';
test('Chinese and English render the same selected source without network calls',()=>{
 const s=demoSnapshot(); s.preferences.language='en';
 assert.equal(text(s,'refresh'),'Refresh now'); assert.match(present(s).amount,/18.60/);
 s.preferences.language='zh'; assert.equal(text(s,'refresh'),'立即刷新');
 assert.match(present(demoSnapshot('codex')).amount,/76/);
});
test('unknown is never zero and stale reading keeps its timestamp',()=>{
 const s=demoSnapshot(); s.reading.data=null; assert.equal(present(s).amount,'—');
 s.reading=demoSnapshot().reading; s.reading.error={code:'network',retryAt:null};
 assert.equal(present(s).stale,true); assert.match(present(s).amount,/18.60/); assert.equal(present(s).updated,s.reading.updated);
});
test('configuration names remain data and do not become markup',()=>{
 const s=demoSnapshot();s.connections[0].name='<img src=x onerror=alert(1)>';
 assert.equal(present(s).name,s.connections[0].name);
});
test('Claude is distinct from Claude Code API connections and weekly summary uses tightest group',()=>{
 const s=demoSnapshot('claude');
 assert.equal(present(s).name,'Claude');assert.equal(present(s).amount,'82%');
 s.preferences.display={claude:'10080'};assert.equal(present(s).amount,'39%');
 assert.equal(text(s,'claude'),'Claude · Subscription quota');
 s.preferences.language='zh';assert.match(text(s,'claude'),/套餐/);
});
test('missing primary duration uses the first explicit period, matching tray summary',()=>{
 const s=demoSnapshot('codex');s.reading.data={kind:'quota',value:{plan:null,windows:[{remaining:80,minutes:null,resetsAt:null},{remaining:50,minutes:10080,resetsAt:null}]}};
 assert.equal(present(s).amount,'50%');assert.equal(present(s).selected,'10080');
});
test('compact reset time belongs to the quota group supplying the displayed minimum',()=>{
 const s=demoSnapshot('claude');s.preferences.display={claude:'10080'};
 if(s.reading.data?.kind!=='quota')throw new Error('quota fixture missing');
 s.reading.data.value.windows[1].resetsAt=111;
 s.reading.data.value.windows[3].resetsAt=222;
 assert.equal(present(s).amount,'39%');assert.equal(present(s).quotaWindow?.resetsAt,222);
 s.reading.data.value.windows[3].remaining=null;
 assert.equal(present(s).amount,'61%');assert.equal(present(s).quotaWindow?.resetsAt,111);
 assert.equal(present(demoSnapshot()).quotaWindow,undefined);
});

test('selected model isolates balance and reset and falls back to its available period',()=>{
 const s=demoSnapshot('claude');
 Object.assign(s.preferences,{model:{claude:'sonnet'},display:{claude:'300'}});
 if(s.reading.data?.kind!=='quota')throw new Error('quota fixture missing');
 s.reading.data.value.windows[2].resetsAt=333;
 assert.equal(present(s).amount,'93%');assert.equal(present(s).selected,'10080');assert.equal(present(s).quotaWindow?.resetsAt,333);
 s.reading.data.value.windows.reverse();assert.equal(present(s).amount,'93%');
 Object.assign(s.preferences,{model:{claude:'opus'}});assert.equal(present(s).amount,'39%');
 Object.assign(s.preferences,{model:{claude:'claude'},display:{claude:'10080'}});assert.equal(present(s).amount,'61%');
});
test('unknown selected model never borrows quota and deleted model returns to automatic',()=>{
 const s=demoSnapshot('claude');Object.assign(s.preferences,{model:{claude:'sonnet'},display:{claude:'10080'}});
 if(s.reading.data?.kind!=='quota')throw new Error('quota fixture missing');
 s.reading.data.value.windows[2].remaining=null;
 assert.equal(present(s).amount,'—');assert.equal(present(s).model,'sonnet');
 s.reading.data.value.windows=s.reading.data.value.windows.filter(w=>w.label!=='sonnet');
 assert.equal(present(s).amount,'39%');assert.equal(present(s).model,'');
});
test('model preferences survive serialization and remain source scoped',()=>{
 const s=demoSnapshot('claude');Object.assign(s.preferences,{model:{claude:'sonnet',codex:'other'},display:{claude:'10080',codex:'300'}});
 const restored=JSON.parse(JSON.stringify(s));assert.equal(present(restored).amount,'93%');
 restored.preferences.source='codex';restored.reading=demoSnapshot('codex').reading;
 assert.equal(present(restored).amount,'76%');
});

test('radio options use stable model identity and periods belong to selected model',()=>{
 const s=demoSnapshot('claude');s.preferences.model={claude:'sonnet'};
 assert.deepEqual(modelChoices(s).map(c=>c.value),['','claude','opus','sonnet']);
 assert.deepEqual(displayChoices(s),[{value:'10080',label:'7d'}]);
 assert.equal(present(s).model,'sonnet');
 s.preferences.model={claude:'missing'};assert.equal(present(s).model,'');
 assert.deepEqual(displayChoices(s).map(c=>c.value),['300','10080']);
});

test('Codex automatic stays on main while explicit external models are independent',()=>{
 const s=demoSnapshot('codex');s.reading.data={kind:'quota',value:{plan:'Plus',windows:[{label:'codex-spark',remaining:93,minutes:10080,resetsAt:333},{label:'codex',remaining:76,minutes:300,resetsAt:111},{label:'external-model',remaining:null,minutes:300,resetsAt:222}]}};
 assert.equal(present(s).amount,'76%');
 s.preferences.display={codex:'10080'};assert.equal(present(s).amount,'76%');
 s.preferences.model={codex:'codex-spark'};
 assert.equal(present(s).amount,'93%');assert.equal(present(s).quotaWindow?.resetsAt,333);
 assert.ok(modelChoices(s).some(c=>c.value==='external-model'&&c.label==='external-model'));
 s.preferences.model={codex:'external-model'};assert.equal(present(s).amount,'—');
 s.preferences.model={codex:'gone'};assert.equal(present(s).amount,'76%');
});
test('automatic periods skip unknown usage while explicit model remains unknown',()=>{
 const s=demoSnapshot('claude');s.reading.data={kind:'quota',value:{plan:null,windows:[{label:'claude',remaining:null,minutes:300,resetsAt:111},{label:'claude',remaining:61,minutes:10080,resetsAt:222}]}};
 assert.equal(present(s).amount,'61%');assert.equal(present(s).selected,'10080');
 s.preferences.model={claude:'claude'};
 assert.equal(present(s).amount,'—');assert.equal(present(s).selected,'300');
});
test('Fable is selectable with its own weekly balance and reset in both languages',()=>{
 const s=demoSnapshot('claude');
 if(s.reading.data?.kind!=='quota')throw new Error('quota data missing');
 s.reading.data.value.windows.push({label:'fable',remaining:35,minutes:10080,resetsAt:1793354400});
 assert.ok(modelChoices(s).some(c=>c.value==='fable'&&c.label==='Fable'));
 s.preferences.model={claude:'fable'};
 assert.equal(present(s).amount,'35%');assert.equal(present(s).quotaWindow?.resetsAt,1793354400);
 assert.deepEqual(displayChoices(s),[{value:'10080',label:'7d'}]);
 assert.equal(text(s,'fable'),'Fable weekly');
 s.preferences.language='zh';assert.equal(text(s,'fable'),'Fable 周额度');
});
