#!/usr/bin/env python3
"""PV + household-load model trainer: ridge regression vs baselines, planner-view metrics.

Trains three variants:
  actual    actual weather  -> actual PV   (upper bound: how predictable is PV at all)
  forecast  forecast weather (+ horizon_h) -> actual PV   (the deployable PV model)
  load      forecast temp + calendar       -> actual household load (deployable; EV window excluded)

Key design points (v2):
  * DAYTIME-ONLY PV training (GHI > 10): night rows are trivially zero and dilute the fit —
    inference (functions/main.py) returns 0 outright when the forecast says night.
  * PLANNER-VIEW metrics: the charging planner consumes DAILY kWh sums at 6-48h lead time,
    so model selection uses daily-kWh MAE (deduped to one forecast run per target bin,
    horizon closest to 18h), not raw hourly MAE. Per-horizon MAE buckets are also reported.
  * Walk-forward alpha CV: one-day-ahead folds over the train span pick the ridge alpha.
  * 2nd-harmonic shading interactions (gti_x_hour_sin2/cos2): tree shade is not a single
    smooth bump; two harmonics can express double dips / sharp edges. MUST stay mirrored
    with the feature construction in functions/main.py `_build_pv_predictor`.
  * Load variant excludes the EV charging window (car+house is not house) exactly like
    `_build_load_lookup` does, and its baseline IS that function's (is_weekend, hour)
    bucket mean — the model must beat the thing it would replace.

Output pv_model_coefficients.json holds plain raw-space linear coefficients:
  pred_kw = max(0, intercept + sum(coef[f] * x[f]))
so inference in a Cloud Function is a dot product — no sklearn, no pickle.

Usage:
  python3 train_pv_model.py --data-dir data --capacity-kw 6.6
"""
import argparse
import datetime
import json
import os

import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler

# MUST stay in lockstep with functions/main.py `_build_pv_predictor` feature construction.
PV_FEATURES = [
    "global_tilted_irradiance_wm2",
    "shortwave_radiation_wm2", "direct_radiation_wm2", "diffuse_radiation_wm2",
    "direct_normal_irradiance_wm2",
    "temperature_c", "is_day",
    "hour_sin", "hour_cos", "doy_sin", "doy_cos",
    "sun_height", "gti_x_sun_height",
]

# MUST stay in lockstep with functions/main.py `_build_load_lookup` model path.
LOAD_FEATURES = [
    "hour_sin", "hour_cos", "hour_sin2", "hour_cos2",
    "is_weekend", "temperature_c", "is_day",
]

ALPHA_GRID = [0.1, 0.3, 1.0, 3.0, 10.0, 30.0]
MIN_TRAIN_ROWS = 150   # daytime-only halves row counts vs v1's 200
HOURS_PER_ROW = 0.5    # 30-min bins
PLANNER_HORIZON_H = 18.0  # mid of the 6-30h lead-time range the 23:30 planner actually uses


def _usable_features(df, features, min_coverage=0.5):
    kept = [f for f in features if f in df.columns and df[f].notna().mean() >= min_coverage]
    dropped = [f for f in features if f not in kept]
    if dropped:
        print(f"  (excluded low-coverage features: {', '.join(dropped)})")
    return kept


def add_time_features(df, time_col):
    t = pd.to_datetime(df[time_col])
    hour = t.dt.hour + t.dt.minute / 60.0
    doy = t.dt.dayofyear.astype(float)
    df["hour_sin"] = np.sin(2 * np.pi * hour / 24.0)
    df["hour_cos"] = np.cos(2 * np.pi * hour / 24.0)
    df["hour_sin2"] = np.sin(4 * np.pi * hour / 24.0)
    df["hour_cos2"] = np.cos(4 * np.pi * hour / 24.0)
    df["doy_sin"] = np.sin(2 * np.pi * doy / 365.25)
    df["doy_cos"] = np.cos(2 * np.pi * doy / 365.25)
    df["sun_height"] = np.maximum(0.0, np.sin(np.pi * np.maximum(0.0, hour - 6.0) / 12.0))
    df["is_weekend"] = (t.dt.weekday >= 5).astype(float)
    if "global_tilted_irradiance_wm2" in df.columns:
        df["gti_x_sun_height"] = df["global_tilted_irradiance_wm2"] * df["sun_height"]
        for h in ("hour_sin", "hour_cos", "hour_sin2", "hour_cos2"):
            df[f"gti_x_{h}"] = df["global_tilted_irradiance_wm2"] * df[h]
    df["_date"] = t.dt.date
    df["_hour"] = t.dt.hour
    return df


