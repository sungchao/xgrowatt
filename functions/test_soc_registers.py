#!/usr/bin/env python3
"""One-off register experiment: write SoC 43 via the standard command, then poll the
read-back to see WHICH field (wchargeSOCLowLimit1 vs wchargeSOCLowLimit2) reflects it
and how fast. Run while no charge window is active (afternoon) — tonight's 23:45 push
overwrites the test value anyway, so no cleanup needed.

Usage:
  python3 test_soc_registers.py ~/Downloads/xgrowatt-key.json            # write 43 + poll
  python3 test_soc_registers.py ~/Downloads/xgrowatt-key.json --read-only  # just poll
"""
import argparse
import datetime

import time

import firebase_admin
from firebase_admin import credentials, firestore
import growattServer

TEST_SOC = "43"
POLL_MINUTES = 10


def read_limits(api, device_sn):
    s = api.get_mix_inverter_settings(device_sn)
    obj = s.get("obj", s) if isinstance(s, dict) else {}
    return (obj.get("wchargeSOCLowLimit1"), obj.get("wchargeSOCLowLimit2"),
            obj.get("lastUpdateTimeText", "?"))


def read_limits_firestore(db):
    """Reads the cloud mirror (status/growatt_inverter_settings) — the exact payload our
    system sees, refreshed by the cloud function every 5 minutes."""
    doc = db.collection("status").document("growatt_inverter_settings").get()
    if not doc.exists:
        return None, None, "?"
    data = doc.to_dict()
    obj = data.get("settings", {})
    if isinstance(obj, dict) and "obj" in obj:
        obj = obj["obj"]
    return (obj.get("wchargeSOCLowLimit1"), obj.get("wchargeSOCLowLimit2"),
            data.get("last_updated", "?"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("key")
    ap.add_argument("--read-only", action="store_true")
    args = ap.parse_args()

    firebase_admin.initialize_app(credentials.Certificate(args.key))
    db = firestore.client()
    settings = db.collection("settings").document("growatt").get().to_dict()
    username, password = settings["username"], settings["password"]
    device_sn = settings.get("device_sn")

    api = growattServer.GrowattApi(add_random_user_id=True)
    custom_url = settings.get("server_url")
    if custom_url and "openapi" not in custom_url:
        api.server_url = custom_url
    login = api.login(username, password)
    user_id = login.get("userId")
    plants = api.plant_list(user_id)["data"]
    plant_id = plants[0]["plantId"]
    if not device_sn:
        device_sn = api.device_list(plant_id)[0].get("deviceSn")
    print(f"Logged in. Device: {device_sn}\n")

    l1, l2, ts = read_limits(api, device_sn)
    print(f"[before ] limit1={l1}  limit2={l2}  (device lastUpdate: {ts})")

    if not args.read_only:
        # Standard 18-param command: power 100, SoC 43, windows 0-6 + 12-14 (unchanged)
        params = ["100", TEST_SOC, "1",
                  "00", "00", "06", "00", "1",
                  "12", "00", "14", "00", "1",
                  "00", "00", "00", "00", "0"]
        resp = api.update_mix_inverter_setting(device_sn, "mix_ac_charge_time_period", params)
        print(f"[write  ] sent SoC={TEST_SOC} -> response: {resp}\n")

    print(f"Polling the FIRESTORE MIRROR every 60s for {POLL_MINUTES} min (it refreshes "
          f"every ~5 min via the cloud sync). Watch ShinePhone too.\n")
    for i in range(POLL_MINUTES):
        time.sleep(60)
        try:
            l1, l2, ts = read_limits_firestore(db)
            now = datetime.datetime.now().strftime("%H:%M:%S")
            marker1 = " <— 变了!" if str(l1) == TEST_SOC else ""
            marker2 = " <— 变了!" if str(l2) == TEST_SOC else ""
            print(f"[+{i+1:2d} min {now}] limit1={l1}{marker1}  limit2={l2}{marker2}  (mirror: {ts})")
        except Exception as e:
            print(f"[+{i+1:2d} min] read failed: {e}")

    print("\n完成。今晚 23:45 的正常推送会覆盖测试值,无需手动恢复。")


if __name__ == "__main__":
    main()
