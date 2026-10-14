"""
Tesla Fleet API Integration Module
Handles OAuth 2.0 PKCE/Token Auth, Automatic Token Refresh, Anti-Vamp-Drain Sleep Protection,
and Live EV Charging Telemetry Extraction.
"""

import time
import requests
import datetime
from typing import Optional, Dict, Any

# Regional Base URLs for Tesla Fleet API
TESLA_AUTH_URL = "https://auth.tesla.com/oauth2/v3/authorize"
TESLA_TOKEN_URL = "https://auth.tesla.com/oauth2/v3/token"
FLEET_API_BASE_URL_NA_APAC = "https://fleet-api.prd.na.vn.cloud.tesla.com"
FLEET_API_BASE_URL_EU = "https://fleet-api.prd.eu.vn.cloud.tesla.com"

# Default Scopes for Read-Only, User Vehicle List, Location & Charge Monitoring
TESLA_SCOPES = "openid offline_access user_data vehicle_device_data vehicle_cmds vehicle_charging_cmds vehicle_location"


class TeslaFleetClient:
    """Client for interacting with Tesla Fleet API safely with anti-vamp drain protection."""

    def __init__(self, client_id: str = "", client_secret: str = "", region: str = "NA_APAC"):
        self.client_id = client_id
        self.client_secret = client_secret
        self.base_url = FLEET_API_BASE_URL_EU if region == "EU" else FLEET_API_BASE_URL_NA_APAC

    def get_auth_url(self, redirect_uri: str, state: str = "xgrowatt_tesla_oauth") -> str:
        """Generates Tesla OAuth 2.0 Auth URL for user login."""
        params = {
            "response_type": "code",
            "client_id": self.client_id,
            "redirect_uri": redirect_uri,
            "scope": TESLA_SCOPES,
            "state": state
        }
        req = requests.Request("GET", TESLA_AUTH_URL, params=params).prepare()
        return req.url

    def exchange_code_for_tokens(self, code: str, redirect_uri: str) -> Dict[str, Any]:
        """Exchanges OAuth auth code for access_token and refresh_token."""
        payload = {
            "grant_type": "authorization_code",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "code": code,
            "redirect_uri": redirect_uri,
            "audience": self.base_url
        }
        res = requests.post(TESLA_TOKEN_URL, data=payload, timeout=10)
        res.raise_for_status()
        data = res.json()
        expires_in = data.get("expires_in", 28800) # Default 8 hours
        data["expires_at"] = int(time.time()) + expires_in - 300 # 5 min buffer
        return data

    def get_partner_token(self) -> Dict[str, Any]:
        """Fetches partner token using client_credentials grant."""
        payload = {
            "grant_type": "client_credentials",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "scope": TESLA_SCOPES,
            "audience": self.base_url
        }
        res = requests.post(TESLA_TOKEN_URL, data=payload, timeout=10)
        res.raise_for_status()
        data = res.json()
        expires_in = data.get("expires_in", 28800)
        data["expires_at"] = int(time.time()) + expires_in - 300
        return data

    def refresh_access_token(self, refresh_token: str) -> Dict[str, Any]:
        """Refreshes expired access_token using refresh_token."""
        payload = {
            "grant_type": "refresh_token",
            "client_id": self.client_id,
            "refresh_token": refresh_token
        }
        res = requests.post(TESLA_TOKEN_URL, json=payload, timeout=10)
        res.raise_for_status()
        data = res.json()
        expires_in = data.get("expires_in", 28800)
        data["expires_at"] = int(time.time()) + expires_in - 300
        return data

    def wake_up(self, access_token: str, vehicle_id: str) -> Dict[str, Any]:
        """Sends wake_up command to the vehicle. Required before fetching live data if asleep."""
        headers = {"Authorization": f"Bearer {access_token}"}
        res = requests.post(f"{self.base_url}/api/1/vehicles/{vehicle_id}/wake_up", headers=headers, timeout=15)
        res.raise_for_status()
        return res.json().get("response", {})

    def execute_command(self, access_token: str, vehicle_id: str, command: str, params: Dict[str, Any] = None) -> Dict[str, Any]:
        """Executes a vehicle command via Tesla Fleet API (e.g., actuate_trunk, door_lock, door_unlock)."""
        headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}
        url = f"{self.base_url}/api/1/vehicles/{vehicle_id}/command/{command}"
        res = requests.post(url, headers=headers, json=params or {}, timeout=15)
        res.raise_for_status()
        return res.json().get("response", {})

    def get_vehicles(self, access_token: str) -> list:
        """Queries GET /api/1/vehicles (Lightweight, does NOT wake up car)."""
        headers = {"Authorization": f"Bearer {access_token}"}
        res = requests.get(f"{self.base_url}/api/1/vehicles", headers=headers, timeout=10)
        res.raise_for_status()
        return res.json().get("response", [])

    def get_vehicle_data(self, access_token: str, vehicle_id_or_vin: str) -> Dict[str, Any]:
        """Queries GET /api/1/vehicles/{id}/vehicle_data to fetch complete telemetry
        plus location_data endpoint for live GPS coordinates.
        """
        headers = {"Authorization": f"Bearer {access_token}"}
        
        # 1. Full vehicle telemetry
        url_full = f"{self.base_url}/api/1/vehicles/{vehicle_id_or_vin}/vehicle_data"
        res_full = requests.get(url_full, headers=headers, timeout=15)
        res_full.raise_for_status()
        resp_full = res_full.json().get("response", {})
        
        # 2. Location endpoints data for GPS coordinates
        url_loc = f"{self.base_url}/api/1/vehicles/{vehicle_id_or_vin}/vehicle_data?endpoints=location_data"
        res_loc = requests.get(url_loc, headers=headers, timeout=15)
        resp_loc = res_loc.json().get("response", {}) if res_loc.status_code == 200 else {}
        
        charge_state = resp_full.get("charge_state", {})
        drive_state = resp_full.get("drive_state", {})
        loc_drive_state = resp_loc.get("drive_state", {})
        
        # Merge GPS coordinates from location_data endpoint into drive_state
        if loc_drive_state:
            drive_state.update(loc_drive_state)

        return {
            "charge_state": charge_state,
            "drive_state": drive_state,
            "vehicle_state": resp_full.get("vehicle_state", {}),
            "location": resp_full.get("location", {})
        }


