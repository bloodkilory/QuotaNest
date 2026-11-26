use quotanest_windows::{claude, models};
use serde_json::json;
use std::fs;
#[test]
fn official_login_is_read_only_and_api_keys_are_not_oauth() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(".credentials.json");
    let data = json!({"claudeAiOauth":{"accessToken":"synthetic-oauth","expiresAt":(models::now()+3600)*1000,"scopes":["user:profile"],"subscriptionType":"max"}}).to_string();
    fs::write(&path, &data).unwrap();
    let credential = claude::read_credentials(dir.path()).ok().unwrap();
    assert_eq!(credential.plan.as_deref(), Some("max"));
    assert_eq!(fs::read_to_string(&path).unwrap(), data);
    fs::write(
        &path,
        json!({"apiKey":"not-subscription","env":{"ANTHROPIC_AUTH_TOKEN":"proxy"}}).to_string(),
    )
    .unwrap();
    assert_eq!(
        claude::read_credentials(dir.path()).err().unwrap().code,
        "claude_login_missing"
    );
}
#[test]
fn expired_or_profileless_login_has_actionable_errors_and_rotation_changes_identity() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(".credentials.json");
    let write = |token: &str, expiry: u64, scopes: serde_json::Value| {
        fs::write(
            &path,
            json!({"claudeAiOauth":{"accessToken":token,"expiresAt":expiry,"scopes":scopes}})
                .to_string(),
        )
        .unwrap()
    };
    write("synthetic", 1, json!(["user:profile"]));
    assert_eq!(
        claude::read_credentials(dir.path()).err().unwrap().code,
        "claude_login_expired"
    );
    write(
        "synthetic",
        (models::now() + 3600) * 1000,
        json!(["user:inference"]),
    );
    assert_eq!(
        claude::read_credentials(dir.path()).err().unwrap().code,
        "claude_scope_missing"
    );
    write(
        "synthetic-a",
        (models::now() + 3600) * 1000,
        json!(["user:profile"]),
    );
    let first = claude::read_credentials(dir.path())
        .ok()
        .unwrap()
        .generation;
    write(
        "synthetic-b",
        (models::now() + 3600) * 1000,
        json!(["user:profile"]),
    );
    assert_ne!(
        first,
        claude::read_credentials(dir.path())
            .ok()
            .unwrap()
            .generation
    );
}
#[test]
fn claude_preserves_distinct_groups_and_iso_reset_times_without_inventing_zero() {
    let quota=models::parse_claude(&json!({"five_hour":{"utilization":24,"resets_at":"2026-10-23T10:00:00.000Z"},"seven_day":{"utilization":61},"seven_day_sonnet":{"utilization":7},"seven_day_opus":{"utilization":100}})).unwrap();
    assert_eq!(quota.windows.len(), 4);
    assert_eq!(quota.windows[0].remaining, Some(76.0));
    assert_eq!(quota.windows[0].minutes, Some(300));
    assert!(quota.windows[0].resets_at.unwrap() > 0.0);
    assert_eq!(quota.windows[2].label.as_deref(), Some("sonnet"));
    assert_eq!(quota.windows[3].remaining, Some(0.0));
    assert!(models::parse_claude(
        &json!({"five_hour":{"utilization":null},"seven_day":{"utilization":true}})
    )
    .is_err());
}
#[test]
fn claude_is_selectable_without_cc_switch_or_prior_login() {
    use quotanest_windows::service::{Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    assert!(service.select("claude").is_ok());
}

#[test]
fn fable_scoped_weekly_quota_uses_its_own_percent_and_reset() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    service.select("claude").unwrap();
    // 使用新版响应结构；未触发限制的 Fable 额度也必须保留。
    let mut payload = json!({
        "five_hour": {"utilization": 12},
        "seven_day": {"utilization": 76},
        "limits": [{
            "kind": "weekly_scoped",
            "group": "weekly",
            "percent": 65,
            "severity": "normal",
            "resets_at": "2026-10-30T10:00:00Z",
            "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null},
            "is_active": false
        }],
        "weekly_scoped_shares": [{
            "limit_index": 0,
            "used_percent_of_weekly": 33,
            "allowance_percent_of_weekly": 50
        }]
    });
    service.state.reading.data = Some(Data::Quota(models::parse_claude(&payload).unwrap()));
    assert!(service.select_model("fable").is_ok());
    assert_eq!(service.display_amount(), "35%");
    assert_eq!(service.display_window().unwrap().minutes, Some(10080));
    assert_eq!(service.display_window().unwrap().resets_at, Some(1793354400.));
    for (percent, remaining) in [
        (json!(0), Some(100.)),
        (json!(100), Some(0.)),
        (json!(null), None),
    ] {
        payload["limits"][0]["percent"] = percent;
        service.state.reading.data = Some(Data::Quota(models::parse_claude(&payload).unwrap()));
        assert_eq!(service.selected_model(), Some("fable"));
        assert_eq!(service.display_window().unwrap().remaining, remaining);
    }
    let has_fable = |p: &serde_json::Value| {
        models::parse_claude(p)
            .unwrap()
            .windows
            .iter()
            .any(|w| w.label.as_deref() == Some("fable"))
    };
    payload["limits"][0]["scope"]["surface"] = json!("cowork");
    assert!(!has_fable(&payload));
    payload["limits"] = json!(null);
    assert!(!has_fable(&payload));
}
#[test]
fn official_period_uses_tightest_group_and_display_choice_is_saved_per_source() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    service.select("claude").unwrap();
    let request = service.begin().unwrap();
    service.finish(request,Ok(Data::Quota(models::parse_claude(&json!({"five_hour":{"utilization":18},"seven_day":{"utilization":39},"seven_day_opus":{"utilization":80}})).unwrap())));
    assert_eq!(service.display_amount(), "82%");
    service.select_display("10080").unwrap();
    assert_eq!(service.display_amount(), "20%");
    service.select("codex").unwrap();
    assert_eq!(service.display_amount(), "—");
    service.select("claude").unwrap();
    assert_eq!(
        service.state.preferences.display.get("claude").unwrap(),
        "10080"
    );
}
#[test]
fn cc_switch_directory_changes_do_not_clear_official_cooldown() {
    use quotanest_windows::service::{Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    service.select("claude").unwrap();
    service.validate_credential("official");
    let request = service.begin().unwrap();
    service.finish(
        request,
        Err(models::AppError {
            code: "rate_limited".into(),
            retry_at: Some(models::now() + 3600),
        }),
    );
    service.set_directory("new CC Switch folder".into());
    assert!(service.validate_credential("official").is_some());
    assert_eq!(service.state.preferences.source, "claude");
}
#[test]
fn missing_primary_duration_uses_first_explicit_period_in_tray() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    let request = service.begin().unwrap();
    service.finish(request,Ok(Data::Quota(models::parse_codex(&json!({"rateLimits":{"primary":{"usedPercent":20},"secondary":{"usedPercent":50,"windowDurationMins":10080}}})).unwrap())));
    assert_eq!(service.display_amount(), "50%");
}

