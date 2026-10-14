# Firebase & Cloud Functions Debugging Guide (Solar Battery System)

This guide documents the battle-tested debugging patterns, Firestore schemas, query syntax rules, ML forecasting pitfalls, and deployment workflows for the **XGrowatt Auto-SPH** solar and battery management system.

---

## 📂 1. Firestore Database Schema & Collection Conventions

| Collection Name | Document ID Pattern | Key Fields & Types | Purpose |
|---|---|---|---|
| `status` | `charging_plan` | `for_date` (String), `target_soc` (Int), `charge_kwh` (Double), `pv_forecast_kwh` (Double), `suggested_tasks` (Array) | Active AI plan for **tomorrow's** charging schedule (displayed on main app card). |
| `status` | `pv_model` | `forecast.coef` (Map), `forecast.features` (Array), `forecast.recommended` (String), `forecast.trained_at` (String) | Deployed Bayesian Ridge / Ridge ML model coefficients and uncertainty bounds. |
| `status` | `battery_health` | `bms_soc` (Int), `days_since_last_calibration` (Int), `last_calibration_date` (String), `soh` (Double) | LFP battery health and calibration tracking. |
| `charging_plan_history` | `YYYY-MM-DD` | `for_date`, `pv_forecast_kwh`, `pv_forecast_raw_kwh`, `target_soc`, `charge_kwh`, `model_used` | Historical daily AI plan archive (used by analytics and 14-day bias feedback). |
| `daily_bills` | `YYYY-MM-DD` | `solar_kwh` (Double), `load_kwh` (Double), `import_kwh` (Double), `export_kwh` (Double), `net_cost` (Double) | Ground-truth daily electricity metrics reconciled from inverter telemetry. |
| `weather_forecast` | `YYYY-MM-DD_HH` | `issued_at` (Timestamp), `hours` (Array of 72 hourly weather dicts) | Hourly snapshots of weather forecasts from Open-Meteo (GTI, DNI, cloud, rain). |
| `telemetry_history` | Auto-generated ID | `timestamp` (Timestamp), `solar_generation_kw` (Double), `global_tilted_irradiance_wm2` (Double), `cloud_cover_pct` (Int), `precipitation_mm` (Double) | 5-minute time-series telemetry data for ML training and real-time monitoring. |
| `settings` | `growatt` / `tesla` | `pv_capacity_kw` (Double), `panel_tilt_deg` (Double), `panel_azimuth_deg` (Double), `timezone` (String) | User and hardware configuration parameters. |

> [!CAUTION] **Collection Name Trap**
> - The history collection is **`charging_plan_history`** (singular `plan`), NOT `charging_plans_history`.
> - The telemetry history is **`telemetry_history`**, NOT `telemetry`.
> - Daily solar field in `daily_bills` is **`solar_kwh`** (NOT `epv_today_kwh` or `epv_kwh`).

---

## 🐍 2. Python Firestore Query Best Practices

### A. Environment Initialization
Always ensure project ID is set before initializing Firebase Admin SDK in standalone scripts:
```python
import os, sys
os.environ['GOOGLE_CLOUD_PROJECT'] = 'demo-solar-microgrid'
import firebase_admin
from firebase_admin import firestore

if not firebase_admin._apps:
    firebase_admin.initialize_app()
db = firestore.client()
```

### B. Document ID vs Field Filtering
- In `firebase_admin.firestore`, **`FieldPath.document_id()` does NOT exist** on the top-level module.
- Always use explicit date fields like `where('for_date', '>=', cutoff_date)` or `where('date', '>=', cutoff_date)`:
```python
# ✅ CORRECT:
cutoff = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=14)).strftime('%Y-%m-%d')
docs = db.collection('charging_plan_history').where('for_date', '>=', cutoff).stream()

# ❌ INCORRECT (Raises AttributeError):
# docs = db.collection('charging_plan_history').where(firestore.FieldPath.document_id(), '>=', cutoff).stream()
```

### C. Modern Filter Syntax (Avoiding Deprecation Warnings)
```python
# Standard SDK query:
from google.cloud.firestore_v1.base_query import FieldFilter

# Modern query format:
query = db.collection('daily_bills').where(filter=FieldFilter('date', '>=', cutoff))
```

---

## 🧠 3. ML Solar Forecasting & Weather Attenuation Rules

