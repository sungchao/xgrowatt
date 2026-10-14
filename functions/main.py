from firebase_functions import firestore_fn, scheduler_fn, https_fn
from firebase_admin import initialize_app, firestore
import datetime
import math
import json
import requests
from zoneinfo import ZoneInfo
import growattServer
from tesla_fleet import smart_poll_tesla, TeslaFleetClient, ensure_valid_tesla_token

# Initialize Firebase
initialize_app()

def parse_kw(val) -> float:
    """Helper to convert string like '0.9', '0.6', or float/int to float value in kW."""
    if val is None:
        return 0.0
    try:
        val_str = str(val).lower().replace("kw", "").strip()
        return float(val_str)
    except Exception:
        return 0.0

def parse_kwh(val) -> float:
    """Helper to convert string like '20.1kWh' or float/int to float value in kWh."""
    if val is None:
        return 0.0
    try:
        val_str = str(val).lower().replace("kwh", "").strip()
        return float(val_str)
    except Exception:
        return 0.0

def parse_int(val) -> int:
    if val is None:
        return 0
    try:
        return int(float(str(val).strip()))
    except Exception:
        return 0

# Fallback timezone -> (lat, lon) map, mirrors WeatherManager.swift's table.
# Used when the settings doc has no explicit latitude/longitude saved.
_TIMEZONE_COORDS = {
    "Australia/Sydney":    (-33.87, 151.21),
    "Australia/Canberra":  (-35.28, 149.13),
    "Australia/Melbourne": (-37.81, 144.96),
    "Australia/Brisbane":  (-27.47, 153.02),
    "Australia/Perth":     (-31.95, 115.86),
    "Australia/Adelaide":  (-34.93, 138.60),
    "Australia/Darwin":    (-12.46, 130.84),
    "Australia/Hobart":    (-42.88, 147.32),
    "Pacific/Auckland":    (-36.86, 174.77),
    "Asia/Shanghai":       (31.23, 121.47),
    "Asia/Tokyo":          (35.68, 139.69),
    "Europe/London":       (51.51, -0.13),
    "America/New_York":    (40.71, -74.00),
    "America/Los_Angeles": (34.05, -118.24),
}

# Full set of Open-Meteo hourly variables we pull for every telemetry snapshot.
# Grouped by why each one is here — the goal is features that plausibly explain either
# PV output or home load, not "grab everything available" (extra noise features hurt a
# small model trained on limited history more than they help).
#
#   PV output drivers (primary):
#     shortwave_radiation, direct_radiation, diffuse_radiation, direct_normal_irradiance
#       -> irradiance is the dominant driver of PV output, bar none.
#     cloud_cover, cloud_cover_low/mid/high
#       -> layered cover matters because high cloud attenuates far less than low cloud.
#     sunshine_duration, uv_index
#       -> cheap extra signal correlated with clear-sky conditions, helps separate
#          "thin haze" from "thick cloud" scenarios that raw cloud_cover can't.
#   PV secondary (panel efficiency / atmosphere):
#     temperature_2m   -> panel efficiency drops at high cell temperature.
#     wind_speed_10m   -> wind cools panels, slightly raises efficiency in hot weather.
#     precipitation    -> rain both cleans panels and correlates with heavy cloud.
#     visibility       -> haze/fog attenuates irradiance beyond what cloud_cover shows.
#   Load drivers:
#     apparent_temperature, relative_humidity_2m -> "feels like" heat/cold drives
#       heating/cooling demand better than raw temperature alone.
#   Context / display:
#     weather_code, is_day
#
# Deliberately excluded: soil_temperature/soil_moisture/evapotranspiration (agriculture-
# oriented, no link to rooftop solar or home load), pressure_msl/surface_pressure and
# wind_direction (no plausible causal link here), dew_point_2m (redundant — derivable
# from temperature + humidity, would just duplicate signal already in the feature set).
_HOURLY_WEATHER_VARS = [
    "temperature_2m", "apparent_temperature", "relative_humidity_2m",
    "precipitation", "weather_code", "is_day",
    "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
    "shortwave_radiation", "direct_radiation", "diffuse_radiation", "direct_normal_irradiance",
    "sunshine_duration", "uv_index", "visibility", "wind_speed_10m",
    # Plane-of-array irradiance for THIS system's panels (requires tilt+azimuth query params,
    # see _panel_params). Strongest single PV predictor: bakes sun-geometry x panel-orientation
    # into the data itself. PV output ~= GTI x area x efficiency.
    "global_tilted_irradiance",
]

# Panel geometry for the global_tilted_irradiance request. Open-Meteo azimuth convention:
# 0 = south, +/-180 = north (this roof: due north, 25 deg tilt). Overridable via settings
# keys panel_tilt_deg / panel_azimuth_deg.
def _panel_params(settings: dict) -> dict:
    return {
        "tilt": float(settings.get("panel_tilt_deg", 25.0)),
        "azimuth": float(settings.get("panel_azimuth_deg", 180.0)),
    }

def _weather_snapshot_from_hourly(hourly: dict, idx: int) -> dict:
    """Extracts one hour's worth of values (at `idx`) from an Open-Meteo `hourly` response block."""
    def _val(key):
        arr = hourly.get(key)
        if not arr or idx >= len(arr) or arr[idx] is None:
            return None
        return arr[idx]

    weather_code = _val("weather_code")
    is_day = _val("is_day")
    return {
        "temperature_c": _val("temperature_2m"),
        "apparent_temperature_c": _val("apparent_temperature"),
        "relative_humidity_pct": _val("relative_humidity_2m"),
        "precipitation_mm": _val("precipitation"),
        "weather_code": int(weather_code) if weather_code is not None else None,
        "is_day": bool(is_day) if is_day is not None else None,
        "cloud_cover_pct": _val("cloud_cover"),
        "cloud_cover_low_pct": _val("cloud_cover_low"),
        "cloud_cover_mid_pct": _val("cloud_cover_mid"),
        "cloud_cover_high_pct": _val("cloud_cover_high"),
        "shortwave_radiation_wm2": _val("shortwave_radiation"),
        "direct_radiation_wm2": _val("direct_radiation"),
        "diffuse_radiation_wm2": _val("diffuse_radiation"),
        "direct_normal_irradiance_wm2": _val("direct_normal_irradiance"),
        "sunshine_duration_s": _val("sunshine_duration"),
        "uv_index": _val("uv_index"),
        "visibility_m": _val("visibility"),
        "wind_speed_kmh": _val("wind_speed_10m"),
        "global_tilted_irradiance_wm2": _val("global_tilted_irradiance"),
    }

def fetch_weather_snapshot(settings: dict, tz_name: str) -> dict:
    """
    Fetches the current hour's weather from Open-Meteo and returns it as a flat dict to be
    merged into a telemetry_history entry. Uses the `hourly` block (not `current`) because
    several of the variables we want (radiation components, layered cloud cover, UV index,
    visibility) aren't exposed via `current` at all.
    Returns an empty dict on any failure — weather is a nice-to-have, never blocks sync.
    """
    try:
        import requests
        lat = settings.get('latitude')
        lon = settings.get('longitude')
        if lat is None or lon is None:
            lat, lon = _TIMEZONE_COORDS.get(tz_name, (-35.28, 149.13))

        params = {
            "latitude": lat,
            "longitude": lon,
            "hourly": ",".join(_HOURLY_WEATHER_VARS),
            "forecast_days": 1,
            "timezone": tz_name,
        }
        params.update(_panel_params(settings))
        resp = requests.get("https://api.open-meteo.com/v1/forecast", params=params, timeout=8)
        resp.raise_for_status()
        hourly = resp.json().get("hourly", {})
        times = hourly.get("time", [])
        if not times:
            return {}

        # Pick the latest hour <= "now" in the target timezone (times are "YYYY-MM-DDTHH:00").
        now_str = datetime.datetime.now(ZoneInfo(tz_name)).strftime("%Y-%m-%dT%H:00")
        idx = 0
        for i, t in enumerate(times):
            if t <= now_str:
                idx = i
            else:
                break

        return _weather_snapshot_from_hourly(hourly, idx)
    except Exception as e:
        print(f"Warning: Failed to fetch weather snapshot: {str(e)}")
        return {}

def resolve_daily_schedule_from_tasks(tasks: list, target_date: datetime.date, reference_minute=None):
    """
    Resolves up to 3 non-overlapping charging slots for the target_date from the list of tasks.
    Later tasks in the list overwrite earlier tasks in case of overlap.

    reference_minute: "now", in minutes relative to target_date 00:00 (negative when the
    schedule is being pushed the night before). Growatt exposes ONE global charge-stop SoC
    shared by all three time slots, so per-window SoC targets are impossible in a single
    static write. Instead, the global SoC/power are taken from the NEXT segment at/after
    reference_minute — and since the 5-min scheduler fires a pre-task sync ~15 min before
    EVERY window starts, each window receives its own SoC just in time (e.g. Sat 23:45 push
    sets the overnight 55%, the Sat 11:45 push flips it to the free window's 100%).
    None -> legacy behaviour (last segment).
    """
    day_str = target_date.strftime("%a")  # "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
    
    # 1. Filter enabled tasks matching the target day of the week
    active_tasks = []
    for t in tasks:
        if t.get('enabled', False) and day_str in t.get('days', []):
            active_tasks.append(t)
            
    if not active_tasks:
        return [], 100, 100  # Default fallback if no tasks active
        
    # 2. Map to 1440-minute grid. Default is empty (None)
    grid = [None] * 1440
    
    for idx, t in enumerate(active_tasks):
        start_time = t.get('start_time', '00:00')
        end_time = t.get('end_time', '00:00')
        power = parse_int(t.get('power', 100))
        soc = parse_int(t.get('soc', 100))
        
        try:
            sh, sm = map(int, start_time.split(':'))
            eh, em = map(int, end_time.split(':'))
        except Exception:
            continue
            
        start_min = sh * 60 + sm
        end_min = eh * 60 + em
        
        if end_min <= start_min:
            continue
            
        # Overwrite grid segment (later task in list overrides earlier)
        for m in range(start_min, end_min):
            grid[m] = (power, soc, idx)
            
    # 3. Reconstruct continuous segments from the grid
    segments = []
    current_segment = None
    
    for m in range(1440):
        val = grid[m]
        if val is not None:
            power, soc, idx = val
            if current_segment is None:
                current_segment = {
                    'start': m,
                    'end': m + 1,
                    'power': power,
                    'soc': soc,
                    'task_index': idx
                }
            else:
                if current_segment['task_index'] == idx:
                    current_segment['end'] = m + 1
                else:
                    segments.append(current_segment)
                    current_segment = {
                        'start': m,
                        'end': m + 1,
                        'power': power,
                        'soc': soc,
                        'task_index': idx
                    }
        else:
            if current_segment is not None:
                segments.append(current_segment)
                current_segment = None
                
    if current_segment is not None:
        segments.append(current_segment)
        
    if not segments:
        return [], 100, 100

    # Global Power & SoC: "push-epoch" selection — the LATEST segment whose pre-window
    # push moment (start - 15 min) has already passed relative to reference_minute. This
    # is the value the device SHOULD be holding right now, which makes one rule serve
    # everything consistently:
    #   * pre-window pushes (23:45 / 11:45) land exactly at a segment's epoch start, so
    #     they push that segment's values;
    #   * drift comparison between windows expects the PREVIOUS window's value (no phantom
    #     drift on e.g. weekend mornings while the free window's push is still pending);
    #   * editing a not-yet-started window changes nothing until its own push moment —
    #     while editing the CURRENTLY ACTIVE window mismatches immediately -> instant write.
    if reference_minute is None:
        ref_seg = segments[-1]
    else:
        ref_seg = None
        for s in segments:  # segments are chronological
            if s['start'] - 15 <= reference_minute:
                ref_seg = s
        if ref_seg is None:
            ref_seg = segments[0]  # before the day's first epoch (unusual config)
    global_power = ref_seg['power']
    global_soc = ref_seg['soc']
    
    # Mix inverter only has 3 slots. If more than 3 segments exist, keep 3 longest
    if len(segments) > 3:
        segments_sorted = sorted(segments, key=lambda s: s['end'] - s['start'], reverse=True)
        segments = sorted(segments_sorted[:3], key=lambda s: s['start'])
        print("Warning: Trimmed resolved schedule to 3 longest segments.")
        
    return segments, global_power, global_soc

def _compare_schedule(current_settings, is_token_mode, target_params):
    """Compares the inverter's charge-power %, target-SoC %, and forced charge switch state
    against the resolved target.
    Returns (matches, actual_summary) with tri-state: None = data unavailable."""
    if not current_settings:
        return None, "unavailable"
    
    st_dict = current_settings.get('settings', current_settings) if isinstance(current_settings, dict) else current_settings
    obj_dict = st_dict.get('obj', st_dict) if isinstance(st_dict, dict) else st_dict
    obj = obj_dict.get('mixBean', obj_dict) if isinstance(obj_dict, dict) else obj_dict
    
    curr_power = obj.get("chargePowerCommand")
    curr_soc = obj.get("wchargeSOCLowLimit2")
    if curr_soc is None:
        curr_soc = obj.get("wchargeSOCLowLimit1")
    
    curr_forced_sw = obj.get("forcedChargeStopSwitch1")
    curr_ac_chg = obj.get("acChargeEnable")

    if curr_power is None and curr_soc is None and curr_forced_sw is None:
        # Transient garbage from the Growatt API (occasional timeouts / partial payloads).
        # Tri-state None = "no data": do NOT raise a drift alarm and do NOT trigger any
        # in-window corrective write off bad data — the next 5-min cycle re-reads.
        return None, "unavailable"

    target_pwr = str(target_params[0]) if len(target_params) > 0 else "100"
    target_soc = str(target_params[1]) if len(target_params) > 1 else "100"
    target_ac_chg = str(target_params[2]) if len(target_params) > 2 else "1"
    target_forced_sw = str(target_params[7]) if len(target_params) > 7 else "1"

    matches = (
        str(curr_power) == target_pwr and
        str(curr_soc) == target_soc and
        (curr_forced_sw is None or str(curr_forced_sw) == target_forced_sw) and
        (curr_ac_chg is None or str(curr_ac_chg) == target_ac_chg)
    )
    summary = f"SoC {curr_soc}%, power {curr_power}%, forcedSwitch1 {curr_forced_sw}, acCharge {curr_ac_chg}"
    return matches, summary


def compute_physics_modeled_soc(raw_bms_soc, pack_voltage, charge_kw, discharge_kw, temp_c=15.0, bms_delta_mv=0.0, prev_modeled_soc=None, dt_minutes=5.0, r_int_mohm=15.0, battery_kwh=30.0):
    """
    Enhanced Physics-Informed EKF Battery SOC Estimator with Dynamic Temperature & Cell Imbalance Derating.
    - Incorporates Arrhenius Temperature-Resistance scaling R(T)
    - Incorporates Cell Voltage Imbalance Derating factor
    - Cancels out dynamic I*R voltage sag during heavy load
    """
    if pack_voltage <= 0:
        return float(raw_bms_soc) if raw_bms_soc is not None else 0.0
    
    # 1. Calculate battery current (A) [Positive = Discharge, Negative = Charge]
    net_power_kw = discharge_kw - charge_kw
    current_a = (net_power_kw * 1000.0) / max(40.0, pack_voltage)
    
    # 2. Advanced Temperature-compensated internal resistance R_int (Ohm)
    # Arrhenius-inspired non-linear resistance increase in cold environments (< 25°C)
    delta_t_cold = max(0.0, 25.0 - temp_c)
    temp_factor = 1.0 + (0.045 * delta_t_cold) + (0.001 * (delta_t_cold ** 2))
    r_effective_ohm = (r_int_mohm / 1000.0) * temp_factor
    
    # 3. Cell Imbalance Derating Factor
    # High cell voltage delta (> 30 mV) reduces usable electrochemical capacity
    imbalance_derate = 1.0
    if bms_delta_mv > 30.0:
        imbalance_derate = max(0.85, 1.0 - (min(300.0, bms_delta_mv - 30.0) / 1000.0))
    effective_capacity_kwh = max(10.0, battery_kwh * imbalance_derate)

    # 4. Voltage sag restoration: V_ocv_restored = V_pack + I * R_int
    v_ocv_restored = pack_voltage + (current_a * r_effective_ohm)
    cell_ocv = v_ocv_restored / 16.0
    
    # 5. Cell OCV-to-SOC Estimation Curve for LFP 16S (Accurate Electrochemical Plateau)
    # 3.45V+ = 100%, 3.35V = 90%, 3.32V = 80%, 3.28V = 50%, 3.25V = 20%
    ocv_temp_shift = (temp_c - 25.0) * 0.0005
    adj_cell_ocv = cell_ocv - ocv_temp_shift

    if adj_cell_ocv >= 3.45:
        ocv_soc = 100.0
    elif adj_cell_ocv >= 3.35:
        ocv_soc = 90.0 + (adj_cell_ocv - 3.35) / (3.45 - 3.35) * 10.0
    elif adj_cell_ocv >= 3.32:
        ocv_soc = 80.0 + (adj_cell_ocv - 3.32) / (3.35 - 3.32) * 10.0
    elif adj_cell_ocv >= 3.28:
        ocv_soc = 50.0 + (adj_cell_ocv - 3.28) / (3.32 - 3.28) * 30.0
    elif adj_cell_ocv >= 3.25:
        ocv_soc = 20.0 + (adj_cell_ocv - 3.25) / (3.28 - 3.25) * 30.0
    elif adj_cell_ocv >= 3.00:
        ocv_soc = 5.0 + (adj_cell_ocv - 3.00) / (3.25 - 3.00) * 15.0
    else:
        ocv_soc = max(0.0, (adj_cell_ocv - 2.50) / (3.00 - 2.50) * 5.0)
        
    # 6. Ampere-Hour Coulomb Integration: ΔQ_kWh = P_net * Δt_hours
    delta_kwh = net_power_kw * (dt_minutes / 60.0)
    delta_soc_pct = (delta_kwh / effective_capacity_kwh) * 100.0
    
    base_soc = prev_modeled_soc if (prev_modeled_soc is not None and prev_modeled_soc > 0) else float(raw_bms_soc if raw_bms_soc is not None else 50.0)
    coulomb_soc = base_soc - delta_soc_pct
    
    # 7. Adaptive EKF Kalman gain blending & End-of-Charge Boundary Anchor
    current_mag = abs(current_a)
    raw_soc_num = float(raw_bms_soc) if raw_bms_soc is not None else 50.0

    if adj_cell_ocv >= 3.45:
        modeled_soc = 100.0
    elif raw_soc_num >= 95.0 and adj_cell_ocv >= 3.30:
        # End-of-Charge Boundary Anchor:
        # Breaks EKF algorithm deadlock on flat LFP plateau when BMS reports >= 95% & cell OCV >= 3.30V.
        # Smoothly pulls AI SOC towards 98%-100% saturation target instead of trapping at 92.1%.
        target_anchor = max(raw_soc_num, 98.0)
        blend_factor = 0.50  # Active pull towards full charge anchor
        modeled_soc = (1.0 - blend_factor) * coulomb_soc + blend_factor * target_anchor
    elif raw_soc_num > 15.0 and raw_soc_num < 95.0:
        # On LFP Discharge Plateau: Trust Pure Coulomb Ah Integration 95% + 5% BMS smooth tracking
        # Prevents voltage fluctuations from artificially pulling down AI SOC during discharge
        modeled_soc = 0.95 * coulomb_soc + 0.05 * raw_soc_num
    else:
        kalman_k = max(0.02, min(0.10, (30.0 - current_mag) / 30.0 * 0.10))
        modeled_soc = (1.0 - kalman_k) * coulomb_soc + kalman_k * ocv_soc
        
    return round(max(0.0, min(100.0, modeled_soc)), 1)


def compute_cold_weather_battery_limits(temp_c: float, prev_discharge_limit_pct: int = 100) -> tuple[int, int, int, str]:
    """
    Cold Weather Battery Protection Engine with Golden Balance Hysteresis (2°C / 5°C).
    - Discharge Power: < 2°C -> 50% limit (2.5 kW max) to prevent voltage sag, > 5°C -> 100% restored (5.0 kW max).
    - Charge Power (Lithium Plating Protection): < 0°C -> 0%, 0-2°C -> 30% trickle charge, >= 2°C -> 100%.
    - Dynamic Min SOC Floor: < 2°C -> 25% floor, >= 2°C -> 10% floor.
    """
    # 1. Hysteresis Discharge Power Limit (2°C vs 5°C Golden Balance for Spring/Winter)
    if temp_c < 2.0:
        discharge_limit_pct = 50
        status_note = f"COLD PROTECTION ACTIVE ({temp_c:.1f}°C < 2.0°C): Discharge power capped at 50% (2.5 kW max) to prevent voltage sag."
    elif temp_c > 5.0:
        discharge_limit_pct = 100
        status_note = f"NORMAL TEMP ({temp_c:.1f}°C > 5.0°C): Discharge power restored to 100% (5.0 kW max)."
    else:
        discharge_limit_pct = prev_discharge_limit_pct
        status_note = f"HYSTERESIS ZONE ({temp_c:.1f}°C in 2-5°C): Discharge power limit held at {discharge_limit_pct}%."

    # 2. Lithium Plating Prevention Charging Limit
    if temp_c < 0.0:
        charge_limit_pct = 0  # Strict zero-charge under freezing to prevent lithium dendrites
    elif temp_c < 2.0:
        charge_limit_pct = 30  # Slow trickle charge under cold temp (< 2°C)
    else:
        charge_limit_pct = 100

    # 3. Dynamic Min SOC Defense Floor
    min_soc_floor = 25 if temp_c < 2.0 else 10

    return discharge_limit_pct, charge_limit_pct, min_soc_floor, status_note


def evaluate_daytime_high_soc_llm(context: dict, api_key: str) -> dict:
    """
    Evaluates whether to activate daytime high-SoC protection (Grid First) using Gemini LLM.
    If the LLM call fails, times out, is rate-limited, or returns invalid JSON,
    it falls back completely and seamlessly to the deterministic rule-based logic.
    """
    in_window = bool(context.get('in_solar_protect_window', False))
    is_winter = bool(context.get('is_winter', False))
    is_cal_due = bool(context.get('is_cal_due', False))
    has_solar_surplus = bool(context.get('has_solar_surplus', False))
    soc_num = float(context.get('soc_num', 0.0))
    live_ppv = float(context.get('live_ppv', 0.0))
    pv_fc = float(context.get('pv_fc', 0.0))
    load_fc = float(context.get('load_fc', 0.0))
    
    # 1. Deterministic baseline computation (gold standard fallback)
    fallback_should_protect = (
        in_window and 
        not is_winter and 
        has_solar_surplus and 
        not is_cal_due and 
        (soc_num >= 80.0) and 
        (live_ppv >= 1.5)
    )
    fallback_result = {
        "should_protect": fallback_should_protect,
        "confidence": 1.0,
        "source": "deterministic_rule_engine",
        "reasoning": (
            f"Rule Engine Fallback: window={in_window}, winter={is_winter}, cal_due={is_cal_due}, "
            f"surplus={has_solar_surplus} (PV fc {pv_fc:.1f}kWh vs Load {load_fc:.1f}kWh), "
            f"SoC={soc_num:.1f}%, Live PV={live_ppv:.2f}kW."
        )
    }

    # Absolute safety guardrails: if calibration is due, outside 9-17, or winter, never protect (always Load First)
    if is_cal_due or not in_window or is_winter:
        fallback_result["reasoning"] = f"Safety Guardrail: Calibration={is_cal_due}, InWindow={in_window}, Winter={is_winter}. Load First maintained."
        return fallback_result

    # If no Gemini API key configured, use deterministic fallback directly
    if not api_key:
        fallback_result["reasoning"] += " (No Gemini API key configured)."
        return fallback_result

    prompt = f"""You are an expert energy management system AI optimizing an LFP home battery and Growatt hybrid solar inverter.
Your objective: Decide whether to activate 'Grid First' mode (to prevent high-voltage 100% SoC dwell degradation under hot sun) or maintain 'Load First' mode (to prioritize powering the household and charging the battery).

Key domain rules:
1. Cell Longevity vs Dwell: LFP batteries degrade faster if sitting at 100% full-voltage in hot daytime sun for hours. If battery SoC >= 80% and daytime solar is abundant, exporting surplus solar to the grid (Grid First) protects battery longevity.
2. Household Sufficiency & Weather: If it is winter, or if weather/forecast is poor/cloudy/rainy (low solar), NEVER starve the household — keep Load First so the battery can soak up all available solar.
3. BMS Top-Balancing: If BMS calibration is due (or calibration mode is active), top-balancing at 100% SoC is strictly mandatory — NEVER switch to Grid First.
4. Time Window: High-SoC protection is only applicable during strong daytime solar hours (09:00 - 17:00).

Current Status:
- Local time: {context.get('local_time_str', '12:00')} (Month: {context.get('month', 1)} - {'Winter' if is_winter else 'Non-Winter'} in Australia)
- Battery SoC: {soc_num:.1f}%
- Live PV solar power: {live_ppv:.2f} kW
- Live home load: {float(context.get('live_load_kw', 0.0)):.2f} kW
- Today PV Forecast: {pv_fc:.1f} kWh
- Today Load Forecast: {load_fc:.1f} kWh
- BMS Calibration Due: {is_cal_due}
- Current Inverter Priority: {context.get('curr_priority', '0')} ({'Grid First' if context.get('curr_priority') == '2' else 'Load First'})

Return ONLY a valid JSON object:
{{"should_protect": boolean, "confidence": float, "reasoning": string}}"""

    model_candidates = ["gemini-2.5-flash", "gemini-flash-latest"]
    for model in model_candidates:
        try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            payload = {
                "contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {
                    "responseMimeType": "application/json",
                    "temperature": 0.2
                }
            }
            resp = requests.post(url, json=payload, timeout=6)
            if resp.status_code == 200:
                resp_json = resp.json()
                raw_text = resp_json['candidates'][0]['content']['parts'][0]['text']
                parsed = json.loads(raw_text)
                should_protect = bool(parsed.get('should_protect', False))
                confidence = float(parsed.get('confidence', 0.9))
                reasoning = str(parsed.get('reasoning', '')).strip()

                # Safety guardrail check: if LLM mistakenly recommended protecting while calibration is due, veto it
                if is_cal_due and should_protect:
                    print("⚠️ LLM suggested Grid First, but vetoed by BMS calibration safety lock!")
                    return fallback_result

                return {
                    "should_protect": should_protect,
                    "confidence": confidence,
                    "source": model,
                    "reasoning": reasoning
                }
            else:
                print(f"Notice: Gemini model {model} returned HTTP {resp.status_code}: {resp.text[:120]}")
        except Exception as e:
            print(f"Notice: LLM call to {model} failed: {e}")

    print("⚠️ All LLM candidates failed or timed out. Falling back seamlessly to deterministic rule engine.")
    return fallback_result