#[test]
fn saved_model_filters_tray_and_survives_restart() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let mut prefs: Preferences = serde_json::from_value(json!({"source":"claude","language":"en","directory":"demo","autostart":false,"display":{"claude":"300"},"model":{"claude":"sonnet","codex":"other"}})).unwrap();
    prefs = serde_json::from_slice(&serde_json::to_vec(&prefs).unwrap()).unwrap();
    let mut service = Service::new(prefs);
    let quota = models::parse_claude(&json!({"five_hour":{"utilization":18},"seven_day":{"utilization":39},"seven_day_sonnet":{"utilization":7},"seven_day_opus":{"utilization":61}})).unwrap();
    service.state.reading.data = Some(Data::Quota(quota.clone()));
    assert_eq!(service.display_amount(), "93%");
    let mut reordered = quota.clone();
    reordered.windows.reverse();
    service.state.reading.data = Some(Data::Quota(reordered));
    assert_eq!(service.display_amount(), "93%");
    let mut unknown = quota.clone();
    unknown.windows[2].remaining = None;
    service.state.reading.data = Some(Data::Quota(unknown));
    assert_eq!(service.display_amount(), "—");
    let mut deleted = quota;
    deleted
        .windows
        .retain(|w| w.label.as_deref() != Some("sonnet"));
    service.state.reading.data = Some(Data::Quota(deleted));
    assert_eq!(service.display_amount(), "82%");
}

