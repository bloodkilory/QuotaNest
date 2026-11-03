export interface AppError { code:string; retryAt:number|null }
export interface Wallet { currency:string;total:string;granted:string;toppedUp:string }
export interface Quota { plan:string|null;windows:{label?:string|null;remaining:number|null;minutes:number|null;resetsAt:number|null}[] }
export type Data = {kind:'balance';value:Wallet[]} | {kind:'quota';value:Quota};
export interface Reading {data:Data|null;updated:number|null;error:AppError|null;refreshing:boolean}
export interface Connection {id:string;name:string;harness:string;origin:string;supported:boolean}
export interface Preferences {source:string;language:string;directory:string;autostart:boolean;display?:Record<string,string>;model?:Record<string,string>}
export interface Snapshot {preferences:Preferences;connections:Connection[];reading:Reading;discoveryError:AppError|null;update:{version:string;name:string;url:string;checksumUrl:string}|null;updateStatus:string}
const copy:Record<string,[string,string]>={
 model:['Tray model','托盘模型'],autoModel:['Automatic · lowest remaining','自动 · 最低剩余'],
 subscription:['Subscription quota','套餐余量'],
 close:['Close','关闭'],
 title:['QuotaNest','余度 QuotaNest'], source:['Display source','显示来源'],
 claude:['Claude · Subscription quota','Claude · 套餐余量'],claudeGroup:['Claude subscription','Claude 总额度'],sonnet:['Sonnet weekly','Sonnet 周额度'],opus:['Opus weekly','Opus 周额度'],trayDisplay:['Tray reading','托盘读数'],plan:['Plan','套餐'],
 codex:['Codex · Subscription quota','Codex · 套餐余量'], api:['API balance','API 余额'], configuration:['Saved configuration, not observed session routing','已保存配置，不代表当前会话实际路由'],
 available:['Available balance','可用余额'],granted:['Granted','赠送余额'],paid:['Topped up','充值余额'],
 refresh:['Refresh now','立即刷新'],refreshing:['Refreshing…','正在查询…'],updated:['Updated','更新于'],never:['No successful reading yet','尚无成功查询'],stale:['Outdated reading','读数已过期'],
 everyTwoMinutes:['Refreshes every 2 minutes','每 2 分钟刷新'],settings:['Settings','设置'],back:['Back','返回'],language:['Language','语言'],system:['Follow system','跟随系统'],
 connect:['Connect CC Switch','连接 CC Switch'],directory:['CC Switch data directory','CC Switch 数据目录'],scan:['Read saved connections','读取已有连接'],
 empty:['Connect CC Switch to select a DeepSeek official API connection.','连接 CC Switch 后，可选择 DeepSeek 官方 API 配置。'],
 unsupported:['Balance query not supported','尚未适配余额查询'],autostart:['Launch at sign-in','登录时启动'],save:['Save settings','保存设置'],
 checkUpdate:['Check for updates','检查应用更新'],install:['Download & install','下载并安装'],idle:['Checks on startup and when you click','启动时和点击时检查更新'],
 checking:['Checking GitHub Releases…','正在检查 GitHub 正式版…'],current:['No newer Windows release available','暂无更新的 Windows 正式版'],availableUpdate:['A Windows update is available','有新的 Windows 正式版'],
 downloading:['Downloading and verifying SHA-256…','正在下载并校验 SHA-256…'],quit:['Quit QuotaNest','退出余度'],
 demo:['Preview · demo data · no account access','预览 · 演示数据 · 不读取账号'],window:['Quota window','额度窗口'],remaining:['remaining','剩余'],reset:['Resets','重置于'],
 privacy:['Reads selected local configuration. Keys stay in the backend.','只读取所选本机配置，凭据不进入界面。'],scope:['Supported: native Windows Codex, Claude subscription and DeepSeek API. WSL and other official providers are not supported yet.','支持范围：原生 Windows Codex、Claude 官方套餐与 DeepSeek API；暂不支持 WSL 和其他官方平台。'],
 claude_login_missing:['No Claude subscription login. Run claude auth login in official native Claude Code.','未找到 Claude 订阅登录，请在原生官方 Claude Code 运行 claude auth login。'],claude_login_expired:['Claude login expired. Open Claude Code and sign in again, then refresh.','Claude 登录已过期，请回到官方 Claude Code 更新登录后刷新。'],claude_scope_missing:['Claude login lacks user:profile access. Sign in again with a subscription account.','Claude 登录缺少 user:profile 权限，请用订阅账号重新登录。'],claude_login_unreadable:['Cannot read Claude login. Check the official configuration file and permissions.','无法读取 Claude 登录，请检查官方配置文件及读取权限。'],claude_config_invalid:['CLAUDE_CONFIG_DIR must be an absolute directory path.','CLAUDE_CONFIG_DIR 必须是绝对目录路径。'],
 network:['Connection failed. Check your proxy/network, then refresh.','连接失败，请检查代理或网络后刷新。'],server:['Service temporarily unavailable.','服务暂不可用。'],unauthorized:['Sign-in expired. Sign in again in the original tool.','登录或凭据已失效，请在原工具重新登录或配置。'],
 forbidden:['This account cannot read the requested quota/balance.','当前账号无权读取该额度或余额。'],rate_limited:['Rate limited. Waiting until the service allows another check.','查询受限，等待服务允许后再检查。'],
 source_missing:['CC Switch database not found. Choose its data directory.','未找到 CC Switch 数据库，请选择其数据目录。'],source_busy:['CC Switch is updating. Keeping the last reading.','CC Switch 正在更新，保留上次读数。'],
 invalid_source:['CC Switch configuration cannot be read. Reconnect it.','无法读取 CC Switch 配置，请重新连接。'],incompatible_source:['CC Switch schema not supported (18–20 required).','CC Switch 数据版本不兼容，仅支持 schema 18–20。'],
 unsupported_source:['Only official DeepSeek API balance queries are supported.','仅支持 DeepSeek 官方 API 余额查询。'],credentials_missing:['No usable saved credentials. Configure them in CC Switch.','没有可用的已有凭据，请在 CC Switch 中配置。'],
 source_changed:['Connection changed; old balance cleared. Refresh again.','连接已变化，旧余额已清除，请重新刷新。'],codex_missing:['Native codex.exe not found. Install the official Codex CLI and sign in.','未找到原生 codex.exe，请安装官方 Codex CLI 并登录。'],
 protocol:['Codex returned an invalid response. Update its official CLI and retry.','Codex 响应无效，请更新官方 CLI 后重试。'],invalid_quota:['No valid quota returned; unknown is not zero.','没有返回有效额度，未知额度不会显示为零。'],
 invalid_balance:['No valid balance returned; unknown is not zero.','没有返回有效余额，未知余额不会显示为零。'],response_too_large:['Response exceeded the size limit.','响应超出大小限制。'],redirect_refused:['Redirect refused; credentials were not forwarded.','已拒绝重定向，没有转发凭据。'],
 invalid_update:['Windows release assets are incomplete or invalid.','Windows 正式版附件不完整或无效。'],checksum_mismatch:['SHA-256 mismatch. Installation stopped.','SHA-256 校验不匹配，已停止安装。'],update_download:['Could not download the Windows installer.','Windows 安装包下载失败。'],
 preferences_write:['Could not save local settings.','无法保存本机设置。'],autostart_failed:['Could not update launch-at-sign-in setting.','无法更新登录启动设置。'],http_error:['The service returned an unexpected status.','服务返回异常状态。'],update_failed:['Could not check for updates. Retry later.','更新检查失败，请稍后重试。']
};
export function isChinese(s:Snapshot):boolean {return s.preferences.language==='zh' || (s.preferences.language==='system' && (typeof navigator!=='undefined' && navigator.language.startsWith('zh')));}
export function text(s:Snapshot,key:string):string {return copy[key]?.[isChinese(s)?1:0]??copy.http_error[isChinese(s)?1:0];}
export function modelLabel(s:Snapshot,value:string):string {return value==='codex'?'Codex':value==='claude'?text(s,'claudeGroup'):value==='sonnet'?'Sonnet':value==='opus'?'Opus':value;}
export function modelChoices(s:Snapshot):{value:string;label:string}[] {
 const data=s.reading.data;
 if(data?.kind!=='quota')return [];
 const models=[...new Set(data.value.windows.flatMap(w=>w.label?[w.label]:[]))].sort();
 return models.length?[{value:'',label:text(s,'autoModel')},...models.map(value=>({value,label:modelLabel(s,value)}))]:[];
}
export function selectedModel(s:Snapshot):string {
 const saved=s.preferences.model?.[s.preferences.source];
 return modelChoices(s).find(o=>o.value===saved)?.value||'';
}
function modelWindows(s:Snapshot):Quota['windows'] {
 const data=s.reading.data;const model=selectedModel(s);
 return data?.kind==='quota'?data.value.windows.filter(w=>model?w.label===model:w.remaining!=null&&(s.preferences.source!=='codex'||!w.label||w.label==='codex')):[];
}
export function displayChoices(s:Snapshot):{value:string;label:string}[] {
 const data=s.reading.data;
 if(data?.kind==='balance')return data.value.map(w=>({value:w.currency,label:w.currency}));
 if(data?.kind==='quota')return [...new Set(modelWindows(s).flatMap(w=>w.minutes==null?[]:[w.minutes]))].sort((a,b)=>a-b).map(m=>({value:String(m),label:periodLabel(m)}));
 return [];
}
export function periodLabel(minutes:number):string {return minutes>=1440?`${minutes/1440}d`:minutes>=60?`${minutes/60}h`:`${minutes}m`;}
export function present(s:Snapshot) {
 const c=s.connections.find(c=>s.preferences.source===`api:${c.id}`);
 const data=s.reading.data;const options=displayChoices(s);const saved=s.preferences.display?.[s.preferences.source];
 const selected=options.find(o=>o.value===saved)?.value||options[0]?.value;
 let amount='—';let quotaWindow:Quota['windows'][number]|undefined;
 if(data?.kind==='balance'){const wallet=data.value.find(w=>w.currency===selected)||data.value[0];if(wallet)amount=`${wallet.currency} ${wallet.total}`;}
 if(data?.kind==='quota'){
  for(const w of modelWindows(s).filter(w=>selected==null||String(w.minutes)===selected)){
   if(!quotaWindow||(w.remaining!=null&&(quotaWindow.remaining==null||w.remaining<quotaWindow.remaining)))quotaWindow=w;
  }
  if(quotaWindow?.remaining!=null)amount=`${quotaWindow.remaining.toFixed(0)}%`;
 }
 return {name:s.preferences.source==='codex'?'Codex':s.preferences.source==='claude'?'Claude':c?.name||'DeepSeek',amount,selected,model:selectedModel(s),quotaWindow,stale:!!s.reading.error && !!data,updated:s.reading.updated};
}
export function demoSnapshot(source='api:claude|demo'):Snapshot {
 return {preferences:{source,language:'en',directory:'C:\\Users\\Demo\\.cc-switch',autostart:false},connections:[{id:'claude|demo',name:'DeepSeek',harness:'claude',origin:'https://api.deepseek.com',supported:true}],reading:{data:source==='claude'?{kind:'quota',value:{plan:'Max',windows:[{label:'claude',remaining:82,minutes:300,resetsAt:1792792800},{label:'claude',remaining:61,minutes:10080,resetsAt:null},{label:'sonnet',remaining:93,minutes:10080,resetsAt:null},{label:'opus',remaining:39,minutes:10080,resetsAt:null}]}}:source==='codex'?{kind:'quota',value:{plan:'Plus',windows:[{label:'codex',remaining:76,minutes:300,resetsAt:1792749600},{label:'codex',remaining:62,minutes:10080,resetsAt:1793318400},{label:'codex-spark',remaining:91,minutes:10080,resetsAt:1793354400},{label:'external-model',remaining:null,minutes:300,resetsAt:null}]}}:{kind:'balance',value:[{currency:'CNY',total:'18.60',granted:'3.60',toppedUp:'15.00'},{currency:'USD',total:'3.20',granted:'0.20',toppedUp:'3.00'}]},updated:1792731600,error:null,refreshing:false},discoveryError:null,update:null,updateStatus:'idle'};
}
