#!/usr/bin/env python3
"""Firestore -> local CSV dataset exporter for PV model training.

Reads:
  telemetry_history   actuals (PV / load / SOC) + joined actual weather
  weather_forecast    forecast snapshots collected by fetch_weather_forecast
  settings/growatt    timezone

Writes to --out-dir (default ./data):
  telemetry_30min.csv   telemetry resampled to a 30-min local-time grid
  forecast_long.csv     forecast runs expanded to (issued_at, target_time, horizon_h, features)
  train_forecast.csv    forecast rows joined with actual PV/load — the main training table

Usage:
  python3 export_dataset.py /path/to/serviceAccountKey.json [--days 90] [--out-dir data]

Safe to re-run any time; it always rebuilds the CSVs from scratch.
"""
import argparse
import datetime
import os

import pandas as pd
import firebase_admin
from firebase_admin import credentials, firestore
from zoneinfo import ZoneInfo

# Must stay in lockstep with functions/main.py `_weather_snapshot_from_hourly` output keys.
WEATHER_COLS = [
    "temperature_c", "apparent_temperature_c", "relative_humidity_pct",
    "precipitation_mm", "weather_code", "is_day",
    "cloud_cover_pct", "cloud_cover_low_pct", "cloud_cover_mid_pct", "cloud_cover_high_pct",
    "shortwave_radiation_wm2", "direct_radiation_wm2", "diffuse_radiation_wm2",
    "direct_normal_irradiance_wm2",
    "sunshine_duration_s", "uv_index", "visibility_m", "wind_speed_kmh",
    "global_tilted_irradiance_wm2",
]

TELEMETRY_COLS = [
    "soc", "battery_energy_kwh", "solar_generation_kw", "charge_power_kw",
    "discharge_power_kw", "local_load_kw", "grid_export_kw", "grid_import_kw",
]


def export_telemetry(db, tz_name, days, out_dir):
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
    docs = db.collection("telemetry_history") \
             .where("timestamp", ">=", cutoff) \
             .order_by("timestamp") \
             .stream()

    rows = []
    for d in docs:
        x = d.to_dict()
        ts = x.get("timestamp")
        if ts is None:
            continue
        row = {"timestamp": ts}
        for c in TELEMETRY_COLS + WEATHER_COLS:
            row[c] = x.get(c)
        rows.append(row)
    print(f"telemetry_history: fetched {len(rows)} docs (last {days} days)")
    if not rows:
        return None

    df = pd.DataFrame(rows)
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True).dt.tz_convert(tz_name)
    df = df.set_index("timestamp").sort_index()
    # bool -> float so resample-mean works; NaN stays NaN
    df["is_day"] = df["is_day"].astype("float")

    agg = {c: "mean" for c in df.columns}
    agg["weather_code"] = "first"  # categorical, mean is meaningless
    g = df.resample("30min").agg(agg)

    # The sync function skips writes when values are identical and <1h old (night-time
    # mostly), so the raw series has gaps whose true value equals the previous row.
    # ffill(limit=2) = carry forward at most 1 hour, matching that skip window exactly.
    g = g.ffill(limit=2)
    g = g.dropna(subset=["solar_generation_kw"])

    path = os.path.join(out_dir, "telemetry_30min.csv")
    g.to_csv(path)
    n_days = g.index.normalize().nunique()
    print(f"  -> {path}: {len(g)} rows over {n_days} days")
    missing = g["shortwave_radiation_wm2"].isna().mean() * 100
    print(f"  -> weather field missing rate (GHI): {missing:.1f}%")
    return g


def export_forecasts(db, tz_name, out_dir):
    docs = db.collection("weather_forecast").stream()
    rows = []
    n_docs = 0
    for d in docs:
        n_docs += 1
        x = d.to_dict()
        issued = x.get("issued_at")
        for h in x.get("hours", []):
            t = h.get("time")
            if not t or issued is None:
                continue
            row = {"issued_at": issued, "target_time_str": t}
            for c in WEATHER_COLS:
                row[c] = h.get(c)
            rows.append(row)
    print(f"weather_forecast: {n_docs} snapshot docs, {len(rows)} hourly rows")
    if not rows:
        return None

    fc = pd.DataFrame(rows)
    fc["issued_at"] = pd.to_datetime(fc["issued_at"], utc=True).dt.tz_convert(tz_name)
    # 'time' strings are local wall-clock; NaT/shift handles DST edge hours
    fc["target_time"] = pd.to_datetime(fc["target_time_str"]).dt.tz_localize(
        tz_name, ambiguous="NaT", nonexistent="shift_forward")
    fc = fc.dropna(subset=["target_time"]).drop(columns=["target_time_str"])
    fc["is_day"] = fc["is_day"].astype("float")
    fc["horizon_h"] = (fc["target_time"] - fc["issued_at"]).dt.total_seconds() / 3600.0
    # keep future-looking rows only (each snapshot also contains a few already-past hours)
    fc = fc[fc["horizon_h"] >= 0].sort_values(["issued_at", "target_time"])

    path = os.path.join(out_dir, "forecast_long.csv")
    fc.to_csv(path, index=False)
    print(f"  -> {path}: {len(fc)} rows, horizon 0-{fc['horizon_h'].max():.0f}h")
    return fc


def build_training_table(tele30, fc, out_dir):
    """Join forecast features (hourly) onto the actual 30-min telemetry grid.

    One forecast hour maps to two 30-min bins. A target hour forecast by multiple runs
    appears once per run (different horizon_h) — deliberate, lets the model see how
    forecast error grows with lead time.
    """
    t = tele30.reset_index()
    t["hour_key"] = t["timestamp"].dt.floor("h")
    actuals = t[["timestamp", "hour_key", "solar_generation_kw", "local_load_kw", "soc"]].rename(
        columns={"solar_generation_kw": "actual_pv_kw", "local_load_kw": "actual_load_kw"})

    fc = fc.copy()
    fc["hour_key"] = fc["target_time"]
    merged = fc.merge(actuals, on="hour_key", how="inner")
    merged = merged.drop(columns=["hour_key"]).sort_values(["timestamp", "horizon_h"])

    path = os.path.join(out_dir, "train_forecast.csv")
    merged.to_csv(path, index=False)
    print(f"  -> {path}: {len(merged)} (forecast, actual) training pairs")
    return merged


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("key", nargs="?", help="path to Firebase service account JSON (optional)")
    ap.add_argument("--days", type=int, default=90, help="how far back to export telemetry")
    ap.add_argument("--out-dir", default="data")
    args = ap.parse_args()

    if not firebase_admin._apps:
        if args.key:
            firebase_admin.initialize_app(credentials.Certificate(args.key))
        else:
            firebase_admin.initialize_app(options={'projectId': 'demo-solar-microgrid'})
    db = firestore.client()

    sdoc = db.collection("settings").document("growatt").get()
    tz_name = (sdoc.to_dict() or {}).get("timezone", "Australia/Canberra") if sdoc.exists else "Australia/Canberra"
    ZoneInfo(tz_name)  # validate early
    print(f"Timezone: {tz_name}")

    os.makedirs(args.out_dir, exist_ok=True)

    tele30 = export_telemetry(db, tz_name, args.days, args.out_dir)
    fc = export_forecasts(db, tz_name, args.out_dir)

    if tele30 is not None and fc is not None:
        build_training_table(tele30, fc, args.out_dir)
    else:
        print("Skipped train_forecast.csv (need both telemetry and forecast data).")
    print("Done.")


if __name__ == "__main__":
    main()