def ensure_valid_tesla_token(db, cfg: Dict[str, Any]) -> str:
    """Checks if the access_token is expired and refreshes it synchronously if needed.
    Returns the valid access_token, or raises an Exception if refresh fails.
    """
    client_id = cfg.get("client_id", "")
    client_secret = cfg.get("client_secret", "")
    access_token = cfg.get("access_token", "")
    refresh_token = cfg.get("refresh_token", "")
    expires_at = cfg.get("expires_at", 0)

    now_ts = int(time.time())
    if now_ts >= expires_at and refresh_token:
        print("Tesla access token expired — refreshing via OAuth refresh_token...")
        client = TeslaFleetClient(client_id=client_id, client_secret=client_secret)
        refreshed = client.refresh_access_token(refresh_token)
        access_token = refreshed["access_token"]
        
        db.collection("settings").document("tesla").set({
            "access_token": access_token,
            "refresh_token": refreshed.get("refresh_token", refresh_token),
            "expires_at": refreshed["expires_at"],
            "updated_at": datetime.datetime.now(datetime.timezone.utc)
        }, merge=True)
        # Update the runtime config dict so callers have the new values
        cfg["access_token"] = access_token
        cfg["refresh_token"] = refreshed.get("refresh_token", refresh_token)
        cfg["expires_at"] = refreshed["expires_at"]
        
    return access_token


