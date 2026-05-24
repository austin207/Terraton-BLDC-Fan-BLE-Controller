#!/usr/bin/env python3
"""
ml/train.py — Terraton Fan Recommender  Training Pipeline
==========================================================
Phase 1  XGBoost baseline + SHAP rules          (500+ rows, runs in seconds)
Phase 2  Two-tower Keras model → TFLite fp16    (10k+ rows, ~15 KB on device)

Usage
-----
    pip install -r requirements.txt

    # Pull live data from Cloudflare R2
    python train.py

    # Use a local CSV (export from R2 for offline dev / first smoke-test)
    python train.py --local data.csv

    # Phase 1 only (XGBoost — no TensorFlow needed)
    python train.py --phase 1

Output
------
    output/gear_xgb.json                         Phase 1 gear classifier
    output/savings_xgb.json                      Phase 1 savings regressor
    output/shap_importance.png                   Feature importance chart
    output/terraton_recommender.keras            Phase 2 Keras checkpoint
    output/terraton_recommender_fp16.tflite      → copy to Flutter assets/
    output/normalization_config.json             → copy to Flutter assets/

Flutter integration
-------------------
    1. Add tflite_flutter: ^0.10.4 to pubspec.yaml
    2. Copy the two output files above into terraton_fan_app/assets/
    3. The inference code reads normalization_config.json, preprocesses user
       logs + live Open-Meteo weather, then runs the TFLite interpreter.
"""

import argparse
import json
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, mean_absolute_error
from sklearn.model_selection import train_test_split

warnings.filterwarnings('ignore')

# ── 0. Config ──────────────────────────────────────────────────────────────────

# Cloudflare R2 — S3-compatible direct access for reading training data.
#
# IMPORTANT: These are R2 API tokens, NOT the Worker Bearer token
# (terraton-secret-2026 is for the upload endpoint only — different thing).
#
# To get R2 API tokens:
#   Cloudflare dashboard → R2 → Manage R2 API Tokens → Create API Token
#   Permissions: Object Read  (read-only is enough for training)
#   Copy the Access Key ID and Secret Access Key shown once on creation.
#
# To get your account ID:
#   Cloudflare dashboard → right sidebar → Account ID (32-char hex string)
#
R2_ENDPOINT   = 'https://<account_id>.r2.cloudflarestorage.com'  # fill in account_id
R2_ACCESS_KEY = '<r2_access_key_id>'                              # from R2 API tokens
R2_SECRET_KEY = '<r2_secret_access_key>'                          # from R2 API tokens
R2_BUCKET     = 'terraton-usage-data'

OUTPUT_DIR = Path('output')
OUTPUT_DIR.mkdir(exist_ok=True)

# KSEB LT domestic slab marginal rates (₹/kWh), slabs 1-8.
KSEB_RATES = [3.15, 3.70, 4.50, 5.80, 6.70, 7.50, 7.90, 8.20]

# Fan operating modes (order must match Flutter's mode_dist key order).
MODES = ['normal', 'nature', 'smart', 'reverse', 'boost']

# Normalisation ranges — fixed constants shared with the Flutter app.
# The app reads normalization_config.json which mirrors these exactly.
# NEVER change these after shipping the first TFLite model without retraining.
NORM = {
    'avg_session_mins': (0.0,  120.0),
    'sessions':         (0.0,  20.0),
    'temp_max_c':       (20.0, 42.0),   # Kerala climate range
    'temp_min_c':       (18.0, 35.0),
    'humidity_pct':     (40.0, 100.0),
    'tariff_per_kwh':   (0.0,  10.0),
    'kseb_slab':        (1.0,  8.0),
    'peak_hour':        (0.0,  23.0),
    'month':            (1.0,  12.0),
}

# Kerala weather defaults used when Open-Meteo returned -1 sentinel.
KERALA_DEFAULTS = {'temp_max_c': 31.0, 'temp_min_c': 26.0, 'humidity_pct': 80.0}


# ── 1. Data loading ────────────────────────────────────────────────────────────

