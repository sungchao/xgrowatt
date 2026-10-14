"""
One-time backfill: fills in weather fields for telemetry_history entries that predate
the weather-join feature (or any entry where a weather fetch happened to fail).

Uses Open-Meteo's Historical Weather API (ERA5 reanalysis, hourly resolution, free,
no API key needed) instead of the live `forecast` endpoint used for new entries — this
is intentional: it's more accurate for past dates (reanalysis vs. a live nowcast) and
lets us backfill any date instantly instead of waiting for new data to accumulate.

This is a LOCAL, one-off maintenance script — it is NOT deployed as a Cloud Function.
Run it once from your machine (or re-run any time; it skips entries that already have
weather data, so it's safe to run repeatedly).

Setup:
  1. Firebase Console -> Project Settings -> Service Accounts -> Generate new private key.
     Save the downloaded JSON file somewhere (do NOT commit it to git).
  2. pip install firebase-admin requests --break-system-packages   (or use a venv)
  3. Run:
       python3 backfill_weather.py /path/to/serviceAccountKey.json

Optional flags:
       python3 backfill_weather.py key.json --dry-run       # preview only, no writes
       python3 backfill_weather.py key.json --limit 500     # cap how many docs to scan
"""


import argparse

import time
from collections import defaultdict

import requests
import firebase_admin
from firebase_admin import credentials, firestore

# Must match functions/main.py's _HOURLY_WEATHER_VARS — kept as a separate literal here
# (rather than imported) so this script has no dependency on main.py's module-level
# firebase_admin.initialize_app() call, which expects Cloud Functions' default credentials.
HOURLY_WEATHER_VARS = [
    "temperature_2m", "apparent_temperature", "relative_humidity_2m",
    "precipitation", "weather_code", "is_day",
    "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
    "shortwave_radiation", "direct_radiation", "diffuse_radiation", "direct_normal_irradiance",
    "sunshine_duration", "uv_index", "visibility", "wind_speed_10m",
    "global_tilted_irradiance",
]

# A reduced set to retry with if the historical archive rejects one of the fancier variables
# (uv_index / sunshine_duration availability can differ between the forecast and archive APIs).
CORE_WEATHER_VARS = [
    "temperature_2m", "apparent_temperature", "relative_humidity_2m",
    "precipitation", "weather_code", "is_day",
    "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
    "shortwave_radiation", "direct_radiation", "diffuse_radiation", "direct_normal_irradiance",
    "wind_speed_10m",
]