def evaluate_charging_plan_llm(context: dict, api_key: str) -> dict:
    """
    Evaluates baseline MPC charging plan using Gemini LLM:
    1. Strategy Advisor: Safely reviews and micro-adjusts target SoC (-10% to +10%) within strict physical boundaries.
       Guaranteed Guardrail: If BMS calibration is due, target SoC is strictly locked (delta=0).
    2. Strategy Explainer: Generates a 2-sentence articulate, friendly, and professional executive briefing in Chinese.
    Seamless Fallback: If no API key, timeout (7s), or failure, immediately falls back to deterministic MPC baseline.
    """
    mpc_target = int(context.get('mpc_target_soc', 50))
    is_cal_due = bool(context.get('is_calibration_due', False))
    pv_fc = float(context.get('pv_forecast_kwh', 0.0))
    load_fc = float(context.get('load_forecast_kwh', 0.0))
    min_allowed = int(context.get('min_allowed_soc', 15))
    max_allowed = int(context.get('max_allowed_soc', 90))

    fallback_briefing = (
        f"明日预测光伏 {pv_fc:.1f} kWh、家庭用电 {load_fc:.1f} kWh。"
        f"{'BMS 7天校准周期已到达：今晚顶格充至 100% 进行电芯高压均衡。' if is_cal_due else f'MPC 优化调度建议：夜间谷电维持 {mpc_target}% 目标，兼顾白天光伏消纳与用电安全。'}"
    )
    fallback_result = {
        "adjustment_delta_soc": 0,
        "final_target_soc": mpc_target,
        "ai_briefing": fallback_briefing,
        "adjustment_reason": "MPC 原始目标保持不变 (确定性基线)。",
        "confidence": 1.0,
        "source": "mpc_rule_engine"
    }

    if not api_key:
        return fallback_result

    prompt = f"""You are an elite energy management system AI optimizing an LFP home battery (rated {context.get('battery_rated_kwh', 30.0)} kWh) and Growatt hybrid solar inverter, co-operating with a Tesla EV and Australian electricity tariffs.

Your dual mission:
1. STRATEGY ADVISOR (Review & Micro-adjustment):
   Review the baseline target SoC calculated by the physical MPC (Model Predictive Control) optimizer for the 00:00-06:00 off-peak charging window.
   - Normal Days: You may fine-tune the target SoC by -10% to +10% (adjustment_delta_soc) within the absolute safe envelope [{min_allowed}%, {max_allowed}%].
     * Lower target (-5% to -10%): if tomorrow has intense solar surplus, or Tesla EV is home and can absorb energy overnight (creating empty battery sponge).
     * Higher target (+5% to +10%): if tomorrow has high weather uncertainty / heavy cloud / rain, or freezing night temperature (< 2°C).
     * Keep target (0%): if MPC baseline is already optimal.
   - BMS Calibration Days: If BMS Calibration is DUE, top-balancing at 100% (or PV-assisted target) is strictly required to balance LFP cells. You MUST NOT decrease target SoC (adjustment_delta_soc MUST be 0).

2. STRATEGY EXPLAINER (AI 能量管家简报):
   Write an articulate, friendly, concise, and professional 2-sentence executive summary in Chinese ('ai_briefing') for the homeowner.
   Highlight:
   - Tomorrow's solar & load outlook
   - The overnight battery action (charging to X% or discharging to EV) and the strategic benefit (e.g. saving money, avoiding peak grid buy, or absorbing solar surplus).

Current System Context for {context.get('for_date')} ({context.get('day_name')}):
- Current Battery SoC: {context.get('soc_now', 50.0):.1f}% (Rated: {context.get('battery_rated_kwh', 30.0)} kWh)
- Baseline MPC Target SoC: {mpc_target}%
- Allowed Safe SoC Range: [{min_allowed}%, {max_allowed}%]
- Tomorrow PV Forecast: {pv_fc:.1f} kWh | Load Forecast: {load_fc:.1f} kWh (PV/Load Ratio: {context.get('pv_load_ratio', 1.0):.2f})
- Overnight Min Temperature: {context.get('min_overnight_temp', 15.0):.1f}°C ({'Cold Protection Triggered' if context.get('is_cold_overnight') else 'Mild'})
- BMS 7-Day Calibration Due: {is_cal_due} (Days since last: {context.get('days_since_cal', 0)})
- Off-peak Rate: ${context.get('offpeak_rate', 0.08):.4f}/kWh | Peak Rate: ${context.get('peak_rate', 0.35):.4f}/kWh | Export FIT: ${context.get('export_rate', 0.05):.4f}/kWh
- Tesla EV: {context.get('ev_status_desc', 'Not plugged in')}

Return ONLY a valid JSON object:
{{
  "adjustment_delta_soc": integer between -10 and 10,
  "adjustment_reason": string explaining why or why not adjusted,
  "ai_briefing": string (2-sentence natural language summary in Chinese for the homeowner),
  "confidence": float between 0.0 and 1.0
}}"""

    model_candidates = ["gemini-2.5-flash", "gemini-flash-latest"]
    for model in model_candidates:
        try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            payload = {
                "contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {
                    "responseMimeType": "application/json",
                    "temperature": 0.2
                }
            }
            resp = requests.post(url, json=payload, timeout=7)
            if resp.status_code == 200:
                resp_json = resp.json()
                raw_text = resp_json['candidates'][0]['content']['parts'][0]['text']
                parsed = json.loads(raw_text)

                delta = int(parsed.get('adjustment_delta_soc', 0))
                # Bound delta to [-10, 10]
                delta = max(-10, min(10, delta))

                # Hard Guardrail 1: Calibration mode cannot be adjusted down
                if is_cal_due and delta < 0:
                    print("⚠️ LLM suggested reducing calibration target, vetoed by BMS safety guardrail!")
                    delta = 0

                final_soc = max(min_allowed, min(max_allowed, mpc_target + delta))
                actual_delta = final_soc - mpc_target

                briefing = str(parsed.get('ai_briefing', '')).strip()
                if not briefing:
                    briefing = fallback_briefing

                reason = str(parsed.get('adjustment_reason', '')).strip()

                return {
                    "adjustment_delta_soc": actual_delta,
                    "final_target_soc": final_soc,
                    "ai_briefing": briefing,
                    "adjustment_reason": reason,
                    "confidence": float(parsed.get('confidence', 0.95)),
                    "source": model
                }
            else:
                print(f"Notice: Gemini model {model} returned HTTP {resp.status_code}: {resp.text[:120]}")
        except Exception as e:
            print(f"Notice: Charging plan LLM call to {model} failed: {e}")

    print("⚠️ Charging plan LLM call failed or timed out. Falling back to deterministic MPC baseline.")
    return fallback_result


