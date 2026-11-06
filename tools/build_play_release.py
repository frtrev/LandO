#!/usr/bin/env python3
"""Build/verify a Play AAB. --internal-test allows unresolved Console setup."""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import subprocess
import urllib.request
from check_play_bundle import check

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--internal-test', action='store_true', help='Prepare a test artifact while production setup is pending.')
parser.add_argument('--skip-tests', action='store_true', help='Use only when analyze/tests already passed for these sources.')
args = parser.parse_args()
config = json.loads((ROOT/'store/release.json').read_text())
status = json.loads((ROOT/'store/publishing-status.json').read_text())
if os.environ.get('LANDO_DEVELOPMENT_SIGNING') == 'true':
    raise SystemExit('Play builds cannot use development/debug signing.')
if not args.internal_test:
    blockers = []
    if not config.get('PRIVACY_POLICY_URL', '').startswith('https://'): blockers.append('Publish store/privacy-policy.html and set PRIVACY_POLICY_URL in store/release.json.')
    if not status['reportDeliveryVerified']: blockers.append('Activate and verify the in-app AI report delivery before marking reportDeliveryVerified true.')
    if not status['playAppSigningMapsRestrictionConfigured']: blockers.append('Add the Play APP SIGNING certificate SHA-1 (not just the upload key) to Google Maps/Places Android key restrictions.')
    if not status['storeAssetsReviewed']: blockers.append('Review real Android screenshots, 512 px icon, 1024×500 feature graphic and listing copy.')
    if blockers: raise SystemExit('Production setup is incomplete:\n- '+'\n- '.join(blockers)+'\nUse --internal-test only for an internal testing artifact.')
policy = html.escape((ROOT/'assets/legal/privacy-policy.txt').read_text())
(ROOT/'store/privacy-policy.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LandO Privacy Policy</title><style>body{font:16px/1.65 system-ui,sans-serif;margin:40px auto;padding:0 24px;max-width:850px;color:#162a20;background:#fafcfb}pre{white-space:pre-wrap;font:inherit}</style><main><pre>'+policy+'</pre><a href="mailto:ftrevino@yahoo.com">Contact LandO support</a></main></html>')
if not args.skip_tests:
    subprocess.run(['flutter', 'analyze'], cwd=ROOT, check=True)
    subprocess.run(['flutter', 'test'], cwd=ROOT, check=True)
subprocess.run(['flutter', 'build', 'appbundle', '--release', '--dart-define-from-file=store/release.json'], cwd=ROOT, check=True)
jar = ROOT/'.dart_tool/play-release/bundletool-1.18.3.jar'
expected = 'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29'
if not jar.exists() or hashlib.sha256(jar.read_bytes()).hexdigest() != expected:
    jar.parent.mkdir(parents=True, exist_ok=True)
    partial = jar.with_suffix('.part')
    try:
        urllib.request.urlretrieve('https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar', partial)
        if hashlib.sha256(partial.read_bytes()).hexdigest() != expected: raise SystemExit('bundletool checksum mismatch.')
        partial.replace(jar)
    finally: partial.unlink(missing_ok=True)
check(ROOT/'build/app/outputs/bundle/release/app-release.aab', jar)
if args.internal_test: print('INTERNAL TEST artifact only: complete store/PLAY_RELEASE.md before public release.')
