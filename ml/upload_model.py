#!/usr/bin/env python3
"""
ml/upload_model.py — Upload trained TFLite model to R2 and update the
OTA version manifest (models/latest.json).

The Flutter app checks this manifest on Wi-Fi at launch. If the version
number is higher than what's cached locally, it downloads the new model.

Called by mlops_retrain.yml after a successful Phase 2 training run.
Reads credentials from the same env vars as data_health.py.
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import boto3

R2_BUCKET   = os.getenv('R2_BUCKET',     'terraton-usage-data')
R2_ENDPOINT = os.getenv('R2_ENDPOINT',   '')
R2_KEY      = os.getenv('R2_ACCESS_KEY', '')
R2_SECRET   = os.getenv('R2_SECRET_KEY', '')

OUTPUT_DIR  = Path('ml/output')
TFLITE_FILE = OUTPUT_DIR / 'terraton_recommender_fp16.tflite'
NORM_FILE   = OUTPUT_DIR / 'normalization_config.json'
MANIFEST    = 'models/latest.json'


def get_next_version(s3) -> int:
    """Read current version from R2 manifest; return version + 1."""
    try:
        obj  = s3.get_object(Bucket=R2_BUCKET, Key=MANIFEST)
        data = json.loads(obj['Body'].read())
        return int(data.get('version', 0)) + 1
    except s3.exceptions.NoSuchKey:
        return 1
    except Exception:
        return 1


def upload(s3, local_path: Path, s3_key: str) -> str:
    size_kb = local_path.stat().st_size / 1024
    print(f'Uploading {local_path.name} → {s3_key}  ({size_kb:.1f} KB) ...')
    s3.upload_file(
        str(local_path),
        R2_BUCKET,
        s3_key,
        ExtraArgs={'ContentType': 'application/octet-stream'},
    )
    return s3_key


def main():
    if not R2_ENDPOINT or not R2_KEY:
        print('ERROR: R2_ENDPOINT and R2_ACCESS_KEY must be set.', file=sys.stderr)
        sys.exit(1)

    if not TFLITE_FILE.exists():
        print(f'ERROR: {TFLITE_FILE} not found — run train.py --phase 2 first.',
              file=sys.stderr)
        sys.exit(1)

    s3 = boto3.client(
        's3',
        endpoint_url=R2_ENDPOINT,
        aws_access_key_id=R2_KEY,
        aws_secret_access_key=R2_SECRET,
        region_name='auto',
    )

    version       = get_next_version(s3)
    trained_at    = datetime.now(tz=timezone.utc).isoformat()
    tflite_key    = f'models/terraton_recommender_v{version}_fp16.tflite'
    norm_key      = f'models/normalization_config_v{version}.json'

    # Upload model + normalization config
    upload(s3, TFLITE_FILE, tflite_key)
    if NORM_FILE.exists():
        upload(s3, NORM_FILE, norm_key)

    # Load norm config to embed metadata in the manifest
    norm_config = json.loads(NORM_FILE.read_text()) if NORM_FILE.exists() else {}

    # Build and upload the manifest
    manifest = {
        'version':        version,
        'tflite_key':     tflite_key,
        'norm_key':       norm_key,
        'tflite_size_kb': round(TFLITE_FILE.stat().st_size / 1024, 1),
        'trained_at':     trained_at,
        'savings_scale':  norm_config.get('savings_scale'),
        'model_dim': {
            'user':    norm_config.get('user_feature_dim', 37),
            'context': norm_config.get('ctx_feature_dim',   7),
        },
    }

    print(f'Updating manifest → {MANIFEST}')
    s3.put_object(
        Bucket=R2_BUCKET,
        Key=MANIFEST,
        Body=json.dumps(manifest, indent=2).encode(),
        ContentType='application/json',
    )

    print()
    print(f'✅  Model v{version} live in R2.')
    print(f'    tflite  : {tflite_key}')
    print(f'    manifest: {MANIFEST}')
    print(f'    App will OTA this model on next Wi-Fi launch.')


if __name__ == '__main__':
    main()