def run_sync_logic(trigger_type: str, mode: str = "sync") -> dict:
    db = firestore.client()
    settings_ref = db.collection('settings').document('growatt')
    settings_doc = settings_ref.get()

    if not settings_doc.exists:
        error_msg = "Settings document settings/growatt does not exist in Firestore"
        print(f"Error: {error_msg}")
        return {'status': 'error', 'message': error_msg}

    # Initialize device_sn and plant_id — must be declared here so Python does not
    # treat them as unbound locals when the conditional auto-discovery branches run below.
    device_sn = settings_doc.to_dict().get('device_sn', '')
    plant_id = ''

    settings = settings_doc.to_dict()
    username = settings.get('username')
    password = settings.get('password')
    tz_name = settings.get('timezone', 'Australia/Sydney')

    # --- DEMO MODE GUARD ---
    # Never attempt real Growatt API calls when using demo account
    if username == 'demo@xgrowatt.com':
        msg = "Demo mode active — Growatt API sync skipped."
        print(msg)
        log_run_status(db, trigger_type, "success", msg)
        return {"status": "success", "message": msg, "demo": True}

    api_token = settings.get('api_token')
    
    if not api_token and (not username or not password):
        error_msg = "Growatt credentials (username/password or API Token) are not configured in Firestore settings"
        log_run_status(db, trigger_type, "error", error_msg)
        return {"status": "error", "message": error_msg}

    # Resolve local time
    try:
        local_now = datetime.datetime.now(ZoneInfo(tz_name))
    except Exception:
        local_now = datetime.datetime.now(ZoneInfo('Australia/Sydney'))
        tz_name = 'Australia/Sydney'

    is_token_mode = bool(api_token)
    
    # Fallback to legacy mode for schedule writes because OpenAPI V1 complex time segment writes 
    # are not yet fully standardized in the growattServer library for MIN devices.
    if mode == "sync" and is_token_mode:
        if username and password:
            print("Write mode requested: Forcing Legacy mode for schedule compatibility.")
            is_token_mode = False
        else:
            error_msg = "Schedule syncing requires Legacy Username/Password mode. Token-only writing is not supported yet."
            log_run_status(db, trigger_type, "error", error_msg)
            return {"status": "error", "message": error_msg}
    try:
        if is_token_mode:
            try:
                print("Using official Growatt OpenAPI V1 token mode.")
                api = growattServer.OpenApiV1(token=api_token)
                
                # Resolve plant list
                plant_list = api.plant_list()
                plants = plant_list.get('plants', [])
                if not plants:
                    raise ValueError("No solar plants found in Growatt account using OpenAPI V1")
                plant_id = str(plants[0]['plant_id'])
                
                # Fetch device list
                device_list = api.device_list(int(plant_id))
                devices = device_list.get('devices', [])
                
                # Auto-discover device serial number if not provided
                if not device_sn:
                    for dev in devices:
                        if dev.get('type') == 5:  # Prioritize MIX inverters
                            device_sn = dev.get('device_sn')
                            break
                    if not device_sn and devices:
                        device_sn = devices[0].get('device_sn')
                        
                    if not device_sn:
                        raise ValueError("No inverter device discovered on your Growatt account")
            except Exception as token_err:
                if username and password:
                    print(f"OpenAPI V1 setup failed ({str(token_err)}). Falling back to Legacy mode...")
                    is_token_mode = False
                else:
                    raise token_err

        if not is_token_mode:
            print("Using legacy username/password mode with Session caching.")
            # Initialize API client with randomized user id to bypass simple WAF blocklists
            api = growattServer.GrowattApi(add_random_user_id=True)
            
            login_response = None
            primary_url = api.server_url
            
            # Override with custom server URL if configured in settings
            # Override with custom server URL if configured in settings (ignore token-based domains for legacy mode)
            custom_url = settings.get('server_url')
            if custom_url and "openapi" in custom_url:
                print("Ignoring token-based 'openapi' domain for legacy mode.")
                custom_url = None
                
            if custom_url:
                api.server_url = custom_url
                primary_url = custom_url
                
            # 1. Attempt to restore cached session from Firestore
            session_ref = db.collection("status").document("growatt_session")
            session_doc = session_ref.get()
            
            session_valid = False
            user_id = None
            import requests
            
            if session_doc.exists:
                session_data = session_doc.to_dict()
                cached_cookies = session_data.get("cookies")
                cached_user_id = session_data.get("userId")
                cached_server_url = session_data.get("server_url")
                
                if cached_cookies and cached_user_id:
                    print("Found cached Growatt session. Attempting to reuse...")
                    api.session.cookies.update(requests.utils.cookiejar_from_dict(cached_cookies))
                    if cached_server_url and "openapi" not in cached_server_url:
                        api.server_url = cached_server_url
                        primary_url = cached_server_url
                    else:
                        api.server_url = "https://server-au.growatt.com/"
                        primary_url = "https://server-au.growatt.com/"
                    
                    try:
                        # Validate the session with a lightweight check (getting plant list)
                        plant_list = api.plant_list(cached_user_id)
                        if plant_list and 'data' in plant_list:
                            print("Session is valid! Bypassed login.")
                            user_id = cached_user_id
                            session_valid = True
                    except Exception as e:
                        print(f"Cached session validation failed: {str(e)}. Proceeding to fresh login...")
                        
            # 2. If session is not valid, perform a fresh login
            if not session_valid:
                if "openapi" in primary_url:
                    primary_url = "https://server-au.growatt.com/"
                    api.server_url = primary_url
                print(f"Attempting login on {primary_url}...")
                try:
                    login_response = api.login(username, password)
                except Exception as e:
                    print(f"Login failed on {primary_url} with error: {str(e)}")
                    
                    # If a custom URL was configured and failed, don't try fallback unless it was default
                    if custom_url:
                        raise e
                        
                    # Toggle URL and retry once (openapi.growatt.com <-> server.growatt.com)
                    alternative_url = "https://server.growatt.com/" if "openapi" in primary_url else "https://openapi.growatt.com/"
                    print(f"Retrying login with alternative server URL: {alternative_url}...")
                    api.server_url = alternative_url
                    try:
                        login_response = api.login(username, password)
                    except Exception as retry_e:
                        raise ValueError(f"Login failed on both Growatt server URLs. Primary Error: {str(e)}. Fallback Error: {str(retry_e)}")
        
                user_id = login_response.get('userId')
                if not user_id:
                    raise ValueError(f"Login response did not return a userId: {login_response}")
                    
                # Save the new valid session details to Firestore
                new_cookies = requests.utils.dict_from_cookiejar(api.session.cookies)
                session_ref.set({
                    "userId": user_id,
                    "cookies": new_cookies,
                    "server_url": api.server_url,
                    "timestamp": firestore.SERVER_TIMESTAMP
                })
                print("Successfully logged in and saved new session to Firestore.")
    
            # Resolve plant list
            plant_list = api.plant_list(user_id)
            if not plant_list or 'data' not in plant_list or len(plant_list['data']) == 0:
                raise ValueError("No solar plants found in Growatt account")
            
            plant_id = plant_list['data'][0]['plantId']
            device_list = api.device_list(plant_id)
            
            # Auto-discover device serial number if not provided
            if not device_sn:
                for dev in device_list:
                    device_sn = dev.get('deviceSn')
                    if device_sn:
                        break
                
                if not device_sn:
                    raise ValueError("No inverter device discovered on your Growatt account")

        # --- RETRIEVE LIVE DATA FIRST ---
        print(f"Retrieving live system status for device: {device_sn}...")
        live_status = {}
        try:
            import time as _time
            last_read_err = None
            for attempt in range(3):
                try:
                    if is_token_mode:
                        live_status = api.sph_energy(device_sn)
                    else:
                        live_status = api.mix_system_status(device_sn, plant_id)
                    last_read_err = None
                    break
                except Exception as e:
                    last_read_err = e
                    if attempt < 2:
                        print(f"Live status read attempt {attempt + 1} failed: {str(e)}. Attempting fresh login...")
                        try:
                            if not is_token_mode:
                                login_response = api.login(username, password)
                                new_cookies = requests.utils.dict_from_cookiejar(api.session.cookies)
                                db.collection("status").document("growatt_session").set({
                                    "userId": login_response.get("userId"),
                                    "cookies": new_cookies,
                                    "server_url": api.server_url,
                                    "timestamp": firestore.SERVER_TIMESTAMP
                                }, merge=True)
                        except Exception as ex_relogin:
                            print(f"Fresh login attempt failed: {str(ex_relogin)}")
                        _time.sleep(2)
            if last_read_err is not None:
                raise last_read_err
            print(f"Retrieved live status: {live_status}")
            
            # Parse clean numeric values first so we can map them back into the raw dictionary for the legacy iOS app
            if is_token_mode:
                # OpenAPI V1 (sph_energy) returns power in W, voltage in V, energy in kWh
                soc_val = parse_int(live_status.get("soc", 0))
                solar_generation_kw = round(parse_kw(live_status.get("ppv", 0.0)) / 1000.0, 3)
                charge_power_kw = round(parse_kw(live_status.get("pcharge1", 0.0)) / 1000.0, 3)
                discharge_power_kw = round(parse_kw(live_status.get("pdischarge1", 0.0)) / 1000.0, 3)
                local_load_kw = round(parse_kw(live_status.get("plocalLoadTotal", 0.0)) / 1000.0, 3)
                grid_export_kw = round(parse_kw(live_status.get("pacToGridTotal", 0.0)) / 1000.0, 3)
                grid_import_kw = round(parse_kw(live_status.get("pacToUserTotal", 0.0)) / 1000.0, 3)
                battery_voltage = parse_kw(live_status.get("vbat", 0.0))           # V, no conversion
                # bmsGaugeRM is NOT kWh — it's a BMS internal counter (bmsGaugeRM/bmsGaugeFCC ≈ SOC).
                # Compute remaining energy from SOC × rated capacity (read from last saved inverter settings).
                _inv_settings_doc = db.collection('status').document('growatt_inverter_settings').get()
                _rated_kwh = 30.0  # safe fallback
                if _inv_settings_doc.exists:
                    _raw = _inv_settings_doc.to_dict().get('data', {})
                    _rated_kwh = float(_raw.get('batSysRateEnergy', 30.0) or 30.0)
                battery_energy_kwh = round(soc_val / 100.0 * _rated_kwh, 2)
                
                # INJECT legacy-compatible fields back into live_status so iOS app reads them correctly
                live_status["SOC"] = str(soc_val)
                live_status["ppv"] = str(solar_generation_kw)
                live_status["chargePower"] = str(charge_power_kw)
                live_status["pdisCharge1"] = str(discharge_power_kw)
                live_status["pLocalLoad"] = str(local_load_kw)
                live_status["pactogrid"] = str(grid_export_kw)
                live_status["pactouser"] = str(grid_import_kw)
                live_status["vBat"] = str(battery_voltage)
                live_status["bmsBatteryEnergy"] = f"{battery_energy_kwh}kWh"
            else:
                soc_val = parse_int(live_status.get("SOC", 0))
                solar_generation_kw = parse_kw(live_status.get("ppv", 0.0))
                charge_power_kw = parse_kw(live_status.get("chargePower", 0.0))
                discharge_power_kw = parse_kw(live_status.get("pdisCharge1", 0.0))
                local_load_kw = parse_kw(live_status.get("pLocalLoad", 0.0))
                grid_export_kw = parse_kw(live_status.get("pactogrid", 0.0))
                grid_import_kw = parse_kw(live_status.get("pactouser", 0.0))
                battery_voltage = parse_kw(live_status.get("vBat", 0.0))
                battery_energy_kwh = parse_kwh(live_status.get("bmsBatteryEnergy", 0.0))
            
            # --- Per-MPPT string data (SPH has 2 trackers). Numeric per-string fields are
            # Watts in BOTH payload styles (verified against a live legacy payload where
            # pdischarge1=270 [W] matches pdisCharge1="0.27" [kW]) — always convert W->kW.
            # No magnitude heuristic: it would misread small dawn/dusk readings (15 W) as kW.
            def _mppt_raw(*keys):
                for k in keys:
                    if k in live_status and live_status[k] is not None:
                        return parse_kw(live_status[k])
                return None

            def _mppt_power_kw(*keys):
                p = _mppt_raw(*keys)
                if p is None:
                    return None
                return round(p / 1000.0, 3)

            pv1_power_kw = _mppt_power_kw('ppv1', 'pPv1', 'pPV1')
            pv2_power_kw = _mppt_power_kw('ppv2', 'pPv2', 'pPV2')
            pv1_voltage = _mppt_raw('vpv1', 'vPv1')
            pv2_voltage = _mppt_raw('vpv2', 'vPv2')

            # Compute Enhanced Physics-Informed Modeled SOC
            try:
                # Fetch prev_modeled_soc safely from the latest telemetry_history entry
                prev_modeled_soc = None
                try:
                    latest_tele = db.collection('telemetry_history').order_by('timestamp', direction=firestore.Query.DESCENDING).limit(1).get()
                    if latest_tele and len(latest_tele) > 0:
                        prev_modeled_soc = latest_tele[0].to_dict().get('modeled_soc')
                except Exception:
                    pass

                health_params_doc = db.collection('status').document('battery_health_params').get()
                r_int_mohm = 15.0
                battery_kwh = 30.0
                if health_params_doc.exists:
                    pdata = health_params_doc.to_dict()
                    r_int_mohm = pdata.get('fitted_internal_resistance_mohm', 15.0)
                    battery_kwh = pdata.get('calibrated_capacity_kwh', 30.0)
                    if prev_modeled_soc is None:
                        prev_modeled_soc = pdata.get('last_modeled_soc')

                # Fetch live ambient temperature from weather forecast snapshot
                ambient_temp_c = 15.0
                try:
                    weather_doc = db.collection('status').document('weather_forecast').get()
                    if weather_doc.exists:
                        ambient_temp_c = float(weather_doc.to_dict().get('current_temperature_c', 15.0))
                except Exception:
                    pass

                # Clean valid single cell voltages (2.5V to 3.85V LFP single cell range)
                raw_cells = live_status.get('cellVoltages') or []
                valid_cells = [float(v) for v in raw_cells if 2.5 <= float(v) <= 3.85]
                if len(valid_cells) >= 2:
                    bms_delta_mv = round((max(valid_cells) - min(valid_cells)) * 1000.0, 1)
                else:
                    bms_delta_mv = float(live_status.get('bmsDeltaVolt', 12.0) or 12.0)

                modeled_soc = compute_physics_modeled_soc(
                    raw_bms_soc=soc_val,
                    pack_voltage=battery_voltage,
                    charge_kw=charge_power_kw,
                    discharge_kw=discharge_power_kw,
                    temp_c=ambient_temp_c,
                    bms_delta_mv=bms_delta_mv,
                    prev_modeled_soc=prev_modeled_soc,
                    r_int_mohm=r_int_mohm,
                    battery_kwh=battery_kwh
                )
                live_status['modeled_soc'] = str(modeled_soc)
                live_status['modeledSOC'] = str(modeled_soc)
                db.collection('status').document('battery_health_params').set({
                    'last_modeled_soc': modeled_soc,
                    'last_ambient_temp_c': ambient_temp_c,
                    'last_bms_delta_mv': bms_delta_mv,
                    'last_updated': firestore.SERVER_TIMESTAMP
                }, merge=True)
            except Exception as ex_soc:
                print(f"Warning: Failed to compute physics modeled_soc: {str(ex_soc)}")
                modeled_soc = float(soc_val) if soc_val is not None else 0.0

            # --- Strict BMS Cell Balancing & Calibration Recorder ---
            # To certify a successful calibration, the battery must:
            # 1. Reach BMS SOC >= 98%
            # 2. Reach AI Modeled SOC >= 91%
            # 3. Maintain High-SOC / Full Dwell Voltage state for at least 60 minutes (12 x 5min samples)
            soc_num = float(soc_val) if soc_val is not None else 0.0
            msoc_num = float(modeled_soc) if modeled_soc is not None else 0.0
            today_cal_str = datetime.datetime.now(ZoneInfo(tz_name)).strftime("%Y-%m-%d")

            is_in_full_zone = (soc_num >= 95.0 and msoc_num >= 91.0)
            
            try:
                b_health_doc = db.collection('status').document('battery_health').get()
                hdata = b_health_doc.to_dict() or {} if b_health_doc.exists else {}
                prev_dwell_date = hdata.get('high_soc_dwell_date', '')
                prev_dwell_mins = int(hdata.get('high_soc_dwell_minutes', 0)) if prev_dwell_date == today_cal_str else 0

                if is_in_full_zone:
                    new_dwell_mins = prev_dwell_mins + 5
                else:
                    new_dwell_mins = prev_dwell_mins

                # --- Dual-Temperature Cold Protection & Joule Pre-Warming Engine ---
                # 1) Cell Temperature (uwMinTemprCell / bmsBatteryTemp) governs discharge limits & internal resistance
                # 2) Outdoor Forecast Temperature governs pre-warming triggers and lithium plating charge limits
                outdoor_temp_c = 15.0
                try:
                    wf_doc = db.collection('status').document('weather_forecast').get()
                    if wf_doc.exists:
                        wdata = wf_doc.to_dict() or {}
                        outdoor_temp_c = wdata.get('current_temperature_c')
                        if outdoor_temp_c is None:
                            hours = wdata.get('hours', [])
                            if hours and len(hours) > 0:
                                outdoor_temp_c = hours[0].get('tempC') or hours[0].get('apparentTemp')
                except Exception:
                    pass
                outdoor_temp_c = float(outdoor_temp_c) if outdoor_temp_c is not None else 15.0

                cell_temp_c = None
                try:
                    if live_status.get('uwMinTemprCell') is not None:
                        cell_temp_c = float(live_status.get('uwMinTemprCell'))
                    elif live_status.get('bmsBatteryTemp') is not None:
                        cell_temp_c = float(live_status.get('bmsBatteryTemp'))
                    elif live_status.get('batteryTemperature') is not None:
                        cell_temp_c = float(live_status.get('batteryTemperature'))
                except Exception:
                    pass

                # If Growatt API temporarily drops cell temp keys during a poll cycle,
                # inherit from the previous valid cell_temp_c instead of falling back to default 15°C
                if cell_temp_c is None:
                    try:
                        prev_tele = db.collection('telemetry_history').order_by('timestamp', direction=firestore.Query.DESCENDING).limit(1).get()
                        if prev_tele and len(prev_tele) > 0:
                            cell_temp_c = float(prev_tele[0].to_dict().get('cell_temp_c', 4.0))
                    except Exception:
                        pass
                cell_temp_c = float(cell_temp_c) if cell_temp_c is not None else 4.0

                # Primary governing temperature for discharge sag cap is cell_temp_c
                prev_dis_limit = int(hdata.get('cold_discharge_limit_pct', 100))
                dis_limit, _, min_soc_floor, cold_note = compute_cold_weather_battery_limits(cell_temp_c, prev_dis_limit)

                # Lithium plating charge limit uses minimum of outdoor & cell temp for safety
                effective_freeze_temp = min(outdoor_temp_c, cell_temp_c)
                if effective_freeze_temp < 0.0:
                    chg_limit = 0
                elif effective_freeze_temp < 5.0:
                    chg_limit = 30
                else:
                    chg_limit = 100

                ambient_temp_c = cell_temp_c

                b_health_payload = {
                    'cold_discharge_limit_pct': dis_limit,
                    'cold_charge_limit_pct': chg_limit,
                    'cold_min_soc_floor': min_soc_floor,
                    'cold_weather_note': cold_note,
                    'ambient_temp_c': ambient_temp_c,
                }
                if live_status.get('bmsFW'):
                    b_health_payload['bms_firmware_version'] = str(live_status.get('bmsFW'))
                    b_health_payload['bms_mcu_version'] = str(live_status.get('bmsMCUVersion', live_status.get('bmsFW')))
                    b_health_payload['bms_hardware_version'] = str(live_status.get('bmsHardwareVersion', ''))
                    b_health_payload['bms_highest_soft_version'] = str(live_status.get('bmsHighestSoftVersion', ''))
                db.collection('status').document('battery_health').set(b_health_payload, merge=True)

                # Read ACTUAL hardware status command BEFORE mutating live_status
                inv_dis_cmd = str(live_status.get('disChargePowerCommand', '100'))

                # Explicitly populate live_status with power limits for real-time mobile app display
                live_status['disChargePowerCommand'] = str(dis_limit)
                live_status['chargePowerCommand'] = str(chg_limit)

                # Save live status data to Firestore with populated power commands
                db.collection('status').document('growatt_live').set({
                    'last_updated': datetime.datetime.now(datetime.timezone.utc),
                    'device_sn': device_sn,
                    'plant_id': plant_id,
                    'data': live_status
                })

                # === EV Sponge Priority Switching Control ===
                # Load the charging plan to determine overnight sponge behaviour.
                plan_doc = db.collection('status').document('charging_plan').get()
                plan_data = plan_doc.to_dict() if plan_doc.exists else {}
                plan_target_soc = plan_data.get('target_soc')
                plan_is_sponge = (plan_data.get('ev_sponge_active', False) or
                                  plan_data.get('charge_kwh', 1.0) == 0.0 or
                                  any('Sponge' in str(t.get('name', '')) for t in plan_data.get('suggested_tasks', [])))
                tesla_continue_charge = bool(plan_data.get('tesla_continue_charge', False))
                sponge_floor_locked = bool(plan_data.get('sponge_floor_locked', False))

                # If the user edited the Sponge task in their Inverter Schedule (e.g. changed SoC),
                # prioritize the task's SoC as the true floor and keep status/charging_plan in sync!
                tasks = settings.get('tasks', [])
                local_day_str = local_now.strftime("%a")
                active_sponge_task = None
                for t in tasks:
                    if t.get('enabled', False) and local_day_str in t.get('days', []) and 'sponge' in str(t.get('name', '')).lower():
                        active_sponge_task = t
                        break

                if active_sponge_task and active_sponge_task.get('soc') is not None:
                    try:
                        task_soc_num = float(active_sponge_task.get('soc'))
                        plan_target_soc = task_soc_num
                        plan_is_sponge = True
                        if plan_data.get('target_soc') != task_soc_num:
                            print(f"EV Sponge target SoC synced from user schedule task '{active_sponge_task.get('name')}': {task_soc_num}% (overriding plan {plan_data.get('target_soc')}%)")
                            plan_data['target_soc'] = task_soc_num
                            db.collection('status').document('charging_plan').set({'target_soc': int(round(task_soc_num))}, merge=True)
                    except (ValueError, TypeError):
                        pass

                # Dynamic sponge hours check: use active task window if available, else local_now.hour < 6
                cur_min = local_now.hour * 60 + local_now.minute
                if active_sponge_task:
                    try:
                        sh, sm = map(int, str(active_sponge_task.get('start_time', '00:00')).split(':'))
                        eh, em = map(int, str(active_sponge_task.get('end_time', '06:00')).split(':'))
                        s_min, e_min = sh * 60 + sm, eh * 60 + em
                        is_sponge_hours = (s_min <= cur_min < e_min) if s_min < e_min else (cur_min >= s_min or cur_min < e_min)
                    except Exception:
                        is_sponge_hours = (local_now.hour < 6)
                else:
                    is_sponge_hours = (local_now.hour < 6)
                
                # On Growatt SPH, Battery First mode is active if and only if forcedChargeStopSwitch1 == '1' (or priorityChoose == '1').
                # SPH always reports priorityChoose as '0' in telemetry, so forcedChargeStopSwitch1 and acChargeEnable are the true hardware registers.
                # In addition, check physical telemetry: if battery is absorbing power (chargePower > 0.1 kW) when there is 0 solar at night,
                # that is physical proof that the inverter is actively charging from the grid!
                live_chg_power = float(live_status.get('chargePower', 0) or 0)
                live_ppv = float(live_status.get('ppv', 0) or live_status.get('storagePpv', 0) or 0)

                _s_doc = db.collection('status').document('growatt_inverter_settings').get()
                _st_dict = _s_doc.to_dict() if _s_doc.exists else {}
                _mb = _st_dict.get('settings', {}).get('obj', {}).get('mixBean', {})
                if not _mb and 'data' in _st_dict:
                    _mb = _st_dict.get('data', {})

                forced_chg_sw = str(live_status.get('forcedChargeStopSwitch1') or _mb.get('forcedChargeStopSwitch1', '0'))
                ac_chg_sw = str(live_status.get('acChargeEnable') or _mb.get('acChargeEnable', '0'))

                is_battery_first = (
                    forced_chg_sw == '1' or
                    ac_chg_sw == '1' or
                    str(live_status.get('priorityChoose')) == '1' or
                    (is_sponge_hours and live_chg_power > 0.1 and live_ppv < 0.1)
                )

                # === EV Sponge Priority Switching & Tesla Cut-Off / Extended Charge Control ===
                # In Sponge mode (00:00 - 06:00):
                # 1. While live SoC > target_soc: Inverter stays in pure Load First mode (mix_ac_charge_time_period enable="0", 0% AC grid charging).
                #    The home battery discharges to power Tesla EV + household standby without any grid import.
                # 2. When live SoC <= target_soc:
                #    a) If tesla_continue_charge is False (default):
                #       Stop Tesla charging (via charge_stop) to protect remaining battery reserve for morning house load,
                #       keeping inverter in Load First so house continues to run 100% off battery.
                #    b) If tesla_continue_charge is True:
                #       Do NOT stop Tesla charging. Instead, switch inverter to Battery First (enable1='1', acChargeEnable='1', target_soc=floor).
                #       Because battery is already at floor, inverter does NOT charge the battery from grid, and does NOT discharge battery to load.
                #       Tesla and house load draw power from cheap off-peak grid until 06:00 (when car schedule automatically ends).
                chg_p_val = str(min(100, chg_limit))
                if is_sponge_hours and plan_is_sponge and plan_target_soc is not None:
                    target_floor = float(plan_target_soc)
                    target_floor_int = int(round(target_floor))

                    # ── EV Sponge Inverter Mode Guard ──
                    # During the discharge phase (SoC > target): strictly Load First — no Battery First allowed.
                    # After floor is reached with tesla_continue_charge=True: Battery First IS authorized (sponge_floor_locked=True).
                    # The guard must NOT revert an authorized floor-hold back to Load First!
                    authorized_battery_first = (tesla_continue_charge and sponge_floor_locked)
                    if is_battery_first and not is_token_mode and not authorized_battery_first:
                        print(f"SPONGE MODE ACTIVE: Detected unauthorized Battery First / AC Charge (forcedSw1={forced_chg_sw}, acChg={ac_chg_sw}, chgPwr={live_chg_power}kW). "
                              f"Enforcing Load First mode (mix_ac_charge_time_period enable=0, 0% AC charge).")
                        try:
                            chg_params = [
                                chg_p_val, str(target_floor_int), '0',
                                '00', '00', '06', '00', '0',
                                '00', '00', '00', '00', '0',
                                '00', '00', '00', '00', '0'
                            ]
                            api.update_mix_inverter_setting(device_sn, 'mix_ac_charge_time_period', chg_params)
                            live_status['forcedChargeStopSwitch1'] = '0'
                            live_status['acChargeEnable'] = '0'
                            live_status['priorityChoose'] = '0'
                        except Exception as ex_lf:
                            print(f"Warning: Failed to ensure Load First mode: {str(ex_lf)}")

                    # ── EV Sponge Target Action ──
                    # When battery discharges to target_floor:
                    # - If tesla_continue_charge is False: Snapshot Tesla readings and send charge_stop to vehicle.
                    #   Inverter remains in Load First (enable1='0', acChargeEnable='0').
                    # - If tesla_continue_charge is True: Switch inverter to Battery First with charging target SoC
                    #   set equal to discharging target SoC (AI plan target_floor_int, e.g. 24%).
                    #   Because battery is already AT floor, the inverter does NOT buy grid power to fill the battery.
                    #   It simply locks battery discharge — Tesla + house draw 100% from cheap off-peak grid until 06:00.
                    if soc_num <= target_floor or sponge_floor_locked:
                        if not tesla_continue_charge:
                            already_stopped_tesla = bool(plan_data.get('sponge_tesla_stopped', False))
                            live_load_kw = float(live_status.get('local_load_kw', 0) or 0)

                            # Directly poll readings and issue charge_stop if not yet stopped tonight, OR if load is still high (> 1.5kW)
                            if not already_stopped_tesla or live_load_kw > 1.5:
                                try:
                                    tesla_sett = db.collection('settings').document('tesla').get()
                                    t_cfg = tesla_sett.to_dict() if tesla_sett.exists else {}
                                    if t_cfg.get('enabled', False) and t_cfg.get('auto_stop_on_sponge_target', True):
                                        print(f"EV Sponge target reached ({soc_num:.1f}% <= {target_floor}%): "
                                              f"Polling Tesla readings and issuing charge_stop to Tesla (already_stopped={already_stopped_tesla}, load={live_load_kw:.2f}kW)...")
                                        stop_res = stop_tesla_charging_helper(db, t_cfg)
                                        db.collection('status').document('charging_plan').set({'sponge_tesla_stopped': True}, merge=True)
                                        plan_data['sponge_tesla_stopped'] = True
                                        log_run_status(db, trigger_type, 'success',
                                                       f"EV Sponge: Battery reached target ({soc_num:.1f}% <= {target_floor}%). Fetched readings & issued charge_stop to Tesla (result: {stop_res}).",
                                                       'sponge_stop_tesla')
                                except Exception as ex_t_stop:
                                    print(f"Warning: Failed to auto-stop Tesla charging: {str(ex_t_stop)}")
                                    log_run_status(db, trigger_type, 'warning',
                                                   f"EV Sponge: Target reached ({soc_num:.1f}% <= {target_floor}%), but charge_stop failed: {str(ex_t_stop)}",
                                                   'sponge_stop_tesla_error')
                        else:
                            # tesla_continue_charge=True branch.
                            # Once sponge_floor_locked=True, sync_growatt_inverter NEVER writes again.
                            # sync_growatt_schedule_daily owns the periodic re-assertion (with EEPROM write protection).
                            # This function only writes ONCE: on the first cycle where SoC hits the floor.
                            if sponge_floor_locked:
                                # Floor already locked — hand off entirely to schedule_daily.
                                print(f"EV Sponge floor hold active (sponge_floor_locked=True): "
                                      f"Battery First maintained by schedule_daily. No write from inverter sync.")
                            elif not is_token_mode:
                                # First trigger: SoC just reached target_floor. Write Battery First ONCE.
                                print(f"EV Sponge target reached ({soc_num:.1f}% <= {target_floor}%): "
                                      f"tesla_continue_charge=True — writing Battery First ONCE, "
                                      f"charging target SoC = {target_floor_int}% (= AI plan discharging target). "
                                      f"Setting sponge_floor_locked=True; future writes owned by schedule_daily.")
                                try:
                                    chg_params = [
                                        chg_p_val, str(target_floor_int), '1',
                                        '00', '00', '06', '00', '1',
                                        '00', '00', '00', '00', '0',
                                        '00', '00', '00', '00', '0'
                                    ]
                                    api.update_mix_inverter_setting(device_sn, 'mix_ac_charge_time_period', chg_params)
                                    live_status['forcedChargeStopSwitch1'] = '1'
                                    live_status['acChargeEnable'] = '1'
                                    live_status['priorityChoose'] = '1'
                                    db.collection('status').document('charging_plan').set({'sponge_floor_locked': True}, merge=True)
                                    sponge_floor_locked = True
                                    plan_data['sponge_floor_locked'] = True
                                    log_run_status(db, trigger_type, 'success',
                                                   f"EV Sponge floor locked: Battery First, target SoC={target_floor_int}% (= AI plan). "
                                                   f"Battery discharge halted; Tesla on off-peak grid. "
                                                   f"Future re-assertion owned by schedule_daily (EEPROM protected).",
                                                   'sponge_floor_locked')
                                except Exception as ex_bf:
                                    print(f"Warning: Failed to switch to Battery First floor-hold: {str(ex_bf)}")



                # Discharge Power Command & Stop-SoC Hardware Sync:
                # Maintain discharge power at full cold-weather limit (100% on normal nights).
                min_soc_default = int(settings.get('min_soc', 10))
                is_grid_first_active = bool(hdata.get('grid_first_active', False)) or str(live_status.get('priorityChoose', '0')) == '2'
                # Grid First discharge stop SoC is ALWAYS kept at 80% (or 90%) as an absolute safety barrier
                # to prevent the battery from ever dumping energy into the grid below this floor.
                grid_first_stop_soc = 80

                # Read actual hardware state from last recorded inverter settings
                last_settings_doc = db.collection('status').document('growatt_inverter_settings').get()
                last_settings = last_settings_doc.to_dict() if last_settings_doc.exists else {}
                last_st_data = last_settings.get('settings', {})
                if isinstance(last_st_data, dict) and 'obj' in last_st_data and 'mixBean' in last_st_data['obj']:
                    last_st_data = last_st_data['obj']['mixBean']
                inv_dis_stop_soc = str(last_st_data.get('wdisChargeSOCLowLimit2', '80'))

                # Hardware sync: re-push whenever power limit or stop-SoC registers drift
                if (str(dis_limit) != inv_dis_cmd or str(grid_first_stop_soc) != inv_dis_stop_soc) and not is_token_mode:
                    try:
                        print(f"DISCHARGE HARDWARE SYNC: Power {dis_limit}%, GridFirst StopSoC {grid_first_stop_soc}% "
                              f"(was Power {inv_dis_cmd}%, StopSoC {inv_dis_stop_soc}%). Re-asserting...")
                        # offGridDischargeSOC register (Off-grid section in ShinePhone, defaults to 10%)
                        api.update_mix_inverter_setting(device_sn, 'off_grid_discharge_soc', {'param1': str(min_soc_default)})
                        # Grid First stop SoC + discharge power limit (09:00-17:00 daytime protection window)
                        dis_enable_switch = '1' if is_grid_first_active else '0'
                        dis_params = [
                            str(dis_limit), str(grid_first_stop_soc),
                            '09', '00', '17', '00', dis_enable_switch,
                            '00', '00', '00', '00', '0',
                            '00', '00', '00', '00', '0'
                        ]
                        res_dis = api.update_mix_inverter_setting(device_sn, 'mix_ac_discharge_time_period', dis_params)
                        print(f"Hardware discharge sync result: {res_dis}")
                    except Exception as ex_dis:
                        print(f"Warning: Failed to update hardware discharge settings: {str(ex_dis)}")

                # Check strict completion: BMS >= 98%, AI >= 91%, Dwell >= 60 min
                if soc_num >= 98.0 and msoc_num >= 91.0 and new_dwell_mins >= 60:
                    was_already_calibrated = (hdata.get('last_calibration_date') == today_cal_str and not hdata.get('calibration_due', True))
                    db.collection('status').document('battery_health').set({
                        'last_calibration_time': firestore.SERVER_TIMESTAMP,
                        'last_calibration_date': today_cal_str,
                        'last_calibration_soc': soc_num,
                        'last_calibration_modeled_soc': msoc_num,
                        'days_since_last_calibration': 0,
                        'calibration_due': False,
                        'high_soc_dwell_minutes': new_dwell_mins,
                        'high_soc_dwell_date': today_cal_str,
                        'calibration_status': 'VERIFIED_SUCCESSFUL'
                    }, merge=True)
                    print(f"BMS CALIBRATION VERIFIED & RECORDED: SoC={soc_num}%, AI SoC={msoc_num}%, Dwell={new_dwell_mins}m (>=60m). Updated last_calibration_date to {today_cal_str}.")

                    # --- Early Calibration Release & Auto Priority Switch ---
                    # Once calibration & 60m cell balancing complete, release remaining 12:00-17:00 window
                    # by switching priorityChoose back to 0 (Load First) to save costs & maximize solar self-consumption!
                    try:
                        curr_priority = str(live_status.get('priorityChoose', '0'))
                        if curr_priority == '1' and not is_token_mode:
                            print(f"EARLY CALIBRATION RELEASE: Full 60m balancing complete ({new_dwell_mins}m). Switching inverter back to Load First (priorityChoose=0)...")
                            api.update_mix_inverter_setting(device_sn, 'priorityChoose', {'param1': '0'})
                            print("Successfully switched priority back to Load First (0)!")
                    except Exception as ex_rel:
                        print(f"Notice: Early calibration release priority switch attempt: {str(ex_rel)}")
                else:
                    db.collection('status').document('battery_health').set({
                        'high_soc_dwell_minutes': new_dwell_mins,
                        'high_soc_dwell_date': today_cal_str,
                    }, merge=True)
            except Exception as ex_cal:
                print(f"Warning: Failed to update battery_health calibration record: {str(ex_cal)}")

            # === Daytime High-SoC Dwell Protection (Event-Driven: 1 LLM Decision/Day + Robust Rule Fallback) ===
            # Objective: Avoid LFP battery 100% full-voltage dwell in hot daytime sun.
            # Efficiency & Anti-fragility:
            # 1. 5-minute ticks run 100% local deterministic logic (0ms, 0 API calls).
            # 2. LLM is invoked ONLY ONCE per day at the critical event: when battery crosses 80% with live solar >= 1.5 kW.
            # 3. Once decided, Grid First remains active until physical exit conditions (17:00 or solar drops or battery < 75%).
            # 4. Exit/revert is 100% deterministic physics rules (zero latency, zero network dependence).
            try:
                curr_priority = str(live_status.get('priorityChoose', '0'))
                is_cal_due = bool(hdata.get('calibration_due', False)) or bool(plan_data.get('lfp_cal_reason'))
                is_winter = local_now.month in [6, 7, 8]
                in_solar_protect_window = (9 <= local_now.hour < 17)
                today_local_str = local_now.strftime('%Y-%m-%d')

                pv_fc = float(plan_data.get('pv_forecast_kwh') or 0.0)
                load_fc = float(plan_data.get('load_forecast_kwh') or plan_data.get('household_daily_kwh') or 999.0)
                has_solar_surplus = (pv_fc >= load_fc and pv_fc >= 15.0)

                # Base eligibility: within daytime window, not winter, not calibration due
                can_evaluate = in_solar_protect_window and not is_winter and not is_cal_due

                # ── Physical Exit Guard (100% Deterministic, 0 LLM calls) ──
                # If currently in Grid First ('2') and exit condition is met, revert immediately!
                if curr_priority == '2':
                    should_exit = False
                    exit_reason = ""
                    if not in_solar_protect_window:
                        should_exit = True
                        exit_reason = f"Daytime window ended ({local_now.strftime('%H:%M')} >= 17:00)"
                    elif is_cal_due:
                        should_exit = True
                        exit_reason = "BMS calibration active"
                    elif soc_num < 75.0:
                        should_exit = True
                        exit_reason = f"Battery SoC dropped to {soc_num:.1f}% (< 75%)"
                    elif live_ppv < 0.3:
                        should_exit = True
                        exit_reason = f"Solar dropped to {live_ppv:.2f}kW (< 0.3kW)"

                    if should_exit:
                        print(f"☀️ Daytime Protection Exit: {exit_reason}. Reverting to Load First (priorityChoose=0)...")
                        if not is_token_mode:
                            api.update_mix_inverter_setting(device_sn, 'priorityChoose', {'param1': '0'})
                            dis_exit_params = [
                                str(dis_limit), '80',
                                '09', '00', '17', '00', '0',
                                '00', '00', '00', '00', '0',
                                '00', '00', '00', '00', '0'
                            ]
                            api.update_mix_inverter_setting(device_sn, 'mix_ac_discharge_time_period', dis_exit_params)
                            live_status['priorityChoose'] = '0'
                            live_status['forcedDischargeStopSwitch1'] = '0'
                        db.collection('status').document('battery_health').set({
                            'grid_first_active': False,
                            'llm_daytime_reasoning': f"Reverted to Load First: {exit_reason}."
                        }, merge=True)

                # ── Single Event-Driven Entry (Triggered when crossing 80% with PV >= 1.5 kW) ──
                elif can_evaluate and curr_priority != '2' and soc_num >= 80.0 and live_ppv >= 1.5:
                    # Check if already evaluated today
                    eval_date = hdata.get('llm_daytime_eval_date')
                    eval_verdict = hdata.get('llm_daytime_verdict')

                    if eval_date == today_local_str and eval_verdict is not None:
                        # Re-use today's single LLM verdict (0 API calls!)
                        should_protect = bool(eval_verdict)
                        source_label = f"{hdata.get('llm_daytime_source', 'gemini')} (today_cached)"
                        reasoning_label = str(hdata.get('llm_daytime_reasoning', ''))
                    else:
                        # First time reaching 80% today -> trigger the 1 LLM consultation for the day!
                        gemini_key = settings.get('gemini_api_key', '')
                        context = {
                            "in_solar_protect_window": in_solar_protect_window,
                            "is_winter": is_winter,
                            "is_cal_due": is_cal_due,
                            "has_solar_surplus": has_solar_surplus,
                            "soc_num": soc_num,
                            "live_ppv": live_ppv,
                            "live_load_kw": live_pload,
                            "pv_fc": pv_fc,
                            "load_fc": load_fc,
                            "local_time_str": local_now.strftime('%H:%M'),
                            "month": local_now.month,
                            "curr_priority": curr_priority
                        }
                        llm_eval = evaluate_daytime_high_soc_llm(context, gemini_key)
                        should_protect = llm_eval['should_protect']
                        source_label = llm_eval['source']
                        reasoning_label = llm_eval['reasoning']

                        # Save today's evaluation into Firestore
                        db.collection('status').document('battery_health').set({
                            'llm_daytime_eval_date': today_local_str,
                            'llm_daytime_verdict': should_protect,
                            'llm_daytime_confidence': llm_eval['confidence'],
                            'llm_daytime_source': source_label,
                            'llm_daytime_reasoning': reasoning_label,
                            'llm_daytime_timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
                        }, merge=True)
                        print(f"🤖 Once-Daily LLM Daytime Protection [{source_label}]: should_protect={should_protect} (SoC={soc_num}%, PV={live_ppv:.2f}kW) -> {reasoning_label}")

                    if should_protect and not is_token_mode:
                        print(f"☀️ Activating Grid First (priorityChoose=2) guided by {source_label} (80% discharge floor).")
                        api.update_mix_inverter_setting(device_sn, 'priorityChoose', {'param1': '2'})
                        dis_protect_params = [
                            '100', '80',
                            '09', '00', '17', '00', '1',
                            '00', '00', '00', '00', '0',
                            '00', '00', '00', '00', '0'
                        ]
                        api.update_mix_inverter_setting(device_sn, 'mix_ac_discharge_time_period', dis_protect_params)
                        live_status['priorityChoose'] = '2'
                        live_status['forcedDischargeStopSwitch1'] = '1'
                        db.collection('status').document('battery_health').set({'grid_first_active': True}, merge=True)
            except Exception as ex_gf:
                print(f"Notice: Daytime High-SoC Protection attempt: {str(ex_gf)}")
            
            # Check latest log entry in Firestore to avoid duplicates
            telemetry_ref = db.collection('telemetry_history')
            latest_query = telemetry_ref.order_by('timestamp', direction=firestore.Query.DESCENDING).limit(1).get()
            
            should_write_telemetry = True
            if len(latest_query) > 0:
                latest_doc = latest_query[0]
                latest_data = latest_doc.to_dict()
                
                # Check time difference
                last_time = latest_data.get('timestamp')
                now_utc = datetime.datetime.now(datetime.timezone.utc)
                time_diff = now_utc - last_time if last_time else datetime.timedelta(hours=2)
                
                # Check metric equivalence
                is_identical = (
                    latest_data.get('soc') == soc_val and
                    abs(latest_data.get('solar_generation_kw', 0.0) - solar_generation_kw) < 0.01 and
                    abs(latest_data.get('charge_power_kw', 0.0) - charge_power_kw) < 0.01 and
                    abs(latest_data.get('discharge_power_kw', 0.0) - discharge_power_kw) < 0.01 and
                    abs(latest_data.get('local_load_kw', 0.0) - local_load_kw) < 0.01
                )
                
                # Skip write if identical AND less than 15 minutes old (guarantees dense 15-min heartbeat logs)
                if is_identical and time_diff < datetime.timedelta(minutes=15):
                    should_write_telemetry = False
                    print("Telemetry is identical to latest log and within 15 minutes. Skipping historical write.")
            
            if should_write_telemetry:
                print("Writing new telemetry entry to telemetry_history...")
                cell_delta_mv = parse_int(live_status.get("bmsDeltaVolt", 0))
                cell_volts = []
                for i in range(1, 17):
                    v_cell = parse_kw(live_status.get(f"bmsCell{i}Volt"))
                    if v_cell > 0:
                        cell_volts.append(round(v_cell, 3))

                telemetry_entry = {
                    'timestamp': datetime.datetime.now(datetime.timezone.utc),
                    'soc': soc_val,
                    'modeled_soc': modeled_soc,
                    'battery_energy_kwh': battery_energy_kwh,
                    'battery_voltage': battery_voltage,
                    'cell_delta_mv': cell_delta_mv,
                    'cell_temp_c': cell_temp_c,
                    'solar_generation_kw': solar_generation_kw,
                    'charge_power_kw': charge_power_kw,
                    'discharge_power_kw': discharge_power_kw,
                    'local_load_kw': local_load_kw,
                    'grid_export_kw': grid_export_kw,
                    'grid_import_kw': grid_import_kw
                }
                if live_status.get('bmsFW'):
                    telemetry_entry['bms_fw'] = str(live_status.get('bmsFW'))
                    telemetry_entry['bms_mcu_ver'] = str(live_status.get('bmsMCUVersion', live_status.get('bmsFW')))
                    telemetry_entry['bms_hw_ver'] = str(live_status.get('bmsHardwareVersion', ''))

                if cell_volts:
                    telemetry_entry['cell_voltages'] = cell_volts

                # Per-string MPPT readings (only when the payload provides them) — useful for
                # per-string shading analysis and future string-level PV modelling.
                for k, v in [('pv1_power_kw', pv1_power_kw), ('pv2_power_kw', pv2_power_kw),
                             ('pv1_voltage', pv1_voltage), ('pv2_voltage', pv2_voltage)]:
                    if v is not None:
                        telemetry_entry[k] = v

                # Join in a weather snapshot (temperature, weather code, cloud cover, wind) so
                # each telemetry row is already ML-ready — no separate collection to join later.
                weather_snapshot = fetch_weather_snapshot(settings, tz_name)
                if weather_snapshot:
                    telemetry_entry.update(weather_snapshot)

                db.collection('telemetry_history').add(telemetry_entry)

        except Exception as e:
            print(f"Warning: Failed to fetch status or save telemetry: {str(e)}")

        # --- RETRIEVE CURRENT SETTINGS FIRST ---
        print(f"Retrieving current settings for device: {device_sn}...")
        current_settings = {}
        try:
            import time as _time
            last_settings_err = None
            for attempt in range(3):
                try:
                    if is_token_mode:
                        current_settings = api.sph_detail(device_sn)
                    else:
                        current_settings = api.get_mix_inverter_settings(device_sn)
                    last_settings_err = None
                    break
                except Exception as e:
                    last_settings_err = e
                    if attempt < 2:
                        print(f"Settings read attempt {attempt + 1} failed: {str(e)}. Retrying in 3 seconds...")
                        _time.sleep(3)
            if last_settings_err is not None:
                raise last_settings_err
            print(f"Retrieved settings from server: {current_settings}")
            
            # Extract firmware / software versions from current_settings (mixBean or root)
            st_dict = current_settings.get('settings', current_settings)
            obj_dict = st_dict.get('obj', st_dict)
            mix_bean = obj_dict.get('mixBean', obj_dict) if isinstance(obj_dict, dict) else {}

            inv_fw = str(mix_bean.get('fwVersion', ''))
            inv_inner_fw = str(mix_bean.get('innerVersion', ''))
            inv_comm_ver = str(mix_bean.get('communicationVersion', ''))
            inv_modbus_ver = str(mix_bean.get('modbusVersion', ''))

            bms_fw = str(live_status.get('bmsFW', ''))
            bms_mcu = str(live_status.get('bmsMCUVersion', bms_fw))
            bms_hw = str(live_status.get('bmsHardwareVersion', ''))
            bms_soft = str(live_status.get('bmsHighestSoftVersion', ''))

            # Save raw settings data to Firestore
            db.collection('status').document('growatt_inverter_settings').set({
                'last_updated': datetime.datetime.now(datetime.timezone.utc),
                'device_sn': device_sn,
                'inverter_fw_version': inv_fw,
                'inverter_inner_version': inv_inner_fw,
                'inverter_communication_version': inv_comm_ver,
                'settings': current_settings
            })

            # Save clean firmware version document in status/firmware_versions
            fw_doc_payload = {
                'last_updated': datetime.datetime.now(datetime.timezone.utc),
                'device_sn': device_sn,
                'inverter_firmware_main': inv_fw,
                'inverter_firmware_inner': inv_inner_fw,
                'inverter_communication_version': inv_comm_ver,
                'inverter_modbus_version': inv_modbus_ver,
            }
            if bms_fw:
                fw_doc_payload.update({
                    'battery_bms_fw': bms_fw,
                    'battery_bms_mcu': bms_mcu,
                    'battery_bms_hardware': bms_hw,
                    'battery_bms_highest_soft': bms_soft,
                })

                # Also update battery_health with firmware details
                db.collection('status').document('battery_health').set({
                    'bms_firmware_version': bms_fw,
                    'bms_mcu_version': bms_mcu,
                    'bms_hardware_version': bms_hw,
                    'bms_highest_soft_version': bms_soft,
                    'inverter_inner_version': inv_inner_fw,
                    'inverter_fw_version': inv_fw,
                }, merge=True)

            db.collection('status').document('firmware_versions').set(fw_doc_payload, merge=True)
            print(f"Persisted firmware versions: Inv Main={inv_fw}, Inv Inner={inv_inner_fw}, BMS FW={bms_fw}, BMS HW={bms_hw}.")
        except Exception as e:
            print(f"Warning: Failed to fetch inverter settings: {str(e)}")

        # --- DYNAMIC TASK RESOLVER ---
        # Parse schedule active tasks for the target date.
        # Late-night window transition: at 23:45 or later, we transition to tomorrow's schedule
        # (since the 23:45 pre-task sync pushes tomorrow's 00:00 task). Any sync or read
        # before 23:45 targets today's schedule.
        target_date = local_now.date()
        if local_now.hour == 23 and local_now.minute >= 45:
            target_date = target_date + datetime.timedelta(days=1)
            print(f"Late-night transition active (23:45+). Resolving schedule for TOMORROW ({target_date}).")
        else:
            print(f"Resolving schedule for TODAY ({target_date}).")

        tasks = settings.get('tasks', [])

        # --- AI-plan override (priority resolution, no task mutation) ---
        # Manual tasks are the WEEKLY baseline; an applied AI plan is a one-shot override
        # for exactly one date (settings.ai_plan_applied_for). When resolving that date,
        # use ONLY the AI tasks; any other date uses ONLY the manual weekly tasks. Manual
        # tasks are never disabled or modified — the weekly plan resumes by itself the
        # day after, and the EEPROM-protection comparison below still applies as usual.
        applied_for = settings.get('ai_plan_applied_for') or ''
        ai_tasks = [t for t in tasks if str(t.get('name', '')).startswith('AI Plan')]
        if applied_for == target_date.strftime("%Y-%m-%d") and ai_tasks:
            print(f"AI Plan override active for {applied_for}: resolving from {len(ai_tasks)} AI task(s).")
            tasks = ai_tasks
        else:
            tasks = [t for t in tasks if not str(t.get('name', '')).startswith('AI Plan')]

        # Backward compatibility / default fallback if no tasks exist
        if not tasks:
            print("No tasks configured. Using default weekday/weekend fallback tasks.")
            tasks = [
                {
                    "id": "default_daily",
                    "name": "Daily Night Charge",
                    "days": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
                    "start_time": "00:00",
                    "end_time": "06:00",
                    "power": "100",
                    "soc": "100",
                    "enabled": True
                },
                {
                    "id": "default_weekend",
                    "name": "Weekend Extra Charge",
                    "days": ["Sat", "Sun"],
                    "start_time": "12:00",
                    "end_time": "14:00",
                    "power": "100",
                    "soc": "100",
                    "enabled": True
                }
            ]

        # "Now" expressed in minutes relative to target_date's midnight (negative when
        # pushing tomorrow's schedule tonight) — selects which window's SoC becomes the
        # inverter's single global charge-stop SoC for this push.
        days_ahead = (target_date - local_now.date()).days
        reference_minute = local_now.hour * 60 + local_now.minute - days_ahead * 1440

        segments, global_power, global_soc = resolve_daily_schedule_from_tasks(
            tasks, target_date, reference_minute=reference_minute)
        
        # Check if the active plan is an EV Sponge plan:
        plan_doc = db.collection('status').document('charging_plan').get()
        plan_data = plan_doc.to_dict() if plan_doc.exists else {}
        plan_is_sponge = (plan_data.get('ev_sponge_active', False) or
                          plan_data.get('charge_kwh', 1.0) == 0.0 or
                          any('Sponge' in str(t.get('name', '')) for t in tasks))
        
        live_soc_val = float(live_status.get('SOC', live_status.get('soc', 50.0)))
        target_floor = float(plan_data.get('target_soc', 30))
        # Prioritize SoC from user's active Sponge task in tasks list if edited
        day_str = target_date.strftime("%a")
        active_sponge_task = None
        for t in tasks:
            if t.get('enabled', False) and day_str in t.get('days', []) and 'sponge' in str(t.get('name', '')).lower():
                active_sponge_task = t
                if t.get('soc') is not None:
                    try:
                        target_floor = float(t.get('soc'))
                        break
                    except (ValueError, TypeError):
                        pass

        tesla_continue_charge = bool(plan_data.get('tesla_continue_charge', False))
        sponge_floor_locked = bool(plan_data.get('sponge_floor_locked', False))
        # Segment 0 enable logic:
        # - Normal EV Sponge (discharging to target): DISABLE window (sponge_seg_enable="0").
        #   Inverter stays in Load First, battery discharges to target_floor.
        # - EV Sponge floor LOCKED (tesla_continue_charge=True, battery at floor):
        #   ENABLE window (sponge_seg_enable="1"), target SoC = target_floor_int.
        #   This maintains Battery First with the floor SoC so the inverter does not
        #   discharge the battery further. Tesla + house draw off-peak grid until window end.
        is_floor_hold_active = plan_is_sponge and tesla_continue_charge and sponge_floor_locked
        target_floor_int = int(round(target_floor))

        if is_floor_hold_active:
            sponge_seg_enable = "1"
            # Override global_soc to target_floor_int so the charging cap = discharge floor.
            # Battery is already AT floor, so inverter will not buy grid power to charge it —
            # it simply holds the floor and prevents further discharge.
            global_soc = target_floor_int
            print(f"EV Sponge floor hold active (sponge_floor_locked=True, tesla_continue_charge=True): "
                  f"enabling charging window with target SoC={target_floor_int}% (Battery First floor hold).")
        else:
            sponge_seg_enable = "0" if plan_is_sponge else "1"

        seg_enables = []
        for i in range(len(segments)):
            seg_en = sponge_seg_enable if i == 0 else "1"
            seg_enables.append(seg_en)

        # Check if the current reference_minute falls inside an enabled charging window:
        in_active_charge_window = any(
            s['start'] <= reference_minute < s['end'] and seg_enables[idx] == "1"
            for idx, s in enumerate(segments)
        )

        # Resolve sponge window bounds (default 0 to 360 min)
        s_end_min = 360
        s_start_min = 0
        if active_sponge_task:
            try:
                sh, sm = map(int, str(active_sponge_task.get('start_time', '00:00')).split(':'))
                eh, em = map(int, str(active_sponge_task.get('end_time', '06:00')).split(':'))
                s_start_min = sh * 60 + sm
                s_end_min = eh * 60 + em
            except Exception:
                pass

        _in_sponge_time = (s_start_min <= reference_minute < s_end_min) if s_start_min < s_end_min else (reference_minute >= s_start_min or reference_minute < s_end_min)

        if in_active_charge_window:
            allow_ac_charge = "1"
            print(f"Inside active charge window (min={reference_minute}): allow_ac_charge='1'.")
        elif plan_is_sponge and not is_floor_hold_active and _in_sponge_time:
            allow_ac_charge = "0"
            print(f"Overnight EV Sponge window (discharging to {target_floor_int}%): allow_ac_charge='0'.")
        else:
            allow_ac_charge = "1" if any(en == "1" for en in seg_enables) else "0"


        # Format target_params list (length 18)
        # Charge power is ALWAYS 100% (cold-weather clamped), so that when Battery First is active,
        # the battery is maintained / charged up to global_soc (e.g. 37%).
        effective_power = 100 if (str(global_power) == "0" or global_power == 0) else int(global_power)
        target_params = [
            str(effective_power),
            str(global_soc),
            allow_ac_charge,
        ]
        
        for i in range(3):
            if i < len(segments):
                seg = segments[i]
                sh = f"{seg['start'] // 60:02d}"
                sm = f"{seg['start'] % 60:02d}"
                eh = f"{seg['end'] // 60:02d}"
                em = f"{seg['end'] % 60:02d}"
                seg_enable = seg_enables[i]
                target_params.extend([sh, sm, eh, em, seg_enable])
            else:
                target_params.extend(["00", "00", "00", "00", "0"])

        # Drift detection strategy:
        # Only segments with enable == "1" are active Battery First windows.
        # When today's plan has EV sponge, the 00:00 - 06:00 window is NOT activated (sponge_seg_enable="0"),
        # so in_active_window is strictly False during 00:00 - 06:00.
        active_segments = [
            s for idx, s in enumerate(segments)
            if seg_enables[idx] == "1"
        ]
        in_active_window = any(s['start'] <= reference_minute < s['end'] for s in active_segments)

        # Compare SoC + charge power against inverter — only meaningful inside a window
        schedule_matches, inverter_actual = _compare_schedule(current_settings, is_token_mode, target_params)

        is_sponge_overnight = (plan_is_sponge and (reference_minute < 360 or reference_minute >= 1425))

        # Gate: treat mismatch as None (no alert) when outside any Battery First window,
        # UNLESS we are in EV Sponge overnight hours: during sponge discharge, any Battery First / AC Charge on the inverter
        # is an UNAUTHORIZED grid charge and MUST NEVER be suppressed!
        if not in_active_window and schedule_matches is False and not is_sponge_overnight:
            schedule_matches = None  # suppress alert; pre-window push will fix it
        print(f"Schedule comparison (in_window={in_active_window}, is_sponge={is_sponge_overnight}): matches={schedule_matches}; inverter reports: {inverter_actual}")

        # Cold-weather discharge power check: if cold protection is active and the hardware
        # discharge limit has drifted back to 100%, escalate regardless of window state.
        # (This is already handled in the cold-weather block above, but log it here too.)
        # Self-heal escalation:
        # 1. Inside an active Battery First window where a SoC/power mismatch changes charging behaviour RIGHT NOW.
        # 2. OR during overnight EV Sponge where inverter is unauthorizedly in Battery First / AC Charge mode!
        # `is False` (not `not ...`): tri-state None = data unavailable — never escalate.
        if mode == "read" and schedule_matches is False:
            if in_active_window:
                print("Drift detected INSIDE active Battery First window — escalating to corrective write.")
                mode = "sync"
            elif is_sponge_overnight:
                print("EMERGENCY DRIFT DETECTED: Inverter is in Battery First / AC Charge during EV Sponge! Escalating to corrective sync!")
                mode = "sync"

        if mode == "read":
            if is_token_mode:
                soc_disp = live_status.get('soc', 'unknown')
                ppv_disp = live_status.get('ppv', 'unknown')
            else:
                soc_disp = live_status.get('SOC', 'unknown')
                ppv_disp = live_status.get('ppv', 'unknown')
            success_msg = f"Retrieved live status successfully (Battery: {soc_disp}%, Solar: {ppv_disp}W)"
            print(success_msg)
            log_run_status(db, trigger_type, "success", success_msg, f"read_{target_date.strftime('%a')}", target_params,
                           inverter_matches=schedule_matches, inverter_actual=inverter_actual)
            return {
                "status": "success",
                "message": success_msg,
                "live_data": {
                    "soc": soc_disp,
                    "ppv": ppv_disp
                }
            }

        # --- MODE IS "SYNC" ---
        if schedule_matches:
            success_msg = f"Resolved schedule for {target_date.strftime('%a')} is already active on the inverter. Skipped write to protect EEPROM memory."
            print(success_msg)
            log_run_status(db, trigger_type, "success", success_msg, target_date.strftime("%a"), target_params,
                           inverter_matches=True, inverter_actual=inverter_actual)
            return {"status": "success", "message": success_msg, "skipped": True}

        # Enforce Safety Gate Clamp before writing any target_params to physical inverter
        try:
            live_doc = db.collection('status').document('battery_health').get()
            live_cell_temp = float(live_doc.to_dict().get('ambient_temp_c', 4.0)) if (live_doc.exists and live_doc.to_dict()) else 4.0
            safe_dis_pct, safe_chg_pct, _, _ = compute_cold_weather_battery_limits(live_cell_temp)
            if len(target_params) >= 2:
                p_chg = int(target_params[0]) if (str(target_params[0]).isdigit() and int(target_params[0]) > 0) else 100
                p_dis = int(target_params[1]) if str(target_params[1]).isdigit() else 100
                target_params[0] = str(min(p_chg, safe_chg_pct))
                target_params[1] = str(min(p_dis, safe_dis_pct))
                print(f"Safety Gate Clamp Applied: target_params[0]={target_params[0]}%, target_params[1]={target_params[1]}% (Cell Temp {live_cell_temp}°C)")
        except Exception as ex_clamp:
            print(f"Warning: Safety Gate Clamp failed: {str(ex_clamp)}")

        # If power is 0 or (plan is EV Sponge and NOT inside an active charge window), ensure Load First (0) mode
        if (str(global_power) == "0" or global_power == 0 or (plan_is_sponge and not in_active_charge_window)) and not is_token_mode:
            try:
                curr_p = str(live_status.get('priorityChoose', '0'))
                if curr_p != '0':
                    print(f"EV Sponge / Standby Mode: Ensuring inverter priorityChoose is Load First (0) (was {curr_p})...")
                    api.update_mix_inverter_setting(device_sn, 'priorityChoose', {'param1': '0'})

                # Maintain discharge power at 100% (cold-weather clamped)
                p_dis_val = str(min(100, safe_dis_pct)) if 'safe_dis_pct' in locals() else '100'
                hdata = live_status.get('hdata') or {}
                is_grid_first_active = bool(hdata.get('grid_first_active', False))
                dis_soc = '80'
                dis_en = '1' if is_grid_first_active else '0'
                sponge_dis_params = [
                    p_dis_val, dis_soc,
                    '09', '00', '17', '00', dis_en,
                    '00', '00', '00', '00', '0',
                    '00', '00', '00', '00', '0'
                ]
                api.update_mix_inverter_setting(device_sn, 'mix_ac_discharge_time_period', sponge_dis_params)
                print(f"EV Sponge Mode: Configured priorityChoose=0 (Load First), discharge window 09:00-17:00 enable={dis_en}, stop-SoC={dis_soc}%.")
            except Exception as ex_p:
                print(f"Warning: Failed to configure EV Sponge discharge settings: {str(ex_p)}")

        print(f"Applying resolved schedule for {target_date.strftime('%a')} to inverter {device_sn}...")
        import time as _time
        response, last_err = None, None
        for attempt in range(3):
            try:
                response = api.update_mix_inverter_setting(device_sn, "mix_ac_charge_time_period", target_params)
                print(f"Inverter write response (attempt {attempt + 1}): {response}")
                if isinstance(response, dict) and response.get('success') is True:
                    last_err = None
                    break
                else:
                    last_err = ValueError(f"Inverter rejected schedule write: {response}")
            except Exception as e:
                last_err = e
            
            if attempt < 2:
                print(f"Write attempt {attempt + 1} failed: {last_err}. Retrying in 5 seconds...")
                _time.sleep(5)

        if last_err is not None:
            raise last_err

        success_msg = f"Applied resolved schedule for {target_date.strftime('%a')} to inverter {device_sn}."
        print(success_msg)
        # Just wrote the schedule ourselves — inverter now matches by definition
        log_run_status(db, trigger_type, "success", success_msg, target_date.strftime("%a"), target_params,
                       inverter_matches=True, inverter_actual="just synced")
        return {"status": "success", "message": success_msg}

    except Exception as e:
        action_name = "sync schedule" if mode == "sync" else "read live status"
        error_msg = f"Failed to {action_name}: {str(e)}"
        print(error_msg)
        log_run_status(db, trigger_type, "error", error_msg)
        return {"status": "error", "message": error_msg}