def smart_poll_tesla(db) -> Dict[str, Any]:
    """Smart Polling Logic for Tesla Fleet API with Anti-Vamp-Drain Sleep Protection
    and Anti-Ghost-Data freshness checks.
    
    Returns structured status dictionary saved into Firestore `status/tesla_live`.
    """
    settings_doc = db.collection("settings").document("tesla").get()

    
    # If no Tesla account configured or disabled, return default/mock active state
    if not settings_doc.exists:
        return _build_mock_tesla_status(is_connected=False, note="Tesla credentials not configured in settings/tesla")
    
    cfg = settings_doc.to_dict() or {}
    if not cfg.get("enabled", False):
        return _build_mock_tesla_status(is_connected=False, note="Tesla integration disabled in settings")
        
    client_id = cfg.get("client_id", "")
    client_secret = cfg.get("client_secret", "")
    
    if not cfg.get("access_token"):
        return _build_mock_tesla_status(is_connected=False, note="Tesla OAuth token missing. Click Connect in App.")

    # Token Expiration Check & Auto-Refresh
    try:
        access_token = ensure_valid_tesla_token(db, cfg)
    except Exception as e_ref:
        print(f"Error refreshing Tesla token: {str(e_ref)}")
        return _build_mock_tesla_status(is_connected=False, note=f"Token refresh failed: {str(e_ref)}")

    client = TeslaFleetClient(client_id=client_id, client_secret=client_secret)

    # Step 1: Lightweight vehicle list check (Does NOT wake up vehicle!)
    try:
        vehicles = client.get_vehicles(access_token)
        if not vehicles:
            return _build_mock_tesla_status(is_connected=False, note="No vehicles linked to Tesla account.")
            
        primary_car = vehicles[0]
        vehicle_id = primary_car.get("id_s") or str(primary_car.get("id"))
        car_name = primary_car.get("display_name") or "Tesla Model Y"
        v_state = primary_car.get("state", "unknown")
        
        # Anti-Vamp Drain Check: If car is asleep or offline, do NOT fetch vehicle_data!
        if v_state in ["asleep", "offline"]:
            print(f"Tesla vehicle '{car_name}' is currently {v_state} — skipping vehicle_data call to prevent vamp drain.")
            # Read last cached status from status/tesla_live
            last_doc = db.collection("status").document("tesla_live").get()
            last_dict = last_doc.to_dict() if last_doc.exists else {}
            last_dict.update({
                "car_name": car_name,
                "vehicle_state": v_state,
                "charging_state": "Asleep (Preserving Battery)",
                "data_fresh": False,
                "note": "Vehicle in sleep mode — showing last known data.",
                "last_updated": datetime.datetime.now(datetime.timezone.utc).isoformat()
            })
            return last_dict
            
        # Step 2: Car is ONLINE -> Query detailed vehicle_data
        vdata = client.get_vehicle_data(access_token, vehicle_id)
        charge_info = vdata.get("charge_state", {})
        drive_info = vdata.get("drive_state", {})
        location_info = vdata.get("location", {})
        
        # ── Anti-Ghost-Data: Check data timestamp freshness ──────────────────
        # charge_state.timestamp is Unix epoch (milliseconds) of when car last synced
        data_ts_ms = charge_info.get("timestamp", 0)
        now_ms = int(time.time() * 1000)
        data_age_mins = round((now_ms - data_ts_ms) / 60000, 1) if data_ts_ms else 999
        data_fresh = data_age_mins < 5  # Fresh if < 5 minutes old

        current_charging_state = charge_info.get("charging_state", "")
        is_charging = current_charging_state == "Charging"

        # ⚡ Only auto-wake if:
        #   1. Car is actively CHARGING (already on power, no vampire drain risk)
        #   2. Data is stale (> 5 min old)
        # Never auto-wake when parked idle — avoid vampire drain!
        if not data_fresh and data_ts_ms > 0 and is_charging:
            print(f"⚡ Charging but ghost data detected ({data_age_mins:.1f} min old) — waking to sync...")
            try:
                client.wake_up(access_token, vehicle_id)
                time.sleep(12)  # Wait 12 sec for vehicle to wake and sync
                vdata = client.get_vehicle_data(access_token, vehicle_id)
                charge_info = vdata.get("charge_state", {})
                drive_info = vdata.get("drive_state", {})
                location_info = vdata.get("location", {})
                data_ts_ms = charge_info.get("timestamp", 0)
                data_age_mins = round((now_ms - data_ts_ms) / 60000, 1) if data_ts_ms else 999
                data_fresh = data_age_mins < 5
                print(f"✅ Post-wake data age: {data_age_mins:.1f} min | Fresh: {data_fresh}")
            except Exception as e_wake:
                print(f"Wake-up failed (non-critical): {str(e_wake)}")
        elif not data_fresh and not is_charging:
            # Parked idle with stale data — DON'T wake, just flag it
            print(f"🅿️  Parked idle, data is {data_age_mins:.1f} min old — skipping wake to protect battery.")
        # ─────────────────────────────────────────────────────────────────────

        battery_level = charge_info.get("usable_battery_level") if charge_info.get("usable_battery_level") is not None else charge_info.get("battery_level", 0)
        charger_power = charge_info.get("charger_power", 0.0)
        charge_added = charge_info.get("charge_energy_added", 0.0)
        charging_state = charge_info.get("charging_state", "Disconnected")
        charge_limit = charge_info.get("charge_limit_soc", 80)
        minutes_to_full = charge_info.get("minutes_to_full_charge", 0)
        charger_voltage = charge_info.get("charger_voltage", 0)
        charger_current = charge_info.get("charger_actual_current", 0)

        # Location & Driving state details
        latitude = drive_info.get("latitude") or drive_info.get("native_latitude") or drive_info.get("active_route_latitude") or location_info.get("latitude") or -35.165303
        longitude = drive_info.get("longitude") or drive_info.get("native_longitude") or drive_info.get("active_route_longitude") or location_info.get("longitude") or 149.127856
        shift_state = drive_info.get("shift_state")
        speed = drive_info.get("speed")
        dest = drive_info.get("active_route_destination")

        # Reverse Geocoding Helper via OpenStreetMap Nominatim (Free, no quota issue)
        geo_address = ""
        try:
            geo_res = requests.get(
                f"https://nominatim.openstreetmap.org/reverse?lat={latitude}&lon={longitude}&format=json",
                headers={"User-Agent": "XGrowatt/1.0"},
                timeout=3
            ).json()
            addr = geo_res.get("address", {})
            road = addr.get("road") or addr.get("pedestrian") or addr.get("suburb") or ""
            suburb = addr.get("suburb") or addr.get("city") or addr.get("town") or ""
            if road and suburb:
                geo_address = f"{road}, {suburb}"
            elif suburb:
                geo_address = suburb
            elif geo_res.get("display_name"):
                geo_address = geo_res.get("display_name").split(",")[0]
        except Exception:
            pass

        if shift_state in ["D", "R", "N"] or (speed is not None and speed > 0):
            speed_str = f" @ {speed} mph" if speed else ""
            dest_str = f" ➔ {dest}" if dest else ""
            location_name = f"Driving ({shift_state or 'D'}{speed_str}){dest_str}"
        else:
            if geo_address:
                location_name = f"Parked at {geo_address}"
            else:
                location_name = "Parked"

        # Vehicle & Climate State details
        veh_info = vdata.get("vehicle_state", {})
        climate_info = vdata.get("climate_state", {})

        is_locked = bool(veh_info.get("locked", True))
        sentry_mode = bool(veh_info.get("sentry_mode", False))
        is_climate_on = bool(climate_info.get("is_climate_on", False))
        inside_temp = climate_info.get("inside_temp")
        outside_temp = climate_info.get("outside_temp")

        df = veh_info.get("df", 0)
        dr = veh_info.get("dr", 0)
        pf = veh_info.get("pf", 0)
        pr = veh_info.get("pr", 0)
        is_any_door_open = bool(df or dr or pf or pr)
        is_frunk_open = bool(veh_info.get("ft", 0) > 0)
        is_trunk_open = bool(veh_info.get("rt", 0) > 0)

        result = {
            "is_connected": True,
            "car_name": car_name,
            "vehicle_state": v_state,
            "is_locked": is_locked,
            "is_climate_on": is_climate_on,
            "sentry_mode": sentry_mode,
            "is_any_door_open": is_any_door_open,
            "doors_detail": {
                "driver_front": bool(df),
                "driver_rear": bool(dr),
                "passenger_front": bool(pf),
                "passenger_rear": bool(pr)
            },
            "is_frunk_open": is_frunk_open,
            "is_trunk_open": is_trunk_open,
            "inside_temp_c": inside_temp,
            "outside_temp_c": outside_temp,
            "battery_level": int(battery_level),
            "charge_limit_soc": int(charge_limit),
            "charger_power_kw": float(charger_power),
            "charge_energy_added_kwh": float(charge_added),
            "charging_state": str(charging_state),
            "minutes_to_full_charge": int(minutes_to_full),
            "charger_voltage": int(charger_voltage),
            "charger_actual_current": int(charger_current),
            "latitude": float(latitude),
            "longitude": float(longitude),
            "location_name": str(location_name),
            "data_age_mins": data_age_mins,
            "data_fresh": data_fresh,
            "last_updated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "note": "Live telemetry & location active" if data_fresh else f"⚠️ Data may be stale ({data_age_mins:.0f} min old)"
        }
        
        # Save snapshot into status/tesla_live
        db.collection("status").document("tesla_live").set(result)
        track_tesla_session(db, result)
        return result

    except Exception as e_poll:
        print(f"Error in smart_poll_tesla: {str(e_poll)}")
        return _build_mock_tesla_status(is_connected=False, note=f"API Error: {str(e_poll)}")


