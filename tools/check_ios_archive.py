#!/usr/bin/env python3
"""Inspect LandO's actual iOS archive without printing its embedded Maps key.

This does not replace Xcode Organizer / App Store Connect validation.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def check(archive, require_signature=False):
    app = archive/'Products/Applications/Runner.app'
    info = plistlib.loads((app/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'app.neotheone.lando', 'Unexpected bundle ID.'
    assert info['CFBundleDisplayName'] == 'LandO'
    assert int(info['DTSDKName'].removeprefix('iphoneos').split('.')[0]) >= 26, 'Use iOS SDK 26 or newer.'
    assert info['MinimumOSVersion'] == '16.4'
    assert sorted(info['UIDeviceFamily']) == [1, 2], 'This packet covers iPhone and iPad.'
    assert info.get('ITSAppUsesNonExemptEncryption') is False
    assert info.get('NSLocationWhenInUseUsageDescription')
    assert not info.get('UIBackgroundModes')
    assert not any(k in info for k in ['NSLocationAlwaysAndWhenInUseUsageDescription', 'NSMicrophoneUsageDescription', 'NSCameraUsageDescription', 'NSUserTrackingUsageDescription'])
    assert not info.get('NSAppTransportSecurity', {}).get('NSAllowsArbitraryLoads', False)
    key = info.get('GoogleMapsAPIKey', '')
    assert key and not key.startswith(('YOUR_', '$(')), 'Configure ios/Flutter/MapsSecrets.xcconfig.'
    manifest = plistlib.loads((app/'PrivacyInfo.xcprivacy').read_bytes())
    assert manifest['NSPrivacyTracking'] is False
    assert not manifest['NSPrivacyTrackingDomains']
    assert 'NSPrivacyCollectedDataTypeOtherUserContent' in {d['NSPrivacyCollectedDataType'] for d in manifest['NSPrivacyCollectedDataTypes']}
    manifests = {}
    for path in app.rglob('PrivacyInfo.xcprivacy'):
        data = plistlib.loads(path.read_bytes())
        assert not data.get('NSPrivacyTracking', False), f'Review tracking in {path.relative_to(app)}'
        manifests[str(path.relative_to(app))] = data
    for required in ['GoogleMaps.bundle', 'GooglePlaces.bundle', 'Flutter.framework', 'llama.framework', 'flutter_secure_storage', 'sqflite']:
        assert any(required in name for name in manifests), f'Missing SDK privacy manifest: {required}'
    assert not any(p.suffix.lower() in {'.gguf', '.jks', '.keystore', '.p12', '.mobileconfig', '.db'} for p in app.rglob('*')), 'Private files or downloaded weights are bundled.'
    assert (app/'Frameworks/App.framework/flutter_assets/assets/legal/privacy-policy.txt').exists()
    dsym_dir = archive/'dSYMs'
    dsym_names = sorted(p.name for p in dsym_dir.glob('*.dSYM'))
    assert 'Runner.app.dSYM' in dsym_names and 'App.framework.dSYM' in dsym_names
    binaries = [app/'Runner', *[p/p.stem for p in (app/'Frameworks').glob('*.framework')]]
    native = []
    for binary in binaries:
        if not binary.is_file(): continue
        arch = subprocess.run(['xcrun', 'lipo', '-archs', str(binary)], capture_output=True, text=True, check=True).stdout.strip()
        assert arch == 'arm64', f'Unexpected archive architecture in {binary.name}: {arch}'
        native.append(binary.name)
    signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, text=True)
    signed = signature.returncode == 0
    if require_signature:
        assert signed, 'The archive is not code-signed. Use Xcode automatic signing / your distribution team.'
        entitlements = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True).stdout
        entitlements = plistlib.loads(entitlements)
    result = {
        'bundleIdentifier': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
        'build': info['CFBundleVersion'], 'sdk': info['DTSDKName'], 'minimumIOS': info['MinimumOSVersion'],
        'devices': ['iPhone', 'iPad'], 'signatureVerified': signed,
        'privacyManifests': manifests, 'nativeArm64Binaries': native, 'debugSymbols': dsym_names,
        'note': 'Technical archive checks only. Validate the distribution IPA in Xcode and App Store Connect before submission.',
    }
    output = ROOT/'build/app-store/archive-validation.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(f'PASS: {result["bundleIdentifier"]} {result["version"]}+{result["build"]}, {result["sdk"]}, {len(manifests)} privacy manifests, {len(native)} ARM64 binaries.')
    print(f'Signature verified: {signed}. Report: {output}')

def check_export(ipa):
    with tempfile.TemporaryDirectory(prefix='lando-ipa-check-') as temp:
        directory = Path(temp)
        with zipfile.ZipFile(ipa) as archive:
            assert all((directory/name).resolve().is_relative_to(directory.resolve()) for name in archive.namelist()), 'Unsafe IPA path.'
            archive.extractall(directory)
        apps = list((directory/'Payload').glob('*.app'))
        assert len(apps) == 1, 'Expected one exported app.'
        app = apps[0]
        info = plistlib.loads((app/'Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'app.neotheone.lando'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, check=True)
        signed_entitlements = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True).stdout
        entitlements = plistlib.loads(signed_entitlements)
        assert not entitlements.get('get-task-allow', False), 'Development signing cannot be submitted.'
        raw = subprocess.run(['security', 'cms', '-D', '-i', str(app/'embedded.mobileprovision')], capture_output=True, check=True).stdout
        profile = plistlib.loads(raw)
        assert not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'), 'Expected App Store distribution, not development, Ad Hoc or enterprise.'
        assert profile['ExpirationDate'].replace(tzinfo=timezone.utc) > datetime.now(timezone.utc), 'Provisioning profile expired.'
        team = profile['TeamIdentifier'][0]
        assert entitlements['application-identifier'] == team+'.app.neotheone.lando'
        assert not profile['Entitlements'].get('get-task-allow', False)
        result = {
            'bundleIdentifier': info['CFBundleIdentifier'],
            'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'distributionSignatureVerified': True, 'appStoreProfile': True,
            'team': team, 'profileExpires': profile['ExpirationDate'].isoformat()+'Z',
            'ipaSHA256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
            'note': 'Local verification only; App Store Connect processing/review still required.',
        }
        output = ROOT/'build/app-store/ipa-validation.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2)+'\n')
        print(f'PASS: locally verified App Store distribution IPA for {result["bundleIdentifier"]}. Report: {output}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=ROOT/'build/ios/archive/Runner.xcarchive')
    parser.add_argument('--require-signature', action='store_true')
    parser.add_argument('--ipa', type=Path, help='Validate a locally exported App Store distribution IPA instead of an archive.')
    args = parser.parse_args()
    if args.ipa:
        check_export(args.ipa)
    else:
        check(args.archive, args.require_signature)