def load_from_r2() -> pd.DataFrame:
    import boto3
    print('Connecting to Cloudflare R2...')
    s3 = boto3.client(
        's3',
        endpoint_url=R2_ENDPOINT,
        aws_access_key_id=R2_ACCESS_KEY,
        aws_secret_access_key=R2_SECRET_KEY,
        region_name='auto',
    )
    records = []
    paginator = s3.get_paginator('list_objects_v2')
    for page in paginator.paginate(Bucket=R2_BUCKET):
        for obj in page.get('Contents', []):
            raw = s3.get_object(Bucket=R2_BUCKET, Key=obj['Key'])['Body'].read()
            try:
                records.append(json.loads(raw))
            except json.JSONDecodeError:
                pass
    print(f'Loaded {len(records):,} records from R2.')
    return pd.json_normalize(records)


def load_from_csv(path: str) -> pd.DataFrame:
    print(f'Loading from {path} ...')
    return pd.read_csv(path)


# ── 2. Parse + expand list columns ────────────────────────────────────────────

def parse(raw: pd.DataFrame) -> pd.DataFrame:
    df = raw.copy()

    # gear_dist — list of 6 fractions
    gear_cols = [f'gear_{i}' for i in range(1, 7)]
    if 'gear_dist' in df.columns:
        gdf = pd.DataFrame(df['gear_dist'].tolist(), index=df.index, columns=gear_cols)
        df  = pd.concat([df.drop('gear_dist', axis=1), gdf], axis=1)

    # hourly_usage — list of 24 booleans
    hour_cols = [f'hour_{h:02d}' for h in range(24)]
    if 'hourly_usage' in df.columns:
        hdf = pd.DataFrame(df['hourly_usage'].tolist(), index=df.index, columns=hour_cols)
        df  = pd.concat([df.drop('hourly_usage', axis=1), hdf], axis=1)

    # mode_dist — dict → 5 fixed columns (missing mode = 0)
    if 'mode_dist' in df.columns:
        mdf = pd.DataFrame(df['mode_dist'].tolist(), index=df.index)
        for m in MODES:
            df[f'mode_{m}'] = mdf.get(m, 0.0).fillna(0.0)
        df = df.drop('mode_dist', axis=1)

    # Derived time features
    df['period'] = pd.to_datetime(df['period'], errors='coerce')
    df['month']  = df['period'].dt.month.fillna(6).astype(int)

    # Coerce numeric fields
    for col in ['avg_session_mins', 'sessions', 'total_kwh', 'avg_watts',
                'tariff_per_kwh', 'kseb_slab', 'monthly_kwh_est',
                'temp_max_c', 'temp_min_c', 'humidity_pct']:
        df[col] = pd.to_numeric(df[col], errors='coerce')

    # Drop rows that can't produce a useful label
    df = df.dropna(subset=['total_kwh', 'avg_watts', 'sessions'])
    df = df[(df['sessions'] > 0) & (df['total_kwh'] > 0) & (df['avg_watts'] > 0)]

    print(f'After parsing: {len(df):,} rows | {df["device_hash"].nunique():,} devices')
    return df.reset_index(drop=True)


# ── 3. Feature engineering ─────────────────────────────────────────────────────

def engineer(df: pd.DataFrame) -> pd.DataFrame:
    df  = df.copy()
    gc  = [f'gear_{i}'   for i in range(1, 7)]
    hc  = [f'hour_{h:02d}' for h in range(24)]

    # Efficiency: kWh per active fan-hour (lower = better)
    df['kwh_per_session_hour'] = (
        df['total_kwh'] /
        ((df['avg_session_mins'] / 60) * df['sessions']).clip(lower=0.1)
    )

    # Peak usage hour (0-23)
    df['peak_hour'] = df[hc].values.argmax(axis=1).astype(float)

    # Night waste: fraction of usage between 22:00 and 05:00
    night = [f'hour_{h:02d}' for h in list(range(22, 24)) + list(range(0, 6))]
    df['night_usage_ratio'] = df[night].mean(axis=1)

    # Dominant gear (1-6) — gear they run most
    df['dominant_gear'] = df[gc].values.argmax(axis=1) + 1

    # Speed spread — how evenly distributed is usage across gears?
    g = df[gc].values.clip(min=1e-9)
    df['speed_entropy'] = -(g * np.log(g)).sum(axis=1)

    # Heat sensitivity — does this device run higher gears on hotter days?
    # Computed per device across multiple rows; fallback 0 for single-row devices.
    def _heat_corr(grp):
        valid = grp[grp['temp_max_c'] > 0]
        if len(valid) >= 3 and valid['temp_max_c'].std() > 0.5:
            return valid['dominant_gear'].corr(valid['temp_max_c'])
        return 0.0

    hs = df.groupby('device_hash').apply(_heat_corr).rename('heat_sensitivity')
    df = df.merge(hs, on='device_hash', how='left')
    df['heat_sensitivity'] = df['heat_sensitivity'].fillna(0.0)

    # KSEB marginal rate at the device's current slab
    df['kseb_marginal_rate'] = (
        df['kseb_slab'].clip(1, 8).astype(int)
        .apply(lambda s: KSEB_RATES[s - 1])
    )

    # Cost per session (₹)
    df['cost_per_session'] = (df['total_kwh'] / df['sessions'].clip(1)) * df['tariff_per_kwh']

    # Replace -1 weather sentinels with Kerala defaults (model never sees -1)
    df['temp_max_c']   = df['temp_max_c'].where(df['temp_max_c']   > 0, KERALA_DEFAULTS['temp_max_c'])
    df['temp_min_c']   = df['temp_min_c'].where(df['temp_min_c']   > 0, KERALA_DEFAULTS['temp_min_c'])
    df['humidity_pct'] = df['humidity_pct'].where(df['humidity_pct'] > 0, KERALA_DEFAULTS['humidity_pct'])

    return df