TIMEZONE_COORDS = {
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

# Presence of this field = "already backfilled". Using the (newest) GTI field means a
# re-run after the GTI rollout will revisit ALL rows and add the missing GTI values to
# entries that were backfilled before GTI existed. Existing fields are merged, not lost.
MARKER_FIELD = "global_tilted_irradiance_wm2"

# Panel geometry for global_tilted_irradiance (matches main.py's _panel_params defaults;
# overridden from settings/growatt panel_tilt_deg / panel_azimuth_deg at runtime).
PANEL_TILT_DEG = 25.0
PANEL_AZIMUTH_DEG = 180.0  # Open-Meteo convention: 0 = south, +/-180 = north


def fetch_day_weather(lat: float, lon: float, tz_name: str, date_str: str,
                      tilt: float = PANEL_TILT_DEG, azimuth: float = PANEL_AZIMUTH_DEG) -> dict:
    """Fetches one day's hourly weather from the Historical Weather API. Returns the
    raw `hourly` dict (keyed by variable name -> list aligned with `hourly['time']`)."""
    for var_list in (HOURLY_WEATHER_VARS, CORE_WEATHER_VARS):
        try:
            resp = requests.get(
                "https://archive-api.open-meteo.com/v1/archive",
                params={
                    "latitude": lat,
                    "longitude": lon,
                    "start_date": date_str,
                    "end_date": date_str,
                    "hourly": ",".join(var_list),
                    "timezone": tz_name,
                    "tilt": tilt,
                    "azimuth": azimuth,
                },
                timeout=15,
            )
            resp.raise_for_status()
            hourly = resp.json().get("hourly", {})
            if hourly.get("time"):
                return hourly
        except Exception as e:
            print(f"    weather fetch failed for {date_str} with {len(var_list)} vars: {e}")
            continue
    return {}


def extract_hour(hourly: dict, hour_str: str) -> dict:
    """hour_str like '2026-07-01T14:00'. Returns a flat dict of weather fields for that hour."""
    times = hourly.get("time", [])
    if hour_str not in times:
        return {}
    idx = times.index(hour_str)

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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("service_account_key", help="Path to Firebase service account JSON key")
    parser.add_argument("--dry-run", action="store_true", help="Preview only, do not write")
    parser.add_argument("--limit", type=int, default=None, help="Max telemetry docs to scan")
    args = parser.parse_args()

    cred = credentials.Certificate(args.service_account_key)
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    # Resolve location + timezone from settings/growatt (same source main.py uses).
    settings_doc = db.collection("settings").document("growatt").get()
    settings = settings_doc.to_dict() if settings_doc.exists else {}
    tz_name = settings.get("timezone", "Australia/Sydney")
    lat = settings.get("latitude")
    lon = settings.get("longitude")
    if lat is None or lon is None:
        lat, lon = TIMEZONE_COORDS.get(tz_name, (-35.28, 149.13))
    print(f"Using location lat={lat}, lon={lon}, timezone={tz_name}")

    # 1. Find telemetry_history docs missing weather data.
    print("Scanning telemetry_history for entries missing weather data...")
    query = db.collection("telemetry_history").order_by("timestamp")
    if args.limit:
        query = query.limit(args.limit)
    docs = list(query.stream())
    print(f"Fetched {len(docs)} telemetry_history docs total.")

    missing = []
    for doc in docs:
        data = doc.to_dict()
        ts = data.get("timestamp")
        if ts is None:
            continue
        if data.get(MARKER_FIELD) is not None:
            continue  # already backfilled (or written fresh with weather already)
        missing.append((doc.id, ts))

    print(f"{len(missing)} docs are missing weather data and need backfilling.")
    if not missing:
        print("Nothing to do.")
        return

    # 2. Group by local calendar date so we only call the weather API once per day.
    import zoneinfo
    tz = zoneinfo.ZoneInfo(tz_name)
    by_date = defaultdict(list)
    for doc_id, ts in missing:
        local_dt = ts.astimezone(tz)
        date_str = local_dt.strftime("%Y-%m-%d")
        hour_str = local_dt.strftime("%Y-%m-%dT%H:00")
        by_date[date_str].append((doc_id, hour_str))

    print(f"Spans {len(by_date)} distinct calendar day(s). Fetching weather per day...")

    updated_count = 0
    skipped_count = 0
    batch = db.batch()
    batch_size = 0

    tilt = float(settings.get("panel_tilt_deg", PANEL_TILT_DEG))
    azimuth = float(settings.get("panel_azimuth_deg", PANEL_AZIMUTH_DEG))

    for date_str, entries in sorted(by_date.items()):
        print(f"  {date_str}: {len(entries)} telemetry entries")
        hourly = fetch_day_weather(lat, lon, tz_name, date_str, tilt=tilt, azimuth=azimuth)
        if not hourly:
            print(f"    -> no weather data returned for {date_str}, skipping this day.")
            skipped_count += len(entries)
            continue

        for doc_id, hour_str in entries:
            weather = extract_hour(hourly, hour_str)
            # Drop None values so a re-run can never overwrite an existing good field with
            # None (e.g. uv_index fetched previously but absent from the CORE fallback set).
            weather = {k: v for k, v in weather.items() if v is not None}
            if not weather:
                skipped_count += 1
                continue

            if args.dry_run:
                updated_count += 1
                continue

            doc_ref = db.collection("telemetry_history").document(doc_id)
            batch.update(doc_ref, weather)
            batch_size += 1
            updated_count += 1

            if batch_size >= 400:  # stay under Firestore's 500-write batch limit
                batch.commit()
                batch = db.batch()
                batch_size = 0

        time.sleep(0.2)  # be polite to the free API

    if not args.dry_run and batch_size > 0:
        batch.commit()

    print(f"Done. Updated {updated_count} docs, skipped {skipped_count} (no matching weather data).")
    if args.dry_run:
        print("(dry run — no writes were made)")


if __name__ == "__main__":
    main()