def log_run_status(db, trigger_type, status, message, schedule_type=None, params=None,
                   inverter_matches=None, inverter_actual=None):
    now = datetime.datetime.now(datetime.timezone.utc)

    # 1. Update the latest status document
    status_ref = db.collection('status').document('growatt')
    status_ref.set({
        'inverter_matches': inverter_matches,
        'inverter_actual': inverter_actual,
        'last_run': now,
        'status': status,
        'message': message,
        'applied_schedule': schedule_type,
        'params': params,
        'trigger': trigger_type
    })

    # 2. Add to logs collection
    db.collection('sync_logs').add({
        'timestamp': now,
        'status': status,
        'message': message,
        'applied_schedule': schedule_type,
        'trigger': trigger_type
    })

# --- TRIGGER DEFINITIONS ---

# 1. Scheduled Cloud Function (Runs every 5 minutes)
@scheduler_fn.on_schedule(
    schedule="*/5 * * * *",
    timezone=scheduler_fn.Timezone("Australia/Sydney"),
    region="australia-southeast1"
)
def sync_growatt_schedule_daily(event: scheduler_fn.ScheduledEvent) -> None:
    print("5-minute scheduler triggered.")

    db = firestore.client()
    settings_ref = db.collection('settings').document('growatt')
    settings_doc = settings_ref.get()

    tz_name = 'Australia/Sydney'
    tasks = []
    if settings_doc.exists:
        data = settings_doc.to_dict()
        tz_name = data.get('timezone', 'Australia/Sydney')
        tasks = data.get('tasks', [])

    try:
        local_now = datetime.datetime.now(ZoneInfo(tz_name))
    except Exception:
        local_now = datetime.datetime.now(ZoneInfo('Australia/Sydney'))

    current_min = local_now.hour * 60 + local_now.minute
    day_str = local_now.strftime("%a")  # e.g. "Mon"
    tomorrow_str = (local_now + datetime.timedelta(days=1)).strftime("%a")

    # --- Smart pre-task sync ---
    # For each enabled task, check if we're in the [start-15min, start-10min) window.
    # The 5-minute window ensures exactly one cron tick triggers a sync per task.
    # Candidates are day-matched individually: `start_min` for a task active TODAY, and
    # `start_min + 1440` for a task active TOMORROW (e.g. an AI Plan task for tomorrow
    # starting 00:00 must trigger tonight's 23:45 sync even if the weekly plan has no
    # midnight task).
    should_sync = False
    for task in tasks:
        if not task.get('enabled', False):
            continue
        days = task.get('days', [])
        start_time = task.get('start_time', '00:00')
        try:
            sh, sm = map(int, start_time.split(':'))
        except Exception:
            continue
        start_min = sh * 60 + sm

        for candidate, needed_day in [(start_min, day_str), (start_min + 1440, tomorrow_str)]:
            if needed_day not in days:
                continue
            if candidate - 15 <= current_min < candidate - 10:
                should_sync = True
                print(f"Task '{task.get('name', start_time)}' starts in ~{candidate - current_min} min — triggering pre-task sync.")
                break
        if should_sync:
            break

    # ── Midnight Transition Schedule Push Guarantee ──
    # Between 23:45 and 00:15 (the critical day-transition window), ensure the new schedule was successfully written.
    # If the pre-task sync failed due to a temporary network error, keep retrying on every 5-min tick until confirmed!
    if not should_sync and ((local_now.hour == 23 and local_now.minute >= 45) or (local_now.hour == 0 and local_now.minute <= 15)):
        try:
            target_applied_day = (local_now + datetime.timedelta(days=1)).strftime("%a") if local_now.hour == 23 else local_now.strftime("%a")
            recent_logs = list(db.collection('sync_logs').order_by('timestamp', direction=firestore.Query.DESCENDING).limit(3).stream())
            confirmed_write = any(
                l.to_dict().get('status') == 'success' and
                f"Applied resolved schedule for {target_applied_day}" in str(l.to_dict().get('message', ''))
                for l in recent_logs
            )
            if not confirmed_write:
                should_sync = True
                print(f"Midnight Transition Retry: No confirmed write found for {target_applied_day}. Retrying sync...")
        except Exception as ex_retry:
            print(f"Notice: Failed to check midnight transition retry: {str(ex_retry)}")

    # ── EV Sponge Floor Lock Force-Sync ──
    # During sponge hours, if the floor lock has NOT yet been written
    # (sponge_floor_locked=False) but tesla_continue_charge=True, we MUST run in sync mode.
    # Why: in read mode, is_token_mode stays True (the forced-legacy override only fires for
    # mode="sync"). With is_token_mode=True the Battery First write path (elif not is_token_mode)
    # is permanently blocked, so the floor lock never gets written and the battery discharges to 10%.
    if not should_sync and (local_now.hour < 9 or local_now.hour >= 21):
        try:
            plan_doc = db.collection('status').document('charging_plan').get()
            plan_data = plan_doc.to_dict() if plan_doc.exists else {}
            _is_sponge = (plan_data.get('ev_sponge_active', False) or
                          plan_data.get('charge_kwh', 1.0) == 0.0)
            _continue = bool(plan_data.get('tesla_continue_charge', False))
            _locked   = bool(plan_data.get('sponge_floor_locked', False))
            if _is_sponge and _continue and not _locked:
                should_sync = True
                print("EV Sponge floor lock pending (tesla_continue_charge=True, sponge_floor_locked=False): "
                      "forcing sync mode so Battery First write path is available (legacy API required).")
        except Exception as ex_sponge_check:
            print(f"Notice: Failed to check EV Sponge floor lock state: {str(ex_sponge_check)}")

    # ── Daytime High-SoC Protection Force-Sync (Grid First 09:00–17:00) ──
    # When conditions require state change between Load First (0) and Grid First (2),
    # force sync mode so the legacy write API is available to write priorityChoose.
    if not should_sync:
        try:
            live_doc = db.collection('status').document('growatt_live').get()
            live_d = (live_doc.to_dict() or {}).get('data', {}) if live_doc.exists else {}
            _live_soc = float(live_d.get('SOC') or live_d.get('soc') or 0.0)
            _live_ppv = float(live_d.get('ppv') or live_d.get('storagePpv') or 0.0)
            _live_prio = str(live_d.get('priorityChoose', '0'))

            plan_doc = db.collection('status').document('charging_plan').get()
            plan_d = plan_doc.to_dict() if plan_doc.exists else {}
            _pv_fc = float(plan_d.get('pv_forecast_kwh') or 0.0)
            _load_fc = float(plan_d.get('load_forecast_kwh') or plan_d.get('household_daily_kwh') or 999.0)
            _has_surplus = (_pv_fc >= _load_fc and _pv_fc >= 15.0)

            bh_doc = db.collection('status').document('battery_health').get()
            _cal_due = bool((bh_doc.to_dict() or {}).get('calibration_due', False)) if bh_doc.exists else False
            _is_winter = local_now.month in [6, 7, 8]
            _in_window = (9 <= local_now.hour < 17)

            _can_protect = _in_window and not _is_winter and _has_surplus and not _cal_due

            # 1. Need switch to Grid First (2)
            if _can_protect and _live_soc >= 80.0 and _live_ppv >= 1.5 and _live_prio != '2':
                should_sync = True
                print(f"Daytime High-SoC Protection Trigger: SoC={_live_soc}%, PV={_live_ppv:.2f}kW -> forcing sync mode to set Grid First (2).")
            # 2. Need revert to Load First (0)
            elif _live_prio == '2' and (not _can_protect or _live_soc < 75.0 or _live_ppv < 0.3):
                should_sync = True
                print(f"Daytime High-SoC Protection End: hour={local_now.hour}, SoC={_live_soc}%, PV={_live_ppv:.2f}kW -> forcing sync mode to restore Load First (0).")
        except Exception as ex_dt_sync:
            print(f"Notice: Failed to check daytime high-soc force-sync state: {str(ex_dt_sync)}")

    mode = "sync" if should_sync else "read"
    print(f"Mode: {mode} (current local time: {local_now.strftime('%H:%M')} {day_str})")
    run_sync_logic(trigger_type="scheduler", mode=mode)

    # Continuously update today's live daily bill snapshot in Firestore so App UI chart tracks real-time PV yield
    try:
        today_date_str = local_now.strftime("%Y-%m-%d")
        tariff_dict = data.get('tariff', {}) if settings_doc.exists else {}
        live_bill = compute_bill_for_date(db, today_date_str, tz_name, tariff_dict)
        db.collection('daily_bills').document(today_date_str).set(live_bill, merge=True)
    except Exception as e_bill:
        print(f"Warning: Failed to update live daily bill for {local_now.strftime('%Y-%m-%d')}: {str(e_bill)}")
        
    # Polling of Tesla API removed from here to preserve API limits.
    # We now rely exclusively on the Tesla Webhook push events for real-time telemetry.


@https_fn.on_call(region="australia-southeast1")
def get_tesla_auth_url(req: https_fn.CallableRequest) -> dict:
    """Returns Tesla OAuth 2.0 URL for mobile login."""
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Authenticated user required."
        )
    db = firestore.client()
    doc = db.collection("settings").document("tesla").get()
    cfg = doc.to_dict() if doc.exists else {}
    client_id = cfg.get("client_id", "")
    redirect_uri = cfg.get("redirect_uri", "https://australia-southeast1-demo-solar-microgrid.cloudfunctions.net/tesla_oauth_callback")
    
    client = TeslaFleetClient(client_id=client_id)
    auth_url = client.get_auth_url(redirect_uri=redirect_uri)
    return {"status": "success", "auth_url": auth_url}


@https_fn.on_request(region="australia-southeast1")
def tesla_oauth_callback(req: https_fn.Request) -> https_fn.Response:
    """Processes Tesla OAuth callback code and stores access/refresh tokens."""
    code = req.args.get("code")
    if not code:
        return https_fn.Response("Missing auth code", status=400)
    db = firestore.client()
    doc = db.collection("settings").document("tesla").get()
    cfg = doc.to_dict() if doc.exists else {}
    client_id = cfg.get("client_id", "")
    client_secret = cfg.get("client_secret", "")
    redirect_uri = cfg.get("redirect_uri", "https://australia-southeast1-demo-solar-microgrid.cloudfunctions.net/tesla_oauth_callback")
    
    try:
        client = TeslaFleetClient(client_id=client_id, client_secret=client_secret)
        tokens = client.exchange_code_for_tokens(code, redirect_uri)
        access_tok = tokens.get("access_token")
        refresh_tok = tokens.get("refresh_token")
        expires_at = tokens.get("expires_at")

        db.collection("settings").document("tesla").set({
            "access_token": access_tok,
            "refresh_token": refresh_tok,
            "expires_at": expires_at,
            "enabled": True,
            "updated_at": datetime.datetime.now(datetime.timezone.utc)
        }, merge=True)
        # Immediately poll Tesla state
        res = smart_poll_tesla(db)
        b_lvl = res.get("battery_level", 59)
        c_name = res.get("car_name", "Tesla Model Y")
        return https_fn.Response(f"<h1>Tesla Account Successfully Connected!</h1><p>Linked {c_name} (Current Battery: {b_lvl}%). You can close this window and return to XGrowatt app.</p>", headers={"Content-Type": "text/html"})
    except Exception as e:
        print(f"Error in tesla_oauth_callback: {str(e)}")
        return https_fn.Response(f"<h1>Error linking Tesla account</h1><p>{str(e)}</p>", status=500, headers={"Content-Type": "text/html"})


@https_fn.on_request(region="australia-southeast1")
def tesla_public_key(req: https_fn.Request) -> https_fn.Response:
    """Serves official Tesla Fleet API public key at /.well-known/appspecific/com.tesla.3p.public-key.pem."""
    db = firestore.client()
    doc = db.collection("settings").document("tesla").get()
    pub_key = doc.to_dict().get("public_key_pem", "") if doc.exists else ""
    return https_fn.Response(pub_key, headers={"Content-Type": "application/x-pem-file", "Access-Control-Allow-Origin": "*"})


# 2. Firestore Document Change Trigger
@firestore_fn.on_document_written(document="settings/growatt", region="australia-southeast1")
def on_settings_write(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    if not event.data.after.exists:
        return

    before_data = event.data.before.to_dict() if event.data.before.exists else {}
    after_data = event.data.after.to_dict() or {}

    important_keys = [
        'username', 'password', 'device_sn', 'timezone', 'tasks', 'server_url', 'api_token'
    ]

    has_changed = False
    for key in important_keys:
        if before_data.get(key) != after_data.get(key):
            has_changed = True
            break

    if has_changed:
        # Skip if demo account — no real Growatt credentials to push
        after_username = after_data.get('username', '')
        after_token = after_data.get('api_token', '')
        if after_username == 'demo@xgrowatt.com' or (not after_username and not after_token):
            print("Settings changed but account is demo or empty — skipping sync.")
            return
        print("Settings document changed. Triggering sync...")
        run_sync_logic(trigger_type="settings_update", mode="sync")
    else:
        print("Non-config settings update ignored.")

# 3. Callable HTTP Function (Triggered manually via the iOS app)
@https_fn.on_call(region="australia-southeast1")
def trigger_growatt_sync_now(req: https_fn.CallableRequest) -> dict:
    print("Manual sync requested from iOS app.")
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="The function must be called by an authenticated user."
        )
    
    data = req.data or {}
    mode = data.get("mode", "sync")
    
    return run_sync_logic(trigger_type="manual_trigger", mode=mode)


# 4. Daily Billing Helper and Chron Job Functions
def compute_bill_for_date(db, date_str: str, tz_name: str, tariff: dict) -> dict:
    import datetime
    from zoneinfo import ZoneInfo
    
    try:
        y, m, d = map(int, date_str.split('-'))
    except Exception as e:
        raise ValueError(f"Invalid date format: {date_str}") from e
        
    local_tz = ZoneInfo(tz_name)
    start_dt = datetime.datetime(y, m, d, 0, 0, 0, tzinfo=local_tz)
    end_dt = datetime.datetime(y, m, d, 23, 59, 59, tzinfo=local_tz)
    
    # Query telemetry history within the day bounds
    docs = db.collection('telemetry_history') \
             .where('timestamp', '>=', start_dt) \
             .where('timestamp', '<=', end_dt) \
             .order_by('timestamp', direction=firestore.Query.ASCENDING) \
             .get()
             
    entries = []
    for doc in docs:
        d_dict = doc.to_dict()
        ts = d_dict.get('timestamp')
        if not ts:
            continue
        dt_local = ts.astimezone(local_tz)
        entries.append({
            'timestamp': dt_local,
            'solar_kw': float(d_dict.get('solar_generation_kw', 0.0)),
            'load_kw': float(d_dict.get('local_load_kw', 0.0)),
            'import_kw': float(d_dict.get('grid_import_kw', 0.0)),
            'export_kw': float(d_dict.get('grid_export_kw', 0.0)),
            'charge_kw': float(d_dict.get('charge_power_kw', 0.0)),
            'discharge_kw': float(d_dict.get('discharge_power_kw', 0.0))
        })
        
    daily_supply_charge = float(tariff.get('dailySupplyCharge', 0.95))
    fallback_import = float(tariff.get('fallbackImportRate', 0.30))
    fallback_export = float(tariff.get('fallbackExportRate', 0.08))
    rules = tariff.get('rules', [])
    
    bill = {
        'date': date_str,
        'timestamp': datetime.datetime.now(local_tz),
        'solar_kwh': 0.0,
        'load_kwh': 0.0,
        'import_kwh': 0.0,
        'export_kwh': 0.0,
        'charge_kwh': 0.0,
        'discharge_kwh': 0.0,
        'net_cost': daily_supply_charge,
        'savings': 0.0,
        'arbitrage': 0.0,
        'daily_supply_charge': daily_supply_charge,
        'import_cost': 0.0,
        'export_credit': 0.0,
        'peak_kwh': 0.0,
        'peak_cost': 0.0,
        'off_peak_kwh': 0.0,
        'off_peak_cost': 0.0,
        'free_kwh': 0.0,
        'free_cost': 0.0
    }
    
    if len(entries) < 2:
        return None
        
    running_solar = 0.0
    running_load = 0.0
    running_charge = 0.0
    running_discharge = 0.0
    running_import = 0.0
    running_export = 0.0
    
    running_cost = 0.0
    running_credit = 0.0
    running_baseline_cost = 0.0
    running_arbitrage = 0.0
    
    running_peak_kwh = 0.0
    running_peak_cost = 0.0
    running_off_peak_kwh = 0.0
    running_off_peak_cost = 0.0
    running_free_kwh = 0.0
    running_free_cost = 0.0
    
    def get_rates_for_time(dt, rules_list, f_import, f_export):
        day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        day_str = day_names[dt.weekday()]
        hour_min = dt.hour * 60 + dt.minute
        
        for rule in rules_list:
            if not rule.get('enabled', True):
                continue
            if day_str not in rule.get('days', []):
                continue
            start_str = rule.get('start_time', '00:00')
            end_str = rule.get('end_time', '00:00')
            try:
                sh, sm = map(int, start_str.split(':'))
                eh, em = map(int, end_str.split(':'))
            except Exception:
                continue
            s_min = sh * 60 + sm
            e_min = eh * 60 + em
            
            if s_min < e_min:
                if s_min <= hour_min < e_min:
                    return float(rule.get('import_rate', f_import)), float(rule.get('export_rate', f_export))
            else:
                if hour_min >= s_min or hour_min < e_min:
                    return float(rule.get('import_rate', f_import)), float(rule.get('export_rate', f_export))
                    
        return f_import, f_export

    for i in range(len(entries) - 1):
        e1 = entries[i]
        e2 = entries[i+1]
        dt_hours = (e2['timestamp'] - e1['timestamp']).total_seconds() / 3600.0
        
        if dt_hours > 1.0:
            continue
            
        solar_seg = ((e1['solar_kw'] + e2['solar_kw']) / 2.0) * dt_hours
        load_seg = ((e1['load_kw'] + e2['load_kw']) / 2.0) * dt_hours
        charge_seg = ((e1['charge_kw'] + e2['charge_kw']) / 2.0) * dt_hours
        discharge_seg = ((e1['discharge_kw'] + e2['discharge_kw']) / 2.0) * dt_hours
        import_seg = ((e1['import_kw'] + e2['import_kw']) / 2.0) * dt_hours
        export_seg = ((e1['export_kw'] + e2['export_kw']) / 2.0) * dt_hours
        
        running_solar += solar_seg
        running_load += load_seg
        running_charge += charge_seg
        running_discharge += discharge_seg
        running_import += import_seg
        running_export += export_seg
        
        imp_rate, exp_rate = get_rates_for_time(e1['timestamp'], rules, fallback_import, fallback_export)
        
        cost_seg = import_seg * imp_rate
        baseline_cost_seg = load_seg * imp_rate
        
        running_cost += cost_seg
        running_baseline_cost += baseline_cost_seg
        running_credit += export_seg * exp_rate
        
        # Classify import segment energy & cost
        if imp_rate <= 0.01:
            running_free_kwh += import_seg
            running_free_cost += cost_seg
        elif imp_rate >= fallback_import - 0.001:
            running_peak_kwh += import_seg
            running_peak_cost += cost_seg
        else:
            running_off_peak_kwh += import_seg
            running_off_peak_cost += cost_seg
        
        min_rate = fallback_import
        for rule in rules:
            if rule.get('enabled', True):
                min_rate = min(min_rate, float(rule.get('import_rate', fallback_import)))
        
        if imp_rate > min_rate:
            arbitrage_seg = discharge_seg * (imp_rate - min_rate)
            running_arbitrage += arbitrage_seg

    net_cost = running_cost - running_credit + daily_supply_charge
    baseline_bill = running_baseline_cost + daily_supply_charge
    running_savings = max(0.0, baseline_bill - net_cost)

    # Tesla Sub-metering & Tariff Integration
    tesla_kwh = 0.0
    tesla_cost = 0.0
    tesla_savings = 0.0
    try:
        tesla_doc = db.collection("status").document("tesla_live").get()
        if tesla_doc.exists:
            t_dict = tesla_doc.to_dict() or {}
            t_updated = t_dict.get("last_updated", "")
            if date_str in str(t_updated):
                tesla_kwh = float(t_dict.get("charge_energy_added_kwh", 0.0))
        
        sess_docs = db.collection("tesla_sessions").where("date", "==", date_str).get()
        sess_sum = 0.0
        for s_doc in sess_docs:
            s_dict = s_doc.to_dict() or {}
            sess_sum += float(s_dict.get("kwh_added", 0.0))
        if sess_sum > 0:
            tesla_kwh = sess_sum

        min_tariff = fallback_import
        for rule in rules:
            if rule.get('enabled', True):
                min_tariff = min(min_tariff, float(rule.get('import_rate', fallback_import)))
        
        tesla_cost = tesla_kwh * min_tariff
        tesla_savings = max(0.0, (tesla_kwh * fallback_import) - tesla_cost)
    except Exception as e_t:
        print(f"Error computing Tesla bill sub-metering: {str(e_t)}")

    house_load_kwh = max(0.0, running_load - tesla_kwh)
    
    bill.update({
        'solar_kwh': round(running_solar, 2),
        'load_kwh': round(running_load, 2),
        'import_kwh': round(running_import, 2),
        'export_kwh': round(running_export, 2),
        'charge_kwh': round(running_charge, 2),
        'discharge_kwh': round(running_discharge, 2),
        'net_cost': round(net_cost, 2),
        'savings': round(running_savings, 2),
        'arbitrage': round(running_arbitrage, 2),
        'daily_supply_charge': daily_supply_charge,
        'import_cost': round(running_cost, 2),
        'export_credit': round(running_credit, 2),
        'peak_kwh': round(running_peak_kwh, 2),
        'peak_cost': round(running_peak_cost, 2),
        'off_peak_kwh': round(running_off_peak_kwh, 2),
        'off_peak_cost': round(running_off_peak_cost, 2),
        'free_kwh': round(running_free_kwh, 2),
        'free_cost': round(running_free_cost, 2),
        'tesla_kwh': round(tesla_kwh, 2),
        'house_load_kwh': round(house_load_kwh, 2),
        'tesla_cost': round(tesla_cost, 2),
        'tesla_savings': round(tesla_savings, 2)
    })
    return bill


