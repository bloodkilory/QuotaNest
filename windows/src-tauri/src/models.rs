use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::str::FromStr;
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppError {
    pub code: String,
    pub retry_at: Option<u64>,
}
impl AppError {
    pub fn new(code: &str) -> Self {
        Self {
            code: code.into(),
            retry_at: None,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Wallet {
    pub currency: String,
    pub total: String,
    pub granted: String,
    pub topped_up: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaWindow {
    #[serde(default)]
    pub label: Option<String>,
    pub remaining: Option<f64>,
    pub minutes: Option<u64>,
    pub resets_at: Option<f64>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Quota {
    pub plan: Option<String>,
    pub windows: Vec<QuotaWindow>,
}
pub fn parse_balance(root: &Value) -> Result<Vec<Wallet>, AppError> {
    let invalid = || AppError::new("invalid_balance");
    root["is_available"].as_bool().ok_or_else(invalid)?;
    let values = root["balance_infos"].as_array().ok_or_else(invalid)?;
    if values.is_empty() || values.len() > 2 {
        return Err(invalid());
    }
    let mut currencies = std::collections::HashSet::new();
    values
        .iter()
        .map(|v| {
            let currency = v["currency"]
                .as_str()
                .filter(|s| ["CNY", "USD"].contains(s))
                .ok_or_else(invalid)?;
            if !currencies.insert(currency) {
                return Err(invalid());
            }
            let amount = |key: &str| -> Result<String, AppError> {
                let s = v[key]
                    .as_str()
                    .filter(|s| !s.is_empty() && s.len() <= 38)
                    .ok_or_else(invalid)?;
                let digits = s.strip_prefix('-').unwrap_or(s);
                let mut parts = digits.split('.');
                let whole = parts.next().unwrap_or("");
                let fraction = parts.next();
                if whole.is_empty()
                    || !whole.bytes().all(|c| c.is_ascii_digit())
                    || parts.next().is_some()
                    || fraction
                        .is_some_and(|f| f.is_empty() || !f.bytes().all(|c| c.is_ascii_digit()))
                {
                    return Err(invalid());
                }
                let value = Decimal::from_str(s).map_err(|_| invalid())?;
                Ok(format!("{:.2}", value.round_dp(2)))
            };
            Ok(Wallet {
                currency: currency.into(),
                total: amount("total_balance")?,
                granted: amount("granted_balance")?,
                topped_up: amount("topped_up_balance")?,
            })
        })
        .collect()
}
pub fn parse_codex(root: &Value) -> Result<Quota, AppError> {
    let map = root["rateLimitsByLimitId"].as_object();
    let main = map
        .and_then(|m| m.get("codex"))
        .filter(|v| v.is_object())
        .or_else(|| root.get("rateLimits").filter(|v| v.is_object()));
    let mut buckets = main.map(|v| vec![("codex", v)]).unwrap_or_default();
    if let Some(map) = map {
        buckets.extend(
            map.iter()
                .filter(|(key, value)| key.as_str() != "codex" && value.is_object())
                .map(|(key, value)| (key.as_str(), value)),
        );
    }
    let windows = buckets
        .iter()
        .flat_map(|(label, bucket)| {
            ["primary", "secondary"]
                .into_iter()
                .filter_map(|key| bucket.get(key).filter(|v| v.is_object()))
                .map(|v| QuotaWindow {
                    label: Some((*label).into()),
                    remaining: v["usedPercent"]
                        .as_f64()
                        .filter(|n| n.is_finite())
                        .map(|n| (100.0 - n).clamp(0.0, 100.0)),
                    minutes: v["windowDurationMins"].as_u64(),
                    resets_at: v["resetsAt"].as_f64().filter(|v| v.is_finite()),
                })
        })
        .collect::<Vec<_>>();
    if windows.is_empty() {
        return Err(AppError::new("invalid_quota"));
    }
    Ok(Quota {
        plan: main.and_then(|v| v["planType"].as_str()).map(str::to_owned),
        windows,
    })
}
pub fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.code)
    }
}
impl std::error::Error for AppError {}

pub fn parse_claude(root: &Value) -> Result<Quota, AppError> {
    let mut rows = [
        ("five_hour", 300, "claude"),
        ("seven_day", 10080, "claude"),
        ("seven_day_sonnet", 10080, "sonnet"),
        ("seven_day_opus", 10080, "opus"),
    ]
    .into_iter()
    .map(|(key, minutes, label)| (&root[key], minutes, label, "utilization"))
    .collect::<Vec<_>>();
    // 新版 Fable 周额度使用自身的 percent，不能换算为总周额度份额。
    rows.extend(
        root["limits"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|row| {
                row["kind"].as_str() == Some("weekly_scoped")
                    && row["scope"]["surface"].is_null()
                    && row["scope"]["model"]["display_name"]
                        .as_str()
                        .is_some_and(|name| name.eq_ignore_ascii_case("Fable"))
            })
            .map(|row| (row, 10080, "fable", "percent")),
    );
    let windows = rows
        .into_iter()
        .filter_map(|(row, minutes, label, percent_key)| {
            let row = row.as_object()?;
            let used = row
                .get(percent_key)
                .and_then(Value::as_f64)
                .filter(|v| v.is_finite());
            let resets_at = row
                .get("resets_at")
                .and_then(Value::as_str)
                .and_then(|s| {
                    time::OffsetDateTime::parse(s, &time::format_description::well_known::Rfc3339)
                        .ok()
                })
                .map(|d| d.unix_timestamp() as f64);
            Some(QuotaWindow {
                label: Some(label.into()),
                remaining: used.map(|used| (100.0 - used).clamp(0.0, 100.0)),
                minutes: Some(minutes),
                resets_at,
            })
        })
        .collect::<Vec<_>>();
    if !windows.iter().any(|w| w.remaining.is_some()) {
        return Err(AppError::new("invalid_quota"));
    }
    Ok(Quota {
        plan: None,
        windows,
    })
}