def track_tesla_session(db, live_status: Dict[str, Any]):
    """Tracks active and historical Tesla charging sessions in Firestore collection `tesla_sessions`."""
    try:
        charging_state = live_status.get("charging_state", "")
        car_name = live_status.get("car_name", "Tesla Model Y")
        battery_level = live_status.get("battery_level", 0)
        charge_added = live_status.get("charge_energy_added_kwh", 0.0)
        charger_power = live_status.get("charger_power_kw", 0.0)
        now_dt = datetime.datetime.now(datetime.timezone.utc)
        today_date = now_dt.strftime("%Y-%m-%d")

        active_ref = db.collection("tesla_sessions").document("active")
        active_doc = active_ref.get()

        if charging_state == "Charging":
            if not active_doc.exists:
                session_data = {
                    "session_id": f"sess_{int(now_dt.timestamp())}",
                    "car_name": car_name,
                    "date": today_date,
                    "start_time": now_dt.isoformat(),
                    "start_soc": battery_level,
                    "start_charge_added": charge_added,
                    "current_charge_added": charge_added,
                    "max_power_kw": charger_power,
                    "status": "charging",
                    "last_updated": now_dt.isoformat()
                }
                active_ref.set(session_data)
            else:
                sess = active_doc.to_dict() or {}
                max_pwr = max(sess.get("max_power_kw", 0.0), charger_power)
                active_ref.update({
                    "current_charge_added": charge_added,
                    "end_soc": battery_level,
                    "max_power_kw": max_pwr,
                    "last_updated": now_dt.isoformat()
                })
        else:
            if active_doc.exists:
                sess = active_doc.to_dict() or {}
                if sess.get("status") == "charging":
                    start_dt = datetime.datetime.fromisoformat(sess.get("start_time"))
                    duration_mins = int((now_dt - start_dt).total_seconds() / 60)
                    session_kwh = max(0.0, charge_added - sess.get("start_charge_added", 0.0))
                    if session_kwh == 0.0 and charge_added > 0:
                        session_kwh = charge_added

                    closed_session = {
                        "session_id": sess.get("session_id"),
                        "car_name": car_name,
                        "date": sess.get("date", today_date),
                        "start_time": sess.get("start_time"),
                        "end_time": now_dt.isoformat(),
                        "duration_mins": duration_mins,
                        "start_soc": sess.get("start_soc", 0),
                        "end_soc": battery_level,
                        "kwh_added": round(session_kwh, 2),
                        "max_power_kw": sess.get("max_power_kw", 0.0),
                        "status": "completed"
                    }

                    sess_id = sess.get("session_id", f"sess_{int(now_dt.timestamp())}")
                    db.collection("tesla_sessions").document(sess_id).set(closed_session)
                    active_ref.delete()
                    print(f"Closed Tesla charging session {sess_id}: {session_kwh:.2f} kWh in {duration_mins} mins.")
    except Exception as e_sess:
        print(f"Error tracking Tesla session: {str(e_sess)}")


def _build_mock_tesla_status(is_connected: bool = False, note: str = "") -> Dict[str, Any]:
    """Generates clean default/mock status payload when Tesla credentials are not active yet."""
    return {
        "is_connected": is_connected,
        "car_name": "Tesla Model Y",
        "vehicle_state": "online",
        "battery_level": 59,
        "charge_limit_soc": 80,
        "charger_power_kw": 0.0,
        "charge_energy_added_kwh": 14.5,
        "charging_state": "Standby",
        "minutes_to_full_charge": 0,
        "charger_voltage": 240,
        "charger_actual_current": 0,
        "latitude": -35.165303,
        "longitude": 149.127856,
        "location_name": "Parked at Katherine Avenue, Amaroo",
        "last_updated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "note": note
    }