def split_by_date(df):
    """Time-based split: last ~20% of calendar days = test. Never split randomly —
    adjacent 30-min rows are heavily autocorrelated and random splits leak."""
    dates = sorted(df["_date"].unique())
    n_test = max(1, int(round(len(dates) * 0.2)))
    test_dates = set(dates[-n_test:])
    return df[~df["_date"].isin(test_dates)], df[df["_date"].isin(test_dates)], sorted(test_dates)


def select_alpha(train, features, target_col, fallback):
    """Walk-forward CV: for each of the last <=5 train days, fit on strictly earlier days
    and validate on that day; pick the alpha with the lowest mean MAE."""
    dates = sorted(train["_date"].unique())
    if len(dates) < 4:
        print(f"  alpha CV skipped (only {len(dates)} train days) -> alpha={fallback}")
        return fallback
    folds = dates[-min(5, len(dates) - 2):]
    scores = {}
    for alpha in ALPHA_GRID:
        errs = []
        for d in folds:
            tr = train[train["_date"] < d]
            va = train[train["_date"] == d]
            if len(tr) < 30 or len(va) == 0:
                continue
            sc = StandardScaler().fit(tr[features].values)
            mdl = Ridge(alpha=alpha).fit(sc.transform(tr[features].values), tr[target_col].values)
            pred = np.clip(mdl.predict(sc.transform(va[features].values)), 0, None)
            errs.append(float(np.mean(np.abs(va[target_col].values - pred))))
        if errs:
            scores[alpha] = float(np.mean(errs))
    if not scores:
        return fallback
    best = min(scores, key=scores.get)
    pretty = ", ".join(f"{a}:{m:.3f}" for a, m in sorted(scores.items()))
    print(f"  alpha CV ({len(folds)} folds) MAE -> {pretty} | chosen alpha={best}")
    return best


def planner_view(test):
    """One row per 30-min target bin: keep the forecast run whose horizon is closest to
    18h (the planner's typical lead time). Without dedupe, targets covered by many
    snapshots dominate the metrics and short horizons mask the error the planner sees."""
    if "horizon_h" not in test.columns:
        return test
    t = test.copy()
    t["_hkey"] = (t["horizon_h"] - PLANNER_HORIZON_H).abs()
    return t.sort_values("_hkey").drop_duplicates(subset=["timestamp"]).drop(columns=["_hkey"])


def hourly_metrics(y_true, y_pred):
    return {
        "mae_kw": float(np.mean(np.abs(y_true - y_pred))),
        "rmse_kw": float(np.sqrt(np.mean((y_true - y_pred) ** 2))),
    }


def horizon_metrics(test, y_true, y_pred):
    if "horizon_h" not in test.columns:
        return None
    out = {}
    h = test["horizon_h"].values
    for lo, hi in [(0, 12), (12, 24), (24, 48)]:
        m = (h > lo) & (h <= hi)
        if m.sum() >= 10:
            out[f"{lo}-{hi}h"] = {"mae_kw": float(np.mean(np.abs(y_true[m] - y_pred[m]))),
                                  "n": int(m.sum())}
    return out or None


def daily_metrics(test, y_true, y_pred):
    """Daily-energy error on the planner-view (deduped) rows — the metric that matters:
    the planner consumes daily kWh sums, and a model can win hourly MAE while carrying
    a systematic daily bias."""
    d = pd.DataFrame({"_date": test["_date"].values,
                      "t": y_true * HOURS_PER_ROW, "p": y_pred * HOURS_PER_ROW})
    g = d.groupby("_date").sum()
    if len(g) == 0:
        return None
    err = g["p"] - g["t"]
    return {
        "daily_mae_kwh": float(err.abs().mean()),
        "daily_bias_kwh": float(err.mean()),
        "n_days": int(len(g)),
        "actual_mean_kwh": float(g["t"].mean()),
    }