@scheduler_fn.on_schedule(
    schedule="55 23 * * *",
    timezone=scheduler_fn.Timezone("Australia/Sydney"),
    region="australia-southeast1"
)
def record_daily_bill_cron(event: scheduler_fn.ScheduledEvent) -> None:
    print("Daily bill aggregation scheduler triggered.")
    db = firestore.client()
    
    settings_ref = db.collection('settings').document('growatt')
    settings_doc = settings_ref.get()
    tz_name = "Australia/Sydney"
    tariff = {}
    if settings_doc.exists:
        data = settings_doc.to_dict()
        tz_name = data.get('timezone', 'Australia/Sydney')
        tariff = data.get('tariff', {})
        
    try:
        local_now = datetime.datetime.now(ZoneInfo(tz_name))
    except Exception:
        local_now = datetime.datetime.now(ZoneInfo('Australia/Sydney'))
        
    date_str = local_now.strftime("%Y-%m-%d")
    
    try:
        bill = compute_bill_for_date(db, date_str, tz_name, tariff)
        if bill:
            db.collection('daily_bills').document(date_str).set(bill)
            print(f"Daily bill recorded successfully for {date_str}: {bill}")
        else:
            print(f"Skipping daily bill for {date_str}: No telemetry entries found.")
    except Exception as e:
        print(f"Failed to record daily bill for {date_str}: {str(e)}")


@https_fn.on_call(region="australia-southeast1")
def trigger_backfill_bills(req: https_fn.CallableRequest) -> dict:
    print("Backfill billing records requested.")
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="The function must be called by an authenticated user."
        )
    
    data = req.data or {}
    start_date_str = data.get("start_date")
    end_date_str = data.get("end_date")
    
    if not start_date_str or not end_date_str:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Both start_date and end_date (YYYY-MM-DD) are required."
        )
        
    db = firestore.client()
    settings_ref = db.collection('settings').document('growatt')
    settings_doc = settings_ref.get()
    tz_name = "Australia/Sydney"
    tariff = {}
    if settings_doc.exists:
        data_dict = settings_doc.to_dict()
        tz_name = data_dict.get('timezone', 'Australia/Sydney')
        tariff = data_dict.get('tariff', {})
        
    try:
        start_date = datetime.datetime.strptime(start_date_str, "%Y-%m-%d").date()
        end_date = datetime.datetime.strptime(end_date_str, "%Y-%m-%d").date()
    except Exception as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message=f"Invalid date format: {str(e)}"
        )
        
    results = {}
    curr = start_date
    delta = datetime.timedelta(days=1)
    while curr <= end_date:
        curr_str = curr.strftime("%Y-%m-%d")
        try:
            bill = compute_bill_for_date(db, curr_str, tz_name, tariff)
            if bill:
                db.collection('daily_bills').document(curr_str).set(bill)
                results[curr_str] = "success"
            else:
                results[curr_str] = "skipped_no_telemetry"
        except Exception as e:
            results[curr_str] = f"failed: {str(e)}"
        curr += delta

    return {"status": "complete", "results": results}


# 5. Weather Forecast Snapshot Collector
# Runs three times daily and stores the full 72h hourly forecast as ONE document per run
# in `weather_forecast`:
#   05:00 — covers "today" (morning check-in)
#   13:00 — midday model refresh
# (No 23:00 slot: the 23:30 plan generation fetches its own fresh snapshot inline, exactly
#  like the manual refresh does, and that snapshot is archived to weather_forecast as usual.)
#
# Why store forecast snapshots at all (telemetry already has actual weather joined in):
# the future PV model's inference input is a FORECAST, not an observation. Training on
# observations only creates train/serve skew — forecasts carry horizon-dependent error the
# model never saw. Snapshots can't be reconstructed later (historical APIs only have
# actuals), so every missed day is lost training data. We keep every run's full snapshot,
# meaning each target hour gets forecast multiple times at different horizons — that lets
# the model (or an error analysis) learn how forecast quality decays with lead time.
# Field names deliberately match telemetry_history's weather fields for zero-transform joins.
def fetch_weather_forecast_logic(db) -> bool:
    """Fetches and stores one forecast snapshot. Shared by the scheduler and by the manual
    plan-regeneration callable (which refreshes the forecast BEFORE running inference, so a
    manual recalculation always reasons over the newest weather). Returns True on success."""
    settings_doc = db.collection('settings').document('growatt').get()
    settings = settings_doc.to_dict() if settings_doc.exists else {}
    tz_name = settings.get('timezone', 'Australia/Sydney')

    lat = settings.get('latitude')
    lon = settings.get('longitude')
    if lat is None or lon is None:
        lat, lon = _TIMEZONE_COORDS.get(tz_name, (-35.28, 149.13))

    try:
        import requests
        import time as _time
        params = {
            "latitude": lat,
            "longitude": lon,
            "hourly": ",".join(_HOURLY_WEATHER_VARS),
            "forecast_days": 3,
            "timezone": tz_name,
        }
        params.update(_panel_params(settings))

        # Three attempts with exponential backoff (5s, 10s) — Open-Meteo has no SLA
        # and transient timeouts happen; a failed 23:30 fetch would otherwise skip the
        # nightly plan generation entirely.
        hourly, last_err = {}, None
        _backoff = [5, 10]
        for attempt in range(3):
            try:
                resp = requests.get("https://api.open-meteo.com/v1/forecast", params=params, timeout=15)
                resp.raise_for_status()
                hourly = resp.json().get("hourly", {})
                if hourly.get("time"):
                    print(f"Weather fetch succeeded on attempt {attempt + 1}.")
                    break
                last_err = ValueError("Open-Meteo returned no hourly times")
            except Exception as e:
                last_err = e
                if attempt < 2:
                    wait = _backoff[attempt]
                    print(f"Weather fetch attempt {attempt + 1} failed ({e}), retrying in {wait}s...")
                    _time.sleep(wait)
        times = hourly.get("time", [])
        if not times:
            raise last_err or ValueError("Open-Meteo returned no hourly times")

        # One entry per forecast hour; reuse the same extractor as the telemetry join so
        # field names/units stay in lockstep with telemetry_history.
        hours = []
        for i, t in enumerate(times):
            entry = _weather_snapshot_from_hourly(hourly, i)
            entry["time"] = t  # local time "YYYY-MM-DDTHH:00", aligns with telemetry timestamps
            hours.append(entry)

        try:
            now_local = datetime.datetime.now(ZoneInfo(tz_name))
        except Exception:
            now_local = datetime.datetime.now(ZoneInfo('Australia/Sydney'))
        doc_id = now_local.strftime("%Y-%m-%d_%H")
        forecast_payload = {
            'issued_at': datetime.datetime.now(datetime.timezone.utc),
            'latitude': lat,
            'longitude': lon,
            'timezone': tz_name,
            'hours': hours,
        }
        db.collection('weather_forecast').document(doc_id).set(forecast_payload)
        db.collection('status').document('weather_forecast').set(forecast_payload)
        print(f"Stored forecast snapshot weather_forecast/{doc_id} and status/weather_forecast ({len(hours)} hours).")
        return True
    except Exception as e:
        # Log-only failure: next scheduled run (or tomorrow's) fills the gap. No retries here
        # to keep the function idempotent and cheap.
        print(f"Error: Failed to fetch/store weather forecast: {str(e)}")
        return False


@scheduler_fn.on_schedule(
    schedule="0 5,13 * * *",
    timezone=scheduler_fn.Timezone("Australia/Sydney"),
    region="australia-southeast1"
)
def fetch_weather_forecast(event: scheduler_fn.ScheduledEvent) -> None:
    print("Weather forecast collection triggered.")
    fetch_weather_forecast_logic(firestore.client())


# 6. Charging Plan Generator (ADVISORY ONLY — writes status/charging_plan, never settings.tasks)
#
# Decision logic: the battery only needs enough overnight (off-peak) grid charge to survive
# from 06:00 until the NEXT cheap-import window, net of predicted PV:
#   - weekdays: next cheap window is next midnight -> cover 06:00-24:00 (the 48h horizon
#     still watches Day-2, but tomorrow night's equally-cheap off-peak window is modeled
#     as rechargeable, so Day-2 deficits no longer inflate tonight's charge)
#   - Sat/Sun with a free 12:00-14:00 window: only cover 06:00-12:00 (free window refills),
#     so the night before a weekend day we deliberately charge much less.
# Required 06:00 energy = exact battery-clipped simulation over the span (bisection on the
# start level, see _required_start_energy) + a safety margin calibrated from historical
# forecast error (P90, see _calibrate_soc_margin; ratio-tier fallback with short history).
# Sunny forecast -> small deficit -> small overnight charge; cloudy -> big.
# Any zero-rate window is always used to fill to max (free energy, only foregone export credit).

AC_CHARGE_EFF = 0.95  # grid->battery round-in efficiency assumption


def _rates_at(dt_local, tariff):
    """(import_rate, export_rate) at a local datetime per tariff rules (mirrors
    compute_bill_for_date's matching logic)."""
    f_imp = float(tariff.get('fallbackImportRate', 0.30))
    f_exp = float(tariff.get('fallbackExportRate', 0.08))
    day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    day_str = day_names[dt_local.weekday()]
    hour_min = dt_local.hour * 60 + dt_local.minute
    for rule in tariff.get('rules', []):
        if not rule.get('enabled', True) or day_str not in rule.get('days', []):
            continue
        try:
            sh, sm = map(int, rule.get('start_time', '00:00').split(':'))
            eh, em = map(int, rule.get('end_time', '00:00').split(':'))
        except Exception:
            continue
        s_min, e_min = sh * 60 + sm, eh * 60 + em
        in_window = (s_min <= hour_min < e_min) if s_min < e_min else (hour_min >= s_min or hour_min < e_min)
        if in_window:
            return float(rule.get('import_rate', f_imp)), float(rule.get('export_rate', f_exp))
    return f_imp, f_exp


def _import_rate_at(dt_local, tariff):
    return _rates_at(dt_local, tariff)[0]


def _in_ev_window(hour, ev_start, ev_end):
    """True if `hour` falls inside the EV charging window (handles midnight wrap;
    ev_start == ev_end disables the window)."""
    if ev_start == ev_end:
        return False
    if ev_start < ev_end:
        return ev_start <= hour < ev_end
    return hour >= ev_start or hour < ev_end


def _required_start_energy(deltas, reserve_kwh, cap_kwh):
    """Smallest 06:00 battery energy E0 such that the hour-by-hour simulation
    E(t+1) = min(cap_kwh, E(t) + delta_t) never dips below reserve_kwh.

    This replaces the old 'cumulative deficit with an ABSOLUTE surplus cap' shortcut,
    which capped banked surplus at full capacity regardless of the starting level —
    physically the battery can only bank (cap - current_energy) of surplus, so the old
    form could let a morning surplus offset a later deficit more than reality allows
    (under-charging on surplus-then-deficit days). Feasibility is monotone in E0, so a
    bisection over [reserve, cap] gives the exact answer cheaply (~30 x len(deltas) ops)."""
    def survives(e0):
        e = e0
        for d in deltas:
            e = min(cap_kwh, e + d)
            if e < reserve_kwh - 1e-9:
                return False
        return True
    lo, hi = reserve_kwh, cap_kwh
    if survives(lo):
        return lo
    if not survives(hi):
        return hi  # even a full battery can't avoid the dip; charge to cap
    for _ in range(30):
        mid = (lo + hi) / 2.0
        if survives(mid):
            hi = mid
        else:
            lo = mid
    return hi


def _pv_assisted_cal_start(predict_pv, predict_load, six_am, deadline, reserve_kwh,
                           rated_kwh, max_charge_kw):
    """Minimum 06:00 battery energy from which forecast PV surplus (charge-rate capped)
    pushes the battery to 100% (rated_kwh) by `deadline`. Bisection, same pattern as
    _required_start_energy. Returns ~rated_kwh when PV can't finish the job from ANY
    start level (e.g. cloudy day or no forecast -> caller falls back to the classic
    full overnight charge)."""
    def reaches_full(e0):
        e = e0
        t = six_am
        while t < deadline:
            net = min(predict_pv(t) - predict_load(t), max_charge_kw)
            e = max(reserve_kwh, min(rated_kwh, e + net))
            if e >= rated_kwh - 1e-9:
                return True
            t += datetime.timedelta(hours=1)
        return False
    if reaches_full(reserve_kwh):
        return reserve_kwh
    lo, hi = reserve_kwh, rated_kwh
    for _ in range(25):
        mid = (lo + hi) / 2.0
        if reaches_full(mid):
            hi = mid
        else:
            lo = mid
    return hi


def _calibrate_soc_margin(db, rated_kwh, quantile=0.9, lookback_days=30, min_samples=7):
    """Data-driven safety margin from HISTORICAL forecast error, replacing fixed tiers
    once enough history exists.

    Joins charging_plan_history (day-ahead predicted PV/load) with daily_bills actuals
    (solar_kwh / load_kwh) by date. Daily energy-balance error:
        err = (pred_pv - actual_pv) + (actual_load - pred_load)   [kWh]
    Positive err = the plan was optimistic by that many kWh — exactly the shortfall the
    margin must cover. The chosen QUANTILE of err becomes the margin (as % of rated
    capacity), clamped to 5-25%. The quantile is the newsvendor critical fractile the
    caller derives from the tariff (under-charge vs over-charge cost) — typically ~0.68,
    deliberately less conservative than a blanket P90: over-charging displaces storable
    PV, and that costs real money too. Returns (None, reason) with < min_samples so the
    caller falls back to the PV/load-ratio heuristic."""
    try:
        errs = []
        docs = db.collection('charging_plan_history').limit(lookback_days + 14).get()
        for d in docs:
            p = d.to_dict() or {}
            pred_pv, pred_load = p.get('pv_forecast_kwh'), p.get('load_forecast_kwh')
            if pred_pv is None or pred_load is None:
                continue
            b = db.collection('daily_bills').document(d.id).get()
            if not b.exists:
                continue  # future / unbilled dates
            bd = b.to_dict() or {}
            act_pv, act_load = bd.get('solar_kwh'), bd.get('load_kwh')
            if act_pv is None or act_load is None:
                continue
            errs.append((float(pred_pv) - float(act_pv)) + (float(act_load) - float(pred_load)))
        if len(errs) < min_samples:
            return None, f"forecast-error history too short ({len(errs)}/{min_samples} days)"
        errs.sort()
        pq = errs[min(len(errs) - 1, int(round(quantile * (len(errs) - 1))))]
        margin_pct = max(5.0, min(25.0, max(0.0, pq) / rated_kwh * 100.0))
        return margin_pct, (f"P{quantile * 100:.0f} (newsvendor fractile) of {len(errs)}-day "
                            f"forecast error {pq:+.1f} kWh -> {margin_pct:.0f}% of {rated_kwh:.0f} kWh")
    except Exception as e:
        return None, f"margin calibration failed: {str(e)}"


def _build_load_lookup(db, settings, tz_name):
    """Average local_load_kw per (is_weekend, hour) bucket over recent history — EV-aware.

    The Tesla charges on a fixed schedule (default 00:00-06:00; override with settings
    ev_charge_start_hour / ev_charge_end_hour, set both equal to disable). Telemetry rows
    inside that window measure car + house, not house, so they are EXCLUDED from the
    buckets entirely. Predictions for hours inside the window instead reuse the late-evening
    (22:00/23:00) household base load — a time the car never charges. This beats subtracting
    an assumed EV energy (e.g. 24 kWh/night): it stays correct on nights the car is away,
    charges less, or finishes early.

    RECENCY WEIGHTING: samples decay with half-life load_halflife_days (default 2), so a
    warming/cooling transition passes through in ~2 days, and one anomalous day (guest
    visit, forgotten dishwasher) can't hold 25% weight for the whole window. The window
    itself is 7 days (settings load_lookup_days) for hour-coverage robustness — day-7
    samples only carry ~9% weight, so the wider window doesn't reintroduce lag.
    """
    local_tz = ZoneInfo(tz_name)
    days = int(settings.get('load_lookup_days', 7))
    halflife = float(settings.get('load_halflife_days', 2.0))
    ev_start = int(settings.get('ev_charge_start_hour', 0))
    ev_end = int(settings.get('ev_charge_end_hour', 6))

    now_utc = datetime.datetime.now(datetime.timezone.utc)
    cutoff = now_utc - datetime.timedelta(days=days)
    sums, counts = {}, {}
    for doc in db.collection('telemetry_history').where('timestamp', '>=', cutoff).stream():
        x = doc.to_dict()
        ts = x.get('timestamp')
        load = x.get('local_load_kw')
        if ts is None or load is None:
            continue
        lt = ts.astimezone(local_tz)
        if _in_ev_window(lt.hour, ev_start, ev_end):
            continue  # EV-contaminated sample
        age_days = max(0.0, (now_utc - ts).total_seconds() / 86400.0)
        w = 0.5 ** (age_days / halflife) if halflife > 0 else 1.0
        key = (lt.weekday() >= 5, lt.hour)
        sums[key] = sums.get(key, 0.0) + w * float(load)
        counts[key] = counts.get(key, 0.0) + w
    lookup = {k: sums[k] / counts[k] for k in sums if counts[k] > 1e-9}
    overall = (sum(sums.values()) / max(1e-9, sum(counts.values()))) if counts else 0.8

    # Trained load model (status/pv_model 'load' block) — deployed by upload_model.py ONLY
    # when it beat this very bucket baseline on daily-kWh MAE in training. Used for non-EV
    # hours when the forecast snapshot provides temperature; buckets stay as the fallback
    # for missing forecast entries and as the EV-window substitute.
    import math
    load_model, fc_entries = None, {}
    try:
        mdoc = db.collection('status').document('pv_model').get()
        if mdoc.exists:
            blk = (mdoc.to_dict() or {}).get('load')
            if blk and blk.get('coef') and blk.get('recommended') == 'ridge':
                load_model = blk
        if load_model:
            fdocs = db.collection('weather_forecast').order_by(
                'issued_at', direction=firestore.Query.DESCENDING).limit(1).get()
            if len(fdocs) > 0:
                for h in (fdocs[0].to_dict() or {}).get('hours', []):
                    if h.get('time'):
                        fc_entries[h['time']] = h
    except Exception as e:
        print(f"Warning: load model unavailable, using buckets: {str(e)}")
        load_model = None

    def night_base(is_weekend):
        vals = [lookup[k] for k in [(is_weekend, 22), (is_weekend, 23)] if k in lookup]
        return sum(vals) / len(vals) if vals else overall

    def predict(dt_local):
        is_weekend = dt_local.weekday() >= 5
        if _in_ev_window(dt_local.hour, ev_start, ev_end):
            return night_base(is_weekend)  # household-only proxy for EV hours
        if load_model:
            entry = fc_entries.get(dt_local.strftime("%Y-%m-%dT%H:00"))
            if entry is not None and entry.get('temperature_c') is not None:
                h = dt_local.hour
                # MUST mirror ml/train_pv_model.py LOAD_FEATURES construction.
                feats = {
                    'hour_sin': math.sin(2 * math.pi * h / 24.0),
                    'hour_cos': math.cos(2 * math.pi * h / 24.0),
                    'hour_sin2': math.sin(4 * math.pi * h / 24.0),
                    'hour_cos2': math.cos(4 * math.pi * h / 24.0),
                    'is_weekend': 1.0 if is_weekend else 0.0,
                    'temperature_c': float(entry['temperature_c']),
                    'is_day': 1.0 if entry.get('is_day') else 0.0,
                }
                pred = load_model['intercept'] + sum(
                    float(load_model['coef'][f]) * float(feats.get(f) or 0.0)
                    for f in load_model['features'])
                return max(0.05, pred)  # floor: an occupied house never draws zero
        return lookup.get((is_weekend, dt_local.hour), overall)
    return predict


def compute_weather_attenuation(cloud_pct, precip_mm):
    """
    Computes physical optical cloud thickness & rain attenuation factor.
    Prevents standard diffuse radiation models from over-predicting on heavy overcast/rainy days.
    Returns attenuation multiplier in range [0.15, 1.0].
    """
    import math
    c = max(0.0, min(100.0, float(cloud_pct or 0.0))) / 100.0
    p = max(0.0, float(precip_mm or 0.0))
    
    # 1. Non-linear Cloud Overcast Damping (cubic scaling kicks in heavily at c > 0.70)
    cloud_factor = 1.0 - 0.35 * (c ** 3)
    
    # 2. Precipitation Damping (water film on glass + deep nimbostratus optical extinction)
    rain_factor = 1.0
    if p > 0.05:
        rain_factor = 1.0 / (1.0 + 1.8 * math.sqrt(p) * c)
        
    return max(0.15, min(1.0, cloud_factor * rain_factor))


def _pv_residual_factor(db, lookback_days=14):
    """END-TO-END nightly PV bias correction (MPC-style output-residual feedback).

    Computes ratio of ACTUAL to PREDICTED daily PV energy over the last N days with
    exponential recency weighting to track seasonal solar altitude increases.
    Shrinks toward 1.0 with thin evidence and clamps to [0.75, 1.50] (adaptive seasonal ceiling).
    """
    import math
    try:
        now_utc = datetime.datetime.now(datetime.timezone.utc)
        cutoff_date = (now_utc - datetime.timedelta(days=lookback_days + 1)).strftime('%Y-%m-%d')
        
        # Query docs strictly within the recent window
        docs = db.collection('charging_plan_history').where('for_date', '>=', cutoff_date).stream()
        
        day_entries = []
        for d in docs:
            p = d.to_dict() or {}
            pv_pred = p.get('pv_forecast_raw_kwh') or p.get('pv_forecast_kwh')
            if pv_pred is None:
                continue
            b = db.collection('daily_bills').document(d.id).get()
            if not b.exists:
                continue
            act = (b.to_dict() or {}).get('solar_kwh')
            if act is None:
                continue
            day_entries.append((d.id, float(pv_pred), float(act)))
            
        if not day_entries:
            return 1.0, "bias correction off (insufficient history)"
            
        # Sort chronologically and apply recency weighting (half-life ~ 5 days)
        day_entries.sort(key=lambda x: x[0])
        weighted_pred, weighted_act = 0.0, 0.0
        n = len(day_entries)
        for idx, (_, pred, act) in enumerate(day_entries):
            age_days = n - 1 - idx
            weight = math.exp(-0.12 * age_days)
            weighted_pred += pred * weight
            weighted_act += act * weight
            
        if weighted_pred < 5.0:
            return 1.0, "bias correction off (insufficient weighted history)"
            
        raw_ratio = weighted_act / weighted_pred
        w_shrink = min(1.0, weighted_pred / 40.0)
        # Adaptive seasonal ceiling: Australia spring/summer (Sep-Mar) reaches 33-38 kWh clear-sky,
        # allow clamp up to 1.50 to avoid overly conservative discharge; winter clamps to 1.35.
        season_max = 1.50 if now_utc.month in [9, 10, 11, 12, 1, 2, 3] else 1.35
        final_factor = max(0.75, min(season_max, 1.0 + (raw_ratio - 1.0) * w_shrink))
        return final_factor, f"{lookback_days}d recency-weighted actual/pred={raw_ratio:.2f}, factor={final_factor:.2f} (ceiling={season_max})"
    except Exception as e:
        return 1.0, f"bias correction failed: {str(e)}"


