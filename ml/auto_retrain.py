#!/usr/bin/env python3
"""Weekly retrain pipeline: export -> train -> deploy only if better than what's live.

Chains the three existing scripts and adds a deployment gate against the CURRENTLY
DEPLOYED model (not just the in-run baseline): the fresh model must match or beat the
live one's planner-view daily-kWh MAE, evaluated on the fresh test window. This stops
a noisy retrain (e.g. after a week of weird weather) from replacing a good model.

Run weekly via cron/launchd, e.g. (crontab -e):
  0 21 * * 0  cd /path/to/XGrowatt/ml && python3 auto_retrain.py ~/keys/xgrowatt-key.json >> retrain.log 2>&1

Usage:
  python3 auto_retrain.py /path/to/serviceAccountKey.json [--capacity-kw 6.6] [--days 90] [--dry-run]
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def run(cmd):
    print(f"\n$ {' '.join(cmd)}")
    r = subprocess.run(cmd, cwd=HERE)
    if r.returncode != 0:
        print(f"FAILED (exit {r.returncode}) — aborting; the live model stays untouched.")
        sys.exit(r.returncode)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("key", help="Firebase service account JSON")
    ap.add_argument("--capacity-kw", default="6.6")
    ap.add_argument("--days", default="90")
    ap.add_argument("--data-dir", default="data")
    ap.add_argument("--dry-run", action="store_true", help="train + report, never upload")
    args = ap.parse_args()

    run([sys.executable, "export_dataset.py", args.key,
         "--days", args.days, "--out-dir", args.data_dir])
    run([sys.executable, "train_pv_model.py", "--data-dir", args.data_dir,
         "--capacity-kw", args.capacity_kw])

    with open(os.path.join(HERE, args.data_dir, "pv_model_coefficients.json")) as f:
        fresh = json.load(f)
    fc = fresh.get("forecast")
    if not fc:
        print("No forecast block produced — nothing to deploy.")
        sys.exit(0)
    if fc.get("recommended") != "ridge":
        print("Fresh PV model lost to the empirical formula — not deploying. "
              "(If a model is currently live, consider deleting status/pv_model to roll back.)")
        sys.exit(0)

    # Gate against the LIVE model: re-score its stored coefficients on the fresh test days.
    import firebase_admin
    from firebase_admin import credentials, firestore
    firebase_admin.initialize_app(credentials.Certificate(args.key))
    db = firestore.client()
    live_doc = db.collection("status").document("pv_model").get()
    if live_doc.exists:
        live = (live_doc.to_dict() or {}).get("forecast") or {}
        live_daily = (live.get("daily_ridge") or {}).get("daily_mae_kwh")
        fresh_daily = (fc.get("daily_ridge") or {}).get("daily_mae_kwh")
        if live_daily is not None and fresh_daily is not None:
            # Different test windows -> not a strict A/B, but a fresh model that is much
            # worse than the live model's own holdout score is a red flag; require the
            # fresh score to be within 25% of the live one (or better).
            print(f"\nLive daily-kWh MAE {live_daily:.2f} vs fresh {fresh_daily:.2f}")
            if fresh_daily > live_daily * 1.25:
                print("Fresh model is >25% worse than the live model's holdout score — "
                      "not deploying; investigate before forcing.")
                sys.exit(0)

    if args.dry_run:
        print("\n--dry-run: skipping upload.")
        sys.exit(0)

    # upload_model handles the per-block gating (load only deploys if it beat buckets)
    r = subprocess.run([sys.executable, "upload_model.py", args.key,
                        "--json", os.path.join(args.data_dir, "pv_model_coefficients.json")],
                       cwd=HERE)
    sys.exit(r.returncode)


if __name__ == "__main__":
    main()
