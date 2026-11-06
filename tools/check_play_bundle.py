#!/usr/bin/env python3
"""Validate a signed LandO AAB without printing embedded Maps credentials."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def java_tool(name):
    homes = [Path(os.environ.get('JAVA_HOME', '/nonexistent')), Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home')]
    for home in homes:
        path = home / 'bin' / name
        if path.exists(): return str(path)
    found = shutil.which(name)
    if not found: raise SystemExit(f'Install a JDK providing {name}.')
    return found

def run(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(f'{Path(args[0]).name} failed during bundle validation. No credentials were logged.')
    return result.stdout

def check(bundle, bundletool):
    java = java_tool('java')
    run([java, '-jar', str(bundletool), 'validate', f'--bundle={bundle}'])
    config = json.loads(run([java, '-jar', str(bundletool), 'dump', 'config', f'--bundle={bundle}']))
    assert config['optimizations']['uncompressNativeLibraries']['alignment'] == 'PAGE_ALIGNMENT_16K', 'Bundle native libraries are not packaged for 16 KB pages.'
    manifest = ET.fromstring(run([java, '-jar', str(bundletool), 'dump', 'manifest', f'--bundle={bundle}', '--module=base']))
    a = '{http://schemas.android.com/apk/res/android}'
    assert manifest.attrib['package'] == 'com.neotheone.lando'
    sdk = manifest.find('uses-sdk')
    target = int(sdk.attrib[a+'targetSdkVersion'])
    assert target >= 36, 'Current Play submissions require target API 36 or newer.'
    application = manifest.find('application')
    assert application.attrib.get(a+'debuggable', 'false') == 'false'
    assert application.attrib.get(a+'usesCleartextTraffic') == 'false'
    permissions = sorted(p.attrib[a+'name'] for p in manifest.findall('uses-permission'))
    allowed = {'android.permission.INTERNET', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION', 'android.permission.ACCESS_NETWORK_STATE', 'android.permission.ACCESS_WIFI_STATE', 'com.neotheone.lando.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}
    assert set(permissions) <= allowed, f'Unexpected release permission: {set(permissions)-allowed}'
    native = []
    with zipfile.ZipFile(bundle) as archive:
        assert not any(n.lower().endswith(('.gguf', '.jks', '.keystore', '.db', '.lando.json')) for n in archive.namelist()), 'Private data or downloaded weights must not be bundled.'
        assert 'base/assets/flutter_assets/assets/legal/privacy-policy.txt' in archive.namelist()
        assert any(n.endswith('.RSA') and n.startswith('META-INF/') for n in archive.namelist()), 'Bundle is unsigned.'
        for name in archive.namelist():
            if not name.endswith('.so') or not any('/'+abi+'/' in name for abi in ['arm64-v8a', 'x86_64']): continue
            data = archive.read(name)
            assert data[:6] == b'\x7fELF\x02\x01', f'Unexpected 64-bit ELF format: {name}'
            offset = struct.unpack_from('<Q', data, 32)[0]
            size, count = struct.unpack_from('<HH', data, 54)
            alignments = [struct.unpack_from('<Q', data, offset+i*size+48)[0] for i in range(count) if struct.unpack_from('<I', data, offset+i*size)[0] == 1]
            assert alignments and min(alignments) >= 16384, f'4 KB-only native library: {name}'
            native.append(name)
    assert any('/arm64-v8a/' in n for n in native)
    signature = run([java_tool('jarsigner'), '-verify', str(bundle)])
    assert 'jar verified.' in signature, 'JAR signature verification failed.'
    cert = run([java_tool('keytool'), '-printcert', '-jarfile', str(bundle)])
    assert 'Android Debug' not in cert, 'Debug-signed bundles cannot be uploaded.'
    fingerprint = re.search(r'SHA256:\s*([A-Fa-f0-9:]+)', cert).group(1).replace(':', '').lower()
    expected_der = subprocess.run(['openssl', 'x509', '-in', str(ROOT/'store/upload-certificate.pem'), '-outform', 'DER'], capture_output=True, check=True).stdout
    assert fingerprint == hashlib.sha256(expected_der).hexdigest(), 'The AAB does not match the saved upload certificate.'
    result = {'package': manifest.attrib['package'], 'versionName': manifest.attrib[a+'versionName'], 'versionCode': int(manifest.attrib[a+'versionCode']), 'targetSdk': target, 'minSdk': int(sdk.attrib[a+'minSdkVersion']), 'debuggable': False, 'cleartextTraffic': False, 'signatureVerified': True, 'uploadCertificateSHA256': fingerprint, 'native64BitLibrariesVerified': len(native), 'nativePageAlignment': '16 KB or greater', 'bundlePageAlignment': 'PAGE_ALIGNMENT_16K', 'permissions': permissions, 'aabSHA256': hashlib.sha256(bundle.read_bytes()).hexdigest()}
    output = ROOT/'build/play-store/validation.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(f'PASS: signed {result["package"]} {result["versionName"]}+{result["versionCode"]}, API {target}, {len(native)} 64-bit libraries, 16 KB bundle/ELF alignment.')
    print(f'Validation report: {output}')
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, default=ROOT/'build/app/outputs/bundle/release/app-release.aab')
    parser.add_argument('--bundletool', type=Path, required=True)
    args = parser.parse_args()
    check(args.bundle, args.bundletool)