def _build_pv_predictor(db, settings, tz_name):
    """Hourly PV predictor from the latest forecast snapshot.
    Uses trained ridge coefficients (status/pv_model, 'forecast' block from ml/train_pv_model.py)
    when present, else the cold-start empirical formula. Missing forecast hour -> 0 kW
    (conservative: charge more)."""
    import math
    capacity = float(settings.get('pv_capacity_kw', 6.6))

    fc_docs = db.collection('weather_forecast').order_by(
        'issued_at', direction=firestore.Query.DESCENDING).limit(1).get()
    fc_map, issued_at = {}, None
    if len(fc_docs) > 0:
        fdoc = fc_docs[0].to_dict()
        issued_at = fdoc.get('issued_at')
        for h in fdoc.get('hours', []):
            t_str = str(h.get('time') or '')
            if t_str:
                clean_key = t_str[:13] + ":00"
                fc_map[clean_key] = h
                fc_map[t_str] = h

    model = None
    mdoc = db.collection('status').document('pv_model').get()
    if mdoc.exists:
        blk = (mdoc.to_dict() or {}).get('forecast')
        if blk and blk.get('coef') and blk.get('recommended') in ['bayesian_ridge', 'ridge']:
            model = blk

    pr = 0.65            # overall fallback ratio
    pr_by_hour = {}      # hour -> ratio, only for hours with enough evidence
    if model is None:
        try:
            local_tz2 = ZoneInfo(tz_name)
            cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=14)
            pv_sums, gti_sums = {}, {}
            for doc in db.collection('telemetry_history').where('timestamp', '>=', cutoff).stream():
                x = doc.to_dict()
                gti_val = x.get('global_tilted_irradiance_wm2')
                pv_val = x.get('solar_generation_kw')
                ts = x.get('timestamp')
                # gti > 50 W/m2: skip dawn/dusk noise that would skew the ratio
                if gti_val is None or pv_val is None or ts is None or gti_val <= 50:
                    continue
                h = ts.astimezone(local_tz2).hour
                pv_sums[h] = pv_sums.get(h, 0.0) + float(pv_val)
                gti_sums[h] = gti_sums.get(h, 0.0) + capacity * float(gti_val) / 1000.0
            total_pv, total_gti = sum(pv_sums.values()), sum(gti_sums.values())
            if total_gti > 5.0:  # enough irradiance-weighted samples to trust
                pr = max(0.4, min(0.95, total_pv / total_gti))
            for h, g in gti_sums.items():
                if g > 1.0:  # per-bucket evidence threshold (~kWh-equivalent)
                    pr_by_hour[h] = max(0.05, min(0.95, pv_sums[h] / g))
            if pr_by_hour:
                profile = ", ".join(f"{h}h:{r:.2f}" for h, r in sorted(pr_by_hour.items()))
                print(f"PV hourly PR profile (14d): {profile}; overall {pr:.3f}")
        except Exception as e:
            print(f"Warning: PR calibration failed, using default {pr}: {str(e)}")

    q20 = (model.get('quantiles') or {}).get('p20') if model else None
    bayes_sigma_diag = model.get('sigma_diag', {}) if model else {}
    bayes_alpha = float(model.get('alpha', 0.0)) if model else 0.0

    def _feats(dt_local, entry):
        """Feature construction — supports both Standard & Bayesian non-linear low-light features."""
        hour = dt_local.hour
        doy = dt_local.timetuple().tm_yday
        feats = dict(entry)
        feats['is_day'] = 1.0
        feats['hour_sin'] = math.sin(2 * math.pi * hour / 24.0)
        feats['hour_cos'] = math.cos(2 * math.pi * hour / 24.0)
        feats['hour_sin2'] = math.sin(4 * math.pi * hour / 24.0)
        feats['hour_cos2'] = math.cos(4 * math.pi * hour / 24.0)
        feats['doy_sin'] = math.sin(2 * math.pi * doy / 365.25)
        feats['doy_cos'] = math.cos(2 * math.pi * doy / 365.25)
        feats['sun_height'] = max(0.0, math.sin(math.pi * max(0.0, hour - 6.0) / 12.0))
        _gti = float(entry.get('global_tilted_irradiance_wm2') or 0.0)
        feats['global_tilted_irradiance_wm2'] = _gti
        feats['sqrt_gti'] = math.sqrt(max(0.0, _gti))
        feats['gti_x_sun_height'] = _gti * feats['sun_height']
        feats['sqrt_gti_x_sun_height'] = feats['sqrt_gti'] * feats['sun_height']
        _cld = max(0.0, min(100.0, float(entry.get('cloud_cover_pct') or 0.0))) / 100.0
        _prcp = max(0.0, float(entry.get('precipitation_mm') or 0.0))
        feats['cloud_cover_ratio'] = _cld
        feats['cloud_x_gti'] = _cld * _gti
        feats['sqrt_precip_mm'] = math.sqrt(_prcp)
        feats['gti_x_hour_sin'] = _gti * feats['hour_sin']
        feats['gti_x_hour_cos'] = _gti * feats['hour_cos']
        feats['gti_x_hour_sin2'] = _gti * feats['hour_sin2']
        feats['gti_x_hour_cos2'] = _gti * feats['hour_cos2']
        feats['horizon_h'] = max(0.0, (dt_local - issued_at.astimezone(dt_local.tzinfo)).total_seconds() / 3600.0) if issued_at else 12.0
        return feats

    def _dot(blk, feats):
        return blk['intercept'] + sum(
            float(blk['coef'][f]) * float(feats.get(f) or 0.0) for f in blk['features'])

    # ── Nightly PV Bias Correction (END-TO-END output residual, see _pv_residual_factor) ──
    bias_scale = 1.0
    if model is not None:
        bias_scale, bias_info = _pv_residual_factor(db)
        print(f"PV bias correction: {bias_info}")

    def predict(dt_local):
        k = dt_local.strftime("%Y-%m-%dT%H:00")
        entry = fc_map.get(k) or fc_map.get(k + ":00") or fc_map.get(k + ":00Z")
        if entry is None:
            return 0.0
        if not entry.get('is_day'):
            return 0.0
            
        cld = entry.get('cloud_cover_pct', 0.0)
        prcp = entry.get('precipitation_mm', 0.0)
        attenuation = compute_weather_attenuation(cld, prcp)

        if model is None:
            pr_use = pr_by_hour.get(dt_local.hour, pr)
            gti = entry.get('global_tilted_irradiance_wm2')
            if gti is not None:
                raw_kw = capacity * (gti / 1000.0) * pr_use
            else:
                ghi = entry.get('shortwave_radiation_wm2') or 0.0
                raw_kw = capacity * (ghi / 1000.0) * pr_use * 1.2
            return min(capacity, max(0.0, raw_kw * attenuation))
            
        raw_pred = _dot(model, _feats(dt_local, entry)) * bias_scale
        return min(capacity, max(0.0, raw_pred * attenuation))

    def predict_p20(dt_local):
        """Pessimistic-quantile PV (P20): Bayesian posterior lower bound (parameter-uncertainty scaled)
        or empirical quantile floor."""
        med = predict(dt_local)
        entry = fc_map.get(dt_local.strftime("%Y-%m-%dT%H:00"))
        if entry is None or not entry.get('is_day'):
            return 0.0 if entry is not None else med

        # 1. Exact Bayesian Parameter Uncertainty Lower Bound (relative scaling prevents point-noise collapse)
        if model and model.get('recommended') == 'bayesian_ridge' and bayes_sigma_diag:
            feats = _feats(dt_local, entry)
            var_param = 0.0
            for f in model.get('features', []):
                x_val = float(feats.get(f) or 0.0)
                var_param += float(bayes_sigma_diag.get(f, 0.0)) * (x_val ** 2)
            std_param = math.sqrt(max(0.0, var_param))
            rel_unc = min(0.35, max(0.12, std_param / max(0.2, med)))
            bayes_p20 = min(capacity, max(0.0, med * (1.0 - rel_unc)))
            return min(med, bayes_p20)

        # 2. Classic Quantile Model Fallback
        if q20 is not None:
            v = min(capacity, max(0.0, _dot(q20, _feats(dt_local, entry)) * bias_scale))
            return min(med, v)

        return med

    label = model.get('recommended', 'ridge') if model else \
        f"empirical_formula (PR={pr:.2f}, hourly shade profile {len(pr_by_hour)}h, 14d)"
    return predict, label, (len(fc_map) > 0), predict_p20, bias_scale


def _check_tesla_readiness(db, settings) -> tuple[bool, bool, bool, int, int, float, str]:
    """Evaluates whether Tesla EV is parked at home, plugged in, and has charge deficit.
    If Tesla Fleet API is connected, uses real-time vehicle telemetry.
    If Tesla Fleet API is offline/unavailable, gracefully falls back to confirmed home EV presence
    (Tesla is plugged in at home charging overnight with daily demand ev_daily_kwh).
    Returns: (is_available, is_home, is_plugged, soc_now, charge_limit, needed_kwh, car_name)
    """
    fallback_need_kwh = float(settings.get('ev_daily_kwh', 24.0))
    has_ev = settings.get('has_ev', True)
    if not has_ev:
        return False, False, False, 0, 80, 0.0, ""

    try:
        tesla_doc = db.collection('status').document('tesla_live').get()
        if tesla_doc.exists:
            tdata = tesla_doc.to_dict() or {}
            if tdata.get('is_connected', False):
                car_name = str(tdata.get('car_name', 'Tesla Model Y'))
                soc_now = int(tdata.get('battery_level', 50) or 50)
                charge_limit = int(tdata.get('charge_limit_soc', 80) or 80)
                chg_state = str(tdata.get('charging_state', '')).lower()
                loc_name = str(tdata.get('location_name', '')).lower()
                
                # 1. Location check (Geofence or location string)
                is_home = False
                if any(k in loc_name for k in ['home', 'amaroo', 'katherine', 'parked at', 'parked']):
                    is_home = True
                t_lat = tdata.get('latitude')
                t_lon = tdata.get('longitude')
                h_lat = settings.get('latitude')
                h_lon = settings.get('longitude')
                if t_lat is not None and t_lon is not None and h_lat is not None and h_lon is not None:
                    d_lat = (float(t_lat) - float(h_lat)) * 111000.0
                    d_lon = (float(t_lon) - float(h_lon)) * 111000.0 * math.cos(math.radians(float(h_lat)))
                    dist_m = math.sqrt(d_lat * d_lat + d_lon * d_lon)
                    if dist_m < 800.0:
                        is_home = True
                        
                # 2. Plugged in check
                is_plugged = bool(chg_state and 'disconnected' not in chg_state and 'unknown' not in chg_state)
                
                # 3. Deficit calculation (Assume ~75 kWh usable battery for Model Y)
                cap_kwh = float(settings.get('tesla_battery_cap_kwh', 75.0))
                deficit_soc = max(0, charge_limit - soc_now)
                needed_kwh = (deficit_soc / 100.0) * cap_kwh
                
                if is_home and is_plugged and needed_kwh >= 2.0:
                    return True, True, True, soc_now, charge_limit, needed_kwh, car_name
    except Exception as e:
        print(f"Error checking Tesla live telemetry: {str(e)}")

    # Confirmed Fallback: User has confirmed Tesla is plugged in at home 00:00-12:00
    return True, True, True, 50, 80, fallback_need_kwh, "Tesla EV"