def fit_and_package(name, train, test, test_dates, features, target_col, alpha,
                    baseline_fn, baseline_label, quantiles=None):
    X_tr, y_tr = train[features].values, train[target_col].values
    scaler = StandardScaler().fit(X_tr)
    model = Ridge(alpha=alpha).fit(scaler.transform(X_tr), y_tr)

    # Planner-view evaluation set (deduped by target bin where horizons exist)
    pv_test = planner_view(test)
    y_te = pv_test[target_col].values
    pred = np.clip(model.predict(scaler.transform(pv_test[features].values)), 0, None)
    base = np.clip(baseline_fn(pv_test), 0, None)

    m, bm = hourly_metrics(y_te, pred), hourly_metrics(y_te, base)
    dm, dbm = daily_metrics(pv_test, y_te, pred), daily_metrics(pv_test, y_te, base)
    # Horizon buckets on the FULL (non-deduped) test rows — shows error growth with lead time
    if "horizon_h" in test.columns:
        full_pred = np.clip(model.predict(scaler.transform(test[features].values)), 0, None)
        hm = horizon_metrics(test, test[target_col].values, full_pred)
    else:
        hm = None

    print(f"[{name}] ridge     MAE {m['mae_kw']:.3f} kW"
          + (f" | daily {dm['daily_mae_kwh']:.2f} kWh (bias {dm['daily_bias_kwh']:+.2f})" if dm else ""))
    print(f"[{name}] {baseline_label:<9} MAE {bm['mae_kw']:.3f} kW"
          + (f" | daily {dbm['daily_mae_kwh']:.2f} kWh (bias {dbm['daily_bias_kwh']:+.2f})" if dbm else ""))
    if hm:
        print(f"[{name}] ridge MAE by horizon: "
              + ", ".join(f"{k} {v['mae_kw']:.3f} (n={v['n']})" for k, v in hm.items()))

    # PLANNER-VIEW model selection: daily kWh MAE decides; hourly MAE is the tiebreaker view.
    if dm and dbm:
        better = "ridge" if dm["daily_mae_kwh"] < dbm["daily_mae_kwh"] else "baseline"
        basis = "daily-kWh MAE"
    else:
        better = "ridge" if m["mae_kw"] < bm["mae_kw"] else "baseline"
        basis = "hourly MAE"
    print(f"[{name}] -> {better} wins on {basis}")

    # Quantile models (pinball loss, still LINEAR -> same dot-product inference).
    # p20 = pessimistic PV bound the planner uses as a weather-conditioned survival floor;
    # p80 = optimistic bound (reserved for notifications/UI). Coverage check: P(actual >=
    # p20 pred) should be ~0.8 — blocks are dropped if calibration is badly off, so the
    # planner silently falls back to the global newsvendor margin.
    q_blocks = None
    if quantiles:
        from sklearn.linear_model import QuantileRegressor
        q_blocks = {}
        for qname, qv in quantiles.items():
            qr = QuantileRegressor(quantile=qv, alpha=1e-4, solver="highs").fit(
                scaler.transform(X_tr), y_tr)
            qc = qr.coef_ / scaler.scale_
            qi = float(qr.intercept_ - np.sum(qr.coef_ * scaler.mean_ / scaler.scale_))
            qpred = np.clip(qi + pv_test[features].values @ qc, 0, None)
            cov = float(np.mean(y_te >= qpred)) if qv < 0.5 else float(np.mean(y_te <= qpred))
            print(f"[{name}] {qname} (q={qv}) coverage {cov:.2f} "
                  f"(target ~{(1 - qv) if qv < 0.5 else qv:.2f})")
            q_blocks[qname] = {
                "features": features, "quantile": qv, "coverage": cov,
                "coef": {f: float(c) for f, c in zip(features, qc)},
                "intercept": qi,
            }
        p20 = q_blocks.get("p20")
        if p20 and not (0.55 <= p20["coverage"] <= 0.98):
            print(f"[{name}] p20 coverage {p20['coverage']:.2f} out of [0.55, 0.98] — "
                  f"dropping quantile blocks (planner will use the global margin).")
            q_blocks = None

    raw_coef = model.coef_ / scaler.scale_
    raw_intercept = float(model.intercept_ - np.sum(model.coef_ * scaler.mean_ / scaler.scale_))
    return {
        "quantiles": q_blocks,
        "features": features,
        "coef": {f: float(c) for f, c in zip(features, raw_coef)},
        "intercept": raw_intercept,
        "alpha": alpha,
        "n_train": int(len(train)),
        "n_test": int(len(pv_test)),
        "test_days": [str(d) for d in test_dates],
        "metrics_ridge": m,
        "metrics_baseline": bm,
        "daily_ridge": dm,
        "daily_baseline": dbm,
        "by_horizon_ridge": hm,
        "recommended": better,
        "selection_basis": basis,
    }