### A. The Diffuse Radiation Over-Prediction Pitfall
- **Problem**: Numerical weather providers (Open-Meteo / ECMWF) calculate plane-of-array irradiance (GTI) using standard diffuse sky decomposition models. Under 100% thick nimbostratus rain clouds, models still report `200~300 W/m²` GTI, causing linear ML models to over-predict solar generation by **200%~300%** on stormy days.
- **Solution**: Always apply continuous non-linear physical weather attenuation:
```python
def compute_weather_attenuation(cloud_pct, precip_mm):
    """
    Computes physical optical cloud thickness & rain attenuation factor.
    Prevents diffuse radiation models from over-predicting on stormy/overcast days.
    Returns attenuation multiplier in range [0.15, 1.0].
    """
    import math
    c = max(0.0, min(100.0, float(cloud_pct or 0.0))) / 100.0
    p = max(0.0, float(precip_mm or 0.0))
    
    # 1. Non-linear Cloud Overcast Damping (cubic scaling kicks in heavily at c > 0.70)
    cloud_factor = 1.0 - 0.35 * (c ** 3)
    
    # 2. Precipitation Damping (water film + nimbostratus optical extinction)
    rain_factor = 1.0
    if p > 0.05:
        rain_factor = 1.0 / (1.0 + 1.8 * math.sqrt(p) * c)
        
    return max(0.15, min(1.0, cloud_factor * rain_factor))
```

### B. Recency-Weighted Adaptive Bias Feedback (MPC Output Residual)
To adapt to rapid spring/autumn solar altitude changes without getting stuck on mid-winter historical averages:
1. Strictly constrain queries to the last 14 days (`where('for_date', '>=', cutoff)`).
2. Apply exponential recency decay (`weight = math.exp(-0.12 * age_days)`).
3. Compute ratio against pre-correction raw forecasts (`pv_forecast_raw_kwh`) to prevent self-canceling oscillation loops.

---

## 📱 4. Mobile App (Android/iOS) UI Alignment Rules

1. **Active Plan vs History**:
   - Main Dashboard `AiPlanCard` displays **`status/charging_plan`** (`for_date` = tomorrow).
   - Analytics / History tabs display **`charging_plan_history`** (`for_date` <= today).
2. **Value Consistency Rule**:
   - The top Metric Table (`target_soc`), collapsed preview text (`target_soc`), and suggested task table (`suggested_tasks[0].soc`) must all be assigned the exact same integer `int(target_soc)`.
3. **Realtime Sync**:
   - The Android app listens via `addSnapshotListener`. When documents in `charging_plan_history` are updated, switching tabs or pulling down to refresh automatically propagates the new data to the UI StateFlow.

---

## 🚀 5. Deployment & Verification Checklist

When deploying changes to Cloud Functions:
1. **Python Syntax Check**:
   ```bash
   python3 -m py_compile functions/main.py
   ```
2. **Deploy Functions**:
   ```bash
   firebase deploy --only functions
   ```
3. **Verify Execution**:
   - Trigger plan generation test:
     ```bash
     source functions/venv/bin/activate && python3 -c "import main, firebase_admin; from firebase_admin import firestore; firebase_admin.initialize_app(); db = firestore.client(); plan = main.generate_charging_plan_logic(db); print('Target SoC:', plan.get('target_soc'))"
     ```
   - Check Firestore document `status/charging_plan` to confirm fields match expectations.

---

## 🛠️ 6. `zsh: command not found: gcloud` 解决方案

如果在 macOS 终端中运行 `gcloud` 命令报错 `zsh:1: command not found: gcloud`，可采用以下两种方案解决：

### 方案 A：安装并配置 Google Cloud SDK (CLI 方案)

1. **通过 Homebrew 安装**：
   ```bash
   brew install --cask google-cloud-sdk
   ```
2. **在 `~/.zshrc` 中添加环境变量与补全**：
   ```bash
   echo 'source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"' >> ~/.zshrc
   echo 'source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"' >> ~/.zshrc
   source ~/.zshrc
   ```
3. **初始化与认证登录**：
   ```bash
   gcloud init
   gcloud auth application-default login
   ```

---

### 方案 B：无需 gcloud CLI 的 Python SDK / REST API 方案 (推荐 🌟)

如果在未安装 `gcloud` 的环境中需要查询 Cloud Functions 日志、Cloud Scheduler 状态或触发云端任务，直接使用 Python `google-auth` + REST API，完全不需要依赖 `gcloud` 命令行工具：

```python
import google.auth
from google.auth.transport.requests import Request
import requests

# 1. 自动获取当前环境凭据与 Token
credentials, _ = google.auth.default()
credentials.refresh(Request())
token = credentials.token
project = 'demo-solar-microgrid'

# 2. 直接查询 Cloud Logging 日志
headers = {'Authorization': f'Bearer {token}'}
log_query = {
    'resourceNames': [f'projects/{project}'],
    'filter': 'resource.type=("cloud_run_revision" OR "cloud_scheduler_job") AND timestamp >= "2026-08-25T13:20:00Z"',
    'pageSize': 20
}
resp = requests.post('https://logging.googleapis.com/v2/entries:list', json=log_query, headers=headers)
for entry in resp.json().get('entries', []):
    print(entry.get('timestamp'), entry.get('textPayload') or entry.get('jsonPayload'))
```