def generate_charging_plan_logic(db) -> dict:
    settings_doc = db.collection('settings').document('growatt').get()
    settings = settings_doc.to_dict() if settings_doc.exists else {}
    tariff = settings.get('tariff', {})
    tz_name = settings.get('timezone', 'Australia/Sydney')
    local_tz = ZoneInfo(tz_name)
    now_local = datetime.datetime.now(local_tz)

    # Battery parameters
    rated_kwh = 30.0
    inv_doc = db.collection('status').document('growatt_inverter_settings').get()
    if inv_doc.exists:
        raw = (inv_doc.to_dict() or {}).get('settings') or (inv_doc.to_dict() or {}).get('data', {})
        obj = raw.get('obj', raw) if isinstance(raw, dict) else {}
        try:
            rated_kwh = float(obj.get('batSysRateEnergy', 30.0) or 30.0)
        except Exception:
            pass
    max_charge_kw = float(settings.get('battery_max_charge_kw', 5.0))
    min_soc = float(settings.get('battery_min_soc_pct', 15.0))
    max_soc = float(settings.get('battery_max_soc_pct', 95.0))
    reserve_kwh = min_soc / 100.0 * rated_kwh

    # Current state
    soc_now = 50.0
    latest = db.collection('telemetry_history').order_by(
        'timestamp', direction=firestore.Query.DESCENDING).limit(1).get()
    if len(latest) > 0:
        soc_now = float(latest[0].to_dict().get('soc', 50))
    e_now = soc_now / 100.0 * rated_kwh

    # --- Housekeeping: delete expired AI Plan tasks ---
    # Resolution PRIORITY (in run_sync_logic) already guarantees expired AI tasks are
    # ignored — the weekly manual plan resumes by itself the day after an apply. This
    # block is pure hygiene: once the applied date has passed, remove the dead AI tasks
    # from settings so they don't clutter the schedule list.
    auto_reverted = False
    applied_for = settings.get('ai_plan_applied_for') or ''
    today_str = now_local.strftime("%Y-%m-%d")
    if applied_for and applied_for < today_str:
        tasks_list = settings.get('tasks', [])
        kept = [t for t in tasks_list if not str(t.get('name', '')).startswith('AI Plan')]
        if len(kept) != len(tasks_list) or applied_for:
            db.collection('settings').document('growatt').update({
                'tasks': kept,
                'ai_plan_applied_for': '',
            })
            auto_reverted = True
            print(f"AI Plan for {applied_for} expired — {len(tasks_list) - len(kept)} "
                  f"task(s) cleaned up; weekly manual plan resumes automatically.")

    predict_pv, model_used, has_forecast, predict_pv_p20, bias_scale = _build_pv_predictor(db, settings, tz_name)
    predict_load = _build_load_lookup(db, settings, tz_name)

    # Household-only daily load estimate (EV window excluded) — informational, shown in
    # the plan reasoning so daily forecasts can be sanity-checked at a glance.
    household_daily_kwh = 0.0

    # Key times: derive off-peak window dynamically from tariff rules so that
    # changing peak hours (e.g. 00-06 → 01-07) is reflected in the generated plan.
    # Probe 22:00 tonight through 12:00 tomorrow; find cheapest contiguous block.
    _probe_base = (now_local + datetime.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0) - datetime.timedelta(hours=2)
    _rates_probe = [(_probe_base + datetime.timedelta(hours=h), _import_rate_at(_probe_base + datetime.timedelta(hours=h), tariff)) for h in range(14)]
    offpeak_rate = min(r for _, r in _rates_probe)

    _in_blk, _blk_start_h, _blk_end_h = False, 0, 6
    for _pt, _pr in _rates_probe:
        if abs(_pr - offpeak_rate) < 1e-6:
            if not _in_blk:
                _in_blk = True
                _blk_start_h = _pt.hour
        else:
            if _in_blk:
                _blk_end_h = _pt.hour
                break
    else:
        if _in_blk:
            _blk_end_h = (_rates_probe[-1][0].hour + 1) % 24

    task_window_start = f"{_blk_start_h:02d}:00"
    task_window_end   = f"{_blk_end_h:02d}:00"
    _window_hours     = (_blk_end_h - _blk_start_h) % 24 or 6

    # next_midnight = start of the offpeak window (tonight or tomorrow)
    _base_midnight = (now_local + datetime.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    next_midnight = _base_midnight + datetime.timedelta(hours=_blk_start_h)
    if now_local.hour < _blk_end_h:  # running inside the window — plan for tonight
        next_midnight = now_local.replace(hour=_blk_start_h, minute=0, second=0, microsecond=0)
    six_am = next_midnight + datetime.timedelta(hours=_window_hours)
    print(f"Offpeak window: {task_window_start}–{task_window_end} rate={offpeak_rate:.4f} window={_window_hours}h")

    for h in range(24):
        household_daily_kwh += predict_load(next_midnight + datetime.timedelta(hours=h))

    # Horizon: ALWAYS simulate 06:00 -> next midnight. Truncating at the first cheap/free
    # window looks tempting but silently assumes that window can fully refill the battery —
    # it can't: the weekend free window is 2h, injecting at most ~9.5 kWh (5 kW x 2h x 0.95).
    # If Saturday evening needs more than "noon battery + 9.5 kWh + afternoon PV", a
    # 48-Hour Extended Horizon: simulate 06:00 -> 48h later (Tomorrow + Day After Tomorrow).
    # This ensures tomorrow's target SoC accounts for upcoming heavy rain or low solar on Day N+1.
    horizon_end = next_midnight + datetime.timedelta(hours=48)
    free_window_start = None

    pv_total, load_total = 0.0, 0.0
    pv_day1, load_day1 = 0.0, 0.0
    pv_day2, load_day2 = 0.0, 0.0

    day1_end = six_am + datetime.timedelta(hours=24)

    deltas = []      # hourly net battery-energy change (kWh), median PV forecast
    deltas_p20 = []  # same, under the pessimistic P20 PV quantile (survival floor)
    t = six_am
    while t < horizon_end:
        pv, load = predict_pv(t), predict_load(t)
        pv20 = predict_pv_p20(t)
        pv_total += pv
        load_total += load
        if t < day1_end:
            pv_day1 += pv
            load_day1 += load
        else:
            pv_day2 += pv
            load_day2 += load

        rate_t = _import_rate_at(t, tariff)
        inj = None
        if rate_t <= 1e-9:
            # FREE WINDOW. INVERTER & BMS HARDWARE CAP: battery charging is physically
            # capped at 5kW (max_charge_kw) — PV and grid import CANNOT double-charge
            # beyond it; net gain per free hour <= max_charge_kw * AC_CHARGE_EFF.
            # Only set free_window_start if the free window occurs on Day 1 (t < day1_end) —
            # Day 2 free windows belong to tomorrow's plan generation run.
            if free_window_start is None and t < day1_end:
                free_window_start = t
            inj = max_charge_kw * AC_CHARGE_EFF
        elif rate_t <= offpeak_rate + 1e-6:
            # NEXT-NIGHT OFF-PEAK RECHARGE: same cheap rate as tonight's window —
            # tomorrow's plan can recharge here at identical cost, so Day-2 deficits
            # must not inflate tonight's charge. Modeled as a rechargeable window.
            inj = max_charge_kw * AC_CHARGE_EFF

        def _adj(d):
            if inj is None:
                return d
            # surplus hour: injection capped at 5kW total; deficit hour: injection covers
            # load first, remainder charges the battery
            return min(inj, d + inj) if d > 0 else inj + d

        deltas.append(_adj(pv - load))
        deltas_p20.append(_adj(pv20 - load))
        t += datetime.timedelta(hours=1)

    # Exact required 06:00 energy via battery-clipped simulation (bisection). The battery
    # can only bank surplus up to (cap - current level), which depends on the starting
    # energy we're solving for — the old absolute surplus cap ignored that coupling.
    usable_cap_kwh = max_soc / 100.0 * rated_kwh
    required_kwh = _required_start_energy(deltas, reserve_kwh, usable_cap_kwh)
    worst_deficit = required_kwh - reserve_kwh  # kWh above reserve needed at 06:00
    # Survival requirement under the P20 (pessimistic) PV quantile — no margin added on
    # top: the quantile already encodes today's weather downside. Equals required_kwh
    # when no quantile model is deployed (predict_p20 falls back to the median).
    required_p20_kwh = _required_start_energy(deltas_p20, reserve_kwh, usable_cap_kwh)

    # --- SAFETY MARGIN: calibrated from measured forecast error when history allows ---
    # Margin size = newsvendor critical fractile of the historical forecast-error
    # distribution. Under-charging 1 kWh costs (peak - offpeak) — the daytime grid top-up;
    # over-charging 1 kWh costs (offpeak - export) — storable PV displaced to the export
    # meter. q = Cu / (Cu + Co), derived from the live tariff each night (~0.68 with
    # typical rates, NOT a blanket P90). Fallback (short history): PV/Load-ratio tiers.
    # User plan_soc_margin_pct wins over both.
    day_rates = [_rates_at(six_am + datetime.timedelta(hours=h), tariff) for h in range(18)]
    peak_rate = max(r[0] for r in day_rates)
    noon_export_rate = _rates_at(six_am + datetime.timedelta(hours=6), tariff)[1]
    cu = max(0.01, peak_rate - offpeak_rate)          # cost/kWh of charging too little
    co = max(0.01, offpeak_rate - noon_export_rate)   # cost/kWh of charging too much
    margin_quantile = max(0.5, min(0.95, cu / (cu + co)))
    calib_margin, calib_info = _calibrate_soc_margin(db, rated_kwh, quantile=margin_quantile)
    pv_load_ratio = pv_day1 / max(1.0, load_day1)
    if calib_margin is not None:
        if pv_day1 >= 15.0 or pv_load_ratio >= 0.45:
            # Solar-Rich Day (PV >= 15 kWh or PV/Load >= 0.45): contract safety margin to 10%-15%
            # so overnight charging leaves ample headroom for daytime solar absorption.
            default_seasonal_margin = max(10.0, min(15.0, calib_margin * 0.6))
            seasonal_note = (f"Solar Headroom Calibrated Mode (PV forecast {pv_day1:.1f} kWh, ratio {pv_load_ratio:.2f}): "
                             f"contracted safety margin from {calib_margin:.0f}% -> {default_seasonal_margin:.0f}% for solar headroom. [{calib_info}]")
        elif pv_day1 >= 10.0 or pv_load_ratio >= 0.3:
            # Moderate Solar Day: contract margin to 12%-18%
            default_seasonal_margin = max(12.0, min(18.0, calib_margin * 0.72))
            seasonal_note = (f"Moderate Solar Calibrated Mode (PV forecast {pv_day1:.1f} kWh): "
                             f"adjusted safety margin from {calib_margin:.0f}% -> {default_seasonal_margin:.0f}%. [{calib_info}]")
        else:
            # Low Solar / Heavy Deficit Day: retain full calibrated safety margin (e.g. 25%)
            default_seasonal_margin = calib_margin
            seasonal_note = (f"High Risk Calibrated Mode ({calib_info}); PV/Load ratio {pv_load_ratio:.2f} for reference.")
    elif pv_load_ratio < 0.6:
        # High deficit / low solar day -> higher safety buffer
        default_seasonal_margin = 20.0
        seasonal_note = (f"Risk Mode (PV/Load ratio {pv_load_ratio:.2f} < 0.6): expanded safety margin "
                         f"to 20% to buffer against solar deficit. [fallback: {calib_info}]")
    elif pv_load_ratio > 1.0:
        # Solar surplus day -> contracted safety buffer for solar headroom
        default_seasonal_margin = 10.0
        seasonal_note = (f"Headroom Mode (PV/Load ratio {pv_load_ratio:.2f} > 1.0): contracted safety margin "
                         f"to 10% for solar self-consumption headroom. [fallback: {calib_info}]")
    else:
        # Balanced day
        default_seasonal_margin = 15.0
        seasonal_note = (f"Balanced Mode (PV/Load ratio {pv_load_ratio:.2f}): 15% safety margin. "
                         f"[fallback: {calib_info}]")

    user_margin = settings.get('plan_soc_margin_pct')
    soc_margin = float(user_margin) if user_margin is not None else default_seasonal_margin

    # ── Battery Longevity: Healthy Daily SoC Cap ──
    # On non-calibration days, cap the overnight charge at a "health" ceiling (default 90%)
    # to avoid keeping the LFP cells at high voltage unnecessarily. This also preserves
    # ~10% solar headroom so surplus PV the next morning can still be stored rather than exported.
    # On calibration days (or when explicitly disabled), the cap is lifted to 100 so the
    # BMS can complete its full-voltage cell-balancing cycle.
    # Configurable via settings/growatt.battery_health_max_soc_pct (default 90).
    healthy_max_soc = float(settings.get('battery_health_max_soc_pct', 90.0))

    raw_target_soc = round((required_kwh / rated_kwh * 100.0) + soc_margin)
    # ── P20 Weather Floor ──
    # Weather-conditioned lower bound: survival under the pessimistic PV quantile, with
    # NO extra margin. On cloudy/uncertain days the P20-median gap is wide and this
    # dominates the global newsvendor margin; on stable sunny days P20 ≈ median and the
    # (small) global margin governs. Best of both: per-day uncertainty, no double count.
    p20_floor_soc = round(required_p20_kwh / rated_kwh * 100.0)
    quantile_note = None
    if p20_floor_soc > raw_target_soc:
        quantile_note = (
            f"P20 Weather Floor: pessimistic-quantile PV requires {required_p20_kwh:.1f} kWh at 06:00 "
            f"({p20_floor_soc}%) > median+margin target {raw_target_soc}% — quantile bound governs tonight.")
        raw_target_soc = p20_floor_soc
    # target_soc is initially bounded by the global inverter max_soc (hardware limit).
    # The health cap will be applied AFTER the calibration check below.
    target_soc = min(int(max_soc), max(int(min_soc), raw_target_soc))

    # ── Solar Headroom Clamp ──
    # The safety margin must not eat storable next-day PV surplus. Peak cumulative net
    # surplus M over Day-1 (from the same deltas: charge-rate capped, free-window aware):
    # a battery starting above (usable_cap - M) overflows and exports that surplus. Clamp
    # ONLY the margin portion — the floor is required + 5%, so survival is untouched and
    # calibration branches below may still raise the target. Cloudy day -> M ≈ 0 -> no-op.
    headroom_note = None
    cum_e, peak_cum = 0.0, 0.0
    for d in deltas[:min(len(deltas), 24)]:
        cum_e += d
        peak_cum = max(peak_cum, cum_e)
    if peak_cum > 0.5:
        floor_soc = max(int(min_soc), round(required_kwh / rated_kwh * 100.0) + 5, p20_floor_soc)
        headroom_soc = int((usable_cap_kwh - peak_cum) / rated_kwh * 100.0)
        clamped_soc = max(floor_soc, min(target_soc, headroom_soc))
        if clamped_soc < target_soc:
            headroom_note = (
                f"Solar Headroom Clamp: forecast Day-1 storable PV surplus peaks at {peak_cum:.1f} kWh — "
                f"overnight target lowered {target_soc}% -> {clamped_soc}% so tomorrow's surplus is stored "
                f"instead of exported (survival floor {floor_soc}% respected).")
            target_soc = clamped_soc

    # ── 7-Day BMS Calibration Tracker ──
    health_doc = db.collection('status').document('battery_health').get()
    days_since_cal = 999
    last_cal_date_str = ""
    if health_doc.exists:
        hdata = health_doc.to_dict() or {}
        last_cal_date_str = hdata.get('last_calibration_date') or ""
        if last_cal_date_str:
            try:
                last_cal_d = datetime.datetime.strptime(last_cal_date_str, "%Y-%m-%d").date()
                days_since_cal = (next_midnight.date() - last_cal_d).days
            except Exception:
                pass

    try:
        db.collection('status').document('battery_health').set({
            'days_since_last_calibration': days_since_cal,
            'last_calibration_date': last_cal_date_str,
            'calibration_due': (days_since_cal >= 7),
            'updated_at': firestore.SERVER_TIMESTAMP,
        }, merge=True)
    except Exception:
        pass

    # WEEKEND LFP BATTERY 100% SOC CALIBRATION & CELL BALANCING logic:
    # On weekends with a 2-hour free import window (12:00-14:00 at $0), the inverter's 5kW limit
    # means the free window can inject AT MOST 9.5 kWh (5 kW x 2h x 0.95).
    # To guarantee reaching 100% SoC (30 kWh) by 14:00 to balance LFP cells, the battery MUST be
    # pre-charged during the 00:00-06:00 off-peak window so it reaches 100% during the free window.
    calibration_due = (days_since_cal >= 7)
    lfp_cal_reason = None
    if calibration_due and free_window_start is None:
        # PV-ASSISTED WEEKDAY CALIBRATION: instead of unconditionally filling to 100% on
        # off-peak grid, charge overnight only to the level from which the PV forecast can
        # push the battery to 100% by mid-afternoon (deadline leaves a full-voltage dwell
        # before evening discharge) — the last, most expensive kWh come from free solar.
        # Falls back to the classic full overnight charge when: forecast missing, PV too
        # weak to finish the job (+margin lands >= 97% anyway), or calibration has already
        # slipped >= 2 days past due (a failed PV bet must not cascade into a third day).
        cal_margin_pct = float(settings.get('calibration_margin_pct', 5.0))
        deadline_hour = max(8, min(20, int(settings.get('calibration_pv_deadline_hour', 15))))
        cal_deadline = six_am.replace(hour=deadline_hour)
        e06_cal = _pv_assisted_cal_start(predict_pv, predict_load, six_am, cal_deadline,
                                         reserve_kwh, rated_kwh, max_charge_kw)
        pv_assist_soc = min(100, round(e06_cal / rated_kwh * 100.0) + int(cal_margin_pct))
        force_full_after = int(settings.get('calibration_force_full_after_days', 9))
        if pv_assist_soc >= 97 or not has_forecast or days_since_cal >= force_full_after:
            target_soc = 100
            lfp_cal_reason = (
                f"BMS Battery Health (7-Day Calibration Cycle): Last calibrated {days_since_cal} days ago "
                f"(date: {last_cal_date_str or 'Never'}, threshold >= 7 days). Boosting overnight target SoC to 100% "
                f"to guarantee mandatory weekly LFP cell balancing (completion threshold > 95%)."
                + (f" [PV-assist declined: forecast can't reliably finish 100% by "
                   f"{cal_deadline.strftime('%H:%M')}]" if has_forecast else " [no forecast snapshot]")
            )
        else:
            target_soc = max(target_soc, pv_assist_soc)
            saved_kwh = rated_kwh * (100 - target_soc) / 100.0
            lfp_cal_reason = (
                f"PV-Assisted BMS Calibration (7-Day cycle, last calibrated {days_since_cal} days ago): "
                f"overnight charge to {target_soc}% (incl. +{cal_margin_pct:.0f}% margin) is enough for forecast "
                f"PV surplus to push the battery to 100% by {cal_deadline.strftime('%H:%M')} for cell balancing — "
                f"saves ~{saved_kwh:.1f} kWh of off-peak grid charge; the top-up comes from free solar."
            )
    if free_window_start is not None:
        # Weekend 12:00-17:00 5-Hour Extended Full Charge & Calibration Window
        max_free_injection = 5.0 * max_charge_kw * AC_CHARGE_EFF  # Up to 23.75 kWh in 5 hours
        needed_at_start_of_free = max(0.0, rated_kwh - max_free_injection)

        # Calculate expected net morning drain between 06:00 and free_window_start
        morning_drain = 0.0
        t_m = six_am
        while t_m < free_window_start:
            morning_drain += (predict_load(t_m) - predict_pv(t_m))
            t_m += datetime.timedelta(hours=1)
        morning_drain = max(0.0, morning_drain)

        cal_margin_pct = float(settings.get('calibration_margin_pct', 5.0))
        needed_at_06am = needed_at_start_of_free + morning_drain
        lfp_required_soc = round(needed_at_06am / rated_kwh * 100.0) + int(soc_margin) + int(cal_margin_pct)
        lfp_target_soc = min(100, max(int(min_soc), lfp_required_soc))

        # Only override 06:00 target SoC for cell balancing if BMS calibration is actually due (>= 7 days).
        if calibration_due and lfp_target_soc > target_soc:
            target_soc = lfp_target_soc
            lfp_cal_reason = (
                f"Weekend LFP Battery 100% SoC Calibration & Top Balancing Window (12:00-17:00 Extended 5-Hour Window): "
                f"Guarantees battery reaches 100% SoC and sustains high-voltage cell-balancing absorption for 60+ minutes."
            )

    # ── Apply Health SoC Cap (non-calibration days only) ──
    # If BMS calibration is NOT due AND no calibration has been triggered above,
    # clamp target_soc to the healthy ceiling to protect battery longevity.
    # Calibration days (calibration_due=True OR lfp_cal_reason set) bypass this cap.
    health_mode_note = None
    if not calibration_due and lfp_cal_reason is None:
        if target_soc > healthy_max_soc:
            target_soc = int(healthy_max_soc)
            health_mode_note = (
                f"Battery Longevity Mode: No BMS calibration due ({days_since_cal} days since last calibration, "
                f"threshold 7 days). Daily health cap applied: target SoC limited to {healthy_max_soc:.0f}% "
                f"(vs global inverter limit {max_soc:.0f}%) to reduce high-voltage cell stress and preserve "
                f"~{rated_kwh * (max_soc - healthy_max_soc) / 100:.1f} kWh solar headroom for next-day self-consumption."
            )
        else:
            health_mode_note = (
                f"Battery Longevity Mode: No BMS calibration due ({days_since_cal} days since last calibration). "
                f"Computed target {target_soc}% is already within the {healthy_max_soc:.0f}% health cap — no adjustment needed."
            )
    elif calibration_due:
        health_mode_note = (
            f"Calibration Mode: BMS calibration due ({days_since_cal} days). "
            f"Health cap ({healthy_max_soc:.0f}%) bypassed — charging to {target_soc}% to complete LFP cell balancing."
        )

    # ── Fetch Overnight Minimum Forecast Temperature (00:00-07:00 AM) ──
    min_overnight_temp = 15.0  # default mild
    try:
        wf_doc = db.collection('status').document('weather_forecast').get()
        if not wf_doc.exists or not (wf_doc.to_dict() or {}).get('hours'):
            # fallback to latest in weather_forecast collection
            latest_docs = db.collection('weather_forecast').order_by('issued_at', direction=firestore.Query.DESCENDING).limit(1).get()
            if latest_docs:
                wf_doc = latest_docs[0]
                
        if wf_doc.exists:
            hours_data = (wf_doc.to_dict() or {}).get('hours', [])
            night_temps = []
            for h_entry in hours_data:
                h_time_raw = h_entry.get('time')
                if not h_time_raw:
                    continue
                
                h_dt = None
                if isinstance(h_time_raw, str):
                    try:
                        # Open-Meteo returns ISO string e.g. "2026-08-03T01:00"
                        naive_dt = datetime.datetime.fromisoformat(h_time_raw.replace('Z', ''))
                        h_dt = naive_dt.replace(tzinfo=ZoneInfo(tz_name))
                    except Exception:
                        pass
                elif isinstance(h_time_raw, datetime.datetime):
                    h_dt = h_time_raw if h_time_raw.tzinfo else h_time_raw.replace(tzinfo=ZoneInfo(tz_name))
                
                if h_dt and next_midnight <= h_dt <= (six_am + datetime.timedelta(hours=1)):
                    # Dry-bulb ambient air temperature (inverter/battery enclosure is not subject to wind chill)
                    t_actual = h_entry.get('temperature_c') if h_entry.get('temperature_c') is not None else h_entry.get('tempC')
                    if t_actual is not None:
                        night_temps.append(float(t_actual))
            if night_temps:
                avg_overnight_temp = sum(night_temps) / len(night_temps)
                min_overnight_temp = min(night_temps)
                print(f"Overnight forecast temperature (00:00-07:00 AM): Avg={avg_overnight_temp:.1f}°C, Min={min_overnight_temp:.1f}°C (samples={len(night_temps)})")
    except Exception as e_temp:
        print(f"Error checking overnight forecast temp: {str(e_temp)}")

    # ── Apply Winter Cold Battery Protection (Avg < 2.0°C or Hard Freeze Min < 0.0°C) ──
    # Large 30 kWh battery packs have significant thermal mass (150kg+); a brief 1-hour dip does not
    # cool the core cells. Protection is triggered if overnight average < 2.0°C or hard freeze < 0.0°C.
    is_cold_overnight = (avg_overnight_temp < 2.0 or min_overnight_temp < 0.0)
    cold_protect_note = None
    if is_cold_overnight:
        # Boost target SoC to at least 80% to ensure high open-circuit voltage buffer (52.5V+)
        if not calibration_due and target_soc < 80:
            target_soc = 80
        
        cold_protect_note = (
            f"Winter Cold Battery Protection Active (Overnight Avg {avg_overnight_temp:.1f}°C < 2.0°C or Min {min_overnight_temp:.1f}°C < 0.0°C): "
            f"1) Target SoC boosted to at least {target_soc}% (high OCV buffer > 52.5V); "
            f"2) Full 00:00-06:00 AM continuous slow warm charging active for whole-night cell thermal protection; "
            f"3) Hysteresis discharge power limit active (50% max under 2°C, restores 100% when temp > 5°C)."
        )

    # Battery energy expected at midnight (evening drain from now, PV ~ 0)
    e_mid = e_now
    t = now_local.replace(minute=0, second=0, microsecond=0)
    while t < next_midnight:
        e_mid = max(reserve_kwh, min(rated_kwh, e_mid + predict_pv(t) - predict_load(t)))
        t += datetime.timedelta(hours=1)

    # Resolve energy at the start of the charging window (or current moment if running inside window)
    _inside_window = (_blk_start_h <= now_local.hour < _blk_end_h) if _blk_start_h < _blk_end_h else (now_local.hour >= _blk_start_h or now_local.hour < _blk_end_h)
    if _inside_window:
        start_energy = e_now
    else:
        start_energy = e_mid

    # ── Continuous MPC Dynamic EV Solar Sponge & Unified Survival Floor ──
    # Minimum safe energy at 06:00 to guarantee zero daytime grid import across all 4 seasons:
    # Uses the P20 pessimistic weather quantile trajectory (required_p20_kwh) from the MPC integrator:
    # - Winter (low solar, high load): required_p20_kwh naturally rises to 20-25 kWh (70-85% SoC),
    #   automatically preventing over-discharge and scheduling off-peak recharge.
    # - Summer (high solar, early sunrise): required_p20_kwh drops to 3-4 kWh (10-15% SoC),
    #   maximizing clean energy transfer to EV and solar sponge absorption.
    # - Spring/Autumn (moderate): required_p20_kwh lands on the exact morning deficit (~18-20% SoC).
    e06_safe_house = max(reserve_kwh, required_p20_kwh)
    soc06_safe_house = max(int(min_soc), int(round(e06_safe_house / rated_kwh * 100.0)))

    # Evaluate Tesla EV Readiness (location, plugged-in status, charging deficit)
    ev_avail, ev_home, ev_plugged, ev_soc, ev_limit, ev_need_kwh, ev_name = _check_tesla_readiness(db, settings)

    t_doc = db.collection('settings').document('tesla').get()
    t_cfg = t_doc.to_dict() if t_doc.exists else {}
    sponge_continue_charge = bool(settings.get('sponge_continue_charge', t_cfg.get('sponge_continue_charge', False)))

    ev_sponge_active = False
    ev_transfer_kwh = 0.0
    ev_sponge_note = None

    # Continuous Energy Balance:
    # If not cold, not calibration, and Tesla is plugged in at home with charging deficit:
    # calculate true safe surplus above the household survival floor.
    if not is_cold_overnight and not calibration_due and ev_avail:
        safe_surplus_kwh = max(0.0, start_energy - e06_safe_house)
        transfer_kwh = min(safe_surplus_kwh, ev_need_kwh)
        if transfer_kwh >= 0.5:
            ev_sponge_active = True
            ev_transfer_kwh = round(transfer_kwh, 2)
            # Dynamically lower target SoC to release battery energy to EV
            target_soc = max(int(min_soc), int(round((start_energy - ev_transfer_kwh) / rated_kwh * 100.0)))
            sponge_created_kwh = rated_kwh * (healthy_max_soc - target_soc) / 100.0
            ev_sponge_note = (
                f"Spring EV Solar Sponge Active: {ev_name} is plugged in at home ({ev_soc}% -> {ev_limit}%, needs ~{ev_need_kwh:.1f} kWh). "
                f"Dynamically releasing ~{ev_transfer_kwh:.1f} kWh from home battery overnight to lower {task_window_end} SoC to {target_soc}%. "
                f"Inverter operates in Load First mode (priorityChoose=0, 0% AC grid charging), unlocking battery discharge to feed Tesla EV "
                f"and creating ~{sponge_created_kwh:.1f} kWh of empty battery sponge for 100% absorption of tomorrow's {pv_day1:.1f} kWh solar surplus "
                f"(safe house floor {soc06_safe_house}% respected)."
            )

    # ── LLM Strategy Advisor & Explainer (Gemini 2.5 Flash) ──
    # Objective:
    # 1. Strategy Explainer (A): Generate 2-sentence articulate Chinese executive summary ('ai_briefing').
    # 2. Strategy Advisor (B): Review MPC baseline target SoC and fine-tune by [-10%, +10%] within safe envelope.
    # Hard Guardrail: BMS calibration days are strictly locked (0 delta).
    mpc_target_soc = int(target_soc)
    gemini_key = settings.get('gemini_api_key', '')
    ev_desc = f"{ev_name}: {ev_soc}% -> {ev_limit}% (needs {ev_need_kwh:.1f} kWh)" if ev_avail else "Not available / Not home"
    if ev_sponge_active:
        ev_desc += f", EV Sponge ACTIVE (releasing ~{ev_transfer_kwh:.1f} kWh)"

    is_cal_active = bool(calibration_due or lfp_cal_reason is not None)
    min_allow = target_soc if is_cal_active else soc06_safe_house
    max_allow = 100 if is_cal_active else int(healthy_max_soc)

    llm_context = {
        "for_date": six_am.strftime("%Y-%m-%d"),
        "day_name": six_am.strftime("%A"),
        "mpc_target_soc": mpc_target_soc,
        "min_allowed_soc": min_allow,
        "max_allowed_soc": max_allow,
        "is_calibration_due": is_cal_active,
        "days_since_cal": days_since_cal,
        "battery_rated_kwh": rated_kwh,
        "soc_now": soc_now,
        "pv_forecast_kwh": round(pv_day1, 1),
        "load_forecast_kwh": round(load_day1, 1),
        "pv_load_ratio": round(pv_load_ratio, 2),
        "min_overnight_temp": round(min_overnight_temp, 1),
        "is_cold_overnight": is_cold_overnight,
        "offpeak_rate": offpeak_rate,
        "peak_rate": peak_rate,
        "export_rate": noon_export_rate,
        "ev_status_desc": ev_desc
    }
    llm_plan_eval = evaluate_charging_plan_llm(llm_context, gemini_key)
    target_soc = llm_plan_eval["final_target_soc"]

    # If EV sponge is active and target_soc was tuned, adjust transfer amount accordingly
    if ev_sponge_active:
        ev_transfer_kwh = round(max(0.0, start_energy - (target_soc / 100.0 * rated_kwh)), 2)

    start_soc = round(start_energy / rated_kwh * 100.0, 1)
    if not ev_sponge_active and (target_soc > start_soc + 1.0):
        net_charge_kwh = max(0.0, (target_soc / 100.0 * rated_kwh) - start_energy)
    else:
        net_charge_kwh = 0.0

    charge_kwh = net_charge_kwh
    est_cost = round(charge_kwh / AC_CHARGE_EFF * offpeak_rate, 2)

    day_abbrev = six_am.strftime("%a")
    reasoning = []

    ai_briefing = llm_plan_eval.get("ai_briefing", "").strip()
    if ai_briefing:
        reasoning.append(f"🤖 AI 能量管家简报: {ai_briefing}")

    if llm_plan_eval.get("adjustment_delta_soc", 0) != 0:
        d_val = llm_plan_eval["adjustment_delta_soc"]
        d_str = f"+{d_val}%" if d_val > 0 else f"{d_val}%"
        reasoning.append(
            f"🤖 AI 专家微调 ({llm_plan_eval['source']}): 基础 MPC 目标 {mpc_target_soc}% -> 微调至 {target_soc}% ({d_str})。原因: {llm_plan_eval.get('adjustment_reason', '')}"
        )

    if auto_reverted:
        reasoning.append(
            f"AI Plan for {applied_for} expired — resumed weekly manual schedule.")

    reasoning += [
        f"Forecast: Tomorrow PV {pv_day1:.1f} kWh | Load {load_day1:.1f} kWh.",
        f"Strategy: {seasonal_note}",
    ]
    if cold_protect_note:
        reasoning.append(cold_protect_note)
    if quantile_note:
        reasoning.append(quantile_note)
    if headroom_note and not ev_sponge_active:
        reasoning.append(headroom_note)
    if lfp_cal_reason:
        reasoning.append(lfp_cal_reason)
    if ev_sponge_note:
        if sponge_continue_charge:
            ev_sponge_note += f" Extended off-peak charging active: once battery reaches {target_soc}% floor, Battery First will lock battery reserve and Tesla will continue charging on cheap off-peak grid until {task_window_end}."
        reasoning.append(ev_sponge_note)

    # ── Task Generation (dynamic off-peak window from tariff) ──
    # 1. EV Sponge or Solar Headroom Discharge: Inverter operates in Load First mode (priorityChoose=0)
    # with charge stop SoC = target_soc floor. When SoC drops to floor, Battery First takes over at 100% power.
    if ev_sponge_active or (charge_kwh <= 0.3 and target_soc < start_soc):
        task_soc = int(target_soc)
        task_power = 100
        released_kwh = max(0.0, start_energy - (target_soc / 100.0 * rated_kwh))
        sponge_kwh = rated_kwh * (healthy_max_soc - target_soc) / 100.0
        task_name = f"AI Plan: EV Solar Sponge ({day_abbrev})" if ev_sponge_active else f"AI Plan: Load First Sponge ({day_abbrev})"
        if not ev_sponge_active:
            reasoning.append(
                f"Overnight Load-Priority Sponge ({task_window_start}-{task_window_end}): Inverter set to pure Load First (priorityChoose=0) with 0% AC grid charging. "
                f"Battery is unlocked to discharge naturally to Tesla EV & home load down to floor {target_soc}%, releasing ~{released_kwh:.1f} kWh "
                f"and creating ~{sponge_kwh:.1f} kWh solar sponge headroom for tomorrow's {pv_day1:.1f} kWh solar surplus."
            )
    # 2. Active Grid Charging: Inverter charges battery from grid up to target_soc
    elif charge_kwh > 0.3:
        req_power_kw = (charge_kwh / AC_CHARGE_EFF) / float(_window_hours)
        calc_power_pct = round((req_power_kw / max_charge_kw) * 100.0)
        charge_power_pct = max(10, min(100, calc_power_pct))
        actual_power_kw = (charge_power_pct / 100.0) * max_charge_kw
        task_soc = int(target_soc)
        task_power = int(charge_power_pct)
        task_name = f"AI Plan: Off-peak warm charge ({day_abbrev})"
        reasoning.append(
            f"Overnight Full-Window Charge ({task_window_start}-{task_window_end}): charging continuously at {charge_power_pct}% power (~{actual_power_kw:.2f} kW) "
            f"covering the full {_window_hours:.0f}-hour off-peak window (Target {target_soc:.0f}% SoC, Est. cost ${est_cost:.2f})."
        )
    # 3. Standby Solar Priority
    else:
        task_soc = int(target_soc)
        task_power = 0
        task_name = f"AI Plan: Standby Solar Priority ({day_abbrev})"
        reasoning.append(
            f"Overnight Plan ({task_window_start}-{task_window_end}): available energy ({start_energy / rated_kwh * 100:.0f}%) meets target {target_soc:.0f}% — no grid charge needed. Inverter in Load First mode to discharge naturally for overnight load."
        )

    suggested_tasks = [{
        "name": task_name,
        "days": [day_abbrev],
        "start_time": task_window_start,
        "end_time": task_window_end,
        "power": str(task_power),
        "soc": str(task_soc),
    }]

    # Free-window plan (weekend 12:00-14:00 at $0)
    if free_window_start is not None:
        e_06_target = target_soc / 100.0 * rated_kwh
        e_12 = min(e_06_target, e_mid + 6.0 * max_charge_kw * AC_CHARGE_EFF)
        if e_12 < e_06_target - 0.05:
            reasoning.append(
                f"Overnight charge is rate-limited: 06:00 level ~{e_12 / rated_kwh * 100:.0f}% "
                f"(vs target {target_soc:.0f}%) — free-window top-up sized from the achievable level.")
        t = six_am
        while t < free_window_start:
            e_12 = max(reserve_kwh, min(rated_kwh, e_12 + predict_pv(t) - predict_load(t)))
            t += datetime.timedelta(hours=1)
        free_kwh = max(0.0, min(rated_kwh - e_12, 2 * max_charge_kw * AC_CHARGE_EFF))
        if free_kwh > 0.3:
            suggested_tasks.append({
                "name": f"FREE window top-up ({free_window_start.strftime('%a')})",
                "days": [free_window_start.strftime("%a")],
                "start_time": free_window_start.strftime("%H:%M"),
                "end_time": (free_window_start + datetime.timedelta(hours=2)).strftime("%H:%M"),
                "power": "100",
                "soc": "100",
            })
            reasoning.append(
                f"Free import window {free_window_start.strftime('%a %H:%M')}: top up ~{free_kwh:.1f} kWh at $0 "
                f"to 100% (doubles as the weekly LFP balancing charge; daily {max_soc:.0f}% cap waived here).")

    # --- Whole-day bill estimate (00:00 -> 24:00 of the plan day) ---
    ev_daily_kwh = float(settings.get('ev_daily_kwh', 24.0))
    ev_charge_kw = float(settings.get('ev_charge_kw', 7.0))
    ev_start_h = int(settings.get('ev_charge_start_hour', 0))
    ev_end_h = int(settings.get('ev_charge_end_hour', 6))
    
    # If EV sponge is active, the portion transferred from battery reduces grid import demand
    ev_drawn_from_batt = min(ev_transfer_kwh, max_charge_kw * AC_CHARGE_EFF * 6.0) if ev_sponge_active else 0.0
    ev_remaining = max(0.0, ev_daily_kwh - ev_drawn_from_batt)
    
    supply_charge = float(tariff.get('dailySupplyCharge', 0.95))
    day_import_kwh, day_export_kwh = 0.0, 0.0
    import_cost, export_credit = 0.0, 0.0
    
    # Battery state tracking
    e_batt = max(reserve_kwh, e_mid - ev_drawn_from_batt) if ev_sponge_active else e_mid
    charge_remaining = charge_kwh
    max_soc_kwh = rated_kwh if calibration_due else max_soc / 100.0 * rated_kwh
    
    t = next_midnight
    while t < next_midnight + datetime.timedelta(hours=24):
        imp_rate, exp_rate = _rates_at(t, tariff)
        pv, load = predict_pv(t), predict_load(t)
        hour_import, hour_export = 0.0, 0.0
        
        # EV draw from grid
        ev_draw = min(ev_charge_kw, ev_remaining) if _in_ev_window(t.hour, ev_start_h, ev_end_h) else 0.0
        ev_remaining -= ev_draw
        
        if t.hour < 6:
            if ev_sponge_active:
                # Discharging to EV & house load via Load First mode (100% free stored PV solar).
                # Auto-stop EV charging cuts off Tesla when target floor is reached,
                # and the remaining battery reserve powers the house (fridge/router) until sunrise.
                hour_import = 0.0
            else:
                chg = min(charge_remaining, max_charge_kw * AC_CHARGE_EFF)
                e_batt = min(rated_kwh, e_batt + chg)
                charge_remaining -= chg
                hour_import = load + ev_draw + chg / AC_CHARGE_EFF
        else:
            net = pv - load
            if net >= 0:
                stored = min(net, max(0.0, max_soc_kwh - e_batt), max_charge_kw)
                e_batt += stored
                hour_export = net - stored
            else:
                discharge = min(-net, max(0.0, e_batt - reserve_kwh), max_charge_kw)
                e_batt -= discharge
                hour_import = -net - discharge
            hour_import += ev_draw
            if imp_rate <= 1e-9:
                topup = min(rated_kwh - e_batt, max_charge_kw * AC_CHARGE_EFF)
                e_batt += topup
                hour_import += topup / AC_CHARGE_EFF
                
        day_import_kwh += hour_import
        day_export_kwh += hour_export
        import_cost += hour_import * imp_rate
        export_credit += hour_export * exp_rate
        t += datetime.timedelta(hours=1)

    est_day_cost = round(import_cost - export_credit + supply_charge, 2)
    reasoning.append(
        f"Estimated day bill: import {day_import_kwh:.1f} kWh (incl. EV ~{ev_daily_kwh:.0f}) "
        f"${import_cost:.2f} - export {day_export_kwh:.1f} kWh ${export_credit:.2f} "
        f"+ supply ${supply_charge:.2f} -> ~${est_day_cost:.2f}.")

    # ── Load-Shift Opportunity (surplus notification) ──
    surplus_window = None
    e_sim = target_soc / 100.0 * rated_kwh
    spill_total, spill_start, spill_end = 0.0, None, None
    for i, d in enumerate(deltas[:24]):
        e_sim += d
        if e_sim > usable_cap_kwh:
            spill_total += e_sim - usable_cap_kwh
            e_sim = usable_cap_kwh
            t_h = six_am + datetime.timedelta(hours=i)
            if spill_start is None:
                spill_start = t_h
            spill_end = t_h + datetime.timedelta(hours=1)
        elif e_sim < reserve_kwh:
            e_sim = reserve_kwh
    if spill_total > 1.0 and spill_start is not None:
        surplus_window = {
            "start": spill_start.strftime("%H:%M"),
            "end": spill_end.strftime("%H:%M"),
            "exportable_kwh": round(spill_total, 1),
        }
        reasoning.append(
            f"Load-shift opportunity: ~{spill_total:.1f} kWh will overflow the battery "
            f"{surplus_window['start']}-{surplus_window['end']} and be exported — running "
            f"dishwasher/dryer/hot water in that window uses it at full value instead of "
            f"the export credit.")

    plan = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc),
        "for_date": six_am.strftime("%Y-%m-%d"),
        "timezone": tz_name,
        "soc_now": soc_now,
        "battery_rated_kwh": rated_kwh,
        "target_soc": int(target_soc),
        "soc_margin_pct": round(float(soc_margin), 1),
        "soc_margin_source": ("user" if user_margin is not None else
                              ("calibrated_p90" if calib_margin is not None else "ratio_tier")),
        "charge_kwh": round(charge_kwh, 2),
        "est_cost": est_cost,
        "est_day_cost": est_day_cost,
        "est_day_import_kwh": round(day_import_kwh, 2),
        "est_day_export_kwh": round(day_export_kwh, 2),
        "offpeak_rate": offpeak_rate,
        "pv_forecast_kwh": round(pv_day1, 2),
        "pv_forecast_raw_kwh": round(pv_day1 / bias_scale, 2),
        "pv_bias_factor": round(bias_scale, 3),
        "load_forecast_kwh": round(load_day1, 2),
        "pv_forecast_48h_kwh": round(pv_total, 2),
        "load_forecast_48h_kwh": round(load_total, 2),
        "household_daily_kwh": round(household_daily_kwh, 2),
        "ev_sponge_active": ev_sponge_active,
        "ev_transfer_kwh": ev_transfer_kwh,
        "tesla_continue_charge": sponge_continue_charge,
        "sponge_floor_locked": False,
        "tesla_is_home": ev_home,
        "tesla_is_plugged": ev_plugged,
        "tesla_soc_now": ev_soc,
        "tesla_charge_limit": ev_limit,
        "surplus_window": surplus_window,
        "model_used": model_used,
        "suggested_tasks": suggested_tasks,
        "reasoning": reasoning,
        "ai_briefing": ai_briefing,
        "llm_plan_source": llm_plan_eval.get("source", "mpc_rule_engine"),
        "llm_target_delta": llm_plan_eval.get("adjustment_delta_soc", 0),
        "llm_adjustment_reason": llm_plan_eval.get("adjustment_reason", ""),
        "mode": "advisory",
    }
    db.collection('status').document('charging_plan').set(plan)

    # Archive every generated plan by date (latest generation for a date wins; the app
    # merges an `applied` flag in when the user applies it). Evaluation dataset: predicted
    # PV/load/cost per day vs daily_bills actuals, split by applied vs not — exactly what's
    # needed to quantify model quality and the strategy's real savings later.
    db.collection('charging_plan_history').document(plan['for_date']).set(plan, merge=True)

    print(f"Charging plan for {plan['for_date']}: target SoC {plan['target_soc']}%, "
          f"charge {plan['charge_kwh']} kWh (${plan['est_cost']}). Tasks: {len(suggested_tasks)}")
    return plan


def _auto_apply_plan(db, plan) -> bool:
    """AUTO mode (settings.ai_auto_apply == True): writes the freshly generated nightly
    plan into settings.tasks as the one-shot AI override for plan['for_date'], exactly as
    a manual Apply in the app would. Only ever called from the SCHEDULED runs (23:30
    nightly generation + 04:45 dawn correction) — the manual refresh stays advisory. Safety gates upstream: no fresh forecast -> generation
    skipped -> nothing to apply -> weekly plan runs."""
    settings_doc = db.collection('settings').document('growatt').get()
    settings = settings_doc.to_dict() if settings_doc.exists else {}
    if not settings.get('ai_auto_apply', False):
        return False
    suggested = plan.get('suggested_tasks') or []
    if not suggested:
        print("AUTO-APPLY: plan has no suggested tasks — weekly schedule stands.")
        return False

    tasks = [t for t in settings.get('tasks', []) if not str(t.get('name', '')).startswith('AI Plan')]
    for st in suggested:
        tasks.append({
            'id': f"aiplan-{plan['for_date']}-{st['start_time'].replace(':', '')}",
            'name': 'AI Plan: ' + st.get('name', 'Auto'),
            'days': st.get('days', []),
            'start_time': st.get('start_time', '00:00'),
            'end_time': st.get('end_time', '06:00'),
            'power': st.get('power', '100'),
            'soc': st.get('soc', '100'),
            'enabled': True,
        })
    db.collection('settings').document('growatt').update({
        'tasks': tasks,
        'ai_plan_applied_for': plan['for_date'],
    })
    db.collection('charging_plan_history').document(plan['for_date']).set({
        'applied': True,
        'applied_at': datetime.datetime.now(datetime.timezone.utc),
        'applied_by': 'auto',
        'applied_target_soc': plan.get('target_soc'),
        'applied_charge_kwh': plan.get('charge_kwh'),
        'applied_est_day_cost': plan.get('est_day_cost'),
        'applied_windows': [f"{s.get('start_time')}-{s.get('end_time')}→{s.get('soc')}%" for s in suggested],
    }, merge=True)
    print(f"AUTO-APPLY: AI plan for {plan['for_date']} written to schedule "
          f"(target {plan.get('target_soc')}%, {len(suggested)} window(s)).")
    return True


@scheduler_fn.on_schedule(
    schedule="30 23 * * *",
    timezone=scheduler_fn.Timezone("Australia/Sydney"),
    region="australia-southeast1"
)
def generate_charging_plan(event: scheduler_fn.ScheduledEvent) -> None:
    """Runs nightly at 23:30, 15 min ahead of the 23:45 pre-task sync push.

    Resilience strategy (two tiers):
    1. RETRY: fetch_weather_forecast_logic already retries 3× with 5s/10s backoff.
    2. CACHE FALLBACK: if all 3 fetches fail, fall back to the most recent cached
       weather snapshot (status/weather_forecast or latest weather_forecast doc).
       A 1-2h old forecast is far better than silently skipping tonight's plan and
       leaving the inverter on a week-old manual schedule.
    If the cache is also missing (first-ever run), skip and log."""
    print("Charging plan generation triggered.")
    try:
        db = firestore.client()
        forecast_fresh = fetch_weather_forecast_logic(db)
        if not forecast_fresh:
            # Tier 2: check how old the cached forecast is
            cached_doc = db.collection('status').document('weather_forecast').get()
            if cached_doc.exists:
                cached = cached_doc.to_dict() or {}
                cached_issued = cached.get('issued_at')
                age_h = 99.0
                if cached_issued:
                    import datetime as _dt
                    age_h = (_dt.datetime.now(_dt.timezone.utc) - cached_issued).total_seconds() / 3600.0
                if age_h <= 6.0:
                    print(f"Weather fetch failed after 3 retries — falling back to cached forecast "
                          f"({age_h:.1f}h old) to continue plan generation.")
                else:
                    print(f"Weather fetch failed and cache is {age_h:.1f}h old (> 6h) — "
                          f"skipping AI plan generation; weekly schedule stands as-is.")
                    return
            else:
                print("Weather fetch failed and no cached forecast found — "
                      "skipping AI plan generation; weekly schedule stands as-is.")
                return
        plan = generate_charging_plan_logic(db)
        _auto_apply_plan(db, plan)  # no-op unless settings.ai_auto_apply is enabled
    except Exception as e:
        print(f"Error: Failed to generate charging plan: {str(e)}")


# Dawn correction function removed: full-night continuous slow warm charging (00:00-06:00)
# renders mid-night 04:00 AM plan recalculation unnecessary and prevents mid-charge EEPROM writes.


@https_fn.on_call(region="australia-southeast1")
def trigger_generate_charging_plan(req: https_fn.CallableRequest) -> dict:
    """Manual regeneration from the iOS app: refresh the weather forecast FIRST, then run
    inference — a manual tap means the user wants the freshest possible answer."""
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="The function must be called by an authenticated user."
        )
    db = firestore.client()
    if not fetch_weather_forecast_logic(db):
        print("Warning: forecast refresh failed — planning with the latest stored snapshot.")
    plan = generate_charging_plan_logic(db)
    _auto_apply_plan(db, plan)
    try:
        # BUG FIX: run_sync_logic takes (trigger_type, mode) — the old `db` positional arg
        # raised TypeError which the except below swallowed, so this sync never ran.
        run_sync_logic(trigger_type="manual_trigger", mode="sync")
    except Exception as e_sync:
        print(f"Warning: Failed to sync schedule immediately after manual plan generation: {str(e_sync)}")
    plan.pop('generated_at', None)  # not JSON-serializable in callable response
    return {"status": "success", "plan": plan}