def train_pv_variant(name, df, target_col, features, capacity_kw, alpha_arg, quantiles=None):
    features = _usable_features(df, features)
    df = df.dropna(subset=features + [target_col]).copy()
    # DAYTIME ONLY: inference returns 0 for night hours; don't spend model capacity there.
    df = df[df["shortwave_radiation_wm2"] > 10]
    if len(df) == 0:
        print(f"[{name}] no usable daytime rows, skipping.")
        return None
    train, test, test_dates = split_by_date(df)
    print(f"\n[{name}] {len(train)} train / {len(test)} test daytime rows "
          f"(test days: {', '.join(str(d) for d in test_dates)})")
    if len(train) < MIN_TRAIN_ROWS:
        print(f"[{name}] WARNING: only {len(train)} training rows (<{MIN_TRAIN_ROWS}). "
              f"Cold-start territory — expect the baseline formula to be competitive.")
    if len(test) == 0:
        print(f"[{name}] not enough days to hold out a test set, skipping.")
        return None
    alpha = select_alpha(train, features, target_col, alpha_arg)
    baseline = lambda t: capacity_kw * (t["shortwave_radiation_wm2"].values / 1000.0) * 0.75
    return fit_and_package(name, train, test, test_dates, features, target_col, alpha,
                           baseline, "formula", quantiles=quantiles)


def train_load_variant(df, ev_start, ev_end, alpha_arg):
    """Household load model. EV-window rows are excluded from BOTH train and test —
    the planner never uses a model prediction inside the EV window (it substitutes the
    late-evening base, see _build_load_lookup), so evaluating there would be meaningless."""
    target_col = "actual_load_kw"
    features = _usable_features(df, LOAD_FEATURES)
    df = df.dropna(subset=features + [target_col]).copy()
    in_ev = (df["_hour"] >= ev_start) & (df["_hour"] < ev_end) if ev_start < ev_end else \
            ((df["_hour"] >= ev_start) | (df["_hour"] < ev_end))
    if ev_start != ev_end:
        df = df[~in_ev]
    if len(df) == 0:
        print("[load] no usable rows, skipping.")
        return None
    train, test, test_dates = split_by_date(df)
    print(f"\n[load] {len(train)} train / {len(test)} test rows, EV window {ev_start}-{ev_end}h "
          f"excluded (test days: {', '.join(str(d) for d in test_dates)})")
    if len(test) == 0:
        print("[load] not enough days to hold out a test set, skipping.")
        return None
    alpha = select_alpha(train, features, target_col, alpha_arg)

    # Baseline = exactly what _build_load_lookup deploys today: (is_weekend, hour) bucket mean.
    bucket = train.groupby([train["is_weekend"], train["_hour"]])[target_col].mean()
    overall = float(train[target_col].mean())

    def baseline(t):
        keys = list(zip(t["is_weekend"].values, t["_hour"].values))
        return np.array([bucket.get(k, overall) for k in keys])

    return fit_and_package("load", train, test, test_dates, features, target_col, alpha,
                           baseline, "buckets")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data-dir", default="data")
    ap.add_argument("--capacity-kw", type=float, default=6.6,
                    help="installed PV capacity for the baseline formula — keep equal to "
                         "settings/growatt.pv_capacity_kw so comparisons match production")
    ap.add_argument("--alpha", type=float, default=1.0, help="fallback ridge alpha if CV can't run")
    ap.add_argument("--ev-start-hour", type=int, default=0)
    ap.add_argument("--ev-end-hour", type=int, default=6)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    out_path = args.out or os.path.join(args.data_dir, "pv_model_coefficients.json")

    result = {
        "trained_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "capacity_kw": args.capacity_kw,
        "predict": "pred_kw = max(0, intercept + sum(coef[f] * x[f])); night -> 0; clip at capacity",
    }

    tele_path = os.path.join(args.data_dir, "telemetry_30min.csv")
    if os.path.exists(tele_path):
        tele = add_time_features(pd.read_csv(tele_path, parse_dates=["timestamp"]), "timestamp")
        result["actual"] = train_pv_variant(
            "actual", tele, "solar_generation_kw", PV_FEATURES, args.capacity_kw, args.alpha)
    else:
        print(f"{tele_path} not found — run export_dataset.py first.")

    fc_path = os.path.join(args.data_dir, "train_forecast.csv")
    if os.path.exists(fc_path):
        fc = add_time_features(pd.read_csv(fc_path, parse_dates=["timestamp"]), "timestamp")
        result["forecast"] = train_pv_variant(
            "forecast", fc, "actual_pv_kw", PV_FEATURES + ["horizon_h"],
            args.capacity_kw, args.alpha, quantiles={"p20": 0.2, "p80": 0.8})
        result["load"] = train_load_variant(fc, args.ev_start_hour, args.ev_end_hour, args.alpha)
    else:
        print(f"{fc_path} not found — forecast + load variants skipped.")

    with open(out_path, "w") as f:
        json.dump(result, f, indent=2)
    print(f"\nSaved -> {out_path}")
    print("Deploy with upload_model.py (uploads 'forecast' and 'load' blocks to status/pv_model).")


if __name__ == "__main__":
    main()
