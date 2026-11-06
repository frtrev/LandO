#!/usr/bin/env python3
"""Create a new local Play upload key. Never replaces an existing signing file."""
import os
from pathlib import Path
import secrets
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
key = root / 'android/upload-keystore.jks'
config = root / 'android/key.properties'
certificate = root / 'store/upload-certificate.pem'
if key.exists() or config.exists() or certificate.exists():
    raise SystemExit('Signing files already exist; refusing to replace them.')
keytool = Path('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool')
if not keytool.exists():
    keytool = shutil.which('keytool')
if not keytool:
    raise SystemExit('Install a Java JDK with keytool first.')
password = secrets.token_urlsafe(36)
env = dict(os.environ, LANDO_UPLOAD_STORE_PASSWORD=password, LANDO_UPLOAD_KEY_PASSWORD=password)
try:
    subprocess.run([str(keytool), '-genkeypair', '-v', '-keystore', str(key),
                    '-storetype', 'JKS', '-alias', 'lando-upload', '-keyalg', 'RSA',
                    '-keysize', '3072', '-validity', '10000', '-dname', 'CN=LandO Upload,O=LandO',
                    '-storepass:env', 'LANDO_UPLOAD_STORE_PASSWORD', '-keypass:env', 'LANDO_UPLOAD_KEY_PASSWORD'],
                   env=env, check=True, capture_output=True)
    key.chmod(0o600)
    with config.open('x') as handle:
        handle.write(f'storeFile=upload-keystore.jks\nstorePassword={password}\nkeyPassword={password}\nkeyAlias=lando-upload\n')
    config.chmod(0o600)
    subprocess.run([str(keytool), '-exportcert', '-rfc', '-alias', 'lando-upload',
                    '-keystore', str(key), '-storepass:env', 'LANDO_UPLOAD_STORE_PASSWORD',
                    '-file', str(certificate)], env=env, check=True, capture_output=True)
except BaseException:
    for file in [key, config, certificate]:
        file.unlink(missing_ok=True)
    raise SystemExit('Upload key creation failed; no partial signing files were retained.')
print('Upload key created. Back up android/upload-keystore.jks and android/key.properties privately. Passwords were not printed.')