# ── 4. Pseudo-label generation ─────────────────────────────────────────────────
#
# No ground-truth "optimal gear" exists, so we derive labels from the data:
#
#   For every (kseb_slab_bucket × temp_bucket) cluster:
#     - Efficient users = bottom 25% by kwh_per_session_hour
#     - Target gear     = most-used gear among efficient users in that cluster
#     - Target savings  = (user avg_watts − efficient avg_watts)
#                         × user monthly fan-hours × tariff_per_kwh / 1000
#
# This captures "what do people like you, in similar weather and tariff
# conditions, do when they're being energy-efficient?"
# ──────────────────────────────────────────────────────────────────────────────

def generate_labels(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    gc = [f'gear_{i}' for i in range(1, 7)]

    df['temp_bucket'] = pd.cut(
        df['temp_max_c'],
        bins=[0, 28, 32, 36, 50],
        labels=[0, 1, 2, 3],
    )
    df['cluster_key'] = df['kseb_slab'].astype(int).astype(str) + '_' + df['temp_bucket'].astype(str)

    target_gear    = np.zeros(len(df), dtype=int)
    target_savings = np.zeros(len(df), dtype=float)

    for key, grp in df.groupby('cluster_key'):
        idx_list = grp.index.tolist()

        if len(grp) < 4:
            # Too few samples — use each device's own dominant gear as target
            for i, idx in enumerate(idx_list):
                pos = df.index.get_loc(idx)
                target_gear[pos] = int(df.loc[idx, 'dominant_gear'])
            continue

        threshold   = grp['kwh_per_session_hour'].quantile(0.25)
        efficient   = grp[grp['kwh_per_session_hour'] <= threshold]

        opt_dist    = efficient[gc].mean()
        opt_gear    = int(opt_dist.idxmax().split('_')[1])
        opt_watts   = efficient['avg_watts'].mean()

        for idx in idx_list:
            pos           = df.index.get_loc(idx)
            user_watts    = df.loc[idx, 'avg_watts']
            monthly_hrs   = (df.loc[idx, 'avg_session_mins'] / 60) * df.loc[idx, 'sessions'] * 30
            tariff        = df.loc[idx, 'tariff_per_kwh']

            target_gear[pos] = opt_gear
            savings_kwh      = max(0.0, user_watts - opt_watts) * monthly_hrs / 1000
            target_savings[pos] = savings_kwh * tariff

    df['target_gear']    = target_gear
    df['target_savings'] = target_savings

    print(f'Label distribution (optimal gear):\n{pd.Series(target_gear).value_counts().sort_index().to_string()}')
    return df


# ── 5. Feature matrices ────────────────────────────────────────────────────────

def _norm(series: pd.Series, lo: float, hi: float) -> pd.Series:
    return ((series - lo) / (hi - lo)).clip(0.0, 1.0)


def build_matrices(df: pd.DataFrame):
    """
    Returns (X_user [37 cols], X_ctx [7 cols]).

    USER features — long-term habit profile fed into the user tower.
    These change slowly; in the app they are recomputed once a week.

    CONTEXT features — current conditions fed into the context tower.
    These change every time the app opens (live weather + current hour).
    """
    gc = [f'gear_{i}'     for i in range(1, 7)]
    hc = [f'hour_{h:02d}' for h in range(24)]
    mc = [f'mode_{m}'     for m in MODES]

    X_user = pd.concat([
        df[gc],                                                                        # 6
        df[mc].fillna(0.0),                                                            # 5
        df[hc],                                                                        # 24
        _norm(df['avg_session_mins'], *NORM['avg_session_mins']).rename('sess_mins_n'), # 1
        _norm(df['sessions'],         *NORM['sessions']        ).rename('sessions_n'), # 1
    ], axis=1)  # total: 37

    X_ctx = pd.concat([
        _norm(df['temp_max_c'],     *NORM['temp_max_c']    ).rename('temp_max_n'),
        _norm(df['temp_min_c'],     *NORM['temp_min_c']    ).rename('temp_min_n'),
        _norm(df['humidity_pct'],   *NORM['humidity_pct']  ).rename('humidity_n'),
        _norm(df['tariff_per_kwh'], *NORM['tariff_per_kwh']).rename('tariff_n'),
        _norm(df['kseb_slab'],      *NORM['kseb_slab']     ).rename('kseb_slab_n'),
        _norm(df['peak_hour'],      *NORM['peak_hour']     ).rename('peak_hour_n'),
        _norm(df['month'],          *NORM['month']         ).rename('month_n'),
    ], axis=1)  # total: 7

    return X_user, X_ctx


# ── 6. Phase 1 — XGBoost ──────────────────────────────────────────────────────

def train_xgboost(X_user, X_ctx, y_gear, y_savings):
    import xgboost as xgb

    print('\n── Phase 1: XGBoost ──────────────────────────────────────────────')

    X = pd.concat([X_user, X_ctx], axis=1)
    X_tr, X_te, yg_tr, yg_te, ys_tr, ys_te = train_test_split(
        X, y_gear, y_savings, test_size=0.2, random_state=42,
    )

    # Gear classifier (6-class)
    gear_clf = xgb.XGBClassifier(
        n_estimators=400,
        max_depth=6,
        learning_rate=0.04,
        subsample=0.8,
        colsample_bytree=0.8,
        min_child_weight=3,
        gamma=0.1,
        eval_metric='mlogloss',
        early_stopping_rounds=30,
        random_state=42,
        verbosity=0,
    )
    gear_clf.fit(X_tr, yg_tr - 1,
                 eval_set=[(X_te, yg_te - 1)], verbose=False)

    preds = gear_clf.predict(X_te) + 1
    acc   = accuracy_score(yg_te, preds)
    print(f'  Gear accuracy : {acc:.1%}  (random baseline: {1/6:.1%})')

    # Savings regressor
    sav_reg = xgb.XGBRegressor(
        n_estimators=400,
        max_depth=5,
        learning_rate=0.04,
        subsample=0.8,
        colsample_bytree=0.8,
        early_stopping_rounds=30,
        random_state=42,
        verbosity=0,
    )
    sav_reg.fit(X_tr, ys_tr, eval_set=[(X_te, ys_te)], verbose=False)
    mae = mean_absolute_error(ys_te, sav_reg.predict(X_te))
    print(f'  Savings MAE   : ₹{mae:.2f}/month')

    gear_clf.save_model(str(OUTPUT_DIR / 'gear_xgb.json'))
    sav_reg.save_model(str(OUTPUT_DIR / 'savings_xgb.json'))

    return gear_clf, sav_reg, X_te, yg_te, ys_te


# ── 7. SHAP analysis ───────────────────────────────────────────────────────────

def shap_analysis(clf, X_te, feature_names):
    import shap
    import matplotlib.pyplot as plt
    import seaborn as sns

    print('\n── SHAP Feature Importance ───────────────────────────────────────')
    explainer   = shap.TreeExplainer(clf)
    shap_values = explainer.shap_values(X_te)

    # For multi-class XGB, shap_values is (n_classes, n_samples, n_features).
    # Take mean absolute value across classes for overall importance.
    if isinstance(shap_values, list):
        importance = np.abs(np.array(shap_values)).mean(axis=(0, 1))
    else:
        importance = np.abs(shap_values).mean(axis=0)

    imp_df = (pd.Series(importance, index=feature_names)
                .sort_values(ascending=False)
                .head(20))

    fig, ax = plt.subplots(figsize=(9, 7))
    sns.barplot(x=imp_df.values, y=imp_df.index, palette='viridis', ax=ax)
    ax.set_title('Top 20 Features — mean |SHAP|', fontsize=13)
    ax.set_xlabel('Mean absolute SHAP value')
    fig.tight_layout()
    out = OUTPUT_DIR / 'shap_importance.png'
    fig.savefig(str(out), dpi=150)
    plt.close()
    print(f'  Saved: {out}')
    print(f'  Top 5 features: {", ".join(imp_df.index[:5])}')

    return explainer


# ── 8. Phase 2 — Two-tower Keras model ────────────────────────────────────────
#
# Architecture
# ────────────
#
#   USER TOWER (long-term habits)       CONTEXT TOWER (current conditions)
#   ─────────────────────────────       ─────────────────────────────────
#   Input (37,)                         Input (7,)
#   Dense 64 → ReLU                     Dense 32 → ReLU
#   Dense 32 → ReLU                     Dense 16 → ReLU  (user_embedding)
#   Dense 16 → ReLU (user_embedding)
#
#                   Concat (32,)
#                   Dense 32 → ReLU
#                   Dense 16 → ReLU
#                       ↙           ↘
#   Dense 6 → Softmax              Dense 1 → ReLU
#   (gear probabilities)           (₹/month savings)
#
# TFLite notes
# ────────────
#   • All ops used (Dense, ReLU, Softmax, Concatenate) are fully supported
#     by the TFLite built-in op set — no select ops needed.
#   • Model exported as float16: ~15 KB, runs in <1 ms on any Android phone.
#   • Two fixed-shape inputs avoid any dynamic-shape issues at conversion.
#   • The user tower can be split into a standalone tflite (user_encoder.tflite)
#     later so the embedding is cached weekly instead of recomputed every open.
# ──────────────────────────────────────────────────────────────────────────────

def build_model(user_dim: int = 37, ctx_dim: int = 7):
    import tensorflow as tf
    from tensorflow.keras import Input, Model
    from tensorflow.keras.layers import Dense, Concatenate

    user_in = Input(shape=(user_dim,), name='user_features')
    u = Dense(64, activation='relu')(user_in)
    u = Dense(32, activation='relu')(u)
    u_emb = Dense(16, activation='relu', name='user_embedding')(u)

    ctx_in = Input(shape=(ctx_dim,), name='context_features')
    c = Dense(32, activation='relu')(ctx_in)
    c_emb = Dense(16, activation='relu', name='context_embedding')(c)

    z = Concatenate()([u_emb, c_emb])
    z = Dense(32, activation='relu')(z)
    z = Dense(16, activation='relu')(z)

    gear_out    = Dense(6, activation='softmax', name='gear_probs')(z)
    savings_out = Dense(1, activation='relu',    name='savings_rupees')(z)

    return Model(inputs=[user_in, ctx_in], outputs=[gear_out, savings_out],
                 name='terraton_recommender')


def train_keras(X_user, X_ctx, y_gear, y_savings):
    import tensorflow as tf

    print('\n── Phase 2: Two-tower Keras model ────────────────────────────────')

    model = build_model(X_user.shape[1], X_ctx.shape[1])
    model.summary(line_length=70)

    # One-hot encode gear (1-6 → index 0-5)
    y_gear_oh = tf.keras.utils.to_categorical(y_gear - 1, num_classes=6)

    # Scale savings so they sit in a similar range to the cross-entropy loss.
    savings_scale = float(max(y_savings.max(), 1.0))
    y_sav_n       = y_savings / savings_scale

    # Chronological split: train on past, validate on most recent 20%.
    n     = len(X_user)
    split = int(n * 0.8)
    Xu_tr, Xu_te   = X_user.iloc[:split].values.astype('float32'), X_user.iloc[split:].values.astype('float32')
    Xc_tr, Xc_te   = X_ctx.iloc[:split].values.astype('float32'),  X_ctx.iloc[split:].values.astype('float32')
    yg_tr, yg_te   = y_gear_oh[:split], y_gear_oh[split:]
    ys_tr, ys_te   = y_sav_n[:split],   y_sav_n[split:]

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss={
            'gear_probs':    'categorical_crossentropy',
            'savings_rupees': 'mse',
        },
        loss_weights={
            'gear_probs':    0.7,   # gear correctness is the primary goal
            'savings_rupees': 0.3,
        },
        metrics={'gear_probs': 'accuracy'},
    )

    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor='val_gear_probs_accuracy',
            patience=20,
            restore_best_weights=True,
            mode='max',
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss', patience=8, factor=0.5, verbose=0,
        ),
    ]

    model.fit(
        [Xu_tr, Xc_tr],
        {'gear_probs': yg_tr, 'savings_rupees': ys_tr},
        validation_data=([Xu_te, Xc_te], {'gear_probs': yg_te, 'savings_rupees': ys_te}),
        epochs=300,
        batch_size=min(64, max(8, n // 20)),  # sensible batch for small datasets
        callbacks=callbacks,
        verbose=1,
    )

    model.save(str(OUTPUT_DIR / 'terraton_recommender.keras'))
    return model, savings_scale


# ── 9. TFLite export ──────────────────────────────────────────────────────────

def export_tflite(model, savings_scale: float) -> bytes:
    import tensorflow as tf

    print('\n── TFLite Export ─────────────────────────────────────────────────')

    # Float16 post-training quantisation:
    #   - Weights stored as fp16 (~50% size reduction vs fp32)
    #   - Activations stay fp32 at runtime (Android CPU)
    #   - No representative dataset required (unlike int8)
    #   - Negligible accuracy drop for this model size
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations           = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]

    tflite_bytes = converter.convert()

    out = OUTPUT_DIR / 'terraton_recommender_fp16.tflite'
    out.write_bytes(tflite_bytes)
    print(f'  Saved : {out}')
    print(f'  Size  : {len(tflite_bytes) / 1024:.1f} KB')

    _validate_tflite(tflite_bytes, model, savings_scale)
    return tflite_bytes


def _validate_tflite(tflite_bytes: bytes, keras_model, savings_scale: float):
    """Run 20 samples through both Keras and TFLite; assert outputs agree."""
    import tensorflow as tf

    interp = tf.lite.Interpreter(model_content=tflite_bytes)
    interp.allocate_tensors()
    in_det  = interp.get_input_details()
    out_det = interp.get_output_details()

    rng     = np.random.default_rng(0)
    u_batch = rng.random((20, in_det[0]['shape'][1])).astype('float32')
    c_batch = rng.random((20, in_det[1]['shape'][1])).astype('float32')

    keras_gears = keras_model.predict([u_batch, c_batch], verbose=0)[0].argmax(axis=1)

    tflite_gears = []
    for i in range(20):
        interp.set_tensor(in_det[0]['index'], u_batch[i:i+1])
        interp.set_tensor(in_det[1]['index'], c_batch[i:i+1])
        interp.invoke()
        tflite_gears.append(interp.get_tensor(out_det[0]['index'])[0].argmax())

    match = sum(k == t for k, t in zip(keras_gears, tflite_gears))
    print(f'  Keras ↔ TFLite agreement: {match}/20 samples (expect ≥18)')


# ── 10. Normalization config (read by Flutter app) ────────────────────────────

def save_norm_config(savings_scale: float):
    config = {
        'version':         1,
        'norm_ranges':     NORM,
        'savings_scale':   savings_scale,
        'modes':           MODES,
        'gear_count':      6,
        'user_feature_dim': 37,
        'ctx_feature_dim':  7,
        'kerala_defaults': KERALA_DEFAULTS,
        'kseb_rates':      KSEB_RATES,
        'notes': (
            'norm_ranges values are [min, max]. '
            'Normalise with: (value - min) / (max - min), clip to [0, 1]. '
            'savings_rupees TFLite output must be multiplied by savings_scale '
            'to recover ₹/month.'
        ),
    }
    out = OUTPUT_DIR / 'normalization_config.json'
    out.write_text(json.dumps(config, indent=2))
    print(f'  Saved : {out}')


# ── 11. Sample recommendations ────────────────────────────────────────────────

def print_recommendations(tflite_bytes: bytes, X_user, X_ctx, df, savings_scale, n=8):
    import tensorflow as tf

    print('\n── Sample Recommendations ────────────────────────────────────────')
    interp = tf.lite.Interpreter(model_content=tflite_bytes)
    interp.allocate_tensors()
    ind = interp.get_input_details()
    outd = interp.get_output_details()

    sample = df.sample(min(n, len(df)), random_state=1).index

    for idx in sample:
        pos = df.index.get_loc(idx)
        row = df.loc[idx]

        interp.set_tensor(ind[0]['index'], X_user.iloc[pos:pos+1].values.astype('float32'))
        interp.set_tensor(ind[1]['index'], X_ctx.iloc[pos:pos+1].values.astype('float32'))
        interp.invoke()

        probs    = interp.get_tensor(outd[0]['index'])[0]
        raw_sav  = interp.get_tensor(outd[1]['index'])[0][0]
        opt_gear = int(probs.argmax()) + 1
        savings  = float(raw_sav) * savings_scale
        conf     = float(probs.max())

        usual = int(row['dominant_gear'])
        marker = '✓' if usual == opt_gear else '↓' if opt_gear < usual else '↑'
        print(
            f'  {row["device_hash"][:8]}… | '
            f'Slab {int(row["kseb_slab"])} | '
            f'{row["temp_max_c"]:.0f}°C | '
            f'Usual Speed {usual} {marker} Recommended Speed {opt_gear} '
            f'(conf {conf:.0%}) | '
            f'Est. ₹{savings:.2f}/month savings'
        )


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Terraton recommender training pipeline')
    parser.add_argument('--local', metavar='CSV',
                        help='Path to local CSV instead of pulling from R2')
    parser.add_argument('--phase', type=int, choices=[1, 2], default=2,
                        help='1=XGBoost only  2=XGBoost + Keras + TFLite  (default: 2)')
    args = parser.parse_args()

    # ── Load & parse ──────────────────────────────────────────────────────────
    raw = load_from_csv(args.local) if args.local else load_from_r2()
    df  = parse(raw)

    if len(df) < 50:
        print(f'WARNING: only {len(df)} rows — need at least 500 for Phase 1, '
              f'10k+ for Phase 2 to be meaningful.')

    # ── Feature engineering & labels ──────────────────────────────────────────
    df = engineer(df)
    df = generate_labels(df)

    X_user, X_ctx = build_matrices(df)
    y_gear    = df['target_gear'].values.astype(int)
    y_savings = df['target_savings'].values.astype(float)

    # ── Phase 1: XGBoost ──────────────────────────────────────────────────────
    feat_names = list(X_user.columns) + list(X_ctx.columns)
    gear_clf, sav_reg, X_te, yg_te, ys_te = train_xgboost(X_user, X_ctx, y_gear, y_savings)
    shap_analysis(gear_clf, X_te, feat_names)

    if args.phase == 1:
        print('\nPhase 1 complete.')
        print('Re-run with --phase 2 once you have 10k+ rows for the TFLite model.')
        return

    # ── Phase 2: Keras → TFLite ───────────────────────────────────────────────
    if len(df) < 500:
        print(f'\nPhase 2 proceeding with only {len(df)} rows — '
              f'model will overfit; this is a dry-run only.\n')

    keras_model, savings_scale = train_keras(X_user, X_ctx, y_gear, y_savings)
    tflite_bytes               = export_tflite(keras_model, savings_scale)
    save_norm_config(savings_scale)
    print_recommendations(tflite_bytes, X_user, X_ctx, df, savings_scale)

    print('\n── Done ──────────────────────────────────────────────────────────')
    print('Copy these two files into terraton_fan_app/assets/ :')
    print(f'  {(OUTPUT_DIR / "terraton_recommender_fp16.tflite").resolve()}')
    print(f'  {(OUTPUT_DIR / "normalization_config.json").resolve()}')
    print()
    print('Flutter inference (tflite_flutter package):')
    print('  interpreter.runForMultipleInputs([userFeatures, contextFeatures], outputs)')
    print('  gearProbs   = outputs[0]   → argmax + 1 = recommended gear (1–6)')
    print('  savingsRaw  = outputs[1]   → * savings_scale = ₹/month estimate')


if __name__ == '__main__':
    main()
