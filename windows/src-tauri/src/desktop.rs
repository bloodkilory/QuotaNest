use crate::{
    cc_switch, claude, codex, deepseek,
    models::AppError,
    service::{Data, Preferences, Service, Snapshot},
    tray_visual::{self, Action, BoxRect, Hover},
    updates,
};
use std::{
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration,
};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager, WebviewWindow, WindowEvent,
};

#[derive(Clone)]
struct Backend {
    service: Arc<Mutex<Service>>,
    work: Arc<tokio::sync::Notify>,
    update_work: Arc<tokio::sync::Mutex<()>>,
    home: PathBuf,
    preferences: PathBuf,
    demo: bool,
    hover: Arc<Mutex<Hover>>,
    demo_tray_event: Arc<Mutex<String>>,
}
impl Backend {
    fn snapshot(&self) -> Snapshot {
        self.service.lock().unwrap().snapshot()
    }
    fn save(&self, preferences: &Preferences) -> Result<(), AppError> {
        let dir = self
            .preferences
            .parent()
            .ok_or_else(|| AppError::new("preferences_write"))?;
        std::fs::create_dir_all(dir).map_err(|_| AppError::new("preferences_write"))?;
        let temp = self.preferences.with_extension("tmp");
        std::fs::write(
            &temp,
            serde_json::to_vec(preferences).map_err(|_| AppError::new("preferences_write"))?,
        )
        .map_err(|_| AppError::new("preferences_write"))?;
        std::fs::rename(temp, &self.preferences).map_err(|_| AppError::new("preferences_write"))
    }
}
fn demo_data(source: &str) -> Data {
    if source == "codex" {
        Data::Quota(crate::models::parse_codex(&serde_json::json!({"rateLimitsByLimitId":{"codex":{"planType":"Plus","primary":{"usedPercent":24,"windowDurationMins":300},"secondary":{"usedPercent":38,"windowDurationMins":10080}},"codex-spark":{"primary":{"usedPercent":9,"windowDurationMins":10080,"resetsAt":1793354400}},"external-model":{"primary":{"usedPercent":null,"windowDurationMins":300}}}})).unwrap())
    } else if source == "claude" {
        Data::Quota(crate::models::parse_claude(&serde_json::json!({"five_hour":{"utilization":18,"resets_at":"2026-10-23T20:00:00Z"},"seven_day":{"utilization":39},"seven_day_sonnet":{"utilization":7},"seven_day_opus":{"utilization":61}})).unwrap())
    } else {
        Data::Balance(crate::models::parse_balance(&serde_json::json!({"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"18.60","granted_balance":"3.60","topped_up_balance":"15.00"},{"currency":"USD","total_balance":"3.20","granted_balance":"0.20","topped_up_balance":"3.00"}]})).unwrap())
    }
}
async fn poll(backend: Backend, app: tauri::AppHandle) {
    // One global transfer at a time, even if the user switches sources repeatedly.
    let Some(request) = backend.service.lock().unwrap().begin() else {
        return;
    };
    let source = request.source.clone();
    let result = if backend.demo {
        Ok(demo_data(&source))
    } else if source == "codex" {
        codex::fetch(&backend.home).await.map(Data::Quota)
    } else if source == "claude" {
        let directory = claude::directory(&backend.home);
        match directory.and_then(|directory| {
            claude::read_credentials(&directory).map(|credential| (directory, credential))
        }) {
            Ok((directory, credential)) => {
                let limited = {
                    let mut service = backend.service.lock().unwrap();
                    if !service.current(&request) {
                        return;
                    }
                    service.validate_credential(&credential.generation)
                };
                let value = if let Some(error) = limited {
                    Err(error)
                } else {
                    claude::fetch(&credential).await
                };
                if let Err(error) = &value {
                    backend
                        .service
                        .lock()
                        .unwrap()
                        .record_rate_limit(&request, error);
                }
                match claude::read_credentials(&directory) {
                    Ok(current) if current.generation == credential.generation => {
                        value.map(Data::Quota)
                    }
                    _ => {
                        let mut service = backend.service.lock().unwrap();
                        if service.current(&request) {
                            service.credentials_changed();
                        }
                        Err(AppError::new("source_changed"))
                    }
                }
            }
            Err(error) => {
                let mut service = backend.service.lock().unwrap();
                if service.current(&request) {
                    service.credentials_changed();
                }
                Err(error)
            }
        }
    } else if let Some(id) = source.strip_prefix("api:") {
        let directory = PathBuf::from(&request.directory);
        match cc_switch::resolve(&directory, id) {
            Ok(credential) => {
                let limited = {
                    let mut service = backend.service.lock().unwrap();
                    if !service.current(&request) {
                        return;
                    }
                    service.validate_credential(&credential.generation)
                };
                let value = if let Some(error) = limited {
                    Err(error)
                } else {
                    deepseek::fetch(&credential).await
                };
                if let Err(error) = &value {
                    backend
                        .service
                        .lock()
                        .unwrap()
                        .record_rate_limit(&request, error);
                }
                match cc_switch::resolve(&directory, id) {
                    Ok(current) if current.generation == credential.generation => {
                        value.map(Data::Balance)
                    }
                    Err(error) if error.code == "source_busy" => Err(error),
                    _ => {
                        let mut service = backend.service.lock().unwrap();
                        if service.current(&request) {
                            service.credentials_changed();
                        }
                        Err(AppError::new("source_changed"))
                    }
                }
            }
            Err(error) => {
                let mut service = backend.service.lock().unwrap();
                if service.current(&request) && error.code != "source_busy" {
                    service.credentials_changed();
                }
                Err(error)
            }
        }
    } else {
        Err(AppError::new("unsupported_source"))
    };
    let accepted = backend.service.lock().unwrap().finish(request, result);
    if accepted {
        update_tray(&backend, &app);
    }
}
fn update_tray(backend: &Backend, app: &tauri::AppHandle) {
    let (tooltip, pixels) = {
        let service = backend.service.lock().unwrap();
        let amount = service.display_amount();
        let stale = service.state.reading.error.is_some();
        let context = service
            .display_window()
            .map(|w| {
                let model = match w.label.as_deref() {
                    Some("sonnet") => "Sonnet",
                    Some("opus") => "Opus",
                    Some("claude") => "Claude subscription",
                    Some(other) => other,
                    None => "",
                };
                let period = w
                    .minutes
                    .map(|m| {
                        if m >= 1440 {
                            format!("{}d", m as f64 / 1440.)
                        } else if m >= 60 {
                            format!("{}h", m as f64 / 60.)
                        } else {
                            format!("{m}m")
                        }
                    })
                    .unwrap_or_default();
                format!(" · {model} {period}")
            })
            .unwrap_or_default();
        let ratio = amount.strip_suffix('%').and_then(|v| v.parse::<f64>().ok());
        let text = if let Some(n) = ratio {
            format!("{n:.0}")
        } else if amount.starts_with("CNY ") {
            "¥".into()
        } else if amount.starts_with("USD ") {
            "$".into()
        } else {
            "—".into()
        };
        (
            format!(
                "QuotaNest · {}{context} · {amount}{}",
                if service.state.preferences.source == "claude" {
                    "Claude"
                } else if service.state.preferences.source == "codex" {
                    "Codex"
                } else {
                    "DeepSeek"
                },
                if stale { " · !" } else { "" }
            ),
            tray_visual::render(
                &text,
                ratio,
                tray_visual::color(&service.state.preferences.source),
                stale,
            ),
        )
    };
    if let Some(tray) = app.tray_by_id("quota") {
        let _ = tray.set_icon(Some(tauri::image::Image::new_owned(pixels, 32, 32)));
        let hovered = backend.hover.lock().unwrap().visible;
        let _ = tray.set_tooltip(if hovered { None } else { Some(tooltip) });
    }
    let _ = app.emit("snapshot-changed", ());
}
fn physical(rect: tauri::Rect, scale: f64) -> BoxRect {
    let p = rect.position.to_physical::<f64>(scale);
    let s = rect.size.to_physical::<f64>(scale);
    BoxRect {
        x: p.x,
        y: p.y,
        w: s.width,
        h: s.height,
    }
}
fn window_rect(window: &WebviewWindow) -> Option<BoxRect> {
    let p = window.outer_position().ok()?;
    let s = window.outer_size().ok()?;
    Some(BoxRect {
        x: p.x as f64,
        y: p.y as f64,
        w: s.width as f64,
        h: s.height as f64,
    })
}
fn place(window: &WebviewWindow, anchor: BoxRect) {
    if let Ok(Some(monitor)) =
        window.monitor_from_point(anchor.x + anchor.w / 2., anchor.y + anchor.h / 2.)
    {
        let work = monitor.work_area();
        let scale = monitor.scale_factor();
        let (width, height) = if window.label() == "hover" {
            (240., 110.)
        } else {
            (380., 650.)
        };
        let size = (
            (width * scale).min(work.size.width as f64),
            (height * scale).min(work.size.height as f64),
        );
        let target = tauri::PhysicalSize::new(size.0 as u32, size.1 as u32);
        if window.inner_size().ok() != Some(target) {
            let _ = window.set_size(target);
        }
        let outer = window
            .outer_size()
            .map(|s| (s.width as f64, s.height as f64))
            .unwrap_or(size);
        let (x, y) = tray_visual::position(
            anchor,
            BoxRect {
                x: work.position.x as f64,
                y: work.position.y as f64,
                w: work.size.width as f64,
                h: work.size.height as f64,
            },
            outer,
        );
        let _ = window.set_position(tauri::PhysicalPosition::new(x as i32, y as i32));
    }
}
fn controls(app: &tauri::AppHandle) {
    let backend = app.state::<Backend>();
    backend.hover.lock().unwrap().dismiss();
    if let Some(hover) = app.get_webview_window("hover") {
        let _ = hover.hide();
    }
    update_tray(&backend, app);
    if let Some(window) = app.get_webview_window("main") {
        if let Some(tray) = app.tray_by_id("quota") {
            if let Ok(Some(rect)) = tray.rect() {
                place(&window, physical(rect, window.scale_factor().unwrap_or(1.)));
            }
        }
        let _ = app.emit_to("main", "open-settings", ());
        show(&window);
    }
}
#[tauri::command]
fn hide_controls(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.hide();
    }
}
#[tauri::command]
fn demo_tray_bounds(
    backend: tauri::State<'_, Backend>,
    app: tauri::AppHandle,
) -> Result<serde_json::Value, AppError> {
    if !backend.demo {
        return Err(AppError::new("unsupported_source"));
    }
    let hover = app
        .get_webview_window("hover")
        .ok_or_else(|| AppError::new("protocol"))?;
    let tray = app
        .tray_by_id("quota")
        .ok_or_else(|| AppError::new("protocol"))?
        .rect()
        .map_err(|_| AppError::new("protocol"))?
        .ok_or_else(|| AppError::new("protocol"))?;
    let rect = physical(tray, hover.scale_factor().unwrap_or(1.));
    let card = window_rect(&hover).ok_or_else(|| AppError::new("protocol"))?;
    let cursor = hover.cursor_position().ok();
    let main_visible = app
        .get_webview_window("main")
        .is_some_and(|w| w.is_visible().unwrap_or(false));
    let visible = hover.is_visible().unwrap_or(false);
    let state = backend.hover.lock().unwrap();
    let service = backend.service.lock().unwrap();
    Ok(
        serde_json::json!({"displayAmount":service.display_amount(),"selectedModel":service.selected_model(),"displayWindow":service.display_window(),"lastEvent":backend.demo_tray_event.lock().unwrap().clone(),"cursor":cursor.map(|p| [p.x,p.y]),"mainVisible":main_visible,"controllerVisible":state.visible,"anchor":state.anchor.map(|a| [a.x,a.y,a.w,a.h]),"tray":{"x":rect.x,"y":rect.y,"w":rect.w,"h":rect.h},"card":{"x":card.x,"y":card.y,"w":card.w,"h":card.h},"visible":visible}),
    )
}
#[tauri::command]
fn select_display(
    value: String,
    backend: tauri::State<'_, Backend>,
    app: tauri::AppHandle,
) -> Result<Snapshot, AppError> {
    let snapshot = {
        let mut service = backend.service.lock().unwrap();
        service.select_display(&value)?;
        if !backend.demo {
            backend.save(&service.state.preferences)?;
        }
        service.snapshot()
    };
    update_tray(&backend, &app);
    Ok(snapshot)
}
#[tauri::command]
fn select_model(
    value: String,
    backend: tauri::State<'_, Backend>,
    app: tauri::AppHandle,
) -> Result<Snapshot, AppError> {
    let snapshot = {
        let mut service = backend.service.lock().unwrap();
        service.select_model(&value)?;
        if !backend.demo {
            backend.save(&service.state.preferences)?;
        }
        service.snapshot()
    };
    update_tray(&backend, &app);
    Ok(snapshot)
}

fn start_poll(backend: &Backend, _app: &tauri::AppHandle) {
    backend.work.notify_one();
}
#[tauri::command]
fn snapshot(backend: tauri::State<'_, Backend>) -> Snapshot {
    backend.snapshot()
}
#[tauri::command]
fn refresh(backend: tauri::State<'_, Backend>, app: tauri::AppHandle) {
    start_poll(&backend, &app);
}
#[tauri::command]
fn select_source(
    source: String,
    backend: tauri::State<'_, Backend>,
    app: tauri::AppHandle,
) -> Result<Snapshot, AppError> {
    let mut service = backend.service.lock().unwrap();
    service.select(&source)?;
    if backend.demo {
        service.state.reading.data = Some(demo_data(&source));
        service.state.reading.updated = Some(crate::models::now());
    }
    if !backend.demo {
        backend.save(&service.state.preferences)?;
    }
    let snapshot = service.snapshot();
    drop(service);
    update_tray(&backend, &app);
    start_poll(&backend, &app);
    Ok(snapshot)
}
#[tauri::command]
fn discover(directory: String, backend: tauri::State<'_, Backend>) -> Result<Snapshot, AppError> {
    let mut service = backend.service.lock().unwrap();
    if backend.demo {
        return Ok(service.snapshot());
    }
    match cc_switch::discover(&PathBuf::from(&directory)) {
        Ok(connections) => {
            service.set_directory(directory);
            service.state.connections = connections;
            service.state.discovery_error = None;
            if service.state.preferences.source.starts_with("api:")
                && !service.state.connections.iter().any(|c| {
                    c.supported && format!("api:{}", c.id) == service.state.preferences.source
                })
            {
                service.credentials_changed();
            }
            backend.save(&service.state.preferences)?;
        }
        Err(error) => {
            if error.code != "source_busy" && service.state.preferences.source.starts_with("api:") {
                service.credentials_changed();
            }
            service.state.discovery_error = Some(error);
        }
    }
    Ok(service.snapshot())
}
#[tauri::command]
fn save_preferences(
    preferences: Preferences,
    backend: tauri::State<'_, Backend>,
    _app: tauri::AppHandle,
) -> Result<Snapshot, AppError> {
    if !["system", "en", "zh"].contains(&preferences.language.as_str())
        || preferences.directory.len() > 32768
    {
        return Err(AppError::new("preferences_write"));
    }
    let mut service = backend.service.lock().unwrap();
    let mut next = service.state.preferences.clone();
    next.language = preferences.language;
    next.autostart = preferences.autostart;
    // Directory changes are applied only through explicit discovery; not by a language save.
    if !backend.demo {
        let autolaunch = autolaunch()?;
        let result = if next.autostart {
            autolaunch.enable()
        } else {
            autolaunch.disable()
        };
        result.map_err(|_| AppError::new("autostart_failed"))?;
        backend.save(&next)?;
    }
    service.state.preferences = next;
    Ok(service.snapshot())
}
#[tauri::command]
async fn check_update(backend: tauri::State<'_, Backend>) -> Result<(), AppError> {
    let Ok(_work) = backend.update_work.try_lock() else {
        return Ok(());
    };
    backend.service.lock().unwrap().state.update_status = "checking".into();
    let result = if backend.demo {
        Ok(None)
    } else {
        updates::check().await
    };
    let mut service = backend.service.lock().unwrap();
    match result {
        Ok(update) => {
            service.state.update_status = if update.is_some() {
                "availableUpdate"
            } else {
                "current"
            }
            .into();
            service.state.update = update;
        }
        Err(_) => service.state.update_status = "update_failed".into(),
    }
    Ok(())
}
#[tauri::command]
async fn install_update(
    backend: tauri::State<'_, Backend>,
    app: tauri::AppHandle,
) -> Result<(), AppError> {
    let Ok(_work) = backend.update_work.try_lock() else {
        return Ok(());
    };
    if backend.demo {
        return Err(AppError::new("invalid_update"));
    }
    let update = backend
        .service
        .lock()
        .unwrap()
        .state
        .update
        .clone()
        .ok_or_else(|| AppError::new("invalid_update"))?;
    backend.service.lock().unwrap().state.update_status = "downloading".into();
    let directory = backend.preferences.parent().unwrap().join("Updates");
    let result: Result<(), AppError> = async {
        let installer = updates::stage(&update, &directory).await?;
        #[cfg(windows)]
        {
            std::process::Command::new(installer)
                .arg("/UPDATE")
                .spawn()
                .map_err(|_| AppError::new("update_download"))?;
            app.exit(0);
        }
        #[cfg(not(windows))]
        {
            let _ = (installer, app);
            return Err(AppError::new("invalid_update"));
        }
        #[allow(unreachable_code)]
        Ok(())
    }
    .await;
    if let Err(ref e) = result {
        backend.service.lock().unwrap().state.update_status = e.code.clone();
    }
    result
}
#[tauri::command]
fn quit(app: tauri::AppHandle) {
    app.exit(0);
}
fn show(window: &WebviewWindow) {
    let _ = window.show();
    let _ = window.unminimize();
    let _ = window.set_focus();
}
fn clock_ms() -> u64 {
    use std::sync::OnceLock;
    static START: OnceLock<std::time::Instant> = OnceLock::new();
    START
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_millis() as u64
}
fn autolaunch() -> Result<auto_launch::AutoLaunch, AppError> {
    let path = std::env::current_exe().map_err(|_| AppError::new("autostart_failed"))?;
    let mut builder = auto_launch::AutoLaunchBuilder::new();
    builder
        .set_app_name("QuotaNest")
        .set_app_path(&path.to_string_lossy())
        .set_args(&["--background"]);
    #[cfg(windows)]
    builder.set_windows_enable_mode(auto_launch::WindowsEnableMode::CurrentUser);
    builder
        .build()
        .map_err(|_| AppError::new("autostart_failed"))
}
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app,_,_|controls(app)))

        .invoke_handler(tauri::generate_handler![snapshot,hide_controls,demo_tray_bounds,refresh,select_display,select_model,select_source,discover,save_preferences,check_update,install_update,quit])
        .setup(|app|{
            let home=std::env::var_os(if cfg!(windows){"USERPROFILE"}else{"HOME"}).map(PathBuf::from).ok_or("home missing")?;
            let preferences=app.path().app_config_dir()?.join("preferences.json");
            let demo=std::env::args().any(|a|a=="--demo");
            let mut prefs=if demo{Preferences::defaults(&home)}else{std::fs::read(&preferences).ok().and_then(|b|serde_json::from_slice::<Preferences>(&b).ok()).unwrap_or_else(||Preferences::defaults(&home))};
            if !demo {prefs.autostart=autolaunch()?.is_enabled().unwrap_or(prefs.autostart);}
            let mut service=Service::new(prefs);
            if demo {
                service.state.connections=vec![cc_switch::Connection{id:"claude|demo".into(),name:"DeepSeek".into(),harness:"claude".into(),origin:"https://api.deepseek.com".into(),supported:true}];
                service.select("api:claude|demo")?;service.state.reading.data=Some(demo_data("api:claude|demo"));service.state.reading.updated=Some(crate::models::now());
            }else if service.state.preferences.source.starts_with("api:") {
                match cc_switch::discover(&PathBuf::from(&service.state.preferences.directory)){Ok(c)=>service.state.connections=c,Err(e)=>service.state.discovery_error=Some(e)}
            }
            let backend=Backend{service:Arc::new(Mutex::new(service)),work:Arc::new(tokio::sync::Notify::new()),update_work:Arc::new(tokio::sync::Mutex::new(())),home,preferences,demo,hover:Arc::new(Mutex::new(Hover::default())),demo_tray_event:Arc::default()};
            app.manage(backend.clone());
            let open=MenuItem::with_id(app,"open","Open QuotaNest",true,None::<&str>)?;
            let refresh=MenuItem::with_id(app,"refresh","Refresh / 刷新",true,None::<&str>)?;
            let quit=MenuItem::with_id(app,"quit","Quit / 退出",true,None::<&str>)?;
            let menu=Menu::with_items(app,&[&open,&refresh,&quit])?;
            let window=app.get_webview_window("main").ok_or("window missing")?;
            let menu_backend=backend.clone();
            TrayIconBuilder::with_id("quota").icon(app.default_window_icon().ok_or("icon missing")?.clone()).tooltip("QuotaNest").menu(&menu).show_menu_on_left_click(false)
                .on_menu_event(move|app,event|match event.id.as_ref(){"open"=>controls(app),"refresh"=>start_poll(&menu_backend,app),"quit"=>app.exit(0),_=>{}})
                .on_tray_icon_event(|tray,event|{
                    let app=tray.app_handle();
                    if app.state::<Backend>().demo { *app.state::<Backend>().demo_tray_event.lock().unwrap()=format!("{event:?}"); }
                    match event {
                        TrayIconEvent::Click{button:MouseButton::Left,button_state:MouseButtonState::Up,..}=>controls(app),
                        TrayIconEvent::Enter{rect,..}|TrayIconEvent::Move{rect,..}=>{
                            let state=app.state::<Backend>();
                            let active=state.hover.lock().unwrap().anchor.is_some();
                            if active || app.get_webview_window("main").is_some_and(|w|w.is_visible().unwrap_or(false)){return;}

                            let _=tray.set_tooltip(None::<&str>);
                            if let Some(window)=app.get_webview_window("hover") {
                                let anchor=physical(rect,window.scale_factor().unwrap_or(1.));place(&window,anchor);
                                app.state::<Backend>().hover.lock().unwrap().enter(anchor,clock_ms());
                            }
                        },_=>{}
                    }
                }).build(app)?;
            let hide=window.clone();window.on_window_event(move|event|{match event {WindowEvent::CloseRequested{api,..}=>{api.prevent_close();let _=hide.hide();},WindowEvent::Focused(false)=>{let _=hide.hide();},_=>{}}});
            if demo {show(&window);}
            let hover_app=app.handle().clone();let hover_backend=backend.clone();
            tauri::async_runtime::spawn(async move{loop{
                tokio::time::sleep(Duration::from_millis(80)).await;
                let active=hover_backend.hover.lock().unwrap().anchor.is_some();if !active{continue;}
                let app=hover_app.clone();let state=hover_backend.clone();
                let _=hover_app.run_on_main_thread(move||{
                    if let Some(window)=app.get_webview_window("hover") {
                        if let (Ok(cursor),Some(card))=(window.cursor_position(),window_rect(&window)) {
                            let action=state.hover.lock().unwrap().tick((cursor.x,cursor.y),card,clock_ms());
                            match action {Action::Show=>{let _=window.show();},Action::Hide=>{let _=window.hide();update_tray(&state,&app);},Action::None=>{}}
                        }
                    }
                });
            }});
            update_tray(&backend,app.handle());
            let handle=app.handle().clone();
            start_poll(&backend,&handle);
            let check_backend=backend.clone();
            if !demo {tauri::async_runtime::spawn(async move{let result=updates::check().await;let mut s=check_backend.service.lock().unwrap();match result{Ok(u)=>{s.state.update_status=if u.is_some(){"availableUpdate"}else{"current"}.into();s.state.update=u;},Err(_)=>s.state.update_status="update_failed".into()}});}
            tauri::async_runtime::spawn(async move{loop{tokio::select!{_=backend.work.notified()=>{},_=tokio::time::sleep(Duration::from_secs(120))=>{}};poll(backend.clone(),handle.clone()).await;}});
            Ok(())
        }).run(tauri::generate_context!()).expect("QuotaNest could not start");
}
