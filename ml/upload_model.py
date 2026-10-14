#!/usr/bin/env python3
"""Uploads trained PV (+ load) model coefficients to Firestore (status/pv_model).

The generate_charging_plan Cloud Function checks this document on every run:
  forecast block present + recommended=="ridge" -> PV dot-product inference, else empirical formula
  load     block present + recommended=="ridge" -> load dot-product inference, else hour buckets
So this script IS the model deployment step. Each block is gated independently on its own
training result (planner-view daily-kWh MAE). To roll back everything:
just delete the status/pv_model document in the Firestore console.

Usage:
  python3 upload_model.py ~/Downloads/xgrowatt-key.json [--json data/pv_model_coefficients.json]
"""
import argparse
import json
import sys

import firebase_admin
from firebase_admin import credentials, firestore


def _show(name, blk):
    m, bm = blk.get("metrics_ridge", {}), blk.get("metrics_baseline", {})
    dm, dbm = blk.get("daily_ridge") or {}, blk.get("daily_baseline") or {}
    print(f"[{name}] 训练/测试: {blk.get('n_train')} / {blk.get('n_test')} 行 "
          f"(测试日: {', '.join(blk.get('test_days', []))})")
    print(f"[{name}] 模型 MAE {m.get('mae_kw', 0):.3f} kW | 日 kWh MAE {dm.get('daily_mae_kwh', float('nan')):.2f} "
          f"(bias {dm.get('daily_bias_kwh', float('nan')):+.2f})")
    print(f"[{name}] 基线 MAE {bm.get('mae_kw', 0):.3f} kW | 日 kWh MAE {dbm.get('daily_mae_kwh', float('nan')):.2f} "
          f"(bias {dbm.get('daily_bias_kwh', float('nan')):+.2f})")
    print(f"[{name}] 推荐: {blk.get('recommended')} (依据: {blk.get('selection_basis', 'MAE')})")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("key", help="service account JSON 路径")
    ap.add_argument("--json", default="data/pv_model_coefficients.json")
    ap.add_argument("--force", action="store_true",
                    help="upload the PV forecast block even if the baseline beat it")
    args = ap.parse_args()

    with open(args.json) as f:
        result = json.load(f)

    fc = result.get("forecast")
    if not fc:
        print("JSON 里没有 'forecast' 块 — 预报训练数据还不够(weather_forecast 攒满约 2 周后再试)。")
        sys.exit(1)

    print(f"训练时间: {result.get('trained_at')}\n")
    _show("forecast", fc)
    if fc.get("recommended") != "ridge":
        if not args.force:
            print("\nPV 模型没有赢过经验公式,不上传(继续攒数据每周重训;确要上传加 --force)。")
            sys.exit(1)
        else:
            print("\n[--force 强行部署] 将 recommended 强制置为 'ridge' 以在推理端启用该模型。")
            fc["recommended"] = "ridge"

    load = result.get("load")
    if load:
        print()
        _show("load", load)

    doc = {
        "forecast": fc,
        "trained_at": result.get("trained_at"),
        "capacity_kw": result.get("capacity_kw"),
    }
    # Load block deploys ONLY on merit — a losing load model is dropped so the Cloud
    # Function falls back to the bucket baseline it failed to beat. Delete any previously
    # deployed load block in that case (set() without merge replaces the whole doc).
    if load and load.get("recommended") == "ridge":
        doc["load"] = load
        load_msg = "load 模型赢过 bucket 基线 — 一并部署。"
    else:
        load_msg = "load 模型未赢过 bucket 基线 — 不部署(推理端继续用 4 天分时段均值)。"

    firebase_admin.initialize_app(credentials.Certificate(args.key))
    firestore.client().collection("status").document("pv_model").set(doc)
    print(f"\n{load_msg}")
    print("已写入 status/pv_model — 下一次计划生成(23:30 或手动刷新)即生效,")
    print("charging_plan 的 model_used 字段可确认当前推理路径。")


if __name__ == "__main__":
    main()
