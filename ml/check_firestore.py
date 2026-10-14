#!/usr/bin/env python3
"""Firestore preflight check: verifies settings, tariff rules, and data-pipeline health.

Usage:
  python3 check_firestore.py ~/Downloads/xgrowatt-key.json

Exit code 0 = all PASS/WARN, 1 = at least one FAIL.
"""
import argparse
import datetime
import sys

import firebase_admin
from firebase_admin import credentials, firestore

EXPECTED_PV_CAPACITY = 6.6

RESULTS = []


def report(level, msg):
    RESULTS.append(level)
    print(f"[{level}] {msg}")


def check_settings(db):
    print("\n=== settings/growatt ===")
    doc = db.collection('settings').document('growatt').get()
    if not doc.exists:
        report("FAIL", "settings/growatt 不存在")
        return {}
    s = doc.to_dict()

    # PV capacity — feeds the empirical formula in generate_charging_plan
    cap = s.get('pv_capacity_kw')
    if cap is None:
        report("FAIL", f"pv_capacity_kw 缺失 — 云函数将用默认 10,请设为 {EXPECTED_PV_CAPACITY}")
    elif abs(float(cap) - EXPECTED_PV_CAPACITY) > 0.01:
        report("WARN", f"pv_capacity_kw = {cap},预期 {EXPECTED_PV_CAPACITY}")
    else:
        report("PASS", f"pv_capacity_kw = {cap}")

    # Battery knobs (all have code defaults; report what's in effect)
    for key, default in [('battery_max_charge_kw', 5.0),
                         ('battery_min_soc_pct', 15.0),
                         ('battery_max_soc_pct', 95.0)]:
        v = s.get(key)
        if v is None:
            report("PASS", f"{key} 未设置,使用代码默认 {default}")
        else:
            report("PASS", f"{key} = {v}")

    # Location & tz — used by weather fetch/forecast; city-centre fallback loses accuracy
    if s.get('latitude') is not None and s.get('longitude') is not None:
        report("PASS", f"坐标 = ({s['latitude']:.4f}, {s['longitude']:.4f})")
    else:
        report("WARN", "latitude/longitude 缺失 — 天气将退回时区城市中心坐标")
    report("PASS" if s.get('timezone') else "FAIL", f"timezone = {s.get('timezone', '<缺失>')}")

    if s.get('username') or s.get('api_token'):
        report("PASS", "Growatt 凭据已配置")
    else:
        report("FAIL", "username/api_token 都缺失,无法同步逆变器")
    return s


def check_tariff(s):
    print("\n=== tariff 规则 ===")
    tariff = s.get('tariff') or {}
    rules = [r for r in tariff.get('rules', []) if r.get('enabled', True)]
    if not rules:
        report("FAIL", "tariff.rules 为空 — 计划生成器无法识别 off-peak/免费窗口")
        return

    for r in rules:
        print(f"       {r.get('start_time')}-{r.get('end_time')} {r.get('days')} "
              f"import={r.get('import_rate')} export={r.get('export_rate')}")

    all_days = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

    def covers(r, start, end, days):
        return (r.get('start_time') == start and r.get('end_time') == end
                and days.issubset(set(r.get('days', []))))

    offpeak = [r for r in rules if covers(r, '00:00', '06:00', all_days)]
    if offpeak:
        report("PASS", f"off-peak 00:00-06:00 全周规则存在 (import {offpeak[0].get('import_rate')})")
    else:
        report("FAIL", "缺少 00:00-06:00 全周 off-peak 规则(或天数不全)")

    free = [r for r in rules
            if covers(r, '12:00', '14:00', {"Sat", "Sun"}) and float(r.get('import_rate', 1)) == 0.0]
    if free:
        report("PASS", "周末 12:00-14:00 免费规则存在 (import 0)")
    else:
        report("FAIL", "缺少 Sat/Sun 12:00-14:00 且 import_rate=0 的免费规则")

    if offpeak and free:
        op = float(offpeak[0].get('import_rate', 0.3))
        fb = float(tariff.get('fallbackImportRate', 0.30))
        if op >= fb:
            report("WARN", f"off-peak 费率 ({op}) >= fallback ({fb}) — 计划生成器会误判便宜窗口")


def check_data_pipeline(db):
    now = datetime.datetime.now(datetime.timezone.utc)

    print("\n=== telemetry_history ===")
    docs = db.collection('telemetry_history').order_by(
        'timestamp', direction=firestore.Query.DESCENDING).limit(1).get()
    if len(docs) == 0:
        report("FAIL", "telemetry_history 为空")
    else:
        x = docs[0].to_dict()
        age_min = (now - x['timestamp']).total_seconds() / 60
        report("PASS" if age_min < 30 else "WARN",
               f"最新遥测 {age_min:.0f} 分钟前 (soc={x.get('soc')}, pv={x.get('solar_generation_kw')} kW)")
        ghi = x.get('shortwave_radiation_wm2')
        report("PASS" if ghi is not None else "WARN",
               f"最新遥测天气字段 GHI = {ghi}" + ("" if ghi is not None else " — 天气 join 未生效?"))

    print("\n=== weather_forecast ===")
    docs = db.collection('weather_forecast').order_by(
        'issued_at', direction=firestore.Query.DESCENDING).limit(1).get()
    if len(docs) == 0:
        report("FAIL", "weather_forecast 为空 — fetch_weather_forecast 未部署或还没跑过")
    else:
        x = docs[0].to_dict()
        age_h = (now - x['issued_at']).total_seconds() / 3600
        n = len(x.get('hours', []))
        report("PASS" if age_h < 14 and n >= 48 else "WARN",
               f"最新预报快照 {age_h:.1f} 小时前,{n} 个小时条目 (期望 72,<14h)")

    print("\n=== status 文档 ===")
    plan = db.collection('status').document('charging_plan').get()
    if plan.exists:
        p = plan.to_dict()
        report("PASS", f"charging_plan 存在: {p.get('for_date')} 目标 SoC {p.get('target_soc')}%, "
                       f"充 {p.get('charge_kwh')} kWh (${p.get('est_cost')}), 模型={p.get('model_used')}")
    else:
        report("WARN", "status/charging_plan 不存在 — 函数未部署或还没到 23:10(可 Force run)")

    model = db.collection('status').document('pv_model').get()
    if model.exists:
        report("PASS", "status/pv_model 存在(岭回归已上线)")
    else:
        report("PASS", "status/pv_model 不存在 — 冷启动阶段正常,用经验公式兜底")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("key", help="service account JSON 路径")
    args = ap.parse_args()

    firebase_admin.initialize_app(credentials.Certificate(args.key))
    db = firestore.client()

    s = check_settings(db)
    check_tariff(s)
    check_data_pipeline(db)

    n_fail = RESULTS.count("FAIL")
    n_warn = RESULTS.count("WARN")
    print(f"\n结果: {RESULTS.count('PASS')} PASS / {n_warn} WARN / {n_fail} FAIL")
    sys.exit(1 if n_fail else 0)


if __name__ == "__main__":
    main()
