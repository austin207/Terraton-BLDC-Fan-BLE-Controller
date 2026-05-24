#!/usr/bin/env python3
"""
ml/data_health.py — R2 data freshness and volume check.

Used by:
  mlops_data_health.yml  — daily freshness alert
  mlops_retrain.yml      — gate before training (--no-exit + --json)

Reads R2 credentials from environment variables:
  R2_ENDPOINT, R2_ACCESS_KEY, R2_SECRET_KEY, R2_BUCKET (optional, defaults below)
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

R2_BUCKET   = os.getenv('R2_BUCKET',     'terraton-usage-data')
R2_ENDPOINT = os.getenv('R2_ENDPOINT',   '')
R2_KEY      = os.getenv('R2_ACCESS_KEY', '')
R2_SECRET   = os.getenv('R2_SECRET_KEY', '')


def check(alert_hours: float = 48.0) -> dict:
    if not R2_ENDPOINT or not R2_KEY:
        print('ERROR: R2_ENDPOINT and R2_ACCESS_KEY must be set.', file=sys.stderr)
        sys.exit(1)

    s3 = boto3.client(
        's3',
        endpoint_url=R2_ENDPOINT,
        aws_access_key_id=R2_KEY,
        aws_secret_access_key=R2_SECRET,
        region_name='auto',
    )

    # List all objects in the bucket (training data only — not models/ prefix)
    all_objects = []
    paginator = s3.get_paginator('list_objects_v2')
    for page in paginator.paginate(Bucket=R2_BUCKET):
        for obj in page.get('Contents', []):
            # Skip the models/ folder — those are uploaded by us, not the app
            if not obj['Key'].startswith('models/'):
                all_objects.append(obj)

    total_rows = len(all_objects)

    if total_rows == 0:
        return {
            'healthy': False,
            'total_rows': 0,
            'last_upload_age_hours': float('inf'),
            'message': 'No training data found in R2 bucket.',
        }

    now     = datetime.now(tz=timezone.utc)
    latest  = max(all_objects, key=lambda o: o['LastModified'])
    age_h   = (now - latest['LastModified']).total_seconds() / 3600
    healthy = age_h <= alert_hours

    # Estimate rows per day from recent objects (last 7 days)
    week_ago = now.timestamp() - 7 * 86400
    recent   = [o for o in all_objects if o['LastModified'].timestamp() > week_ago]
    rows_per_day = len(recent) / 7 if recent else 0

    result = {
        'healthy':                healthy,
        'total_rows':             total_rows,
        'last_upload_age_hours':  round(age_h, 2),
        'last_upload_key':        latest['Key'],
        'rows_last_7_days':       len(recent),
        'avg_rows_per_day':       round(rows_per_day, 1),
        'alert_threshold_hours':  alert_hours,
        'message': (
            f'OK — {total_rows} rows total, last upload {age_h:.1f}h ago.'
            if healthy else
            f'ALERT — no data for {age_h:.1f}h (threshold: {alert_hours}h).'
        ),
    }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--json',                   action='store_true',
                        help='Print JSON summary to stdout')
    parser.add_argument('--no-exit',                action='store_true',
                        help='Never exit with code 1 (for pipeline use)')
    parser.add_argument('--alert-threshold-hours',  type=float, default=48.0,
                        dest='alert_hours',
                        help='Hours without new data before alerting (default 48)')
    args = parser.parse_args()

    result = check(alert_hours=args.alert_hours)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        status = '✅' if result['healthy'] else '🚨'
        print(f"{status} {result['message']}")
        print(f"   Total rows        : {result['total_rows']:,}")
        print(f"   Last upload       : {result['last_upload_age_hours']:.1f}h ago")
        print(f"   Rows last 7 days  : {result['rows_last_7_days']}")
        print(f"   Avg rows/day      : {result['avg_rows_per_day']}")

    if not result['healthy'] and not args.no_exit:
        sys.exit(1)


if __name__ == '__main__':
    main()
