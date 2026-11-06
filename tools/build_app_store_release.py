#!/usr/bin/env python3
"""Build and inspect LandO's iOS archive; never uploads or submits the app."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--unsigned', action='store_true', help='Compile an archive for inspection without an Apple signing identity; no installable IPA.')
parser.add_argument('--skip-tests', action='store_true', help='Only after analyze and the test suite passed for these sources.')
args = parser.parse_args()
def run(command):
    if command[0] == 'xcodebuild':
        # Xcode's raw script logs may contain expanded Maps build settings.
        # Keep those logs out of terminal output and show only diagnostics.
        print('Running Xcode '+('export' if '-exportArchive' in command else 'archive')+'...', flush=True)
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        for line in (result.stdout+'\n'+result.stderr).splitlines():
            if any(token in line for token in ['error:', '** ARCHIVE', '** EXPORT']):
                safe = re.sub(r'(AIza[\w-]+|AQ\.[\w-]+|sk-[\w-]+)', '[credential removed]', line)
                print(safe)
        if result.returncode:
            raise SystemExit('Xcode '+('export' if '-exportArchive' in command else 'archive')+' failed. Resolve the diagnostics above; nothing was uploaded.')
        return
    subprocess.run(command, cwd=ROOT, check=True)
if not args.skip_tests:
    run(['flutter', 'analyze'])
    run(['flutter', 'test'])
# Flutter 3.47.5 resets the generated plugin package to iOS 15 during its
# archive command. Configure Flutter first, synchronize the package with the
# actual Runner deployment target, then archive directly through Xcode.
run(['flutter', 'build', 'ios', '--release', '--config-only', '--no-codesign',
     '--dart-define-from-file=store/release.json'])
run(['/bin/sh', 'ios/scripts/sync_package_deployment.sh'])
archive = ROOT/'build/ios/archive/Runner.xcarchive'
command = ['xcodebuild', '-workspace', 'ios/Runner.xcworkspace', '-scheme', 'Runner',
           '-configuration', 'Release', '-destination', 'generic/platform=iOS',
           '-archivePath', str(archive), 'archive']
if args.unsigned:
    command += ['CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO']
run(command)
run([sys.executable, 'tools/check_ios_archive.py'])
if args.unsigned:
    print(f'UNSIGNED archive only: {archive}. It cannot be uploaded or installed as-is.')
else:
    started = time.time()
    run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
         '-exportPath', str(ROOT/'build/ios/ipa'), '-exportOptionsPlist',
         'ios/ExportOptions.plist', '-allowProvisioningUpdates'])
    ipas = [p for p in (ROOT/'build/ios/ipa').glob('*.ipa') if p.stat().st_mtime >= started]
    if not ipas:
        raise SystemExit('No new IPA was exported. Open the archive in Xcode Organizer to resolve distribution signing and export an App Store Connect IPA.')
    run([sys.executable, 'tools/check_ios_archive.py', '--ipa', str(ipas[0])])
    print('Exported distribution IPA: '+str(ipas[0]))
print('Review store/APP_STORE_RELEASE.md for App Store Connect metadata, privacy, screenshots and remaining owner checks. Nothing was uploaded.')