#[test]
fn model_selection_uses_stable_labels_and_matching_reset_and_period() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    service.select("claude").unwrap();
    let quota = models::parse_claude(&json!({"five_hour":{"utilization":18},"seven_day":{"utilization":39},"seven_day_sonnet":{"utilization":7,"resets_at":"2026-10-30T10:00:00Z"},"seven_day_opus":{"utilization":61,"resets_at":"2026-10-31T10:00:00Z"}})).unwrap();
    service.state.reading.data = Some(Data::Quota(quota.clone()));
    service.select_display("300").unwrap();
    service.select_model("sonnet").unwrap();
    assert_eq!(service.selected_model(), Some("sonnet"));
    assert_eq!(service.display_amount(), "93%");
    assert_eq!(service.display_window().unwrap().minutes, Some(10080));
    assert_eq!(
        service.display_window().unwrap().resets_at,
        Some(1793354400.)
    );
    assert!(service.select_display("300").is_err());
    assert!(service.select_model("missing").is_err());
    service.select_model("opus").unwrap();
    assert_eq!(service.display_amount(), "39%");
    service.select_model("claude").unwrap();
    service.select_display("10080").unwrap();
    assert_eq!(service.display_amount(), "61%");
    service.select_model("").unwrap();
    assert_eq!(service.display_amount(), "39%");
    service.select_model("sonnet").unwrap();
    let prefs: Preferences =
        serde_json::from_slice(&serde_json::to_vec(&service.state.preferences).unwrap()).unwrap();
    let mut restored = Service::new(prefs);
    restored.select("codex").unwrap();
    restored.state.reading.data = Some(Data::Quota(quota.clone()));
    restored.select_model("opus").unwrap();
    assert_eq!(restored.display_amount(), "39%");
    restored.select("claude").unwrap();
    restored.state.reading.data = Some(Data::Quota(quota));
    assert_eq!(restored.display_amount(), "93%");
    let request = restored.begin().unwrap();
    restored.finish(request, Err(models::AppError::new("network")));
    assert_eq!(restored.display_amount(), "93%");
}
#[test]
fn old_preferences_default_to_automatic() {
    use quotanest_windows::service::Preferences;
    let prefs:Preferences=serde_json::from_value(json!({"source":"claude","language":"en","directory":"demo","autostart":false,"display":{"claude":"10080"}})).unwrap();
    assert!(prefs.model.is_empty());
    assert_eq!(prefs.display.get("claude").unwrap(), "10080");
}

#[test]
fn unknown_model_payload_does_not_fall_back_to_another_model() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    service.select("claude").unwrap();
    service
        .state
        .preferences
        .model
        .insert("claude".into(), "sonnet".into());
    let quota=models::parse_claude(&json!({"five_hour":{"utilization":18},"seven_day_sonnet":{"utilization":null,"resets_at":"2026-10-30T10:00:00Z"}})).unwrap();
    service.state.reading.data = Some(Data::Quota(quota));
    assert_eq!(service.display_amount(), "—");
    assert_eq!(service.selected_model(), Some("sonnet"));
    assert_eq!(
        service.display_window().unwrap().resets_at,
        Some(1793354400.)
    );
}

#[test]
fn automatic_skips_unknown_period_but_explicit_model_keeps_it() {
    use quotanest_windows::service::{Data, Preferences, Service};
    let dir = tempfile::tempdir().unwrap();
    let mut service = Service::new(Preferences::defaults(dir.path()));
    service.select("claude").unwrap();
    service.state.reading.data = Some(Data::Quota(
        models::parse_claude(
            &json!({"five_hour":{"utilization":null},"seven_day":{"utilization":39}}),
        )
        .unwrap(),
    ));
    assert_eq!(service.display_amount(), "61%");
    assert_eq!(service.display_window().unwrap().minutes, Some(10080));
    service.select_model("claude").unwrap();
    assert_eq!(service.display_amount(), "—");
    assert_eq!(service.display_window().unwrap().minutes, Some(300));
}