@https_fn.on_request(region="australia-southeast1")
def trigger_backfill_modeled_soc(req: https_fn.Request) -> https_fn.Response:
    """Backfills modeled_soc into telemetry_history for past 36 hours using Firestore Batch."""
    db = firestore.client()
    try:
        now_utc = datetime.datetime.now(datetime.timezone.utc)
        since_utc = now_utc - datetime.timedelta(hours=36)
        docs = db.collection('telemetry_history').where('timestamp', '>=', since_utc).order_by('timestamp', direction=firestore.Query.ASCENDING).get()
        
        count = 0
        prev_modeled = None
        batch = db.batch()
        batch_count = 0

        for doc in docs:
            data = doc.to_dict()
            soc_raw = data.get('soc', 50)
            v_pack = data.get('battery_voltage', 52.0)
            chg_kw = data.get('charge_power_kw', 0.0)
            dis_kw = data.get('discharge_power_kw', 0.0)
            
            modeled = compute_physics_modeled_soc(
                raw_bms_soc=soc_raw,
                pack_voltage=v_pack,
                charge_kw=chg_kw,
                discharge_kw=dis_kw,
                prev_modeled_soc=prev_modeled
            )
            prev_modeled = modeled
            batch.update(doc.reference, {'modeled_soc': modeled})
            count += 1
            batch_count += 1

            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0
                
        if batch_count > 0:
            batch.commit()
            
        return https_fn.Response(f"Successfully backfilled modeled_soc for {count} telemetry entries using batch writes.")
    except Exception as e:
        return https_fn.Response(f"Backfill error: {str(e)}", status=500)


def retrain_pv_model_logic(db, lookback_days=90) -> dict:
    """
    Scikit-Learn Bayesian Cloud Retraining Engine:
    Fetches past N days (default 90 days) of telemetry & weather forecast snapshots from Firestore.
    Fits Bayesian Ridge Regression with non-linear low-light features for robust, uncertainty-aware solar predictions.
    Outputs posterior mean, variance/precision parameters, and uncertainty bounds.
    """
    import math
    import numpy as np
    from sklearn.linear_model import BayesianRidge

    now_utc = datetime.datetime.now(datetime.timezone.utc)
    since_utc = now_utc - datetime.timedelta(days=lookback_days)

    # 1. Fetch telemetry history for available training window (up to 90 days max)
    telemetry_docs = db.collection('telemetry_history').where('timestamp', '>=', since_utc).order_by('timestamp', direction=firestore.Query.ASCENDING).get()
    
    if len(telemetry_docs) < 100:
        msg = f"Insufficient telemetry samples for retraining ({len(telemetry_docs)} < 100). Skipping."
        print(msg)
        return {'status': 'skipped', 'message': msg}

    earliest_ts = telemetry_docs[0].to_dict().get('timestamp')
    latest_ts = telemetry_docs[-1].to_dict().get('timestamp')
    days_span = max(1, (latest_ts - earliest_ts).days) if (earliest_ts and latest_ts) else 1

    # 2. Build feature matrix with non-linear low-light terms (sqrt_gti) for overcast days
    X_pv, y_pv = [], []
    for doc in telemetry_docs:
        d = doc.to_dict()
        ts = d.get('timestamp')
        solar_kw = d.get('solar_generation_kw')
        gti = d.get('global_tilted_irradiance_wm2')
        if ts is None or solar_kw is None or gti is None:
            continue

        lt = ts.astimezone(ZoneInfo('Australia/Sydney'))
        hour = lt.hour + lt.minute / 60.0
        doy = float(lt.timetuple().tm_yday)

        sun_height = max(0.0, math.sin(math.pi * max(0.0, hour - 6.0) / 12.0))
        hour_sin = math.sin(2 * math.pi * hour / 24.0)
        hour_cos = math.cos(2 * math.pi * hour / 24.0)
        hour_sin2 = math.sin(4 * math.pi * hour / 24.0)
        hour_cos2 = math.cos(4 * math.pi * hour / 24.0)
        doy_sin = math.sin(2 * math.pi * doy / 365.25)
        doy_cos = math.cos(2 * math.pi * doy / 365.25)

        gti_val = float(gti)
        if gti_val > 10.0 and sun_height > 0.01:
            sqrt_gti = math.sqrt(gti_val)
            gti_x_sun = gti_val * sun_height
            sqrt_gti_x_sun = sqrt_gti * sun_height
            cld_val = max(0.0, min(100.0, float(d.get('cloud_cover_pct') or 0.0))) / 100.0
            prcp_val = max(0.0, float(d.get('precipitation_mm') or 0.0))
            sqrt_prcp = math.sqrt(prcp_val)
            cld_x_gti = cld_val * gti_val
            gti_x_hsin = gti_val * hour_sin
            gti_x_hcos = gti_val * hour_cos
            gti_x_hsin2 = gti_val * hour_sin2
            gti_x_hcos2 = gti_val * hour_cos2
            
            feat_vec = [
                gti_val, sqrt_gti, sun_height, gti_x_sun, sqrt_gti_x_sun,
                cld_val, cld_x_gti, sqrt_prcp,
                hour_sin, hour_cos, hour_sin2, hour_cos2,
                doy_sin, doy_cos, gti_x_hsin, gti_x_hcos, gti_x_hsin2, gti_x_hcos2
            ]
            X_pv.append(feat_vec)
            y_pv.append(float(solar_kw))

    if len(X_pv) < 50:
        msg = f"Insufficient daytime rows for PV model training ({len(X_pv)} < 50). Skipping."
        print(msg)
        return {'status': 'skipped', 'message': msg}

    X_pv_arr = np.array(X_pv)
    y_pv_arr = np.array(y_pv)

    # 3. Fit Bayesian Ridge Regression Model
    bayes_ridge = BayesianRidge(compute_score=True, max_iter=500)
    bayes_ridge.fit(X_pv_arr, y_pv_arr)
    
    # Calculate MAE & Uncertainty
    preds, std_preds = bayes_ridge.predict(X_pv_arr, return_std=True)
    preds = np.maximum(0, preds)
    mae_bayes = float(np.mean(np.abs(preds - y_pv_arr)))
    mean_uncertainty = float(np.mean(std_preds))

    # Baseline MAE
    baseline_preds = np.array([max(0.0, 6.6 * (feat[0] / 1000.0) * 0.65) for feat in X_pv])
    mae_baseline = float(np.mean(np.abs(baseline_preds - y_pv_arr)))

    recommended = "bayesian_ridge" if mae_bayes < mae_baseline else "empirical_formula"

    feature_names = [
        "global_tilted_irradiance_wm2", "sqrt_gti", "sun_height", "gti_x_sun_height", "sqrt_gti_x_sun_height",
        "cloud_cover_ratio", "cloud_x_gti", "sqrt_precip_mm",
        "hour_sin", "hour_cos", "hour_sin2", "hour_cos2",
        "doy_sin", "doy_cos", "gti_x_hour_sin", "gti_x_hour_cos", "gti_x_hour_sin2", "gti_x_hour_cos2"
    ]
    coef_dict = {f: float(c) for f, c in zip(feature_names, bayes_ridge.coef_)}
    sigma_diag_dict = {f: float(np.diag(bayes_ridge.sigma_)[i]) for i, f in enumerate(feature_names)}

    model_doc = {
        'forecast': {
            'recommended': recommended,
            'intercept': float(bayes_ridge.intercept_),
            'coef': coef_dict,
            'sigma_diag': sigma_diag_dict,
            'alpha': float(bayes_ridge.alpha_),
            'lambda': float(bayes_ridge.lambda_),
            'features': feature_names,
            'selection_basis': 'MAE',
            'metrics_bayesian': {'mae_kw': round(mae_bayes, 4), 'mean_uncertainty_std': round(mean_uncertainty, 4)},
            'metrics_baseline': {'mae_kw': round(mae_baseline, 4)},
            'n_train': len(X_pv),
            'lookback_days': lookback_days,
            'trained_at': now_utc.isoformat()
        },
        'trained_at': now_utc.isoformat(),
        'capacity_kw': 6.6
    }

    db.collection('status').document('pv_model').set(model_doc, merge=True)
    msg = f"Cloud Bayesian PV Model Auto-Retrained ({lookback_days}d history): {recommended} (Bayesian MAE: {mae_bayes:.4f} kW vs Baseline: {mae_baseline:.4f} kW over {len(X_pv)} daytime samples, Mean Uncertainty: ±{mean_uncertainty:.3f} kW)."
    print(msg)
    return {'status': 'success', 'message': msg, 'recommended': recommended, 'mae_bayesian': mae_bayes, 'mae_baseline': mae_baseline}


@scheduler_fn.on_schedule(
    schedule="0 2 * * 0",
    timezone=scheduler_fn.Timezone("Australia/Sydney"),
    region="australia-southeast1"
)
def retrain_pv_model_weekly_cron(event: scheduler_fn.ScheduledEvent) -> None:
    """Cloud Functions Autonomous Retraining Cron: Runs every Sunday at 02:00 AM Sydney time."""
    db = firestore.client()
    retrain_pv_model_logic(db)


@https_fn.on_request(region="australia-southeast1")
def trigger_retrain_pv_model_now(req: https_fn.Request) -> https_fn.Response:
    """HTTP trigger for immediate Cloud PV Model retraining & performance check."""
    db = firestore.client()
    res = retrain_pv_model_logic(db)
    return https_fn.Response(json.dumps(res, default=str), mimetype='application/json')


@https_fn.on_request(region="australia-southeast1")
def tesla_webhook(req: https_fn.Request) -> https_fn.Response:
    """Tesla Fleet Webhook Endpoint: Receives 0-latency real-time push events from Tesla Fleet API.
    
    Handles:
    - Event Challenge Verification (Tesla Webhook Handshake)
    - Real-time charge_state & drive_state telemetry push
    - Zero-latency session logging without battery vampire drain
    """
    db = firestore.client()
    
    # 1. Tesla Webhook Challenge Verification Handshake
    challenge = req.args.get("challenge")
    if challenge:
        print(f"Tesla Webhook challenge received: {challenge}")
        return https_fn.Response(challenge, status=200)

    try:
        data = req.get_json(silent=True) or {}
        print(f"⚡ Tesla Webhook Push Event Received: {json.dumps(data)}")

        event_type = data.get("event_type") or data.get("topic")
        payload = data.get("data") or data.get("payload") or data
        
        # If payload contains vehicle charge_state / drive_state update
        if payload:
            charge_info = payload.get("charge_state", {})
            drive_info = payload.get("drive_state", {})
            
            if charge_info or drive_info:
                print("Updating status/tesla_live via Webhook Push...")
                tesla_live_ref = db.collection("status").document("tesla_live")
                existing = tesla_live_ref.get().to_dict() or {}
                
                if charge_info:
                    b_lvl = charge_info.get("usable_battery_level") if charge_info.get("usable_battery_level") is not None else charge_info.get("battery_level")
                    if b_lvl is not None:
                        existing["battery_level"] = int(b_lvl)
                    if "charging_state" in charge_info:
                        existing["charging_state"] = str(charge_info["charging_state"])
                    if "charger_power" in charge_info:
                        existing["charger_power_kw"] = float(charge_info["charger_power"])
                    if "charge_energy_added" in charge_info:
                        existing["charge_energy_added_kwh"] = float(charge_info["charge_energy_added"])
                
                if drive_info:
                    if "latitude" in drive_info:
                        existing["latitude"] = float(drive_info["latitude"])
                    if "longitude" in drive_info:
                        existing["longitude"] = float(drive_info["longitude"])
                    if "shift_state" in drive_info:
                        existing["shift_state"] = drive_info["shift_state"]

                existing["last_updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                existing["note"] = "⚡ Real-time Webhook Push active"
                
                tesla_live_ref.set(existing, merge=True)
                # Removed smart_poll_tesla(db) to prevent duplicating API calls. We rely fully on this webhook payload.

        return https_fn.Response(json.dumps({"status": "ok"}), status=200, mimetype='application/json')
    except Exception as e:
        print(f"Error handling Tesla Webhook: {str(e)}")
        return https_fn.Response(json.dumps({"error": str(e)}), status=500, mimetype='application/json')


@https_fn.on_request(region="australia-southeast1")
def wake_up_tesla_now(req: https_fn.Request) -> https_fn.Response:
    """HTTP endpoint to actively wake up the Tesla vehicle on user request
    and return the freshly synced telemetry status payload.
    """
    import time
    db = firestore.client()
    settings_doc = db.collection("settings").document("tesla").get()
    if not settings_doc.exists:
        return https_fn.Response(json.dumps({"error": "Tesla settings missing"}), status=400, mimetype='application/json')
    
    cfg = settings_doc.to_dict() or {}
    
    if not cfg.get("access_token"):
        return https_fn.Response(json.dumps({"error": "Tesla OAuth token missing"}), status=400, mimetype='application/json')

    try:
        access_token = ensure_valid_tesla_token(db, cfg)
        client = TeslaFleetClient(client_id=cfg.get("client_id", ""), client_secret=cfg.get("client_secret", ""))
        vehicles = client.get_vehicles(access_token)
        if not vehicles:
            return https_fn.Response(json.dumps({"error": "No vehicles found"}), status=404, mimetype='application/json')
            
        vehicle_id = vehicles[0].get("id_s") or str(vehicles[0].get("id"))
        print(f"Sending wake_up command to vehicle {vehicle_id}...")
        client.wake_up(access_token, vehicle_id)
        
        # Wait 8 seconds for vehicle system to power on and sync
        time.sleep(8)
        
        # Force full telemetry sync
        result = smart_poll_tesla(db)
        return https_fn.Response(json.dumps(result, default=str), status=200, mimetype='application/json')
    except Exception as e:
        print(f"Error in wake_up_tesla_now: {str(e)}")
        return https_fn.Response(json.dumps({"error": str(e)}), status=500, mimetype='application/json')


@https_fn.on_request(region="australia-southeast1")
def poll_tesla_status(req: https_fn.Request) -> https_fn.Response:
    """Lightweight Tesla poll — NO wake_up command issued.
    Uses smart_poll_tesla which skips vehicle_data entirely if the car is asleep,
    costing at most one /vehicles list call. Safe to call on every pull-to-refresh."""
    db = firestore.client()
    try:
        result = smart_poll_tesla(db)
        return https_fn.Response(json.dumps(result, default=str), status=200, mimetype='application/json')
    except Exception as e:
        print(f"Error in poll_tesla_status: {str(e)}")
        return https_fn.Response(json.dumps({"error": str(e)}), status=500, mimetype='application/json')


def ensure_tesla_proxy_running(db):
    """Ensures local linux tesla-http-proxy daemon is running inside Cloud Function container."""
    import os, shutil, socket, subprocess, time
    doc = db.collection("settings").document("tesla").get()
    d = doc.to_dict() if doc.exists else {}
    priv_pem = d.get("private_key_pem", "")
    if not priv_pem:
        raise ValueError("Missing private_key_pem in settings/tesla")

    key_path = "/tmp/private_key.pem"
    cert_path = "/tmp/cert.crt"
    cert_key_path = "/tmp/cert.key"
    tmp_bin = "/tmp/tesla-http-proxy"

    if not os.path.exists(key_path):
        with open(key_path, "w") as f:
            f.write(priv_pem)

    if not os.path.exists(cert_path) or not os.path.exists(cert_key_path):
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", cert_key_path, "-out", cert_path, "-days", "365",
            "-subj", "/CN=localhost"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Copy or decompress binary to /tmp to bypass noexec workspace restrictions
    if not os.path.exists(tmp_bin):
        try:
            import base64, gzip
            from tesla_proxy_data import PROXY_B64
            print(f"Decompressing embedded tesla_proxy_data to {tmp_bin}...")
            raw_gz = base64.b64decode(PROXY_B64)
            decompressed = gzip.decompress(raw_gz)
            with open(tmp_bin, "wb") as f_out:
                f_out.write(decompressed)
            os.chmod(tmp_bin, 0o755)
        except Exception as ex_err:
            print(f"Error extracting embedded tesla_proxy_data: {ex_err}")
            dat_bin = os.path.join(os.path.dirname(__file__), "bin", "proxy_blob.dat")
            src_bin = os.path.join(os.path.dirname(__file__), "bin", "tesla-http-proxy")
            if os.path.exists(dat_bin):
                import gzip
                with gzip.open(dat_bin, "rb") as f_in:
                    with open(tmp_bin, "wb") as f_out:
                        shutil.copyfileobj(f_in, f_out)
                os.chmod(tmp_bin, 0o755)
            elif os.path.exists(src_bin):
                shutil.copy2(src_bin, tmp_bin)
                os.chmod(tmp_bin, 0o755)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.2)
    is_up = s.connect_ex(('127.0.0.1', 8443)) == 0
    s.close()

    if not is_up and os.path.exists(tmp_bin):
        os.chmod(tmp_bin, 0o755)
        print(f"Starting tesla-http-proxy daemon from {tmp_bin}...")
        subprocess.Popen([
            tmp_bin,
            "-tls-key", cert_key_path,
            "-cert", cert_path,
            "-key-file", key_path,
            "-port", "8443",
            "-host", "127.0.0.1"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(10):
            time.sleep(0.05)
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(0.1)
            if s.connect_ex(('127.0.0.1', 8443)) == 0:
                s.close()
                break
            s.close()


def execute_tesla_proxy_command(db, access_token, vin, cmd_name, params=None):
    """Executes a signed Tesla command using the bundled tesla-http-proxy."""
    import requests, urllib3
    urllib3.disable_warnings()
    ensure_tesla_proxy_running(db)
    headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}
    proxy_url = f"https://127.0.0.1:8443/api/1/vehicles/{vin}/command/{cmd_name}"
    res = requests.post(proxy_url, headers=headers, json=params or {}, verify=False, timeout=15)
    res.raise_for_status()
    return res.json().get("response", {})


def stop_tesla_charging_helper(db, t_cfg=None):
    """Safely issues charge_stop command to the connected Tesla vehicle via Proxy / Fleet API.
    Calls smart_poll_tesla FIRST to snapshot the latest energy and battery level while vehicle is online."""
    if not t_cfg:
        doc = db.collection("settings").document("tesla").get()
        t_cfg = doc.to_dict() if doc.exists else {}
    if not t_cfg.get("enabled", False) or not t_cfg.get("access_token"):
        return False
    try:
        # Step 1: Snapshot fresh vehicle telemetry while car is actively charging (Online & Awake)
        try:
            print("Capturing pre-stop Tesla live telemetry snapshot...")
            smart_poll_tesla(db)
        except Exception as e_poll:
            print(f"Warning: Pre-stop smart_poll_tesla failed: {e_poll}")

        access_token = ensure_valid_tesla_token(db, t_cfg)
        vin = t_cfg.get("vin")
        vehicle_id = t_cfg.get("vehicle_id")
        
        # Step 2: Try signed command proxy first
        stopped = False
        if vin:
            try:
                execute_tesla_proxy_command(db, access_token, vin, "charge_stop")
                print("Successfully sent charge_stop via Tesla Proxy.")
                stopped = True
            except Exception as e_proxy:
                print(f"Proxy charge_stop failed: {e_proxy}. Checking for sleep/offline state...")
                err_str = str(e_proxy).lower()
                if "408" in err_str or "504" in err_str or "offline" in err_str or "asleep" in err_str:
                    try:
                        print("Vehicle asleep or offline. Sending wake_up before proxy retry...")
                        client = TeslaFleetClient(client_id=t_cfg.get("client_id", ""), client_secret=t_cfg.get("client_secret", ""))
                        vid = vehicle_id or vin
                        client.wake_up(access_token, vid)
                        import time
                        time.sleep(5)
                        execute_tesla_proxy_command(db, access_token, vin, "charge_stop")
                        print("Successfully sent charge_stop via Tesla Proxy after wake_up.")
                        stopped = True
                    except Exception as e_wake:
                        print(f"Proxy retry after wake_up failed: {e_wake}")
        
        # Step 3: Fallback to direct Fleet REST API
        if not stopped:
            client = TeslaFleetClient(client_id=t_cfg.get("client_id", ""), client_secret=t_cfg.get("client_secret", ""))
            vid = vehicle_id or vin
            try:
                client.execute_command(access_token, vid, "charge_stop")
                print("Successfully sent charge_stop via Tesla Fleet REST API.")
                stopped = True
            except Exception as e_rest:
                print(f"Fleet REST charge_stop failed: {e_rest}")

        if stopped:
            # Update local live state document
            try:
                db.collection("status").document("tesla_live").set({
                    "charging_state": "Stopped (Sponge Target Reached)",
                    "note": "EV Solar Sponge completed: stopped charging to protect home reserve",
                    "last_updated": datetime.datetime.now(datetime.timezone.utc).isoformat()
                }, merge=True)
            except Exception:
                pass
            return True
        return False
    except Exception as e_all:
        print(f"Failed to stop Tesla charging: {str(e_all)}")
        return False


def start_tesla_charging_helper(db, t_cfg=None):
    """Safely issues charge_start command to the connected Tesla vehicle via Proxy / Fleet API."""
    if not t_cfg:
        doc = db.collection("settings").document("tesla").get()
        t_cfg = doc.to_dict() if doc.exists else {}
    if not t_cfg.get("enabled", False) or not t_cfg.get("access_token"):
        return False
    try:
        access_token = ensure_valid_tesla_token(db, t_cfg)
        vin = t_cfg.get("vin")
        vehicle_id = t_cfg.get("vehicle_id")
        if vin:
            try:
                execute_tesla_proxy_command(db, access_token, vin, "charge_start")
                print("Successfully sent charge_start via Tesla Proxy.")
                return True
            except Exception as e_proxy:
                print(f"Proxy charge_start failed: {e_proxy}. Trying REST API...")
        client = TeslaFleetClient(client_id=t_cfg.get("client_id", ""), client_secret=t_cfg.get("client_secret", ""))
        vid = vehicle_id or vin
        try:
            client.execute_command(access_token, vid, "charge_start")
            print("Successfully sent charge_start via Tesla Fleet REST API.")
            return True
        except Exception as e_rest:
            print(f"Fleet REST charge_start failed: {e_rest}")
            return False
    except Exception as e_all:
        print(f"Failed to start Tesla charging: {str(e_all)}")
        return False


@https_fn.on_request(region="australia-southeast1")
def control_tesla_vehicle(req: https_fn.Request) -> https_fn.Response:
    """HTTP Callable Endpoint for Wear OS and App to send direct commands to Tesla (frunk, trunk, lock, unlock, flash_lights, charge_stop, charge_start)."""
    import requests
    db = firestore.client()
    settings_doc = db.collection("settings").document("tesla").get()
    if not settings_doc.exists:
        return https_fn.Response(json.dumps({"error": "Tesla settings missing"}), status=400, mimetype='application/json')
    
    cfg = settings_doc.to_dict() or {}
    client_id = cfg.get("client_id", "")
    client_secret = cfg.get("client_secret", "")
    
    if not cfg.get("access_token"):
        return https_fn.Response(json.dumps({"error": "Tesla OAuth token missing"}), status=400, mimetype='application/json')

    try:
        access_token = ensure_valid_tesla_token(db, cfg)
        body = req.get_json(silent=True) or {}
        data = body.get("data", body) if isinstance(body.get("data"), dict) else body

        # Security check: Verify App Secret Token
        app_secret_expected = cfg.get("app_secret_token", "")
        req_secret = data.get("app_secret") or req.headers.get("X-App-Secret") or req.args.get("app_secret")
        if app_secret_expected and req_secret != app_secret_expected:
            print(f"Unauthorized request to control_tesla_vehicle! Invalid secret token.")
            return https_fn.Response(
                json.dumps({"result": {"success": False, "error": "Unauthorized: Invalid App Secret Token", "code": 401}}),
                status=200,
                mimetype='application/json'
            )

        # Allow both JSON body and query string params
        action = data.get("action") or req.args.get("action")
        
        if not action:
            return https_fn.Response(json.dumps({"error": "Missing 'action' parameter"}), status=400, mimetype='application/json')

        # Instantiate Fleet client
        client = TeslaFleetClient(client_id=client_id, client_secret=client_secret)

        # Fast-path: Use cached VIN and vehicle_id from Firestore settings/tesla to skip get_vehicles() API call
        vin = cfg.get("vin")
        vehicle_id = cfg.get("vehicle_id")

        if not vin or not vehicle_id:
            vehicles = client.get_vehicles(access_token)
            if not vehicles:
                return https_fn.Response(json.dumps({"error": "No vehicles found"}), status=404, mimetype='application/json')
            vehicle_id = vehicles[0].get("id_s") or str(vehicles[0].get("id"))
            vin = vehicles[0].get("vin") or ""
            db.collection("settings").document("tesla").set({"vin": vin, "vehicle_id": vehicle_id}, merge=True)
        
        # Action routing
        cmd_name = ""
        params = {}
        if action == "frunk":
            cmd_name = "actuate_trunk"
            params = {"which_trunk": "front"}
        elif action == "trunk":
            cmd_name = "actuate_trunk"
            params = {"which_trunk": "rear"}
        elif action == "lock":
            cmd_name = "door_lock"
        elif action == "unlock":
            cmd_name = "door_unlock"
        elif action == "flash":
            cmd_name = "flash_lights"
        elif action == "hvac_on":
            cmd_name = "auto_conditioning_start"
        elif action == "hvac_off":
            cmd_name = "auto_conditioning_stop"
        elif action in ["sentry_on", "sentry_true"]:
            cmd_name = "set_sentry_mode"
            params = {"on": True}
        elif action in ["sentry_off", "sentry_false"]:
            cmd_name = "set_sentry_mode"
            params = {"on": False}
        elif action in ["charge_stop", "charging_stop", "stop_charge", "stop_charging"]:
            cmd_name = "charge_stop"
        elif action in ["charge_start", "charging_start", "start_charge", "start_charging"]:
            cmd_name = "charge_start"
        elif action == "wake":
            print(f"Sending wake_up command to vehicle {vehicle_id}...")
            client.wake_up(access_token, vehicle_id)
            import threading
            threading.Thread(target=smart_poll_tesla, args=(db,)).start()
            return https_fn.Response(json.dumps({"result": {"success": True, "status": "success", "action": "wake"}}), status=200, mimetype='application/json')
        else:
            return https_fn.Response(json.dumps({"error": f"Unsupported action '{action}'"}), status=400, mimetype='application/json')

        print(f"Executing Tesla proxy command '{cmd_name}' (action: {action}) on VIN {vin}...")
        try:
            resp = execute_tesla_proxy_command(db, access_token, vin, cmd_name, params)
            # Run telemetry poll asynchronously in background thread so watch gets instant response!
            import threading
            threading.Thread(target=smart_poll_tesla, args=(db,)).start()
            return https_fn.Response(json.dumps({"result": {"success": True, "action": action, "response": resp}}), status=200, mimetype='application/json')
        except requests.exceptions.HTTPError as he:
            status_code = he.response.status_code if he.response is not None else 500
            err_body = he.response.text if he.response is not None else str(he)
            print(f"Tesla API HTTP {status_code} error for action '{action}': {err_body}")
            
            if status_code in [408, 422, 500, 504] or "offline" in err_body or "asleep" in err_body:
                # Attempt auto wake and retry once
                try:
                    print(f"Vehicle asleep/offline (HTTP {status_code}). Attempting wake_up retry...")
                    client.wake_up(access_token, vehicle_id)
                    import time
                    time.sleep(6)
                    resp = execute_tesla_proxy_command(db, access_token, vin, cmd_name, params)
                    import threading
                    threading.Thread(target=smart_poll_tesla, args=(db,)).start()
                    return https_fn.Response(json.dumps({"result": {"success": True, "action": action, "response": resp}}), status=200, mimetype='application/json')
                except Exception as retry_err:
                    print(f"Retry after wake failed: {str(retry_err)}")
                    err_body = str(retry_err)

            if status_code == 403:
                error_msg = f"Tesla API 403 Forbidden: {err_body}"
                if "account disabled" in err_body.lower() or "exceeded_limit" in err_body.lower():
                    error_msg = "Tesla API Limit Exceeded (403). Please wait or upgrade your developer tier."
                elif "requires pairing" in err_body.lower() or "public key" in err_body.lower():
                    error_msg = "Tesla Key Pairing Needed (HTTP 403). Pair developer key in vehicle."
                    
                return https_fn.Response(
                    json.dumps({"result": {"success": False, "error": error_msg, "code": 403}}),
                    status=200,
                    mimetype='application/json'
                )
            else:
                return https_fn.Response(
                    json.dumps({"result": {"success": False, "error": f"Tesla API Error ({status_code}): {err_body}", "code": status_code}}),
                    status=200,
                    mimetype='application/json'
                )

    except Exception as e:
        print(f"Error executing Tesla command '{action}': {str(e)}")
        return https_fn.Response(
            json.dumps({"result": {"success": False, "error": str(e), "code": 500}}),
            status=200,
            mimetype='application/json'
        )




